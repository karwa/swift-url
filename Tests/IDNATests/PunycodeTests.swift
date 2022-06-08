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

@testable import IDNA

class PunycodeTests: XCTestCase {}

extension PunycodeTests {

  func testEncode() {

    func _enpunycode(_ input: String) -> String? {
      var encoded = [UInt8]()
      guard Punycode.encode(input.unicodeScalars, into: { ascii in encoded.append(ascii) }) else {
        return nil
      }
      return String(decoding: encoded, as: UTF8.self)
    }

    // === Valid Inputs ===

    // Purely ASCII text is passed through unchanged, including preserving case, spaces, and control characters.
    XCTAssertEqual(_enpunycode("this is a test"), "this is a test")
    XCTAssertEqual(_enpunycode(stringWithEveryASCIICharacter), stringWithEveryASCIICharacter)

    // This also applies to punycode-encoded labels. They will not be double-encoded.
    XCTAssertEqual(_enpunycode("xn--n3h"), "xn--n3h")
    XCTAssertEqual(_enpunycode("xn--bbb"), "xn--bbb")
    XCTAssertEqual(_enpunycode("xn--blahblahblah"), "xn--blahblahblah")

    // Empty strings do not return failure.
    XCTAssertEqual(_enpunycode(""), "")

    // Hyphens.
    XCTAssertEqual(_enpunycode("-"), "-")
    XCTAssertEqual(_enpunycode("--"), "--")
    XCTAssertEqual(_enpunycode("---"), "---")
    XCTAssertEqual(_enpunycode("-a-b-"), "-a-b-")
    XCTAssertEqual(_enpunycode("-a-b-c"), "-a-b-c")
    XCTAssertEqual(_enpunycode("-énçøded"), "xn---nded-zram6j")
    XCTAssertEqual(_enpunycode("énçøded-"), "xn--nded--yram6j")
    XCTAssertEqual(_enpunycode("-énçøded-"), "xn---nded--xuao1l")
    XCTAssertEqual(_enpunycode("éxn--çøded-"), "xn--xn--ded--v0ap4o")

    // The tail should always consist of lowercase ASCII characters,
    // but it preserves the original codepoints exactly, including their case.
    XCTAssertEqual(_enpunycode("hËŁŁøWœrł∂"), "xn--hWr-via9trpal5m6995a")

    // Obligatory Emoji.
    XCTAssertEqual(_enpunycode("💩"), "xn--ls8h")
    XCTAssertEqual(_enpunycode("🦆 says hi"), "xn-- says hi-8336g")
    XCTAssertEqual(_enpunycode("🦆 sAyS HI"), "xn-- sAyS HI-8336g")

    // === Invalid Inputs ===

    // Unicode.Scalar is already validated, so the only other limitation on what can be encoded is string length;
    // it may not exceed 3854 (0xF0F - 1) scalars, as the implementation would overflow.
    // This is overall string length, including both ASCII and non-ASCII scalars.
    if Punycode.encode((0x00..<0xF0F).lazy.map { Unicode.Scalar($0)! }, into: { _ in }) {
      XCTFail("Expected string to be rejected")
    }
    if Punycode.encode((0x80..<(0x80 + 0xF0F)).lazy.map { Unicode.Scalar($0)! }, into: { _ in }) {
      XCTFail("Expected string to be rejected")
    }
  }

  func testDecodeInPlace() {

    enum ExpectedResult {
      case success
      case failure
      case notPunycode
    }

    func _depunycode(_ input: String, expected: ExpectedResult = .failure) -> [Unicode.Scalar]? {
      var decoded = Array(input.unicodeScalars)
      switch Punycode.decodeInPlace(&decoded) {
      case .success(let count):
        XCTAssertEqual(expected, .success, "Unexpected decoding")
        decoded.removeLast(decoded.count - count)
        return decoded
      case .notPunycode:
        XCTAssertEqual(expected, .notPunycode, "Expected decoding")
        return decoded
      case .failed:
        XCTAssertEqual(expected, .failure, "Expected failure")
        return nil
      }
    }

    // === Valid Inputs ===

    // Purely ASCII text is passed through unchanged, including preserving case, spaces, and control characters.
    XCTAssertEqualElements(
      _depunycode("this is a test", expected: .notPunycode), "this is a test".unicodeScalars
    )
    XCTAssertEqualElements(
      _depunycode(stringWithEveryASCIICharacter, expected: .notPunycode), stringWithEveryASCIICharacter.unicodeScalars
    )

    // Empty strings do not return failure.
    XCTAssertEqualElements(_depunycode("", expected: .notPunycode), [])
    XCTAssertEqualElements(_depunycode("xn--", expected: .success), [])

    // Hyphens.
    XCTAssertEqualElements(_depunycode("-", expected: .notPunycode), "-".unicodeScalars)
    XCTAssertEqualElements(_depunycode("--", expected: .notPunycode), "--".unicodeScalars)
    XCTAssertEqualElements(_depunycode("---", expected: .notPunycode), "---".unicodeScalars)
    XCTAssertEqualElements(_depunycode("-a-b-", expected: .notPunycode), "-a-b-".unicodeScalars)
    XCTAssertEqualElements(_depunycode("-a-b-c", expected: .notPunycode), "-a-b-c".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn---nded-zram6j", expected: .success), "-énçøded".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn--nded--yram6j", expected: .success), "énçøded-".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn---nded--xuao1l", expected: .success), "-énçøded-".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn--xn--ded--v0ap4o", expected: .success), "éxn--çøded-".unicodeScalars)

    // Case is preserved in the basic (ASCII) section when decoding.
    XCTAssertEqualElements(
      _depunycode("xn--hWr-via9trpal5m6995a", expected: .success),
      "hËŁŁøWœrł∂".unicodeScalars
    )
    XCTAssertEqualElements(
      _depunycode("xn--PorqunopuedensimplementehablarenEspaol-fmd56a", expected: .success),
      "PorquénopuedensimplementehablarenEspañol".unicodeScalars
    )

    // The tail recognizes ASCII alphas case-insensitively.
    XCTAssertEqualElements(_depunycode("xn--n3h", expected: .success), "☃".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn--n3H", expected: .success), "☃".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn--N3H", expected: .success), "☃".unicodeScalars)

    // Obligatory Emoji.
    XCTAssertEqualElements(_depunycode("xn--ls8h", expected: .success), "💩".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn-- says hi-8336g", expected: .success), "🦆 says hi".unicodeScalars)
    XCTAssertEqualElements(_depunycode("xn-- sAyS HI-8336g", expected: .success), "🦆 sAyS HI".unicodeScalars)

    // Valid Punycode but invalid IDN.
    XCTAssertEqualElements(
      _depunycode("xn--pokxncvks", expected: .success),
      "\u{3253}\u{32CE}\u{32CD}\u{32D3}\u{32D5}\u{32D8}".unicodeScalars
    )

    // === Invalid Inputs ===

    // Non-ASCII character among basic scalars.
    XCTAssertNil(_depunycode("xn--h☃r-via9trpal5m6995a"))

    // Non-ASCII alphanumeric scalar in tail.
    XCTAssertNil(_depunycode("xn--ls_8h"))
    XCTAssertNil(_depunycode("xn--ls8h+"))
    XCTAssertNil(_depunycode("xn--ls.8h"))
    XCTAssertNil(_depunycode("xn--lš8h"))

    // Not a valid variable-length integer.
    XCTAssertNil(_depunycode("xn--x"))
    XCTAssertNil(_depunycode("xn--xx"))

    // Invalid Unicode Scalar (value > 0x10FFFF).
    XCTAssertNil(_depunycode("xn--ja9012e9j0dq3r2309j"))

    // Delta would overflow.
    XCTAssertNil(_depunycode("xn--w093fj-xzc09uq2e092djfase2309jfeipq02ieq0-r0w9ju39hf983r3208fjtufncrv9ph90834"))
    XCTAssertNil(_depunycode("xn--ww902716a"))
  }
}

extension PunycodeTests {

  func testRFCSampleStrings() {

    // Sample strings from:
    // https://datatracker.ietf.org/doc/html/rfc3492#section-7.1

    func doTest(encoded expectedEncoded: String, decoded expectedDecoded: String) {

      // Decode the label, resulting in a string of Unicode scalars.
      var actualDecoded = Array(expectedEncoded.unicodeScalars)[...]
      guard case .success(let decodedCount) = Punycode.decodeInPlace(&actualDecoded) else {
        XCTFail("Failed to decode, or 'xn--' prefix not found")
        return
      }
      actualDecoded = actualDecoded.prefix(decodedCount)
      XCTAssertEqualElements(actualDecoded, expectedDecoded.unicodeScalars)

      // Re-encoding the decoded output should reproduce the original string.
      var actualReencoded = [Unicode.Scalar]()
      guard Punycode.encode(actualDecoded, into: { actualReencoded.append(Unicode.Scalar($0)) }) else {
        XCTFail("Failed to re-encode decoded output")
        return
      }
      XCTAssertEqualElements(actualReencoded, expectedEncoded.unicodeScalars)
    }

    // Arabic (Egyptian):
    doTest(
      encoded:
        "xn--egbpdaj6bu4bxfgehfvwxn",
      decoded:
        """
        \u{0644}\u{064A}\u{0647}\u{0645}\u{0627}\u{0628}\u{062A}\u{0643}\u{0644}\
        \u{0645}\u{0648}\u{0634}\u{0639}\u{0631}\u{0628}\u{064A}\u{061F}
        """
    )
    // Chinese (Simplified):
    doTest(
      encoded:
        "xn--ihqwcrb4cv8a8dqg056pqjye",
      decoded:
        "\u{4ED6}\u{4EEC}\u{4E3A}\u{4EC0}\u{4E48}\u{4E0D}\u{8BF4}\u{4E2D}\u{6587}"
    )
    // Chinese (Traditional):
    doTest(
      encoded:
        "xn--ihqwctvzc91f659drss3x8bo0yb",
      decoded:
        "\u{4ED6}\u{5011}\u{7232}\u{4EC0}\u{9EBD}\u{4E0D}\u{8AAA}\u{4E2D}\u{6587}"
    )
    // Czech:
    doTest(
      encoded:
        "xn--Proprostnemluvesky-uyb24dma41a",
      decoded:
        """
        \u{0050}\u{0072}\u{006F}\u{010D}\u{0070}\u{0072}\u{006F}\u{0073}\u{0074}\
        \u{011B}\u{006E}\u{0065}\u{006D}\u{006C}\u{0075}\u{0076}\u{00ED}\u{010D}\
        \u{0065}\u{0073}\u{006B}\u{0079}
        """
    )
    // Hebrew:
    doTest(
      encoded:
        "xn--4dbcagdahymbxekheh6e0a7fei0b",
      decoded:
        """
        \u{05DC}\u{05DE}\u{05D4}\u{05D4}\u{05DD}\u{05E4}\u{05E9}\u{05D5}\u{05D8}\
        \u{05DC}\u{05D0}\u{05DE}\u{05D3}\u{05D1}\u{05E8}\u{05D9}\u{05DD}\u{05E2}\
        \u{05D1}\u{05E8}\u{05D9}\u{05EA}
        """
    )
    // Hindi (Devanagari):
    doTest(
      encoded:
        "xn--i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd",
      decoded:
        """
        \u{092F}\u{0939}\u{0932}\u{094B}\u{0917}\u{0939}\u{093F}\u{0928}\u{094D}\
        \u{0926}\u{0940}\u{0915}\u{094D}\u{092F}\u{094B}\u{0902}\u{0928}\u{0939}\
        \u{0940}\u{0902}\u{092C}\u{094B}\u{0932}\u{0938}\u{0915}\u{0924}\u{0947}\
        \u{0939}\u{0948}\u{0902}
        """
    )
    // Japanese (kanji and hiragana):
    doTest(
      encoded:
        "xn--n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa",
      decoded:
        """
        \u{306A}\u{305C}\u{307F}\u{3093}\u{306A}\u{65E5}\u{672C}\u{8A9E}\u{3092}\
        \u{8A71}\u{3057}\u{3066}\u{304F}\u{308C}\u{306A}\u{3044}\u{306E}\u{304B}
        """
    )
    // Korean (Hangul syllables):
    doTest(
      encoded:
        "xn--989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c",
      decoded:
        """
        \u{C138}\u{ACC4}\u{C758}\u{BAA8}\u{B4E0}\u{C0AC}\u{B78C}\u{B4E4}\u{C774}\
        \u{D55C}\u{AD6D}\u{C5B4}\u{B97C}\u{C774}\u{D574}\u{D55C}\u{B2E4}\u{BA74}\
        \u{C5BC}\u{B9C8}\u{B098}\u{C88B}\u{C744}\u{AE4C}
        """
    )
    // Russian (Cyrillic):
    doTest(
      encoded:
        "xn--b1abfaaepdrnnbgefbadotcwatmq2g4l",
      decoded:
        """
        \u{043F}\u{043E}\u{0447}\u{0435}\u{043C}\u{0443}\u{0436}\u{0435}\u{043E}\
        \u{043D}\u{0438}\u{043D}\u{0435}\u{0433}\u{043E}\u{0432}\u{043E}\u{0440}\
        \u{044F}\u{0442}\u{043F}\u{043E}\u{0440}\u{0443}\u{0441}\u{0441}\u{043A}\
        \u{0438}
        """
    )
    // Spanish:
    doTest(
      encoded:
        "xn--PorqunopuedensimplementehablarenEspaol-fmd56a",
      decoded:
        """
        \u{0050}\u{006F}\u{0072}\u{0071}\u{0075}\u{00E9}\u{006E}\u{006F}\u{0070}\
        \u{0075}\u{0065}\u{0064}\u{0065}\u{006E}\u{0073}\u{0069}\u{006D}\u{0070}\
        \u{006C}\u{0065}\u{006D}\u{0065}\u{006E}\u{0074}\u{0065}\u{0068}\u{0061}\
        \u{0062}\u{006C}\u{0061}\u{0072}\u{0065}\u{006E}\u{0045}\u{0073}\u{0070}\
        \u{0061}\u{00F1}\u{006F}\u{006C}
        """
    )
    // Vietnamese:
    doTest(
      encoded:
        "xn--TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g",
      decoded:
        """
        \u{0054}\u{1EA1}\u{0069}\u{0073}\u{0061}\u{006F}\u{0068}\u{1ECD}\u{006B}\
        \u{0068}\u{00F4}\u{006E}\u{0067}\u{0074}\u{0068}\u{1EC3}\u{0063}\u{0068}\
        \u{1EC9}\u{006E}\u{00F3}\u{0069}\u{0074}\u{0069}\u{1EBF}\u{006E}\u{0067}\
        \u{0056}\u{0069}\u{1EC7}\u{0074}
        """
    )

    // Extras from the standard:
    // > The next several examples are all names of Japanese music artists,
    // > song titles, and TV programs, just because the author happens to have
    // > them handy
    // :)

    // 3<nen>B<gumi><kinpachi><sensei>
    doTest(
      encoded: "xn--3B-ww4c5e180e575a65lsy2b",
      decoded: "\u{0033}\u{5E74}\u{0042}\u{7D44}\u{91D1}\u{516B}\u{5148}\u{751F}"
    )

    // <amuro><namie>-with-SUPER-MONKEYS
    doTest(
      encoded: "xn---with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n",
      decoded:
        """
        \u{5B89}\u{5BA4}\u{5948}\u{7F8E}\u{6075}\u{002D}\u{0077}\u{0069}\u{0074}\
        \u{0068}\u{002D}\u{0053}\u{0055}\u{0050}\u{0045}\u{0052}\u{002D}\u{004D}\
        \u{004F}\u{004E}\u{004B}\u{0045}\u{0059}\u{0053}
        """
    )

    // Hello-Another-Way-<sorezore><no><basho>
    doTest(
      encoded: "xn--Hello-Another-Way--fc4qua05auwb3674vfr0b",
      decoded:
        """
        \u{0048}\u{0065}\u{006C}\u{006C}\u{006F}\u{002D}\u{0041}\u{006E}\u{006F}\
        \u{0074}\u{0068}\u{0065}\u{0072}\u{002D}\u{0057}\u{0061}\u{0079}\u{002D}\
        \u{305D}\u{308C}\u{305E}\u{308C}\u{306E}\u{5834}\u{6240}
        """
    )

    // <hitotsu><yane><no><shita>2
    doTest(
      encoded: "xn--2-u9tlzr9756bt3uc0v",
      decoded: "\u{3072}\u{3068}\u{3064}\u{5C4B}\u{6839}\u{306E}\u{4E0B}\u{0032}"
    )

    // Maji<de>Koi<suru>5<byou><mae>
    doTest(
      encoded: "xn--MajiKoi5-783gue6qz075azm5e",
      decoded:
        """
        \u{004D}\u{0061}\u{006A}\u{0069}\u{3067}\u{004B}\u{006F}\u{0069}\u{3059}\
        \u{308B}\u{0035}\u{79D2}\u{524D}
        """
    )

    // <pafii>de<runba>
    doTest(
      encoded: "xn--de-jg4avhby1noc0d",
      decoded: "\u{30D1}\u{30D5}\u{30A3}\u{30FC}\u{0064}\u{0065}\u{30EB}\u{30F3}\u{30D0}"
    )

    // <sono><supiido><de>
    doTest(
      encoded: "xn--d9juau41awczczp",
      decoded: "\u{305D}\u{306E}\u{30B9}\u{30D4}\u{30FC}\u{30C9}\u{3067}"
    )
  }
}
