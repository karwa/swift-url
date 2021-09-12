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


// --------------------------------------------
// MARK: - Parser Callbacks
// --------------------------------------------
// Almost no users of this type care about the specific errors
// that occur during parsing - but there are use-cases, and it's
// helpful for testing. It's important that regular, release-builds
// of the IP address parsers optimize out and around error reporting,
// so the callback needs to take advantage of generic specialization.
// --------------------------------------------


@usableFromInline
internal protocol IPAddressParserCallback {
  mutating func validationError(ipv6 error: IPv6Address.ParserError)
  mutating func validationError(ipv4 error: IPv4Address.ParserError)
}

@usableFromInline
internal struct IgnoreIPAddressParserErrors: IPAddressParserCallback {

  @inlinable
  internal init() {}

  @inlinable @inline(__always)
  internal func validationError(ipv6 error: IPv6Address.ParserError) {}

  @inlinable @inline(__always)
  internal func validationError(ipv4 error: IPv4Address.ParserError) {}
}


// --------------------------------------------
// MARK: - Byte Order
// --------------------------------------------


/// The way in which octets are arranged to form a multi-byte integer.
///
/// Applications should prefer to work with individual octets wherever possible, as octets have a consistent numeric interpretation and binary representation
/// across machines of different endianness.
///
/// When combining octets in to larger (e.g. 16- or 32-bit) integers, we have to consider that machines have a choice in how their octets are arranged in memory.
/// For instance, the first piece of the IPv6 address `2608::3:5` consists of 2 octets, `0x26` and `0x08`; if we created a 16-bit integer with those same octets
/// arranged in that order, a big-endian machine would read this as having numeric value 9736 (for the purposes of integer-level operations, such as addition),
/// whereas a little-endian machine would consider the same octets to contain the numeric value 2086.
///
/// Hence there are 2 ways to combine octets in to larger integers:
///
///  1. With the same octets in the same order in memory. We call this the `binary` interpretation, although it is more-commonly known as
///    "network" byte order, or big-endian. As noted above, integers derived from the same address using the `binary` interpretation
///    may have different numeric values on different machines.
///
///  2. By rearranging octets to give a consistent numeric value. We call this the `numeric` interpretation, although it is more-comonly known as
///    "host" byte-order. For instance, when reading the first 16-bit piece of the above address on a little-endian machine,
///    the octets `0x26 0x08` will be reordered to `0x08 0x26`, so that the numeric value (9736) is the same as the hexadecimal number `0x2608`.
///    Assigning a group of octets using the `numeric` integer 9736 will similarly reorder the octets, so that they appear as the octet sequence `0x26 0x08`
///    in the address.
///
public enum OctetArrangement {

  /// Offers consistent numeric values across machines of different endianness, by adjusting the binary representation when reading or writing multi-byte integers.
  /// Also known as host byte order (i.e. the integers that you read and write are expected to be in host byte order).
  ///
  case numeric

  /// Offers consistent binary representations across machines of different endianness, although each machine may interpret those bits as a different numeric value.
  /// Also known as network byte order (i.e. the integers that you read and write are expected to be in network byte order).
  ///
  case binary

  /// A synonym for `.numeric`.
  @inlinable public static var hostOrder: Self { return .numeric }

  /// A synonym for `.binary`.
  @inlinable public static var networkOrder: Self { return .binary }
}


// --------------------------------------------
// MARK: - IPv6
// --------------------------------------------


/// A 128-bit numerical identifier assigned to a device on an
/// [Internet Protocol, version 6](https://tools.ietf.org/html/rfc2460) network.
///
public struct IPv6Address {

  public typealias Octets = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  /// The octets of this address.
  public var octets: Octets

  /// Creates an address with the given octets.
  @inlinable
  public init(octets: Octets = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) {
    self.octets = octets
  }

  public typealias Pieces = (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16)

  /// Creates an address from the given 16-bit integer pieces.
  ///
  /// - seealso: `OctetArrangement`
  /// - parameters:
  ///     - pieces:            The integer pieces of the address.
  ///     - octetArrangement:  How the octets in each integer of `pieces` are arranged:
  ///                          <ul>
  ///                          <li>If `numeric`, the integers are assumed to be in "host byte order", and their octets will be rearranged if necessary.</li>
  ///                          <li>If `binary`, the integers are assumed to be in "network byte order", and their octets will be stored in the order
  ///                              they are in.</li>
  ///                          </ul>
  ///
  @inlinable
  public init(pieces: Pieces, _ octetArrangement: OctetArrangement) {
    self.init()
    self[pieces: octetArrangement] = pieces
  }

  /// The address, expressed as 16-bit integer pieces.
  ///
  /// - seealso: `OctetArrangement`
  /// - parameters:
  ///     - octetArrangement:  How the octets in each integer of `pieces` are arranged:
  ///                          <ul>
  ///                          <li>If `numeric`, the integers are assumed to be in "host byte order", and their octets will be rearranged if necessary.</li>
  ///                          <li>If `binary`, the integers are assumed to be in "network byte order", and their octets will be stored in the order
  ///                              they are in.</li>
  ///                          </ul>
  ///
  @inlinable
  public subscript(pieces octetArrangement: OctetArrangement) -> Pieces {
    get {
      let networkOrder = withUnsafeBytes(of: octets) { $0.load(as: Pieces.self) }
      switch octetArrangement {
      case .binary:
        return networkOrder
      case .numeric:
        return (
          UInt16(bigEndian: networkOrder.0), UInt16(bigEndian: networkOrder.1), UInt16(bigEndian: networkOrder.2),
          UInt16(bigEndian: networkOrder.3), UInt16(bigEndian: networkOrder.4), UInt16(bigEndian: networkOrder.5),
          UInt16(bigEndian: networkOrder.6), UInt16(bigEndian: networkOrder.7)
        )
      }
    }
    set {
      switch octetArrangement {
      case .binary:
        withUnsafeBytes(of: newValue) { src in
          withUnsafeMutableBytes(of: &octets) { dst in
            dst.copyBytes(from: src)
          }
        }
      case .numeric:
        self[pieces: .binary] = (
          newValue.0.bigEndian, newValue.1.bigEndian, newValue.2.bigEndian,
          newValue.3.bigEndian, newValue.4.bigEndian, newValue.5.bigEndian,
          newValue.6.bigEndian, newValue.7.bigEndian
        )
      }
    }
  }
}

// Standard protocols.

extension IPv6Address: Equatable, Hashable, LosslessStringConvertible {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    return withUnsafeBytes(of: lhs.octets) { lhsBytes in
      return withUnsafeBytes(of: rhs.octets) { rhsBytes in
        return lhsBytes.elementsEqual(rhsBytes)
      }
    }
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    withUnsafeBytes(of: octets) { hasher.combine(bytes: $0) }
  }

  @inlinable
  public var description: String {
    return serialized
  }
}

extension IPv6Address: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let parsedValue = IPv6Address(string) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid IPv6 Address"
      )
    }
    self = parsedValue
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.serialized)
  }
}

// Parsing.

extension IPv6Address {

  /// Parses an IPv6 address from a String.
  ///
  /// Accepted formats are documented in [Section 2.2][rfc4291] ("Text Representation of Addresses") of
  /// IP Version 6 Addressing Architecture (RFC 4291).
  ///
  /// [rfc4291]: https://tools.ietf.org/html/rfc4291#section-2.2
  ///
  /// - parameters:
  ///     - description: The string to parse.
  ///
  @inlinable @inline(__always)
  public init?<S>(_ description: S) where S: StringProtocol {
    self.init(utf8: description.utf8)
  }

  /// Parses an IPv6 address from a collection of UTF-8 code-units.
  ///
  /// Accepted formats are documented in [Section 2.2][rfc4291] ("Text Representation of Addresses") of
  /// IP Version 6 Addressing Architecture (RFC 4291).
  ///
  /// [rfc4291]: https://tools.ietf.org/html/rfc4291#section-2.2
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  @inlinable @inline(__always)
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    var callback = IgnoreIPAddressParserErrors()
    let _parsed =
      utf8.withContiguousStorageIfAvailable {
        IPv6Address.parse(utf8: $0.boundsChecked, callback: &callback)
      } ?? IPv6Address.parse(utf8: utf8, callback: &callback)
    guard let parsed = _parsed else {
      return nil
    }
    self = parsed
  }
}

extension IPv6Address {

  @inlinable
  internal static func parse<UTF8Bytes, Callback>(
    utf8: UTF8Bytes, callback: inout Callback
  ) -> Self? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: IPAddressParserCallback {

    guard utf8.isEmpty == false else {
      callback.validationError(ipv6: .emptyInput)
      return nil
    }

    var _parsedPieces: IPv6Address.Pieces = (0, 0, 0, 0, 0, 0, 0, 0)
    return withUnsafeMutableBufferPointerToElements(tuple: &_parsedPieces) { parsedPieces -> Self? in
      var pieceIndex = 0
      var expandFrom = -1  // The index of the piece after the compressed range. -1 means no compression.
      var idx = utf8.startIndex

      if utf8[idx] == ASCII.colon.codePoint {
        utf8.formIndex(after: &idx)
        guard idx < utf8.endIndex, utf8[idx] == ASCII.colon.codePoint else {
          callback.validationError(ipv6: .unexpectedLeadingColon)
          return nil
        }
        utf8.formIndex(after: &idx)
        pieceIndex &+= 1
        expandFrom = pieceIndex
      }

      parseloop: while idx < utf8.endIndex {
        guard pieceIndex != 8 else {
          callback.validationError(ipv6: .tooManyPieces)
          return nil
        }
        guard utf8[idx] != ASCII.colon.codePoint else {
          guard expandFrom == -1 else {
            callback.validationError(ipv6: .multipleCompressedPieces)
            return nil
          }
          utf8.formIndex(after: &idx)
          pieceIndex &+= 1
          expandFrom = pieceIndex
          continue parseloop
        }
        // Parse a hex-numeric value.
        // Byte-swap if necessary so the octets represent the same numeric value in network byte order.
        let pieceStartIndex = idx
        var value: UInt16 = 0
        var length: UInt8 = 0
        while length < 4, idx < utf8.endIndex, let numberValue = ASCII(utf8[idx])?.hexNumberValue {
          value <<= 4
          value &+= UInt16(numberValue)
          length &+= 1
          utf8.formIndex(after: &idx)
        }
        value = value.bigEndian
        // After the numeric value.
        // - endIndex signifies the final piece.
        // - ':' signifies the end of the piece, start of the next piece.
        // - '.' signifies that number we just parsed is part of an embedded IPv4 address. Rewind and parse it as IPv4.
        guard idx < utf8.endIndex else {
          parsedPieces[pieceIndex] = value
          pieceIndex &+= 1
          break parseloop
        }
        guard utf8[idx] != ASCII.colon.codePoint else {
          parsedPieces[pieceIndex] = value
          pieceIndex &+= 1
          utf8.formIndex(after: &idx)
          guard idx < utf8.endIndex else {
            callback.validationError(ipv6: .unexpectedTrailingColon)
            return nil
          }
          continue parseloop
        }
        guard utf8[idx] != ASCII.period.codePoint else {
          guard length != 0 else {
            callback.validationError(ipv6: .unexpectedPeriod)
            return nil
          }
          guard !(pieceIndex > 6) else {
            callback.validationError(ipv6: .invalidPositionForIPv4Address)
            return nil
          }
          let addressRange = Range(uncheckedBounds: (pieceStartIndex, utf8.endIndex))
          guard let embeddedIPv4Address = IPv4Address(dottedDecimalUTF8: utf8[addressRange]) else {
            callback.validationError(ipv6: .invalidIPv4Address)
            return nil
          }
          withUnsafeBytes(of: embeddedIPv4Address.octets) { octetBuffer in
            // After binding memory, the local variable `value` is poisoned and must not be used again.
            // However, we may still copy its values through the bound pointer and abandon the local variable.
            let uint16s = octetBuffer.bindMemory(to: UInt16.self)
            parsedPieces.baseAddress.unsafelyUnwrapped.advanced(by: pieceIndex)
              .assign(from: uint16s.baseAddress.unsafelyUnwrapped, count: 2)
          }
          pieceIndex &+= 2

          break parseloop
        }
        callback.validationError(ipv6: .unexpectedCharacter)
        return nil
      }

      if expandFrom != -1 {
        // Shift the pieces from 'expandFrom' out towards the end, by swapping with the zeroes already there.
        var swaps = pieceIndex &- expandFrom
        pieceIndex = 7
        while pieceIndex != 0, swaps > 0 {
          let destinationPiece = expandFrom &+ swaps &- 1
          // Manual swap leads to suprisingly better codegen than 'swapAt': https://github.com/apple/swift/pull/36864
          let tmp = parsedPieces[pieceIndex]
          parsedPieces[pieceIndex] = parsedPieces[destinationPiece]
          parsedPieces[destinationPiece] = tmp
          pieceIndex &-= 1
          swaps &-= 1
        }
      } else {
        guard pieceIndex == 8 else {
          callback.validationError(ipv6: .notEnoughPieces)
          return nil
        }
      }

      // Parsing successful.
      // Rather than returning a success/failure flag and creating an address from our original `resultTuple`,
      // load a new tuple via the pointer and return the constructed IP address.
      // Doing so saves a huge amount of byte-shuffling due to outlining.
      return IPv6Address(
        octets: UnsafeRawPointer(parsedPieces.baseAddress.unsafelyUnwrapped).load(as: IPv6Address.Octets.self)
      )
    }
  }

  @usableFromInline
  internal struct ParserError {

    @usableFromInline
    internal let errorCode: UInt8

    @inlinable
    internal init(errorCode: UInt8) {
      self.errorCode = errorCode
    }

    /// Empty input.
    @inlinable internal static var emptyInput: Self { Self(errorCode: 1) }
    /// Unexpected lone ':' at start of address.
    @inlinable internal static var unexpectedLeadingColon: Self { Self(errorCode: 2) }
    /// Unexpected lone ':' at end of address.
    @inlinable internal static var unexpectedTrailingColon: Self { Self(errorCode: 3) }
    /// Unexpected '.' in address segment.
    @inlinable internal static var unexpectedPeriod: Self { Self(errorCode: 4) }
    /// Unexpected character after address segment.
    @inlinable internal static var unexpectedCharacter: Self { Self(errorCode: 5) }
    /// Too many pieces in address.
    @inlinable internal static var tooManyPieces: Self { Self(errorCode: 6) }
    /// Not enough pieces in address.
    @inlinable internal static var notEnoughPieces: Self { Self(errorCode: 7) }
    /// Multiple compressed pieces in address.
    @inlinable internal static var multipleCompressedPieces: Self { Self(errorCode: 8) }
    /// Invalid position for embedded IPv4 address
    @inlinable internal static var invalidPositionForIPv4Address: Self { Self(errorCode: 9) }
    /// Embedded IPv4 address is invalid.
    @inlinable internal static var invalidIPv4Address: Self { Self(errorCode: 10) }
  }
}

// Serialization.

extension IPv6Address {

  /// The canonical textual representation of this address, as defined by [RFC 5952](https://tools.ietf.org/html/rfc5952).
  ///
  public var serialized: String {
    var direct = serializedDirect
    return withUnsafeBytes(of: &direct.buffer) {
      String(decoding: $0.prefix(Int(direct.count)), as: UTF8.self)
    }
  }

  @usableFromInline
  internal var serializedDirect: (buffer: (UInt64, UInt64, UInt64, UInt64, UInt64), count: UInt8) {

    // Maximum length of an IPv6 address = 39 bytes.
    // Note that this differs from libc's INET6_ADDRSTRLEN which is 46 because inet_ntop writes
    // embedded IPv4 addresses in dotted-decimal notation, but RFC 5952 doesn't require that:
    // https://tools.ietf.org/html/rfc5952#section-5
    var _stringBuffer: (UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0)
    let count = withUnsafeMutableBytes(of: &_stringBuffer) { stringBuffer -> Int in
      withUnsafeBufferPointerToElements(tuple: self[pieces: .numeric]) { piecesBuffer -> Int in
        // Look for ranges of consecutive zeroes.
        let compressedPieces: Range<Int>
        let compressedRangeResult = piecesBuffer._longestSubrange(equalTo: 0)
        if compressedRangeResult.length > 1 {
          compressedPieces = compressedRangeResult.subrange
        } else {
          compressedPieces = -1 ..< -1
        }

        var stringIndex = 0
        var pieceIndex = 0
        while pieceIndex < 8 {
          // Skip compressed pieces.
          if pieceIndex == compressedPieces.lowerBound {
            stringBuffer[stringIndex] = ASCII.colon.codePoint
            stringIndex &+= 1
            if pieceIndex == 0 {
              stringBuffer[stringIndex] = ASCII.colon.codePoint
              stringIndex &+= 1
            }
            pieceIndex = compressedPieces.upperBound
            continue
          }
          // Print the piece and, if not the last piece, the separator.
          let bytesWritten = ASCII.writeHexString(
            for: piecesBuffer[pieceIndex],
            to: stringBuffer.baseAddress.unsafelyUnwrapped + stringIndex
          )
          stringIndex &+= Int(bytesWritten)
          if pieceIndex != 7 {
            stringBuffer[stringIndex] = ASCII.colon.codePoint
            stringIndex &+= 1
          }
          pieceIndex &+= 1
        }
        return stringIndex
      }
    }
    assert((0...39).contains(count))
    return (_stringBuffer, UInt8(truncatingIfNeeded: count))
  }
}


// --------------------------------------------
// MARK: - IPv4
// --------------------------------------------


/// A 32-bit numerical identifier assigned to a device on an
/// [Internet Protocol, version 4](https://tools.ietf.org/html/rfc791) network.
///
public struct IPv4Address {

  public typealias Octets = (UInt8, UInt8, UInt8, UInt8)

  /// The octets of this address.
  public var octets: Octets

  /// Creates an address with the given octets.
  public init(octets: Octets = (0, 0, 0, 0)) {
    self.octets = octets
  }

  /// Creates an address with the given 32-bit integer value.
  ///
  /// - seealso: `OctetArrangement`
  /// - parameters:
  ///     - value:             The integer value of the address.
  ///     - octetArrangement:  How the octets of `value` are arranged:
  ///                          <ul>
  ///                          <li>If `numeric`, the integer is assumed to be in "host byte order", and its octets will be rearranged if necessary.</li>
  ///                          <li>If `binary`, the integer is assumed to be in "network byte order", and its octets will be stored in the order
  ///                              they are in.</li>
  ///                          </ul>
  ///
  public init(value: UInt32, _ octetArrangement: OctetArrangement) {
    self.init()
    self[value: octetArrangement] = value
  }

  /// The address, expressed as 16-bit integer pieces.
  ///
  /// - seealso: `OctetArrangement`
  /// - parameters:
  ///     - octetArrangement:  How the octets of `value` are arranged:
  ///                          <ul>
  ///                          <li>If `numeric`, the integer is assumed to be in "host byte order", and its octets will be rearranged if necessary.</li>
  ///                          <li>If `binary`, the integer is assumed to be in "network byte order", and its octets will be stored in the order
  ///                              they are in.</li>
  ///                          </ul>
  ///
  public subscript(value octetArrangement: OctetArrangement) -> UInt32 {
    get {
      let networkOrder = withUnsafeBytes(of: octets) { $0.load(as: UInt32.self) }
      switch octetArrangement {
      case .binary:
        return networkOrder
      case .numeric:
        return UInt32(bigEndian: networkOrder)
      }
    }
    set {
      switch octetArrangement {
      case .binary:
        withUnsafeBytes(of: newValue) { src in
          withUnsafeMutableBytes(of: &octets) { dst in
            dst.copyBytes(from: src)
          }
        }
      case .numeric:
        self[value: .binary] = newValue.bigEndian
      }
    }
  }
}

// Standard protocols.

extension IPv4Address: Equatable, Hashable, LosslessStringConvertible {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    return withUnsafeBytes(of: lhs.octets) { lhsBytes in
      return withUnsafeBytes(of: rhs.octets) { rhsBytes in
        return lhsBytes.elementsEqual(rhsBytes)
      }
    }
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    withUnsafeBytes(of: octets) { hasher.combine(bytes: $0) }
  }

  public var description: String {
    return serialized
  }
}

extension IPv4Address: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let parsedValue = Self(string) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid IPv4 Address"
      )
    }
    self = parsedValue
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(self.serialized)
  }
}

// Parsing.

extension IPv4Address {

  /// Parses an IPv4 address from a String.
  ///
  /// The following formats are recognized:
  ///
  ///  - _a.b.c.d_, where each numeric part defines the value of the address' octet at that position.
  ///  - _a.b.c_, where _a_ and _b_ define the address' first 2 octets, and _c_ is interpreted as a 16-bit integer whose most and least significant bytes define
  ///    the address' 3rd and 4th octets respectively.
  ///  - _a.b_, where _a_ defines the address' first octet, and _b_ is interpreted as a 24-bit integer whose bytes define the remaining octets from most to least
  ///    significant.
  ///  - _a_, where _a_ is interpreted as a 32-bit integer whose bytes define the octets of the address in order from most to least significant.
  ///
  /// The numeric parts may be written in decimal, octal (prefixed with a `0`), or hexadecimal (prefixed with `0x`, case-insensitive).
  /// Additionally, a single trailing '.' is permitted (e.g. `a.b.c.d.`).
  ///
  /// Examples:
  /// ```
  /// IPv4Address("0x7f.0.0.1")!.octets == (0x7f, 0x00, 0x00, 0x01) == "127.0.0.1"
  /// IPv4Address("10.1.0x12.")!.octets == (0x0a, 0x01, 0x00, 0x12) == "10.1.0.18"
  /// IPv4Address("0300.0xa80032")!.octets == (0xc0, 0xa8, 0x00, 0x32) == "192.168.0.50"
  /// IPv4Address("0x8Badf00d")!.octets == (0x8b, 0xad, 0xf0, 0x0d) == "139.173.240.13"
  /// ```
  ///
  /// - parameters:
  ///     - description: The string to parse.
  ///
  @inlinable @inline(__always)
  public init?<Source>(_ description: Source) where Source: StringProtocol {
    self.init(utf8: description.utf8)
  }

  /// Parses an IPv4 address from the given collection of UTF-8 code-units.
  ///
  /// The following formats are recognized:
  ///
  ///  - _a.b.c.d_, where each numeric part defines the value of the address' octet at that position.
  ///  - _a.b.c_, where _a_ and _b_ define the address' first 2 octets, and _c_ is interpreted as a 16-bit integer whose most and least significant bytes define
  ///    the address' 3rd and 4th octets respectively.
  ///  - _a.b_, where _a_ defines the address' first octet, and _b_ is interpreted as a 24-bit integer whose bytes define the remaining octets from most to least
  ///    significant.
  ///  - _a_, where _a_ is interpreted as a 32-bit integer whose bytes define the octets of the address in order from most to least significant.
  ///
  /// The numeric parts may be written in decimal, octal (prefixed with a `0`), or hexadecimal (prefixed with `0x`, case-insensitive).
  /// Additionally, a single trailing '.' is permitted (e.g. `a.b.c.d.`).
  ///
  /// Examples:
  /// ```
  /// IPv4Address("0x7f.0.0.1".utf8)!.octets == (0x7f, 0x00, 0x00, 0x01) == "127.0.0.1"
  /// IPv4Address("10.1.0x12.".utf8)!.octets == (0x0a, 0x01, 0x00, 0x12) == "10.1.0.18"
  /// IPv4Address("0300.0xa80032".utf8)!.octets == (0xc0, 0xa8, 0x00, 0x32) == "192.168.0.50"
  /// IPv4Address("0x8Badf00d".utf8)!.octets == (0x8b, 0xad, 0xf0, 0x0d) == "139.173.240.13"
  /// ```
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  @inlinable @inline(__always)
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    var callback = IgnoreIPAddressParserErrors()
    let _parsed =
      utf8.withContiguousStorageIfAvailable {
        IPv4Address.parse(utf8: $0.boundsChecked, callback: &callback)
      } ?? IPv4Address.parse(utf8: utf8, callback: &callback)
    guard let parsed = _parsed else {
      return nil
    }
    self = parsed
  }
}

extension IPv4Address {

  @inlinable
  internal static func parse<UTF8Bytes, Callback>(
    utf8: UTF8Bytes, callback: inout Callback
  ) -> IPv4Address? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8, Callback: IPAddressParserCallback {

    var idx = utf8.startIndex
    guard idx < utf8.endIndex else {
      callback.validationError(ipv4: .emptyInput)
      return nil
    }

    var _parsedPieces: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
    return withUnsafeMutableBufferPointerToElements(tuple: &_parsedPieces) { parsedPieces -> IPv4Address? in
      var pieceIndex = 0

      while idx < utf8.endIndex {
        var value: UInt32 = 0
        var radix: UInt32 = 10

        // Parse the radix.
        guard let firstCharInPiece = ASCII(utf8[idx]), ASCII.ranges.digits.contains(firstCharInPiece) else {
          callback.validationError(ipv4: .pieceBeginsWithInvalidCharacter)
          return nil
        }
        if firstCharInPiece == ASCII.n0 {
          utf8.formIndex(after: &idx)
          if idx < utf8.endIndex {
            if ASCII(utf8[idx])?.lowercased == .x {
              radix = 16
              utf8.formIndex(after: &idx)
            } else {
              radix = 8
            }
          }
        }
        // Parse the piece value.
        while idx < utf8.endIndex, let numericValue = ASCII(utf8[idx])?.hexNumberValue {
          guard numericValue < radix else {
            callback.validationError(ipv4: .pieceContainsInvalidCharacterForRadix)
            return nil
          }
          var (overflowM, overflowA) = (false, false)
          (value, overflowM) = value.multipliedReportingOverflow(by: radix)
          (value, overflowA) = value.addingReportingOverflow(UInt32(numericValue))
          if overflowM || overflowA {
            callback.validationError(ipv4: .pieceOverflows)
            return nil
          }
          utf8.formIndex(after: &idx)
        }
        // Set the piece to its numeric value.
        guard pieceIndex < 4 else {
          callback.validationError(ipv4: .tooManyPieces)
          return nil
        }
        parsedPieces[pieceIndex] = value
        pieceIndex &+= 1
        // The piece must be followed by a '.' unless we're at endIndex.
        // Even the last piece may have a trailing dot.
        guard idx < utf8.endIndex, utf8[idx] == ASCII.period.codePoint else {
          break
        }
        utf8.formIndex(after: &idx)
      }

      guard idx == utf8.endIndex else {
        callback.validationError(ipv4: .unexpectedTrailingCharacter)
        return nil
      }

      var numericAddress: UInt32
      // swift-format-ignore
      switch pieceIndex {
      case 1:  // 'a'       - 32-bits.
        numericAddress = parsedPieces[0]
      case 2:  // 'a.b'     - 8-bits/24-bits.
        var hasInvalid = parsedPieces[0] & ~0x0000_00FF
        hasInvalid    |= parsedPieces[1] & ~0x00FF_FFFF
        guard hasInvalid == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return nil
        }
        numericAddress = (parsedPieces[0] << 24) | parsedPieces[1]
      case 3:  // 'a.b.c'   - 8-bits/8-bits/16-bits.
        var hasInvalid = parsedPieces[0] & ~0x0000_00FF
        hasInvalid    |= parsedPieces[1] & ~0x0000_00FF
        hasInvalid    |= parsedPieces[2] & ~0x0000_FFFF
        guard hasInvalid == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return nil
        }
        numericAddress = (parsedPieces[0] << 24) | (parsedPieces[1] << 16) | parsedPieces[2]
      case 4:  // 'a.b.c.d' - 8-bits/8-bits/8-bits/8-bits.
        var hasInvalid = parsedPieces[0] & ~0x0000_00FF
        hasInvalid    |= parsedPieces[1] & ~0x0000_00FF
        hasInvalid    |= parsedPieces[2] & ~0x0000_00FF
        hasInvalid    |= parsedPieces[3] & ~0x0000_00FF
        guard hasInvalid == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return nil
        }
        numericAddress = (parsedPieces[0] << 24) | (parsedPieces[1] << 16) | (parsedPieces[2] << 8) | parsedPieces[3]
      default:
        fatalError("Internal error. pieceIndex not in 1...4")
      }
      // Parsing successful.
      return IPv4Address(value: numericAddress, .numeric)
    }
  }

  @usableFromInline
  internal struct ParserError {

    @usableFromInline
    internal let errorCode: UInt8

    @inlinable
    internal init(errorCode: UInt8) {
      self.errorCode = errorCode
    }

    /// Empty input.
    @inlinable internal static var emptyInput: Self { Self(errorCode: 1) }
    /// Piece begins with invalid character.
    @inlinable internal static var pieceBeginsWithInvalidCharacter: Self { Self(errorCode: 2) }
    /// Piece contains invalid character for radix.
    @inlinable internal static var pieceContainsInvalidCharacterForRadix: Self { Self(errorCode: 3) }
    /// Unexpected character at end of address.
    @inlinable internal static var unexpectedTrailingCharacter: Self { Self(errorCode: 4) }
    /// Invalid IPv4 address segment. Unexpected character.
    @inlinable internal static var invalidCharacter: Self { Self(errorCode: 5) }
    /// Piece overflows.
    @inlinable internal static var pieceOverflows: Self { Self(errorCode: 6) }
    /// Address overflows
    @inlinable internal static var addressOverflows: Self { Self(errorCode: 7) }
    /// Too many pieces in address.
    @inlinable internal static var tooManyPieces: Self { Self(errorCode: 8) }
    /// Incorrect number of pieces in address.
    @inlinable internal static var notEnoughPieces: Self { Self(errorCode: 9) }
  }
}

extension IPv4Address {

  /// Parses an IPv4 address from a String.
  ///
  /// This simplified parser only recognises the 4-piece decimal notation ("a.b.c.d"), also known as dotted-decimal notation.
  ///
  /// - parameters:
  ///     - string: The string to parse.
  ///
  @inlinable
  public init?<S>(dottedDecimal string: S) where S: StringProtocol {
    let _parsed =
      string.utf8.withContiguousStorageIfAvailable {
        IPv4Address(dottedDecimalUTF8: $0.boundsChecked)
      } ?? IPv4Address(dottedDecimalUTF8: string.utf8)
    guard let parsed = _parsed else { return nil }
    self = parsed
  }

  /// Parses an IPv4 address from a buffer of UTF-8 codeunits.
  ///
  /// This simplified parser only recognises the 4-piece decimal notation ("a.b.c.d"), also known as dotted-decimal notation.
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  @inlinable
  public init?<UTF8Bytes>(dottedDecimalUTF8 utf8: UTF8Bytes) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

    var numericAddress = UInt32(0)
    var idx = utf8.startIndex
    var numbersSeen = 0
    while idx < utf8.endIndex {
      if numbersSeen != 0 {
        guard ASCII(utf8[idx]) == .period else {
          return nil  // invalid character.
        }
        guard numbersSeen < 4 else {
          return nil  // too many pieces.
        }
        utf8.formIndex(after: &idx)
      }
      var ipv4Piece = -1  // -1 means "no digits parsed".
      while idx < utf8.endIndex, let digit = ASCII(utf8[idx])?.decimalNumberValue {
        switch ipv4Piece {
        case -1:
          ipv4Piece = Int(digit)
        case 0:
          return nil  // leading 0 - unsupported radix.
        default:
          ipv4Piece &*= 10
          ipv4Piece &+= Int(digit)
        }
        guard ipv4Piece < 256 else {
          return nil  // piece overflow.
        }
        utf8.formIndex(after: &idx)
      }
      guard ipv4Piece > -1 else {
        return nil  // piece does not begin with a decimal digit.
      }
      numericAddress &<<= 8
      numericAddress &+= UInt32(ipv4Piece)
      numbersSeen &+= 1
    }
    guard numbersSeen == 4 else {
      return nil  // not enough pieces.
    }
    self = IPv4Address(value: numericAddress, .numeric)
  }
}

// Serialization.

extension IPv4Address {

  /// The textual representation of this address, in dotted decimal notation, as defined by [RFC 4001](https://tools.ietf.org/html/rfc4001#page-7).
  ///
  public var serialized: String {
    var direct = serializedDirect
    return withUnsafeBytes(of: &direct.buffer) {
      String(decoding: $0.prefix(Int(direct.count)), as: UTF8.self)
    }
  }

  @usableFromInline
  internal var serializedDirect: (buffer: (UInt64, UInt64), count: UInt8) {

    // The maximum length of an IPv4 address in decimal notation ("XXX.XXX.XXX.XXX") is 15 bytes.
    // We write one-too-many separators and chop it off at the end, so 16 bytes are needed.
    var _stringBuffer: (UInt64, UInt64) = (0, 0)
    let count = withUnsafeMutableBytes(of: &_stringBuffer) { stringBuffer -> Int in
      return withUnsafeBytes(of: octets) { octetBytes -> Int in
        var stringBufferIdx = stringBuffer.startIndex
        for i in 0..<4 {
          let bytesWritten = ASCII.writeDecimalString(
            for: octetBytes[i],
            to: stringBuffer.baseAddress.unsafelyUnwrapped + stringBufferIdx
          )
          stringBufferIdx &+= Int(bytesWritten)
          stringBuffer[stringBufferIdx] = ASCII.period.codePoint
          stringBufferIdx &+= 1
        }
        return stringBufferIdx &- 1
      }
    }
    assert((0...15).contains(count))
    return (_stringBuffer, UInt8(truncatingIfNeeded: count))
  }
}
