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

/// A key-value pair.
///
/// The `Equatable` conformance for this type checks exact code-unit/code-point equality
/// rather than Unicode canonical equivalence. In other words:
///
/// ```swift
/// let nfc = KeyValuePair(key: "caf\u{00E9}",  value: "")
/// let nfd = KeyValuePair(key: "cafe\u{0301}", value: "")
///
/// nfc == nfd // false
/// ```
///
struct KeyValuePair: Equatable {
  var key: String
  var value: String

  init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  init(_ kvp: WebURL.KeyValuePairs<some KeyValueStringSchema>.Element) {
    self.init(key: kvp.key, value: kvp.value)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value.utf8.elementsEqual(rhs.value.utf8)
  }
}

/// Asserts that the given `WebURL.KeyValuePairs` (or slice thereof)
/// contains the same pairs as the given list.
///
/// Keys and values from the `WebURL.KeyValuePairs` are decoded before checking
/// for equality. The lists must match at the code-unit/code-point level.
///
func XCTAssertEqualKeyValuePairs(
  _ left: some Collection<WebURL.KeyValuePairs<some KeyValueStringSchema>.Element>,
  _ right: some Collection<KeyValuePair>,
  file: StaticString = #fileID,
  line: UInt = #line
) {
  XCTAssertEqualElements(left.map { KeyValuePair($0) }, right, file: file, line: line)
}

/// Asserts that the given `WebURL.KeyValuePairs` (or slice thereof)
/// contains the same pairs as the given Array.
///
/// Keys and values from the `WebURL.KeyValuePairs` are decoded before checking
/// for equality. The lists must match at the code-unit/code-point level.
///
func XCTAssertEqualKeyValuePairs(
  _ left: some Collection<WebURL.KeyValuePairs<some KeyValueStringSchema>.Element>,
  _ right: [(key: String, value: String)],
  file: StaticString = #fileID,
  line: UInt = #line
) {
  XCTAssertEqualKeyValuePairs(left, right.map { KeyValuePair(key: $0.key, value: $0.value) }, file: file, line: line)
}

/// A key-value string schema with non-standard delimiters.
///
/// ```
/// key1:value1,key2:value2
/// ```
///
/// Other than delimiters, it should match `PercentEncodedKeyValueString`.
///
struct CommaSeparated: KeyValueStringSchema {

  var preferredPairDelimiter: UInt8 { UInt8(ascii: ",") }
  var preferredKeyValueDelimiter: UInt8 { UInt8(ascii: ":") }

  var decodePlusAsSpace: Bool { false }

  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    PercentEncodedKeyValueString().shouldPercentEncode(ascii: codePoint)
  }
}

/// A key-value string schema which supports additional options for form-encoding.
///
struct ExtendedForm: KeyValueStringSchema {

  var semicolonIsPairDelimiter = false
  var encodeSpaceAsPlus = false

  func isPairDelimiter(_ codePoint: UInt8) -> Bool {
    codePoint == UInt8(ascii: "&") || (semicolonIsPairDelimiter && codePoint == UInt8(ascii: ";"))
  }

  var preferredPairDelimiter: UInt8 { UInt8(ascii: "&") }
  var preferredKeyValueDelimiter: UInt8 { UInt8(ascii: "=") }

  var decodePlusAsSpace: Bool { true }

  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    FormCompatibleKeyValueString().shouldPercentEncode(ascii: codePoint)
  }
}

/// Asserts that information in the `WebURL.KeyValuePairs` cache
/// is consistent with a freshly-recalculated cache.
///
func XCTAssertKeyValuePairCacheIsAccurate(_ kvps: WebURL.KeyValuePairs<some KeyValueStringSchema>) {

  let expectedCache = type(of: kvps).Cache.calculate(
    storage: kvps.storage,
    component: kvps.component,
    schema: kvps.schema
  )
  XCTAssertEqual(kvps.cache.startIndex, expectedCache.startIndex)
  XCTAssertEqual(kvps.cache.componentContents, expectedCache.componentContents)
}
