import XCTest
@testable import URL

final class URLTests: XCTestCase {

    func testSpecExamples() {
        // These examples taken from the spec:
        // https://url.spec.whatwg.org/#urls

        if let results = XURL.Parser.parse("https://example.org/") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.org"))
        } else {
            XCTFail("Failed to parse")
        }

        if let results = XURL.Parser.parse("https://////example.org///") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.org"))
        } else {
            XCTFail("Failed to parse")
        }
	
        if let results = XURL.Parser.parse("https://example.com/././foo") {
            XCTAssertEqual(results.scheme, "https")
            XCTAssertEqual(results.authority.host, .domain("example.com"))
            XCTAssertEqual(results.path, ["foo"])
        } else {
            XCTFail("Failed to parse")
        }

        // XFAIL: We need to normalise the case.

        // if let results = XURL.Parser.parse("https://EXAMPLE.com/../x") {
        //     XCTAssertEqual(results.scheme, "https")
        //     XCTAssertEqual(results.authority.host, .domain("example.com"))
        //     XCTAssertEqual(results.path, ["x"])
        // } else {
        //     XCTFail("Failed to parse")
        // }
    }

   func testBasic() {

       func opaque(_ str: String) -> XURL.Host {
           return .opaque(str)
           //return .opaque(OpaqueHost(unchecked: str))
       }
       let testData: [(String, XURL.Components)] = [

        // Leading, trailing whitespace.
        ("        http://www.google.com   ", XURL.Components(
            scheme: "http",
            authority: .init(username: nil, password: nil, host: .domain("www.google.com"), port: nil),
            path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Non-ASCII characters in path.
        //
        // FIXME: Includes empty path components, but I'm *sure* this follows the spec
        // (in fact, we deviate a little so we don't add quite so many empty path components).
        ("http://mail.yahoo.com/€uronews/", XURL.Components(
            scheme: "http",
            authority: .init(username: nil, password: nil, host: .domain("mail.yahoo.com"), port: nil),
            path: ["%E2%82%ACuronews", ""], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Spaces in credentials.
        ("ftp://myUsername:sec ret ))@ftp.someServer.de:21/file/thing/book.txt", XURL.Components(
            scheme: "ftp",
            authority: .init(username: "myUsername", password: "sec%20ret%20))", host: .domain("ftp.someServer.de"), port: nil),
            path: ["file", "thing", "book.txt"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Windows drive letters.
        ("file:///C|/demo", XURL.Components(
            scheme: "file",
            authority: .init(username: nil, password: nil, host: .empty, port: nil),
            path: ["C:", "demo"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // '..' in path.
        //
        // FIXME: Includes empty path components, but I'm *sure* this follows the spec
        // (in fact, we deviate a little so we don't add quite so many empty path components).
        ("http://www.test.com/../athing/anotherthing/.././something/", XURL.Components(
            scheme: "http",
            authority: .init(username: nil, password: nil, host: .domain("www.test.com"), port: nil),
            path: ["athing", "something", ""], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // IPv6 address.
        ("https://[::ffff:192.168.0.1]/aThing", XURL.Components(
            scheme: "https",
            authority: .init(username: nil, password: nil, host: .ipv6Address(IPAddress.V6("::ffff:c0a8:1")!), port: nil),
            path: ["aThing"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // IPv4 address.
        ("https://192.168.0.1/aThing", XURL.Components(
            scheme: "https",
            authority: .init(username: nil, password: nil, host: .ipv4Address(IPAddress.V4("192.168.0.1")!), port: nil),
            path: ["aThing"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // ==== Everything below is XFAIL while host parsing is still being implemented ==== //

        //Non-ASCII domain.
        // ("http://www.bücher.de", XURL.Components(
        //     scheme: "http",
        //     authority: .init(username: nil, password: nil, host: .domain("www.xn--bcher-kva.de"), port: nil),
        //     path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
        // ),

        // Non-ASCII opaque host.
        // ("tp://www.bücher.de", XURL.Components(
        //     scheme: "tp",
        //     authority: .init(username: nil, password: nil, host: opaque("www.b%C3%BCcher.de"), port: nil),
        //     path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
        // ),

        // Emoji opaque host.
        // ("tp://👩‍👩‍👦‍👦️/family", XURL.Components(
        //     scheme: "tp",
        //     authority: .init(username: nil, password: nil, host: opaque("%F0%9F%91%A9%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A6%E2%80%8D%F0%9F%91%A6%EF%B8%8F"), port: nil),
        //     path: ["family"], query: nil, fragment: nil, cannotBeABaseURL: false)
        // ),

       ]

       //print("===================")
       for (input, expectedComponents) in testData {
            let results = XURL.Parser.parse(input)
            XCTAssertEqual(results, expectedComponents, "Failed to correctly parse \(input)")
            // debugPrint(input, results)
        }
        //print("===================")
   }
}


fileprivate func debugPrint(_ url: String, _ parsedComponents: XURL.Components?) {
    print("URL:\t|\(url)|")
    if let results = parsedComponents {
        print("Results:\n\(results)")
    } else {
        print("Results:\nFAIL")
    }
    print("===================")
}
