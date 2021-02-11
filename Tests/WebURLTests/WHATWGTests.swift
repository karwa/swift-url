import XCTest
import WebURLTestSupport
@testable import WebURL

// Data files:
//
// Constructor tests:
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json
// at version 33e4ac09029c463ea6ee57d6f33477a9043e98e8
// Adjusted to remove an invalid surrogate pair which Foundation's JSON parser refuses to parse.
//
// Setter tests:
// https://github.com/web-platform-tests/wpt/blob/master/url/resources/setters_tests.json
// at version 050308a616a8388f1ad5d6e87eac0270fd35023f (unaltered).

final class WHATWGTests: XCTestCase {}

// WHATWG URL Constructor Tests.
// Creates a URL object from a (input: String, base: String) pair, and checks that it has the expected
// properties (host, port, path, etc).
//
extension WHATWGTests {

  func testURLConstructor() throws {
    let url = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("urltestdata.json")
    let fileContents = try JSONDecoder().decode([URLConstructorTest.FileEntry].self, from: try Data(contentsOf: url))
    assert(
      fileContents.count == 665,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )
    var harness = URLConstructorTest.WebURLReportHarness(expectedFailures: [
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
      566,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      567,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      
      // FIXME: This one needs another look. We should not accept any IDNA-encoded domain names, even if they are _already_ encoded.
      
      570,  // domain2ascii: Empty host after the domain to ASCII.
    ])
    
    harness.runTests(fileContents)
    XCTAssert(harness.entriesSeen == 665, "Unexpected number of tests executed.")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    // Generate a report file because the XCTest ones really aren't that helpful.
    let reportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_constructor_wpt.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}

// WHATWG Setter Tests.
// Creates a URL object from an input String (which must not fail), and modifies one property.
// Checks the resulting (serialised) URL and that the property now returns the expected value,
// including making any necessary transformations or ignoring invalid new-values.
//
extension WHATWGTests {

  private struct URLSetterTestGroup {
    var property: String
    var tests: [URLSetterTest]
  }
  
  private struct URLSetterTest: CustomStringConvertible {
    var comment: String?
    var href: String
    var newValue: String
    var expected: [String: String]
    
    var description: String {
      var result = """
      {
        .comment:   \(comment ?? "(none)")

        .starting href:   \(href)
        .property set to: \(newValue)

        .expected result:

      """
      for (key, value) in expected {
        result += "    - \(key): \(value)\n"
      }
      result += """
      }
      """
      return result
    }
  }
  
  private var testedJSProperties: [String] {
    // No tests for "href". We include "host" but skip the actual tests, as a reminder to one day support them.
    return ["search", "host", "hostname", "hash", "pathname", "password", "username", "protocol", "port"]
  }

  private func webURLStringPropertyWithJSName(_ str: String) -> WritableKeyPath<WebURL.JSModel, String>? {
    switch str {
    case "href":
      return \.href
    case "search":
      return \.search
//    case "host":
//      return \.hostKind
    case "hostname":
      return \.hostname
    case "hash":
      return \.fragment
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
    dict["comment"] = nil  // Don't need the file-level comment.
    assert(
      dict.count == 9,
      "Incorrect number of test cases. If you updated the test list, be sure to update the expected failure indexes"
    )
    
    // The JSON data is in the format:
    // {
    // "property" : [
    //     {
    //     "href": "....",
    //     "new_value": "..."
    //     "expected": {
    //       "href": "...",
    //       "property": "...",
    //       ...
    //      },
    //      { ... }, { ... }, { ... } ...
    //   ],
    // }
    var testGroups = [URLSetterTestGroup]()
    for property in testedJSProperties {
      guard let rawTestsForProperty = dict[property] as? [[String: Any]] else {
        XCTFail("No tests in group: \(property)")
        continue
      }
      testGroups.append(URLSetterTestGroup(
        property: property,
        tests: rawTestsForProperty.map { rawTest in
          URLSetterTest(
            comment: rawTest["comment"] as? String,
            href: rawTest["href"] as! String,
            newValue: rawTest["new_value"] as! String,
            expected: rawTest["expected"] as! [String: String]
          )
        }
      ))
    }

    // Run the tests.
    var report = SimpleTestReport()
    for testGroup in testGroups {
      report.markSection(testGroup.property)
      if let webURLProperty = webURLStringPropertyWithJSName(testGroup.property) {
        for testcase in testGroup.tests {
          report.performTest { reporter in performSetterTest(property: webURLProperty, testcase, &reporter) }
        }
      } else {
        // No corresponding WebURL.JSModel property to test.
        report.skipTest(count: testGroup.tests.count)
      }
    }
    XCTAssertFalse(report.hasUnexpectedResults, "Test failed")
    
    let reportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_setters_wpt.txt")
    try report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  /// Runs an individual setter test.
  ///
  /// 1. Parses the input.
  /// 2. Sets the value on the parsed URL via the `property` key-path.
  /// 3. Checks the URL's properties and values against the expected values.
  ///
  private func performSetterTest(
    property: WritableKeyPath<WebURL.JSModel, String>,
    _ testcase: URLSetterTest, _ reporter: inout SimpleTestReport.Reporter
  ) {
    reporter.capture(key: "Test case", testcase.description)
    // 1. Parse the URL.
    guard var url = WebURL(testcase.href)?.jsModel else {
      reporter.fail("Starting URL failed to parse")
      return
    }
    // 2. Set the value.
    url[keyPath: property] = testcase.newValue
    reporter.capture(key: "Actual result", url._debugDescription)
    // 3. Check all given keys against their expected values.
    for (expected_key, expected_value) in testcase.expected {
      if let stringKey = webURLStringPropertyWithJSName(expected_key) {
        reporter.expectEqual(url[keyPath: stringKey], expected_value, expected_key)
      } else {
        // No corresponding WebURL.JSModel property to test.
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
