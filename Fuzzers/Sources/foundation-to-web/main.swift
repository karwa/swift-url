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
public func foundation_to_web(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {

  let bytes = UnsafeBufferPointer(start: start, count: count)
  let input = String(decoding: bytes, as: UTF8.self)

  guard let foundationURL = URL(string: input) else {
    return 0  // Fuzzer did not produce a URL. Try again.
  }
  guard let webURL = WebURL(foundationURL) else {
    return 0  // WebURL didn't convert the URL. That's fine.
  }
  // If WebURL agrees to convert the URL, check equivalence without taking shortcuts.
  var foundationURLString = foundationURL.absoluteString
  let areEquivalent = foundationURLString.withUTF8 { foundationStringUTF8 in
    WebURL._SPIs._checkEquivalence(webURL, foundationURL, foundationString: foundationStringUTF8, shortcuts: false)
  }
  guard areEquivalent else {
    fatalError(
      """
      URLs are not equivalent:
      - Input string: \(input)
      - Foundation.URL: \(foundationURL)
      - WebURL: \(webURL)
      """
    )
  }
  // URLs appear to be equivalent. On to the next one.
  return 0
}
