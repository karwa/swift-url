import XCTest

@testable import WebURL

/// Tests for `WebURL.SchemeKind`.
///
final class SchemeKindTests: XCTestCase {

  func testParser() {

    let testData: [(String, WebURL.SchemeKind, Bool)] = [
      ("ftp", .ftp, true),
      ("file", .file, true),
      ("http", .http, true),
      ("https", .https, true),
      ("ws", .ws, true),
      ("wss", .wss, true),
      ("foo", .other, false),
      ("✌️", .other, false),
    ]
    for (name, expectedSchemeKind, expectedIsSpecial) in testData {
      XCTAssertEqual(WebURL.SchemeKind(parsing: name.utf8), expectedSchemeKind)
      XCTAssertEqual(expectedSchemeKind.isSpecial, expectedIsSpecial)
      // The parser should not allow any trailing content.
      let nameWithSchemeTerminator = name + ":"
      XCTAssertEqual(WebURL.SchemeKind(parsing: nameWithSchemeTerminator.utf8), .other)
      let nameWithASCII = name + "x"
      XCTAssertEqual(WebURL.SchemeKind(parsing: nameWithASCII.utf8), .other)
      let nameWithNonASCII = name + "✌️"
      XCTAssertEqual(WebURL.SchemeKind(parsing: nameWithNonASCII.utf8), .other)
    }
    XCTAssertEqual(WebURL.SchemeKind(parsing: "".utf8), .other)
    XCTAssertEqual(WebURL.SchemeKind(parsing: "\n".utf8), .other)
  }

  func testDefaultPorts() {

    let testData: [(WebURL.SchemeKind, UInt16?)] = [
      (.ftp, 21),
      (.http, 80),
      (.https, 443),
      (.ws, 80),
      (.wss, 443),
      (.file, nil),
      (.other, nil),
    ]
    for (schemeKind, expectedDefaultPort) in testData {
      XCTAssertEqual(schemeKind.defaultPort, expectedDefaultPort)
      if let defaultPort = expectedDefaultPort {
        // isDefaultPortString should only return 'true' for the literal port number as an ASCII string.
        let serialized = String(defaultPort)
        XCTAssertTrue(schemeKind.isDefaultPortString(serialized.utf8))
        XCTAssertFalse(schemeKind.isDefaultPortString((":" + serialized).utf8))
        XCTAssertFalse(schemeKind.isDefaultPortString((serialized + "\n").utf8))
        XCTAssertFalse(schemeKind.isDefaultPortString((serialized + "🦩").utf8))
        // Schemes with default ports are special.
        XCTAssertTrue(schemeKind.isSpecial)
      } else {
        // If there is no default port, everything should return 'false'.
        XCTAssertFalse(schemeKind.isDefaultPortString("80".utf8))
        XCTAssertFalse(schemeKind.isDefaultPortString(":80".utf8))
        XCTAssertFalse(schemeKind.isDefaultPortString(":80\n".utf8))
        XCTAssertFalse(schemeKind.isDefaultPortString("🦩".utf8))
      }
      XCTAssertFalse(schemeKind.isDefaultPortString("".utf8))
      XCTAssertFalse(schemeKind.isDefaultPortString("\n".utf8))
    }
  }
}
