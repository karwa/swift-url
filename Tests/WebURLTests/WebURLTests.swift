import XCTest
import WebURLTestSupport
@testable import WebURL

class WebURLTests: XCTestCase {}

extension WebURLTests {

  /// These tests use the same methodology as the WPT constructor tests, with the goal that anything not overly implementation-specific
  /// can be upstreamed.
  ///
  func testURLConstructor() throws {
    let url = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("additional_constructor_tests.json")
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
      var url = WebURL("ws://hostnamewhichtakesustotheedge:443?hellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellop")!.jsModel
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
