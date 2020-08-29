import XCTest

@testable import WebURL

final class WHATWGTests_NewURL: XCTestCase {}

// WHATWG URL Constructor Tests.
// Creates a URL object from a (input: String, base: String) pair, and checks that it has the expected
// properties (host, port, path, etc).
//
// Data file from:
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json as of 15.06.2020
//
extension WHATWGTests_NewURL {

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
        guard expected.base == nil || expected.base!.isEmpty || expected.base == "about:blank" else {
          report.advanceTestIndex()
          continue
        }
        report.recordTest { report in
          let _parserResult = NewURL(expected.input!, base: expected.base)
          // Capture test data.
          report.capture(key: "expected", expected)
          report.capture(key: "actual", _parserResult as Any)
          // Compare results.
          guard let parserResult = _parserResult else {
            report.expectTrue(expected.failure == true)
            return
          }
          report.expectFalse(expected.failure == true)
          report.expectEqual(parserResult.scheme + ":", expected.protocol)
//          report.expectEqual(parserResult.href, expected.href)
//          report.expectEqual(parserResult.host, expected.host)
//          report.expectEqual(parserResult.hostname, expected.hostname)
//          report.expectEqual(parserResult.port.map { Int($0) }, expected.port)
          report.expectEqual(parserResult.username, expected.username)
          report.expectEqual(parserResult.password, expected.password)
//          report.expectEqual(parserResult.path, expected.pathname)
//          report.expectEqual(parserResult.query, expected.search)
//          report.expectEqual(parserResult.fragment, expected.hash)
          // The test file doesn't include expected `origin` values for all entries.
//          if let expectedOrigin = expected.origin {
//            report.expectEqual(parserResult.origin.serialized, expectedOrigin)
//          }
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
extension WHATWGTests_NewURL {

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

  private func webURLStringPropertyWithJSName(_ str: String) -> WritableKeyPath<WebURL, String>? {
    switch str {
    case "search":
      return \.search
    case "hostname":
      return \.hostname
    case "hash":
      return \.fragment
    case "host":
      return \.host
    case "pathname":
      return \.pathname
    case "password":
      return \.password
    case "username":
      return \.username
    case "protocol":
      return \.scheme
    default:
      return nil
    }
  }

  private func webURLPortPropertyWithJSName(_ str: String) -> WritableKeyPath<WebURL, UInt16?>? {
    switch str {
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
        assertionFailure("Unhandled test cases for property: \(testGroup.property)")
        report.expectTrue(false)
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
    _ testcase: URLSetterTest, property: WritableKeyPath<WebURL, T>,
    transformValue: (String) -> T, _ report: inout WHATWG_TestReport
  ) {

    testcase.comment.map { report.capture(key: "Comment", $0) }
    report.capture(key: "Input", testcase.href)
    report.capture(key: "New Value", testcase.newValue)
    // 1. Parse the URL.
    guard var url = WebURL(testcase.href) else {
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
