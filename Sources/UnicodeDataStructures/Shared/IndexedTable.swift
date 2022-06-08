// Copyright The swift-url Contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Describes how data is indexed in an ``IndexedTable``.
///
@usableFromInline
internal protocol IndexedTableSchema {

  /// The type of data that is being indexed.
  ///
  associatedtype Column: FixedWidthInteger & UnsignedInteger

  /// The number of bits to index from each `Column` value.
  ///
  /// Indexing more bits means taking more samples of the column's value. This allows the index to
  /// more precisely determine where a value is in the table, reducing the size of the blocks
  /// returned by ``IndexedTable/lookupRows(containing:body:)``.
  ///
  /// However, the number of samples required to index `N` bits is `(2^N) + 1`, so indexing an
  /// additional bit doubles the storage requirement of the index, and the actual reduction in block
  /// size depends on how data is distributed among blocks.
  ///
  static var ColumnBitsToIndex: Int { get }

  /// The storage type to use for index entries.
  ///
  /// This determines the amount of data the index is able to address;
  /// the location table may not have more than `IndexStorage.max` elements.
  ///
  associatedtype IndexStorage: FixedWidthInteger & UnsignedInteger

  // TODO: Add a way to customize the index mapping. For the IDNA BMP index:
  // - U+3400 - U+A400 (corresponding to basically all CJK characters) have a single mapping entry in the table
  // - U+AC00 - U+D700 (corresponding to east asian scripts) also have a single mapping entry
  //
  // This means a huge amount of the space is covered by just 2 entries! The index ends up containing this
  // location a lot, and not of its space is used to help accelerate other code-points. We could hard-code
  // at least the first region for the BMP table, freeing more bits for the other regions.

}

/// An immutable, indexed table.
///
/// The table contains a number of `(Column, Data)` pairs which can be considered its _rows_, and are stored
/// in order, by ascending value of `Column`. A separate index table contains samples of the column's
/// value at various points in the table, and can be used to accelerate lookups by giving approximate
/// locations for any value.
///
/// The table's `Schema` encapsulates various properties of how data is indexed - such as the type of data of
/// the `Column` (must be an unsigned, fixed-width integer), how many bits of the column's values are indexed,
/// and how indexes are stored.
///
@usableFromInline
internal struct IndexedTable<Schema, Data> where Schema: IndexedTableSchema {

  @usableFromInline internal let _index: [Schema.IndexStorage]
  @usableFromInline internal let _columnValues: [Schema.Column]
  @usableFromInline internal let _dataValues: [Data]

  /// Initializes a table.
  ///
  /// > Important:
  /// > This table is _unchecked_. It is designed for static data tables, which can be validated before deployment.
  /// > It is advised that you call ``validate`` manually in debug builds for some basic structural validation.
  ///
  @inlinable
  internal init(uncheckedIndex index: [Schema.IndexStorage], columnValues: [Schema.Column], dataValues: [Data]) {
    self._index = index
    self._columnValues = columnValues
    self._dataValues = dataValues
  }

  /// Validates aspects of the table which are required for memory safety in its implementation.
  /// It is advised that static data tables call this in debug builds.
  ///
  /// Validates:
  ///
  /// - That we do not have more rows than the index can address.
  ///
  /// - That the split storage used for column and data values has the same length.
  ///   This means they agree on the number of rows, and the same offsets are in-bounds in both.
  ///
  /// - That the index has (2^N)+1 entries. This means we can take any number of N bits, and it is guaranteed
  ///   to be within bounds of the index table. There is also one entry _after_ every one of those entries,
  ///   so we can find where the block ends without branching.
  ///
  /// - That the index is sorted. This means the block of data we give will always have a positive/zero `count`.
  ///
  /// - That all offsets in the index table are valid.
  ///
  /// All of this ensures that the lookup arithmetic, from `Column` value to a collection of rows,
  /// is guaranteed to not access or land at uninitialized memory.
  ///
  /// It does not validate that the index table actually points to the correct locations,
  /// only that it doesn't contain unsafe values.
  ///
  @inlinable
  internal func validate() {
    precondition(Schema.ColumnBitsToIndex <= Schema.Column.bitWidth, "Invalid schema: calm down")
    precondition(_columnValues.count < Schema.IndexStorage.max, "The schema cannot index this much data.")
    precondition(_columnValues.count == _dataValues.count, "There must be an equal number of column and data values")
    precondition(_index.count == (1 << Schema.ColumnBitsToIndex) + 1, "The index is not the correct size")
    var last = _index[0]
    for indexValue in _index {
      precondition(indexValue < _columnValues.endIndex, "The index contains an invalid offset")
      precondition(indexValue >= last, "The index is not sorted")
      last = indexValue
    }
  }

  /// Looks up the block of rows where `needle` is expected to be found.
  ///
  /// There may or may not be a location entry with the exact value `needle`, but if it did exist,
  /// it would be within the block of rows provided by the closure.
  ///
  /// The `body` closure is invoked with two parameters: a buffer of `Column` values,
  /// and a buffer of `Data` values. These buffers are guaranteed to be the same length
  /// and should semantically be seen as a single buffer of `(Column, Data)` rows.
  /// The pointers must not escape the closure.
  ///
  @inlinable
  internal func lookupRows<T>(
    containing needle: Schema.Column,
    body: (_ columnRows: UnsafeBufferPointer<Schema.Column>, _ dataRows: UnsafeBufferPointer<Data>) -> T
  ) -> T {

    let offsetIntoIndexTable = needle &>> (Schema.Column.bitWidth &- Schema.ColumnBitsToIndex)

    // The index is known to contain (2^N) + 1 entries, so:
    // - `offsetIntoIndexTable` is guaranteed to be in-bounds.
    // - `offsetIntoIndexTable + 1` is guaranteed to be in-bounds.
    let (blockStart, blockEnd) = _index.withUnsafeBufferPointer {
      ($0[Int(offsetIntoIndexTable)], $0[Int(offsetIntoIndexTable) &+ 1] &+ 1)
    }

    // The index is known to be sorted, and every value is < _columnValues.endIndex, so:
    // - `blockStart` is in-bounds.
    // - `blockEnd` is calculated from `value in index + 1`, so is <= endIndex.
    // - `blockCount` is >= 1
    assert(blockStart < blockEnd, "The index should be sorted and not contain empty blocks")
    let blockCount = Int(blockEnd &- blockStart)
    return _columnValues.withUnsafeBufferPointer { locTable in
      _dataValues.withUnsafeBufferPointer { dataTable in
        let loc = UnsafeBufferPointer(start: locTable.baseAddress! + Int(blockStart), count: blockCount)
        let dat = UnsafeBufferPointer(start: dataTable.baseAddress! + Int(blockStart), count: blockCount)
        return body(loc, dat)
      }
    }
  }

  /// Builds an index table for the given column data.
  ///
  /// The data must be sorted in ascending order.
  /// If the data is altered, previously-calculated index tables are no longer valid.
  ///
  @inlinable
  internal static func buildIndex(_ values: [Schema.Column]) -> [Schema.IndexStorage] {

    precondition(
      (1...Schema.Column.bitWidth).contains(Schema.ColumnBitsToIndex),
      "A schema must index at least 1 bit, and must not index more bits than the value has"
    )
    precondition(!values.isEmpty, "Cannot index an empty array")

    var _lastSample: Schema.IndexStorage = 0
    var samples: [Schema.IndexStorage] = (0..<1 << Schema.ColumnBitsToIndex).map { k in
      let bucketStart = Schema.Column(k << (Schema.Column.bitWidth - Schema.ColumnBitsToIndex))

      let entryAfterBucketStart = values._codepointdatabase_partitionedIndex(where: { $0 <= bucketStart })
      let offsetForBucketStart = Schema.IndexStorage(max(entryAfterBucketStart - 1, 0))

      precondition(offsetForBucketStart >= _lastSample, "Location data is not sorted")
      _lastSample = offsetForBucketStart
      return offsetForBucketStart
    }

    let endEntry = Schema.IndexStorage(values.count - 1)
    precondition(endEntry >= _lastSample, "Location data is not sorted")
    samples.append(endEntry)
    return samples
  }
}
