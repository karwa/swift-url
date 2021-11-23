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
  public struct TestFile: Codable {
    public var tests: [FileEntry]

    public init(from decoder: Decoder) throws {
      self.tests = try decoder.singleValueContainer().decode([FileEntry].self)
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(tests)
    }
  }

  /// An entry in a WPT URL constructor test file; either a comment or a constructor test case.
  ///
  public enum FileEntry: Codable {
    case comment(String)
    case testcase(Testcase)

    public init(from decoder: Decoder) throws {
      if let testcase = try? Testcase(from: decoder) {
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

  // Note: 'base' is NOT always present since https://github.com/web-platform-tests/wpt/pull/29579
  //       WPT README needs to be updated.
  /// A data structure containing information for a WPT URL constructor test.
  ///
  /// Details from https://github.com/web-platform-tests/wpt/blob/master/url/README.md as of `09d8830`:
  ///
  /// The keys for each test case are:
  ///
  /// - `base`: an absolute URL as a string whose parsing without a base of its own must succeed.
  ///   This key is always present, and may have a value like "about:blank" when `input` is an absolute URL.
  /// - `input`: an URL as a string to be parsed with `base` as its base URL.
  /// - Either:
  ///    - `failure` with the value `true`, indicating that parsing `input` should return failure,
  ///    - or `href`, `origin`, `protocol`, `username`, `password`, `host`, `hostname`, `port`, `pathname`, `search`, and `hash`
  ///      with string values; indicating that parsing `input` should return an URL record and that the getters of each corresponding attribute in that
  ///      URL’s API should return the corresponding value.
  ///
  ///      The `origin` key may be missing. In that case, the API’s `origin` attribute is not tested.
  ///
  public struct Testcase: Equatable, Hashable, Codable {
    public var input: String
    public var base: String?
    public var expectedValues: URLValues? = nil

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
}

extension WPTConstructorTest.Testcase: CustomStringConvertible {

  public var description: String {
    guard let expectedValues = expectedValues else {
      return """
        {
          .input:    \(input)
          .base:     \(base ?? "<nil>")
            -- expected failure --
        }
        """
    }
    return """
      {
        .input:    \(input)
        .base:     \(base ?? "<nil>")

        .href:     \(expectedValues[.href]!)
        .origin:   \(expectedValues.origin ?? "<not present>")
        .protocol: \(expectedValues[.protocol]!)
        .username: \(expectedValues[.username]!)
        .password: \(expectedValues[.password]!)
        .host:     \(expectedValues[.host]!)
        .hostname: \(expectedValues[.hostname]!)
        .port:     \(expectedValues[.port]!)
        .pathname: \(expectedValues[.pathname]!)
        .search:   \(expectedValues[.search]!)
        .hash:     \(expectedValues[.hash]!)
      }
      """
  }
}


// --------------------------------------------
// MARK: - Test harness
// --------------------------------------------


extension WPTConstructorTest {

  /// An object which runs a set of WPT URL constructor tests and processes its results.
  ///
  public typealias Harness = _WPTConstructorTest_Harness
}

public protocol _WPTConstructorTest_Harness {

  /// Parses the given input string, relative to the given base URL, in accordance with the WHATWG URL Standard, and returns
  /// a `URLValues` containing values for the properties specified in the standard. If parsing fails, returns `nil`.
  ///
  func parseURL(_ input: String, base: String?) -> URLValues?

  /// A callback that is invoked when the harness encounters a comment in the constructor test file.
  ///
  mutating func reportComment(_ comment: String)

  /// A callback that is invoked after the harness executes a WPT URL constructor testcase and provides its results.
  ///
  /// This callback is invoked with the results of each testcase that is executed, including those whose results are not unexpected.
  ///
  mutating func reportTestResult(_ result: WPTConstructorTest.Result)
}

extension WPTConstructorTest.Harness {

  public nonmutating func reportComment(_ comment: String) {
    // No-op.
  }
}

extension WPTConstructorTest {

  /// The result of executing a WPT URL constructor test.
  ///
  public struct Result: Equatable, Hashable {

    /// The number of tests that have been run prior to this test.
    public var testNumber: Int

    /// The test that was run.
    public var testcase: Testcase

    /// The URL record properties formed by parsing the `input` and `base` values specified in `testcase`.
    public var propertyValues: URLValues?

    /// The set of test steps that failed.
    ///
    /// If empty, the URL parser appeared to behave in accordance with the URL standard for the `input` and `base` values in `testcase`.
    ///
    public var failures: Failures

    public init(testNumber: Int, testcase: Testcase, propertyValues: URLValues?, failures: Failures) {
      self.testNumber = testNumber
      self.testcase = testcase
      self.propertyValues = propertyValues
      self.failures = failures
    }
  }

  /// The set of test steps which a WPT URL constructor test failed (if any).
  ///
  public struct Failures: OptionSet, Equatable, Hashable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    /// No failures.
    public static var noFailures: Self { .init(rawValue: 0) }

    /// Parsing the base URL must always succeed.
    public static var baseURLFailedToParse: Self { .init(rawValue: 1 << 0) }

    /// A URL which fails to parse with a valid base must also fail to parse with no base (i.e. when used as a base itself).
    public static var inputDidNotFailWhenUsedAsBaseURL: Self { .init(rawValue: 1 << 1) }

    /// URL failed to parse but wasn't an expected failure.
    public static var unexpectedFailureToParse: Self { .init(rawValue: 1 << 2) }

    /// URL was parsed successfully parsed, but was expected to fail.
    public static var unexpectedSuccessfulParse: Self { .init(rawValue: 1 << 3) }

    /// The parsed URL's properties do not match the expected values.
    public static var propertyMismatch: Self { .init(rawValue: 1 << 4) }

    /// The URL was parsed, serialized, and re-parsed, and produced a different result the second time around.
    public static var notIdempotent: Self { .init(rawValue: 1 << 5) }
  }
}

extension WPTConstructorTest.Harness {

  /// Runs the WPT URL constructor tests in the given `TestFile`.
  ///
  public mutating func runTests(_ testFile: WPTConstructorTest.TestFile) {
    runTests(testFile.tests)
  }

  /// Runs the given collection of WPT URL constructor tests.
  ///
  public mutating func runTests(_ tests: [WPTConstructorTest.FileEntry]) {

    var index = 0
    for entry in tests {
      switch entry {
      case .comment(let comment):
        reportComment(comment)
      case .testcase(let testcase):
        var result = WPTConstructorTest.Result(
          testNumber: index, testcase: testcase, propertyValues: nil, failures: .noFailures
        )
        defer {
          reportTestResult(result)
          index += 1
        }
        // If a base URL is given, parsing it must always succeed.
        if let base = testcase.base, parseURL(base, base: nil) == nil {
          result.failures.insert(.baseURLFailedToParse)
        }
        // If failure = true, parsing "about:blank" against input must fail.
        if testcase.failure && parseURL("about:blank", base: testcase.input) != nil {
          result.failures.insert(.inputDidNotFailWhenUsedAsBaseURL)
        }
        guard let parsedVals = parseURL(testcase.input, base: testcase.base) else {
          if !testcase.failure { result.failures.insert(.unexpectedFailureToParse) }
          continue
        }
        if let expectedValues = testcase.expectedValues {
          if !parsedVals.allMismatchingURLProperties(comparedWith: expectedValues).isEmpty {
            result.failures.insert(.propertyMismatch)
          }
        } else {
          result.failures.insert(.unexpectedSuccessfulParse)
        }
        // Check idempotence: parse the href again and check all properties.
        var serialized = parsedVals[.href]!
        serialized.makeContiguousUTF8()
        guard let reparsed = parseURL(serialized, base: nil) else {
          result.failures.insert(.notIdempotent)
          continue
        }
        if !parsedVals.allMismatchingURLProperties(comparedWith: reparsed).isEmpty {
          result.failures.insert(.notIdempotent)
        }
      }
    }
  }
}
