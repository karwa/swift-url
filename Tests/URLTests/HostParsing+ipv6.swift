import XCTest
@testable import URL

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#else
#error("Unknown libc variant")
#endif

extension Array where Element == UInt16 {
    init(fromIPv6Address addr: IPAddress.V6.AddressType) {
        self = [addr.0, addr.1, addr.2, addr.3, addr.4, addr.5, addr.6, addr.7]
    }
}

final class HostParsing_IPv6: XCTestCase {

    fileprivate func parse_pton(_ input: String) -> [UInt16]? {
        var result = in6_addr()
        guard inet_pton(AF_INET6, input, &result) != 0 else { return nil }
        return withUnsafeBytes(of: &result) { ptr in
            let u16 = ptr.bindMemory(to: UInt16.self)
            return Array(u16) 
        }
    }

    func testBasic() {
        let testData: [(String, [UInt16])] = [
            ("2001:0db8:85a3:0000:0000:8a2e:0370:7334", [8193, 3512, 34211, 0, 0, 35374, 880, 29492]),        // Canonical
            ("2001::ce49:7601:e866:efff:62c3:fffe",     [8193, 0, 52809, 30209, 59494, 61439, 25283, 65534]), // Teredo
            ("2608::3:5", [9736, 0, 0, 0, 0, 0, 3, 5]), // Compact
            ("::", [0, 0, 0, 0, 0, 0, 0, 0]), // Empty
            ("::ffff:192.168.0.1", [0, 0, 0, 0, 0, 65535, 49320, 1]), // IPv4
        ]

        for (string, expectedRawAddress) in testData {
            guard let addr = IPAddress.V6(string) else {
                XCTFail("Failed to parse valid address: \(string)")
                continue
            }
            XCTAssertEqual(Array(fromIPv6Address: addr.rawAddress),     expectedRawAddress, "Raw address mismatch for: \(string)")
            XCTAssertEqual(Array(fromIPv6Address: addr.networkAddress), parse_pton(string), "Net address mismatch for: \(string)")
        }
    }

    func testInvalid() {
        let invalidAddresses = [
            // Invalid piece.
            "12345::",
            "FG::",
            // Invalid compression.
            ":",
            ":::",
            "F:",
            "42:",
            // Invalid IPv4 piece.
            "::ffff:555.168.0.1",
            "::ffff:192.168.0.1.8",
            "::ffff:192.168.a.1",
            "::ffff:.168.0.1",
            "::ffff:192.168.0.01",
            "0001:0002:0003:0004:192.168.0.1:0006:0007:0008",
            // Invalid number of pieces.
            "0001:0002:0003:0004:0005",
            "0001:0002:0003:0004:0005:0006:0007:0008:0009",
        ]

        for string in invalidAddresses {
            if let addr = IPAddress.V6(string) {
                XCTFail("Invalid address '\(string)' was parsed as '\(addr.rawAddress)' (raw)")
            }
            if let cAddr = parse_pton(string) {
                XCTFail("pton parsed invalid address '\(string)' as '\(cAddr)'. This behaviour difference should be investigated.")
            }
        }
    }
}