import XCTest
@testable import URL

final class WHATWGTests: XCTestCase {
        
    struct URLConstructorTestInfo: CustomStringConvertible {
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
            let intKeys: [(String, WritableKeyPath<Self, Int?>)] = [
                ("port", \.port)
            ]
            let boolKeys: [(String, WritableKeyPath<Self, Bool?>)] = [
                ("failure", \.failure)
            ]
            self.init()
            for (name, kp) in stringKeys {
                let value = dict[name]
                 if let str = value.flatMap({ $0 as? String }) {
                    self[keyPath: kp] = str
                 } else if value != nil {
                     fatalError("Did not decode type: \(type(of: value)) for name: \(name)")
                 }
            }
            for (name, kp) in intKeys {
                let value = dict[name]
                if let num = value.flatMap({ $0 as? NSNumber }) {
                    self[keyPath: kp] = num.intValue
                } else if let str = value.flatMap({ $0 as? String }) {
                    if str.isEmpty == false {
                    	self[keyPath: kp] = Int(str)!
                    }
                } else if value != nil {
                    fatalError("Did not decode type: \(type(of: value)) for name: \(name)")
                }
            }
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
        // Data file from:
        // https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json as of 15.06.2020
        let url  = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("urltestdata.json")
        let data = try Data(contentsOf: url)
        let array = try JSONSerialization.jsonObject(with: data, options: []) as! NSArray
        assert(array.count == 627, "Incorrect number of test cases.")
        
        func check(parserResult: WebURL?, expected: URLConstructorTestInfo, report: inout TestReport) {
            report.capture(key: "expected", expected)
            report.capture(key: "actual", parserResult as Any)
            
            guard let parserResult = parserResult else {
                report.expectTrue(expected.failure == true)
                return
            }
            report.expectFalse(expected.failure == true)
            report.expectEqual(parserResult.scheme, expected.protocol)
            // Lots of hostname failures are because of IDN
            report.expectEqual(parserResult.href, expected.href)
            report.expectEqual(parserResult.hostname, expected.hostname)
            report.expectEqual(parserResult.port.map { Int($0) }, expected.port)
            report.expectEqual(parserResult.username, expected.username)
            report.expectEqual(parserResult.password, expected.password)
            report.expectEqual(parserResult.pathname, expected.pathname)
            report.expectEqual(parserResult.search, expected.search)
            report.expectEqual(parserResult.fragment, expected.hash)
        }
        
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
        for (item, index) in zip(array, 0..<array.count) {
            if let sectionName = item as? String {
                report.recordSection(sectionName)
                assert(report.expectedFailures.contains(index) == false,
                       "Whoops - you added a comment item to the expected failures list.")
            } else if let rawTestInfo = item as? Dictionary<String, Any> {
                let testInfo = URLConstructorTestInfo(from: rawTestInfo)
                report.recordTest(index: index) { report in
                    check(parserResult: WebURL(testInfo.input!, base: testInfo.base),
                          expected: testInfo,
                          report: &report)
                }
            } else {
                assertionFailure("👽 - Unexpected item found. Index: \(index). Type: \(type(of: item)). Value: \(item)")
            }
        }
        
        let reportString = report.generateReport()
        try reportString.data(using: .utf8)!.write(to: URL(fileURLWithPath: "/var/tmp/url_whatwg_report.txt"))
    }
    
    func testFailing() {
        __BREAKPOINT__ = {
            print("breakpoint")
        }
        let result = WebURL("sc://%/", base: "about:blank")
        XCTAssertNotNil(result)
        print(result)
    }
}


fileprivate struct TestReport {
    var expectedFailures: Set<Int> = []
    
    private var testFailures = [Int: [String: Any]]()
    private var num_xPass_pass = 0
    private var num_xPass_fail = 0
    private var num_xFail_pass = 0
    private var num_xFail_fail = 0
    // Current test.
    private var currentTestDidFail      = false
    private var currentTestCapturedData = [String: Any]()
    
    mutating func recordSection(_ name: String) {
    }
    
    mutating func recordTest(index: Int, _ test: (inout TestReport) throws -> Void) rethrows {
        currentTestDidFail = false
        currentTestCapturedData.removeAll(keepingCapacity: true)
        defer {
            if expectedFailures.contains(index) {
                if !currentTestDidFail {
                    num_xFail_pass += 1
                    XCTFail("Unexpected pass for test \(index). Data: \(currentTestCapturedData)")
                    currentTestCapturedData["TESTREPORT_REASON"] = "✅❌❔ UNEXPECTED PASS"
                	testFailures[index] = currentTestCapturedData
                } else {
                    num_xFail_fail += 1
                }
            } else {
                if currentTestDidFail {
                    num_xPass_fail += 1
                    XCTFail("Unexpected fail for test \(index). Data: \(currentTestCapturedData)")
                    testFailures[index] = currentTestCapturedData
                } else {
                    num_xPass_pass += 1
                }
            }
            currentTestDidFail = false
            currentTestCapturedData.removeAll(keepingCapacity: true)
        }
        
        do {
            try test(&self)
        } catch {
            currentTestDidFail = true
            throw error
        }
    }
    
    mutating func capture(key: String, _ object: Any) {
        currentTestCapturedData[key] = object
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
        for index in testFailures.keys.sorted() {
            guard let capturedData = testFailures[index] else {
                fatalError("Something went wrong...")
            }
            print("[\(index)]:", to: &output)
            print("", to: &output)
            for key in capturedData.keys.sorted() {
                print("\(key):", to: &output)
                print("--------------", to: &output)
                print("\(capturedData[key]!)", to: &output)
                print("", to: &output)
            }
            print("------------------------------", to: &output)
            print("------------------------------", to: &output)
            print("", to: &output)
        }
        return output
    }
}