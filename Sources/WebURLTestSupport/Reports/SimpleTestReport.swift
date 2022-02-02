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

/// An object which captures data and results from individual tests, allowing for summary reports to be generated.
///
/// Tests can be added and organized via functions such as  `performTest`, `markSection`, and `skipTest`, and summary
/// data can be accessed via properties such as `hasUnexpectedResults` and `generateReport`.
///
public struct SimpleTestReport {

  public enum Result {
    case pass, fail
  }

  public struct Reporter {
    public var expectedResult = Result.pass
    fileprivate var actualResult = Result.pass
    fileprivate var capturedData = [(String, Any)]()
    fileprivate var failureKeys = [String]()
  }

  struct Section {
    var name: String?
    var reporters: [Reporter?] = []
  }

  var sections: [Section] = [.init()]

  public init() {
  }

  /// Marks the start of a named test section. All tests executed after this method is called will belong to this section, until the next section is marked.
  ///
  public mutating func markSection(_ name: String) {
    sections.append(Section(name: name))
  }

  /// Marks a test as "skipped". The test index is advanced, so that later indexes remain aligned to the correct tests, but no result (expected/unexpected) is recorded.
  ///
  public mutating func skipTest(count: Int = 1) {
    precondition(count >= 0)
    sections[sections.count - 1].reporters.append(contentsOf: repeatElement(nil, count: count))
  }

  /// Performs a test. The given closure is invoked with a mutable `Reporter` object and test index.
  /// Refer to `Reporter`'s API to find out how to make testable assertions that will be logged in the test report.
  ///
  public mutating func performTest(_ test: (inout Reporter) throws -> Void) {
    var reporter = Reporter()
    do {
      try test(&reporter)
    } catch {
      reporter.uncaughtError(error)
    }
    sections[sections.count - 1].reporters.append(reporter)
  }

  /// Whether or not this report contains any unexpected test results (unexpected passes or failures).
  ///
  public var hasUnexpectedResults: Bool {
    return sections.contains { section in
      section.reporters.contains { reporter in
        reporter?.actualResult != reporter?.expectedResult
      }
    }
  }
}

extension SimpleTestReport.Reporter {

  /// Captures the given test artefact for inclusion in the test report.
  ///
  public mutating func capture(key: String, _ object: Any) {
    capturedData.append((key, object))
  }

  public mutating func fail(_ key: String? = nil) {
    actualResult = .fail
    key.map { failureKeys.append($0) }
  }

  public mutating func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ key: String? = nil) {
    if lhs != rhs { fail(key) }
  }

  public mutating func expectTrue(_ lhs: Bool, _ key: String? = nil) {
    if lhs == false { fail(key) }
  }

  public mutating func expectFalse(_ lhs: Bool, _ key: String? = nil) {
    if lhs == true { fail(key) }
  }

  mutating fileprivate func uncaughtError(_ error: Error) {
    capture(key: "__uncaught_error", error)
    fail()
  }
}

extension SimpleTestReport.Reporter {

  public mutating func reportTestResult<Suite>(_ result: TestResult<Suite>) {
    capture(key: "Testcase", describe(result.testCase))
    capture(key: "Captures", describe(result.captures))
    for f in result.failures {
      fail(describe(f))
    }
  }
}

extension SimpleTestReport {

  public func generateReport() -> String {

    // Gather cumulative stats.
    var tests_count = 0
    var tests_xPass_aFail = 0
    var tests_xPass_aPass = 0
    var tests_xFail_aFail = 0
    var tests_xFail_aPass = 0
    var tests_skipped = 0

    for reporter in sections.lazy.map({ $0.reporters }).joined() {
      defer { tests_count += 1 }
      guard let reporter = reporter else {
        tests_skipped += 1
        continue
      }
      switch (reporter.expectedResult, reporter.actualResult) {
      case (.pass, .pass): tests_xPass_aPass += 1
      case (.fail, .fail): tests_xFail_aFail += 1
      case (.pass, .fail): tests_xPass_aFail += 1
      case (.fail, .pass): tests_xFail_aPass += 1
      }
    }

    var output = ""
    print(
      """
      ---------------------------------------------
      ---------------------------------------------
            \(tests_xPass_aFail + tests_xFail_aPass) tests failed (out of \(tests_count)).
      ---------------------------------------------
      Pass: \(tests_xPass_aPass + tests_xFail_aPass) (\(tests_xPass_aPass) expected)
      Fail: \(tests_xFail_aFail + tests_xPass_aFail) (\(tests_xFail_aFail) expected)
      \(tests_skipped) Tests skipped.
      ---------------------------------------------

      """, to: &output)

    func printLine() {
      print(String(repeating: "=", count: 30), to: &output)
    }

    var testNumber = 0
    for section in sections {
      // Only print the section name if it contains an unexpected result.
      var hasPrintedName = false
      func printSectionNameIfNeeded() {
        if !hasPrintedName {
          if let sectionName = section.name {
            printLine()
            print("### \(sectionName) ###", to: &output)
            printLine()
            print("", to: &output)
          }
          hasPrintedName = true
        }
      }

      for reporter in section.reporters {
        defer { testNumber += 1 }
        guard let reporter = reporter, reporter.actualResult != reporter.expectedResult else { continue }
        printSectionNameIfNeeded()

        print("[\(testNumber)]:", to: &output)
        print("", to: &output)
        print("Expected: \(reporter.expectedResult). Actual: \(reporter.actualResult)", to: &output)

        if !reporter.failureKeys.isEmpty {
          print("", to: &output)
          print("Failed checks:", to: &output)
          reporter.failureKeys.forEach {
            print("- \($0)", to: &output)
          }
        }
        if !reporter.capturedData.isEmpty {
          print("", to: &output)
          print("Captured data:", to: &output)
          reporter.capturedData.forEach {
            let (key, value) = $0
            print("- \(key):", to: &output)
            print(value, to: &output)
            print("", to: &output)
          }
        }

        print("", to: &output)
      }
    }
    return output
  }
}
