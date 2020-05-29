
extension XURL {
    public enum Host: Equatable {
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

    init?(_ input: String, isNotSpecial: Bool = false) {
        func validationFailure(_ msg: String) {
            print("[URL.Host] Validation failure - \(msg).")
        } 
        guard input.isEmpty == false else { self = .empty; return }
        
        if input.first == ASCII.leftSquareBracket {
            guard input.last == ASCII.rightSquareBracket else {
                validationFailure("Invalid IPv6 Address - expected closing ']'")
                return nil        
            }
            guard let addr = IPAddress.V6(input.dropFirst().dropLast()) else {
                // The IPv6 parser emits its own validation failure messages.
                return nil
            }
            self = .ipv6Address(addr)
            return    
        }

        if isNotSpecial {
            guard let opaque = OpaqueHost(input) else { return nil }
            self = .opaque(opaque)
            return
        }

        // TODO: domain-to-ascii

        if let addr = IPAddress.V4(input) {
            self = .ipv4Address(addr)
            return
        }

        self = .domain(input)
    }
}

public struct OpaqueHost: Equatable {
    public let string: String // must not be empty.

    // temp, for testing.
    internal init(unchecked string: String) {
        self.string = string
    } 
}

extension OpaqueHost {

    public struct ParseError: Error {
        private let errorCode: UInt8

        static var emptyInput:                     Self { Self(errorCode: 0) }
        static var invalidPercentEscaping:         Self { Self(errorCode: 1) }
        static var containsForbiddenHostCodePoint: Self { Self(errorCode: 2) }
        static var containsNonURLCodePoint:        Self { Self(errorCode: 3) }
    }

    public static func parse(_ input: UnsafeBufferPointer<UInt8>) -> Result<OpaqueHost, ParseError> {
        guard input.isEmpty == false else { return .failure(.emptyInput) }

        var iter = input.makeIterator()
        while let byte = iter.next() {
            guard let asciiChar = ASCII(byte) else {
                continue // Non-ASCII codepoints checked below.
            }
            if asciiChar == .percentSign {
                guard let percentEncodedByte1 = iter.next(),
                      ASCII(percentEncodedByte1).map({ ASCII.ranges.isHexDigit($0) }) == true else {
                          return .failure(.invalidPercentEscaping)
                }
                guard let percentEncodedByte2 = iter.next(),
                      ASCII(percentEncodedByte2).map({ ASCII.ranges.isHexDigit($0) }) == true else {
                          return .failure(.invalidPercentEscaping)
                }
            } else if asciiChar.isForbiddenHostCodePoint {
                return .failure(.containsForbiddenHostCodePoint)
            }
        }        
        guard hasNonURLCodePoints(input, allowPercentSign: true) == false else {
            return .failure(.containsNonURLCodePoint)
        }

        let escapedHostname = PercentEscaping.encode(bytes: input, where: url_escape_c0)
        assert(escapedHostname.isEmpty == false)
        return .success(OpaqueHost(unchecked: escapedHostname))
    }
}

extension OpaqueHost {
    
    @inlinable public static func parse<S>(_ input: S) -> Result<OpaqueHost, ParseError> where S: StringProtocol {
        return input._withUTF8 { Self.parse($0) }
    }

    @inlinable public init?<S>(_ input: S) where S: StringProtocol {
        guard case .success(let parsed) = Self.parse(input) else { return nil }
        self = parsed 
    }
}
