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

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#else
  #error("Unknown libc variant")
#endif

extension Array where Element == UInt16 {
  init(fromIPv6Address addr: IPv6Address.AddressType) {
    self = [addr.0, addr.1, addr.2, addr.3, addr.4, addr.5, addr.6, addr.7]
  }
}

extension ValidationError {
  public var ipv6Error: IPv6Address.ValidationError? {
    guard case .some(.ipv6AddressError(let error)) = self.hostParserError else { return nil }
    return error
  }
}

final class IPv6AddressTests: XCTestCase {

  fileprivate func parse_pton(_ input: String) -> [UInt16]? {
    var result = in6_addr()
    guard inet_pton(AF_INET6, input, &result) != 0 else { return nil }
    return withUnsafeBytes(of: &result) { ptr in
      let u16 = ptr.bindMemory(to: UInt16.self)
      return Array(u16)
    }
  }

  fileprivate func serialize_ntop(_ input: [UInt16]) -> String? {
    var src = in6_addr()
    src.__u6_addr.__u6_addr16.0 = input[0]
    src.__u6_addr.__u6_addr16.1 = input[1]
    src.__u6_addr.__u6_addr16.2 = input[2]
    src.__u6_addr.__u6_addr16.3 = input[3]
    src.__u6_addr.__u6_addr16.4 = input[4]
    src.__u6_addr.__u6_addr16.5 = input[5]
    src.__u6_addr.__u6_addr16.6 = input[6]
    src.__u6_addr.__u6_addr16.7 = input[7]
    let str = String(_unsafeUninitializedCapacity: 40) {
      return $0.baseAddress!.withMemoryRebound(to: CChar.self, capacity: $0.count) {
        let p = inet_ntop(AF_INET6, &src, $0, 40)
        guard p != nil else { return 0 }
        return strlen($0)
      }
    }
    return str.isEmpty ? nil : str
  }

  func testBasic() {
    let testData: [(String, [UInt16], String)] = [
      // Canonical
      (
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334", [8193, 3512, 34211, 0, 0, 35374, 880, 29492],
        "2001:db8:85a3::8a2e:370:7334"
      ),
      // Teredo
      (
        "2001::ce49:7601:e866:efff:62c3:fffe", [8193, 0, 52809, 30209, 59494, 61439, 25283, 65534],
        "2001:0:ce49:7601:e866:efff:62c3:fffe"
      ),
      // Compact
      ("2608::3:5", [9736, 0, 0, 0, 0, 0, 3, 5], "2608::3:5"),
      // Empty
      ("::", [0, 0, 0, 0, 0, 0, 0, 0], "::"),
      // IPv4
      ("::ffff:192.168.0.1", [0, 0, 0, 0, 0, 65535, 49320, 1], "::ffff:c0a8:1"),
    ]

    for (string, expectedRawAddress, expectedDescription) in testData {
      guard let addr = IPv6Address(string) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }
      XCTAssertEqual(
        Array(fromIPv6Address: addr.rawAddress), expectedRawAddress,
        "Raw address mismatch for: \(string)"
      )
      XCTAssertEqual(
        Array(fromIPv6Address: addr.networkAddress), parse_pton(string),
        "Net address mismatch for: \(string)"
      )
      XCTAssertEqual(addr.serialized, expectedDescription)
      if let reparsedAddr = IPv6Address(addr.serialized) {
        XCTAssertEqual(
          addr, reparsedAddr,
          "Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.serialized)'"
        )
      } else {
        XCTFail("Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.serialized)'")
      }
    }
  }

  func testCompression() {
    let testData: [(String, [UInt16], String)] = [
      // Leading
      ("::1234:F088", [0, 0, 0, 0, 0, 0, 4660, 61576], "::1234:f088"),
      // Middle
      ("1212:F0F0::3434:D0D0", [4626, 61680, 0, 0, 0, 0, 13364, 53456], "1212:f0f0::3434:d0d0"),
      // Trailing
      ("1234:F088::", [4660, 61576, 0, 0, 0, 0, 0, 0], "1234:f088::"),
    ]

    for (string, expectedRawAddress, expectedDescription) in testData {
      guard let addr = IPv6Address(string) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }
      XCTAssertEqual(
        Array(fromIPv6Address: addr.rawAddress), expectedRawAddress,
        "Raw address mismatch for: \(string)"
      )
      XCTAssertEqual(
        Array(fromIPv6Address: addr.networkAddress), parse_pton(string),
        "Net address mismatch for: \(string)"
      )
      XCTAssertEqual(addr.serialized, expectedDescription)
      if let reparsedAddr = IPv6Address(addr.serialized) {
        XCTAssertEqual(
          addr, reparsedAddr,
          "Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.serialized)'"
        )
      } else {
        XCTFail("Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.serialized)'")
      }
    }
  }

  func testInvalid() {
    let invalidAddresses: [(String, IPv6Address.ValidationError)] = [
      // - Invalid piece.
      ("12345::", .unexpectedCharacter),
      ("FG::", .unexpectedCharacter),

      // - Invalid compression.
      (":", .unexpectedLeadingColon),
      (":::", .multipleCompressedPieces),
      ("F:", .unexpectedTrailingColon),
      ("42:", .unexpectedTrailingColon),

      // - Invalid IPv4 piece.
      ("::ffff:555.168.0.1", .invalidIPv4Address(.pieceOverflows)),
      ("::ffff:192.168.0.1.8", .invalidIPv4Address(.tooManyPieces)),
      // TODO: Is it worth having a separate "piece begins with invalid character" error?
      ("::ffff:192.168.a.1", .invalidIPv4Address(.pieceBeginsWithInvalidCharacter)),
      // TODO: Improve this. "unexpectedPeriod" should be more IPv4-related.
      ("::ffff:.168.0.1", .unexpectedPeriod),
      ("::ffff:192.168.0.01", .invalidIPv4Address(.unsupportedRadix)),
      ("::ffff:192.168.0xf.1", .invalidIPv4Address(.invalidCharacter)),
      // TODO: (Maybe) Improve this.
      ("::ffff:192.168.0.1.", .invalidIPv4Address(.tooManyPieces)),  // trailing dot
      // TODO: Improve this. Should be: "invalidPositionForIPv4Address"
      ("0001:0002:0003:0004:192.168.0.1:0006:0007:0008", .invalidIPv4Address(.invalidCharacter)),

      // - Invalid number of pieces.
      ("0001:0002:0003:0004:0005", .notEnoughPieces),
      ("0001:0002:0003:0004:0005:0006:0007:0008:0009", .tooManyPieces),
    ]

    for (string, expectedError) in invalidAddresses {
      var callback = LastValidationError()
      if let addr = IPv6Address.parse(string, callback: &callback) {
        XCTFail("Invalid address '\(string)' was parsed as '\(addr.rawAddress)' (raw)")
      } else {
        XCTAssertEqual(callback.error?.ipv6Error, expectedError, "Unexpected error for invalid address '\(string)'")
      }
    }
  }
}

extension IPv6AddressTests {

  /// Generate 1000 random IP addresses, serialize them via IPAddress.
  /// Then serialize the same addresss via `ntop`, and ensure it returns the same string.
  /// Then parse our serialized version back via `pton`, and ensure it returns the same address.
  ///
  func testRandom_Serialization() {
    for _ in 0..<1000 {
      let expected = IPv6Address.Utils.randomAddress()
      let address = IPv6Address(networkAddress: expected)
      if address.serialized.contains("::") {
        XCTAssertTrue(Array(fromIPv6Address: expected).longestSubrange(equalTo: 0).length > 0)
      }
      // Serialize with libc. It should return the same String.
      let libcStr = withUnsafePointer(to: expected) { intsPtr in
        intsPtr.withMemoryRebound(to: UInt16.self, capacity: 8) { addrPtr in
          return serialize_ntop(Array(UnsafeBufferPointer(start: addrPtr, count: 8)))
        }
      }
      // Exception: if the address <= UInt32.max, libc prints this as an embedded IPv4 address
      // (e.g. it prints "::198.135.80.188", we print "::c687:50bc").
      if libcStr?.contains(".") == true {
        XCTAssertTrue(expected.0 == 0 && expected.1.bigEndian <= UInt64(UInt32.max))
        continue
      }
      XCTAssertEqual(libcStr, address.serialized)

      // Parse our serialized output with libc. It should return the same address.
      let libcAddr = parse_pton(address.serialized)
      XCTAssertEqual(libcAddr, Array(fromIPv6Address: address.networkAddress))
    }
  }

  /// Generate 1000 random IP Address Strings, parse them via IPAddress,
  /// check that the numerical value matches the expected network address,
  /// and that `pton` gets the same result when parsing the same random String.
  ///
  func testRandom_Parsing() {
    for _ in 0..<1000 {
      let (randomAddress, randomAddressString) = IPv6Address.Utils.randomString()
      guard let parsedAddress = IPv6Address(randomAddressString) else {
        XCTFail("Failed to parse address: \(randomAddressString); expected address: \(randomAddress)")
        continue
      }
      XCTAssertEqual(Array(fromIPv6Address: parsedAddress.networkAddress), Array(fromIPv6Address: randomAddress))
      XCTAssertEqual(Array(fromIPv6Address: parsedAddress.networkAddress), parse_pton(randomAddressString))
    }
  }
}
