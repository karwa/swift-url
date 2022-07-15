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

final class HostTests: XCTestCase {}


// --------------------------------------------
// MARK: - Protocol conformances
// --------------------------------------------


extension HostTests {

  func testCustomStringConvertible() {

    let ipv4Addr = IPv4Address(octets: (192, 168, 0, 1))
    let ipv4Host = WebURL.Host.ipv4Address(ipv4Addr)
    XCTAssertEqual(ipv4Host.description, "192.168.0.1")
    XCTAssertEqual(ipv4Host.description, ipv4Host.serialized)

    // IPv6 description includes square brackets, so it can be re-parsed as a hostname
    // (although the brackets will need removing for `IPv6Address.init`).

    let ipv6Addr = IPv6Address(pieces: (0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334), .numeric)
    let ipv6Host = WebURL.Host.ipv6Address(ipv6Addr)
    XCTAssertEqual(ipv6Host.description, "[2001:db8:85a3::8a2e:370:7334]")
    XCTAssertEqual(ipv6Host.description, ipv6Host.serialized)

    let asciiDomain = WebURL.Domain("example.com")!
    let asciiHost = WebURL.Host.domain(asciiDomain)
    XCTAssertEqual(asciiHost.description, "example.com")
    XCTAssertEqual(asciiHost.description, asciiHost.serialized)

    let idnDomain = WebURL.Domain("a.xn--igbi0gl.com")!
    let idnHost = WebURL.Host.domain(idnDomain)
    XCTAssertEqual(idnHost.description, "a.xn--igbi0gl.com")
    XCTAssertEqual(idnHost.description, idnHost.serialized)

    let idnDomain2 = WebURL.Domain("a.أهلا.com")!
    let idnHost2 = WebURL.Host.domain(idnDomain2)
    XCTAssertEqual(idnHost2.description, "a.xn--igbi0gl.com")
    XCTAssertEqual(idnHost2.description, idnHost2.serialized)

    let empty = WebURL.Host.empty
    XCTAssertEqual(empty.description, "")
    XCTAssertEqual(empty.description, empty.serialized)

    // These are just strings; we can't prevent users creating them from invalid values.
    // We just return the string they gave us.
    let opaque = WebURL.Host.opaque("some string")
    XCTAssertEqual(opaque.description, "some string")
    XCTAssertEqual(opaque.description, opaque.serialized)
  }

  func testCodable() throws {

    guard #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) else {
      throw XCTSkip("JSONEncoder.OutputFormatting.withoutEscapingSlashes requires tvOS 13 or newer")
    }

    func roundTripJSON<Value: Codable & Equatable>(
      _ original: Value, expectedJSON: String, expectedDecoded: Value? = nil
    ) throws {
      // Encode to JSON, check that we get the expected string.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
      let jsonString = String(decoding: try encoder.encode(original), as: UTF8.self)
      XCTAssertEqual(jsonString, expectedJSON)
      // Decode the JSON output, check we get the expected result.
      let decodedValue = try JSONDecoder().decode(Value.self, from: Data(jsonString.utf8))
      XCTAssertEqual(decodedValue, expectedDecoded ?? original)
    }

    func fromJSON(_ json: String) throws -> WebURL.Host {
      try JSONDecoder().decode(WebURL.Host.self, from: Data(json.utf8))
    }

    ipv4: do {
      // Host values can round-trip through JSON.
      let address = IPv4Address(octets: (192, 168, 0, 1))
      try roundTripJSON(
        WebURL.Host.ipv4Address(address),
        expectedJSON:
          #"""
          {
            "hostname" : "192.168.0.1",
            "kind" : "ipv4"
          }
          """#
      )
      // When decoding, invalid values are rejected.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "not-an-address",
            "kind" : "ipv4"
          }
          """#
        )
      )
      // When decoding, we use the full host parser, which handles things like IDNA domains which map to IPv4 addresses.
      let exoticIpv4_1 = try fromJSON(
        #"""
        {
          "hostname" : "0x7F.1",
          "kind" : "ipv4"
        }
        """#
      )
      XCTAssertEqual(exoticIpv4_1, .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))))
      let exoticIpv4_2 = try fromJSON(
        #"""
        {
          "hostname" : "0x𝟕f.1",
          "kind" : "ipv4"
        }
        """#
      )
      XCTAssertEqual(exoticIpv4_2, .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))))
    }

    ipv6: do {
      // Host values can round-trip through JSON.
      let address = IPv6Address(pieces: (0x2001, 0x0db8, 0x85a3, 0x0000, 0x0000, 0x8a2e, 0x0370, 0x7334), .numeric)
      try roundTripJSON(
        WebURL.Host.ipv6Address(address),
        expectedJSON:
          #"""
          {
            "hostname" : "[2001:db8:85a3::8a2e:370:7334]",
            "kind" : "ipv6"
          }
          """#
      )
      // When decoding, invalid values are rejected.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "not-an-address",
            "kind" : "ipv6"
          }
          """#
        )
      )
      // When decoding, addresses are parsed by the regular IPv6 parser,
      // which supports uncompressed pieces and mixed-case hex characters.
      let decoded = try fromJSON(
        #"""
        {
          "hostname" : "[2001:0DB8:85A3:0:0:8a2E:0370:7334]",
          "kind" : "ipv6"
        }
        """#
      )
      XCTAssertEqual(decoded, .ipv6Address(address))
      // When decoding, the hostname must be enclosed in square brackets.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "2001:db8:85a3::8a2e:370:7334",
            "kind" : "ipv6"
          }
          """#
        )
      )
    }

    domain: do {
      // Normalized values round-trip exactly, including IDNA.
      try roundTripJSON(
        WebURL.Host.domain(WebURL.Domain("example.com")!),
        expectedJSON:
          #"""
          {
            "hostname" : "example.com",
            "kind" : "domain"
          }
          """#
      )
      try roundTripJSON(
        WebURL.Host.domain(WebURL.Domain("a.xn--igbi0gl.com")!),
        expectedJSON:
          #"""
          {
            "hostname" : "a.xn--igbi0gl.com",
            "kind" : "domain"
          }
          """#
      )
      // When decoding, invalid domains are rejected.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "hello world",
            "kind" : "domain"
          }
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "[::123]",
            "kind" : "domain"
          }
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "127.0.0.1",
            "kind" : "domain"
          }
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "xn--cafe-dma.fr",
            "kind" : "domain"
          }
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "xn--caf-yvc.fr",
            "kind" : "domain"
          }
          """#
        )
      )
      // When decoding, values are normalized as domains.
      XCTAssertEqual(
        try fromJSON(
          #"""
          {
            "hostname" : "EX%61MPLE.com",
            "kind" : "domain"
          }
          """#
        ),
        .domain(WebURL.Domain("example.com")!)
      )
      XCTAssertEqual(
        try fromJSON(
          #"""
          {
            "hostname" : "a.أهلا.com",
            "kind" : "domain"
          }
          """#
        ),
        .domain(WebURL.Domain("a.xn--igbi0gl.com")!)
      )
    }

    opaque: do {
      // Because ".opaque" is just a string and "Host" is just an enum, users can construct invalid values.

      // Valid values round-trip exactly. All non-empty names with no 'kind' are considered opaque.
      try roundTripJSON(
        WebURL.Host.opaque("EX%61MPLE.com"),
        expectedJSON:
          #"""
          {
            "hostname" : "EX%61MPLE.com"
          }
          """#
      )
      try roundTripJSON(
        WebURL.Host.opaque("abc.%D8%A3%D9%87%D9%84%D8%A7.com"),
        expectedJSON:
          #"""
          {
            "hostname" : "abc.%D8%A3%D9%87%D9%84%D8%A7.com"
          }
          """#
      )
      try roundTripJSON(
        WebURL.Host.opaque("xn--cafe-dma.com"),
        expectedJSON:
          #"""
          {
            "hostname" : "xn--cafe-dma.com"
          }
          """#
      )
      try roundTripJSON(
        WebURL.Host.opaque("xn--caf-yvc.com"),
        expectedJSON:
          #"""
          {
            "hostname" : "xn--caf-yvc.com"
          }
          """#
      )
      try roundTripJSON(
        WebURL.Host.opaque("127.0.0.1"),
        expectedJSON:
          #"""
          {
            "hostname" : "127.0.0.1"
          }
          """#
      )
      // When decoding, invalid hostnames are rejected.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "EX%61 MPLE.com"
          }
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "[::123]"
          }
          """#
        )
      )
      // When decoding, values are normalized as opaque hostnames.
      try roundTripJSON(
        WebURL.Host.opaque("a.أهلا.com"),
        expectedJSON:
          #"""
          {
            "hostname" : "a.أهلا.com"
          }
          """#,
        expectedDecoded: .opaque("a.%D8%A3%D9%87%D9%84%D8%A7.com")
      )
    }

    empty: do {
      // Empty hosts can round-trip through JSON. They do not have a 'kind'.
      try roundTripJSON(
        WebURL.Host.empty,
        expectedJSON:
          #"""
          {
            "hostname" : ""
          }
          """#
      )
      // When decoding, all empty hostnames become '.empty', regardless of the 'kind'.
      var wrongKind = try fromJSON(
        #"""
        {
          "hostname" : "",
          "kind" : "ipv4"
        }
        """#
      )
      XCTAssertEqual(wrongKind, .empty)
      wrongKind = try fromJSON(
        #"""
        {
          "hostname" : "",
          "kind" : "ipv6"
        }
        """#
      )
      XCTAssertEqual(wrongKind, .empty)
      wrongKind = try fromJSON(
        #"""
        {
          "hostname" : "",
          "kind" : "domain"
        }
        """#
      )
      XCTAssertEqual(wrongKind, .empty)
      wrongKind = try fromJSON(
        #"""
        {
          "hostname" : "",
          "kind" : "xxx"
        }
        """#
      )
      XCTAssertEqual(wrongKind, .empty)
    }

    invalidKind: do {
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          {
            "hostname" : "somehost",
            "kind" : "xxx"
          }
          """#
        )
      )
    }
  }
}

#if swift(>=5.5) && canImport(_Concurrency)

  extension HostTests {

    func testSendable() {
      // Since Sendable only exists at compile-time, it's enough to just ensure that this type-checks.
      func _requiresSendable<T: Sendable>(_: T) {}

      let host = WebURL.Host("example.com", scheme: "http")!
      _requiresSendable(host)
    }
  }

#endif


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension HostTests {

  func testParsing() {

    // In special URL contexts, all non-IP hostnames are domains.
    test: do {
      let host = WebURL.Host("example.com", scheme: "http")
      guard case .domain(let domain) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain.serialized, "example.com")
      XCTAssertFalse(domain.isIDN)
    }
    test: do {
      let host = WebURL.Host("nodots", scheme: "http")
      guard case .domain(let domain) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain.serialized, "nodots")
      XCTAssertFalse(domain.isIDN)
    }

    // In special URL contexts, Unicode hostnames are validated and normalized using IDNA.
    test: do {
      var host = WebURL.Host("💩.com", scheme: "http")
      guard case .domain(let domain) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain.serialized, "xn--ls8h.com")
      XCTAssertTrue(domain.isIDN)

      host = WebURL.Host("www.foo。bar.com", scheme: "http")
      guard case .domain(let domain2) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain2.serialized, "www.foo.bar.com")
      XCTAssertFalse(domain2.isIDN)

      host = WebURL.Host("xn--caf-dma.com", scheme: "http")
      guard case .domain(let domain3) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain3.serialized, "xn--caf-dma.com")
      XCTAssertTrue(domain3.isIDN)

      host = WebURL.Host("xn--cafe-dma.com", scheme: "http")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("xn--cafe-yvc.com", scheme: "http")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("has a space.com", scheme: "http")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // Special URL contexts detect IPv4 addresses, including after IDNA.
    test: do {
      var host = WebURL.Host("11.173.240.13", scheme: "http")
      guard case .ipv4Address(IPv4Address(octets: (11, 173, 240, 13))) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("0xbadf00d", scheme: "http")
      guard case .ipv4Address(IPv4Address(octets: (11, 173, 240, 13))) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("0x𝟕f.1", scheme: "http")
      guard case .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("11.173.240.13.4", scheme: "http")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // In non-special URL contexts, all non-IP hostnames are opaque strings.
    test: do {
      let host = WebURL.Host("example.com", scheme: "non-special")
      guard case .opaque("example.com") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // In non-special URL contexts, Unicode hostnames are percent-encoded.
    // Other invalid characters are rejected.
    test: do {
      var host = WebURL.Host("💩.com", scheme: "foo")
      guard case .opaque("%F0%9F%92%A9.com") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("www.foo。bar.com", scheme: "foo")
      guard case .opaque("www.foo%E3%80%82bar.com") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("xn--caf-dma.com", scheme: "foo")
      guard case .opaque("xn--caf-dma.com") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("xn--cafe-dma.com", scheme: "foo")
      guard case .opaque("xn--cafe-dma.com") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("xn--cafe-yvc.com", scheme: "foo")
      guard case .opaque("xn--cafe-yvc.com") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("has a space.com", scheme: "foo")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // Non-special URL contexts do not detect IPv4 addresses.
    test: do {
      var host = WebURL.Host("11.173.240.13", scheme: "foo")
      guard case .opaque("11.173.240.13") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("0xbadf00d", scheme: "foo")
      guard case .opaque("0xbadf00d") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("0x𝟕f.1", scheme: "foo")
      guard case .opaque("0x%F0%9D%9F%95f.1") = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // Both special and non-special URL contexts detect IPv6 addresses.
    test: do {
      var host = WebURL.Host("[::127.0.0.1]", scheme: "http")
      guard case .ipv6Address(IPv6Address(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("[::127.0.0.1]", scheme: "foo")
      guard case .ipv6Address(IPv6Address(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("[blahblahblah]", scheme: "http")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("[blahblahblah]", scheme: "foo")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // Special URL contexts interpret domains and IPv4 addresses through percent-encoding.
    test: do {
      var host = WebURL.Host("www.foo%E3%80%82bar.com", scheme: "http")
      guard case .domain(let domain) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain.serialized, "www.foo.bar.com")
      XCTAssertFalse(domain.isIDN)

      host = WebURL.Host("%F0%9F%92%A9.com", scheme: "http")
      guard case .domain(let domain2) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
      XCTAssertEqual(domain2.serialized, "xn--ls8h.com")
      XCTAssertTrue(domain2.isIDN)

      host = WebURL.Host("0x%F0%9D%9F%95f.1", scheme: "http")
      guard case .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))) = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // Only File and non-special URLs may have empty hostnames.
    test: do {
      var host = WebURL.Host("", scheme: "http")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("", scheme: "ftp")
      guard case .none = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("", scheme: "file")
      guard case .empty = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }

      host = WebURL.Host("", scheme: "foo")
      guard case .empty = host else {
        XCTFail("Unexpected host: \(String(describing: host))")
        break test
      }
    }

    // Hosts which get IDNA-mapped to the empty string. Not allowed even in file URLs.
    do {
      XCTAssertEqual(WebURL.Host("\u{AD}", scheme: "foo"), .opaque("%C2%AD"))
      XCTAssertNil(WebURL.Host("\u{AD}", scheme: "file"))
      XCTAssertNil(WebURL.Host("\u{AD}", scheme: "http"))
    }

    // Localhost is normalized to empty in file URLs, to lowercase in other special URLs,
    // and not at all in non-special URLs.
    do {
      XCTAssertEqual(WebURL.Host("localhost", scheme: "file"), .empty)
      XCTAssertEqual(WebURL.Host("loCAlhost", scheme: "file"), .empty)
      XCTAssertEqual(WebURL.Host("loc%61lhost", scheme: "file"), .empty)
      XCTAssertEqual(WebURL.Host("loC𝐀𝐋𝐇𝐨𝐬𝐭", scheme: "file"), .empty)

      XCTAssertEqual(WebURL.Host("localhost", scheme: "http")?.serialized, "localhost")
      XCTAssertEqual(WebURL.Host("loCAlhost", scheme: "http")?.serialized, "localhost")
      XCTAssertEqual(WebURL.Host("loc%61lhost", scheme: "http")?.serialized, "localhost")
      XCTAssertEqual(WebURL.Host("loC𝐀𝐋𝐇𝐨𝐬𝐭", scheme: "http")?.serialized, "localhost")

      XCTAssertEqual(WebURL.Host("localhost", scheme: "foo"), .opaque("localhost"))
      XCTAssertEqual(WebURL.Host("loCAlhost", scheme: "foo"), .opaque("loCAlhost"))
      XCTAssertEqual(WebURL.Host("loc%61lhost", scheme: "foo"), .opaque("loc%61lhost"))
      XCTAssertEqual(
        WebURL.Host("loC𝐀𝐋𝐇𝐨𝐬𝐭", scheme: "foo"),
        .opaque("loC%F0%9D%90%80%F0%9D%90%8B%F0%9D%90%87%F0%9D%90%A8%F0%9D%90%AC%F0%9D%90%AD")
      )
    }

    // Windows drive letters are not valid hosts in any special URLs, and must be escaped in non-special URLs.
    do {
      XCTAssertNil(WebURL.Host("C:", scheme: "file"))
      XCTAssertNil(WebURL.Host("C|", scheme: "file"))
      XCTAssertNil(WebURL.Host("C%3A", scheme: "file"))
      XCTAssertNil(WebURL.Host("C%7C", scheme: "file"))

      XCTAssertNil(WebURL.Host("C:", scheme: "http"))
      XCTAssertNil(WebURL.Host("C|", scheme: "http"))
      XCTAssertNil(WebURL.Host("C%3A", scheme: "http"))
      XCTAssertNil(WebURL.Host("C%7C", scheme: "http"))

      XCTAssertNil(WebURL.Host("C:", scheme: "foo"))
      XCTAssertNil(WebURL.Host("C|", scheme: "foo"))
      XCTAssertEqual(WebURL.Host("C%3A", scheme: "foo"), .opaque("C%3A"))
      XCTAssertEqual(WebURL.Host("C%7C", scheme: "foo"), .opaque("C%7C"))
    }
  }
}
