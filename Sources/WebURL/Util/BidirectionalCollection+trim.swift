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
  internal func trim(where predicate: (Element) throws -> Bool) rethrows -> SubSequence {
    var sliceStart = startIndex
    var sliceEnd = endIndex
    // Consume elements from the front.
    while sliceStart < sliceEnd, try predicate(self[sliceStart]) {
      formIndex(after: &sliceStart)
    }
    // Consume elements from the back only if the element at the "before" index matches the predicate.
    while sliceStart < sliceEnd {
      let idxBeforeSliceEnd = index(before: sliceEnd)
      guard try predicate(self[idxBeforeSliceEnd]) else {
        return self[sliceStart..<sliceEnd]
      }
      sliceEnd = idxBeforeSliceEnd
    }
    return self[Range(uncheckedBounds: (sliceStart, sliceStart))]  // Consumed everything.
  }
}
