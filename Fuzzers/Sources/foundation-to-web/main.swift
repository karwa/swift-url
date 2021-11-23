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
import WebURLTestSupport

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

  // If WebURL does make a conversion, the result must be semantically equivalent
  // according to the more thorough checks in WebURLTestSupport:
  let failures = checkSemanticEquivalence(foundationURL, webURL)
  guard failures.isEmpty else {
    fatalError(
      #"""
      Non-equivalent URLs:
      - Foundation: "\#(foundationURL)"
      - WebURL: "\#(webURL)"
      - Failures: \#(failures)
      """#
    )
  }
  // URLs appear to be equivalent. On to the next one.
  return 0
}
