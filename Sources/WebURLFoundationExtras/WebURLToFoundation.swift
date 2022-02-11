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
// MARK: - WebURL to Foundation
// --------------------------------------------
//
// Because WebURLs are normalized, and Foundation's parser is strict, there is generally no additional normalization
// which needs to be checked for compatibility with the WHATWG URL Standard. It's still important to verify
// that the components have equivalent values, however "equivalence" for components can be simplified
// to exact string equality.
//
// The most important thing we need to consider is that the WHATWG standard tolerates some (technically invalid)
// characters which Foundation doesn't, so we offer (optional) percent-encoding to ensure that more URLs
// can be successfully converted.
//
// ============ END ============


extension WebURL {

  /// Returns a copy of this URL which includes any percent-encoding required to convert to a `Foundation.URL`.
  ///
  /// When converting between `Foundation.URL` and `WebURL`, the URL strings and components are verified
  /// as equivalent, although they may not be identical. For example, conversion from Foundation to WebURL
  /// requires normalizing obscure IP addresses and simplifying the path, and conversion from WebURL to Foundation
  /// sometimes needs to add percent-encoding. This is necessary because they conform to different URL standards.
  ///
  /// However it can be inconvenient. When converting back and forth between URL types, it is often useful
  /// to guarantee that the result is not just equivalent, but **identical** to the starting URL,
  /// so that it may be matched with the `==` operator or found in a `Dictionary`.
  /// This is known as _"round-tripping"_.
  ///
  /// The URL returned by this property includes the percent-encoding required to convert to Foundation.
  /// If it can be converted to a `Foundation.URL`, that result can later be converted _back_ to a `WebURL` which
  /// is **identical** to the URL returned by this property. No further normalization or encoding will be required.
  ///
  /// Example:
  ///
  /// ```swift
  /// "https://example.com/products?id={uuid}"
  /// // original:                     ^    ^
  /// "https://example.com/products?id=%7Buuid%7D"
  /// // encoded:                      ^^^    ^^^
  /// ```
  ///
  /// See the `URL.init?(_: WebURL, addPercentEncoding: Bool)` initializer for more information about which
  /// characters will be encoded.
  ///
  public var encodedForFoundation: WebURL {
    var encodedCopy = self
    let _ = encodedCopy._spis._addPercentEncodingToAllComponents(RFC2396DisallowedSubdelims())
    return encodedCopy
  }
}

extension Foundation.URL {

  /// Creates a Foundation `URL` equivalent to the given `WebURL`.
  ///
  /// When converting between `Foundation.URL` and `WebURL`, the URL strings and components are verified
  /// as equivalent, although they may not be identical. Conversion from WebURL to Foundation sometimes
  /// needs to add percent-encoding. This is necessary because they conform to different URL standards.
  ///
  /// `WebURL`, in common with all major browsers, allows the following characters even if they are not percent-encoded,
  /// but Foundation's `URL` does not. By default, this encoding will be added for you, although you may opt-out
  /// of this by setting the `addPercentEncoding` parameter to `false`. Note that doing so will mean that URLs
  /// containing the following characters cannot be converted:
  ///
  /// - Curly braces (`{}`)
  /// - Backslashes (`\`)
  /// - Circumflex accents (`^`)
  /// - Backticks (`` ` ``)
  /// - Vertical bars (`|`).
  /// - Square brackets (`[]`), unless used to delimit an IPv6 address.
  /// - Number signs (`#`), unless used to delimit the URL's fragment.
  /// - Percent signs (`%`), unless used to delimit a percent-encoded byte.
  ///
  /// Example:
  ///
  /// ```swift
  /// "https://example.com/products?id={uuid}"
  /// // original:                     ^    ^
  /// "https://example.com/products?id=%7Buuid%7D"
  /// // encoded:                      ^^^    ^^^
  /// ```
  ///
  /// If percent-encoding is being added (which is the default), and `webURL` has already been encoded
  /// for Foundation compatibility via the `.encodedForFoundation` property, the result will _round-trip_
  /// back to an identical `WebURL` value. If percent-encoding is not being added, the result will also round-trip
  /// without requiring additional normalization or percent-encoding.
  ///
  /// - parameters:
  ///   - webURL:             The URL to convert
  ///   - addPercentEncoding: Whether characters disallowed by Foundation should be percent-encoded.
  ///                         The default is `true`.
  ///
  public init?(_ webURL: WebURL, addPercentEncoding: Bool = true) {

    // Foundation will percent-encode some disallowed characters on its own (`[]`, but not `{}` etc).
    // If the user explicitly asked to opt-out of encoding, we should fail rather than let it do that.
    var encodedCopy = webURL
    switch encodedCopy._spis._addPercentEncodingToAllComponents(RFC2396DisallowedSubdelims()) {
    case .doesNotNeedEncoding:
      break
    case .encodingAdded:
      guard addPercentEncoding else { return nil }
    case .unableToEncode:
      return nil
    }

    self.init(string: encodedCopy.serialized())

    var foundationURLString = self.absoluteString
    let isEquivalent = foundationURLString.withUTF8 {
      WebURL._SPIs._checkEquivalence_w2f(encodedCopy, self, foundationString: $0, shortcuts: true)
    }
    guard isEquivalent else { return nil }
  }
}


// --------------------------------------------
// MARK: - URL Equivalence
// --------------------------------------------


extension WebURL._SPIs {

  /// Returns whether the given WebURL and Foundation.URL have an equivalent set of components.
  ///
  /// This function is designed to check WebURL to Foundation conversions.
  /// As such, it requires both the URL string and its components to be identical between the two URLs;
  /// for example, the scheme is assumed to already be lowercased, and IP-address are in their canonical form.
  /// This is a much stricter equivalence check than is used by Foundation to WebURL conversion.
  ///
  /// If `shortcuts` is `true`, this function takes steps to avoid checking each individual component.
  /// For example, if Foundation's URL string does not contain a `"@"` character anywhere, it is assumed
  /// that Foundation's URL will not return a username or password, and we can simply check that `webURL` agrees
  /// rather than actually calling getter for those components (as they are very expensive, even if the value is nil).
  ///
  /// These shortcuts are only safe if `foundationURL` has been parsed from `webURL.serialized()`,
  /// and are verified by tests, including fuzz-testing. If shortcuts is `false`, every component is checked
  /// and this function makes no assumptions that the two URLs are related at all.
  ///
  /// - parameters:
  ///   - webURL:           A WebURL value to compare for equivalence.
  ///   - foundationURL:    A Foundation.URL value to compare for equivalence.
  ///   - foundationString: A buffer containing the UTF-8 contents of `foundationURL.absoluteString`.
  ///   - shortcuts:        Whether to allow shortcuts for faster equivalence checks.
  ///                       Only safe if `foundationURL` has been parsed from `webURL.serialized()`.
  ///
  /// - returns: Whether `webURL` and `foundationURL` have an equivalent set of URL components.
  ///
  /// > Important:
  /// > This function is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  public static func _checkEquivalence_w2f(
    _ webURL: WebURL, _ foundationURL: Foundation.URL, foundationString: UnsafeBufferPointer<UInt8>, shortcuts: Bool
  ) -> Bool {

    // Require exact string equality.
    // This ensures that Foundation didn't encode anything we didn't want it to
    // (e.g. square brackets or '#'s in opaque paths), and is a useful for guaranteeing round-tripping.
    guard foundationString.fastElementsEqual(webURL.utf8) else {
      return false
    }

    // Scheme:

    guard foundationURL.scheme?._withContiguousUTF8({ webURL.utf8.scheme.fastElementsEqual($0) }) == true else {
      return false
    }

    // Foundation.URLs with opaque paths (e.g. "mailto:") return nil/empty for all components except the scheme.
    // That said, they are surprisingly common, so we can't just reject them. Allow them without verification 😐.

    guard !webURL.hasOpaquePath else {
      if shortcuts {
        return true
      } else {
        return checkURLWithOpaquePathEquivalenceUsingURLComponents_w2f(webURL, foundationURL)
      }
    }

    // [Shortcut] Quick Scan:
    // Getting components from Foundation is expensive, even if the component is 'nil'. So take a shortcut:
    // if a component's delimiter is not present anywhere in Foundation's URL string, the component is also not present.

    var assumeNoUserInfo = false
    var assumeNoQuery = false
    var assumeNoFragment = false

    if shortcuts {
      (assumeNoUserInfo, assumeNoQuery, assumeNoFragment) = (
        !foundationString.fastContains(UInt8(ascii: "@")),
        !foundationString.fastContains(UInt8(ascii: "?")),
        !foundationString.fastContains(UInt8(ascii: "#"))
      )
    }

    // Username & Password:

    if assumeNoUserInfo {
      assert(shortcuts)
      guard webURL.utf8.username == nil, webURL.utf8.password == nil else {
        return false
      }
    } else {
      guard checkUserInfoEquivalence_w2f(webURL, foundationURL) else {
        return false
      }
    }

    // Host:

    let hostOK = foundationURL.host._withContiguousUTF8 { foundationHost -> Bool in
      switch (webURL.utf8.hostname, foundationHost) {
      case (.some(var webURLHost), .some(let foundationHost)):
        if webURL._spis._isSpecial || webURL._spis._isIPv6 {
          // Foundation.URL.host doesn't include square brackets in IPv6 addresses.
          if webURL._spis._isIPv6 {
            let first = webURLHost.popFirst()
            let last = webURLHost.popLast()
            assert(first == UInt8(ascii: "["))
            assert(last == UInt8(ascii: "]"))
          }
          return webURLHost.fastElementsEqual(foundationHost)
        }
        return webURLHost.lazy.percentDecoded().fastElementsEqual(foundationHost)
      case (.none, .none):
        return true
      case (.some(let webURLHost), .none):
        // Foundation.URL.host returns nil for empty hostnames.
        return webURLHost.isEmpty
      default:
        return false
      }
    }
    guard hostOK else { return false }

    // Port:

    guard webURL.port == foundationURL.port else {
      return false
    }

    // Path:
    // The only thing we have to verify is whether WebURL and Foundation.URL agree about which
    // part of the URL string contains the path.
    //
    // Unfortunately, that is difficult to check directly, as Foundation.URL only returns percent-decoded paths.
    // We can sometimes overcome it by using URLComponents, but the conversion is expensive and unreliable.

    // [Shortcut] Skip Path:
    // Since we have verified all components preceding the path, if we also verify the component following the path
    // (or reach the end of the string), we may infer that WebURL and Foundation.URL agree about which part
    // of the URL string was the URL's path component.

    if !shortcuts {
      guard checkPathEquivalenceUsingURLComponents_w2f(webURL, foundationURL) else {
        return false
      }
    }

    // Query:

    var queryIsPresent = false
    let webURLQuery = webURL.utf8.query

    if assumeNoQuery {
      assert(shortcuts)
      guard webURLQuery == nil else {
        return false
      }
    } else {
      let queryOK = foundationURL.query._withContiguousUTF8 { foundationQuery -> Bool in
        switch (webURLQuery, foundationQuery) {
        case (.some(let webURLQuery), .some(let foundationQuery)):
          queryIsPresent = true
          return webURLQuery.fastElementsEqual(foundationQuery)
        case (.none, .none):
          return true
        default:
          return false
        }
      }
      guard queryOK else { return false }
    }

    // [Shortcut] Skip Fragment:
    // If we have seen and verified a query component, that serves to verify the path, and implies that
    // WebURL and Foundation.URL also agree about which part of the string contains the URL's fragment.

    guard !queryIsPresent || !shortcuts else {
      return true
    }

    // Fragment:

    let webURLFragment = webURL.utf8.fragment

    if assumeNoFragment {
      assert(shortcuts)
      guard webURLFragment == nil else {
        return false
      }
    } else {
      let fragmentOK = foundationURL.fragment._withContiguousUTF8 { foundationFragment -> Bool in
        switch (webURLFragment, foundationFragment) {
        case (.some(let webURLFragment), .some(let foundationFragment)):
          return webURLFragment.fastElementsEqual(foundationFragment)
        case (.none, .none):
          return true
        default:
          return false
        }
      }
      guard fragmentOK else { return false }
    }

    // All Checks Passed. The URLs appear to contain equivalent components.
    return true
  }

  /// Returns whether the given WebURL and Foundation.URL have an equivalent set of user-info components.
  ///
  /// This function is deliberately outlined from `_checkEquivalence_w2f`.
  ///
  @inline(never)
  private static func checkUserInfoEquivalence_w2f(_ webURL: WebURL, _ foundationURL: URL) -> Bool {

    // If a URL has no username but does have a password (e.g. "http://:password@host/"),
    // Foundation returns that the username is empty, but WebURL returns nil.
    // That's a safe difference, but only if both agree that a password is present.
    var emptyUsernameRequiresPasswordCheck = false

    // Username:

    let userOK = foundationURL.user._withContiguousUTF8 { foundationUser -> Bool in
      switch (webURL.utf8.username, foundationUser) {
      case (.some(let webURLUsername), .some(let foundationUser)):
        return webURLUsername.lazy.percentDecoded().fastElementsEqual(foundationUser)
      case (.none, .none):
        return true
      case (.none, .some(let foundationUser)):
        emptyUsernameRequiresPasswordCheck = true
        return foundationUser.isEmpty
      default:
        return false
      }
    }
    guard userOK else { return false }

    // Password:

    let passwordOK = foundationURL.password._withContiguousUTF8 { foundationPassword -> Bool in
      switch (webURL.utf8.password, foundationPassword) {
      case (.some(let webURLPassword), .some(let foundationPassword)):
        emptyUsernameRequiresPasswordCheck = false
        return webURLPassword.fastElementsEqual(foundationPassword)
      case (.none, .none):
        return true
      default:
        return false
      }
    }
    guard passwordOK, !emptyUsernameRequiresPasswordCheck else { return false }

    return true
  }

  /// Returns whether the given WebURL and Foundation.URL (as interpreted by URLComponents) have an equivalent path,
  /// although it is not possible to verify in all circumstances.
  ///
  /// This function is deliberately outlined from `_checkEquivalence_w2f`.
  ///
  @inline(never)
  private static func checkPathEquivalenceUsingURLComponents_w2f(_ webURL: WebURL, _ foundationURL: URL) -> Bool {

    guard let fndRawPath = URLComponents(url: foundationURL, resolvingAgainstBaseURL: true)?.percentEncodedPath else {
      return true  // Unable to validate.
    }
    guard !fndRawPath.isEmpty, !fndRawPath.utf8.lazy.percentDecoded().fastContains(UInt8(ascii: ";")) else {
      return true  // Unable to validate.
    }
    guard !fndRawPath.utf8.fastContains(UInt8(ascii: "\\")) else {
      return false  // Should not be present.
    }

    let webURLPath: WebURL.UTF8View.SubSequence
    // Path sigils are not considered part of the path by WebURL.
    if webURL._spis._hasPathSigil {
      webURLPath = webURL.utf8[webURL.utf8.scheme.endIndex..<webURL.utf8.path.endIndex].dropFirst()
    } else {
      webURLPath = webURL.utf8.path
    }
    return fndRawPath._withContiguousUTF8 { webURLPath.fastElementsEqual($0) }
  }

  /// Returns whether the given WebURL and Foundation.URL (as interpreted by URLComponents) have an equivalent
  /// set of components, given that the URL has an opaque path.
  ///
  /// It is not possible to verify the components in all circumstances.
  ///
  /// This function is deliberately outlined from `_checkEquivalence_w2f`.
  ///
  @inline(never)
  private static func checkURLWithOpaquePathEquivalenceUsingURLComponents_w2f(
    _ webURL: WebURL, _ foundationURL: URL
  ) -> Bool {

    assert(webURL.hasOpaquePath)

    guard let foundationComponents = URLComponents(url: foundationURL, resolvingAgainstBaseURL: true) else {
      return true  // Unable to validate.
    }

    // Opaque path:

    let foundationPath = foundationComponents.percentEncodedPath
    guard !foundationPath.isEmpty, !foundationPath.utf8.lazy.percentDecoded().fastContains(UInt8(ascii: ";")) else {
      return true  // Unable to validate.
    }
    guard foundationPath._withContiguousUTF8({ webURL.utf8.path.fastElementsEqual($0) }) else {
      return false
    }

    // Query:

    let queryOK = foundationComponents.percentEncodedQuery._withContiguousUTF8 { foundationQuery -> Bool in
      switch (webURL.utf8.query, foundationQuery) {
      case (.some(let webURLQuery), .some(let foundationQuery)):
        return webURLQuery.fastElementsEqual(foundationQuery)
      case (.none, .none):
        return true
      default:
        return false
      }
    }
    guard queryOK else { return false }

    // Fragment:

    let fragmentOK = foundationComponents.percentEncodedFragment._withContiguousUTF8 { foundationFragment -> Bool in
      switch (webURL.utf8.fragment, foundationFragment) {
      case (.some(let webURLFragment), .some(let foundationFragment)):
        return webURLFragment.fastElementsEqual(foundationFragment)
      case (.none, .none):
        return true
      default:
        return false
      }
    }

    return fragmentOK
  }
}


// --------------------------------------------
// MARK: - PercentEncodeSets
// --------------------------------------------


/// Code-points banned by RFC-2396 for use as subcomponent delimiters.
///
/// RFC-2396 forbids the following code-points from being used unless escaped.
/// These are the `control`, `space`, and `delims` character sets.
///
/// | Characters    | Bytes       |                                                                 |
/// |---------------|-------------|-----------------------------------------------------------------|
/// | C0 Controls   |  0x00-0x1F  | Already encoded by WebURL in all components.                    |
/// | Space         |    0x20     | Already encoded by WebURL in all components.                    |
/// | "             |    0x22     | Already encoded by WebURL in all components.                    |
/// | < >           |  0x3C,0x3E  | Already encoded by WebURL in all components.                    |
/// | U+007F DELETE |    0x7F     | Already encoded by WebURL in all components.                    |
/// | #             |    0x23     | Allowed by WebURL in the fragment, e.g. `"sc:/foo#abc#def#gh"`. |
/// | %             |    0x25     | Allowed by WebURL, e.g. `"%ZZ"`.                                |
///
/// Additionally, the following code-points comprise the `unwise` character set.
///
/// | Characters | Bytes       |                    |
/// |------------|-------------|--------------------|
/// |     [ ]    |  0x5B,0x5D  | Allowed by WebURL. |
/// |      \     |    0x5C     | Allowed by WebURL. |
/// |      ^     |    0x5E     | Allowed by WebURL. |
/// |     \`     |    0x60     | Allowed by WebURL. |
/// |     { }    |  0x7B,0x7D  | Allowed by WebURL. |
/// |     \|     |    0x7C     | Allowed by WebURL. |
///
/// https://www.rfc-editor.org/rfc/rfc2396#section-2.4.3
///
internal struct RFC2396DisallowedSubdelims: PercentEncodeSet {

  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    //                 FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210_FEDCBA98_76543210
    let lo: UInt64 = 0b01010000_00000000_00000000_00101101_11111111_11111111_11111111_11111111
    let hi: UInt64 = 0b00111000_00000000_00000000_00000001_01111000_00000000_00000000_00000000
    if codePoint < 64 {
      return lo & (1 &<< codePoint) != 0
    } else if codePoint < 128 {
      return hi & (1 &<< (codePoint &- 64)) != 0
    }
    return true
  }
}
