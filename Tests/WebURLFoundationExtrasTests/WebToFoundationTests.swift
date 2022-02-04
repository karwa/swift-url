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

import Foundation
import WebURL
import WebURLTestSupport
import XCTest

@testable import WebURLFoundationExtras

/// Asserts that the given URLs contain an equivalent set of components,
/// without taking any shortcuts or making assumptions that they originate from the same string.
///
fileprivate func XCTAssertEquivalentURLs(_ webURL: WebURL, _ foundationURL: URL, _ message: String = "") {
  var message = message
  if !message.isEmpty {
    message += " -- "
  }
  message += "Foundation: \(foundationURL) -- WebURL: \(webURL)"

  var urlString = foundationURL.absoluteString
  // Check using the simplified web-to-foundation equivalence checks.
  var areEquivalent = urlString.withUTF8 {
    WebURL._SPIs._checkEquivalence_w2f(webURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  XCTAssertTrue(areEquivalent, "\(message) [WebToFoundation]")
  // Also check using the foundation-to-web equivalence checks.
  areEquivalent = urlString.withUTF8 {
    WebURL._SPIs._checkEquivalence(webURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  XCTAssertTrue(areEquivalent, "\(message) [FoundationToWeb]")
}

extension WebURL {
  fileprivate var withEncodedRFC2396DisallowedSubdelims: WebURL {
    var copy = self
    let _ = copy._spis._addPercentEncodingToAllComponents(RFC2396DisallowedSubdelims())
    return copy
  }
}

final class WebToFoundationTests: ReportGeneratingTestCase {}


// --------------------------------------------
// MARK: - WPT Constructor Testcases
// --------------------------------------------
// These don't run full WPT constructor tests; they use the WPT test files as a database of quirky URLs
// to test our conversion process on.


extension WebToFoundationTests {

  private static let conversionFailures_always: Set<Int> = [
    // We don't add percent-encoding to a URL's opaque path.
    9,  // Opaque path with space.
    11,  // Opaque path with space.
    354,  // Opaque path with unescaped backslash.
    356,  // Opaque path with unescaped '%'.
    357,  // Opaque path with unescaped '%'.

    // If a URL has an opaque path and fragment, Foundation percent-encodes the '#'.
    105,  // URL with opaque path and fragment.
    165,  // URL with opaque path and fragment.
    300,  // URL with opaque path and fragment.
    301,  // URL with opaque path and fragment.
    302,  // URL with opaque path and fragment.
    303,  // URL with opaque path and fragment.
    304,  // URL with opaque path and fragment.
    333,  // URL with opaque path and fragment.
    334,  // URL with opaque path and fragment.

    // We can't add percent-encoding in domains.
    387,  // Unescaped curly brackets, backtick.
    623,  // Unescaped curly brackets, backtick.
  ]
  private static let conversionFailures_noAddedPercentEncoding: Set<Int> = {
    var conversionFailures: Set<Int> = conversionFailures_always
    conversionFailures.formUnion([
      34,  // Unescaped backslash.
      60,  // Unescaped hash.
      63,  // Unescaped square brackets.
      64,  // Unescaped square brackets.
      139,  // Unescaped percent-sign.
      146,  // Unescaped percent-sign.
      147,  // Unescaped percent-sign.
      148,  // Unescaped percent-sign.
      149,  // Unescaped percent-sign.
      307,  // Unescaped curly brackets, backtick.
      345,  // Unescaped percent-sign.
      388,  // Unescaped curly brackets, backtick.
      480,  // Unescaped vertical bar.

      591,  // Unescaped percent-sign.
      593,  // Unescaped percent-sign.
      618,  // Unescaped percent-sign.
      619,  // Unescaped percent-sign.
      620,  // Unescaped percent-sign.
      621,  // Unescaped percent-sign.
      622,  // Unescaped curly brackets, square brackets, backtick, backslash, vertical bar, etc.
      624,  // Unescaped percent-sign, square brackets, vertical bar, etc.
      625,  // Unescaped percent-sign, square brackets, vertical bar, etc.
      626,  // Unescaped curly brackets, square brackets, backtick, backslash, vertical bar, etc.
      627,  // Unescaped curly brackets, square brackets, backtick, backslash, vertical bar, etc.
      628,  // Unescaped curly brackets, square brackets, backtick, backslash, vertical bar, etc.
      629,  // Unescaped curly brackets, square brackets, backtick, backslash, vertical bar, etc.
    ])
    return conversionFailures
  }()

  func _doTestWPTTestCases(
    addEncoding: Bool, isExpectedFailure: (Int) -> Bool
  ) throws -> (report: SimpleTestReport, reportedResultCount: Int) {

    let testFile = try loadTestFile(.WPTURLConstructorTests, as: WPTConstructorTest.TestFile.self)

    var report = SimpleTestReport()
    var idx = 0

    for fileEntry in testFile {
      switch fileEntry {
      case .comment(let comment):
        report.markSection(comment)
      case .testcase(let testcase):
        report.performTest { reporter in
          defer { idx += 1 }
          if isExpectedFailure(idx) {
            reporter.expectedResult = .fail
          }

          // 1. Parse the (input, base) pair with WebURL.
          guard let webURL = WebURL.JSModel(testcase.input, base: testcase.base)?.swiftModel else {
            return
          }
          reporter.capture(key: "WebURL", webURL)

          var encodedWebURL = webURL
          if addEncoding {
            encodedWebURL = encodedWebURL.withEncodedRFC2396DisallowedSubdelims
            reporter.capture(key: "Encoded WebURL", encodedWebURL)
          }

          // 2. Convert to a Foundation URL.
          guard let foundationURL = URL(webURL, addPercentEncoding: addEncoding) else {
            reporter.fail("Failed to convert")
            return
          }
          reporter.capture(key: "Foundation", foundationURL)

          // 3. Check equivalence without shortcuts.
          var foundationString = foundationURL.absoluteString
          let isEquivalent = foundationString.withUTF8 {
            WebURL._SPIs._checkEquivalence_w2f(encodedWebURL, foundationURL, foundationString: $0, shortcuts: false)
          }
          reporter.expectTrue(isEquivalent, "Equivalence")

          // Finished.
        }
      }
    }
    return (report, idx)
  }

  func testWPTTestCases_withEncoding() throws {
    let (report, resultCount) = try _doTestWPTTestCases(
      addEncoding: true,
      isExpectedFailure: { Self.conversionFailures_always.contains($0) }
    )
    XCTAssertEqual(resultCount, 666)
    XCTAssertFalse(report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "webtofoundation_wpt_withEncoding.txt")
    try report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testWPTTestCases_noEncoding() throws {
    let (report, resultCount) = try _doTestWPTTestCases(
      addEncoding: false,
      isExpectedFailure: { Self.conversionFailures_noAddedPercentEncoding.contains($0) }
    )
    XCTAssertEqual(resultCount, 666)
    XCTAssertFalse(report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "webtofoundation_wpt_noEncoding.txt")
    try report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}


extension WebToFoundationTests {

  func testURLWithOpaquePath() {

    // Opaque path with allowed characters.
    test: do {
      let url = WebURL("sc:foobar")!
      guard let converted = URL(url) else {
        XCTFail("Failed to convert URL \(url)")
        break test
      }
      XCTAssertEquivalentURLs(url, converted)
    }

    // Opaque path with disallowed characters.
    test: do {
      let url = WebURL("sc:hello, world!")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }

    // Opaque path with query.
    test: do {
      let url = WebURL("sc:foo?bar")!
      guard let converted = URL(url) else {
        XCTFail("Failed to convert URL \(url)")
        break test
      }
      XCTAssertEquivalentURLs(url, converted)
    }
    test: do {
      let url = WebURL("sc:foo?bar[baz]=qux")!
      guard let converted = URL(url) else {
        XCTFail("Failed to convert URL \(url)")
        break test
      }
      XCTAssertEquivalentURLs(url.withEncodedRFC2396DisallowedSubdelims, converted)
    }
    test: do {
      let url = WebURL("sc:hello world?bar")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }

    // Opaque path with fragment.
    // These should all fail because Foundation.URL encodes the '#'.
    test: do {
      let url = WebURL("sc:foo#bar")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }
    test: do {
      let url = WebURL("sc:foo#bar[baz]=qux")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }
    test: do {
      let url = WebURL("sc:hello world#bar")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }

    // Opaque path with query and fragment.
    // Should also fail for the same reason as above.
    test: do {
      let url = WebURL("sc:foo?bar#baz")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }
    test: do {
      let url = WebURL("sc:foo?bar#baz[qux]=qaz")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }
    test: do {
      let url = WebURL("sc:hello world?foo#bar")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }
  }
}


// --------------------------------
// MARK: - Fuzz Corpus Tests
// --------------------------------


final class WebToFoundation_CorpusTests: XCTestCase {

  func testFuzzCorpus() {
    for bytes in corpus_web_to_foundation {
      guard let webURL = WebURL(utf8: bytes) else {
        continue  // Not a valid URL.
      }
      guard let foundationURL = URL(webURL) else {
        continue  // Couldn't convert the URL. That's fine.
      }
      let encodedWebURL = webURL.withEncodedRFC2396DisallowedSubdelims
      XCTAssertEquivalentURLs(encodedWebURL, foundationURL, "String: \(String(decoding: bytes, as: UTF8.self))")
    }
  }
}
