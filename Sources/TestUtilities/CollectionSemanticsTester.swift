import XCTest

/// A collection of tests which test collections.
///
/// These tests are intended to exercise conformers to the `Collection` API,
/// asserting that they adhere to the various semantics documented by the protocol.
/// These tests are not exhaustive, and you should combine them with your own tests.
///
public struct CollectionSemanticsTester {
    
    private static func getContext(file: StaticString, line: UInt) -> XCTAssertionContext {
        return XCTAssertionContext(file: file, line: line) { _, myLine, myMsg in "\(myLine): \(myMsg)" }
    }
    
    public static func test<C: Collection>(
        _ collection: C, file: StaticString = #file, line: UInt = #line
    ) {
        let xct = getContext(file: file, line: line)
        runBaseCollectionTests(collection, xct)
    }
    
    public static func test<C: Collection>(
        _ collection: C, file: StaticString = #file, line: UInt = #line
    ) where C.Element: Equatable {
        let xct = getContext(file: file, line: line)
        runBaseCollectionTests(collection, xct)
        runBaseCollectionTests_eq(collection, xct)
    }
    
    public static func test<C: BidirectionalCollection>(
        _ collection: C, file: StaticString = #file, line: UInt = #line
    ) {
        let xct = getContext(file: file, line: line)
        runBaseCollectionTests(collection, xct)
        runBidirectionalCollectionTests(collection, xct)
    }
    
    public static func test<C: BidirectionalCollection>(
        _ collection: C, file: StaticString = #file, line: UInt = #line
    ) where C.Element: Equatable {
        let xct = getContext(file: file, line: line)
        runBaseCollectionTests(collection, xct)
        runBidirectionalCollectionTests(collection, xct)
        
        runBaseCollectionTests_eq(collection, xct)
    }
}

// Collection tests.

extension CollectionSemanticsTester {
    
    @inline(never)
    static func runBaseCollectionTests<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        _testCount(collection, xct)
        _testStartIndex(collection, xct)
        _testEndIndex(collection, xct)
        _testMultipassIndexes(collection, xct)
    }
    
    @inline(never)
    static func _testCount<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        let underestimatedCount = collection.underestimatedCount
        xct.assertGreaterThanOrEqual(underestimatedCount, 0, "underestimatedCount should be positive or zero")
         
        let count = collection.count
        xct.assertGreaterThanOrEqual(count, 0, "count should be positive or zero")
        xct.assertLessThanOrEqual(underestimatedCount, count, "underestimatedCount should be <= count")
        
        let startIndex = collection.startIndex
        let endIndex = collection.endIndex
        xct.assertLessThanOrEqual(startIndex, endIndex, "startIndex should be <= endIndex")
        
        let calculatedCount = collection.distance(from: startIndex, to: endIndex)
        xct.assertEqual(count, calculatedCount, "count should be equal to the distance between start and end indexes")
        
        let iteratedCount = collection.reduce(into: 0) { counter, _ in counter += 1 }
        xct.assertEqual(count, iteratedCount, "iterating the collection should return `count` elements")
        
        // Check that none of these properties mutated during the test.
        xct.assertEqual(underestimatedCount, collection.underestimatedCount, "underestimatedCount should not change unless mutated")
        xct.assertEqual(count, collection.count, "count should not change unless mutated")
        xct.assertEqual(startIndex, collection.startIndex, "startIndex should not change unless mutated")
        xct.assertEqual(endIndex, collection.endIndex, "endIndex should not change unless mutated")
    }
    
    
    @inline(never)
    static func _testStartIndex<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        var start = collection.startIndex
        if collection.isEmpty {
            xct.assertEqual(start, collection.endIndex,
                            "startIndex and endIndex should be equal")
            xct.assertNil(collection.index(start, offsetBy: 1, limitedBy: collection.endIndex),
                          "incrementing startIndex should return nil")
            xct.assertFalse(collection.formIndex(&start, offsetBy: 1, limitedBy: collection.endIndex),
                            "incrementing startIndex in-place should return false")
            xct.assertEqual(start, collection.endIndex,
                            "incrementing startIndex in-place should leave the index unchanged")
        } else {
            xct.assertNotEqual(start, collection.endIndex,
                               "startIndex and endIndex should not be equal")
            xct.assertEqual(collection.index(start, offsetBy: collection.count, limitedBy: collection.endIndex),
                            collection.endIndex,
                            "incrementing startIndex by count should return endIndex")
            xct.assertNil(collection.index(start, offsetBy: collection.count + 10, limitedBy: collection.endIndex),
                          "incrementing startIndex by more than count should return nil")
            let next = collection.index(after: start)
            xct.assertGreaterThan(next, start,
                                  "incrementing startIndex should return a greater index")
            if collection.count == 1 {
                xct.assertEqual(next, collection.endIndex,
                                "incrementing startIndex should return endIndex")
            } else {
                _ = collection[next] // should not crash.
                xct.assertLessThan(next, collection.endIndex,
                    "incrementing startIndex should return an index lower than endIndex")
            }
        }
    }
    
    @inline(never)
    static func _testEndIndex<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        var end = collection.endIndex
        xct.assertNil(collection.index(end, offsetBy: 1, limitedBy: collection.endIndex),
                      "incrementing endIndex should return nil")
        xct.assertFalse(collection.formIndex(&end, offsetBy: 1, limitedBy: collection.endIndex),
                        "incrementing endIndex in-place should return false")
        xct.assertEqual(end, collection.endIndex,
                        "incrementing endIndex in-place should leave the index unchanged")
    }
    
    @inline(never)
    static func _testMultipassIndexes<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        var indexes = [C.Index]()
        indexes.reserveCapacity(collection.underestimatedCount)
        var index = collection.startIndex
        while index != collection.endIndex {
            indexes.append(index)
            collection.formIndex(after: &index)
        }
        xct.assertEqual(indexes.count, collection.count,
                        "The number of indexes should equal the number of items")
        xct.assertEqual(indexes.sorted(), indexes,
                        "indexes were returned out of order")
        
        var position = 0
        index = collection.startIndex
        while index != collection.endIndex {
            xct.assertEqual(index, indexes[position],
                            "multiple passes returned different indexes")
            collection.formIndex(after: &index)
            position += 1
        }
    }
}

// Collection tests where Element: Equatable

extension CollectionSemanticsTester {
    
    @inline(never)
    static func runBaseCollectionTests_eq<C: Collection>(_ collection: C, _ xct: XCTAssertionContext)
        where C.Element: Equatable {
		_testMultipassElements(collection, xct)
    }
    
    @inline(never)
    static func _testMultipassElements<C: Collection>(_ collection: C, _ xct: XCTAssertionContext)
        where C.Element: Equatable {
        var elements = [C.Element]()
        elements.reserveCapacity(collection.underestimatedCount)
        var index = collection.startIndex
        while index != collection.endIndex {
            elements.append(collection[index])
            collection.formIndex(after: &index)
        }
        xct.assertEqual(elements.count, collection.count,
                        "The number of elements seen through iteration should equal the number of items")
        
        var position = 0
        index = collection.startIndex
        while index != collection.endIndex {
            xct.assertEqual(collection[index], elements[position],
                            "multiple passes returned different elements")
            collection.formIndex(after: &index)
            position += 1
        }
    }
}

// Bidirectional tests.

extension CollectionSemanticsTester {
    
    @inline(never)
    static func runBidirectionalCollectionTests<C: BidirectionalCollection>(_ collection: C, _ xct: XCTAssertionContext) {
        _testEndIndex_bidi(collection, xct)
        // TODO: Add startIndex bidi tests.
        // TODO: Add forward&reverse index walk.
    }
    
    @inline(never)
    static func _testEndIndex_bidi<C: BidirectionalCollection>(_ collection: C, _ xct: XCTAssertionContext) {
        var end = collection.endIndex
        if collection.isEmpty {
            xct.assertNil(collection.index(end, offsetBy: -1, limitedBy: collection.startIndex),
                          "decrementing endIndex by 1 should return nil")
            xct.assertNil(collection.index(end, offsetBy: -2, limitedBy: collection.startIndex),
                          "decrementing endIndex by 2 should return nil")
        } else {
            // Decrement by 1. Check that the index is valid and we cannot jump over endIndex from it.
            let _prevIndex = collection.index(end, offsetBy: -1, limitedBy: collection.startIndex)
            xct.assertNotNil(_prevIndex, "decrementing endIndex should return a valid index")
            if let prevIndex = _prevIndex {
                _ = collection[prevIndex] // should not crash.
                xct.assertLessThan(prevIndex, end,
                                   "decrementing endIndex should return a lower index")
                xct.assertEqual(end, collection.index(prevIndex, offsetBy: 1, limitedBy: end),
                                "incrementing the last valid index should return endIndex")
                xct.assertNil(collection.index(prevIndex, offsetBy: 10, limitedBy: end),
                              "incrementing the last valid index past endIndex should return nil")
                
                // Decrement again and check again that we cannot jump over endIndex.
                if prevIndex == collection.startIndex {
                    xct.assertEqual(collection.count, 1,
                                    "the index before endIndex is startIndex, so `count` should be 1")
                } else {
                    xct.assertGreaterThan(collection.count, 1,
                                          "there is an index between startIndex and endIndex, so `count` should be greater than 1")
                    let _prevPrevIndex = collection.index(prevIndex, offsetBy: -1, limitedBy: collection.startIndex)
                    xct.assertNotNil(_prevPrevIndex, "decrementing the last valid index should return a valid index")
                    if let prevPrevIndex = _prevPrevIndex {
                        _ = collection[prevPrevIndex] // should not crash.
                        xct.assertLessThan(prevPrevIndex, prevIndex,
                                           "decrementing the last valid index should return a lower index")
                        xct.assertLessThan(prevPrevIndex, end,
                                           "decrementing endIndex twice should return a lower index")
                        xct.assertEqual(end, collection.index(prevPrevIndex, offsetBy: 2, limitedBy: end),
                                        "decrementing the last valid index and incrementing by 2 should return endIndex")
                        xct.assertNil(collection.index(prevPrevIndex, offsetBy: 10, limitedBy: end),
                                      "decrementing the last valid index and incrementing past endIndex should return nil")
                    }
                }
            }
        }
        // in-place index formation.
        if collection.isEmpty {
            xct.assertFalse(collection.formIndex(&end, offsetBy: -1, limitedBy: collection.startIndex),
                            "decrementing endIndex in-place should return false")
            xct.assertEqual(end, collection.endIndex,
                            "decrementing endIndex in-place should leave the indexed unchanged")
        } else {
            xct.assertTrue(collection.formIndex(&end, offsetBy: -1, limitedBy: collection.startIndex),
                           "decrementing endIndex in-place should return truen")
            xct.assertLessThan(end, collection.endIndex,
                               "decrementing endIndex in-place should result in a lower index")
            xct.assertFalse(collection.formIndex(&end, offsetBy: 10, limitedBy: collection.endIndex),
                            "decrementing endIndex and incrementing it by >1 (in-place) should return false")
            xct.assertEqual(end, collection.endIndex,
                            "decrementing endIndex and incrementing it by >1 (in-place) should leave the index equal to endIndex")
        }
    }
}
