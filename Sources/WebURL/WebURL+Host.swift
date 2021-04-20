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

  /// A host is a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
  /// Typically a host serves as a network address, but it is sometimes used as opaque identifier in URLs where a network address is not necessary.
  ///
  /// * A domain is a non-empty ASCII string which identifies a realm within a network.
  ///   The hosts of URLs with special schemes (http, ftp, file, etc) are always either domains, IPv4 or v6 addresses, and never opaque.
  ///   In terms of unicode equivalence, domains are already normalized by the IDNA transform and encoded with Punycode, so they may be compared directly.
  ///
  /// * An opaque host is a non-empty ASCII string which can be used for further processing.
  ///   The hosts of URLs with non-special schemes are always either opaque or IPv6 addresses, and never domains or IPv4 addresses.
  ///   The name may contain non-ASCII characters or other forbidden host code-points in percent-encoded form.
  ///   The URL parser does not normalize these in any way.
  ///
  public enum Host {
    case ipv4Address(IPv4Address)
    case ipv6Address(IPv6Address)
    case domain(String)
    case opaque(String)
    case empty
  }

  /// The host of this URL, if present.
  ///
  /// A host is a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
  /// Typically a host serves as a network address, but it is sometimes used as opaque identifier in URLs where a network address is not necessary.
  ///
  public var host: Host? {
    guard let hostname = self.hostname else { return nil }
    var callback = IgnoreValidationErrors()
    switch ParsedHost(hostname.utf8, schemeKind: schemeKind, callback: &callback) {
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
      return .domain(hostname)
    case .opaque:
      return .opaque(hostname)
    }
  }
}

// Standard protocols.

extension WebURL.Host: Equatable, Hashable {}

extension WebURL.Host: CustomStringConvertible {

  public var description: String {
    serialized
  }
}

// Serialization.

extension WebURL.Host {

  /// The string representation of this host.
  ///
  /// The serialization format is defined by the [URL Standard](https://url.spec.whatwg.org/#host-serializing).
  /// This is the same as the URL's `hostname` property.
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
