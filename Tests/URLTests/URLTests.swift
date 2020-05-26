import XCTest
@testable import URL

final class URLTests: XCTestCase {

    func _doParseTest(_ str: String) -> XURL.Components? {
        XURL.Parser.parse(str)
    }

    func testBasic() {

        if let results = _doParseTest("https://example.org/") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.org"))
        } else {
            XCTFail("Failed to parse")
        }

        if let results = _doParseTest("https://////example.org///") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.org"))
        } else {
            XCTFail("Failed to parse")
        }
	
        if let results = _doParseTest("https://example.com/././foo") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.com"))
            XCTAssertEqual(results.path, ["foo"])
        } else {
            XCTFail("Failed to parse")
        }

        if let results = _doParseTest("https://EXAMPLE.com/../x") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.com"))
            XCTAssertEqual(results.path, ["x"])
        } else {
            XCTFail("Failed to parse")
        }
    }

   

    func testExample() {
        _testExample()
    }

    func _testExample() {
        let tests = [
         "http://www.bücher.de",
         "        http://www.google.com   ",
         "http://mail.yahoo.com/€uronews/",
         "ftp://myUsername:sec ret ))@ftp.someServer.de:21/file/thing/book.txt",
         "https://www.reddit.com/r/PS5/comments/ftoa1s/playstation_5_new_details_from_mark_cerny_boost/fmb37ej/?context=3",
         "file:///C|/demo",
         "http://www.test.com/../athing/anotherthing/.././something/",
         "https://[::ffff:192.168.0.1]/aThing",
         "https://192.168.0.1/aThing",
         "ftp://Ë/somePath",
         "tp://Ë/somePath",
         ]
        print("===================")
        for t in tests {
            let results = XURL.Parser.parse(t)
            print("URL:\t|\(t)|")
            if let r = results {
                print("Results:\n\(r)")
            } else {
                print("Results:\nFAIL")
            }
            print("===================")
        }
    }

    // static var allTests = [
    //     ("testExample", testExample),
    // ]
}
