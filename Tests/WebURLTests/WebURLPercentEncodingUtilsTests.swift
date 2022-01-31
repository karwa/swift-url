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

class WebURLPercentEncodingUtilsTests: XCTestCase {}

extension WebURLPercentEncodingUtilsTests {

  func testDoesNotNeedEncoding() {

    struct EncodeASCIIPeriods: PercentEncodeSet {
      func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
        codePoint == UInt8(ascii: ".")
      }
    }

    func check<EncodeSet: PercentEncodeSet>(_ original: String, _ encodeSet: EncodeSet) {
      let originalURL = WebURL(original)!
      XCTAssertEqual(originalURL.serialized(), original)

      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .doesNotNeedEncoding)

      // Check the serialization and structure are identical to the original.
      XCTAssertEqual(encodedURL.serialized(), original)
      XCTAssertTrue(encodedURL.storage.structure.describesSameStructure(as: originalURL.storage.structure))
      encodedURL.storage.structure.checkInvariants()

      // Check that the "modified" URL reparses to the same result.
      XCTAssertURLIsIdempotent(encodedURL)
    }

    let componentSetWithoutSubdelims = URLEncodeSet.Component().withoutSubdelims

    // No special characters.
    check("https://example.com/foo/bar?baz#qux", componentSetWithoutSubdelims)
    // IPv6 address.
    check("https://[::ffff:c0a8:1]/foo/bar?baz#qux", componentSetWithoutSubdelims)
    // Only percent-encoding.
    check("https://example.com/fo%2Fo/b%5Br?b%7Cz#q%23x", componentSetWithoutSubdelims)
    // Opaque path.
    check("foo:abc[flag]`()\\{uuid}", componentSetWithoutSubdelims)

    // Domain.
    check("https://a.b.c.d/foo/bar?baz#qux", EncodeASCIIPeriods())
    // IPv4 Address.
    check("https://127.0.0.1/foo/bar?baz#qux", EncodeASCIIPeriods())
  }

  func testEmptyComponents() {

    // Since this operation works on the URL's code-units and bypasses the regular setters,
    // check a variety of edge-cases to make sure the URLStructure is as we expect.

    let encodeSet = URLEncodeSet.Component().withoutSubdelims

    func check(_ original: String, additionalStructureChecks: (URLStructure<URLStorage.SizeType>) -> Void = { _ in }) {
      let originalURL = WebURL(original)!
      XCTAssertEqual(originalURL.serialized(), original)
      additionalStructureChecks(originalURL.storage.structure)

      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .doesNotNeedEncoding)

      // Check the serialization and structure are identical to the original.
      XCTAssertEqual(encodedURL.serialized(), original)
      XCTAssertTrue(encodedURL.storage.structure.describesSameStructure(as: originalURL.storage.structure))
      encodedURL.storage.structure.checkInvariants()
      additionalStructureChecks(encodedURL.storage.structure)

      // Check that the "modified" URL reparses to the same result.
      XCTAssertURLIsIdempotent(encodedURL)
    }

    // Empty username.
    check("https://:pass@test/foo?baz#qux")

    // Nil hostname (path-only).
    check("foo:/foo?baz#qux")
    // Empty hostname.
    check("foo:///foo?baz#qux")

    // Empty path.
    check("foo://host?baz#qux") { structure in XCTAssertEqual(structure.firstPathComponentLength, 0) }
    // Root path.
    check("foo://host/?baz#qux") { structure in XCTAssertEqual(structure.firstPathComponentLength, 1) }

    // Nil query.
    check("foo://host#qux") { structure in XCTAssertTrue(structure.queryIsKnownFormEncoded) }
    // Empty query.
    check("foo://host?#qux") { structure in XCTAssertTrue(structure.queryIsKnownFormEncoded) }

    // Nil fragment.
    check("foo://host?bar")
    // Empty fragment.
    check("foo://host?bar#")
  }

  func testAddingEncoding_firstPathComponent() {

    // Check that we update the URLStructure's firstPathComponentLength when adding percent-encoding.

    let encodeSet = URLEncodeSet.Component().withoutSubdelims

    do {
      let originalURL = WebURL("http://test/foo[flag:true]/bar")!
      XCTAssertEqual(originalURL.storage.structure.firstPathComponentLength, 15)
      XCTAssertEqual(originalURL.pathComponents.first, "foo[flag:true]")

      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)

      XCTAssertEqual(encodedURL.serialized(), "http://test/foo%5Bflag%3Atrue%5D/bar")
      XCTAssertEqual(encodedURL.storage.structure.firstPathComponentLength, 21)
      XCTAssertEqual(encodedURL.pathComponents.first, "foo[flag:true]")
      encodedURL.storage.structure.checkInvariants()

      XCTAssertURLIsIdempotent(encodedURL)
    }
    do {
      let originalURL = WebURL("scheme:/foo[flag:true]/bar")!
      XCTAssertEqual(originalURL.storage.structure.firstPathComponentLength, 15)
      XCTAssertEqual(originalURL.pathComponents.first, "foo[flag:true]")

      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)

      XCTAssertEqual(encodedURL.serialized(), "scheme:/foo%5Bflag%3Atrue%5D/bar")
      XCTAssertEqual(encodedURL.storage.structure.firstPathComponentLength, 21)
      XCTAssertEqual(encodedURL.pathComponents.first, "foo[flag:true]")
      encodedURL.storage.structure.checkInvariants()

      XCTAssertURLIsIdempotent(encodedURL)
    }
  }

  func testAddingEncoding_queryIsKnownFormEncoded() {

    // Check that we reset the URLStructure's queryIsKnownFormEncoded when adding percent-encoding.

    struct EncodeUnderscores: PercentEncodeSet {
      func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
        codePoint == UInt8(ascii: "_")
      }
    }

    // If the encode-set does not include '+', '=', or '&', params will be preserved,
    // but the 'queryIsKnownFormEncoded' flag will be reset because the query is over-encoded.
    do {
      var originalURL = WebURL("https://test/foo")!
      originalURL.formParams.search = "res_taur_ants in NYC"
      originalURL.formParams.cli_ent = "mobi_le"
      XCTAssertEqual(originalURL.serialized(), "https://test/foo?search=res_taur_ants+in+NYC&cli_ent=mobi_le")
      XCTAssertTrue(originalURL.storage.structure.queryIsKnownFormEncoded)

      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(EncodeUnderscores()), .encodingAdded)

      XCTAssertEqual(encodedURL.serialized(), "https://test/foo?search=res%5Ftaur%5Fants+in+NYC&cli%5Fent=mobi%5Fle")
      XCTAssertFalse(encodedURL.storage.structure.queryIsKnownFormEncoded)
      XCTAssertEqual(encodedURL.formParams.search, "res_taur_ants in NYC")
      XCTAssertEqual(encodedURL.formParams.cli_ent, "mobi_le")
      encodedURL.storage.structure.checkInvariants()

      XCTAssertURLIsIdempotent(encodedURL)
    }
  }

  func testAddingEncoding_digits() {

    // Even if for some reason we decide to encode ASCII digits, characters which are part of
    // percent-encoded bytes shouldn't be encoded. Also, the port number should never be encoded.

    struct EncodeDigits: PercentEncodeSet {
      func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
        ASCII(codePoint)?.isDigit == true
      }
    }

    let encodeSet = EncodeDigits()

    do {
      var url = WebURL("http://u%25s3r:pa55wo%25rd@h0st:99/p4t%23")!
      XCTAssertEqual(url.serialized(), "http://u%25s3r:pa55wo%25rd@h0st:99/p4t%23")

      XCTAssertEqual(url._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)
      XCTAssertEqual(url.serialized(), "http://u%25s%33r:pa%35%35wo%25rd@h0st:99/p%34t%23")
      XCTAssertEqual(url.port, 99)
      url.storage.structure.checkInvariants()

      XCTAssertURLIsIdempotent(url)
    }
    do {
      var url = WebURL("scheme://u%25s3r:pa55wo%25rd@h0st:99/p4t%23")!
      XCTAssertEqual(url.serialized(), "scheme://u%25s3r:pa55wo%25rd@h0st:99/p4t%23")

      XCTAssertEqual(url._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)
      XCTAssertEqual(url.serialized(), "scheme://u%25s%33r:pa%35%35wo%25rd@h%30st:99/p%34t%23")
      XCTAssertEqual(url.port, 99)
      url.storage.structure.checkInvariants()

      XCTAssertURLIsIdempotent(url)
    }
  }

  func testAddingEncoding() {

    let encodeSet = URLEncodeSet.Component().withoutSubdelims

    func check(_ original: String, encoded: String, additionalChecks: (WebURL) -> Void) {
      let originalURL = WebURL(original)!
      XCTAssertEqual(originalURL.serialized(), original)

      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)

      // Check that COW was triggered.
      XCTAssertEqual(originalURL.serialized(), original)

      XCTAssertEqual(encodedURL.serialized(), encoded)
      encodedURL.storage.structure.checkInvariants()
      additionalChecks(encodedURL)

      XCTAssertURLIsIdempotent(encodedURL)
    }

    // Username
    check("http://us%er$foo@test/", encoded: "http://us%25er%24foo@test/") { encodedURL in
      XCTAssertEqual(encodedURL.username, "us%25er%24foo")
    }

    // Password
    check("http://user:pa%s$@test/", encoded: "http://user:pa%25s%24@test/") { encodedURL in
      XCTAssertEqual(encodedURL.password, "pa%25s%24")
    }

    // Opaque hostname
    check("foo://h%o$t/", encoded: "foo://h%25o%24t/") { encodedURL in
      XCTAssertEqual(encodedURL.hostname, "h%25o%24t")
    }

    // Path
    check("foo://host/p[%1]/p^2^", encoded: "foo://host/p%5B%251%5D/p%5E2%5E") { encodedURL in
      XCTAssertEqual(encodedURL.path, "/p%5B%251%5D/p%5E2%5E")
      XCTAssertEqualElements(encodedURL.pathComponents, ["p[%1]", "p^2^"])
    }

    // Query
    check(
      "foo://host?color[R]=100&color{%G}=233&color|B|=42",
      encoded: "foo://host?color%5BR%5D=100&color%7B%25G%7D=233&color%7CB%7C=42"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.query, "color%5BR%5D=100&color%7B%25G%7D=233&color%7CB%7C=42")
      XCTAssertEqual(encodedURL.formParams.get("color[R]"), "100")
      XCTAssertEqual(encodedURL.formParams.get("color{%G}"), "233")
      XCTAssertEqual(encodedURL.formParams.get("color|B|"), "42")
    }

    // Fragment
    check("foo://test#abc#d%%zef[#]ghi^|", encoded: "foo://test#abc%23d%25%25zef%5B%23%5Dghi%5E%7C") { encodedURL in
      XCTAssertEqual(encodedURL.fragment, "abc%23d%25%25zef%5B%23%5Dghi%5E%7C")
    }

    // Many components.
    check(
      "https://test/foo[a]/b%ar|a|^1^?ba%z[a]{1}#qux[a]#%1",
      encoded: "https://test/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E?ba%25z%5Ba%5D%7B1%7D#qux%5Ba%5D%23%251"
    ) { encodedURL in
      XCTAssertURLComponents(
        encodedURL, scheme: "https", hostname: "test", path: "/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E",
        query: "ba%25z%5Ba%5D%7B1%7D", fragment: "qux%5Ba%5D%23%251"
      )
    }
    check(
      "foo://te$%t/foo[a]/b%ar|a|^1^?ba%z[a]{1}#qux[a]#%1",
      encoded: "foo://te%24%25t/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E?ba%25z%5Ba%5D%7B1%7D#qux%5Ba%5D%23%251"
    ) { encodedURL in
      XCTAssertURLComponents(
        encodedURL, scheme: "foo", hostname: "te%24%25t", path: "/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E",
        query: "ba%25z%5Ba%5D%7B1%7D", fragment: "qux%5Ba%5D%23%251"
      )
    }
  }
}


// --------------------------------------------
// MARK: - Utils
// --------------------------------------------


fileprivate struct EncodeSetWithoutSubdelims<Base: PercentEncodeSet>: PercentEncodeSet {
  var base: Base
  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    switch codePoint {
    case UInt8(ascii: "/"), UInt8(ascii: "&"), UInt8(ascii: "+"), UInt8(ascii: "="):
      return false
    default:
      return base.shouldPercentEncode(ascii: codePoint)
    }
  }
}

extension PercentEncodeSet {
  fileprivate var withoutSubdelims: EncodeSetWithoutSubdelims<Self> {
    EncodeSetWithoutSubdelims(base: self)
  }
}
