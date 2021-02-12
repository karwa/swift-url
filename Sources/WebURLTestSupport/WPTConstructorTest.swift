
public enum URLConstructorTest {}


// MARK: - Test file data model.


extension URLConstructorTest {
  
  /// An entry in a WPT URL constructor test file; either a comment as a string or a test case as an object.
  ///
  public enum FileEntry: Equatable, Hashable, Codable {
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
}

extension URLConstructorTest {

  /// A data structure containing information for a URL constructor test.
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
  @dynamicMemberLookup
  public struct Testcase {
    public var input: String
    public var base: String
    public var expectedValues: URLValues? = nil
    
    public var failure: Bool {
      return expectedValues == nil
    }
    
    public subscript(dynamicMember dynamicMember: KeyPath<URLValues, String>) -> String? {
      expectedValues?[keyPath: dynamicMember]
    }
    public subscript(dynamicMember dynamicMember: KeyPath<URLValues, String?>) -> String? {
      expectedValues?[keyPath: dynamicMember]
    }
  }
}

extension URLConstructorTest.Testcase: Equatable, Hashable, Codable {
  
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
    self.base = try container.decode(String.self, forKey: .base)
    
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
      try container.encode(expectedValues.href, forKey: .href)
      try container.encode(expectedValues.protocol, forKey: .protocol)
      try container.encode(expectedValues.username, forKey: .username)
      try container.encode(expectedValues.password, forKey: .password)
      try container.encode(expectedValues.host, forKey: .host)
      try container.encode(expectedValues.hostname, forKey: .hostname)
      try container.encode(expectedValues.port, forKey: .port)
      try container.encode(expectedValues.pathname, forKey: .pathname)
      try container.encode(expectedValues.search, forKey: .search)
      try container.encode(expectedValues.hash, forKey: .hash)
    } else {
      try container.encode(true, forKey: .failure)
    }
  }
}

extension URLConstructorTest.Testcase: CustomStringConvertible {
      
  public var description: String {
    guard let expectedValues = expectedValues else {
      return """
      {
        .input:    \(input)
        .base:     \(base)
          -- expected failure --
      }
      """
    }
    return """
    {
      .input:    \(input)
      .base:     \(base)

      .href:     \(expectedValues.href)
      .protocol: \(expectedValues.`protocol`)
      .username: \(expectedValues.username)
      .password: \(expectedValues.password)
      .host:     \(expectedValues.host)
      .hostname: \(expectedValues.hostname)
      .origin:   \(expectedValues.origin ?? "<not present>")
      .port:     \(expectedValues.port)
      .pathname: \(expectedValues.pathname)
      .search:   \(expectedValues.search)
      .hash:     \(expectedValues.hash)
    }
    """
  }
}


// MARK: - Test execution.


extension URLConstructorTest {

  /// An object which runs a set of URL constructor tests and processes its results.
  ///
  public typealias Harness = _URLConstructorTest_Harness
}

public protocol _URLConstructorTest_Harness {
  
  /// Parses the given input string, relative to the given base URL, in accordance with the WHATWG URL Standard, and returns
  /// a `URLValues` containing values for the properties specified in the standard. If parsing fails, returns `nil`.
  ///
  func parseURL(_ input: String, base: String?) -> URLValues?
  
  /// A callback that is invoked when the harness encounters an entry in the constructor test file that is not a test case (e.g. a comment).
  ///
  mutating func reportNonTestEntry(_ entry: URLConstructorTest.FileEntry)
  
  /// A callback that is invoked after the harness executes a URL constructor test, providing the results of that test.
  /// This callback is invoked with the results of every test that is executed, including those whose results are not unexpected.
  ///
  mutating func reportTestResult(_ result: URLConstructorTest.Result)
}

extension URLConstructorTest.Harness {
  
  public nonmutating func reportNonTestEntry(_ entry: URLConstructorTest.FileEntry) {
  	// Default: no-op.
  }
}

extension URLConstructorTest {

  /// The set of sub-tests which a URL constructor test failed (if any).
  ///
  public struct SubtestFailures: OptionSet, Equatable, Hashable {
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
    
    /// The URL was parsed, serialised, and re-parsed, and produced a different result the second time around.
    public static var notIdempotent: Self { .init(rawValue: 1 << 5) }
  }
}

extension URLConstructorTest {

  /// The result of executing a URL constructor test.
  ///
  public struct Result: Equatable, Hashable {
    
    /// The number of tests that have been run prior to this test.
    public var testNumber: Int
    
    /// The test that was run.
    public var testcase: Testcase
    
    /// The URL record properties formed by parsing the `input` and `base` values specified in `testcase`.
    public var propertyValues: URLValues?
    
    /// The set of subtests, run as part of the URL constructor test, that failed.
    /// If empty, the URL parser appeared to behave in accordance with the URL standard for the `input` and `base` values in `testcase`.
    public var failures: SubtestFailures
    
    public init(testNumber: Int, testcase: Testcase, propertyValues: URLValues?, failures: SubtestFailures) {
      self.testNumber = testNumber
      self.testcase = testcase
      self.propertyValues = propertyValues
      self.failures = failures
    }
  }
}

extension URLConstructorTest.Harness {
  
  /// Runs the given collection of URL constructor tests.
  ///
  public mutating func runTests(_ tests: [URLConstructorTest.FileEntry]) {
  
    var index = 0
    for entry in tests {
      guard case .testcase(let testcase) = entry else {
        reportNonTestEntry(entry)
        continue
      }
      defer { index += 1 }
      var failures = URLConstructorTest.SubtestFailures.noFailures
      // Parsing the base URL must always succeed.
      if parseURL(testcase.base, base: nil) == nil {
        failures.insert(.baseURLFailedToParse)
      }
      // If failure = true, parsing "about:blank" against input must fail.
      if testcase.failure && parseURL("about:blank", base: testcase.input) != nil {
        failures.insert(.inputDidNotFailWhenUsedAsBaseURL)
      }
      
      guard let parsedVals = parseURL(testcase.input, base: testcase.base) else {
        if !testcase.failure { failures.insert(.unexpectedFailureToParse) }
        let result = URLConstructorTest.Result(
          testNumber: index, testcase: testcase, propertyValues: nil, failures: failures
        )
        reportTestResult(result)
        continue
      }
      defer {
        let result = URLConstructorTest.Result(
          testNumber: index, testcase: testcase, propertyValues: parsedVals, failures: failures
        )
        reportTestResult(result)
      }
      
      if let expectedValues = testcase.expectedValues {
        if !parsedVals.unequalURLProperties(comparedWith: expectedValues).isEmpty {
          failures.insert(.propertyMismatch)
        }
      } else {
        failures.insert(.unexpectedSuccessfulParse)
      }
      
      // Check idempotence: parse the href again and check all properties.
      var serialized = parsedVals.href
      serialized.makeContiguousUTF8()
      guard let reparsed = parseURL(serialized, base: nil) else {
        failures.insert(.notIdempotent)
        continue
      }
      if !parsedVals.unequalURLProperties(comparedWith: reparsed).isEmpty {
        failures.insert(.notIdempotent)
      }
    }
  }
}
