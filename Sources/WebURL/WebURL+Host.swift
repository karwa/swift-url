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

  /// The kind of host contained in a URL.
  ///
  @usableFromInline
  internal enum HostKind {
    case ipv4Address
    case ipv6Address
    case domain
    case opaque
    case empty
  }

  /// The host of this URL.
  ///
  /// A host is a network address or opaque identifier. This property exposes the URL's precise interpretation
  /// of its host, allowing a network connection to be established directly rather than manually parsing the URL's
  /// ``hostname``.
  ///
  /// ```swift
  /// let url = WebURL("http://127.0.0.1:8888/my_site")!
  ///
  /// guard url.scheme == "http" || url.scheme == "https" else {
  ///   throw UnknownSchemeError()
  /// }
  /// switch url.host {
  ///   case .domain(let name): ... // DNS lookup.
  ///   case .ipv4Address(let address): ... // Connect to known address.
  ///   case .ipv6Address(let address): ... // Connect to known address.
  ///   case .opaque, .empty, .none: fatalError("Not possible for http")
  /// }
  /// ```
  ///
  /// See the ``IPv6Address`` and ``IPv4Address`` documentation for more information
  /// about how to use them to establish a network connection.
  ///
  /// ### Allowed Hosts
  ///
  /// The kinds of hosts supported by a URL depends on its ``scheme``, and is defined
  /// by the [URL Standard][URL-hostcombinations].
  ///
  /// | Schemes             | Domain | IPv4 | IPv6 | Opaque | Empty | Nil (not present) |
  /// |:-------------------:|:------:|:----:|:----:|:------:|:-----:|:-----------------:|
  /// | http(s), ws(s), ftp |   ✅   |  ✅  |  ✅  |    -   |   -   |         -         |
  /// |                file |   ✅   |  ✅  |  ✅  |    -   |   ✅  |         -         |
  /// |     everything else |    -   |   -  |  ✅  |   ✅   |   ✅  |         ✅        |
  ///
  /// What this means, in summary:
  ///
  /// - For **custom schemes** (`"my.app://..."`, etc), the URL Standard does not make any assumptions
  ///   about what a hostname means, except that hostnames in square brackets are IPv6 addresses
  ///   (for example, `"[::1]"`).
  ///
  ///   The hosts of these URLs may indeed be IPv4 addresses or domains, but as far as the standard is concerned,
  ///   they are opaque strings. They are not parsed or canonicalized, and invalid IPv4 addresses or domains
  ///   are not necessarily invalid hosts.
  ///
  /// - For **special schemes**, the standard knows which kinds of hosts are supported,
  ///   and will parse and canonicalize them.
  ///
  ///   For example, domains are expected to be resolved using the Domain Name System (DNS), which is case-insensitive
  ///   and has a unique way of encoding Unicode hostnames, so these hosts are normalized to lowercase and encoded
  ///   as Internationalized Domain Names if necessary.
  ///
  /// - **`http` and `https` URLs** always have a host, and it is never opaque or empty.
  ///
  /// > Note:
  /// > WebURL does not currently support Internationalized Domain Names (IDN), although we hope to support them
  /// > soon.
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
    guard let hostnameCodeUnits = utf8.hostname else { return nil }
    var callback = IgnoreValidationErrors()
    switch ParsedHost(hostnameCodeUnits, schemeKind: schemeKind, callback: &callback) {
    case .none:
      assertionFailure("Normalized hostname failed to reparse")
      return nil
    case .ipv4Address(let address):
      return .ipv4Address(address)
    case .ipv6Address(let address):
      return .ipv6Address(address)
    case .empty:
      return .empty
    case .asciiDomain:
      return .domain(String(decoding: hostnameCodeUnits, as: UTF8.self))
    case .opaque:
      return .opaque(String(decoding: hostnameCodeUnits, as: UTF8.self))
    }
  }

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

  public var description: String {
    serialized
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.Host: Sendable {}
  extension WebURL.HostKind: Sendable {}
#endif


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
