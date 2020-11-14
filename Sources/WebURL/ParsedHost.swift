/// A description of a host that has been parsed from a string.
///
/// - seealso: `ParsedURLString`
///
enum ParsedHost: Equatable {
  case domain
  case ipv4Address(IPv4Address)
  case ipv6Address(IPv6Address)
  case opaque
  case empty
}

// Parsing and serialization.

extension ParsedHost {

  /// Parses the given hostname to determine what kind of host it is, and whether or not it is valid.
  /// The created `ParsedHost` object may then be used to write a normalized/encoded version of the hostname.
  ///
  init?<Bytes, Callback>(
    _ hostname: Bytes, schemeKind: WebURL.SchemeKind, callback: inout Callback
  ) where Bytes: BidirectionalCollection, Bytes.Element == UInt8, Callback: URLParserCallback {

    guard hostname.isEmpty == false else {
      self = .empty
      return
    }
    var ipv6Slice = hostname[...]
    if ipv6Slice.removeFirst() == ASCII.leftSquareBracket {
      guard ipv6Slice.popLast() == ASCII.rightSquareBracket else {
        callback.validationError(.unclosedIPv6Address)
        return nil
      }
      guard let result = IPv6Address.parse(ipv6Slice, callback: &callback) else {
        return nil
      }
      self = .ipv6Address(result)
      return
    }
    guard schemeKind.isSpecial else {
      guard Self.isValidOpaqueHostname(hostname, callback: &callback) else {
        return nil
      }
      self = .opaque
      return
    }

    let domain = hostname.lazy.percentDecoded
    // TODO: [idna]
    //
    // 6. Let asciiDomain be the result of running domain to ASCII on domain.
    //
    // 7. If asciiDomain is failure, validation error, return failure.
    //
    // Because we don't have IDNA transformations, reject all non-ASCII domain names and
    // lazily lowercase them.
    // Additionally, lowercasing is deferred until after IPv4 addresses are parsed, since it doesn't
    // care about the case of alpha characters.
    for byte in domain {
      guard let ascii = ASCII(byte) else {
        callback.validationError(.domainToASCIIFailure)
        return nil
      }
      if URLStringUtils.isForbiddenHostCodePoint(ascii) {
        callback.validationError(.hostForbiddenCodePoint)
        return nil
      }
    }
    let asciiDomain = domain

    var ipv4Error = LastValidationError()
    switch IPv4Address.parse(asciiDomain, callback: &ipv4Error) {
    case .success(let address):
      self = .ipv4Address(address)
      return
    case .failure:
      callback.validationError(ipv4Error.error!)
      return nil
    case .notAnIPAddress:
      break
    }

    if schemeKind == .file, ASCII.Lowercased(asciiDomain).elementsEqual("localhost".utf8) {
      self = .empty
      return
    }
    self = .domain
  }

  private static func isValidOpaqueHostname<Bytes, Callback>(
    _ hostname: Bytes, callback: inout Callback
  ) -> Bool where Bytes: Collection, Bytes.Element == UInt8, Callback: URLParserCallback {

    guard hostname.isEmpty == false else {
      return false  // Opaque hosts are defined to be non-empty.
    }
    for byte in hostname {
      // Non-ASCII codepoints checked by 'validateURLCodePointsAndPercentEncoding'.
      guard let asciiChar = ASCII(byte) else {
        continue
      }
      if URLStringUtils.isForbiddenHostCodePoint(asciiChar), asciiChar != .percentSign {
        callback.validationError(.hostForbiddenCodePoint)
        return false
      }
    }
    validateURLCodePointsAndPercentEncoding(hostname, callback: &callback)
    return true
  }

  /// Writes a normalized hostname using the given `Writer` instance.
  /// `bytes` must be the same collection this `ParsedHost` was created for.
  ///
  func write<Bytes, Writer>(
    bytes: Bytes, using writer: inout Writer
  ) where Bytes: BidirectionalCollection, Bytes.Element == UInt8, Writer: HostnameWriter {

    switch self {
    case .empty:
      writer.writeHostname { $0(EmptyCollection()) }

    case .domain:
      // This is our cheap substitute for IDNA. Only valid for ASCII domains.
      assert(bytes.isEmpty == false)
      let transformed = ASCII.Lowercased(bytes.lazy.percentDecoded)
      writer.writeHostname { $0(transformed) }

    case .opaque:
      assert(bytes.isEmpty == false)
      writer.writeHostname { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
        // TODO: [performance] - store whether %-encoding was required in URLMetrics.
        _ = bytes
          .lazy.percentEncoded(using: URLEncodeSet.C0.self)
          .writeBuffered { piece in writePiece(piece) }
      }

    // TODO: [performance] - Write IPv4+v6 addresses directly, rather than going through String.
    case .ipv4Address(let addr):
      writer.writeHostname { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
        var str = addr.serialized
        str.withUTF8 { writePiece($0) }
      }

    case .ipv6Address(let addr):
      var str = addr.serialized
      writer.writeHostname { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
        var bracket = ASCII.leftSquareBracket.codePoint
        withUnsafeMutablePointer(to: &bracket) { bracketPtr in
          writePiece(UnsafeBufferPointer(start: bracketPtr, count: 1))
          str.withUTF8 { writePiece($0) }
          bracketPtr.pointee = ASCII.rightSquareBracket.codePoint
          writePiece(UnsafeBufferPointer(start: bracketPtr, count: 1))
        }
      }
    }
  }
}
