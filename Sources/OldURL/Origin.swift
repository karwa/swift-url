extension OldURLParser {

  // According to the HTML spec (https://html.spec.whatwg.org/multipage/origin.html#origin as of 27.06.2020):
  //
  // An "origin" can either be:
  // - A tuple of (scheme, host, port, null/domain), or
  // - An "opaque origin", which is a unique internal value, generated and assigned
  //   to particular DOM elements at specific times.
  //
  // According to the URL spec (https://url.spec.whatwg.org/#origin as of 27.06.2020):
  //
  // In order to obtain a URL's origin, we need to run some particular steps, switching on the URL's `scheme`.
  // - For a tuple origin, the 'domain' is always null.
  // - If returning an opaque origin, the spec asks us to "return a new opaque origin", and notes that
  //   "This does indeed mean that these URLs cannot be same-origin with themselves."
  //
  // For us, that means: no opaque origins are ever equal, and the concept of "same origin-domain" is not meaningful.

  /// Origins are the fundamental currency of the Web's security model.
  ///
  /// Two actors in the Web platform that share an origin are assumed to trust each other and to have the same authority.
  /// Actors with differing origins are considered potentially hostile versus each other, and are isolated from each other to varying degrees.
  ///
  public struct Origin {
    fileprivate enum Kind {
      case opaque
      case tuple(OldURLParser.Components)
    }
    fileprivate var kind: Kind
  }
}

extension OldURLParser.Components {

  var origin: OldURLParser.Origin {
    switch scheme {
    case .http, .https, .ws, .wss, .ftp:
      return OldURLParser.Origin(kind: .tuple(self))
    case .file:
      return OldURLParser.Origin(kind: .opaque)
    case .other(let str) where str == "blob":
      // TODO:
      // 1. If URL’s blob URL entry is non-null, then return URL’s blob URL entry’s environment’s origin.
      return path.first.flatMap { OldURLParser.parse($0)?.origin } ?? OldURLParser.Origin(kind: .opaque)
    case .other(_):
      return OldURLParser.Origin(kind: .opaque)
    }
  }
}

// Standard protocols.

extension OldURLParser.Origin: CustomStringConvertible {

  public var description: String {
    return serialized
  }
}

// TODO: Investigate adding `Equatable` conformance.
//
// It's a bit tricky since `x.origin == x.origin` is false for opaque origins,
// but FloatingPoint.NaN has the same issue.

extension OldURLParser.Origin {

  public func isSameOrigin(as other: Self) -> Bool {
    switch (kind, other.kind) {
    case (.opaque, _): return false
    case (_, .opaque): return false
    case (.tuple(let lhs), .tuple(let rhs)):
      return lhs.scheme == rhs.scheme && lhs.host == rhs.host && lhs.port == rhs.port
    }
  }
}

// Serialization impl.

extension OldURLParser.Origin {

  public var serialized: String {
    guard case .tuple(let components) = kind else {
      return "null"
    }
    var result = components.scheme.rawValue + "://"
    result += components.host.map { $0.serialized } ?? ""
    result += components.port.map { ":\($0)" } ?? ""
    return result
  }
}
