// Copyright The swift-url Contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
        XCTAssertTrue(schemeKind.isDefaultPort(utf8: serialized.utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: (":" + serialized).utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: (serialized + "0").utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: (serialized + "\n").utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: (serialized + "🦩").utf8))
        // Schemes with default ports are special.
        XCTAssertTrue(schemeKind.isSpecial)
      } else {
        // If there is no default port, everything should return 'false'.
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: "80".utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: ":80".utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: ":80\n".utf8))
        XCTAssertFalse(schemeKind.isDefaultPort(utf8: "🦩".utf8))
      }
      XCTAssertFalse(schemeKind.isDefaultPort(utf8: "".utf8))
      XCTAssertFalse(schemeKind.isDefaultPort(utf8: "\n".utf8))
    }
  }
}
