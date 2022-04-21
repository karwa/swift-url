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

import WebURLTestSupport
import XCTest

@testable import WebURL

final class IPv6AddressTests: XCTestCase {

  func testBasic() {

    let testData: [(String, String, IPv6Address.Octets, IPv6Address.Pieces)] = [
      // Canonical
      (
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334", "2001:db8:85a3::8a2e:370:7334",
        (0x20, 0x01, 0x0d, 0x0b8, 0x85, 0xa3, 0x00, 0x00, 0x00, 0x00, 0x8a, 0x2e, 0x03, 0x70, 0x73, 0x34),
        (0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334)
      ),
      // Teredo
      (
        "2001::ce49:7601:e866:efff:62c3:fffe", "2001:0:ce49:7601:e866:efff:62c3:fffe",
        (0x20, 0x01, 0x00, 0x00, 0xce, 0x49, 0x76, 0x01, 0xe8, 0x66, 0xef, 0xff, 0x62, 0xc3, 0xff, 0xfe),
        (0x2001, 0x0000, 0xce49, 0x7601, 0xe866, 0xefff, 0x62c3, 0xfffe)
      ),
      // Compact
      (
        "2608::3:5", "2608::3:5",
        (0x26, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x05),
        (0x2608, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0003, 0x0005)
      ),
      // Empty
      (
        "::", "::",
        (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00),
        (0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000)
      ),
      // IPv4
      (
        "::ffff:192.168.0.1", "::ffff:c0a8:1",
        (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xc0, 0xa8, 0x00, 0x01),
        (0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xffff, 0xc0a8, 0x0001)
      ),
    ]

    for (string, expectedDescription, expectedOctets, expectedNumericPieces) in testData {
      guard let addr = IPv6Address(string) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }

      XCTAssertEqual(addr.octets, expectedOctets)
      XCTAssertEqual(addr.serialized, expectedDescription)
      XCTAssertEqual(addr[pieces: .numeric], expectedNumericPieces)
      XCTAssertEqual(
        Array(elements: addr[pieces: .binary]), Array(elements: expectedNumericPieces).map { UInt16(bigEndian: $0) }
      )

      guard let reparsedAddr = IPv6Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(addr.octets, reparsedAddr.octets)
      XCTAssertEqual(addr.serialized, reparsedAddr.serialized)
    }
  }

  func testCompression() {

    let testData: [(String, String, IPv6Address.Octets, IPv6Address.Pieces)] = [
      // Leading
      (
        "::1234:F088", "::1234:f088",
        (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0xf0, 0x88),
        (0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x1234, 0xf088)
      ),
      (
        "0:0::0:192.168.0.2", "::c0a8:2",
        (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0xa8, 0x00, 0x02),
        (0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xc0a8, 0x0002)
      ),
      // Middle
      (
        "1212:F0F0::3434:D0D0", "1212:f0f0::3434:d0d0",
        (0x12, 0x12, 0xf0, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x34, 0xd0, 0xd0),
        (0x1212, 0xf0f0, 0x0000, 0x0000, 0x0000, 0x0000, 0x3434, 0xd0d0)
      ),
      // Trailing
      (
        "1234:F088::", "1234:f088::",
        (0x12, 0x34, 0xf0, 0x88, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00),
        (0x1234, 0xf088, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000)
      ),
    ]

    for (string, expectedDescription, expectedOctets, expectedNumericPieces) in testData {
      guard let addr = IPv6Address(string) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }

      XCTAssertEqual(addr.octets, expectedOctets)
      XCTAssertEqual(addr.serialized, expectedDescription)
      XCTAssertEqual(addr[pieces: .numeric], expectedNumericPieces)
      XCTAssertEqual(
        Array(elements: addr[pieces: .binary]), Array(elements: expectedNumericPieces).map { UInt16(bigEndian: $0) }
      )

      guard let reparsedAddr = IPv6Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(addr.octets, reparsedAddr.octets)
      XCTAssertEqual(addr.serialized, reparsedAddr.serialized)
    }
  }

  func testInvalid() {

    let invalidAddresses: [(String, IPv6Address.ParserError)] = [
      // - Invalid piece.
      ("12345::", .unexpectedCharacter),
      ("FG::", .unexpectedCharacter),

      // - Invalid compression.
      (":", .unexpectedLeadingColon),
      (":::", .multipleCompressedPieces),
      ("F:", .unexpectedTrailingColon),
      ("42:", .unexpectedTrailingColon),

      // - Invalid IPv4 piece.

      ("::ffff:555.168.0.1", .invalidIPv4Address),
      ("::ffff:192.168.0.1.8", .invalidIPv4Address),
      ("::ffff:192.168.a.1", .invalidIPv4Address),
      ("::ffff:192.168.0.01", .invalidIPv4Address),
      ("::ffff:192.168.0xf.1", .invalidIPv4Address),
      ("::ffff:192.168.0.1.", .invalidIPv4Address),  // trailing dot
      ("::ffff:.168.0.1", .unexpectedPeriod),
      // TODO: Improve this. Should be: "invalidPositionForIPv4Address"
      ("0001:0002:0003:0004:192.168.0.1:0006:0007:0008", .invalidIPv4Address),

      // - Invalid number of pieces.
      ("0001:0002:0003:0004:0005", .notEnoughPieces),
      ("0001:0002:0003:0004:0005:0006:0007:0008:0009", .tooManyPieces),

      // - Invalid characters.
      ("::helo", .unexpectedCharacter),
      ("::.", .unexpectedPeriod),
      (":: ", .unexpectedCharacter),
      ("::\n", .unexpectedCharacter),
      ("::\t", .unexpectedCharacter),
      ("::ff ff", .unexpectedCharacter),
      ("::ff\nff", .unexpectedCharacter),
      ("1234k:12k::1234", .unexpectedCharacter),
      ("1234:12k4::1234", .unexpectedCharacter),
      ("1234:12k::1234k", .unexpectedCharacter),

      // - Trailing garbage.
      ("::c0a8:2\t", .unexpectedCharacter),
      ("::c0a8:2\n", .unexpectedCharacter),
      ("::c0a8:2 ", .unexpectedCharacter),
      ("::c0a8:2hello", .unexpectedCharacter),
      ("::c0a8:2 hello", .unexpectedCharacter),

      // - Leading garbage.
      ("\t::c0a8:2", .unexpectedCharacter),
      ("\n::c0a8:2", .unexpectedCharacter),
      (" ::c0a8:2", .unexpectedCharacter),
      ("hello::c0a8:2", .unexpectedCharacter),
      ("hello ::c0a8:2", .unexpectedCharacter),
    ]

    struct LastParserError: IPAddressParserCallback {
      var error: IPv6Address.ParserError?
      mutating func validationError(ipv6 error: IPv6Address.ParserError) {
        self.error = error
      }
      func validationError(ipv4 error: IPv4Address.ParserError) {
        XCTFail("Unexpected IPv4 error: \(error)")
      }
    }

    for (string, expectedError) in invalidAddresses {
      var callback = LastParserError()
      if let addr = IPv6Address.parse(utf8: string.utf8, callback: &callback) {
        XCTFail("Invalid address '\(string)' was parsed as '\(addr)")
      }
      XCTAssertEqual(
        callback.error?.errorCode, expectedError.errorCode, "Unexpected error for invalid address '\(string)'"
      )
    }
  }
}


// --------------------------------------------
// MARK: - Protocol conformances
// --------------------------------------------


#if swift(>=5.5) && canImport(_Concurrency)

  extension IPv6AddressTests {

    func testSendable() {
      // Since Sendable only exists at compile-time, it's enough to just ensure that this type-checks.
      func _requiresSendable<T: Sendable>(_: T) {}
      _requiresSendable(IPv6Address())
    }
  }

#endif


// --------------------------------------------
// MARK: - Randomized testing
// --------------------------------------------


#if canImport(Glibc) || canImport(Darwin) || canImport(WinSDK)

  #if canImport(Glibc)
    import Glibc
    // let in6_addr_octets = \in6_addr.__in6_u.__u6_addr8
    let in6_addr_pieces = \in6_addr.__in6_u.__u6_addr16
  #elseif canImport(Darwin)
    import Darwin
    // let in6_addr_octets = \in6_addr.__u6_addr.__u6_addr8
    let in6_addr_pieces = \in6_addr.__u6_addr.__u6_addr16
  #elseif canImport(WinSDK)
    import WinSDK
    // let in6_addr_octets = \in6_addr.u.Byte
    let in6_addr_pieces = \in6_addr.u.Word
  #endif

  fileprivate func libc_pton(_ input: String) -> IPv6Address.Pieces? {
    var result = in6_addr()
    guard inet_pton(AF_INET6, input, &result) != 0 else { return nil }
    return (
      result[keyPath: in6_addr_pieces].0,
      result[keyPath: in6_addr_pieces].1,
      result[keyPath: in6_addr_pieces].2,
      result[keyPath: in6_addr_pieces].3,
      result[keyPath: in6_addr_pieces].4,
      result[keyPath: in6_addr_pieces].5,
      result[keyPath: in6_addr_pieces].6,
      result[keyPath: in6_addr_pieces].7
    )
  }

  fileprivate func libc_ntop(_ input: IPv6Address.Pieces) -> String? {
    var src = in6_addr()
    src[keyPath: in6_addr_pieces].0 = input.0
    src[keyPath: in6_addr_pieces].1 = input.1
    src[keyPath: in6_addr_pieces].2 = input.2
    src[keyPath: in6_addr_pieces].3 = input.3
    src[keyPath: in6_addr_pieces].4 = input.4
    src[keyPath: in6_addr_pieces].5 = input.5
    src[keyPath: in6_addr_pieces].6 = input.6
    src[keyPath: in6_addr_pieces].7 = input.7
    let bytes = [CChar](unsafeUninitializedCapacity: Int(INET6_ADDRSTRLEN)) { buffer, count in
      #if canImport(WinSDK)
        let p = inet_ntop(AF_INET6, &src, buffer.baseAddress, buffer.count)
      #else
        let p = inet_ntop(AF_INET6, &src, buffer.baseAddress, socklen_t(buffer.count))
      #endif
      count = (p == nil) ? 0 : (strlen(buffer.baseAddress!) + 1 /* null-terminator, written by inet_ntop */)
    }
    return bytes.isEmpty ? nil : String(cString: bytes)
  }

  extension IPv6AddressTests {

    /// Tests IPv6Address serialization with random addresses, and compares the results to the system's libc implementations.
    ///
    /// - Generate a random IP address, serialize it via IPv6Address.
    /// - Serialize the same addresss via `ntop`, and ensure it returns the same serialized string.
    ///   - If there is a difference, make sure we know what it happening and why there is a difference.
    /// - Parse our serialization via `pton`, and ensure it returns the same address.
    /// - Parse our serialization again using IPv6Address, to ensure that the parser and serializer round-trip.
    ///
    func testRandom_Serialization() {
      for _ in 0..<1000 {
        let expectedPieces = IPv6Address.Utils.randomAddress()
        let address = IPv6Address(pieces: expectedPieces, .binary)

        // Serialize the address with libc.
        // Both implementations should return the same serialization.
        let libcStr = libc_ntop(expectedPieces)
        if libcStr?.contains(".") == true {
          // Some implementations of ntop serialize addresses which are <= UInt32.max as embedded IPv4 addresses.
          // (e.g. ntop might print "::198.135.80.188", we print "::c687:50bc").
          XCTAssertTrue(
            Array(elements: expectedPieces).dropLast(2).allSatisfy { $0 == 0 },
            "ntop produced unexpected serialization '\(libcStr!)' for address \(expectedPieces)"
          )
        } else {
          XCTAssertEqual(
            libcStr, address.serialized,
            "Serialization mismatch for address \(expectedPieces)"
          )
        }

        // Parse our serialized output with libc.
        // It should be able to parse our serialization and return the same address.
        XCTAssertEqual(
          libc_pton(address.serialized), address[pieces: .binary],
          "pton returned a different address for string: \(address.serialized)"
        )

        // Parse our serialized output with IPv6Address.
        // We should be able to re-parse our serialization and return the same address.
        if let reparsed = IPv6Address(address.serialized) {
          XCTAssertEqual(
            address.octets, reparsed.octets,
            "\(address.serialized) reparsed as \(reparsed.serialized)"
          )
        } else {
          XCTFail("Address failed to re-parse: \(address.serialized)")
        }
      }
    }

    /// Tests IPv6Address parsing with random addresses, and compares the results to the system's libc implementations.
    ///
    /// - Generate a random IP Address and serialization, including quirks such as embedded IPv4 addresses, compressed pieces, etc.
    /// - Parse the serialization via IPv6Address.
    /// - Check that the parsed address matches the expected network address.
    /// - Check that `pton` gets the same result when parsing the same serialization.
    ///
    func testRandom_Parsing() {
      for _ in 0..<1000 {
        let (expectedPieces, randomAddressString) = IPv6Address.Utils.randomString()

        guard let parsedAddress = IPv6Address(randomAddressString) else {
          XCTFail("Failed to parse serialization '\(randomAddressString)' of address: \(expectedPieces)")
          continue
        }

        // Check the value is correct.
        XCTAssertEqual(
          parsedAddress[pieces: .binary], expectedPieces,
          "Incorrect address for string: \(randomAddressString)"
        )

        // Parse the same string with libc.
        // Both implementations should return the same address.
        XCTAssertEqual(
          parsedAddress[pieces: .binary], libc_pton(randomAddressString),
          "pton returned a different address for string: \(randomAddressString)"
        )
      }
    }
  }

#endif
