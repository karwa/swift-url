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
@usableFromInline
internal protocol HasRawStorage {
  associatedtype RawStorage

  init(storage: RawStorage)
  var storage: RawStorage { get }
}

/// Describes the data associated with code-points in a `CodePointDatabase`.
///
@usableFromInline
internal protocol CodePointDatabase_Schema {

  /// The type of data that is stored for ASCII code-points.
  associatedtype ASCIIData: HasRawStorage

  /// The type of data that is stored for non-ASCII code-points.
  associatedtype UnicodeData: HasRawStorage

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
  /// The default behaviour is to simply return `data`. Most values do not care about their precise location
  /// in the database this way. If you don't use the `startCodePoint` portion of ``CodePointDatabase/LookupResult``,
  /// you don't need to care about this.
  ///
  static func unicodeData(
    _ data: UnicodeData, at originalStart: UInt32, copyForStartingAt newStartPoint: UInt32
  ) -> UnicodeData
}

extension CodePointDatabase_Schema {

  @inlinable
  internal static func unicodeData(
    _ data: UnicodeData, at originalStart: UInt32, copyForStartingAt newStartPoint: UInt32
  ) -> UnicodeData {
    data
  }
}


// --------------------------------------------
// MARK: - CodePointDatabase
// --------------------------------------------


// swift-format-ignore
/// A static database of information about Unicode code-points.
///
/// Databases can be constructed using a `CodePointDatabase.Builder`, after which they may be queried,
/// or printed as a Swift source file.
///
/// Data is stored in 3 sections:
///
/// - A direct lookup for ASCII code-points, to values of the `Schema.ASCIIData` type.
///
/// - A 4:12 2-stage lookup for BMP code-points, to values of the `Schema.UnicodeData` type.
///
/// - A per-plane lookup table for non-BMP code-points, using compressed 16-bit entries,
///   to values of the `Schema.UnicodeData` type.
///
@usableFromInline
internal struct CodePointDatabase<Schema: CodePointDatabase_Schema> {

  @usableFromInline
  internal typealias SplitTable<CodePoint, Data> = (codePointTable: [CodePoint], dataTable: [Data])

  @usableFromInline internal var _asciiData : [Schema.ASCIIData.RawStorage]
  @usableFromInline internal var _bmpData   : [SplitTable<UInt16, Schema.UnicodeData.RawStorage>]
  @usableFromInline internal var _nonbmpData: [SplitTable<UInt16, Schema.UnicodeData.RawStorage>]

  /// Initializes a database from static data.
  ///
  @inlinable
  internal init(
    asciiData : [Schema.ASCIIData.RawStorage],
    bmpData   : [SplitTable<UInt16, Schema.UnicodeData.RawStorage>],
    nonbmpData: [SplitTable<UInt16, Schema.UnicodeData.RawStorage>]
  ) {
    self._asciiData = asciiData
    self._bmpData = bmpData
    self._nonbmpData = nonbmpData
    #if DEBUG
      validateStructure()
    #endif
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
    do {
      precondition(_asciiData.count == 128)
      precondition(_bmpData.count == 16)
      precondition(_nonbmpData.count == 16)
    }
    // Check that the lengths of the split arrays are equal.
    // This means a valid position in the index table is a valid position in the entry table,
    // and we don't need to bounds-check when using a position from one table in the other table.
    do {
      for splitTable in _bmpData {
        precondition(
          splitTable.codePointTable.count == splitTable.dataTable.count,
          "The split index and entry tables must have the same number of elements"
        )
      }
      for splitTable in _nonbmpData {
        precondition(
          splitTable.codePointTable.count == splitTable.dataTable.count,
          "The split index and entry tables must have the same number of elements"
        )
      }
    }
    // Every plane/sub-plane table must have at least one entry, for the start of the plane/sub-plane.
    do {
      var bmpIter = _bmpData.enumerated().makeIterator()
      precondition(bmpIter.next()?.element.codePointTable[0] == 0x80, "The first BMP sub-plane should start at 0x80")
      while let (subplane, splitTable) = bmpIter.next() {
        precondition(splitTable.codePointTable[0] == (subplane << 12))
      }
      for splitTable in _nonbmpData {
        precondition(splitTable.codePointTable[0] == 0)
      }
    }
  }
}


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension CodePointDatabase {

  @usableFromInline
  internal enum LookupResult {

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
  internal subscript(scalar: Unicode.Scalar) -> LookupResult {
    if scalar.isASCII {
      return .ascii(Schema.ASCIIData(storage: _asciiData.withUnsafeBufferPointer { buf in buf[Int(scalar.value)] }))
    }
    if scalar.value < 0x01_0000 {
      return _bmp_withIndexAndDataTable(containing: scalar) {
        codePointTable, dataTable, offsetWithinBMP in
        let k = codePointTable._codepointdatabase_partitionedIndex { offsetWithinBMP >= $0 } &- 1
        return .nonAscii(Schema.UnicodeData(storage: dataTable[k]), startCodePoint: UInt32(codePointTable[k]))
      }
    }
    return _nonbmp_withIndexAndDataTable(containing: scalar) {
      codePointTable, dataTable, planeStart, offsetWithinPlane in
      let k = codePointTable._codepointdatabase_partitionedIndex { offsetWithinPlane >= $0 } &- 1
      let startCodePoint = planeStart | UInt32(codePointTable[k])
      return .nonAscii(Schema.UnicodeData(storage: dataTable[k]), startCodePoint: startCodePoint)
    }
  }

  // Note: The BMP codepoint table stores full scalar values in its 16 bits, since BMP scalars are only 16 bit.
  //       In other words, 0x0ABC, 0x1ABC, and 0x2ABC are stored like that in the code-point table,
  //       rather than being stored like "offset: 0x0ABC in table: 0/1/2/...".
  @inlinable
  internal func _bmp_withIndexAndDataTable<T>(
    containing scalar: Unicode.Scalar,
    body: (
      _ codePointTable: UnsafeBufferPointer<UInt16>,
      _ dataTable: UnsafeBufferPointer<Schema.UnicodeData.RawStorage>,
      _ offsetWithinBMP: UInt16
    ) -> T
  ) -> T {
    let offsetWithinBMP = UInt16(truncatingIfNeeded: scalar.value)
    let subplane = offsetWithinBMP &>> 12
    return _bmpData.withUnsafeBufferPointer { subplaneSplitTables in
      let dataForSubplane = subplaneSplitTables[Int(subplane)]
      return dataForSubplane.codePointTable.withUnsafeBufferPointer { codePointTable in
        return dataForSubplane.dataTable.withUnsafeBufferPointer { dataTable in
          return body(codePointTable, dataTable, offsetWithinBMP)
        }
      }
    }
  }

  @inlinable
  internal func _nonbmp_withIndexAndDataTable<T>(
    containing scalar: Unicode.Scalar,
    body: (
      _ codePointTable: UnsafeBufferPointer<UInt16>,
      _ dataTable: UnsafeBufferPointer<Schema.UnicodeData.RawStorage>,
      _ planeStart: UInt32, _ offsetWithinPlane: UInt16
    ) -> T
  ) -> T {
    let (plane, offsetWithinPlane) = (scalar.value &>> 16, UInt16(truncatingIfNeeded: scalar.value))
    let planeStart = plane &<< 16
    return _nonbmpData.withUnsafeBufferPointer { planeSplitTables in
      let dataForPlane = planeSplitTables[Int(plane &- 1)]
      return dataForPlane.codePointTable.withUnsafeBufferPointer { codePointTable in
        return dataForPlane.dataTable.withUnsafeBufferPointer { dataTable in
          return body(codePointTable, dataTable, planeStart, offsetWithinPlane)
        }
      }
    }
  }
}

extension CodePointDatabase.LookupResult where Schema.ASCIIData == Schema.UnicodeData {

  @inlinable
  internal var value: Schema.ASCIIData {
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


#if UNICODE_DB_INCLUDE_BUILDER

  extension CodePointDatabase {

    /// For the builder only. Creates an empty database.
    ///
    fileprivate init() {
      _asciiData = []
      _bmpData = (0x00...0x0F).map { _ in (codePointTable: [], dataTable: []) }
      _nonbmpData = (0x01...0x10).map { _ in (codePointTable: [], dataTable: []) }
    }

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
      private var db: CodePointDatabase
      private var top: UInt32

      internal init() {
        db = CodePointDatabase()
        top = 0
      }

      internal func finalize() -> CodePointDatabase {
        precondition(top - 1 == 0x10FFFF, "Entries must be inserted up to (including) 0x10FFFF")
        db.validateStructure()
        return db
      }

      internal mutating func appendAscii(_ data: Schema.ASCIIData, for codePoint: UInt32) {
        // Validate insertion.
        precondition(top == codePoint, "Inserting ASCII entry in wrong location!")
        precondition(codePoint < 128, "\(codePoint) is not an ASCII code-point")
        top += 1

        // Insert.
        db._asciiData.append(data.storage)
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
            assert(table.codePointTable.isEmpty)
            assert(table.dataTable.isEmpty)
            table.codePointTable.append(UInt16(truncatingIfNeeded: planeRange.lowerBound))
            let adjusted = Schema.unicodeData(data, at: codePoints.lowerBound, copyForStartingAt: planeRange.lowerBound)
            table.dataTable.append(adjusted.storage)
            return true
          }
          if planeRange.contains(codePoints.lowerBound) {
            // Add this data to an existing plane table.
            assert(table.codePointTable.isEmpty == false || codePoints.lowerBound == 0x80)
            assert(table.dataTable.isEmpty == false || codePoints.lowerBound == 0x80)
            table.codePointTable.append(UInt16(truncatingIfNeeded: codePoints.lowerBound))
            table.dataTable.append(data.storage)
            return true
          }
          // Data does not belong in this plane at all.
          return false
        }

        var wasInsertedAtLeastOnce = false

        // - Add the data value for any parts of the range which lie within the BMP.

        if codePoints.lowerBound < 0x1_0000 {
          for subPlane in 0x00...0x0F {
            let subplaneStart = UInt32(subPlane) << 12
            let subplaneRange = subplaneStart...subplaneStart + 0x0FFF
            if addToPlaneTable(&db._bmpData[subPlane], planeRange: subplaneRange) { wasInsertedAtLeastOnce = true }
          }
        }

        // - Add the data value for any parts of the range which lie above the BMP.

        for plane in 1..<17 {
          let planeStart = UInt32(plane) << 16
          let planeRange = planeStart...planeStart + 0xFFFF
          if addToPlaneTable(&db._nonbmpData[plane - 1], planeRange: planeRange) { wasInsertedAtLeastOnce = true }
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

  extension CodePointDatabase {

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
        elementType: Formatter.asciiEntryElementType,
        data: _asciiData, columns: 8,
        formatter: Formatter.formatASCIIEntry,
        to: &output
      )
      output += "\n"

      // BMP.

      Self.printPlaneData(
        name: name + "_bmp",
        tableData: _bmpData,
        using: Formatter.self,
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

      // Print each split table separately.

      var subTables = [(String, String)]()
      for (plane, data) in tableData.enumerated() {
        let codePointTableName = "\(name)_\(plane)"
        let dataTableName = "\(name)_data_\(plane)"

        printArrayLiteral(
          name: codePointTableName,
          elementType: "UInt16",
          data: data.codePointTable, columns: 10,
          formatter: { $0.hexString(format: .fullWidth) },
          to: &output
        )
        output += "\n"

        printArrayLiteral(
          name: dataTableName,
          elementType: Formatter.unicodeEntryElementType,
          data: data.dataTable, columns: 8,
          formatter: Formatter.formatUnicodeEntry,
          to: &output
        )
        output += "\n"

        subTables.append((codePointTableName, dataTableName))
      }

      // Print an overall "_splitTables" array for recombining as a CodePointDatabase.

      printArrayLiteral(
        name: "\(name)_splitTables",
        elementType: "(codePointTable: [UInt16], dataTable: [\(Formatter.unicodeEntryElementType)])",
        data: subTables, columns: 1,
        formatter: { "(codePointTable: \($0.0), dataTable: \($0.1))" },
        to: &output
      )
    }
  }

#endif  // UNICODE_DB_INCLUDE_BUILDER
