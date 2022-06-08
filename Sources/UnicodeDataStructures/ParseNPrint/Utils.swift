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

#if WEBURL_UNICODE_PARSE_N_PRINT

  // --------------------------------------------
  // MARK: - Slicing and Padding
  // --------------------------------------------


  extension BidirectionalCollection {

    /// Returns the slice of this collection's trailing elements which match the given predicate.
    ///
    /// If no elements match the predicate, the returned slice is empty, from `endIndex..<endIndex`.
    ///
    internal func suffix(while predicate: (Element) -> Bool) -> SubSequence {
      var i = endIndex
      while i > startIndex {
        let beforeI = index(before: i)
        guard predicate(self[beforeI]) else { return self[i..<endIndex] }
        i = beforeI
      }
      return self[startIndex..<endIndex]
    }
  }

  extension Substring {

    internal var trimmingSpaces: Substring {
      let firstNonSpace = firstIndex(where: { $0 != " " }) ?? endIndex
      let lastNonSpace = lastIndex(where: { $0 != " " }).map { index(after: $0) } ?? endIndex
      return self[firstNonSpace..<lastNonSpace]
    }
  }

  extension String {
    internal func leftPadding(toLength newLength: Int, withPad character: Character) -> String {
      precondition(count <= newLength, "newLength must be greater than or equal to string length")
      return String(repeating: character, count: newLength - count) + self
    }
  }


  // --------------------------------------------
  // MARK: - Converting SegmentedLine <-> CodePointDatabase
  // --------------------------------------------


  extension SegmentedLine where Bound == UInt32 {

    func generateTable<Schema>(
      _: Schema.Type,
      mapAsciiValue: (Value) -> Schema.ASCIIData,
      mapUnicodeValue: (Value) -> Schema.UnicodeData
    ) -> CodePointDatabase<Schema> where Schema: CodePointDatabase_Schema {
      precondition(self.bounds.lowerBound == 0)
      precondition(self.bounds.upperBound == 0x11_0000)

      var builder = CodePointDatabase<Schema>.Builder()
      for (range, value) in segments {
        for asciiCodePoint in range.clamped(to: 0..<0x80) {
          builder.appendAscii(mapAsciiValue(value), for: asciiCodePoint)
        }
        guard range.upperBound > 0x80 else { continue }
        builder.appendUnicode(mapUnicodeValue(value), for: ClosedRange(range.clamped(to: 0x80..<0x110000)))
      }
      return builder.finalize()
    }
  }

// CodePointDatabase -> SegmentedLine (unused right now)
//
//extension CodePointDatabase {
//
//  static func toRangeTableData(
//    offset: UInt32, _ input: SplitTable<UInt16, Schema.UnicodeData.RawStorage>
//  ) -> [(UInt32, Schema.UnicodeData)] {
//    var result = [(UInt32, Schema.UnicodeData)]()
//    result.reserveCapacity(input.codePointTable.count)
//    for i in 0..<input.codePointTable.count {
//      result.append(
//        (offset + UInt32(input.codePointTable[i]), Schema.UnicodeData(storage: input.dataTable[i]))
//      )
//    }
//    return result
//  }
//
//  func iterateRangeTables(body: (RangeTable<UInt32, Schema.UnicodeData>) -> Void) {
//
//    // FIXME: ASCII?
//
//    for (n, bmpSubArray) in _bmpData.enumerated() {
//      let start = UInt32(bmpSubArray.codePointTable.first!)
//      let end = start + 0x00_1000
//      let table = RangeTable(_upperBound: end, _data: Self.toRangeTableData(offset: 0, bmpSubArray))
//      body(table)
//    }
//    for (n, nonbmpArray) in _nonbmpData.enumerated() {
//      let start = UInt32((n + 1) * 0x1_0000)
//      let end = start + 0x01_0000
//      let table = RangeTable(_upperBound: end, _data: Self.toRangeTableData(offset: start, nonbmpArray))
//      body(table)
//    }
//  }
//}

#endif  // WEBURL_UNICODE_PARSE_N_PRINT
