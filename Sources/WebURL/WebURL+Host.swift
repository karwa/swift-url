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

  /// The specific kind of host found in a URL.
  ///
  /// A URL's Host is a network address or opaque identifier. The URL Standard defines several specific kinds
  /// of network addresses which can be found in a URL - for example, IP addresses and domains. The kinds
  /// of hosts which are detected depend on the URL's ``scheme``.
  ///
  /// Access a URL's host through its ``WebURL/host-swift.property`` property.
  ///
  /// ```swift
  /// let url = WebURL("http://127.0.0.1:8888/my_site")!
  ///
  /// guard url.scheme == "http" || url.scheme == "https" else {
  ///   throw UnknownSchemeError()
  /// }
  /// switch url.host {
  ///   case .domain(let name): ... // DNS lookup.
  ///   case .ipv6Address(let address): ... // Connect to known address.
  ///   case .ipv4Address(let address): ... // Connect to known address.
  ///   case .opaque, .empty, .none: fatalError("Not possible for http")
  /// }
  /// ```
  ///
  /// > Tip:
  /// > The documentation for this type can be found at: ``WebURL/host-swift.property``.
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
    case domain(String)

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

  /// The host of this URL.
  ///
  /// A host is a network address or opaque identifier, whose serialization is the URL's ``hostname``.
  /// Hosts are interpreted from string values using context such as a URL's ``scheme``.
  ///
  /// For example, we know that the host of `"http://example.com/"` refers to a kind of network address because HTTP
  /// is a well-known network protocol, but in a custom URL scheme - say `"app.settings://example.com"`,
  /// the same hostname might not refer to a network address at all.
  ///
  /// The `Host` enumeration tells you precisely how the URL Standard interprets a host in a given context,
  /// as well as utilities to interpret hostnames as various other URLs do.
  ///
  /// ```swift
  /// let url = WebURL("http://127.0.0.1:8888/my_site")!
  ///
  /// // 🤓 Get precise information about the URL's host.
  /// switch url.host {
  ///   case .domain(let domain): ... // Perform DNS lookup.
  ///   case .ipv4Address(let address): ... // Connect to known address.
  ///   case .ipv6Address(let address): ... // Connect to known address.
  ///   case .opaque, .empty, .none: fatalError("Not possible for http")
  /// }
  /// ```
  ///
  /// See the ``WebURL/WebURL/Domain``, ``IPv6Address``, and ``IPv4Address`` documentation
  /// for more information about how to use them to establish a network connection or perform other processing.
  /// They are the recommended way to process hostnames in URLs, as they capture more information and provide
  /// stronger guarantees than is possible with hostname strings.
  ///
  /// ### Allowed Hosts
  ///
  /// The kinds of hosts supported by a URL are defined by the [URL Standard][URL-hostcombinations].
  ///
  /// | Schemes             | Domain | IPv4 | IPv6 | Opaque | Empty | Nil (not present) |
  /// |:-------------------:|:------:|:----:|:----:|:------:|:-----:|:-----------------:|
  /// | http(s), ws(s), ftp |   ✅   |  ✅  |  ✅  |    -   |   -   |         -         |
  /// |                file |   ✅   |  ✅  |  ✅  |    -   |   ✅  |         -         |
  /// |     everything else |    -   |   -  |  ✅  |   ✅   |   ✅  |         ✅        |
  ///
  /// In other words:
  ///
  /// - For **special schemes** (`"http://..."`, etc), the standard knows the hostname is supposed to be
  ///   some kind of network address, so it parses and normalizes them, and rejects hostnames it doesn't understand
  ///   or which result in invalid addresses.
  ///
  ///   Note that "domain" does not mean that the host is a valid DNS name.
  ///   Valid DNS names have requirements which are not enforced at the URL level.
  ///
  /// - For **custom schemes** (`"my.app://..."`, etc), the URL Standard cannot know what the hostname means,
  ///   so it considers it an opaque string. The only exception is that square brackets are reserved for
  ///   IPv6 addresses (`"[::1]"`). IPv6 addresses are syntactically supported in every URL.
  ///
  ///   Often, it is helpful to interpret and normalize the opaque string as though it were a domain -
  ///   for example, to detect IPv4 addresses or to apply IDNA compatibility processing. The URL Standard
  ///   cannot do this by default, but you can with **FIXME**
  ///
  /// - **`http` and `https` URLs** always have a host, and it is never opaque or empty.
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
  /// ### Obtaining a Host's String Representation
  ///
  /// - ``WebURL/WebURL/Host-swift.enum/serialized``
  ///
  /// ### Host Type
  ///
  /// - ``WebURL/WebURL/Host-swift.enum``
  ///
  /// ## See Also
  ///
  /// - ``WebURL/hostname``
  /// - ``IPv4Address``
  /// - ``IPv6Address``
  ///
  public var host: Host? {
    guard let kind = hostKind, let name = utf8.hostname else { return nil }
    switch kind {
    case .ipv4Address:
      return .ipv4Address(IPv4Address(dottedDecimalUTF8: name)!)
    case .ipv6Address:
      return .ipv6Address(IPv6Address(utf8: name.dropFirst().dropLast())!)
    case .domain, .domainWithIDN:
      return .domain(String(decoding: name, as: UTF8.self))
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

  /// Interprets a hostname in a given URL context.
  ///
  /// This initializer allows you to understand and normalize hostnames as the URL parser does,
  /// using the [host parser][url-hostparser] from the URL Standard.
  ///
  /// For example, if you are reading a hostname from a command-line argument or configuration file,
  /// it may be desirable to parse it in the context of an HTTP URL. Doing so would provide reasonable validation
  /// of the input, automatic support for IPv4/v6 addresses and Unicode domains via IDNA compatibility processing,
  /// and other useful normalization such as percent-decoding and lowercasing - all of which are standard in HTTP URLs.
  ///
  /// ```swift
  /// // For custom URL schemes (e.g. redis:/mongodb:/etc URLs), the URL Standard generally
  /// // considers hostnames to be opaque and doesn't interpret them.
  /// // Request engines end up parsing the hostname themselves to figure out what it means.
  ///
  /// WebURL.Host("EXAMPLE.com", scheme: "foo")   // 😐 .opaque, "EXAMPLE.com"
  /// WebURL.Host("abc.أهلا.com", scheme: "foo")   // 😕 .opaque, "abc.%D8%A3%D9%87%D9%84%D8%A7.com"
  /// WebURL.Host("192.168.0.1", scheme: "foo")   // 🤨 .opaque, "192.168.0.1"
  ///
  /// // Matching the behavior of HTTP URLs can be a useful strategy -
  /// // especially as it comes with Unicode domain names (IDNA) and IPv4 support.
  ///
  /// WebURL.Host("EXAMPLE.com", scheme: "http")  // 😍 .domain, "example.com"
  /// WebURL.Host("abc.أهلا.com", scheme: "http")  // 🤩 .domain, "abc.xn--igbi0gl.com"
  /// WebURL.Host("192.168.0.1", scheme: "http")  // 🥳 .ipv4Address, IPv4Address { 192.168.0.1 }
  ///
  /// // IPv6 addresses are supported by all schemes.
  ///
  /// WebURL.Host("[::ca08:99]", scheme: "http")  // ✅ .ipv6Address, IPv6Address { ... }
  /// WebURL.Host("[::ca08:99]", scheme: "foo")   // ✅ .ipv6Address, IPv6Address { ... }
  /// ```
  ///
  /// [url-hostparser]: https://url.spec.whatwg.org/#concept-host-parser
  ///
  /// - parameters:
  ///   - string: The string to parse.
  ///   - scheme: The
  ///
  @inlinable
  public init?<StringType>(_ string: StringType, scheme: String) where StringType: StringProtocol {
    guard let contig = string._withContiguousUTF8({ WebURL.Host(utf8: $0, scheme: scheme) }) else {
      return nil
    }
    self = contig
  }

  @inlinable
  public init?<UTF8Bytes>(
    utf8: UTF8Bytes, scheme: String
  ) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    // Parse the scheme.
    let schemeKind: WebURL.SchemeKind
    if scheme == "http" || scheme == "https" {
      schemeKind = .http
    } else {
      schemeKind = scheme._withContiguousUTF8 { WebURL.SchemeKind(parsing: $0) }
    }

    // Check empty hostnames.
    guard !utf8.isEmpty else {
      if schemeKind.isSpecial, schemeKind != .file {
        return nil  // .schemeDoesNotSupportNilOrEmptyHostnames
      }
      // The operation is valid. Calculate the new structure and replace the code-units.
      self = .empty
      return
    }

    // Parse the hostname in the context of the given scheme.
    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(utf8, schemeKind: schemeKind, callback: &callback) else {
      return nil
    }
    switch newHost {
    case .ipv4Address(let address):
      self = .ipv4Address(address)
    case .ipv6Address(let address):
      self = .ipv6Address(address)
    case .empty:
      self = .empty
    case .toASCIINormalizedDomain, .simpleDomain, .opaque:
      var writer = _DomainOrOpaqueStringWriter()
      newHost.write(bytes: utf8, using: &writer)
      let result = writer.result!
      if case .opaque = result.kind {
        self = .opaque(result.string)
      } else {
        self = .domain(result.string)
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
    case .domain(let name), .opaque(let name): return name
    case .empty: return ""
    }
  }
}
