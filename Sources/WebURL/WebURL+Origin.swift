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

// TODO: (DocC) - Add Topic references, See Also links to Origin.==
// Currently, DocC does not support links to operators.

extension WebURL {

  /// The domain of trust this URL belongs to, according to the web's security model.
  ///
  /// Origins are the fundamental currency of web security. Two actors on the Web platform that share an origin are
  /// assumed to trust each other and to have the same authority. Actors with differing origins are
  /// considered potentially hostile versus each other, and are isolated from each other to varying degrees.
  ///
  /// To check if two URLs have the same origin, compare their origin properties using the `==` operator.
  ///
  /// ```swift
  /// let urlA = WebURL("https://example.com/foo")!
  /// let urlB = WebURL("https://github.com/karwa/swift-url")!
  ///
  /// guard urlA.origin == urlB.origin else {
  ///   // Cross-origin access rejected:
  ///   // 'example.com' is not same-origin with 'github.com'.
  /// }
  /// ```
  ///
  /// ### Known and Opaque Origins
  ///
  /// A URL may have one of two types of origins, depending on its ``scheme`` and whether that scheme establishes
  /// an authority context. Origins of URLs known to the standard are internal tuples, consisting of
  /// their (scheme, ``hostname``, and ``port``). Origins of other URLs are known as **opaque**.
  ///
  /// If a URL has an opaque origin, it means that no obvious domain of trust can be established from the URL
  /// according to the standard. The [HTML Standard][HTML-origin] describes such an origin as
  /// "an internal value [...] for which the only meaningful operation is testing for equality".
  ///
  /// | Schemes                              | Example                        |          Origin         |
  /// |--------------------------------------|--------------------------------|:-----------------------:|
  /// | http(s), ws(s),ftp                   | `http://user@example.com`      | (http, example.com, 80) |
  /// | blob\*                               | `blob:http://user@example.com` | (http, example.com, 80) |
  /// | file                                 | `file:///usr/bin/swift`        |          Opaque         |
  /// | everything else                      | `my.app:/settings/language`    |          Opaque         |
  ///
  /// _\* if it has an opaque path containing another URL_
  ///
  /// An opaque origin does **not** not mean "not present" or "empty" in the sense that `nil` values do,
  /// as two `nil`s are considered equal to each other. Opaque origins are _undefined_ security domains;
  /// they must be considered **not equal** to any other origin, and be maximally isolated.
  ///
  /// > Note:
  /// > This indeed means that opaque origins do not compare as `==` with themselves.
  ///
  /// ### Custom Origin-like Concepts
  ///
  /// Despite there being URLs which the standard cannot compute security domains for,
  /// an application or library is free to augment that knowledge to establish its own origin-like concept
  /// for isolating domains of trust from one another:
  ///
  /// ```swift
  /// enum SecurityDomain {
  ///
  ///   /// Security domain is 'obvious' due to URL scheme
  ///   /// being known by the standard.
  ///   case derivedFromURL(WebURL.Origin)
  ///
  ///   /// A security domain which has been established
  ///   /// by application-specific logic.
  ///   case applicationDefined(MyApp.RealmOfTrust)
  ///
  ///   /// Opaque origin, unable to determine a security domain.
  ///   /// These must be maximally isolated from each other.
  ///   case undefinedOpaque
  ///
  ///   /// Checks whether two security domains are considered equivalent.
  ///   static func == (lhs: Self, rhs: Self) -> Bool {
  ///     switch (lhs, rhs) {
  ///     case (.derivedFromURL(let lhsOrigin), .derivedFromURL(let rhsOrigin)):
  ///       return lhsOrigin == rhsOrigin
  ///     case (.applicationDefined(let lhsRealm), .applicationDefined(let rhsRealm)):
  ///       return lhsRealm == rhsRealm
  ///     default:
  ///       return false
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// When designing such a type, it may be helpful to read [RFC-6456 ("The Web Origin Concept")][RFC-6454]
  /// for a holistic understanding of how the web's origin-based security model works.
  ///
  /// [HTML-origin]: https://html.spec.whatwg.org/multipage/origin.html#concept-origin-opaque
  /// [RFC-6454]: https://tools.ietf.org/html/rfc6454
  ///
  /// ### Origins in Hash Tables
  ///
  /// Because opaque origins do not compare as `==` with themselves, it is **strongly** advised that you
  /// do not store them in hash tables such as `Dictionary` or `Set`. Doing so is not meaningful
  /// and will degrade the table's performance.
  ///
  /// It is, however, perfectly fine to store **non-opaque** origins in these types.
  ///
  /// ```swift
  /// var allowedOrigins: Set<WebURL.Origin> = []
  ///
  /// let opaqueOrigin = WebURL("file:///usr/bin/swift")!.origin
  /// allowedOrigins.insert(opaqueOrigin)
  /// allowedOrigins.contains(opaqueOrigin) // ❗️ False.
  ///
  /// let knownOrigin = WebURL("https://example.com/foo")!.origin
  /// allowedOrigins.insert(knownOrigin)
  /// allowedOrigins.contains(knownOrigin) // ✅ True.
  /// ```
  ///
  /// ## Topics
  ///
  /// ### Checking If an Origin Is Opaque
  ///
  /// - ``WebURL/WebURL/Origin-swift.struct/isOpaque``
  ///
  /// ### Obtaining an Origin's String Representation
  ///
  /// - ``WebURL/WebURL/Origin-swift.struct/serialized``
  ///
  /// ### Origin Type
  ///
  /// - ``WebURL/WebURL/Origin-swift.struct``
  ///
  public var origin: Origin {
    switch schemeKind {
    case .http, .https, .ws, .wss, .ftp:
      let serializedTuple = "\(scheme)://\(hostname!)\(port.map { ":\($0)" } ?? "")"
      return Origin(kind: .tuple(serializedTuple))
    case .other where hasOpaquePath && utf8.scheme.elementsEqual("blob".utf8):
      return WebURL(path)?.origin ?? Origin(kind: .opaque)
    default:
      return Origin(kind: .opaque)
    }
  }

  /// A URL's Origin is the domain of trust that it belongs to, according to the web's security model.
  ///
  /// Origins are the fundamental currency of web security. Two actors on the Web platform that share an origin are
  /// assumed to trust each other and to have the same authority. Actors with differing origins are
  /// considered potentially hostile versus each other, and are isolated from each other to varying degrees.
  ///
  /// Access a URL's origin through its ``WebURL/origin-swift.property`` property.
  ///
  /// ```swift
  /// let urlA = WebURL("https://example.com/foo")!
  /// let urlB = WebURL("https://github.com/karwa/swift-url")!
  ///
  /// guard urlA.origin == urlB.origin else {
  ///   // Cross-origin access rejected:
  ///   // 'example.com' is not same-origin with 'github.com'.
  /// }
  /// ```
  ///
  /// > Tip:
  /// > The documentation for this type can be found at: ``WebURL/origin-swift.property``.
  ///
  public struct Origin {

    fileprivate enum Kind {

      /// An "opaque origin", which is an internal value. This type deviates from the standard by assigning
      /// these no identity, rather than assigning a unique identity upon creation.
      /// This should not matter for security, as the change in behavior only leads to _more_ isolation, never less.
      case opaque

      /// A tuple of (scheme, host, port, null/domain). Stored pre-serialized.
      /// According to the URL standard, the 'domain' should always be null.
      case tuple(String)
    }
    fileprivate var kind: Kind
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL.Origin: Equatable, Hashable {

  /// Whether two origins are considered to be "same origin" with respect to one another.
  ///
  /// Two actors on the Web platform that share an origin are assumed to trust each other
  /// and to have the same authority. Actors with differing origins are considered potentially hostile
  /// versus each other, and are isolated from each other to varying degrees.
  ///
  /// ```swift
  /// let urlHttpA = WebURL("https://example.com/foo")!
  /// let urlHttpB = WebURL("https://example.com/bar/baz?qux")!
  /// // http(s) URLs have known origins.
  /// urlHttpA.isOpaque // False
  /// urlHttpB.isOpaque // False
  ///
  /// urlHttpA.origin == urlHttpB.origin
  /// // ✅ True. "https://example.com" is same-origin with "https://example.com"
  ///
  /// let urlHttpC = WebURL("https://github.com/karwa/swift-url")!
  /// urlHttpA.origin == urlHttpC.origin
  /// // ❌ False. "https://example.com" is not same-origin with "https://github.com"
  /// ```
  ///
  /// Be aware that opaque origins represent an _undefined_ security domain, meaning that they
  /// are never considered "same origin" with respect to any origin, including themselves.
  /// For example, there is no obvious way to define a security domain for a file URL.
  ///
  /// ```swift
  /// // Unknown schemes and 'file' have opaque origins.
  /// let urlFileA = WebURL("file:///home/frank/docs/")!
  /// urlFileA.origin.isOpaque  // True
  ///
  /// urlFileA.origin == urlHttpA.origin
  /// // ❌ False. Opaque origins are not same-origin with anything.
  ///
  /// let urlFileB = WebURL("file:///home/monica/private_files/")!
  /// urlFileA.origin == urlFileB.origin
  /// // ❌ False. File URLs do not have obvious trust domains.
  ///
  /// urlFileA.origin == urlFileA.origin
  /// // ❌ False. Opaque origins are not even same-origin with themselves.
  /// ```
  ///
  /// > Important:
  /// > Do not store opaque origins in hash-tables such as `Set` or `Dictionary`, as they cannot be looked-up
  /// > (they are not equal `==` with any value) and will degrade the table's performance.
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

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.Origin: Sendable {}
#endif


// --------------------------------------------
// MARK: - Properties
// --------------------------------------------


extension WebURL.Origin {

  /// Whether this is an opaque origin, i.e. an undefined security domain.
  ///
  /// If a URL has an opaque origin, it means that no obvious domain of trust can be established from the URL
  /// according to the standard.
  ///
  /// An opaque origin does **not** not mean "not present" or "empty" in the sense that `nil` values do,
  /// as two `nil`s are considered equal to each other. Opaque origins are _undefined_ security domains;
  /// they must be considered **not equal** to any other origin, and be maximally isolated from them.
  ///
  /// ```swift
  /// // File URLs and custom schemes have opaque origins.
  /// let urlFileA = WebURL("file:///home/frank/docs/")!
  /// urlFileA.origin.isOpaque // True
  ///
  /// let urlHttpA = WebURL("https://example.com/foo")!
  /// urlFileA.origin == urlHttpA.origin
  /// // ❌ False. Opaque origins are not same-origin with anything.
  ///
  /// let urlFileB = WebURL("file:///home/monica/private_files/")!
  /// urlFileA.origin == urlFileB.origin
  /// // ❌ False. File URLs do not have obvious trust domains.
  ///
  /// urlFileA.origin == urlFileA.origin
  /// // ❌ False. Opaque origins are not even same-origin with themselves.
  /// ```
  ///
  /// > Important:
  /// > Do not store opaque origins in hash-tables such as `Set` or `Dictionary`, as they cannot be looked-up
  /// > (they are not equal `==` with any value) and will degrade the table's performance.
  ///
  public var isOpaque: Bool {
    if case .opaque = kind { return true }
    return false
  }

  /// The string representation of this origin.
  ///
  /// The serialization of an origin is defined in the [HTML specification][HTML].
  /// Despite opaque origins serializing as "null", they are conceptually very different from null values
  /// in programming languages. Whilst two null values may be considered equivalent,
  /// two opaque origins should be considered distinct and maximally isolated from each other.
  ///
  /// ```swift
  /// WebURL("https://example.com/foo")!.origin.serialized
  /// // "https://example.com"
  /// WebURL("https://user@example.com/bar")!.origin.serialized
  /// // "https://example.com"
  /// WebURL("https://example.com:8888/bar")!.origin.serialized
  /// // "https://example.com:8888"
  /// WebURL("https://github.com/karwa/swift-url")!.origin.serialized
  /// // "https://github.com"
  ///
  /// WebURL("file:///usr/bin/swift")!.origin.serialized
  /// // "null"
  /// WebURL("my.app:/settings/language")!.origin.serialized
  /// // "null"
  /// ```
  ///
  /// > Note:
  /// > Since serialized, non-opaque origins are syntactically valid URLs, they may be parsed as URLs
  /// > in order to reconstruct a ``WebURL/Origin-swift.struct`` from its serialization.
  /// >
  /// > It is not possible to reconstruct an opaque origin from its serialization.
  ///
  /// [HTML]: https://html.spec.whatwg.org/multipage/origin.html#ascii-serialisation-of-an-origin
  ///
  public var serialized: String {
    guard case .tuple(let serialization) = kind else {
      return "null"
    }
    return serialization
  }
}
