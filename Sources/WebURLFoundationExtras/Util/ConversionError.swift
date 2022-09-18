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

/// An Error which is thrown when a `WebURL` value could not be converted to a `Foundation.URL`.
///
internal struct WebURLToFoundationConversionError: Error, CustomStringConvertible {

  /// The `WebURL` which could not be converted.
  internal var url: WebURL

  internal init(_ url: WebURL) {
    self.url = url
  }

  internal var description: String {
    "Failed to convert WebURL to Foundation.URL: \(url)."
  }
}

extension URL {

  /// Converts the given `WebURL` to a `Foundation.URL`, or throws a `WebURLToFoundationConversionError`.
  ///
  internal init(convertOrThrow url: WebURL, addPercentEncoding: Bool = true) throws {
    guard let convertedURL = URL(url, addPercentEncoding: addPercentEncoding) else {
      throw WebURLToFoundationConversionError(url)
    }
    self = convertedURL
  }
}
