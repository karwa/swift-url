import XCTest
@testable import URL

final class WHATWGTests: XCTestCase {
        
    struct URLConstructorTestInfo {
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
    }
    
    struct TestReport {
        
        mutating func recordSection(_ name: String) {
        }
    }
    
    func testWHATWG() throws {
        // Data file from:
        // https://github.com/web-platform-tests/wpt/blob/master/url/resources/urltestdata.json as of 15.06.2020
        let url  = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("urltestdata.json")
        let data = try Data(contentsOf: url)
        let array = try JSONSerialization.jsonObject(with: data, options: []) as! NSArray
        assert(array.count == 627, "Incorrect number of test cases.")
        
        var report = TestReport()
        
        func check(parserResult: XURL.Components?, expected: URLConstructorTestInfo) {
            guard let parserResult = parserResult else {
                XCTAssertTrue(expected.failure == true, """
                Unexpected failure.
                Input:\t|\(expected.input!)|
                Base: \t|\(expected.base ?? "<<nil>>")|
                """)
                return
            }
            XCTAssertFalse(expected.failure == true)
            XCTAssertEqual(parserResult.scheme + ":", expected.protocol)
            XCTAssertEqual(parserResult.host?.description ?? "", expected.host ?? "")
            XCTAssertEqual(parserResult.fragment.map { $0.isEmpty ? $0 : "#" + $0 } ?? "", expected.hash ?? "")
        }
        
        for (item, index) in zip(array, 0..<array.count) {
            if let sectionName = item as? String {
                report.recordSection(sectionName)
            } else if let rawTestInfo = item as? Dictionary<String, Any> {
                let testInfo = URLConstructorTestInfo(from: rawTestInfo)
                check(parserResult: XURL.Parser.parse(testInfo.input!, base: testInfo.base),
                      expected: testInfo)
            } else {
                assertionFailure("👽 - Unexpected item found. Index: \(index). Type: \(type(of: item)). Value: \(item)")
            }
        }
    }
}
