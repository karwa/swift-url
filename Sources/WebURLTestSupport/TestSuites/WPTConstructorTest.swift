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

public enum WPTConstructorTest {}


// --------------------------------------------
// MARK: - Test file data model
// --------------------------------------------


extension WPTConstructorTest {

  /// The contents of a WPT URL constructor test file.
  ///
  public typealias TestFile = [FileEntry]

  /// An entry in a WPT URL constructor test file; either a comment or a constructor test case.
  ///
  public enum FileEntry: Codable {
    case comment(String)
    case testcase(TestCase)

    public init(from decoder: Decoder) throws {
      if let testcase = try? TestCase(from: decoder) {
        self = .testcase(testcase)
      } else {
        self = .comment(try decoder.singleValueContainer().decode(String.self))
      }
    }

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .comment(let header):
        var container = encoder.singleValueContainer()
        try container.encode(header)
      case .testcase(let testcase):
        try testcase.encode(to: encoder)
      }
    }
  }
}


// --------------------------------------------
// MARK: - Test Suite
// --------------------------------------------
// See https://github.com/web-platform-tests/wpt/blob/master/url/README.md for more information.


// TODO: Update WPT README. 'base' is NOT always present since https://github.com/web-platform-tests/wpt/pull/29579

extension WPTConstructorTest: TestSuite {

  public typealias Harness = _WPTConstructorTest_Harness

  public struct TestCase: Hashable, Codable {

    /// An absolute URL as a string whose parsing without a base of its own must succeed.
    ///
    public var base: String?

    /// A URL as a string to be parsed with `base` as its base URL.
    ///
    public var input: String

    /// The properties of the URL record obtained by parsing `input` against `base`.
    ///
    /// If `nil`, parsing should return failure.
    /// Otherwise, the `href`, `origin`, `protocol`, `username`, `password`, `host`, `hostname`,
    /// `port`, `pathname`, `search`, and `hash` values should match the corresponding properties of the URL record.
    ///
    /// The `origin` key may be missing. In that case, the API’s `origin` attribute is not tested.
    ///
    public var expectedValues: URLValues? = nil

    /// Whether parsing `input` against `base` is expected to return failure.
    ///
    public var failure: Bool {
      return expectedValues == nil
    }

    public init(input: String, base: String?, expectedValues: URLValues?) {
      self.input = input
      self.base = base
      self.expectedValues = expectedValues
    }

    enum CodingKeys: String, CodingKey {
      case input = "input"
      case base = "base"

      case failure = "failure"

      case href = "href"
      case origin = "origin"
      case `protocol` = "protocol"
      case username = "username"
      case password = "password"
      case host = "host"
      case hostname = "hostname"
      case port = "port"
      case pathname = "pathname"
      case search = "search"
      case hash = "hash"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.input = try container.decode(String.self, forKey: .input)
      self.base = try container.decode(String?.self, forKey: .base)

      if let xfail = try? container.decode(Bool.self, forKey: .failure) {
        assert(xfail, "A failure key means the test is expected to fail; is always 'true' if present")
        self.expectedValues = nil
      } else {
        self.expectedValues = URLValues(
          href: try container.decode(String.self, forKey: .href),
          origin: try? container.decode(String.self, forKey: .origin),
          protocol: try container.decode(String.self, forKey: .protocol),
          username: try container.decode(String.self, forKey: .username),
          password: try container.decode(String.self, forKey: .password),
          host: try container.decode(String.self, forKey: .host),
          hostname: try container.decode(String.self, forKey: .hostname),
          port: try container.decode(String.self, forKey: .port),
          pathname: try container.decode(String.self, forKey: .pathname),
          search: try container.decode(String.self, forKey: .search),
          hash: try container.decode(String.self, forKey: .hash)
        )
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(input, forKey: .input)
      try container.encode(base, forKey: .base)
      if let expectedValues = expectedValues {
        try container.encodeIfPresent(expectedValues[.href], forKey: .href)
        try container.encodeIfPresent(expectedValues[.origin], forKey: .origin)
        try container.encodeIfPresent(expectedValues[.protocol], forKey: .protocol)
        try container.encodeIfPresent(expectedValues[.username], forKey: .username)
        try container.encodeIfPresent(expectedValues[.password], forKey: .password)
        try container.encodeIfPresent(expectedValues[.host], forKey: .host)
        try container.encodeIfPresent(expectedValues[.hostname], forKey: .hostname)
        try container.encodeIfPresent(expectedValues[.port], forKey: .port)
        try container.encodeIfPresent(expectedValues[.pathname], forKey: .pathname)
        try container.encodeIfPresent(expectedValues[.search], forKey: .search)
        try container.encodeIfPresent(expectedValues[.hash], forKey: .hash)
      } else {
        try container.encode(true, forKey: .failure)
      }
    }
  }

  public struct CapturedData: Hashable {
    /// The URL record properties formed by parsing `input` against `base`.
    ///
    public var propertyValues: URLValues?

    public init(propertyValues: URLValues? = nil) {
      self.propertyValues = propertyValues
    }
  }

  // swift-format-ignore
  public enum TestFailure: String, Hashable, CustomStringConvertible {
    case baseURLFailedToParse = "Parsing the base URL must always succeed."
    case inputDidNotFailWhenUsedAsBaseURL = "A URL which fails to parse with a valid base must also fail to parse with no base (i.e. when used as a base itself)."
    case unexpectedFailureToParse = "URL failed to parse but wasn't an expected failure."
    case unexpectedSuccessfulParse = "URL was parsed successfully, but was expected to fail."
    case propertyMismatch = "The parsed URL's properties do not match the expected values."
    case notIdempotent = "The URL was parsed, serialized, and re-parsed, and produced a different result the second time around."
  }
}

public protocol _WPTConstructorTest_Harness: TestHarnessProtocol where Suite == WPTConstructorTest {

  /// Parses the given input string, relative to the given base URL, in accordance with the WHATWG URL Standard,
  /// and returns a `URLValues` containing values for the properties specified in the standard.
  /// If parsing fails, returns `nil`.
  ///
  func parseURL(_ input: String, base: String?) -> URLValues?
}

extension WPTConstructorTest.Harness {

  public func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>) {

    var captures = Suite.CapturedData()
    defer { result.captures = captures }

    // 1. If a base URL is given, parsing it must always succeed.
    if let base = testcase.base, parseURL(base, base: nil) == nil {
      result.failures.insert(.baseURLFailedToParse)
    }

    // 2. If failure = true, parsing "about:blank" against input must fail.
    if testcase.failure && parseURL("about:blank", base: testcase.input) != nil {
      result.failures.insert(.inputDidNotFailWhenUsedAsBaseURL)
    }

    // 3. Parse input against base.
    guard let parsedVals = parseURL(testcase.input, base: testcase.base) else {
      if !testcase.failure { result.failures.insert(.unexpectedFailureToParse) }
      return
    }
    captures.propertyValues = parsedVals

    // 4. Check the URL record's values against the expected values.
    if let expectedValues = testcase.expectedValues {
      if !parsedVals.allMismatchingURLProperties(comparedWith: expectedValues).isEmpty {
        result.failures.insert(.propertyMismatch)
      }
    } else {
      result.failures.insert(.unexpectedSuccessfulParse)
    }

    // 5. Check idempotence: parse the href again and check all properties.
    var serialized = parsedVals[.href]!
    serialized.makeContiguousUTF8()
    guard let reparsed = parseURL(serialized, base: nil) else {
      result.failures.insert(.notIdempotent)
      return
    }
    if !parsedVals.allMismatchingURLProperties(comparedWith: reparsed).isEmpty {
      result.failures.insert(.notIdempotent)
    }

    // Finished.
  }
}

extension TestHarnessProtocol where Suite == WPTConstructorTest {

  public mutating func runTests(_ tests: [WPTConstructorTest.FileEntry]) {
    var index = 0
    for sectionOrTestcase in tests {
      switch sectionOrTestcase {
      case .comment(let name):
        markSection(name)
      case .testcase(let testcase):
        var result = TestResult<Suite>(testNumber: index, testCase: testcase)
        _runTestCase(testcase, &result)
        reportTestResult(result)
        index += 1
      }
    }
  }
}
