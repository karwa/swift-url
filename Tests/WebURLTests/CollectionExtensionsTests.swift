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

class CollectionExtensionsTests: XCTestCase {}

// Collection.longestSubrange

extension CollectionExtensionsTests {

  func testLongestSubrange() {

    // Empty collection.
    let results_empty = ([] as [Int]).longestSubrange { _ in true }
    XCTAssertEqual(results_empty.subrange, 0..<0)
    XCTAssertEqual(results_empty.length, 0)

    let range_basic = [1, 2, 4, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 6, 7, 8]

    // No match (empty result).
    let range_empty_result = range_basic.longestSubrange { $0 == 10 }
    XCTAssertEqual(range_empty_result.subrange, 0..<0)
    XCTAssertEqual(range_empty_result.length, 0)
    // Single match.
    let range_single_end_result = range_basic.longestSubrange { $0 == 8 }
    XCTAssertEqual(range_single_end_result.subrange, 15..<16)
    XCTAssertEqual(range_single_end_result.length, 1)
    // Multiple matches, no length ties.
    let range_basic_result = range_basic.longestSubrange { $0 == 2 }
    XCTAssertEqual(range_basic_result.subrange, 9..<13)
    XCTAssertEqual(range_basic_result.length, 4)
    // Multiple matches, tied on length.
    let range_tie_result = range_basic.longestSubrange { $0 == 4 }
    XCTAssertEqual(range_tie_result.subrange, 2..<3)
    XCTAssertEqual(range_tie_result.length, 1)
  }
}

// BidirectionalCollection.trim

extension CollectionExtensionsTests {

  func testTrim() {
    // Empty collection.
    let results_empty = ([] as [Int]).trim { $0.isMultiple(of: 2) }
    XCTAssertEqual(results_empty, [])
    // No match (nothing trimmed).
    let results_nomatch = [1, 3, 5, 7, 9, 11, 13, 15].trim { $0.isMultiple(of: 2) }
    XCTAssertEqual(results_nomatch, [1, 3, 5, 7, 9, 11, 13, 15])
    // No tail match (only trim head).
    let results_notailmatch = [1, 3, 5, 7, 9, 11, 13, 15].trim { $0 < 10 }
    XCTAssertEqual(results_notailmatch, [11, 13, 15])
    // No head match (only trim tail).
    let results_noheadmatch = [1, 3, 5, 7, 9, 11, 13, 15].trim { $0 > 10 }
    XCTAssertEqual(results_noheadmatch, [1, 3, 5, 7, 9])
    // Everything matches (trim everything).
    let results_allmatch = [1, 3, 5, 7, 9, 11, 13, 15].trim { _ in true }
    XCTAssertEqual(results_allmatch, [])

    // Both ends match, one element does not match (trim everything except that element).
    let results_onematch = [2, 10, 12, 15, 20, 100].trim { $0.isMultiple(of: 2) }
    XCTAssertEqual(results_onematch, [15])

    // Both ends match, some string of >1 elements do not match (return that string).
    let results_0 = [2, 10, 11, 15, 20, 21, 100].trim(where: { $0.isMultiple(of: 2) })
    XCTAssertEqual(results_0, [11, 15, 20, 21])
  }
}

// BidirectionalCollection.suffix(while:)

extension CollectionExtensionsTests {

  func testSuffixWhile() {

    // Empty collection.
    do {
      let matches = ([] as [Int]).suffix(while: { _ in true })
      XCTAssert(matches.isEmpty)
      XCTAssertEqual(matches.startIndex, 0)
      XCTAssertEqual(matches.endIndex, 0)
    }

    let elements = [1, 2, 4, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 6, 7, 8]
    XCTAssertEqual(elements.endIndex, 16)

    // No match (empty result).
    do {
      let matches = elements.suffix(while: { $0 > 10 })
      XCTAssert(matches.isEmpty)
      XCTAssertEqualElements(matches, [])
      XCTAssertEqual(matches.startIndex, elements.endIndex)
      XCTAssertEqual(matches.endIndex, elements.endIndex)
    }
    // Single match.
    do {
      let matches = elements.suffix(while: { $0 == 8 })
      XCTAssertFalse(matches.isEmpty)
      XCTAssertEqualElements(matches, [8])
      XCTAssertEqual(matches.startIndex, 15)
      XCTAssertEqual(matches.endIndex, 16)
    }
    // Multiple items match.
    do {
      let matches = elements.suffix(while: { $0 > 2 })
      XCTAssertFalse(matches.isEmpty)
      XCTAssertEqualElements(matches, [6, 7, 8])
      XCTAssertEqual(matches.startIndex, 13)
      XCTAssertEqual(matches.endIndex, 16)
    }
    // Everything matches.
    do {
      let matches = elements.suffix(while: { $0 < 10 })
      XCTAssertFalse(matches.isEmpty)
      XCTAssertEqualElements(matches, elements)
      XCTAssertEqual(matches.startIndex, 0)
      XCTAssertEqual(matches.endIndex, 16)
    }
  }
}

// Fast collection algorithms.

extension CollectionExtensionsTests {

  func testFastFirstIndex() {
    do {
      let elems = [1, 2, 3, 4, 5, 6]
      XCTAssertEqual(elems.fastFirstIndex(where: { $0.isMultiple(of: 2) }), 1)
      XCTAssertEqual(elems.fastFirstIndex(where: { $0.isMultiple(of: 3) }), 2)
      XCTAssertEqual(elems.fastFirstIndex(where: { $0.isMultiple(of: 4) }), 3)
      XCTAssertEqual(elems.fastFirstIndex(where: { $0.isMultiple(of: 9) }), nil)
    }
    do {
      let elems = [1, 2, 3, 4, 4, 5, 4, 6]
      XCTAssertEqual(elems.fastFirstIndex(of: 4), 3)
      XCTAssertEqual(elems.fastFirstIndex(of: 10), nil)
    }
    do {
      let elems: Array<Int> = []
      XCTAssertNil(elems.fastFirstIndex(where: { _ in true }))
    }
  }

  func testFastLastIndex() {
    do {
      let elems = [1, 2, 3, 4, 5, 6]
      XCTAssertEqual(elems.fastLastIndex(where: { $0.isMultiple(of: 2) }), 5)
      XCTAssertEqual(elems.fastLastIndex(where: { $0.isMultiple(of: 3) }), 5)
      XCTAssertEqual(elems.fastLastIndex(where: { $0.isMultiple(of: 4) }), 3)
      XCTAssertEqual(elems.fastLastIndex(where: { $0.isMultiple(of: 9) }), nil)
    }
    do {
      let elems = [1, 2, 3, 4, 4, 5, 4, 6]
      XCTAssertEqual(elems.fastLastIndex(of: 4), 6)
      XCTAssertEqual(elems.fastLastIndex(of: 10), nil)
    }
    do {
      let elems: Array<Int> = []
      XCTAssertNil(elems.fastLastIndex(where: { _ in true }))
    }
  }

  func testFastPrefix() {
    // Match prefix.
    do {
      let elems = [2, 4, 6, 7, 8, 9]
      let prefix = elems.fastPrefix(where: { $0.isMultiple(of: 2) })
      XCTAssertEqual(prefix.startIndex, 0)
      XCTAssertEqual(prefix.endIndex, 3)
      XCTAssertEqualElements(prefix, [2, 4, 6])
    }
    // Match everything.
    do {
      let elems = [2, 4, 6, 8]
      let prefix = elems.fastPrefix(where: { $0.isMultiple(of: 2) })
      XCTAssertEqual(prefix.startIndex, 0)
      XCTAssertEqual(prefix.endIndex, 4)
      XCTAssertEqualElements(prefix, [2, 4, 6, 8])
    }
    // No prefix match.
    do {
      let elems = [2, 4, 6, 7, 8, 9]
      let prefix = elems.fastPrefix(where: { !$0.isMultiple(of: 2) })
      XCTAssertEqual(prefix.startIndex, 0)
      XCTAssertEqual(prefix.endIndex, 0)
      XCTAssertEqualElements(prefix, [])
    }
    // Empty collection.
    do {
      let elems: Array<Int> = []
      let prefix = elems.fastPrefix(where: { _ in true })
      XCTAssertEqual(prefix.startIndex, 0)
      XCTAssertEqual(prefix.endIndex, 0)
      XCTAssertEqualElements(prefix, [])
    }
  }

  func testFastDrop() {
    // Drop prefix.
    do {
      let elems = [2, 4, 6, 7, 8, 9]
      let suffix = elems.fastDrop(while: { $0.isMultiple(of: 2) })
      XCTAssertEqual(suffix.startIndex, 3)
      XCTAssertEqual(suffix.endIndex, 6)
      XCTAssertEqualElements(suffix, [7, 8, 9])
    }
    // Drop everything.
    do {
      let elems = [2, 4, 6, 8]
      let suffix = elems.fastDrop(while: { $0.isMultiple(of: 2) })
      XCTAssertEqual(suffix.startIndex, 4)
      XCTAssertEqual(suffix.endIndex, 4)
      XCTAssertEqualElements(suffix, [])
    }
    // Drop nothing.
    do {
      let elems = [2, 4, 6, 7, 8, 9]
      let prefix = elems.fastDrop(while: { !$0.isMultiple(of: 2) })
      XCTAssertEqual(prefix.startIndex, 0)
      XCTAssertEqual(prefix.endIndex, 6)
      XCTAssertEqualElements(prefix, [2, 4, 6, 7, 8, 9])
    }
    // Empty collection.
    do {
      let elems: Array<Int> = []
      let suffix = elems.fastDrop(while: { _ in true })
      XCTAssertEqual(suffix.startIndex, 0)
      XCTAssertEqual(suffix.endIndex, 0)
      XCTAssertEqualElements(suffix, [])
    }
  }

  func testFastPopFirst() {
    // Pop until all elements consumed.
    do {
      var elems = [2, 4, 6][...]
      XCTAssertEqual(elems.fastPopFirst(), 2)
      XCTAssertEqualElements(elems, [4, 6])
      XCTAssertEqual(elems.fastPopFirst(), 4)
      XCTAssertEqualElements(elems, [6])
      XCTAssertEqual(elems.fastPopFirst(), 6)
      XCTAssertTrue(elems.isEmpty)
      XCTAssertEqual(elems.fastPopFirst(), nil)
      XCTAssertEqual(elems.fastPopFirst(), nil)
      XCTAssertEqual(elems.fastPopFirst(), nil)
    }
    // Empty collection.
    do {
      var elems: Array<Int>.SubSequence = [][...]
      XCTAssertTrue(elems.isEmpty)
      XCTAssertEqual(elems.fastPopFirst(), nil)
    }
  }

  func testFastAllSatisfy() {
    // Do all satisfy.
    do {
      let elems = [2, 4, 6, 8, 10]
      XCTAssertTrue(elems.fastAllSatisfy { $0.isMultiple(of: 2) })
    }
    // Don't all satisfy.
    do {
      let elems = [2, 4, 6, 7, 8, 9]
      XCTAssertFalse(elems.fastAllSatisfy { $0.isMultiple(of: 2) })
    }
    // Empty collection.
    do {
      let elems: Array<Int> = []
      XCTAssertTrue(elems.fastAllSatisfy { _ in false })
      XCTAssertTrue(elems.fastAllSatisfy { _ in true })
    }
  }
}
