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
    if ipv6Slice.removeFirst() == ASCII.leftSquareBracket.codePoint {
      guard ipv6Slice.popLast() == ASCII.rightSquareBracket.codePoint else {
        callback.validationError(.unclosedIPv6Address)
        return nil
      }
      guard let result = IPv6Address.parse(utf8: ipv6Slice, callback: &callback) else {
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
      if ascii.isForbiddenHostCodePoint {
        callback.validationError(.hostForbiddenCodePoint)
        return nil
      }
    }
    let asciiDomain = domain

    var ipv4Error = LastValidationError()
    switch IPv4Address.parse(utf8: asciiDomain, callback: &ipv4Error) {
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
      if asciiChar.isForbiddenHostCodePoint, asciiChar != .percentSign {
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
      writer.writeHostname { writePiece in
        // TODO: [performance] - store whether %-encoding was required in URLMetrics.
        _ = bytes.lazy.percentEncoded(using: URLEncodeSet.C0.self).write(to: writePiece)
      }

    case .ipv4Address(let addr):
      writer.writeHostname { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
        var serialized = addr.serializedDirect
        withUnsafeBytes(of: &serialized.buffer) { bufferBytes in
          let codeunits = bufferBytes.bindMemory(to: UInt8.self).prefix(Int(serialized.count))
          writePiece(UnsafeBufferPointer(rebasing: codeunits))
        }
      }

    case .ipv6Address(let addr):
      writer.writeHostname { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
        var serialized = addr.serializedDirect
        var bracket = ASCII.leftSquareBracket.codePoint
        withUnsafeMutablePointer(to: &bracket) { bracketPtr in
          writePiece(UnsafeBufferPointer(start: bracketPtr, count: 1))
          withUnsafeBytes(of: &serialized.buffer) { bufferBytes in
            let codeunits = bufferBytes.bindMemory(to: UInt8.self).prefix(Int(serialized.count))
            writePiece(UnsafeBufferPointer(rebasing: codeunits))
          }
          bracketPtr.pointee = ASCII.rightSquareBracket.codePoint
          writePiece(UnsafeBufferPointer(start: bracketPtr, count: 1))
        }
      }
    }
  }
}
