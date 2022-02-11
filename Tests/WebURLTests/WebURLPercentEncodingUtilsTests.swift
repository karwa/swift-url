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

    func check<EncodeSet: PercentEncodeSet>(_ original: String, _ encodeSet: EncodeSet) {
      // 1. The given string must be a normalized URL.
      let originalURL = WebURL(original)!
      XCTAssertEqual(originalURL.serialized(), original)
      // 2. Encoding the URL must return '.doesNotNeedEncoding'.
      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .doesNotNeedEncoding)
      // 3. The serialization and structure should remain the same as the original.
      encodedURL.storage.structure.checkInvariants()
      XCTAssertEqual(encodedURL.serialized(), original)
      XCTAssertTrue(encodedURL.storage.structure.describesSameStructure(as: originalURL.storage.structure))
      XCTAssertURLIsIdempotent(encodedURL)
    }

    let componentSetWithoutSubdelims = URLEncodeSet.Component().withoutSubdelims

    // No special characters.
    check("https://example.com/foo/bar?baz#qux", componentSetWithoutSubdelims)
    // Schemes are never encoded, do not cause failure.
    check("foo-bar:/baz", EncodeSingleCodePoint("-"))
    // IPv4 addresses are never encoded, do not cause failure.
    check("https://127.0.0.1/foo/bar?baz#qux", EncodeSingleCodePoint("."))
    // IPv6 addresses are never encoded, do not cause failure.
    check("https://[::ffff:c0a8:1]/foo/bar?baz#qux", EncodeSingleCodePoint("["))

    // URL is already percent-encoded.
    check("https://example.com/fo%2Fo/b%5Br?b%7Cz#q%23x", componentSetWithoutSubdelims)
    // Opaque path with no special characters.
    check("foo:abc-(flag)-(!'*._~)", componentSetWithoutSubdelims)
    // Opaque path with percent-encoding.
    check("foo:abc-%24(flag)%5B-(!%2F'*._~)", componentSetWithoutSubdelims)
  }

  func testUnableToEncode() {

    func check<EncodeSet: PercentEncodeSet>(_ encodeSet: EncodeSet, original: String, expected: String) {
      // 1. The given string must be a normalized URL.
      let originalURL = WebURL(original)!
      XCTAssertEqual(originalURL.serialized(), original)
      // 2. Encoding the URL must fail, returning '.unableToEncode'.
      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .unableToEncode)
      // 3. If the operation failed, some components may be encoded whilst others won't be.
      //    Check the result is as expected.
      XCTAssertEqual(encodedURL.serialized(), expected)
      // 4. The URL must be left in a valid state despite the failure.
      XCTAssertURLIsIdempotent(encodedURL)
    }

    let componentSetWithoutSubdelims = URLEncodeSet.Component().withoutSubdelims

    // Special characters in domains cannot be encoded, cause failure.
    check(
      componentSetWithoutSubdelims,
      original: "https://exa{m}ple.com/fo[o]/bar?b[a]z#q[u]x",
      expected: "https://exa{m}ple.com/fo[o]/bar?b[a]z#q[u]x"
    )
    check(
      EncodeSingleCodePoint("."),
      original: "https://a.b.c.d/foo/bar?baz#qux",
      expected: "https://a.b.c.d/foo/bar?baz#qux"
    )
    // Opaque paths are not encoded (by choice), special characters cause failure.
    check(
      componentSetWithoutSubdelims,
      original: "foo:abc[flag]`()\\{uuid}",
      expected: "foo:abc[flag]`()\\{uuid}"
    )
    // If the operation fails, some components may already have been encoded.
    check(
      componentSetWithoutSubdelims,
      original: "https://us%%er:pa$$word@exa{m}ple.com/fo[o]/bar?b[a]z#q[u]x",
      expected: "https://us%25%25er:pa%24%24word@exa{m}ple.com/fo[o]/bar?b[a]z#q[u]x"
    )
  }

  func testEncodingAdded() {

    let encodeSet = URLEncodeSet.Component().withoutSubdelims

    func check(original: String, expected: String, additionalChecks: (WebURL) -> Void) {
      // 1. The given string must be a normalized URL.
      let originalURL = WebURL(original)!
      XCTAssertEqual(originalURL.serialized(), original)
      // 2. Encoding the URL must succeed, returning '.encodingAdded'.
      var encodedURL = originalURL
      XCTAssertEqual(encodedURL._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)
      // 3. The mutation should have triggered COW.
      XCTAssertEqual(originalURL.serialized(), original)
      // 4. Check the result.
      encodedURL.storage.structure.checkInvariants()
      XCTAssertEqual(encodedURL.serialized(), expected)
      XCTAssertURLIsIdempotent(encodedURL)
      additionalChecks(encodedURL)
    }

    // Username
    check(
      original: "http://us%er$foo@test/",
      expected: "http://us%25er%24foo@test/"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.username, "us%25er%24foo")
    }

    // Password
    check(
      original: "http://user:pa%s$@test/",
      expected: "http://user:pa%25s%24@test/"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.password, "pa%25s%24")
    }

    // Opaque hostname
    check(
      original: "foo://h%o$t/",
      expected: "foo://h%25o%24t/"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.hostname, "h%25o%24t")
    }

    // Path
    check(
      original: "foo://host/p[%1]/p^2^",
      expected: "foo://host/p%5B%251%5D/p%5E2%5E"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.path, "/p%5B%251%5D/p%5E2%5E")
      XCTAssertEqualElements(encodedURL.pathComponents, ["p[%1]", "p^2^"])
    }

    // Query
    check(
      original: "foo://host?color[R]=100&color{%G}=233&color|B|=42",
      expected: "foo://host?color%5BR%5D=100&color%7B%25G%7D=233&color%7CB%7C=42"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.query, "color%5BR%5D=100&color%7B%25G%7D=233&color%7CB%7C=42")
      XCTAssertEqual(encodedURL.formParams.get("color[R]"), "100")
      XCTAssertEqual(encodedURL.formParams.get("color{%G}"), "233")
      XCTAssertEqual(encodedURL.formParams.get("color|B|"), "42")
    }

    // Fragment
    check(
      original: "foo://test#abc#d%%zef[#]ghi^|",
      expected: "foo://test#abc%23d%25%25zef%5B%23%5Dghi%5E%7C"
    ) { encodedURL in
      XCTAssertEqual(encodedURL.fragment, "abc%23d%25%25zef%5B%23%5Dghi%5E%7C")
    }

    // Many components.
    check(
      original: "https://test/foo[a]/b%ar|a|^1^?ba%z[a]{1}#qux[a]#%1",
      expected: "https://test/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E?ba%25z%5Ba%5D%7B1%7D#qux%5Ba%5D%23%251"
    ) { encodedURL in
      XCTAssertURLComponents(
        encodedURL, scheme: "https", hostname: "test", path: "/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E",
        query: "ba%25z%5Ba%5D%7B1%7D", fragment: "qux%5Ba%5D%23%251"
      )
    }
    check(
      original: "foo://te$%t/foo[a]/b%ar|a|^1^?ba%z[a]{1}#qux[a]#%1",
      expected: "foo://te%24%25t/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E?ba%25z%5Ba%5D%7B1%7D#qux%5Ba%5D%23%251"
    ) { encodedURL in
      XCTAssertURLComponents(
        encodedURL, scheme: "foo", hostname: "te%24%25t", path: "/foo%5Ba%5D/b%25ar%7Ca%7C%5E1%5E",
        query: "ba%25z%5Ba%5D%7B1%7D", fragment: "qux%5Ba%5D%23%251"
      )
    }
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

  func testEncodingAdded_firstPathComponent() {

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

  func testEncodingAdded_queryIsKnownFormEncoded() {

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

  func testEncodingAdded_digits() {

    // Even if for some reason we decide to encode ASCII digits, characters which are part of
    // percent-encoded bytes shouldn't be encoded. Also, the port number should never be encoded.

    struct EncodeDigits: PercentEncodeSet {
      func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
        ASCII(codePoint)?.isDigit == true
      }
    }

    let encodeSet = EncodeDigits()

    do {
      var url = WebURL("http://u%25s3r:pa55wo%25rd@host:99/p4t%23")!
      XCTAssertEqual(url.serialized(), "http://u%25s3r:pa55wo%25rd@host:99/p4t%23")

      XCTAssertEqual(url._spis._addPercentEncodingToAllComponents(encodeSet), .encodingAdded)
      XCTAssertEqual(url.serialized(), "http://u%25s%33r:pa%35%35wo%25rd@host:99/p%34t%23")
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

fileprivate struct EncodeSingleCodePoint: PercentEncodeSet {
  var singleByteCodePoint: UInt8

  init(_ character: Unicode.Scalar) {
    self.singleByteCodePoint = UInt8(ascii: character)
  }

  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    codePoint == singleByteCodePoint
  }
}
