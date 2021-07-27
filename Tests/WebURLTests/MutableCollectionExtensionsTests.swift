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

    // Empty collection.
    do {
      var empty: [Int] = []
      let end = empty.trimSegments(from: 0, separatedBy: { _ in true }) { s, isFirst, isLast in
        XCTAssertTrue(isFirst)
        XCTAssertTrue(isLast)
        XCTAssertEqual(s.startIndex, 0)
        XCTAssertEqual(s.endIndex, 0)
        return s
      }
      XCTAssertEqual(end, 0)
      XCTAssertEqualElements(empty, [])
    }

    func withUTF8Array<T>(_ string: String, _ modify: (inout [UInt8]) -> T) -> (String, T) {
      var utf8 = Array(string.utf8)
      let result = modify(&utf8)
      return (String(decoding: utf8, as: UTF8.self), result)
    }

    // No segments, no trimming.
    do {
      let (string, endOffset) = withUTF8Array("abcdefg") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { _ in false }) { s, isFirst, isLast in
          XCTAssertTrue(isFirst)
          XCTAssertTrue(isLast)
          XCTAssertEqual(s.startIndex, 0)
          XCTAssertEqual(s.endIndex, 7)
          XCTAssertEqualElements(s, "abcdefg".utf8)
          return s
        }
      }
      XCTAssertEqual(endOffset, 7)
      XCTAssertEqual(string, "abcdefg")
    }

    // No segments, trim end.
    do {
      let (string, endOffset) = withUTF8Array("abcdefg") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { _ in false }) { s, isFirst, isLast in
          XCTAssertTrue(isFirst)
          XCTAssertTrue(isLast)
          XCTAssertEqual(s.startIndex, 0)
          XCTAssertEqual(s.endIndex, 7)
          XCTAssertEqualElements(s, "abcdefg".utf8)
          return s.prefix(4)
        }
      }
      XCTAssertEqual(endOffset, 4)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "abcd".utf8)
      XCTAssertEqual(string, "abcdefg")
    }

    // No segments, trim start.
    do {
      let (string, endOffset) = withUTF8Array("abcdefg") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { _ in false }) { s, isFirst, isLast in
          XCTAssertTrue(isFirst)
          XCTAssertTrue(isLast)
          XCTAssertEqual(s.startIndex, 0)
          XCTAssertEqual(s.endIndex, 7)
          XCTAssertEqualElements(s, "abcdefg".utf8)
          return s.suffix(4)
        }
      }
      XCTAssertEqual(endOffset, 4)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "defg".utf8)
      XCTAssertEqual(string, "defgefg")
    }

    // No segments, trim both ends.
    do {
      let (string, endOffset) = withUTF8Array("abcdefghijklmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { _ in false }) { s, isFirst, isLast in
          XCTAssertTrue(isFirst)
          XCTAssertTrue(isLast)
          XCTAssertEqual(s.startIndex, 0)
          XCTAssertEqual(s.endIndex, 16)
          XCTAssertEqualElements(s, "abcdefghijklmnop".utf8)
          return s.dropFirst(4).prefix(8)
        }
      }
      XCTAssertEqual(endOffset, 8)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "efghijkl".utf8)
      XCTAssertEqual(string, "efghijklijklmnop")
    }

    // 2 segments, no trim.
    do {
      let (string, endOffset) = withUTF8Array("abcdefg/hijklmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 0)
            XCTAssertEqual(s.endIndex, 7)
            XCTAssertEqualElements(s, "abcdefg".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 8)
            XCTAssertEqual(s.endIndex, 17)
            XCTAssertEqualElements(s, "hijklmnop".utf8)
          }
          XCTAssertTrue(isFirst || isLast)
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          return s
        }
      }
      XCTAssertEqual(endOffset, 17)
      XCTAssertEqual(string, "abcdefg/hijklmnop")
    }

    // 2 segments, trim first from both ends.
    do {
      let (string, endOffset) = withUTF8Array("abcdefg/hijklmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 0)
            XCTAssertEqual(s.endIndex, 7)
            XCTAssertEqualElements(s, "abcdefg".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 8)
            XCTAssertEqual(s.endIndex, 17)
            XCTAssertEqualElements(s, "hijklmnop".utf8)
          }
          XCTAssertTrue(isFirst || isLast)
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))

          if isFirst {
            return s.dropFirst().dropLast(3)
          }
          return s
        }
      }
      XCTAssertEqual(endOffset, 13)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "bcd/hijklmnop".utf8)
      XCTAssertEqual(string, "bcd/hijklmnopmnop")
    }

    // 2 segments, trim last from both ends.
    do {
      let (string, endOffset) = withUTF8Array("abcdefg/hijklmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 0)
            XCTAssertEqual(s.endIndex, 7)
            XCTAssertEqualElements(s, "abcdefg".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 8)
            XCTAssertEqual(s.endIndex, 17)
            XCTAssertEqualElements(s, "hijklmnop".utf8)
          }
          XCTAssertTrue(isFirst || isLast)
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))

          if isLast {
            return s.dropFirst().dropLast(3)
          }
          return s
        }
      }
      XCTAssertEqual(endOffset, 13)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "abcdefg/ijklm".utf8)
      XCTAssertEqual(string, "abcdefg/ijklmmnop")
    }

    // 2 segments, collection starts with separator, first component is trimmed. Leading separator maintained.
    do {
      let (string, endOffset) = withUTF8Array("/abcdefg/hijklmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 8)
            XCTAssertEqualElements(s, "abcdefg".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 9)
            XCTAssertEqual(s.endIndex, 18)
            XCTAssertEqualElements(s, "hijklmnop".utf8)
          }
          XCTAssertTrue(isFirst || isLast)
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))

          if isFirst {
            return s.dropFirst().dropLast(3)
          }
          return s
        }
      }
      XCTAssertEqual(endOffset, 14)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/bcd/hijklmnop".utf8)
      XCTAssertEqual(string, "/bcd/hijklmnopmnop")
    }

    // 2 segments, collection starts with separator, last component is trimmed. Leading separator maintained.
    do {
      let (string, endOffset) = withUTF8Array("/abcdefg/hijklmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 8)
            XCTAssertEqualElements(s, "abcdefg".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 9)
            XCTAssertEqual(s.endIndex, 18)
            XCTAssertEqualElements(s, "hijklmnop".utf8)
          }
          XCTAssertTrue(isFirst || isLast)
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))

          if isLast {
            return s.dropFirst().dropLast(3)
          }
          return s
        }
      }
      XCTAssertEqual(endOffset, 14)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abcdefg/ijklm".utf8)
      XCTAssertEqual(string, "/abcdefg/ijklmmnop")
    }

    // Many segments, no trim.
    do {
      var expectedSegments = ["abc", "defg", "hijk", "lmnop"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 4)
            XCTAssertEqualElements(s, "abc".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 15)
            XCTAssertEqual(s.endIndex, 20)
            XCTAssertEqualElements(s, "lmnop".utf8)
          }
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          return s
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 20)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/hijk/lmnop".utf8)
      XCTAssertEqual(string, "/abc/defg/hijk/lmnop")
    }

    // Many segments, trim first.
    do {
      var expectedSegments = ["abc", "defg", "hijk", "lmnop"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 4)
            XCTAssertEqualElements(s, "abc".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 15)
            XCTAssertEqual(s.endIndex, 20)
            XCTAssertEqualElements(s, "lmnop".utf8)
          }
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if isFirst {
            return s.dropFirst(2)
          }
          return s
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 18)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/c/defg/hijk/lmnop".utf8)
      XCTAssertEqual(string, "/c/defg/hijk/lmnopop")
    }

    // Many segments, trim last.
    do {
      var expectedSegments = ["abc", "defg", "hijk", "lmnop"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 4)
            XCTAssertEqualElements(s, "abc".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 15)
            XCTAssertEqual(s.endIndex, 20)
            XCTAssertEqualElements(s, "lmnop".utf8)
          }
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if isLast {
            return s.dropFirst(2)
          }
          return s
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 18)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/hijk/nop".utf8)
      XCTAssertEqual(string, "/abc/defg/hijk/nopop")
    }

    // Many segments, trim one in the middle.
    do {
      var expectedSegments = ["abc", "defg", "hijk", "lmnop"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmnop") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 4)
            XCTAssertEqualElements(s, "abc".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 15)
            XCTAssertEqual(s.endIndex, 20)
            XCTAssertEqualElements(s, "lmnop".utf8)
          }
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if s.first == ASCII.d.codePoint {
            return s.dropFirst().dropLast(2)
          }
          return s
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 17)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/e/hijk/lmnop".utf8)
      XCTAssertEqual(string, "/abc/e/hijk/lmnopnop")
    }

    // Many segments, trim multiple.
    do {
      var expectedSegments = ["abc", "defg", "hijk", "lmno", "pqrs"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 4)
            XCTAssertEqualElements(s, "abc".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 20)
            XCTAssertEqual(s.endIndex, 24)
            XCTAssertEqualElements(s, "pqrs".utf8)
          }
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if s.first == ASCII.d.codePoint || s.first == ASCII.h.codePoint {
            return s.dropFirst().dropLast(2)
          }
          return s
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 18)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/e/i/lmno/pqrs".utf8)
      XCTAssertEqual(string, "/abc/e/i/lmno/pqrso/pqrs")
    }

    // Trailing separator (many segments, trim multiple).
    do {
      var expectedSegments = ["abc", "defg", "hijk", "lmno", "pqrs", ""]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs/") { utf8 in
        utf8.trimSegments(from: 0, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 1)
            XCTAssertEqual(s.endIndex, 4)
            XCTAssertEqualElements(s, "abc".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 25)
            XCTAssertEqual(s.endIndex, 25)
            XCTAssertEqualElements(s, [])
          }
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if s.first == ASCII.d.codePoint || s.first == ASCII.h.codePoint {
            return s.dropFirst().dropLast(2)
          }
          return s
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 19)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/e/i/lmno/pqrs/".utf8)
      XCTAssertEqual(string, "/abc/e/i/lmno/pqrs//pqrs/")
    }

    // No segment breaks after offset.
    do {
      let (string, endOffset) = withUTF8Array("/abc/defg/hijklmnopqrs") { utf8 in
        utf8.trimSegments(from: 10, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in

          XCTAssertEqual(s.startIndex, 10)
          XCTAssertEqual(s.endIndex, 22)
          XCTAssertEqualElements(s, "hijklmnopqrs".utf8)

          XCTAssertTrue(isFirst)
          XCTAssertTrue(isLast)
          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))

          return s.dropFirst(4)
        }
      }
      XCTAssertEqual(endOffset, 18)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/lmnopqrs".utf8)
      XCTAssertEqual(string, "/abc/defg/lmnopqrspqrs")
    }

    // Many segment breaks after offset
    do {
      var expectedSegments = ["hijk", "lmno", "pqrs", ""]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs/") { utf8 in
        utf8.trimSegments(from: 10, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in

          if isFirst {
            XCTAssertEqual(s.startIndex, 10)
            XCTAssertEqual(s.endIndex, 14)
            XCTAssertEqualElements(s, "hijk".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 25)
            XCTAssertEqual(s.endIndex, 25)
            XCTAssertEqualElements(s, [])
          }

          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          return s.dropLast()
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 22)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/hij/lmn/pqr/".utf8)
      XCTAssertEqual(string, "/abc/defg/hij/lmn/pqr/rs/")
    }

    // Offset is in the middle of a segment
    do {
      var expectedSegments = ["jk", "lmno", "pqrs", ""]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs/") { utf8 in
        utf8.trimSegments(from: 12, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in

          if isFirst {
            XCTAssertEqual(s.startIndex, 12)
            XCTAssertEqual(s.endIndex, 14)
            XCTAssertEqualElements(s, "jk".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 25)
            XCTAssertEqual(s.endIndex, 25)
            XCTAssertEqualElements(s, [])
          }

          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          return s.dropFirst()
        }
      }
      XCTAssert(expectedSegments.isEmpty)
      XCTAssertEqual(endOffset, 22)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/hik/mno/qrs/".utf8)
      XCTAssertEqual(string, "/abc/defg/hik/mno/qrs/rs/")
    }

    // Offset is on a separator
    do {
      var expectedSegments = ["hijk", "lmno", "pqrs", ""]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs/") { utf8 -> Int in
        XCTAssertEqual(utf8[9], ASCII.forwardSlash.codePoint)
        return utf8.trimSegments(from: 9, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 10)
            XCTAssertEqual(s.endIndex, 14)
            XCTAssertEqualElements(s, "hijk".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 25)
            XCTAssertEqual(s.endIndex, 25)
            XCTAssertEqualElements(s, [])
          }

          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          return s.dropLast(2)
        }
      }
      XCTAssertEqual(endOffset, 19)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/hi/lm/pq/".utf8)
      XCTAssertEqual(string, "/abc/defg/hi/lm/pq//pqrs/")
    }

    // Trim first segment to empty, from offset.
    do {
      var expectedSegments = ["hijk", "lmno", "pqrs"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs") { utf8 -> Int in
        XCTAssertEqual(utf8[9], ASCII.forwardSlash.codePoint)
        return utf8.trimSegments(from: 9, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 10)
            XCTAssertEqual(s.endIndex, 14)
            XCTAssertEqualElements(s, "hijk".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 20)
            XCTAssertEqual(s.endIndex, 24)
            XCTAssertEqualElements(s, "pqrs".utf8)
          }

          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if isFirst {
            return s.prefix(0)
          }
          return s
        }
      }
      XCTAssertEqual(endOffset, 20)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg//lmno/pqrs".utf8)
      XCTAssertEqual(string, "/abc/defg//lmno/pqrspqrs")
    }

    // Trim last segment to empty, from offset.
    do {
      var expectedSegments = ["hijk", "lmno", "pqrs"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs") { utf8 -> Int in
        XCTAssertEqual(utf8[9], ASCII.forwardSlash.codePoint)
        return utf8.trimSegments(from: 9, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 10)
            XCTAssertEqual(s.endIndex, 14)
            XCTAssertEqualElements(s, "hijk".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 20)
            XCTAssertEqual(s.endIndex, 24)
            XCTAssertEqualElements(s, "pqrs".utf8)
          }

          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          if isLast {
            return s.prefix(0)
          }
          return s
        }
      }
      XCTAssertEqual(endOffset, 20)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg/hijk/lmno/".utf8)
      XCTAssertEqual(string, "/abc/defg/hijk/lmno/pqrs")
    }

    // Trim all segments to empty, from offset.
    do {
      var expectedSegments = ["hijk", "lmno", "pqrs"]
      let (string, endOffset) = withUTF8Array("/abc/defg/hijk/lmno/pqrs") { utf8 -> Int in
        XCTAssertEqual(utf8[9], ASCII.forwardSlash.codePoint)
        return utf8.trimSegments(from: 9, separatedBy: { $0 == ASCII.forwardSlash.codePoint }) { s, isFirst, isLast in
          if isFirst {
            XCTAssertEqual(s.startIndex, 10)
            XCTAssertEqual(s.endIndex, 14)
            XCTAssertEqualElements(s, "hijk".utf8)
          }
          if isLast {
            XCTAssertEqual(s.startIndex, 20)
            XCTAssertEqual(s.endIndex, 24)
            XCTAssertEqualElements(s, "pqrs".utf8)
          }

          XCTAssertFalse(s.contains(ASCII.forwardSlash.codePoint))
          XCTAssertEqualElements(s, expectedSegments.removeFirst().utf8)
          return s.prefix(0)
        }
      }
      XCTAssertEqual(endOffset, 12)
      XCTAssertEqualElements(string.utf8.prefix(endOffset), "/abc/defg///".utf8)
      XCTAssertEqual(string, "/abc/defg///jk/lmno/pqrs")
    }
  }
}
