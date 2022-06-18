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
// at version 2a64dae4641fbd61bd4257df460e188f425b492e
// Adjusted to remove an invalid surrogate pair which Foundation's JSON parser refuses to parse.


extension WebPlatformTests {

  func testURLConstructor() throws {
    let testFile = try loadTestFile(.WPTURLConstructorTests, as: WPTConstructorTest.TestFile.self)
    assert(
      testFile.count == 839,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )

    var harness = WPTConstructorTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssertEqual(harness.reportedResultCount, 737, "Unexpected number of tests executed.")
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
    XCTAssert(harness.reportedResultCount > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_setters_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testURLSetters_additional() throws {
    let testFile = try loadTestFile(.WebURLAdditionalSetterTests, as: WPTSetterTest.TestFile.self)
    var harness = WPTSetterTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssert(harness.reportedResultCount > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_setters_more.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}


// --------------------------------------------
// MARK: - ToASCII
// --------------------------------------------
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/toascii.json
// at version b772ca18865a09f3307440a9a756cb08fc0028a6
// Adjusted to delete line 2 (the comment)


extension WebPlatformTests {

  func testToASCII() throws {
    let testFile = try loadTestFile(.WPTToASCIITests, as: WPTToASCIITest.TestFile.self)
    assert(
      testFile.count == 39,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )

    var harness = WPTToASCIITest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssertEqual(harness.reportedResultCount, 39, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_toascii_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}
