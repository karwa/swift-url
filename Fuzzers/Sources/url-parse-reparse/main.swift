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

import WebURL

@_cdecl("LLVMFuzzerTestOneInput")
public func url_parse_reparse(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {

  let bytes = UnsafeBufferPointer(start: start, count: count)
  if let url = WebURL(utf8: bytes) {
    guard let reparsed = WebURL(utf8: url.utf8) else {
      preconditionFailure("Failed to reparse URL")
    }
    guard reparsed.utf8.elementsEqual(url.utf8) else {
      preconditionFailure("Reparsed URL was not equal to the original")
    }
    // TODO: Also check that `URLStructure` is the same.
  }

  return 0
}
