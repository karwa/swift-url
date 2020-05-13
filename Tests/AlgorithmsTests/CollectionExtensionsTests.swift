import XCTest
import TestUtilities
@testable import Algorithms

class AlgorithmsTestCase: XCTestCase {}

// Collection+Split.

extension AlgorithmsTestCase {
    
    public func testCollectionSplitExact() {
        let splits = (0..<100).split(maxLength: 10)
        
        // Check content.
        XCTAssertEqual(splits.count, 10)
        XCTAssertEqual(splits.first, 0..<10)
        XCTAssertEqual(splits[splits.index(splits.startIndex, offsetBy: 4)], 40..<50)
        XCTAssertEqual(splits[splits.index(splits.endIndex, offsetBy: -4)], 60..<70)
        XCTAssertEqual(splits.last, 90..<100)
        for row in splits {
            XCTAssertEqual(row.count, 10)
        }
        
        // Check semantics.
        CollectionSemanticsTester.test(splits)
    }
    
    public func testCollectionSplitExact_eager() {
        let splits = (0..<100)._eagerSplit(maxLength: 10)
        
        // Check content.
        XCTAssertEqual(splits.count, 10)
        XCTAssertEqual(splits.first, 0..<10)
        XCTAssertEqual(splits[splits.index(splits.startIndex, offsetBy: 4)], 40..<50)
        XCTAssertEqual(splits[splits.index(splits.endIndex, offsetBy: -4)], 60..<70)
        XCTAssertEqual(splits.last, 90..<100)
        for row in splits {
            XCTAssertEqual(row.count, 10)
        }
    }
    
    public func testCollectionSplitExact_equivalence() {
        let values = (0..<100)
        let lazy: LazySplitCollection<Range<Int>> = values.split(maxLength: 10)
        let eager: [Range<Int>] = values._eagerSplit(maxLength: 10)
        XCTAssertTrue(eager.elementsEqual(lazy))
        XCTAssertTrue(lazy.joined().elementsEqual(values))
        XCTAssertTrue(eager.joined().elementsEqual(values))
    }
        
    public func testCollectionSplitRemainder() {
        let text = "So this is a story all about how my life got flipped, turned upside-down"
        let lines: LazySplitCollection<String> = text.split(maxLength: 10)
        
        // Check content.
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines.last?.count, 2)
        XCTAssertEqual(lines.first, text.prefix(10))
        XCTAssertEqual(lines[lines.index(lines.startIndex, offsetBy: 3)], "ow my life")
        XCTAssertEqual(lines[lines.index(lines.endIndex, offsetBy: -3)], "ed, turned")
        XCTAssertEqual(lines.last, "wn")
        for row in lines {
            XCTAssertLessThanOrEqual(row.count, 10)
        }
        
        // Check semantics.
        CollectionSemanticsTester.test(lines)
    }
    
    public func testCollectionSplitRemainder_eager() {
        let text = "So this is a story all about how my life got flipped, turned upside-down"
        let lines: [Substring] = text._eagerSplit(maxLength: 10)
        
        // Check content.
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines.last?.count, 2)
        XCTAssertEqual(lines.first, text.prefix(10))
        XCTAssertEqual(lines[lines.index(lines.startIndex, offsetBy: 3)], "ow my life")
        XCTAssertEqual(lines[lines.index(lines.endIndex, offsetBy: -3)], "ed, turned")
        XCTAssertEqual(lines.last, "wn")
        for row in lines {
            XCTAssertLessThanOrEqual(row.count, 10)
        }
    }

    public func testCollectionSplitRemainder_equivalence() {
        let text = "So this is a story all about how my life got flipped, turned upside-down"
        let lazy: LazySplitCollection<String> = text.split(maxLength: 10)
        let eager: [Substring] = text._eagerSplit(maxLength: 10)
        XCTAssertTrue(eager.elementsEqual(lazy))
        XCTAssertEqual(lazy.joined(), text)
        XCTAssertEqual(eager.joined(), text)
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
        let results_empty = ([] as Array<Int>).trim { $0.isMultiple(of: 2) }
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