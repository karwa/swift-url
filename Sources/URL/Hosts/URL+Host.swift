
extension WebURLParser {
    public enum Host: Equatable, Hashable {
        case domain(String)
        case ipv4Address(IPAddress.V4)
        case ipv6Address(IPAddress.V6)
        case opaque(OpaqueHost)
        case empty
    }
}

extension WebURLParser.Host {

    var isEmpty: Bool {
        switch self {
            case .domain(let str): return str.isEmpty
            case .empty: return true
            default:     return false
        }
    }
}

extension WebURLParser.Host {

    public enum ValidationError: Equatable, CustomStringConvertible {
        case ipv4AddressError(IPAddress.V4.ValidationError)
        case ipv6AddressError(IPAddress.V6.ValidationError)
        case opaqueHostError(OpaqueHost.ValidationError)
        case hostParserError(HostParserError)

        public var description: String {
            switch self {
            case .ipv4AddressError(let error):
                return error.description
            case .ipv6AddressError(let error):
                return error.description
            case .opaqueHostError(let error):
                return error.description
            case .hostParserError(let error):
                return error.description
            }
        }
    }

    public struct HostParserError: Error, Equatable, CustomStringConvertible {
        private let errorCode: UInt8
        internal static var expectedClosingSquareBracket:   Self { Self(errorCode: 0) }
        internal static var containsForbiddenHostCodePoint: Self { Self(errorCode: 1) }

        public var description: String {
            switch self {
            case .expectedClosingSquareBracket:
                return "Invalid IPv6 Address - expected closing ']'"
            case .expectedClosingSquareBracket:
                return "Host contains forbidden codepoint"
            default:
                assert(false, "Unrecognised error code: \(errorCode)")
                return "Internal Error: Unrecognised error code"
            }
        }
    }

    public static func parse(_ input: UnsafeBufferPointer<UInt8>, isNotSpecial: Bool = false, onValidationError: (ValidationError)->Void) -> Self? {

        guard input.isEmpty == false else { 
            return .empty
        }        
        if input.first == ASCII.leftSquareBracket {
            guard input.last == ASCII.rightSquareBracket else {
                onValidationError(.hostParserError(.expectedClosingSquareBracket))
                return nil
            }
            let slice = UnsafeBufferPointer(rebasing: input.dropFirst().dropLast())
            return IPAddress.V6.parse(slice, onValidationError: { onValidationError(.ipv6AddressError($0)) }).map { .ipv6Address($0) }
        }

        if isNotSpecial {
            return OpaqueHost.parse(input, onValidationError: { onValidationError(.opaqueHostError($0)) }).map { .opaque($0) }
        }

        // TODO: Make this lazy.
        var domain = PercentEscaping.decode(bytes: input)
        // TODO:
        //
        // 6. Let asciiDomain be the result of running domain to ASCII on domain.
        //
        // 7. If asciiDomain is failure, validation error, return failure.
        //
        if let error = fake_domain2ascii(&domain) {
            onValidationError(.hostParserError(error))
            return nil
        }
        
        return domain.withUnsafeBufferPointer { asciiDomain in
            if asciiDomain.contains(where: { ASCII($0)?.isForbiddenHostCodePoint ?? false }) {
                onValidationError(.hostParserError(.containsForbiddenHostCodePoint))
                return nil
            }

            var ipv4Error: IPAddress.V4.ValidationError?
            switch IPAddress.V4.parse(asciiDomain, onValidationError: { ipv4Error = $0 }) {
            case .success(let address):
                return .ipv4Address(address)
            case .failure:
                onValidationError(.ipv4AddressError(ipv4Error!))
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
func fake_domain2ascii(_ domain: inout Array<UInt8>) -> WebURLParser.Host.HostParserError? {
    for i in domain.indices {
        guard let asciiChar = ASCII(domain[i]) else { return .containsForbiddenHostCodePoint }
        domain[i] = asciiChar.lowercased.codePoint
    }
    return nil
}

extension WebURLParser.Host {

    @inlinable public static func parse<S>(_ input: S, isNotSpecial: Bool = false, onValidationError: (ValidationError)->Void) -> Self? where S: StringProtocol {
        return input._withUTF8 { Self.parse($0, isNotSpecial: isNotSpecial, onValidationError: onValidationError) }
    }

    @inlinable public init?<S>(_ input: S, isNotSpecial: Bool = false) where S: StringProtocol {
        guard let parsed = Self.parse(input, isNotSpecial: isNotSpecial, onValidationError: { _ in }) else { return nil }
        self = parsed 
    }
}

extension WebURLParser.Host: CustomStringConvertible {

    /// Serialises the host, according to https://url.spec.whatwg.org/#host-serializing (as of 14.06.2020).
    ///
    public var description: String {
        switch self {
        case .ipv4Address(let address):
            return address.description
        case .ipv6Address(let address):
            return "[\(address.description)]"
        case .opaque(let host):
            return host.description
        case .domain(let domain):
            return domain.description
        case .empty:
            return ""
        }
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
        case .empty:        return .empty
        case .ipv4Address:  return .ipv4Address
        case .ipv6Address:  return .ipv6Address
        case .opaque:       return .opaque
        case .domain:       return .domain
       }
    }

    enum CodingKeys: String, CodingKey {
        case kind  = "kind"
        case value = "value"
    } 
    public init(from decoder: Decoder) throws {
       let container = try decoder.container(keyedBy: CodingKeys.self)
       let kind      = try container.decode(Kind.self, forKey: .kind)
       switch kind {
        case .empty: 
           self = .empty
        case .ipv4Address:
            self = .ipv4Address(try container.decode(IPAddress.V4.self, forKey: .value))
        case .ipv6Address:
            self = .ipv6Address(try container.decode(IPAddress.V6.self, forKey: .value))
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
