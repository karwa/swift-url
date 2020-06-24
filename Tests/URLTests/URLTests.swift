import XCTest
@testable import URL

final class URLTests: XCTestCase {

    func testSpecExamples() {
        // These examples taken from the spec:
        // https://url.spec.whatwg.org/#urls

        if let results = XURL.Parser.parse("https://example.org/") {
            XCTAssertEqual(results.scheme, .https)
            XCTAssertEqual(results.host, .domain("example.org"))
        } else {
            XCTFail("Failed to parse")
        }

        if let results = XURL.Parser.parse("https://////example.org///") {
            XCTAssertEqual(results.scheme, .https)
            XCTAssertEqual(results.host, .domain("example.org"))
        } else {
            XCTFail("Failed to parse")
        }
	
        if let results = XURL.Parser.parse("https://example.com/././foo") {
            XCTAssertEqual(results.scheme, .https)
            XCTAssertEqual(results.host, .domain("example.com"))
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

       let testData: [(String, XURL.Components)] = [

        // Leading, trailing whitespace.
        ("        http://www.google.com   ", XURL.Components(
            scheme: .http,
            username: "", password: "", host: .domain("www.google.com"), port: nil,
            path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Non-ASCII characters in path.
        //
        // FIXME: Includes empty path components, but I'm *sure* this follows the spec
        // (in fact, we deviate a little so we don't add quite so many empty path components).
        ("http://mail.yahoo.com/€uronews/", XURL.Components(
            scheme: .http,
            username: "", password: "", host: .domain("mail.yahoo.com"), port: nil,
            path: ["%E2%82%ACuronews", ""], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Spaces in credentials.
        ("ftp://%100myUsername:sec ret ))@ftp.someServer.de:21/file/thing/book.txt", XURL.Components(
            scheme: .ftp,
            username: "%100myUsername", password: "sec%20ret%20))", host: .domain("ftp.someserver.de"), port: nil,
            path: ["file", "thing", "book.txt"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Windows drive letters.
        ("file:///C|/demo", XURL.Components(
            scheme: .file,
            username: "", password: "", host: .empty, port: nil,
            path: ["C:", "demo"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // '..' in path.
        //
        // FIXME: Includes empty path components, but I'm *sure* this follows the spec
        // (in fact, we deviate a little so we don't add quite so many empty path components).
        ("http://www.test.com/../athing/anotherthing/.././something/", XURL.Components(
            scheme: .http,
            username: "", password: "", host: .domain("www.test.com"), port: nil,
            path: ["athing", "something", ""], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // IPv6 address.
        ("https://[::ffff:192.168.0.1]/aThing", XURL.Components(
            scheme: .https,
            username: "", password: "", host: .ipv6Address(IPAddress.V6("::ffff:c0a8:1")!), port: nil,
            path: ["aThing"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // IPv4 address.
        ("https://192.168.0.1/aThing", XURL.Components(
            scheme: .https,
            username: "", password: "", host: .ipv4Address(IPAddress.V4("192.168.0.1")!), port: nil,
            path: ["aThing"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Non-ASCII opaque host.
        ("tp://www.bücher.de", XURL.Components(
            scheme: .other("tp"),
            username: "", password: "", host: .opaque(OpaqueHost("www.b%C3%BCcher.de")!), port: nil,
            path: [], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // Emoji opaque host.
        ("tp://👩‍👩‍👦‍👦️/family", XURL.Components(
            scheme: .other("tp"),
            username: "", password: "",
            host: .opaque(OpaqueHost("%F0%9F%91%A9%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A6%E2%80%8D%F0%9F%91%A6%EF%B8%8F")!), port: nil,
            path: ["family"], query: nil, fragment: nil, cannotBeABaseURL: false)
        ),

        // ==== Everything below is XFAIL while host parsing is still being implemented ==== //

        //Non-ASCII domain.
        // ("http://www.bücher.de", XURL.Components(
        //     scheme: "http",
        //     authority: .init(username: nil, password: nil, host: .domain("www.xn--bcher-kva.de"), port: nil),
        //     path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
        // ),
       ]

       print("===================")
       for (input, expectedComponents) in testData {
            let results = XURL.Parser.parse(input)
            XCTAssertEqual(results, expectedComponents, "Failed to correctly parse \(input)")
            debugPrint(input, results)
        }
        print("===================")
   }

   func testInvalidIPv4() {
        let testData: [(String, XURL.Components?)] = [
            ("https://0x3h", XURL.Components(
                scheme: .https,
                username: "", password: "", host: .domain("0x3h"), port: nil,
                path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)),
            ("https://234.266.2", nil),
        ]

        for (input, expectedComponents) in testData {
            let results = XURL.Parser.parse(input)
            XCTAssertEqual(results, expectedComponents, "Failed to correctly parse \(input)")
        }
   }

   func testPercentEscaping() {
       let testStrings: [String] = [
         "hello, world", // ASCII
         "👩‍👩‍👦‍👦️", // Long unicode
         "%🐶️",   // Leading percent
         "%z🐶️",  // Leading percent + one nonhex
         "%3🐶️",  // Leading percent + one hex
         "%3z🐶️", // Leading percent + one hex + one nonhex
         "🐶️%",   // Trailing percent
         "🐶️%z",  // Trailing percent + one nonhex
         "🐶️%3",  // Trailing percent + one hex
         "🐶️%3z", // Trailing percent + one hex + one nonhex
         // "%100" FIXME: Percent escaping doesn't round-trip.
       ]
       for string in testStrings {
//           let escaped = string.percentEscaped(where: { _ in false })
//           let decoded = escaped.removingPercentEscaping() //PercentEscaping.decodeString(utf8: escaped.utf8)

//           XCTAssertEqual(Array(string.utf8), Array(decoded.utf8))
//            print("--------------")
//            print("original: '\(string)'\t\tUTF8: \(Array(string.utf8))")
//            print("decoded : '\(decoded)'\t\tUTF8: \(Array(decoded.utf8))")
//            print("escaped:  '\(escaped)'\t\tUTF8: \(Array(escaped.utf8))")
        }
   }

   func testutf8() {


       let original = ""
       let encoded = "%F0%9F%91%A9%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A6%E2%80%8D%F0%9F%91%A6%EF%B8%8F"
//       let decoded = encoded.removingPercentEscaping() //PercentEscaping.decodeString(utf8: encoded.utf8)
        print("original: '\(original)'\t\tUTF8: \(Array(original.utf8))")
//        print("decoded : '\(decoded)'\t\tUTF8: \(Array(decoded.utf8))")
    //    for x in UInt8.min ... UInt8.max {
    //        let scalar = UnicodeScalar(x)
    //        print("\(x)", "Character: \(scalar).")
           
    //        let result = hasNonURLCodePoints(scalar.utf8)
    //        print("\(x)", "    Is Non-URL code point? \(result)")
    //        print("\(x)", "    Is forbidden host code point? \(ASCII(x)?.isForbiddenHostCodePoint ?? true)")
    //    }




    //     var invalid: [UInt8] = [0xEF, 0xBF, 0xBE] //[0xF4, 0x8F, 0xBF, 0xBF]
    //    for x: UInt8 in 0xA0 ... 0xAF {
    //     //    invalid[2] = x

    //        var iter = invalid.makeIterator()
    //        let result = hasNonURLCodePoints2(&iter)
    //        print("Is Non-URL code point? \(result)")

    //        iter = invalid.makeIterator()

    //         var utf8Decoder = UTF8()
    //         Decode: while true {
    //         switch utf8Decoder.decode(&iter) {
    //         case .scalarValue(let v):
    //             print("\(x)", "**** Decoded invalid sequence as: \(v) (value: \(v.value). isNonChar? \(v.properties.isNoncharacterCodePoint))")
    //         case .error:
    //             print("\(x)", "**** Decoder returned ERROR")
    //         case .emptyInput:
    //             print("\(x)", "**** Decoder returned EMPTY_INPUT")
    //             break Decode
    //         }
    //    }
    // }
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
