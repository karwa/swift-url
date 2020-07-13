import XCTest

@testable import URL

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#else
  #error("Unknown libc variant")
#endif

final class IPv4AddressTests: XCTestCase {

  fileprivate func parse_aton(_ straddr: String) -> UInt32? {
    var addr = in_addr()
    guard inet_aton(straddr, &addr) != 0 else { return nil }
    return addr.s_addr
  }

  fileprivate func serialize_ntoa(_ netaddr: UInt32) -> String {
    var addr = in_addr()
    addr.s_addr = netaddr
    return String(cString: inet_ntoa(addr))
  }

  func testBasic() {
    // 192.255.2.5 
    //  = (192 * 256^3) + (255 * 256^2) + (2 * 256) + (5 * 1)
    //  = 3221225472 + 16711680 + 512 + 5 
    //  = 3237937669
    let expectedRawAddress: UInt32 = 3_237_937_669

    let strings = [
      "3237937669",  // 1 component, decimal. 
      "0xC0.077601005",  // 2 components, hex/octal.
      "192.0xff.01005",  // 3 components, decimal/hex/octal.
      "192.255.2.5",  // 4 components, decimal.
    ]
    for string in strings {
      guard let addr = IPv4Address(string[...]) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }
      // Check that the result is the expected value.
      XCTAssertEqual(addr.rawAddress, expectedRawAddress, "Unexpected result for address: \(string)")
      // Check that libc gets the same result.
      XCTAssertEqual(addr.networkAddress, parse_aton(string), "Mismatch detected for address: \(string)")
      // Check the serialized value.
      XCTAssertEqual(addr.serialized, "192.255.2.5")
    }
  }

  func testTrailingDots() {
    let expectedRawAddress: UInt32 = 2_071_690_107

    // Zero trailing dots are allowed (obviously).
    if let addr = IPv4Address("123.123.123.123") {
      XCTAssertEqual(addr.rawAddress, expectedRawAddress)
      XCTAssertEqual(addr.networkAddress, parse_aton("123.123.123.123"))
      XCTAssertEqual(addr.serialized, "123.123.123.123")
    } else {
      XCTFail("Failed to parse valid address")
    }
    // One trailing dot is allowed.
    if let addr = IPv4Address("123.123.123.123.") {
      XCTAssertEqual(addr.rawAddress, expectedRawAddress)
      XCTAssertEqual(addr.serialized, "123.123.123.123")
    } else {
      XCTFail("Failed to parse valid address")
    }
    // Two or more trailing dots are not allowed.
    if let _ = IPv4Address("123.123.123.123..") { XCTFail("Expected fail") }
    if let _ = IPv4Address("123.123.123.123...") { XCTFail("Expected fail") }
    if let _ = IPv4Address("123.123.123.123....") { XCTFail("Expected fail") }
    // More than 4 components are not allowed.
    if let _ = IPv4Address("123.123.123.123.123") { XCTFail("Expected fail") }
    if let _ = IPv4Address("123.123.123.123.123.") { XCTFail("Expected fail") }
    if let _ = IPv4Address("123.123.123.123.123..") { XCTFail("Expected fail") }
  }

  func testTrailingZeroes() {
    if let addr = IPv4Address("234") {
      XCTAssertEqual(addr.networkAddress, parse_aton("234"))
      XCTAssertEqual(addr.rawAddress, 234)
      XCTAssertEqual(addr.serialized, "0.0.0.234")
    } else {
      XCTFail("Failed to parse valid address")
    }

    if let addr = IPv4Address("234.0") {
      XCTAssertEqual(addr.networkAddress, parse_aton("234.0"))
      XCTAssertEqual(addr.rawAddress, 3_925_868_544)
      XCTAssertEqual(addr.serialized, "234.0.0.0")
    } else {
      XCTFail("Failed to parse valid address")
    }

    // First, test that we parse the correct value with no trailing zeroes.
    // "234.011" = "234.0.0.9" (the 9 occupies the lowest byte) = 150995178 (big-endian).
    let noTrailingZeroes = [
      "234.011",
      "234.011.",
    ]
    for string in noTrailingZeroes {
      guard let addr = IPv4Address(string[...]) else {
        XCTFail("Failed to parse valid address")
        continue
      }
      let expectedRawAddress: UInt32 = 3_925_868_553
      // inet_aton doesn't accept trailing dots, but the WHATWG URL spec does.
      let libcString: String
      if string.hasSuffix(".") {
        libcString = String(string.dropLast())
      } else {
        libcString = string
      }
      XCTAssertEqual(addr.networkAddress, parse_aton(libcString))
      XCTAssertEqual(addr.rawAddress, expectedRawAddress)
      XCTAssertEqual(addr.serialized, "234.0.0.9")
    }

    // Next, test that we parse the correct value with any valid number of trailing zeroes.
    // "234.011.0" = "234.9.0.0" (the 9 is shifted up to the second byte and the lowest bytes are all zero) = 2538 (big-endian). 
    let valid_trailingZeroes = [
      "234.011.0",
      "234.011.0.",
      "234.011.0.0",
      "234.011.0.0.",
    ]
    for string in valid_trailingZeroes {
      guard let addr = IPv4Address(string[...]) else {
        XCTFail("Failed to parse valid address")
        continue
      }
      let expectedRawAddress: UInt32 = 3_926_458_368
      // inet_aton doesn't accept trailing dots, but the WHATWG URL spec does.
      let libcString: String
      if string.hasSuffix(".") {
        libcString = String(string.dropLast())
      } else {
        libcString = string
      }
      XCTAssertEqual(addr.networkAddress, parse_aton(libcString))
      XCTAssertEqual(addr.rawAddress, expectedRawAddress)
      XCTAssertEqual(addr.serialized, "234.9.0.0")
    }

    // Lastly, test that we reject an invalid number of trailing zeroes. 
    let invalid_trailingZeroes = [
      "234.011.0.0.0",
      "234.011.0.0.0.",
      "234.011.0.0.0.0",
      "234.011.0.0.0.0.",
    ]
    for string in invalid_trailingZeroes {
      XCTAssertNil(IPv4Address(string[...]), "Invalid address should have been rejected: \(string)")
      // Sanity check.
      XCTAssertNil(parse_aton(string), "libc unexpectedly considers this address valid: \(string)")
    }
  }

  func testInvalid() {
    if let _ = IPv4Address("0.0x300") {} else { XCTFail("Failed to parse valid address") }
    if let _ = IPv4Address("0..0x300") { XCTFail("Expected fail") }

    // Non-numbers.
    if let _ = IPv4Address("sup?") { XCTFail("Expected fail") }
    if let _ = IPv4Address("100sup?") { XCTFail("Expected fail") }
    if let _ = IPv4Address("100.sup?") { XCTFail("Expected fail") }

    // Overflow.
    if let _ = IPv4Address("0xFFFFFFFF") {} else { XCTFail("Failed to parse valid address") }
    if let _ = IPv4Address("0xFFFFFFFF1") { XCTFail("Expected to fail") }
    if let _ = IPv4Address("1.0xFFFFFFF") { XCTFail("Expected to fail") }
    if let _ = IPv4Address("1.1.0xFFFFF") { XCTFail("Expected to fail") }
    if let _ = IPv4Address("1.1.1.0xFFF") { XCTFail("Expected to fail") }

    // Invalid base-X characters.
    if let _ = IPv4Address("192.0xF") {} else { XCTFail("Failed to parse valid address") }
    if let _ = IPv4Address("192.F") { XCTFail("Expected fail") }
    if let _ = IPv4Address("192.0F") { XCTFail("Expected fail") }
  }
}

// Randomized testing.

extension IPv4AddressTests {

  /// Generate 1000 random IP addresses, serialise them via IPAddress, then
  /// parse the serialized version back via `aton`. Ensure that the same address
  /// is returned.
  ///
  func testRandom_Serialisation() {
    for _ in 0..<1000 {
      let randomAddress = UInt32.random(in: .min ... .max)
      let randomIPString = IPv4Address(networkAddress: randomAddress).serialized
      let atonAddress = parse_aton(randomIPString)
      XCTAssert(
        atonAddress == randomAddress,
        "Mismatch detected for address \(randomIPString) (\(randomAddress))"
      )
    }
  }

  /// Generates a random IP address string representing the given address.
  ///
  /// The string may randomly use any shorthand (a/a.b/a.b.c/a.b.c.d), and each piece may
  /// randomly be written in octal, decimal, or hexadecimal notation.
  ///
  /// For example, printing the address `123456789`:
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
  private static func makeRandomIPAddressString(for address: UInt32) -> String {
    enum Format: CaseIterable {
      case a
      case ab
      case abc
      case abcd
    }
    enum PieceRadix: CaseIterable {
      case octal
      case decimal
      case hex
    }
    let randomIPString: String

    func formatPiece<B: BinaryInteger>(piece: B, radix: PieceRadix) -> String {
      switch radix {
      case .octal: return "0" + String(piece, radix: 8)
      case .decimal: return String(piece, radix: 10)
      case .hex: return "0x" + String(piece, radix: 16)
      }
    }
    // swift-format-ignore
    switch Format.allCases.randomElement()! {
    case .a:
      let a = address
      randomIPString = formatPiece(piece: a, radix: PieceRadix.allCases.randomElement()!)
    case .ab:
      let a =  UInt8((address & 0b11111111_00000000_00000000_00000000) >> 24)
      let b = UInt32((address & 0b00000000_11111111_11111111_11111111))
      randomIPString = formatPiece(piece: a, radix: PieceRadix.allCases.randomElement()!) + "." +
                       formatPiece(piece: b, radix: PieceRadix.allCases.randomElement()!)
    case .abc:
      let a =  UInt8((address & 0b11111111_00000000_00000000_00000000) >> 24)
      let b =  UInt8((address & 0b00000000_11111111_00000000_00000000) >> 16)
      let c = UInt16((address & 0b00000000_00000000_11111111_11111111))
      randomIPString = formatPiece(piece: a, radix: PieceRadix.allCases.randomElement()!) + "." +
                       formatPiece(piece: b, radix: PieceRadix.allCases.randomElement()!) + "." +
                       formatPiece(piece: c, radix: PieceRadix.allCases.randomElement()!)
    case .abcd:
      let a =  UInt8((address & 0b11111111_00000000_00000000_00000000) >> 24)
      let b =  UInt8((address & 0b00000000_11111111_00000000_00000000) >> 16)
      let c =  UInt8((address & 0b00000000_00000000_11111111_00000000) >> 8)
      let d =  UInt8((address & 0b00000000_00000000_00000000_11111111))
      randomIPString = formatPiece(piece: a, radix: PieceRadix.allCases.randomElement()!) + "." +
                       formatPiece(piece: b, radix: PieceRadix.allCases.randomElement()!) + "." +
                       formatPiece(piece: c, radix: PieceRadix.allCases.randomElement()!) + "." +
                       formatPiece(piece: d, radix: PieceRadix.allCases.randomElement()!)
    }
    return randomIPString
  }

  /// Generate 1000 random IP Address Strings, parse them via IPAddress,
  /// check that the numerical value matches the expected network address,
  /// and that `aton` gets the same result when parsing the same random String.
  ///
  func testRandom_Parsing() {
    for _ in 0..<1000 {
      let randomAddress = UInt32.random(in: .min ... .max)
      let randomAddressString = Self.makeRandomIPAddressString(for: randomAddress)

      guard let parsedAddress = IPv4Address(randomAddressString) else {
        XCTFail("Failed to parse address: \(randomAddressString); expected address: \(randomAddress)")
        continue
      }
      XCTAssertEqual(parsedAddress.rawAddress, randomAddress)
      XCTAssertEqual(parsedAddress.networkAddress, parse_aton(randomAddressString))
    }
  }
}
