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

// Slices, trimming.

extension BidirectionalCollection {

  /// Returns the slice of this collection's trailing elements which match the given predicate.
  ///
  /// If no elements match the predicate, the returned slice is empty, from `endIndex..<endIndex`.
  ///
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

extension Substring {

  internal var trimmingSpaces: Substring {
    let firstNonSpace = firstIndex(where: { $0 != " " }) ?? endIndex
    let lastNonSpace = lastIndex(where: { $0 != " " }).map { index(after: $0) } ?? endIndex
    return self[firstNonSpace..<lastNonSpace]
  }
}

// Padding.

extension String {
  internal func leftPadding(toLength newLength: Int, withPad character: Character) -> String {
    precondition(count <= newLength, "newLength must be greater than or equal to string length")
    return String(repeating: character, count: newLength - count) + self
  }
}

// Int to Hex.

extension FixedWidthInteger {
  internal var hexString: String {
    "0x" + String(self, radix: 16, uppercase: true)
  }
}

extension FixedWidthInteger {
  internal var paddedHexString: String {
    "0x" + (String(self, radix: 16, uppercase: true).leftPadding(toLength: Self.bitWidth / 4, withPad: "0"))
  }
}
