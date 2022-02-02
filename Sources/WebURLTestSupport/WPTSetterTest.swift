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
    public var tests: [URLModelProperty: [TestCase]]

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: URLModelProperty.self)
      var tests = [URLModelProperty: [TestCase]]()
      for property in URLModelProperty.allCases {
        if var testcases = try container.decodeIfPresent([TestCase].self, forKey: property) {
          for i in 0..<testcases.count {
            testcases[i].property = property
          }
          tests[property] = testcases
        }
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
}


// --------------------------------------------
// MARK: - Test Suite
// --------------------------------------------
// See https://github.com/web-platform-tests/wpt/blob/master/url/README.md for more information.


extension WPTSetterTest: TestSuite {

  public typealias Harness = _WPTSetterTest_Harness

  /// A WPT URL setter test for a particular property, consisting of a starting URL, new value for the property,
  /// and expected property values after the set operation.
  ///
  public struct TestCase: Hashable, Codable {
    public var property: URLModelProperty?
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
      self.property = nil  // Unfortunately, needs to be set _after_ init.

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

  public struct CapturedData: Hashable {

    /// The URL's values after setting `property` to the value given by `testcase`.
    ///
    public var resultingValues: URLValues?
  }

  // swift-format-ignore
  public enum TestFailure: String, Hashable, CustomStringConvertible {
    case failedToParse = "The starting URL failed to parse."
    case propertyMismatches = "The URL did not contain the expected values after setting."
    case notIdempotent = "After setting, the URL was serialized and re-parsed, and produced a different result the second time around."
  }
}

public protocol _WPTSetterTest_Harness: TestHarnessProtocol where Suite == WPTSetterTest {

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
}

extension WPTSetterTest.Harness {

  public func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>) {

    var captures = Suite.CapturedData()
    defer { result.captures = captures }

    // 1. Parse the URL.
    guard var url = parseURL(testcase.href) else {
      result.failures.insert(.failedToParse)
      return
    }

    // 2. Set the value.
    setValue(testcase.new_value, forProperty: testcase.property!, on: &url)
    let values = urlValues(url)
    captures.resultingValues = values

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

extension TestHarnessProtocol where Suite == WPTSetterTest {

  /// Runs the WPT URL setter tests in the given `TestFile`.
  ///
  public mutating func runTests(_ testFile: WPTSetterTest.TestFile) {
    runTests(testFile.tests)
  }

  /// Runs the given collection of WPT URL setter tests.
  ///
  public mutating func runTests(_ tests: [URLModelProperty: [WPTSetterTest.TestCase]]) {
    var index = 0
    for (property, testcases) in tests {
      markSection(property.rawValue)
      for testcase in testcases {
        var result = TestResult<Suite>(testNumber: index, testCase: testcase)
        _runTestCase(testcase, &result)
        reportTestResult(result)
        index += 1
      }
    }
  }
}
