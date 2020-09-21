extension NewURL {

  /// A URL’s scheme is an ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing after parsing.
  ///
  public enum Scheme: Equatable, Hashable {
    case ftp
    case file
    case http
    case https
    case ws
    case wss
    case other
  }
}

extension NewURL.Scheme {
  
  var isSpecial: Bool {
    return self != .other
  }

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
  static func parse<S>(asciiBytes: S) -> Self where S: Sequence, S.Element == UInt8 {
    func notRecognised() -> Self {
      // FIXME (swift): This should be `Unicode.ASCII.self`, but UTF8 decoding is literally 10x faster.
      // https://bugs.swift.org/browse/SR-13063
      return .other
    }
    
    // Lowercase characters, erase non-ASCII bytes to ":" (a character which we know isn't in any special scheme).
    var iter = asciiBytes.lazy.map { ASCII($0)?.lowercased ?? .colon }.makeIterator()
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

extension NewURL.Scheme {
  
  var defaultPort: UInt16? {
    switch self {
    case .http, .ws:   return 80
    case .https, .wss: return 443
    case .ftp:         return 21
    default:           return nil
    }
  }
}
