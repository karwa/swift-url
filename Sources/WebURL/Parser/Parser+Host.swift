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

import IDNA

/// A description of a host that has been parsed from a string.
///
/// - seealso: `ParsedURLString`
///
@usableFromInline
internal enum ParsedHost {
  case toASCIINormalizedDomain(_ToASCIINormalizedDomainInfo)
  case simpleDomain(_ScannedDomainInfo)
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

    guard schemeKind.isSpecial else {
      guard let opaqueHostInfo = ParsedHost._parseOpaqueHostname(hostname, callback: &callback) else {
        return nil
      }
      self = .opaque(opaqueHostInfo)
      return
    }

    let result: Optional<ParsedHost>
    let needsPercentDecoding =
      hostname.withContiguousStorageIfAvailable {
        $0.boundsChecked.uncheckedFastContains(ASCII.percentSign.codePoint)
      } ?? true
    if needsPercentDecoding {
      result = ParsedHost._parseSpecialHostname(
        hostname.lazy.percentDecoded(), schemeKind, isPercentDecoded: true, callback: &callback
      )
    } else {
      result = ParsedHost._parseSpecialHostname(
        hostname, schemeKind, isPercentDecoded: false, callback: &callback
      )
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

  /// Parses the given special hostname, interpreting it as either some kind of domain or IPv4 address.
  /// If necessary, it will also normalize the hostname using IDNA compatibility processing.
  ///
  @inlinable
  internal static func _parseSpecialHostname<UTF8Bytes, Callback>(
    _ hostname: UTF8Bytes, _ scheme: WebURL.SchemeKind, isPercentDecoded: Bool, callback: inout Callback
  ) -> ParsedHost? where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

    switch ParsedHost._scanSpecialHostname(hostname, isPercentDecoded: isPercentDecoded, isLowercased: false) {

    // Simple domains:
    case .domain(let scannedInfo) where !scannedInfo.hasPunycodeLabels:
      if case .file = scheme, isLocalhost(utf8: hostname) {
        return .empty
      }
      return .simpleDomain(scannedInfo)

    // Other domains, non-ASCII:
    case .domain, .notASCII:
      var normalizedDomain = [UInt8]()
      normalizedDomain.reserveCapacity(hostname.underestimatedCount)
      let isValid = IDNA.toASCII(utf8: hostname) { byte in normalizedDomain.append(byte) }
      guard isValid, !normalizedDomain.isEmpty else {
        return nil
      }
      switch ParsedHost._scanSpecialHostname(normalizedDomain, isPercentDecoded: false, isLowercased: true) {
      case .domain(let scannedInfo):
        if case .file = scheme, isLocalhost(utf8: normalizedDomain) {
          return .empty
        }
        return .toASCIINormalizedDomain(
          _ToASCIINormalizedDomainInfo(
            codeUnits: normalizedDomain,
            hasPunycodeLabels: scannedInfo.hasPunycodeLabels
          )
        )
      case .endsInANumber:
        return IPv4Address(utf8: normalizedDomain).map { .ipv4Address($0) }
      case .forbiddenDomainCodePoint:
        callback.validationError(.hostOrDomainForbiddenCodePoint)
        return nil
      case .notASCII:
        fatalError("Output of IDNA.toASCII should be ASCII")
      }

    // IPv4:
    case .endsInANumber:
      return IPv4Address(utf8: hostname).map { .ipv4Address($0) }

    // Invalid:
    case .forbiddenDomainCodePoint:
      callback.validationError(.hostOrDomainForbiddenCodePoint)
      return nil
    }
  }

  /// Scans the given special hostname, checking that it only contains allowed, ASCII characters,
  /// and returning information which is useful to parse and write a normalized version of the hostname.
  ///
  @inlinable
  internal static func _scanSpecialHostname<UTF8Bytes>(
    _ hostname: UTF8Bytes, isPercentDecoded: Bool, isLowercased: Bool
  ) -> _ScanSpecialHostnameResult where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    var info = _ScannedDomainInfo(
      decodedCount: 0,
      // Store the bit which tells us whether this 'hostname' has been percent-decoded from its original form.
      needsPercentDecoding: isPercentDecoded,
      // Set 'needsLowercasing = isLowercased', so we short-circuit ASCII case checks if `isLowercased=true`.
      needsLowercasing: isLowercased,
      hasPunycodeLabels: hasIDNAPrefix(utf8: hostname)
    )

    var i = hostname.startIndex
    assert(i < hostname.endIndex, "hostname is empty")
    var startOfLastLabel = i

    while i < hostname.endIndex {
      guard let char = ASCII(hostname[i]) else {
        return .notASCII
      }
      if char.isForbiddenDomainCodePoint {
        return .forbiddenDomainCodePoint
      }
      info.needsLowercasing = info.needsLowercasing || char.isUppercaseAlpha
      info.decodedCount &+= 1
      hostname.formIndex(after: &i)

      if char == .period, i < hostname.endIndex {
        startOfLastLabel = i
        info.hasPunycodeLabels = info.hasPunycodeLabels || hasIDNAPrefix(utf8: hostname[i..<hostname.endIndex])
      }
    }

    // Fix-up after the short-circuit trick from above.
    info.needsLowercasing = !isLowercased && info.needsLowercasing

    var lastLabel = hostname[Range(uncheckedBounds: (startOfLastLabel, hostname.endIndex))]
    // Fast path: if the last label does not begin with a digit, it is not any kind of number we recognize.
    if let firstChar = lastLabel.fastPopFirst(), ASCII(firstChar)?.isDigit == true {
      if _asciiDomainLabelIsANumber(firstChar: firstChar, remainder: lastLabel) {
        return .endsInANumber
      }
    }

    return .domain(info)
  }

  /// Returns whether an ASCII domain label is a number.
  ///
  /// The label is provided in two parts: its initial character, and the remaining text.
  /// The initial character is assumed to be an ASCII digit, and the remaining text is assumed to be ASCII.
  /// If the domain ends with a trailing period, it may be included in `remainder`.
  ///
  @inlinable
  internal static func _asciiDomainLabelIsANumber<UTF8Bytes>(
    firstChar: UInt8, remainder: UTF8Bytes
  ) -> Bool where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, UTF8Bytes.SubSequence == UTF8Bytes {

    assert(ASCII(firstChar)?.isDigit == true)
    var remainder = remainder
    if remainder.last == ASCII.period.codePoint {
      remainder.removeLast()
    }

    guard let secondChar = remainder.fastPopFirst().flatMap({ ASCII($0) }) else {
      assert(remainder.isEmpty, "Found a non-ASCII character")
      return true
    }

    if secondChar.isDigit {
      return remainder.fastAllSatisfy({ ASCII($0)?.isDigit == true })

    } else if firstChar == ASCII.n0.codePoint, secondChar == .x || secondChar == .X {
      return remainder.fastAllSatisfy({ ASCII($0)?.isHexDigit == true })

    }
    return false
  }
}

@usableFromInline
internal enum _ScanSpecialHostnameResult {

  /// The hostname is a syntactically-allowed special URL host - meaning it is not empty,
  /// and contains only non-forbidden ASCII characters. Additionally, the hostname does not
  /// [end in a number][ends-in-a-number], so it should be interpreted as a domain.
  ///
  /// The `_ScannedDomainInfo` payload contains details about the domain which can be used to guide
  /// further processing - for example, whether or not the domain has any Punycode/IDNA labels
  /// (which require decoding and Unicode validation), or whether writing the normalized domain
  /// requires percent-decoding and/or lowercasing the source contents.
  ///
  /// [ends-in-a-number]: https://url.spec.whatwg.org/#ends-in-a-number-checker
  ///
  case domain(_ScannedDomainInfo)

  /// The hostname is a syntactically-allowed special URL host - meaning it is not empty,
  /// and contains only non-forbidden ASCII characters. Additionally, the hostname
  /// [ends in a number][ends-in-a-number], so it should be interpreted as an IPv4 address.
  ///
  /// [ends-in-a-number]: https://url.spec.whatwg.org/#ends-in-a-number-checker
  ///
  case endsInANumber

  /// The hostname contains non-ASCII code-points. Convert it using domain-to-ascii and try again.
  ///
  case notASCII

  /// The hostname contains forbidden domain code-points. It is not a valid domain or IPv4 address.
  ///
  case forbiddenDomainCodePoint
}

@usableFromInline
internal struct _ToASCIINormalizedDomainInfo {

  @usableFromInline
  internal var codeUnits: [UInt8]

  @usableFromInline
  internal var hasPunycodeLabels: Bool

  @inlinable
  internal init(codeUnits: [UInt8], hasPunycodeLabels: Bool) {
    self.codeUnits = codeUnits
    self.hasPunycodeLabels = hasPunycodeLabels
  }
}

@usableFromInline
internal struct _ScannedDomainInfo {

  @usableFromInline
  internal var decodedCount: Int

  @usableFromInline
  internal var needsPercentDecoding: Bool

  @usableFromInline
  internal var needsLowercasing: Bool

  @usableFromInline
  internal var hasPunycodeLabels: Bool

  @inlinable
  internal init(decodedCount: Int, needsPercentDecoding: Bool, needsLowercasing: Bool, hasPunycodeLabels: Bool) {
    self.decodedCount = decodedCount
    self.needsPercentDecoding = needsPercentDecoding
    self.needsLowercasing = needsLowercasing
    self.hasPunycodeLabels = hasPunycodeLabels
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

    case .toASCIINormalizedDomain(let idnaInfo):
      let kind: WebURL.HostKind = idnaInfo.hasPunycodeLabels ? .domainWithIDN : .domain
      writer.writeHostname(lengthIfKnown: idnaInfo.codeUnits.count, kind: kind) { $0(idnaInfo.codeUnits) }

    case .simpleDomain(let scannedInfo):
      assert(!scannedInfo.hasPunycodeLabels, "Domain is not simple")
      // It isn't worth splitting "needs percent decoding" from "needs lowercasing".
      // Only fast-path the case when no additional processing is required.
      if scannedInfo.needsPercentDecoding || scannedInfo.needsLowercasing {
        writer.writeHostname(lengthIfKnown: scannedInfo.decodedCount, kind: .domain) {
          $0(ASCII.Lowercased(bytes.lazy.percentDecoded()))
        }
      } else {
        writer.writeHostname(lengthIfKnown: scannedInfo.decodedCount, kind: .domain) {
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
