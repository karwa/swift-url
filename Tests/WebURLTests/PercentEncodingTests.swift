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
      for codeUnit in encodedUTF8 {
        guard let ascii = ASCII(codeUnit) else {
          XCTFail("Found non-ASCII byte in percent-encoded string")
          continue
        }
        // The 'component' encode set is a superset of the following sets.
        XCTAssertFalse(URLEncodeSet.C0.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.Path.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.Query_NotSpecial.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.Fragment.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.UserInfo.shouldPercentEncode(ascii: codeUnit))
        // The only set it does not contain is the special-query set, which includes the extra U+0027.
        if URLEncodeSet.Query_Special.shouldPercentEncode(ascii: codeUnit) {
          XCTAssertEqual(ascii, .apostrophe)
        }
        // Strings encoded by the 'component' set should not contain forbidden host code-points (other than '%').
        XCTAssertFalse(
          ascii.isForbiddenHostCodePoint && ascii != .percentSign,
          "Forbidden host code point: \(Character(UnicodeScalar(ascii.codePoint)))"
        )
      }
      // The 'component' encode set should always preserve its contents, even if it contains
      // things that look like percent-encode sequences (maybe someone really meant to write "%20").
      XCTAssertEqualElements(encodedUTF8.lazy.percentDecodedUTF8, input.utf8)
    }

    // An important feature of the component encode-set is that it includes the % sign itself (U+0025).
    XCTAssertTrue(URLEncodeSet.Component.shouldPercentEncode(ascii: ASCII.percentSign.codePoint))
  }

  func testEncodeSet_Component() {
    do_testEncodeSet_Component(encodingWith: {
      $0.utf8.lazy.percentEncodedUTF8(URLEncodeSet.Component.self)
    })
  }

  func testTable() {
    XCTAssert(percent_encoding_table.count == 128)
  }

  func testDualImplementationEquivalence() {
    func testEncodeSet<EncodeSet: DualImplementedPercentEncodeSet>(_: EncodeSet.Type) {
      for char in ASCII.allCharacters {
        XCTAssertEqual(
          EncodeSet.shouldEscape_binary(ascii: char.codePoint),
          EncodeSet.shouldEscape_table(ascii: char.codePoint),
          "Mismatch for character \"\(char)\" (#\(char.codePoint)) in encode set #\(EncodeSet.self)"
        )
      }
    }
    testEncodeSet(URLEncodeSet.C0.self)
    testEncodeSet(URLEncodeSet.Fragment.self)
    testEncodeSet(URLEncodeSet.Query_NotSpecial.self)
    testEncodeSet(URLEncodeSet.Query_Special.self)
    testEncodeSet(URLEncodeSet.Path.self)
    testEncodeSet(URLEncodeSet.UserInfo.self)
    testEncodeSet(URLEncodeSet.Component.self)
    testEncodeSet(URLEncodeSet.FormEncoded.self)
  }
}

extension PercentEncodingTests {

  func testPercentEncoded() {
    XCTAssertEqualElements("hello, world!".percentEncoded(URLEncodeSet.UserInfo.self), "hello,%20world!")
    XCTAssertEqualElements("/usr/bin/swift".percentEncoded(URLEncodeSet.Component.self), "%2Fusr%2Fbin%2Fswift")
    XCTAssertEqualElements("got en%63oders?".percentEncoded(URLEncodeSet.UserInfo.self), "got%20en%63oders%3F")
    XCTAssertEqualElements("king of the 🦆s".percentEncoded(URLEncodeSet.FormEncoded.self), "king+of+the+%F0%9F%A6%86s")
  }

  func testURLComponentEncoded() {
    XCTAssertEqual("hello, world!".urlComponentEncoded, "hello%2C%20world!")
    XCTAssertEqual("/usr/bin/swift".urlComponentEncoded, "%2Fusr%2Fbin%2Fswift")
    XCTAssertEqual("😎".urlComponentEncoded, "%F0%9F%98%8E")
    // The .urlComponentEncoded property should use the component encode set.
    do_testEncodeSet_Component(encodingWith: { $0.urlComponentEncoded.utf8 })
  }

  func testURLFormEncoded() {
    let myKVPs: KeyValuePairs = ["favourite pet": "🦆, of course", "favourite foods": "🍎 & 🍦"]
    let form = myKVPs.map { key, value in "\(key.urlFormEncoded)=\(value.urlFormEncoded)" }
      .joined(separator: "&")
    XCTAssertEqual(form, "favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6")
  }

  func testPercentDecodedWithEncodeSet() {
    XCTAssertEqual("hello,%20world!".percentDecoded(PassthroughEncodeSet.self), "hello, world!")
    XCTAssertEqual("%2Fusr%2Fbin%2Fswift".percentDecoded(PassthroughEncodeSet.self), "/usr/bin/swift")
    XCTAssertEqual("king+of+the+%F0%9F%A6%86s".percentDecoded(URLEncodeSet.FormEncoded.self), "king of the 🦆s")
  }

  func testPercentDecoded() {
    XCTAssertEqual("hello%2C%20world!".percentDecoded, "hello, world!")
    XCTAssertEqual("%2Fusr%2Fbin%2Fswift".percentDecoded, "/usr/bin/swift")
    XCTAssertEqual("%F0%9F%98%8E".percentDecoded, "😎")

    // Check that we only do percent-decoding, not form-decoding.
    XCTAssertEqual("king+of+the+%F0%9F%A6%86s".percentDecoded, "king+of+the+🦆s")
  }

  func testURLFormDecoded() {
    let form = "favourite+pet=%F0%9F%A6%86%2C+of+course&favourite+foods=%F0%9F%8D%8E+%26+%F0%9F%8D%A6"
    let decoded = form.split(separator: "&").map { joined_kvp in joined_kvp.split(separator: "=") }
      .map { kvp in (kvp[0].urlFormDecoded, kvp[1].urlFormDecoded) }
    XCTAssertEqual(decoded.count, 2)
    XCTAssertTrue(decoded[0] == ("favourite pet", "🦆, of course"))
    XCTAssertTrue(decoded[1] == ("favourite foods", "🍎 & 🍦"))
  }
}
