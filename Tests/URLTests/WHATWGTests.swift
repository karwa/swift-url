import XCTest
@testable import URL

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
    private struct URLConstructorTestCase: CustomStringConvertible {
        var input:          String? = nil
        var base:           String? = nil
        var href:           String? = nil
        var origin:         String? = nil
        var `protocol`:     String? = nil
        var username:       String? = nil
        var password:       String? = nil
        var host:           String? = nil
        var hostname:       String? = nil
        var pathname:       String? = nil
        var search:         String? = nil
        var hash:           String? = nil
        var searchParams:   String? = nil
        var port:           Int? = nil
        var failure:        Bool? = nil
        
        private init() {}
        
        init(from dict: Dictionary<String, Any>) {
            self.init()
            
            // Populate String keys
            let stringKeys: [(String, WritableKeyPath<Self, String?>)] = [
                ("input", \.input),
                ("base", \.base),
                ("href", \.href),
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
            \t.port:     \(port?.description ?? "<nil>")
            \t.pathname: \(pathname ?? "<nil>")
            \t.search:   \(search ?? "<nil>")
            \t.hash:     \(hash ?? "<nil>")
            }
            """
            return result
        }
    }
    
    func testURLConstructor() throws {
        let url  = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("urltestdata.json")
        let data = try Data(contentsOf: url)
        let array = try JSONSerialization.jsonObject(with: data, options: []) as! NSArray
        assert(array.count == 627, "Incorrect number of test cases.")
   
        var report = TestReport()
        report.expectedFailures = [
            // These test failures are due to us not having implemented the `domain2ascii` transform,
            // often in combination with other features (e.g. with percent encoding).
            //
            272, // domain2ascii: (no-break, zero-width, zero-width-no-break) are name-prepped away to nothing.
            276, // domain2ascii: U+3002 is mapped to U+002E (dot).
            286, // domain2ascii: fullwidth input should be converted to ASCII and NOT IDN-ized.
            294, // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
            295, // domain2ascii: Basic IDN support, UTF-8 and UTF-16 input should be converted to IDN.
            312, // domain2ascii: Fullwidth and escaped UTF-8 fullwidth should still be treated as IP.
            412, // domain2ascii: Hosts and percent-encoding.
            413, // domain2ascii: Hosts and percent-encoding.
            621, // domain2ascii: IDNA ignored code points in file URLs hosts.
            622, // domain2ascii: IDNA ignored code points in file URLs hosts.
            626, // domain2ascii: Empty host after the domain to ASCII.
        ]
        for item in array {
            if let sectionName = item as? String {
                report.recordSection(sectionName)
            } else if let rawTestInfo = item as? Dictionary<String, Any> {
                let expected = URLConstructorTestCase(from: rawTestInfo)
                report.recordTest { report in
                    let _parserResult = WebURL(expected.input!, base: expected.base)
                    // Capture test data.
                    report.capture(key: "expected", expected)
                    report.capture(key: "actual", _parserResult as Any)
                    // Compare results.
                    guard let parserResult = _parserResult else {
                        report.expectTrue(expected.failure == true)
                        return
                    }
                    report.expectFalse(expected.failure == true)
                    report.expectEqual(parserResult.scheme, expected.protocol)
                    report.expectEqual(parserResult.href, expected.href)
                    report.expectEqual(parserResult.hostname, expected.hostname)
                    report.expectEqual(parserResult.port.map { Int($0) }, expected.port)
                    report.expectEqual(parserResult.username, expected.username)
                    report.expectEqual(parserResult.password, expected.password)
                    report.expectEqual(parserResult.pathname, expected.pathname)
                    report.expectEqual(parserResult.search, expected.search)
                    report.expectEqual(parserResult.fragment, expected.hash)
                }
            } else {
                assertionFailure("👽 - Unexpected item found. Type: \(type(of: item)). Value: \(item)")
            }
        }
        
        let reportString = report.generateReport()
        let reportPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("url_whatwg_constructor_report.txt")
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

         let url   = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("setters_tests.json")
         let data  = try Data(contentsOf: url)
         var dict        = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        
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
        dict["comment"] = nil // Don't need the file-level comment.
        assert(dict.count == 9, "Incorrect number of test cases.")
         for property in ["search", "hostname", "port", "hash", "host", "pathname", "password", "username", "protocol"] {
            guard let rawTestsInGroup = dict[property] as? [[String: Any]] else {
                fatalError("No tests in group")
            }
            testGroups.append(URLSetterTestGroup(
                property: property,
                tests: rawTestsInGroup.map { testcase -> URLSetterTest in
                return URLSetterTest(
                    comment:  testcase["comment"]   as? String,
                    href:     testcase["href"]      as! String,
                    newValue: testcase["new_value"] as! String,
                    expected: testcase["expected"]  as! [String: String]
                )}
            ))
         }
        
        // Run the tests.
        var report = TestReport()
        report.expectedFailures = [
            // The 'port' tests are a little special.
            // The JS URL model exposes `port` as a String, and these XFAIL-ed tests
            // check that parsing stops when it encounters an invalid character/overflows/etc.
            // However, `WebURL.port` is a `UInt16?`, so these considerations simply don't apply.
            //
            // The tests fail because `transformValue` ends up returning `nil` for these junk strings.
            52, 53, 54, 55, 56, 57, 58, 60, 61, // `port` tests.
            
            96, // IDNA Nontransitional_Processing.
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
    private func performSetterTest<T>(_ testcase: URLSetterTest, property: WritableKeyPath<WebURL, T>, transformValue: (String)->T, _ report: inout TestReport) {
        
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
        report.capture(key: "Expected", testcase.expected.lazy.map { "\($0): \"\($1)\"" }.joined(separator: "\n\t") as String)
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

// A helper for generating better test reports for the WHATWG tests.
// XCTest just doesn't handle it well:
// - No support for "sub-tests".
//   I'd rather see that 15 sub-tests failed than that 126 individual assertions across all sub-tests failed.
// - The reports are only decent in Xcode.
// - No ability to XFAIL tests and check that they really *do* fail.
// - etc...
fileprivate struct TestReport {
    var expectedFailures: Set<Int> = []
    
    private var testFailures = [Int: [(String, Any)]]()
    private var sections = [(Int, String)]()
    private var num_xPass_pass = 0
    private var num_xPass_fail = 0
    private var num_xFail_pass = 0
    private var num_xFail_fail = 0
    // Current test.
    private var currentTestIdx = 0
    private var currentTestDidFail      = false
    private var currentTestCapturedData = [(String, Any)]()
    
    mutating func recordSection(_ name: String) {
        sections.append((currentTestIdx, name))
        currentTestIdx += 1
    }
    
    mutating func recordTest(_ test: (inout TestReport) throws -> Void) rethrows {
        currentTestDidFail = false
        currentTestCapturedData.removeAll(keepingCapacity: true)
        defer {
            if expectedFailures.contains(currentTestIdx) {
                if !currentTestDidFail {
                    num_xFail_pass += 1
                    XCTFail("Unexpected pass for test \(currentTestIdx). Data: \(currentTestCapturedData)")
                    currentTestCapturedData.insert(("TESTREPORT_REASON", "✅❌❔ UNEXPECTED PASS"), at: 0)
                	testFailures[currentTestIdx] = currentTestCapturedData
                } else {
                    num_xFail_fail += 1
                }
            } else {
                if currentTestDidFail {
                    num_xPass_fail += 1
                    XCTFail("Unexpected fail for test \(currentTestIdx). Data: \(currentTestCapturedData)")
                    testFailures[currentTestIdx] = currentTestCapturedData
                } else {
                    num_xPass_pass += 1
                }
            }
            currentTestDidFail = false
            currentTestCapturedData.removeAll(keepingCapacity: true)
            currentTestIdx += 1
        }
        
        do {
            try test(&self)
        } catch {
            currentTestDidFail = true
            throw error
        }
    }
    
    mutating func capture(key: String, _ object: Any) {
        currentTestCapturedData.append((key, object))
    }
    
    mutating func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ key: String? = nil) {
        if lhs != rhs {
            currentTestDidFail = true
        }
    }
    
    mutating func expectTrue(_ lhs: Bool, _ message: String = "condition was false") {
        if lhs == false {
            currentTestDidFail = true
        }
    }
    
    mutating func expectFalse(_ lhs: Bool, _ message: String = "condition was true") {
        if lhs == true {
            currentTestDidFail = true
        }
    }
    
    func generateReport() -> String {
        var output = ""
        print("""
        ------------------------------
        ------------------------------
              \(testFailures.count) Tests Failed
        ------------------------------
        Pass: \(num_xPass_pass + num_xFail_pass) (\(num_xPass_pass) expected)
        Fail: \(num_xPass_fail + num_xFail_fail) (\(num_xFail_fail) expected)
        Total: \(num_xPass_pass + num_xPass_fail + num_xFail_pass + num_xFail_fail) tests run
        ------------------------------
        """, to: &output)
        var sectionIterator = sections.makeIterator()
        var nextSection = sectionIterator.next()
        for index in testFailures.keys.sorted() {
            
            func printDivider() {
                if let section = nextSection {
                    if index > section.0 {
                        nextSection = sectionIterator.next()
                        if index > nextSection?.0 ?? -1 {
                            printDivider()
                            return
                        }

                        print("", to: &output)
                        print("============== \(section.1) ===========", to: &output)
                        print("", to: &output)
                        return
                    }
                }
                print("------------------------------", to: &output)
                print("", to: &output)
            }
            printDivider()
            
            guard let capturedData = testFailures[index] else { fatalError("Something went wrong...") }
            print("[\(index)]:", to: &output)
            print("", to: &output)
            for (key, value) in capturedData {
                print("""
                \t\(key):
                \t--------------
                \t\(value)
                """, to: &output)
                print("", to: &output)
            }
            
        }
        return output
    }
}
