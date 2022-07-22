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

  /// Returns the slice of this collection's trailing elements which match the given predicate.
  ///
  /// If no elements match the predicate, the returned slice is empty, from `endIndex..<endIndex`.
  ///
  @inlinable
  internal func suffix(while predicate: (Element) -> Bool) -> SubSequence {
    var i = endIndex
    while i > startIndex {
      let beforeI = index(before: i)
      guard predicate(self[beforeI]) else { return self[i..<endIndex] }
      i = beforeI
    }
    return self[startIndex..<endIndex]
  }
}
