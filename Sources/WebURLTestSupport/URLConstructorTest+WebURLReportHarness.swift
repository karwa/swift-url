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

import WebURL

extension URLConstructorTest {

  /// A harness for running a series of `URLConstructorTest`s with the `WebURL` parser and accumulating the results in a `SimpleTestReport`.
  ///
  public struct WebURLReportHarness {
    public private(set) var report = SimpleTestReport()
    public private(set) var entriesSeen = 0
    public let expectedFailures: Set<Int>

    public init(expectedFailures: Set<Int> = []) {
      self.expectedFailures = expectedFailures
    }
  }
}

extension URLConstructorTest.WebURLReportHarness: URLConstructorTest.Harness {

  public func parseURL(_ input: String, base: String?) -> URLValues? {
    return WebURL.JSModel(input, base: base)?.urlValues
  }

  public mutating func reportNonTestEntry(_ entry: URLConstructorTest.FileEntry) {
    entriesSeen += 1
    switch entry {
    case .comment(let comment): report.markSection(comment)
    case .testcase: assertionFailure("Unexpected test in reportNonTestEntry")
    }
  }

  public mutating func reportTestResult(_ result: URLConstructorTest.Result) {
    entriesSeen += 1
    report.performTest { reporter in
      reporter.capture(key: "Testcase", result.testcase)
      reporter.capture(key: "Result", result.propertyValues?.description ?? "nil")

      if expectedFailures.contains(result.testNumber) {
        reporter.expectedResult = .fail
      }
      if !result.failures.isEmpty {
        var remainingFailures = result.failures
        if let _ = remainingFailures.remove(.baseURLFailedToParse) {
          reporter.fail("base URL failed to parse")
        }
        if let _ = remainingFailures.remove(.inputDidNotFailWhenUsedAsBaseURL) {
          reporter.fail("Test is XFAIL, but input string parsed successfully without a base URL")
        }
        if let _ = remainingFailures.remove(.unexpectedFailureToParse) {
          reporter.fail("Unexpected failure to parse")
        }
        if let _ = remainingFailures.remove(.unexpectedSuccessfulParse) {
          reporter.fail("Unexpected successful parsing")
        }
        if let _ = remainingFailures.remove(.propertyMismatch) {
          let diff = URLValues.diff(result.testcase.expectedValues, result.propertyValues)
          let namedDiff = URLValues.allTestableURLProperties.filter { diff.contains($0.keyPath) }
          assert(!diff.isEmpty && !namedDiff.isEmpty, "Test failed due to mismatching properties, but diff was empty")
          for (mismatchingPropertyName, _) in namedDiff {
            reporter.fail(mismatchingPropertyName)
          }
        }
        if let _ = remainingFailures.remove(.notIdempotent) {
          reporter.fail("<idempotence>")
        }
        if !remainingFailures.isEmpty {
          assertionFailure("Unhandled failure condition")
          reporter.fail("unknown reason")
        }
      }
    }
  }
}
