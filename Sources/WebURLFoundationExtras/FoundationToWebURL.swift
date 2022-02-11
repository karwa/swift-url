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
//    - Percent-encoding may be added. [Compatible with RFC-2396: 😩 (kind of)]
//
//      > A URI is always in an "escaped" form, since escaping or unescaping a
//      > completed URI might change its semantics.  Normally, the only time
//      > escape encodings can safely be made is when the URI is being created
//      > from its component parts; each component may have its own set of
//      > characters that are reserved, so only the mechanism responsible for
//      > generating or interpreting that component can determine whether or
//      > not escaping a character will change its semantics.
//      https://datatracker.ietf.org/doc/html/rfc2396#section-2.4.2
//
//      This means it is not possible to say, in general, whether escaping or unescaping a component
//      will change its semantics; only the software creating or interpreting it can say for sure.
//      Luckily, the WHATWG URL Standard is very tolerant of non-encoded characters, and only
//      adds percent-encoding to the following characters:
//
//      - < "=" | ";" > in the user-info section.
//
//        RFC-2396 allows these to be unescaped, the WHATWG model doesn't. ❌
//        That's a real difference, but we allow it since the username and password are officially deprecated,
//        and it's too difficult to handle without better APIs on Foundation.URL.
//
//      _ < "'" > in the query of URLs with a special scheme (http/s, ws/s, ftp, file).
//
//        The apostrophe/single-quote is an unreserved character, which means we are allowed to escape
//        it if needed:
//
//        > Unreserved characters can be escaped without changing the semantics
//        > of the URI, but this should not be done unless the URI is being used
//        > in a context that does not allow the unescaped character to appear.
//        https://datatracker.ietf.org/doc/html/rfc2396#section-2.3
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
//      This is potentially a meaningful difference (🤷‍♂️). The hostname "hello.0a" is presumably invalid
//      by RFC-2396, since its final label starts with a digit, but clearly it is _not_ a valid IPv4 address.
//      The WHATWG URL Standard considers this a valid domain.
//
//      We opt to allow these, for 3 reasons:
//
//      1. RFC-2396 considers it invalid anyway.
//
//         This difference would not allow "hello.0a" or "127.0.0.1foo" to be considered IPv4 addresses.
//
//      2. RFC-1123 (referenced by RFC-2396) appears to (perhaps, technically) allow it.
//
//         RFC-1123 says that any domain label is allowed to be purely numeric, and mentions in a discussion section
//         that the TLD "will be alphabetic", but discussion sections "contain[s] suggested approaches that
//         an implementor may want to consider" and so appear to be informative rather than normative.
//         https://datatracker.ietf.org/doc/html/rfc1123#section-2
//
//      3. It appears to be compatible with RFC-3986 (✅), which does not mention using the final label
//         to distinguish the kind of host:
//
//         >    host        = IP-literal / IPv4address / reg-name
//         >
//         > The syntax rule for host is ambiguous because it does not completely
//         > distinguish between an IPv4address and a reg-name.  In order to
//         > disambiguate the syntax, we apply the "first-match-wins" algorithm:
//         > If host matches the rule for IPv4address, then it should be
//         > considered an IPv4 address literal and not a reg-name.
//         https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2
//
//         Since this only applies to http(s), ws(s), ftp and file URLs, and the HTTP/WS standards
//         all reference RFC-3986 rather than RFC-2396, it appears safe to use the WHATWG interpretation.
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
  /// When converting between `Foundation.URL` and `WebURL`, the URL strings and components are verified
  /// as equivalent, although they may not be identical. Conversion from Foundation to WebURL requires
  /// normalization - such as canonicalizing obscure IP addresses, or simplifying the path.
  /// This is necessary because they conform to different URL standards.
  ///
  /// If the given Foundation URL was previously created from a `WebURL`, it should already be normalized,
  /// and will _round-trip_ to an identical `WebURL` as was used to create it. See WebURL's `.encodedForFoundation`
  /// property for more information about round-tripping.
  ///
  /// The vast majority of `URL`s from Foundation can be converted, but there are some exceptions.
  /// In particular, the URL must be have a scheme (such as `"https"`, `"file"`, or your own custom scheme),
  /// and schemes known to the URL Standard (such as http/s and file URLs) require some additional validation.
  ///
  /// - parameters:
  ///   - foundationURL: The URL to convert
  ///
  public init?(_ foundationURL: URL) {

    var _foundationString = foundationURL.absoluteString
    let equivalentWebURL = _foundationString.withUTF8 { foundationString -> WebURL? in
      guard
        let webURL = WebURL(utf8: foundationString),
        WebURL._SPIs._checkEquivalence_f2w(webURL, foundationURL, foundationString: foundationString, shortcuts: true)
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
  /// This function is designed to check Foundation to WebURL conversions.
  /// As such, neither the URL string nor its components are required to be identical between the two URLs;
  /// certain kinds of normalization that are required by the WHATWG URL Standard are allowed if
  /// they are considered compatible with RFC-2396 (the standard Foundation's URL conforms to).
  ///
  /// If `shortcuts` is `true`, this function takes steps to avoid checking each individual component.
  /// For example, if Foundation's URL string does not contain a `"@"` character anywhere, it is assumed
  /// that Foundation's URL will not return a username or password, and we can simply check that `webURL` agrees
  /// rather than actually calling getter for those components (as they are very expensive, even if the value is nil).
  ///
  /// These shortcuts are only safe if `webURL` has been parsed from `foundationURL.absoluteString`,
  /// and are verified by tests, including fuzz-testing. If shortcuts is `false`, every component is checked
  /// and this function makes no assumptions that the two URLs are related at all.
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
  public static func _checkEquivalence_f2w(
    _ webURL: WebURL, _ foundationURL: URL, foundationString: UnsafeBufferPointer<UInt8>, shortcuts: Bool
  ) -> Bool {

    // Scheme:

    guard
      foundationURL.scheme?.lowercased()._withContiguousUTF8({ webURL.utf8.scheme.fastElementsEqual($0) }) == true
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
      guard checkUserInfoEquivalence_f2w(webURL, foundationURL) else {
        return false
      }
    }

    // Host:

    let foundationHost = foundationURL.host
    let hostOK = foundationHost._withContiguousUTF8 { foundationHostUTF8 -> Bool in
      switch webURL._spis._utf8_host {
      case .ipv6Address(let webURLAddr):
        return foundationHostUTF8.flatMap(IPv6Address.init(utf8:)).flatMap { fastEquals(webURLAddr, $0) } ?? false
      case .ipv4Address(let webURLAddr):
        return foundationHostUTF8.flatMap(IPv4Address.init(utf8:)).flatMap { fastEquals(webURLAddr, $0) } ?? false
      case .domain(let webURLHost):
        // This is lowercasing the string, because we don't have a case-insensitive ASCII bytes comparison function.
        return foundationHost.flatMap { webURLHost.fastElementsEqual($0.lowercased().utf8) } ?? false
      case .opaque(let webURLHostname):
        return foundationHostUTF8.flatMap { webURLHostname.lazy.percentDecoded().fastElementsEqual($0) } ?? false
      case .empty:
        // Foundation.URL.host returns nil for empty hostnames.
        return foundationHost == nil
      case .none:
        return foundationHost == nil
      }
    }
    guard hostOK else { return false }

    // Port:

    switch (webURL.port, foundationURL.port) {
    case (.some(let webURLPort), .some(let foundationPort)):
      guard webURLPort == foundationPort else {
        return false
      }
    case (.none, .none):
      break
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
      guard checkPathEquivalenceUsingURLComponents_f2w(webURL, foundationURL) else {
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
          if webURL._spis._isSpecial, foundationQuery.fastContains(UInt8(ascii: "'")) {
            let encodedFoundationQuery = foundationQuery.lazy.percentEncoded(using: SpecialQueryExtras())
            return webURLQuery.fastElementsEqual(encodedFoundationQuery)
          } else {
            return webURLQuery.fastElementsEqual(foundationQuery)
          }
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
  /// This function is deliberately outlined from `_checkEquivalence_f2w`.
  ///
  @inline(never)
  private static func checkUserInfoEquivalence_f2w(_ webURL: WebURL, _ foundationURL: URL) -> Bool {

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
        let encodedFoundationPassword = foundationPassword.lazy.percentEncoded(using: UserInfoExtras())
        return webURLPassword.fastElementsEqual(encodedFoundationPassword)
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
  /// This function uses WebURL to simplify the raw path as given by URLComponents, assuming that this
  /// simplification preserves equivalence, so in effect it is only checking that WebURL and URLComponents
  /// agree about which part of the URL string contains the path.
  ///
  /// This function is deliberately outlined from `_checkEquivalence_f2w`.
  ///
  @inline(never)
  private static func checkPathEquivalenceUsingURLComponents_f2w(_ webURL: WebURL, _ foundationURL: URL) -> Bool {

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
