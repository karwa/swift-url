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

import WebURL

extension IPv4Address {
  public enum Utils {}
}

extension IPv4Address.Utils {

  // Random addresses.

  /// Returns a random 32-bit number, which may be interpreted as an IPv4 network address.
  ///
  public static func randomAddress() -> UInt32 {
    var rng = SystemRandomNumberGenerator()
    return randomAddress(using: &rng)
  }

  /// Returns a random 32-bit number, which may be interpreted as an IPv4 network address.
  ///
  public static func randomAddress<RNG: RandomNumberGenerator>(using rng: inout RNG) -> UInt32 {
    return .random(in: 0 ... .max, using: &rng)
  }

  // Random strings.

  public enum Format: CaseIterable {
    case a
    case ab
    case abc
    case abcd
  }

  public enum PieceRadix: CaseIterable {
    case octal
    case decimal
    case hex
  }

  /// Generates a random IP address string representing the given address.
  /// The returned string describes the octets of the address in binary/big-endian/network byte order.
  ///
  /// - parameters:
  ///   - address:         The address to serialize
  ///   - allowedFormats:  The set of allowed shorthand formats which may be produced.
  ///                      One of these will be selected at random.
  ///   - allowedRadixes:  The set of allowed radixes for pieces of the chosen format.
  ///                      The radix for each piece will be selected at random from this list.
  ///
  /// Example representations of the address `123456789`:
  /// ```
  /// 7.0x5b.0xcd.0x15  (dec/hex/hex/hex)
  /// 07.0x5b.52501     (oct/hex/dec)
  /// 7.0133.0146425    (dec/oct/oct)
  /// 7.6016277         (dec/dec)
  /// 07.0133.0315.025  (oct/oct/oct/oct)
  /// 7.0x5b.205.21     (dec/hex/dec/dec)
  /// 0726746425        (oct)
  /// ```
  ///
  public static func randomString(
    address: UInt32,
    allowedFormats: [Format] = Format.allCases,
    allowedRadixes: [PieceRadix] = PieceRadix.allCases
  ) -> String {
    var rng = SystemRandomNumberGenerator()
    return randomString(
      address: address, allowedFormats: allowedFormats, allowedRadixes: allowedRadixes, using: &rng
    )
  }

  /// Generates a random IP address string representing the given address.
  /// The returned string describes the octets of the address in binary/big-endian/network byte order.
  ///
  /// - seealso: `randomString<RNG>(address:allowedFormats:allowedRadixes:)`
  ///
  public static func randomString<RNG: RandomNumberGenerator>(
    address: UInt32,
    allowedFormats: [Format] = Format.allCases,
    allowedRadixes: [PieceRadix] = PieceRadix.allCases,
    using rng: inout RNG
  ) -> String {

    func formatPiece<B: BinaryInteger>(piece: B, radix: PieceRadix) -> String {
      switch radix {
      case .octal: return "0" + String(piece, radix: 8)
      case .decimal: return String(piece, radix: 10)
      case .hex: return "0x" + String(piece, radix: 16)
      }
    }

    // Bitmasking and shifting are numeric operations, but we want the bytes to be serialized
    // as they are in the binary representation, so little-endian machines must byte-swap.
    let address = address.bigEndian

    // swift-format-ignore
    switch allowedFormats.randomElement(using: &rng)! {
    case .a:
      let a = address
      return formatPiece(piece: a, radix: allowedRadixes.randomElement(using: &rng)!)
    case .ab:
      let a =  UInt8((address & 0b11111111_00000000_00000000_00000000) >> 24)
      let b = UInt32((address & 0b00000000_11111111_11111111_11111111))
      return formatPiece(piece: a, radix: allowedRadixes.randomElement(using: &rng)!) + "." +
             formatPiece(piece: b, radix: allowedRadixes.randomElement(using: &rng)!)
    case .abc:
      let a =  UInt8((address & 0b11111111_00000000_00000000_00000000) >> 24)
      let b =  UInt8((address & 0b00000000_11111111_00000000_00000000) >> 16)
      let c = UInt16((address & 0b00000000_00000000_11111111_11111111))
      return formatPiece(piece: a, radix: allowedRadixes.randomElement(using: &rng)!) + "." +
             formatPiece(piece: b, radix: allowedRadixes.randomElement(using: &rng)!) + "." +
             formatPiece(piece: c, radix: allowedRadixes.randomElement(using: &rng)!)
    case .abcd:
      let a =  UInt8((address & 0b11111111_00000000_00000000_00000000) >> 24)
      let b =  UInt8((address & 0b00000000_11111111_00000000_00000000) >> 16)
      let c =  UInt8((address & 0b00000000_00000000_11111111_00000000) >> 8)
      let d =  UInt8((address & 0b00000000_00000000_00000000_11111111))
      return formatPiece(piece: a, radix: allowedRadixes.randomElement(using: &rng)!) + "." +
             formatPiece(piece: b, radix: allowedRadixes.randomElement(using: &rng)!) + "." +
             formatPiece(piece: c, radix: allowedRadixes.randomElement(using: &rng)!) + "." +
             formatPiece(piece: d, radix: allowedRadixes.randomElement(using: &rng)!)
    }
  }
}

// MARK: - IPv6

extension IPv6Address {
  public enum Utils {}
}

extension IPv6Address.Utils {

  // Random addresses.

  /// Generates a random 128-bit number, which may be interpreted as an IPv6 network address.
  ///
  /// At random, a series of 16-bit pieces are set to 0, in order to prompt a compressed serialization format.
  /// There is no bias to produce more addresses in the IPv4 range.
  ///
  public static func randomAddress() -> IPv6Address.Pieces {
    var rng = SystemRandomNumberGenerator()
    let injectCompression = Bool.random(using: &rng)
    return randomAddress(limitedToIPv4: false, injectCompression: injectCompression, using: &rng)
  }

  /// Generates a random 128-bit number, which may be interpreted as an IPv6 network address.
  ///
  /// - parameters:
  ///   - limitedToIPv4:     If `true`, the resulting addresses are limited to the IPv4 range.
  ///   - injectCompression: If `true`, a random series of 16-bit pieces are set to 0, in order to prompt a compressed serialization format.
  ///   - rng:               The `RandomNumberGenerator` to use.
  ///
  public static func randomAddress<RNG: RandomNumberGenerator>(
    limitedToIPv4: Bool,
    injectCompression: Bool,
    using rng: inout RNG
  ) -> IPv6Address.Pieces {

    var address: IPv6Address.Pieces = (0, 0, 0, 0, 0, 0, 0, 0)

    switch limitedToIPv4 {
    case true:
      withUnsafeMutableBytes(of: &address) { octets in
        octets[12] = .random(in: 0 ... .max, using: &rng)
        octets[13] = .random(in: 0 ... .max, using: &rng)
        octets[14] = .random(in: 0 ... .max, using: &rng)
        octets[15] = .random(in: 0 ... .max, using: &rng)
      }

    case false:
      withUnsafeMutableBytes(of: &address) { octets in
        octets[0] = .random(in: 0 ... .max, using: &rng)
        octets[1] = .random(in: 0 ... .max, using: &rng)
        octets[2] = .random(in: 0 ... .max, using: &rng)
        octets[3] = .random(in: 0 ... .max, using: &rng)
        octets[4] = .random(in: 0 ... .max, using: &rng)
        octets[5] = .random(in: 0 ... .max, using: &rng)
        octets[6] = .random(in: 0 ... .max, using: &rng)
        octets[7] = .random(in: 0 ... .max, using: &rng)
        octets[8] = .random(in: 0 ... .max, using: &rng)
        octets[9] = .random(in: 0 ... .max, using: &rng)
        octets[10] = .random(in: 0 ... .max, using: &rng)
        octets[11] = .random(in: 0 ... .max, using: &rng)
        octets[12] = .random(in: 0 ... .max, using: &rng)
        octets[13] = .random(in: 0 ... .max, using: &rng)
        octets[14] = .random(in: 0 ... .max, using: &rng)
        octets[15] = .random(in: 0 ... .max, using: &rng)

        if injectCompression {
          // Compress a random range by setting octets to 0. The range should:
          // - Be aligned to a 2-octet piece, and
          // - Be at least 4 octets long, and
          // - End at another 2-octet piece.
          let compressStart = Int.random(in: 0..<6)
          let compressEnd = Int.random(in: (compressStart + 2)..<9)
          for x in (compressStart * 2)..<(compressEnd * 2) {
            octets[x] = 0
          }
        }
      }
    }
    return address
  }

  // Random strings.

  /// Generates a random IPv6 address and random serialization.
  ///
  /// The goal is for this function to return pretty-much all of the addresses our IPv6Address parser supports.
  /// As a rough guide, assuming the RNG gives random `Bool`s with 50:50 chance and all `UInt64`s are generated with equal probability:
  ///
  /// - 50% chance to get an address in the IPv4 range
  ///   - 25% chance that it gets formatted as an IPv4 address ("::192.168.0.1")
  ///   - 25% chance that it gets formatted as an IPv6 address ("::c0a8:1")
  /// - 50% chance to get an address beyond the IPv4 range
  ///   - 25% chance that some region of it is compressed
  ///     - 12.5% chance that it is actually formatted as a compressed address ("ff08::c80a")
  ///     - 12.5% chance that it contains a string of zeroes ("ff08:0:0:0:0:0:0:c80a")
  ///   - 25% chance that it is not compressed
  ///
  /// This may be skewed a bit - some generated addresses will already be compressed, regardless of our
  /// randomized toggle to inject compressible pieces.
  ///
  /// The returned string describes the 16-bit pieces of the address in binary/big-endian/network byte order.
  ///
  public static func randomString() -> (IPv6Address.Pieces, String) {
    var rng = SystemRandomNumberGenerator()
    let address = randomAddress(
      limitedToIPv4: Bool.random(using: &rng),
      injectCompression: Bool.random(using: &rng),
      using: &rng
    )
    let string = randomString(
      address: address,
      allowIPv4Addresses: true,
      mayCompress: true,
      using: &rng
    )
    return (address, string)
  }

  /// Generates a random IPv6 address string.
  ///
  /// The format of the resulting String is configured by the `allowIPv4Addresses` and `mayCompress` flags. These flags only describe
  /// the allowed formats, and the actual format will be randomly selected given that configuration.
  ///
  /// The returned string describes the 16-bit pieces of the address in binary/big-endian/network byte order.
  ///
  /// - parameters:
  ///   - address:             The address to serialize.
  ///   - allowIPv4Addresses:  If `true`, and if `address` represents a value that could be written as an IPv4 address, the resulting String
  ///                          may contain an embedded IPv4 address.
  ///   - mayCompress:         If `true`, and if `address` has a string of zero-valued `UInt16` pieces, the resulting String may compress
  ///                          them using the "::" notation.
  ///   - using:               The random number generator to use.
  ///
  ///
  public static func randomString<RNG: RandomNumberGenerator>(
    address: IPv6Address.Pieces,
    allowIPv4Addresses: Bool,
    mayCompress: Bool,
    using rng: inout RNG
  ) -> String {

    // If the address can be represented as an IPv4 address, randomly decide to format it that way.

    let binaryIPv4Address = withUnsafeBytes(of: address) { rawAddress -> UInt32? in
      guard rawAddress[0..<12].allSatisfy({ $0 == 0 }) else { return nil }
      return rawAddress.baseAddress!.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
    }

    if let ipv4Address = binaryIPv4Address, allowIPv4Addresses && Bool.random(using: &rng) {
      let ipv4Piece = IPv4Address.Utils.randomString(
        address: ipv4Address,
        allowedFormats: [.abcd], allowedRadixes: [.decimal],
        using: &rng
      )
      return "::" + ipv4Piece
    }

    // Otherwise, serialize as an IPv6 address. Randomly compressing pieces which can be compressed or not.

    var addressString = ""

    withUnsafeBytes(of: address) { addressBytes in
      let pieces = addressBytes.bindMemory(to: UInt16.self)
      let compressedRange: (subrange: Range<Int>, length: Int)
      if mayCompress && Bool.random(using: &rng) {
        compressedRange = pieces._longestSubrange(equalTo: 0)
      } else {
        compressedRange = (subrange: 0..<0, length: 0)
      }

      for i in pieces.startIndex..<compressedRange.subrange.startIndex {
        addressString += String(pieces[i].bigEndian, radix: 16).lowercased()
        addressString += ":"
      }
      if compressedRange.length > 0 {
        if !addressString.isEmpty {
          addressString.removeLast()
        }
        addressString += "::"
      }
      for i in compressedRange.subrange.endIndex..<pieces.endIndex {
        addressString += String(pieces[i].bigEndian, radix: 16).lowercased()
        addressString += ":"
      }
      if compressedRange.subrange.endIndex != pieces.endIndex {
        addressString.removeLast()
      }
    }

    return addressString
  }
}


// --------------------------------------------
// MARK: - Unaligned loads
// --------------------------------------------


extension UnsafeRawPointer {

  /// Returns a new instance of the given type, constructed from the raw memory at the specified offset.
  ///
  /// The memory at this pointer plus offset must be initialized to `T` or another type that is layout compatible with `T`.
  /// It does not need to be aligned for access to `T`.
  ///
  @inlinable @inline(__always)
  internal func loadUnaligned<T>(fromByteOffset offset: Int = 0, as: T.Type) -> T where T: FixedWidthInteger {
    assert(_isPOD(T.self))
    var val: T = 0
    withUnsafeMutableBytes(of: &val) {
      $0.copyMemory(from: UnsafeRawBufferPointer(start: self + offset, count: MemoryLayout<T>.stride))
    }
    return val
  }
}
