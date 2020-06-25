
extension WebURLParser {
    
    /// A URL’s scheme is an ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing after parsing.
    ///
    public enum Scheme: Equatable, Hashable {
        case ftp
        case file
        case http
        case https
        case ws
        case wss
        case other(String)
    }
}

// Standard protocols.

extension WebURLParser.Scheme: RawRepresentable, Codable {
        
    public init(rawValue: String) {
        switch rawValue {
        case "ftp":   self = .ftp
        case "file":  self = .file
        case "http":  self = .http
        case "https": self = .https
        case "ws":    self = .ws
        case "wss":   self = .wss
        default:      self = .other(rawValue)
        }
    }
    
    public var rawValue: String {
        switch self {
        case .ftp:   return "ftp"
        case .file:  return "file"
        case .http:  return "http"
        case .https: return "https"
        case .ws:    return "ws"
        case .wss:   return "wss"
        case .other(let scheme): return scheme
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension WebURLParser.Scheme {
    
    /// A special Scheme is a protocol scheme specifically listed by the URL standard as special.
    /// Special schemes can undergo slightly different parsing procedures, and their hosts are _domains_ rather than opaque hostnames.
    ///
    /// https://url.spec.whatwg.org/#url-miscellaneous as of 14.06.2020
    ///
    public var isSpecial: Bool {
        if case .other = self { return false }
        return true
    }
    
    /// Some special schemes (see `.isSpecial`) have default port numbers specifically listed by the URL standard.
    /// When parsing a special URL with a port number, the port will be omitted if it is already the default value for the URL's protocol.
    ///
    /// https://url.spec.whatwg.org/#url-miscellaneous as of 14.06.2020
    ///
    public var defaultPort: UInt16? {
        switch self {
        case .ftp:   return 21
        case .file:  return nil
        case .http:  return 80
        case .https: return 443
        case .ws:    return 80
        case .wss:   return 443
        case .other: return nil
        }
    }
}

extension WebURLParser.Scheme {
    
    /// Parses the scheme from a collection of ASCII bytes.
    ///
    /// This essentially does the same thing as the `init(rawValue:)`, but without requiring the bytes to first be
    /// decoded and copied in to a standard-library `String`.
    /// Protocol schemes are defined as being ASCII, and feeding non-ASCII bytes to this parser will result in a non-ASCII (invalid) scheme.
    ///
    /// - parameters:
    ///     - asciiBytes:  A Collection of ASCII-encoded characters.
    /// - returns:         The parsed `Scheme` object.
    ///
    static func parse<C>(asciiBytes: C) -> Self where C: Collection, C.Element == UInt8 {
        func notRecognised() -> Self {
            // FIXME (swift): This should be `Unicode.ASCII.self`, but UTF8 decoding is literally 10x faster.
            // https://bugs.swift.org/browse/SR-13063
            return .other(String(decoding: asciiBytes, as: UTF8.self))
        }
        // We use ASCII.init(_unchecked:) because we're only checking equality for specific ASCII sequences.
        // We don't actually care if the byte is ASCII, or use any algorithms which rely on that.
        //
        // But we *really* want to make sure that we don't pay for optionals - this parser is invoked *a lot*.
        var iter = asciiBytes.lazy.map { ASCII(_unchecked: $0) }.makeIterator()
        switch iter.next() {
        case .h?:
            guard iter.next() == .t, iter.next() == .t, iter.next() == .p else { return notRecognised() }
            switch iter.next() {
            case .s?:
                guard iter.next() == nil else { return notRecognised() }
                return .https
            case .none:
                return .http
            case .some(_):
                return notRecognised()
            }
        case .f?:
            switch iter.next() {
            case .i?:
                guard iter.next() == .l, iter.next() == .e, iter.next() == nil else { return notRecognised() }
                return .file
            case .t?:
                guard iter.next() == .p, iter.next() == nil else { return notRecognised() }
                return .ftp
            default:
                return notRecognised()
            }
        case .w?:
            guard iter.next() == .s else { return notRecognised() }
            switch iter.next() {
            case .s?:
                guard iter.next() == nil else { return notRecognised() }
                return .wss
            case .none:
                return .ws
            default:
                return notRecognised()
            }
        default:
            return notRecognised()
        }
    }
}
