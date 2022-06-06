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

// --------------------------------------------
// MARK: - Schemas and Data
// --------------------------------------------


/// A type which acts as a facade for some underlying storage.
///
/// There are no requirements of said storage; a conforming type might simply pass-through
/// a value without change. This protocol exists to facilitate transparently presenting data stored
/// as a raw value (say, an integer) as a value of a friendlier type.
///
/// It's like `RawRepresentable`, but the initializer cannot fail.
///
public protocol HasRawStorage {
  associatedtype RawStorage

  init(storage: RawStorage)
  var storage: RawStorage { get }
}

/// Describes the data associated with code-points in a `CodePointDatabase`.
///
public protocol CodePointDatabase_Schema {

  /// The type of data that is stored for Unicode code-points.
  ///
  /// The data will be stored in the database in its `RawStorage` form,
  /// and transparently mapped to its interface type.
  ///
  associatedtype UnicodeData: HasRawStorage

  /// The type of data that is stored for ASCII code-points.
  ///
  /// The data will be stored in the database in its `RawStorage` form,
  /// and transparently mapped to its interface type.
  ///
  associatedtype ASCIIData: HasRawStorage = UnicodeData

  /// How many bits to index from BMP code-points.
  ///
  /// Indexing more bits means taking more samples from the location table, reducing the space which needs
  /// to be binary-searched. However, the number of samples required to index N bits is `(2^N) + 1`,
  /// so it doubles in size for each additional bit we index.
  ///
  /// The default is to index 6 bits, giving 64 samples (130 bytes, since samples are 16 bits each).
  /// Each database may decide to index more or fewer bits.
  ///
  static var BMPIndexBits: Int { get }

  /// (Optional) Returns a copy of the given non-ASCII data, adjusted to apply to a different start location.
  ///
  /// This customization point allows databases to contain values which depend on their location within the database.
  ///
  /// For example, one may wish to map the code-points 𝐀-𝐙 (`U+1D400 MATHEMATICAL BOLD CAPITAL A` to
  /// `U+1D419 MATHEMATICAL BOLD CAPITAL Z`) to the ASCII code-points A-Z. In that case, a single mapping entry
  /// could cover the entire space from 1D400 to 1D419, and when we look up the value for a scalar in that range,
  /// we would subtract the value from 1D400 to find its offset, and add it to the ASCII 'A'
  /// in a kind of 'rebase' operation.
  ///
  /// Anyway, those kinds of values are sensitive to the exact range of code-points they are assigned to.
  /// If we need to split an entry, we need to calculate an adjusted value for the split region, otherwise
  /// we would loop and start rebasing from 'A' again. This function calculates those adjusted values.
  ///
  /// The default behavior is to simply return `data`. Most values do not care about their precise location
  /// in the database this way. If you don't use the `startCodePoint` portion of ``CodePointDatabase/LookupResult``,
  /// you don't need to care about this.
  ///
  static func unicodeData(
    _ data: UnicodeData, at originalStart: UInt32, copyForStartingAt newStartPoint: UInt32
  ) -> UnicodeData
}

extension CodePointDatabase_Schema {

  @inlinable
  public static var BMPIndexBits: Int { 6 }

  @inlinable
  public static func unicodeData(
    _ data: UnicodeData, at originalStart: UInt32, copyForStartingAt newStartPoint: UInt32
  ) -> UnicodeData {
    data
  }
}


// --------------------------------------------
// MARK: - CodePointDatabase
// --------------------------------------------


// swift-format-ignore
/// An immutable database of information about Unicode code-points.
///
/// Databases can be constructed using a `CodePointDatabase.Builder`, after which they may be queried,
/// or printed as a Swift source file.
///
/// Data is stored in 3 sections:
///
/// - A direct lookup for ASCII code-points, to values of the `Schema.ASCIIData` type.
///
/// - A 2-stage, indexed lookup for BMP code-points, to values of the `Schema.UnicodeData` type.
///
///   The top N bits of the code-point are indexed, where N is chosen by the Schema.
///   This means a O(1), branchless reduction in the search space to a block of entries covering 2^(16 - N) code-points.
///   For a list of `n` elements, a binary-search requires a maximum of `log2(n)` comparisons,
///   meaning that in the worst case, when every code-point has an individual data entry, we would need a maximum
///   of (16 - N) comparisons to locate the data for an arbitrary code-point.
///
///   Often it will be much fewer than that, because the data entries are grouped in to regions.
///   For example, the IDNA mapping table has about 4000 entries for all 2^16 code-points in the BMP.
///   Code-point and data tables are split to avoid padding and improve cache performance.
///
/// - Per-plane binary-searched tables for non-BMP code-points, to values of the `Schema.UnicodeData` type.
///
///   Most planes outside the BMP are [not assigned](https://en.wikipedia.org/wiki/Plane_(Unicode)), but
///   the ones that are include plane 1, the SMP (mostly historic scripts and emoji), and planes 2 and 3 -
///   the SIP and TIP respectively, containing CJK ideographs.
///
///   Per-plane tables means we can represent code-points as 16-bit values, which more efficiently
///   packs their contents and improves cache utilization. Code-point and data tables are split
///   to avoid padding and also improve cache performance.
///
public struct CodePointDatabase<Schema: CodePointDatabase_Schema> {

  public typealias SplitTable<CodePoint, Data> = (codepoints: [CodePoint], data: [Data])

  @usableFromInline internal let _asciiData  : [Schema.ASCIIData.RawStorage]
  @usableFromInline internal let _bmpData    : IndexedTable<BMPIndex, Schema.UnicodeData.RawStorage>
  @usableFromInline internal let _nonbmpData : [SplitTable<UInt16, Schema.UnicodeData.RawStorage>]

  /// Initializes a database from static data.
  ///
  @inlinable @inline(__always)
  public init(
    asciiData : [Schema.ASCIIData.RawStorage],
    bmpIndex  : [BMPIndex.IndexStorage],
    bmpData   : SplitTable<UInt16, Schema.UnicodeData.RawStorage>,
    nonbmpData: [SplitTable<UInt16, Schema.UnicodeData.RawStorage>]
  ) {
    self._asciiData = asciiData
    self._bmpData = IndexedTable<BMPIndex, Schema.UnicodeData.RawStorage>(
      uncheckedIndex: bmpIndex,
      columnValues: bmpData.codepoints,
      dataValues: bmpData.data
    )
    self._nonbmpData = nonbmpData
    #if DEBUG
      self.validateStructure()
    #endif
  }

  public struct BMPIndex: IndexedTableSchema {

    public typealias IndexStorage = UInt16

    @usableFromInline
    internal typealias Column = UInt16

    @inlinable @inline(__always)
    internal static var ColumnBitsToIndex: Int { Schema.BMPIndexBits }
  }
}


// --------------------------------------------
// MARK: - Structure Validation
// --------------------------------------------


extension CodePointDatabase {

  /// Validates basic structural information about the database.
  ///
  /// This function does not perform any validation of data associated with code points,
  /// nor does it check that code-point tables are sorted (as they are expected to be).
  ///
  @usableFromInline
  internal func validateStructure() {

    // ASCII.
    precondition(_asciiData.count == 128)
    // BMP.
    _bmpData.validate()
    // Non-BMP.
    precondition(_nonbmpData.count == 16)
    for splitTable in _nonbmpData {
      // Check that the lengths of the split arrays are equal.
      // This means a valid position in the index table is a valid position in the entry table,
      // and we don't need to bounds-check when using a position from one table in the other table.
      precondition(
        splitTable.codepoints.count == splitTable.data.count,
        "The split index and entry tables must have the same number of elements"
      )
      // Every plane/sub-plane table must have at least one entry, for the start of the plane/sub-plane.
      precondition(splitTable.codepoints[0] == 0)
    }
  }
}


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension CodePointDatabase {

  public enum LookupResult {

    /// The data associated with an ASCII code-point.
    ///
    /// Each data value is associated with a single code-point.
    ///
    case ascii(Schema.ASCIIData)

    /// The data associated with a non-ASCII code-point.
    ///
    /// A single data value may represent a range of code-points.
    /// `startCodePoint` gives the code-point at which this data value starts to apply.
    ///
    case nonAscii(Schema.UnicodeData, startCodePoint: UInt32)
  }

  @inlinable
  public subscript(scalar: Unicode.Scalar) -> LookupResult {
    if scalar.isASCII {
      return .ascii(Schema.ASCIIData(storage: _asciiData.withUnsafeBufferPointer { buf in buf[Int(scalar.value)] }))
    }
    if scalar.value < 0x01_0000 {
      let offsetWithinBMP = UInt16(truncatingIfNeeded: scalar.value)
      return _bmpData.lookupRows(containing: offsetWithinBMP) { codePoints, data in
        let k = codePoints._codepointdatabase_partitionedIndex { offsetWithinBMP >= $0 } &- 1
        return .nonAscii(Schema.UnicodeData(storage: data[k]), startCodePoint: UInt32(codePoints[k]))
      }
    }
    return _nonbmp_withIndexAndDataTable(containing: scalar.value) {
      codePointTable, dataTable, planeStart, offsetWithinPlane in
      let k = codePointTable._codepointdatabase_partitionedIndex { offsetWithinPlane >= $0 } &- 1
      let startCodePoint = planeStart | UInt32(codePointTable[k])
      return .nonAscii(Schema.UnicodeData(storage: dataTable[k]), startCodePoint: startCodePoint)
    }
  }

  @inlinable
  internal func _nonbmp_withIndexAndDataTable<T>(
    containing codePoint: UInt32,
    body: (
      _ codePointTable: UnsafeBufferPointer<UInt16>,
      _ dataTable: UnsafeBufferPointer<Schema.UnicodeData.RawStorage>,
      _ planeStart: UInt32, _ offsetWithinPlane: UInt16
    ) -> T
  ) -> T {
    return _nonbmpData.withUnsafeBufferPointer { planeSplitTables in
      // Safety: 'planeDataIdx' only contains 4 bits of data after masking, so is limited to 0..<16 (all valid indexes).
      let planeDataIdx = UInt8(truncatingIfNeeded: (codePoint &>> 16) &- 1) & 0xF
      let dataForPlane = planeSplitTables[Int(planeDataIdx)]
      return dataForPlane.codepoints.withUnsafeBufferPointer { codePointTable in
        return dataForPlane.data.withUnsafeBufferPointer { dataTable in
          let startOfPlane = UInt32(planeDataIdx &+ 1) &<< 16
          let offsetWithinPlane = UInt16(truncatingIfNeeded: codePoint)
          return body(codePointTable, dataTable, startOfPlane, offsetWithinPlane)
        }
      }
    }
  }
}

extension CodePointDatabase.LookupResult where Schema.ASCIIData == Schema.UnicodeData {

  @inlinable
  public var value: Schema.ASCIIData {
    switch self {
    case .ascii(let v): return v
    case .nonAscii(let v, startCodePoint: _): return v
    }
  }
}

extension RandomAccessCollection {

  /// Returns the index of the first element in the collection
  /// that doesn't match the predicate.
  ///
  /// The collection must already be partitioned according to the
  /// predicate, as if `x.partition(by: predicate)` had already
  /// been called.
  ///
  @inlinable
  internal func _codepointdatabase_partitionedIndex(where predicate: (Element) -> Bool) -> Index {
    var low = self.startIndex
    var high = self.endIndex
    while low < high {
      let mid = index(low, offsetBy: distance(from: low, to: high) / 2)
      if predicate(self[mid]) {
        low = index(after: mid)
      } else {
        high = mid
      }
    }
    return low
  }
}


// --------------------------------------------
// MARK: - Generating Static Databases
// --------------------------------------------


#if WEBURL_UNICODE_PARSE_N_PRINT

  extension CodePointDatabase {

    /// A builder for a static database of information about Unicode code-points.
    ///
    /// Append entries to the database in code-point order, starting with `appendAscii` at code-point 0 (`U+0000`),
    /// appending individual entries for each of the 128 ASCII code-points.
    ///
    /// Next, call `appendUnicode`, starting at code-point 128 (`U+0080`). You may append entries for ranges of
    /// code-points at a time, but each range must be immediately follow the one that came before:
    ///
    /// ```swift
    /// appendUnicode(entryUno, 0x0080...0xABAB)
    /// appendUnicode(entryDuo, 0xABAC...0xCDCD)
    /// appendUnicode(entryTri, 0xCDCE...0xEFEF)
    /// appendUnicode(entryQut, 0xEFF0...0x10FFFF)
    /// ```
    ///
    /// You must finish with an entry that includes the maximum code-point, `0x10FFFF`.
    ///
    internal struct Builder {

      private var _asciiData: [Schema.ASCIIData.RawStorage]
      private var _bmpData: SplitTable<UInt16, Schema.UnicodeData.RawStorage>
      private var _nonbmpData: [SplitTable<UInt16, Schema.UnicodeData.RawStorage>]
      private var top: UInt32

      internal init() {
        _asciiData = []
        _bmpData = (codepoints: [], data: [])
        _nonbmpData = (0x01...0x10).map { _ in (codepoints: [], data: []) }
        top = 0
      }

      internal mutating func finalize() -> CodePointDatabase {
        precondition(top - 1 == 0x10FFFF, "Entries must be inserted up to (including) 0x10FFFF")

        let db = CodePointDatabase(
          asciiData: _asciiData,
          bmpIndex: IndexedTable<BMPIndex, Schema.UnicodeData.RawStorage>.buildIndex(_bmpData.codepoints),
          bmpData: _bmpData,
          nonbmpData: _nonbmpData
        )
        db.validateStructure()
        return db
      }

      internal mutating func appendAscii(_ data: Schema.ASCIIData, for codePoint: UInt32) {
        // Validate insertion.
        precondition(top == codePoint, "Inserting ASCII entry in wrong location!")
        precondition(codePoint < 128, "\(codePoint) is not an ASCII code-point")
        top += 1

        // Insert.
        _asciiData.append(data.storage)
      }

      internal mutating func appendUnicode(_ data: Schema.UnicodeData, for codePoints: ClosedRange<UInt32>) {
        // Validate insertion.
        precondition(top == codePoints.lowerBound, "Inserting Unicode entry in wrong location!")
        precondition(codePoints.lowerBound >= 0x80, "\(codePoints.lowerBound) is ASCII; use appendAscii instead")
        precondition(codePoints.lowerBound < 0x10FFFF, "\(codePoints.lowerBound) is not a valid Unicode code-point")
        precondition(codePoints.upperBound <= 0x10FFFF, "\(codePoints.upperBound) is not a valid Unicode code-point")
        top = codePoints.upperBound + 1

        // Insert.

        func addToPlaneTable(
          _ table: inout SplitTable<UInt16, Schema.UnicodeData.RawStorage>, planeRange: ClosedRange<UInt32>
        ) -> Bool {

          if codePoints.contains(planeRange.lowerBound) {
            // Crossing to a new plane table means we may need to split/copy the data.
            assert(table.codepoints.isEmpty)
            assert(table.data.isEmpty)
            let adjusted = Schema.unicodeData(data, at: codePoints.lowerBound, copyForStartingAt: planeRange.lowerBound)
            table.codepoints.append(UInt16(truncatingIfNeeded: planeRange.lowerBound))
            table.data.append(adjusted.storage)
            return true
          }
          if planeRange.contains(codePoints.lowerBound) {
            // Add this data to an existing plane table.
            assert(table.codepoints.isEmpty == false || codePoints.lowerBound == 0x80)
            assert(table.data.isEmpty == false || codePoints.lowerBound == 0x80)
            table.codepoints.append(UInt16(truncatingIfNeeded: codePoints.lowerBound))
            table.data.append(data.storage)
            return true
          }
          // Data does not belong in this plane at all.
          return false
        }

        var wasInsertedAtLeastOnce = false

        // - Add the data value for any parts of the range which lie within the BMP.

        if addToPlaneTable(&_bmpData, planeRange: 0x80...0x0_FFFF) { wasInsertedAtLeastOnce = true }

        // - Add the data value for any parts of the range which lie above the BMP.

        for plane in 1..<17 {
          let planeStart = UInt32(plane) << 16
          let planeRange = planeStart...planeStart + 0xFFFF
          if addToPlaneTable(&_nonbmpData[plane - 1], planeRange: planeRange) { wasInsertedAtLeastOnce = true }
        }

        precondition(wasInsertedAtLeastOnce, "Entry was not inserted: \(data)")
      }
    }
  }


  // --------------------------------------------
  // MARK: - Printing
  // --------------------------------------------


  internal protocol CodePointDatabase_Formatter {
    associatedtype Schema: CodePointDatabase_Schema

    static var asciiStorageElementType: String { get }
    static var unicodeStorageElementType: String { get }

    static func formatASCIIStorage(_: Schema.ASCIIData.RawStorage) -> String
    static func formatUnicodeStorage(_: Schema.UnicodeData.RawStorage) -> String
  }

  internal struct DefaultFormatter<Schema>: CodePointDatabase_Formatter
  where
    Schema: CodePointDatabase_Schema,
    Schema.ASCIIData.RawStorage: FixedWidthInteger, Schema.UnicodeData.RawStorage: FixedWidthInteger
  {
    internal static var asciiStorageElementType: String { "\(Schema.ASCIIData.RawStorage.self)" }
    internal static var unicodeStorageElementType: String { "\(Schema.UnicodeData.RawStorage.self)" }

    internal static func formatASCIIStorage(_ storage: Schema.ASCIIData.RawStorage) -> String {
      storage.hexString(format: .fullWidth)
    }

    internal static func formatUnicodeStorage(_ storage: Schema.UnicodeData.RawStorage) -> String {
      storage.hexString(format: .fullWidth)
    }
  }

  extension CodePointDatabase where Schema.UnicodeData.RawStorage: Equatable {

    /// Returns a String of this database as Swift source code.
    ///
    /// The `name` parameter is used as a prefix for the various internal tables.
    ///
    internal func printAsSwiftSourceCode<Formatter>(
      name: String, using formatter: Formatter.Type
    ) -> String where Formatter: CodePointDatabase_Formatter, Formatter.Schema == Schema {

      var output = ""

      // ASCII.

      printArrayLiteral(
        name: "\(name)_ascii",
        elementType: Formatter.asciiStorageElementType,
        data: _asciiData, columns: 8,
        formatter: Formatter.formatASCIIStorage,
        to: &output
      )
      output += "\n"

      // BMP.

      printArrayLiteral(
        name: "\(name)_bmp_index",
        elementType: "\(BMPIndex.IndexStorage.self)",
        data: _bmpData._index, columns: 8,
        to: &output
      )
      output += "\n"

      printArrayLiteral(
        name: "\(name)_bmp_codepoint",
        elementType: "UInt16",
        data: _bmpData._columnValues, columns: 8,
        formatter: { $0.hexString(format: .fullWidth) },
        to: &output
      )
      output += "\n"

      printArrayLiteral(
        name: "\(name)_bmp_data",
        elementType: Formatter.unicodeStorageElementType,
        data: _bmpData._dataValues, columns: 8,
        formatter: Formatter.formatUnicodeStorage,
        to: &output
      )
      output += "\n"

      // Non-BMP.

      Self.printPlaneData(
        name: name + "_nonbmp",
        tableData: _nonbmpData,
        using: Formatter.self,
        to: &output
      )

      return output
    }

    private static func printPlaneData<Formatter>(
      name: String,
      tableData: [SplitTable<UInt16, Schema.UnicodeData.RawStorage>],
      using formatter: Formatter.Type,
      to output: inout String
    ) where Formatter: CodePointDatabase_Formatter, Formatter.Schema == Schema {

      // De-dupe the tables.

      var uniqueCodepointTables = [[UInt16]]()
      var uniqueDataTables = [[Schema.UnicodeData.RawStorage]]()
      let dedupedPlaneData: [(codepointsIdx: Int, dataIdx: Int)] = tableData.map { splitTable in

        // Use .firstIndex(of:), because we only have 17 planes, and most of the time,
        // either the count is different or there are just 1 or 2 elements. Not worth hashing everything.

        var codepointTableIdx: Int
        if let existingCPTable = uniqueCodepointTables.firstIndex(of: splitTable.codepoints) {
          codepointTableIdx = existingCPTable
        } else {
          codepointTableIdx = uniqueCodepointTables.endIndex
          uniqueCodepointTables.append(splitTable.codepoints)
        }
        var dataTableIdx: Int
        if let existingDataTable = uniqueDataTables.firstIndex(of: splitTable.data) {
          dataTableIdx = existingDataTable
        } else {
          dataTableIdx = uniqueDataTables.endIndex
          uniqueDataTables.append(splitTable.data)
        }
        return (codepointTableIdx, dataTableIdx)
      }

      // Print each uniqued table separately.

      func codepointTableName(_ n: Int) -> String {
        "\(name)_codepoint_\(n)"
      }

      func dataTableName(_ n: Int) -> String {
        "\(name)_data_\(n)"
      }

      for (n, codepointTable) in uniqueCodepointTables.enumerated() {
        printArrayLiteral(
          name: codepointTableName(n),
          elementType: "UInt16",
          data: codepointTable, columns: 10,
          formatter: { $0.hexString(format: .fullWidth) },
          to: &output
        )
        output += "\n"
      }

      for (n, dataTable) in uniqueDataTables.enumerated() {
        printArrayLiteral(
          name: dataTableName(n),
          elementType: Formatter.unicodeStorageElementType,
          data: dataTable, columns: 8,
          formatter: Formatter.formatUnicodeStorage,
          to: &output
        )
        output += "\n"
      }

      // Print an overall array for use when initializing a CodePointDatabase.

      printArrayLiteral(
        name: "\(name)",
        elementType: "(codepoints: [UInt16], data: [\(Formatter.unicodeStorageElementType)])",
        data: dedupedPlaneData, columns: 1,
        formatter: { "(\(codepointTableName($0.codepointsIdx)), \(dataTableName($0.dataIdx)))" },
        to: &output
      )
    }
  }

#endif  // WEBURL_UNICODE_PARSE_N_PRINT
