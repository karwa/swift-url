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

import Foundation
import WebURL
import WebURLFoundationExtras

@_cdecl("LLVMFuzzerTestOneInput")
public func web_to_foundation(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {

  let bytes = UnsafeBufferPointer(start: start, count: count)
  guard let webURL = WebURL(utf8: bytes) else {
    return 0  // Fuzzer did not produce a URL. Try again.
  }
  guard let foundationURL = URL(webURL, addPercentEncoding: true) else {
    return 0  // Couldn't convert the URL. That's fine.
  }

  // If we agree to convert the URL, check equivalence without taking shortcuts.
  let encodedWebURL = webURL.encodedForFoundation
  var foundationURLString = foundationURL.absoluteString
  let areEquivalent = foundationURLString.withUTF8 {
    WebURL._SPIs._checkEquivalence_w2f(encodedWebURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  guard areEquivalent else {
    fatalError(
      """
      URLs are not equivalent:
      - Input string: \(String(decoding: bytes, as: UTF8.self))
      - WebURL: \(webURL)
      - Encoded WebURL: \(encodedWebURL)
      - Foundation.URL: \(foundationURL)
      """
    )
  }
  // URLs appear to be equivalent. On to the next one.
  return 0
}
