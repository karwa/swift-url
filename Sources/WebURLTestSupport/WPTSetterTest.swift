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

public enum WPTSetterTest {}


// --------------------------------------------
// MARK: - Test file data model
// --------------------------------------------


extension WPTSetterTest {

  /// The contents of a WPT URL setter test file.
  ///
  public struct TestFile: Codable {
    public var tests: [URLModelProperty: [Testcase]]

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: URLModelProperty.self)
      var tests = [URLModelProperty: [Testcase]]()
      for key in URLModelProperty.allCases {
        let testcases = try container.decodeIfPresent([Testcase].self, forKey: key)
        tests[key] = testcases
      }
      self.tests = tests
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: URLModelProperty.self)
      for (property, testcases) in tests {
        try container.encode(testcases, forKey: property)
      }
    }
  }

  /// A WPT URL setter test for a particular property, consisting of a starting URL, new value for the property, and expected property values after the set operation.
  ///
  public struct Testcase: Equatable, Hashable, Codable {
    public var comment: String?
    public var href: String
    public var new_value: String
    public var expected: [URLModelProperty: String]

    enum CodingKeys: String, CodingKey {
      case comment = "comment"
      case href = "href"
      case new_value = "new_value"
      case expected = "expected"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
      self.href = try container.decode(String.self, forKey: .href)
      self.new_value = try container.decode(String.self, forKey: .new_value)
      let expectedValuesContainer = try container.nestedContainer(keyedBy: URLModelProperty.self, forKey: .expected)
      self.expected = [:]
      for prop in expectedValuesContainer.allKeys {
        expected[prop] = try expectedValuesContainer.decode(String.self, forKey: prop)
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(comment, forKey: .comment)
      try container.encode(href, forKey: .href)
      try container.encode(new_value, forKey: .new_value)
      var expectedValuesContainer = container.nestedContainer(keyedBy: URLModelProperty.self, forKey: .expected)
      for (property, value) in expected {
        try expectedValuesContainer.encode(value, forKey: property)
      }
    }
  }
}


// --------------------------------------------
// MARK: - Test harness
// --------------------------------------------


extension WPTSetterTest {

  /// An object which runs a set of WPT URL setter tests and processes their results.
  ///
  public typealias Harness = _WPTSetterTest_Harness
}

public protocol _WPTSetterTest_Harness {

  associatedtype URLType

  /// Parses the given input string in accordance with the WHATWG URL Standard, and returns a `URLType` with the result. If parsing fails, returns `nil`.
  ///
  func parseURL(_ input: String) -> URLType?

  /// Performs the 'set' operation, setting the given property to the given value on the given url object.
  ///
  func setValue(_ newValue: String, forProperty property: URLModelProperty, on url: inout URLType)

  /// Extracts the `URLValues` from the given url object.
  ///
  func urlValues(_: URLType) -> URLValues

  /// A callback that is invoked after the harness executes a URL setter test, providing the results of that test.
  /// This callback is invoked with the results of every test that is executed, including those whose results are not unexpected.
  ///
  mutating func reportTestResult(_ result: WPTSetterTest.Result)
}

extension WPTSetterTest {

  /// The result of executing a WPT URL setter test.
  ///
  public struct Result: Equatable, Hashable {

    /// The property that was set by this test.
    public var property: URLModelProperty

    /// The test that was run.
    public var testcase: Testcase

    /// The URL's values after setting `property` to the value given by `testcase`.
    public var resultingValues: URLValues?

    /// The set of test steps that failed.
    ///
    /// If empty, the URL object appeared to behave in accordance with the URL standard.
    ///
    public var failures: Failures
  }

  /// The set of test steps which a WPT URL setter test failed (if any).
  ///
  public struct Failures: OptionSet, Equatable, Hashable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    /// No failures.
    public static var noFailures: Self { .init(rawValue: 0) }

    /// The starting URL failed to parse.
    public static var failedToParse: Self { .init(rawValue: 1 << 0) }

    /// The URL did not contain the expected values after setting.
    public static var propertyMismatches: Self { .init(rawValue: 1 << 1) }

    /// After setting, the URL was serialized and re-parsed, and produced a different result the second time around.
    public static var notIdempotent: Self { .init(rawValue: 1 << 2) }
  }
}

extension WPTSetterTest.Harness {

  /// Runs the WPT URL setter tests in the given `TestFile`.
  ///
  public mutating func runTests(_ testFile: WPTSetterTest.TestFile) {
    runTests(testFile.tests)
  }

  /// Runs the given collection of WPT URL setter tests.
  ///
  public mutating func runTests(_ tests: [URLModelProperty: [WPTSetterTest.Testcase]]) {
    for (property, testcases) in tests {
      for testcase in testcases {
        var result = WPTSetterTest.Result(
          property: property, testcase: testcase, resultingValues: nil, failures: .noFailures
        )
        defer { reportTestResult(result) }
        // 1. Parse the URL.
        guard var url = parseURL(testcase.href) else {
          result.failures.insert(.failedToParse)
          return
        }
        // 2. Set the value.
        setValue(testcase.new_value, forProperty: property, on: &url)
        let values = urlValues(url)
        result.resultingValues = values
        // 3. Check all given keys against their expected values.
        for (expected_key, expected_value) in testcase.expected {
          if values[expected_key] != expected_value {
            result.failures.insert(.propertyMismatches)
          }
        }
        // 4. (Not in standard). Check that modified URL is idempotent WRT serialization.
        guard
          let reparsedValues = parseURL(values[.href]!).map({ urlValues($0) }),
          values.allMismatchingURLProperties(comparedWith: reparsedValues).isEmpty
        else {
          result.failures.insert(.notIdempotent)
          return
        }
      }
    }
  }
}
