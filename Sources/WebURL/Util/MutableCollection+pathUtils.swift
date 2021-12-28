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

  /// Returns the first slice of 2 or more consecutive elements which match the given predicate,
  /// or `nil` if the collection does not contain a run of 2 or more consecutive elements which match the predicate.
  ///
  /// ```swift
  /// let testOne = [1, 2, 3, 4]
  /// testOne.firstConsecutiveElements { $0 == 2 } // nil
  ///
  /// let testTwo = [1, 2, 2, 3, 4]
  /// testTwo.firstConsecutiveElements { $0 == 2 } // [2, 2], at indices 1..<3
  /// ```
  ///
  @inlinable
  internal func firstConsecutiveElements(matching predicate: (Element) -> Bool) -> SubSequence? {

    var i = startIndex
    while let firstMatch = self[i...].fastFirstIndex(where: predicate) {
      let run = self[index(after: firstMatch)...].prefix(while: predicate)
      if !run.isEmpty {
        return self[firstMatch..<run.endIndex]
      }
      i = run.endIndex
    }
    return nil
  }
}

extension MutableCollection {

  /// Copies elements from `source` to `destination` over the range `source..<limit`.
  ///
  /// This is an alternative to writing `self[destination..<(destination + (limit - source))] = self[source..<limit]`,
  /// which avoids quadratic performance issues for copy-on-write data types like `Array` (at least in release builds; debug builds are still quadratic 😖).
  ///
  @inlinable
  internal mutating func _copyElements(from source: inout Index, to destination: inout Index, limit: Index) {

    // It's hard to avoid quadratic performance for COW data types like Array.
    // Setting each index individually helps in release mode, at least.
    // See: https://forums.swift.org/t/avoiding-cow-in-mutablecollections-slice-setter/49587
    while source < limit {
      let tmp = self[source]
      self[destination] = tmp
      formIndex(after: &source)
      formIndex(after: &destination)
    }
  }
}

extension MutableCollection {

  /// Collapses runs of 2 or more consecutive elements which match the given predicate, keeping only the first element from each run.
  ///
  /// This function overwrites elements of the collection without changing its overall length (as that is not supported by `MutableCollection`).
  /// That means the collection will contain a tail region of old elements which need to be discarded (either removed/deinitialized, or simply ignored by subsequent
  /// processing). This function returns the index from which that tail region starts, and it is the caller's responsibility to ignore/discard elements from that position.
  ///
  /// The following example demonstrates removing consecutive `2`s from an `Array`.
  /// Note the call to `removeSubrange` to discard elements in the tail region:
  ///
  /// ```swift
  /// var elements = [1, 2, 2, 3, 2, 2, 2, 4, 5, 2, 2, 2, 2, 6, 7, 8, 2]
  /// let end = elements.collapseConsecutiveElements(from: 3, matching: { $0 == 2 })
  /// elements.removeSubrange(end...)
  /// print(elements) // [1, 2, 2, 3, 2, 4, 5, 2, 6, 7, 8, 2]
  /// ```
  ///
  /// - complexity: O(*n*), where *n* is the length of the collection from `beginning`.
  /// - important: Performance with COW data types like `Array` can be flaky (quadratic) in debug builds, but should be linear in release builds 🤞
  ///
  /// - parameters:
  ///   - beginning: The index to begin searching from.
  ///   - predicate: The predicate by which elements are grouped. Consecutive elements that match this predicate are collapsed; only the first
  ///                matching element of each run is kept.
  /// - returns: The index after the last meaningful element in the collection.
  ///            Elements in positions `returnValue..<endIndex` will have already been collapsed or copied to an earlier position in the collection,
  ///            and should be discarded or ignored.
  ///
  @inlinable
  internal mutating func collapseConsecutiveElements(
    from beginning: Index, matching predicate: (Element) -> Bool
  ) -> Index {

    var readHead = beginning
    guard let firstRun = self[readHead...].firstConsecutiveElements(matching: predicate) else {
      return endIndex  // Nothing to collapse.
    }
    var writeHead = index(after: firstRun.startIndex)  // Keep one duplicate.
    readHead = firstRun.endIndex

    while let dupes = self[readHead...].firstConsecutiveElements(matching: predicate) {
      precondition(writeHead <= readHead, "writeHead has somehow overtaken readHead!")
      let nextReadHead = dupes.endIndex  // Hope the slice gets released before we mutate self 🤞.
      _copyElements(from: &readHead, to: &writeHead, limit: index(after: dupes.startIndex))  // Keep one duplicate.
      readHead = nextReadHead
    }
    precondition(writeHead <= readHead, "writeHead has somehow overtaken readHead!")
    _copyElements(from: &readHead, to: &writeHead, limit: endIndex)
    return writeHead
  }
}

extension MutableCollection {

  /// Splits this collection's elements in to segments, separated by elements matching the given predicate, and trims each segment in-place using
  /// the given trimming closure. The trimmed segments, including separators, are coalesced and written over the collection's existing contents.
  ///
  /// Note that this function does not change the length of the collection; instead, it returns the new "end" index of the shortened content.
  /// The caller should remove or ignore any content from the returned index.
  ///
  /// For instance, the following code removes all trailing periods from the segments of a path string, where segments are delimited by forward slashes.
  /// Note that final string is constructed from a slice up to the index returned by this function.
  ///
  /// ```swift
  /// var utf8 = Array("/abc/def../ghi./.jkl/".utf8)
  /// let end = utf8.trimSegments(separatedBy: { $0 == Character("/").asciiValue! }) { component, _, _ in
  ///   let trailingDots = component.suffix(while: { $0 == Character(".").asciiValue! })
  ///   return component[..<trailingDots.startIndex]
  /// }
  /// String(decoding: utf8[..<end], as: UTF8.self) // "/abc/def/ghi/.jkl/"
  /// ```
  ///
  /// - complexity: O(*n*), where *n* is the length of the collection from `beginning`.
  /// - important: Performance with COW data types like `Array` can be flaky (quadratic) in debug builds, but should be linear in release builds 🤞
  ///
  /// - parameters:
  ///   - beginning:   The index from which segments should be trimmed. If not given, segments are trimmed from the collection's `startIndex`.
  ///   - isSeparator: A predicate which distinguishes elements that should be considered a separator between segments.
  ///   - trim:        A closure which trims segments of the collection. It is provided with a slice of the collection, as well as flags informing it whether
  ///                  this is the first and/or last segment, and returns the portion of the slice which should be kept.
  /// - returns: The new "endIndex" of the collection. Elements from this position are duplicates which have been copied to earlier positions, and should
  ///            be discarded.
  ///
  @inlinable
  internal mutating func trimSegments(
    from beginning: Index? = nil,
    separatedBy isSeparator: (Element) -> Bool,
    _ trim: (SubSequence, _ isFirst: Bool, _ isLast: Bool) -> SubSequence
  ) -> Index {

    var readHead = beginning ?? startIndex
    // If the content begins with a separator, advance past it.
    // The segment's contents extend from after the separator until the next separator.
    if readHead < endIndex, isSeparator(self[readHead]) {
      formIndex(after: &readHead)
    }

    var writeHead = readHead
    var isFirst = true

    while let separatorIdx = self[readHead...].fastFirstIndex(where: isSeparator) {
      let trimmedSegment = trim(self[readHead..<separatorIdx], isFirst, false)

      readHead = trimmedSegment.startIndex
      precondition(writeHead <= readHead, "writeHead has somehow overtaken readHead!")
      _copyElements(from: &readHead, to: &writeHead, limit: trimmedSegment.endIndex)

      self[writeHead] = self[separatorIdx]
      formIndex(after: &writeHead)
      readHead = index(after: separatorIdx)

      isFirst = false
    }

    let trimmedTail = trim(self[readHead...], isFirst, true)
    readHead = trimmedTail.startIndex
    precondition(writeHead <= readHead, "writeHead has somehow overtaken readHead!")
    _copyElements(from: &readHead, to: &writeHead, limit: trimmedTail.endIndex)
    return writeHead
  }
}
