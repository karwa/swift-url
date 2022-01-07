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

  /// Parses a URL string.
  ///
  /// The string is parsed according to the [WHATWG URL Standard][URL-spec], which governs how browsers and other
  /// actors on the web platform should interpret URLs. The string must contain an absolute URL
  /// (i.e. including a scheme), but otherwise the parser is quite forgiving and will accept a wide range of
  /// improperly-formatted inputs.
  ///
  /// ```swift
  /// WebURL("https://github.com/karwa/swift-url") // ✅ Typical HTTPS URL.
  /// WebURL("file:///usr/bin/swift")              // ✅ Typical file URL.
  /// WebURL("my.app:/settings/language?debug")    // ✅ Typical custom URL.
  /// WebURL("  https://github.com/karwa/  ")      // ✅ Extra spaces are no problem.
  /// WebURL("https://github.com/🦆/swift-url")    // ✅ Will be automatically encoded.
  ///
  /// WebURL("invalid")         // ❌ No scheme.
  /// WebURL("/usr/bin/swift")  // ❌ No scheme.
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/resolve(_:)``
  /// - ``WebURL/serialized(excludingFragment:)``
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

  /// Parses a URL string from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs a URL from raw UTF-8 bytes rather than requiring they be stored as a `String`.
  /// The bytes must contain an absolute URL string. This initializer uses precisely the same parsing algorithm
  /// as ``init(_:)``, meaning it also allows for extra spaces, non-ASCII characters, and other improperly-formatted
  /// URLs.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object,
  /// and parsing each line as a URL directly from the binary data. Doing this saves allocating a `String`
  /// and UTF-8 validation.
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
  /// The way in which improper UTF-8 is handled depends on where it is within the URL. Most components will simply
  /// percent-encode anything which is not ASCII, but the hostname component may perform Unicode normalization
  /// for certain schemes and thus may reject invalid UTF-8.
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
  /// This function supports a wide range of relative URL strings, producing the same result as following
  /// an HTML `<a>` tag on this URL's "page".
  ///
  /// ```swift
  /// let base = WebURL("https://github.com/karwa/swift-url/")!
  ///
  /// base.resolve("pulls/39")            // ✅ "https://github.com/karwa/swift-url/pulls/39"
  /// base.resolve("/apple/swift/")       // ✅ "https://github.com/apple/swift/"
  /// base.resolve("..?tab=repositories") // ✅ "https://github.com/karwa/?tab=repositories"
  /// ```
  ///
  /// The process for resolving a relative references is defined by the [WHATWG URL Standard][URL-spec].
  /// Some forms of relative reference may be surprising, so you are advised to consider validating result
  /// if the relative reference is derived from runtime data.
  ///
  /// For example, protocol-relative references can direct to a hostname which is different to the base URL,
  /// and absolute URL strings may also be used as relative references.
  ///
  /// ```swift
  /// let base = WebURL("https://github.com/karwa/swift-url/")!
  ///
  /// base.resolve("//evil.com/wicked/thing")
  /// // ❗️ "https://evil.com/wicked/thing"
  /// //            ^^^^^^^^
  /// base.resolve("http://evil.com/wicked/thing")
  /// // ❗️ "http://evil.com/wicked/thing"
  /// //     ^^^^   ^^^^^^^^
  /// ```
  ///
  /// [URL-spec]: https://url.spec.whatwg.org/
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
        (lhsBuffer.baseAddress == rhsBuffer.baseAddress && lhsBuffer.count == rhsBuffer.count)
          || lhsBuffer.elementsEqual(rhsBuffer)
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
  /// dispatch a URL for further processing. For example, a URL with the "http" scheme should be processed
  /// by software that understands the HTTP protocol and may have unique requirements.
  /// Every URL **must** have a scheme.
  ///
  /// ```swift
  /// WebURL("https://example.com/")!.scheme     // "https"
  /// WebURL("file:///usr/bin/swift")!.scheme    // "file"
  /// WebURL("my.app:/profile/settings")!.scheme // "my.app"
  /// ```
  ///
  /// The following example demonstrates a function which ensures a URL uses TLS to establish an encrypted connection.
  ///
  /// ```swift
  /// func ensureSecure(_ url: WebURL) -> WebURL? {
  ///   switch url.scheme {
  ///   // Already secure.
  ///   case "https", "wss":
  ///     return url
  ///   // http and ws can be upgraded to use TLS.
  ///   case "http":
  ///     var secureURL = url
  ///     secureURL.scheme = "https"
  ///     return secureURL
  ///   case "ws":
  ///     var secureURL = url
  ///     secureURL.scheme = "wss"
  ///     return secureURL
  ///   // Unknown scheme, unable to secure.
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
  /// > Tip: Schemes do not contain percent-encoding and are normalized to lowercase,
  /// > so they may be directly compared to literals such as `"http"`.
  ///
  /// Some schemes are referred to as being _"special"_. The URL Standard enforces additional, protocol-specific
  /// restrictions and guarantees about URLs with the following schemes:
  ///
  /// - `http`, and `https`,
  /// - `ws`, and `wss`
  /// - `ftp`,
  /// - `file`
  ///
  /// For example, http and https URLs have hostnames which are known to be _domains_; they may not have empty
  /// hostnames, and require additional normalization and Unicode processing that is not required of other URLs.
  ///
  /// > Note:
  /// > Setting this property may silently fail if the new scheme is invalid or incompatible with
  /// > the URL's previous scheme. Use ``setScheme(_:)`` to catch failures.
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
  /// If present, the username is as a non-empty, percent-encoded string.
  /// Note that the entire practice of including credentials in URLs is officially deprecated.
  ///
  /// ```swift
  /// var url = WebURL("ftp://user@ftp.example.com/")!
  /// url.username        // "user"
  /// url.username = "😀" // ✅ "ftp://%F0%9F%98%80@ftp.example.com/"
  ///
  /// // ℹ️ Values derived at runtime should be percent-encoded.
  /// url.username = someString.percentEncoded(using: .urlComponentSet)
  /// ```
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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
  /// If present, the password is a non-empty, percent-encoded string.
  /// Note that the entire practice of including credentials in URLs is officially deprecated.
  ///
  /// ```swift
  /// var url = WebURL("ftp://user:secret@ftp.example.com/")!
  /// url.password        // "secret"
  /// url.password = "🤫" // ✅ "ftp://user:%F0%9F%A4%AB@ftp.example.com/"
  ///
  /// // ℹ️ Values derived at runtime should be percent-encoded.
  /// url.password = someString.percentEncoded(using: .urlComponentSet)
  /// ```
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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

  /// The hostname of this URL.
  ///
  /// If present, the hostname is a percent-encoded string which describes this URL's ``host-swift.property``.
  /// Typically a host serves as a network address, but is sometimes used as an opaque identifier in URLs
  /// where a network address is not necessary.
  ///
  /// When setting this property, the new value is parsed as one of the hosts allowed by this URL's ``scheme``
  /// (see ``host-swift.property`` for information about which kinds of hosts are allowed for each scheme).
  /// If valid, the new host will be normalized before it is written to the URL. Any values set to this property
  /// must be percent-encoded in advance, otherwise the host may be considered invalid.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/foo?bar")!
  /// url.hostname            // "example.com"
  /// url.hostname = "0x7F.1" // ✅ "http://127.0.0.1/foo?bar"
  ///
  /// // ❌ http(s) URLs may not have empty hosts.
  /// url.hostname = ""       // "http://127.0.0.1/foo?bar" (Unchanged)
  /// ```
  ///
  /// > Tip:
  /// > As an optimization, if this URL is known to have a special scheme (such as http/https), there is no need to
  /// > percent-encode the new hostname. Percent-encoding will be decoded by the host parser for these schemes
  /// > and will not make any invalid domains/IP addresses valid. It is, however, **required** for URLs with
  /// > non-special schemes.
  /// >
  /// > ```swift
  /// > var nonSpecial = WebURL("my.app://my-host/baz")!
  /// > nonSpecial.hostname = "foo^bar"   // ❌ Fails. '^' is forbidden in hostnames.
  /// > nonSpecial.hostname = "foo%5Ebar" // ✅ "my.app://foo%5Ebar/baz"
  /// > //                        ^^^
  /// > ```
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

  /// The path of this URL.
  ///
  /// A URL’s path is either a list of percent-encoded strings, or an opaque percent-encoded string,
  /// and usually identifies a location. The ``hasOpaquePath`` property can be used to determine
  /// if a URL has an opaque path.
  ///
  /// ### List-style Paths
  ///
  /// List-style paths contain a number of hierarchical components delimited by the "`/`" character,
  /// and are by far the most common style of paths. If a URL has a host (including an empty host),
  /// or its path begins with a "`/`", it has a list-style path. URLs with a special ``scheme``
  /// (such as http, https, or file URLs) _always_ have list-style paths.
  ///
  /// ```swift
  /// var url = WebURL("https://github.com/karwa/swift-url")!
  /// url.path                   // "/karwa/swift-url"
  /// url.path = "/apple/swift"  // ✅ "https://github.com/apple/swift"
  ///
  /// // ℹ️ List-style paths are automatically normalized.
  /// url.path = "/apple/swift/../../whatwg/url"  // "https://github.com/whatwg/url"
  /// ```
  ///
  /// When constructing list-style path strings using data obtained at runtime, be mindful that paths
  /// are lists of percent-encoded components, **not** percent-encoded lists of components. Each component must
  /// be encoded/decoded individually to guarantee that the path has the correct structure.
  ///
  /// ```swift
  /// func urlForBand(_ name: String) -> WebURL {
  ///   var url  = WebURL("https://example.com/")!
  ///   url.path = "/music/bands/" + name.percentEncoded(using: .urlComponentSet)
  ///   return url
  /// }
  /// urlForBand("The Rolling Stones")
  /// // ✅ "https://example.com/music/bands/The%20Rolling%20Stones"
  /// urlForBand("AC/DC")
  /// // ✅ "https://example.com/music/bands/AC%2FDC"
  /// ```
  ///
  /// > Tip:
  /// > Correctly handling list-style paths in string form is non-trivial, which is why `WebURL` includes
  /// > a ``pathComponents-swift.property`` write-through view to read and modify these kinds of paths.
  ///
  /// ### Opaque Paths
  ///
  /// If a URL has no host and its path does not begin with a "`/`", that path is considered by the URL Standard to
  /// be an opaque string. Since they are opaque, these paths have no assumed hierarchical structure, and are
  /// incompatible with the ``pathComponents-swift.property`` view. Modifying a URL's opaque path is unsupported
  /// and will fail.
  ///
  /// These URLs tend to be quite rare. See the ``hasOpaquePath`` property for more information about them.
  ///
  /// ```swift
  /// var url = WebURL("mailto:bob@example.com")!
  /// url.path           // "bob@example.com"
  /// url.hasOpaquePath  // true
  ///
  /// // ❌ Modifying opaque paths is unsupported.
  /// url.path = "monica@example.com" // "bob@example.com" (Unchanged)
  /// ```
  ///
  /// ### Examples
  ///
  /// The following table contains some sample URLs, their paths, and whether those paths are lists or opaque.
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
  /// If present, a URL's query is a percent-encoded or form-encoded string. It contains non-hierarchical
  /// data that, along with the ``path``, serves to identify a resource. The precise structure of the query string
  /// is not standardized, but is often used to store a list of key-value pairs ("query parameters").
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/currency?v=20&from=USD&to=EUR")!
  /// url.query                          // "v=20&from=USD&to=EUR"
  /// url.query = "v=56&from=GBP&to=RUB" // ✅ "https://example.com/currency?v=56&from=GBP&to=RUB"
  /// ```
  ///
  /// The following example demonstrates constructing a query string containing percent-encoded key-value pairs.
  ///
  /// ```swift
  /// // ℹ️ To use form-encoding instead, write:
  /// // '.percentEncoded(using: .formEncoding)'
  /// //                         ^^^^^^^^^^^^^
  /// func conversionURL(_ amount: Int, from: String, to: String) -> WebURL {
  ///   var url      = WebURL("https://example.com/currency")!
  ///   var newQuery = "v=\(amount)"
  ///   newQuery    += "&from=\(from.percentEncoded(using: .urlComponentSet))"
  ///   newQuery    += "&to=\(to.percentEncoded(using: .urlComponentSet))"
  ///   url.query    = newQuery
  ///   return url
  /// }
  ///
  /// conversionURL(99, from: "GBP", to: "JPY")
  /// // ✅ "https://example.com/currency?v=99&from=GBP&to=JPY"
  /// conversionURL(42, from: "¥", to: "€")
  /// // ✅ "https://example.com/currency?v=42&from=%C2%A5&to=%E2%82%AC"
  /// ```
  ///
  /// Percent-encoding and form-encoding look similar, but are incompatible with each other. To ensure information
  /// is conveyed accurately, confirm which style of encoding the URL's receiver expects, and build your query string
  /// accordingly. Form-encoding can be recognized by its use of the "`+`" character to encode spaces.
  ///
  /// > Tip:
  /// > Correctly handling encoded key-value pairs in string form is non-trivial, which is why `WebURL` includes
  /// > a ``formParams`` write-through view to read and modify these kinds of query strings.
  /// > Currently it only supports form-encoded query strings.
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
  /// If present, the fragment is a percent-encoded string, which may be used for further processing
  /// on the resource identified by the other components. The precise structure of the fragment is not standardized,
  /// and some protocols allow the client to use it for application-specific purposes. For example, the HTTP protocol
  /// does not include the fragment as part of any request, so it is sometimes used by websites to refer to important
  /// headings within their HTML documents.
  ///
  /// ```swift
  /// var url = WebURL("my.app:/docs/shopping_list#groceries")!
  /// url.fragment              // "groceries"
  /// url.fragment = "bathroom" // ✅ "my.app:/docs/shopping_list#bathroom"
  ///
  /// // ℹ️ Values derived at runtime should be percent-encoded.
  /// url.fragment = someString.percentEncoded(using: .urlComponentSet)
  /// ```
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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
  /// URLs with opaque paths are non-hierarchical: they do not specify a host, and their paths are opaque strings
  /// rather than lists of path components. They can be recognized by the lack of slashes immediately following the
  /// scheme delimiter.
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
  /// It is invalid for any operation to turn a URL with an opaque path in to one with a list-style path, or vice versa.
  /// As such, attempting to set any authority components (the ``username``, ``password``, ``hostname`` and ``port``)
  /// on a URL with an opaque path will fail. Additionally, the ``path`` may not be set on these URLs, and they do
  /// not support the ``pathComponents-swift.property`` view.
  ///
  /// > Tip:
  /// > URLs with a special ``scheme`` (such as http, https, and file URLs) never have opaque paths.
  ///
  /// It may sound frightening that a class of URLs exist for which so many operations will silently fail,
  /// but it tends not to be a significant issue in practice. As mentioned above, http(s) and file URLs never
  /// have opaque paths, and custom schemes typically require validating their structure before they are processed
  /// anyway.
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
  /// This function has the same semantics as the ``username`` property setter.
  ///
  /// This function throws if the URL does not support credentials (for example, because it does not specify a host).
  ///
  /// When setting this component, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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
  /// This function has the same semantics as the ``password`` property setter.
  ///
  /// This function throws if the URL does not support credentials (for example, because it does not specify a host).
  ///
  /// When setting this component, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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
  /// This function has the same semantics as the ``hostname`` property setter.
  ///
  /// This function throws if the hostname cannot be parsed as a valid host for the URL's ``scheme``,
  /// or if the URL does not support hostnames (for example, because it has an opaque path, ``hasOpaquePath``).
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// otherwise it may be considered invalid. See ``WebURL/hostname`` for more information.
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
  /// This function has the same semantics as the ``port`` property setter.
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
  /// This function has the same semantics as the ``path`` property setter.
  ///
  /// Currently, this function only throws if the URL has an opaque path (see ``hasOpaquePath``).
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. Constructing a correctly-encoded path string
  /// is non-trivial; see ``WebURL/path`` for more information.
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
  /// This function has the same semantics as the ``query`` property setter. Currently, it has no failure conditions.
  ///
  /// When setting this component, the new value is expected to be percent-encoded or form-encoded,
  /// although additional percent-encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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
  /// This function has the same semantics as the ``fragment`` property setter. Currently, it has no failure conditions.
  ///
  /// When setting this component, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
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
