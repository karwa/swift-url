
/// A data structure containing information for a URL constructor test.
/// A base URL string and input string are required.
///
@dynamicMemberLookup
public struct URLConstructorTest {
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

// To be compatible with the WPT constructor test file, we have to encode the expected values in-line.
extension URLConstructorTest: Equatable, Hashable, Codable {
  
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

extension URLConstructorTest: CustomStringConvertible {
      
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

public enum URLConstructorTestFileEntry: Equatable, Hashable, Codable {
  case sectionHeader(String)
  case test(URLConstructorTest)
  
  public init(from decoder: Decoder) throws {
    if let testcase = try? URLConstructorTest(from: decoder) {
      self = .test(testcase)
    } else {
      self = .sectionHeader(try decoder.singleValueContainer().decode(String.self))
    }
  }
  
  public func encode(to encoder: Encoder) throws {
    switch self {
    case .sectionHeader(let header):
      var container = encoder.singleValueContainer()
      try container.encode(header)
    case .test(let testcase):
      try testcase.encode(to: encoder)
    }
  }
}
