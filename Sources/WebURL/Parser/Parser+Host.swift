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
      guard let address = IPv6Address(utf8: ipv6Slice) else {
        callback.validationError(.invalidIPv6Address)
        return nil
      }
      self = .ipv6Address(address)
      return
    }

    guard schemeKind.isSpecial else {
      guard let hostnameInfo = ParsedHost._tryParseOpaqueHostname(hostname, callback: &callback) else {
        return nil
      }
      self = .opaque(hostnameInfo)
      return
    }

    let domain = hostname.lazy.percentDecoded()

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

    switch ParsedHost._tryParseDomain(domain, callback: &callback) {
    case .containsUnicodeOrIDNA:
      return nil
    case .forbiddenHostCodePoint:
      return nil
    case .endsInANumber:
      guard let address = IPv4Address(utf8: domain) else {
        return nil
      }
      self = .ipv4Address(address)
      return
    case .asciiDomain(let asciiDomainInfo):
      if schemeKind == .file, ASCII.Lowercased(domain).elementsEqual("localhost".utf8) {
        self = .empty
        return
      }
      self = .asciiDomain(asciiDomainInfo)
    }
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
      if URLEncodeSet.C0Control().shouldPercentEncode(ascii: asciiChar.codePoint) {
        hostnameInfo.needsPercentEncoding = true
        hostnameInfo.encodedCount += 2
      }
    }
    validateURLCodePointsAndPercentEncoding(utf8: hostname, callback: &callback)
    return hostnameInfo
  }

  /// Parses the given domain, returning information about which kind of domain it is, and some details which are useful to write a normalized version
  /// of the domain.
  ///
  @inlinable
  internal static func _tryParseDomain<UTF8Bytes, Callback>(
    _ domain: LazilyPercentDecoded<UTF8Bytes>, callback: inout Callback
  ) -> _DomainParseResult
  where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    var domainInfo = _ASCIIDomainInfo(decodedCount: 0, needsDecodeOrLowercasing: false)

    guard hasIDNAPrefix(utf8: domain) == false else {
      callback.validationError(.domainToASCIIFailure)
      return .containsUnicodeOrIDNA
    }

    var i = domain.startIndex
    var startOfLastLabel = i

    while i < domain.endIndex {
      guard let char = ASCII(domain[i]) else {
        callback.validationError(.domainToASCIIFailure)
        return .containsUnicodeOrIDNA
      }
      if char.isForbiddenHostCodePoint {
        callback.validationError(.hostForbiddenCodePoint)
        return .forbiddenHostCodePoint
      }
      domainInfo.needsDecodeOrLowercasing =
        (domainInfo.needsDecodeOrLowercasing || i.isDecodedOrUnsubstituted || char.isUppercaseAlpha)
      domainInfo.decodedCount &+= 1
      domain.formIndex(after: &i)
      if char == .period {
        guard hasIDNAPrefix(utf8: domain[i...]) == false else {
          callback.validationError(.domainToASCIIFailure)
          return .containsUnicodeOrIDNA
        }
        if i < domain.endIndex {
          startOfLastLabel = i
        }
      }
    }

    var lastLabel = domain[startOfLastLabel...]
    if lastLabel.last == ASCII.period.codePoint {
      lastLabel.removeLast()
    }
    if !lastLabel.isEmpty {
      if lastLabel.allSatisfy({ ASCII($0)?.isDigit == true }) {
        return .endsInANumber
      } else if lastLabel.popFirst() == ASCII.n0.codePoint,
        lastLabel.popFirst().flatMap({ ASCII($0)?.lowercased }) == .x,
        lastLabel.allSatisfy({ ASCII($0)?.isHexDigit == true })
      {
        return .endsInANumber
      }
    }

    return .asciiDomain(domainInfo)
  }
}

@usableFromInline
internal enum _DomainParseResult {

  /// The given domain contains non-ASCII code-points or IDNA labels.
  /// Currently, these are not supported.
  ///
  case containsUnicodeOrIDNA

  /// The given domain contains forbidden host code-points.
  ///
  case forbiddenHostCodePoint

  /// The given domain's final label is a number, according to https://url.spec.whatwg.org/#ends-in-a-number-checker
  /// It should be parsed as an IPv4 address, rather than a domain.
  ///
  case endsInANumber

  /// The given domain appears to be valid, containing only ASCII characters and no IDNA.
  ///
  case asciiDomain(_ASCIIDomainInfo)
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
      writer.writeHostname(lengthIfKnown: 0, kind: .empty) { $0(EmptyCollection()) }

    case .asciiDomain(let domainInfo):
      if domainInfo.needsDecodeOrLowercasing {
        writer.writeHostname(lengthIfKnown: domainInfo.decodedCount, kind: .domain) {
          $0(ASCII.Lowercased(bytes.lazy.percentDecoded()))
        }
      } else {
        writer.writeHostname(lengthIfKnown: domainInfo.decodedCount, kind: .domain) {
          $0(bytes)
        }
      }

    case .opaque(let hostnameInfo):
      if hostnameInfo.needsPercentEncoding {
        writer.writeHostname(lengthIfKnown: hostnameInfo.encodedCount, kind: .opaque) { writePiece in
          _ = bytes.lazy.percentEncoded(using: .c0ControlSet).write(to: writePiece)
        }
      } else {
        writer.writeHostname(lengthIfKnown: hostnameInfo.encodedCount, kind: .opaque) { writePiece in
          writePiece(bytes)
        }
      }

    // For IPv4/v6 addresses, it's actually faster not to use 'lengthIfKnown' because it means
    // hoisting '.serializedDirect' outside of 'writeHostname', and for some reason that's a lot slower.
    case .ipv4Address(let addr):
      writer.writeHostname(lengthIfKnown: nil, kind: .ipv4Address) { (writePiece: (UnsafeRawBufferPointer) -> Void) in
        var serialized = addr.serializedDirect
        withUnsafeBytes(of: &serialized.buffer) { bufferBytes in
          writePiece(UnsafeRawBufferPointer(start: bufferBytes.baseAddress, count: Int(serialized.count)))
        }
      }

    case .ipv6Address(let addr):
      writer.writeHostname(lengthIfKnown: nil, kind: .ipv6Address) { (writePiece: (UnsafeRawBufferPointer) -> Void) in
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
