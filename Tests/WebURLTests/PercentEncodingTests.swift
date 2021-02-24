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

import Checkit
import XCTest

@testable import WebURL

final class PercentEncodingTests: XCTestCase {}

extension PercentEncodingTests {

  func do_testEncodeSet_Component<T>(encodingWith encoder: (String) -> T) where T: Collection, T.Element == UInt8 {
    let testData: [String] = [
      stringWithEveryASCIICharacter,
      stringWithEveryASCIICharacter + "😎✈️🏝🍹" + stringWithEveryASCIICharacter.shuffled(),
      "%00this is not percent-encoded: %20",
      "nochange0123456789",
      "",
    ]
    for input in testData {
      let encodedUTF8 = encoder(input)
      for byte in encodedUTF8 {
        guard let ascii = ASCII(byte) else {
          XCTFail("Found non-ASCII byte in percent-encoded string")
          continue
        }
        // The 'component' encode set is a superset of the following sets.
        XCTAssertFalse(URLEncodeSet.C0.shouldEscape(character: ascii))
        XCTAssertFalse(URLEncodeSet.Path.shouldEscape(character: ascii))
        XCTAssertFalse(URLEncodeSet.Query_NotSpecial.shouldEscape(character: ascii))
        XCTAssertFalse(URLEncodeSet.Fragment.shouldEscape(character: ascii))
        XCTAssertFalse(URLEncodeSet.UserInfo.shouldEscape(character: ascii))
        // The only set it does not contain is the special-query set, which includes the extra U+0027.
        if URLEncodeSet.Query_Special.shouldEscape(character: ascii) {
          XCTAssertEqual(ascii, .apostrophe)
        }
        // Strings encoded by the 'component' set should not contain forbidden host code-points (other than '%').
        XCTAssertFalse(
          URLStringUtils.isForbiddenHostCodePoint(ascii) && ascii != .percentSign,
          "Forbidden host code point: \(Character(UnicodeScalar(ascii.codePoint)))"
        )
      }
      // The 'component' encode set should always preserve its contents, even if it contains
      // things that look like percent-encode sequences (maybe someone really meant to write "%20").
      XCTAssertEqualElements(encodedUTF8.lazy.percentDecoded, input.utf8)
    }

    // An important feature of the component encode-set is that it includes the % sign itself (U+0025).
    XCTAssertTrue(URLEncodeSet.Component.shouldEscape(character: .percentSign))
  }

  func testEncodeSet_Component() {
    do_testEncodeSet_Component(encodingWith: {
      $0.utf8.lazy.percentEncoded(using: URLEncodeSet.Component.self).joined()
    })
  }
}

extension PercentEncodingTests {

  func testURLEncoded() {
    XCTAssertEqual("hello, world!".urlEncoded, "hello%2C%20world!")
    XCTAssertEqual("/usr/bin/swift".urlEncoded, "%2Fusr%2Fbin%2Fswift")
    XCTAssertEqual("😎".urlEncoded, "%F0%9F%98%8E")
    // The .urlEncoded property should use the component encode set.
    do_testEncodeSet_Component(encodingWith: { $0.urlEncoded.utf8 })
  }

  func testURLFormEncoded() {
    let myKVPs: KeyValuePairs = ["favourite pet": "🦆, of course", "favourite foods": "🍎 & 🍦"]
    let form = myKVPs.map { key, value in "\(key.urlFormEncoded)=\(value.urlFormEncoded)" }
      .joined(separator: "&")
    XCTAssertEqual(form, "favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6")
  }

  func testURLDecoded() {
    XCTAssertEqual("hello%2C%20world!".urlDecoded, "hello, world!")
    XCTAssertEqual("%2Fusr%2Fbin%2Fswift".urlDecoded, "/usr/bin/swift")
    XCTAssertEqual("%F0%9F%98%8E".urlDecoded, "😎")
  }

  func testURLFormDecoded() {
    let form = "favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6"
    let decoded = form.split(separator: "&").map { joined_kvp in joined_kvp.split(separator: "=") }
      .map { kvp in (kvp[0].urlFormDecoded, kvp[1].urlFormDecoded) }
    XCTAssertEqual(decoded.count, 2)
    XCTAssertTrue(decoded[0] == ("favourite pet", "🦆, of course"))
    XCTAssertTrue(decoded[1] == ("favourite foods", "🍎 & 🍦"))
  }

  func testLazyURLDecoded() {
    XCTAssertEqual(
      Array("hello%2C%20world! 😎✈️".lazy.urlDecodedScalars),
      ["h", "e", "l", "l", "o", ",", " ", "w", "o", "r", "l", "d", "!", " ", "\u{0001F60E}", "\u{2708}", "\u{FE0F}"]
    )
    XCTAssertEqualElements("hello%2C%20world!".lazy.urlDecodedScalars, "hello, world!".unicodeScalars)
    XCTAssertEqualElements("%2Fusr%2Fbin%2Fswift".lazy.urlDecodedScalars, "/usr/bin/swift".unicodeScalars)
    XCTAssertEqualElements("%F0%9F%98%8E".lazy.urlDecodedScalars, CollectionOfOne("\u{0001F60E}"))
  }
}
