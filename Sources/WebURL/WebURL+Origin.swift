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
  public struct Origin {
    /// See https://html.spec.whatwg.org/multipage/origin.html#origin for definitions.
    fileprivate enum Kind {
      /// An "opaque origin", which is a unique internal value, generated and assigned to particular DOM elements at specific times.
      case opaque
      /// A tuple of (scheme, host, port, null/domain). Stored pre-serialized.
      /// According to the URL standard, the 'domain' should always be null ( https://url.spec.whatwg.org/#origin ).
      case tuple(String)
    }
    fileprivate var kind: Kind
  }
}

extension WebURL {

  /// The origin of this URL.
  ///
  /// Note that the only URLs with meaningul origins are those with the http, https, ftp, ws, or wss schemes,
  /// as well as cannot-be-a-base-URLs with the "blob" scheme whose path is another URL.
  /// All other URLs have "opaque" origins. See the `isOpaque` property for details.
  ///
  /// ```swift
  /// WebURL("https://example.com/index.html")!.origin // "https://example.com"
  /// WebURL("http://localhost:8080/index.html")!.origin // "http://localhost:8080"
  /// WebURL("file:///usr/bin/swift")!.origin // "null"
  /// WebURL("blob:https://example.com:443/index.html")!.origin // "https://example.com"
  /// ```
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

  /// If `true`, this origin is an opaque, internal value. Note that opaque origins are **not considered same-origin with themselves**.
  ///
  /// Since opaque origins are not same-origin with themselves, they compare as not equal using the `==` operator. That means you should not store
  /// them in hash-tables such as `Set` or `Dictionary`, as they will always insert in to the table and quickly degrade its performance:
  ///
  /// ```swift
  /// let myURL = WebURL("foo://exampleHost:4567/")!
  /// myURL.origin.isOpaque // true
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
