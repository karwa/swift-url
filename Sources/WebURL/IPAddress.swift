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


/// The way in which binary data is interpreted as an integer.
///
/// It is sometimes useful to view an IP address in terms units larger than individual octets;
/// for example viewing the 16 x 8-bit octets of an IPv6 address as 8 x 16-bit double-octet integers.
/// There are two ways to do this, depending on how we wish to interpret the resulting integers.
///
///  - The ``binary`` interpretation.
///
///    Larger integers contain the same octets, in the same order, as are found in memory.
///    These integers do not necessarily have any defined numerical meaning, but are useful for copying the
///    address to other memory.
///
///    For example, the first 16-bit piece of the IPv6 address `2608::3:5` has the numeric value 9736
///    on a big-endian machine. But those same octets, in the same order, are interpreted as the number 2086
///    by a little-endian machine. These numeric values are not meaningful because they are machine-dependent,
///    and the integers are simply used as byte storage.
///
///  - The ``numeric`` interpretation.
///
///    Larger integers contain the same octets as are found in memory, but are arranged to give a meaningful,
///    machine-independent numeric value.
///
///    For example, the first 16-bit piece of the IPv6 address `2608::3:5` will always appear to have
///    the numeric value `0x2608` (9736) when we print it or compare it to an integer parsed from a string.
///
/// The most important thing is to remember that endianness is a property of the data, and how it corresponds
/// to the endianness of your machine doesn't matter. The thing to think about when deciding which arrangement to
/// use is: are you using the integers just to copy bytes in memory? If so, use ``binary``.
/// Or do you want a meaningful number? In that case, use ``numeric``.
///
/// > Tip:
/// > If you can, see if you can solve your problem using octets and avoid thinking about this at all.
/// > An address' octets at position `.0`, `.1`, `.2`, etc. are always in the same order, and have the same
/// > binary representation and numeric value on every system.
///
public enum OctetArrangement {

  /// Integer pieces larger than an octet have a consistent numeric value on all machines.
  ///
  /// For example, the first 16-bit piece of the IPv6 address `2608::3:5` will always appear to have
  /// the numeric value `0x2608` (9736) when we print it, or compare it to an integer parsed from a string.
  ///
  case numeric

  /// Integer pieces larger than an octet have a consistent byte sequence on all machines.
  ///
  /// For example, the first 16-bit piece of the IPv6 address `2608::3:5` has the numeric value 9736
  /// on a big-endian machine, but those same octets, in the same order, are interpreted as the number 2086
  /// by a little-endian machine.
  ///
  /// These integers are just raw slices of memory, and only meaningful for copying to other memory.
  ///
  case binary

  /// A synonym for ``numeric``.
  @inlinable public static var hostOrder: Self { return .numeric }

  /// A synonym for ``binary``.
  @inlinable public static var networkOrder: Self { return .binary }
}


// --------------------------------------------
// MARK: - IPv6
// --------------------------------------------


/// A 128-bit numerical identifier assigned to a device on an [Internet Protocol, version 6][rfc2460] network.
///
/// Construct an `IPv6Address` initializing a value with an IP address string.
/// Parsing is defined by the URL Standard, and supports all of the shorthands described by
/// [Section 2.2 of RFC 4291][rfc4291] - "IP Version 6 Addressing Architecture//Text Representation of Addresses",
/// such as compressed pieces and embedded IPv4 addresses.
///
/// ```swift
/// IPv6Address("2001:0:ce49:7601:e866:efff:62c3:fffe")! // ✅ Full address
/// IPv6Address("2608::3:5")!                            // ✅ Compressed address
/// IPv6Address("::192.168.0.1")!                        // ✅ Embedded IPv4 address
///
/// // Or you can initialize from bytes/pieces directly.
/// IPv6Address(octets: (0x26, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x03, 0, 0x05))
/// IPv6Address(pieces: (0x2608, 0, 0, 0, 0, 0, 0x03, 0x05), .numeric)
/// ```
///
/// To obtain an address' string representation, use the ``serialized`` property or simply initialize a `String`.
/// This serialization conforms to [RFC 5952][rfc5952] - "A Recommendation for IPv6 Address Text Representation",
/// so it makes use of compressed notation and normalizes to lowercase.
///
/// ```swift
/// let address1 = IPv6Address("2001:0:CE49:7601:E866:EFFF:62C3:FFFE")!
/// address1.serialized  // ✅ "2001:0:ce49:7601:e866:efff:62c3:fffe"
/// String(address1)     // Same as above.
///
/// let address2 = IPv6Address("2608:0:0:0::3:5")!
/// address2.serialized  // ✅ "2608::3:5"
/// String(address2)     // Same as above.
/// ```
///
/// ### Connecting to an Address
///
/// The thing you'll most likely want to do with an IP address is connect to it, by converting to either C's `in6_addr`
/// or NIO's `SocketAddress`. To do so, use the ``octets-swift.property`` property to access the address' raw bytes
/// and copy them to the destination.
///
/// ```swift
/// let address = IPv6Address()
///
/// // Converting to C's in6_addr:
/// var c_address = in6_addr()
/// withUnsafeBytes(of: address.octets) { addressBytes in
///   withUnsafeMutableBytes(of: &c_address) { $0.copyMemory(from: addressBytes) }
/// }
///
/// // Creating an NIO SocketAddress:
/// let nioAddress = withUnsafeByes(of: address.octets) { addressBytes in
///   let buffer = ByteBuffer(bytes: addressBytes)
///   return try! SocketAddress(packedIPAddress: buffer, port: /* Your choice */)
/// }
/// ```
///
/// ### Reading or Modifying an Address
///
/// The ``octets-swift.property`` property allows you to read and modify the address' raw bytes (or "octets").
/// This can be useful if you're performing filtering or masking, or other low-level networking operations.
/// It is preferred to work with IP addresses in terms of octets.
///
/// ```swift
/// var address = IPv6Address("2001:0:ce49:7601:e866:efff:62c3:fffe")!
/// address.octets.0  //  32, 0x20
/// address.octets.1  //   1, 0x01
/// address.octets.4  // 206, 0xCE
/// address.octets.5  //  73, 0x49
///
/// address.octets.4 = 0xFA
/// address.octets.5 = 0xCE
/// print(address)
/// // ✅ "2001:0:face:7601:e866:efff:62c3:fffe"
/// //            ^^^^
/// ```
///
/// The ``subscript(pieces:)`` subscript allows you to read and modify the address' octets as 16-bit integers.
/// There are two ways to view the address at units larger than an octet - either as **binary data**
/// for copying to/from memory, or **numeric integers**, whose values are what you see when printing the address
/// as a string.
///
/// These correspond to the ``OctetArrangement/binary`` and ``OctetArrangement/numeric`` views of the address.
///
/// ```swift
/// var address = IPv6Address("2001:0:ce49:7601:e866:efff:62c3:fffe")!
///
/// // Use numeric pieces to read or write numeric integers or literals.
/// address[pieces: .numeric].0 = 0xFEED
/// address[pieces: .numeric].1 = 0xBEEF
/// print(address)
/// // ✅ "feed:beef:ce49:7601:e866:efff:62c3:fffe"
/// //     ^^^^ ^^^^
///
/// // Binary pieces should only be used when copying to/from memory.
/// address[pieces: .binary].0 = 0xFEED
/// address[pieces: .binary].1 = 0xBEEF
/// print(address)
/// // ❌ "edfe:efbe:ce49:7601:e866:efff:62c3:fffe"
/// //     ^^^^ ^^^^ - Where's the beef?!
/// ```
///
/// > Note:
/// > This type does not support Zone-IDs, as URLs themselves do not support Zone-IDs.
///
/// [rfc2460]: https://tools.ietf.org/html/rfc2460
/// [rfc4291]: https://tools.ietf.org/html/rfc4291#section-2.2
/// [rfc5952]: https://tools.ietf.org/html/rfc5952
///
/// ## Topics
///
/// ### Parsing an Address from a String
///
/// - ``IPv6Address/init(_:)``
/// - ``IPv6Address/init(utf8:)``
///
/// ### Obtaining an Address' String Representation
///
/// - ``IPv6Address/serialized``
///
/// ### Addresses as Bytes
///
/// - ``IPv6Address/init(octets:)``
/// - ``IPv6Address/octets-swift.property``
///
/// ### Addresses as 16-bit Integer Pieces
///
/// - ``IPv6Address/init(pieces:_:)``
/// - ``IPv6Address/subscript(pieces:)``
/// - ``OctetArrangement``
///
public struct IPv6Address {

  public typealias Octets = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  /// The octets of this address.
  ///
  /// The octets are the lowest-level, most basic interpretation of an address. They are also the simplest to work with,
  /// as they have the same binary and numeric values on every machine. It is correct to both copy addresses
  /// to/from memory as octets, and to use integer literals or other numeric integers with an address' octets.
  ///
  /// ```swift
  /// var address = IPv6Address("2001:0:ce49:7601:e866:efff:62c3:fffe")!
  /// address.octets.0  //  32, 0x20
  /// address.octets.1  //   1, 0x01
  /// address.octets.4  // 206, 0xCE
  /// address.octets.5  //  73, 0x49
  ///
  /// address.octets.4 = 0xFA
  /// address.octets.5 = 0xCE
  /// print(address)
  /// // ✅ "2001:0:face:7601:e866:efff:62c3:fffe"
  /// //            ^^^^
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/subscript(pieces:)``
  ///
  public var octets: Octets

  /// Creates an address from its raw octets.
  ///
  /// The octets are the lowest-level, most basic interpretation of an address. They are also the simplest to work with,
  /// as they have the same binary and numeric values on every machine. It is correct to both copy addresses
  /// to/from memory as octets, and to use integer literals or other numeric integers with an address' octets.
  ///
  /// ```swift
  /// // Yes, they are rather long.
  /// let address = IPv6Address(octets: (0x20, 0x01, 0x00, 0x00, 0xCE, 0x49, 0x76, 0x01, 0xE8, 0x66, 0xEF, 0xFF, 0x62, 0xC3, 0xFF, 0xFE))
  ///
  /// print(address)    // "2001:0:ce49:7601:e866:efff:62c3:fffe"
  /// address.octets.0  //  32, 0x20
  /// address.octets.1  //   1, 0x01
  /// address.octets.4  // 206, 0xCE
  /// address.octets.5  //  73, 0x49
  ///
  /// address.octets.4 = 0xFA
  /// address.octets.5 = 0xCE
  /// print(address)
  /// // ✅ "2001:0:face:7601:e866:efff:62c3:fffe"
  /// //            ^^^^
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/init(_:)``
  /// - ``IPv6Address/init(pieces:_:)``
  ///
  @inlinable
  public init(octets: Octets = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) {
    self.octets = octets
  }

  public typealias Pieces = (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16)

  /// Creates an address from 16-bit integer pieces.
  ///
  /// The 16-bit pieces are interpreted according to the `octetArrangement` parameter. If they are binary pieces
  /// being copied from memory, specify that they have ``OctetArrangement/binary`` arrangement.
  /// If they are numbers, for example integer literals or other numeric integers, specify that they
  /// have ``OctetArrangement/numeric`` arrangement.
  ///
  /// ```swift
  /// // These are integer literals, so use the '.numeric' interpretation.
  /// let address = IPv6Address(pieces: (0x2001, 0x0000, 0xCE49, 0x7601, 0xE866, 0xEFFF, 0x62C3, 0xFFFE), .numeric)
  ///
  /// // The numeric value is what we see in the string.
  /// print(address)               // "2001:0:ce49:7601:e866:efff:62c3:fffe"
  /// address[pieces: .numeric].2  // 0xCE49
  /// address[pieces: .numeric].3  // 0x7601
  ///
  /// // Binary pieces should only be used when copying to/from memory.
  /// let badAddress = IPv6Address(pieces: (0x2001, 0x0000, 0xCE49, 0x7601, 0xE866, 0xEFFF, 0x62C3, 0xFFFE), .binary)
  /// print(badAddress)            // ❌ "120:0:49ce:176:66e8:ffef:c362:feff"
  /// ```
  ///
  /// - parameters:
  ///   - pieces:           The integer pieces of the address.
  ///   - octetArrangement: The way in which the pieces should be interpreted.
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/init(_:)``
  /// - ``IPv6Address/init(octets:)``
  ///
  @inlinable
  public init(pieces: Pieces, _ octetArrangement: OctetArrangement) {
    self.init()
    self[pieces: octetArrangement] = pieces
  }

  /// The octets of this address, combined in to 16-bit integer pieces.
  ///
  /// The 16-bit pieces are accepted and returned according to the `octetArrangement` parameter. If they are
  /// binary pieces being copied to/from memory, specify that they have ``OctetArrangement/binary`` arrangement.
  /// If they are numbers, for example integer literals or other numeric integers, specify that they
  /// have ``OctetArrangement/numeric`` arrangement.
  ///
  /// ```swift
  /// // These are integer literals, so use the '.numeric' interpretation.
  /// var address = IPv6Address(pieces: (0x2001, 0x0000, 0xCE49, 0x7601, 0xE866, 0xEFFF, 0x62C3, 0xFFFE), .numeric)
  ///
  /// // The numeric value is what we see in the string.
  /// print(address)                // "2001:0:ce49:7601:e866:efff:62c3:fffe"
  /// address[pieces: .numeric].2   // 0xCE49
  /// address[pieces: .numeric].3   // 0x7601
  ///
  /// // Use numeric pieces to read or write numeric integers or literals.
  /// address[pieces: .numeric].2 = 0xFEED
  /// address[pieces: .numeric].3 = 0xFACE
  /// print(address)
  /// // ✅ "2001:0:feed:face:e866:efff:62c3:fffe"
  /// //            ^^^^ ^^^^
  ///
  /// // Binary pieces should only be used when copying to/from memory.
  /// address[pieces: .binary].2 = 0xFEED
  /// address[pieces: .binary].3 = 0xFACE
  /// print(address)
  /// // ❌ "2001:0:edfe:cefa:e866:efff:62c3:fffe"
  /// //            ^^^^ ^^^^
  /// ```
  ///
  /// - parameters:
  ///   - octetArrangement: The way in which the pieces should be interpreted.
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/octets-swift.property``
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

#if swift(>=5.5) && canImport(_Concurrency)
  extension IPv6Address: Sendable {}
#endif

// Parsing.

extension IPv6Address {

  /// Parses an IPv6 address string.
  ///
  /// The behavior of this parser is defined by the URL Standard, and supports all of the shorthands described by
  /// [Section 2.2 of RFC 4291][rfc4291] - "IP Version 6 Addressing Architecture//Text Representation of Addresses",
  /// such as compressed pieces and embedded IPv4 addresses.
  ///
  /// ```swift
  /// IPv6Address("2001:0:ce49:7601:e866:efff:62c3:fffe")! // ✅ Full address
  /// IPv6Address("2608::3:5")!                            // ✅ Compressed address
  /// IPv6Address("::192.168.0.1")!                        // ✅ Embedded IPv4 address
  /// ```
  ///
  /// > Note:
  /// > This parser supports the same formats for IPv6 addresses as `inet_pton`, but does not accept Zone-IDs.
  /// > Some implementations of `inet_pton` accept Zone-IDs in address strings as a non-standard extension,
  /// > but actual support varies greatly. Some platforms will appear to parse an address including a Zone-ID,
  /// > but really just ignore the Zone-ID value.
  ///
  /// [rfc4291]: https://tools.ietf.org/html/rfc4291#section-2.2
  ///
  /// - parameters:
  ///     - description: The string to parse.
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/serialized``
  ///
  @inlinable @inline(__always)
  public init?<StringType>(_ description: StringType) where StringType: StringProtocol {
    if let result = description._withContiguousUTF8({ IPv6Address(utf8: $0) }) {
      self = result
    } else {
      return nil
    }
  }

  /// Parses an IPv6 address string from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs an IPv6 address from raw UTF-8 bytes rather than requiring
  /// they be stored as a `String`. It uses precisely the same parsing algorithm as ``init(_:)``.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object, and parsing each line
  /// as an IPv6 address string directly from the binary text. Doing this saves allocating a String
  /// and UTF-8 validation. Since all valid address strings are ASCII, validating UTF-8 is redundant.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize from binary text.
  ///   let address = IPv6Address(utf8: lineBytes)
  ///   ...
  /// }
  /// ```
  ///
  /// > Note:
  /// > This is not the same as constructing an `IPv6Address` from its raw bytes.
  /// > The bytes provided to this function must contain a formatted address string.
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/serialized``
  /// - ``IPv6Address/init(octets:)``
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
          // Manual swap leads to surprisingly better codegen than 'swapAt': https://github.com/apple/swift/pull/36864
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

  /// The canonical textual representation of this address.
  ///
  /// This serialization is defined by the URL Standard, and conforms to [RFC 5952][rfc5952] -
  /// "A Recommendation for IPv6 Address Text Representation", so it makes use of compressed notation
  /// and normalizes to lowercase.
  ///
  /// ```swift
  /// let address1 = IPv6Address("2001:0:ce49:7601:e866:efff:62c3:fffe")!
  /// let address2 = IPv6Address("2608::0:0:0:3:5")!
  /// let address3 = IPv6Address("::192.168.0.1")!
  ///
  /// address1.serialized
  /// // "2001:0:ce49:7601:e866:efff:62c3:fffe" - ✅ Full address
  /// address2.serialized
  /// // "2608::3:5" - ✅ Compressed address
  /// address3.serialized
  /// // "::c0a8:1" - ✅ Hex notation
  /// ```
  ///
  /// > Note:
  /// > Some platforms make different decisions about whether certain IPv6 addresses should be formatted
  /// > as embedded IPv4 in their implementations of `inet_ntop`. This serialization is an independent implementation,
  /// > which is guaranteed to produce the same result on every platform (namely: hex notation).
  ///
  /// [rfc5952]: https://tools.ietf.org/html/rfc5952
  ///
  /// ## See Also
  ///
  /// - ``IPv6Address/init(_:)``
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


/// A 32-bit numerical identifier assigned to a device on an [Internet Protocol, version 4][rfc791] network.
///
/// Construct an `IPv4Address` by initializing a value with an IP address string.
/// Parsing is defined by the URL Standard, and supports all of the exotic shorthands
/// supported by C's `inet_aton`. It allows for 1-4 parts, each of which may be an octal, decimal, or hex number.
///
/// ```swift
/// let addr1 = IPv4Address("192.168.0.17")!  // ✅ "Dotted decimal"
/// let addr2 = IPv4Address("0x7F.1")!        // ✅ 2 Hex components
/// let addr3 = IPv4Address("0337.19.0xA")!   // ✅ Dec/Hex/Oct combined
///
/// // Or you can initialize from bytes/a 32-bit value directly.
/// let addr4 = IPv4Address(octets: (192, 168, 15, 200))
/// let addr5 = IPv4Address(value: 3232239560, .numeric)
/// ```
///
/// To obtain an address' string representation, use the ``serialized`` property or simply initialize a `String`.
/// This serialization uses dotted-decimal notation, as recommended by [RFC 4001][rfc4001],
/// "Textual Conventions for Internet Network Addresses".
///
/// ```swift
/// addr1.serialized  // "192.168.0.17"
/// addr2.serialized  // "127.0.0.1"
/// addr3.serialized  // "223.19.0.10"
///
/// String(addr4)     // "192.168.15.200"
/// String(addr5)     // "192.168.15.200", yes addr4 == addr5.
/// ```
///
/// ### Connecting to an Address
///
/// The thing you'll most likely want to do with an IP address is connect to it, by converting to either C's `in_addr`
/// or NIO's `SocketAddress`. To do so, use the ``octets-swift.property`` property to access the address' raw bytes
/// and copy them to the destination, or ``subscript(value:)`` to copy the address as a single 32-bit integer.
///
/// ```swift
/// let address = IPv4Address()
///
/// // Converting to C's in_addr:
/// let c_address = in_addr(s_addr: address[value: .binary])
///
/// // Creating an NIO SocketAddress:
/// let nioAddress = withUnsafeByes(of: address.octets) { addressBytes in
///   let buffer = ByteBuffer(bytes: addressBytes)
///   return try! SocketAddress(packedIPAddress: buffer, port: /* Your choice */)
/// }
/// ```
///
/// ### Reading or Modifying an Address
///
/// The ``octets-swift.property`` property allows you to read and modify the address' raw bytes (or "octets").
/// This can be useful if you're performing filtering or masking, or other low-level networking operations.
/// It is preferred to work with IP addresses in terms of octets, as they avoid all questions about byte-ordering.
///
/// ```swift
/// var address = IPv4Address("192.168.0.17")!
/// address.octets.0  //  192
/// address.octets.1  //  168
/// address.octets.2  //    0
/// address.octets.3  //   17
///
/// address.octets.1 = 111
/// address.octets.2 = 101
/// print(address)
/// // ✅ "192.111.101.17"
/// //         ^^^ ^^^
/// ```
///
/// The ``subscript(value:)`` subscript allows you to read and modify the address' octets as a 32-bit integer.
/// There are two ways to view the address at units larger than an octet - either as **binary data** for copying
/// to/from memory, or **numeric integers**, whose value corresponds to what you see when printing the address
/// as a string.
///
/// These correspond to the ``OctetArrangement/binary`` and ``OctetArrangement/numeric`` views of the address.
///
/// Unlike with IPv6 addresses, reading or writing an IPv4 address using larger pieces isn't that useful
/// outside of copying to/from memory. You should prefer using octets to read or manipulate IPv4 addresses.
///
/// [rfc791]: https://tools.ietf.org/html/rfc791
/// [rfc4001]: https://tools.ietf.org/html/rfc4001#page-7
///
/// ## Topics
///
/// ### Parsing an Address from a String
///
/// - ``IPv4Address/init(_:)``
/// - ``IPv4Address/init(dottedDecimal:)``
///
/// - ``IPv4Address/init(utf8:)``
/// - ``IPv4Address/init(dottedDecimalUTF8:)``
///
/// ### Obtaining an Address' String Representation
///
/// - ``IPv4Address/serialized``
///
/// ### Addresses as Bytes
///
/// - ``IPv4Address/init(octets:)``
/// - ``IPv4Address/octets-swift.property``
///
/// ### Addresses as a 32-bit Integer
///
/// - ``IPv4Address/init(value:_:)``
/// - ``IPv4Address/subscript(value:)``
/// - ``OctetArrangement``
///
public struct IPv4Address {

  public typealias Octets = (UInt8, UInt8, UInt8, UInt8)

  /// The octets of this address.
  ///
  /// The octets are the lowest-level, most basic interpretation of an address. They are also the simplest to work with,
  /// as they have the same binary and numeric values on every machine. It is correct to both copy addresses
  /// to/from memory as octets, and to use integer literals or other numeric integers with an address' octets.
  ///
  /// ```swift
  /// var address = IPv4Address("192.168.0.17")!
  /// address.octets.0  //  192
  /// address.octets.1  //  168
  /// address.octets.2  //    0
  /// address.octets.3  //   17
  ///
  /// address.octets.1 = 111
  /// address.octets.2 = 101
  /// print(address)
  /// // ✅ "192.111.101.17"
  /// //         ^^^ ^^^
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/subscript(value:)``
  ///
  public var octets: Octets

  /// Creates an address from its raw octets.
  ///
  /// The octets are the lowest-level, most basic interpretation of an address. They are also the simplest to work with,
  /// as they have the same binary and numeric values on every machine. It is correct to both copy addresses
  /// to/from memory as octets, and to use integer literals or other numeric integers with an address' octets.
  ///
  /// ```swift
  /// var address = IPv4Address(octets: (192, 168, 0, 17))
  /// address.octets.0  //  192
  /// address.octets.1  //  168
  /// address.octets.2  //    0
  /// address.octets.3  //   17
  ///
  /// address.octets.1 = 111
  /// address.octets.2 = 101
  /// print(address)
  /// // ✅ "192.111.101.17"
  /// //         ^^^ ^^^
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/init(_:)``
  /// - ``IPv4Address/init(dottedDecimal:)``
  /// - ``IPv4Address/init(value:_:)``
  ///
  public init(octets: Octets = (0, 0, 0, 0)) {
    self.octets = octets
  }

  /// Creates an address from a 32-bit integer.
  ///
  /// The 32-bit integer is interpreted according to the `octetArrangement` parameter. If it contains binary pieces
  /// being copied from memory, specify that it has ``OctetArrangement/binary`` arrangement. If it is a number,
  /// for example an integer literals or other numeric integer, specify that it has ``OctetArrangement/numeric``
  /// arrangement.
  ///
  /// Unlike with IPv6 addresses, reading or writing an IPv4 address using larger pieces isn't that useful
  /// outside of copying to/from memory. You should prefer using octets if assigning numerical meaning to
  /// any part of an IPv4 address.
  ///
  /// ```swift
  /// // This is an integer literal, so use the '.numeric' interpretation.
  /// let address = IPv4Address(value: 3232235537, .numeric)
  ///
  /// // The numeric value is what we see in the string and octets.
  /// print(address)     // "192.168.0.17"
  /// address.octets.0   //  192
  /// address.octets.1   //  168
  /// address.octets.2   //    0
  /// address.octets.3   //   17
  ///
  /// // Binary values should only be used when copying to/from memory.
  /// // For example, copying from C's in_addr:
  /// let c_address: in_addr = ...
  /// let address = IPv4Address(value: c_address.s_addr, .binary)
  /// ```
  ///
  /// - parameters:
  ///   - value:            The integer value of the address.
  ///   - octetArrangement: The way in which the value should be interpreted.
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/init(_:)``
  /// - ``IPv4Address/init(octets:)``
  ///
  public init(value: UInt32, _ octetArrangement: OctetArrangement) {
    self.init()
    self[value: octetArrangement] = value
  }

  /// The octets of this address, as a 32-bit integer.
  ///
  /// The 32-bit integer is accepted and returned according to the `octetArrangement` parameter. If it is
  /// a binary value being copied to/from memory, specify that it has ``OctetArrangement/binary`` arrangement.
  /// If it is a number, for example an integer literal or other numeric integer, specify that it has
  /// ``OctetArrangement/numeric`` arrangement.
  ///
  /// Unlike with IPv6 addresses, reading or writing an IPv4 address using larger pieces isn't that useful
  /// outside of copying to/from memory. You should prefer using octets if assigning numerical meaning to
  /// any part of an IPv4 address.
  ///
  /// ```swift
  /// // This is an integer literal, so use the '.numeric' interpretation.
  /// let address = IPv4Address(value: 3232235537, .numeric)
  ///
  /// // The numeric value is what we see in the string and octets.
  /// print(address)     // "192.168.0.17"
  /// address.octets.0   //  192
  /// address.octets.1   //  168
  /// address.octets.2   //    0
  /// address.octets.3   //   17
  ///
  /// // Binary values should only be used when copying to/from memory.
  /// // For example, copying to C's in_addr:
  /// let c_address: in_addr = in_addr(s_addr: address[value: .binary])
  /// ```
  ///
  /// - parameters:
  ///   - octetArrangement: The way in which the value should be interpreted.
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/octets-swift.property``
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

#if swift(>=5.5) && canImport(_Concurrency)
  extension IPv4Address: Sendable {}
#endif

// Parsing.

extension IPv4Address {

  /// Parses an IPv4 address string.
  ///
  /// The behavior of this parser is defined by the URL Standard, and supports all of the exotic shorthands
  /// supported by C's `inet_aton`. It allows for 1-4 parts, each of which may be an octal, decimal, or hex number.
  ///
  /// ```swift
  /// IPv4Address("192.168.0.17")!  // ✅ "Dotted decimal"
  /// IPv4Address("0x7F.1")!        // ✅ 2 Hex components
  /// IPv4Address("0337.19.0xA")!   // ✅ Dec/Hex/Oct combined
  /// ```
  ///
  /// These exotic address formats are generally discouraged, but are supported for web compatibility.
  /// Use the ``init(dottedDecimal:)`` initializer instead to limit supported formats to the 4-piece "dotted-decimal"
  /// notation.
  ///
  /// ```swift
  /// IPv4Address(dottedDecimal: "192.168.0.17")! // ✅ "Dotted decimal"
  /// IPv4Address(dottedDecimal: "0x7F.1")        // ❌ nil
  /// IPv4Address(dottedDecimal: "0337.19.0xA")   // ❌ nil
  /// ```
  ///
  /// ### Accepted Formats
  ///
  /// This parser supports the same formats as C's `aton`, which are:
  ///
  ///  - term `a.b.c.d`: where each numeric part defines the value of the address' octet at that position.
  ///  - term `a.b.c`: where _a_ and _b_ define the address' first 2 octets, and _c_ is interpreted as a 16-bit integer
  ///    whose most and least significant bytes define the address' 3rd and 4th octets respectively.
  ///  - term `a.b`: where _a_ defines the address' first octet, and _b_ is interpreted as a 24-bit integer
  ///    whose bytes define the remaining octets from most to least significant.
  ///  - term `a`: where _a_ is interpreted as a 32-bit integer whose bytes define the octets of the address
  ///    in order from most to least significant.
  ///
  /// The numeric parts may be written in octal (prefixed with a `0`), decimal, or hexadecimal
  /// (prefixed with `0x` or `0X`). Additionally, a single trailing '.' is permitted (e.g. `a.b.c.d.`).
  ///
  /// - parameters:
  ///     - description: The string to parse.
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/serialized``
  ///
  @inlinable @inline(__always)
  public init?<StringType>(_ description: StringType) where StringType: StringProtocol {
    if let result = description._withContiguousUTF8({ IPv4Address(utf8: $0) }) {
      self = result
    } else {
      return nil
    }
  }

  /// Parses an IPv4 address string from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs an IPv4 address from raw UTF-8 bytes rather than requiring they be stored
  /// as a `String`. It uses precisely the same parsing algorithm as ``init(_:)``.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object, and parsing each line
  /// as an IPv4 address string directly from the binary text. Doing this saves allocating a String
  /// and UTF-8 validation. Since all valid address strings are ASCII, validating UTF-8 is redundant.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize from binary text.
  ///   let address = IPv4Address(utf8: lineBytes)
  ///   ...
  /// }
  /// ```
  ///
  /// > Note:
  /// > This is not the same as constructing an `IPv4Address` from its raw bytes.
  /// > The bytes provided to this function must contain a formatted address string.
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/serialized``
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

  /// Parses an IPv4 address string in dotted-decimal notation.
  ///
  /// This initializer is more selective than ``init(_:)``, and only recognizes IPv4 addresses
  /// in 4-piece dotted-decimal notation. The more exotic formats supported by C's `aton` will
  /// **not** be considered IPv4 addresses.
  ///
  /// ```swift
  /// IPv4Address(dottedDecimal: "192.168.0.17")! // ✅ "Dotted decimal"
  /// IPv4Address(dottedDecimal: "0x7F.1")        // ❌ nil
  /// IPv4Address(dottedDecimal: "0337.19.0xA")   // ❌ nil
  /// ```
  ///
  /// - parameters:
  ///     - string: The string to parse.
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/serialized``
  ///
  @inlinable @inline(__always)
  public init?<StringType>(dottedDecimal string: StringType) where StringType: StringProtocol {
    if let result = string._withContiguousUTF8({ IPv4Address(dottedDecimalUTF8: $0) }) {
      self = result
    } else {
      return nil
    }
  }

  /// Parses an IPv4 address string in dotted-decimal notation, from a collection of UTF-8 code-units.
  ///
  /// This initializer constructs an IPv4 address from raw UTF-8 bytes rather than requiring they be stored
  /// as a `String`. It uses precisely the same parsing algorithm as ``init(dottedDecimal:)``.
  ///
  /// The following example demonstrates loading a file as a Foundation `Data` object, and parsing each line
  /// as an IPv4 address string directly from the binary text. Doing this saves allocating a String
  /// and UTF-8 validation. Since all valid address strings are ASCII, validating UTF-8 is redundant.
  ///
  /// ```swift
  /// let fileContents: Data = getFileContents()
  ///
  /// for lineBytes = fileContents.lazy.split(0x0A /* ASCII line feed */) {
  ///   // ℹ️ Initialize from binary text.
  ///   let address = IPv4Address(dottedDecimalUTF8: lineBytes)
  ///   ...
  /// }
  /// ```
  ///
  /// > Note:
  /// > This is not the same as constructing an `IPv4Address` from its raw bytes.
  /// > The bytes provided to this function must contain a formatted address string.
  ///
  /// - parameters:
  ///     - utf8: The string to parse, as a collection of UTF-8 code-units.
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/serialized``
  ///
  @inlinable @inline(__always)
  public init?<UTF8Bytes>(dottedDecimalUTF8 utf8: UTF8Bytes) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    let _parsed =
      utf8.withContiguousStorageIfAvailable {
        IPv4Address.parseDottedDecimal(utf8: $0.boundsChecked)
      } ?? IPv4Address.parseDottedDecimal(utf8: utf8)
    guard let parsed = _parsed else {
      return nil
    }
    self = parsed
  }

  @inlinable
  internal static func parseDottedDecimal<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> IPv4Address? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

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
    return IPv4Address(value: numericAddress, .numeric)
  }
}

// Serialization.

extension IPv4Address {

  /// The canonical textual representation of this address.
  ///
  /// This serialization uses dotted-decimal notation, as recommended by [RFC 4001][rfc4001],
  /// "Textual Conventions for Internet Network Addresses".
  ///
  /// ```swift
  /// let address1 = IPv4Address("192.168.0.17")!
  /// let address2 = IPv4Address("0x7F.1")!
  /// let address3 = IPv4Address("0337.19.0xA")!
  ///
  /// address1.serialized  // "192.168.0.17" ✅ "Dotted decimal"
  /// address2.serialized  // "127.0.0.1"    ✅ 4 components
  /// address3.serialized  // "223.19.0.10"
  /// ```
  ///
  /// [rfc4001]: https://tools.ietf.org/html/rfc4001#page-7
  ///
  /// ## See Also
  ///
  /// - ``IPv4Address/init(_:)``
  /// - ``IPv4Address/init(dottedDecimal:)``
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
