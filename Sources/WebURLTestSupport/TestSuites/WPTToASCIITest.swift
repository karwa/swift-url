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

import Foundation

public enum WPTToASCIITest {}


// --------------------------------------------
// MARK: - Test file data model
// --------------------------------------------


extension WPTToASCIITest {

  /// The contents of a WPT URL ToASCII test file.
  ///
  public typealias TestFile = [TestCase]
}


// --------------------------------------------
// MARK: - Test Suite
// --------------------------------------------
// See https://github.com/web-platform-tests/wpt/blob/master/url/README.md for more information.


extension WPTToASCIITest: TestSuite {

  public typealias Harness = _WPTToASCIITest_Harness

  public struct TestCase: Hashable, Codable {

    public var comment: String?

    /// The domain to be parsed according to the rules of UTS #46 (as stipulated by the URL Standard).
    ///
    public var input: String

    /// The expected output of the parser after serialization. An output of `nil` means parsing is expected to fail.
    ///
    public var output: String?

    public init(comment: String?, input: String, output: String?) {
      self.comment = comment
      self.input = input
      self.output = output
    }
  }

  public struct CapturedData: Hashable {

    public var parserResult: URLValues?
    public var hostnameSetterResult: URLValues?

    public init(parserResult: URLValues? = nil, hostnameSetterResult: URLValues? = nil) {
      self.parserResult = parserResult
      self.hostnameSetterResult = hostnameSetterResult
    }
  }

  // swift-format-ignore
  public enum TestFailure: String, Hashable, CustomStringConvertible {
    case unexpectedSuccessfulParse = "The input was parsed successfully, but was expected to fail"
    case unexpectedFailureToParse = "The input failed to parse, but was expected to succeed"
    case unexpectedSuccessfulSet = "The 'set' operation was successful, but was expected to fail"
    case hostPropertyMismatch = "The host/hostname property has an unexpected value"
    case pathPropertyMismatch = "The path property has an unexpected value"
    case hrefPropertyMismatch = "The href property has an unexpected value"
  }
}

public protocol _WPTToASCIITest_Harness: TestHarnessProtocol where Suite == WPTToASCIITest {

  associatedtype ParsedURL

  func getPropertyValues(_ url: ParsedURL) -> URLValues

  /// Parses the given input string, in accordance with the WHATWG URL Standard.
  ///
  func parseURL(_ input: String) -> ParsedURL?

  /// Sets a URL's `hostname` property to the given value.
  /// The setter is expected to have the same behavior as JavaScript's `hostname` setter.
  ///
  func setHostname(_ url: inout ParsedURL, to newValue: String)
}

extension WPTToASCIITest.Harness {

  public func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>) {

    var captures = Suite.CapturedData()
    defer { result.captures = captures }

    // 1. Parse a URL with the format "https://{input}/z".
    do {
      let parserResult = parseURL("https://\(testcase.input)/z").map { getPropertyValues($0) }
      captures.parserResult = parserResult

      check: if let expectedHostname = testcase.output {

        guard let urlValues = parserResult else {
          result.failures.insert(.unexpectedFailureToParse)
          break check
        }
        if urlValues[.host] != expectedHostname || urlValues[.hostname] != expectedHostname {
          result.failures.insert(.hostPropertyMismatch)
        }
        if urlValues[.pathname] != "/z" {
          result.failures.insert(.pathPropertyMismatch)
        }
        if urlValues[.href] != "https://\(expectedHostname)/z" {
          result.failures.insert(.hrefPropertyMismatch)
        }

      } else {

        if parserResult != nil {
          result.failures.insert(.unexpectedSuccessfulParse)
        }

      }
    }

    // 2. We don't implement the '.host' setter.

    // 3. Set an HTTPS URL's '.hostname' to {input}.
    do {
      guard var url = parseURL("https://y/z") else {
        preconditionFailure("'https://y/z' failed to parse? Come on...")
      }
      setHostname(&url, to: testcase.input)
      let urlValues = getPropertyValues(url)
      captures.hostnameSetterResult = urlValues

      check: if let expectedHostname = testcase.output {

        if urlValues[.host] != expectedHostname || urlValues[.hostname] != expectedHostname {
          result.failures.insert(.hostPropertyMismatch)
        }
        if urlValues[.pathname] != "/z" {
          result.failures.insert(.pathPropertyMismatch)
        }
        if urlValues[.href] != "https://\(expectedHostname)/z" {
          result.failures.insert(.hrefPropertyMismatch)
        }

      } else {

        if urlValues[.hostname] != "y" {
          result.failures.insert(.unexpectedSuccessfulSet)
        }

      }
    }

    // Finished.
  }
}

extension TestHarnessProtocol where Suite == WPTToASCIITest {

  public mutating func runTests(_ tests: [WPTToASCIITest.TestCase]) {
    var index = 0
    for testcase in tests {
      var result = TestResult<Suite>(testNumber: index, testCase: testcase)
      _runTestCase(testcase, &result)
      reportTestResult(result)
      index += 1
    }
  }
}
