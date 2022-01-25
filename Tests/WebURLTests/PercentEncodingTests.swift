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

  func testTable() {
    XCTAssert(percent_encoding_table.count == 128)
  }

  func testPercentEncodedCharacter() {
    for byte in UInt8.min...UInt8.max {
      withPercentEncodedString(byte) { stringBuffer in
        XCTAssertEqual(stringBuffer.count, 3)
        let string = String(decoding: stringBuffer, as: UTF8.self)
        XCTAssertEqual(string.count, 3)
        XCTAssertEqual(string.first, "%")
        XCTAssertEqual(UInt8(string.dropFirst(), radix: 16), byte)
      }
    }
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
    testEncodeSet(URLEncodeSet.C0Control.self)
    testEncodeSet(URLEncodeSet.Fragment.self)
    testEncodeSet(URLEncodeSet.Query.self)
    testEncodeSet(URLEncodeSet.SpecialQuery.self)
    testEncodeSet(URLEncodeSet.Path.self)
    testEncodeSet(URLEncodeSet.UserInfo.self)
    testEncodeSet(URLEncodeSet.Component.self)
    testEncodeSet(URLEncodeSet.FormEncoding.self)
  }

  func testComponentEncodeSet() {
    let testData: [String] = [
      stringWithEveryASCIICharacter,
      stringWithEveryASCIICharacter + "😎✈️🏝🍹" + stringWithEveryASCIICharacter.shuffled(),
      "%00this is not percent-encoded: %20",
      "nochange0123456789",
      "",
    ]
    for input in testData {
      let encodedUTF8 = input.utf8.lazy.percentEncoded(using: .urlComponentSet)
      for codeUnit in encodedUTF8 {
        guard let ascii = ASCII(codeUnit) else {
          XCTFail("Found non-ASCII byte in percent-encoded string")
          continue
        }
        // The 'component' encode set is a superset of the following sets.
        XCTAssertFalse(URLEncodeSet.C0Control().shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.Path().shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.Query().shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.Fragment().shouldPercentEncode(ascii: codeUnit))
        XCTAssertFalse(URLEncodeSet.UserInfo().shouldPercentEncode(ascii: codeUnit))
        // The only set it does not contain is the special-query set, which includes the extra U+0027.
        if URLEncodeSet.SpecialQuery().shouldPercentEncode(ascii: codeUnit) {
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
      XCTAssertEqualElements(encodedUTF8.lazy.percentDecoded(), input.utf8)
    }

    // An important feature of the component encode-set is that it includes the % sign itself (U+0025).
    XCTAssertTrue(URLEncodeSet.Component().shouldPercentEncode(ascii: ASCII.percentSign.codePoint))
  }
}

extension PercentEncodingTests {

  func testPercentEncoded_documentationExamples() {

    // LazyCollectionProtocol.percentEncoded(using:)
    do {
      // Encode arbitrary data as an ASCII string.
      let image = Data([0xBA, 0x74, 0x5F, 0xE0, 0x11, 0x22, 0xEB, 0x10, 0x2C, 0x7F])
      XCTAssert(
        image.lazy.percentEncoded(using: .urlComponentSet)
          .elementsEqual("%BAt_%E0%11%22%EB%10%2C%7F".utf8)
      )

      // Encode-sets determine which characters are encoded, and some perform substitutions.
      let bytes = "hello, world!".utf8
      XCTAssert(
        bytes.lazy.percentEncoded(using: .urlComponentSet)
          .elementsEqual("hello%2C%20world!".utf8)
      )
      XCTAssert(
        bytes.lazy.percentEncoded(using: .formEncoding)
          .elementsEqual("hello%2C+world%21".utf8)
      )
    }

    // Collection.percentEncodedString(using:)
    do {
      // Encode arbitrary data as an ASCII string.
      let image = Data([0xBA, 0x74, 0x5F, 0xE0, 0x11, 0x22, 0xEB, 0x10, 0x2C, 0x7F])
      XCTAssertEqual(image.percentEncodedString(using: .urlComponentSet), "%BAt_%E0%11%22%EB%10%2C%7F")

      // Encode-sets determine which characters are encoded, and some perform substitutions.
      let bytes = "hello, world!".utf8
      XCTAssert(bytes.percentEncodedString(using: .urlComponentSet) == "hello%2C%20world!")
      XCTAssert(bytes.percentEncodedString(using: .formEncoding) == "hello%2C+world%21")
    }

    // StringProtocol.percentEncoded(using:)
    do {
      // Percent-encoding can be used to escapes special characters, e.g. spaces.
      XCTAssertEqual("hello, world!".percentEncoded(using: .userInfoSet), "hello,%20world!")

      // Encode-sets determine which characters are encoded, and some perform substitutions.
      XCTAssertEqual("/usr/bin/swift".percentEncoded(using: .urlComponentSet), "%2Fusr%2Fbin%2Fswift")
      XCTAssertEqual("king of the 🦆s".percentEncoded(using: .formEncoding), "king+of+the+%F0%9F%A6%86s")
    }
  }

  func testLazilyPercentEncoded_collectionConformance() {

    func _testLazilyEncoded<EncodeSet: PercentEncodeSet>(
      _ original: String, using encodeSet: EncodeSet._Member, expected encoded: String
    ) {
      // Check the contents and Collection conformance.
      let lazilyEncoded = original.utf8.lazy.percentEncoded(using: encodeSet)
      XCTAssertEqualElements(lazilyEncoded, encoded.utf8)
      CollectionChecker.check(lazilyEncoded)

      // Check the contents and Collection conformance in reverse.
      let lazilyEncodedReversed = lazilyEncoded.reversed() as ReversedCollection
      XCTAssertEqualElements(lazilyEncodedReversed, encoded.utf8.reversed())
      CollectionChecker.check(lazilyEncodedReversed)
    }

    _testLazilyEncoded("hello, world!", using: .userInfoSet, expected: "hello,%20world!")
    _testLazilyEncoded("/usr/bin/swift", using: .urlComponentSet, expected: "%2Fusr%2Fbin%2Fswift")
    _testLazilyEncoded("got en%63oders?", using: .userInfoSet, expected: "got%20en%63oders%3F")
    _testLazilyEncoded("king of the 🦆s", using: .formEncoding, expected: "king+of+the+%F0%9F%A6%86s")

    _testLazilyEncoded("fo%1o", using: .userInfoSet, expected: "fo%1o")
    _testLazilyEncoded("%1", using: .userInfoSet, expected: "%1")
    _testLazilyEncoded("%%%%%", using: .userInfoSet, expected: "%%%%%")
  }
}

extension PercentEncodingTests {

  func testPercentDecoded_documentationExamples() {

    // LazyCollectionProtocol.percentDecoded(substitutions:)
    do {
      // The bytes, containing a string with UTF-8 form-encoding.
      let source: [UInt8] = [
        0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64,
      ]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "h%C2%A3llo+world")

      // Specify the `.formEncoding` substitution set to decode the contents.
      XCTAssert(source.lazy.percentDecoded(substitutions: .formEncoding).elementsEqual("h£llo world".utf8))
    }

    // LazyCollectionProtocol.percentDecoded()
    do {
      // The bytes, containing a string with percent-encoding.
      let source: [UInt8] = [0x25, 0x36, 0x31, 0x25, 0x36, 0x32, 0x25, 0x36, 0x33]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "%61%62%63")

      // In this case, the decoded bytes contain the ASCII string "abc".
      XCTAssert(source.lazy.percentDecoded().elementsEqual("abc".utf8))
    }

    // StringProtocol.percentDecodedBytesArray(substitutions:)
    do {
      let originalImage = Data([0xBA, 0x74, 0x5F, 0xE0, 0x11, 0x22, 0xEB, 0x10, 0x2C, 0x7F])

      // Encode the data, e.g. using form-encoding.
      let encodedImage = originalImage.percentEncodedString(using: .formEncoding)
      XCTAssertEqual("%BAt_%E0%11%22%EB%10%2C%7F", encodedImage)

      // Decode the data, giving the same substitution map.
      let decodedImage = encodedImage.percentDecodedBytesArray(substitutions: .formEncoding)
      XCTAssert(decodedImage.elementsEqual(originalImage))
    }

    // StringProtocol.percentDecodedBytesArray()
    do {
      let url = WebURL("data:application/octet-stream,%BC%A8%CD")!

      // Check the data URL's payload.
      let payloadOptions = url.path.prefix(while: { $0 != "," })
      if payloadOptions.hasSuffix(";base64") {
        // ... decode as base-64
        XCTFail()
      } else {
        let encodedPayload = url.path[payloadOptions.endIndex...].dropFirst()
        let decodedPayload = encodedPayload.percentDecodedBytesArray()
        XCTAssert(decodedPayload == [0xBC, 0xA8, 0xCD])
      }
    }

    // StringProtocol.percentDecoded(substitutions:)
    do {
      // Decode percent-encoded UTF-8 as a string.
      XCTAssertEqual("hello,%20world!".percentDecoded(substitutions: .none), "hello, world!")
      XCTAssertEqual("%2Fusr%2Fbin%2Fswift".percentDecoded(substitutions: .none), "/usr/bin/swift")

      // Some encodings require a substitution map to accurately decode.
      XCTAssertEqual("king+of+the+%F0%9F%A6%86s".percentDecoded(substitutions: .formEncoding), "king of the 🦆s")
    }

    // StringProtocol.percentDecoded()
    do {
      // Decode percent-encoded UTF-8 as a string.
      XCTAssertEqual("hello%2C%20world!".percentDecoded(), "hello, world!")
      XCTAssertEqual("%2Fusr%2Fbin%2Fswift".percentDecoded(), "/usr/bin/swift")
      XCTAssertEqual("%F0%9F%98%8E".percentDecoded(), "😎")
    }
  }

  func testPercentDecoded_fastPath() {

    func checkFastPathResult<Substitutions: SubstitutionMap>(
      _ str: String, map: Substitutions._Member, expectedCanSkip: Bool, _ expectedDecoded: String
    ) {
      var copy = str
      let canSkipDecoding = copy.withUTF8 { map.base._canSkipDecoding($0) }
      XCTAssertEqual(canSkipDecoding, expectedCanSkip)
      if canSkipDecoding {
        XCTAssertEqual(str.percentDecoded(substitutions: map), str)
      }
      XCTAssertEqual(str.percentDecoded(substitutions: map), expectedDecoded)
    }

    // For regular decoding (no substitutions), a percent-sign means the source data might be encoded.
    checkFastPathResult(
      "hello, world! Test&Symbols£$@[]{}\n><?", map: .none, expectedCanSkip: true,
      "hello, world! Test&Symbols£$@[]{}\n><?"
    )
    checkFastPathResult(
      "Perform addition using the '+' operator", map: .none, expectedCanSkip: true,
      "Perform addition using the '+' operator"
    )
    checkFastPathResult(  // Not encoded, but contains a percent-sign so the fast-path assumes it might be.
      "hello, world! Te%st&Symbols£$@[]{}\n><?", map: .none, expectedCanSkip: false,
      "hello, world! Te%st&Symbols£$@[]{}\n><?"
    )
    checkFastPathResult(
      "hello, world! Te%GGst&Symbols£$@[]{}\n><?", map: .none, expectedCanSkip: false,
      "hello, world! Te%GGst&Symbols£$@[]{}\n><?"
    )
    checkFastPathResult(
      "hello, world! Te%20st&Symbols£$@[]{}\n><?", map: .none, expectedCanSkip: false,
      "hello, world! Te st&Symbols£$@[]{}\n><?"
    )

    // For form-decoding, a percent-sign or '+' character means the source data might be encoded.
    checkFastPathResult(
      "hello, world! Test&Symbols£$@[]{}\n><?", map: .formEncoding, expectedCanSkip: true,
      "hello, world! Test&Symbols£$@[]{}\n><?"
    )
    checkFastPathResult(
      "Perform addition using the '+' operator", map: .formEncoding, expectedCanSkip: false,
      "Perform addition using the ' ' operator"
    )
    checkFastPathResult(  // Not encoded, but contains a percent-sign so the fast-path assumes it might be.
      "hello, world! Te%st&Symbols£$@[]{}\n><?", map: .formEncoding, expectedCanSkip: false,
      "hello, world! Te%st&Symbols£$@[]{}\n><?"
    )
    checkFastPathResult(
      "hello, world! Te%GGst&Symbols£$@[]{}\n><?", map: .formEncoding, expectedCanSkip: false,
      "hello, world! Te%GGst&Symbols£$@[]{}\n><?"
    )
    checkFastPathResult(
      "hello, world! Te%20st&Symbols£$@[]{}\n><?", map: .formEncoding, expectedCanSkip: false,
      "hello, world! Te st&Symbols£$@[]{}\n><?"
    )
  }

  func testPercentDecoded_noFormDecoding() {
    // Check that we only do percent-decoding, not form-decoding.
    XCTAssertEqual("king+of+the+%F0%9F%A6%86s".percentDecoded(), "king+of+the+🦆s")
  }

  func testLazilyPercentDecoded_collectionConformance() {

    func _testLazilyDecoded<Substitutions: SubstitutionMap>(
      _ encoded: String, substitutions: Substitutions._Member, to decoded: String
    ) {
      let lazilyDecoded = encoded.utf8.lazy.percentDecoded(substitutions: substitutions)
      // Check the contents and Collection conformance.
      XCTAssertEqualElements(lazilyDecoded, decoded.utf8)
      CollectionChecker.check(lazilyDecoded)
      // Check the contents and Collection conformance in reverse.
      let lazilyDecodedReversed = lazilyDecoded.reversed() as ReversedCollection
      XCTAssertEqualElements(lazilyDecodedReversed, decoded.utf8.reversed())
      CollectionChecker.check(lazilyDecodedReversed)
    }

    _testLazilyDecoded("hello%2C%20world!", substitutions: .none, to: "hello, world!")
    _testLazilyDecoded("%2Fusr%2Fbin%2Fswift", substitutions: .none, to: "/usr/bin/swift")
    _testLazilyDecoded("%F0%9F%98%8E", substitutions: .none, to: "😎")

    _testLazilyDecoded("%5", substitutions: .none, to: "%5")
    _testLazilyDecoded("%0%61", substitutions: .none, to: "%0a")
    _testLazilyDecoded("%0%6172", substitutions: .none, to: "%0a72")
    _testLazilyDecoded("%0z%61", substitutions: .none, to: "%0za")
    _testLazilyDecoded("%0z%|1", substitutions: .none, to: "%0z%|1")
    _testLazilyDecoded("%%%%%%", substitutions: .none, to: "%%%%%%")

    _testLazilyDecoded("%F0%9F%A6%86%2C+of+course", substitutions: .formEncoding, to: "🦆, of course")
    _testLazilyDecoded("%F0%9F%8D%8E+%26+%F0%9F%8D%A6", substitutions: .formEncoding, to: "🍎 & 🍦")
  }

  func testLazilyDecoded_isDecodedOrUnsubstituted() {

    let decoded = "h%65llo".utf8.lazy.percentDecoded()
    var idx = decoded.startIndex
    XCTAssertEqual(UnicodeScalar(decoded[idx]), "h")
    XCTAssertFalse(decoded.isByteDecodedOrUnsubstituted(at: idx))
    decoded.formIndex(after: &idx)

    XCTAssertEqual(UnicodeScalar(decoded[idx]), "e")
    XCTAssertTrue(decoded.isByteDecodedOrUnsubstituted(at: idx))
    decoded.formIndex(after: &idx)

    var expected = "llo".unicodeScalars[...]
    while idx < decoded.endIndex {
      XCTAssertEqual(UnicodeScalar(decoded[idx]), expected.removeFirst())
      XCTAssertFalse(decoded.isByteDecodedOrUnsubstituted(at: idx))
      decoded.formIndex(after: &idx)
    }

    // endIndex always returns false.
    XCTAssertEqual(idx, decoded.endIndex)
    XCTAssertFalse(decoded.isByteDecodedOrUnsubstituted(at: idx))
    XCTAssertFalse(decoded.isByteDecodedOrUnsubstituted(at: decoded.endIndex))
  }

  func testLazilyDecoded_sourceIndices() {
    let source = "h%65llo".utf8
    let decoded = source.lazy.percentDecoded()

    var idx = decoded.startIndex
    XCTAssertEqual(UnicodeScalar(decoded[idx]), "h")
    XCTAssertEqual(String(source[decoded.sourceIndices(at: idx)]), "h")
    decoded.formIndex(after: &idx)

    XCTAssertEqual(UnicodeScalar(decoded[idx]), "e")
    XCTAssertEqual(String(source[decoded.sourceIndices(at: idx)]), "%65")
    decoded.formIndex(after: &idx)

    var expected = "llo".unicodeScalars[...]
    while idx < decoded.endIndex {
      XCTAssertEqual(UnicodeScalar(decoded[idx]), expected.removeFirst())
      XCTAssertEqualElements(CollectionOfOne(decoded[idx]), source[decoded.sourceIndices(at: idx)])
      decoded.formIndex(after: &idx)
    }

    // endIndex always returns an empty range at source.endIndex.
    XCTAssertEqual(idx, decoded.endIndex)
    XCTAssertEqual(decoded.sourceIndices(at: idx), source.endIndex..<source.endIndex)
    XCTAssertEqual(decoded.sourceIndices(at: decoded.endIndex), source.endIndex..<source.endIndex)
  }
}
