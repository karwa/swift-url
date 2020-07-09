extension BidirectionalCollection {

  /// Returns a `SubSequence` formed by discarding all elements at the start and end of the Collection
  /// which satisfy the given predicate.
  ///
  /// e.g. `[2, 10, 11, 15, 20, 21, 100].trim(where: { $0.isMultiple(of: 2) })` == `[11, 15, 20, 21]`
  ///
  /// - parameters:
  ///    - predicate:  A closure which determines if the element should be omitted from the resulting slice.
  ///
  @inlinable
  public func trim(where predicate: (Element) throws -> Bool) rethrows -> SubSequence {
    var sliceStart = startIndex
    var sliceEnd = endIndex
    // Consume elements from the front.
    while sliceStart != sliceEnd, try predicate(self[sliceStart]) {
      sliceStart = index(after: sliceStart)
    }
    // Consume elements from the back only if the element at the "before" index matches the predicate.
    while sliceStart != sliceEnd {
      let idxBeforeSliceEnd = index(before: sliceEnd)
      guard try predicate(self[idxBeforeSliceEnd]) else {
        return self[sliceStart..<sliceEnd]
      }
      sliceEnd = idxBeforeSliceEnd
    }
    return self[Range(uncheckedBounds: (sliceStart, sliceStart))]  // Consumed everything.
  }
}
