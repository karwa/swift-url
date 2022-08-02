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
    public let std3Tests: Set<Int>

    public init(std3Tests: Set<Int> = []) {
      self.std3Tests = std3Tests
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
      // So how do we test UseSTD3ASCIIRules=false?
      //
      // The spec functions always produce an output string, sometimes with an accompanying set of errors.
      // Our implementation should always return the same string as the spec/test file, but where it expects us
      // to also return an STD3-related validation error, we won't return that error.
      // Result is the same; we're just more lenient about some particular scalars and don't consider them an "error".

      if std3Tests.contains(result.testNumber) {

        // 1. The testcase expects the function to produce a validation error
        //    due to a disallowed codepoint in the input (P1/V6).
        let expectedFailures = UTS46Conformance.FailableValidationSteps.parse(result.testCase.toAsciiN.status)
        assert(expectedFailures.contains(where: { $0 == .P1 || $0 == .V6 }))

        // 2. But neither toUnicode nor toASCII actually produced an error for this input.
        assert(result.failures == [.toUnicode, .toAsciiN])
        assert(result.captures!.toAsciiNResult != nil)
        assert(result.captures!.toUnicodeResult != nil)

        // 3. The output we produced matches what was expected, besides the lack of error.
        //    And it should be an exact match - the same scalars, same code-units. Not just "canonically equivalent".
        assert(result.captures!.toUnicodeResult?.utf8.elementsEqual(result.testCase.toUnicode.result) == true)
        assert(result.captures!.toAsciiNResult?.utf8.elementsEqual(result.testCase.toAsciiN.result) == true)

        // 4. Also, toASCII with (beStrict = true) does indeed fail with an error.
        let successInStrictMode = IDNA.toASCII(utf8: result.testCase.source, beStrict: true) { _ in }
        assert(!successInStrictMode)

        // 5. Sure enough, if we examine the _expected_ toUnicode result,
        //    we find a scalar which we have marked as `disallowed_STD3_valid`.
        let expectedToUnicode = String(decoding: result.testCase.toUnicode.result, as: UTF8.self)
        assert(expectedToUnicode.unicodeScalars.contains(where: { IDNA._SPIs._isDisallowed_STD3_valid($0) }))

        // X. If all of these checks passed, we appear to be producing the correct result
        //    for an implementation where UseSTD3ASCIIRules=false.
        reporter.expectedResult = .fail
      }
      reporter.reportTestResult(result)
    }
  }
}
