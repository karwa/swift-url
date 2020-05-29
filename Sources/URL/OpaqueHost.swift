
public struct OpaqueHost: Equatable, Hashable {
    public let hostname: String

    private init(unchecked hostname: String) {
        self.hostname = hostname
    } 
}

extension OpaqueHost {

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        private let errorCode: UInt8

        static var emptyInput:                     Self { Self(errorCode: 0) }
        static var invalidPercentEscaping:         Self { Self(errorCode: 1) }
        static var containsForbiddenHostCodePoint: Self { Self(errorCode: 2) }
        static var containsNonURLCodePoint:        Self { Self(errorCode: 3) }

        public var description: String {
            switch self {
            case .emptyInput:
                return "Empty input"
            case .invalidPercentEscaping:
                return "Invalid percent-escaped sequence"
            case .containsForbiddenHostCodePoint:
                return "String contains an forbidden host code point"
            case .containsNonURLCodePoint:
                return "String contains a non URL code point"
            default:
                fatalError("Unrecognised error code")
            }
        }
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

extension OpaqueHost: CustomStringConvertible {

    public var description: String {
        return hostname
    }
}
