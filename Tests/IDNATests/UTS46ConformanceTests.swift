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
    var harness = WebURLTestSupport.UTS46Conformance.WebURLIDNAReportHarness(std3Deviations: [

      // The UTS46 tests do not cover the options used by the URL standard.
      // https://github.com/whatwg/url/issues/341#issuecomment-1115988436
      //
      // Error codes "P1" and "V6" mean that the domain contains an invalid code-point.
      // However, the validity of some code-points depends on the value of the UseSTD3ASCIIRules parameter.
      // STD3 ASCII rules are very strict - only ASCII alphanumerics and hyphens, not even underscores are allowed.
      // URLs are more lenient - we won't fail if the hostname contains an '=' sign, for example.
      //
      // The test file is generated with UseSTD3ASCIIRules=true. This has been reported to the Unicode org and WHATWG.
      // Hopefully we'll get a unique status tag in future so we don't need to hardcode a list of deviations.

      // For each of these specific testcases, the harness will assert that:
      // - the testcase expects that errors "P1" or "V6" could be raised,
      // - the ToUnicode result contains a scalar which we think is disallowed_STD3_valid, and
      // - we are more lenient, and didn't raise an error.
      // - that our ToUnicode result matches the expected one.
      //
      // And in those cases, it will set the test as an _expected_ failure.

      425, 461, 1756, 1817, 1818, 1819, 1890, 1891,
      1892, 1893, 1894, 1895, 1896, 1897, 1898, 1899,
      1920, 2216, 2356, 2529, 2852, 2853, 2854, 3029,
      3030, 3031, 3032, 3033, 3034, 3035, 3036, 3037,
      3038, 3039, 3040, 3041, 3042, 3043, 3044, 3045,
      3046, 3047, 3082, 3083, 3084, 3085, 3086, 3283,
      3284, 3285, 3286, 3287, 3288, 3289, 3290, 3291,
      3292, 3293, 3294, 3295, 3296, 3297, 3298, 3299,
      3300, 3550, 3678, 4002, 4003, 4006, 4007, 4011,
      4012, 4578, 4774, 4775, 4776, 4777, 4778, 4990,
      5226, 5227, 5228, 5325, 5326, 5327, 5328, 5329,
      5330, 5331, 5332, 5333, 5334, 5335, 5336, 5337,
      5338, 5339, 5340, 5341, 5342, 6120, 6122, 6125,
      6126, 6128, 6130, 6133, 6135, 6220, 6224,
    ])
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
