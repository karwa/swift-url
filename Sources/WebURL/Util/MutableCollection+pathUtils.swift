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
    while let firstMatch = fastFirstIndex(from: i, to: endIndex, where: predicate) {
      let run = self[index(after: firstMatch)...].fastPrefix(where: predicate)
      if !run.isEmpty {
        return self[firstMatch..<run.endIndex]
      }
      i = run.endIndex
    }
    return nil
  }
}

extension MutableCollection {

  /// Copies elements from `source..<limit` to locations starting at `destination`.
  ///
  /// This function is equivalent to writing:
  ///
  /// ```swift
  /// self[destination..<(destination + (limit - source))] = self[source..<limit]
  /// ```
  ///
  /// The benefits of this implementation are that
  ///
  /// 1. It takes advantage of contiguous mutable storage when available
  ///    (the standard library's default implementation of the above does not), and
  ///
  /// 2. The source and destination belong to the same collection,
  ///    meaning we do not need to form another reference to the storage and cause it to be non-uniquely referenced.
  ///    When performing the above in a loop, the complexity can be quadratic due to COW.
  ///    This implementation can keep things linear.
  ///
  /// The ranges `source..<limit` and `destination..<destination + (limit - source)` may overlap.
  ///
  /// - parameters:
  ///   - source:      The position of the first element to copy
  ///   - limit:       The position after the last element to copy
  ///   - destination: The position of the first element to overwrite.
  ///                  Upon returning, this value will be set to the position after
  ///                  the last modified element.
  ///
  @inlinable
  internal mutating func rebase(from source: Index, until limit: Index, to destination: inout Index) {

    guard
      let info = withContiguousStorageIfAvailable({ _ -> (src: Int, dst: Int, len: Int) in
        // wCSIA almost always means RandomAccessCollection,
        // so this index->offset translation should be O(1).
        let src = distance(from: startIndex, to: source)
        let dst = distance(from: startIndex, to: destination)
        let len = distance(from: source, to: limit)
        return (src: src, dst: dst, len: len)
      }),
      let _ = withContiguousMutableStorageIfAvailable({ buffer in
        // swift-format-ignore
        precondition(
          info.len >= 0 &&
          info.src >= buffer.startIndex && info.src &+ info.len <= buffer.endIndex &&
          info.dst >= buffer.startIndex && info.dst &+ info.len <= buffer.endIndex
        )
        guard let baseAddress = buffer.baseAddress else {
          assert(info.len == 0)
          return
        }
        #if swift(>=5.8)
          (baseAddress + info.dst).update(from: baseAddress + info.src, count: info.len)
        #else
          (baseAddress + info.dst).assign(from: baseAddress + info.src, count: info.len)
        #endif
      })
    else {
      return _rebase_slow(from: source, until: limit, to: &destination)
    }

    formIndex(&destination, offsetBy: info.len)
  }

  @inlinable
  internal mutating func _rebase_slow(from source: Index, until limit: Index, to destination: inout Index) {

    precondition(limit >= source)

    var source = source
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
      rebase(from: readHead, until: index(after: dupes.startIndex), to: &writeHead)  // Keep one duplicate.
      readHead = nextReadHead
    }
    precondition(writeHead <= readHead, "writeHead has somehow overtaken readHead!")
    rebase(from: readHead, until: endIndex, to: &writeHead)
    return writeHead
  }
}

extension MutableCollection {

  // TODO: It would be better if this was altered to work in terms of a leading separator,
  //       since that's how path components and query parameters are actually modelled by their respective views.

  /// Splits this collection in to segments, separated by elements matching the given predicate,
  /// and trims each segment using the given closure. The trimmed segments, including their trailing separators,
  /// are written in-place over the collection's existing contents.
  ///
  /// This function does not change the length of the collection -
  /// instead, it returns the new "end" index of the shortened content.
  /// The caller should remove or ignore any content from the returned index.
  ///
  /// The following code removes all trailing periods from the segments of a path string.
  /// Note that final string is constructed from a slice up to the index returned by this function.
  ///
  /// ```swift
  /// var utf8 = Array("/abc/def../ghi./.jkl/".utf8)
  ///
  /// let end = utf8.trimSegments(
  ///   skipInitialSeparator: true,
  ///   separatedBy: { $0 == UInt8(ascii: "/") }
  /// ) { elements, range, _ in
  ///   let trailingDots = elements[range].suffix(while: { $0 == UInt8(ascii: ".") })
  ///   return range.lowerBound..<trailingDots.startIndex
  /// }
  ///
  /// String(decoding: utf8[..<end], as: UTF8.self) // "/abc/def/ghi/.jkl/"
  /// ```
  ///
  /// The following example removes all single-character segments from a path string.
  ///
  /// ```swift
  /// var utf8 = Array("/abc/d/ef/./g/hi/jkl/".utf8)
  ///
  /// let end = utf8.trimSegments(
  ///   skipInitialSeparator: true,
  ///   separatedBy: { $0 == UInt8(ascii: "/") }
  /// ) { _, range, _ in
  ///   range.count == 1 ? nil : range
  /// }
  ///
  /// String(decoding: utf8[..<end], as: UTF8.self) // "/abc/ef/hi/jkl/"
  /// ```
  ///
  /// - complexity: O(*n*), where *n* is the length of the collection from `beginning` to `end`.
  ///
  /// - parameters:
  ///   - beginning:             The index at the start of the first segment.
  ///                            If not specified, segments are trimmed from the collection's `startIndex`.
  ///   - end:                   The endIndex of the final segment.
  ///                            If not specified, the final segment ends at the collection's `endIndex`.
  ///   - skipInitialSeparator:  If `true`, and `beginning` points to a separator,
  ///                            the first segment will begin after that separator.
  ///   - isSeparator:           A predicate which decides whether an element is a separator between segments.
  ///   - trim:                  A closure which is passed the collection and range of a segment,
  ///                            and returns the range to keep (or `nil` to discard the segment).
  ///
  /// - returns: The position after the final retained segment.
  ///            Elements in positions `(returned index)..<end` may be discarded.
  ///
  @inlinable
  internal mutating func trimSegments(
    from beginning: Index? = nil,
    to end: Index? = nil,
    skipInitialSeparator: Bool,
    separatedBy isSeparator: (Element) -> Bool,
    _ trim: (inout Self, Range<Index>, _ isLast: Bool) -> Range<Index>?
  ) -> Index {

    // We pass the segment as a (collection, range) pair because creating a slice
    // introduces ARC overhead. Will hopefully be solved by OSSA modules:
    // https://forums.swift.org/t/arc-overhead-when-wrapping-a-class-in-a-struct-which-is-only-borrowed/62037/8

    let end = end ?? endIndex

    var readHead = beginning ?? startIndex
    if skipInitialSeparator, readHead < end, isSeparator(self[readHead]) {
      formIndex(after: &readHead)
    }
    var writeHead = readHead

    precondition(readHead <= end, "beginning is after end")

    while let separatorIdx = fastFirstIndex(from: readHead, to: end, where: isSeparator) {
      let startOfNextSegment = index(after: separatorIdx)
      guard let trimmedSegment = trim(&self, Range(uncheckedBounds: (readHead, separatorIdx)), false) else {
        readHead = startOfNextSegment
        continue
      }
      assert(writeHead <= trimmedSegment.lowerBound, "writeHead has somehow overtaken readHead!")
      rebase(from: trimmedSegment.lowerBound, until: trimmedSegment.upperBound, to: &writeHead)

      self[writeHead] = self[separatorIdx]
      formIndex(after: &writeHead)
      readHead = startOfNextSegment
    }

    guard let trimmedTail = trim(&self, Range(uncheckedBounds: (readHead, end)), true) else {
      return writeHead
    }
    assert(writeHead <= trimmedTail.lowerBound, "writeHead has somehow overtaken readHead!")
    rebase(from: trimmedTail.lowerBound, until: trimmedTail.upperBound, to: &writeHead)
    return writeHead
  }
}
