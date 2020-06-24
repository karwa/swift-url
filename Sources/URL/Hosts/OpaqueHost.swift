
public struct OpaqueHost: Equatable, Hashable, Codable {
    public let hostname: String

    private init(unchecked hostname: String) {
        self.hostname = hostname
    } 
}

extension OpaqueHost {

    public struct ValidationError: Equatable, CustomStringConvertible {
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
                assert(false, "Unrecognised error code: \(errorCode)")
                return "Internal Error: Unrecognised error code"
            }
        }
    }

    public static func parse(_ input: UnsafeBufferPointer<UInt8>, onValidationError: (ValidationError)->Void) -> OpaqueHost? {
        // This isn't technically in the spec algorithm, but opaque hosts are defined to be non-nil.
        guard input.isEmpty == false else { onValidationError(.emptyInput); return nil }

        var iter = input.makeIterator()
        while let byte = iter.next() {
            guard let asciiChar = ASCII(byte) else {
                continue // Non-ASCII codepoints checked below.
            }
            if asciiChar == .percentSign {
                if let percentEncodedByte1 = iter.next(), ASCII(percentEncodedByte1)?.isHexDigit != true,
                   let percentEncodedByte2 = iter.next(), ASCII(percentEncodedByte2)?.isHexDigit != true {
                    onValidationError(.invalidPercentEscaping)
                }
            } else if URLStringUtils.isForbiddenHostCodePoint(asciiChar) {
                onValidationError(.containsForbiddenHostCodePoint)
                return nil
            }
        }
        if URLStringUtils.hasNonURLCodePoints(input, allowPercentSign: true) {
            onValidationError(.containsNonURLCodePoint)
        }

        var escapedHostname = ""
        PercentEscaping.encodeIterativelyAsString(
            bytes: input,
            escapeSet: .url_c0,
            processChunk: { piece in escapedHostname.append(piece) }
        )
        assert(escapedHostname.isEmpty == false)
        return OpaqueHost(unchecked: escapedHostname)
    }
}

extension OpaqueHost {

    @inlinable public static func parse<S>(_ input: S, onValidationError: (ValidationError)->Void) -> OpaqueHost? where S: StringProtocol {
        return input._withUTF8 { Self.parse($0, onValidationError: onValidationError) }
    }

    @inlinable public init?<S>(_ input: S) where S: StringProtocol {
        guard let parsedValue = Self.parse(input, onValidationError: { _ in }) else {
            return nil
        }
        self = parsedValue
    }
}

extension OpaqueHost: CustomStringConvertible {

    public var description: String {
        return hostname
    }
}
