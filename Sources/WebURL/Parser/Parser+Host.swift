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

    guard !hostname.isEmpty else {
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

    let result: Optional<ParsedHost>

    if schemeKind.isSpecial {
      let needsPercentDecoding =
        hostname.withContiguousStorageIfAvailable {
          $0.boundsChecked.uncheckedFastContains(ASCII.percentSign.codePoint)
        } ?? true
      if !needsPercentDecoding {
        result = ParsedHost._parseDomainOrIPv4(
          hostname, scheme: schemeKind, isPercentDecoded: false, callback: &callback
        )
      } else {
        result = ParsedHost._parseDomainOrIPv4(
          hostname.lazy.percentDecoded(), scheme: schemeKind, isPercentDecoded: true, callback: &callback
        )
      }
    } else {
      result = ParsedHost._parseOpaqueHostname(hostname, callback: &callback).map { .opaque($0) }
    }

    if let result = result {
      self = result
    } else {
      return nil
    }
  }

  /// Parses the given opaque hostname, returning an `_OpaqueHostnameInfo` if the hostname is valid.
  ///
  @inlinable
  internal static func _parseOpaqueHostname<UTF8Bytes, Callback>(
    _ hostname: UTF8Bytes, callback: inout Callback
  ) -> _OpaqueHostnameInfo? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    assert(!hostname.isEmpty)

    var hostnameInfo = _OpaqueHostnameInfo(needsPercentEncoding: false, encodedCount: 0)
    for byte in hostname {
      hostnameInfo.encodedCount &+= 1
      guard let asciiChar = ASCII(byte) else {
        hostnameInfo.needsPercentEncoding = true
        hostnameInfo.encodedCount &+= 2
        continue
      }
      if asciiChar.isForbiddenHostCodePoint {
        callback.validationError(.hostOrDomainForbiddenCodePoint)
        return nil
      }
      if URLEncodeSet.C0Control().shouldPercentEncode(ascii: asciiChar.codePoint) {
        hostnameInfo.needsPercentEncoding = true
        hostnameInfo.encodedCount &+= 2
      }
    }

    return hostnameInfo
  }

  /// Parses the given domain or IPv4 address.
  ///
  @inlinable
  internal static func _parseDomainOrIPv4<UTF8Bytes, Callback>(
    _ domain: UTF8Bytes, scheme: WebURL.SchemeKind, isPercentDecoded: Bool, callback: inout Callback
  ) -> ParsedHost? where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    switch ParsedHost._parseASCIIDomain(domain, isPercentDecoded: isPercentDecoded) {
    case .containsUnicodeOrIDNA:
      // TODO: Handle domains conaining Unicode or IDNA labels.
      callback.validationError(.domainToASCIIFailure)
      return nil
    case .forbiddenDomainCodePoint:
      callback.validationError(.hostOrDomainForbiddenCodePoint)
      return nil
    case .endsInANumber:
      guard let address = IPv4Address(utf8: domain) else {
        return nil
      }
      return .ipv4Address(address)
    case .asciiDomain(let asciiDomainInfo):
      if case .file = scheme, isLocalhost(utf8: domain) {
        return .empty
      }
      return .asciiDomain(asciiDomainInfo)
    }
  }

  /// Parses the given domain as ASCII, returning information about which kind of domain it is,
  /// and some details which are useful to write a normalized version of the domain.
  ///
  @inlinable
  internal static func _parseASCIIDomain<UTF8Bytes>(
    _ domain: UTF8Bytes, isPercentDecoded: Bool
  ) -> _DomainParseResult where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    assert(!domain.isEmpty)
    var domainInfo = _ASCIIDomainInfo(decodedCount: 0, needsPercentDecoding: isPercentDecoded, needsLowercasing: false)

    guard !hasIDNAPrefix(utf8: domain) else {
      return .containsUnicodeOrIDNA
    }

    var i = domain.startIndex
    var startOfLastLabel = i

    while i < domain.endIndex {
      guard let char = ASCII(domain[i]) else {
        return .containsUnicodeOrIDNA
      }
      if char.isForbiddenDomainCodePoint {
        return .forbiddenDomainCodePoint
      }
      domainInfo.needsLowercasing = domainInfo.needsLowercasing || char.isUppercaseAlpha
      domainInfo.decodedCount &+= 1
      domain.formIndex(after: &i)

      if char == .period {
        guard !hasIDNAPrefix(utf8: domain[Range(uncheckedBounds: (i, domain.endIndex))]) else {
          return .containsUnicodeOrIDNA
        }
        if i < domain.endIndex {
          startOfLastLabel = i
        }
      }
    }

    var lastLabel = domain[Range(uncheckedBounds: (startOfLastLabel, domain.endIndex))]
    // Fast path: if the last label does not begin with a digit, it is not any kind of number we recognize.
    if let firstChar = lastLabel.fastPopFirst(), ASCII(firstChar)?.isDigit == true {
      if _domainLabelIsANumber(firstChar: firstChar, remainder: lastLabel) {
        return .endsInANumber
      }
    }

    return .asciiDomain(domainInfo)
  }

  /// Returns whether an ASCII domain label is a number.
  ///
  /// The label is provided in two parts: its initial character, and the remaining text.
  /// The initial character is assumed to be an ASCII digit, and the remaining text is assumed to be ASCII.
  /// If the domain ends with a trailing period, it may be included in `remainder`.
  ///
  @inlinable
  internal static func _domainLabelIsANumber<UTF8Bytes>(
    firstChar: UInt8, remainder: UTF8Bytes
  ) -> Bool where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, UTF8Bytes.SubSequence == UTF8Bytes {

    assert(ASCII(firstChar)?.isDigit == true)
    var remainder = remainder
    if remainder.last == ASCII.period.codePoint {
      remainder.removeLast()
    }
    guard let secondChar = remainder.fastPopFirst().flatMap({ ASCII($0) }) else {
      return true  // The first character is a digit, and the second is assumed ASCII if present.
    }
    if secondChar.isDigit {
      if remainder.fastAllSatisfy({ ASCII($0)?.isDigit == true }) {
        return true
      }
    } else if firstChar == ASCII.n0.codePoint, secondChar == .x || secondChar == .X {
      if remainder.fastAllSatisfy({ ASCII($0)?.isHexDigit == true }) {
        return true
      }
    }
    return false
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
  case forbiddenDomainCodePoint

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
  internal var needsPercentDecoding: Bool

  @usableFromInline
  internal var needsLowercasing: Bool

  @inlinable
  internal init(decodedCount: Int, needsPercentDecoding: Bool, needsLowercasing: Bool) {
    self.decodedCount = decodedCount
    self.needsPercentDecoding = needsPercentDecoding
    self.needsLowercasing = needsLowercasing
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
      // It isn't worth splitting "needs percent decoding" from "needs lowercasing".
      // Only fast-path the case when no additional processing is required.
      if domainInfo.needsPercentDecoding || domainInfo.needsLowercasing {
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
