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

import XCTest

@testable import WebURL

class MutableCollectionExtensionsTests: XCTestCase {}

// MutableCollection.collapseConsecutiveElements(from:matching:)

extension MutableCollectionExtensionsTests {

  func testCollapseRuns() {

    // Empty collection.
    do {
      var empty: [Int] = []
      let end = empty.collapseConsecutiveElements(from: 0, matching: { _ in true })
      XCTAssertEqual(end, 0)
    }

    var collection = [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2]
    func resetCollection() {
      collection = [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2]
    }

    // No matches.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0 == 10 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex)
    }

    // No matches from offset.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 4, matching: { $0 == 1 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex)
    }

    // Single element matches (no runs of consecutive elements)
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0 == 4 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex)
    }

    // Multiple, single-element matches (no runs of consecutive elements)
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0 == 3 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex)
    }

    // Single run of consecutive elements.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0 == 5 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2, 2])
      XCTAssertEqualElements(collection[..<end], [1, 2, 2, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex - 1)
    }

    // Single run of consecutive elements, ending at endIndex.
    do {
      collection = [1, 2, 2, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2, 5, 5, 5, 5]
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0 == 5 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2, 5, 5, 5, 5])
      XCTAssertEqualElements(collection[..<end], [1, 2, 2, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2, 5])
      XCTAssertEqual(end, collection.endIndex - 3)
    }

    // Single run of consecutive elements, no match from offset.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 10, matching: { $0 == 5 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex)
    }

    // Single run of consecutive elements, offset is in the middle of the run.
    do {
      resetCollection()
      XCTAssertEqual(collection[8], 5)
      XCTAssertEqual(collection[9], 5)
      let end = collection.collapseConsecutiveElements(from: 9, matching: { $0 == 5 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 2, 4, 5, 5, 2, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex)
    }

    // Multiple runs of consecutive elements.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0 == 2 })
      XCTAssertEqualElements(collection, [1, 2, 3, 2, 4, 5, 5, 2, 3, 6, 7, 8, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqualElements(collection[..<end], [1, 2, 3, 2, 4, 5, 5, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex - 6)
    }

    // Multiple runs of consecutive elements, from offset.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 3, matching: { $0 == 2 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 4, 5, 5, 2, 3, 6, 7, 8, 2, 3, 6, 7, 8, 2])
      XCTAssertEqualElements(collection[..<end], [1, 2, 2, 3, 2, 4, 5, 5, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex - 5)
    }

    // Multiple runs of consecutive elements, offset is in the middle of a run.
    do {
      resetCollection()
      XCTAssertEqual(collection[4], 2)
      XCTAssertEqual(collection[5], 2)
      XCTAssertEqual(collection[6], 2)
      let end = collection.collapseConsecutiveElements(from: 5, matching: { $0 == 2 })
      XCTAssertEqualElements(collection, [1, 2, 2, 3, 2, 2, 4, 5, 5, 2, 3, 6, 7, 8, 2, 6, 7, 8, 2])
      XCTAssertEqualElements(collection[..<end], [1, 2, 2, 3, 2, 2, 4, 5, 5, 2, 3, 6, 7, 8, 2])
      XCTAssertEqual(end, collection.endIndex - 4)
    }

    // Predicate matches distinct elements.
    do {
      resetCollection()
      let end = collection.collapseConsecutiveElements(from: 0, matching: { $0.isMultiple(of: 2) })
      XCTAssertEqualElements(collection, [1, 2, 3, 2, 5, 5, 2, 3, 6, 7, 8, 2, 2, 2, 3, 6, 7, 8, 2])
      XCTAssertEqualElements(collection[..<end], [1, 2, 3, 2, 5, 5, 2, 3, 6, 7, 8])
      XCTAssertEqual(end, collection.endIndex - 8)
    }

    // Strings.

    func withUTF8Array<T>(_ string: String, _ modify: (inout [UInt8]) -> T) -> (String, T) {
      var utf8 = Array(string.utf8)
      let result = modify(&utf8)
      return (String(decoding: utf8, as: UTF8.self), result)
    }

    do {
      let (string, endOffset) = withUTF8Array("aababbaaacaaa") { utf8 in
        utf8.collapseConsecutiveElements(from: 0, matching: { $0 == ASCII.a.codePoint })
      }
      XCTAssertEqual(endOffset, 8)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "ababbaca".utf8)
      XCTAssertEqual(string, "ababbacaacaaa")
    }

    do {
      let (string, endOffset) = withUTF8Array(#"\\server\/\/\/\/\/\/\/\/\/\/\share\///////pop/////.//././//.////boo"#) {
        $0.collapseConsecutiveElements(from: 8, matching: { PathComponentParser.isPathSeparator($0, scheme: .file) })
      }
      XCTAssertEqual(endOffset, 30)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), #"\\server\share\pop/././././boo"#.utf8)
      XCTAssertEqual(string, #"\\server\share\pop/././././boohare\///////pop/////.//././//.////boo"#)
    }
  }
}

// MutableCollection.trimSegments(from:separatedBy:_:)

extension MutableCollectionExtensionsTests {

  func testTrimSegments() {

    func withUTF8Array<T>(_ string: String, _ modify: (inout [UInt8]) -> T) -> (String, T) {
      var utf8 = Array(string.utf8)
      let result = modify(&utf8)
      return (String(decoding: utf8, as: UTF8.self), result)
    }

    for skipInitialSeparator in [true, false] {

      func _testTrimSegments(
        source: String, from: Int? = nil, to: Int? = nil,
        remove: Set<Int> = [], trim: Set<Int> = [], trimAmount: (front: Int, back: Int) = (1, 3),
        ranges: [Range<Int>]
      ) -> String {

        var callbackCount = 0

        let (string, _) = withUTF8Array(source) { utf8 in
          let newEnd = utf8.trimSegments(
            from: from,
            to: to,
            skipInitialSeparator: skipInitialSeparator,
            separatedBy: { $0 == ASCII.forwardSlash.codePoint }
          ) { elements, range, isLast in

            if callbackCount == 0 {
              XCTAssertEqualElements(elements, source.utf8)
              XCTAssertEqual(isLast, ranges.count == 1)
            }
            XCTAssertEqual(elements[range].contains(ASCII.forwardSlash.codePoint), false)
            XCTAssertEqual(range, ranges[callbackCount])
            XCTAssertEqual(isLast, callbackCount == ranges.count - 1)
            defer { callbackCount += 1 }

            if remove.contains(callbackCount) {
              return nil
            } else if trim.contains(callbackCount) {
              return range.dropFirst(trimAmount.front).dropLast(trimAmount.back)
            } else {
              return range
            }
          }
          utf8.removeSubrange(newEnd..<(to ?? utf8.endIndex))
        }

        XCTAssertEqual(callbackCount, ranges.count)
        return string
      }

      func _testMultiTrimSegments(
        source: String, from: Int? = nil, to: Int? = nil,
        ranges: [Range<Int>],
        trimAmount: (front: Int, back: Int) = (1, 3),
        expected: [String]
      ) {

        var expectedResults = expected.makeIterator()

        for segmentToRemove in 0..<ranges.count {
          // (remove: n, trim: none)
          let str = _testTrimSegments(
            source: source,
            from: from,
            to: to,
            remove: [segmentToRemove],
            ranges: ranges
          )
          XCTAssertEqual(str, expectedResults.next())

          for segmentToTrim in 0..<ranges.count where segmentToTrim != segmentToRemove {
            // (remove: n, trim: m)
            let str = _testTrimSegments(
              source: source,
              from: from,
              to: to,
              remove: [segmentToRemove],
              trim: [segmentToTrim],
              trimAmount: trimAmount,
              ranges: ranges
            )
            XCTAssertEqual(str, expectedResults.next())
          }
        }

        XCTAssertEqual(expectedResults.next(), nil)
      }

      // Empty collection.

      do {
        var str = _testTrimSegments(source: "", ranges: [0..<0])
        XCTAssertEqual(str, "")

        str = _testTrimSegments(source: "", remove: [0], ranges: [0..<0])
        XCTAssertEqual(str, "")

        str = _testTrimSegments(source: "", trim: [0], ranges: [0..<0])
        XCTAssertEqual(str, "")
      }

      // Empty range.

      do {
        let source = "ab/c//de/f"
        for offset in 0..<source.utf8.count {

          var str = _testTrimSegments(
            source: source,
            from: offset,
            to: offset,
            ranges: [offset..<offset]
          )
          XCTAssertEqual(str, source)

          str = _testTrimSegments(
            source: source,
            from: offset,
            to: offset,
            remove: [0],
            ranges: [offset..<offset]
          )
          XCTAssertEqual(str, source)

          str = _testTrimSegments(
            source: source,
            from: offset,
            to: offset,
            trim: [0],
            ranges: [offset..<offset]
          )
          XCTAssertEqual(str, source)
        }
      }

      // 1 segment. No separators.

      do {
        let source = "abcdefg"
        let ranges = [0..<7]

        // Remove none.
        var str = _testTrimSegments(source: source, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove all.
        str = _testTrimSegments(source: source, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "")

        // Trim start.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (2, 0), ranges: ranges)
        XCTAssertEqual(str, "cdefg")

        // Trim end.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (0, 2), ranges: ranges)
        XCTAssertEqual(str, "abcde")

        // Trim both ends.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (2, 2), ranges: ranges)
        XCTAssertEqual(str, "cde")
      }

      // 1 segment. Collection starts with separator, which is skipped.

      if skipInitialSeparator {
        let source = "/abcdefg"
        let ranges = [1..<8]

        // Remove none.
        var str = _testTrimSegments(source: source, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove all.
        str = _testTrimSegments(source: source, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "/")

        // Trim start.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (2, 0), ranges: ranges)
        XCTAssertEqual(str, "/cdefg")

        // Trim end.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (0, 2), ranges: ranges)
        XCTAssertEqual(str, "/abcde")

        // Trim both ends.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (2, 2), ranges: ranges)
        XCTAssertEqual(str, "/cde")
      }

      // 2 segments. One separator in the middle.

      do {
        let source = "abcdefg/hijklmnop"
        let ranges = [0..<7, 8..<17]

        // swift-format-ignore
        _testMultiTrimSegments(
          source: source,
          ranges: ranges,
          expected: [
            "hijklmnop",  // (remove: 0, trim: none)
            "ijklm",      // (remove: 0, trim: 1)

            "abcdefg/",   // (remove: 1, trim: none)
            "bcd/",       // (remove: 1, trim: 0)
          ]
        )

        // Remove none.
        var str = _testTrimSegments(source: source, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove all.
        str = _testTrimSegments(source: source, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "")

        // Trim all.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "bcd/ijklm")
      }

      // 2/3 segments. Collection starts with separator.

      do {
        let source = "/abcdefg/hijklmnop"
        var ranges: [Range<Int>] {
          if skipInitialSeparator {
            return [1..<8, 9..<18]
          } else {
            return [0..<0, 1..<8, 9..<18]
          }
        }

        if skipInitialSeparator {
          // swift-format-ignore
          _testMultiTrimSegments(
            source: source,
            ranges: ranges,
            expected: [
              "/hijklmnop",  // (remove: 0, trim: none)
              "/ijklm",      // (remove: 0, trim: 1)

              "/abcdefg/",   // (remove: 1, trim: none)
              "/bcd/",       // (remove: 1, trim: 0)
            ]
          )
        } else {
          // swift-format-ignore
          _testMultiTrimSegments(
            source: source,
            ranges: ranges,
            expected: [
              "abcdefg/hijklmnop",  // (remove: 0, trim: none)
              "bcd/hijklmnop",      // (remove: 0, trim: 1)
              "abcdefg/ijklm",      // (remove: 0, trim: 2)

              "/hijklmnop",         // (remove: 1, trim: none)
              "/hijklmnop",         // (remove: 1, trim: 0)
              "/ijklm",             // (remove: 1, trim: 2)

              "/abcdefg/",          // (remove: 2, trim: none)
              "/abcdefg/",          // (remove: 2, trim: 0)
              "/bcd/",              // (remove: 2, trim: 1)
            ]
          )
        }

        // Remove none.
        var str = _testTrimSegments(source: source, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove all.
        str = _testTrimSegments(source: source, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, skipInitialSeparator ? "/" : "")

        // Trim all.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "/bcd/ijklm")
      }

      // Many segments. Collection starts and ends with a separator.

      do {
        let source = "/abc/defg/hijk/lmnop/"
        var ranges: [Range<Int>] {
          if skipInitialSeparator {
            return [1..<4, 5..<9, 10..<14, 15..<20, 21..<21]
          } else {
            return [0..<0, 1..<4, 5..<9, 10..<14, 15..<20, 21..<21]
          }
        }

        if skipInitialSeparator {
          // swift-format-ignore
          _testMultiTrimSegments(
            source: source,
            ranges: ranges,
            trimAmount: (front: 1, back: 1),
            expected: [
              "/defg/hijk/lmnop/",  // (remove: 0, trim: none)
              "/ef/hijk/lmnop/",    // (remove: 0, trim: 1)
              "/defg/ij/lmnop/",    // (remove: 0, trim: 2)
              "/defg/hijk/mno/",    // (remove: 0, trim: 3)
              "/defg/hijk/lmnop/",  // (remove: 0, trim: 4)

              "/abc/hijk/lmnop/",   // (remove: 1, trim: none)
              "/b/hijk/lmnop/",     // (remove: 1, trim: 0)
              "/abc/ij/lmnop/",     // (remove: 1, trim: 2)
              "/abc/hijk/mno/",     // (remove: 1, trim: 3)
              "/abc/hijk/lmnop/",   // (remove: 1, trim: 4)

              "/abc/defg/lmnop/",   // (remove: 2, trim: none)
              "/b/defg/lmnop/",     // (remove: 2, trim: 0)
              "/abc/ef/lmnop/",     // (remove: 2, trim: 1)
              "/abc/defg/mno/",     // (remove: 2, trim: 3)
              "/abc/defg/lmnop/",   // (remove: 2, trim: 4)

              "/abc/defg/hijk/",    // (remove: 3, trim: none)
              "/b/defg/hijk/",      // (remove: 3, trim: 0)
              "/abc/ef/hijk/",      // (remove: 3, trim: 1)
              "/abc/defg/ij/",      // (remove: 3, trim: 2)
              "/abc/defg/hijk/",    // (remove: 3, trim: 4)

              "/abc/defg/hijk/lmnop/",  // (remove: 4, trim: none)
              "/b/defg/hijk/lmnop/",    // (remove: 4, trim: 0)
              "/abc/ef/hijk/lmnop/",    // (remove: 4, trim: 1)
              "/abc/defg/ij/lmnop/",    // (remove: 4, trim: 2)
              "/abc/defg/hijk/mno/",    // (remove: 4, trim: 3)
            ]
          )
        } else {
          // swift-format-ignore
          _testMultiTrimSegments(
            source: source,
            ranges: ranges,
            trimAmount: (front: 1, back: 1),
            expected: [
              "abc/defg/hijk/lmnop/",   // (remove: 0, trim: none)
              "b/defg/hijk/lmnop/",     // (remove: 0, trim: 1)
              "abc/ef/hijk/lmnop/",     // (remove: 0, trim: 2)
              "abc/defg/ij/lmnop/",     // (remove: 0, trim: 3)
              "abc/defg/hijk/mno/",     // (remove: 0, trim: 4)
              "abc/defg/hijk/lmnop/",   // (remove: 0, trim: 5)

              "/defg/hijk/lmnop/",      // (remove: 1, trim: none)
              "/defg/hijk/lmnop/",      // (remove: 1, trim: 0)
              "/ef/hijk/lmnop/",        // (remove: 1, trim: 2)
              "/defg/ij/lmnop/",        // (remove: 1, trim: 3)
              "/defg/hijk/mno/",        // (remove: 1, trim: 4)
              "/defg/hijk/lmnop/",      // (remove: 1, trim: 5)

              "/abc/hijk/lmnop/",       // (remove: 2, trim: none)
              "/abc/hijk/lmnop/",       // (remove: 2, trim: 0)
              "/b/hijk/lmnop/",         // (remove: 2, trim: 1)
              "/abc/ij/lmnop/",         // (remove: 2, trim: 3)
              "/abc/hijk/mno/",         // (remove: 2, trim: 4)
              "/abc/hijk/lmnop/",       // (remove: 2, trim: 5)

              "/abc/defg/lmnop/",       // (remove: 3, trim: none)
              "/abc/defg/lmnop/",       // (remove: 3, trim: 0)
              "/b/defg/lmnop/",         // (remove: 3, trim: 1)
              "/abc/ef/lmnop/",         // (remove: 3, trim: 2)
              "/abc/defg/mno/",         // (remove: 3, trim: 4)
              "/abc/defg/lmnop/",       // (remove: 3, trim: 5)

              "/abc/defg/hijk/",        // (remove: 4, trim: none)
              "/abc/defg/hijk/",        // (remove: 4, trim: 0)
              "/b/defg/hijk/",          // (remove: 4, trim: 1)
              "/abc/ef/hijk/",          // (remove: 4, trim: 2)
              "/abc/defg/ij/",          // (remove: 4, trim: 3)
              "/abc/defg/hijk/",        // (remove: 4, trim: 5)

              "/abc/defg/hijk/lmnop/",  // (remove: 5, trim: none)
              "/abc/defg/hijk/lmnop/",  // (remove: 5, trim: 0)
              "/b/defg/hijk/lmnop/",    // (remove: 5, trim: 1)
              "/abc/ef/hijk/lmnop/",    // (remove: 5, trim: 2)
              "/abc/defg/ij/lmnop/",    // (remove: 5, trim: 3)
              "/abc/defg/hijk/mno/",    // (remove: 5, trim: 4)
            ]
          )
        }

        // Remove none.
        var str = _testTrimSegments(source: source, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove some.
        str = _testTrimSegments(
          source: source,
          remove: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }),
          ranges: ranges
        )
        XCTAssertEqual(str, skipInitialSeparator ? "/defg/lmnop/" : "abc/hijk/")

        // Remove all.
        str = _testTrimSegments(source: source, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, skipInitialSeparator ? "/" : "")

        // Trim some.
        str = _testTrimSegments(
          source: source,
          trim: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }), trimAmount: (1, 1),
          ranges: ranges
        )
        XCTAssertEqual(str, skipInitialSeparator ? "/b/defg/ij/lmnop/" : "/abc/ef/hijk/mno/")

        // Trim all.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), trimAmount: (1, 1), ranges: ranges)
        XCTAssertEqual(str, "/b/ef/ij/mno/")

        // Trim to empty segments.
        str = _testTrimSegments(source: source, trim: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "////m/")
      }

      // Empty segments.

      do {
        let source = "abc/defg//hijkl///m"
        let ranges = [0..<3, 4..<8, 9..<9, 10..<15, 16..<16, 17..<17, 18..<19]

        // swift-format-ignore
        _testMultiTrimSegments(
          source: source,
          ranges: ranges,
          trimAmount: (front: 1, back: 1),
          expected: [
            "defg//hijkl///m",     // (remove: 0, trim: none)
            "ef//hijkl///m",       // (remove: 0, trim: 1)
            "defg//hijkl///m",     // (remove: 0, trim: 2)
            "defg//ijk///m",       // (remove: 0, trim: 3)
            "defg//hijkl///m",     // (remove: 0, trim: 4)
            "defg//hijkl///m",     // (remove: 0, trim: 5)
            "defg//hijkl///",      // (remove: 0, trim: 6)

            "abc//hijkl///m",      // (remove: 1, trim: none)
            "b//hijkl///m",        // (remove: 1, trim: 0)
            "abc//hijkl///m",      // (remove: 1, trim: 2)
            "abc//ijk///m",        // (remove: 1, trim: 3)
            "abc//hijkl///m",      // (remove: 1, trim: 4)
            "abc//hijkl///m",      // (remove: 1, trim: 5)
            "abc//hijkl///",       // (remove: 1, trim: 6)

            "abc/defg/hijkl///m",  // (remove: 2, trim: none)
            "b/defg/hijkl///m",    // (remove: 2, trim: 0)
            "abc/ef/hijkl///m",    // (remove: 2, trim: 1)
            "abc/defg/ijk///m",    // (remove: 2, trim: 3)
            "abc/defg/hijkl///m",  // (remove: 2, trim: 4)
            "abc/defg/hijkl///m",  // (remove: 2, trim: 5)
            "abc/defg/hijkl///",   // (remove: 2, trim: 6)

            "abc/defg////m",       // (remove: 3, trim: none)
            "b/defg////m",         // (remove: 3, trim: 0)
            "abc/ef////m",         // (remove: 3, trim: 1)
            "abc/defg////m",       // (remove: 3, trim: 2)
            "abc/defg////m",       // (remove: 3, trim: 4)
            "abc/defg////m",       // (remove: 3, trim: 5)
            "abc/defg////",        // (remove: 3, trim: 6)

            "abc/defg//hijkl//m",  // (remove: 4, trim: none)
            "b/defg//hijkl//m",    // (remove: 4, trim: 0)
            "abc/ef//hijkl//m",    // (remove: 4, trim: 1)
            "abc/defg//hijkl//m",  // (remove: 4, trim: 2)
            "abc/defg//ijk//m",    // (remove: 4, trim: 3)
            "abc/defg//hijkl//m",  // (remove: 4, trim: 5)
            "abc/defg//hijkl//",   // (remove: 4, trim: 6)

            "abc/defg//hijkl//m",  // (remove: 5, trim: none)
            "b/defg//hijkl//m",    // (remove: 5, trim: 0)
            "abc/ef//hijkl//m",    // (remove: 5, trim: 1)
            "abc/defg//hijkl//m",  // (remove: 5, trim: 2)
            "abc/defg//ijk//m",    // (remove: 5, trim: 3)
            "abc/defg//hijkl//m",  // (remove: 5, trim: 4)
            "abc/defg//hijkl//",   // (remove: 5, trim: 6)

            "abc/defg//hijkl///",  // (remove: 6, trim: none)
            "b/defg//hijkl///",    // (remove: 6, trim: 0)
            "abc/ef//hijkl///",    // (remove: 6, trim: 1)
            "abc/defg//hijkl///",  // (remove: 6, trim: 2)
            "abc/defg//ijk///",    // (remove: 6, trim: 3)
            "abc/defg//hijkl///",  // (remove: 6, trim: 4)
            "abc/defg//hijkl///",  // (remove: 6, trim: 5)
          ]
        )

        // Remove none.
        var str = _testTrimSegments(source: source, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove some.
        str = _testTrimSegments(
          source: source,
          remove: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }),
          ranges: ranges
        )
        XCTAssertEqual(str, "defg/hijkl//")

        // Remove all.
        str = _testTrimSegments(source: source, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "")

        // Remove empties.
        str = _testTrimSegments(source: source, remove: [2, 4, 5], ranges: ranges)
        XCTAssertEqual(str, "abc/defg/hijkl/m")
      }

      // One segment. Operate in range.

      do {
        let source = "/abc/defghijklmnopq/rstu"
        let from = 7  //     ^      ^
        let to = 14
        let ranges = [7..<14]

        // Remove none.
        var str = _testTrimSegments(source: source, from: from, to: to, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove all.
        str = _testTrimSegments(source: source, from: from, to: to, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "/abc/demnopq/rstu")

        // Trim start.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (3, 0),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/deijklmnopq/rstu")

        // Trim end.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (0, 3),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/defghimnopq/rstu")

        // Trim both ends.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (2, 2),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/dehijmnopq/rstu")

        // Trim to empty segment.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (10, 10),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/demnopq/rstu")
      }

      // Many segments. Operate in range.

      do {
        let source = "/abc/defgh/ijkl/mnopq/rstu"
        let from = 7  //     ^           ^
        let to = 19
        let ranges = [7..<10, 11..<15, 16..<19]

        // swift-format-ignore
        _testMultiTrimSegments(
          source: source,
          from: from,
          to: to,
          ranges: ranges,
          trimAmount: (front: 1, back: 1),
          expected: [
            "/abc/deijkl/mnopq/rstu",  // (remove: 0, trim: none)
            "/abc/dejk/mnopq/rstu",    // (remove: 0, trim: 1)
            "/abc/deijkl/npq/rstu",    // (remove: 0, trim: 2)

            "/abc/defgh/mnopq/rstu",   // (remove: 1, trim: none)
            "/abc/deg/mnopq/rstu",     // (remove: 1, trim: 0)
            "/abc/defgh/npq/rstu",     // (remove: 1, trim: 2)

            "/abc/defgh/ijkl/pq/rstu", // (remove: 2, trim: none)
            "/abc/deg/ijkl/pq/rstu",   // (remove: 2, trim: 0)
            "/abc/defgh/jk/pq/rstu",   // (remove: 2, trim: 1)
          ]
        )

        // Remove none.
        var str = _testTrimSegments(source: source, from: from, to: to, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove some.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          remove: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/deijkl/pq/rstu")

        // Remove all.
        str = _testTrimSegments(source: source, from: from, to: to, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, "/abc/depq/rstu")

        // Trim some.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }), trimAmount: (1, 1),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/deg/ijkl/npq/rstu")

        // Trim all.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (1, 1),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/deg/jk/npq/rstu")

        // Trim to empty segments.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (5, 5),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/de//pq/rstu")
      }

      // Many segments. Operate in range. Offset is on a separator.

      do {
        let source = "/abc/defgh/ijkl/mnopq/rstu"
        let from = 4  //  ^                ^
        let to = 21
        var ranges: [Range<Int>] {
          if skipInitialSeparator {
            return [5..<10, 11..<15, 16..<21]
          } else {
            return [4..<4, 5..<10, 11..<15, 16..<21]
          }
        }

        if skipInitialSeparator {
          // swift-format-ignore
          _testMultiTrimSegments(
            source: source,
            from: from,
            to: to,
            ranges: ranges,
            trimAmount: (front: 1, back: 1),
            expected: [
              "/abc/ijkl/mnopq/rstu",   // (remove: 0, trim: none)
              "/abc/jk/mnopq/rstu",     // (remove: 0, trim: 1)
              "/abc/ijkl/nop/rstu",     // (remove: 0, trim: 2)

              "/abc/defgh/mnopq/rstu",  // (remove: 1, trim: none)
              "/abc/efg/mnopq/rstu",    // (remove: 1, trim: 0)
              "/abc/defgh/nop/rstu",    // (remove: 1, trim: 2)

              "/abc/defgh/ijkl//rstu",  // (remove: 2, trim: none)
              "/abc/efg/ijkl//rstu",    // (remove: 2, trim: 0)
              "/abc/defgh/jk//rstu",    // (remove: 2, trim: 1)
            ]
          )
        } else {
          // swift-format-ignore
          _testMultiTrimSegments(
            source: source,
            from: from,
            to: to,
            ranges: ranges,
            trimAmount: (front: 1, back: 1),
            expected: [
              "/abcdefgh/ijkl/mnopq/rstu",  // (remove: 0, trim: none)
              "/abcefg/ijkl/mnopq/rstu",    // (remove: 0, trim: 1)
              "/abcdefgh/jk/mnopq/rstu",    // (remove: 0, trim: 2)
              "/abcdefgh/ijkl/nop/rstu",    // (remove: 0, trim: 3)

              "/abc/ijkl/mnopq/rstu",       // (remove: 1, trim: none)
              "/abc/ijkl/mnopq/rstu",       // (remove: 1, trim: 0)
              "/abc/jk/mnopq/rstu",         // (remove: 1, trim: 2)
              "/abc/ijkl/nop/rstu",         // (remove: 1, trim: 3)

              "/abc/defgh/mnopq/rstu",      // (remove: 2, trim: none)
              "/abc/defgh/mnopq/rstu",      // (remove: 2, trim: 0)
              "/abc/efg/mnopq/rstu",        // (remove: 2, trim: 1)
              "/abc/defgh/nop/rstu",        // (remove: 2, trim: 3)

              "/abc/defgh/ijkl//rstu",      // (remove: 3, trim: none)
              "/abc/defgh/ijkl//rstu",      // (remove: 3, trim: 0)
              "/abc/efg/ijkl//rstu",        // (remove: 3, trim: 1)
              "/abc/defgh/jk//rstu",        // (remove: 3, trim: 2)
            ]
          )
        }

        // Remove none.
        var str = _testTrimSegments(source: source, from: from, to: to, ranges: ranges)
        XCTAssertEqual(str, source)

        // Remove some.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          remove: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }),
          ranges: ranges
        )
        XCTAssertEqual(str, skipInitialSeparator ? "/abc/ijkl//rstu" : "/abcdefgh/mnopq/rstu")

        // Remove all.
        str = _testTrimSegments(source: source, from: from, to: to, remove: Set(0..<ranges.count), ranges: ranges)
        XCTAssertEqual(str, skipInitialSeparator ? "/abc//rstu" : "/abc/rstu")

        // Trim some.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set((0..<ranges.count).lazy.filter { $0.isMultiple(of: 2) }), trimAmount: (1, 1),
          ranges: ranges
        )
        XCTAssertEqual(str, skipInitialSeparator ? "/abc/efg/ijkl/nop/rstu" : "/abc/defgh/jk/mnopq/rstu")

        // Trim all.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (1, 1),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc/efg/jk/nop/rstu")

        // Trim to empty segments.
        str = _testTrimSegments(
          source: source,
          from: from,
          to: to,
          trim: Set(0..<ranges.count), trimAmount: (5, 5),
          ranges: ranges
        )
        XCTAssertEqual(str, "/abc////rstu")
      }
    }
  }
}
