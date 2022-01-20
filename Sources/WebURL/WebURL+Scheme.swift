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
  @usableFromInline
  internal enum SchemeKind {
    case ftp
    case file
    case http
    case https
    case ws
    case wss
    case other
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.SchemeKind: Sendable {}
#endif

extension WebURL.SchemeKind {

  /// Determines the `SchemeKind` for the given scheme content.
  ///
  /// This initializer does not determine whether a given scheme string is valid or not;
  /// it only detects certain known schemes and returns `.other` for everything else.
  ///
  /// Note that the ":" terminator must **not** be included in the content;
  /// `"http"` will be recognized, but `"http:"` won't. This initializer is case-insensitive.
  ///
  /// - parameters:
  ///     - schemeContent: The scheme content, as a sequence of UTF8-encoded bytes.
  ///
  @inlinable
  internal init<UTF8Bytes>(parsing schemeContent: UTF8Bytes) where UTF8Bytes: Sequence, UTF8Bytes.Element == UInt8 {

    if let contiguouslyParsed = schemeContent.withContiguousStorageIfAvailable({ buffer -> Self in
      guard let count = UInt8(exactly: buffer.count), count > 0 else { return .other }
      return WebURL.SchemeKind(ptr: UnsafeRawPointer(buffer.baseAddress.unsafelyUnwrapped), count: count)
    }) {
      self = contiguouslyParsed
      return
    }

    var buffer = 0 as UInt64
    self = withUnsafeMutableBytes(of: &buffer) { buffer -> Self in
      var iter = schemeContent.makeIterator()

      guard let byte0 = iter.next(), let byte1 = iter.next() else {
        return .other
      }
      buffer[0] = byte0
      buffer[1] = byte1
      guard let byte2 = iter.next() else {
        return WebURL.SchemeKind(ptr: UnsafeRawPointer(buffer.baseAddress.unsafelyUnwrapped), count: 2)
      }
      buffer[2] = byte2
      guard let byte3 = iter.next() else {
        return WebURL.SchemeKind(ptr: UnsafeRawPointer(buffer.baseAddress.unsafelyUnwrapped), count: 3)
      }
      buffer[3] = byte3
      guard let byte4 = iter.next() else {
        return WebURL.SchemeKind(ptr: UnsafeRawPointer(buffer.baseAddress.unsafelyUnwrapped), count: 4)
      }
      buffer[4] = byte4
      guard iter.next() == nil else {
        return .other
      }
      return WebURL.SchemeKind(ptr: UnsafeRawPointer(buffer.baseAddress.unsafelyUnwrapped), count: 5)
    }
  }

  // Note: 'count' is a separate parameter because UnsafeRawBufferPointer.count includes a force-unwrap,
  //       which can have a significant performance impact: https://bugs.swift.org/browse/SR-14422
  @inlinable
  internal init(ptr: UnsafeRawPointer, count: UInt8) {
    // Setting the 6th bit of each byte (i.e. OR-ing with 00100000) normalizes the code-unit to lowercase ASCII.
    switch count {
    case 2:
      var s = ptr.loadUnaligned(as: UInt16.self)
      s |= 0b00100000_00100000
      self = (s == Self._ws) ? .ws : .other
    case 3:
      // On big-endian machines, we need to swap-widen-swap:
      // [F, T] ->(swap)-> [T, F] ->(widen)-> [0, 0, T, F] ->(swap)-> [F, T, 0, 0].
      var s = UInt32(ptr.loadUnaligned(as: UInt16.self).littleEndian).littleEndian
      withUnsafeMutableBytes(of: &s) { $0[2] = ptr.load(fromByteOffset: 2, as: UInt8.self) }
      s |= UInt32(bigEndian: 0b00100000_00100000_00100000_00000000)
      self = (s == Self._wss) ? .wss : (s == Self._ftp) ? .ftp : .other
    case 4:
      var s = ptr.loadUnaligned(as: UInt32.self)
      s |= 0b00100000_00100000_00100000_00100000
      self = (s == Self._http) ? .http : (s == Self._file) ? .file : .other
    case 5:
      var s = ptr.loadUnaligned(as: UInt32.self)
      s |= 0b00100000_00100000_00100000_00100000
      self =
        ((s == Self._http) && ptr.load(fromByteOffset: 4, as: UInt8.self) | 0b00100000 == ASCII.s.codePoint)
        ? .https : .other
    default:
      self = .other
    }
  }

  // On little-endian machines, the shifting will arrange these in reverse order (e.g. "PTTH" in memory),
  // and .init(bigEndian:) will swap them back so they will have the same bytes, in the same order, as the code-units.
  @inlinable @inline(__always)
  internal static var _ws: UInt16 {
    UInt16(bigEndian: UInt16(ASCII.w.codePoint) &<< 8 | UInt16(ASCII.s.codePoint))
  }
  @inlinable @inline(__always)
  internal static var _wss: UInt32 {
    UInt32(
      bigEndian: UInt32(ASCII.w.codePoint) &<< 24 | UInt32(ASCII.s.codePoint) &<< 16 | UInt32(ASCII.s.codePoint) &<< 8
    )
  }
  @inlinable @inline(__always)
  internal static var _ftp: UInt32 {
    UInt32(
      bigEndian: UInt32(ASCII.f.codePoint) &<< 24 | UInt32(ASCII.t.codePoint) &<< 16 | UInt32(ASCII.p.codePoint) &<< 8
    )
  }
  @inlinable @inline(__always)
  internal static var _http: UInt32 {
    UInt32(
      bigEndian: UInt32(ASCII.h.codePoint) &<< 24 | UInt32(ASCII.t.codePoint) &<< 16 | UInt32(ASCII.t.codePoint) &<< 8
        | UInt32(ASCII.p.codePoint)
    )
  }
  @inlinable @inline(__always)
  internal static var _file: UInt32 {
    UInt32(
      bigEndian: UInt32(ASCII.f.codePoint) &<< 24 | UInt32(ASCII.i.codePoint) &<< 16 | UInt32(ASCII.l.codePoint) &<< 8
        | UInt32(ASCII.e.codePoint)
    )
  }
}

extension WebURL.SchemeKind {

  /// Whether or not this scheme is considered "special".
  ///
  /// URLs with special schemes may have additional constraints or normalization rules.
  ///
  @inlinable
  internal var isSpecial: Bool {
    if case .other = self { return false }
    return true
  }

  /// This scheme's default port number, if it has one.
  ///
  /// Only some special schemes have known default port numbers.
  ///
  @inlinable
  internal var defaultPort: UInt16? {
    switch self {
    case .http, .ws: return 80
    case .https, .wss: return 443
    case .ftp: return 21
    default: return nil
    }
  }

  /// Returns whether or not the given sequence of bytes are a UTF8-encoded string representation of this scheme's default port number.
  /// If this scheme does not have a default port number, this method returns `false`.
  ///
  /// Note that the port string's leading ":" separator must not be included.
  ///
  @inlinable
  internal func isDefaultPort<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> Bool where UTF8Bytes: Sequence, UTF8Bytes.Element == UInt8 {

    var buffer: UInt32 = 0

    var bytesConsumed = 0 as UInt8
    var iter = utf8.makeIterator()
    while let nextByte = iter.next(), bytesConsumed < 4 {
      buffer &<<= 8
      buffer |= UInt32(nextByte)
      bytesConsumed &+= 1
    }
    guard iter.next() == nil else {
      return false
    }

    switch self {
    case .http, .ws:
      return buffer == UInt32(ASCII.n8.codePoint) << 8 | UInt32(ASCII.n0.codePoint)
    case .https, .wss:
      return buffer == UInt32(ASCII.n4.codePoint) << 16 | UInt32(ASCII.n4.codePoint) << 8 | UInt32(ASCII.n3.codePoint)
    case .ftp:
      return buffer == UInt32(ASCII.n2.codePoint) << 8 | UInt32(ASCII.n1.codePoint)
    default:
      return false
    }
  }
}
