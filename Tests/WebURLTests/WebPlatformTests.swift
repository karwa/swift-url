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

func loadTestResource(name: String) -> Data? {
  // Yeah. This is for real.
  // I'm pretty massively disappointed that I need to do this.
  #if os(macOS)
    let url = Bundle.module.url(forResource: "Resources/\(name)", withExtension: "json")!
    return try? Data(contentsOf: url)  
  #else
    var path = #filePath
    path.removeLast(22) // "WebPlatformTests.swift"
    path += "Resources/\(name).json"
    return FileManager.default.contents(atPath: path)
  #endif
}


// --------------------------------------------
// MARK: - URL Constructor
// --------------------------------------------
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json
// at version 33e4ac09029c463ea6ee57d6f33477a9043e98e8
// Adjusted to remove an invalid surrogate pair which Foundation's JSON parser refuses to parse.


extension WebPlatformTests {

  func testURLConstructor() throws {
    let data = loadTestResource(name: "urltestdata")!
    let testFile = try JSONDecoder().decode(WPTConstructorTest.TestFile.self, from: data)
    assert(
      testFile.tests.count == 665,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )

    var harness = WPTConstructorTest.WebURLReportHarness(expectedFailures: [
      // These test failures are due to us not having implemented the `domain2ascii` transform,
      // often in combination with other features (e.g. with percent encoding).
      //
      261,  // domain2ascii: (no-break, zero-width, zero-width-no-break) are name-prepped away to nothing.
      263,  // domain2ascii: U+3002 is mapped to U+002E (dot).
      269,  // domain2ascii: fullwidth input should be converted to ASCII and NOT IDN-ized.
      274,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      275,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      286,  // domain2ascii: Fullwidth and escaped UTF-8 fullwidth should still be treated as IP.
      369,  // domain2ascii: Hosts and percent-encoding.
      370,  // domain2ascii: Hosts and percent-encoding.
      566,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      567,  // domain2ascii: IDNA ignored code points in file URLs hosts.
    ])
    harness.runTests(testFile)
    XCTAssert(harness.entriesSeen == 665, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_constructor_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testURLConstructor_additional() throws {
    let data = loadTestResource(name: "additional_constructor_tests")!
    let testFile = try JSONDecoder().decode(WPTConstructorTest.TestFile.self, from: data)
    assert(
      testFile.tests.count == 83,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )

    var harness = WPTConstructorTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssert(harness.entriesSeen == 83, "Unexpected number of tests executed.")
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
// at version 050308a616a8388f1ad5d6e87eac0270fd35023f


extension WebPlatformTests {

  func testURLSetters() throws {
    let data = loadTestResource(name: "setters_tests")!
    let testFile = try JSONDecoder().decode(WPTSetterTest.TestFile.self, from: data)

    var harness = WPTSetterTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssertEqual(harness.entriesSeen, 156, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_setters_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testURLSetters_additional() throws {
    let data = loadTestResource(name: "additional_setters_tests")!
    let testFile = try JSONDecoder().decode(WPTSetterTest.TestFile.self, from: data)

    var harness = WPTSetterTest.WebURLReportHarness()
    harness.runTests(testFile)
    XCTAssertEqual(harness.entriesSeen, 5, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl_setters_more.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}
