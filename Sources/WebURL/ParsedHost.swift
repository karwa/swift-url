enum ParsedHost: Equatable {
  case domain
  case ipv4Address(IPv4Address)
  case ipv6Address(IPv6Address)
  case opaque
  case empty
}

// Parsing and serialization.

extension ParsedHost {

  static func parse<Bytes, Callback>(
    _ input: Bytes, isNotSpecial: Bool = false, callback: inout Callback
  ) -> Self? where Bytes: BidirectionalCollection, Bytes.Element == UInt8, Callback: URLParserCallback {

    guard input.isEmpty == false else {
      return .empty
    }
    var ipv6Slice = input[...]
    if ipv6Slice.removeFirst() == ASCII.leftSquareBracket {
      guard ipv6Slice.popLast() == ASCII.rightSquareBracket else {
        callback.validationError(.unclosedIPv6Address)
        return nil
      }
      return IPv6Address.parse(ipv6Slice, callback: &callback).map { .ipv6Address($0) }
    }

    if isNotSpecial {
      return validateOpaqueHostname(input, callback: &callback) ? .opaque : nil
    }

    let domain = input.lazy.percentDecoded
    // TODO:
    //
    // 6. Let asciiDomain be the result of running domain to ASCII on domain.
    //
    // 7. If asciiDomain is failure, validation error, return failure.
    //
    // Because we don't have IDNA transformations, reject all non-ASCII domain names and
    // lazily lowercase them.
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
    let asciiDomain = domain  //LowercaseASCIITransformer(base: domain)

    var ipv4Error = LastValidationError()
    switch IPv4Address.parse(asciiDomain, callback: &ipv4Error) {
    case .success(let address):
      return .ipv4Address(address)
    case .failure:
      callback.validationError(ipv4Error.error!)
      return nil
    case .notAnIPAddress:
      break
    }
    return .domain
  }

  static func validateOpaqueHostname<Bytes, Callback>(
    _ input: Bytes, callback: inout Callback
  ) -> Bool where Bytes: Collection, Bytes.Element == UInt8, Callback: URLParserCallback {
    // This isn't technically in the spec algorithm, but opaque hosts are defined to be non-empty.
    guard input.isEmpty == false else {
      return false
    }
    for byte in input {
      // Non-ASCII codepoints checked by 'validateURLCodePointsAndPercentEncoding'.
      guard let asciiChar = ASCII(byte) else {
        continue
      }
      if URLStringUtils.isForbiddenHostCodePoint(asciiChar) && asciiChar != .percentSign {
        callback.validationError(.hostForbiddenCodePoint)
        return false
      }
    }
    if Callback.self != IgnoreValidationErrors.self {
      validateURLCodePointsAndPercentEncoding(input, callback: &callback)
    }
    return true
  }

  func write<Bytes, Writer>(bytes: Bytes, using writer: inout Writer)
  where Bytes: BidirectionalCollection, Bytes.Element == UInt8, Writer: URLWriter {
    switch self {
    case .empty:
      break  // Nothing to do.
    case .domain:
      // This is our cheap substitute for IDNA. Only valid for ASCII domains.
      assert(bytes.isEmpty == false)
      let transformed = LowercaseASCIITransformer(base: bytes.lazy.percentDecoded)
      writer.writeHostname { $0(transformed) }
    case .opaque:
      assert(bytes.isEmpty == false)
      writer.writeHostname { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
        PercentEncoding.encode(bytes: bytes, using: URLEncodeSet.C0.self) { piece in
          writePiece(piece)
        }
      }
    // TODO: Write IP addresses directly to the output, rather than going through String.
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
