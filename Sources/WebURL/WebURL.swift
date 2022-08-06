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

/// A Uniform Resource Locator (URL) is a universal identifier,
/// which often describes the location of a resource.
///
public struct WebURL {

  @usableFromInline
  internal var storage: URLStorage

  @inlinable
  internal init(storage: URLStorage) {
    self.storage = storage
  }

  /// Create a URL from a string.
  ///
  /// Strings are parsed according to the [WHATWG URL Standard][URL-spec], which is the standard
  /// used by modern web browsers. It has excellent compatibility with real-world URLs as seen across the web.
  ///
  /// Strings must contain an absolute URL (meaning they must include a scheme),
  /// but the parser is forgiving and will repair many ill-formatted URLs if it can understand them.
  ///
  /// ```swift
  /// WebURL("https://github.com/karwa/swift-url") // ✅ Typical HTTPS URL.
  /// WebURL("file:///usr/bin/swift")              // ✅ Typical file URL.
  /// WebURL("my.app:/settings/language?debug")    // ✅ Typical custom URL.
  /// WebURL("https://🦆.example.com/?search=😀")  // ✅ Encoded as needed.
  ///
  /// WebURL("invalid")         // ❌ No scheme.
  /// WebURL("/usr/bin/swift")  // ❌ No scheme.
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/resolve(_:)``
  ///
  /// [URL-spec]: https://url.spec.whatwg.org/
  ///
  @inlinable @inline(__always)
  public init?<StringType>(_ string: StringType) where StringType: StringProtocol {
    if let result = string._withContiguousUTF8({ WebURL(utf8: $0) }) {
      self = result
    } else {
      return nil
    }
  }

  /// Create a URL from a string, expressed as UTF-8 bytes.
  ///
  /// This initializer parses a URL from UTF-8 bytes, including those stored in other containers than `String`.
  /// This initializer uses precisely the same parsing algorithm as ``init(_:)``, so the bytes must contain
  /// an absolute URL string.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object,
  /// and parsing each line as a URL directly from the binary data. Doing this can reduce overheads
  /// in applications which process large numbers of URLs.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize directly from bytes.
  ///   let url = WebURL(utf8: lineBytes)
  ///   ...
  /// }
  /// ```
  ///
  /// The given bytes are assumed to be valid UTF-8, and otherwise-valid URLs containing invalid UTF-8
  /// are not guaranteed to fail. For most URL components, all non-ASCII bytes are opaque and will be preserved
  /// in the resulting URL string by percent-encoding, but some components may perform Unicode processing and thus
  /// may reject invalid UTF-8.
  ///
  /// ## See Also
  ///
  /// - ``UTF8View/resolve(_:)``
  ///
  @inlinable @inline(__always)
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    guard let url = urlFromBytes(utf8, baseURL: nil) else { return nil }
    self = url
  }

  /// Resolves a relative reference, with this as the base URL.
  ///
  /// Relative references allow resources to be specified with respect to an origin, or _base URL_.
  ///
  /// Links in HTML documents, such as `<img src="cat.png">`, or `<a href="../photos">`,
  /// are relative references, which are resolved against the URL of the page they are on.
  /// You can also use relative references in your own applications, and with your own URL schemes.
  ///
  /// ```swift
  /// let base = WebURL("https://github.com/karwa/swift-url/")!
  ///
  /// base.resolve("pulls/39")            // ✅ "https://github.com/karwa/swift-url/pulls/39"
  /// base.resolve("/apple/swift/")       // ✅ "https://github.com/apple/swift/"
  /// base.resolve("..?tab=repositories") // ✅ "https://github.com/karwa/?tab=repositories"
  /// ```
  ///
  /// The references supported by this parser are defined in the [WHATWG URL Standard][URL-spec].
  ///
  /// > Note:
  /// >
  /// > Although _specified_ relative to a base URL, references are able to change any component of the result,
  /// > including its hostname and even scheme. This can result in URLs with a different ``origin-swift.property``
  /// > to the base URL. Be mindful of this if URLs are used to calculate domains of trust over resources.
  /// >
  /// > ```swift
  /// > let base = WebURL("https://github.com/karwa/swift-url/")!
  /// >
  /// > base.resolve("//evil.com/boo")
  /// > // ❗️ "https://evil.com/boo"
  /// > //            ^^^^^^^^ - hostname changed
  /// >
  /// > base.resolve("http://evil.com/boo")
  /// > // ❗️ "http://evil.com/boo"
  /// > //     ^^^^   ^^^^^^^^ - scheme and hostname changed
  /// > ```
  ///
  /// [URL-spec]: https://url.spec.whatwg.org/#url-writing
  ///
  @inlinable @inline(__always)
  public func resolve<StringType>(_ string: StringType) -> WebURL? where StringType: StringProtocol {
    string._withContiguousUTF8 { utf8.resolve($0) }
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL: Equatable, Hashable, Comparable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.utf8.withUnsafeBufferPointer { lhsBuffer in
      rhs.utf8.withUnsafeBufferPointer { rhsBuffer in
        lhsBuffer.count == rhsBuffer.count
          && (lhsBuffer.baseAddress == rhsBuffer.baseAddress || lhsBuffer.elementsEqual(rhsBuffer))
      }
    }
  }

  public func hash(into hasher: inout Hasher) {
    utf8.withUnsafeBufferPointer { buffer in
      hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.utf8.withUnsafeBufferPointer { lhsBuffer in
      rhs.utf8.withUnsafeBufferPointer { rhsBuffer in
        lhsBuffer.lexicographicallyPrecedes(rhsBuffer)
      }
    }
  }
}

extension WebURL: CustomStringConvertible, LosslessStringConvertible {

  public var description: String {
    serialized()
  }
}

extension WebURL: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let decoded = WebURL(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid URL")
    }
    self = decoded
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serialized())
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL: Sendable {}
#endif


// --------------------------------------------
// MARK: - Properties
// --------------------------------------------


extension WebURL {

  // Required by the parser.
  @inlinable
  internal var schemeKind: WebURL.SchemeKind {
    storage.structure.schemeKind
  }

  @inlinable
  internal var hostKind: HostKind? {
    storage.structure.hostKind
  }
}

extension WebURL {

  /// Returns the string representation of this URL.
  ///
  /// The serialization of a URL is defined by the URL Standard. This is the same serialization as is used
  /// when initializing a String from a `WebURL` value, printing a `WebURL`, or encoding a `WebURL`
  /// using `Codable`.
  ///
  /// ```swift
  /// let url: WebURL = ...
  /// url.serialized()
  /// String(url)      // Same as above.
  /// print(url)       // Same as print(url.serialized())
  /// ```
  ///
  /// ### Idempotence
  ///
  /// The URL Standard ensures that the combination of parser, serializer, and API, guarantee idempotence.
  /// This means that any `WebURL` value may be converted to a string (for example, in a log file or JSON)
  /// and re-parsed, and the result is guaranteed to be identical to the original `WebURL`.
  ///
  /// ```swift
  /// func takesURLAsString(_ urlString: String) {
  ///   // ✅ If `urlString` is a serialized WebURL, this is guaranteed
  ///   //    to reconstruct the value exactly.
  ///   let reparsed = WebURL(urlString)
  ///   assert(reparsed.serialized() == urlString)
  /// }
  /// ```
  /// > Tip:
  /// > In Swift terms, this means that WebURL is `LosslessStringConvertible`.
  ///
  /// > Note:
  /// > This may seem like an obvious feature, but not all URL libraries offer it.
  /// > Some libraries require special `normalize()` functions, or that you enable a 'relaxed' parsing mode,
  /// > and some URL types have additional state which isn't part of the serialization at all!
  ///
  /// - parameters:
  ///   - excludingFragment: Whether the fragment should be omitted from the result. The default is `false`.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/init(_:)``
  ///
  public func serialized(excludingFragment: Bool = false) -> String {
    excludingFragment
      ? String(decoding: utf8[0..<storage.structure.fragmentStart], as: UTF8.self)
      : String(decoding: utf8, as: UTF8.self)
  }

  /// The scheme of this URL, for example `https` or `file`.
  ///
  /// A URL’s `scheme` is a non-empty, lowercased ASCII string that identifies the type of URL and can be used to
  /// dispatch a URL for further processing. Every URL **must** have a scheme.
  ///
  /// ```swift
  /// WebURL("https://example.com/")!.scheme     // "https"
  /// WebURL("file:///usr/bin/swift")!.scheme    // "file"
  /// WebURL("my.app:/profile/settings")!.scheme // "my.app"
  /// ```
  ///
  /// Examples of URL schemes [include][wiki-schemes] `bitcoin`, `data`, `fax` (!), `rdar`, `redis`, and `spotify`.
  /// URL components, such as the ``hostname`` and ``path``, can mean quite different things in each of these schemes.
  ///
  /// Some schemes (known as _"special"_ schemes) are known to the URL Standard:
  ///
  /// - `http`, and `https`,
  /// - `ws`, and `wss`
  /// - `ftp`,
  /// - `file`
  ///
  /// URLs with these schemes may use different validation or normalization logic than other URLs.
  /// For example, they may be required to have a hostname, or to have a non-empty path,
  /// and that is checked at the URL level.
  ///
  /// The following example demonstrates setting a URL's scheme, as part of a function which upgrades
  /// insecure HTTP and WebSocket requests to use encryption.
  ///
  /// ```swift
  /// func ensureSecure(_ url: WebURL) -> WebURL? {
  ///   switch url.scheme {
  ///   case "https", "wss":
  ///     return url
  ///   case "http", "ws":
  ///     var secureURL = url
  ///     secureURL.scheme += "s"
  ///     return secureURL
  ///   default:
  ///     return nil
  ///   }
  /// }
  ///
  /// ensureSecure(WebURL("http://example.com/")!) // ✅ "https://example.com/"
  /// ensureSecure(WebURL("ws://example.com/")!)   // ✅ "wss://example.com/"
  /// ensureSecure(WebURL("file:///var/tmp/")!)    // ✅ nil
  /// ```
  ///
  /// > Tip:
  /// >
  /// > Schemes do not contain percent-encoding and are normalized to lowercase,
  /// > so they may be directly compared to literals such as `"http"` or `"ws"`.
  ///
  /// > Note:
  /// >
  /// > Setting this property may silently fail if the new scheme is invalid or incompatible with
  /// > the URL's previous scheme. Use ``setScheme(_:)`` to catch failures.
  ///
  /// [wiki-schemes]: https://en.wikipedia.org/wiki/List_of_URI_schemes
  ///
  /// ## See Also
  ///
  /// - ``WebURL/setScheme(_:)``
  ///
  public var scheme: String {
    get { String(decoding: utf8.scheme, as: UTF8.self) }
    set { try? setScheme(newValue) }
  }

  /// The username of this URL.
  ///
  /// If present, the username is a non-empty ASCII string.
  /// Note that the practice of including credentials in URLs is officially deprecated.
  ///
  /// ```swift
  /// var url = WebURL("ftp://user@ftp.example.com/")!
  ///
  /// url.username
  /// // ✅ "user"
  ///
  /// url.username = someString.percentEncoded(using: .urlComponentSet)
  /// // ✅ "ftp://100%25%20%F0%9F%98%8E@ftp.example.com/"
  /// //           ^^^^^^^^^^^^^^^^^^^^^
  ///
  /// url.username
  /// // ✅ "100%25%20%F0%9F%98%8E"
  ///
  /// url.username?.percentDecoded()
  /// // ✅ "100% 😎"
  /// ```
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > Setting this property may silently fail if the URL does not support credentials.
  /// > Use ``setUsername(_:)`` to catch failures.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/setUsername(_:)``
  ///
  public var username: String? {
    get { utf8.username.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setUsername(newValue) }
  }

  /// The password of this URL.
  ///
  /// If present, the password is a non-empty ASCII string.
  /// Note that the practice of including credentials in URLs is officially deprecated.
  ///
  /// ```swift
  /// var url = WebURL("ftp://user:secret@ftp.example.com/")!
  ///
  /// url.password
  /// // ✅ "secret"
  ///
  /// url.password = someString.percentEncoded(using: .urlComponentSet)
  /// // ✅ "ftp://user:%F0%9F%A4%AB@ftp.example.com/"
  /// //                ^^^^^^^^^^^^
  ///
  /// url.password
  /// // ✅ "%F0%9F%A4%AB"
  ///
  /// url.password?.percentDecoded()
  /// // ✅ "🤫"
  /// ```
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > Setting this property may silently fail if the URL does not support credentials.
  /// > Use ``setPassword(_:)`` to catch failures.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/setPassword(_:)``
  ///
  public var password: String? {
    get { utf8.password.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setPassword(newValue) }
  }

  /// The serialization of this URL's host.
  ///
  /// If present, the hostname is an ASCII string which describes this URL's ``host-swift.property``.
  /// Typically a host serves as a network address, but is sometimes an opaque identifier in URLs
  /// where a network address is not necessary.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/foo?bar")!
  ///
  /// url.hostname
  /// // ✅ "example.com"
  ///
  /// url.hostname = "127.0.0.1"
  /// // ✅ "http://127.0.0.1/foo?bar"
  /// //            ^^^^^^^^^
  ///
  /// url.hostname
  /// // ✅ "127.0.0.1"
  ///
  /// url.host
  /// // ℹ️ .ipv4Address(IPv4Address { 127.0.0.1 })
  /// ```
  ///
  /// When modifying this component, the new value is parsed as one of this URL's supported kinds of
  /// ``WebURL/WebURL/Host-swift.enum``, and the URL's hostname will be its ASCII serialization.
  /// Be aware that _special_ schemes (such as `http(s)`) may disallow certain kinds of host.
  ///
  /// ```swift
  /// // http(s) URLs may not have empty hosts.
  ///
  /// url.hostname = ""
  /// // ❌ "http://127.0.0.1/foo?bar" (Unchanged)
  /// //            ^^^^^^^^^
  /// ```
  ///
  /// For non-special schemes, hosts are either opaque strings or IPv6 addresses.
  /// Opaque strings must be percent-encoded in advance, or the operation will fail.
  /// This differs from other component setters, which typically encode disallowed characters.
  ///
  /// ```swift
  /// var nonSpecial = WebURL("my.app://my-host/baz")!
  ///
  /// nonSpecial.hostname = "foo^bar"   // ❌ Fails. '^' is forbidden in hostnames.
  /// nonSpecial.hostname = "foo%5Ebar" // ✅ "my.app://foo%5Ebar/baz"
  /// //                        ^^^
  /// ```
  ///
  /// > Note:
  /// > Setting this property may silently fail if the new value is invalid for the URL's scheme.
  /// > Use ``setHostname(_:)`` to catch failures.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/setHostname(_:)``
  /// - ``WebURL/host-swift.property``
  ///
  public var hostname: String? {
    get { utf8.hostname.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setHostname(newValue) }
  }

  /// The port number of this URL.
  ///
  /// If present, the port number is a 16-bit unsigned integer that identifies a networking port.
  /// Some schemes have a default port number, which is omitted from URLs with that scheme.
  /// Use ``portOrKnownDefault`` to return the scheme's default port number as a fallback.
  ///
  /// ```swift
  /// var url = WebURL("http://localhost:8000/my_site/foo")!
  /// url.port               // 8000
  /// url.portOrKnownDefault // 8000
  ///
  /// url.port = 9292        // ✅ "http://localhost:9292/my_site/foo"
  /// url.portOrKnownDefault // 9292
  ///
  /// url.port = nil         // ✅ "http://localhost/my_site/foo"
  /// url.port               // nil
  /// url.portOrKnownDefault // 80
  /// ```
  ///
  /// > Note:
  /// > Setting this property may silently fail if the new value is out of range, or if the URL does not support
  /// > port numbers. Use ``setPort(_:)`` to catch failures.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/portOrKnownDefault``
  /// - ``WebURL/setPort(_:)``
  ///
  public var port: Int? {
    get { utf8.port.map { Int(String(decoding: $0, as: UTF8.self), radix: 10)! } }
    set { try? setPort(newValue) }
  }

  /// The port number of this URL, or the default port of its scheme.
  ///
  /// If present, the port number is a 16-bit unsigned integer that identifies a networking port.
  /// Some schemes have a default port number, which is omitted from URLs with that scheme.
  ///
  /// This property returns the scheme's default port number if no explicit port is present in the URL.
  /// If the scheme does not have a default port, this property returns `nil`.
  ///
  /// ```swift
  /// var url = WebURL("http://localhost:8000/my_site/foo")!
  /// url.port               // 8000
  /// url.portOrKnownDefault // 8000
  ///
  /// url.port = 9292        // ✅ "http://localhost:9292/my_site/foo"
  /// url.portOrKnownDefault // 9292
  ///
  /// url.port = nil         // ✅ "http://localhost/my_site/foo"
  /// url.port               // nil
  /// url.portOrKnownDefault // 80
  /// ```
  ///
  /// To set a URL's port number, assign a value to its ``port`` property.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/port``
  ///
  @inlinable
  public var portOrKnownDefault: Int? {
    port ?? schemeKind.defaultPort.map { Int($0) }
  }

  /// The serialization of this URL's path.
  ///
  /// A URL’s path is either a list of zero or more ASCII strings, or an opaque ASCII string,
  /// and usually identifies a location. The ``hasOpaquePath`` property can be used to determine
  /// whether a URL's path is a list or opaque.
  ///
  /// ### List-style Paths
  ///
  /// List-style paths contain zero or more segments ("path components") delimited by the "`/`" character,
  /// and are the most common style of path:
  ///
  /// - URLs with special schemes (such as `http(s)` or `file`) always have list-style paths.
  /// - If a URL has a host, it has a list-style path.
  /// - If a path's serialization begins with "`/`", it is a list-style path.
  ///
  /// ```swift
  /// var url = WebURL("https://github.com/karwa/swift-url")!
  ///
  /// url.path
  /// // ✅ "/karwa/swift-url"
  ///
  /// url.path = "/apple/swift"
  /// // ✅ "https://github.com/apple/swift"
  /// //                       ^^^^^^^^^^^^
  ///
  /// url.path = "/apple/swift/../../whatwg/url"
  /// // ✅ "https://github.com/whatwg/url"
  /// //                       ^^^^^^^^^^^
  /// // List-style paths are automatically compacted.
  /// ```
  ///
  /// > Tip:
  /// > To read or modify the segments _within_ a list-style path string,
  /// > use the ``pathComponents-swift.property`` view.
  ///
  /// When modifying this component, the new value is interpreted as a list of path components
  /// and compacted. The percent-encoding of each path component is preserved,
  /// although additional characters will be encoded if they are disallowed from this component.
  /// This offers precise control over whether characters are percent-encoded or not,
  /// which may be necessary when constructing certain URLs.
  ///
  /// Constructing path strings manually can be delicate. Using the pathComponents view is recommended.
  ///
  /// ### Opaque Paths
  ///
  /// If a URL has no host and its path does not begin with a "`/`", it is said to have an _opaque path_.
  /// These URLs look like the following. You can recognize them by the lack of any slashes following the scheme.
  ///
  /// ```
  /// mailto:bob@example.com
  /// └─┬──┘ └──────┬──────┘
  /// scheme       path
  ///
  /// javascript:alert("hello");
  /// └───┬────┘ └──────┬──────┘
  ///  scheme          path
  ///
  /// data:text/plain;base64,...
  /// └┬─┘ └─────────┬─────────┘
  /// scheme        path
  /// ```
  ///
  /// These URLs are rather special in a number of ways. Since the path and query components of a URL are
  /// also opaque strings, every aspect of these URLs (other than the scheme prefix) is opaque.
  /// They are very flexible, but are incompatible with some ways of working with URLs - for example,
  /// they are incompatible with the ``pathComponents-swift.property`` view. These URLs tend to be quite rare.
  /// See the ``hasOpaquePath`` property for more information.
  ///
  /// Modifying a URL's opaque path is unsupported and will fail.
  ///
  /// ```swift
  /// var url = WebURL("mailto:bob@example.com")!
  ///
  /// url.path
  /// // ✅ "bob@example.com"
  ///
  /// url.hasOpaquePath
  /// // ✅ true
  ///
  /// url.path = "monica@example.com"
  /// // ❌ "mailto:bob@example.com" (Unchanged)
  /// //            ^^^^^^^^^^^^^^^
  /// //  Modifying opaque paths is unsupported.
  /// ```
  ///
  /// > Note:
  /// > Setting this property will silently fail if the URL has an opaque path.
  /// > Use ``setPath(_:)`` to catch failures.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/pathComponents-swift.property``
  /// - ``WebURL/setPath(_:)``
  /// - ``WebURL/hasOpaquePath``
  ///
  public var path: String {
    get { String(decoding: utf8.path, as: UTF8.self) }
    set { try? setPath(newValue) }
  }

  /// The query of this URL.
  ///
  /// If present, the query is an ASCII string. The precise structure of the string is not standardized,
  /// but it is often a list of encoded key-value pairs ("query parameters").
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/currency?v=20&from=USD&to=EUR")!
  ///
  /// url.query
  /// // ✅ "v=20&from=USD&to=EUR"
  ///
  /// url.query = "v=56&from=GBP&to=RUB"
  /// // ✅ "https://example.com/currency?v=56&from=GBP&to=RUB"
  /// //                                  ^^^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// > Tip:
  /// > To read or modify query parameters _within_ the query string, use the ``formParams`` view.
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > Whilst there are currently no invalid queries, failures may be added as the standard evolves.
  /// > Use ``setQuery(_:)`` to catch failures which may arise in the future.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/formParams``
  /// - ``WebURL/setQuery(_:)``
  ///
  public var query: String? {
    get { utf8.query.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setQuery(newValue) }
  }

  /// The fragment of this URL.
  ///
  /// If present, the fragment is an ASCII string, which may be used for further processing
  /// on the resource identified by the other components. The precise structure of the string is not standardized,
  /// and some protocols allow the client to use it for application-specific purposes.
  ///
  /// For example, some video streaming websites allow the fragment to contain a timestamp (e.g. `"#3m15s"`).
  /// The HTTP protocol does not send this to the server - instead, scripts on the website's page
  /// interpret this value and skip to the indicated time.
  ///
  /// ```swift
  /// var url = WebURL("my.app:/docs/shopping_list#groceries")!
  ///
  /// url.fragment
  /// // ✅ "groceries"
  ///
  /// url.fragment = "birthday party".percentEncoded(using: .urlComponentSet)
  /// // ✅ "my.app:/docs/shopping_list#birthday%20party"
  /// //                                ^^^^^^^^^^^^^^^^
  ///
  /// url.fragment
  /// // ✅ "birthday%20party"
  ///
  /// url.fragment?.percentDecoded()
  /// // ✅ "birthday party"
  /// ```
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > Whilst there are currently no invalid fragments, failures may be added as the standard evolves.
  /// > Use ``setFragment(_:)`` to catch failures which may arise in the future.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/setFragment(_:)``
  ///
  public var fragment: String? {
    get { utf8.fragment.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setFragment(newValue) }
  }

  /// Whether this URL has an opaque path.
  ///
  /// A URL's path can either be a list, or an opaque string.
  ///
  /// - URLs with special schemes (such as `http(s)` or `file`) always have list-style paths.
  /// - If a URL has a host, it has a list-style path.
  /// - If a path's serialization begins with "`/`", it is a list-style path.
  ///
  /// If a URL has no host and its path does not begin with a "`/`", it is said to have an _opaque path_.
  /// These following URLs have opaque paths. Notice the lack of slashes immediately following the scheme.
  ///
  /// ```
  /// mailto:bob@example.com
  /// └─┬──┘ └──────┬──────┘
  /// scheme       path
  ///
  /// javascript:alert("hello");
  /// └───┬────┘ └──────┬──────┘
  ///  scheme          path
  ///
  /// data:text/plain;base64,...
  /// └┬─┘ └─────────┬─────────┘
  /// scheme        path
  /// ```
  ///
  /// URLs with opaque paths are special in a number of ways. Since the path and query components of a URL are
  /// also opaque strings, every aspect of these URLs (other than the scheme prefix) is opaque.
  /// They are very flexible, but are incompatible with some ways of working with URLs.
  ///
  /// It is invalid for any operation to turn a URL with an opaque path in to one with a list-style path, or vice versa.
  /// As such, attempting to set any authority components (the ``username``, ``password``, ``hostname`` and ``port``)
  /// on a URL with an opaque path will fail. Additionally, the ``path`` may not be set on these URLs, and they do
  /// not support the ``pathComponents-swift.property`` view.
  ///
  /// ### Examples
  ///
  /// | URL                                 | Path                     | Style  |
  /// | ----------------------------------- | ------------------------ | ------ |
  /// |`https://github.com/karwa/swift-url` | `/karwa/swift-url`       | List   |
  /// |`file:///var/tmp/some%20file`        | `/var/tmp/some%20file`   | List   |
  /// |`my.app:/profile/settings`           | `/profile/settings`      | List   |
  /// |`mailto:bob@example.com`             | `bob@example.com`        | Opaque |
  /// |`javascript:alert("hello");`         | `alert("hello")`         | Opaque |
  /// |`data:text/plain;base64,...`         | `text/plain;base64,...`  | Opaque |
  /// |`blob:https://example.com`           | `https://example.com`    | Opaque |
  ///
  /// > Tip:
  /// > Remember that URLs with a special ``scheme`` (such as http, https, and file URLs) never have opaque paths.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/path``
  /// - ``WebURL/pathComponents-swift.property``
  /// - ``WebURL/resolve(_:)``
  ///
  @inlinable
  public var hasOpaquePath: Bool {
    storage.hasOpaquePath
  }
}


// --------------------------------------------
// MARK: - Setters
// --------------------------------------------


extension WebURL {

  /// Replaces this URL's ``scheme`` or throws an error.
  ///
  /// This function has the same semantics as the ``scheme`` property setter.
  ///
  /// This function throws if the new scheme is invalid, or if the URL cannot be adjusted to the new scheme.
  /// For example, changing between special and non-special schemes is not supported, and in some cases
  /// changing between file URLs and other special schemes is not possible.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/scheme``
  /// - ``WebURL/UTF8View/setScheme(_:)``
  ///
  @inlinable
  public mutating func setScheme<StringType>(_ newScheme: StringType) throws where StringType: StringProtocol {
    try newScheme._withContiguousUTF8 { try utf8.setScheme($0) }
  }

  /// Replaces this URL's ``username`` or throws an error.
  ///
  /// This function has the same behavior as the ``username`` property setter.
  ///
  /// This function throws if the URL does not support credentials (for example, because it does not specify a host).
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/username``
  /// - ``WebURL/UTF8View/setUsername(_:)``
  ///
  @inlinable
  public mutating func setUsername<StringType>(_ newUsername: StringType?) throws where StringType: StringProtocol {
    try newUsername._withContiguousUTF8 { try utf8.setUsername($0) }
  }

  /// Replaces this URL's ``password`` or throws an error.
  ///
  /// This function has the same behavior as the ``password`` property setter.
  ///
  /// This function throws if the URL does not support credentials (for example, because it does not specify a host).
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/password``
  /// - ``WebURL/UTF8View/setPassword(_:)``
  ///
  @inlinable
  public mutating func setPassword<StringType>(_ newPassword: StringType?) throws where StringType: StringProtocol {
    try newPassword._withContiguousUTF8 { try utf8.setPassword($0) }
  }

  /// Replaces this URL's ``hostname`` or throws an error.
  ///
  /// This function has the same behavior as the ``hostname`` property setter.
  ///
  /// This function throws if the hostname cannot be parsed as a valid host for the URL's ``scheme``,
  /// or if the URL does not support hostnames (for example, because it has an opaque path, ``hasOpaquePath``).
  ///
  /// When modifying this component, the new value is parsed as one of this URL's supported kinds of
  /// ``WebURL/WebURL/Host-swift.enum``, and the URL's hostname will be its ASCII serialization.
  /// Opaque hostnames must be percent-encoded in advance, or the operation will fail.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - parameters:
  ///   - newHostname: The new hostname to set. Be aware that this should be percent-encoded in advance.
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/hostname``
  /// - ``WebURL/UTF8View/setHostname(_:)``
  ///
  @inlinable
  public mutating func setHostname<StringType>(_ newHostname: StringType?) throws where StringType: StringProtocol {
    try newHostname._withContiguousUTF8 { try utf8.setHostname($0) }
  }

  /// Replaces this URL's ``port`` or throws an error.
  ///
  /// This function has the same behavior as the ``port`` property setter.
  ///
  /// This function throws if the new value is out of range, or if the URL does not support port numbers
  /// (for example, because it does not have a host).
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/port``
  ///
  public mutating func setPort(_ newPort: Int?) throws {
    guard let newPort = newPort else {
      return try storage.setPort(to: nil).get()
    }
    guard let uint16Port = UInt16(exactly: newPort) else {
      throw URLSetterError.portValueOutOfBounds
    }
    try storage.setPort(to: uint16Port).get()
  }

  /// Replaces this URL's ``path`` or throws an error.
  ///
  /// This function has the same behavior as the ``path`` property setter.
  ///
  /// Currently, this function only throws if the URL has an opaque path (see ``hasOpaquePath``).
  ///
  /// When modifying this component, the new value is interpreted as a list of path components
  /// and compacted. The percent-encoding of each path component is preserved,
  /// although additional characters will be encoded if they are disallowed from this component.
  /// This offers precise control over whether characters are percent-encoded or not,
  /// which may be necessary when constructing certain URLs.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/path``
  /// - ``WebURL/UTF8View/setPath(_:)``
  ///
  @inlinable
  public mutating func setPath<StringType>(_ newPath: StringType) throws where StringType: StringProtocol {
    try newPath._withContiguousUTF8 { try utf8.setPath($0) }
  }

  /// Replaces this URL's ``query`` or throws an error.
  ///
  /// This function has the same behavior as the ``query`` property setter. Currently, it has no failure conditions.
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/query``
  /// - ``WebURL/UTF8View/setQuery(_:)``
  ///
  @inlinable
  public mutating func setQuery<StringType>(_ newQuery: StringType?) throws where StringType: StringProtocol {
    try newQuery._withContiguousUTF8 { try utf8.setQuery($0) }
  }

  /// Replaces this URL's ``fragment`` or throws an error.
  ///
  /// This function has the same behavior as the ``fragment`` property setter. Currently, it has no failure conditions.
  ///
  /// When modifying this component, percent-encoding in the new value is preserved.
  /// Additionally, should the value contain any characters that are disallowed in this component,
  /// they will also be percent-encoded. This offers precise control over whether characters
  /// are percent-encoded or not, which may be necessary when constructing certain URLs.
  ///
  /// If assigning an arbitrary (non-percent-encoded) string to the component,
  /// you should percent-encode it first to ensure its contents are accurately represented.
  /// At a minimum you should encode the `"%"` character as `"%25"`, or
  /// encode the string using the ``PercentEncodeSet/urlComponentSet``.
  ///
  /// > Note:
  /// > The WHATWG URL Standard is a [living standard][WHATWG-LS], so new failure conditions may be added
  /// > as the standard evolves.
  ///
  /// [WHATWG-LS]: https://whatwg.org/faq#living-standard
  ///
  /// - throws: An opaque `Error` value, whose string representation contains a detailed description of the failure.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/fragment``
  /// - ``WebURL/UTF8View/setFragment(_:)``
  ///
  @inlinable
  public mutating func setFragment<StringType>(_ newFragment: StringType?) throws where StringType: StringProtocol {
    try newFragment._withContiguousUTF8 { try utf8.setFragment($0) }
  }
}
