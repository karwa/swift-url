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
//
// Converting between URL standards is a delicate business, with important security considerations.
// These implementation notes contain a detailed analysis (with citations) describing how WebURL
// approaches converting a Foundation.URL value to its own model.
//
//
// ### 1. Introduction
//
//
//    Let's say we have a Foundation.URL, and parse its URL string using WebURL, and it succeeds.
//    Surely, the resulting WebURL must be equivalent to the Foundation.URL source, right? Well, no.
//    When comparing across different standards, the same URL string might be interpreted differently
//    and point to different resources. That is just an inherent consequence of these types conforming
//    to different URL standards, and having functionally different parsers. For example:
//
//    "https:///apple.com"
//      - Foundation sees { hostname: ""         , path: "/apple.com"   }
//      - WebURL sees     { hostname: "apple.com", path: "/" (implicit) }
//
//      Reason: The WHATWG URL standard is lenient about duplicate slashes for certain schemes.
//
//    "http://@hello:@world"
//      - Foundation sees { username: ""      , password: "", hostname: "hello" }
//      - WebURL sees     { username: "@hello", password: "", hostname: "world" }
//
//      Reason: Foundation considers the _first_ "@" to be the userinfo/hostname separator,
//              but the WHATWG URL Standard considers the _last_ "@" to be the separator.
//
//    We cannot say these URLs are equivalent, because the components are so different that a request
//    made using the resulting WebURL is not obviously equivalent to a request made using the Foundation.URL
//    we started with. Allowing either of these URLs to convert successfully would therefore be a major security issue.
//
//    Not all of these are due to differences in the standard; some may be caused by bugs in Foundation
//    (if it was a bug in WebURL, we'd obviously fix it). Also, components do not necessarily need to be identical
//    to be considered equivalent; RFC-2396 (the standard Foundation conforms to) allows certain kinds of
//    normalization.
//
//    In other words, what we find is that:
//
//    - Equivalence must be based on the URL's components.
//
//    - The contents of the components are what **the API** reports, not what the standards say they should be.
//
//    - Given a component's content, we can however look to the standards to see which kinds of normalization
//      preserve semantic equivalence, and which do not.
//
//
// ### 2. Scheme-independent interpretation.
//
//
//    The WHATWG URL Standard interprets and normalizes components in the following ways,
//    independent of the URL's scheme.
//
//    Scheme:
//    - Normalized to lowercase. [Compatible with RFC-2396: ✅]
//
//      > Scheme names consist of a sequence of characters beginning with a
//      > lower case letter and followed by any combination of lower case
//      > letters, digits, plus ("+"), period ("."), or hyphen ("-").  For
//      > resiliency, programs interpreting URI should treat upper case letters
//      > as equivalent to lower case in scheme names (e.g., allow "HTTP" as
//      > well as "http")
//      https://datatracker.ietf.org/doc/html/rfc2396#section-3.1
//
//    Username and Password:
//    - Delimiters may be removed if components are empty. [Compatible with RFC-2396: ❌ (scheme-specific)]
//
//      The WHATWG URL Standard only removes delimiters for empty components in the userinfo section,
//      and not for any other components. RFC-2396 doesn't mention this at all, but its predecessor, RFC-1738,
//      says that it isn't generally valid:
//
//      > Note that an empty user name or password is different than no user
//      > name or password; there is no way to specify a password without
//      > specifying a user name. E.g., <URL:ftp://@host.com/> has an empty
//      > user name and no password, <URL:ftp://host.com/> has no user name,
//      > while <URL:ftp://foo:@host.com/> has a user name of "foo" and an
//      > empty password.
//      https://datatracker.ietf.org/doc/html/rfc1738#section-3.1
//
//      Its successor, RFC-3986, agrees and says that it is scheme-specific:
//
//      > Normalization should not remove delimiters when their associated
//      > component is empty unless licensed to do so by the scheme specification.
//      > [...] the presence or absence of delimiters within a userinfo subcomponent is
//      > usually significant to its interpretation.
//      https://datatracker.ietf.org/doc/html/rfc3986#section-6.2.3
//
//    Hostname:
//    - (Hostnames in the WHATWG URL Standard have a scheme-specific interpretation. It has its own section below)
//
//    Port:
//    - Default ports are omitted for known schemes. [Compatible with RFC-2396: ✅]
//
//      > The port is the network port number for the server.  Most schemes
//      > designate protocols that have a default port number.  Another port
//      > number may optionally be supplied, in decimal, separated from the
//      > host by a colon.  If the port is omitted, the default port number is
//      > assumed.
//      https://datatracker.ietf.org/doc/html/rfc2396#section-3.2.2
//
//    Path:
//    - "." and ".." components in the path will be simplified. [Compatible with RFC-2396: 🤷‍♂️][RFC-3986: ✅]
//
//      RFC-2396 does not mention "." or ".." components the description of the "path" component,
//      nor the "abspath" grammar definition. They are only referred to with respect to relative references:
//      - Section 5, "Relative URI References" <https://datatracker.ietf.org/doc/html/rfc2396#section-5>,
//      - Section 5.2, "Resolving Relative References to Absolute Form" <https://datatracker.ietf.org/doc/html/rfc2396#section-5.2>
//
//      However, if we look at its successor, RFC-3986, we find the following description of the "path" component:
//
//      > The path segments "." and "..", also known as dot-segments, are
//      > defined for relative reference within the path name hierarchy.  They
//      > are intended for use at the beginning of a relative-path reference
//      > (Section 4.2) to indicate relative position within the hierarchical
//      > tree of names. [...]
//      > Aside from dot-segments in hierarchical paths, a path segment is
//      > considered opaque by the generic syntax.
//      https://datatracker.ietf.org/doc/html/rfc3986#section-3.3
//
//      Moreover, resolving dot components in the path is explicitly described as a safe, non-scheme-specific
//      normalization procedure, and failing to do so is even described as being "incorrect":
//
//      > The complete path segments "." and ".." are intended only for use
//      > within relative references (Section 4.1) and are removed as part of
//      > the reference resolution process (Section 5.2).  However, some
//      > deployed implementations incorrectly assume that reference resolution
//      > is not necessary when the reference is already a URI and thus fail to
//      > remove dot-segments when they occur in non-relative paths.  URI
//      > normalizers should remove dot-segments by applying the
//      > remove_dot_segments algorithm to the path
//      https://datatracker.ietf.org/doc/html/rfc3986#section-6.2.2.3
//
//      So it looks like RFC-2396 under-specified this (it was never expressly forbidden, just not specified
//      in the context of absolute URLs), and RFC-3986 corrected it. Therefore, we're going to consider it safe.
//
//    Query and Fragment:
//    - (Have no standardized meaning. The WHATWG URL Standard does not specify any component-specific normalization)
//
//    All Components:
//    - Percent-encoding may be added. [Compatible with RFC-2396: ✅]
//
//      > Many URI include components consisting of or delimited by, certain
//      > special characters.  These characters are called "reserved", since
//      > their usage within the URI component is limited to their reserved
//      > purpose.  If the data for a URI component would conflict with the
//      > reserved purpose, then the conflicting data must be escaped before
//      > forming the URI.
//      >
//      > reserved = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" | "$" | ","
//      >
//      > The "reserved" syntax class above refers to those characters that are
//      > allowed within a URI, but which may not be allowed within a
//      > particular component of the generic URI syntax; they are used as
//      > delimiters of the components described in Section 3
//
//      > Unreserved characters can be escaped without changing the semantics of the URI
//      https://datatracker.ietf.org/doc/html/rfc2396#section-2.3
//
//      The WHATWG URL Standard does not generally remove percent-encoding (except in certain hostnames,
//      discussed later). It may add percent-encoding if its encode-set differs from RFC-2396, but that is
//      safe as long as the character is not being used in a delimiter position.
//
//      If it _did_ encode a character which was being used for its reserved purpose as a delimiter,
//      it follows that the set of components would no longer match.
//
//
// ### 3. Scheme-specific interpretation.
//
//
//    The WHATWG URL Standard includes particular parsing behaviors for known schemes ("special" schemes).
//
//    Path:
//    - Backslashes in the path are treated as path-segment separators. [Compatible with RFC-2396: ❌]
//
//      For some schemes, the WHATWG URL Standard considers backslashes in the path to be path separators.
//      This is not compatible with RFC-2396, but in this case we get lucky: backslashes are part of RFC-2396's
//      "unwise" character set and must be percent-encoded (and Foundation.URL enforces this):
//
//      > Other characters are excluded because gateways and other transport
//      > agents are known to sometimes modify such characters, or they are
//      > used as delimiters.
//      >
//      > unwise      = "{" | "}" | "|" | "\" | "^" | "[" | "]" | "`"
//      https://datatracker.ietf.org/doc/html/rfc2396#section-2.4.3
//
//      So whilst this behavior is technically not compatible with the older standard, we won't ever encounter it.
//
//    - Special handling of Windows drive letters in file URLs. [Compatible with RFC-2396: ❌]
//
//      The WHATWG URL Standard's method of simplifying paths includes scheme-specific compatibility quirks
//      for handling Windows drive letters in file URLs. This is obviously never specified by RFC-2396,
//      but given its limited scope, we consider it an acceptable deviation.
//
//      This is one of very few cases where we can't justify behavior using RFC-2396 or its peers,
//      and have to make a judgement call.
//
//
// ### 4. Hostnames
//
//
//    The WHATWG URL Standard interprets hostnames based on the URL's scheme:
//
//    - http(s), ws(s), ftp, and file URL hostnames can be domains, IPv4 addresses, or IPv6 addresses.
//    - Hostnames of other URLs may be IPv6 addresses, otherwise they are just opaque strings.
//
//    RFC-2396 recognizes 2 kinds of hostnames: registry-based, and server-based. IPv6 was added later.
//
//    Registry-based:
//
//      > The structure of a registry-based naming authority is specific to the
//      > URI scheme, but constrained to the allowed characters for an
//      > authority component.
//      https://datatracker.ietf.org/doc/html/rfc2396#section-3.2.1
//
//      Basically, this is what the WHATWG URL Standard calls an "opaque hostname".
//      They are not interpreted or normalized.
//
//    Server-based:
//
//      > URL schemes that involve the direct use of an IP-based protocol to a
//      > specified server on the Internet use a common syntax for the server
//      > component of the URI's scheme-specific data
//      > [...]
//      > The host is a domain name of a network host, or its IPv4 address as a
//      > set of four decimal digit groups separated by "."
//      > [...]
//      > Hostnames take the form described in Section 3 of [RFC1034] and
//      > Section 2.1 of [RFC1123]: a sequence of domain labels separated by
//      > ".", each domain label starting and ending with an alphanumeric
//      > character and possibly also containing "-" characters.  The rightmost
//      > domain label of a fully qualified domain name will never start with a
//      > digit, thus syntactically distinguishing domain names from IPv4
//      > addresses
//      https://datatracker.ietf.org/doc/html/rfc2396#section-3.2.2
//
//      This is very similar to the WHATWG URL Standard, except that for a hostname to be parsed
//      as an IPv4 address, the final label must _entirely_ consist of digits or be a hex number,
//      rather than just starting with an initial digit.
//
//      This is a meaningful difference (❌). The hostname "hello.0a" is presumably invalid by RFC-2396,
//      since its final label starts with a digit, but clearly it is _not_ a valid IPv4 address.
//      The WHATWG URL Standard considers this a valid domain, so these hostnames must be rejected.
//      https://github.com/whatwg/url/issues/679
//
//      Another potential difference is that the WHATWG URL Standard percent-decodes server-based hostnames
//      before interpreting them, whilst RFC-2396 appears to not allow percent-encoding in these hostnames.
//      It is difficult to decide what to do about this, but since Foundation.URL does not even expose
//      percent-encoded hostnames via its API, anybody performing their own hostname parsing (e.g. via `inet_pton`)
//      would arrive at the same result.
//
//      RFC-3986 _does_ allow percent-encoding here (it doesn't make a distinction between server/registry hosts),
//      although the ABNF appears to suggest that IPv4 literals may not include them. However, when discussing
//      syntax-based (non-scheme-specific) normalization, it also says:
//
//      > some URI producers percent-encode
//      > octets that do not require percent-encoding, resulting in URIs that
//      > are equivalent to their non-encoded counterparts.  These URIs should
//      > be normalized by decoding any percent-encoded octet that corresponds
//      > to an unreserved character
//      https://datatracker.ietf.org/doc/html/rfc3986#section-6.2.2.2
//
//      Which of course raises the question: what happens if a hostname, after percent-decoding, suddenly
//      becomes an IPv4 literal? Consider: "http://%3127%2e0%2e0%2e1/"; its hostname appears to contain a single label
//      which does start with a digit, yet when decoded, it becomes "http://127.0.0.1".
//      The only practical way around this is to percent-decode before interpreting the hostname; else this
//      apparently safe normalization would meaningfully alter the URL.
//
//      Again, this is a case where we need to make a judgement call. Given Foundation's API limitations,
//      it is impractical to do anything other than allowing these hostnames, and those same API limitations
//      mean it is unlikely to lead to issues in practice. The issues described above w.r.t RFC-3986 imply
//      that this may actually be the safer choice. But it is worth monitoring the situation,
//      because hostnames are particularly security-sensitive.
//
//    IPv6 Literals:
//
//      IPv6 literals were added in RFC-2732 <https://datatracker.ietf.org/doc/html/rfc2732>.
//      This RFC should technically only apply to server-based hostnames (meaning it would be limited to known schemes).
//      However, RFC-2396 forbids square brackets in hostnames, and 2732 says that it:
//
//      > allows the use of "[" and "]" within a URI explicitly
//      > for this reserved purpose
//
//      Meaning hostnames containing square brackets are not valid for any purpose other than IPv6 addresses.
//      We therefore consider it safe to interpret all hostnames in square brackets as IPv6 addresses, regardless
//      of scheme.
//
//    Which Schemes use Server-based Hostnames?
//
//      - FTP URLs are defined by RFC-1738 and use its "Common Internet Scheme Syntax",
//        which requires the hostname be a fully-qualified domain or IPv4 address.
//        https://datatracker.ietf.org/doc/html/rfc1738#section-3.2
//
//      - HTTP URLs were defined by RFC-1738 to also use the "Common Internet Scheme Syntax".
//        These days, the HTTP standard refers to RFC-3986, which recommends DNS syntax even
//        when DNS is not used as the resolution service.
//        https://datatracker.ietf.org/doc/html/rfc1738#section-3.3
//        https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2
//
//      - WS URLs emerged much later, and are defined by RFC-6455. Their host component also
//        refers to RDC-3986. In practice, it must use the same rules as HTTP URLs.
//        https://datatracker.ietf.org/doc/html/rfc6455#section-3
//
//      - File URLs are also defined by RFC-1738, which defines their hosts as being fully-qualified
//        domains. It was updated by RFC-8089, which kept the same wording. Neither mentions IPv4 addresses,
//        but since their syntax does not overlap, it seems safe to allow them.
//        https://datatracker.ietf.org/doc/html/rfc1738#section-3.10
//        https://datatracker.ietf.org/doc/html/rfc8089#section-2
//
//    So the classification used by the WHATWG URL Standard, in terms of which schemes use which kinds of hostnames,
//    and how those hostnames should be interpreted, appears to be mostly compatible with RFC-2396.
//    The most significant difference is in how IPv4 addresses are distinguished from domains.
//
//    Normalization:
//    - Domains are normalized to lowercase. [Compatible with RFC-2396: ✅]
//
//      > In many cases, different URI strings may actually identify the
//      > identical resource. For example, the host names used in URL are
//      > actually case insensitive, and the URL <http://www.XEROX.com> is
//      > equivalent to <http://www.xerox.com>. In general, the rules for
//      > equivalence and definition of a normal form, if any, are scheme
//      > dependent. When a scheme uses elements of the common syntax, it will
//      > also use the common syntax equivalence rules, namely that the scheme
//      > and hostname are case insensitive and a URL with an explicit ":port",
//      > where the port is the default for the scheme, is equivalent to one
//      > where the port is elided.
//      https://datatracker.ietf.org/doc/html/rfc2396#section-6
//
//      RFC-3986 agrees:
//      > When a URI uses components of the generic syntax, the component
//      > syntax equivalence rules always apply; namely, that the scheme and
//      > host are case-insensitive and therefore should be normalized to
//      > lowercase.  For example, the URI <HTTP://www.EXAMPLE.com/> is
//      > equivalent to <http://www.example.com/>.
//      https://datatracker.ietf.org/doc/html/rfc3986#section-6.2.2.1
//
//    - "localhost" is replaced with an empty host for file URLs. [Compatible with RFC-2396: ❌]
//
//      The RFCs say that "localhost" and an empty host are generally equivalent,
//      but that does not always make it safe to replace "localhost" with an empty host.
//      For example, on Windows, it can change the meaning of a URL which refers to a local UNC share.
//      https://github.com/whatwg/url/issues/618
//
//
// ### 5. API Limitations.
//
//
// Our ability to verify components is limited by Foundation's API. For example:
//
// - Many Foundation.URL component values are automatically percent-decoded,
//
// - In many cases, Foundation simply returns empty strings for its component values, even though these components
//   are obviously present in the absolute-string representation. These empty strings are even tested by Foundation!
//   So it seems intentional(?), despite clearly being wrong.
//
// One alternative that was attempted was to use URLComponents, which can solve some of these issues. However:
//
// - It is another URL parser, whose documentation admits it may have subtle differences to URL,
//   but does not specify those differences. This is about URL -> WebURL conversion, not URLComponents -> WebURL.
//   Going through another parser adds more uncertainty.
//
// - We have indeed found many examples where it does interpret a URL's components differently, including
//   some alarming implementation bugs. e.g. https://bugs.swift.org/browse/SR-15512
//
// So we have to relax things a little bit, while still verifying as much as we reasonably can.
//
// We won't allow any conversions to succeed if we can't at least verify the authority.
// This is similar to WebKit's approach, which, after it was exploited, moved to validate the origin for http(s) URLs:
// https://github.com/WebKit/WebKit/blob/85b14032e9c4f66c5a501d4074a861c7da0afaea/Source/WTF/wtf/cf/URLCF.cpp#L70
//
//
// ============ END ============


extension WebURL {

  /// Creates a `WebURL` that is equivalent to the given `URL` from Foundation.
  ///
  /// The resulting `WebURL` is normalized according to the requirements of the WHATWG URL Standard,
  /// and its components are verified to ensure that normalization is compatible with the RFC-2396
  /// interpretation of the URL (RFC-2396 is the standard Foundation's `URL` conforms to).
  ///
  /// The vast majority of `URL`s can be converted, but there are some exceptions.
  /// In particular, the URL must be absolute (with or without a `baseURL`), and some invalid http(s) URLs
  /// are deemed invalid by the WHATWG URL Standard.
  ///
  public init?(_ foundationURL: URL) {

    var _foundationString = foundationURL.absoluteString
    let equivalentWebURL = _foundationString.withUTF8 { foundationString -> WebURL? in
      guard
        let webURL = WebURL(utf8: foundationString),
        WebURL._SPIs._checkEquivalence(webURL, foundationURL, foundationString: foundationString, shortcuts: true)
      else {
        return nil
      }
      return webURL
    }

    guard let converted = equivalentWebURL else {
      return nil
    }
    self = converted
  }
}


// --------------------------------------------
// MARK: - URL Equivalence
// --------------------------------------------


extension WebURL._SPIs {

  /// Returns whether the given WebURL and Foundation.URL have an equivalent set of components.
  ///
  /// URL components are not required to have identical contents to be considered equivalent;
  /// certain kinds of normalization required by the WHATWG URL Standard are allowed if (and only if)
  /// they are compatible with RFC-2396.
  ///
  /// If `shortcuts` is `true`, this function takes steps to avoid checking each individual component.
  /// For example, if Foundation's URL string does not contain a `"@"` character anywhere, it is assumed
  /// that the URL does not contain a username or password, and we can simply check that `webURL` agrees
  /// rather than actually getting the components from Foundation (which is expensive, even if the value is nil).
  /// These shortcuts are only safe if `webURL` has been parsed from `foundationURL.absoluteString`,
  /// and are verified by tests, including fuzz-testing.
  ///
  /// - parameters:
  ///   - webURL:           A WebURL value to compare for equivalence.
  ///   - foundationURL:    A Foundation.URL value to compare for equivalence.
  ///   - foundationString: A buffer containing the UTF-8 contents of `foundationURL.absoluteString`.
  ///   - shortcuts:        Whether to allow shortcuts for faster equivalence checks.
  ///                       Only safe if `webURL` has been parsed from `foundationURL.absoluteString`.
  ///
  /// - returns: Whether `webURL` and `foundationURL` have an equivalent set of URL components.
  ///
  /// > Important:
  /// > This function is not considered part of WebURL's supported API.
  /// > Please **do not use** it. It may disappear, or its behavior may change, at any time.
  ///
  public static func _checkEquivalence(
    _ webURL: WebURL, _ foundationURL: URL, foundationString: UnsafeBufferPointer<UInt8>, shortcuts: Bool
  ) -> Bool {

    // Scheme:

    guard let foundationScheme = foundationURL.scheme,
      webURL.utf8.scheme.fastElementsEqual(foundationScheme.lowercased().utf8)
    else {
      return false
    }

    // Foundation.URLs with opaque paths (e.g. "mailto:") return nil/empty for all components except the scheme.
    // That said, they are surprisingly common, so we can't just reject them. Allow them without verification 😐.

    guard !webURL.hasOpaquePath else {
      return true
    }

    // [Shortcut] Quick Scan:
    // Getting components from Foundation is expensive, even if the component is 'nil'. So take a shortcut:
    // if a component's delimiter is not present anywhere in the URL string, the component is also not present.

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
      guard checkUserInfoEquivalence(webURL, foundationURL) else {
        return false
      }
    }

    // Host:

    var foundationHost = foundationURL.host
    foundationHost?.makeContiguousUTF8()
    switch webURL._spis._utf8_host {
    case .ipv6Address(let webURLAddr):
      guard let fndtnAddr = foundationHost.flatMap(IPv6Address.init(_:)), fastEquals(webURLAddr, fndtnAddr) else {
        return false
      }
    case .ipv4Address(let webURLAddr):
      guard let fndtnAddr = foundationHost.flatMap(IPv4Address.init(_:)), fastEquals(webURLAddr, fndtnAddr) else {
        return false
      }
    case .domain(let webURLHost):
      guard let foundationHost = foundationHost else {
        return false
      }
      // Reject domains whose last label starts with a digit. RFC-2396 says these are IPv4 addresses, not domains.
      var trimmedFoundationHost = foundationHost.utf8[...]
      if trimmedFoundationHost.last == UInt8(ascii: ".") {
        trimmedFoundationHost.removeLast()
      }
      if var lastLabelStart = trimmedFoundationHost.lastIndex(of: UInt8(ascii: ".")) {
        trimmedFoundationHost.formIndex(after: &lastLabelStart)
        let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        if lastLabelStart < trimmedFoundationHost.endIndex, digits.contains(trimmedFoundationHost[lastLabelStart]) {
          return false
        }
      }
      guard webURLHost.fastElementsEqual(foundationHost.lowercased().utf8) else {
        return false
      }
    case .opaque(let webURLHostname):
      guard let fndHost = foundationHost, webURLHostname.lazy.percentDecoded().fastElementsEqual(fndHost.utf8) else {
        return false
      }
    case .empty:
      // Foundation.URL.host returns nil for empty hostnames.
      // This also blocks "localhost" stripping for file URLs, which is not considered equivalence-preserving.
      guard foundationHost == nil else {
        return false
      }
    case .none:
      guard foundationHost == nil else {
        return false
      }
    }

    // Port:

    switch (webURL.port, foundationURL.port) {
    case (.none, .none):
      break
    case (.some(let webURLPort), .some(let foundationPort)):
      guard webURLPort == foundationPort else {
        return false
      }
    case (.none, .some(let foundationPort)):
      guard webURL.portOrKnownDefault == foundationPort else {
        return false
      }
    default:
      return false
    }

    // Path:
    // The path will be simplified, but that is compatible with RFC-2396 (probably; see notes above),
    // so the only thing we have to verify is whether WebURL and Foundation.URL agree about which
    // part of the URL string contains the path.
    //
    // Unfortunately, that is difficult to check directly, as Foundation.URL only returns percent-decoded paths.
    // We can sometimes overcome it by using URLComponents, but the conversion is expensive and unreliable.

    // [Shortcut] Skip Path:
    // Since we have verified all components preceding the path, if we also verify the component following the path
    // (or reach the end of the string), we may infer that WebURL and Foundation.URL agree about which part
    // of the URL string was the URL's path component.

    if !shortcuts {
      guard checkPathEquivalenceUsingURLComponents(webURL, foundationURL) else {
        return false
      }
    }

    // Query:

    var queryIsPresent = false

    if assumeNoQuery {
      assert(shortcuts)
      guard webURL.utf8.query == nil else {
        return false
      }
    } else {
      switch (webURL.utf8.query, foundationURL.query) {
      case (.none, .none):
        break
      case (.some(let webURLQuery), .some(var foundationQuery)):
        queryIsPresent = true
        foundationQuery.makeContiguousUTF8()
        if webURL._spis._isSpecial, foundationQuery.utf8.fastContains(UInt8(ascii: "'")) {
          let encodedFoundationQuery = foundationQuery.utf8.lazy.percentEncoded(using: SpecialQueryExtras())
          guard webURLQuery.fastElementsEqual(encodedFoundationQuery) else {
            return false
          }
        } else {
          guard webURLQuery.fastElementsEqual(foundationQuery.utf8) else {
            return false
          }
        }
      default:
        return false
      }
    }

    // [Shortcut] Skip Fragment:
    // If we have seen and verified a query component, that serves to verify the path, and implies that
    // WebURL and Foundation.URL also agree about which part of the string contains the URL's fragment.

    guard !queryIsPresent || !shortcuts else {
      return true
    }

    // Fragment:

    if assumeNoFragment {
      assert(shortcuts)
      guard webURL.utf8.fragment == nil else {
        return false
      }
    } else {
      switch (webURL.utf8.fragment, foundationURL.fragment) {
      case (.none, .none):
        break
      case (.some(let webURLFragment), .some(let foundationFragment)):
        guard webURLFragment.fastElementsEqual(foundationFragment.utf8) else {
          return false
        }
      default:
        return false
      }
    }

    // All Checks Passed. The URLs appear to contain equivalent components.
    return true
  }

  /// Returns whether the given WebURL and Foundation.URL have an equivalent set of user-info components.
  ///
  /// This function is deliberately outlined from `_checkEquivalence`.
  ///
  @inline(never)
  private static func checkUserInfoEquivalence(_ webURL: WebURL, _ foundationURL: URL) -> Bool {

    // Username:

    // If a URL has no username but does have a password (e.g. "http://:password@host/"),
    // Foundation returns that the username is empty, but WebURL returns nil.
    // That's a safe difference, but only if both agree that a password is present.
    var emptyUsernameRequiresPasswordCheck = false

    switch (webURL.utf8.username, foundationURL.user) {
    case (.none, .none):
      break
    case (.some(let webURLUsername), .some(let foundationUsername)):
      guard webURLUsername.lazy.percentDecoded().fastElementsEqual(foundationUsername.utf8) else {
        return false
      }
    case (.none, .some(let foundationUsername)):
      guard foundationUsername.isEmpty else {
        return false
      }
      emptyUsernameRequiresPasswordCheck = true
    default:
      return false
    }

    // Password:
    // The NSURL Swift overlay has an extraordinarily inefficient implementation for the password getter,
    // involving writing the *entire URL string* to an Array, and constructing a String from the relevant slice.
    // Unfortunately, Foundation has a lot of bugs involving user-info components, so we can't take any shortcuts:
    // - https://bugs.swift.org/browse/SR-15513
    // - https://bugs.swift.org/browse/SR-15738

    switch (webURL.utf8.password, foundationURL.password) {
    case (.none, .none):
      break
    case (.some(let webURLPassword), .some(let foundationPassword)):
      let encodedFoundationPassword = foundationPassword.utf8.lazy.percentEncoded(using: UserInfoExtras())
      guard webURLPassword.fastElementsEqual(encodedFoundationPassword) else {
        return false
      }
      emptyUsernameRequiresPasswordCheck = false
    default:
      return false
    }

    guard !emptyUsernameRequiresPasswordCheck else {
      return false
    }

    return true
  }

  /// Returns whether the given WebURL and Foundation.URL (as interpreted by URLComponents) have an equivalent path,
  /// although it is not possible to verify in all circumstances.
  ///
  /// This function uses WebURL to simplify the raw path as given by URLComponents, assuming that this
  /// simplification preserves equivalence, so in effect it is only checking that WebURL and URLComponents
  /// agree about which part of the URL string contains the path.
  ///
  @inline(never)
  private static func checkPathEquivalenceUsingURLComponents(_ webURL: WebURL, _ foundationURL: URL) -> Bool {

    guard let fndRawPath = URLComponents(url: foundationURL, resolvingAgainstBaseURL: true)?.percentEncodedPath else {
      return true  // Unable to validate.
    }
    guard !fndRawPath.isEmpty, !fndRawPath.utf8.lazy.percentDecoded().fastContains(UInt8(ascii: ";")) else {
      return true  // Unable to validate.
    }
    guard !fndRawPath.utf8.fastContains(UInt8(ascii: "\\")) else {
      return false  // Should not be present.
    }
    return webURL._spis._simplifyPath(fndRawPath[...]).fastElementsEqual(webURL.utf8.path)
  }
}


// --------------------------------------------
// MARK: - PercentEncodeSets
// --------------------------------------------


/// A `PercentEncodeSet` containing characters encoded by WebURL's user-info encode-set,
/// but not Foundation's `urlUserAllowed` or `urlPasswordAllowed` sets.
///
internal struct UserInfoExtras: PercentEncodeSet {
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    codePoint == UInt8(ascii: ";") || codePoint == UInt8(ascii: "=")
  }
}

/// A `PercentEncodeSet` containing characters encoded by WebURL's 'special query' set,
/// but not the regular 'query' or Foundation's `urlQueryAllowed` sets.
///
internal struct SpecialQueryExtras: PercentEncodeSet {
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    codePoint == UInt8(ascii: "'")
  }
}
