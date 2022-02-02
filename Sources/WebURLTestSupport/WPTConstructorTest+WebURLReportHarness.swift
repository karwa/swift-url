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

extension WPTConstructorTest {

  /// A harness for running a series of `WPTConstructorTest`s with the `WebURL` parser,
  /// and accumulating the results in a `SimpleTestReport`.
  ///
  public struct WebURLReportHarness {
    public private(set) var report = SimpleTestReport()
    public private(set) var reportedResultCount = 0
    public let expectedFailures: Set<Int>

    public init(expectedFailures: Set<Int> = []) {
      self.expectedFailures = expectedFailures
    }
  }
}

extension WPTConstructorTest.WebURLReportHarness: WPTConstructorTest.Harness {

  public func parseURL(_ input: String, base: String?) -> URLValues? {
    return WebURL.JSModel(input, base: base)?.urlValues
  }

  public mutating func markSection(_ name: String) {
    report.markSection(name)
  }

  public mutating func reportTestResult(_ result: TestResult<Suite>) {
    reportedResultCount += 1
    report.performTest { reporter in
      if expectedFailures.contains(result.testNumber) { reporter.expectedResult = .fail }
      reporter.reportTestResult(result)
    }
  }
}
