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

final class WebPlatformTests: ReportGeneratingTestCase {}

// --------------------------------------------
// MARK: - URL Constructor
// --------------------------------------------
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json
// at version 5acc42721ce5811462acc297bff75d33f999cd8f
// Adjusted to remove an invalid surrogate pair which Foundation's JSON parser refuses to parse.


extension WebPlatformTests {

  func testURLConstructor() throws {
    let testFile = try loadTestFile(.WPTURLConstructorTests, as: WPTConstructorTest.TestFile.self)
    assert(
      testFile.count == 765,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )

    var harness = WPTConstructorTest.WebURLReportHarness(expectedFailures: [
      // These test failures are due to us not having implemented the `domain2ascii` transform,
      // often in combination with other features (e.g. with percent encoding).
      //
      263,  // domain2ascii: (no-break, zero-width, zero-width-no-break) are name-prepped away to nothing.
      265,  // domain2ascii: U+3002 is mapped to U+002E (dot).
      273,  // domain2ascii: fullwidth input should be converted to ASCII and NOT IDN-ized.
      278,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      279,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      290,  // domain2ascii: Fullwidth and escaped UTF-8 fullwidth should still be treated as IP.
      393,  // domain2ascii: Hosts and percent-encoding.
      394,  // domain2ascii: Hosts and percent-encoding.
      609,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      610,  // domain2ascii: IDNA ignored code points in file URLs hosts.
    ])
    harness.runTests(testFile)
    XCTAssertEqual(harness.reportedResultCount, 666, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_constructor_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testURLConstructor_additional() throws {
    let testFile = try loadTestFile(.WebURLAdditionalConstructorTests, as: WPTConstructorTest.TestFile.self)
    var harness = WPTConstructorTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssert(harness.reportedResultCount > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_constructor_more.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}


// --------------------------------------------
// MARK: - Setters
// --------------------------------------------
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/setters_tests.json
// at version 77d54aa9e0405f737987b59331f3584e3e1c26f9


extension WebPlatformTests {

  func testURLSetters() throws {
    let testFile = try loadTestFile(.WPTURLSetterTests, as: WPTSetterTest.TestFile.self)
    var harness = WPTSetterTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssert(harness.entriesSeen > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_setters_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testURLSetters_additional() throws {
    let testFile = try loadTestFile(.WebURLAdditionalSetterTests, as: WPTSetterTest.TestFile.self)
    var harness = WPTSetterTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssert(harness.entriesSeen > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_setters_more.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}
