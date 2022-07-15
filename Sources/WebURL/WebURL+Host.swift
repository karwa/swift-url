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

  /// A host, as interpreted by the URL Standard. A host is a network address or opaque identifier.
  ///
  /// A URL's host is interpreted from its ``WebURL/WebURL/hostname``.
  /// In general, hosts are simply opaque strings; for example, in the URL `redis://some_host/42`,
  /// the way in which `"some_host"` is interpreted is an implementation detail of the `"redis:"` URL scheme
  /// and request library being used - it might be some kind of network address, a path to a local file,
  /// a device/application ID, etc. It is up to the request library to parse the identifier
  /// and decide which kind of host it is, or if it is even valid.
  ///
  /// However, a few URL schemes (such as `"http(s):"` and `"file:"`) are known to the URL Standard,
  /// and it is necessary that all implementations interpret their hosts as specific, supported network addresses.
  /// For example, hostnames containing Unicode characters must be converted to ASCII using
  /// a special compatibility processing known as IDNA, and certain numerical hostnames (like `"127.0.0.1"`)
  /// are interpreted as IPv4 addresses.
  ///
  /// - **Recognized Hosts**
  ///
  /// The [URL Standard][URL-hostcombinations] interprets the following kinds of hosts for each scheme:
  ///
  /// | Scheme              | Domain | IPv4 | IPv6 | Opaque | Empty | Nil (not present) |
  /// |:-------------------:|:------:|:----:|:----:|:------:|:-----:|:-----------------:|
  /// | http(s), ws(s), ftp |   ✅   |  ✅  |  ✅  |    -   |   -   |         -         |
  /// |                file |   ✅   |  ✅  |  ✅  |    -   |   ✅  |         -         |
  /// |     everything else |    -   |   -  |  ✅  |   ✅   |   ✅  |         ✅        |
  ///
  /// - **Accessing a URL's host**
  ///
  /// A URL's host is given by its ``WebURL/WebURL/host-swift.property`` property.
  /// This is especially useful when processing URLs whose schemes are known to the URL Standard.
  ///
  /// ```swift
  /// let url = WebURL("http://127.0.0.1:8888/my_site")!
  ///
  /// guard url.scheme == "http" || url.scheme == "https" else {
  ///   throw UnknownSchemeError()
  /// }
  /// switch url.host {
  ///   case .domain(let domain):
  ///     // Look up name (e.g. using the system resolver/getaddrinfo).
  ///   case .ipv6Address(let address):
  ///     // Connect to known address.
  ///   case .ipv4Address(let address):
  ///     // Connect to known address.
  ///   case .opaque, .empty, .none:
  ///     fatalError("Not possible for http")
  /// }
  /// ```
  ///
  /// - **Parsing opaque hostnames**
  ///
  /// Applications may wish to parse opaque hostnames as HTTP URLs do. For example, if we were processing `"ssh:"` URLs,
  /// it could be valuable to support IPv4 addresses and IDNA. Similarly, if a hostname is provided on its own
  /// (perhaps as a command-line argument or configuration file entry), it can be useful to guarantee
  /// it is interpreted as an HTTP URL with that hostname.
  ///
  /// This can be achieved using the ``WebURL/WebURL/Host-swift.enum/init(_:scheme:)`` initializer,
  /// which parses and interprets a hostname in the context of a given scheme.
  ///
  /// ```swift
  /// // 🚩 "http:" URLs use a special Unicode -> ASCII conversion
  /// //    (called "IDNA"), designed for compatibility with existing
  /// //    internet infrastructure.
  ///
  /// let httpURL = WebURL("http://alice@أهلا.com/data")!
  /// httpURL       // "http://alice@xn--igbi0gl.com/data"
  ///               //               ^^^^^^^^^^^
  /// httpURL.host  // ✅ .domain(Domain { "xn--igbi0gl.com" })
  ///
  /// // 🚩 "ssh:" URLs have opaque hostnames, so Unicode characters
  /// //    are just percent-encoded. The URL Standard doesn't even know
  /// //    this a network address, so we don't get any automatic processing.
  ///
  /// let sshURL = WebURL("ssh://alice@أهلا.com/data")!
  /// sshURL       // "ssh://alice@%D8%A3%D9%87%D9%84%D8%A7.com/data"
  ///              //              ^^^^^^^^^^^^^^^^^^^^^^^^
  /// sshURL.host  // 😐 .opaque("%D8%A3%D9%87%D9%84%D8%A7.com")
  ///
  /// // 🚩 Using the WebURL.Host initializer, we can interpret our
  /// //    SSH hostname as if it were in an HTTP URL.
  ///
  /// let sshAsHttp = WebURL.Host(sshURL.hostname!, scheme: "http")
  /// // ✅ .domain(Domain { "xn--igbi0gl.com" })
  /// ```
  ///
  /// This also allows us to detect and support IPv4 addresses:
  ///
  /// ```swift
  /// let url = WebURL("ssh://user@192.168.15.21/data")!
  /// url       // "ssh://user@192.168.15.21/data"
  /// url.host  // 😐 .opaque("192.168.15.21")
  ///           //     ^^^^^^
  ///
  /// WebURL.Host(url.hostname!, scheme: "http")
  /// // ✅ .ipv4Address(IPv4Address { 192.168.15.21 })
  /// ```
  ///
  /// [URL-hostcombinations]: https://url.spec.whatwg.org/#url-representation
  ///
  /// ## Topics
  ///
  /// ### Kinds of Host
  ///
  /// - ``WebURL/WebURL/Host-swift.enum/domain(_:)``
  /// - ``WebURL/WebURL/Host-swift.enum/ipv4Address(_:)``
  /// - ``WebURL/WebURL/Host-swift.enum/ipv6Address(_:)``
  /// - ``WebURL/WebURL/Host-swift.enum/opaque(_:)``
  /// - ``WebURL/WebURL/Host-swift.enum/empty``
  ///
  /// ### Parsing a Host from a String and Context
  ///
  /// - ``WebURL/WebURL/Host-swift.enum/init(_:scheme:)``
  /// - ``WebURL/WebURL/Host-swift.enum/init(utf8:scheme:)``
  ///
  /// ### Obtaining a Host's String Representation
  ///
  /// - ``WebURL/WebURL/Host-swift.enum/serialized``
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/host-swift.property``
  /// - ``WebURL/WebURL/hostname``
  /// - ``WebURL/WebURL/Domain``
  /// - ``WebURL/IPv4Address``
  /// - ``WebURL/IPv6Address``
  ///
  public enum Host {

    /// An Internet Protocol, version 4 address.
    ///
    /// ## See Also
    ///
    /// - ``IPv4Address``
    ///
    case ipv4Address(IPv4Address)

    /// An Internet Protocol, version 6 address.
    ///
    /// ## See Also
    ///
    /// - ``IPv6Address``
    ///
    case ipv6Address(IPv6Address)

    /// A domain is a non-empty ASCII string which identifies a realm within a network.
    ///
    case domain(Domain)

    /// An opaque host is a non-empty percent-encoded string which can be used for further processing.
    ///
    case opaque(String)

    /// An empty hostname.
    ///
    case empty
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL.Host: Equatable, Hashable {}

extension WebURL.Host: CustomStringConvertible {

  @inlinable
  public var description: String {
    serialized
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.Host: Sendable {}
  extension WebURL.HostKind: Sendable {}
#endif

extension WebURL.Host: Codable {

  public enum CodingKeys: CodingKey {
    case hostname
    case kind
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(serialized, forKey: .hostname)
    let kind: String
    switch self {
    case .opaque, .empty: return
    case .domain: kind = "domain"
    case .ipv4Address: kind = "ipv4"
    case .ipv6Address: kind = "ipv6"
    }
    try container.encode(kind, forKey: .kind)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let hostname = try container.decode(String.self, forKey: .hostname)

    // All empty hostnames become '.empty', regardless of kind.
    guard !hostname.isEmpty else {
      self = .empty
      return
    }

    let kind = try container.decodeIfPresent(String.self, forKey: .kind)
    switch kind {
    // Domains and IPv4 require a special context.
    case "domain", "ipv4":
      switch (kind, WebURL.Host(hostname, scheme: "http")) {
      case ("domain", .some(.domain(let domain))):
        self = .domain(domain)
      case ("ipv4", .some(.ipv4Address(let address))):
        self = .ipv4Address(address)
      default:
        throw DecodingError.dataCorruptedError(forKey: .hostname, in: container, debugDescription: "invalid hostname")
      }
    // IPv6 and Opaque hosts can be parsed in a non-special context.
    case "ipv6", .none:
      switch (kind, WebURL.Host(hostname, scheme: "foo")) {
      case ("ipv6", .some(.ipv6Address(let address))):
        self = .ipv6Address(address)
      case (.none, .some(.opaque(let opaque))):
        self = .opaque(opaque)
      default:
        throw DecodingError.dataCorruptedError(forKey: .hostname, in: container, debugDescription: "invalid hostname")
      }
    default:
      throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "invalid kind")
    }
  }
}


// --------------------------------------------
// MARK: - Hosts in WebURL values
// --------------------------------------------


extension WebURL {

  /// The kind of host contained in a URL.
  ///
  @usableFromInline
  internal enum HostKind {
    case ipv4Address
    case ipv6Address
    case domain
    case domainWithIDN
    case opaque
    case empty
  }

  /// The host of this URL, as interpreted by the standard.
  ///
  /// A URL's host is interpreted from its ``WebURL/WebURL/hostname``.
  /// In general, hosts are simply opaque strings; for example, in the URL `redis://some_host/42`,
  /// the way in which `"some_host"` is interpreted is an implementation detail of the `"redis:"` URL scheme
  /// and request library being used - it might be some kind of network address, a path to a local file,
  /// a device/application ID, etc. It is up to the request library to parse the identifier
  /// and decide which kind of host it is, or if it is even valid.
  ///
  /// However, a few URL schemes (such as `"http(s):"` and `"file:"`) are known to the URL Standard,
  /// and it is necessary that all implementations interpret their hosts as specific, supported network addresses.
  /// For example, hostnames containing Unicode characters must be converted to ASCII using
  /// a special compatibility processing known as IDNA, and certain numerical hostnames (like `"127.0.0.1"`)
  /// are interpreted as IPv4 addresses.
  ///
  /// ```swift
  /// let url = WebURL("http://127.0.0.1:8888/my_site")!
  ///
  /// guard url.scheme == "http" || url.scheme == "https" else {
  ///   throw UnknownSchemeError()
  /// }
  /// switch url.host {
  ///   case .domain(let domain):
  ///     // Look up name (e.g. using the system resolver/getaddrinfo).
  ///   case .ipv6Address(let address):
  ///     // Connect to known address.
  ///   case .ipv4Address(let address):
  ///     // Connect to known address.
  ///   case .opaque, .empty, .none:
  ///     fatalError("Not possible for http")
  /// }
  /// ```
  ///
  /// The ``WebURL/WebURL/Host-swift.enum`` enum contains additional APIs, which allow you to interpret hostnames
  /// in the context of schemes known to the standard. This means that applications and libraries which process
  /// custom URL schemes or standalone hostname strings can also support Unicode hostnames via IDNA
  /// and IPv4 addresses.
  ///
  /// - **Recognized Hosts**
  ///
  /// The [URL Standard][URL-hostcombinations] interprets the following kinds of hosts for each scheme:
  ///
  /// | Scheme              | Domain | IPv4 | IPv6 | Opaque | Empty | Nil (not present) |
  /// |:-------------------:|:------:|:----:|:----:|:------:|:-----:|:-----------------:|
  /// | http(s), ws(s), ftp |   ✅   |  ✅  |  ✅  |    -   |   -   |         -         |
  /// |                file |   ✅   |  ✅  |  ✅  |    -   |   ✅  |         -         |
  /// |     everything else |    -   |   -  |  ✅  |   ✅   |   ✅  |         ✅        |
  ///
  /// [URL-hostcombinations]: https://url.spec.whatwg.org/#url-representation
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/Host-swift.enum/init(_:scheme:)``
  ///
  public var host: Host? {
    guard let kind = hostKind, let name = utf8.hostname else { return nil }
    switch kind {
    case .ipv4Address:
      return .ipv4Address(IPv4Address(dottedDecimalUTF8: name)!)
    case .ipv6Address:
      return .ipv6Address(IPv6Address(utf8: name.dropFirst().dropLast())!)
    case .domain, .domainWithIDN:
      let hasPunycodeLabels = (kind == .domainWithIDN)
      return .domain(Domain(serialization: String(decoding: name, as: UTF8.self), hasPunycodeLabels: hasPunycodeLabels))
    case .opaque:
      return .opaque(String(decoding: name, as: UTF8.self))
    case .empty:
      return .empty
    }
  }
}


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension WebURL.Host {

  /// Parses a hostname in the context of a given URL scheme.
  ///
  /// In general, the URL Standard considers hosts to simply be opaque strings;
  /// for example, in the URL `redis://some_host/42`, the way in which `"some_host"` is interpreted
  /// is an implementation detail of the `"redis:"` URL scheme and request library being used -
  /// it might be some kind of network address, a path to a local file, a device/application ID, etc.
  /// It is up to the request library to parse the identifier and decide which kind of host it is,
  /// or if it is even valid.
  ///
  /// However, a few URL schemes (such as `"http(s):"` and `"file:"`) are known to the URL Standard,
  /// and it is necessary that all implementations interpret their hosts as specific, supported network addresses.
  /// For example, hostnames containing Unicode characters must be converted to ASCII using
  /// a special compatibility processing known as IDNA, and certain numerical hostnames (like `"127.0.0.1"`)
  /// are interpreted as IPv4 addresses.
  ///
  /// This initializer allows you to understand, validate, and normalize hostnames
  /// using the [host parser][url-hostparser] from the URL Standard, in the context of the given `scheme`.
  ///
  /// ```swift
  /// // For custom URL schemes (e.g. redis:/mongodb:/etc URLs),
  /// // the URL Standard generally considers hostnames to be opaque.
  /// // Request libraries have to parse the hostname themselves
  /// // to figure out what it means.
  ///
  /// WebURL.Host("EXAMPLE.com", scheme: "foo")
  /// // 😐 .opaque, "EXAMPLE.com"
  ///
  /// WebURL.Host("abc.أهلا.com", scheme: "foo")
  /// // 😕 .opaque, "abc.%D8%A3%D9%87%D9%84%D8%A7.com"
  ///
  /// WebURL.Host("192.168.0.1", scheme: "foo")
  /// // 🤨 .opaque, "192.168.0.1"
  ///
  /// // Matching the behavior of HTTP URLs can be very useful -
  /// // especially as it comes with Unicode domain names (IDNA)
  /// // and IPv4 support.
  ///
  /// WebURL.Host("EXAMPLE.com", scheme: "http")
  /// // 😍 .domain, Domain { "example.com" }
  ///
  /// WebURL.Host("abc.أهلا.com", scheme: "http")
  /// // 🤩 .domain, Domain { "abc.xn--igbi0gl.com" }
  ///
  /// WebURL.Host("192.168.0.1", scheme: "http")
  /// // 🥳 .ipv4Address, IPv4Address { 192.168.0.1 }
  /// ```
  ///
  /// If the host is not valid for the given scheme, this initializer fails and returns `nil`.
  ///
  /// The ``WebURL/WebURL/Host-swift.enum`` documentation has more information about
  /// which kinds of hosts are supported for each `scheme`.
  ///
  /// [url-hostparser]: https://url.spec.whatwg.org/#concept-host-parser
  ///
  /// - parameters:
  ///   - string: The string to parse.
  ///   - scheme: The URL scheme which provides the context for interpreting the given string.
  ///
  @inlinable
  public init?<StringType>(_ string: StringType, scheme: String) where StringType: StringProtocol {
    guard let value = string._withContiguousUTF8({ WebURL.Host(utf8: $0, scheme: scheme) }) else {
      return nil
    }
    self = value
  }

  /// Parses a hostname string from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs a `Host` from raw UTF-8 bytes rather than requiring
  /// they be stored as a `String`. It uses precisely the same parsing algorithm as ``init(_:scheme:)``.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object, and parsing each line
  /// as a host directly from the binary text. Doing this saves allocating a String and UTF-8 validation.
  /// Hosts which are interpreted as containing Unicode text are transformed to ASCII via
  /// IDNA compatibility processing, which performs its own UTF-8 validation.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize from binary text.
  ///   let host = WebURL.Host(utf8: lineBytes, scheme: "http")
  ///   ...
  /// }
  /// ```
  ///
  /// - parameters:
  ///   - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///   - scheme: The URL scheme which provides the context for interpreting the given string.
  ///
  @inlinable
  public init?<UTF8Bytes>(
    utf8: UTF8Bytes, scheme: String
  ) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    // Parse the scheme. This will generally be a string literal, so fast-path HTTP family URLs.
    let schemeKind: WebURL.SchemeKind
    if scheme == "http" || scheme == "https" {
      schemeKind = .http
    } else {
      schemeKind = scheme._withContiguousUTF8 { WebURL.SchemeKind(parsing: $0) }
    }

    let _parsed =
      utf8.withContiguousStorageIfAvailable {
        WebURL.Host.parse(utf8: $0.boundsChecked, schemeKind: schemeKind)
      } ?? WebURL.Host.parse(utf8: utf8, schemeKind: schemeKind)
    guard let parsed = _parsed else {
      return nil
    }
    self = parsed
  }
}

extension WebURL.Host {

  @inlinable
  internal static func parse<UTF8Bytes>(
    utf8: UTF8Bytes, schemeKind: WebURL.SchemeKind
  ) -> Self? where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    // This is a simplified version of the logic from the `hostname` setter,
    // omitting checks that consider details such as whether the URL has a port number.

    // Check empty hostnames.
    guard !utf8.isEmpty else {
      if schemeKind.isSpecial, schemeKind != .file {
        return nil  // .schemeDoesNotSupportNilOrEmptyHostnames
      }
      return .empty
    }

    // Parse the hostname in the context of the given scheme.
    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(utf8, schemeKind: schemeKind, callback: &callback) else {
      return nil
    }
    switch newHost {
    case .ipv4Address(let address):
      return .ipv4Address(address)
    case .ipv6Address(let address):
      return .ipv6Address(address)
    case .empty:
      return .empty
    case .toASCIINormalizedDomain, .simpleDomain, .opaque:
      var writer = _DomainOrOpaqueStringWriter()
      newHost.write(bytes: utf8, using: &writer)
      let result = writer.result!
      if case .opaque = result.kind {
        return .opaque(result.string)
      } else {
        let hasPunycodeLabels = (result.kind == .domainWithIDN)
        return .domain(WebURL.Domain(serialization: result.string, hasPunycodeLabels: hasPunycodeLabels))
      }
    }
  }
}


// --------------------------------------------
// MARK: - Serialization
// --------------------------------------------


extension WebURL.Host {

  /// The string representation of this host.
  ///
  /// The serialization defined by the [URL Standard](https://url.spec.whatwg.org/#host-serializing),
  /// and is the same as the URL's ``WebURL/hostname`` property.
  ///
  /// ```swift
  /// let url = WebURL("http://[::c0a8:1]:4242/my_site")!
  /// url.hostname         // "[::c0a8:1]"
  /// url.host?.serialized // "[::c0a8:1]"
  /// ```
  ///
  public var serialized: String {
    switch self {
    case .ipv4Address(let address): return address.serialized
    case .ipv6Address(let address): return "[\(address.serialized)]"
    case .domain(let domain): return domain.serialized
    case .opaque(let name): return name
    case .empty: return ""
    }
  }
}
