import Algorithms  // for Collection.longestSubrange.


// MARK: - Callbacks


/// An object which is informed by the IPv4 parser if a validation error occurs.
///
public protocol IPv4ParserCallback {
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
fileprivate struct IPParserCallbackv4Tov6<Base>: IPv4ParserCallback where Base: IPv6AddressParserCallback {
  var v6Handler: UnsafeMutablePointer<Base>
  func validationError(ipv4 error: IPv4Address.ValidationError) {
    v6Handler.pointee.validationError(ipv6: .invalidIPv4Address(error))
  }
}

extension IPv6AddressParserCallback {

  /// See documentation for `IPParserCallbackv4Tov6`.
  fileprivate mutating func wrappingIPv4Errors<Result>(
    _ perform: (inout IPParserCallbackv4Tov6<Self>)->Result
  ) -> Result {
    return withUnsafeMutablePointer(to: &self) { ptr in
      var adapter = IPParserCallbackv4Tov6(v6Handler: ptr)
      return perform(&adapter)
    }
  }
}


// MARK: - IPv6


/// A 128-bit numerical identifier assigned to a device on an
/// [Internet Protocol, version 6](https://tools.ietf.org/html/rfc2460) network.
///
public struct IPv6Address {
  public typealias AddressType = (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16)

  // Host byte order.

  /// The raw address (i.e. in host byte order).
  ///
  public var rawAddress: AddressType

  /// Creates a value with the given raw address.
  ///
  /// - parameters:
  ///     - rawAddress:   The address value in host byte order.
  ///
  @inlinable
  public init(rawAddress: AddressType = (0, 0, 0, 0, 0, 0, 0, 0)) {
    self.rawAddress = rawAddress
  }

  // Network byte order.

  /// The network address (i.e. in network byte order).
  ///
  public var networkAddress: AddressType {
    return (
      rawAddress.0.bigEndian, rawAddress.1.bigEndian,
      rawAddress.2.bigEndian, rawAddress.3.bigEndian,
      rawAddress.4.bigEndian, rawAddress.5.bigEndian,
      rawAddress.6.bigEndian, rawAddress.7.bigEndian
    )
  }

  /// Creates a value with the given network address.
  ///
  /// - parameters:
  ///     - networkAddress:   The address value in network byte order.
  ///
  @inlinable
  public init(networkAddress: AddressType) {
    self.init(
      rawAddress: (
        networkAddress.0.bigEndian, networkAddress.1.bigEndian,
        networkAddress.2.bigEndian, networkAddress.3.bigEndian,
        networkAddress.4.bigEndian, networkAddress.5.bigEndian,
        networkAddress.6.bigEndian, networkAddress.7.bigEndian
      ))
  }

}

// Standard protocols.

extension IPv6Address: Equatable, Hashable, LosslessStringConvertible {
  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.rawAddress.0 == rhs.rawAddress.0 && lhs.rawAddress.1 == rhs.rawAddress.1
      && lhs.rawAddress.2 == rhs.rawAddress.2 && lhs.rawAddress.3 == rhs.rawAddress.3
      && lhs.rawAddress.4 == rhs.rawAddress.4 && lhs.rawAddress.5 == rhs.rawAddress.5
      && lhs.rawAddress.6 == rhs.rawAddress.6 && lhs.rawAddress.7 == rhs.rawAddress.7
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    withUnsafeBytes(of: rawAddress) { hasher.combine(bytes: $0) }
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

// Parsing initializers.

extension IPv6Address {

  @inlinable public static func parse<Source, Callback>(
    _ input: Source, callback: inout Callback
  ) -> Self? where Source: StringProtocol, Callback: IPv6AddressParserCallback {
    return input._withUTF8 { parse($0, callback: &callback) }
  }

  @inlinable public init?<S>(_ input: S) where S: StringProtocol {
    var callback = IgnoreValidationErrors()
    guard let parsed = Self.parse(input, callback: &callback) else { return nil }
    self = parsed
  }
}

// Parsing and serialization impl.

extension IPv6Address {

  public struct ValidationError: Equatable, CustomStringConvertible {
    private let errorCode: UInt8
    private let context: Int
    private init(errorCode: UInt8, context: Int = -1) {
      self.errorCode = errorCode
      self.context = context
    }

    // Note: These are deliberately not public, because we don't want to make the set of possible errors API.
    //       They are 'internal' for testing purposes only.
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
        return "Not enough segments in address"
      case .multipleCompressedPieces:
        return "Multiple compressed pieces in address"
      case .invalidPositionForIPv4Address:
        return "Invalid position for IPv4 address segment"
      case _ where self.errorCode == Self.invalidIPv4Address_errorCode:
        let wrappedError = IPv4Address.ValidationError(unpacking: context)
        return "Invalid IPv4 address: \(wrappedError)"
      default:
        assert(false, "Unrecognised error code: \(errorCode). Context: \(context)")
        return "Internal Error: Unrecognised error code"
      }
    }
  }

  /// Parses an IPv6 address from a UTF-8 string.
  ///
  /// TODO: Add description of accepted formats.
  ///
  /// - parameters:
  ///     - input:      A buffer of ASCII/UTF-8 codepoints. The buffer does not have to be null-terminated.
  ///     - callback:   A callback to be invoked if a validation error occurs. This callback is only invoked once,
  ///                   and any validation error terminates parsing.
  /// - returns:
  ///     Either the successfully-parsed address, or `.none` if parsing fails.
  ///
  public static func parse<Bytes, Callback>(_ input: Bytes, callback: inout Callback) -> Self?
  where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv6AddressParserCallback {
    guard input.isEmpty == false else {
      callback.validationError(ipv6: .emptyInput)
      return nil
    }

    var result: IPv6Address.AddressType = (0, 0, 0, 0, 0, 0, 0, 0)
    return withUnsafeMutableBytes(of: &result) { tuplePointer -> Self? in
      let addressBuffer = tuplePointer.bindMemory(to: UInt16.self)
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
        guard idx != input.endIndex else {
          addressBuffer[pieceIndex] = value
          pieceIndex &+= 1
          break parseloop
        }
        // Parse characters after the numeric value.
        // - ':' signifies the end of the piece.
        // - '.' signifies that we should re-parse the piece as an IPv4 address.
        guard _slowPath(input[idx] != ASCII.colon) else {
          addressBuffer[pieceIndex] = value
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
          guard let value =  callback.wrappingIPv4Errors({ cb in
            IPv4Address.parse_simple(input[pieceStartIndex...], callback: &cb)
          }) else {
            return nil
          }
          addressBuffer[pieceIndex] = UInt16(truncatingIfNeeded: value.rawAddress >> 16)
          addressBuffer[pieceIndex &+ 1] = UInt16(truncatingIfNeeded: value.rawAddress)
          pieceIndex &+= 2

          break parseloop
        }
        callback.validationError(ipv6: .unexpectedCharacter)
        return nil
      }

      if compress != -1 {
        var swaps = pieceIndex - compress
        pieceIndex = 7
        while pieceIndex != 0, swaps > 0 {
          let destinationPiece = compress + swaps - 1
          // Check that locations are not the same, otherwise we'll have an exclusivity violation.
          if pieceIndex != destinationPiece {
            swap(&addressBuffer[pieceIndex], &addressBuffer[destinationPiece])
          }
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
      return IPv6Address(
        rawAddress:
          UnsafeRawPointer(addressBuffer.baseAddress.unsafelyUnwrapped)
          .load(fromByteOffset: 0, as: IPv6Address.AddressType.self)
      )
    }
  }
}

extension IPv6Address {

  public var serialized: String {
    // Maximum normalised length of an IPv6 address = 39 bytes
    // 32 (128 bits/4 bits per hex character) + 7 (separators)
    return String(_unsafeUninitializedCapacity: 39) { stringBuffer in
      return withUnsafeBytes(of: rawAddress) { __rawRawAddressBuffer in
        let rawAddressBuffer = __rawRawAddressBuffer.bindMemory(to: UInt16.self)
        // Look for ranges of consecutive zeroes.
        let compressedPieces: Range<Int>
        let compressedRangeResult = rawAddressBuffer.longestSubrange(equalTo: 0)
        if compressedRangeResult.length > 1 {
          compressedPieces = compressedRangeResult.subrange
        } else {
          compressedPieces = -1 ..< -1
        }

        var stringBufferIdx = stringBuffer.startIndex
        var pieceIndex = 0
        while pieceIndex < 8 {
          // Skip compressed pieces.
          if pieceIndex == compressedPieces.lowerBound {
            stringBuffer[stringBufferIdx] = ASCII.colon.codePoint
            stringBufferIdx &+= 1
            if pieceIndex == 0 {
              stringBuffer[stringBufferIdx] = ASCII.colon.codePoint
              stringBufferIdx &+= 1
            }
            pieceIndex = compressedPieces.upperBound
            continue
          }
          // Print the piece and, if not the last piece, the separator.
          stringBufferIdx &+= ASCII.insertHexString(
            for: rawAddressBuffer[pieceIndex],
            into: UnsafeMutableBufferPointer(rebasing: stringBuffer[stringBufferIdx...])
          )
          if pieceIndex != 7 {
            stringBuffer[stringBufferIdx] = ASCII.colon.codePoint
            stringBufferIdx &+= 1
          }
          pieceIndex &+= 1
        }
        return stringBufferIdx
      }
    }
  }
}


// MARK: - IPv4


/// A 32-bit numerical identifier assigned to a device on an
/// [Internet Protocol, version 4](https://tools.ietf.org/html/rfc791) network.
///
public struct IPv4Address {

  // Host byte order.

  /// The raw address (i.e. in host byte order).
  ///
  public var rawAddress: UInt32

  /// Creates a value with the given raw address.
  ///
  /// - parameters:
  ///     - rawAddress:   The address value in host byte order.
  ///
  @inlinable
  public init(rawAddress: UInt32) {
    self.rawAddress = rawAddress
  }

  // Network byte order.

  /// The network address (i.e. in network byte order).
  ///
  public var networkAddress: UInt32 {
    return rawAddress.bigEndian
  }

  /// Creates a value with the given network address.
  ///
  /// - parameters:
  ///     - networkAddress:   The address value in network byte order.
  ///
  @inlinable
  public init(networkAddress: UInt32) {
    self.init(rawAddress: networkAddress.bigEndian)
  }
}

// Standard protocols.

extension IPv4Address: Equatable, Hashable, LosslessStringConvertible {

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

// Parsing initializers.

extension IPv4Address {

  @inlinable public static func parse<Source, Callback>(
    _ input: Source, callback: inout Callback
  ) -> ParseResult where Source: StringProtocol, Callback: IPv4ParserCallback {
    return input._withUTF8 { parse($0, callback: &callback) }
  }

  @inlinable public init?<Source>(_ input: Source) where Source: StringProtocol {
    var callback = IgnoreValidationErrors()
    guard case .success(let parsedValue) = Self.parse(input, callback: &callback) else { return nil }
    self = parsedValue
  }
}

// Parsing and serialization impl.

extension IPv4Address {

  public enum ParseResult {
    case success(IPv4Address)
    case failure
    case notAnIPAddress
  }

  public struct ValidationError: Equatable, CustomStringConvertible {
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

    // Note: These are deliberately not public, because we don't want to make the set of possible errors API.
    //       They are 'internal' for testing purposes only.
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

  /// Parses an IPv4 address from a UTF-8 string.
  ///
  /// The given string may have 1, 2, 3 or 4 pieces, separated by a '.',
  /// and each piece may be specified in octal, decimal, or hexadecimal notation.
  /// A single trailing '.' is permitted.
  ///
  /// - parameters:
  ///     - input:     A buffer of ASCII/UTF-8 codepoints. The buffer does not have to be null-terminated.
  ///     - callback:  A callback to be invoked if a validation error occurs.
  /// - returns:
  ///     A result object containing either the successfully-parsed address, or a failure flag communicating whether parsing
  ///     failed because the string was not in the correct format.
  ///
  public static func parse<Bytes, Callback>(
    _ input: Bytes, callback: inout Callback
  ) -> ParseResult where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv4ParserCallback {
    guard input.isEmpty == false else {
      callback.validationError(ipv4: .emptyInput)
      return .failure
    }

    // This algorithm isn't from the WHATWG spec, but supports all the required shorthands.
    // Translated and adapted to Swift (with some modifications) from:
    // https://android.googlesource.com/platform/bionic/+/froyo/libc/inet/inet_aton.c

    var __pieces: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
    return withUnsafeMutableBytes(of: &__pieces) { rawPtr -> ParseResult in
      let pieces = rawPtr.bindMemory(to: UInt32.self)
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
        guard pieceIndex < 3 else {
          callback.validationError(ipv4: .tooManyPieces)
          return .notAnIPAddress
        }
        pieceIndex &+= 1
        pieces[pieceIndex] = value
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

      var rawAddress: UInt32 = 0
      switch pieceIndex {
      case 0:  // 'a'       - 32-bits.
        rawAddress = pieces[0]
      case 1:  // 'a.b'     - 8-bits/24-bits.
        var invalidBits = pieces[0] & ~0x0000_00FF
        invalidBits |= pieces[1] & ~0x00FF_FFFF
        guard invalidBits == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return .failure
        }
        rawAddress = (pieces[0] << 24) | pieces[1]
      case 2:  // 'a.b.c'   - 8-bits/8-bits/16-bits.
        var invalidBits = pieces[0] & ~0x0000_00FF
        invalidBits |= pieces[1] & ~0x0000_00FF
        invalidBits |= pieces[2] & ~0x0000_FFFF
        guard invalidBits == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return .failure
        }
        rawAddress = (pieces[0] << 24) | (pieces[1] << 16) | pieces[2]
      case 3:  // 'a.b.c.d' - 8-bits/8-bits/8-bits/8-bits.
        var invalidBits = pieces[0] & ~0x0000_00FF
        invalidBits |= pieces[1] & ~0x0000_00FF
        invalidBits |= pieces[2] & ~0x0000_00FF
        invalidBits |= pieces[3] & ~0x0000_00FF
        guard invalidBits == 0 else {
          callback.validationError(ipv4: .addressOverflows)
          return .failure
        }
        rawAddress = (pieces[0] << 24) | (pieces[1] << 16) | (pieces[2] << 8) | pieces[3]
      default:
        fatalError("Internal error. pieceIndex has unexpected value.")
      }
      // Parsing successful.
      return .success(IPv4Address(rawAddress: rawAddress))
    }
  }

  /// Parses an IPv4 address from a UTF-8 string.
  ///
  /// This simplified parser accepts only the 4-piece decimal notation ("a.b.c.d").
  /// Trailing '.'s are not permitted.
  ///
  /// - parameters:
  ///     - input:     A buffer of ASCII/UTF-8 codepoints. The buffer does not have to be null-terminated.
  ///     - callback:  A callback to be invoked if a validation error occurs. This callback is only invoked once,
  ///                  and any validation error terminates parsing.
  /// - returns:
  ///     Either the successfully-parsed address, or `.none` if parsing failed.
  ///
  public static func parse_simple<Bytes, Callback>(
    _ input: Bytes, callback: inout Callback
  ) -> Self? where Bytes: Collection, Bytes.Element == UInt8, Callback: IPv4ParserCallback {

    var result = UInt32(0)
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
        assert(digit != 99)  // We already checked it was a digit.
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
      result <<= 8
      result &+= UInt32(ipv4Piece)
      numbersSeen &+= 1
    }
    guard numbersSeen == 4 else {
      callback.validationError(ipv4: .notEnoughPieces)
      return nil
    }
    return IPv4Address(rawAddress: result)
  }
}

extension IPv4Address {

  public var serialized: String {
    // 15 bytes is the maximum length of an IPv4 address in decimal notation ("XXX.XXX.XXX.XXX"),
    // but is also happily the small-string size on 64-bit platforms.
    return String(_unsafeUninitializedCapacity: 15) { stringBuffer in
      return withUnsafeBytes(of: rawAddress.byteSwapped) { __rawAddressBytes -> Int in
        let addressBytes = __rawAddressBytes.bindMemory(to: UInt8.self)
        var stringBufferIdx = stringBuffer.startIndex
        for i in 0..<4 {
          stringBufferIdx &+= ASCII.insertDecimalString(
            for: addressBytes[i],
            into: UnsafeMutableBufferPointer(
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
  }
}
