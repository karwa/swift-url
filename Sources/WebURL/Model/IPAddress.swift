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

import Algorithms

// MARK: - Callbacks


/// An object which is informed by the IPv4 parser if a validation error occurs.
///
public protocol IPv4AddressParserCallback {
  mutating func validationError(ipv4 error: IPv4Address.ValidationError)
}

/// An object which is informed by the IPv6 parser if a validation error occurs.
///
public protocol IPv6AddressParserCallback {
  mutating func validationError(ipv6 error: IPv6Address.ValidationError)
}

/// A view which allows an `IPv6AddressParserCallback` to accept IPv4 parser errors, by wrapping them in an IPv6 `invalidIPv4Address` error.
/// This view contains a mutable reference to the underlying v6 callback, meaning it **must not escape** the context where that reference is valid.
///
/// This allows a single object to conform to both `IPv6AddressParserCallback` and `IPv4AddressParserCallback`, while giving IPv4 errors
/// encountered via the v6 parser a distinct representation from those encountered via the v4 parser.
///
fileprivate struct IPParserCallbackv4Tov6<Base>: IPv4AddressParserCallback where Base: IPv6AddressParserCallback {
  var v6Handler: UnsafeMutablePointer<Base>
  func validationError(ipv4 error: IPv4Address.ValidationError) {
    v6Handler.pointee.validationError(ipv6: .invalidIPv4Address(error))
  }
}

extension IPv6AddressParserCallback {

  /// See documentation for `IPParserCallbackv4Tov6`.
  fileprivate mutating func wrappingIPv4Errors<Result>(
    _ perform: (inout IPParserCallbackv4Tov6<Self>) -> Result
  ) -> Result {
    return withUnsafeMutablePointer(to: &self) { ptr in
      var adapter = IPParserCallbackv4Tov6(v6Handler: ptr)
      return perform(&adapter)
    }
  }
}


// MARK: - Byte Order


/// The way in which octets are arranged to form a multi-byte integer.
///
/// Applications should prefer to work with individual octets wherever possible, as octets have a consistent numeric interpretation and binary representation
/// across machines of different endianness.
///
/// When combining multiple octets in to larger (e.g. 16- or 32-bit) integers, we have to consider that each machine has a natural ordering which it
/// uses to interpret those octets as a numeric value. For instance, the first piece of the IPv6 address `2608::3:5` consists of the octets `0x26 0x08` -
/// when read left-to-right (big-endian), `0x26` is considered the most significant byte, resulting in the numeric value 9736 (0x2608);
/// however, when read right-to-left (little-endian), `0x08` is considered the most significant byte, resulting in the numeric value 2086 (0x0826).
///
/// Hence there are 2 ways to combine octets in to larger integers:
///
///  1. As described above. We call this the `binary` interpretation, as it preserves the sequence of octets in their original order,
///    even if different machines interpret the result as different numeric values (e.g. 9736 on BE, 2086 on LE).
///
///  2. By rearranging the octets of multi-byte integers which we read from- or write to the address. We call this the `numeric` interpretation,
///    as it offers a consistent numeric value of each integer component rather than a consistent layout in memory. For instance, when reading the
///    first 16-bit piece of the above address on a little-endian machine, the octets `0x26 0x08` will be reordered to `0x08 0x26`,
///    so that the numeric value (9736) is the same as on a big-endian machine. Assigning a group of octets using the `numeric` integer 9736 will similarly
///    result in the little-endian machine reordering the integer so that the octets are written in the order `0x26 0x08` (as they would be on a big-endian machine),
///    rather than `0x08 0x26` (which is what the little-endian integer actually looks like in memory).
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


// MARK: - IPv6


/// A 128-bit numerical identifier assigned to a device on an
/// [Internet Protocol, version 6](https://tools.ietf.org/html/rfc2460) network.
///
public struct IPv6Address {

  public typealias Octets = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

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
  ///                            - If `numeric`, the integers are assumed to be in "host byte order", and their octets will be rearranged if necessary.
  ///                            - If `binary`, the integers are assumed to be in "network byte order", and their octets will be stored in the order
  ///                              they are in.
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
  ///                            - If `numeric`, the integers are assumed to be in "host byte order", and their octets will be rearranged if necessary.
  ///                            - If `binary`, the integers are assumed to be in "network byte order", and their octets will be stored in the order
  ///                              they are in.
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
    var callback = IgnoreValidationErrors()
    guard let parsed = IPv6Address.parse(utf8: description.utf8, callback: &callback) else { return nil }
    self = parsed
  }

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
  public init<S>(reportingErrors description: S) throws where S: StringProtocol {
    var callback = LastValidationError()
    guard let parsed = IPv6Address.parse(utf8: description.utf8, callback: &callback) else {
      guard case .ipv6AddressError(let error) = callback.error?.hostParserError else {
        preconditionFailure("IPv6 Parser returned a non-IPv6-parser error?!")
      }
      throw error
    }
    self = parsed
  }
}

extension IPv6Address {

  public struct ValidationError: Swift.Error, Equatable, CustomStringConvertible {
    private let errorCode: UInt8
    private let context: Int
    private init(errorCode: UInt8, context: Int = -1) {
      self.errorCode = errorCode
      self.context = context
    }

    // These are deliberately not public, because we don't want to make the set of possible errors API.
    // They are 'internal' for testing purposes only.
    internal static var emptyInput: Self { Self(errorCode: 1) }
    // -
    internal static var unexpectedLeadingColon: Self { Self(errorCode: 2) }
    internal static var unexpectedTrailingColon: Self { Self(errorCode: 3) }
    internal static var unexpectedPeriod: Self { Self(errorCode: 4) }
    internal static var unexpectedCharacter: Self { Self(errorCode: 5) }
    // -
    internal static var tooManyPieces: Self { Self(errorCode: 6) }
    internal static var notEnoughPieces: Self { Self(errorCode: 7) }
    internal static var multipleCompressedPieces: Self { Self(errorCode: 8) }
    // -
    internal static var invalidPositionForIPv4Address: Self { Self(errorCode: 9) }

    internal static var invalidIPv4Address_errorCode: UInt8 = 10
    internal static func invalidIPv4Address(_ err: IPv4Address.ValidationError) -> Self {
      Self(errorCode: invalidIPv4Address_errorCode, context: err.packedAsInt)
    }

    public var description: String {
      switch self {
      case .emptyInput:
        return "Empty input"
      case .unexpectedLeadingColon:
        return "Unexpected lone ':' at start of address"
      case .unexpectedTrailingColon:
        return "Unexpected lone ':' at end of address"
      case .unexpectedPeriod:
        return "Unexpected '.' in address segment"
      case .unexpectedCharacter:
        return "Unexpected character after address segment"
      case .tooManyPieces:
        return "Too many pieces in address"
      case .notEnoughPieces:
        return "Not enough pieces in address"
      case .multipleCompressedPieces:
        return "Multiple compressed pieces in address"
      case .invalidPositionForIPv4Address:
        return "Invalid position for embedded IPv4 address"
      case _ where self.errorCode == Self.invalidIPv4Address_errorCode:
        let wrappedError = IPv4Address.ValidationError(unpacking: context)
        return "Embedded IPv4 address is invalid: \(wrappedError)"
      default:
        assertionFailure("Unrecognised error code: \(errorCode). Context: \(context)")
        return "Internal Error: Unrecognised error code \(errorCode)"
      }
    }
  }

  // Note: This does not 'throw', as we want to specialize when the caller doesn't care about the error.

  /// Parses an IPv6 address from a buffer of UTF-8 code-units.
  ///
  /// Accepted formats are documented in [Section 2.2][rfc4291] ("Text Representation of Addresses") of
  /// IP Version 6 Addressing Architecture (RFC 4291).
  ///
  /// [rfc4291]: https://tools.ietf.org/html/rfc4291#section-2.2
  ///
  /// - parameters:
  ///     - input:     The string to parse, as a collection of UTF-8 code-units.
  ///     - callback:  A callback to be invoked if a validation error occurs.
  ///                  This callback is only invoked once, and any validation error terminates parsing.
  /// - returns:  Either the successfully-parsed address, or `nil` if parsing fails.
  ///
  @inlinable
  public static func parse<Bytes, Callback>(utf8 input: Bytes, callback: inout Callback) -> Self?
  where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv6AddressParserCallback {
    return input.withContiguousStorageIfAvailable {
      parse_impl(utf8: $0, callback: &callback)
    } ?? parse_impl(utf8: input, callback: &callback)
  }

  @usableFromInline
  @_specialize(kind:partial,where Callback == IgnoreValidationErrors)
  static func parse_impl<Bytes, Callback>(utf8 input: Bytes, callback: inout Callback) -> Self?
  where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv6AddressParserCallback {

    guard input.isEmpty == false else {
      callback.validationError(ipv6: .emptyInput)
      return nil
    }
    var _parsedPieces: IPv6Address.Pieces = (0, 0, 0, 0, 0, 0, 0, 0)
    return withUnsafeMutableBufferPointerToElements(tuple: &_parsedPieces) { parsedPieces -> Self? in
      var pieceIndex = 0
      var compress = -1  // We treat -1 as "null".
      var idx = input.startIndex

      // Handle leading compressed pieces ('::').
      if input[idx] == ASCII.colon {
        idx = input.index(after: idx)
        guard idx != input.endIndex, input[idx] == ASCII.colon else {
          callback.validationError(ipv6: .unexpectedLeadingColon)
          return nil
        }
        idx = input.index(after: idx)
        pieceIndex &+= 1
        compress = pieceIndex
      }

      parseloop: while idx != input.endIndex {
        guard pieceIndex != 8 else {
          callback.validationError(ipv6: .tooManyPieces)
          return nil
        }
        // If the piece starts with a ':', it must be a compressed group of pieces.
        guard input[idx] != ASCII.colon else {
          guard compress == -1 else {
            callback.validationError(ipv6: .multipleCompressedPieces)
            return nil
          }
          idx = input.index(after: idx)
          pieceIndex &+= 1
          compress = pieceIndex
          continue parseloop
        }
        // Parse the piece's numeric value.
        let pieceStartIndex = idx
        var value: UInt16 = 0
        var length: UInt8 = 0
        while length < 4, idx != input.endIndex, let asciiChar = ASCII(input[idx]) {
          let numberValue = ASCII.parseHexDigit(ascii: asciiChar)
          guard numberValue != ASCII.parse_NotFound else { break }
          value <<= 4
          value &+= UInt16(numberValue)
          length &+= 1
          idx = input.index(after: idx)
        }
        // The bytes of 'value' are arranged in host order. Flip to network order if necessary.
        value = value.bigEndian
        guard idx != input.endIndex else {
          parsedPieces[pieceIndex] = value
          pieceIndex &+= 1
          break parseloop
        }
        // Parse characters after the numeric value.
        // - ':' signifies the end of the piece.
        // - '.' signifies that we should re-parse the piece as an IPv4 address.
        guard _slowPath(input[idx] != ASCII.colon) else {
          parsedPieces[pieceIndex] = value
          pieceIndex &+= 1
          idx = input.index(after: idx)
          guard idx != input.endIndex else {
            callback.validationError(ipv6: .unexpectedTrailingColon)
            return nil
          }
          continue parseloop
        }
        guard _slowPath(input[idx] != ASCII.period) else {
          guard length != 0 else {
            callback.validationError(ipv6: .unexpectedPeriod)
            return nil
          }
          guard !(pieceIndex > 6) else {
            callback.validationError(ipv6: .invalidPositionForIPv4Address)
            return nil
          }
          guard
            let value = callback.wrappingIPv4Errors({ cb in
              IPv4Address.parse_simple(utf8: input[pieceStartIndex...], callback: &cb)
            })
          else {
            // IPv4Address.parse_simple should have informed the callback of the error.
            return nil
          }
          withUnsafeBytes(of: value.octets) { octetBuffer in
            // After binding memory, the local variable `value` is poisoned and must not be used again.
            // It's fine to just copy its values through the pointer and abandon the local variable, though.
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

      if compress != -1 {
        var swaps = pieceIndex &- compress
        pieceIndex = 7
        while pieceIndex != 0, swaps > 0 {
          let destinationPiece = compress &+ swaps &- 1
          parsedPieces.swapAt(pieceIndex, destinationPiece)
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
      // Rather than returning a success/failure flag and creating an address from `resultTuple`, load a tuple
      // via the pointer and return the constructed address. This prevents the withUnsafeMutableBytes closure
      // from being outlined, resulting in significantly less byte-shuffling.
      return IPv6Address(
        octets: UnsafeRawPointer(parsedPieces.baseAddress.unsafelyUnwrapped).load(as: IPv6Address.Octets.self)
      )
    }
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

  var serializedDirect: (buffer: (UInt64, UInt64, UInt64, UInt64, UInt64), count: UInt8) {

    // Maximum length of an IPv6 address = 39 bytes.
    // Note that this differs from libc's INET6_ADDRSTRLEN which is 46 because inet_ntop writes
    // embedded IPv4 addresses in dotted-decimal notation, but RFC 5952 doesn't require that:
    // https://tools.ietf.org/html/rfc5952#section-5
    var _stringBuffer: (UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0)
    let count = withUnsafeMutableBytes(of: &_stringBuffer) { stringBuffer -> Int in
      withUnsafeBufferPointerToElements(tuple: self[pieces: .numeric]) { piecesBuffer -> Int in
        // Look for ranges of consecutive zeroes.
        let compressedPieces: Range<Int>
        let compressedRangeResult = piecesBuffer.longestSubrange(equalTo: 0)
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
          stringIndex &+= ASCII.insertHexString(
            for: piecesBuffer[pieceIndex],
            into: UnsafeMutableRawBufferPointer(rebasing: stringBuffer[stringIndex...])
          )
          if pieceIndex != 7 {
            stringBuffer[stringIndex] = ASCII.colon.codePoint
            stringIndex &+= 1
          }
          pieceIndex &+= 1
        }
        return stringIndex
      }
    }
    return (_stringBuffer, UInt8(truncatingIfNeeded: count))
  }
}


// MARK: - IPv4


/// A 32-bit numerical identifier assigned to a device on an
/// [Internet Protocol, version 4](https://tools.ietf.org/html/rfc791) network.
///
public struct IPv4Address {

  public typealias Octets = (UInt8, UInt8, UInt8, UInt8)

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
  ///                            - If `numeric`, the integer is assumed to be in "host byte order", and its octets will be rearranged if necessary.
  ///                            - If `binary`, the integer is assumed to be in "network byte order", and its octets will be stored in the order
  ///                              they are in.
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
  ///                            - If `numeric`, the integer is assumed to be in "host byte order", and its octets will be rearranged if necessary.
  ///                            - If `binary`, the integer is assumed to be in "network byte order", and its octets will be stored in the order
  ///                              they are in.
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
  ///  - _a_, where _a_ is interpreted as a 32-bit integer whose octets define the octets of the address in order from most to least significant.
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
  ///     - description:  The string to parse.
  ///
  @inlinable @inline(__always)
  public init?<Source>(_ description: Source) where Source: StringProtocol {
    var callback = IgnoreValidationErrors()
    guard case .success(let parsed) = IPv4Address.parse(utf8: description.utf8, callback: &callback) else {
      return nil
    }
    self = parsed
  }

  /// Parses an IPv4 address from a String.
  ///
  /// The following formats are recognized:
  ///
  ///  - _a.b.c.d_, where each numeric part defines the value of the address' octet at that position.
  ///  - _a.b.c_, where _a_ and _b_ define the address' first 2 octets, and _c_ is interpreted as a 16-bit integer whose most and least significant bytes define
  ///    the address' 3rd and 4th octets respectively.
  ///  - _a.b_, where _a_ defines the address' first octet, and _b_ is interpreted as a 24-bit integer whose bytes define the remaining octets from most to least
  ///    significant.
  ///  - _a_, where _a_ is interpreted as a 32-bit integer whose octets define the octets of the address in order from most to least significant.
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
  ///     - description:  The string to parse.
  ///
  @inlinable @inline(__always)
  public init<S>(reportingErrors description: S) throws where S: StringProtocol {
    var callback = LastValidationError()
    guard case .success(let parsed) = IPv4Address.parse(utf8: description.utf8, callback: &callback) else {
      guard case .ipv4AddressError(let error) = callback.error?.hostParserError else {
        preconditionFailure("IPv4 Parser returned a non-IPv4-parser error?!")
      }
      throw error
    }
    self = parsed
  }
}

extension IPv4Address {

  public enum ParseResult {
    case success(IPv4Address)
    case failure
    case notAnIPAddress
  }

  public struct ValidationError: Swift.Error, Equatable, CustomStringConvertible {
    private let errorCode: UInt8
    private init(errorCode: UInt8) {
      self.errorCode = errorCode
    }
    // Packing and unpacking for embedding in `IPv6.ParseResult.Error`.
    fileprivate var packedAsInt: Int {
      return Int(errorCode)
    }
    fileprivate init(unpacking packedValue: Int) {
      self = Self(errorCode: UInt8(packedValue))
    }

    // These are deliberately not public, because we don't want to make the set of possible errors API.
    // They are 'internal' for testing purposes only.
    internal static var emptyInput: Self { Self(errorCode: 1) }
    // -
    internal static var pieceBeginsWithInvalidCharacter: Self { Self(errorCode: 3) }  // full only.
    internal static var pieceContainsInvalidCharacterForRadix: Self { Self(errorCode: 4) }  // full only.
    internal static var unsupportedRadix: Self { Self(errorCode: 9) }  // simple only.
    internal static var unexpectedTrailingCharacter: Self { Self(errorCode: 5) }
    internal static var invalidCharacter: Self { Self(errorCode: 2) }
    // -
    internal static var pieceOverflows: Self { Self(errorCode: 6) }
    internal static var addressOverflows: Self { Self(errorCode: 7) }
    // -
    internal static var tooManyPieces: Self { Self(errorCode: 8) }
    internal static var notEnoughPieces: Self { Self(errorCode: 10) }

    public var description: String {
      switch self {
      case .emptyInput:
        return "Empty input"
      case .invalidCharacter:
        return "Invalid IPv4 address segment. Unexpected character"
      case .pieceBeginsWithInvalidCharacter:
        return "Piece begins with invalid character"
      case .pieceContainsInvalidCharacterForRadix:
        return "Piece contains invalid character for radix"
      case .pieceOverflows:
        return "Piece overflows"
      case .addressOverflows:
        return "Address overflows"
      case .tooManyPieces:
        return "Too many pieces in address"
      case .unexpectedTrailingCharacter:
        return "Unexpected character at end of address"
      case .unsupportedRadix:
        return "Unexpected leading '0' in peice. Octal and hexadecimal pieces are not supported by the simple parser"
      case .notEnoughPieces:
        return "Incorrect number of pieces in address"
      default:
        assert(false, "Unrecognised error code: \(errorCode)")
        return "Internal Error: Unrecognised error code"
      }
    }
  }

  /// Parses an IPv4 address from a buffer of UTF-8 codeunits.
  ///
  /// The following formats are recognized:
  ///
  ///  - _a.b.c.d_, where each numeric part defines the value of the address' octet at that position.
  ///  - _a.b.c_, where _a_ and _b_ define the address' first 2 octets, and _c_ is interpreted as a 16-bit integer whose most and least significant bytes define
  ///    the address' 3rd and 4th octets respectively.
  ///  - _a.b_, where _a_ defines the address' first octet, and _b_ is interpreted as a 24-bit integer whose bytes define the remaining octets from most to least
  ///    significant.
  ///  - _a_, where _a_ is interpreted as a 32-bit integer whose octets define the octets of the address in order from most to least significant.
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
  ///     - input:     The string to parse, as a collection of UTF-8 code-units.
  ///     - callback:  A callback to be invoked if a validation error occurs.
  ///                  If parsing does not succeed, the callback will have been informed of the error. It may also be informed of other, non-fatal errors.
  ///
  /// - returns:
  ///     A result object containing either the successfully-parsed address, or a failure flag communicating whether parsing
  ///     failed because the IP address was invalid (e.g. the value overflows) or whether it failed because the string isn't an IP address.
  ///     For example, the string "9999999999.com" fails because it isn't an IP address, whereas "9999999999" fails due to overflow.
  ///
  @inlinable
  public static func parse<Bytes, Callback>(
    utf8 input: Bytes, callback: inout Callback
  ) -> ParseResult where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv4AddressParserCallback {
    return input.withContiguousStorageIfAvailable {
      parse_impl(utf8: $0, callback: &callback)
    } ?? parse_impl(utf8: input, callback: &callback)
  }

  @usableFromInline
  @_specialize(kind:partial,where Callback == IgnoreValidationErrors)
  static func parse_impl<Bytes, Callback>(
    utf8 input: Bytes, callback: inout Callback
  ) -> ParseResult where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv4AddressParserCallback {

    guard input.isEmpty == false else {
      callback.validationError(ipv4: .emptyInput)
      return .failure
    }

    // This algorithm isn't from the WHATWG spec, but supports all the required shorthands.
    // Translated and adapted to Swift (with some modifications) from:
    // https://android.googlesource.com/platform/bionic/+/froyo/libc/inet/inet_aton.c

    // TODO: Make sure we return the same non-fatal validation errors as the spec.

    var _parsedPieces: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
    return withUnsafeMutableBufferPointerToElements(tuple: &_parsedPieces) { parsedPieces -> ParseResult in
      var pieceIndex = -1
      var idx = input.startIndex

      // We need to track and continue processing numeric digits even if a piece overflows,
      // because the standard works in terms of mathematical integers, not fixed-size binary integers.
      // A piece overflow in a well-formatted IP-address string should return a `.failure`,
      // but in a non-IP-address string, it should be ignored in favour of a `.notAnIPAddress` result.
      // For example, the string "10000000000.com" should return `.notAnIPAddress` due to the `.com`,
      // not a `.failure` due to overflow.
      var pieceDidOverflow = false

      while idx != input.endIndex {
        var value: UInt32 = 0
        var radix: UInt32 = 10

        do {
          guard let asciiChar = ASCII(input[idx]), ASCII.ranges.digits.contains(asciiChar) else {
            callback.validationError(ipv4: .pieceBeginsWithInvalidCharacter)
            return .notAnIPAddress
          }
          // Leading '0' or '0x' sets the radix.
          if asciiChar == ASCII.n0 {
            idx = input.index(after: idx)
            if idx != input.endIndex {
              switch input[idx] {
              case ASCII.x, ASCII.X:
                radix = 16
                idx = input.index(after: idx)
              default:
                radix = 8
              }
            }
          }
        };

        // Parse remaining digits in piece.
        while idx != input.endIndex {
          guard let numericValue = ASCII(input[idx]).map({ ASCII.parseHexDigit(ascii: $0) }),
            numericValue != ASCII.parse_NotFound
          else {
            break
          }
          guard numericValue < radix else {
            callback.validationError(ipv4: .pieceContainsInvalidCharacterForRadix)
            return .notAnIPAddress
          }
          var (overflowM, overflowA) = (false, false)
          (value, overflowM) = value.multipliedReportingOverflow(by: radix)
          (value, overflowA) = value.addingReportingOverflow(UInt32(numericValue))
          if overflowM || overflowA {
            pieceDidOverflow = true
          }
          idx = input.index(after: idx)
        }
        // Set value for piece.
        // Note that we do not flip to network byte order as we still want to process these numerically.
        guard pieceIndex < 3 else {
          callback.validationError(ipv4: .tooManyPieces)
          return .notAnIPAddress
        }
        pieceIndex &+= 1
        parsedPieces[pieceIndex] = value
        // Allow one trailing '.' after the piece, even if it's the last piece.
        guard idx != input.endIndex, input[idx] == ASCII.period else {
          break
        }
        idx = input.index(after: idx)
      }

      guard idx == input.endIndex else {
        callback.validationError(ipv4: .unexpectedTrailingCharacter)
        return .notAnIPAddress
      }
      guard pieceDidOverflow == false else {
        callback.validationError(ipv4: .pieceOverflows)
        return .failure
      }

      var numericAddress: UInt32 = 0
      // swift-format-ignore
      switch pieceIndex {
      case 0:  // 'a'       - 32-bits.
        numericAddress = parsedPieces[0]
      case 1:  // 'a.b'     - 8-bits/24-bits.
        var invalidBits = parsedPieces[0] & ~0x0000_00FF
        invalidBits    |= parsedPieces[1] & ~0x00FF_FFFF
        guard invalidBits == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return .failure
        }
        numericAddress = (parsedPieces[0] << 24) | parsedPieces[1]
      case 2:  // 'a.b.c'   - 8-bits/8-bits/16-bits.
        var invalidBits = parsedPieces[0] & ~0x0000_00FF
        invalidBits    |= parsedPieces[1] & ~0x0000_00FF
        invalidBits    |= parsedPieces[2] & ~0x0000_FFFF
        guard invalidBits == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return .failure
        }
        numericAddress = (parsedPieces[0] << 24) | (parsedPieces[1] << 16) | parsedPieces[2]
      case 3:  // 'a.b.c.d' - 8-bits/8-bits/8-bits/8-bits.
        var invalidBits = parsedPieces[0] & ~0x0000_00FF
        invalidBits    |= parsedPieces[1] & ~0x0000_00FF
        invalidBits    |= parsedPieces[2] & ~0x0000_00FF
        invalidBits    |= parsedPieces[3] & ~0x0000_00FF
        guard invalidBits == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return .failure
        }
        numericAddress = (parsedPieces[0] << 24) | (parsedPieces[1] << 16) | (parsedPieces[2] << 8) | parsedPieces[3]
      default:
        fatalError("Internal error. pieceIndex has unexpected value.")
      }
      // Parsing successful.
      return .success(IPv4Address(value: numericAddress, .numeric))
    }
  }

  /// Parses an IPv4 address from a buffer of UTF-8 codeunits.
  ///
  /// This simplified parser only recognises the 4-piece decimal notation ("a.b.c.d"), also known as dotted decimal notation.
  /// Trailing '.'s are not permitted.
  ///
  /// - parameters:
  ///     - input:     The string to parse, as a collection of UTF-8 code-units.
  ///     - callback:  A callback to be invoked if a validation error occurs.
  ///                  This callback is only invoked once, and any validation error terminates parsing.
  /// - returns:
  ///     Either the successfully-parsed address, or `nil` if parsing failed.
  ///
  public static func parse_simple<Bytes, Callback>(
    utf8 input: Bytes, callback: inout Callback
  ) -> Self? where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv4AddressParserCallback {

    var numericAddress = UInt32(0)
    var idx = input.startIndex
    var numbersSeen = 0
    while idx != input.endIndex {
      // Consume '.' separator from end of previous piece.
      if numbersSeen != 0 {
        guard ASCII(input[idx]) == .period else {
          callback.validationError(ipv4: .invalidCharacter)
          return nil
        }
        guard numbersSeen < 4 else {
          callback.validationError(ipv4: .tooManyPieces)
          return nil
        }
        idx = input.index(after: idx)
      }
      // Consume decimal digits from the piece.
      var ipv4Piece = -1  // We treat -1 as "null".
      while idx != input.endIndex, let asciiChar = ASCII(input[idx]), ASCII.ranges.digits.contains(asciiChar) {
        let digit = ASCII.parseDecimalDigit(ascii: asciiChar)
        assert(digit != ASCII.parse_NotFound)  // We already checked it was a digit.
        switch ipv4Piece {
        case -1:
          ipv4Piece = Int(digit)
        case 0:
          callback.validationError(ipv4: .unsupportedRadix)
          return nil
        default:
          ipv4Piece *= 10
          ipv4Piece += Int(digit)
        }
        guard ipv4Piece < 256 else {
          callback.validationError(ipv4: .pieceOverflows)
          return nil
        }
        idx = input.index(after: idx)
      }
      guard ipv4Piece != -1 else {
        callback.validationError(ipv4: .pieceBeginsWithInvalidCharacter)
        return nil
      }
      // Accumulate in to result.
      numericAddress <<= 8
      numericAddress &+= UInt32(ipv4Piece)
      numbersSeen &+= 1
    }
    guard numbersSeen == 4 else {
      callback.validationError(ipv4: .notEnoughPieces)
      return nil
    }
    return IPv4Address(value: numericAddress, .numeric)
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

  var serializedDirect: (buffer: (UInt64, UInt64), count: UInt8) {

    // The maximum length of an IPv4 address in decimal notation ("XXX.XXX.XXX.XXX") is 15 bytes.
    var _stringBuffer: (UInt64, UInt64) = (0, 0)
    let count = withUnsafeMutableBytes(of: &_stringBuffer) { stringBuffer -> Int in
      return withUnsafeBytes(of: octets) { octetBytes -> Int in
        var stringBufferIdx = stringBuffer.startIndex
        for i in 0..<4 {
          stringBufferIdx &+= ASCII.insertDecimalString(
            for: octetBytes[i],
            into: UnsafeMutableRawBufferPointer(
              rebasing: stringBuffer[Range(uncheckedBounds: (stringBufferIdx, stringBuffer.endIndex))]
            )
          )
          if i != 3 {
            stringBuffer[stringBufferIdx] = ASCII.period.codePoint
            stringBufferIdx &+= 1
          }
        }
        return stringBufferIdx
      }
    }
    return (_stringBuffer, UInt8(truncatingIfNeeded: count))
  }
}
