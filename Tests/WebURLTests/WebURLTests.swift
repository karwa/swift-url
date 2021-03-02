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
      XCTAssertEqual(original.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertEqual(original.scheme, "http")
    }
    // Scheme.
    url.scheme = "https"
    XCTAssertEqual(url.serialized, "https://example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.scheme, "https")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Username.
    url.username = "user"
    XCTAssertEqual(url.serialized, "http://user@example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.username, "user")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Password.
    url.password = "pass"
    XCTAssertEqual(url.serialized, "http://:pass@example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.password, "pass")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Hostname.
    url.hostname = "test.test"
    XCTAssertEqual(url.serialized, "http://test.test/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.hostname, "test.test")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Port.
    url.port = 8080
    XCTAssertEqual(url.serialized, "http://example.com:8080/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.port, 8080)
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Path.
    url.path = "/foo/bar/baz"
    XCTAssertEqual(url.serialized, "http://example.com/foo/bar/baz?c=d&e=f#gh")
    XCTAssertEqual(url.path, "/foo/bar/baz")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Query
    url.query = "foo=bar&baz=qux"
    XCTAssertEqual(url.serialized, "http://example.com/a/b?foo=bar&baz=qux#gh")
    XCTAssertEqual(url.query, "foo=bar&baz=qux")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
    url = original
    // Fragment
    url.fragment = "foo"
    XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#foo")
    XCTAssertEqual(url.fragment, "foo")
    XCTAssertURLIsIdempotent(url)
    checkOriginalHasNotChanged()
  }

  // Note: This is likely to be a bit fragile, since it relies on optimisations which might not happen at -Onone.
  //       For now, it works.

  /// Tests that setters on a uniquely referenced URL are performed in-place.
  ///
  func testCopyOnWrite_unique() {

    var url = WebURL("wss://user:pass@example.com:90/a/b?c=d&e=f#gh")!
    XCTAssertEqual(url.serialized, "wss://user:pass@example.com:90/a/b?c=d&e=f#gh")

    // All new values must be the same length, so we can be sure we have enough capacity.

    // Scheme.
    checkDoesNotCopy(&url) {
      $0.scheme = "ftp"
    }
    XCTAssertEqual(url.serialized, "ftp://user:pass@example.com:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Username.
    checkDoesNotCopy(&url) {
      $0.username = "resu"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:pass@example.com:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Password.
    checkDoesNotCopy(&url) {
      $0.password = "ssap"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@example.com:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Hostname.
    checkDoesNotCopy(&url) {
      $0.hostname = "moc.elpmaxe"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:90/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Port.
    checkDoesNotCopy(&url) {
      $0.port = 42
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:42/a/b?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Path
    checkDoesNotCopy(&url) {
      $0.path = "/j/k"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:42/j/k?c=d&e=f#gh")
    XCTAssertURLIsIdempotent(url)
    // Query
    checkDoesNotCopy(&url) {
      $0.query = "m=n&o=p"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:42/j/k?m=n&o=p#gh")
    XCTAssertURLIsIdempotent(url)
    // Fragment
    checkDoesNotCopy(&url) {
      $0.fragment = "zz"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:42/j/k?m=n&o=p#zz")
    XCTAssertURLIsIdempotent(url)
    // Chained modifying wrappers.
    checkDoesNotCopy(&url) {
      $0.jsModel.swiftModel.jsModel.swiftModel.jsModel.swiftModel.fragment = "aa"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:42/j/k?m=n&o=p#aa")
    XCTAssertURLIsIdempotent(url)
  }
}

// WebURL component tests.
//
// The behaviour of getters and setters are tested via the JS model according to the WPT test files.
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
      XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Throw] Change of special-ness.
      XCTAssertThrowsSpecific(URLSetterError.changeOfSchemeSpecialness) {
        try url.setScheme("foo")
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Deviation] If there is content after the ":", the operation fails. The JS model silently discards it.
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme("http://foo/")
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // ":" is allowed as the final character, but not required.
      XCTAssertNoThrow(try url.setScheme("ws"))
      XCTAssertEqual(url.serialized, "ws://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      XCTAssertNoThrow(try url.setScheme("https:"))
      XCTAssertEqual(url.serialized, "https://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Deviation] Tabs and newlines are not ignored, cause setter to fail. The JS model ignores them.
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme("\th\nttp:")
      }
      XCTAssertEqual(url.serialized, "https://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)
    }

    do {
      // [Throw] URL with credentials or port changing to scheme which does not allow them.
      var url = WebURL("http://user:pass@somehost/")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveCredentialsOrPort) {
        try url.setScheme("file")
      }
      XCTAssertNoThrow(try url.setScheme("https"))
      XCTAssertEqual(url.serialized, "https://user:pass@somehost/")
      XCTAssertURLIsIdempotent(url)

      url = WebURL("http://somehost:8080/")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveCredentialsOrPort) {
        try url.setScheme("file")
      }
      XCTAssertNoThrow(try url.setScheme("https"))
      XCTAssertEqual(url.serialized, "https://somehost:8080/")
      XCTAssertURLIsIdempotent(url)
    }

    do {
      // [Throw] URL with empty hostname changing to scheme which does not allow them.
      var url = WebURL("file:///")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveEmptyHostname) {
        try url.setScheme("http")
      }
      XCTAssertNoThrow(try url.setScheme("file"))
      XCTAssertEqual(url.serialized, "file:///")
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
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.username = "some username"
    XCTAssertEqual(url.username, "some%20username")
    XCTAssertEqual(url.serialized, "http://some%20username@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting the empty string is the same as setting 'nil'.
    url.username = ""
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.username = "some username"
    XCTAssertEqual(url.username, "some%20username")
    XCTAssertEqual(url.serialized, "http://some%20username@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting 'nil' is the same as setting the empty string.
    url.username = nil
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Setting credentials when the scheme does not allow them.
    url = WebURL("file://somehost/p1/p2")!
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized, "file://somehost/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setUsername("user") }
    XCTAssertEqual(url.serialized, "file://somehost/p1/p2")
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
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.password = "🤫"
    XCTAssertEqual(url.password, "%F0%9F%A4%AB")
    XCTAssertEqual(url.serialized, "http://:%F0%9F%A4%AB@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting the empty string is the same as setting 'nil'.
    url.password = ""
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    url.password = "🤫"
    XCTAssertEqual(url.password, "%F0%9F%A4%AB")
    XCTAssertEqual(url.serialized, "http://:%F0%9F%A4%AB@example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Setting the 'nil' is the same as setting the empty string.
    url.password = nil
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Throw]: Setting credentials when the scheme does not allow them.
    url = WebURL("file://somehost/p1/p2")!
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized, "file://somehost/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setPassword("pass") }
    XCTAssertEqual(url.serialized, "file://somehost/p1/p2")
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
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("hello#") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("hel:lo") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Hostname is not filtered. Tabs and newlines are invalid host code points, cause setter to fail.
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("\thel\nlo") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Swift model can distinguish between empty and not-present hostnames.
    XCTAssertNil(WebURL("unix:/some/path")!.hostname)
    XCTAssertEqual(WebURL("unix:///some/path")!.hostname, "")

    // [Deviation] Swift model allows setting hostname to nil (removing it, not just making it empty).
    // Special schemes do not allow 'nil' hostnames.
    XCTAssertEqual(url.scheme, "http")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // 'file' allows empty hostnames, but not 'nil' hostnames.
    url = WebURL("file:///some/path")!
    XCTAssertEqual(url.hostname, "")
    XCTAssertEqual(url.scheme, "file")
    XCTAssertEqual(url.serialized, "file:///some/path")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized, "file:///some/path")
    XCTAssertURLIsIdempotent(url)

    // Non-special schemes allow 'nil' hostnames.
    url = WebURL("unix:///some/path")!
    XCTAssertNoThrow(try url.setHostname(String?.none))
    XCTAssertEqual(url.serialized, "unix:/some/path")
    XCTAssertURLIsIdempotent(url)
    // But not if they already have credentials or ports.
    url = WebURL("unix://user:pass@example/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.username, "user")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized, "unix://user:pass@example/some/path")
    XCTAssertURLIsIdempotent(url)

    url = WebURL("unix://example:99/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.port, 99)
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized, "unix://example:99/some/path")
    XCTAssertURLIsIdempotent(url)
    // When setting a hostname to/from 'nil', we may need to add/remove a path sigil.
    do {
      func check_has_path_sigil(url: WebURL) {
        XCTAssertEqual(url.serialized, "web+demo:/.//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .path)
        XCTAssertEqual(url.hostname, nil)
        XCTAssertEqual(url.path, "//not-a-host/test")
        XCTAssertURLIsIdempotent(url)
      }
      func check_has_auth_sigil(url: WebURL, hostname: String) {
        XCTAssertEqual(url.serialized, "web+demo://\(hostname)//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .authority)
        XCTAssertEqual(url.hostname, hostname)
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

    // [Throw] Cannot set hostname on cannot-be-a-base URLs.
    url = WebURL("mailto:bob")!
    XCTAssertNil(url.hostname)
    XCTAssertTrue(url.cannotBeABase)
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetHostOnCannotBeABaseURL) {
      try url.setHostname("somehost")
    }
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Cannot set empty hostname on special schemes.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname("")
    }
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Cannot set empty hostname if the URL contains credentials or port.
    url = WebURL("foo://user@example.com/p1/p2")!
    XCTAssertEqual(url.username, "user")
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "foo://user@example.com/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname("")
    }
    XCTAssertEqual(url.serialized, "foo://user@example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    url = WebURL("foo://example.com:8080/p1/p2")!
    XCTAssertEqual(url.port, 8080)
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "foo://example.com:8080/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname("")
    }
    XCTAssertEqual(url.serialized, "foo://example.com:8080/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Invalid hostnames.
    url = WebURL("foo://example.com/")!
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "foo://example.com/")
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("@") }
    XCTAssertEqual(url.serialized, "foo://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("/a/b/c") }
    XCTAssertEqual(url.serialized, "foo://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname("[:::]") }
    XCTAssertEqual(url.serialized, "foo://example.com/")
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
    XCTAssertEqual(url.serialized, "file://somehost/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Setting a port to a non-valid UInt16 value.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertThrowsSpecific(URLSetterError.portValueOutOfBounds) { try url.setPort(-99) }
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)
    XCTAssertThrowsSpecific(URLSetterError.portValueOutOfBounds) { try url.setPort(Int(UInt32.max)) }
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Non-present port is represented as 'nil', rather than empty string.
    XCTAssertNil(url.port)
    // Set the port to a non-nil value.
    XCTAssertNoThrow(try url.setPort(42))
    XCTAssertEqual(url.port, 42)
    XCTAssertEqual(url.serialized, "http://example.com:42/p1/p2")
    XCTAssertURLIsIdempotent(url)
    // And back to nil.
    XCTAssertNoThrow(try url.setPort(nil))
    XCTAssertNil(url.port)
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)
  }

  /// Tests the Swift model 'path' property.
  ///
  /// The Swift model deviates from the JS model in that it does not filter the new value when setting.
  ///
  func testPath() {

    // [Throw] Cannot set path on cannot-be-a-base URLs.
    var url = WebURL("mailto:bob")!
    XCTAssertEqual(url.path, "bob")
    XCTAssertTrue(url.cannotBeABase)
    XCTAssertThrowsSpecific(URLSetterError.cannotSetPathOnCannotBeABaseURL) { try url.setPath("frank") }
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Tabs and newlines are not trimmed.
    url = WebURL("file:///hello/world?someQuery")!
    XCTAssertNoThrow(try url.setPath("\t\n\t"))
    XCTAssertEqual(url.path, "/%09%0A%09")
    XCTAssertEqual(url.serialized, "file:///%09%0A%09?someQuery")
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
    XCTAssertEqual(url.serialized, "http://example.com/hello")
    XCTAssertNil(url.query)

    url.query = ""
    XCTAssertEqual(url.serialized, "http://example.com/hello?")
    XCTAssertEqual(url.query, "")
    XCTAssertURLIsIdempotent(url)

    url.query = "a=b&c=d"
    XCTAssertEqual(url.serialized, "http://example.com/hello?a=b&c=d")
    XCTAssertEqual(url.query, "a=b&c=d")
    XCTAssertURLIsIdempotent(url)

    url.query = nil
    XCTAssertEqual(url.serialized, "http://example.com/hello")
    XCTAssertNil(url.query)
    XCTAssertURLIsIdempotent(url)

    // [Deviation] The Swift model does not trim the leading "?" from the new value when setting.
    url.query = "?e=f&g=h"
    XCTAssertEqual(url.serialized, "http://example.com/hello??e=f&g=h")
    XCTAssertEqual(url.query, "?e=f&g=h")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Newlines and tabs are not filtered.
    url.query = "\tso\nmething"
    XCTAssertEqual(url.serialized, "http://example.com/hello?%09so%0Amething")
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
    XCTAssertEqual(url.serialized, "http://example.com/hello")
    XCTAssertNil(url.fragment)

    url.fragment = ""
    XCTAssertEqual(url.serialized, "http://example.com/hello#")
    XCTAssertEqual(url.fragment, "")
    XCTAssertURLIsIdempotent(url)

    url.fragment = "test"
    XCTAssertEqual(url.serialized, "http://example.com/hello#test")
    XCTAssertEqual(url.fragment, "test")
    XCTAssertURLIsIdempotent(url)

    url.fragment = nil
    XCTAssertEqual(url.serialized, "http://example.com/hello")
    XCTAssertNil(url.fragment)
    XCTAssertURLIsIdempotent(url)

    // [Deviation]: The Swift model does not trim the leading "#" from the new value when setting.
    url.fragment = "#test"
    XCTAssertEqual(url.serialized, "http://example.com/hello##test")
    XCTAssertEqual(url.fragment, "#test")
    XCTAssertURLIsIdempotent(url)

    // [Deviation]: Newlines and tabs are not filtered.
    url.fragment = "\tso\nmething"
    XCTAssertEqual(url.serialized, "http://example.com/hello#%09so%0Amething")
    XCTAssertEqual(url.fragment, "%09so%0Amething")
    XCTAssertURLIsIdempotent(url)
  }
}

extension WebURLTests {

  func testSerializedExcludingFragment() {
    do {
      let url = WebURL("http://example.com/some/path?and&a&query#withAFragment")!
      XCTAssertEqual(url.serialized, "http://example.com/some/path?and&a&query#withAFragment")
      XCTAssertEqual(url.serializedExcludingFragment, "http://example.com/some/path?and&a&query")
    }
    // Fragment with a bunch of extra '#'s.
    do {
      let url = WebURL("http://example.com/some/path?and&a&query######withAFragment")!
      XCTAssertEqual(url.serialized, "http://example.com/some/path?and&a&query######withAFragment")
      XCTAssertEqual(url.serializedExcludingFragment, "http://example.com/some/path?and&a&query")
    }
    // No fragment.
    do {
      let url = WebURL("http://example.com/some/path?and&a&query")!
      XCTAssertEqual(url.serialized, "http://example.com/some/path?and&a&query")
      XCTAssertEqual(url.serializedExcludingFragment, "http://example.com/some/path?and&a&query")
    }
  }

  func testPortOrKnownDefault() {
    // Special schemes.
    do {
      let url = WebURL("file:///usr/bin/swift")!
      XCTAssertEqual(url.serialized, "file:///usr/bin/swift")
      XCTAssertNil(url.port)
      XCTAssertNil(url.portOrKnownDefault)
    }
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 80)

      url.port = 999
      XCTAssertEqual(url.serialized, "http://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("ws://example.com/")!
      XCTAssertEqual(url.serialized, "ws://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 80)

      url.port = 999
      XCTAssertEqual(url.serialized, "ws://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("https://example.com/")!
      XCTAssertEqual(url.serialized, "https://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 443)

      url.port = 999
      XCTAssertEqual(url.serialized, "https://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("wss://example.com/")!
      XCTAssertEqual(url.serialized, "wss://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 443)

      url.port = 999
      XCTAssertEqual(url.serialized, "wss://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    do {
      var url = WebURL("ftp://example.com/")!
      XCTAssertEqual(url.serialized, "ftp://example.com/")
      XCTAssertNil(url.port)
      XCTAssertEqual(url.portOrKnownDefault, 21)

      url.port = 999
      XCTAssertEqual(url.serialized, "ftp://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
    // Non-special scheme.
    do {
      var url = WebURL("foo://example.com/")!
      XCTAssertEqual(url.serialized, "foo://example.com/")
      XCTAssertNil(url.port)
      XCTAssertNil(url.portOrKnownDefault)

      url.port = 999
      XCTAssertEqual(url.serialized, "foo://example.com:999/")
      XCTAssertEqual(url.port, 999)
      XCTAssertEqual(url.portOrKnownDefault, 999)
    }
  }
}

extension WebURLTests {

  /// Tests that URL setters do not inadvertently create strings that would be re-parsed as 'cannot-be-a-base' URLs.
  ///
  /// There are 2 situations where this could happen:
  ///
  /// 1. Setting a `nil` host when there is no path
  /// 2. Setting an empty path when there is no host
  ///
  func testDoesNotCreateCannotBeABaseURLs() {

    // Check that we require a path in order to remove a host.
    var url = WebURL("foo://somehost")!
    XCTAssertEqual(url.serialized, "foo://somehost")
    XCTAssertEqual(url.path, "")
    XCTAssertNotNil(url.hostname)
    XCTAssertThrowsSpecific(URLSetterError.cannotRemoveHostnameWithoutPath) {
      try url.setHostname(String?.none)
    }
    XCTAssertEqual(url.serialized, "foo://somehost")
    XCTAssertURLIsIdempotent(url)

    // Check that we require a host in order to remove a path.

    // [Bug] This seems to be a bug in the standard, which our implementation also exhibits (yay for accuracy?).
    //       The path of non-special URLs can be set to empty, even if they don't have a host (path-only URLs).
    //       This makes them 'cannot-be-a-base' URLs, but without the flag. Re-parsing the URL sets the flag,
    //       but it means the set of operations which are allowed depends on how you got the URL (not idempotent).
    //       See: https://github.com/whatwg/url/issues/581

    url = WebURL("foo:/hello/world?someQuery")!
    XCTAssertEqual(url.serialized, "foo:/hello/world?someQuery")
    XCTAssertEqual(url.path, "/hello/world")
    XCTAssertNil(url.hostname)
    XCTAssertFalse(url.cannotBeABase)

    url.path = ""
    XCTAssertEqual(url.serialized, "foo:?someQuery")
    XCTAssertEqual(url.path, "")
    XCTAssertNil(url.hostname)
    XCTAssertFalse(url.cannotBeABase)
    XCTAssertTrue(WebURL(url.serialized)!.cannotBeABase)
    // XCTAssertURLIsIdempotent(url) - see comment above.

    url.path = "test"
    XCTAssertEqual(url.serialized, "foo:/test?someQuery")
    XCTAssertEqual(url.path, "/test")
    XCTAssertNil(url.hostname)
    XCTAssertFalse(url.cannotBeABase)
    XCTAssertURLIsIdempotent(url)
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


    // TODO [testing]: This test needs to be more comprehensive, and we need tests like this exercising all major
    // paths in all setters.

    // Checks what happens when a scheme change requires the port to be removed, and the resulting URL
    // has a different optimal storage type to the original (i.e. suddenly becomes less than 255 bytes).
    // It's such a niche case that we'd otherwise never see it.
    do {
      var url = WebURL(
        "ws://hostnamewhichtakesustotheedge:443?hellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellop"
      )!.jsModel
      switch url.storage {
      case .large(_): break
      default: XCTFail("Unexpected storage type")
      }
      url.scheme = "wss"
      switch url.storage {
      case .small(_): break
      default: XCTFail("Unexpected storage type")
      }
      XCTAssertEqual(
        url.description,
        "wss://hostnamewhichtakesustotheedge/?hellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellop"
      )
    }
  }
}


// MARK: - Host and Origin


extension WebURLTests {

  func testHost() {

    // Non-IP hostnames in special URLs are always domains.
    do {
      let url = WebURL("http://example.com/aPath?aQuery#andFragment, too")!
      if case .domain("example.com") = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }

    // Non-IP hostnames in non-special URLs are always opaque hostnames.
    do {
      let url = WebURL("foo://example.com/aPath?aQuery#andFragment, too")!
      if case .opaque("example.com") = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }

    // Special URLs detect IPv4 addresses.
    do {
      let url = WebURL("http://0xbadf00d/aPath?aQuery#andFragment, too")!
      if case .ipv4Address(.init(octets: (11, 173, 240, 13))) = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }
    // Non-special URLs do not.
    do {
      let url = WebURL("foo://11.173.240.13/aPath?aQuery#andFragment, too")!
      if case .opaque("11.173.240.13") = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }

    // Both special and non-special URLs detect IPv6 addresses.
    do {
      let url = WebURL("http://[::127.0.0.1]/aPath?aQuery#andFragment, too")!
      if case .ipv6Address(.init(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }
    do {
      let url = WebURL("foo://[::127.0.0.1]/aPath?aQuery#andFragment, too")!
      if case .ipv6Address(.init(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }

    // File and non-special URLs may have empty hostnames.
    do {
      let url = WebURL("file:///usr/bin/swift")!
      if case .empty = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
        XCTAssertEqual(url.host?.serialized, "")
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }
    do {
      let url = WebURL("foo:///some/path")!
      if case .empty = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
        XCTAssertEqual(url.host?.serialized, "")
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }

    // Path-only and cannot-be-a-base-path URLs do not have hosts.
    do {
      let url = WebURL("foo:/path/only")!
      if case .none = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
        XCTAssertFalse(url.cannotBeABase)
      } else {
        XCTFail("Unexpected host: \(String(describing: url.host))")
      }
    }
    do {
      let url = WebURL("foo:some non-path")!
      if case .none = url.host {
        XCTAssertEqual(url.host?.serialized, url.hostname)
        XCTAssertTrue(url.cannotBeABase)
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

    // Cannot-be-a-base 'blob:' URLs have the same origin as the URL parsed from their path.
    if let origin = WebURL("blob:https://example.com:443/index.html")?.origin {
      XCTAssertEqual(origin.serialized, "https://example.com")
      XCTAssertFalse(origin.isOpaque)
      XCTAssertEqual(origin, WebURL("https://example.com/some_resource.txt?q=🐟#🦆=👹")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // Non-cannot-be-a-base 'blob:' URLs are always opaque.
    if let origin = WebURL("blob:///https://example.com:443/index.html")?.origin {
      XCTAssertEqual(origin.serialized, "null")
      XCTAssertTrue(origin.isOpaque)
      XCTAssertNotEqual(origin, origin)
      XCTAssertNotEqual(origin, WebURL("blob:https://example.com")?.origin)
    } else {
      XCTFail("Failed to parse valid URL")
    }

    // Cannot-be-a-base 'blob:' URLs have opaque origins if their path is not a valid URL string.
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

  func testResolveHostRelative() {

    // Relative paths are relative, do not modify scheme or authority, remove query and fragment.
    do {
      let url = WebURL("http://example.com/p1/p2/p3?query=good#fragggggment")!
      let url_r = url.resolve(hostRelative: "../lib/swift")
      XCTAssertEqual(url_r?.serialized, "http://example.com/p1/lib/swift")
      XCTAssertEqual(url_r?.path, "/p1/lib/swift")
      XCTAssertEqual(url_r, url.resolve("../lib/swift"))
    }
    // Absolute paths are absolute, do not modify scheme or authority, remove query and fragment.
    do {
      let url = WebURL("http://example.com/p1/p2/p3?query=good#fragggggment")!
      let url_r = url.resolve(hostRelative: "/usr/lib/swift")
      XCTAssertEqual(url_r?.serialized, "http://example.com/usr/lib/swift")
      XCTAssertEqual(url_r?.hostname, "example.com")
      XCTAssertEqual(url_r?.path, "/usr/lib/swift")
      XCTAssertEqual(url_r, url.resolve("/usr/lib/swift"))
    }
    do {
      let url = WebURL("http://example.com/p1/p2/p3?query=good#fragggggment")!
      let url_r = url.resolve(hostRelative: "//notahost/test")
      XCTAssertEqual(url_r?.serialized, "http://example.com//notahost/test")
      XCTAssertEqual(url_r?.path, "//notahost/test")
      XCTAssertEqual(url_r, url.resolve("/.//notahost/test"))
    }

    // Empty strings are a no-op.
    do {
      let url = WebURL("foo://somehost/path?query=good#fragggggment")!
      XCTAssertFalse(url.cannotBeABase)
      let url_r = url.resolve(hostRelative: "")
      XCTAssertEqual(url_r?.serialized, "foo://somehost/path?query=good")
      XCTAssertEqual(url_r?.path, "/path")
      XCTAssertEqual(url_r, url.resolve(""))
    }

    // Windows drive letters.
    do {
      let url = WebURL("file:///C:/Windows/")!
      let url_r = url.resolve(hostRelative: "../../../../../Users/")
      XCTAssertEqual(url_r?.serialized, "file:///C:/Users/")
      XCTAssertEqual(url_r?.path, "/C:/Users/")

      XCTAssertEqual(url_r, url.resolve("/C:/Users/"))
    }
    // Absolute paths copy Windows drive from base.
    do {
      let url = WebURL("file:///C:/Windows/")!
      let url_r = url.resolve(hostRelative: "/hello")
      XCTAssertEqual(url_r?.serialized, "file:///C:/hello")
      XCTAssertEqual(url_r?.path, "/C:/hello")

      XCTAssertEqual(url_r, url.resolve("/C:/hello"))
    }
    do {
      let url = WebURL("file:///C:/Windows/")!
      let url_r = url.resolve(hostRelative: "/D:/hello")
      XCTAssertEqual(url_r?.serialized, "file:///D:/hello")
      XCTAssertEqual(url_r?.path, "/D:/hello")

      XCTAssertEqual(url_r, url.resolve("/D:/hello"))
    }
    do {
      let url = WebURL("file:///C:/Windows/")!
      let url_r = url.resolve(hostRelative: "D:/hello/")
      XCTAssertEqual(url_r?.serialized, "file:///D:/hello/")
      XCTAssertEqual(url_r?.path, "/D:/hello/")

      XCTAssertEqual(url_r, url.resolve("file:D:/hello/"))
    }

    // Spaces are trimmed and newlines ignored.
    do {
      let url = WebURL("file:///C:/Windows/")!
      let url_r = url.resolve(hostRelative: "  \n\tD:/hello/ ")
      XCTAssertEqual(url_r?.serialized, "file:///D:/hello/")
      XCTAssertEqual(url_r?.path, "/D:/hello/")

      XCTAssertEqual(url_r, url.resolve("file:D:/hello/"))
    }

		// Documentation examples:

    // - Absolute URLs
    do {
      let base = WebURL("file:///C:/Windows/")!
      XCTAssertEqual(base.resolve("D:/Media")?.serialized, "d:/Media")
      XCTAssertEqual(base.resolve(hostRelative: "D:/Media")?.serialized, "file:///D:/Media")
    }
    do {
      let endpoint = WebURL("https://api.example.com/")!
      // Using 'resolve':
      func getImportantDataURL(user: String) -> WebURL {
        endpoint.resolve("\(user)/files/importantData")!
      }
      XCTAssertEqual(getImportantDataURL(user: "frank").serialized, "https://api.example.com/frank/files/importantData")
      XCTAssertEqual(getImportantDataURL(user: "http://fake.com").serialized, "http://fake.com/files/importantData")
    }
    do {
      let endpoint = WebURL("https://api.example.com/")!
      // Using 'resolve(hostRelative:)':
      func getImportantDataURL(user: String) -> WebURL {
        endpoint.resolve(hostRelative: "\(user)/files/importantData")!
      }
      XCTAssertEqual(getImportantDataURL(user: "frank").serialized, "https://api.example.com/frank/files/importantData")
      XCTAssertEqual(
        getImportantDataURL(user: "http://fake.com").serialized,
        "https://api.example.com/http://fake.com/files/importantData"
      )
    }

    // - Protocol-relative URLs
    do {
      let container = WebURL("foo://somehost/")!
      // Using 'resolve':
      func getURLForPath(path: String) -> WebURL {
        // Did the caller add a leading '/'? Probably not - let's add one!
        container.resolve("/\(path)")!
      }
      // Will the function add a leading '/'? Probably not - let's add one!
      XCTAssertEqual(getURLForPath(path: "/users/john/profile").serialized, "foo://users/john/profile")
    }
    do {
      let container = WebURL("foo://somehost/")!
      // Using 'resolve(hostRelative:)':
      func getURLForPath(path: String) -> WebURL {
        // Did the caller add a leading '/'? Probably not - let's add one!
        container.resolve(hostRelative: "/\(path)")!
      }
      // Will the function add a leading '/'? Probably not - let's add one!
      XCTAssertEqual(getURLForPath(path: "/users/john/profile").serialized, "foo://somehost//users/john/profile")
    }

  }
}
