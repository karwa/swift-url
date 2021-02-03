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
      413,  // domain2ascii: Hosts and percent-encoding.
      414,  // domain2ascii: Hosts and percent-encoding.
      650,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      651,  // domain2ascii: IDNA ignored code points in file URLs hosts.
      655,  // domain2ascii: Empty host after the domain to ASCII.
    ]
    for item in array {
      if let sectionName = item as? String {
        report.recordSection(sectionName)
      } else if let rawTestInfo = item as? [String: Any] {
        let expected = URLConstructorTestCase(from: rawTestInfo)
        report.recordTest { report in
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
            report.expectTrue(expected.failure == true, "failure")
            return
          }
          report.capture(key: "actual", parserResult._debugDescription)
          report.expectFalse(expected.failure == true, "failure")
          
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
  
// MARK: == PATHS ==
  
  // Single-dot components are skipped and do not affect popcount.
  .init(input: "file:/a/./..", base: nil,
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil,
        ex_fail: false),
  
  .init(input: "file:/a/./././..", base: nil,
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil,
        ex_fail: false),
  
  // Various oddball paths with base URLs.
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
  
// MARK: == PATHS (Windows drive letters) ==
  
  // 0 slashes - Relative paths. The parser in the standard first checks to see if the drive is literally at the start
  //             of the string, and if not, copies in the base path components so the effective first component
  //             (e.g. after popping, etc) becomes the drive.
  //
	//             What this means is that Windows drive components are resolved just like regular relative path
  //             components, unless they are at the very start of the string (where they force the whole thing to
  //             be treated like an absolute path).
  .init(input: "file:C|", base: "about:blank",
        ex_href: "file:///C:",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "about:blank",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "file:///bar",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "file:///bar/",
        ex_href: "file:///bar/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/bar/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:D|/../foo", base: "file:///bar/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D:/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///C:/base1/base2/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/base1/base2/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:D|/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///bar/baz/qux/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/bar/baz/qux/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:../../../D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "foo", base: "file:///C:/base1/base2/base3",
        ex_href: "file:///C:/base1/base2/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/base1/base2/foo",
        ex_query: nil,
        ex_fragment: nil),
    
  // 1 slash - Absolute paths. If the parser in the standard goes down the 'file slash' state, absolute paths
  //           will be checked to see if they literally begin with a Windows drive letter as their first component,
  //           and otherwise (despite being absolute), will be relative to the base URL's drive letter (if it has one).
  //           They only copy the drive from the base URL, not any other parts of the path.
  //
  //           Note that this only applies to the 'file slash' state - i.e. "/C:/Windows" or "file:C:/Windows", and
  //           means that in a path like "/./D|/../foo" with a base URL of "file:///C:/bar/", the "D|" drive in the
  //           input will not be recognised because of "C:" in the base URL (however, without that "C:" in the base,
  //           we would recognise "D|" as a drive).
  .init(input: "file:/D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/.././D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/abc/def/../.././D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/abc/def/../../ghi/./D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///ghi/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/ghi/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/D|/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/./D|/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///C:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "not-file:/abc/def/../.././D|/../foo", base: "not-file:///bar/baz/qux/",
        ex_href: "not-file:/foo",
        ex_scheme: "not-file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/foo",
        ex_query: nil,
        ex_fragment: nil),
  // Absolute paths which don't have their own drive letter are still relative to the base URL drive.
  // (because they go down the 'file slash' path).
  .init(input: "/hello", base: "file:///C:/bar/",
        ex_href: "file:///C:/hello",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/hello",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/hello", base: "file:///C:/bar/",
        ex_href: "file:///C:/hello",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/C:/hello",
        ex_query: nil,
        ex_fragment: nil),
  // But absolute paths from URLs with authorities are never relative to the base URL drive.
  // (because they go down the 'path' path).
  .init(input: "file:///hello", base: "file:///C:/bar/",
        ex_href: "file:///hello",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/hello",
        ex_query: nil,
        ex_fragment: nil),
  
  // 2+ slashes - Misplaced authorities. The parser in the standard has a special 'file host' state, which checks
  //              to see if the component in the hostname position is a Windows drive and, if it is, forwards that
  //              to the regular 'path' state as a first component to the otherwise empty path.
  //
  //              The 'file host' state never copies any path components from the base URL (if present), so it is
  //              kind of "more absolute" than even a regular "/usr/bin/"-style absolute path. In the sense that
  //              "/usr/bin/" with a base URL of "file:///C:/" is "file:///C:/usr/bin/", but "///usr/bin/" always
  //              results in "file:///usr/bin/", regardless of whether the base URL contains a Windows drive letter.
  .init(input: #"\\D|\..\foo"#, base: "file:///C:/bar/baz/qux",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file://D|/../foo", base: "file:///C:/bar/baz/qux",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file://./D|/../foo", base: "file:///C:/bar/baz/qux",
        ex_href: "file://./D:/foo",
        ex_scheme: "file:",
        ex_hostname: ".",
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "not-file://D|/../foo", base: "not-file:///C:/bar/baz/qux",
        ex_href: "not-file://D|/foo",
        ex_scheme: "not-file:",
        ex_hostname: "D|",
        ex_port: nil,
        ex_path: "/foo",
        ex_query: nil,
        ex_fragment: nil),
  // 3+ slashes.
  .init(input: "file:///././D|/../foo", base: "file:///C:/bar/baz/qux",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "///usr/bin/x", base: "file:///C:/foo/bar/baz/",
        ex_href: "file:///usr/bin/x",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/usr/bin/x",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:///usr/bin/x", base: "file:///C:/foo/bar/baz/",
        ex_href: "file:///usr/bin/x",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/usr/bin/x",
        ex_query: nil,
        ex_fragment: nil),
  // Leading empty components disqualify a potential Windows drive.
  .init(input: "file://///////////C|/../D|/../foo", base: "about:blank",
        ex_href: "file://///////////foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "///////////foo",
        ex_query: nil,
        ex_fragment: nil),
  
  // Drive letter implementation checks - Checks for things which are really details of our algorithm rather
  // than specific quirks in the spec, but were nonetheless not caught by the WPT tests at the time.
  
  // Check that components which are deferred are not popped when flushing due to a ".." component.
  .init(input: "file:../C|/foo", base: "file:///D:/base1/base2/base3",
        ex_href: "file:///D:/base1/C|/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/D:/base1/C|/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:////C:/../..", base: "about:blank",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_path: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  
// MARK: == OTHER ==
   
  
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
  
  // Percent-encoded/mixed-case localhost.
  .init(input: "file://loc%61lhost/some/path",
        ex_href: "file:///some/path",
        ex_scheme: "file:",
        ex_hostname: "",
        ex_port: nil,
        ex_path: "/some/path",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file://locAlhost/some/path",
        ex_href: "file:///some/path",
        ex_scheme: "file:",
        ex_hostname: "",
        ex_port: nil,
        ex_path: "/some/path",
        ex_query: nil,
        ex_fragment: nil),
  // Double slash at start of base path (with host - not related to idempotence fix from Aug 2020).
  .init(input: "path",
        base: "non-spec://host/..//p",
        ex_href: "non-spec://host//path",
        ex_scheme: "non-spec:",
        ex_hostname: "host",
        ex_port: nil,
        ex_path: "//path",
        ex_query: nil,
        ex_fragment: nil),
  
  // Path idempotence fixes from Aug 2020.
  .init(input: "hello",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/.//not-a-host/hello",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_path: "//not-a-host/hello",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "hello/..",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/.//not-a-host/",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_path: "//not-a-host/",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "hello/../..",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/.//",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_path: "//",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "hello/../../..",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/",
        ex_scheme: "web+demo:",
        ex_hostname: "",
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
      XCTAssertEqual(test.ex_path ?? "", result.pathname)
      XCTAssertEqual(test.ex_query ?? "", result.search)
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
    var report = WHATWG_TestReport()
    report.expectedFailures = [
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
      report.recordSection(testGroup.property)
      if let stringProperty = webURLStringPropertyWithJSName(testGroup.property) {
        for testcase in testGroup.tests {
          report.recordTest { report in
            performSetterTest(testcase, property: stringProperty, &report)
          }
        }
      } else {
        report.advanceTestIndex()
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
  private func performSetterTest(
    _ testcase: URLSetterTest, property: WritableKeyPath<WebURL.JSModel, String>, _ report: inout WHATWG_TestReport
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

extension WHATWGTests {
  
  func testAdditionalSetters() {
    // Check that 'pathname' setter does not remove leading slashes.
    do {
      var x = WebURL("sc://x?hello")!.jsModel
      XCTAssertEqual(x.href, "sc://x?hello")
      XCTAssertEqual(x.pathname, "")
      x.pathname = #"/"#
      XCTAssertEqual(x.href, "sc://x/?hello")
      XCTAssertEqual(x.pathname, "/")
      x.pathname = #"/s"#
      XCTAssertEqual(x.href, "sc://x/s?hello")
      XCTAssertEqual(x.pathname, "/s")
      x.pathname = #""#
      XCTAssertEqual(x.href, "sc://x?hello")
      XCTAssertEqual(x.pathname, "")
    }
    // Check that 'hostname' setter removes path sigil.
    do {
      func check_has_path_sigil(url: WebURL.JSModel) {
        XCTAssertEqual(url.description, "web+demo:/.//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .path)
        XCTAssertEqual(url.hostname, "")
        XCTAssertEqual(url.pathname, "//not-a-host/test")
      }
      func check_has_auth_sigil(url: WebURL.JSModel, hostname: String) {
        XCTAssertEqual(url.description, "web+demo://\(hostname)//not-a-host/test")
        XCTAssertEqual(url.storage.structure.sigil, .authority)
        XCTAssertEqual(url.hostname, hostname)
        XCTAssertEqual(url.pathname, "//not-a-host/test")
      }
      
      var test_url = WebURL("web+demo:/.//not-a-host/test")!.jsModel
      check_has_path_sigil(url: test_url)
      test_url.hostname = "host"
      check_has_auth_sigil(url: test_url, hostname: "host")
      test_url.hostname = ""
      check_has_auth_sigil(url: test_url, hostname: "")
      // We don't yet expose any way to remove an authority, so go down to URLStorage.
      switch test_url.storage {
      case .generic(var storage): test_url.storage = storage.setHostname(to: UnsafeBufferPointer?.none).0
      case .small(var storage): test_url.storage = storage.setHostname(to: UnsafeBufferPointer?.none).0
      }
      check_has_path_sigil(url: test_url)
    }
    
    // TODO [testing]: This test needs to be more comprehensive, and we need tests like this exercising all major
    // paths in all setters.
    
    // Checks what happens when a scheme change requires the port to be removed, and the resulting URL
    // has a different optimal storage type to the original (i.e. suddenly becomes less than 255 bytes).
    // It's such a niche case that we'd otherwise never see it.
    do {
      var url = WebURL("ws://hostnamewhichtakesustotheedge:443?hellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellop")!.jsModel
      switch url.storage {
      case .generic(_): break
      default: XCTFail("Unexpected storage type")
      }
      url.scheme = "wss"
      switch url.storage {
      case .small(_): break
      default: XCTFail("Unexpected storage type")
      }
      XCTAssertEqual(
        url.description,
        "wss://hostnamewhichtakesustotheedge/?hellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellohellop"
      )
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
