extension BidirectionalCollection {

    /// Returns a `SubSequence` formed by discarding all elements at the start and end of the Collection
    /// which match the given predicate.
    ///
    /// e.g. `[2, 10, 11, 15, 20, 21, 100].trim(where: { $0.isMultiple(of: 2) })` == `[11, 15, 20, 21]`
    ///
    public func trim(where predicate: (Element) throws -> Bool) rethrows -> SubSequence {
        var sliceStart = startIndex
        var sliceEnd = endIndex
        // Consume matching elements from the front.
        while sliceStart != sliceEnd, try predicate(self[sliceStart]) {
            sliceStart = index(after: sliceStart)
        }
        guard sliceStart != sliceEnd else { return self[sliceStart..<sliceStart] } // Consumed everything. No tail left to check.
        // Consume matching elements from the back only if the element at the "before" index matches the predicate. 
        while sliceStart != sliceEnd {
            let idxBeforeSliceEnd = index(before: sliceEnd)
            guard try predicate(self[idxBeforeSliceEnd]) else { return self[sliceStart..<sliceEnd] } // Found start of tail match. 
            sliceEnd = idxBeforeSliceEnd
        }
        fatalError(
            "Invalid Collection. " +
            "Incremented startIndex to find an Index, but decrementing from endIndex never produced that same Index"
        )
    }
}