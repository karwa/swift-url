import XCTest
@testable import URL

import Glibc

func libc_parse(_ straddr: String) -> UInt32? {
    var addr = in_addr()
    guard inet_aton(straddr, &addr) != 0 else { return nil }
    return addr.s_addr
}

final class HostParsing_IPv4: XCTestCase {

    func testBasic() {
        // 192.255.2.5 
        //  = (192 * 256^3) + (255 * 256^2) + (2 * 256) + (5 * 1)
        //  = 3221225472 + 16711680 + 512 + 5 
        //  = 3237937669
        let expectedRawAddress = (3237937669 as UInt32).bigEndian

        let strings = [
            "3237937669",     // 1 component, decimal. 
            "0xC0.077601005", // 2 components, hex/octal.
            "192.0xff.01005", // 3 components, decimal/hex/octal.
            "192.255.2.5"     // 4 components, decimal.
        ]
        for string in strings {
            guard let addr = IPAddress.V4(string[...]) else {
                XCTFail("Failed to parse valid address: \(string)")
                continue
            }
            // Check that libc gets the same result.
            XCTAssertEqual(addr.rawAddress, libc_parse(string), "Mismatch detected for address: \(string)")
            // Check that the result is the expected value.
            XCTAssertEqual(addr.rawAddress, expectedRawAddress, "Unexpected result for address: \(string)")
        }
    }

    func testTrailingDots() {
        let expectedRawAddress = (2071690107 as UInt32).bigEndian

        // Zero trailing dots are allowed (obviously).
        if let addr = IPAddress.V4("123.123.123.123") {
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
        } else {
            XCTFail("Failed to parse valid address")
        }
        // One trailing dot is allowed.
        if let addr = IPAddress.V4("123.123.123.123.") {
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
        } else {
            XCTFail("Failed to parse valid address")
        }
        // Two or more trailing dots are not allowed.
        if let _ = IPAddress.V4("123.123.123.123..")   { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("123.123.123.123...")  { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("123.123.123.123....") { XCTFail("Expected fail") }
        // More than 4 components are not allowed.
        if let _ = IPAddress.V4("123.123.123.123.123")   { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("123.123.123.123.123.")  { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("123.123.123.123.123..") { XCTFail("Expected fail") }
    }

    func testTrailingZeroes() {
        if let addr = IPAddress.V4("234") {
            XCTAssertEqual(addr.rawAddress, libc_parse("234"))
            XCTAssertEqual(addr.rawAddress, (234 as UInt32).bigEndian)
        } else {
            XCTFail("Failed to parse valid address")
        }
        
        if let addr = IPAddress.V4("234.0") {
            XCTAssertEqual(addr.rawAddress, libc_parse("234.0"))
            XCTAssertEqual(addr.rawAddress, (3925868544 as UInt32).bigEndian)
        } else { 
            XCTFail("Failed to parse valid address")
        }
        
        // First, test that we parse the correct value with no trailing zeroes.
        // "234.011" = "234.0.0.9" (the 9 occupies the lowest byte) = 150995178 (big-endian).
        let noTrailingZeroes = [
            "234.011",
            "234.011."
        ]
        for string in noTrailingZeroes {
            guard let addr = IPAddress.V4(string[...]) else { 
                XCTFail("Failed to parse valid address")
                continue
            }
            let expectedRawAddress = (3925868553 as UInt32).bigEndian // 150995178
            // inet_aton doesn't accept trailing dots, but the WHATWG URL spec does.
            let libcString: String
            if string.hasSuffix(".") {
                libcString = String(string.dropLast())
            } else {
                libcString = string
            }
            XCTAssertEqual(libc_parse(libcString), addr.rawAddress)
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
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
            guard let addr = IPAddress.V4(string[...]) else { 
                XCTFail("Failed to parse valid address")
                continue
            }
            let expectedRawAddress = (3926458368 as UInt32).bigEndian // 2538
            // inet_aton doesn't accept trailing dots, but the WHATWG URL spec does.
            let libcString: String
            if string.hasSuffix(".") {
                libcString = String(string.dropLast())
            } else {
                libcString = string
            }
            XCTAssertEqual(libc_parse(libcString), addr.rawAddress)
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
        }

        // Lastly, test that we reject an invalid number of trailing zeroes. 
        let invalid_trailingZeroes = [
            "234.011.0.0.0",
            "234.011.0.0.0.",
            "234.011.0.0.0.0",
            "234.011.0.0.0.0.",
        ]
        for string in invalid_trailingZeroes {
            XCTAssertNil(IPAddress.V4(string[...]), "Invalid address should have been rejected: \(string)")
            // Sanity check.
            XCTAssertNil(libc_parse(string), "libc unexpectedly considers this address valid: \(string)")
        }
    }

    func testInvalid() {    
        if let _ = IPAddress.V4("0.0x300") {} else { XCTFail("Failed to parse valid address") }
        if let _ = IPAddress.V4("0..0x300")        { XCTFail("Expected fail") }

        // Non-numbers.
        if let _ = IPAddress.V4("sup?")      { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("100sup?")   { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("100.sup?")  { XCTFail("Expected fail") }

        // Overflow.
        if let _ = IPAddress.V4("0xFFFFFFFF") {} else { XCTFail("Failed to parse valid address") }
        if let _ = IPAddress.V4("0xFFFFFFFF1")        { XCTFail("Expected to fail") }
        if let _ = IPAddress.V4("1.0xFFFFFFF")        { XCTFail("Expected to fail") }
        if let _ = IPAddress.V4("1.1.0xFFFFF")        { XCTFail("Expected to fail") }
        if let _ = IPAddress.V4("1.1.1.0xFFF")        { XCTFail("Expected to fail") }

        // Invalid base-X characters.
        if let _ = IPAddress.V4("192.0xF") {} else { XCTFail("Failed to parse valid address") }
        if let _ = IPAddress.V4("192.F")           { XCTFail("Expected fail") }
        if let _ = IPAddress.V4("192.0F")          { XCTFail("Expected fail") }
    }
}

