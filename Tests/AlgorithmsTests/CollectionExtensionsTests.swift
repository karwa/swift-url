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

import Checkit
import XCTest

@testable import Algorithms

class AlgorithmsTestCase: XCTestCase {}

// Collection+Split.

extension AlgorithmsTestCase {

  private func _eagerSplit<C: Collection>(_ c: C, maxLength: Int) -> [C.SubSequence] {
    precondition(maxLength > 0, "Cannot split a Collection in to rows of 0 or negative length")
    var results = [C.SubSequence]()
    results.reserveCapacity((c.underestimatedCount / maxLength) + 1)
    var sliceStart = c.startIndex
    var sliceEnd = c.startIndex
    while sliceEnd != c.endIndex {
      sliceStart = sliceEnd
      sliceEnd = c.index(sliceStart, offsetBy: maxLength, limitedBy: c.endIndex) ?? c.endIndex
      results.append(c[sliceStart..<sliceEnd])
    }
    return results
  }

  public func testCollectionSplitExact() {
    let values = (0..<100)
    let lazySplits: LazySplitCollection<Range<Int>> = values.split(maxLength: 10)

    // Check content.
    XCTAssertEqual(lazySplits.count, 10)
    XCTAssertEqual(lazySplits.first, 0..<10)
    XCTAssertEqual(lazySplits[lazySplits.index(lazySplits.startIndex, offsetBy: 4)], 40..<50)
    XCTAssertEqual(lazySplits[lazySplits.index(lazySplits.endIndex, offsetBy: -4)], 60..<70)
    XCTAssertEqual(lazySplits.last, 90..<100)
    for row in lazySplits {
      XCTAssertEqual(row.count, 10)
    }
    // Check that the collection is well-behaved.
    CollectionChecker.check(lazySplits)

    // Check against an eagerly-split version.
    let eagerSplits: [Range<Int>] = _eagerSplit(values, maxLength: 10)
    XCTAssertEqual(lazySplits.count, eagerSplits.count)

    var (eagerIt, lazyIt) = (eagerSplits.makeIterator(), lazySplits.makeIterator())
    while let eagerElem = eagerIt.next(), let lazyElem = lazyIt.next() {
      XCTAssertEqual(eagerElem, lazyElem)
    }
    XCTAssertNil(eagerIt.next())
    XCTAssertNil(lazyIt.next())
  }

  public func testCollectionSplitRemainder() {
    let text = "So this is a story all about how my life got flipped, turned upside-down"
    let lazySplits: LazySplitCollection<String> = text.split(maxLength: 10)

    // Check content.
    XCTAssertEqual(lazySplits.count, 8)
    XCTAssertEqual(lazySplits.dropFirst(7).first?.count, 2)
    XCTAssertEqual(lazySplits.first, text.prefix(10))
    XCTAssertEqual(lazySplits[lazySplits.index(lazySplits.startIndex, offsetBy: 3)], "ow my life")
    XCTAssertEqual(lazySplits[lazySplits.index(lazySplits.endIndex, offsetBy: -3)], "ed, turned")
    XCTAssertEqual(lazySplits.dropFirst(7).first, "wn")
    for row in lazySplits {
      XCTAssertLessThanOrEqual(row.count, 10)
    }

    // Check that the collection is well-behaved.
    CollectionChecker.check(lazySplits)

    // Check against an eagerly-split version.
    let eagerSplits: [Substring] = _eagerSplit(text, maxLength: 10)
    XCTAssertEqual(lazySplits.count, eagerSplits.count)

    var (eagerIt, lazyIt) = (eagerSplits.makeIterator(), lazySplits.makeIterator())
    while let eagerElem = eagerIt.next(), let lazyElem = lazyIt.next() {
      XCTAssertEqual(eagerElem, lazyElem)
    }
    XCTAssertNil(eagerIt.next())
    XCTAssertNil(lazyIt.next())
  }

  public func testCollectionSplitEmpty() {
    let values: [Int] = []
    XCTAssertTrue(values.isEmpty)

    let splitValues = values.split(maxLength: 10)
    XCTAssertTrue(splitValues.isEmpty)
    XCTAssertEqual(splitValues.startIndex, splitValues.endIndex)
    XCTAssertNil(splitValues.index(splitValues.startIndex, offsetBy: 1, limitedBy: splitValues.endIndex))
    XCTAssertNil(splitValues.index(splitValues.endIndex, offsetBy: -1, limitedBy: splitValues.startIndex))
    for _ in splitValues { XCTFail("Cannot iterate an empty collection") }
  }
}

// Collection+Trim.

extension AlgorithmsTestCase {

  func testCollectionTrim() {
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

// Collection+longestRange

extension AlgorithmsTestCase {

  func testCollectionLongestSubrange() {

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
