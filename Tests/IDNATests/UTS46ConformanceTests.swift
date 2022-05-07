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

class UTS46ConformanceTests: ReportGeneratingTestCase {}

extension UTS46ConformanceTests {

  func testConformance() throws {
    let lines = Array(try loadBinaryTestFile(.IdnaTest)).split(separator: UInt8(ascii: "\n"))
    var harness = WebURLTestSupport.UTS46Conformance.WebURLIDNAReportHarness(joinerFailures: [
      145,
      148,
      149,
      150,
      151,
      389,
      392,
      393,
      396,
      397,
      400,
      401,
      404,
    ])
    // harness.runTests(lines.prefix(1000))
    harness.runTests(lines)
    XCTAssertEqual(harness.reportedResultCount, 6235, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "weburl-idna-uts46-tests")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("Report written to: \(reportURL)")
  }
}

class ReportGeneratingTestCase: XCTestCase {

  private static let reportDir = ProcessInfo.processInfo.environment["SWIFT_URL_REPORT_PATH"] ?? NSTemporaryDirectory()

  override class func setUp() {
    try? FileManager.default.createDirectory(atPath: reportDir, withIntermediateDirectories: true, attributes: nil)
  }

  func fileURLForReport(named reportName: String) -> URL {
    URL(fileURLWithPath: ReportGeneratingTestCase.reportDir).appendingPathComponent(reportName)
  }
}
