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

class SimpleToUnicodeTests: XCTestCase {}

fileprivate struct Label: Equatable {
  var label: AnyRandomAccessCollection<Unicode.Scalar>
  var needsTrailingDot: Bool

  init(label: AnyRandomAccessCollection<Unicode.Scalar>, needsTrailingDot: Bool) {
    self.label = label
    self.needsTrailingDot = needsTrailingDot
  }

  init(_ labelString: String, needsTrailingDot: Bool) {
    self.init(label: AnyRandomAccessCollection(Array(labelString.unicodeScalars)), needsTrailingDot: needsTrailingDot)
  }

  static func == (lhs: Label, rhs: Label) -> Bool {
    lhs.label.elementsEqual(rhs.label) && lhs.needsTrailingDot == rhs.needsTrailingDot
  }
}

extension IDNA {
  fileprivate static func toUnicode_Typed<Source>(
    utf8: Source, writer: (Label) -> Bool
  ) -> Bool where Source: Collection, Source.Element == UInt8 {
    toUnicode(utf8: utf8) { writer(Label(label: $0, needsTrailingDot: $1)) }
  }
}

extension SimpleToUnicodeTests {

  func testBasic() {
    let tests: [(String, String?)] = [

      // Mapping and normalization.
      ("hello.example.com", "hello.example.com"),
      ("hElLo.eXaMpLe.cOm", "hello.example.com"),
      ("0x𝟕f.1", "0x7f.1"),
      ("０Ｘｃ０．０２５０．０１", "0xc0.0250.01"),
      ("www.foo。bar.com", "www.foo.bar.com"),
      ("GOO 　goo.com", "goo  goo.com"),
      ("ₓn--fa-hia.example", "faß.example"),

      ("caf\u{00E9}.fr", "caf\u{00E9}.fr"),
      ("cafe\u{0301}.fr", "caf\u{00E9}.fr"),
      ("xn--caf-dma.fr", "caf\u{00E9}.fr"),
      ("xn--cafe-yvc.fr", nil),

      // ASCII to Unicode.
      ("xn--n3h", "☃"),
      ("xn--fa-hia.example", "faß.example"),
      ("hello.xn--ls8h.com", "hello.💩.com"),
      ("xn--fa-hia.api.xn--6qqa088eba.com", "faß.api.你好你好.com"),
      ("a.xn--igbi0gl.com", "a.أهلا.com"),
      ("a.xn--mgbet1febhkb.com", "a.هذهالكلمة.com"),
      ("xn--b1abfaaepdrnnbgefbadotcwatmq2g4l", "почемужеонинеговорятпорусски"),
      ("xn--bbb", "խ"),
      ("xn--1ch.com", "≠.com"),

      // Validation.
      ("a.b.c.xn--pokxncvks", nil),

      // Empty labels.
      ("xn--", ""),
      ("", ""),
      ("a.b.xn--.c", "a.b..c"),
      ("a.b..c", "a.b..c"),
      (".", "."),
      ("....", "...."),
    ]
    for (input, expectedResult) in tests {
      var actualResult = ""
      let success = IDNA.toUnicode(utf8: input.utf8) { label, needsDot in
        if label.contains(".") { XCTFail("Labels may not contain dots") }
        actualResult.unicodeScalars += label
        if needsDot { actualResult += "." }
        return true
      }
      guard success else {
        XCTAssertNil(expectedResult, "Unexpected failure: \(input)")
        continue
      }
      guard let expectedResult = expectedResult else {
        XCTFail("Unexpected success: \(input) -> \(actualResult)")
        continue
      }
      XCTAssertEqualElements(expectedResult.unicodeScalars, actualResult.unicodeScalars)
    }
  }

  func testInvalidUTF8() {

    // Currently, we get NFC normalization by gathering all the mapped code-points in to a String,
    // and using Foundation APIs/stdlib SPIs on String. That means we don't have a true, per-label "stream",
    // and things like invalid UTF-8 are detected before any labels are ever written via the callback.
    // This is what the test checks for with `UsingSerializedNFC = true`.
    //
    // In the future, this should use the stdlib NFC iterator directly, which would allow us to process
    // the Unicode data in a true stream, without going through String. At that point, UTF-8 validation
    // will occur when the particular label is actually processed.
    //
    // We can test that behavior today by disabling normalization, and it is useful for checking
    // how the rest of the code behaves. This is what this test checks for with `UsingSerializedNFC = false`.

    let UsingSerializedNFC = true

    let tests: [(input: [UInt8], output: (success: Bool, visitedLabels: [Label]))] = [
      (
        input: [0xDD],
        output: (false, [])
      ),
      (
        input: [0x61 /* a */, 0xDD],
        output: (false, [])
      ),
      (
        input: [0x61 /* a */, 0x2E /* . */, 0xDD],
        output: (false, [Label("a", needsTrailingDot: true)])
      ),
      (
        input: [0x61 /* a */, 0x2E /* . */, 0x62 /* b */, 0xDD],
        output: (false, [Label("a", needsTrailingDot: true)])
      ),
      (
        input: [0x61 /* a */, 0x2E /* . */, 0x62 /* b */, 0x2E /* . */, 0xDD],
        output: (false, [Label("a", needsTrailingDot: true), Label("b", needsTrailingDot: true)])
      ),
      (
        input: [0x61 /* a */, 0x2E /* . */, 0x62 /* b */, 0x2E /* . */, 0x62 /* c */, 0xDD],
        output: (false, [Label("a", needsTrailingDot: true), Label("b", needsTrailingDot: true)])
      ),
    ]
    for (input, expectedResult) in tests {
      var visitedLabels = [Label]()
      let success = IDNA.toUnicode_Typed(utf8: input) {
        visitedLabels.append($0)
        return true
      }
      XCTAssertEqual(success, expectedResult.success)
      if UsingSerializedNFC {
        XCTAssertEqualElements(visitedLabels, [])
      } else {
        XCTAssertEqualElements(visitedLabels, expectedResult.visitedLabels)
      }
    }
  }
}
