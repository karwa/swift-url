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
    let reportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_constructor_more.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}

extension WebURLTests {

  /// Tests that setters copy to new storage when the mutated URL is not a unique reference.
  ///
  func testCopyOnWrite_nonUnique() {
    // TODO: Move to swift model once it has setters for all components.
    // TODO: Can we rule out copying due to needing more capacity or changing header type?
    //       - Maybe add an internal 'reserveCapacity' function?
    // TODO: These are by no means all paths that each setter can take.
    var url = WebURL("http://example.com/a/b?c=d&e=f#gh")!.jsModel
    let original = url

    func checkOriginalHasNotChanged() {
      XCTAssertEqual(original.href, "http://example.com/a/b?c=d&e=f#gh")
      XCTAssertEqual(original.scheme, "http:")
    }
    // Scheme.
    url.scheme = "https"
    XCTAssertEqual(url.href, "https://example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.scheme, "https:")
    checkOriginalHasNotChanged()
    url = original
    // Username.
    url.username = "user"
    XCTAssertEqual(url.href, "http://user@example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.username, "user")
    checkOriginalHasNotChanged()
    url = original
    // Password.
    url.password = "pass"
    XCTAssertEqual(url.href, "http://:pass@example.com/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.password, "pass")
    checkOriginalHasNotChanged()
    url = original
    // Hostname.
    url.hostname = "test.test"
    XCTAssertEqual(url.href, "http://test.test/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.hostname, "test.test")
    checkOriginalHasNotChanged()
    url = original
    // Port.
    url.port = "8080"
    XCTAssertEqual(url.href, "http://example.com:8080/a/b?c=d&e=f#gh")
    XCTAssertEqual(url.port, "8080")
    checkOriginalHasNotChanged()
    url = original
    // Path.
    url.pathname = "/foo/bar/baz"
    XCTAssertEqual(url.href, "http://example.com/foo/bar/baz?c=d&e=f#gh")
    XCTAssertEqual(url.pathname, "/foo/bar/baz")
    checkOriginalHasNotChanged()
    url = original
    // Query
    url.search = "?foo=bar&baz=qux"
    XCTAssertEqual(url.href, "http://example.com/a/b?foo=bar&baz=qux#gh")
    XCTAssertEqual(url.search, "?foo=bar&baz=qux")
    checkOriginalHasNotChanged()
    url = original
    // Fragment
    url.fragment = "#foo"
    XCTAssertEqual(url.href, "http://example.com/a/b?c=d&e=f#foo")
    XCTAssertEqual(url.fragment, "#foo")
    checkOriginalHasNotChanged()
    url = original
  }

  // Note: This is likely to be a bit fragile, since it relies on optimisations which might not happen at -Onone.
  //       For now, it works.

  /// Tests that setters on a uniquely referenced URL are performed in-place.
  ///
  func testCopyOnWrite_unique() {
    var url = WebURL("wss://user:pass@example.com:90/a/b?c=d&e=f#gh")!
    XCTAssertEqual(url.serialized, "wss://user:pass@example.com:90/a/b?c=d&e=f#gh")

    func checkDoesNotCopy(_ object: inout WebURL, _ perform: (inout WebURL) -> Void) {
      let addressBefore = object.storage.withEntireString { $0.baseAddress }
      perform(&object)
      let addressAfter = object.storage.withEntireString { $0.baseAddress }
      XCTAssertEqual(addressBefore, addressAfter)
    }

    // All new values must be the same length, so we can be sure we have enough capacity.

    // Scheme.
    checkDoesNotCopy(&url) {
      $0.scheme = "ftp"
    }
    XCTAssertEqual(url.serialized, "ftp://user:pass@example.com:90/a/b?c=d&e=f#gh")
    // Username.
    checkDoesNotCopy(&url) {
      $0.username = "resu"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:pass@example.com:90/a/b?c=d&e=f#gh")
    // Password.
    checkDoesNotCopy(&url) {
      $0.password = "ssap"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@example.com:90/a/b?c=d&e=f#gh")
    // Hostname.
    checkDoesNotCopy(&url) {
      $0.hostname = "moc.elpmaxe"
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:90/a/b?c=d&e=f#gh")
    // Port.
    checkDoesNotCopy(&url) {
      $0.port = 42
    }
    XCTAssertEqual(url.serialized, "ftp://resu:ssap@moc.elpmaxe:42/a/b?c=d&e=f#gh")
    // TODO: Add setters as they are implemented in the swift model.
  }
}

extension WebURLTests {

  /// Tests the WebURL scheme setter.
  ///
  /// Broadly speaking, the setter's behaviour should be tested via the JS model according to the WPT test files.
  /// However, the JS model is in many ways not ideal for use in Swift, so deviations and extra information (e.g. errors) should be tested here.
  ///
  func testSchemeSetter() {
    do {
      // [Throw] Invalid scheme.
      var url = WebURL("http://example.com/a/b?c=d&e=f#gh")!
      XCTAssertThrowsSpecific(URLSetterError.error(.invalidScheme)) {
        try url.setScheme(to: "🤯")
      }
      // [Throw] Change of special-ness.
      XCTAssertThrowsSpecific(URLSetterError.error(.changeOfSchemeSpecialness)) {
        try url.setScheme(to: "foo")
      }
      // [Deviation] If there is content after the ":", the operation fails. The JS model silently discards it.
      XCTAssertThrowsSpecific(URLSetterError.error(.invalidScheme)) {
        try url.setScheme(to: "http://foo/")
      }
      // ":" is allowed as the final character, but not required.
      XCTAssertNoThrow(try url.setScheme(to: "ws"))
      XCTAssertEqual(url.serialized, "ws://example.com/a/b?c=d&e=f#gh")
      XCTAssertNoThrow(try url.setScheme(to: "https:"))
      XCTAssertEqual(url.serialized, "https://example.com/a/b?c=d&e=f#gh")

      // [Deviation] Tabs and newlines are not ignored, cause setter to fail. The JS model ignores them.
      XCTAssertThrowsSpecific(URLSetterError.error(.invalidScheme)) {
        try url.setScheme(to: "\th\nttp:")
      }
    }

    do {
      // [Throw] URL with credentials or port changing to scheme which does not allow them.
      var url = WebURL("http://user:pass@somehost/")!
      XCTAssertThrowsSpecific(URLSetterError.error(.newSchemeCannotHaveCredentialsOrPort)) {
        try url.setScheme(to: "file")
      }
      XCTAssertNoThrow(try url.setScheme(to: "https"))
      XCTAssertEqual(url.serialized, "https://user:pass@somehost/")

      url = WebURL("http://somehost:8080/")!
      XCTAssertThrowsSpecific(URLSetterError.error(.newSchemeCannotHaveCredentialsOrPort)) {
        try url.setScheme(to: "file")
      }
      XCTAssertNoThrow(try url.setScheme(to: "https"))
      XCTAssertEqual(url.serialized, "https://somehost:8080/")
    }

    do {
      // [Throw] URL with empty hostname changing to scheme which does not allow them.
      var url = WebURL("file:///")!
      XCTAssertThrowsSpecific(URLSetterError.error(.newSchemeCannotHaveEmptyHostname)) {
        try url.setScheme(to: "http")
      }
      XCTAssertNoThrow(try url.setScheme(to: "file"))
      XCTAssertEqual(url.serialized, "file:///")
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

    url.username = "some username"
    XCTAssertEqual(url.username, "some%20username")
    XCTAssertEqual(url.serialized, "http://some%20username@example.com/")

    // [Deviation] Setting the empty string is the same as setting 'nil'.
    url.username = ""
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized, "http://example.com/")

    url.username = "some username"
    XCTAssertEqual(url.username, "some%20username")
    XCTAssertEqual(url.serialized, "http://some%20username@example.com/")

    // [Deviation] Setting the 'nil' is the same as setting the empty string.
    url.username = nil
    XCTAssertNil(url.username)
    XCTAssertEqual(url.serialized, "http://example.com/")
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

    url.password = "🤫"
    XCTAssertEqual(url.password, "%F0%9F%A4%AB")
    XCTAssertEqual(url.serialized, "http://:%F0%9F%A4%AB@example.com/")

    // [Deviation] Setting the empty string is the same as setting 'nil'.
    url.password = ""
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized, "http://example.com/")

    url.password = "🤫"
    XCTAssertEqual(url.password, "%F0%9F%A4%AB")
    XCTAssertEqual(url.serialized, "http://:%F0%9F%A4%AB@example.com/")

    // [Deviation] Setting the 'nil' is the same as setting the empty string.
    url.password = nil
    XCTAssertNil(url.password)
    XCTAssertEqual(url.serialized, "http://example.com/")
  }

  /// Tests the Swift model 'hostname' property.
  ///
  /// The Swift model deviates from the JS model in that it does not trim or filter the new value when setting, can represent not-present hosts as 'nil', and supports
  /// setting hosts to 'nil'.
  ///
  func testHostname() {
    // [Deviation] Hostname is not trimmed; invalid host code points such as "?", "#", or ":" cause the setter to fail.
    var url = WebURL("http://example.com/")!
    XCTAssertThrowsSpecific(URLSetterError.error(.invalidHostname)) {
      try url.setHostname(to: "hello?")
    }
    XCTAssertThrowsSpecific(URLSetterError.error(.invalidHostname)) {
      try url.setHostname(to: "hello#")
    }
    XCTAssertThrowsSpecific(URLSetterError.error(.invalidHostname)) {
      try url.setHostname(to: "hel:lo")
    }
    // [Deviation] Hostname is not filtered. Tabs and newlines are invalid host code points, cause setter to fail.
    XCTAssertThrowsSpecific(URLSetterError.error(.invalidHostname)) {
      try url.setHostname(to: "\thel\nlo")
    }

    // [Deviation] Swift model can distinguish between empty and not-present hostnames.
    XCTAssertNil(WebURL("unix:/some/path")!.hostname)
    XCTAssertEqual(WebURL("unix:///some/path")!.hostname, "")

    // [Deviation] Swift model allows setting hostname to nil (removing it, not just making it empty).
    //             But only if the scheme allows it, of course.
    XCTAssertThrowsSpecific(URLSetterError.error(.schemeDoesNotSupportNilOrEmptyHostnames)) {
      try url.setHostname(to: String?.none)
    }
    // Non-special schemes allow 'nil' hostnames.
    url = WebURL("unix:///some/path")!
    XCTAssertNoThrow(try url.setHostname(to: String?.none))
    XCTAssertEqual(url.serialized, "unix:/some/path")
    // But not if they already have credentials or ports.
    url = WebURL("unix://user:pass@example/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.username, "user")
    XCTAssertThrowsSpecific(URLSetterError.error(.cannotSetHostnameWithCredentialsOrPort)) {
      try url.setHostname(to: String?.none)
    }
    url = WebURL("unix://example:99/some/path")!
    XCTAssertEqual(url.hostname, "example")
    XCTAssertEqual(url.port, 99)
    XCTAssertThrowsSpecific(URLSetterError.error(.cannotSetHostnameWithCredentialsOrPort)) {
      try url.setHostname(to: String?.none)
    }
    // When setting a hostname to/from 'nil', we may need to add/remove a path sigil.
    do {
      func check_has_path_sigil(url: WebURL) {
        XCTAssertEqual(url.serialized, "web+demo:/.//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .path)
        XCTAssertEqual(url.hostname, nil)
        XCTAssertEqual(url.path, "//not-a-host/test")
      }
      func check_has_auth_sigil(url: WebURL, hostname: String) {
        XCTAssertEqual(url.serialized, "web+demo://\(hostname)//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .authority)
        XCTAssertEqual(url.hostname, hostname)
        XCTAssertEqual(url.path, "//not-a-host/test")
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
  }

  /// Tests the Swift model 'port' property.
  ///
  /// The Swift model deviates from the JS model in that it takes an `Int?` rather than a string.
  ///
  func testPort() {
    // [Throw] Adding a port to a URL which does not allow them.
    var url = WebURL("file://somehost/p1/p2")!
    XCTAssertThrowsSpecific(URLSetterError.error(.cannotHaveCredentialsOrPort)) {
      try url.setPort(to: 99)
    }
    // [Throw] Setting a port to a non-valid UInt16 value.
    url = WebURL("http://example.com/p1/p2")!
    XCTAssertThrowsSpecific(URLSetterError.error(.portValueOutOfBounds)) {
      try url.setPort(to: -99)
    }
    XCTAssertThrowsSpecific(URLSetterError.error(.portValueOutOfBounds)) {
      try url.setPort(to: Int(UInt32.max))
    }
    // [Deviation] Non-present port is represented as 'nil', rather than empty string.
    XCTAssertNil(url.port)
    // Set the port to a non-nil value.
    XCTAssertNoThrow(try url.setPort(to: 42))
    XCTAssertEqual(url.port, 42)
    XCTAssertEqual(url.serialized, "http://example.com:42/p1/p2")
    // And back to nil.
    XCTAssertNoThrow(try url.setPort(to: nil))
    XCTAssertNil(url.port)
    XCTAssertEqual(url.serialized, "http://example.com/p1/p2")
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
    XCTAssertThrowsSpecific(URLSetterError.error(.cannotSetPathOnCannotBeABaseURL)) {
      try url.setPath(to: "frank")
    }

    // [Deviation] Tabs and newlines are not trimmed.
    url = WebURL("file:///hello/world?someQuery")!
    XCTAssertNoThrow(try url.setPath(to: "\t\n\t"))
    XCTAssertEqual(url.path, "/%09%0A%09")
    XCTAssertEqual(url.serialized, "file:///%09%0A%09?someQuery")

    // [Bug] This seems to be a bug in the standard, which our implementation also exhibits (yay for accuracy?).
    //       The path of non-special URLs can be set to the empty string, which makes them cannot-be-a-base URLs,
    //       but without the flag. Re-parsing the serialized URL sets the flag, so the two behave differently.
    // See: https://github.com/whatwg/url/issues/581
    url = WebURL("foo:/hello/world?someQuery")!
    XCTAssertEqual(url.serialized, "foo:/hello/world?someQuery")
    XCTAssertEqual(url.path, "/hello/world")
    XCTAssertFalse(url._cannotBeABaseURL)

    url.path = ""
    XCTAssertEqual(url.serialized, "foo:?someQuery")
    XCTAssertEqual(url.path, "")
    XCTAssertFalse(url._cannotBeABaseURL)
    XCTAssertTrue(WebURL(url.serialized)!._cannotBeABaseURL)

    url.path = "test"
    XCTAssertEqual(url.serialized, "foo:/test?someQuery")
    XCTAssertEqual(url.path, "/test")
    XCTAssertFalse(url._cannotBeABaseURL)
  }
}

extension WebURLTests {

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
