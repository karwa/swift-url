import XCTest

/// A collection of tests which test collections.
///
/// These tests are intended to exercise conformers to the `Collection` API,
/// asserting that they adhere to the various semantics documented by the protocol.
/// These tests are not exhaustive, and you should combine them with your own tests.
///
public struct CollectionSemanticsTester {
    
    public static func test<C: Collection>(
        _ collection: C, file: StaticString = #file, line: UInt = #line
    ) {
        let xct = XCTAssertionContext(file: file, line: line)
        runBaseCollectionTests(collection, xct)
    }
    
    public static func test<C: BidirectionalCollection>(
        _ collection: C, file: StaticString = #file, line: UInt = #line
    ) {
        let xct = XCTAssertionContext(file: file, line: line)
        runBaseCollectionTests(collection, xct)
        runBidirectionalCollectionTests(collection, xct)
    }
}

// Collection tests.

extension CollectionSemanticsTester {
    
    @inline(never)
    static func runBaseCollectionTests<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        _testCount(collection, xct)
        _testEndIndex(collection, xct)
    }
    
    @inline(never)
    static func _testCount<C: Collection>(_ collection: C, _ xct: XCTAssertionContext) {
        let underestimatedCount = collection.underestimatedCount
        xct.assertGreaterThanOrEqual(underestimatedCount, 0, "underestimatedCount must be positive or zero")
         
        let count = collection.count
        xct.assertGreaterThanOrEqual(count, 0, "count must be positive or zero")
        xct.assertLessThanOrEqual(underestimatedCount, count, "underestimatedCount must be <= count")
        
        let startIndex = collection.startIndex
        let endIndex = collection.endIndex
        xct.assertLessThanOrEqual(startIndex, endIndex, "startIndex must be <= endIndex")
        
        let calculatedCount = collection.distance(from: startIndex, to: endIndex)
        xct.assertEqual(count, calculatedCount, "count must be equal to `collection.distance(from: startIndex, to: endIndex)`")
        
        // Check that none of these properties mutated during the test.
        xct.assertEqual(underestimatedCount, collection.underestimatedCount, "underestimatedCount must not change unless mutated")
        xct.assertEqual(count, collection.count, "count must not change unless mutated")
        xct.assertEqual(startIndex, collection.startIndex, "startIndex must not change unless mutated")
        xct.assertEqual(endIndex, collection.endIndex, "endIndex must not change unless mutated")
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
}

// Bidirectional tests.

extension CollectionSemanticsTester {
    
    @inline(never)
    static func runBidirectionalCollectionTests<C: BidirectionalCollection>(_ collection: C, _ xct: XCTAssertionContext) {
        _testEndIndex_bidi(collection, xct)
    }
    
    @inline(never)
    static func _testEndIndex_bidi<C: BidirectionalCollection>(_ collection: C, _ xct: XCTAssertionContext) {
        var end = collection.endIndex
        if collection.isEmpty {
            xct.assertNil(collection.index(end, offsetBy: -1, limitedBy: collection.startIndex),
                          "decrementing endIndex by 1 should return nil for an empty Collection")
            xct.assertNil(collection.index(end, offsetBy: -2, limitedBy: collection.startIndex),
                          "decrementing endIndex by 2 should return nil for an empty Collection")
        } else {
            // Decrement by 1. Check that the index is valid and we cannot jump over endIndex from it.
            let _prevIndex = collection.index(end, offsetBy: -1, limitedBy: collection.startIndex)
            xct.assertNotNil(_prevIndex, "decrementing endIndex should return a valid index for a non-empty Collection")
            if let prevIndex = _prevIndex {
                _ = collection[prevIndex] // should not crash.
                xct.assertLessThan(prevIndex, end,
                                   "decrementing endIndex should return a lower index")
                xct.assertEqual(end, collection.index(prevIndex, offsetBy: 1, limitedBy: end),
                                "incrementing the last valid index should return endIndex")
                xct.assertNil(collection.index(prevIndex, offsetBy: 2, limitedBy: end),
                              "incrementing the last valid index by 2 should return nil")
                xct.assertNil(collection.index(prevIndex, offsetBy: 3, limitedBy: end),
                              "incrementing the last valid index by 3 should return nil")
                
                // Decrement again and check again that we cannot jump over endIndex.
                if prevIndex == collection.startIndex {
                    xct.assertEqual(collection.count, 1,
                                    "decremented endIndex by 1 and found startIndex, but count != 1")
                } else {
                    xct.assertGreaterThan(collection.count, 1,
                                          "too many indexes. count <= 1, but endIndex - 1 != startIndex")
                    let _prevPrevIndex = collection.index(prevIndex, offsetBy: -1, limitedBy: collection.startIndex)
                    xct.assertNotNil(_prevPrevIndex, "decrementing the last valid index should return a valid index for a Collection with count > 1")
                    if let prevPrevIndex = _prevPrevIndex {
                        _ = collection[prevPrevIndex] // should not crash.
                        xct.assertLessThan(prevPrevIndex, prevIndex,
                                           "decrementing the last valid index should return a lower index")
                        xct.assertLessThan(prevPrevIndex, end,
                                           "decrementing endIndex twice should return a lower index")
                        xct.assertEqual(end, collection.index(prevPrevIndex, offsetBy: 2, limitedBy: end),
                                        "decrementing the last valid index and incrementing by 2 should return endIndex")
                        xct.assertNil(collection.index(prevPrevIndex, offsetBy: 4, limitedBy: end),
                                      "decrementing the last valid index and incrementing by 3 should return nil")
                        xct.assertNil(collection.index(prevPrevIndex, offsetBy: 4, limitedBy: end),
                                      "decrementing the last valid index and incrementing by 4 should return nil")
                    }
                }
            }
        }
        
        
        if collection.isEmpty {
            xct.assertFalse(collection.formIndex(&end, offsetBy: -1, limitedBy: collection.startIndex),
                            "decrementing endIndex in-place should return false for an empty Collection")
            xct.assertEqual(end, collection.startIndex,
                            "decrementing endIndex in-place should leave the indexed unchanged for an empty Collection")
            xct.assertEqual(end, collection.endIndex,
                            "decrementing endIndex in-place should leave the indexed unchanged for an empty Collection")
        } else {
            xct.assertTrue(collection.formIndex(&end, offsetBy: -1, limitedBy: collection.startIndex))
            xct.assertLessThan(end, collection.endIndex)
        }
        
        //
    }
}
