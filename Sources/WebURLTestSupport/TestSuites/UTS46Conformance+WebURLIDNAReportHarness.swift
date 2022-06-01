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

import IDNA

extension UTS46Conformance {

  public struct WebURLIDNAReportHarness {
    public private(set) var report = SimpleTestReport()
    public private(set) var reportedResultCount = 0
    public let std3Deviations: Set<Int>

    public init(std3Deviations: Set<Int> = []) {
      self.std3Deviations = std3Deviations
    }
  }
}

extension UTS46Conformance.WebURLIDNAReportHarness: UTS46Conformance.Harness {

  // ToUnicode.

  // swift-format-ignore
  public static var ToUnicode_NonApplicableValidationSteps: Set<UTS46Conformance.FailableValidationSteps> = [
    .V2, .V3,    // CheckHyphens
    .NV8,        // IDNA2008 extras
    .X3, .X4_2,  // Thrown by older versions of the standard.
  ]

  public func toUnicode<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> String? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    var result = ""
    let success = IDNA.toUnicode(utf8: utf8) { label, dot in
      result.unicodeScalars += label
      if dot { result += "." }
      return true
    }
    return success ? result : nil
  }

  // ToAsciiN.

  // swift-format-ignore
  public static var ToAsciiN_NonApplicableValidationSteps: Set<UTS46Conformance.FailableValidationSteps> = [
    .A4_1, .A4_2,  // VerifyDnsLength
    .V2, .V3,      // CheckHyphens
    .NV8,          // IDNA2008 extras
    .X3, .X4_2,    // Thrown by older versions of the standard.
  ]

  public func toAsciiN<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> String? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    var result = [UInt8]()
    let success = IDNA.toASCII(utf8: utf8) { result.append($0) }
    return success ? String(decoding: result, as: UTF8.self) : nil
  }

  // Reporting.

  public mutating func markSection(_ name: String) {
    report.markSection(name)
  }

  public mutating func reportTestResult(_ result: TestResult<UTS46Conformance>) {
    reportedResultCount += 1
    report.performTest { reporter in
      if std3Deviations.contains(result.testNumber) {
        if !result.failures.isEmpty {
          // This testcase should expect a disallowed codepoint.
          let expectedFailures = UTS46Conformance.FailableValidationSteps.parse(result.testCase.toAsciiN.status)
          assert(expectedFailures.contains(where: { $0 == .P1 || $0 == .V6 }))

          // The expected toUnicode result should contain a scalar which we think is disallowed_STD3_valid.
          let expectedScalars = String(decoding: result.testCase.toUnicode.result, as: UTF8.self).unicodeScalars
          let hasSTD3Disallowed = expectedScalars.contains(where: { IDNA._isDisallowed_STD3_valid($0) })
          assert(hasSTD3Disallowed)

          // The actual result should be the same for toAscii and toUnicode - that we are more lenient.
          assert(result.failures == [.toUnicode, .toAsciiN])
          assert(result.captures?.toAsciiNResult != nil)
          assert(result.captures?.toUnicodeResult != nil)

          // Our toUnicode result must match the expected one at the Unicode scalar level.
          assert(result.captures?.toUnicodeResult?.unicodeScalars.elementsEqual(expectedScalars) == true)

          // Ok - allow the difference in expected/actual result.
          reporter.expectedResult = .fail
        }
      }
      reporter.reportTestResult(result)
    }
  }
}
