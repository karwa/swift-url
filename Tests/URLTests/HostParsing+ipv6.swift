import XCTest
@testable import URL

final class HostParsing_IPv6: XCTestCase {

     func testCanonical() {
        guard let host = XURL.Host("[2001:0db8:85a3:0000:0000:8a2e:0370:7334]") else {
            XCTFail("Failed to parse")
            return
        }
        guard case .ipv6Address(let addr) = host else {
            XCTFail("Unexpected host - found \(host)")
            return
        }
        XCTAssertNotEqual(addr, IPAddress.V6())
        XCTAssertEqual(addr, IPAddress.V6(8193, 3512, 34211, 0, 0, 35374, 880, 29492))
     }

     func testTeredo() {
        guard let host = XURL.Host("[2001::ce49:7601:e866:efff:62c3:fffe]") else {
            XCTFail("Failed to parse")
            return
        }
        guard case .ipv6Address(let addr) = host else {
            XCTFail("Unexpected host - found \(host)")
            return
        }
        XCTAssertEqual(addr, IPAddress.V6(8193, 0, 52809, 30209, 59494, 61439, 25283, 65534))
    }

    func testCompact() {
        guard let host = XURL.Host("[2608::3:5]") else {
            XCTFail("Failed to parse")
            return
        }
        guard case .ipv6Address(let addr) = host else {
            XCTFail("Unexpected host - found \(host)")
            return
        }
        XCTAssertEqual(addr, IPAddress.V6(9736, 0, 0, 0, 0, 0, 3, 5))
    }

    func testIpv4() {
        guard let host = XURL.Host("[::ffff:192.168.0.1]") else {
            XCTFail("Failed to parse")
            return
        }
        guard case .ipv6Address(let addr) = host else {
            XCTFail("Unexpected host - found \(host)")
            return
        }
        XCTAssertEqual(addr, IPAddress.V6(0, 0, 0, 0, 0, 65535, 49320, 1))
    }

    func testEmptyCompressed() {
        guard let host = XURL.Host("[::]") else {
            XCTFail("Failed to parse")
            return
        }
        guard case .ipv6Address(let addr) = host else {
            XCTFail("Unexpected host - found \(host)")
            return
        }
        XCTAssertEqual(addr, IPAddress.V6())
        XCTAssertEqual(addr, IPAddress.V6(0, 0, 0, 0, 0, 0, 0, 0))
    }

    func testInvalid() {
        // Invalid segment.
        if let _ = XURL.Host("[12345::]") { XCTFail("Should have failed") }
        if let _ = XURL.Host("[FG::]")    { XCTFail("Should have failed") }
        // Invalid compression.
        if let _ = XURL.Host("[:]")       { XCTFail("Should have failed") }
        if let _ = XURL.Host("[:::]")     { XCTFail("Should have failed") }
        if let _ = XURL.Host("[F:]")      { XCTFail("Should have failed") }
        if let _ = XURL.Host("[42:]")     { XCTFail("Should have failed") }
        // Invalid IPv4 segment.
        if let _ = XURL.Host("[::ffff:555.168.0.1]")   { XCTFail("Should have failed") }
        if let _ = XURL.Host("[::ffff:192.168.0.1.8]") { XCTFail("Should have failed") }
        if let _ = XURL.Host("[::ffff:192.168.a.1]")   { XCTFail("Should have failed") }
        if let _ = XURL.Host("[::ffff:.168.0.1]")      { XCTFail("Should have failed") }
        if let _ = XURL.Host("[::ffff:192.168.0.01]")  { XCTFail("Should have failed") }
        if let _ = XURL.Host("[0001:0002:0003:0004:192.168.0.1:0006:0007:0008]") { XCTFail("Should have failed") }
        // Invalid number of segments.
        if let _ = XURL.Host("[0001:0002:0003:0004:0005]") { XCTFail("Should have failed") }
        if let _ = XURL.Host("[0001:0002:0003:0004:0005:0006:0007:0008:0009]") { XCTFail("Should have failed") }
    }
}