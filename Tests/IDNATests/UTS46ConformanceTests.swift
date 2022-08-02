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
    var harness = WebURLTestSupport.UTS46Conformance.WebURLIDNAReportHarness(std3Tests: [

      // From UTS46:
      //
      // > A conformance testing file (IdnaTestV2.txt) is provided for each version of Unicode
      // > starting with Unicode 6.0, in versioned directories under [IDNA-Table].
      // > 👉 ** It only provides test cases for UseSTD3ASCIIRules=true. ** 👈
      // https://unicode.org/reports/tr46/#Conformance_Testing
      //
      // - The URL Standard uses UseSTD3ASCIIRules=false.
      // - We ^want^ to test UseSTD3ASCIIRules=false, because that's the code-path WebURL will actually take.
      // - Our implementation supports setting UseSTD3ASCIIRules=true, but only in toASCII,
      //   and we might remove it one day.
      //
      // The test-cases listed here are all rely on UseSTD3ASCIIRules=true.
      // The harness puts them through some additional checks to make sure that we produce the correct result.

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
    print("✏️ Report written to: \(reportURL)")
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
