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

public struct LazySplitCollection<Base: Collection> {
    let base: Base
    let rowLength: Int
    let _startIndex: Index
    
    init(base: Base, rowLength: Int) {
        precondition(rowLength > 0, "Cannot split a Collection in to rows of 0 or negative length")
        self.base = base
        self.rowLength = rowLength
        self._startIndex = Index(
            start: base.startIndex,
            end: base.index(base.startIndex, offsetBy: rowLength, limitedBy: base.endIndex) ?? base.endIndex
        )
    }
}
extension LazySplitCollection: Collection {
    public typealias Element = Base.SubSequence
    
    public struct Index: Equatable, Comparable {
        fileprivate var start: Base.Index
        fileprivate var end: Base.Index
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            // indexes do not overlap, so we only need to check the start location.
            return lhs.start < rhs.start
        }
    }
    
    public var startIndex: Index {
        return _startIndex
    }
    public var endIndex: Index {
        return Index(start: base.endIndex, end: base.endIndex)
    }
    public subscript(position: Index) -> Base.SubSequence {
        return base[position.start ..< position.end]
    }
    
    // Bi-directional traversal.
    public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        var i = i
        guard formIndex(&i, offsetBy: distance, limitedBy: limit) else { return nil }
        return i
    }
    public func formIndex(_ i: inout Index, offsetBy distance: Int, limitedBy limit: Index) -> Bool {
        // When decrementing from endIndex, the first step snaps to the start of the last row.
        // Note: splitting this in to a local function generates much better code after inlining.
        func _decrementFromEndIndex() -> Bool {
            var remainder = base.count.quotientAndRemainder(dividingBy: rowLength).remainder
            if remainder == 0 { remainder = rowLength }
            guard base.formIndex(&i.start, offsetBy: -remainder, limitedBy: base.startIndex) else { return false }
            return self.formIndex(&i, offsetBy: distance + 1, limitedBy: limit)
        }
        
        if distance > 0 {
            guard i.start != base.endIndex else { return false }
            i.start = i.end
            return base.formIndex(&i.end, offsetBy: rowLength * distance, limitedBy: base.endIndex)
        } else if distance < 0 {
            guard i.start != base.endIndex else { return _decrementFromEndIndex() }
            i.end = i.start
            return base.formIndex(&i.start, offsetBy: rowLength * distance, limitedBy: base.startIndex)
        } else {
            return true
        }
    }
    
    // Forward traversal.
    public func index(after i: Index) -> Index {
        return self.index(i, offsetBy: 1, limitedBy: endIndex) ?? endIndex
    }
    public func formIndex(after i: inout Index) {
        _ = self.formIndex(&i, offsetBy: 1, limitedBy: endIndex)
    }
}

extension LazySplitCollection: BidirectionalCollection where Base: BidirectionalCollection {
    
    // Backwards traversal.
    public func index(before i: Index) -> Index {
        return self.index(i, offsetBy: -1, limitedBy: startIndex) ?? startIndex
    }
    public func formIndex(before i: inout Index) {
        _ = self.formIndex(&i, offsetBy: -1, limitedBy: startIndex)
    }
}

extension LazySplitCollection: RandomAccessCollection where Base: RandomAccessCollection {}
