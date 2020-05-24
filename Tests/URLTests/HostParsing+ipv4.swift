import XCTest
@testable import URL

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#else
#error("Unknown libc variant")
#endif

final class HostParsing_IPv4: XCTestCase {

    fileprivate func parse_aton(_ straddr: String) -> UInt32? {
        var addr = in_addr()
        guard inet_aton(straddr, &addr) != 0 else { return nil }
        return addr.s_addr
    }

    func testBasic() {
        // 192.255.2.5 
        //  = (192 * 256^3) + (255 * 256^2) + (2 * 256) + (5 * 1)
        //  = 3221225472 + 16711680 + 512 + 5 
        //  = 3237937669
        let expectedRawAddress: UInt32 = 3237937669

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
            // Check that the result is the expected value.
            XCTAssertEqual(addr.rawAddress, expectedRawAddress, "Unexpected result for address: \(string)")
            // Check that libc gets the same result.
            XCTAssertEqual(addr.networkAddress, parse_aton(string), "Mismatch detected for address: \(string)")
            // Check the serialised value.
            XCTAssertEqual(addr.description, "192.255.2.5")
        }
    }

    func testTrailingDots() {
        let expectedRawAddress: UInt32 = 2071690107

        // Zero trailing dots are allowed (obviously).
        if let addr = IPAddress.V4("123.123.123.123") {
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
            XCTAssertEqual(addr.networkAddress, parse_aton("123.123.123.123"))
            XCTAssertEqual(addr.description, "123.123.123.123")
        } else {
            XCTFail("Failed to parse valid address")
        }
        // One trailing dot is allowed.
        if let addr = IPAddress.V4("123.123.123.123.") {
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
            XCTAssertEqual(addr.description, "123.123.123.123")
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
            XCTAssertEqual(addr.networkAddress, parse_aton("234"))
            XCTAssertEqual(addr.rawAddress, 234)
            XCTAssertEqual(addr.description, "0.0.0.234")
        } else {
            XCTFail("Failed to parse valid address")
        }
        
        if let addr = IPAddress.V4("234.0") {
            XCTAssertEqual(addr.networkAddress, parse_aton("234.0"))
            XCTAssertEqual(addr.rawAddress, 3925868544)
            XCTAssertEqual(addr.description, "234.0.0.0")
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
            let expectedRawAddress: UInt32 = 3925868553
            // inet_aton doesn't accept trailing dots, but the WHATWG URL spec does.
            let libcString: String
            if string.hasSuffix(".") {
                libcString = String(string.dropLast())
            } else {
                libcString = string
            }
            XCTAssertEqual(addr.networkAddress, parse_aton(libcString))
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
            XCTAssertEqual(addr.description, "234.0.0.9")
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
            let expectedRawAddress: UInt32 = 3926458368
            // inet_aton doesn't accept trailing dots, but the WHATWG URL spec does.
            let libcString: String
            if string.hasSuffix(".") {
                libcString = String(string.dropLast())
            } else {
                libcString = string
            }
            XCTAssertEqual(addr.networkAddress, parse_aton(libcString))
            XCTAssertEqual(addr.rawAddress, expectedRawAddress)
            XCTAssertEqual(addr.description, "234.9.0.0")
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
            XCTAssertNil(parse_aton(string), "libc unexpectedly considers this address valid: \(string)")
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

    func testSerialisation() {
        if let addr = IPAddress.V4("250.0.102.02") {
            XCTAssertEqual(addr.description, "250.0.102.2")
        } else {
            XCTFail("Failed to parse valid address")
        }
    }

    // TODO: Move this to an ASCII tests file.
    func testASCIIDecimalPrinting() {
        var buf: [UInt8] = [0, 0, 0, 0]
        buf.withUnsafeMutableBufferPointer { buffer in 
            for num in (UInt8.min)...(UInt8.max) {
                let bufferContentsEnd = ASCII.insertDecimalString(for: num, into: buffer)
                let asciiContents = Array(buffer[..<bufferContentsEnd])
                let stdlibString  = Array(String(num, radix: 10).utf8)
                XCTAssertEqual(stdlibString, asciiContents)
            }
        }
    }
}

