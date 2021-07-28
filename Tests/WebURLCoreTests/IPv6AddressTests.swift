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

@testable import WebURLCore

extension Array {
  fileprivate init(ipv6Octets addr: IPv6Address.Octets) where Element == UInt8 {
    self = [
      addr.0, addr.1, addr.2, addr.3, addr.4, addr.5, addr.6, addr.7,
      addr.8, addr.9, addr.10, addr.11, addr.12, addr.13, addr.14, addr.15,
    ]
  }

  fileprivate init(ipv6Pieces addr: IPv6Address.Pieces) where Element == UInt16 {
    self = [addr.0, addr.1, addr.2, addr.3, addr.4, addr.5, addr.6, addr.7]
  }
}

final class IPv6AddressTests: XCTestCase {

  func testBasic() {

    let testData: [(String, String, [UInt8], [UInt16])] = [
      // Canonical
      (
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334", "2001:db8:85a3::8a2e:370:7334",
        [0x20, 0x01, 0x0d, 0x0b8, 0x85, 0xa3, 0x00, 0x00, 0x00, 0x00, 0x8a, 0x2e, 0x03, 0x70, 0x73, 0x34],
        [0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334]
      ),
      // Teredo
      (
        "2001::ce49:7601:e866:efff:62c3:fffe", "2001:0:ce49:7601:e866:efff:62c3:fffe",
        [0x20, 0x01, 0x00, 0x00, 0xce, 0x49, 0x76, 0x01, 0xe8, 0x66, 0xef, 0xff, 0x62, 0xc3, 0xff, 0xfe],
        [0x2001, 0x0000, 0xce49, 0x7601, 0xe866, 0xefff, 0x62c3, 0xfffe]
      ),
      // Compact
      (
        "2608::3:5", "2608::3:5",
        [0x26, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x05],
        [0x2608, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0003, 0x0005]
      ),
      // Empty
      (
        "::", "::",
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        [0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000]
      ),
      // IPv4
      (
        "::ffff:192.168.0.1", "::ffff:c0a8:1",
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xc0, 0xa8, 0x00, 0x01],
        [0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xffff, 0xc0a8, 0x0001]
      ),
    ]

    for (string, expectedDescription, expectedOctets, expectedNumericPieces) in testData {
      guard let addr = IPv6Address(string) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }

      XCTAssertEqual(Array(ipv6Octets: addr.octets), expectedOctets)
      XCTAssertEqual(addr.serialized, expectedDescription)
      XCTAssertEqual(Array(ipv6Pieces: addr[pieces: .numeric]), expectedNumericPieces)
      XCTAssertEqual(Array(ipv6Pieces: addr[pieces: .binary]), expectedNumericPieces.map { UInt16(bigEndian: $0) })

      guard let reparsedAddr = IPv6Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(Array(ipv6Octets: addr.octets), Array(ipv6Octets: reparsedAddr.octets))
      XCTAssertEqual(addr.serialized, reparsedAddr.serialized)
    }
  }

  func testCompression() {

    let testData: [(String, String, [UInt8], [UInt16])] = [
      // Leading
      (
        "::1234:F088", "::1234:f088",
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0xf0, 0x88],
        [0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x1234, 0xf088]
      ),
      (
        "0:0::0:192.168.0.2", "::c0a8:2",
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0xa8, 0x00, 0x02],
        [0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0xc0a8, 0x0002]
      ),
      // Middle
      (
        "1212:F0F0::3434:D0D0", "1212:f0f0::3434:d0d0",
        [0x12, 0x12, 0xf0, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x34, 0xd0, 0xd0],
        [0x1212, 0xf0f0, 0x0000, 0x0000, 0x0000, 0x0000, 0x3434, 0xd0d0]
      ),
      // Trailing
      (
        "1234:F088::", "1234:f088::",
        [0x12, 0x34, 0xf0, 0x88, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        [0x1234, 0xf088, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000]
      ),
    ]

    for (string, expectedDescription, expectedOctets, expectedNumericPieces) in testData {
      guard let addr = IPv6Address(string) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }

      XCTAssertEqual(Array(ipv6Octets: addr.octets), expectedOctets)
      XCTAssertEqual(addr.serialized, expectedDescription)
      XCTAssertEqual(Array(ipv6Pieces: addr[pieces: .numeric]), expectedNumericPieces)
      XCTAssertEqual(Array(ipv6Pieces: addr[pieces: .binary]), expectedNumericPieces.map { UInt16(bigEndian: $0) })

      guard let reparsedAddr = IPv6Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(Array(ipv6Octets: addr.octets), Array(ipv6Octets: reparsedAddr.octets))
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

// Randomized testing.

#if canImport(Glibc) || canImport(Darwin) || canImport(WinSDK)

  #if canImport(Glibc)
    import Glibc
    let in6_addr_octets = \in6_addr.__in6_u.__u6_addr8
    let in6_addr_pieces = \in6_addr.__in6_u.__u6_addr16
  #elseif canImport(WinSDK)
    import WinSDK
    let in6_addr_octets = \in6_addr.u.Byte
    let in6_addr_pieces = \in6_addr.u.Word
  #elseif canImport(Darwin)
    import Darwin
    let in6_addr_octets = \in6_addr.__u6_addr.__u6_addr8
    let in6_addr_pieces = \in6_addr.__u6_addr.__u6_addr16
  #endif

  fileprivate func pton_octets(_ input: String) -> [UInt8]? {
    var result = in6_addr()

    guard inet_pton(AF_INET6, input, &result) != 0 else { return nil }
    return withUnsafeBytes(of: &result[keyPath: in6_addr_octets]) { ptr in
      let u16 = ptr.bindMemory(to: UInt8.self)
      return Array(u16)
    }
  }

  fileprivate func pton_pieces(_ input: String) -> [UInt16]? {
    var result = in6_addr()
    guard inet_pton(AF_INET6, input, &result) != 0 else { return nil }
    return withUnsafeBytes(of: &result[keyPath: in6_addr_pieces]) { ptr in
      let u16 = ptr.bindMemory(to: UInt16.self)
      return Array(u16)
    }
  }

  fileprivate func ntop_octets(_ input: [UInt8]) -> String? {
    var src = in6_addr()
    src[keyPath: in6_addr_octets].0 = input[0]
    src[keyPath: in6_addr_octets].1 = input[1]
    src[keyPath: in6_addr_octets].2 = input[2]
    src[keyPath: in6_addr_octets].3 = input[3]
    src[keyPath: in6_addr_octets].4 = input[4]
    src[keyPath: in6_addr_octets].5 = input[5]
    src[keyPath: in6_addr_octets].6 = input[6]
    src[keyPath: in6_addr_octets].7 = input[7]
    src[keyPath: in6_addr_octets].8 = input[8]
    src[keyPath: in6_addr_octets].9 = input[9]
    src[keyPath: in6_addr_octets].10 = input[10]
    src[keyPath: in6_addr_octets].11 = input[11]
    src[keyPath: in6_addr_octets].12 = input[12]
    src[keyPath: in6_addr_octets].13 = input[13]
    src[keyPath: in6_addr_octets].14 = input[14]
    src[keyPath: in6_addr_octets].15 = input[15]
    let bytes = [CChar](unsafeUninitializedCapacity: Int(INET6_ADDRSTRLEN)) { buffer, count in
      #if canImport(WinSDK)
        let p = inet_ntop(AF_INET6, &src, buffer.baseAddress, buffer.count)
      #else
        let p = inet_ntop(AF_INET6, &src, buffer.baseAddress, socklen_t(buffer.count))
      #endif
      count = (p == nil) ? 0 : strlen(buffer.baseAddress!)
    }
    return bytes.isEmpty ? nil : String(cString: bytes)
  }

  fileprivate func ntop_pieces(_ input: [UInt16]) -> String? {
    var src = in6_addr()
    src[keyPath: in6_addr_pieces].0 = input[0]
    src[keyPath: in6_addr_pieces].1 = input[1]
    src[keyPath: in6_addr_pieces].2 = input[2]
    src[keyPath: in6_addr_pieces].3 = input[3]
    src[keyPath: in6_addr_pieces].4 = input[4]
    src[keyPath: in6_addr_pieces].5 = input[5]
    src[keyPath: in6_addr_pieces].6 = input[6]
    src[keyPath: in6_addr_pieces].7 = input[7]
    let bytes = [CChar](unsafeUninitializedCapacity: Int(INET6_ADDRSTRLEN)) { buffer, count in
      #if canImport(WinSDK)
        let p = inet_ntop(AF_INET6, &src, buffer.baseAddress, buffer.count)
      #else
        let p = inet_ntop(AF_INET6, &src, buffer.baseAddress, socklen_t(buffer.count))
      #endif
      count = (p == nil) ? 0 : strlen(buffer.baseAddress!)
    }
    return bytes.isEmpty ? nil : String(cString: bytes)
  }

  extension IPv6AddressTests {

    /// Generate 1000 random IP addresses, serialize them via IPAddress.
    /// Then serialize the same addresss via `ntop`, and ensure it returns the same string.
    /// Then parse our serialized version back via `pton`, and ensure it returns the same address.
    ///
    func testRandom_Serialization() {
      for _ in 0..<1000 {
        let expected = IPv6Address.Utils.randomAddress()
        let address = IPv6Address(pieces: expected, .binary)
        if address.serialized.contains("::") {
          XCTAssertTrue(Array(ipv6Pieces: expected)._longestSubrange(equalTo: 0).length > 0)
        }

        // Serialize with libc. It should return the same String.
        let libcStr = ntop_pieces(Array(ipv6Pieces: expected))
        if libcStr?.contains(".") == true {
          // Exception: if the address <= UInt32.max, libc may print this as an embedded IPv4 address on some platforms
          // (e.g. it prints "::198.135.80.188", we print "::c687:50bc").
          XCTAssertTrue(Array(ipv6Pieces: expected).dropLast(2).allSatisfy { $0 == 0 })
        } else {
          XCTAssertEqual(libcStr, address.serialized)
        }

        // Parse our serialized output with libc. It should return the same address.
        XCTAssertEqual(pton_octets(address.serialized), Array(ipv6Octets: address.octets))
        XCTAssertEqual(pton_pieces(address.serialized), Array(ipv6Pieces: address[pieces: .binary]))
      }
    }

    /// Generate 1000 random IP Address Strings, parse them via IPAddress,
    /// check that the numerical value matches the expected network address,
    /// and that `pton` gets the same result when parsing the same random String.
    ///
    func testRandom_Parsing() {
      for _ in 0..<1000 {
        let (randomPieces, randomAddressString) = IPv6Address.Utils.randomString()
        guard let parsedAddress = IPv6Address(randomAddressString) else {
          XCTFail("Failed to parse address: \(randomAddressString); expected pieces: \(randomPieces)")
          continue
        }
        XCTAssertEqual(Array(ipv6Octets: parsedAddress.octets), pton_octets(randomAddressString))
        XCTAssertEqual(Array(ipv6Pieces: parsedAddress[pieces: .binary]), Array(ipv6Pieces: randomPieces))
        XCTAssertEqual(Array(ipv6Pieces: parsedAddress[pieces: .binary]), pton_pieces(randomAddressString))
      }
    }
  }

#endif
