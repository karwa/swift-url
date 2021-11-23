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

// --------------------------------------------
// MARK: - Foundation to WebURL
// --------------------------------------------


extension WebURL {

  /// Creates a `WebURL` which is semantically equivalent to the given `URL`.
  ///
  /// Almost all `URL`s can be converted, but there are some exceptions.
  /// In particular, purely relative URLs and some invalid HTTP URLs cannot be represented by `WebURL`.
  ///
  /// The resulting `WebURL`'s components are normalized, meaning they are semantically equivalent to the corresponding
  /// components from the source `URL`. However, they may not be literally the same strings.
  ///
  public init?(_ nsURL: URL) {

    var urlString = nsURL.absoluteString
    urlString.makeContiguousUTF8()
    self.init(urlString)

    guard nsURL.scheme != nil else {
      return nil  // WebURL requires a scheme.
    }

    guard !self.hasOpaquePath else {
      // Foundation tells us absolutely nothing about URLs with opaque paths (e.g. "mailto:").
      // All properties except the scheme return nil/empty, but the '.absoluteString' has the entire URL.
      // They have no authority components, and the path/query/fragment is unambiguous and not normalized.
      return
    }

    // Username and password can be ambiguous, e.g. "http://@2:@2":
    // - URL reads this as empty username (first @) and host "2" (second @).
    // - WebURL reads this as having username "@2" and host "2".
    // Check that the username and password contents are the same, and reject anything ambiguous.

    switch (self.utf8.username, nsURL.user) {
    case (.none, .none):
      break
    case (.some(let parsedUser), .some(let originalUser)):
      if !parsedUser.lazy.percentDecoded().elementsEqual(originalUser.utf8) {
        return nil
      }
    case (.none, .some(let originalUser)):
      if !originalUser.isEmpty {
        return nil
      }
    case (.some, .none):
      return nil
    }
    switch (self.utf8.password, nsURL.password) {
    case (.none, .none):
      break
    case (.some(let parsedPassword), .some(let originalPassword)):
      if !parsedPassword.elementsEqual(originalPassword.utf8) {
        return nil
      }
    case (.none, .some(let originalPassword)):
      if !originalPassword.isEmpty {
        return nil
      }
    case (.some, .none):
      return nil
    }

    // Between the 2 standards, one thing that can be ambiguous is which host a URL refers to.
    // URL libraries differ widely on how they interpret URLs such as "http://abc@def@ghi",
    // and sending requests to a different host can be a major security issue.
    //
    // For this reason, check that WebURL and Foundation URL agree about which component should
    // be considered the "host", and that normalization preserved the host's identity.

    let nsURLHost = nsURL.host
    switch self._spis._hostKind {
    case .ipv6Address:
      // WebURL normalizes IP addresses, but this is considered a safe change,
      // because IPv6 literals are not otherwise valid hostnames.
      // Check that Foundation's host parses to the same address.
      guard
        let originalIPv6 = nsURLHost.flatMap(IPv6Address.init(_:)),
        originalIPv6 == IPv6Address(utf8: self.utf8.hostname!.dropFirst().dropLast())!
      else {
        return nil
      }
    case .ipv4Address:
      // WebURL normalizes IP addresses, but this is considered a safe change,
      // because only http(s)/ws(s)/ftp/file URLs may have IPv4 addresses,
      // and purely numeric TLDs are not usually valid.
      // Check that Foundation's host parses to the same address.
      guard
        let originalIPv4 = nsURLHost.flatMap(IPv4Address.init(_:)),
        originalIPv4 == IPv4Address(utf8: self.utf8.hostname!)!
      else {
        return nil
      }
    case .domain:
      // WebURL normalizes domains. This is considered a safe change,
      // becuase it only supports ASCII domains, so normalization = lowercasing.
      // DNS names are not case-sensitive.
      guard nsURLHost?.lowercased().utf8.elementsEqual(self.utf8.hostname!.lazy.percentDecoded()) == true else {
        return nil
      }
    case .opaque:
      // Opaque hostnames must be preserved exactly.
      guard nsURLHost?.utf8.elementsEqual(self.utf8.hostname!.lazy.percentDecoded()) == true else {
        return nil
      }
    case .empty:
      // If WebURL's host is empty, the original must be an empty or nil host.
      // This also blocks WebURL's usual "localhost" stripping for file URLs, which is not considered a safe change.
      // https://github.com/whatwg/url/issues/618
      guard nsURLHost?.isEmpty ?? true else {
        return nil
      }
    case .none:
      // Path-only URL, or opaque path (e.g. mailto:).
      guard nsURLHost == nil else {
        return nil
      }
    }

    // It would be too expensive to validate the path contents, and actually getting an accurate path from Foundation
    // turns out to be surprisingly difficult. URL doesn't have a "percentEncodedPath" property; only URLComponents does.
    // But URLComponents(url: URL) will also decode percent-encoding if the path contains a semicolon (! - for real),
    // so it isn't safe to use.
    //
    // Also, the implicit percent-decoding used by URL.path (and sometimes URLComponents(url: URL)) will return
    // an empty string if the path contains percent-encoded invalid UTF-8 (e.g. "s:/;foo%82" returns "", even
    // in URLComponents.percentEncodedPath). https://bugs.swift.org/browse/SR-15508
    //
    // Without even an accurate way to get a URL's precise path, there's really nothing we can do, even if we
    // were willing to pay the performance cost. Thankfully, extensive fuzz-testing shows no cases where WebURL
    // misinterprets which component should be the path.

    path: do {
      let nsURLPath = nsURL.path
      if self.utf8.path.isEmpty != nsURLPath.isEmpty {
        // TODO: [Performance] Try to find a cheaper way than .appendingPathComponent
        if !self.utf8.path.isEmpty, nsURLPath.isEmpty, nsURL.appendingPathComponent("x").path.isEmpty {
          // If we can append a path component and URL.path still returns an empty path,
          // we're probably seeing the percent-encoded non-UTF8 bug. For now, skip path validation.
          break path
        } else {
          // WebURL adds implicit root paths for special schemes. That's a safe deviation.
          if !self._spis._isSpecial { return nil }
        }
      }
    }

    // Again, it is difficult to actually get the accurate query or fragment. For example,
    // URLs like "file:?abc" are normalized by WebURL so they don't have an opaque path ("file:///?abc").
    // But it has the same bugs as URLs with opaque paths in Foundation.URL; so the component properties
    // (host, path, query, fragment) all return empty strings, despite the components clearly
    // being present in the .absoluteString.
    //
    // Again, we rely on fuzz-testing to ensure that WebURL gets it right, and that its query
    // has the correct contents.
  }
}
