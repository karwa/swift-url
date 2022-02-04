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
import WebURLTestSupport
import XCTest

@testable import WebURL
@testable import WebURLFoundationExtras

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
            encodedWebURL = encodedWebURL.encodedForFoundation
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
          var areEquivalent = foundationString.withUTF8 {
            WebURL._SPIs._checkEquivalence_w2f(encodedWebURL, foundationURL, foundationString: $0, shortcuts: false)
          }
          reporter.expectTrue(areEquivalent, "Equivalence")

          // 4. Round-trip back to a WebURL.
          guard let roundtripWebURL = WebURL(foundationURL) else {
            reporter.fail("Failed to round trip converted URL back to a WebURL")
            return
          }

          // 5. Check equivalence again, using the Foundation-to-WebURL function (no shortcuts).
          areEquivalent = foundationString.withUTF8 {
            WebURL._SPIs._checkEquivalence_f2w(roundtripWebURL, foundationURL, foundationString: $0, shortcuts: false)
          }
          reporter.expectTrue(areEquivalent, "Equivalence (Round-trip)")

          // 6. Check that the round-tripped WebURL is identical to the encoded WebURL.
          reporter.expectEqual(roundtripWebURL, encodedWebURL)
          reporter.expectTrue(roundtripWebURL.utf8.elementsEqual(encodedWebURL.utf8))
          reporter.expectTrue(
            roundtripWebURL.storage.structure.describesSameStructure(as: encodedWebURL.storage.structure)
          )

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


// --------------------------------------------
// MARK: - Additional Tests
// --------------------------------------------


/// Asserts that the given URLs contain an equivalent set of components,
/// without taking any shortcuts or making assumptions that they originate from the same string.
///
/// Checks are performed using:
///
/// - `_checkEquivalence_w2f`, which requires string equality, and
/// - `_checkEquivalence_f2w`, which does not require string equality
///
/// Additionally, this function asserts that the converted URL can round-trip back to a WebURL.
/// That conversion is also checked using both `_checkEquivalence_w2f` and `_checkEquivalence_f2w`,
/// and the result must have the same structure and code-units as the given WebURL.
///
fileprivate func XCTAssertEquivalentURLs(_ webURL: WebURL, _ foundationURL: URL, _ message: String = "") {
  var message = message
  if !message.isEmpty {
    message += " -- "
  }
  message += "Foundation: \(foundationURL) -- WebURL: \(webURL)"

  var urlString = foundationURL.absoluteString

  // 1. Check using the web-to-foundation equivalence checks.
  var areEquivalent = urlString.withUTF8 {
    WebURL._SPIs._checkEquivalence_w2f(webURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  XCTAssertTrue(areEquivalent, "\(message) [WebToFoundation]")

  // 2. Double-check using the foundation-to-web equivalence checks.
  areEquivalent = urlString.withUTF8 {
    WebURL._SPIs._checkEquivalence_f2w(webURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  XCTAssertTrue(areEquivalent, "\(message) [FoundationToWeb]")

  // 3. Round-trip the URL back to a WebURL.
  guard let roundtripWebURL = WebURL(foundationURL) else {
    XCTFail("\(message) [Round-Trip]")
    return
  }

  // 4. Check that the conversion was sound.
  var foundationString = foundationURL.absoluteString
  areEquivalent = foundationString.withUTF8 {
    WebURL._SPIs._checkEquivalence_w2f(roundtripWebURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  areEquivalent = foundationString.withUTF8 {
    WebURL._SPIs._checkEquivalence_f2w(roundtripWebURL, foundationURL, foundationString: $0, shortcuts: false)
  }
  XCTAssertTrue(areEquivalent, "\(message) [Round-Trip Equivalence To Source]")

  // Check that the round-tripped URL is identical to the encoded original.
  XCTAssertEqual(roundtripWebURL, webURL, "\(message) [Round-Trip String]")
  XCTAssertTrue(roundtripWebURL.utf8.elementsEqual(webURL.utf8), "\(message) [Round-Trip UTF8]")
  XCTAssertTrue(
    roundtripWebURL.storage.structure.describesSameStructure(as: webURL.storage.structure),
    "\(message) [Round-Trip Strucure]"
  )
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
      XCTAssertEquivalentURLs(url.encodedForFoundation, converted)
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

    // Opaque path with square bracket.
    // These should fail because Foundation percent-encodes it ("p:%5B")
    test: do {
      let url = WebURL("p:[")!
      XCTAssertNil(URL(url), "Unexpected conversion: \(url)")
    }

    // Opaque path with semicolon and non-UTF8 percent-encoding.
    // This *can* be converted, but URLComponents isn't able to verify it.
    test: do {
      let url = WebURL("ht:;//%E90")!
      guard let converted = URL(url) else {
        XCTFail("Failed to convert: \(url)")
        break test
      }
      XCTAssertEqual(converted.absoluteString, "ht:;//%E90")
      XCTAssertEquivalentURLs(url, converted)
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
      let encodedWebURL = webURL.encodedForFoundation
      XCTAssertEquivalentURLs(encodedWebURL, foundationURL, "String: \(String(decoding: bytes, as: UTF8.self))")
    }
  }
}
