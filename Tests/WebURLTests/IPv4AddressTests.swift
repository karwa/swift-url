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

extension UInt32 {
  fileprivate var octets: [UInt8] {
    withUnsafeBytes(of: self) { Array($0) }
  }
}

extension Array {
  fileprivate init(ipv4Octets: IPv4Address.Octets) where Element == UInt8 {
    self = [ipv4Octets.0, ipv4Octets.1, ipv4Octets.2, ipv4Octets.3]
  }
}

final class IPv4AddressTests: XCTestCase {

  func testBasic() {

    let expectedNumericAddress: UInt32 = 3_237_937_669
    let strings = [
      "3237937669",  // 1 component, decimal.
      "0xC0.077601005",  // 2 components, hex/octal.
      "192.0xff.01005",  // 3 components, decimal/hex/octal.
      "192.255.2.5",  // 4 components, decimal.
      "0xc0.0xff.0x02.0x05",  // 4 components, hex.
    ]
    for string in strings {
      guard let addr = IPv4Address(string[...]) else {
        XCTFail("Failed to parse valid address: \(string)")
        continue
      }
      XCTAssertEqual(Array(ipv4Octets: addr.octets), [192, 255, 2, 5])
      XCTAssertEqual(addr.serialized, "192.255.2.5")
      XCTAssertEqual(addr[value: .numeric], expectedNumericAddress)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: expectedNumericAddress))

      guard let reparsedAddr = IPv4Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(Array(ipv4Octets: addr.octets), Array(ipv4Octets: reparsedAddr.octets))
      XCTAssertEqual(addr.serialized, reparsedAddr.serialized)
    }
  }

  func testTrailingDots() {

    let expectedNumericAddress: UInt32 = 16_909_060

    // Zero trailing dots are allowed (obviously).
    if let addr = IPv4Address("1.2.3.4") {
      XCTAssertEqual(Array(ipv4Octets: addr.octets), [1, 2, 3, 4])
      XCTAssertEqual(addr.serialized, "1.2.3.4")
      XCTAssertEqual(addr[value: .numeric], expectedNumericAddress)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: expectedNumericAddress))
    } else {
      XCTFail("Failed to parse valid address")
    }

    // One trailing dot is allowed.
    if let addr = IPv4Address("1.2.3.4.") {
      XCTAssertEqual(Array(ipv4Octets: addr.octets), [1, 2, 3, 4])
      XCTAssertEqual(addr.serialized, "1.2.3.4")
      XCTAssertEqual(addr[value: .numeric], expectedNumericAddress)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: expectedNumericAddress))
    } else {
      XCTFail("Failed to parse valid address")
    }

    // Two or more trailing dots are not allowed.
    if let _ = IPv4Address("1.2.3.4..") { XCTFail("Expected fail") }
    if let _ = IPv4Address("1.2.3.4...") { XCTFail("Expected fail") }
    if let _ = IPv4Address("1.2.3.4....") { XCTFail("Expected fail") }
    // More than 4 components are not allowed.
    if let _ = IPv4Address("1.2.3.4.5") { XCTFail("Expected fail") }
    if let _ = IPv4Address("1.2.3.4.5.") { XCTFail("Expected fail") }
    if let _ = IPv4Address("1.2.3.4.5..") { XCTFail("Expected fail") }
  }

  func testTrailingZeroes() {

    if let addr = IPv4Address("234") {
      XCTAssertEqual(Array(ipv4Octets: addr.octets), [0, 0, 0, 234])
      XCTAssertEqual(addr.serialized, "0.0.0.234")
      XCTAssertEqual(addr[value: .numeric], 234)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: 234))
    } else {
      XCTFail("Failed to parse valid address")
    }

    if let addr = IPv4Address("234.0") {
      XCTAssertEqual(Array(ipv4Octets: addr.octets), [234, 0, 0, 0])
      XCTAssertEqual(addr.serialized, "234.0.0.0")
      XCTAssertEqual(addr[value: .numeric], 3_925_868_544)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: 3_925_868_544))
    } else {
      XCTFail("Failed to parse valid address")
    }

    // First, test that we parse the correct value with no trailing zeroes.
    // "234.011" = "234.0.0.9" (the octal 9 occupies the lowest byte) = 0xEA000009 = 3925868553.
    let noTrailingZeroes = [
      "234.011",
      "234.011.",
    ]
    for string in noTrailingZeroes {
      let expectedNumericAddress: UInt32 = 3_925_868_553

      guard let addr = IPv4Address(string) else {
        XCTFail("Failed to parse valid address")
        continue
      }

      XCTAssertEqual(Array(ipv4Octets: addr.octets), [234, 0, 0, 9])
      XCTAssertEqual(addr.serialized, "234.0.0.9")
      XCTAssertEqual(addr[value: .numeric], expectedNumericAddress)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: expectedNumericAddress))

      guard let reparsedAddr = IPv4Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(Array(ipv4Octets: addr.octets), Array(ipv4Octets: reparsedAddr.octets))
      XCTAssertEqual(addr.serialized, reparsedAddr.serialized)
    }

    // Next, test that we parse the correct value with any valid number of trailing zeroes.
    // "234.011.0" = "234.9.0.0" (the 9 is shifted up to the second byte and the lowest bytes are all zero)
    // = 0xEA090000 = 3926458368.
    let valid_trailingZeroes = [
      "234.011.0",
      "234.011.0.",
      "234.011.0.0",
      "234.011.0.0.",
    ]
    for string in valid_trailingZeroes {
      let expectedNumericAddress: UInt32 = 3_926_458_368

      guard let addr = IPv4Address(string) else {
        XCTFail("Failed to parse valid address")
        continue
      }

      XCTAssertEqual(Array(ipv4Octets: addr.octets), [234, 9, 0, 0])
      XCTAssertEqual(addr.serialized, "234.9.0.0")
      XCTAssertEqual(addr[value: .numeric], expectedNumericAddress)
      XCTAssertEqual(addr[value: .binary], UInt32(bigEndian: expectedNumericAddress))

      guard let reparsedAddr = IPv4Address(addr.serialized) else {
        XCTFail("Failed to reparse. Original: '\(string)'. Parsed: '\(addr.serialized)'")
        continue
      }
      XCTAssertEqual(Array(ipv4Octets: addr.octets), Array(ipv4Octets: reparsedAddr.octets))
      XCTAssertEqual(addr.serialized, reparsedAddr.serialized)
    }

    // Finally, test that we reject an invalid number of trailing zeroes.
    let invalid_trailingZeroes = [
      "234.011.0.0.0",
      "234.011.0.0.0.",
      "234.011.0.0.0.0",
      "234.011.0.0.0.0.",
    ]
    for string in invalid_trailingZeroes {
      XCTAssertNil(IPv4Address(string), "Invalid address should have been rejected: \(string)")
    }
  }

  func testInvalid() {
    // TODO: Check for specific validation errors.

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
    if let _ = IPv4Address("192.0xG") { XCTFail("Expected fail") }
  }
}

// Randomized testing.

#if canImport(Glibc) || canImport(Darwin)

  #if canImport(Glibc)
    import Glibc
  #else
    import Darwin
  #endif

  func libc_aton(_ straddr: String) -> UInt32? {
    var addr = in_addr()
    guard inet_aton(straddr, &addr) != 0 else { return nil }
    return addr.s_addr
  }

  func libc_ntoa(_ netaddr: UInt32) -> String {
    var addr = in_addr()
    addr.s_addr = netaddr
    return String(cString: inet_ntoa(addr))
  }

  extension IPv4AddressTests {

    /// Generate 1000 random IP addresses, serialize them via IPAddress.
    /// Then serialize the same addresss via `ntoa`, and ensure it returns the same string.
    /// Then parse our serialized version back via `aton`, and ensure it returns the same address.
    /// Then parse our serialized version again, and ensure that it returns the same address.
    ///
    func testRandom_Serialisation() {
      for _ in 0..<1000 {
        let expected = IPv4Address.Utils.randomAddress()
        let address = IPv4Address(value: expected, .numeric)

        // Serialize the same address with libc (note: ntoa expects network byte order). It should return the same String.
        XCTAssertEqual(libc_ntoa(expected.bigEndian), address.serialized)

        // Parse our serialized output with libc. It should return the same address.
        let libcAddress = libc_aton(address.serialized)
        XCTAssertEqual(
          libcAddress?.octets, Array(ipv4Octets: address.octets), "Mismatch detected for address \(address)")
        XCTAssertEqual(libcAddress, address[value: .binary], "Mismatch detected for address \(address)")

        // Re-parse our serialized output. It should return the same address.
        if let reparsed = IPv4Address(address.serialized) {
          XCTAssertEqual(Array(ipv4Octets: address.octets), Array(ipv4Octets: reparsed.octets))
        } else {
          XCTFail("Address is not idempotent: \(address.serialized)")
        }
      }
    }

    /// Generate 1000 random IP Address Strings, parse them via IPAddress,
    /// check that the numerical value matches the expected network address,
    /// and that `aton` gets the same result when parsing the same random String.
    ///
    func testRandom_Parsing() {
      for _ in 0..<1000 {
        let randomNumericAddress = IPv4Address.Utils.randomAddress()
        let randomAddressString = IPv4Address.Utils.randomString(address: randomNumericAddress)

        guard let parsed = IPv4Address(randomAddressString) else {
          XCTFail("Failed to parse address: \(randomAddressString); expected address: \(randomNumericAddress)")
          continue
        }
        XCTAssertEqual(Array(ipv4Octets: parsed.octets), libc_aton(randomAddressString)?.octets)
        XCTAssertEqual(parsed[value: .numeric], randomNumericAddress)
        XCTAssertEqual(parsed[value: .binary], libc_aton(randomAddressString))
      }
    }
  }

#endif
