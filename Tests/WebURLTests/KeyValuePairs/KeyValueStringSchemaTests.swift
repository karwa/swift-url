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

#if swift(<5.7)
  #error("WebURL.KeyValuePairs requires Swift 5.7 or newer")
#endif

final class KeyValueStringSchemaTests: XCTestCase {

  /// Verifies known schemas.
  ///
  func testKnownSchemas() {

    for component in KeyValuePairsSupportedComponent.allCases {
      // Built-in schemas support all components.
      XCTAssertNoThrow(try FormCompatibleKeyValueString().verify(for: component))
      XCTAssertNoThrow(try PercentEncodedKeyValueString().verify(for: component))

      // Custom schemas defined in 'KeyValuePairs/Helpers.swift' support all components.
      XCTAssertNoThrow(try CommaSeparated().verify(for: component))
      XCTAssertNoThrow(try ExtendedForm(semicolonIsPairDelimiter: true).verify(for: component))
      XCTAssertNoThrow(try ExtendedForm(encodeSpaceAsPlus: true).verify(for: component))
    }
  }

  /// Tests that `KeyValueStringSchema.verify(for:)` detects mistakes in custom schemas.
  ///
  func testSchemaVerification() {

    struct VariableSchema: KeyValueStringSchema {

      var preferredKeyValueDelimiter = UInt8(ascii: "=")
      var preferredPairDelimiter = UInt8(ascii: "&")
      var decodePlusAsSpace = false
      var encodeSpaceAsPlus = false

      var _isPairDelimiter: (Self, UInt8) -> Bool = { schema, codePoint in
        codePoint == schema.preferredPairDelimiter
      }
      var _isKeyValueDelimiter: (Self, UInt8) -> Bool = { schema, codePoint in
        codePoint == schema.preferredKeyValueDelimiter
      }
      var _shouldPercentEncode: (Self, UInt8) -> Bool = { _, _ in
        false
      }

      func isPairDelimiter(_ codePoint: UInt8) -> Bool {
        _isPairDelimiter(self, codePoint)
      }
      func isKeyValueDelimiter(_ codePoint: UInt8) -> Bool {
        _isKeyValueDelimiter(self, codePoint)
      }
      func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
        _shouldPercentEncode(self, codePoint)
      }
    }

    struct TestCase<T> {
      var keyPath: WritableKeyPath<VariableSchema, T>
      var error: KeyValueStringSchemaVerificationFailure
    }

    for component in KeyValuePairsSupportedComponent.allCases {

      XCTAssertNoThrow(try VariableSchema().verify(for: component))

      // Invalid preferred delimiters.
      // Preferred delimiters are special because we have to be able to write them unescaped to the URL string.

      let preferredDelimiterTests = [
        TestCase(keyPath: \.preferredKeyValueDelimiter, error: .preferredKeyValueDelimiterIsInvalid),
        TestCase(keyPath: \.preferredPairDelimiter, error: .preferredPairDelimiterIsInvalid),
      ]
      for testcase in preferredDelimiterTests {
        for v in UInt8.min...UInt8.max {
          let error: KeyValueStringSchemaVerificationFailure?
          do {
            var schema = VariableSchema()
            schema[keyPath: testcase.keyPath] = v
            try schema.verify(for: component)
            error = nil
          } catch let e {
            error = (e as! KeyValueStringSchemaVerificationFailure)
          }

          // The delimiter:
          //
          // - Must be an ASCII code-point,
          guard let ascii = ASCII(v) else {
            XCTAssertEqual(error, testcase.error)
            continue
          }
          switch ascii {
          // - Must not be the percent sign (`%`), plus sign (`+`), space, or a hex digit, and
          case ASCII.percentSign, ASCII.plus, ASCII.space:
            XCTAssertEqual(error, testcase.error)
          case _ where ascii.isHexDigit:
            XCTAssertEqual(error, testcase.error)
          // - Must not require escaping in the URL component(s) used with this schema.
          default:
            switch component.value {
            case .query:
              let needsEscaping =
                URLEncodeSet.Query().shouldPercentEncode(ascii: v)
                || URLEncodeSet.SpecialQuery().shouldPercentEncode(ascii: v)
              XCTAssertEqual(error, needsEscaping ? testcase.error : nil)
            case .fragment:
              let needsEscaping = URLEncodeSet.Fragment().shouldPercentEncode(ascii: v)
              XCTAssertEqual(error, needsEscaping ? testcase.error : nil)
            }
          }
        }
      }

      // Preferred delimiter not recognized by 'is(KeyValue/Pair)Delimter'.
      // These must be consistent, else the view will produce unexpected results
      // when writing entries and reading them back.

      let delimiterPredicateTests_0 = [
        TestCase(keyPath: \._isKeyValueDelimiter, error: .preferredKeyValueDelimiterNotRecognized),
        TestCase(keyPath: \._isPairDelimiter, error: .preferredPairDelimiterNotRecognized),
      ]
      for testcase in delimiterPredicateTests_0 {
        var schema = VariableSchema()
        schema[keyPath: testcase.keyPath] = { _, codePoint in false }
        XCTAssertThrowsSpecific(testcase.error, { try schema.verify(for: component) })
      }

      // Invalid characters recognized as delimiters.
      // We cannot allow '%' or ASCII hex digits to be interpreted as delimiters,
      // otherwise they would collide with percent-encoding.
      // '+' is also disallowed, even when 'decodePlusAsSpace=false', because it's just a bad idea.

      let delimiterPredicateTests_1 = [
        TestCase(keyPath: \._isKeyValueDelimiter, error: .invalidKeyValueDelimiterIsRecognized),
        TestCase(keyPath: \._isPairDelimiter, error: .invalidPairDelimiterIsRecognized),
      ]
      for testcase in delimiterPredicateTests_1 {
        for disallowedChar in "0123456789abcdefABCDEF%+" {
          var schema = VariableSchema()
          schema[keyPath: testcase.keyPath] = { schema, codePoint in
            codePoint == schema.preferredKeyValueDelimiter
              || codePoint == schema.preferredPairDelimiter
              || codePoint == disallowedChar.asciiValue!
          }
          XCTAssertThrowsSpecific(testcase.error, { try schema.verify(for: component) })
        }
      }

      // Inconsistent space encoding.
      // If spaces are encoded as plus, pluses must also be decoded as space.
      // All other combinations are allowed.

      for decode in [true, false] {
        for encode in [true, false] {
          let schema = VariableSchema(decodePlusAsSpace: decode, encodeSpaceAsPlus: encode)
          if encode == true, decode == false {
            XCTAssertThrowsSpecific(KeyValueStringSchemaVerificationFailure.inconsistentSpaceEncoding) {
              try schema.verify(for: component)
            }
          } else {
            XCTAssertNoThrow(try schema.verify(for: component))
          }
        }
      }
    }
  }
}
