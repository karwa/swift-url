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

extension WebURL {

  /// A domain is a non-empty ASCII string which identifies a realm within a network.
  ///
  /// A domain consists of one of more _labels_, delimited by periods.
  /// An example of a domain is `"www.example.com"`, which consists of the labels `["www", "example", "com"]`.
  ///
  /// Each label is a subordinate namespace (a _subdomain_) in the label which follows it -
  /// so `"news.example.com"` and `"weather.example.com"` are siblings, and are both subdomains of `"example.com"`.
  /// This syntax is used by the **Domain Name System (DNS)** for organizing internet hostnames.
  ///
  /// Internationalized Domain Names (IDNs) encode Unicode labels in an ASCII format.
  /// Such labels can be recognized by the `"xn--"` prefix. An example of an IDN is `"api.xn--igbi0gl.com"`,
  /// which is the encoded version of the Arabic domain `"api.أهلا.com"`.
  ///
  /// The `WebURL.Domain` type represents domains allowed by URLs. The way in which they are resolved to
  /// a network address is not specified, but is not limited to DNS. System resolvers may consult
  /// a variety of sources - including DNS, the system's `hosts` file, mDNS ("Bonjour"), NetBIOS, LLMNR, etc.
  /// Domains in URLs are normalized to lowercase, and do not enforce any restrictions on label or domain length.
  /// They do **not** support encoding arbitrary bytes, although they [allow][url-domaincp] most non-control
  /// ASCII characters that are not otherwise used as URL delimiters. IDNs are validated, and must decode
  /// to an allowed Unicode domain.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")  // ✅ "example.com"
  /// WebURL.Domain("EXAMPLE.com")  // ✅ "example.com"
  /// WebURL.Domain("localhost")    // ✅ "localhost"
  ///
  /// WebURL.Domain("api.أهلا.com")  // ✅ "api.xn--igbi0gl.com"
  /// WebURL.Domain("xn--caf-dma")  // ✅ "xn--caf-dma" ("café")
  ///
  /// WebURL.Domain("in valid")     // ✅ nil (spaces are not allowed)
  /// WebURL.Domain("xn--cafe-yvc") // ✅ nil (invalid IDN)
  /// WebURL.Domain("192.168.0.1")  // ✅ nil (not a domain)
  /// WebURL.Domain("[::1]")        // ✅ nil (not a domain)
  /// ```
  ///
  /// > Note:
  /// > Developers are encouraged to parse hostnames using the ``WebURL/WebURL/Host-swift.enum`` API.
  /// > It returns a `Domain` value if the hostname is a domain, but it also supports other kinds of hosts as well.
  ///
  /// [url-domaincp]: https://url.spec.whatwg.org/#forbidden-domain-code-point
  ///
  /// ## Topics
  ///
  /// ### Parsing Domains
  ///
  /// - ``WebURL/WebURL/Domain/init(_:)``
  /// - ``WebURL/WebURL/Domain/init(utf8:)``
  ///
  /// ### Obtaining a Domain's String Representation
  ///
  /// - ``WebURL/WebURL/Domain/serialized``
  ///
  /// ### Information about a Domain
  ///
  /// - ``WebURL/WebURL/Domain/isIDN``
  ///
  public struct Domain {

    @usableFromInline
    internal var _serialization: String

    @usableFromInline
    internal var _hasPunycodeLabels: Bool

    @inlinable
    internal init(serialization: String, hasPunycodeLabels: Bool) {
      self._serialization = serialization
      self._hasPunycodeLabels = hasPunycodeLabels
    }
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL.Domain: Equatable, Hashable, LosslessStringConvertible {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.serialized == rhs.serialized
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(serialized)
  }

  @inlinable
  public var description: String {
    serialized
  }
}

extension WebURL.Domain: Codable {

  @inlinable
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serialized)
  }

  @inlinable
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let parsedValue = WebURL.Domain(string) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Domain")
    }
    self = parsedValue
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.Domain: Sendable {}
#endif


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension WebURL.Domain {

  /// Parses a domain from a String.
  ///
  /// This initializer invokes the general ``WebURL/WebURL/Host-swift.enum`` parser in the context of an HTTP URL,
  /// and succeeds only if the parser considers the string to represent an allowed domain.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")  // ✅ "example.com"
  /// WebURL.Domain("EXAMPLE.com")  // ✅ "example.com"
  /// WebURL.Domain("localhost")    // ✅ "localhost"
  ///
  /// WebURL.Domain("api.أهلا.com")  // ✅ "api.xn--igbi0gl.com"
  /// WebURL.Domain("xn--caf-dma")  // ✅ "xn--caf-dma" ("café")
  ///
  /// WebURL.Domain("in valid")     // ✅ nil (spaces are not allowed)
  /// WebURL.Domain("xn--cafe-yvc") // ✅ nil (invalid IDN)
  /// WebURL.Domain("192.168.0.1")  // ✅ nil (not a domain)
  /// WebURL.Domain("[::1]")        // ✅ nil (not a domain)
  /// ```
  ///
  /// This API is a useful shorthand when parsing hostnames which **must** be a domain, and no other kind of host.
  /// For parsing general hostname strings, developers are encouraged to invoke the full URL host parser via
  /// ``WebURL/WebURL/Host-swift.enum/init(_:scheme:)`` instead. It returns a `Domain` value
  /// if the hostname is a domain, but it also supports other kinds of hosts as well.
  ///
  /// - parameters:
  ///   - string: The string to parse.
  ///
  @inlinable
  public init?<StringType>(_ string: StringType) where StringType: StringProtocol {
    guard let value = string._withContiguousUTF8({ WebURL.Domain(utf8: $0) }) else {
      return nil
    }
    self = value
  }

  /// Parses a domain from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs a `Domain` from raw UTF-8 bytes rather than requiring
  /// they be stored as a `String`. It uses precisely the same parsing algorithm as ``init(_:)``.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object, and parsing each line
  /// as a domain directly from the binary text. Doing this saves allocating a String and UTF-8 validation.
  /// Domains containing non-ASCII bytes are subject to IDNA compatibility processing, which also
  /// ensures that the contents are valid UTF-8.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize from binary text.
  ///   let domain = WebURL.Domain(utf8: lineBytes)
  ///   ...
  /// }
  /// ```
  ///
  /// This API is a useful shorthand when parsing hostnames which **must** be a domain, and no other kind of host.
  /// For parsing general hostname strings, developers are encouraged to invoke the full URL host parser via
  /// ``WebURL/WebURL/Host-swift.enum/init(utf8:scheme:)`` instead. It returns a `Domain` value
  /// if the hostname is a domain, but it also supports other kinds of hosts as well.
  ///
  /// - parameters:
  ///   - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  @inlinable
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    let parsed =
      utf8.withContiguousStorageIfAvailable {
        WebURL.Host.parse(utf8: $0.boundsChecked, schemeKind: .http)
      } ?? WebURL.Host.parse(utf8: utf8, schemeKind: .http)
    guard case .domain(let domain) = parsed else {
      return nil
    }
    self = domain
  }
}


// --------------------------------------------
// MARK: - Serialization
// --------------------------------------------


extension WebURL.Domain {

  /// The ASCII serialization of this domain.
  ///
  /// This value is guaranteed to be a non-empty ASCII string.
  /// Parsing this serialization with ``init(_:)`` will succeed,
  /// and construct a value which is identical to this domain.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")?.serialized  // ✅ "example.com"
  /// WebURL.Domain("EXAMPLE.com")?.serialized  // ✅ "example.com"
  /// WebURL.Domain("api.أهلا.com")?.serialized  // ✅ "api.xn--igbi0gl.com"
  ///
  /// WebURL.Domain("api.أهلا.com")?.description        // ✅ "api.xn--igbi0gl.com" -- same as above
  /// WebURL.Domain("api.أهلا.com").map { String($0) }  // ✅ "api.xn--igbi0gl.com" -- same as above
  /// ```
  ///
  @inlinable
  public var serialized: String {
    _serialization
  }
}


// --------------------------------------------
// MARK: - Properties
// --------------------------------------------


extension WebURL.Domain {

  /// Whether this is an Internationalized Domain Name (IDN).
  ///
  /// Internationalized Domain Names have at least one label which can be decoded to Unicode.
  /// In other words, one or more labels have the `"xn--"` prefix.
  ///
  /// ```swift
  /// WebURL.Domain("example.com")?.isIDN  // ✅ false -- "example.com"
  /// WebURL.Domain("api.أهلا.com")?.isIDN  // ✅ true -- "api.xn--igbi0gl.com"
  ///                                      //                 ^^^^^^^^^^^
  /// ```
  ///
  @inlinable
  public var isIDN: Bool {
    _hasPunycodeLabels
  }
}
