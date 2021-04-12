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

/// An object which is informed by the URL parser if a validation error occurs.
///
/// Most validation errors are non-fatal and parsing can continue regardless. If parsing fails, the last
/// validation error typically describes the issue which caused it to fail.
///
@usableFromInline
protocol URLParserCallback {
  mutating func validationError(_ error: ValidationError)
}

/// A `URLParserCallback` which simply ignores all validation errors.
///
@usableFromInline
struct IgnoreValidationErrors: URLParserCallback {
  @inlinable @inline(__always) init() {}
  @inlinable @inline(__always) mutating func validationError(_ error: ValidationError) {}
}

/// A `URLParserCallback` which stores the last reported validation error.
///
@usableFromInline
struct LastValidationError: URLParserCallback {
  @usableFromInline var error: ValidationError?
  @inlinable @inline(__always) init() {}
  @inlinable @inline(__always) mutating func validationError(_ error: ValidationError) {
    self.error = error
  }
}

/// A `URLParserCallback` which stores all reported validation errors in an `Array`.
///
@usableFromInline
struct CollectValidationErrors: URLParserCallback {
  @usableFromInline var errors: [ValidationError] = []
  @inlinable @inline(__always) init() { errors.reserveCapacity(8) }
  @inlinable @inline(__always) mutating func validationError(_ error: ValidationError) {
    errors.append(error)
  }
}

@usableFromInline
struct ValidationError: Equatable {
  private var code: UInt8
}

// Parser errors and descriptions.
// swift-format-ignore
extension ValidationError: CustomStringConvertible {

  // Named errors and their descriptions/examples taken from:
  // https://github.com/whatwg/url/pull/502 on 15.06.2020
  internal static var unexpectedC0ControlOrSpace:         Self { Self(code: 0) }
  internal static var unexpectedASCIITabOrNewline:        Self { Self(code: 1) }
  internal static var invalidSchemeStart:                 Self { Self(code: 2) }
  internal static var fileSchemeMissingFollowingSolidus:  Self { Self(code: 3) }
  internal static var invalidScheme:                      Self { Self(code: 4) }
  internal static var missingSchemeNonRelativeURL:        Self { Self(code: 5) }
  internal static var relativeURLMissingBeginningSolidus: Self { Self(code: 6) }
  internal static var unexpectedReverseSolidus:           Self { Self(code: 7) }
  internal static var missingSolidusBeforeAuthority:      Self { Self(code: 8) }
  internal static var unexpectedCommercialAt:             Self { Self(code: 9) }
  internal static var unexpectedCredentialsWithoutHost:   Self { Self(code: 10) }
  internal static var unexpectedPortWithoutHost:          Self { Self(code: 11) }
  internal static var emptyHostSpecialScheme:             Self { Self(code: 12) }
  internal static var hostInvalid:                        Self { Self(code: 13) }
  internal static var portOutOfRange:                     Self { Self(code: 14) }
  internal static var portInvalid:                        Self { Self(code: 15) }
  internal static var unexpectedWindowsDriveLetter:       Self { Self(code: 16) }
  internal static var unexpectedWindowsDriveLetterHost:   Self { Self(code: 17) }
  internal static var unexpectedHostFileScheme:           Self { Self(code: 18) }
  internal static var unexpectedEmptyPath:                Self { Self(code: 19) }
  internal static var invalidURLCodePoint:                Self { Self(code: 20) }
  internal static var unescapedPercentSign:               Self { Self(code: 21) }
  // FIXME: lacking descriptions.
  internal static var unclosedIPv6Address:                Self { Self(code: 22) }
  internal static var domainToASCIIFailure:               Self { Self(code: 23) }
  internal static var domainToASCIIEmptyDomainFailure:    Self { Self(code: 24) }
  internal static var hostForbiddenCodePoint:             Self { Self(code: 25) }
  internal static var invalidIPv6Address:                 Self { Self(code: 26) }
  internal static var invalidIPv4Address:                 Self { Self(code: 27) }
  // This one is not in the spec.
  internal static var _baseURLRequired:                   Self { Self(code: 99) }
  internal static var _invalidUTF8:                       Self { Self(code: 98) }


  public var description: String {
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
        because its cannot-be-a-base-URL flag is set.

        Example (Input’s scheme is missing and no base URL is given):
        (url, base) = ("💩", nil)

        Example (Input’s scheme is missing, but the base URL’s cannot-be-a-base-URL flag is set):
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
    case .hostInvalid:
      return #"""
        The host portion of the URL is an empty string when it includes credentials or a port and the basic URL parser’s state is overridden.

        Example:
          var url = WebURL("https://example:9000")!.jsModel
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
    case .unexpectedHostFileScheme:
      return #"""
        The URL’s scheme is changed to "file" and the existing URL has a host.

        Example:
          var url = WebURL("https://example.org")!.jsModel
          url.scheme = "file"
        """#
    case .unexpectedEmptyPath:
      return #"""
        The URL’s scheme is "file" and it contains an empty path segment.

        Example: "file:///c:/path//to/file"
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
    case ._baseURLRequired:
      return #"""
        A base URL is required.
        """#
    default:
      return "??"
    }
  }
}
