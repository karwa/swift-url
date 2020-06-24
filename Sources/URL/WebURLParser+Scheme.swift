
extension WebURLParser {
    public enum Scheme: RawRepresentable, Equatable, Hashable, Codable {
        case ftp
        case file
        case http
        case https
        case ws
        case wss
        case other(String)
        
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
            case .ftp: return "ftp"
            case .file: return "file"
            case .http: return "http"
            case .https: return "https"
            case .ws: return "ws"
            case .wss: return "wss"
            case .other(let scheme): return scheme
            }
        }
        
        static func parse<C>(asciiBytes: C) -> Scheme where C: Collection, C.Element == UInt8 {
            func notRecognised() -> Scheme {
                // FIXME (swift): This should be `Unicode.ASCII.self`, but UTF8 decoding is literally 10x faster.
                return .other(String(decoding: asciiBytes, as: UTF8.self))
            }
            // We use ASCII.init(_unchecked:) because we're only checking equality for specific ASCII sequences.
            // We don't actually care if the byte is ASCII, or use any algorithms which rely on that.
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
        
        public var isSpecial: Bool {
            if case .other = self { return false }
            return true
        }
    }
}
