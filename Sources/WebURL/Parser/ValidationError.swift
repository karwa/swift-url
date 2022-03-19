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


// --------------------------------------------
// MARK: - Parser Callbacks
// --------------------------------------------
// Almost no users care about the specific errors that occur during parsing
// - but there are use-cases, and it's helpful for testing.
// It's important that regular, release builds of the URL parser
// optimize out and around error reporting, so the callback needs to
// be a protocol in order to take advantage of generic specialization.
// --------------------------------------------


/// An object which is informed by the URL parser if a validation error occurs.
///
/// Most validation errors are non-fatal and parsing can continue regardless. If parsing fails, the last
/// validation error typically describes the issue which caused it to fail.
///
@usableFromInline
internal protocol URLParserCallback {
  mutating func validationError(_ error: ValidationError)
}

/// A `URLParserCallback` which ignores all validation errors.
///
@usableFromInline
internal struct IgnoreValidationErrors: URLParserCallback {

  @inlinable @inline(__always)
  internal init() {}

  @inlinable @inline(__always)
  internal mutating func validationError(_ error: ValidationError) {}
}


// --------------------------------------------
// MARK: - Validation Errors
// --------------------------------------------


/// A notification about a syntax oddity encountered by the URL parser.
///
/// Even valid URLs which can be successfully parsed may emit validation errors - for instance, the mere _presence_ of credentials (username or password)
/// is considered grounds to report a `ValidationError`, even though such URLs can be parsed.
///
@usableFromInline
internal struct ValidationError: Equatable {

  @usableFromInline
  internal var _code: UInt8

  @inlinable
  internal init(_code: UInt8) {
    self._code = _code
  }
}

// swift-format-ignore
extension ValidationError {

  // Named errors and their descriptions/examples from: https://github.com/whatwg/url/pull/502
  @inlinable internal static var unexpectedC0ControlOrSpace:         Self { Self(_code: 0) }
  @inlinable internal static var unexpectedASCIITabOrNewline:        Self { Self(_code: 1) }
  @inlinable internal static var invalidSchemeStart:                 Self { Self(_code: 2) }
  @inlinable internal static var fileSchemeMissingFollowingSolidus:  Self { Self(_code: 3) }
  @inlinable internal static var invalidScheme:                      Self { Self(_code: 4) }
  @inlinable internal static var missingSchemeNonRelativeURL:        Self { Self(_code: 5) }
  @inlinable internal static var relativeURLMissingBeginningSolidus: Self { Self(_code: 6) }
  @inlinable internal static var unexpectedReverseSolidus:           Self { Self(_code: 7) }
  @inlinable internal static var missingSolidusBeforeAuthority:      Self { Self(_code: 8) }
  @inlinable internal static var unexpectedCommercialAt:             Self { Self(_code: 9) }
  @inlinable internal static var unexpectedCredentialsWithoutHost:   Self { Self(_code: 10) }
  @inlinable internal static var unexpectedPortWithoutHost:          Self { Self(_code: 11) }
  @inlinable internal static var emptyHostSpecialScheme:             Self { Self(_code: 12) }
  @inlinable internal static var hostInvalid:                        Self { Self(_code: 13) }
  @inlinable internal static var portOutOfRange:                     Self { Self(_code: 14) }
  @inlinable internal static var portInvalid:                        Self { Self(_code: 15) }
  @inlinable internal static var unexpectedWindowsDriveLetter:       Self { Self(_code: 16) }
  @inlinable internal static var unexpectedWindowsDriveLetterHost:   Self { Self(_code: 17) }
  @inlinable internal static var invalidURLCodePoint:                Self { Self(_code: 18) }
  @inlinable internal static var unescapedPercentSign:               Self { Self(_code: 19) }
  @inlinable internal static var unclosedIPv6Address:                Self { Self(_code: 20) }
  @inlinable internal static var domainToASCIIFailure:               Self { Self(_code: 21) }
  @inlinable internal static var domainToASCIIEmptyDomainFailure:    Self { Self(_code: 22) }
  @inlinable internal static var hostOrDomainForbiddenCodePoint:     Self { Self(_code: 23) }
  @inlinable internal static var invalidIPv6Address:                 Self { Self(_code: 24) }
  @inlinable internal static var invalidIPv4Address:                 Self { Self(_code: 25) }
  // This one is not in the standard.
  @inlinable internal static var _invalidUTF8:                       Self { Self(_code: 99) }
}

// swift-format-ignore
#if DEBUG
extension ValidationError: CustomStringConvertible {

	@usableFromInline
  internal var description: String {
    switch self {
    case .unexpectedC0ControlOrSpace:
      return #"""
        The input to the URL parser contains a leading or trailing C0 control or space.
        The URL parser subsequently strips any matching code points.

        Example: " https://example.org "
        """#
    case .unexpectedASCIITabOrNewline:
      return #"""
        The input to the URL parser contains ASCII tab or newlines.
        The URL parser subsequently strips any matching code points.

        Example: "ht
        tps://example.org"
        """#
    case .invalidSchemeStart:
      return #"""
        The first code point of a URL’s scheme is not an ASCII alpha.

        Example: "3ttps://example.org"
        """#
    case .fileSchemeMissingFollowingSolidus:
      return #"""
        The URL parser encounters a URL with a "file" scheme that is not followed by "//".

        Example: "file:c:/my-secret-folder"
        """#
    case .invalidScheme:
      return #"""
        The URL’s scheme contains an invalid code point.

        Example: "^_^://example.org" and "https//example.org"
        """#
    case .missingSchemeNonRelativeURL:
      return #"""
        The input is missing a scheme, because it does not begin with an ASCII alpha,
        and either no base URL was provided or the base URL cannot be used as a base URL
        because it has an opaque path.

        Example (Input’s scheme is missing and no base URL is given):
        (url, base) = ("💩", nil)

        Example (Input’s scheme is missing, but the base URL has an opaque path):
        (url, base) = ("💩", "mailto:user@example.org")
        """#
    case .relativeURLMissingBeginningSolidus:
      return #"""
        The input is a relative-URL String that does not begin with U+002F (/).

        Example: (url, base) = ("foo.html", "https://example.org/")
        """#
    case .unexpectedReverseSolidus:
      return #"""
        The URL has a special scheme and it uses U+005C (\) instead of U+002F (/).

        Example: "https://example.org\path\to\file"
        """#
    case .missingSolidusBeforeAuthority:
      return #"""
        The URL includes credentials that are not preceded by "//".

        Example: "https:user@example.org"
        """#
    case .unexpectedCommercialAt:
      return #"""
        The URL includes credentials, however this is considered invalid.

        Example: "https://user@example.org"
        """#
    case .unexpectedCredentialsWithoutHost:
      return #"""
        A U+0040 (@) is found between the URL’s scheme and host, but the URL does not include credentials.

        Example: "https://@example.org"
        """#
    case .unexpectedPortWithoutHost:
      return #"""
        The URL contains a port, but no host.

        Example: "https://:443"
        """#
    case .emptyHostSpecialScheme:
      return #"""
        The URL has a special scheme, but does not contain a host.

        Example: "https://#fragment"
        """#
  	// TODO: This description could be improved.
    case .hostInvalid:
      return #"""
        The host portion of the URL is an empty string when it includes credentials or a port and the basic URL parser’s state is overridden.

        Example:
          var url = WebURL("https://example:9000")!
          url.hostname = ""
        """#
    case .portOutOfRange:
      return #"""
        The input’s port is too big.

        Example: "https://example.org:70000"
        """#
    case .portInvalid:
      return #"""
        The input’s port is invalid.

        Example: "https://example.org:7z"
        """#
    case .unexpectedWindowsDriveLetter:
      return #"""
        The input is a relative-URL string that starts with a Windows drive letter and the base URL’s scheme is "file".

        Example: (url, base) = ("/c:/path/to/file", "file:///c:/")
        """#
    case .unexpectedWindowsDriveLetterHost:
      return #"""
        The file URL’s host is a Windows drive letter.

        Example: "file://c:"
        """#
    case .invalidURLCodePoint:
      return #"""
        A code point is found that is not a URL code point or U+0025 (%), in the URL’s path, query, or fragment.

        Example: "https://example.org/>"
        """#
    case .unescapedPercentSign:
      return #"""
        A U+0025 (%) is found that is not followed by two ASCII hex digits, in the URL’s path, query, or fragment.

        Example: "https://example.org/%s"
        """#
    case .unclosedIPv6Address:
      return #"""
        An IPv6 address is missing the closing U+005D (]).

        Example: "https://[::1"
        """#
    case .domainToASCIIFailure:
      return #"""
        The URL's domain contains non-ASCII characters, and IDNA processing failed.

        Note: For the time being, WebURL does not support non-ASCII domains.
        """#
    case .domainToASCIIEmptyDomainFailure:
      return #"""
        The URL's domain contains non-ASCII characters, and IDNA processing returned an empty string.

        This can be caused by many things, such as the domain consisting only of ignorable code points,
        or if the domain is the string "xn--".
        """#
    case .hostOrDomainForbiddenCodePoint:
      return #"""
        The input’s host or domain contains a forbidden code point. Note that hosts are percent-decoded before
        being processed when the URL's scheme is special, which would result in the following URL having a hostname
        of "exa#mple.org" (which contains the forbidden host code point "#").

        Example: "https://exa%23mple.org"
        """#
    case .invalidIPv6Address:
      return #"""
        The URL's domain an invalid IPv6 address.

        Example: "https://[:::]/"
        Example: "https://[::hello]/"
        """#
    case .invalidIPv4Address:
      return #"""
        The URL's domain an invalid IPv4 address.

        Example: "https://999999999999999/"
        Example: "https://300.300.300.300/"
        """#
    // non-spec.
    case ._invalidUTF8:
      return #"""
        The given input is not a valid sequence of UTF-8 code-units.
        """#
		// fallback.
    default:
      return "Internal error: \(_code)"
    }
  }
}
#endif
