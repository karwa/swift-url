// Copyright The swift-url Contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

extension WebURL {

  /// Origins are the fundamental currency of the Web's security model.
  ///
  /// Two actors in the Web platform that share an origin are assumed to trust each other and to have the same authority.
  /// Actors with differing origins are considered potentially hostile versus each other, and are isolated from each other to varying degrees.
  ///
  /// The origin is not an attribute or component of a URL; it is a value which may be computed from a URL.
  ///
  /// The only URLs for which meaningful origins may be computed are:
  /// - Those with the http, https, ftp, ws, or wss schemes (i.e. the "special" schemes, excluding file), and
  /// - Those with the "blob" scheme, which do not have an authority (cannot-be-a-base), and whose path is another URL.
  ///
  /// Computing an origin using any other URL results in an _opaque origin_, which is defined to be an "internal value, with no serialization it can be recreated from,
  /// [...] and for which the only meaningful operation is testing for equality." ([HTML Standard][HTML-origin]).
  ///
  /// The URL standard requires every computation of an opaque origin to result in a _new_ value; and the HTML standard builds on that by computing
  /// new opaque origins at specific times for specific elements or browsing context, when it desires more specific behaviour for trust/security domains.
  ///
  /// This type deviates slightly from the URL standard in that it separates computing an origin using a URL from establishing a new trust/security domain.
  /// Opaque origins are instead considered to be _undefined_ security domains - it does not matter if you call `url.origin` again or store
  /// a previously-computed origin in your application state; an opaque origin will never compare as being "same origin" with anything, even itself.
  /// This behaviour is in some respects analogous to a floating-point NaN value.
  ///
  /// Instead, if an application wishes to establish a trust/security domain, it should do so explicitly by using an augmented origin type, for instance:
  ///
  /// ```
  /// enum ApplicationSpecificOrigin {
  ///   case derivedFromURL(WebURL.Origin) // security domain is 'obvious' due to URL scheme known by the standard.
  ///   case applicationDefined(T) // A security domain which has been established by application-specific logic.
  ///   case undefinedOpaque // opaque origin, application unable to determine a security domain.
  /// }
  /// ```
  /// This can also be useful to define application-specific origins for "file" URLs, which the [URL standard][URL-origin] leaves as "an exercise for the reader".
  ///
  /// It is also recommended to read [RFC-6456 ("The Web Origin Concept")][RFC-6454] for a holistic understanding of the origin-based security model.
  ///
  /// [HTML-origin]: https://html.spec.whatwg.org/multipage/origin.html#concept-origin-opaque
  /// [URL-origin]: https://url.spec.whatwg.org/#origin
  /// [RFC-6454]: https://tools.ietf.org/html/rfc6454
  ///
  public struct Origin {

    fileprivate enum Kind {

      /// An "opaque origin", which is an internal value. This type deviates from the standard by assigning these no identity, rather than assigning
      /// a unique identity upon creation. This should not matter for security, as the change in behaviour only leads to _more_ isolation, never less.
      case opaque

      /// A tuple of (scheme, host, port, null/domain). Stored pre-serialized.
      /// According to the URL standard, the 'domain' should always be null.
      case tuple(String)
    }
    fileprivate var kind: Kind
  }
}

extension WebURL {

  /// The origin of this URL.
  ///
  /// Origins are the fundamental currency of the Web's security model.
  /// Two actors in the Web platform that share an origin are assumed to trust each other and to have the same authority.
  /// Actors with differing origins are considered potentially hostile versus each other, and are isolated from each other to varying degrees.
  ///
  public var origin: Origin {
    switch schemeKind {
    case .http, .https, .ws, .wss, .ftp:
      let serializedTuple = "\(scheme)://\(hostname!)\(port.map { ":\($0)" } ?? "")"
      return Origin(kind: .tuple(serializedTuple))
    case .other where cannotBeABase && utf8.scheme.elementsEqual("blob".utf8):
      return WebURL(path)?.origin ?? Origin(kind: .opaque)
    default:
      return Origin(kind: .opaque)
    }
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL.Origin: Equatable, Hashable {

  /// Whether this origin is considered "same origin" with respect to another origin.
  ///
  /// Note that this always returns `false` for opaque origins.
  ///
  public static func == (lhs: WebURL.Origin, rhs: WebURL.Origin) -> Bool {
    switch (lhs.kind, rhs.kind) {
    // Opaque origins are like floating-point NaNs; not same-origin WRT each other.
    case (.opaque, _): return false
    case (_, .opaque): return false
    case (.tuple(let lhs), .tuple(let rhs)): return lhs == rhs
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch kind {
    case .opaque:
      hasher.combine(UInt8(0))
    case .tuple(let serialization):
      hasher.combine(UInt8(1))
      hasher.combine(serialization)
    }
  }
}

extension WebURL.Origin: CustomStringConvertible {

  public var description: String {
    return serialized
  }
}


// --------------------------------------------
// MARK: - Properties
// --------------------------------------------


extension WebURL.Origin {

  /// If `true`, this is an opaque origin with no meaningful value for use as a trust or security domain.
  ///
  /// Note that, analogous to floating-point NaN values, opaque origins are **not considered same-origin with themselves**.
  /// This also means that opaque origins compare as _not equal_ using the `==` operator, and should not be stored in hash-tables
  /// such as `Set` or `Dictionary`, as they will _always_ insert in to the table and degrade its performance:
  ///
  /// ```swift
  /// let myURL = WebURL("foo://exampleHost:4567/")!
  /// myURL.origin.isOpaque // true. WebURL is unable to define a security domain for "foo" URLs.
  ///
  /// myURL.origin == myURL.origin // false!
  ///
  /// var seenOrigins: Set = [myURL.origin]
  /// seenOrigins.contains(myURL.origin) // false!
  /// seenOrigins.insert(myURL.origin) // always inserts! lots of hash collisions!
  /// ```
  ///
  public var isOpaque: Bool {
    if case .opaque = kind { return true }
    return false
  }

  /// The string representation of this origin.
  ///
  /// The serialization of an origin is defined in the [HTTP specification][HTTP].
  ///
  /// [HTTP]: https://html.spec.whatwg.org/multipage/origin.html#ascii-serialisation-of-an-origin
  ///
  public var serialized: String {
    guard case .tuple(let serialization) = kind else {
      return "null"
    }
    return serialization
  }
}
