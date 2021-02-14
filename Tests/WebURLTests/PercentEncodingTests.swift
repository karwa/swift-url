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

  func testEncodeSet_Component() {
    let testData: [String] = [
      stringWithEveryASCIICharacter,
      stringWithEveryASCIICharacter + "😎✈️🏝🍹" + stringWithEveryASCIICharacter.shuffled(),
      "%00this is not percent-encoded: %20",
      "nochange0123456789",
      "",
    ]
    for input in testData {
      let encodedUTF8 = input.utf8.lazy.percentEncoded(using: URLEncodeSet.Component.self).joined()
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
      }
      // The 'component' encode set should always preserve its contents, even if it contains
      // things that look like percent-encode sequences (maybe someone really meant to write "%20").
      XCTAssertEqualElements(encodedUTF8.percentDecoded, input.utf8)
    }

    // An important feature of the component encode-set is that it includes the % sign itself (U+0025).
    XCTAssertTrue(URLEncodeSet.Component.shouldEscape(character: .percentSign))
  }
}
