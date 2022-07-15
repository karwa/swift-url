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

final class DomainTests: XCTestCase {}


// --------------------------------------------
// MARK: - Protocol conformances
// --------------------------------------------


extension DomainTests {

  func testLosslessStringConvertible() {

    let asciiDomain = WebURL.Domain("example.com")!
    XCTAssertEqual(asciiDomain.description, "example.com")
    XCTAssertEqual(asciiDomain.description, asciiDomain.serialized)
    XCTAssertEqual(String(asciiDomain), asciiDomain.serialized)
    XCTAssertEqual(WebURL.Domain(asciiDomain.description), asciiDomain)

    let asciiDomain2 = WebURL.Domain("EX%61MPlE.cOm")!
    XCTAssertEqual(asciiDomain2.description, "example.com")
    XCTAssertEqual(asciiDomain2.description, asciiDomain2.serialized)
    XCTAssertEqual(String(asciiDomain2), asciiDomain2.serialized)
    XCTAssertEqual(WebURL.Domain(asciiDomain2.description), asciiDomain2)

    let idnDomain = WebURL.Domain("a.xn--igbi0gl.com")!
    XCTAssertEqual(idnDomain.description, "a.xn--igbi0gl.com")
    XCTAssertEqual(idnDomain.description, idnDomain.serialized)
    XCTAssertEqual(String(idnDomain), idnDomain.serialized)
    XCTAssertEqual(WebURL.Domain(idnDomain.description), idnDomain)

    let idnDomain2 = WebURL.Domain("a.أهلا.com")!
    XCTAssertEqual(idnDomain2.description, "a.xn--igbi0gl.com")
    XCTAssertEqual(idnDomain2.description, idnDomain2.serialized)
    XCTAssertEqual(String(idnDomain2), idnDomain2.serialized)
    XCTAssertEqual(WebURL.Domain(idnDomain2.description), idnDomain2)
  }

  func testCodable() throws {

    guard #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) else {
      throw XCTSkip("JSONEncoder.OutputFormatting.withoutEscapingSlashes requires tvOS 13 or newer")
    }

    func roundTripJSON<Value: Codable & Equatable>(
      _ original: Value, expectedJSON: String
    ) throws {
      // Encode to JSON, check that we get the expected string.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
      let jsonString = String(decoding: try encoder.encode(original), as: UTF8.self)
      XCTAssertEqual(jsonString, expectedJSON)
      // Decode the JSON output, check we get the expected result.
      let decodedValue = try JSONDecoder().decode(Value.self, from: Data(jsonString.utf8))
      XCTAssertEqual(decodedValue, original)
    }

    func fromJSON(_ json: String) throws -> WebURL.Domain {
      try JSONDecoder().decode(WebURL.Domain.self, from: Data(json.utf8))
    }

    domain: do {
      // Values round-trip exactly.
      try roundTripJSON(
        WebURL.Domain("example.com")!,
        expectedJSON:
          #"""
          "example.com"
          """#
      )
      try roundTripJSON(
        WebURL.Domain("a.xn--igbi0gl.com")!,
        expectedJSON:
          #"""
          "a.xn--igbi0gl.com"
          """#
      )
      // When decoding, invalid domains are rejected.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "hello world"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "xn--cafe-dma.fr"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "xn--caf-yvc.fr"
          """#
        )
      )
      // When decoding, values are normalized as domains.
      XCTAssertEqual(
        try fromJSON(
          #"""
          "EX%61MPLE.com"
          """#
        ),
        WebURL.Domain("example.com")
      )
      XCTAssertEqual(
        try fromJSON(
          #"""
          "a.أهلا.com"
          """#
        ),
        WebURL.Domain("a.xn--igbi0gl.com")
      )
    }

    do {
      // Strings which the host parser thinks are other kinds of hosts get rejected.
      // IPv4.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "192.168.0.1"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "0x7F.1"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "0x𝟕f.1"
          """#
        )
      )
      // IPv6.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "[2001:db8:85a3::8a2e:370:7334]"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "[2001:0DB8:85A3:0:0:8a2E:0370:7334]"
          """#
        )
      )
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          "2001:db8:85a3::8a2e:370:7334"
          """#
        )
      )
      // Empty.
      XCTAssertThrowsError(
        try fromJSON(
          #"""
          ""
          """#
        )
      )
    }
  }
}

#if swift(>=5.5) && canImport(_Concurrency)

  extension DomainTests {

    func testSendable() {
      // Since Sendable only exists at compile-time, it's enough to just ensure that this type-checks.
      func _requiresSendable<T: Sendable>(_: T) {}

      let domain = WebURL.Domain("example.com")!
      _requiresSendable(domain)
    }
  }

#endif


// --------------------------------------------
// MARK: - Parsing
// --------------------------------------------


extension DomainTests {

  func testParsing() {

    // Simple ASCII domains.
    test: do {
      var domain = WebURL.Domain("example.com")
      XCTAssertEqual(domain?.serialized, "example.com")
      XCTAssertEqual(domain?.isIDN, false)

      domain = WebURL.Domain("nodots")
      XCTAssertEqual(domain?.serialized, "nodots")
      XCTAssertEqual(domain?.isIDN, false)
    }

    // IDNA.
    test: do {
      var domain = WebURL.Domain("💩.com")
      XCTAssertEqual(domain?.serialized, "xn--ls8h.com")
      XCTAssertEqual(domain?.isIDN, true)

      domain = WebURL.Domain("www.foo。bar.com")
      XCTAssertEqual(domain?.serialized, "www.foo.bar.com")
      XCTAssertEqual(domain?.isIDN, false)

      domain = WebURL.Domain("xn--cafe-dma.com")
      XCTAssertNil(domain)

      domain = WebURL.Domain("xn--caf-yvc.com")
      XCTAssertNil(domain)

      domain = WebURL.Domain("has a space.com")
      XCTAssertNil(domain)
    }

    // IPv4 addresses.
    test: do {
      var domain = WebURL.Domain("11.173.240.13")
      XCTAssertNil(domain)

      domain = WebURL.Domain("0xbadf00d")
      XCTAssertNil(domain)

      domain = WebURL.Domain("0x𝟕f.1")
      XCTAssertNil(domain)

      domain = WebURL.Domain("11.173.240.13.4")
      XCTAssertNil(domain)
    }

    // IPv6 addresses.
    test: do {
      var domain = WebURL.Domain("[::127.0.0.1]")
      XCTAssertNil(domain)

      domain = WebURL.Domain("[blahblahblah]")
      XCTAssertNil(domain)
    }

    // Empty strings.
    test: do {
      let domain = WebURL.Domain("")
      XCTAssertNil(domain)

      // IDNA-mapped to the empty string.
      XCTAssertNil(WebURL.Domain("\u{AD}"))
    }

    // Percent-encoding.
    test: do {
      var domain = WebURL.Domain("www.foo%E3%80%82bar.com")
      XCTAssertEqual(domain?.serialized, "www.foo.bar.com")
      XCTAssertEqual(domain?.isIDN, false)

      domain = WebURL.Domain("%F0%9F%92%A9.com")
      XCTAssertEqual(domain?.serialized, "xn--ls8h.com")
      XCTAssertEqual(domain?.isIDN, true)

      domain = WebURL.Domain("0x%F0%9D%9F%95f.1")
      XCTAssertNil(domain)
    }

    // Localhost.
    do {
      let strings = [
        "localhost",
        "loCAlhost",
        "loc%61lhost",
        "loC𝐀𝐋𝐇𝐨𝐬𝐭",
      ]
      for string in strings {
        let domain = WebURL.Domain(string)
        XCTAssertEqual(domain?.serialized, "localhost")
        XCTAssertEqual(domain?.isIDN, false)
      }
    }

    // Windows drive letters.
    do {
      XCTAssertNil(WebURL.Domain("C:"))
      XCTAssertNil(WebURL.Domain("C|"))
      XCTAssertNil(WebURL.Domain("C%3A"))
      XCTAssertNil(WebURL.Domain("C%7C"))
    }
  }
}
