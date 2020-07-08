
public struct OpaqueHost {
    public let hostname: String

    private init(unchecked hostname: String) {
        self.hostname = hostname
    } 
}

// Standard protocols.

extension OpaqueHost: Equatable, Hashable, Codable, CustomStringConvertible {

    public var description: String {
        return serialized
    }
}

// Parsing initializers.

extension OpaqueHost {

    @inlinable public static func parse<Source, Callback>(
        _ input: Source, callback: inout Callback
    ) -> OpaqueHost? where Source: StringProtocol, Callback: URLParserCallback {
        return input._withUTF8 { Self.parse($0, callback: &callback) }
    }

    @inlinable public init?<Source>(_ input: Source) where Source: StringProtocol {
        var callback = IgnoreValidationErrors()
        guard let parsedValue = Self.parse(input, callback: &callback) else { return nil }
        self = parsedValue
    }
}

// Parsing and serialization impl.

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

    public static func parse<Callback>(_ input: UnsafeBufferPointer<UInt8>, callback: inout Callback) -> OpaqueHost? where Callback: URLParserCallback {
        // This isn't technically in the spec algorithm, but opaque hosts are defined to be non-nil.
        guard input.isEmpty == false else { callback.validationError(opaqueHost: .emptyInput); return nil }

        var iter = input.makeIterator()
        while let byte = iter.next() {
            guard let asciiChar = ASCII(byte) else {
                continue // Non-ASCII codepoints checked below.
            }
            if asciiChar == .percentSign {
                if let percentEncodedByte1 = iter.next(), ASCII(percentEncodedByte1)?.isHexDigit != true,
                   let percentEncodedByte2 = iter.next(), ASCII(percentEncodedByte2)?.isHexDigit != true {
                    callback.validationError(opaqueHost: .invalidPercentEscaping)
                }
            } else if URLStringUtils.isForbiddenHostCodePoint(asciiChar) {
                callback.validationError(opaqueHost: .containsForbiddenHostCodePoint)
                return nil
            }
        }
        if URLStringUtils.hasNonURLCodePoints(input, allowPercentSign: true) {
            callback.validationError(opaqueHost: .containsNonURLCodePoint)
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
    
    public var serialized: String {
        return hostname
    }
}

