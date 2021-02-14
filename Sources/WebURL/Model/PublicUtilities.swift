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

extension StringProtocol {
  
  /// Returns a copy of this string with all special URL characters percent-encoded. Equivalent to JavaScript's `encodeURIComponent()` function.
  ///
  /// The % character itself is included in the encode-set, so that any percent-encoded characters in the original string are preserved and decoding this
  /// string returns the original content without loss.
  ///
  public var urlEncoded: String {
    let encodedBytes = self.utf8.lazy.percentEncoded(using: URLEncodeSet.Component.self).joined()
    return String(_unsafeUninitializedCapacity: encodedBytes.count) { buffer  in
      return buffer.initialize(from: encodedBytes).1
    }
  }
}
