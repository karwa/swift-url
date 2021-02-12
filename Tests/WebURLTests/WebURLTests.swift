import XCTest
import WebURLTestSupport
@testable import WebURL

class WebURLTests: XCTestCase {}

extension WebURLTests {
  
  fileprivate struct ConstructorTest: CustomStringConvertible {
    let input: String
    var base: String
    
    var ex_href: String? = nil
    var ex_scheme: String? = nil
    var ex_hostname: String? = nil
    var ex_port: String? = nil
    var ex_pathname: String? = nil
    var ex_query: String? = nil
    var ex_fragment: String? = nil
    
    var ex_fail: Bool = false
    
    var description: String {
      return """
      {
        .input:  \(input)
        .base:   \(base)

        .expected:
          - href:     \(ex_href ?? "<nil>")
          - scheme:   \(ex_scheme ?? "<nil>")
          - hostname: \(ex_hostname ?? "<nil>")
          - port:     \(ex_port ?? "<nil>")
          - pathname: \(ex_pathname ?? "<nil>")
          - query:    \(ex_query ?? "<nil>")
          - fragment: \(ex_fragment ?? "<nil>")
      }
      """
    }
  }
}

fileprivate let additionalTests: [WebURLTests.ConstructorTest] = [
  
// MARK: == PATHS ==
  
  // Single-dot components are skipped and do not affect popcount.
  .init(input: "file:/a/./..", base: "about:blank",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil,
        ex_fail: false),
  
  .init(input: "file:/a/./././..", base: "about:blank",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil,
        ex_fail: false),
  
  // Various oddball paths with base URLs.
  .init(input: ".", base: "file:///a/b/",
        ex_href: "file:///a/b/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/a/b/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "..", base: "file:///a/b/c",
        ex_href: "file:///a/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/a/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "...", base: "file:///a/b/...",
        ex_href: "file:///a/b/...",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/a/b/...",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "./.", base: "file:///a/b/",
        ex_href: "file:///a/b/",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/a/b/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "../", base: "http://example.com",
        ex_href: "http://example.com/",
        ex_scheme: "http:",
        ex_hostname: "example.com",
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "..///", base: "http://example.com",
        ex_href: "http://example.com///",
        ex_scheme: "http:",
        ex_hostname: "example.com",
        ex_port: nil,
        ex_pathname: "///",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "./.", base: "non-special:///a/b/",
        ex_href: "non-special:///a/b/",
        ex_scheme: "non-special:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/a/b/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "./../1/2/../", base: "non-special:///a/b/c/d",
        ex_href: "non-special:///a/b/1/",
        ex_scheme: "non-special:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/a/b/1/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "/", base: "non-special://somehost",
        ex_href: "non-special://somehost/",
        ex_scheme: "non-special:",
        ex_hostname: "somehost",
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  .init(input: "a/../../../../", base: "http://example.com/1/2/3/4/5/6",
        ex_href: "http://example.com/1/2/",
        ex_scheme: "http:",
        ex_hostname: "example.com",
        ex_port: nil,
        ex_pathname: "/1/2/",
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
        ex_pathname: "/C:",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "about:blank",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "file:///bar",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "file:///bar/",
        ex_href: "file:///bar/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/bar/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:D|/../foo", base: "file:///bar/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D:/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///C:/base1/base2/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/C:/base1/base2/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:D|/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:./D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///bar/baz/qux/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/bar/baz/qux/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:../../../D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "foo", base: "file:///C:/base1/base2/base3",
        ex_href: "file:///C:/base1/base2/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/C:/base1/base2/foo",
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
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/.././D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/abc/def/../.././D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/abc/def/../../ghi/./D|/../foo", base: "file:///bar/baz/qux/",
        ex_href: "file:///ghi/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/ghi/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/D|/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/./D|/../foo", base: "file:///C:/base1/base2/",
        ex_href: "file:///C:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/C:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "not-file:/abc/def/../.././D|/../foo", base: "not-file:///bar/baz/qux/",
        ex_href: "not-file:/foo",
        ex_scheme: "not-file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/foo",
        ex_query: nil,
        ex_fragment: nil),
  // Absolute paths which don't have their own drive letter are still relative to the base URL drive.
  // (because they go down the 'file slash' path).
  .init(input: "/hello", base: "file:///C:/bar/",
        ex_href: "file:///C:/hello",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/C:/hello",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:/hello", base: "file:///C:/bar/",
        ex_href: "file:///C:/hello",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/C:/hello",
        ex_query: nil,
        ex_fragment: nil),
  // But absolute paths from URLs with authorities are never relative to the base URL drive.
  // (because they go down the 'path' path).
  .init(input: "file:///hello", base: "file:///C:/bar/",
        ex_href: "file:///hello",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/hello",
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
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file://D|/../foo", base: "file:///C:/bar/baz/qux",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file://./D|/../foo", base: "file:///C:/bar/baz/qux",
        ex_href: "file://./D:/foo",
        ex_scheme: "file:",
        ex_hostname: ".",
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "not-file://D|/../foo", base: "not-file:///C:/bar/baz/qux",
        ex_href: "not-file://D|/foo",
        ex_scheme: "not-file:",
        ex_hostname: "D|",
        ex_port: nil,
        ex_pathname: "/foo",
        ex_query: nil,
        ex_fragment: nil),
  // 3+ slashes.
  .init(input: "file:///././D|/../foo", base: "file:///C:/bar/baz/qux",
        ex_href: "file:///D:/foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/D:/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "///usr/bin/x", base: "file:///C:/foo/bar/baz/",
        ex_href: "file:///usr/bin/x",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/usr/bin/x",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:///usr/bin/x", base: "file:///C:/foo/bar/baz/",
        ex_href: "file:///usr/bin/x",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/usr/bin/x",
        ex_query: nil,
        ex_fragment: nil),
  // Leading empty components disqualify a potential Windows drive.
  .init(input: "file://///////////C|/../D|/../foo", base: "about:blank",
        ex_href: "file://///////////foo",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "///////////foo",
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
        ex_pathname: "/D:/base1/C|/foo",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file:////C:/../..", base: "about:blank",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  
// MARK: == OTHER ==
   
  
  // Check that query component is correctly not-copied for (file/special/non-special) schemes.
  .init(input: "pop", base: "file://hostname/o1/o2?someQuery",
        ex_href: "file://hostname/o1/pop",
        ex_scheme: "file:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_pathname: "/o1/pop",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "/pop", base: "file://hostname/o1/o2?someQuery",
      ex_href: "file://hostname/pop",
      ex_scheme: "file:",
      ex_hostname: "hostname",
      ex_port: nil,
      ex_pathname: "/pop",
      ex_query: nil,
      ex_fragment: nil),
  .init(input: "pop", base: "http://hostname/o1/o2?someQuery",
      ex_href: "http://hostname/o1/pop",
      ex_scheme: "http:",
      ex_hostname: "hostname",
      ex_port: nil,
      ex_pathname: "/o1/pop",
      ex_query: nil,
      ex_fragment: nil),
  .init(input: "/pop", base: "http://hostname/o1/o2?someQuery",
        ex_href: "http://hostname/pop",
        ex_scheme: "http:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_pathname: "/pop",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "pop", base: "non-special://hostname/o1/o2?someQuery",
        ex_href: "non-special://hostname/o1/pop",
        ex_scheme: "non-special:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_pathname: "/o1/pop",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "/pop", base: "non-special://hostname/o1/o2?someQuery",
        ex_href: "non-special://hostname/pop",
        ex_scheme: "non-special:",
        ex_hostname: "hostname",
        ex_port: nil,
        ex_pathname: "/pop",
        ex_query: nil,
        ex_fragment: nil),
  
  // File URLs with invalid hostnames should fail to parse, even if the path begins with a Windows drive letter.
  .init(input: "file://^/C:/hello", base: "about:blank", ex_fail: true),
  
  // Check we do not fail to yield a path when the input contributes nothing and the base URL has a 'nil' path.
  .init(input: "..", base: "sc://a",
        ex_href: "sc://a/",
        ex_scheme: "sc:",
        ex_hostname: "a",
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "../..///.", base: "sc://a",
        ex_href: "sc://a///",
        ex_scheme: "sc:",
        ex_hostname: "a",
        ex_port: nil,
        ex_pathname: "///",
        ex_query: nil,
        ex_fragment: nil),
  
  // Ensure that we always flush trailing empties if the first component doesn't get yielded.
  .init(input: "././././////b", base: "sc://a",
        ex_href: "sc://a/////b",
        ex_scheme: "sc:",
        ex_hostname: "a",
        ex_port: nil,
        ex_pathname: "/////b",
        ex_query: nil,
        ex_fragment: nil),
  
  // Code coverage for relative file paths which sum to nothing.
  .init(input: ".", base: "file:///",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "../b/..", base: "file:///a",
        ex_href: "file:///",
        ex_scheme: "file:",
        ex_hostname: nil,
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),
  
  // Percent-encoded/mixed-case localhost.
  .init(input: "file://loc%61lhost/some/path", base: "about:blank",
        ex_href: "file:///some/path",
        ex_scheme: "file:",
        ex_hostname: "",
        ex_port: nil,
        ex_pathname: "/some/path",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "file://locAlhost/some/path", base: "about:blank",
        ex_href: "file:///some/path",
        ex_scheme: "file:",
        ex_hostname: "",
        ex_port: nil,
        ex_pathname: "/some/path",
        ex_query: nil,
        ex_fragment: nil),
  // Double slash at start of base path (with host - not related to idempotence fix from Aug 2020).
  .init(input: "path",
        base: "non-spec://host/..//p",
        ex_href: "non-spec://host//path",
        ex_scheme: "non-spec:",
        ex_hostname: "host",
        ex_port: nil,
        ex_pathname: "//path",
        ex_query: nil,
        ex_fragment: nil),
  
  // Path idempotence fixes from Aug 2020.
  .init(input: "hello",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/.//not-a-host/hello",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_pathname: "//not-a-host/hello",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "hello/..",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/.//not-a-host/",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_pathname: "//not-a-host/",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "hello/../..",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/.//",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_pathname: "//",
        ex_query: nil,
        ex_fragment: nil),
  .init(input: "hello/../../..",
        base: "web+demo:/.//not-a-host/test",
        ex_href: "web+demo:/",
        ex_scheme: "web+demo:",
        ex_hostname: "",
        ex_port: nil,
        ex_pathname: "/",
        ex_query: nil,
        ex_fragment: nil),

]



extension WebURLTests {
  
  // Converting tests to the WPT format (this comment for posterity's sake):
  //
  // - 'origin' is not included, because it hasn't been implemented in the WebURL model yet.
  //   I may come back to this and re-generate the files once it has.
  //
  // - 'host' is using the same value as 'hostname'. Again, isn't implemented on WebURL.JSModel yet, but
  //   none of these tests include hosts with ports, so luckily this works.
  //
  // - JSONEncoder emits keys in the wrong order. I found a project on GitHub with a JSON key sorter and adjusted it
  //   so it sorts in the order of the WPT tests.
  //   See: https://github.com/karwa/json_sort or https://karwa.github.io/json_sort/ for the live version.
  
  func testConversion() throws {
    var ported: [URLConstructorTest.FileEntry] = []
    for old_test in additionalTests {
      
      var expectedValues: URLValues?
      if old_test.ex_fail == false {
        expectedValues = URLValues(
          href: old_test.ex_href!,
          origin: nil,
          protocol: old_test.ex_scheme!,
          username: "", password: "",
          host: old_test.ex_hostname ?? "", hostname: old_test.ex_hostname ?? "",
          port: old_test.ex_port ?? "",
          pathname: old_test.ex_pathname ?? "",
          search: old_test.ex_query ?? "",
          hash: old_test.ex_fragment ?? "")
      }
      let new_test = URLConstructorTest.Testcase(
        input: old_test.input, base: old_test.base, expectedValues: expectedValues
      )
      ported.append(.testcase(new_test))
    }
    
    let reportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_constructor_ported.json")
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    try enc.encode(ported).write(to: reportURL)
    print("ℹ️ Report written to \(reportURL)")
  }

  /// These tests use the same methodology as the WPT constructor tests, with the goal that anything not overly implementation-specific
  /// can be upstreamed.
  ///
  func testURLConstructor() throws {
    var report = SimpleTestReport()
    for test in additionalTests {
      report.performTest { reporter in
        reporter.capture(key: "Test Case", test)
        
        // Parsing the base URL must always succeed.
        if WebURL(test.base, base: nil) == nil {
          reporter.fail("base URL failed to parse")
          return
        }
        // If failure = true, parsing "about:blank" against input must fail.
        if test.ex_fail {
          reporter.expectTrue(WebURL("about:blank", base: test.input) == nil)
        }
        
        guard let result = WebURL(test.input, base: test.base)?.jsModel else {
          reporter.capture(key: "Actual Result", "<nil>")
          reporter.expectTrue(test.ex_fail, "Expected failure")
          return
        }
        
        func checkProperties(_ url: WebURL.JSModel) {
          reporter.expectEqual(test.ex_href, url.href, "href")
          reporter.expectEqual(test.ex_scheme, url.scheme, "scheme")
          reporter.expectEqual(test.ex_hostname ?? "", url.hostname, "hostname")
          reporter.expectEqual(test.ex_port ?? "", url.port, "port")
          reporter.expectEqual(test.ex_pathname ?? "", url.pathname, "pathname")
          reporter.expectEqual(test.ex_query ?? "", url.search, "query")
          reporter.expectEqual(test.ex_fragment ?? "", url.fragment, "fragment")
        }
        reporter.capture(key: "Actual Result", result._debugDescription)
        checkProperties(result)
        
        // Check idempotence: parse the href again and check all properties.
        var serialized = result.href
        serialized.makeContiguousUTF8()
        guard let reparsed = WebURL(serialized, base: nil)?.jsModel else {
          reporter.fail("idempotence")
          return
        }
        reporter.capture(key: "Reparsed", reparsed._debugDescription)
        reporter.expectEqual(result.href, reparsed.href)
        checkProperties(reparsed)
      }
    }
    XCTAssertFalse(report.hasUnexpectedResults, "Test failed")
    
    // Generate a report file because the XCTest ones really aren't that helpful.
    let reportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("weburl_constructor_more.txt")
    try report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}

extension WebURLTests {
  
  func testJSModelSetters() {
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
