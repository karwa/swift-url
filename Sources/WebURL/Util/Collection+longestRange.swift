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
  internal func longestSubrange(satisfying predicate: (Element) throws -> Bool) rethrows
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
      formIndex(after: &idx)
    }
    if current.length > longest.length {
      longest = (current.start..<endIndex, current.length)
    }
    return longest
  }
}

// Note: This has to be 'public' for WebURLTestSupport :(

extension Collection where Element: Equatable {

  /// Returns the longest subrange of elements that are equal to the given value.
  ///
  /// In the case of a tie, the range closest to the start of the Collection is returned.
  /// If no elements are equal to the given value, the returned range is empty and the returned length is 0.
  ///
  /// - Note: This is a `WebURL` implementation detail and not necessarily part of its supported API.
  ///         Do not use this function outside of the `WebURL` package.
  ///
  /// - parameters:
  ///     - element:  The value to compare elements with.
  /// - returns:      A tuple containing the longest subrange equal to the given value,
  ///                 as well as how many elements are contained within that range.
  ///
  @inlinable
  public func _longestSubrange(equalTo value: Element) -> (subrange: Range<Index>, length: Int) {
    return longestSubrange { $0 == value }
  }
}
