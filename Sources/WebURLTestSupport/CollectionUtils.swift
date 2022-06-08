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

extension BidirectionalCollection where Element == UInt8 {

  /// Returns a slice of this collection, trimmed of any ASCII spaces from the start and end.
  ///
  var trimmingASCIISpaces: SubSequence {
    let firstNonSpace = firstIndex(where: { $0 != UInt8(ascii: " ") }) ?? endIndex
    let lastNonSpace = lastIndex(where: { $0 != UInt8(ascii: " ") }).map { index(after: $0) } ?? endIndex
    return self[firstNonSpace..<lastNonSpace]
  }
}
