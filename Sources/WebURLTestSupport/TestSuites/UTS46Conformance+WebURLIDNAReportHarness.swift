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
    public let joinerFailures: Set<Int>

    public init(joinerFailures: Set<Int> = []) {
      self.joinerFailures = joinerFailures
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

  private static func shouldSkipTest(statusCodes: ArraySlice<UInt8>) -> Bool {
    let validationFailures = UTS46Conformance.FailableValidationSteps.parse(statusCodes)

    // The UTS46 tests do not cover the options used by the URL standard.
    // https://github.com/whatwg/url/issues/341#issuecomment-1115988436
    //
    // Error codes "P1" and "V6" mean that the domain contains an invalid code-point
    // (mapping table status 'disallowed'). However, for some code-points with status
    // disallowed_STD3_valid/disallowed_STD3_mapped, that status depends on the value
    // of the UseSTD3ASCIIRules parameter.
    //
    // UTS46 isn't clear whether this parameter of ToUnicode/ToASCII should be forwarded
    // to the 'validation' step of IDNA processing. It seems like it should be, and some
    // implementations do, but the Unicode org reference implementation which generates
    // the test file does not.
    //
    // What's more, the test file is generated with UseSTD3ASCIIRules=true.
    // But with our IDNA.toUnicode function, UseSTD3ASCIIRules parameter is actually always false!
    // And toASCII's UseSTD3ASCIIRules is given by another parameter 'beStrict', which also defaults to false.
    // Because that's what URL's use.
    //
    // So - if the testcase includes expected errors "P1" or "V6", it's hard to say
    // whether our UseSTD3ASCIIRules=false implementation should still flag that error or let it pass.
    //
    // This has been reported to the WHATWG and Unicode organisation (see above).
    // It would be really great to improve on this situation by marking the errors which depend on
    // UseSTD3ASCIIRules.

    if validationFailures.contains(.P1) || validationFailures.contains(.V6) {
      return true
    }

    // Otherwise, we should run the test.

    return false
  }

  public mutating func reportTestResult(_ result: TestResult<UTS46Conformance>) {
    reportedResultCount += 1

    guard
      !Self.shouldSkipTest(statusCodes: result.testCase.toUnicode.status),
      !Self.shouldSkipTest(statusCodes: result.testCase.toAsciiN.status)
    else {
      report.skipTest()
      return
    }
    report.performTest { reporter in
      // Some tests contain valid uses of zero-width joiners.
      // We are overly strict and reject these. We'd need Joining_Type data to confirm that they are valid.
      if joinerFailures.contains(result.testNumber) {
        // assert(result.captures!.toUnicodeResult == nil)
        // assert(result.captures!.toAsciiNResult == nil)
        reporter.expectedResult = .fail
      }
      reporter.reportTestResult(result)
    }
  }
}
