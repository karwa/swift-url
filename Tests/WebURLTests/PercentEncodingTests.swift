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
        XCTAssertFalse(PercentEncodeSet.C0Control.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(PercentEncodeSet.Path.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(PercentEncodeSet.Query_NotSpecial.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(PercentEncodeSet.Fragment.shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(PercentEncodeSet.UserInfo.shouldPercentEncode(ascii: codeUnit))
        // The only set it does not contain is the special-query set, which includes the extra U+0027.
        if PercentEncodeSet.Query_Special.shouldPercentEncode(ascii: codeUnit) {
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
    XCTAssertTrue(PercentEncodeSet.Component.shouldPercentEncode(ascii: ASCII.percentSign.codePoint))
  }

  func testEncodeSet_Component() {
    do_testEncodeSet_Component(encodingWith: {
      $0.utf8.lazy.percentEncoded(as: \.component)
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
    testEncodeSet(PercentEncodeSet.C0Control.self)
    testEncodeSet(PercentEncodeSet.Fragment.self)
    testEncodeSet(PercentEncodeSet.Query_NotSpecial.self)
    testEncodeSet(PercentEncodeSet.Query_Special.self)
    testEncodeSet(PercentEncodeSet.Path.self)
    testEncodeSet(PercentEncodeSet.UserInfo.self)
    testEncodeSet(PercentEncodeSet.Component.self)
    testEncodeSet(PercentEncodeSet.FormEncoded.self)
  }
}

extension PercentEncodingTests {

  func testPercentEncoded() {
    XCTAssertEqualElements("hello, world!".percentEncoded(as: \.userInfo), "hello,%20world!")
    XCTAssertEqualElements("/usr/bin/swift".percentEncoded(as: \.component), "%2Fusr%2Fbin%2Fswift")
    XCTAssertEqualElements("got en%63oders?".percentEncoded(as: \.userInfo), "got%20en%63oders%3F")
    XCTAssertEqualElements("king of the 🦆s".percentEncoded(as: \.form), "king+of+the+%F0%9F%A6%86s")

    XCTAssertEqualElements("fo%1o".percentEncoded(as: \.userInfo), "fo%1o")
    XCTAssertEqualElements("%1".percentEncoded(as: \.userInfo), "%1")
    XCTAssertEqualElements("%%%%%".percentEncoded(as: \.userInfo), "%%%%%")
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

  func testLazilyPercentEncoded() {

    func _testLazilyEncoded<EncodeSet: PercentEncodeSetProtocol>(
      _ original: String, as encodeSet: KeyPath<PercentEncodeSet, EncodeSet.Type>, to encoded: String
    ) {
      // Check the contents and Collection conformance.
      let lazilyEncoded = original.utf8.lazy.percentEncoded(as: encodeSet)
      XCTAssertEqualElements(lazilyEncoded, encoded.utf8)
      // Due to https://bugs.swift.org/browse/SR-13874 we can only check conformance for percentEncodedGroups.
      // CollectionChecker.check(lazilyEncoded)
      CollectionChecker.check(original.utf8.lazy.percentEncodedGroups(as: encodeSet))

      // Check the contents and Collection conformance in reverse.
      // Again, limited to awkward hacks via percentEncodedGroups due to stdlib bugs.
      let lazilyEncodedGroups = original.utf8.lazy.percentEncodedGroups(as: encodeSet)
      XCTAssertEqualElements(lazilyEncodedGroups.reversed().flatMap { $0.reversed() }, encoded.utf8.reversed())
      CollectionChecker.check(lazilyEncodedGroups.reversed() as ReversedCollection)
    }

    _testLazilyEncoded("hello, world!", as: \.userInfo, to: "hello,%20world!")
    _testLazilyEncoded("/usr/bin/swift", as: \.component, to: "%2Fusr%2Fbin%2Fswift")
    _testLazilyEncoded("got en%63oders?", as: \.userInfo, to: "got%20en%63oders%3F")
    _testLazilyEncoded("king of the 🦆s", as: \.form, to: "king+of+the+%F0%9F%A6%86s")

    _testLazilyEncoded("fo%1o", as: \.userInfo, to: "fo%1o")
    _testLazilyEncoded("%1", as: \.userInfo, to: "%1")
    _testLazilyEncoded("%%%%%", as: \.userInfo, to: "%%%%%")
  }

  func testPercentDecodedWithEncodeSet() {
    XCTAssertEqual("hello,%20world!".percentDecoded(from: \.percentEncodedOnly), "hello, world!")
    XCTAssertEqual("%2Fusr%2Fbin%2Fswift".percentDecoded(from: \.percentEncodedOnly), "/usr/bin/swift")
    XCTAssertEqual("king+of+the+%F0%9F%A6%86s".percentDecoded(from: \.form), "king of the 🦆s")
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

  func testLazilyPercentDecoded() {

    func _testLazilyDecoded<EncodeSet: PercentEncodeSetProtocol>(
      _ encoded: String, from decodeSet: KeyPath<PercentDecodeSet, EncodeSet.Type>, to decoded: String
    ) {
      let lazilyDecoded = encoded.utf8.lazy.percentDecodedUTF8(from: decodeSet)
      // Check the contents and Collection conformance.
      // This should also check BidirectionalCollection conformance, but the tests are a bit limited right now.
      XCTAssertEqualElements(lazilyDecoded, decoded.utf8)
      CollectionChecker.check(lazilyDecoded)
      // Check the contents and Collection conformance in reverse.
      // This tends to be quite a good double-check, especially as BidirectionalCollection tests are a bit limited.
      XCTAssertEqualElements(lazilyDecoded.reversed() as ReversedCollection, decoded.utf8.reversed())
      CollectionChecker.check(lazilyDecoded.reversed() as ReversedCollection)
    }

    _testLazilyDecoded("hello%2C%20world!", from: \.percentEncodedOnly, to: "hello, world!")
    _testLazilyDecoded("%2Fusr%2Fbin%2Fswift", from: \.percentEncodedOnly, to: "/usr/bin/swift")
    _testLazilyDecoded("%F0%9F%98%8E", from: \.percentEncodedOnly, to: "😎")

    _testLazilyDecoded("%5", from: \.percentEncodedOnly, to: "%5")
    _testLazilyDecoded("%0%61", from: \.percentEncodedOnly, to: "%0a")
    _testLazilyDecoded("%0%6172", from: \.percentEncodedOnly, to: "%0a72")
    _testLazilyDecoded("%0z%61", from: \.percentEncodedOnly, to: "%0za")
    _testLazilyDecoded("%0z%|1", from: \.percentEncodedOnly, to: "%0z%|1")
    _testLazilyDecoded("%%%%%%", from: \.percentEncodedOnly, to: "%%%%%%")

    _testLazilyDecoded("%F0%9F%A6%86%2C+of+course", from: \.form, to: "🦆, of course")
    _testLazilyDecoded("%F0%9F%8D%8E+%26+%F0%9F%8D%A6", from: \.form, to: "🍎 & 🍦")
  }
}
