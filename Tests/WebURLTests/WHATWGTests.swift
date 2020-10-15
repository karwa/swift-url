import XCTest

@testable import WebURL

final class WHATWGTests: XCTestCase {}

// WHATWG URL Constructor Tests.
// Creates a URL object from a (input: String, base: String) pair, and checks that it has the expected
// properties (host, port, path, etc).
//
// Data file from:
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json as of 15.06.2020
//
extension WHATWGTests {

  // Data structure to parse the test description in to.
  struct URLConstructorTestCase: CustomStringConvertible {
    var input: String? = nil
    var base: String? = nil
    var href: String? = nil
    var origin: String? = nil
    var `protocol`: String? = nil
    var username: String? = nil
    var password: String? = nil
    var host: String? = nil
    var hostname: String? = nil
    var pathname: String? = nil
    var search: String? = nil
    var hash: String? = nil
    var searchParams: String? = nil
    var port: Int? = nil
    var failure: Bool? = nil

    private init() {}

    init(from dict: [String: Any]) {
      self.init()

      // Populate String keys
      let stringKeys: [(String, WritableKeyPath<Self, String?>)] = [
        ("input", \.input),
        ("base", \.base),
        ("href", \.href),
        ("origin", \.origin),
        ("protocol", \.protocol),
        ("username", \.username),
        ("password", \.password),
        ("host", \.host),
        ("hostname", \.hostname),
        ("pathname", \.pathname),
        ("search", \.search),
        ("hash", \.hash),
        ("searchParams", \.searchParams),
      ]
      for (name, keyPath) in stringKeys {
        let value = dict[name]
        if let str = value.flatMap({ $0 as? String }) {
          self[keyPath: keyPath] = str
        } else if value != nil {
          fatalError("Did not decode type: \(type(of: value)) for name: \(name)")
        }
      }
      // Populate Int keys ('port').
      let intKeys: [(String, WritableKeyPath<Self, Int?>)] = [
        ("port", \.port)
      ]
      for (name, kp) in intKeys {
        let value = dict[name]
        if let str = value.flatMap({ $0 as? String }) {
          if str.isEmpty == false {
            self[keyPath: kp] = Int(str)!
          }
        } else if value != nil {
          fatalError("Did not decode type: \(type(of: value)) for name: \(name)")
        }
      }
      // Populate Bool keys ('failure').
      let boolKeys: [(String, WritableKeyPath<Self, Bool?>)] = [
        ("failure", \.failure)
      ]
      for (name, kp) in boolKeys {
        let value = dict[name]
        if let bool = value.flatMap({ $0 as? NSNumber }) {
          self[keyPath: kp] = bool.boolValue
        } else if value != nil {
          fatalError("Did not decode type: \(type(of: value)) for name: \(name)")
        }
      }
    }

    public var description: String {
      var result = """
        {
        \t.input:    \(input!)
        \t.base:     \(base ?? "<nil>")

        """
      guard failure != true else {
        result += """
          \t--XX FAIL XX--
          }
          """
        return result
      }
      result += """
        \t.href:     \(href ?? "<nil>")
        \t.protocol: \(`protocol` ?? "<nil>")
        \t.username: \(username ?? "<nil>")
        \t.password: \(password ?? "<nil>")
        \t.host:     \(host ?? "<nil>")
        \t.hostname: \(hostname ?? "<nil>")
        \t.origin:   \(origin ?? "<nil>")
        \t.port:     \(port.map { String($0) } ?? "<nil>")
        \t.pathname: \(pathname ?? "<nil>")
        \t.search:   \(search ?? "<nil>")
        \t.hash:     \(hash ?? "<nil>")
        }
        """
      return result
    }
  }

  func testURLConstructor() throws {
    let url = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("urltestdata.json")
    let data = try Data(contentsOf: url)
    let array = try JSONSerialization.jsonObject(with: data, options: []) as! NSArray
    assert(array.count == 627, "Incorrect number of test cases.")

    var report = WHATWG_TestReport()
    report.expectedFailures = [
      // These test failures are due to us not having implemented the `domain2ascii` transform,
      // often in combination with other features (e.g. with percent encoding).
      //
      272,  // domain2ascii: (no-break, zero-width, zero-width-no-break) are name-prepped away to nothing.
      276,  // domain2ascii: U+3002 is mapped to U+002E (dot).
      286,  // domain2ascii: fullwidth input should be converted to ASCII and NOT IDN-ized.
      294,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      295,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      312,  // domain2ascii: Fullwidth and escaped UTF-8 fullwidth should still be treated as IP.
      412,  // domain2ascii: Hosts and percent-encoding.
      413,  // domain2ascii: Hosts and percent-encoding.
      621,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      622,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      626,  // domain2ascii: Empty host after the domain to ASCII.
    ]
    for item in array {
      if let sectionName = item as? String {
        report.recordSection(sectionName)
      } else if let rawTestInfo = item as? [String: Any] {
        let expected = URLConstructorTestCase(from: rawTestInfo)
        report.recordTest { report in
          report.capture(key: "expected", expected)
          
          // base URL parsing must always succeed.
          guard let _ = WebURL(expected.base!, base: nil) else {
            report.expectTrue(false)
            return
          }
          // If failure = true, parsing "about:blank" against input must fail.
          if expected.failure == true {
            report.expectTrue(WebURL("about:blank", base: expected.input!) == nil)
          }
          
          let _parserResult = WebURL(expected.input!, base: expected.base!)?.jsModel
          report.capture(key: "actual", _parserResult as Any)
          
          // Compare results.
          guard let parserResult = _parserResult else {
            report.expectTrue(expected.failure == true)
            return
          }
          report.expectFalse(expected.failure == true)
          report.expectEqual(parserResult.scheme, expected.protocol)
          report.expectEqual(parserResult.href, expected.href)
//          report.expectEqual(parserResult.host, expected.host)
          report.expectEqual(parserResult.hostname, expected.hostname)
          report.expectEqual(Int(parserResult.port), expected.port)
          report.expectEqual(parserResult.username, expected.username)
          report.expectEqual(parserResult.password, expected.password)
          report.expectEqual(parserResult.path, expected.pathname)
          report.expectEqual(parserResult.query, expected.search)
          report.expectEqual(parserResult.fragment, expected.hash)
          // The test file doesn't include expected `origin` values for all entries.
//          if let expectedOrigin = expected.origin {
//            report.expectEqual(parserResult.origin.serialized, expectedOrigin)
//          }
          // Check idempotence.
          var serialized = parserResult.href
          serialized.makeContiguousUTF8()
          guard let reparsed = WebURL(serialized, base: nil)?.jsModel else {
            report.expectTrue(false)
            return
          }
          report.expectEqual(parserResult.href, reparsed.href)
        }
      } else {
        assertionFailure("👽 - Unexpected item found. Type: \(type(of: item)). Value: \(item)")
      }
    }

    let reportString = report.generateReport()
    let reportPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "url_whatwg_constructor_report.txt")
    try reportString.data(using: .utf8)!.write(to: reportPath)
    print("ℹ️ Report written to \(reportPath)")
    
    testAdditional()
  }
}

struct AdditionalTest {
  let input: String
  var base: String? = nil
  
  var ex_href: String? = nil
  var ex_scheme: String? = nil
  var ex_hostname: String? = nil
  var ex_port: String? = nil
  var ex_path: String? = nil
  var ex_query: String? = nil
  var ex_fragment: String? = nil
  
  var ex_fail: Bool = false
}

let additionalTests: [AdditionalTest] = [
  
  .init(input: ".", base: "file:///a/b/",
        ex_href: "file:///a/b/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/a/b/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "..", base: "file:///a/b/c",
        ex_href: "file:///a/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/a/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "...", base: "file:///a/b/...",
        ex_href: "file:///a/b/...",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/a/b/...",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "./.", base: "file:///a/b/",
        ex_href: "file:///a/b/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/a/b/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "../", base: "http://example.com",
        ex_href: "http://example.com/",
        ex_scheme: "http:",
        ex_hostname: "example.com",
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "..///", base: "http://example.com",
        ex_href: "http://example.com///",
        ex_scheme: "http:",
        ex_hostname: "example.com",
        ex_port: nil,
        ex_path: "///",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "./.", base: "non-special:///a/b/",
        ex_href: "non-special:///a/b/",
        ex_scheme: "non-special:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/a/b/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "./../1/2/../", base: "non-special:///a/b/c/d",
        ex_href: "non-special:///a/b/1/",
        ex_scheme: "non-special:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/a/b/1/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "/", base: "non-special://somehost",
        ex_href: "non-special://somehost/",
        ex_scheme: "non-special:",
        ex_hostname: "somehost",
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "a/../../../../", base: "http://example.com/1/2/3/4/5/6",
        ex_href: "http://example.com/1/2/",
        ex_scheme: "http:",
        ex_hostname: "example.com",
        ex_port: nil,
        ex_path: "/1/2/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "file:/./.././../C:/../1/2/../", base: "about:blank",
        ex_href: "file:///C:/1/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/1/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "pile:/./.././../C:/../1/2/../", base: "about:blank",
        ex_href: "pile:/1/",
        ex_scheme: "pile:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/1/",
        ex_query: nil,
        ex_fragment: nil),
  
  
  // Check that query component is correctly not-copied for (file/special/non-special) schemes.
  .init(input: "pop", base: "file://hostname/o1/o2?someQuery",
        ex_href: "file://hostname/o1/pop",
        ex_scheme: "file:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_path: "/o1/pop",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "/pop", base: "file://hostname/o1/o2?someQuery",
      ex_href: "file://hostname/pop",
      ex_scheme: "file:",
      ex_hostname: "hostname",
      ex_port: nil,
      ex_path: "/pop",
      ex_query: nil,
      ex_fragment: nil),
  .init(input: "pop", base: "http://hostname/o1/o2?someQuery",
      ex_href: "http://hostname/o1/pop",
      ex_scheme: "http:",
      ex_hostname: "hostname",
      ex_port: nil,
      ex_path: "/o1/pop",
      ex_query: nil,
      ex_fragment: nil),
  .init(input: "/pop", base: "http://hostname/o1/o2?someQuery",
        ex_href: "http://hostname/pop",
        ex_scheme: "http:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_path: "/pop",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "pop", base: "non-special://hostname/o1/o2?someQuery",
        ex_href: "non-special://hostname/o1/pop",
        ex_scheme: "non-special:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_path: "/o1/pop",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "/pop", base: "non-special://hostname/o1/o2?someQuery",
        ex_href: "non-special://hostname/pop",
        ex_scheme: "non-special:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_path: "/pop",
        ex_query: nil,
        ex_fragment: nil),
  
  // File URLs with invalid hostnames should fail to parse, even if the path begins with a Windows drive letter.
  .init(input: "file://^/C:/hello", ex_fail: true),
  
  // Check we do not fail to yield a path when the input contributes nothing and the base URL has a 'nil' path.
  .init(input: "..", base: "sc://a",
        ex_href: "sc://a/",
        ex_scheme: "sc:",
        ex_hostname: "a",
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "../..///.", base: "sc://a",
        ex_href: "sc://a///",
        ex_scheme: "sc:",
        ex_hostname: "a",
        ex_port: nil,
        ex_path: "///",
        ex_query: nil,
        ex_fragment: nil),
  
  // Ensure that we always flush trailing empties if the first component doesn't get yielded.
  .init(input: "././././////b", base: "sc://a",
        ex_href: "sc://a/////b",
        ex_scheme: "sc:",
        ex_hostname: "a",
        ex_port: nil,
        ex_path: "/////b",
        ex_query: nil,
        ex_fragment: nil),
  
  // Ensure we detect Windows drive letters even when they don't end with a '/'.
  .init(input: "file:C|", base: nil,
        ex_href: "file:///C:",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "../../..", base: "file:C|",
        ex_href: "file:///C:/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/",
        ex_query: nil,
        ex_fragment: nil),
  
  // Code coverage for relative file paths which sum to nothing.
  .init(input: ".", base: "file:///",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "../b/..", base: "file:///a",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil),
]

extension WHATWGTests {

  func testAdditional() {
    
    for test in additionalTests {
      guard let result = WebURL(test.input, base: test.base)?.jsModel else {
        XCTAssertTrue(test.ex_fail, "Test failed: \(test)")
        continue
      }
      XCTAssertEqual(test.ex_href, result.href)
      XCTAssertEqual(test.ex_scheme, result.scheme)
      XCTAssertEqual(test.ex_hostname ?? "", result.hostname)
      XCTAssertEqual(test.ex_port ?? "", result.port)
      XCTAssertEqual(test.ex_path ?? "", result.path)
      XCTAssertEqual(test.ex_query ?? "", result.query)
      XCTAssertEqual(test.ex_fragment ?? "", result.fragment)
    }
    
    
  }
}

// WHATWG Setter Tests.
// Creates a URL object from an input String (which must not fail), and modifies one property.
// Checks the resulting (serialised) URL and that the property now returns the expected value,
// including making any necessary transformations or ignoring invalid new-values.
//
// Data file from:
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/setters_tests.json as of 15.06.2020
//
extension WHATWGTests {

  private struct URLSetterTest {
    var comment: String?
    var href: String
    var newValue: String
    var expected: [String: String]
  }

  private struct URLSetterTestGroup {
    var property: String
    var tests: [URLSetterTest]
  }

  private func webURLStringPropertyWithJSName(_ str: String) -> WritableKeyPath<WebURL.JSModel, String>? {
    switch str {
    case "href":
      return \.href
//    case "search":
//      return \.search
//    case "hostname":
//      return \.hostname
//    case "hash":
//      return \.fragment
//    case "host":
//      return \.hostKind
//    case "pathname":
//      return \.pathname
//    case "password":
//      return \.password
    case "username":
      return \.username
//    case "protocol":
//      return \.scheme
    default:
      return nil
    }
  }

  private func webURLPortPropertyWithJSName(_ str: String) -> WritableKeyPath<WebURL.JSModel, UInt16?>? {
    switch str {
//    case "port":
//      return \.port
    default:
      return nil
    }
  }

  func testURLSetters() throws {

    let url = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("setters_tests.json")
    let data = try Data(contentsOf: url)
    var dict = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

    // The data is in the format:
    // {
    // "property" : [
    //     {
    //     "href": "....",
    //     "new_value": "..."
    //     "expected": {
    //       "href": "...",
    //       "property": "...",
    //       ...
    //      }
    //   ],
    // }
    var testGroups = [URLSetterTestGroup]()
    dict["comment"] = nil  // Don't need the file-level comment.
    assert(dict.count == 9, "Incorrect number of test cases.")
    for property in ["search", "hostname", "port", "hash", "host", "pathname", "password", "username", "protocol"] {
      guard let rawTestsInGroup = dict[property] as? [[String: Any]] else {
        fatalError("No tests in group")
      }
      testGroups.append(
        URLSetterTestGroup(
          property: property,
          tests: rawTestsInGroup.map { testcase -> URLSetterTest in
            return URLSetterTest(
              comment: testcase["comment"] as? String,
              href: testcase["href"] as! String,
              newValue: testcase["new_value"] as! String,
              expected: testcase["expected"] as! [String: String]
            )
          }
        ))
    }

    // Run the tests.
    var report = WHATWG_TestReport()
    report.expectedFailures = [
      // The 'port' tests are a little special.
      // The JS URL model exposes `port` as a String, and these XFAIL-ed tests
      // check that parsing stops when it encounters an invalid character/overflows/etc.
      // However, `WebURL.port` is a `UInt16?`, so these considerations simply don't apply.
      //
      // The tests fail because `transformValue` ends up returning `nil` for these junk strings.
      52, 53, 54, 55, 56, 57, 58, 60, 61,  // `port` tests.

      96,  // IDNA Nontransitional_Processing.
    ]
    for testGroup in testGroups {
      report.recordSection(testGroup.property)
      if let stringProperty = webURLStringPropertyWithJSName(testGroup.property) {
        for testcase in testGroup.tests {
          report.recordTest { report in
            performSetterTest(testcase, property: stringProperty, transformValue: { $0 }, &report)
          }
        }
      } else if let portProperty = webURLPortPropertyWithJSName(testGroup.property) {
        for testcase in testGroup.tests {
          report.recordTest { report in
            performSetterTest(testcase, property: portProperty, transformValue: { UInt16($0) }, &report)
          }
        }
      } else {
//        assertionFailure("Unhandled test cases for property: \(testGroup.property)")
//        report.expectTrue(false)
      }
    }

    let reportString = report.generateReport()
    let reportPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("url_whatwg_setter_report.txt")
    try reportString.data(using: .utf8)!.write(to: reportPath)
    print("ℹ️ Report written to \(reportPath)")
  }

  /// Runs an individual setter test.
  ///
  /// 1. Parses the input.
  /// 2. Transforms the test's "new_value" property to the expected type.
  /// 3. Sets the transformed value on the parsed URL via the `property` key-path.
  /// 4. Checks the URL's properties and values against the expected values.
  ///
  private func performSetterTest<T>(
    _ testcase: URLSetterTest, property: WritableKeyPath<WebURL.JSModel, T>,
    transformValue: (String) -> T, _ report: inout WHATWG_TestReport
  ) {

    testcase.comment.map { report.capture(key: "Comment", $0) }
    report.capture(key: "Input", testcase.href)
    report.capture(key: "New Value", testcase.newValue)
    // 1. Parse the URL.
    guard var url = WebURL(testcase.href)?.jsModel else {
      report.expectTrue(false, "Failed to parse")
      return
    }
    // 2. Transform the value.
    let transformedValue = transformValue(testcase.newValue)
    report.capture(key: "Transformed Value", transformedValue)
    // 3. Set the value.
    url[keyPath: property] = transformedValue
    report.capture(key: "Result", url)
    report.capture(
      key: "Expected", testcase.expected.lazy.map { "\($0): \"\($1)\"" }.joined(separator: "\n\t") as String)
    // 4. Check all expected keys against their expected values.
    for (expected_key, expected_value) in testcase.expected {
      if let stringKey = webURLStringPropertyWithJSName(expected_key) {
        report.expectEqual(url[keyPath: stringKey], expected_value, expected_key)

      } else if let portKey = webURLPortPropertyWithJSName(expected_key) {
        report.expectEqual(url[keyPath: portKey], UInt16(expected_value), expected_key)
      }
    }
  }
}

#if false // Mutable query parameters have not been implemented for WebURL yet.

// These are not technically WHATWG test cases, but they test
// functionality exposed via the JS/OldURL model.
//
extension OldURL_WHATWGTests {

  func testSearchParamsEscaping() {
    var url = OldURL("http://example/?a=b ~")!
    // Query string is escaped with the "query" escape set.
    XCTAssertEqual(url.href, "http://example/?a=b%20~")

    // We can read through "searchParams", see the expected value, and 'href' doesn't change.
    XCTAssertTrue(url.searchParams!.items.first! == (name: "a", value: "b ~"))
    XCTAssertEqual(url.href, "http://example/?a=b%20~")

    // Modifying via searchParams re-escapes with the "application/x-www-form-urlencoded" escape set.
    // But we read the same value out of it.
    url.searchParams!.items.sort { $0.name < $1.name }
    XCTAssertEqual(url.href, "http://example/?a=b+%7E")
    XCTAssertTrue(url.searchParams!.items.first! == (name: "a", value: "b ~"))
  }
}
#endif
