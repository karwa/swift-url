// MARK: - Sequence.

extension Sequence {
    public func split(maxLength: Int) -> [ArraySlice<Element>] {
        return Array(self)._eagerSplit(maxLength: maxLength)
    }
}

extension Collection {
    
    /// This is an implementation detail of `Sequence.split(maxLength:)`.
    /// It is also used as a secondary implementation to test the lazy version against.
    ///
    internal // @testable
    func _eagerSplit(maxLength: Int) -> [SubSequence] {
        precondition(maxLength > 0, "Cannot split a Collection in to rows of 0 or negative length")
        var results = [SubSequence]()
        results.reserveCapacity((underestimatedCount / maxLength) + 1)
        var sliceStart = startIndex
        var sliceEnd = startIndex
        while sliceEnd != endIndex {
            sliceStart = sliceEnd
            sliceEnd = index(sliceStart, offsetBy: maxLength, limitedBy: endIndex) ?? endIndex
            results.append(self[sliceStart..<sliceEnd])
        }
        return results
    }
}

// MARK: - Collection.

extension Collection {
    public func split(maxLength: Int) -> LazySplitCollection<Self> {
        return LazySplitCollection(base: self, rowLength: maxLength)
    }
}


/// Note: For `BidirectionalCollection`s which do not conform to `RandomAccessCollection`,
///     calculating the index before `endIndex` may be up to O(n). This only applies to these collections, when traversing the collection in reverse,
///     and only for the index immediately preceding `endIndex`. All other index calculations follow the complexity of the `Base` collection.
///
public struct LazySplitCollection<Base: Collection> {
    @usableFromInline let base: Base
    @usableFromInline let rowLength: Int
    public let startIndex: Index
    
    @inlinable
    init(base: Base, rowLength: Int) {
        precondition(rowLength > 0, "Cannot split a Collection in to rows of 0 or negative length")
        self.base = base
        self.rowLength = rowLength
        self.startIndex = Index(
            start: base.startIndex,
            end: base.index(base.startIndex, offsetBy: rowLength, limitedBy: base.endIndex) ?? base.endIndex
        )
    }
}
extension LazySplitCollection: Collection {
    public typealias Element = Base.SubSequence
    
    public struct Index: Equatable, Comparable {
        @usableFromInline var start: Base.Index
        @usableFromInline var end: Base.Index
        
        @inlinable
        init(start: Base.Index, end: Base.Index) {
            self.start = start; self.end = end
        }
        
        @inlinable
        public static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.start == rhs.start &&
                   lhs.end == rhs.end
        }
        
        @inlinable
        public static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.start < rhs.start
        }
    }
    
    @inlinable
    public var endIndex: Index {
        return Index(start: base.endIndex, end: base.endIndex)
    }
    
    @inlinable
    public var isEmpty: Bool {
        return base.isEmpty
    }
    
    @inlinable
    public var count: Int {
        let x = base.count.quotientAndRemainder(dividingBy: rowLength)
        return x.quotient + x.remainder.signum()
    }
    
    @inlinable
    public func distance(from start: Index, to end: Index) -> Int {
        let x = base.distance(from: start.start, to: end.start).quotientAndRemainder(dividingBy: rowLength)
        return x.quotient + x.remainder.signum()
    }
    
    @inlinable
    public subscript(position: Index) -> Base.SubSequence {
        // Interestingly, slicing from endIndex is allowed (and returns an empty slice),
        // so we need to do our own bounds-checking here.
        precondition(position.start != base.endIndex, "Cannot subscript endIndex")
        return base[position.start ..< position.end]
    }
        
    // Index traversal.
    
    @inlinable
    public func index(after i: Index) -> Index {
        return index(i, offsetBy: 1)
    }
    
    @inlinable
    public func formIndex(after i: inout Index) {
        _ = formIndex(&i, offsetBy: 1)
    }
    
    @inlinable
    public func index(_ i: Index, offsetBy distance: Int) -> Index {
        var i = i
        guard formIndex(&i, offsetBy: distance, limitedBy: distance > 0 ? endIndex : startIndex) else {
            fatalError("Index out of range")
        }
        return i
    }

    @inlinable
    public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        var i = i
        guard formIndex(&i, offsetBy: distance, limitedBy: limit) else { return nil }
        return i
    }
    
    /// Offsets the given index by the specified distance, or so that it equals the given limiting index.
    ///
    /// The value passed as `distance` must not offset `i` beyond the bounds of the collection, unless the index passed as `limit` prevents offsetting beyond those bounds.
    ///
    /// - complexity: O(1) if the collection conforms to `RandomAccessCollection`; otherwise, O(k), where k is the absolute value of `distance`.
    ///               O(n+k) if `i == endIndex`, `distance` is negative, and the collection does not conform to `RandomAccessCollection`.
    ///
    /// - parameters:
    ///   - i:        A valid index of the collection.
    ///   - distance: The distance to offset `i`. `distance` must not be negative unless the collection conforms to the `BidirectionalCollection` protocol.
    ///   - limit:    A valid index of the collection to use as a limit. If `distance > 0`, a limit that is less than `i` has no effect.
    ///               Likewise, if `distance < 0`, a limit that is greater than `i` has no effect.
    ///
    /// - returns:    `true` if `i` has been offset by exactly `distance` steps without going beyond `limit`; otherwise, `false`.
    ///               When the return value is `false`, the value of `i` is equal to `limit`.
    ///
    @inlinable
    public func formIndex(_ i: inout Index, offsetBy distance: Int, limitedBy limit: Index) -> Bool {
        guard distance != 0 else { return true }
        if distance > 0 {
            guard limit > i else { i = limit; return false }
            // Advance by (distance - 1) complete rows. If even that fails, `distance` is clearly too large.
            guard base.formIndex(&i.start, offsetBy: rowLength * (distance - 1), limitedBy: limit.start) else {
                i = limit
                return false
            }
            // Try to advance by another whole row.
            // If it fails, `limit` is less than `rowLength` away (i.e. we have an incomplete row).
            // Given that we have one step to go, the desired index must be `limit`. Success.
            guard base.formIndex(&i.start, offsetBy: rowLength, limitedBy: limit.start) else {
                i = limit
                return true
            }
            // `i.start` is in the correct position. Advance `end` by up to `rowLength`.
            i.end = i.start
            _ = base.formIndex(&i.end, offsetBy: rowLength, limitedBy: limit.start)
            return true
            
        } else {
            assert(distance < 0)
            guard limit <= i else { i = limit; return false }
            // Initial decrement.
            if i.start == base.endIndex {
                var remainder = base.count.quotientAndRemainder(dividingBy: rowLength).remainder
                remainder     = (remainder != 0) ? remainder : rowLength
                guard base.formIndex(&i.start, offsetBy: -remainder, limitedBy: limit.start) else {
                    i = limit
                    return false
                }
                assert(i.end == base.endIndex)
            } else {
                i.end = i.start
                guard base.formIndex(&i.start, offsetBy: -rowLength, limitedBy: limit.start) else {
                    i = limit
                    return false
                }
                assert(i.end != base.endIndex)
            }
            assert(base.distance(from: base.startIndex, to: i.start).isMultiple(of: rowLength),
                   "We should be aligned to a row start at this point")
            // Now that we are aligned to a row boundary, offset by multiples of rowLength.
            guard distance != -1 else { return true }
            i.end = i.start
            guard base.formIndex(&i.end, offsetBy: rowLength * (distance + 2), limitedBy: limit.start) else { i = limit; return false }
            i.start = i.end
            return base.formIndex(&i.start, offsetBy: -rowLength, limitedBy: limit.start)
        }
    }
}

extension LazySplitCollection: BidirectionalCollection where Base: BidirectionalCollection {
    
    @inlinable
    public func index(before i: Index) -> Index {
        return self.index(i, offsetBy: -1)
    }
    
    @inlinable
    public func formIndex(before i: inout Index) {
        _ = self.formIndex(&i, offsetBy: -1)
    }
}

extension LazySplitCollection: RandomAccessCollection where Base: RandomAccessCollection {}
