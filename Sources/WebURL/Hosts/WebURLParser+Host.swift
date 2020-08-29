extension WebURLParser {

  public enum Host {
    case domain(String)
    case ipv4Address(IPv4Address)
    case ipv6Address(IPv6Address)
    case opaque(OpaqueHost)
    case empty
  }
}

extension WebURLParser.Host {

  // TODO: Replace `.domain(String)` with a "Domain" type which
  //       cannot be user-instantiated with an empty string.
  //       Then we can remove this.
  var isEmpty: Bool {
    switch self {
    case .domain(let str): return str.isEmpty
    case .empty: return true
    default: return false
    }
  }
}

// Standard protocols.

extension WebURLParser.Host: Equatable, Hashable, CustomStringConvertible {

  public var description: String {
    return serialized
  }
}

extension WebURLParser.Host: Codable {

  public enum Kind: String, Codable {
    case domain
    case ipv4Address
    case ipv6Address
    case opaque
    case empty
  }

  public var kind: Kind {
    switch self {
    case .empty: return .empty
    case .ipv4Address: return .ipv4Address
    case .ipv6Address: return .ipv6Address
    case .opaque: return .opaque
    case .domain: return .domain
    }
  }

  // When serialising/deserialising host objects, we need to include the kind.
  // The string value is not enough (i.e. `Host` is not LosslessStringConvertible),
  // because how the string is interpreted by the parser depends on the URL's scheme.

  enum CodingKeys: String, CodingKey {
    case kind = "kind"
    case value = "value"
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    switch kind {
    case .empty:
      self = .empty
    case .ipv4Address:
      self = .ipv4Address(try container.decode(IPv4Address.self, forKey: .value))
    case .ipv6Address:
      self = .ipv6Address(try container.decode(IPv6Address.self, forKey: .value))
    case .opaque:
      self = .opaque(try container.decode(OpaqueHost.self, forKey: .value))
    case .domain:
      self = .domain(try container.decode(String.self, forKey: .value))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    switch self {
    case .empty:
      break
    case .ipv4Address(let addr):
      try container.encode(addr, forKey: .value)
    case .ipv6Address(let addr):
      try container.encode(addr, forKey: .value)
    case .opaque(let host):
      try container.encode(host, forKey: .value)
    case .domain(let host):
      try container.encode(host, forKey: .value)
    }
  }
}

// Parsing initializers.

extension WebURLParser.Host {

  @inlinable public static func parse<Source, Callback>(
    _ input: Source, isNotSpecial: Bool = false, callback: inout Callback
  ) -> Self? where Source: StringProtocol, Callback: URLParserCallback {
    return input._withUTF8 { Self.parse($0, isNotSpecial: isNotSpecial, callback: &callback) }
  }

  @inlinable public init?<S>(_ input: S, isNotSpecial: Bool = false) where S: StringProtocol {
    var callback = IgnoreValidationErrors()
    guard let parsed = Self.parse(input, isNotSpecial: isNotSpecial, callback: &callback) else { return nil }
    self = parsed
  }
}

// Parsing and serialization impl.

extension WebURLParser.Host {

  public struct ValidationError: Error, Equatable, CustomStringConvertible {
    private let errorCode: UInt8
    internal static var expectedClosingSquareBracket: Self { Self(errorCode: 0) }
    internal static var containsForbiddenHostCodePoint: Self { Self(errorCode: 1) }

    public var description: String {
      switch self {
      case .expectedClosingSquareBracket:
        return "Invalid IPv6 Address - expected closing ']'"
      case .containsForbiddenHostCodePoint:
        return "Host contains forbidden codepoint"
      default:
        assert(false, "Unrecognised error code: \(errorCode)")
        return "Internal Error: Unrecognised error code"
      }
    }
  }

  // TODO: If we were allowed to mutate the input (which the URL parser could certainly allow),
  //       we could percent-decode it in-place.

  public static func parse<Callback>(
    _ input: UnsafeBufferPointer<UInt8>, isNotSpecial: Bool = false, callback: inout Callback
  ) -> Self? where Callback: URLParserCallback {

    guard input.isEmpty == false else {
      return .empty
    }
    if input.first == ASCII.leftSquareBracket {
      guard input.last == ASCII.rightSquareBracket else {
        callback.validationError(hostParser: .expectedClosingSquareBracket)
        return nil
      }
      let slice = UnsafeBufferPointer(rebasing: input.dropFirst().dropLast())
      return IPv6Address.parse(slice, callback: &callback).map { .ipv6Address($0) }
    }

    if isNotSpecial {
      return OpaqueHost.parse(input, callback: &callback).map { .opaque($0) }
    }

    // TODO: Make this lazy or in-place.
    var domain = PercentEscaping.decode(bytes: input)
    // TODO:
    //
    // 6. Let asciiDomain be the result of running domain to ASCII on domain.
    //
    // 7. If asciiDomain is failure, validation error, return failure.
    //
    if let error = fake_domain2ascii(&domain) {
      callback.validationError(hostParser: error)
      return nil
    }

    return domain.withUnsafeBufferPointer { asciiDomain in
      if asciiDomain.contains(where: { ASCII($0).map { URLStringUtils.isForbiddenHostCodePoint($0) } ?? false }) {
        callback.validationError(hostParser: .containsForbiddenHostCodePoint)
        return nil
      }

      var ipv4Error = LastValidationError()
      switch IPv4Address.parse(asciiDomain, callback: &ipv4Error) {
      case .success(let address):
        return .ipv4Address(address)
      case .failure:
        callback.validationError(ipv4Error.error!)
        return nil
      case .notAnIPAddress:
        break
      }

      return .domain(String(decoding: asciiDomain, as: UTF8.self))
    }
  }
}

// This is a poor approximation of unicode's "domain2ascii" algorithm,
// which simply lowercases ASCII alphas and fails for non-ASCII characters.
func fake_domain2ascii(_ domain: inout [UInt8]) -> WebURLParser.Host.ValidationError? {
  for i in domain.indices {
    guard let asciiChar = ASCII(domain[i]) else { return .containsForbiddenHostCodePoint }
    domain[i] = asciiChar.lowercased.codePoint
  }
  return nil
}

extension WebURLParser.Host {

  /// Serialises the host, according to https://url.spec.whatwg.org/#host-serializing (as of 14.06.2020).
  ///
  public var serialized: String {
    switch self {
    case .ipv4Address(let address):
      return address.serialized
    case .ipv6Address(let address):
      return "[\(address.serialized)]"
    case .opaque(let host):
      return host.serialized
    case .domain(let domain):
      return domain
    case .empty:
      return ""
    }
  }
}
