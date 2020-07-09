extension Collection {

  /// Returns the longest subrange of elements satisfying the given predicate.
  ///
  /// In the case of a tie, the range closest to the start of the Collection is returned.
  /// If no elements match the predicate, the returned range is empty and the returned length is 0.
  ///
  /// - parameters:
  ///     - predicate:  The condition which elements should match.
  /// - returns:        A tuple containing the longest subrange matching the predicate,
  ///                   as well as how many elements are contained within that range.
  ///
  @inlinable
  public func longestSubrange(satisfying predicate: (Element) throws -> Bool) rethrows
    -> (subrange: Range<Index>, length: Int)
  {
    var idx = startIndex
    var longest: (Range<Index>, length: Int) = (idx..<idx, 0)
    var current: (start: Index, length: Int) = (idx, 0)
    while idx != endIndex {
      switch try predicate(self[idx]) {
      case true:
        if current.length == 0 { current.start = idx }
        current.length &+= 1
      case false:
        if current.length > longest.length { longest = (current.start..<idx, current.length) }
        current.length = 0
      }
      idx = index(after: idx)
    }
    if current.length > longest.length {
      longest = (current.start..<endIndex, current.length)
    }
    return longest
  }
}

extension Collection where Element: Equatable {

  /// Returns the longest subrange of elements that are equal to the given value.
  ///
  /// In the case of a tie, the range closest to the start of the Collection is returned.
  /// If no elements are equal to the given value, the returned range is empty and the returned length is 0.
  ///
  /// - parameters:
  ///     - element:  The value to compare elements with.
  /// - returns:      A tuple containing the longest subrange equal to the given value,
  ///                 as well as how many elements are contained within that range.
  ///
  @inlinable
  public func longestSubrange(equalTo value: Element) -> (subrange: Range<Index>, length: Int) {
    return longestSubrange { $0 == value }
  }
}
