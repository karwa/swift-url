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

class WebURLTests: ReportGeneratingTestCase {}

extension WebURLTests {

  /// These tests use the same methodology as the WPT constructor tests, with the goal that anything not overly implementation-specific
  /// can be upstreamed.
  ///
  func testURLConstructor() throws {

    let url = URL(fileURLWithPath: #file).deletingLastPathComponent()
      .appendingPathComponent("additional_constructor_tests.json")
    let fileContents = try JSONDecoder().decode([URLConstructorTest.FileEntry].self, from: try Data(contentsOf: url))
    assert(
      fileContents.count == 79,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )
    var harness = URLConstructorTest.WebURLReportHarness()
    harness.runTests(fileContents)
    XCTAssert(harness.entriesSeen == 79, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    // Generate a report file because the XCTest ones really aren't that helpful.
    let reportURL = fileURLForReport(named: "weburl_constructor_more.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}

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
        try url.setScheme(to: "🤯")
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Throw] Change of special-ness.
      XCTAssertThrowsSpecific(URLSetterError.changeOfSchemeSpecialness) {
        try url.setScheme(to: "foo")
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Deviation] If there is content after the ":", the operation fails. The JS model silently discards it.
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme(to: "http://foo/")
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // ":" is allowed as the final character, but not required.
      XCTAssertNoThrow(try url.setScheme(to: "ws"))
      XCTAssertEqual(url.serialized, "ws://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      XCTAssertNoThrow(try url.setScheme(to: "https:"))
      XCTAssertEqual(url.serialized, "https://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)

      // [Deviation] Tabs and newlines are not ignored, cause setter to fail. The JS model ignores them.
      XCTAssertThrowsSpecific(URLSetterError.invalidScheme) {
        try url.setScheme(to: "\th\nttp:")
      }
      XCTAssertEqual(url.serialized, "https://example.com/a/b?c=d&e=f#gh")
      XCTAssertURLIsIdempotent(url)
    }

    do {
      // [Throw] URL with credentials or port changing to scheme which does not allow them.
      var url = WebURL("http://user:pass@somehost/")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveCredentialsOrPort) {
        try url.setScheme(to: "file")
      }
      XCTAssertNoThrow(try url.setScheme(to: "https"))
      XCTAssertEqual(url.serialized, "https://user:pass@somehost/")
      XCTAssertURLIsIdempotent(url)

      url = WebURL("http://somehost:8080/")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveCredentialsOrPort) {
        try url.setScheme(to: "file")
      }
      XCTAssertNoThrow(try url.setScheme(to: "https"))
      XCTAssertEqual(url.serialized, "https://somehost:8080/")
      XCTAssertURLIsIdempotent(url)
    }

    do {
      // [Throw] URL with empty hostname changing to scheme which does not allow them.
      var url = WebURL("file:///")!
      XCTAssertThrowsSpecific(URLSetterError.newSchemeCannotHaveEmptyHostname) {
        try url.setScheme(to: "http")
      }
      XCTAssertNoThrow(try url.setScheme(to: "file"))
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
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setUsername(to: "user") }
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
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setPassword(to: "pass") }
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
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "hello?") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "hello#") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "hel:lo") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Hostname is not filtered. Tabs and newlines are invalid host code points, cause setter to fail.
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "\thel\nlo") }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Swift model can distinguish between empty and not-present hostnames.
    XCTAssertNil(WebURL("unix:/some/path")!.hostname)
    XCTAssertEqual(WebURL("unix:///some/path")!.hostname, "")

    // [Deviation] Swift model allows setting hostname to nil (removing it, not just making it empty).
    // Special schemes do not allow 'nil' hostnames.
    XCTAssertEqual(url.scheme, "http")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(to: String?.none)
    }
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertURLIsIdempotent(url)

    // 'file' allows empty hostnames, but not 'nil' hostnames.
    url = WebURL("file:///some/path")!
    XCTAssertEqual(url.hostname, "")
    XCTAssertEqual(url.scheme, "file")
    XCTAssertEqual(url.serialized, "file:///some/path")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(to: String?.none)
    }
    XCTAssertEqual(url.serialized, "file:///some/path")
    XCTAssertURLIsIdempotent(url)

    // Non-special schemes allow 'nil' hostnames.
    url = WebURL("unix:///some/path")!
    XCTAssertNoThrow(try url.setHostname(to: String?.none))
    XCTAssertEqual(url.serialized, "unix:/some/path")
    XCTAssertURLIsIdempotent(url)
    // But not if they already have credentials or ports.
    url = WebURL("unix://user:pass@example/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.username, "user")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(to: String?.none)
    }
    XCTAssertEqual(url.serialized, "unix://user:pass@example/some/path")
    XCTAssertURLIsIdempotent(url)

    url = WebURL("unix://example:99/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.port, 99)
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(to: String?.none)
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
    XCTAssertTrue(url._cannotBeABaseURL)
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetHostOnCannotBeABaseURL) {
      try url.setHostname(to: "somehost")
    }
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Cannot set empty hostname on special schemes.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.schemeDoesNotSupportNilOrEmptyHostnames) {
      try url.setHostname(to: "")
    }
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Cannot set empty hostname if the URL contains credentials or port.
    url = WebURL("foo://user@example.com/p1/p2")!
    XCTAssertEqual(url.username, "user")
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "foo://user@example.com/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(to: "")
    }
    XCTAssertEqual(url.serialized, "foo://user@example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    url = WebURL("foo://example.com:8080/p1/p2")!
    XCTAssertEqual(url.port, 8080)
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "foo://example.com:8080/p1/p2")
    XCTAssertThrowsSpecific(URLSetterError.cannotSetEmptyHostnameWithCredentialsOrPort) {
      try url.setHostname(to: "")
    }
    XCTAssertEqual(url.serialized, "foo://example.com:8080/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Invalid hostnames.
    url = WebURL("foo://example.com/")!
    XCTAssertEqual(url.hostname, "example.com")
    XCTAssertEqual(url.serialized, "foo://example.com/")
    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "@") }
    XCTAssertEqual(url.serialized, "foo://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "/a/b/c") }
    XCTAssertEqual(url.serialized, "foo://example.com/")
    XCTAssertURLIsIdempotent(url)

    XCTAssertThrowsSpecific(URLSetterError.invalidHostname) { try url.setHostname(to: "[:::]") }
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
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) { try url.setPort(to: 99) }
    XCTAssertEqual(url.serialized, "file://somehost/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Throw] Setting a port to a non-valid UInt16 value.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertThrowsSpecific(URLSetterError.portValueOutOfBounds) { try url.setPort(to: -99) }
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)
    XCTAssertThrowsSpecific(URLSetterError.portValueOutOfBounds) { try url.setPort(to: Int(UInt32.max)) }
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Non-present port is represented as 'nil', rather than empty string.
    XCTAssertNil(url.port)
    // Set the port to a non-nil value.
    XCTAssertNoThrow(try url.setPort(to: 42))
    XCTAssertEqual(url.port, 42)
    XCTAssertEqual(url.serialized, "http://example.com:42/p1/p2")
    XCTAssertURLIsIdempotent(url)
    // And back to nil.
    XCTAssertNoThrow(try url.setPort(to: nil))
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
    XCTAssertTrue(url._cannotBeABaseURL)
    XCTAssertThrowsSpecific(URLSetterError.cannotSetPathOnCannotBeABaseURL) { try url.setPath(to: "frank") }
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertURLIsIdempotent(url)

    // [Deviation] Tabs and newlines are not trimmed.
    url = WebURL("file:///hello/world?someQuery")!
    XCTAssertNoThrow(try url.setPath(to: "\t\n\t"))
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
      try url.setHostname(to: String?.none)
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
    XCTAssertFalse(url._cannotBeABaseURL)

    url.path = ""
    XCTAssertEqual(url.serialized, "foo:?someQuery")
    XCTAssertEqual(url.path, "")
    XCTAssertNil(url.hostname)
    XCTAssertFalse(url._cannotBeABaseURL)
    XCTAssertTrue(WebURL(url.serialized)!._cannotBeABaseURL)
    // XCTAssertURLIsIdempotent(url) - see comment above.

    url.path = "test"
    XCTAssertEqual(url.serialized, "foo:/test?someQuery")
    XCTAssertEqual(url.path, "/test")
    XCTAssertNil(url.hostname)
    XCTAssertFalse(url._cannotBeABaseURL)
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
      case .generic(_): break
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
    let url1 = WebURL("http://example.com/aPath?aQuery#andFragment, too")!
    if case .domain("example.com") = url1.host {
      XCTAssertEqual(url1.host?.serialized, url1.hostname)
    } else {
      XCTFail("Unexpected host: \(String(describing: url1.host))")
    }

    // Non-IP hostnames in non-special URLs are always opaque hostnames.
    let url2 = WebURL("foo://example.com/aPath?aQuery#andFragment, too")!
    if case .opaque("example.com") = url2.host {
      XCTAssertEqual(url2.host?.serialized, url2.hostname)
    } else {
      XCTFail("Unexpected host: \(String(describing: url2.host))")
    }

    // Special URLs detect IPv4 addresses.
    let url3 = WebURL("http://0xbadf00d/aPath?aQuery#andFragment, too")!
    if case .ipv4Address(.init(octets: (11, 173, 240, 13))) = url3.host {
      XCTAssertEqual(url3.host?.serialized, url3.hostname)
    } else {
      XCTFail("Unexpected host: \(String(describing: url3.host))")
    }
    // Non-special URLs do not.
    let url4 = WebURL("foo://11.173.240.13/aPath?aQuery#andFragment, too")!
    if case .opaque("11.173.240.13") = url4.host {
      XCTAssertEqual(url4.host?.serialized, url4.hostname)
    } else {
      XCTFail("Unexpected host: \(String(describing: url4.host))")
    }

    // Both special and non-special URLs detect IPv6 addresses.
    let url5 = WebURL("http://[::127.0.0.1]/aPath?aQuery#andFragment, too")!
    if case .ipv6Address(.init(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = url5.host {
      XCTAssertEqual(url5.host?.serialized, url5.hostname)
    } else {
      XCTFail("Unexpected host: \(String(describing: url5.host))")
    }

    let url6 = WebURL("foo://[::127.0.0.1]/aPath?aQuery#andFragment, too")!
    if case .ipv6Address(.init(pieces: (0, 0, 0, 0, 0, 0, 0x7f00, 0x0001), .numeric)) = url6.host {
      XCTAssertEqual(url6.host?.serialized, url6.hostname)
    } else {
      XCTFail("Unexpected host: \(String(describing: url6.host))")
    }

    // Path-only and cannot-be-a-base-path URLs do not have hosts.
    let url7 = WebURL("foo:/path/only")!
    if case .none = url7.host {
      XCTAssertEqual(url7.host?.serialized, url7.hostname)
      XCTAssertFalse(url7._cannotBeABaseURL)
    } else {
      XCTFail("Unexpected host: \(String(describing: url7.host))")
    }

    let url8 = WebURL("foo:some non-path")!
    if case .none = url8.host {
      XCTAssertEqual(url8.host?.serialized, url8.hostname)
      XCTAssertTrue(url8._cannotBeABaseURL)
    } else {
      XCTFail("Unexpected host: \(String(describing: url8.host))")
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
