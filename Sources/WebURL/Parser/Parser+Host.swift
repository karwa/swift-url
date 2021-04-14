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

/// A description of a host that has been parsed from a string.
///
/// - seealso: `ParsedURLString`
///
@usableFromInline
internal enum ParsedHost {
  case asciiDomain(_ASCIIDomainInfo)
  case ipv4Address(IPv4Address)
  case ipv6Address(IPv6Address)
  case opaque(_OpaqueHostnameInfo)
  case empty
}


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension ParsedHost {

  /// Parses the given hostname to determine what kind of host it is, and whether or not it is valid.
  /// The created `ParsedHost` object may then be used to write a normalized/encoded version of the hostname.
  ///
  @inlinable
  internal init?<UTF8Bytes, Callback>(
    _ hostname: UTF8Bytes, schemeKind: WebURL.SchemeKind, callback: inout Callback
  ) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    guard hostname.isEmpty == false else {
      self = .empty
      return
    }

    var ipv6Slice = hostname[...]
    if ipv6Slice.removeFirst() == ASCII.leftSquareBracket.codePoint {
      guard ipv6Slice.popLast() == ASCII.rightSquareBracket.codePoint else {
        callback.validationError(.unclosedIPv6Address)
        return nil
      }
      guard let result = IPv6Address(utf8: ipv6Slice) else {
        callback.validationError(.invalidIPv6Address)
        return nil
      }
      self = .ipv6Address(result)
      return
    }

    guard schemeKind.isSpecial else {
      guard let hostnameInfo = ParsedHost._tryParseOpaqueHostname(hostname, callback: &callback) else {
        return nil
      }
      self = .opaque(hostnameInfo)
      return
    }

    let domain = hostname.lazy.percentDecodedUTF8

    // TODO: [idna]
    //
    // > 6. Let asciiDomain be the result of running domain to ASCII on domain.
    // > 7. If asciiDomain is failure, validation error, return failure.
    //
    // We don't have IDNA, so we need to reject:
    // - domains with non-ASCII characters
    // - domains which are ASCII but have IDNA-encoded "labels" (dot-separated components).
    //   These require validation which we can't do yet.
    //
    // Which should leave us with pure ASCII domains, which don't depend on Unicode at all.
    // For these, IDNA normalization/encoding is just lowercasing. At least that's something we can do...

    let (_, _asciiDomainInfo) = ParsedHost._tryParseASCIIDomain(domain, callback: &callback)
    guard let asciiDomainInfo = _asciiDomainInfo else {
      return nil
    }
    let asciiDomain = domain

    switch IPv4Address.parse(utf8: asciiDomain) {
    case .success(let address):
      self = .ipv4Address(address)
      return
    case .failure:
      callback.validationError(.invalidIPv4Address)
      return nil
    case .notAnIPAddress:
      break
    }

    if schemeKind == .file, ASCII.Lowercased(asciiDomain).elementsEqual("localhost".utf8) {
      self = .empty
      return
    }
    self = .asciiDomain(asciiDomainInfo)
  }

  /// Parses the given opaque hostname, returning an `_OpaqueHostnameInfo` if the hostname is valid.
  ///
  @inlinable
  internal static func _tryParseOpaqueHostname<UTF8Bytes, Callback>(
    _ hostname: UTF8Bytes, callback: inout Callback
  ) -> _OpaqueHostnameInfo? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    guard hostname.isEmpty == false else {
      return nil
    }
    var hostnameInfo = _OpaqueHostnameInfo(needsPercentEncoding: false, encodedCount: 0)
    for byte in hostname {
      hostnameInfo.encodedCount += 1
      guard let asciiChar = ASCII(byte) else {
        hostnameInfo.needsPercentEncoding = true
        hostnameInfo.encodedCount += 2
        continue  // Non-ASCII codepoints checked by 'validateURLCodePointsAndPercentEncoding', are not fatal.
      }
      if asciiChar.isForbiddenHostCodePoint, asciiChar != .percentSign {
        callback.validationError(.hostForbiddenCodePoint)
        return nil
      }
      if PercentEncodeSet.C0Control.shouldPercentEncode(ascii: asciiChar.codePoint) {
        hostnameInfo.needsPercentEncoding = true
        hostnameInfo.encodedCount += 2
      }
    }
    validateURLCodePointsAndPercentEncoding(hostname, callback: &callback)
    return hostnameInfo
  }

  /// Parses the given domain, returning an `_ASCIIDomainInfo` if the domain is a valid, ASCII domain.
  ///
  /// If the returned value's `domainInfo` is `nil`, parsing may have failed because the domain contained non-ASCII codepoints, or
  /// some of its labels were IDNA-encoded. In this case, the returned value's `mayBeValidIDNA` flag will be set to `true`, and the host-parser
  /// should try to parse the domain using IDNA.
  ///
  @inlinable
  internal static func _tryParseASCIIDomain<UTF8Bytes, Callback>(
    _ domain: LazilyPercentDecodedUTF8WithoutSubstitutions<UTF8Bytes>, callback: inout Callback
  ) -> (mayBeValidIDNA: Bool, domainInfo: _ASCIIDomainInfo?)
  where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    var domainInfo = _ASCIIDomainInfo(decodedCount: 0, needsDecodeOrLowercasing: false)

    guard hasIDNAPrefix(utf8: domain) == false else {
      callback.validationError(.domainToASCIIFailure)
      return (true, nil)
    }
    var i = domain.startIndex
    while i < domain.endIndex {
      guard let char = ASCII(domain[i]) else {
        callback.validationError(.domainToASCIIFailure)
        return (true, nil)
      }
      if char.isForbiddenHostCodePoint {
        callback.validationError(.hostForbiddenCodePoint)
        return (false, nil)
      }
      domainInfo.needsDecodeOrLowercasing = domainInfo.needsDecodeOrLowercasing || i.isDecoded || char.isUppercaseAlpha
      domainInfo.decodedCount &+= 1
      domain.formIndex(after: &i)
      if char == .period {
        guard hasIDNAPrefix(utf8: domain[i...]) == false else {
          callback.validationError(.domainToASCIIFailure)
          return (true, nil)
        }
      }
    }
    return (false, domainInfo)
  }
}

@usableFromInline
internal struct _ASCIIDomainInfo {

  @usableFromInline
  internal var decodedCount: Int

  @usableFromInline
  internal var needsDecodeOrLowercasing: Bool

  @inlinable
  internal init(decodedCount: Int, needsDecodeOrLowercasing: Bool) {
    self.decodedCount = decodedCount
    self.needsDecodeOrLowercasing = needsDecodeOrLowercasing
  }
}

@usableFromInline
internal struct _OpaqueHostnameInfo {

  @usableFromInline
  internal var needsPercentEncoding: Bool

  @usableFromInline
  internal var encodedCount: Int

  @inlinable
  internal init(needsPercentEncoding: Bool, encodedCount: Int) {
    self.needsPercentEncoding = needsPercentEncoding
    self.encodedCount = encodedCount
  }
}


// --------------------------------------------
// MARK: - Writing
// --------------------------------------------


extension ParsedHost {

  /// Writes a normalized hostname using the given `Writer` instance.
  /// `bytes` must be the same collection this `ParsedHost` was created for.
  ///
  @inlinable
  internal func write<UTF8Bytes, Writer>(
    bytes: UTF8Bytes, using writer: inout Writer
  ) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Writer: HostnameWriter {

    switch self {
    case .empty:
      writer.writeHostname(lengthIfKnown: 0) { $0(EmptyCollection()) }

    case .asciiDomain(let domainInfo):
      if domainInfo.needsDecodeOrLowercasing {
        writer.writeHostname(lengthIfKnown: domainInfo.decodedCount) {
          $0(ASCII.Lowercased(bytes.lazy.percentDecodedUTF8))
        }
      } else {
        writer.writeHostname(lengthIfKnown: domainInfo.decodedCount) {
          $0(bytes)
        }
      }

    case .opaque(let hostnameInfo):
      if hostnameInfo.needsPercentEncoding {
        writer.writeHostname(lengthIfKnown: hostnameInfo.encodedCount) { writePiece in
          _ = bytes.lazy.percentEncodedGroups(as: \.c0Control).write(to: writePiece)
        }
      } else {
        writer.writeHostname(lengthIfKnown: hostnameInfo.encodedCount) { writePiece in
          writePiece(bytes)
        }
      }

    // For IPv4/v6 addresses, it's actually faster not to use 'lengthIfKnown' because it means
    // hoisting '.serializedDirect' outside of 'writeHostname', and for some reason that's a lot slower.
    case .ipv4Address(let addr):
      writer.writeHostname(lengthIfKnown: nil) { (writePiece: (UnsafeRawBufferPointer) -> Void) in
        var serialized = addr.serializedDirect
        withUnsafeBytes(of: &serialized.buffer) { bufferBytes in
          writePiece(UnsafeRawBufferPointer(start: bufferBytes.baseAddress, count: Int(serialized.count)))
        }
      }

    case .ipv6Address(let addr):
      writer.writeHostname(lengthIfKnown: nil) { (writePiece: (UnsafeRawBufferPointer) -> Void) in
        var serialized = addr.serializedDirect
        withUnsafeBytes(of: &serialized.buffer) { bufferBytes in
          var bracket = ASCII.leftSquareBracket.codePoint
          withUnsafeMutableBytes(of: &bracket) { bracketPtr in
            writePiece(UnsafeRawBufferPointer(bracketPtr))
            writePiece(UnsafeRawBufferPointer(start: bufferBytes.baseAddress, count: Int(serialized.count)))
            bracketPtr.storeBytes(of: ASCII.rightSquareBracket.codePoint, as: UInt8.self)
            writePiece(UnsafeRawBufferPointer(bracketPtr))
          }
        }
      }
    }
  }
}
