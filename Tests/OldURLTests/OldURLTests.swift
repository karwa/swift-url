import XCTest

@testable import OldURL

// TODO:
// Test plan.
//================
// - hasNonURLCodePoints
// - OldURLParser.Components.QueryParameters

let testBasic_printResults = false

final class OldURLTests: XCTestCase {

  /// Tests a handful of basic situations demonstrating the major features of the parser.
  /// These tests are not meant to be exhaustive; for something more comprehensive, see the WHATWG constructor tests.
  ///
  /// Note that these tests operate at the `OldURLParser.Components` level, not the `WebURL` object model-level.
  ///
  func testBasic() {

    let testData: [(String, OldURLParser.Components?)] = [

      // Leading, trailing whitespace.
      (
        "        http://www.google.com   ",
        OldURLParser.Components(
          scheme: .http,
          username: "", password: "", host: .domain("www.google.com"), port: nil,
          path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // Non-ASCII characters in path.
      (
        "http://mail.yahoo.com/€uronews/",
        OldURLParser.Components(
          scheme: .http,
          username: "", password: "", host: .domain("mail.yahoo.com"), port: nil,
          path: ["%E2%82%ACuronews", ""], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // Spaces in credentials.
      (
        "ftp://%100myUsername:sec ret ))@ftp.someServer.de:21/file/thing/book.txt",
        OldURLParser.Components(
          scheme: .ftp,
          username: "%100myUsername", password: "sec%20ret%20))", host: .domain("ftp.someserver.de"), port: nil,
          path: ["file", "thing", "book.txt"], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // Windows drive letters.
      (
        "file:///C|/demo",
        OldURLParser.Components(
          scheme: .file,
          username: "", password: "", host: .empty, port: nil,
          path: ["C:", "demo"], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // '..' in path.
      (
        "http://www.test.com/../athing/anotherthing/.././something/",
        OldURLParser.Components(
          scheme: .http,
          username: "", password: "", host: .domain("www.test.com"), port: nil,
          path: ["athing", "something", ""], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // IPv6 address.
      (
        "https://[::ffff:192.168.0.1]/aThing",
        OldURLParser.Components(
          scheme: .https,
          username: "", password: "", host: .ipv6Address(IPv6Address("::ffff:c0a8:1")!), port: nil,
          path: ["aThing"], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // IPv4 address.
      (
        "https://192.168.0.1/aThing",
        OldURLParser.Components(
          scheme: .https,
          username: "", password: "", host: .ipv4Address(IPv4Address("192.168.0.1")!), port: nil,
          path: ["aThing"], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // Invalid IPv4 address (trailing non-hex-digit makes it a domain).
      (
        "https://0x3h",
        OldURLParser.Components(
          scheme: .https,
          username: "", password: "", host: .domain("0x3h"), port: nil,
          path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // Invalid IPv4 address (overflows, otherwise correctly-formatted).
      ("https://234.266.2", nil),

      // Non-ASCII opaque host.
      (
        "tp://www.bücher.de",
        OldURLParser.Components(
          scheme: .other("tp"),
          username: "", password: "", host: .opaque(OpaqueHost("www.b%C3%BCcher.de")!), port: nil,
          path: [], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // Emoji opaque host.
      (
        "tp://👩‍👩‍👦‍👦️/family",
        OldURLParser.Components(
          scheme: .other("tp"),
          username: "", password: "",
          host: .opaque(
            OpaqueHost("%F0%9F%91%A9%E2%80%8D%F0%9F%91%A9%E2%80%8D%F0%9F%91%A6%E2%80%8D%F0%9F%91%A6%EF%B8%8F")!),
          port: nil,
          path: ["family"], query: nil, fragment: nil, cannotBeABaseURL: false)
      ),

      // ==== Everything below is XFAIL while host parsing is still being implemented ==== //

      //Non-ASCII domain.
      // ("http://www.bücher.de", OldURLParser.Components(
      //     scheme: "http",
      //     authority: .init(username: nil, password: nil, host: .domain("www.xn--bcher-kva.de"), port: nil),
      //     path: [""], query: nil, fragment: nil, cannotBeABaseURL: false)
      // ),
    ]

    func debugPrint(_ url: String, _ parsedComponents: OldURLParser.Components?) {
      print("URL:\t|\(url)|")
      if let results = parsedComponents {
        print("Results:\n\(OldURL(components: results).debugDescription)")
      } else {
        print("Results:\nFAIL")
      }
      print("===================")
    }


    if testBasic_printResults {
      print("===================")
    }
    for (input, expectedComponents) in testData {
      let results = OldURLParser.parse(input)
      XCTAssertEqual(results, expectedComponents, "Failed to correctly parse \(input)")
      if testBasic_printResults {
        debugPrint(input, results)
      }
    }
    if testBasic_printResults {
      print("===================")
    }
  }
}

// Percent-escaping tests.

extension OldURLTests {

  func testPercentEscaping() {
    let testStrings: [String] = [
      "hello, world",  // ASCII
      "hello, world. I am a long ASCII String. How are you today?",  // Long ASCII
      "👩‍👩‍👦‍👦️",  // Long unicode
      "👨‍👧‍👧 is 🇬🇧 but 🙃 and 🧑🏿‍🚒!",  // Long unicode 2
      "%🐶️",  // Leading percent
      "%z🐶️",  // Leading percent + one nonhex
      "%3🐶️",  // Leading percent + one hex
      "%3z🐶️",  // Leading percent + one hex + one nonhex
      "🐶️%",  // Trailing percent
      "🐶️%z",  // Trailing percent + one nonhex
      "🐶️%3",  // Trailing percent + one hex
      "🐶️%3z",  // Trailing percent + one hex + one nonhex
    ]
    for string in testStrings {
      var encoded = ""
      PercentEscaping.encodeIterativelyAsString(bytes: string.utf8, escapeSet: .url_c0) { encoded.append($0) }
      let decoded = PercentEscaping.decodeString(encoded)

      XCTAssertEqual(Array(string.utf8), Array(decoded.utf8))
    }

    do {
      let containsPercent = "%100"
      var encoded = ""
      // Must include the % sign to ensure that arbitrary strings will round-trip. URL escape sets don't include it.
      let roundTripEscapeSet = PercentEscaping.EscapeSet {
        PercentEscaping.EscapeSet.url_c0.shouldEscape($0) || $0 == .percentSign
      }
      PercentEscaping.encodeIterativelyAsString(
        bytes: containsPercent.utf8,
        escapeSet: roundTripEscapeSet,
        processChunk: { encoded.append($0) }
      )

      let decoded = PercentEscaping.decodeString(encoded)
      XCTAssertEqual(Array(containsPercent.utf8), Array(decoded.utf8))
    }
  }
}
