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
    assert(
      array.count == 662,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )
    let expectedFailures: Set<Int> = [
      // These test failures are due to us not having implemented the `domain2ascii` transform,
      // often in combination with other features (e.g. with percent encoding).
      //
      261,  // domain2ascii: (no-break, zero-width, zero-width-no-break) are name-prepped away to nothing.
      263,  // domain2ascii: U+3002 is mapped to U+002E (dot).
      269,  // domain2ascii: fullwidth input should be converted to ASCII and NOT IDN-ized.
      274,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      275,  // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
      286,  // domain2ascii: Fullwidth and escaped UTF-8 fullwidth should still be treated as IP.
      369,  // domain2ascii: Hosts and percent-encoding.
      370,  // domain2ascii: Hosts and percent-encoding.
      564,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      565,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      568,  // domain2ascii: Empty host after the domain to ASCII.
    ]
    
    var report = SimpleTestReport()
    for item in array {
      if let sectionName = item as? String {
        report.markSection(sectionName)
        
      } else if let rawTestInfo = item as? [String: Any] {
        let expected = URLConstructorTestCase(from: rawTestInfo)
        report.performTest { report, testNumber in
          
          if expectedFailures.contains(testNumber) {
            report.expectedResult = .fail
          }
          
          report.capture(key: "expected", expected)
          
          // Parsing the base URL must always succeed.
          guard let _ = WebURL(expected.base!, base: nil) else {
            report.expectTrue(false)
            return
          }
          // If failure = true, parsing "about:blank" against input must fail.
          if expected.failure == true {
            report.expectTrue(WebURL("about:blank", base: expected.input!) == nil)
          }
          
          guard let parserResult = WebURL(expected.input!, base: expected.base!)?.jsModel else {
            report.capture(key: "actual", "<nil>")
            report.expectTrue(expected.failure == true, "whatwg-expected-failure")
            return
          }
          report.capture(key: "actual", parserResult._debugDescription)
          report.expectFalse(expected.failure == true, "whatwg-expected-failure")
          
          // Compare properties.
          func checkProperties(url: WebURL.JSModel) {
            report.expectEqual(url.scheme, expected.protocol, "protocol")
            report.expectEqual(url.href, expected.href, "href")
  //          report.expectEqual(parserResult.host, expected.host)
            report.expectEqual(url.hostname, expected.hostname, "hostname")
            report.expectEqual(Int(url.port), expected.port, "port")
            report.expectEqual(url.username, expected.username, "username")
            report.expectEqual(url.password, expected.password, "password")
            report.expectEqual(url.pathname, expected.pathname, "pathname")
            report.expectEqual(url.search, expected.search, "search")
            report.expectEqual(url.fragment, expected.hash, "fragment")
            // The test file doesn't include expected `origin` values for all entries.
  //          if let expectedOrigin = expected.origin {
  //            report.expectEqual(parserResult.origin.serialized, expectedOrigin)
  //          }
          }
          checkProperties(url: parserResult)
          
          // Check idempotence: parse the href again and check all properties.
          var serialized = parserResult.href
          serialized.makeContiguousUTF8()
          guard let reparsed = WebURL(serialized, base: nil)?.jsModel else {
            report.expectTrue(false)
            return
          }
          report.capture(key: "reparsed", reparsed._debugDescription)
          report.expectEqual(parserResult.href, reparsed.href)
          checkProperties(url: reparsed)
        }
      } else {
        XCTFail("👽 - Unexpected item found. Type: \(type(of: item)). Value: \(item)")
      }
    }
    XCTAssertFalse(report.hasUnexpectedResults, "Test failed")

    // Generate a report file because the XCTest ones really aren't that helpful.
    let reportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_wpt_constructor.txt")
    try report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
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
    case "search":
      return \.search
    case "hostname":
      return \.hostname
    case "hash":
      return \.fragment
//    case "host":
//      return \.hostKind
    case "pathname":
      return \.pathname
    case "password":
      return \.password
    case "username":
      return \.username
    case "protocol":
      return \.scheme
    case "port":
      return \.port
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
    var report = SimpleTestReport()
    let expectedFailures: Set<Int> = [
      // The 'port' tests are a little special.
      // The JS URL model exposes `port` as a String, and these XFAIL-ed tests
      // check that parsing stops when it encounters an invalid character/overflows/etc.
      // However, `WebURL.port` is a `UInt16?`, so these considerations simply don't apply.
      //
      // The tests fail because `transformValue` ends up returning `nil` for these junk strings.
      //52, 53, 54, 55, 56, 57, 58, 60, 61,  // `port` tests.

      //96,  // IDNA Nontransitional_Processing.
    ]
    for testGroup in testGroups {
      report.markSection(testGroup.property)
      if let stringProperty = webURLStringPropertyWithJSName(testGroup.property) {
        for testcase in testGroup.tests {
          report.performTest { report, _ in
            performSetterTest(testcase, property: stringProperty, &report)
          }
        }
      } else {
        report.skipTest()
//        assertionFailure("Unhandled test cases for property: \(testGroup.property)")
//        report.expectTrue(false)
      }
    }
    XCTAssertFalse(report.hasUnexpectedResults, "Test failed")
    
    let reportString = report.generateReport()
    let reportPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_wpt_setters.txt")
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
  private func performSetterTest(
    _ testcase: URLSetterTest, property: WritableKeyPath<WebURL.JSModel, String>, _ report: inout SimpleTestReport.TestCase
  ) {

    testcase.comment.map { report.capture(key: "Comment", $0) }
    report.capture(key: "Input", testcase.href)
    report.capture(key: "New Value", testcase.newValue)
    // 1. Parse the URL.
    guard var url = WebURL(testcase.href)?.jsModel else {
      report.expectTrue(false, "Failed to parse")
      return
    }
    // 2. Set the value.
    url[keyPath: property] = testcase.newValue
    report.capture(key: "Result", url)
    report.capture(
      key: "Expected", testcase.expected.lazy.map { "\($0): \"\($1)\"" }.joined(separator: "\n\t") as String)
    // 3. Check all expected keys against their expected values.
    for (expected_key, expected_value) in testcase.expected {
      if let stringKey = webURLStringPropertyWithJSName(expected_key) {
        report.expectEqual(url[keyPath: stringKey], expected_value, expected_key)
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
