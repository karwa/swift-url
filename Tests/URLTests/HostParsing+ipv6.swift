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
        let testData: [(String, [UInt16], String)] = [
            // Canonical
            ("2001:0db8:85a3:0000:0000:8a2e:0370:7334", [8193, 3512, 34211, 0, 0, 35374, 880, 29492], "2001:db8:85a3::8a2e:370:7334"),        
            // Teredo
            ("2001::ce49:7601:e866:efff:62c3:fffe",     [8193, 0, 52809, 30209, 59494, 61439, 25283, 65534], "2001:0:ce49:7601:e866:efff:62c3:fffe"),
            // Compact
            ("2608::3:5", [9736, 0, 0, 0, 0, 0, 3, 5], "2608::3:5"), 
            // Empty
            ("::", [0, 0, 0, 0, 0, 0, 0, 0], "::"), 
            // IPv4
            ("::ffff:192.168.0.1", [0, 0, 0, 0, 0, 65535, 49320, 1], "::ffff:c0a8:1"), 
        ]

        for (string, expectedRawAddress, expectedDescription) in testData {
            guard let addr = IPAddress.V6(string) else {
                XCTFail("Failed to parse valid address: \(string)")
                continue
            }
            XCTAssertEqual(Array(fromIPv6Address: addr.rawAddress),     expectedRawAddress, "Raw address mismatch for: \(string)")
            XCTAssertEqual(Array(fromIPv6Address: addr.networkAddress), parse_pton(string), "Net address mismatch for: \(string)")
            XCTAssertEqual(addr.description, expectedDescription)
            if let reparsedAddr = IPAddress.V6(addr.description) {
                XCTAssertEqual(addr, reparsedAddr, "Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.description)'")
            } else {
                XCTFail("Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.description)'")
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
            guard let addr = IPAddress.V6(string) else {
                XCTFail("Failed to parse valid address: \(string)")
                continue
            }
            XCTAssertEqual(Array(fromIPv6Address: addr.rawAddress),     expectedRawAddress, "Raw address mismatch for: \(string)")
            XCTAssertEqual(Array(fromIPv6Address: addr.networkAddress), parse_pton(string), "Net address mismatch for: \(string)")
            XCTAssertEqual(addr.description, expectedDescription)
            if let reparsedAddr = IPAddress.V6(addr.description) {
                XCTAssertEqual(addr, reparsedAddr, "Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.description)'")
            } else {
                XCTFail("Address failed to round-trip. Original: '\(string)'. Printed: '\(addr.description)'")
            }
        }
    }

    func testInvalid() {
        let invalidAddresses: [(String, IPAddress.V6.ParseResult.Error)] = [
            // - Invalid piece.
            ("12345::", .unexpectedCharacter),
            ("FG::",    .unexpectedCharacter),
            
            // - Invalid compression.
            (":",   .unexpectedLeadingColon),
            (":::", .multipleCompressedPieces),
            ("F:",  .unexpectedTrailingColon),
            ("42:", .unexpectedTrailingColon),
            
            // - Invalid IPv4 piece.
            ("::ffff:555.168.0.1",    .invalidIPv4Address(.pieceOverflows)),
            ("::ffff:192.168.0.1.8",  .invalidIPv4Address(.tooManyPieces)),
            // TODO: Is it worth having a separate "piece begins with invalid character" error?
            ("::ffff:192.168.a.1",    .invalidIPv4Address(.pieceBeginsWithInvalidCharacter)),
            // TODO: Improve this. "unexpectedPeriod" should be more IPv4-related.
            ("::ffff:.168.0.1",       .unexpectedPeriod),
            ("::ffff:192.168.0.01",   .invalidIPv4Address(.unsupportedRadix)),
            ("::ffff:192.168.0xf.1",  .invalidIPv4Address(.invalidCharacter)), // `unsupportedRadix` would be better, but isn't worth special-casing the 'x' character IMO.
            // TODO: (Maybe) Improve this.
            ("::ffff:192.168.0.1.",   .invalidIPv4Address(.tooManyPieces)), // trailing dot
            // TODO: Improve this. Should be: "invalidPositionForIPv4Address"
            ("0001:0002:0003:0004:192.168.0.1:0006:0007:0008", .invalidIPv4Address(.invalidCharacter)),
            
            // - Invalid number of pieces.
            ("0001:0002:0003:0004:0005", .notEnoughPieces),
            ("0001:0002:0003:0004:0005:0006:0007:0008:0009", .tooManyPieces),
        ]

        for (string, expectedError) in invalidAddresses {
            let result = IPAddress.V6.parse(string)
            switch result {
            case .success(let addr):
                XCTFail("Invalid address '\(string)' was parsed as '\(addr.rawAddress)' (raw)")
            case .validationFailure(let error):
                XCTAssertEqual(error, expectedError, "Unexpected error for invalid address '\(string)'")
            }
            if let cAddr = parse_pton(string) {
                XCTFail("pton parsed invalid address '\(string)' as '\(cAddr)'. This behaviour difference should be investigated.")
            }
        }
    }
}