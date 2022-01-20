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

  /// Returns the index of the first element to match the given predicate,
  /// or `nil` if no elements match.
  ///
  @inlinable
  internal func fastFirstIndex(where predicate: (Element) -> Bool) -> Index? {
    var idx = startIndex
    while idx < endIndex {
      if predicate(self[idx]) { return idx }
      formIndex(after: &idx)
    }
    return nil
  }

  /// Returns a subsequence of elements which match the given predicate, starting at `startIndex`.
  ///
  @inlinable
  internal func fastPrefix(where predicate: (Element) -> Bool) -> SubSequence {
    if let endOfPrefix = fastFirstIndex(where: { !predicate($0) }) {
      return self[Range(uncheckedBounds: (startIndex, endOfPrefix))]
    }
    return self[Range(uncheckedBounds: (startIndex, endIndex))]
  }

  /// Returns a subsequence of elements formed by discarding elements at the front which match the given predicate.
  ///
  @inlinable
  internal func fastDrop(while predicate: (Element) -> Bool) -> SubSequence {
    if let firstToKeep = fastFirstIndex(where: { !predicate($0) }) {
      return self[Range(uncheckedBounds: (firstToKeep, endIndex))]
    }
    return self[Range(uncheckedBounds: (endIndex, endIndex))]
  }

  /// Whether all elements of the collection satisfy the given predicate.
  /// If the collection is empty, returns `true`.
  ///
  @inlinable
  internal func fastAllSatisfy(_ predicate: (Element) -> Bool) -> Bool {
    fastFirstIndex(where: { !predicate($0) }) == nil
  }
}

extension Collection where Element: Equatable {

  @inlinable @inline(__always)  // The closure should be inlined.
  internal func fastFirstIndex(of element: Element) -> Index? {
    fastFirstIndex(where: { $0 == element })
  }
}

extension Collection where SubSequence == Self {

  /// Removes and returns the first element of this collection, if it is not empty.
  ///
  @inlinable
  internal mutating func fastPopFirst() -> Element? {
    guard startIndex < endIndex else { return nil }
    let element = self[startIndex]
    self = self[Range(uncheckedBounds: (index(after: startIndex), endIndex))]
    return element
  }
}

extension BidirectionalCollection {

  /// Returns the index closest to `endIndex` whose element matches the given predicate.
  ///
  /// The difference between this implementation and the one in the standard library is
  /// that this uses  `>` and `<` rather than `==` and `!=` to compare indexes,
  /// which allows bounds-checking to be more throughly eliminated.
  ///
  @inlinable
  internal func fastLastIndex(where predicate: (Element) -> Bool) -> Index? {
    var i = endIndex
    while i > startIndex {
      formIndex(before: &i)
      // Since endIndex > startIndex, and 'i' starts from endIndex and decrements if > startIndex,
      // it will never underflow. Thus 'i < endIndex' must always be true.
      // The compiler isn't smart enough to prove that, so it won't eliminate the bounds-check.
      // It's better to add the (certainly predictable) branch rather than bork our codegen with a trap.
      if i < endIndex, predicate(self[i]) { return i }
    }
    return nil
  }
}

extension BidirectionalCollection where Element: Equatable {

  /// Returns the index closest to `endIndex` whose element is equal to the given element.
  ///
  /// The difference between this implementation and the one in the standard library is
  /// that this uses  `>` and `<` rather than `==` and `!=` to compare indexes,
  /// which allows bounds-checking to be more throughly eliminated.
  ///
  @inlinable @inline(__always)  // The closure should be inlined.
  internal func fastLastIndex(of element: Element) -> Index? {
    fastLastIndex(where: { $0 == element })
  }
}
