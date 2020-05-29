
extension XURL {
    public enum Host: Equatable, Hashable {
        case domain(String)
        case ipv4Address(IPAddress.V4)
        case ipv6Address(IPAddress.V6)
        case opaque(OpaqueHost)
        case empty
    }
}

extension XURL.Host {

    var isEmpty: Bool {
        switch self {
            case .domain(let str): return str.isEmpty
            case .empty: return true
            default:     return false
        }
    }
}

extension XURL.Host {

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case ipv4AddressError(IPAddress.V4.ParseError)
        case ipv6AddressError(IPAddress.V6.ParseError)
        case opaqueHostError(OpaqueHost.ParseError)
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
        internal static var expectedClosingSquareBracket: Self { Self(errorCode: 0) }

        public var description: String {
            switch self {
            case .expectedClosingSquareBracket:
                return "Invalid IPv6 Address - expected closing ']'"
            default:
                assert(false, "Unrecognised error code: \(errorCode)")
                return "Internal Error: Unrecognised error code"
            }
        }
    }

    public static func parse(_ input: UnsafeBufferPointer<UInt8>, isNotSpecial: Bool = false) -> Result<Self, ParseError> {

        guard input.isEmpty == false else { 
            return .success(.empty)
        }        
        if input.first == ASCII.leftSquareBracket {
            guard input.last == ASCII.rightSquareBracket else {
                return .failure(.hostParserError(.expectedClosingSquareBracket))
            }
            switch IPAddress.V6.parse(UnsafeBufferPointer(rebasing: input.dropFirst().dropLast())) {
            case .success(let address):
                return .success(.ipv6Address(address))
            case .failure(let error):
                return .failure(.ipv6AddressError(error))
            }
        }

        if isNotSpecial {
            switch OpaqueHost.parse(input) {
            case .success(let host):
                return .success(.opaque(host))
            case .failure(let error):
                return .failure(.opaqueHostError(error))
            }
        }

        // TODO:
        //
        // 5. Let domain be the result of running 'UTF-8 decode without BOM' on the string percent decoding of input.
        //    Note: Alternatively 'UTF-8 decode without BOM or fail' can be used, coupled with an early return for failure,
        //          as domain to ASCII fails on U+FFFD REPLACEMENT CHARACTER.
        //
        // 6. Let asciiDomain be the result of running domain to ASCII on domain.
        //
        // 7. If asciiDomain is failure, validation error, return failure.
        //
        // 8. If asciiDomain contains a forbidden host code point, validation error, return failure.

        if case .success(let address) = IPAddress.V4.parse(input) {
            return .success(.ipv4Address(address))
        }
        return .success(.domain(String(decoding: input, as: UTF8.self)))
    }
}

extension XURL.Host {

    @inlinable public static func parse<S>(_ input: S, isNotSpecial: Bool = false) -> Result<Self, ParseError> where S: StringProtocol {
        return input._withUTF8 { Self.parse($0, isNotSpecial: isNotSpecial) }
    }

    @inlinable public init?<S>(_ input: S, isNotSpecial: Bool = false) where S: StringProtocol {
        guard case .success(let parsed) = Self.parse(input, isNotSpecial: isNotSpecial) else { return nil }
        self = parsed 
    }
}

extension XURL.Host: CustomStringConvertible {

    public var description: String {
        switch self {
        case .ipv4Address(let address):
            return address.description
        case .ipv6Address(let address):
            return address.description
        case .opaque(let host):
            return host.description
        case .domain(let domain):
            return domain.description
        case .empty:
            return ""
        }
    }
}
