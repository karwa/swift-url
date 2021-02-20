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
    
    // 'ftp' and 'wss' have the same length; should not reallocate due to capacity.
    checkDoesNotCopy(&url) {
      $0.scheme = "ftp"
    }
    XCTAssertEqual(url.serialized, "ftp://user:pass@example.com:90/a/b?c=d&e=f#gh")
    
    // TODO: Add setters as they are implemented in the swift model.
    
    checkDoesNotCopy(&url) {
      _ in
//      $0.jsModel.hostname = "moc.elpmaxe"
    }
    // XCTAssertEqual(url.serialized, "ftp://moc.elpmaxe/a/b?c=d&e=f#gh")
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
    // Check that 'hostname' setter removes path sigil.
    do {
      func check_has_path_sigil(url: WebURL.JSModel) {
        XCTAssertEqual(url.description, "web+demo:/.//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .path)
        XCTAssertEqual(url.hostname, "")
        XCTAssertEqual(url.pathname, "//not-a-host/test")
      }
      func check_has_auth_sigil(url: WebURL.JSModel, hostname: String) {
        XCTAssertEqual(url.description, "web+demo://\(hostname)//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .authority)
        XCTAssertEqual(url.hostname, hostname)
        XCTAssertEqual(url.pathname, "//not-a-host/test")
      }

      var test_url = WebURL("web+demo:/.//not-a-host/test")!.jsModel
      check_has_path_sigil(url: test_url)
      test_url.hostname = "host"
      check_has_auth_sigil(url: test_url, hostname: "host")
      test_url.hostname = ""
      check_has_auth_sigil(url: test_url, hostname: "")
      // We don't yet expose any way to remove an authority, so go down to URLStorage.
      switch test_url.storage {
      case .generic(var storage): test_url.storage = storage.setHostname(to: UnsafeBufferPointer?.none).0
      case .small(var storage): test_url.storage = storage.setHostname(to: UnsafeBufferPointer?.none).0
      }
      check_has_path_sigil(url: test_url)
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
