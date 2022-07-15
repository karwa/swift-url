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

class WebURLTests: XCTestCase {}


// --------------------------------------------
// MARK: - Protocol conformances
// --------------------------------------------


extension WebURLTests {

  func testEquatableHashable() {
    // The URL Standard defines URL equivalence ( https://url.spec.whatwg.org/#url-equivalence ).
    // 2 URLs are equivalent if their serializations are the same.

    // Note: We don't test that unequal URLs have different hashes (they may indeed collide - depends on the hasher),
    //       but equal URLs should produce the same hash value.
    func checkEqualHashValues(_ urlA: WebURL, _ urlB: WebURL) {
      var hasherA = Hasher()
      var hasherB = Hasher()
      urlA.hash(into: &hasherA)
      urlB.hash(into: &hasherB)
      XCTAssertEqual(hasherA.finalize(), hasherB.finalize())
    }

    do {
      let urlA = WebURL("http://example.com/foo/bar?baz#qux")!
      let urlB = WebURL("http://example.com/foo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertTrue(urlA == urlB)
      XCTAssertFalse(urlA != urlB)
      checkEqualHashValues(urlA, urlB)
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux")!
      let urlB = WebURL("foo:/foo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertTrue(urlA == urlB)
      XCTAssertFalse(urlA != urlB)
      checkEqualHashValues(urlA, urlB)
    }
    do {
      let urlA = WebURL("opq:foo-bar-baz")!
      let urlB = WebURL("opq:foo-bar-baz")!
      XCTAssertEqual(urlA.serialized(), "opq:foo-bar-baz")
      XCTAssertEqual(urlB.serialized(), "opq:foo-bar-baz")
      XCTAssert(urlA.hasOpaquePath && urlB.hasOpaquePath)
      XCTAssertTrue(urlA == urlB)
      XCTAssertFalse(urlA != urlB)
      checkEqualHashValues(urlA, urlB)
    }
    // Obviously different URLs.
    do {
      let urlA = WebURL("http://example.com/foo/bar?baz#qux")!
      let urlB = WebURL("http://somewhereelse.com/foo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://somewhereelse.com/foo/bar?baz#qux")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux")!
      let urlB = WebURL("foo:/bar/foo?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "foo:/bar/foo?baz#qux")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
    }
    do {
      let urlA = WebURL("opq:foo-bar-baz")!
      let urlB = WebURL("opq:baz-bar-foo")!
      XCTAssertEqual(urlA.serialized(), "opq:foo-bar-baz")
      XCTAssertEqual(urlB.serialized(), "opq:baz-bar-foo")
      XCTAssert(urlA.hasOpaquePath && urlB.hasOpaquePath)
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
    }
    // URLs where the only difference is percent-encoding.
    do {
      let urlA = WebURL("http://example.com/foo/bar?baz#qux")!
      let urlB = WebURL("http://example.com/f%6Fo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://example.com/f%6Fo/bar?baz#qux")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
      XCTAssert(urlA.path.percentDecoded() == urlB.path.percentDecoded())
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux")!
      let urlB = WebURL("foo:/foo/bar?baz#qu%78")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "foo:/foo/bar?baz#qu%78")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
      XCTAssert(urlA.fragment?.percentDecoded() == urlB.fragment?.percentDecoded())
    }
    do {
      let urlA = WebURL("opq:foo-bar-baz")!
      let urlB = WebURL("opq:foo-b%61r-baz")!
      XCTAssertEqual(urlA.serialized(), "opq:foo-bar-baz")
      XCTAssertEqual(urlB.serialized(), "opq:foo-b%61r-baz")
      XCTAssert(urlA.hasOpaquePath && urlB.hasOpaquePath)
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
      XCTAssert(urlA.path.percentDecoded() == urlB.path.percentDecoded())
    }
    // Some components are case-normalized by the parser (scheme, certain hostnames),
    // but other parts are case-sensitive.
    do {
      let urlA = WebURL("HTTP://EXamPLE.cOm/foo/bar")!
      let urlB = WebURL("http://exAMple.CoM/foo/bar")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar")
      XCTAssertEqual(urlB.serialized(), "http://example.com/foo/bar")
      XCTAssertTrue(urlA == urlB)
      XCTAssertFalse(urlA != urlB)
      checkEqualHashValues(urlA, urlB)
    }
    do {
      let urlA = WebURL("HTTP://EXamPLE.cOm/FOO/bar")!
      let urlB = WebURL("http://exAMple.CoM/foo/bar")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/FOO/bar")
      XCTAssertEqual(urlB.serialized(), "http://example.com/foo/bar")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
    }
    do {
      let urlA = WebURL("FOO://example.com/foo/bar")!
      let urlB = WebURL("foo://example.com/foo/bar")!
      XCTAssertEqual(urlA.serialized(), "foo://example.com/foo/bar")
      XCTAssertEqual(urlB.serialized(), "foo://example.com/foo/bar")
      XCTAssertTrue(urlA == urlB)
      XCTAssertFalse(urlA != urlB)
      checkEqualHashValues(urlA, urlB)
    }
    do {
      let urlA = WebURL("foo://EXamPLE.cOm/foo/bar")!
      let urlB = WebURL("foo://exAMple.CoM/foo/bar")!
      XCTAssertEqual(urlA.serialized(), "foo://EXamPLE.cOm/foo/bar")
      XCTAssertEqual(urlB.serialized(), "foo://exAMple.CoM/foo/bar")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
    }
    // Even capitalization in percent-encoding makes URLs non-equal (blame the standard!)
    do {
      let urlA = WebURL("http://example.com/f%6Fo/bar?baz#qux")!
      let urlB = WebURL("http://example.com/f%6fo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/f%6Fo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://example.com/f%6fo/bar?baz#qux")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
      XCTAssert(urlA.path.percentDecoded() == urlB.path.percentDecoded())
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux%ff")!
      let urlB = WebURL("foo:/foo/bar?baz#qux%FF")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux%ff")
      XCTAssertEqual(urlB.serialized(), "foo:/foo/bar?baz#qux%FF")
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
      XCTAssert(urlA.fragment?.percentDecoded() == urlB.fragment?.percentDecoded())
    }
    do {
      let urlA = WebURL("opq:foo-ba%D0-baz")!
      let urlB = WebURL("opq:foo-ba%d0-baz")!
      XCTAssertEqual(urlA.serialized(), "opq:foo-ba%D0-baz")
      XCTAssertEqual(urlB.serialized(), "opq:foo-ba%d0-baz")
      XCTAssert(urlA.hasOpaquePath && urlB.hasOpaquePath)
      XCTAssertTrue(urlA != urlB)
      XCTAssertFalse(urlA == urlB)
      XCTAssert(urlA.path.percentDecoded() == urlB.path.percentDecoded())
    }
  }

  func testComparable() {
    // URLs should be compared using their serialization.

    enum Order {
      case ascending
      case descending
      case equal
    }
    func checkComparable(_ urlA: WebURL, _ urlB: WebURL, expected: Order) {
      switch expected {
      case .ascending:
        XCTAssertFalse(urlA == urlB)
        XCTAssertTrue(urlA < urlB)
        XCTAssertTrue(urlB > urlA)
        XCTAssertFalse(urlB < urlA)
        XCTAssertFalse(urlA > urlB)
      case .descending:
        XCTAssertFalse(urlA == urlB)
        XCTAssertTrue(urlA > urlB)
        XCTAssertTrue(urlB < urlA)
        XCTAssertFalse(urlB > urlA)
        XCTAssertFalse(urlA < urlB)
      case .equal:
        XCTAssertTrue(urlA == urlB)
        XCTAssertFalse(urlA < urlB)
        XCTAssertFalse(urlB > urlA)
        XCTAssertFalse(urlB < urlA)
        XCTAssertFalse(urlA > urlB)
      }
    }

    // Equal URLs.
    do {
      let urlA = WebURL("http://example.com/foo/bar?baz#qux")!
      let urlB = WebURL("http://example.com/foo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://example.com/foo/bar?baz#qux")
      checkComparable(urlA, urlB, expected: .equal)
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux")!
      let urlB = WebURL("foo:/foo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "foo:/foo/bar?baz#qux")
      checkComparable(urlA, urlB, expected: .equal)
    }
    do {
      let urlA = WebURL("opq:foo-bar-baz")!
      let urlB = WebURL("opq:foo-bar-baz")!
      XCTAssertEqual(urlA.serialized(), "opq:foo-bar-baz")
      XCTAssertEqual(urlB.serialized(), "opq:foo-bar-baz")
      XCTAssert(urlA.hasOpaquePath && urlB.hasOpaquePath)
      checkComparable(urlA, urlB, expected: .equal)
    }
    // Non-equal URLs.
    do {
      let urlA = WebURL("http://example.com/foo/bar?baz#qux")!
      let urlB = WebURL("http://somewhereelse.com/foo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://somewhereelse.com/foo/bar?baz#qux")
      checkComparable(urlA, urlB, expected: .ascending)
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux")!
      let urlB = WebURL("foo:/bar/foo?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "foo:/bar/foo?baz#qux")
      checkComparable(urlA, urlB, expected: .descending)
    }
    do {
      let urlA = WebURL("opq:foo-bar-baz")!
      let urlB = WebURL("opq:baz-bar-foo")!
      XCTAssertEqual(urlA.serialized(), "opq:foo-bar-baz")
      XCTAssertEqual(urlB.serialized(), "opq:baz-bar-foo")
      XCTAssert(urlA.hasOpaquePath && urlB.hasOpaquePath)
      checkComparable(urlA, urlB, expected: .descending)
    }
    // Percent-encoding.
    do {
      let urlA = WebURL("http://example.com/foo/bar?baz#qux")!
      let urlB = WebURL("http://example.com/f%6Fo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://example.com/f%6Fo/bar?baz#qux")
      checkComparable(urlA, urlB, expected: .descending)
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux")!
      let urlB = WebURL("foo:/foo/bar?baz#qu%78")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "foo:/foo/bar?baz#qu%78")
      checkComparable(urlA, urlB, expected: .descending)
    }
    // Case-sensitivity.
    do {
      let urlA = WebURL("HTTP://EXamPLE.cOm/FOO/bar")!
      let urlB = WebURL("http://exAMple.CoM/foo/bar")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/FOO/bar")
      XCTAssertEqual(urlB.serialized(), "http://example.com/foo/bar")
      checkComparable(urlA, urlB, expected: .ascending)
    }
    do {
      let urlA = WebURL("foo://EXamPLE.cOm/foo/bar")!
      let urlB = WebURL("foo://exAMple.CoM/foo/bar")!
      XCTAssertEqual(urlA.serialized(), "foo://EXamPLE.cOm/foo/bar")
      XCTAssertEqual(urlB.serialized(), "foo://exAMple.CoM/foo/bar")
      checkComparable(urlA, urlB, expected: .ascending)
    }
    // Percent-encoding and case-sensitivity.
    do {
      let urlA = WebURL("http://example.com/f%6Fo/bar?baz#qux")!
      let urlB = WebURL("http://example.com/f%6fo/bar?baz#qux")!
      XCTAssertEqual(urlA.serialized(), "http://example.com/f%6Fo/bar?baz#qux")
      XCTAssertEqual(urlB.serialized(), "http://example.com/f%6fo/bar?baz#qux")
      checkComparable(urlA, urlB, expected: .ascending)
    }
    do {
      let urlA = WebURL("foo:/foo/bar?baz#qux%ff")!
      let urlB = WebURL("foo:/foo/bar?baz#qux%FF")!
      XCTAssertEqual(urlA.serialized(), "foo:/foo/bar?baz#qux%ff")
      XCTAssertEqual(urlB.serialized(), "foo:/foo/bar?baz#qux%FF")
      checkComparable(urlA, urlB, expected: .descending)
    }
  }

  func testCustomStringConvertible() {
    // String.init(WebURL) should include the fragment. Is the same as calling .serialized()
    do {
      let url = WebURL("http://example.com/some/path?and&a&query#withAFragment")!
      XCTAssertEqual(url.serialized(), "http://example.com/some/path?and&a&query#withAFragment")
      XCTAssertEqual(String(url), url.serialized())
      XCTAssertEqual(url.description, url.serialized())

      XCTAssertEqual(url.serialized(excludingFragment: true), "http://example.com/some/path?and&a&query")
      XCTAssertNotEqual(url.serialized(), url.serialized(excludingFragment: true))
    }
  }

  func testCodable() throws {
    guard #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) else {
      throw XCTSkip("JSONEncoder.OutputFormatting.withoutEscapingSlashes requires tvOS 13 or newer")
    }
    // WebURLs should be encoded as their serialization.
    func checkJSONEncoding(_ url: WebURL) throws {
      struct MyType: Equatable, Codable {
        var someData: Int
        var url: WebURL
      }
      let originalValue = MyType(someData: .random(in: 1..<1000), url: url)

      // Encode the value, check that the JSON output is as expected.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys, .prettyPrinted]
      let jsonString = String(decoding: try encoder.encode(originalValue), as: UTF8.self)
      XCTAssertEqual(
        jsonString,
        #"""
        {
          "someData" : \#(originalValue.someData),
          "url" : "\#(originalValue.url.serialized())"
        }
        """#
      )
      // Decode the JSON output, check that the result round-trips.
      let decodedValue = try JSONDecoder().decode(MyType.self, from: Data(jsonString.utf8))
      XCTAssertEqual(originalValue, decodedValue)
    }

    // Special/Non-Special/Opaque Path.
    try checkJSONEncoding(WebURL("https://example.com/foo/bar?baz#qux")!)
    try checkJSONEncoding(WebURL("foo:/bar/rab?baz#qux")!)
    try checkJSONEncoding(WebURL("opq:bar-rab?baz#qux")!)
    // Percent-encoding.
    try checkJSONEncoding(WebURL("http://example.com/f%6Fo/bar?baz#qux")!)
    try checkJSONEncoding(WebURL("foo:/foo/bar?baz#qux%FF")!)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)

  extension WebURLTests {

    func testSendable() {
      // Since Sendable only exists at compile-time, it's enough to just ensure that this type-checks.
      func _requiresSendable<T: Sendable>(_: T) {}

      let url = WebURL("http://example.com")!
      _requiresSendable(url)
      _requiresSendable(url.jsModel)
      _requiresSendable(url.host)
      _requiresSendable(url.utf8)
      _requiresSendable(url.origin)
      _requiresSendable(url.pathComponents)
      _requiresSendable(url.formParams)
    }
  }

#endif


// --------------------------------------------
// MARK: - In-place mutation
// --------------------------------------------


extension WebURLTests {

  /// Tests that setters copy to new storage when the mutated URL is not a unique reference.
  ///
  func testCopyOnWrite_nonUnique() {

    // TODO: Can we rule out copying due to needing more capacity or changing header type?
    //       - Maybe add an internal 'reserveCapacity' function?
    // TODO: These are by no means all paths that each setter can take.
    var url = WebURL("http://example.com/a/b?c=d&e=f#gh")!
    let original = url

    func checkOriginalHasNotChanged() {
      XCTAssertEqual(original.serialized(), "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertEqual(original.scheme, "http")
    }
    // Scheme.
    url.scheme = "https"
    XCTAssertEqual(url.serialized(), "https://example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.scheme, "https")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Username.
    url.username = "user"
    XCTAssertEqual(url.serialized(), "http://user@example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.username, "user")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Password.
    url.password = "pass"
    XCTAssertEqual(url.serialized(), "http://:pass@example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.password, "pass")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Hostname.
    url.hostname = "test.test"
    XCTAssertEqual(url.serialized(), "http://test.test/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.hostname, "test.test")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Port.
    url.port = 8080
    XCTAssertEqual(url.serialized(), "http://example.com:8080/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.port, 8080)
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Path.
    url.path = "/foo/bar/baz"
    XCTAssertEqual(url.serialized(), "http://example.com/foo/bar/baz?c=d&e=f#gh")
    XCTAssertEqual(url.path, "/foo/bar/baz")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Query
    url.query = "foo=bar&baz=qux"
    XCTAssertEqual(url.serialized(), "http://example.com/a/b?foo=bar&baz=qux#gh")
    XCTAssertEqual(url.query, "foo=bar&baz=qux")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Fragment
    url.fragment = "foo"
    XCTAssertEqual(url.serialized(), "http://example.com/a/b?c=d&e=f#foo")
    XCTAssertEqual(url.fragment, "foo")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
  }

  // Note: This is likely to be a bit fragile, since it relies on optimizations which might not happen at -Onone.
  //       For now, it works.

  /// Tests that setters on a uniquely referenced URL are performed in-place.
  ///
  func testCopyOnWrite_unique() {

    var url = WebURL("wss://user:pass@example.com:90/a/b?c=d&e=f#gh")!
    XCTAssertEqual(url.serialized(), "wss://user:pass@example.com:90/a/b?c=d&e=f#gh")

    // All new values must be the same length, so we can be sure we have enough capacity.

    // Scheme.
    checkDoesNotCopy(&url) {
      $0.scheme = "ftp"
    }
    XCTAssertEqual(url.serialized(), "ftp://user:pass@example.com:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Username.
    checkDoesNotCopy(&url) {
      $0.username = "resu"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:pass@example.com:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Password.
    checkDoesNotCopy(&url) {
      $0.password = "ssap"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@example.com:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Hostname.
    checkDoesNotCopy(&url) {
      $0.hostname = "moc.elpmaxe"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@moc.elpmaxe:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Port.
    checkDoesNotCopy(&url) {
      $0.port = 42
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@moc.elpmaxe:42/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Path
    checkDoesNotCopy(&url) {
      $0.path = "/j/k"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@moc.elpmaxe:42/j/k?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Query
    checkDoesNotCopy(&url) {
      $0.query = "m=n&o=p"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@moc.elpmaxe:42/j/k?m=n&o=p#gh")
    XCTAssertURLIsIdempotent(url)
    // Fragment
    checkDoesNotCopy(&url) {
      $0.fragment = "zz"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@moc.elpmaxe:42/j/k?m=n&o=p#zz")
    XCTAssertURLIsIdempotent(url)
    // Chained modifying wrappers.
    checkDoesNotCopy(&url) {
      $0.jsModel.swiftModel.jsModel.swiftModel.jsModel.swiftModel.fragment = "aa"
    }
    XCTAssertEqual(url.serialized(), "ftp://resu:ssap@moc.elpmaxe:42/j/k?m=n&o=p#aa")
    XCTAssertURLIsIdempotent(url)
  }
}


// --------------------------------------------
// MARK: - WebURL component tests.
// --------------------------------------------
// The behavior of getters and setters are tested via the JS model according to the WPT test files.
// However, the JS model is in many ways not ideal for use in Swift, so these tests only cover deviations from that
// model, including errors that can be thrown by the setters.


extension WebURLTests {

  /// Tests the WebURL scheme setter.
  ///
  /// The Swift model deviates from the JS model in that it does not trim or filter the new value when setting.
  ///
  func testSchemeSetter() {

    do {
      // [Throw] Invalid scheme.
      var url = WebURL("http://example.com/a/b?c=d&e=f#gh")!
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme("🤯")
      }
      XCTAssertEqual(url.serialized(), "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Throw] Change of special-ness.
      XCTAssertThrowsSpecific(URLSetterError.changeOfSchemeSpecialness) {
        try url.setScheme("foo")
      }
      XCTAssertEqual(url.serialized(), "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Deviation] If there is content after the ":", the operation fails. The JS model silently discards it.
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme("http://foo/")
      }
      XCTAssertEqual(url.serialized(), "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // ":" is allowed as the final character, but not required.
      XCTAssertNoThrow(try url.setScheme("ws"))
      XCTAssertEqual(url.serialized(), "ws://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      XCTAssertNoThrow(try url.setScheme("https:"))
      XCTAssertEqual(url.serialized(), "https://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Deviation] Tabs and newlines are not ignored, cause setter to fail. The JS model ignores them.
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme("\th\nttp:")
      }
      XCTAssertEqual(url.serialized(), "https://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)
    }

    do {
      // [Throw] URL with credentials or port changing to scheme which does not allow them.
      var url = WebURL("http://user:pass@somehost/")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveCredentialsOrPort) {
        try url.setScheme("file")
      }
      XCTAssertNoThrow(try url.setScheme("https"))
      XCTAssertEqual(url.serialized(), "https://user:pass@somehost/")
      XCTAssertURLIsIdempotent(url)

      url = WebURL("http://somehost:8080/")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveCredentialsOrPort) {
        try url.setScheme("file")
      }
      XCTAssertNoThrow(try url.setScheme("https"))
      XCTAssertEqual(url.serialized(), "https://somehost:8080/")
      XCTAssertURLIsIdempotent(url)
    }

    do {
      // [Throw] URL with empty hostname changing to scheme which does not allow them.
      var url = WebURL("file:///")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveEmptyHostname) {
        try url.setScheme("http")
      }
      XCTAssertNoThrow(try url.setScheme("file"))
      XCTAssertEqual(url.serialized(), "file:///")
      XCTAssertURLIsIdempotent(url)
    }
  }

  /// Tests the Swift model 'username' property.
  ///
  /// The Swift model deviates from the JS model in that it presents empty/not present usernames as 'nil'.
  ///
  func testUsername() {

    // [Deviation] Empty usernames are entirely removed (including separator),
    //             therefore the Swift model returns 'nil' to mean 'not present'.
    var url = WebURL("http://example.com/")!
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.username = "some username"
    XCTAssertEqual(url.username, "some%20username")
    XCTAssertEqual(url.serialized(), "http://some%20username@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting the empty string is the same as setting 'nil'.
    url.username = ""
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.username = "some username"
    XCTAssertEqual(url.username, "some%20username")
    XCTAssertEqual(url.serialized(), "http://some%20username@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting 'nil' is the same as setting the empty string.
    url.username = nil
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Setting credentials when the scheme does not allow them.
    url = WebURL("file://somehost/p1/p2")!
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized(), "file://somehost/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setUsername("user") }
    XCTAssertEqual(url.serialized(), "file://somehost/p1/p2")
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'password' property.
  ///
  /// The Swift model deviates from the JS model in that it presents empty/not present passwords as 'nil'.
  ///
  func testPassword() {

    // [Deviation] Empty passwords are entirely removed (including separator),
    //             therefore the Swift model returns 'nil' to mean 'not present'.
    var url = WebURL("http://example.com/")!
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.password = "🤫"
    XCTAssertEqual(url.password, "%F0%9F%A4%AB")
    XCTAssertEqual(url.serialized(), "http://:%F0%9F%A4%AB@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting the empty string is the same as setting 'nil'.
    url.password = ""
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.password = "🤫"
    XCTAssertEqual(url.password, "%F0%9F%A4%AB")
    XCTAssertEqual(url.serialized(), "http://:%F0%9F%A4%AB@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting the 'nil' is the same as setting the empty string.
    url.password = nil
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Throw]: Setting credentials when the scheme does not allow them.
    url = WebURL("file://somehost/p1/p2")!
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized(), "file://somehost/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setPassword("pass") }
    XCTAssertEqual(url.serialized(), "file://somehost/p1/p2")
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'hostname' property.
  ///
  /// The Swift model deviates from the JS model in that it does not trim or filter the new value when setting, can represent not-present hosts as 'nil', and supports
  /// setting hosts to 'nil'.
  ///
  func testHostname() {

    // [Deviation] Hostname is not trimmed; invalid host code points such as "?", "#", or ":" cause the setter to fail.
    var url = WebURL("http://example.com/")!
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("hello?") }
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("hello#") }
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("hello:99") }
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Hostname is not filtered. Tabs and newlines are invalid host code points, cause setter to fail.
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("\thel\nlo") }
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Swift model can distinguish between empty and not-present hostnames.
    XCTAssertNil(WebURL("unix:/some/path")!.hostname)
    XCTAssertEqual(WebURL("unix:///some/path")!.hostname, "")

    // [Deviation] Swift model allows setting hostname to nil (removing it, not just making it empty).
    // Special schemes do not allow 'nil' hostnames.
    XCTAssertEqual(url.scheme, "http")
    XCTAssertEqual(url.hostKind, .domain)
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized(), "http://example.com/")
    XCTAssertEqual(url.hostKind, .domain)
    XCTAssertURLIsIdempotent(url)

    // 'file' allows empty hostnames, but not 'nil' hostnames.
    url = WebURL("file:///some/path")!
    XCTAssertEqual(url.hostname, "")
    XCTAssertEqual(url.hostKind, .empty)
    XCTAssertEqual(url.scheme, "file")
    XCTAssertEqual(url.serialized(), "file:///some/path")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized(), "file:///some/path")
    XCTAssertEqual(url.hostKind, .empty)
    XCTAssertURLIsIdempotent(url)

    // Non-special schemes allow 'nil' hostnames.
    url = WebURL("unix:///some/path")!
    XCTAssertEqual(url.hostKind, .empty)
    XCTAssertNoThrow(try url.setHostname(String?.none))
    XCTAssertNil(url.hostKind)
    XCTAssertEqual(url.serialized(), "unix:/some/path")
    XCTAssertURLIsIdempotent(url)
    // But not if they already have credentials or ports.
    url = WebURL("unix://user:pass@example/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.username, "user")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized(), "unix://user:pass@example/some/path")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)

    url = WebURL("unix://example:99/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.port, 99)
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized(), "unix://example:99/some/path")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)
    // When setting a hostname to/from 'nil', we may need to add/remove a path sigil.
    do {
      func check_has_path_sigil(url: WebURL) {
        XCTAssertEqual(url.serialized(), "web+demo:/.//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .path)
        XCTAssertEqual(url.hostname, nil)
        XCTAssertEqual(url.hostKind, nil)
        XCTAssertEqual(url.path, "//not-a-host/test")
        XCTAssertURLIsIdempotent(url)
      }
      func check_has_auth_sigil(url: WebURL, hostname: String) {
        XCTAssertEqual(url.serialized(), "web+demo://\(hostname)//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .authority)
        XCTAssertEqual(url.hostname, hostname)
        XCTAssertEqual(url.hostKind, hostname.isEmpty ? .empty : .opaque)
        XCTAssertEqual(url.path, "//not-a-host/test")
        XCTAssertURLIsIdempotent(url)
      }
      // Start with a 'nil' host, path sigil.
      var test_url = WebURL("web+demo:/.//not-a-host/test")!
      check_has_path_sigil(url: test_url)
      // Switch to a non-empty host. We should gain an authority sigil.
      test_url.hostname = "host"
      check_has_auth_sigil(url: test_url, hostname: "host")
      // Switch to an empty host. We should still have an authority sigil.
      test_url.hostname = ""
      check_has_auth_sigil(url: test_url, hostname: "")
      // Switch to a 'nil' host. We should change the authority sigil to a path sigil.
      test_url.hostname = nil
      check_has_path_sigil(url: test_url)
    }

    // [Throw] Cannot set hostname on URLs with opaque paths.
    url = WebURL("mailto:bob")!
    XCTAssertNil(url.hostname)
    XCTAssertNil(url.hostKind)
    XCTAssertTrue(url.hasOpaquePath)
    XCTAssertEqual(url.serialized(), "mailto:bob")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetHostWithOpaquePath) {
      try url.setHostname("somehost")
    }
    XCTAssertEqual(url.serialized(), "mailto:bob")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Cannot set empty hostname on special schemes.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.hostKind, .domain)
    XCTAssertEqual(url.serialized(), "http://example.com/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname("")
    }
    XCTAssertEqual(url.serialized(), "http://example.com/p1/p2")
    XCTAssertEqual(url.hostKind, .domain)
    XCTAssertURLIsIdempotent(url)

    // [Throw] Cannot set empty hostname if the URL contains credentials or port.
    url = WebURL("foo://user@example.com/p1/p2")!
    XCTAssertEqual(url.username, "user")
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertEqual(url.serialized(), "foo://user@example.com/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname("")
    }
    XCTAssertEqual(url.serialized(), "foo://user@example.com/p1/p2")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)

    url = WebURL("foo://example.com:8080/p1/p2")!
    XCTAssertEqual(url.port, 8080)
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertEqual(url.serialized(), "foo://example.com:8080/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname("")
    }
    XCTAssertEqual(url.serialized(), "foo://example.com:8080/p1/p2")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)

    // [Throw] Invalid hostnames.
    url = WebURL("foo://example.com/")!
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertEqual(url.serialized(), "foo://example.com/")
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("@") }
    XCTAssertEqual(url.serialized(), "foo://example.com/")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("/a/b/c") }
    XCTAssertEqual(url.serialized(), "foo://example.com/")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("[:::]") }
    XCTAssertEqual(url.serialized(), "foo://example.com/")
    XCTAssertEqual(url.hostKind, .opaque)
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'port' property.
  ///
  /// The Swift model deviates from the JS model in that it takes an `Int?` rather than a string.
  ///
  func testPort() {

    // [Throw] Adding a port to a URL which does not allow them.
    var url = WebURL("file://somehost/p1/p2")!
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setPort(99) }
    XCTAssertEqual(url.serialized(), "file://somehost/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Setting a port to a non-valid UInt16 value.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertThrowsSpecific(URLSetterError.portValueOutOfBounds) { try url.setPort(-99) }
    XCTAssertEqual(url.serialized(), "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)
    XCTAssertThrowsSpecific(URLSetterError.portValueOutOfBounds) { try url.setPort(Int(UInt32.max)) }
    XCTAssertEqual(url.serialized(), "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Non-present port is represented as 'nil', rather than empty string.
    XCTAssertNil(url.port)
    // Set the port to a non-nil value.
    XCTAssertNoThrow(try url.setPort(42))
    XCTAssertEqual(url.port, 42)
    XCTAssertEqual(url.serialized(), "http://example.com:42/p1/p2")
    XCTAssertURLIsIdempotent(url)
    // And back to nil.
    XCTAssertNoThrow(try url.setPort(nil))
    XCTAssertNil(url.port)
    XCTAssertEqual(url.serialized(), "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'path' property.
  ///
  /// The Swift model deviates from the JS model in that it does not filter the new value when setting.
  ///
  func testPath() {

    // [Throw] Cannot modify an opaque path.
    var url = WebURL("mailto:bob")!
    XCTAssertEqual(url.path, "bob")
    XCTAssertTrue(url.hasOpaquePath)
    XCTAssertThrowsSpecific(URLSetterError.cannotModifyOpaquePath) { try url.setPath("frank") }
    XCTAssertEqual(url.serialized(), "mailto:bob")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Tabs and newlines are not trimmed.
    url = WebURL("file:///hello/world?someQuery")!
    XCTAssertNoThrow(try url.setPath("\t\n\t"))
    XCTAssertEqual(url.path, "/%09%0A%09")
    XCTAssertEqual(url.serialized(), "file:///%09%0A%09?someQuery")
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'query' property.
  ///
  /// The Swift model deviates from the JS model in that it does not trim the leading "?" or filter the new value when setting. It is also able to distinguish between
  /// not-present and empty query strings using 'nil'.
  ///
  func testQuery() {

    // [Deviation] The Swift model does not include the leading "?" in the getter, uses 'nil' to mean 'not present'.
    var url = WebURL("http://example.com/hello")!
    XCTAssertEqual(url.serialized(), "http://example.com/hello")
    XCTAssertNil(url.query)

    url.query = ""
    XCTAssertEqual(url.serialized(), "http://example.com/hello?")
    XCTAssertEqual(url.query, "")
    XCTAssertURLIsIdempotent(url)

    url.query = "a=b&c=d"
    XCTAssertEqual(url.serialized(), "http://example.com/hello?a=b&c=d")
    XCTAssertEqual(url.query, "a=b&c=d")
    XCTAssertURLIsIdempotent(url)

    url.query = nil
    XCTAssertEqual(url.serialized(), "http://example.com/hello")
    XCTAssertNil(url.query)
    XCTAssertURLIsIdempotent(url)

    // [Deviation] The Swift model does not trim the leading "?" from the new value when setting.
    url.query = "?e=f&g=h"
    XCTAssertEqual(url.serialized(), "http://example.com/hello??e=f&g=h")
    XCTAssertEqual(url.query, "?e=f&g=h")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Newlines and tabs are not filtered.
    url.query = "\tso\nmething"
    XCTAssertEqual(url.serialized(), "http://example.com/hello?%09so%0Amething")
    XCTAssertEqual(url.query, "%09so%0Amething")
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'fragment' property.
  ///
  /// The Swift model deviates from the JS model in that it does not trim the leading "#" or filter the new value when setting. It is also able to distinguish between
  /// not-present and empty fragment strings using 'nil'.
  ///
  func testFragment() {

    // [Deviation]: The Swift model does not include the leading "#" in the getter, uses 'nil' to mean 'not present'.
    var url = WebURL("http://example.com/hello")!
    XCTAssertEqual(url.serialized(), "http://example.com/hello")
    XCTAssertNil(url.fragment)

    url.fragment = ""
    XCTAssertEqual(url.serialized(), "http://example.com/hello#")
    XCTAssertEqual(url.fragment, "")
    XCTAssertURLIsIdempotent(url)

    url.fragment = "test"
    XCTAssertEqual(url.serialized(), "http://example.com/hello#test")
    XCTAssertEqual(url.fragment, "test")
    XCTAssertURLIsIdempotent(url)

    url.fragment = nil
    XCTAssertEqual(url.serialized(), "http://example.com/hello")
    XCTAssertNil(url.fragment)
    XCTAssertURLIsIdempotent(url)

    // [Deviation]: The Swift model does not trim the leading "#" from the new value when setting.
    url.fragment = "#test"
    XCTAssertEqual(url.serialized(), "http://example.com/hello##test")
    XCTAssertEqual(url.fragment, "#test")
    XCTAssertURLIsIdempotent(url)

    // [Deviation]: Newlines and tabs are not filtered.
    url.fragment = "\tso\nmething"
    XCTAssertEqual(url.serialized(), "http://example.com/hello#%09so%0Amething")
    XCTAssertEqual(url.fragment, "%09so%0Amething")
    XCTAssertURLIsIdempotent(url)
  }
}

extension WebURLTests {

  func testSerializedExcludingFragment() {
    do {
      let url = WebURL("http://example.com/some/path?and&a&query#withAFragment")!
      XCTAssertEqual(url.serialized(), "http://example.com/some/path?and&a&query#withAFragment")
      XCTAssertEqual(url.serialized(excludingFragment: true), "http://example.com/some/path?and&a&query")
    }
    // Fragment with a bunch of extra '#'s.
    do {
      let url = WebURL("http://example.com/some/path?and&a&query######withAFragment")!
      XCTAssertEqual(url.serialized(), "http://example.com/some/path?and&a&query######withAFragment")
      XCTAssertEqual(url.serialized(excludingFragment: true), "http://example.com/some/path?and&a&query")
    }
    // No fragment.
    do {
      let url = WebURL("http://example.com/some/path?and&a&query")!
      XCTAssertEqual(url.serialized(), "http://example.com/some/path?and&a&query")
      XCTAssertEqual(url.serialized(excludingFragment: true), "http://example.com/some/path?and&a&query")
    }
  }

  func testPortOrKnownDefault() {
    // Special schemes.
    do {
      let url = WebURL("file:///usr/bin/swift")!
      XCTAssertEqual(url.serialized(), "file:///usr/bin/swift")
      XCTAssertNil(url.port)
      XCTAssertNil(url.portOrKnownDefault)
    }
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqual(url.serialized(), "http://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 80)

      url.port = 999
      XCTAssertEqual(url.serialized(), "http://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("ws://example.com/")!
      XCTAssertEqual(url.serialized(), "ws://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 80)

      url.port = 999
      XCTAssertEqual(url.serialized(), "ws://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("https://example.com/")!
      XCTAssertEqual(url.serialized(), "https://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 443)

      url.port = 999
      XCTAssertEqual(url.serialized(), "https://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("wss://example.com/")!
      XCTAssertEqual(url.serialized(), "wss://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 443)

      url.port = 999
      XCTAssertEqual(url.serialized(), "wss://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("ftp://example.com/")!
      XCTAssertEqual(url.serialized(), "ftp://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 21)

      url.port = 999
      XCTAssertEqual(url.serialized(), "ftp://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    // Non-special scheme.
    do {
      var url = WebURL("foo://example.com/")!
      XCTAssertEqual(url.serialized(), "foo://example.com/")
      XCTAssertNil(url.port)
      XCTAssertNil(url.portOrKnownDefault)

      url.port = 999
      XCTAssertEqual(url.serialized(), "foo://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
  }
}

extension WebURLTests {

  /// Tests that URL setters do not inadvertently create strings that would be re-parsed as URLs with opaque paths.
  ///
  /// There are 2 situations where this could happen:
  ///
  /// 1. Setting a `nil` host when there is no path
  /// 2. Setting an empty path when there is no host
  ///
  func testDoesNotCreateURLsWithOpaquePaths() {

    // Check that we require a path in order to remove a host.

    do {  // Remove hostname with no path present. Must fail.
      var url = WebURL("foo://somehost")!
      XCTAssertEqual(url.serialized(), "foo://somehost")
      XCTAssertEqual(url.path, "")
      XCTAssertEqual(url.hostname, "somehost")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertThrowsSpecific(URLSetterError.cannotRemoveHostnameWithoutPath) {
        try url.setHostname(String?.none)
      }

      XCTAssertEqual(url.serialized(), "foo://somehost")
      XCTAssertURLIsIdempotent(url)
    }
    do {  // Remove hostname with path present. Succeeds.
      var url = WebURL("foo://somehost/bar")!
      XCTAssertEqual(url.serialized(), "foo://somehost/bar")
      XCTAssertEqual(url.path, "/bar")
      XCTAssertEqual(url.hostname, "somehost")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertNoThrow(try url.setHostname(String?.none))

      XCTAssertEqual(url.serialized(), "foo:/bar")
      XCTAssertEqual(url.path, "/bar")
      XCTAssertNil(url.hostname)
      XCTAssertFalse(url.hasOpaquePath)
      XCTAssertURLIsIdempotent(url)
    }

    // Check that we require a host in order to remove a path.
    // Rather than throw an error, removing a path from a host-less URL sets a root path.

    do {  // Set empty path via setter with no hostname present. Sets root path.
      var url = WebURL("foo:/hello/world?someQuery")!
      XCTAssertEqual(url.serialized(), "foo:/hello/world?someQuery")
      XCTAssertEqual(url.path, "/hello/world")
      XCTAssertNil(url.hostname)
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertNoThrow(try url.setPath(""))

      XCTAssertEqual(url.serialized(), "foo:/?someQuery")
      XCTAssertEqual(url.path, "/")
      XCTAssertNil(url.hostname)
      XCTAssertFalse(url.hasOpaquePath)
      XCTAssertURLIsIdempotent(url)
    }
    do {  // Set empty path via .pathComponents with no hostname present. Sets root path.
      var url = WebURL("foo:/hello/world?someQuery")!
      XCTAssertEqual(url.serialized(), "foo:/hello/world?someQuery")
      XCTAssertEqual(url.path, "/hello/world")
      XCTAssertNil(url.hostname)
      XCTAssertFalse(url.hasOpaquePath)

      let urlWithNoPath = WebURL("bar://somehost?anotherQuery")!
      XCTAssertEqual(urlWithNoPath.serialized(), "bar://somehost?anotherQuery")
      XCTAssertEqual(urlWithNoPath.path, "")
      XCTAssertEqual(urlWithNoPath.hostname, "somehost")
      XCTAssertFalse(url.hasOpaquePath)
      XCTAssertEqualElements(urlWithNoPath.pathComponents, [])
      XCTAssertEqual(urlWithNoPath.pathComponents.count, 0)

      url.pathComponents = urlWithNoPath.pathComponents

      XCTAssertEqual(url.serialized(), "foo:/?someQuery")
      XCTAssertEqual(url.path, "/")
      XCTAssertNil(url.hostname)
      XCTAssertFalse(url.hasOpaquePath)
      XCTAssertURLIsIdempotent(url)
    }
    do {  // Set empty path with hostname present. Sets empty path.
      var url = WebURL("foo://somehost/bar?someQuery")!
      XCTAssertEqual(url.serialized(), "foo://somehost/bar?someQuery")
      XCTAssertEqual(url.path, "/bar")
      XCTAssertEqual(url.hostname, "somehost")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertNoThrow(try url.setPath(""))

      XCTAssertEqual(url.serialized(), "foo://somehost?someQuery")
      XCTAssertEqual(url.path, "")
      XCTAssertEqual(url.hostname, "somehost")
      XCTAssertFalse(url.hasOpaquePath)
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testJSModelSetters() {
    // Check that 'pathname' setter does not remove leading slashes.
    do {
      var x = WebURL("sc://x?hello")!.jsModel
      XCTAssertEqual(x.href, "sc://x?hello")
      XCTAssertEqual(x.pathname, "")
      x.pathname = #"/"#
      XCTAssertEqual(x.href, "sc://x/?hello")
      XCTAssertEqual(x.pathname, "/")
      x.pathname = #"/s"#
      XCTAssertEqual(x.href, "sc://x/s?hello")
      XCTAssertEqual(x.pathname, "/s")
      x.pathname = #""#
      XCTAssertEqual(x.href, "sc://x?hello")
      XCTAssertEqual(x.pathname, "")
    }
  }
}


// --------------------------------------------
// MARK: - Host and Origin
// --------------------------------------------


extension WebURLTests {

  func testHost() {

    // In special URLs, all non-IP hostnames are domains.
    test: do {
      let url = WebURL("http://example.com/aPath?aQuery#andFragment, too")
      guard case .domain(let domain) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
      XCTAssertEqual(domain.serialized, "example.com")
      XCTAssertFalse(domain.isIDN)
    }
    test: do {
      let url = WebURL("http://nodots/aPath?aQuery#andFragment, too")
      guard case .domain(let domain) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
      XCTAssertEqual(domain.serialized, "nodots")
      XCTAssertFalse(domain.isIDN)
    }

    // In special URLs, Unicode hostnames are validated and normalized using IDNA.
    test: do {
      var url = WebURL("http://💩.com/foo")
      guard case .domain(let domain) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
      XCTAssertEqual(domain.serialized, "xn--ls8h.com")
      XCTAssertTrue(domain.isIDN)

      url = WebURL("http://www.foo。bar.com/foo")
      guard case .domain(let domain2) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
      XCTAssertEqual(domain2.serialized, "www.foo.bar.com")
      XCTAssertFalse(domain2.isIDN)

      url = WebURL("http://xn--caf-dma.com/foo")
      guard case .domain(let domain3) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
      XCTAssertEqual(domain3.serialized, "xn--caf-dma.com")
      XCTAssertTrue(domain3.isIDN)

      url = WebURL("http://xn--cafe-dma.com/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("xn--cafe-dma.com", scheme: "http"))

      url = WebURL("http://xn--cafe-yvc.com/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("xn--cafe-yvc.com", scheme: "http"))

      url = WebURL("http://has a space.com/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("has a space.com", scheme: "http"))
    }

    // Special URLs detect IPv4 addresses, including after IDNA.
    test: do {
      var url = WebURL("http://11.173.240.13/foo")
      guard case .ipv4Address(IPv4Address(octets: (11, 173, 240, 13))) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("http://0xbadf00d/foo")
      guard case .ipv4Address(IPv4Address(octets: (11, 173, 240, 13))) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("http://0x𝟕f.1/foo")
      guard case .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("http://11.173.240.13.4/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("11.173.240.13.4", scheme: "http"))
    }

    // In non-special URLs, all non-IP hostnames are opaque strings.
    test: do {
      let url = WebURL("non-special://example.com/foo")
      guard case .opaque("example.com") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
    }

    // In non-special URLs, Unicode hostnames are percent-encoded.
    // Other invalid characters are rejected.
    test: do {
      var url = WebURL("foo://💩.com/foo")
      guard case .opaque("%F0%9F%92%A9.com") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://www.foo。bar.com/foo")
      guard case .opaque("www.foo%E3%80%82bar.com") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://xn--cafe-dma.com/foo")
      guard case .opaque("xn--cafe-dma.com") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://xn--cafe-yvc.com/foo")
      guard case .opaque("xn--cafe-yvc.com") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://has a space.com/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("has a space.com", scheme: "foo"))
    }

    // Non-special URLs do not detect IPv4 addresses.
    test: do {
      var url = WebURL("foo://11.173.240.13/foo")
      guard case .opaque("11.173.240.13") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://0xbadf00d/foo")
      guard case .opaque("0xbadf00d") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://0x𝟕f.1/foo")
      guard case .opaque("0x%F0%9D%9F%95f.1") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
    }

    // Both special and non-special URLs detect IPv6 addresses.
    test: do {
      var url = WebURL("http://[::127.0.0.1]/foo")
      guard case .ipv6Address(IPv6Address(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("foo://[::127.0.0.1]/foo")
      guard case .ipv6Address(IPv6Address(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("http://[blahblahblah]/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("[blahblahblah]", scheme: "http"))

      url = WebURL("foo://[blahblahblah]/foo")
      guard case .none = url else {
        XCTFail("Unexpected URL: \(String(describing: url))")
        break test
      }
      XCTAssertNil(WebURL.Host("[blahblahblah]", scheme: "foo"))
    }

    // Special URLs interpret domains and IPv4 addresses through percent-encoding.
    test: do {
      var url = WebURL("http://www.foo%E3%80%82bar.com/foo")
      guard case .domain(let domain) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(domain.serialized, "www.foo.bar.com")
      XCTAssertFalse(domain.isIDN)

      url = WebURL("http://%F0%9F%92%A9.com/foo")
      guard case .domain(let domain2) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(domain2.serialized, "xn--ls8h.com")
      XCTAssertTrue(domain2.isIDN)

      url = WebURL("http://0x%F0%9D%9F%95f.1/foo")
      guard case .ipv4Address(IPv4Address(octets: (127, 0, 0, 1))) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
    }

    // Only File and non-special URLs may have empty hostnames.
    test: do {
      var url = WebURL("http:///foo")
      guard case .domain(let domain) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(domain.serialized, "foo")
      XCTAssertFalse(domain.isIDN)
      XCTAssertNil(WebURL.Host("", scheme: "http"))

      url = WebURL("ftp:///foo")
      guard case .domain(let domain2) = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(domain2.serialized, "foo")
      XCTAssertFalse(domain2.isIDN)
      XCTAssertNil(WebURL.Host("", scheme: "ftp"))

      url = WebURL("file:///foo")
      guard case .empty = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      url = WebURL("non-special:///foo")
      guard case .empty = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))
    }

    // Hosts which get IDNA-mapped to the empty string. Not allowed even in file URLs.
    test: do {
      let url = WebURL("foo://\u{AD}/bar")
      guard case .opaque("%C2%AD") = url?.host else {
        XCTFail("Unexpected host: \(String(describing: url?.host))")
        break test
      }
      XCTAssertEqual(url!.host, WebURL.Host(url!.hostname!, scheme: url!.scheme))

      XCTAssertNil(WebURL("file://\u{AD}/bar"))
      XCTAssertNil(WebURL("http://\u{AD}/bar"))
    }

    // Localhost is normalized to empty in file URLs, to a lowercase domain in other special URLs,
    // and not at all in non-special URLs.
    // WebURL.Host.init?(String) equivalence is tested in `HostTests.testParsing`.
    do {
      XCTAssertEqual(WebURL("file://localhost/foo")?.host, .empty)
      XCTAssertEqual(WebURL("file://loCAlhost/foo")?.host, .empty)
      XCTAssertEqual(WebURL("file://loc%61lhost/foo")?.host, .empty)
      XCTAssertEqual(WebURL("file://loC𝐀𝐋𝐇𝐨𝐬𝐭/foo")?.host, .empty)

      let localhostDomain = WebURL.Domain("localhost")!
      XCTAssertEqual(WebURL("http://localhost/foo")?.host, .domain(localhostDomain))
      XCTAssertEqual(WebURL("http://loCAlhost/foo")?.host, .domain(localhostDomain))
      XCTAssertEqual(WebURL("http://loc%61lhost/foo")?.host, .domain(localhostDomain))
      XCTAssertEqual(WebURL("http://loC𝐀𝐋𝐇𝐨𝐬𝐭/foo")?.host, .domain(localhostDomain))

      XCTAssertEqual(WebURL("foo://localhost/foo")?.host, .opaque("localhost"))
      XCTAssertEqual(WebURL("foo://loCAlhost/foo")?.host, .opaque("loCAlhost"))
      XCTAssertEqual(WebURL("foo://loc%61lhost/foo")?.host, .opaque("loc%61lhost"))
      XCTAssertEqual(
        WebURL("foo://loC𝐀𝐋𝐇𝐨𝐬𝐭/foo")?.host,
        .opaque("loC%F0%9D%90%80%F0%9D%90%8B%F0%9D%90%87%F0%9D%90%A8%F0%9D%90%AC%F0%9D%90%AD")
      )
    }

    // Path-only and URLs with opaque paths do not have hosts.
    do {
      let url = WebURL("foo:/path/only")!
      XCTAssertNil(url.hostKind)
      if case .none = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
        XCTAssertFalse(url.hasOpaquePath)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }
    do {
      let url = WebURL("foo:some non-path")!
      XCTAssertNil(url.hostKind)
      if case .none = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
        XCTAssertTrue(url.hasOpaquePath)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }
  }

  func testOrigin() {

    // Special URLs return non-opaque origins.
    // Are same-origin WRT other paths, queries, fragments at... err... the same origin.
    if let origin = WebURL("https://example.com/index.html")?.origin {
      XCTAssertEqual(origin.serialized, "https://example.com")
      XCTAssertFalse(origin.isOpaque)
      XCTAssertEqual(origin, WebURL("https://example.com:443/some_resource.png?the_answer=42#test")?.origin)
      XCTAssertNotEqual(origin, WebURL("https://test.com/")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // Port number included if not the default. Different port numbers are not same-origin.
    if let origin = WebURL("http://localhost:8080/index.html")?.origin {
      XCTAssertEqual(origin.serialized, "http://localhost:8080")
      XCTAssertFalse(origin.isOpaque)
      XCTAssertEqual(origin, WebURL("http://localhost:8080/some_resource.png?query=true#frag-it")?.origin)
      XCTAssertNotEqual(origin, WebURL("http://localhost:80/")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // 'blob:' URLs with opaque paths have the same origin as the URL parsed from their paths.
    if let origin = WebURL("blob:https://example.com:443/index.html")?.origin {
      XCTAssertEqual(origin.serialized, "https://example.com")
      XCTAssertFalse(origin.isOpaque)
      XCTAssertEqual(origin, WebURL("https://example.com/some_resource.txt?q=🐟#🦆=👹")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // 'blob:' URLs with non-opaque paths are always opaque.
    if let origin = WebURL("blob:///https://example.com:443/index.html")?.origin {
      XCTAssertEqual(origin.serialized, "null")
      XCTAssertTrue(origin.isOpaque)
      XCTAssertNotEqual(origin, origin)
      XCTAssertNotEqual(origin, WebURL("blob:https://example.com")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // 'blob:' URLs with opaque paths have opaque origins if their path is not a valid URL string.
    if let origin = WebURL("blob:this is not a URL")?.origin {
      XCTAssertEqual(origin.serialized, "null")
      XCTAssertTrue(origin.isOpaque)
      XCTAssertNotEqual(origin, origin)
      XCTAssertNotEqual(origin, WebURL("blob:also not a URL")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // 'file' URLs have opaque origins.
    if let origin = WebURL("file:///usr/bin/swift")?.origin {
      XCTAssertEqual(origin.serialized, "null")
      XCTAssertTrue(origin.isOpaque)
      XCTAssertNotEqual(origin, origin)
      XCTAssertNotEqual(origin, WebURL("file:///var/tmp/somefile")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // Opaque hosts are not equal to each other.
    do {
      let myURL = WebURL("foo://exampleHost:4567/")!
      XCTAssertTrue(myURL.origin.isOpaque)
      XCTAssertFalse(myURL.origin == myURL.origin)

      var seenOrigins: Set = [myURL.origin]
      XCTAssertFalse(seenOrigins.contains(myURL.origin))
      XCTAssertTrue(seenOrigins.insert(myURL.origin).inserted)
      XCTAssertTrue(seenOrigins.insert(myURL.origin).inserted)
      XCTAssertTrue(seenOrigins.insert(myURL.origin).inserted)
      XCTAssertFalse(seenOrigins.contains(myURL.origin))
    }
  }
}

extension WebURLTests {

  func testIDNA() {
    let hosts: [(given: String, ascii: String?, kind: WebURL.HostKind?)] = [
      ("www.foo。bar.com", "www.foo.bar.com", .domain),
      ("GOO 　goo.com", nil, nil),
      ("💩.com", "xn--ls8h.com", .domainWithIDN),
      ("hello.💩.com", "hello.xn--ls8h.com", .domainWithIDN),
      ("faß.api.你好你好.com", "xn--fa-hia.api.xn--6qqa088eba.com", .domainWithIDN),
      ("faß.ExAmPlE", "xn--fa-hia.example", .domainWithIDN),
      ("0x𝟕f.1", "127.0.0.1", .ipv4Address),
      ("０Ｘｃ０．０２５０．０１", "192.168.0.1", .ipv4Address),
      ("ₓn--fa-hia.example", "xn--fa-hia.example", .domainWithIDN),
      ("☃", "xn--n3h", .domainWithIDN),
      ("xn--n3h", "xn--n3h", .domainWithIDN),
      ("你好你好", "xn--6qqa088eba", .domainWithIDN),
      ("xn--6qqa088eba", "xn--6qqa088eba", .domainWithIDN),
      ("a.أهلا.com", "a.xn--igbi0gl.com", .domainWithIDN),
      ("a.هذهالكلمة.com", "a.xn--mgbet1febhkb.com", .domainWithIDN),
      ("xn--b1abfaaepdrnnbgefbadotcwatmq2g4l", "xn--b1abfaaepdrnnbgefbadotcwatmq2g4l", .domainWithIDN),
      ("xn--bbb", "xn--bbb", .domainWithIDN),
      ("caf\u{00E9}.fr", "xn--caf-dma.fr", .domainWithIDN),
      ("cafe\u{0301}.fr", "xn--caf-dma.fr", .domainWithIDN),
      ("xn--cafe-yvc.fr", nil, nil),
      ("a.b.c.xn--pokxncvks", nil, nil),
      // Deviation character.
      ("xn--1ch.com", "xn--1ch.com", .domainWithIDN),
      // Percent-encoded unicode.
      ("%F0%9F%92%A9", "xn--ls8h", .domainWithIDN),
      // Percent-encoded Punycode.
      ("%78n--", nil, nil),
      ("%58n--", nil, nil),
      ("x%6e--", nil, nil),
      ("%58%6E--fa-hia", "xn--fa-hia", .domainWithIDN),
      ("%58%6E-%2Df%61-hi%61", "xn--fa-hia", .domainWithIDN),
      ("%58%6E-%2Df%41-hi%41", "xn--fa-hia", .domainWithIDN),
      // Percent-encoded "ₓ" in the ACE prefix.
      ("%E2%82%93n--n3h", "xn--n3h", .domainWithIDN),
      ("%E2%82%93n%2D%2dn3h", "xn--n3h", .domainWithIDN),
    ]

    for (givenHostname, expectedURLHost, expectedHostKind) in hosts {

      // Check that we can parse the input hostname in a URL.
      // The hostname of the result should be the expected ASCII IDN (or the operation should fail).
      switch WebURL("http://\(givenHostname)") {
      case .some(let parserResult):
        XCTAssertEqual(parserResult.hostname, expectedURLHost)
        XCTAssertEqual(parserResult.hostKind, expectedHostKind)
        XCTAssertURLIsIdempotent(parserResult)
      case .none:
        XCTAssertNil(expectedURLHost)
      }

      // Same should apply to the .hostname setter.
      var setterResult = WebURL("http://weburl/")!
      precondition(setterResult.serialized() == "http://weburl/")
      precondition(setterResult.hostKind == .domain)
      switch Result(catching: { try setterResult.setHostname(givenHostname) }) {
      case .success:
        XCTAssertEqual(setterResult.hostname, expectedURLHost)
        XCTAssertEqual(setterResult.hostKind, expectedHostKind)
        XCTAssertURLIsIdempotent(setterResult)
      case .failure:
        XCTAssertEqual(setterResult.serialized(), "http://weburl/")
        XCTAssertEqual(setterResult.hostKind, .domain)
        XCTAssertURLIsIdempotent(setterResult)
      }
    }
  }
}
