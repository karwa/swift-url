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

  /// A value representing a scheme's kind.
  ///
  /// A URL's `scheme` (or "protocol") describes how to communicate with the resource's location.
  /// Some schemes ("http", "https", "ws", "wss", "ftp", and "file") are referred to as being "special".
  ///
  /// Note that this type intentionally does not conform to `Equatable`.
  /// Two URLs with the same `SchemeKind` may have different schemes if the scheme is not special.
  ///
  enum SchemeKind {
    case ftp
    case file
    case http
    case https
    case ws
    case wss
    case other
  }
}

extension WebURL.SchemeKind {

  /// Determines the `SchemeKind` for the given scheme content.
  ///
  /// This initializer does not determine whether a given scheme string is valid or not; it only detects certain known schemes and returns `.other` for everything
  /// else. Note that the ":" terminator must not be included in the content; "http" will be recognized, but "http:" won't. This initializer is case-insensitive.
  ///
  /// - parameters:
  ///     - schemeContent: The scheme content, as a sequence of UTF8-encoded bytes.
  ///
  init<Bytes>(parsing schemeContent: Bytes) where Bytes: Sequence, Bytes.Element == UInt8 {

    var iter = ASCII.Lowercased(schemeContent).makeIterator()
    switch iter.next() {
    case .h?:
      if iter.next() == .t, iter.next() == .t, iter.next() == .p {
        if let char = iter.next() {
          self = (char == .s && iter.next() == nil) ? .https : .other
        } else {
          self = .http
        }
        return
      }
    case .f?:
      switch iter.next() {
      case .i?:
        if iter.next() == .l, iter.next() == .e, iter.next() == nil {
          self = .file
          return
        }
      case .t?:
        if iter.next() == .p, iter.next() == nil {
          self = .ftp
          return
        }
      default:
        break
      }
    case .w?:
      if iter.next() == .s {
        if let char = iter.next() {
          self = (char == .s && iter.next() == nil) ? .wss : .other
        } else {
          self = .ws
        }
        return
      }
    default:
      break
    }
    self = .other
  }
}

extension WebURL.SchemeKind {

  /// Whether or not this scheme is considered "special".
  ///
  /// URLs with special schemes may have additional constraints or normalisation rules.
  ///
  var isSpecial: Bool {
    if case .other = self { return false }
    return true
  }

  /// This scheme's default port number, if it has one.
  ///
  /// Only some special schemes have known default port numbers.
  ///
  var defaultPort: UInt16? {
    switch self {
    case .http, .ws: return 80
    case .https, .wss: return 443
    case .ftp: return 21
    default: return nil
    }
  }

  /// Returns whether or not the given sequence of bytes are a UTF8-encoded string representation
  /// of this scheme's default port number. If this scheme does not have a default port number, this method returns `false`.
  ///
  /// Note that the port string's leading ":" separator must not be included.
  ///
  func isDefaultPortString<Bytes>(_ bytes: Bytes) -> Bool where Bytes: Sequence, Bytes.Element == UInt8 {
    var iter = bytes.lazy.map { ASCII($0) ?? .null }.makeIterator()
    switch self {
    case .http, .ws:
      return iter.next() == .n8 && iter.next() == .n0 && iter.next() == nil
    case .https, .wss:
      return iter.next() == .n4 && iter.next() == .n4 && iter.next() == .n3 && iter.next() == nil
    case .ftp:
      return iter.next() == .n2 && iter.next() == .n1 && iter.next() == nil
    default:
      return false
    }
  }
}
