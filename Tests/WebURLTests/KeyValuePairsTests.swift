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
import Checkit
@testable import WebURL

struct CommaSeparated: KeyValueStringSchema {

  var minimalPercentEncoding = false

  var preferredPairDelimiter: UInt8 { UInt8(ascii: ",") }
  var preferredKeyValueDelimiter: UInt8 { UInt8(ascii: ":") }

  var decodePlusAsSpace: Bool { false }
  var encodeSpaceAsPlus: Bool { false }

  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    if minimalPercentEncoding {
      return PercentEncodedKeyValueString().shouldPercentEncode(ascii: codePoint)
    } else {
      return FormCompatibleKeyValueString().shouldPercentEncode(ascii: codePoint)
    }
  }
}

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

/// A key-value pair.
///
/// Note that the `Equatable` conformance requires exact unicode scalar equality.
///
fileprivate struct KeyValuePair: Equatable {

  var key: String
  var value: String

  init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  init<Schema>(_ kvp: WebURL.KeyValuePairs<Schema>.Element) {
    self.init(key: kvp.key, value: kvp.value)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value.utf8.elementsEqual(rhs.value.utf8)
  }
}

extension KeyValuePair {

  init(_ keyValuePair: (String, String)) {
    self.init(key: keyValuePair.0, value: keyValuePair.1)
  }
}



fileprivate func XCTAssertEqualKeyValuePairs(_ left: [KeyValuePair], _ right: [(String, String)]) {
  XCTAssertEqual(left, right.map { KeyValuePair(key: $0.0, value: $0.1) })
}

fileprivate func XCTAssertEqualKeyValuePairs<Schema>(
  _ left: WebURL.KeyValuePairs<Schema>, _ right: [(key: String, value: String)]
) {
  XCTAssertEqualElements(
    left.map { KeyValuePair($0) },
    right.map { KeyValuePair(key: $0.key, value: $0.value) }
  )
}

fileprivate func XCTAssertEqualKeyValuePairs<Schema>(
  _ left: WebURL.KeyValuePairs<Schema>, _ right: [(String, String)]
) {
  XCTAssertEqualElements(
    left.map { KeyValuePair($0) },
    right.map { KeyValuePair(key: $0.0, value: $0.1) }
  )
}

fileprivate func XCTAssertEqualKeyValuePairs<Schema>(
  _ left: WebURL.KeyValuePairs<Schema>.SubSequence, _ right: [(key: String, value: String)]
) {
  XCTAssertEqualElements(
    left.map { KeyValuePair($0) },
    right.map { KeyValuePair(key: $0.key, value: $0.value) }
  )
}

fileprivate func XCTAssertEqualKeyValuePairs<Schema>(
  _ left: WebURL.KeyValuePairs<Schema>, _ right: [KeyValuePair]
) {
  XCTAssertEqualElements(left.lazy.map { KeyValuePair($0) }, right)
}

fileprivate func XCTAssertEqualKeyValuePairs<Schema>(
  _ left: WebURL.KeyValuePairs<Schema>.SubSequence, _ right: [KeyValuePair]
) {
  XCTAssertEqualElements(left.lazy.map { KeyValuePair($0) }, right)
}

fileprivate func XCTAssertKeyValuePairCacheIsAccurate<Schema>(_ kvps: WebURL.KeyValuePairs<Schema>) {

  let expectedCache = WebURL.KeyValuePairs<Schema>.Cache.calculate(
    storage: kvps.storage,
    component: kvps.component,
    schema: kvps.schema
  )
  XCTAssertEqual(kvps.cache.startIndex, expectedCache.startIndex)
  XCTAssertEqual(kvps.cache.componentContents, expectedCache.componentContents)
}

final class KeyValuePairsTests: XCTestCase {}



extension KeyValuePairsTests {

  static let SpecialCharacters = "\u{0000}\u{0001}\u{0009}\u{000A}\u{000D} !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
  static let SpecialCharacters_Escaped_Form = "%00%01%09%0A%0D%20%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D%7E"
  static let SpecialCharacters_Escaped_Form_Plus = "%00%01%09%0A%0D+%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D%7E"
  static let SpecialCharacters_Escaped_MinPctEnc_Query = #"%00%01%09%0A%0D%20!%22%23$%25%26%27()*%2B,-./:;%3C%3D%3E?@[\]^_`{|}~"#
  static let SpecialCharacters_Escaped_MinCommaSep_Frag = #"%00%01%09%0A%0D%20!%22#$%25&'()*%2B%2C-./%3A;%3C=%3E?@[\]^_%60{|}~"#

  // For PercentEncodedKeyValueString.shouldPercentEncode => true for isNonURLCodePoint
  //  static let SpecialCharacters_Escaped_MinPctEnc_Query = #"%00%01%09%0A%0D%20!%22%23$%25%26%27()*%2B,-./:;%3C%3D%3E?@%5B%5C%5D%5E_%60%7B%7C%7D~"#
  //  static let SpecialCharacters_Escaped_MinCommaSep_Frag = #"%00%01%09%0A%0D%20!%22%23$%25&'()*%2B%2C-./%3A;%3C=%3E?@%5B%5C%5D%5E_%60%7B%7C%7D~"#
}

extension KeyValuePairsTests {

  func testSchemaVerification() {

    // Note: We can't test schemas with infractions since they 'fatalError'.
    // Perhaps we should change that?
    // That means adding another enum as a result type, Error, CustomStringConvertible conformances.
    // Can we limit that to debug builds of clients?
    // Would really rather not pay the code-size for something like that.

    func _doSchemaVerification<Schema>(
      _ schema: Schema, for component: KeyValuePairsSupportedComponent
    ) where Schema: KeyValueStringSchema {
      schema.verify(for: component)
    }

    _doSchemaVerification(.formEncoded, for: .query)
    _doSchemaVerification(.formEncoded, for: .fragment)
    _doSchemaVerification(.percentEncoded, for: .query)
    _doSchemaVerification(.percentEncoded, for: .fragment)

    _doSchemaVerification(CommaSeparated(), for: .query)
    _doSchemaVerification(CommaSeparated(), for: .fragment)
  }
}


// -------------------------------
// MARK: - Reading
// -------------------------------


extension KeyValuePairsTests {

  func testCollectionConformance() {

    func _testCollectionConformance<Schema>(_ kvps: WebURL.KeyValuePairs<Schema>) {
      XCTAssertEqualKeyValuePairs(kvps, [
        (key: "a", value: "b"),
        (key: "mixed space & plus", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "👀"),
        (key: "jalapen\u{0303}os", value: "nfd"),
        (key: "specials", value: ##"!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"##),
        (key: "dup", value: "f"),
        (key: "jalape\u{00F1}os", value: "nfc"),
      ])
      XCTAssertEqual(kvps.count, 10)
      CollectionChecker.check(kvps)
    }

    // Tests are repeated with some empty key-value pairs injected in various places.
    // These should be skipped (there is no Index which covers that range of the string),
    // so they should be transparent as far as the Collection side of things is concerned.

    // Form encoding in the query.
    do {
      let injections = [
        (start: "", middle: "", end: ""),
        (start: "&&&", middle: "", end: ""),
        (start: "", middle: "&&&", end: ""),
        (start: "", middle: "", end: "&&&"),
        (start: "&&&&", middle: "&&&&", end: "&&&&")
      ]
      for (start, middle, end) in injections {
        let url = WebURL(#"http://example/?\#(start)a=b&mixed%20space+%26+plus=d&dup=e\#(middle)&=foo&noval&emoji=👀&jalapen\#u{0303}os=nfd&specials=!"%23$%%26'()*%2B,-./:;<%3D>?@[\]^_`{|}~&dup=f&jalape\#u{00F1}os=nfc\#(end)#a=z"#)!
        XCTAssertEqual(url.query, #"\#(start)a=b&mixed%20space+%26+plus=d&dup=e\#(middle)&=foo&noval&emoji=%F0%9F%91%80&jalapen%CC%83os=nfd&specials=!%22%23$%%26%27()*%2B,-./:;%3C%3D%3E?@[\]^_`{|}~&dup=f&jalape%C3%B1os=nfc\#(end)"#)
        _testCollectionConformance(url.queryParams)
      }
    }

    // Form encoding in the query (2).
    // Semicolons are also allowed as pair delimiters.
    do {
      let injections = [
        (start: "", middle: "", end: ""),
        (start: "&;&", middle: "", end: ""),
        (start: "", middle: "&&;", end: ""),
        (start: "", middle: "", end: ";&&"),
        (start: "&&;&", middle: "&;&&", end: "&&;;")
      ]
      for (start, middle, end) in injections {
        let url = WebURL(#"http://example/?\#(start)a=b&mixed%20space+%26+plus=d;dup=e\#(middle)&=foo&noval&emoji=👀;jalapen\#u{0303}os=nfd;specials=!"%23$%%26'()*%2B,-./:%3B<%3D>?@[\]^_`{|}~&dup=f&jalape\#u{00F1}os=nfc\#(end)#a=z"#)!
        XCTAssertEqual(url.query, #"\#(start)a=b&mixed%20space+%26+plus=d;dup=e\#(middle)&=foo&noval&emoji=%F0%9F%91%80;jalapen%CC%83os=nfd;specials=!%22%23$%%26%27()*%2B,-./:%3B%3C%3D%3E?@[\]^_`{|}~&dup=f&jalape%C3%B1os=nfc\#(end)"#)
        _testCollectionConformance(url.keyValuePairs(in: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)))
      }
    }

    // Custom schema in the fragment.
    // Note that the escaping is different (e.g. 'specials' can include unescaped & and =).
    do {
      let injections = [
        (start: "", middle: "", end: ""),
        (start: ",,,", middle: "", end: ""),
        (start: "", middle: ",,,", end: ""),
        (start: "", middle: "", end: ",,,"),
        (start: ",,,,", middle: ",,,,", end: ",,,,")
      ]
      for (start, middle, end) in injections {
        let url = WebURL(##"http://example/?a:z#\##(start)a:b,mixed%20space%20&%20plus:d,dup:e\##(middle),:foo,noval,emoji:👀,jalapen\##u{0303}os:nfd,specials:!"#$%&'()*+%2C-./%3A;<=>?@[\]^_`{|}~,dup:f,jalape\##u{00F1}os:nfc\##(end)"##)!
        XCTAssertEqual(url.fragment, ##"\##(start)a:b,mixed%20space%20&%20plus:d,dup:e\##(middle),:foo,noval,emoji:%F0%9F%91%80,jalapen%CC%83os:nfd,specials:!%22#$%&'()*+%2C-./%3A;%3C=%3E?@[\]^_%60{|}~,dup:f,jalape%C3%B1os:nfc\##(end)"##)
        _testCollectionConformance(url.keyValuePairs(in: .fragment, schema: CommaSeparated()))
      }
    }
  }

  func testEmptyCollection() {

    func _testEmptyCollection<Schema>(
      _ component: WritableKeyPath<WebURL, String?>,
      prefix: String, view getView: (WebURL) -> WebURL.KeyValuePairs<Schema>
    ) {
      var url = WebURL("http://example/")!

      func checkViewIsEmptyList() {
        let view = getView(url)
        XCTAssertEqual(view.isEmpty, true)
        for _ in view { XCTFail("Should be empty") }
        CollectionChecker.check(view)
      }

      // If the URL component is 'nil', we should get an empty list of pairs.
      XCTAssertEqual(url.serialized(), "http://example/")
      XCTAssertEqual(url[keyPath: component], nil)
      checkViewIsEmptyList()

      // If the URL component is the empty string, we should also get an empty list of pairs.
      url[keyPath: component] = ""
      XCTAssertEqual(url.serialized(), "http://example/\(prefix)")
      XCTAssertEqual(url[keyPath: component], "")
      checkViewIsEmptyList()

      let schema = getView(url).schema

      // If the URL component only contains a sequence of empty key-value pairs (e.g. "&&&"),
      // they should all be skipped, and we should also get an empty list of pairs.
      for n in 1...5 {
        let pairDelimiter = Character(UnicodeScalar(schema.preferredPairDelimiter))
        let emptyPairs = String(repeating: pairDelimiter, count: n)

        url[keyPath: component] = emptyPairs
        XCTAssertEqual(url.serialized(), "http://example/\(prefix)\(emptyPairs)")
        XCTAssertEqual(url[keyPath: component], emptyPairs)
        checkViewIsEmptyList()
      }

      // A pair consisting of an empty key and empty value (e.g. "=&=&=") is NOT the same as an empty pair.
      // Even if that is all the URL component contains, we should not get an empty list of pairs.
      for n in 1...5 {
        let pairDelimiter = UnicodeScalar(schema.preferredPairDelimiter).description
        let keyValueDelimiter = UnicodeScalar(schema.preferredKeyValueDelimiter).description
        let keyValueString = repeatElement(keyValueDelimiter, count: n).joined(separator: pairDelimiter)

        url[keyPath: component] = keyValueString
        XCTAssertEqual(url.serialized(), "http://example/\(prefix)\(keyValueString)")
        XCTAssertEqual(url[keyPath: component], keyValueString)

        let view = getView(url)
        XCTAssertEqual(view.isEmpty, false)
        XCTAssertEqual(view.count, n)
        for pair in view {
          XCTAssertEqual(pair.key, "")
          XCTAssertEqual(pair.value, "")
        }
        CollectionChecker.check(view)
      }
    }

    _testEmptyCollection(\.query, prefix: "?", view: { $0.queryParams })
    _testEmptyCollection(\.fragment, prefix: "#", view: { $0.keyValuePairs(in: .fragment, schema: CommaSeparated()) })
  }

  func testKeyLookupSubscript() {

    func _testKeyLookupSubscript<Schema>(_ kvps: WebURL.KeyValuePairs<Schema>) {

      // Single key lookup.
      // This should be equivalent to 'kvps.first { $0.key == TheKey }?.value'

      // Non-escaped, unique key.
      XCTAssertEqual(kvps["a"], "b")
      XCTAssertEqual(kvps["emoji"], "👀")

      // Key requires decoding.
      XCTAssertEqual(kvps["mixed space & plus"], "d")
      XCTAssertEqual(kvps["1 + 1 ="], "2")

      // Duplicate key. Lookup returns the first value.
      XCTAssertEqual(kvps["dup"], "e")

      // Empty key/value.
      XCTAssertEqual(kvps[""], "foo")
      XCTAssertEqual(kvps["noval"], "")

      // Unicode canonical equivalence.
      XCTAssertEqual(kvps["jalapen\u{0303}os"], "nfd")
      XCTAssertEqual(kvps["jalape\u{00F1}os"], "nfd")

      // Non-present key.
      XCTAssertEqual(kvps["doesNotExist"], nil)
      XCTAssertEqual(kvps["jalapenos"], nil)
      XCTAssertEqual(kvps["DUP"], nil)

      // Multiple key lookup.
      // Each key should be looked up as above.

      XCTAssertEqual(kvps["dup", "dup"], ("e", "e"))
      XCTAssertEqual(kvps["jalapen\u{0303}os", "emoji", "jalape\u{00F1}os"], ("nfd", "👀", "nfd"))
      XCTAssertEqual(kvps["1 + 1 =", "dup", "", "mixed space & plus"], ("2", "e", "foo", "d"))
      XCTAssertEqual(kvps["noval", "doesNotExist", "DUP"], ("", nil, nil))
    }

    // Form encoding in the query.
    do {
      let url = WebURL(#"http://example/?a=b&mixed%20space+%26+plus=d&dup=e&=foo&noval&emoji=👀&jalapen\#u{0303}os=nfd&dup=f&jalape\#u{00F1}os=nfc&1+%2B+1+%3D=2#a=z"#)!
      XCTAssertEqual(url.query, #"a=b&mixed%20space+%26+plus=d&dup=e&=foo&noval&emoji=%F0%9F%91%80&jalapen%CC%83os=nfd&dup=f&jalape%C3%B1os=nfc&1+%2B+1+%3D=2"#)
      _testKeyLookupSubscript(url.queryParams)
    }

    // Form encoding in the query (2).
    // Semi-colons allowed as pair delimiters.
    do {
      let url = WebURL(#"http://example/?a=b&mixed%20space+%26+plus=d;dup=e&=foo&noval&emoji=👀;jalapen\#u{0303}os=nfd;dup=f&jalape\#u{00F1}os=nfc&1+%2B+1+%3D=2#a=z"#)!
      XCTAssertEqual(url.query, #"a=b&mixed%20space+%26+plus=d;dup=e&=foo&noval&emoji=%F0%9F%91%80;jalapen%CC%83os=nfd;dup=f&jalape%C3%B1os=nfc&1+%2B+1+%3D=2"#)
      _testKeyLookupSubscript(url.keyValuePairs(in: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)))
    }

    // Custom schema in the fragment.
    // '&', '=', and '+' are used without escaping.
    do {
      let url = WebURL(#"http://example/?a:z#a:b,mixed%20space%20&%20plus:d,dup:e,:foo,noval,emoji:👀,jalapen\#u{0303}os:nfd,dup:f,jalape\#u{00F1}os:nfc,1%20+%201%20=:2"#)!
      XCTAssertEqual(url.fragment, #"a:b,mixed%20space%20&%20plus:d,dup:e,:foo,noval,emoji:%F0%9F%91%80,jalapen%CC%83os:nfd,dup:f,jalape%C3%B1os:nfc,1%20+%201%20=:2"#)
      _testKeyLookupSubscript(url.keyValuePairs(in: .fragment, schema: CommaSeparated()))
    }
  }

  func testAllValuesForKey() {

    func _testAllValuesForKey<Schema>(_ kvps: WebURL.KeyValuePairs<Schema>) {

      // Single value.
      XCTAssertEqual(kvps.allValues(forKey: "mixed space & plus"), ["d"])
      XCTAssertEqual(kvps.allValues(forKey: "1 + 1 ="), ["2"])

      // Multiple values.
      // Order must match that in the list.
      XCTAssertEqual(kvps.allValues(forKey: "dup"), ["e", "f"])

      // Unicode canonical equivalence.
      XCTAssertEqual(kvps.allValues(forKey: "jalapen\u{0303}os"), ["nfd", "nfc"])
      XCTAssertEqual(kvps.allValues(forKey: "jalape\u{00F1}os"), ["nfd", "nfc"])

      // Empty key/value.
      XCTAssertEqual(kvps.allValues(forKey: ""), ["foo"])
      XCTAssertEqual(kvps.allValues(forKey: "noval"), [""])

      // Non-present keys.
      XCTAssertEqual(kvps.allValues(forKey: "doesNotExist"), [])
      XCTAssertEqual(kvps.allValues(forKey: "DUP"), [])
    }

    // Form encoding in the query.
    do {
      let url = WebURL(#"http://example/?a=b&mixed%20space+%26+plus=d&dup=e&=foo&noval&emoji=👀&jalapen\#u{0303}os=nfd&dup=f&jalape\#u{00F1}os=nfc&1+%2B+1+%3D=2#a=z"#)!
      XCTAssertEqual(url.query, #"a=b&mixed%20space+%26+plus=d&dup=e&=foo&noval&emoji=%F0%9F%91%80&jalapen%CC%83os=nfd&dup=f&jalape%C3%B1os=nfc&1+%2B+1+%3D=2"#)
      _testAllValuesForKey(url.queryParams)
    }

    // Form encoding in the query (2).
    // Semi-colons allowed as pair delimiters.
    do {
      let url = WebURL(#"http://example/?a=b&mixed%20space+%26+plus=d;dup=e&=foo&noval&emoji=👀;jalapen\#u{0303}os=nfd;dup=f&jalape\#u{00F1}os=nfc&1+%2B+1+%3D=2#a=z"#)!
      XCTAssertEqual(url.query, #"a=b&mixed%20space+%26+plus=d;dup=e&=foo&noval&emoji=%F0%9F%91%80;jalapen%CC%83os=nfd;dup=f&jalape%C3%B1os=nfc&1+%2B+1+%3D=2"#)
      _testAllValuesForKey(url.keyValuePairs(in: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)))
    }

    // Custom schema in the fragment.
    // '&', '=', and '+' are used without escaping.
    do {
      let url = WebURL(#"http://example/?a:z#a:b,mixed%20space%20&%20plus:d,dup:e,:foo,noval,emoji:👀,jalapen\#u{0303}os:nfd,dup:f,jalape\#u{00F1}os:nfc,1%20+%201%20=:2"#)!
      XCTAssertEqual(url.fragment, #"a:b,mixed%20space%20&%20plus:d,dup:e,:foo,noval,emoji:%F0%9F%91%80,jalapen%CC%83os:nfd,dup:f,jalape%C3%B1os:nfc,1%20+%201%20=:2"#)
      _testAllValuesForKey(url.keyValuePairs(in: .fragment, schema: CommaSeparated()))
    }
  }
}

// -------------------------------
// MARK: - Writing: By Location
// -------------------------------


// replaceSubrange
extension KeyValuePairsTests {

  func testReplaceSubrange_partialReplacement() {

    // Test ranges:
    //
    // - At the start
    // - In the middle
    // - At the end
    //
    // and with the operation:
    //
    // - Inserting (removing no elements,   inserting some elements)
    // - Removing  (removing some elements, inserting no elements)
    // - Shrinking (removing some elements, inserting fewer elements)
    // - Growing   (removing some elements, inserting more elements)
    //
    // This test only covers partial replacements: the key-value string must already have some elements,
    // and some of those elements will still be present in the result.

    func _testReplaceSubrange<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { ($0.key, $0.value) }
      let initialCount = initialPairs.count
      precondition(initialCount >= 4, "We need at least 4 key-value pairs to run this test")

      func replace(offsets: Range<Int>, with newPairs: [(String, String)]) -> WebURL {

        var url = url
        let newPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let replacementStart = kvps.index(kvps.startIndex, offsetBy: offsets.lowerBound)
          let replacementEnd = kvps.index(kvps.startIndex, offsetBy: offsets.upperBound)
          let newPairIndexes = kvps.replaceSubrange(replacementStart..<replacementEnd, with: newPairs)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return newPairIndexes
        }
        XCTAssertURLIsIdempotent(url)

        do {
          let kvps = url.keyValuePairs(in: component, schema: schema)
          XCTAssertEqual(
            kvps.index(kvps.startIndex, offsetBy: offsets.lowerBound),
            newPairIndexes.lowerBound
          )
          XCTAssertEqual(
            kvps.index(kvps.startIndex, offsetBy: offsets.upperBound - offsets.count + newPairs.count),
            newPairIndexes.upperBound
          )
          XCTAssertEqualKeyValuePairs(kvps[newPairIndexes], newPairs)
        }
        do {
          var expected = initialPairs
          expected.replaceSubrange(offsets, with: newPairs)
          XCTAssertEqualKeyValuePairs(url.keyValuePairs(in: component, schema: schema), expected)
        }

        return url
      }

      var result: WebURL

      // Insertion at the start.
      result = replace(offsets: 0..<0, with: [("inserted", "one"), (Self.SpecialCharacters, "two")])
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Insertion in the middle.
      result = replace(offsets: 2..<2, with: [("inserted", "one"), ("another insert", Self.SpecialCharacters)])
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Insertion at the end.
      result = replace(offsets: initialCount..<initialCount, with: [("inserted", "one"), ("another insert", "two")])
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Removal from the start.
      result = replace(offsets: 0..<2, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Removal from the middle.
      result = replace(offsets: 1..<3, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Removal from the end.
      result = replace(offsets: initialCount - 2..<initialCount, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[5])

      // Shrink, anchored to the start.
      result = replace(offsets: 0..<2, with: [("shrink", "start")])
      XCTAssertEqual(result.serialized(), checkpoints[6])

      // Shrink, floating in the middle.
      result = replace(offsets: 1..<3, with: [("shrink", Self.SpecialCharacters)])
      XCTAssertEqual(result.serialized(), checkpoints[7])

      // Shrink, anchored to the end.
      result = replace(offsets: initialCount - 2..<initialCount, with: [("shrink", "end")])
      XCTAssertEqual(result.serialized(), checkpoints[8])

      // Grow, anchored to the start.
      result = replace(offsets: 0..<2, with: [("grow", "start"), ("grow s", "sp ace"), (Self.SpecialCharacters, "🥸")])
      XCTAssertEqual(result.serialized(), checkpoints[9])

      // Grow, floating in the middle.
      result = replace(offsets: 2..<3, with: [("grow", "mid"), ("🌱", "🌻"), ("grow", Self.SpecialCharacters)])
      XCTAssertEqual(result.serialized(), checkpoints[10])

      // Grow, anchored to the end.
      result = replace(offsets: initialCount - 1..<initialCount, with: [("grow", "end"), ("", "noname"), ("", "")])
      XCTAssertEqual(result.serialized(), checkpoints[11])
    }

    // Form encoded in the query.
    _testReplaceSubrange(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=one&\(Self.SpecialCharacters_Escaped_Form)=two&first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&inserted=one&another%20insert=\(Self.SpecialCharacters_Escaped_Form)&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3&inserted=one&another%20insert=two#frag",

        "http://example/?third=2&fourth=3#frag",
        "http://example/?first=0&fourth=3#frag",
        "http://example/?first=0&second=1#frag",

        "http://example/?shrink=start&third=2&fourth=3#frag",
        "http://example/?first=0&shrink=\(Self.SpecialCharacters_Escaped_Form)&fourth=3#frag",
        "http://example/?first=0&second=1&shrink=end#frag",

        "http://example/?grow=start&grow%20s=sp%20ace&\(Self.SpecialCharacters_Escaped_Form)=%F0%9F%A5%B8&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&grow=mid&%F0%9F%8C%B1=%F0%9F%8C%BB&grow=\(Self.SpecialCharacters_Escaped_Form)&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&grow=end&=noname&=#frag",
      ]
    )

    // Form encoded in the query (encodeSpaceAsPlus = true).
    _testReplaceSubrange(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?inserted=one&\(Self.SpecialCharacters_Escaped_Form_Plus)=two&first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&inserted=one&another+insert=\(Self.SpecialCharacters_Escaped_Form_Plus)&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3&inserted=one&another+insert=two#frag",

        "http://example/?third=2&fourth=3#frag",
        "http://example/?first=0&fourth=3#frag",
        "http://example/?first=0&second=1#frag",

        "http://example/?shrink=start&third=2&fourth=3#frag",
        "http://example/?first=0&shrink=\(Self.SpecialCharacters_Escaped_Form_Plus)&fourth=3#frag",
        "http://example/?first=0&second=1&shrink=end#frag",

        "http://example/?grow=start&grow+s=sp+ace&\(Self.SpecialCharacters_Escaped_Form_Plus)=%F0%9F%A5%B8&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&grow=mid&%F0%9F%8C%B1=%F0%9F%8C%BB&grow=\(Self.SpecialCharacters_Escaped_Form_Plus)&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&grow=end&=noname&=#frag",
      ]
    )

    // Custom schema in the fragment (minimal percent-encoding).
    _testReplaceSubrange(
      url: "http://example/?srch#first:0,second:1,third:2,fourth:3",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#inserted:one,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):two,first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,inserted:one,another%20insert:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3,inserted:one,another%20insert:two",

        "http://example/?srch#third:2,fourth:3",
        "http://example/?srch#first:0,fourth:3",
        "http://example/?srch#first:0,second:1",

        "http://example/?srch#shrink:start,third:2,fourth:3",
        "http://example/?srch#first:0,shrink:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),fourth:3",
        "http://example/?srch#first:0,second:1,shrink:end",

        "http://example/?srch#grow:start,grow%20s:sp%20ace,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):%F0%9F%A5%B8,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,grow:mid,%F0%9F%8C%B1:%F0%9F%8C%BB,grow:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),fourth:3",
        "http://example/?srch#first:0,second:1,third:2,grow:end,:noname,:",
      ]
    )

    // Form encoded in the query (special characters in existing content, lots of empty key-value pairs).
    _testReplaceSubrange(
      url: "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [

        // These results look pretty ugly, but we're testing some important things here.
        //
        // - Firstly, any content outside of the area we are modifying should not be changed.
        //
        //   "[+^x%`?]~" is full of special characters which are tolerated in the query,
        //   but would be percent-encoded by the form-encoding schema. They should be preserved as they are.
        //
        // - Secondly, we need to know how empty key-value pairs are handled.
        //
        //   Empty key-value pairs ("&&&") are skipped; they exist in the underlying component string,
        //   but they do NOT exist in the list of pairs, and have no corresponding KeyValuePairs.Index.
        //
        //   Each KeyValuePairs.Index points to where its key starts, so the range `x..<y` refers to
        //   "the start of x's key, up to the start of y's key". For replacements, this means:
        //
        //   1. Any empty pairs before the start of x's key will continue to exist, as will any empty pairs after y.
        //
        //   2. When inserting pairs, there will only be one delimiter between the new content and the start of y's key.
        //
        //   These can be seen clearly in the 2nd checkpoint string (Insertion in the middle).
        //   However, there are some special cases:
        //
        //   3. Empty pairs at the start of the string ("?&&&first=...") occupy positions _before the list's startIndex_,
        //      so there would be no 'replaceSubrange' operation that would remove them.
        //
        //      This can be very awkward, so instead, replacements involving 'startIndex' are snapped
        //      to the start of the URL component string, and will remove content before the first non-empty pair.
        //
        //   4. When appending, if the existing content ends with a trailing pair delimiter, we reuse it.
        //      This means "httpx://example/?foo&" + "bar" -> "httpx://example/?foo&bar", not "httpx://example/?foo&&bar"
        //                                                                         ^                               ^^

        //               [3]
        //               VVV
        "http://example/?inserted=one&\(Self.SpecialCharacters_Escaped_Form)=two&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        //                                                      [1]                                                                   [2]
        //                                                      VVV                                                                    V
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&inserted=one&another%20insert=\(Self.SpecialCharacters_Escaped_Form)&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        //                                                                                             [4]
        //                                                                                             VVV
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&inserted=one&another%20insert=two#frag",

        "http://example/?third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&#frag",

        "http://example/?shrink=start&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&shrink=\(Self.SpecialCharacters_Escaped_Form)&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&shrink=end#frag",

        "http://example/?grow=start&grow%20s=sp%20ace&\(Self.SpecialCharacters_Escaped_Form)=%F0%9F%A5%B8&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&grow=mid&%F0%9F%8C%B1=%F0%9F%8C%BB&grow=\(Self.SpecialCharacters_Escaped_Form)&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&grow=end&=noname&=#frag",
      ]
    )
  }

  func testReplaceSubrange_fullReplacement() {

    func _testReplaceSubrange<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      // Replace everything with empty collection.
      do {
        var url = url
        let range = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let range = kvps.replaceSubrange(kvps.startIndex..<kvps.endIndex, with: EmptyCollection<(String, String)>())
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return range
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        for _ in kvps { XCTFail("Should be empty") }

        XCTAssertEqual(kvps.endIndex, range.lowerBound)
        XCTAssertEqual(kvps.endIndex, range.upperBound)

        XCTAssertEqual(url.serialized(), checkpoints[0])
      }

      // Replace everything with a single element.
      do {
        let newContent = [("hello", "world")]

        var url = url
        let range = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let range = kvps.replaceSubrange(kvps.startIndex..<kvps.endIndex, with: newContent)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return range
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqualKeyValuePairs(kvps, newContent)

        XCTAssertEqual(kvps.startIndex, range.lowerBound)
        XCTAssertEqual(kvps.endIndex, range.upperBound)
        XCTAssertEqualKeyValuePairs(kvps[range], newContent)

        XCTAssertEqual(url.serialized(), checkpoints[1])
      }

      // Replace everything with a non-empty collection.
      do {
        let newContent = [
          ("hello", "world"),
          (Self.SpecialCharacters, Self.SpecialCharacters),
          ("the key", "sp ace"),
        ]

        var url = url
        let range = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let range = kvps.replaceSubrange(kvps.startIndex..<kvps.endIndex, with: newContent)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return range
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqualKeyValuePairs(kvps, newContent)

        XCTAssertEqual(kvps.startIndex, range.lowerBound)
        XCTAssertEqual(kvps.endIndex, range.upperBound)
        XCTAssertEqualKeyValuePairs(kvps[range], newContent)

        XCTAssertEqual(url.serialized(), checkpoints[2])
      }
    }

    // Form encoded in the query (starts with nil query).
    _testReplaceSubrange(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (starts with empty query).
    _testReplaceSubrange(
      url: "http://example/?#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (starts with non-empty query, but empty list).
    _testReplaceSubrange(
      url: "http://example/?&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (starts with non-empty query).
    _testReplaceSubrange(
      url: "http://example/?foo=bar&baz=qux#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (starts with non-empty query, component has leading empty key-value pairs).
    _testReplaceSubrange(
      url: "http://example/?;;;foo=bar&;&baz=qux&;&#frag",
      component: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true), checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Custom schema in the fragment (minimal percent-encoding).
    _testReplaceSubrange(
      url: "http://example/?srch#,,frag:ment,stuff",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch",
        "http://example/?srch#hello:world",
        "http://example/?srch#hello:world,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),the%20key:sp%20ace",
      ]
    )
  }
}

// insert(contentsOf:at:), insert(key:value:at:)

extension KeyValuePairsTests {

  func testInsertCollection() {

    func _testInsertCollection<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

      func insert(_ newPairs: [(String, String)], atOffset offset: Int) -> WebURL {

        var url = url
        let newPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let newPairIndexes = kvps.insert(contentsOf: newPairs, at: kvps.index(kvps.startIndex, offsetBy: offset))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return newPairIndexes
        }
        XCTAssertURLIsIdempotent(url)
        do {
          let kvps = url.keyValuePairs(in: component, schema: schema)
          XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), newPairIndexes.lowerBound)
          XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset + newPairs.count), newPairIndexes.upperBound)
          XCTAssertEqualKeyValuePairs(kvps[newPairIndexes], newPairs)
        }
        do {
          var expected = initialPairs
          expected.insert(contentsOf: newPairs.lazy.map { KeyValuePair($0) }, at: offset)
          XCTAssertEqualKeyValuePairs(url.keyValuePairs(in: component, schema: schema), expected)
        }
        return url
      }

      var result: WebURL

      let pairsToInsert = [
        ("inserted", "some value"),
        (Self.SpecialCharacters, Self.SpecialCharacters),
        ("", ""),
        ("cafe\u{0301}", "caf\u{00E9}")
      ]

      // Insert at the front
      result = insert(pairsToInsert, atOffset: 0)
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Insert in the middle
      result = insert(pairsToInsert, atOffset: min(initialPairs.count, 1))
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Insert at the end.
      result = insert(pairsToInsert, atOffset: initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Insert single element at the front.
      result = insert([("some", "element")], atOffset: 0)
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Insert single element in the middle.
      result = insert([("some", "element")], atOffset: min(initialPairs.count, 1))
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Insert single element at the end.
      result = insert([("some", "element")], atOffset: initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[5])

      // Insert empty collection at the front.
      result = insert([], atOffset: 0)
      XCTAssertEqual(result.serialized(), checkpoints[6])

      // Insert empty collection in the middle.
      result = insert([], atOffset: min(initialPairs.count, 1))
      XCTAssertEqual(result.serialized(), checkpoints[7])

      // Insert empty collection at the end.
      result = insert([], atOffset: initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[8])
    }

    // Form-encoded in the query (starts with nil query).
    _testInsertCollection(
      url: "http://example/",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",

        "http://example/?some=element",
        "http://example/?some=element",
        "http://example/?some=element",

        "http://example/",
        "http://example/",
        "http://example/",
      ]
    )

    // Form-encoded in the query (starts with empty query).
    _testInsertCollection(
      url: "http://example/?",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",

        "http://example/?some=element",
        "http://example/?some=element",
        "http://example/?some=element",

        "http://example/",
        "http://example/",
        "http://example/",
      ]
    )

    // Form-encoded in the query (starts with non-empty query, but empty list).
    _testInsertCollection(
      url: "http://example/?&&&",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",

        "http://example/?some=element",
        "http://example/?some=element",
        "http://example/?some=element",

        "http://example/",
        "http://example/",
        "http://example/",
      ]
    )

    // Form-encoded in the query (starts with non-empty query, encodeSpaceAsPlus = true).
    _testInsertCollection(
      url: "http://example/?foo=bar&baz=qux",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?inserted=some+value&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&=&cafe%CC%81=caf%C3%A9&foo=bar&baz=qux",
        "http://example/?foo=bar&inserted=some+value&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&=&cafe%CC%81=caf%C3%A9&baz=qux",
        "http://example/?foo=bar&baz=qux&inserted=some+value&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&=&cafe%CC%81=caf%C3%A9",

        "http://example/?some=element&foo=bar&baz=qux",
        "http://example/?foo=bar&some=element&baz=qux",
        "http://example/?foo=bar&baz=qux&some=element",

        "http://example/?foo=bar&baz=qux",
        "http://example/?foo=bar&baz=qux",
        "http://example/?foo=bar&baz=qux",
      ]
    )

    // Form-encoded in the query (starts with non-empty query, empty key-value pairs).
    _testInsertCollection(
      url: "http://example/?&&&foo=bar&&&baz=qux&&&",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9",

        "http://example/?some=element&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&some=element&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&some=element",

        "http://example/?foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&",
      ]
    )

    // Custom schema in the fragment (minimal percent-encoding).
    _testInsertCollection(
      url: "http://example/?srch#frag:ment,stuff",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#inserted:some%20value,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),:,cafe%CC%81:caf%C3%A9,frag:ment,stuff",
        "http://example/?srch#frag:ment,inserted:some%20value,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),:,cafe%CC%81:caf%C3%A9,stuff",
        "http://example/?srch#frag:ment,stuff,inserted:some%20value,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),:,cafe%CC%81:caf%C3%A9",

        "http://example/?srch#some:element,frag:ment,stuff",
        "http://example/?srch#frag:ment,some:element,stuff",
        "http://example/?srch#frag:ment,stuff,some:element",

        "http://example/?srch#frag:ment,stuff",
        "http://example/?srch#frag:ment,stuff",
        "http://example/?srch#frag:ment,stuff",
      ]
    )
  }

  func testInsertOne() {

    func _testInsertOne<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

      func insert(_ newPair: (String, String), atOffset offset: Int) -> WebURL {

        var url = url
        let newPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let newIdxs = kvps.insert(key: newPair.0, value: newPair.1, at: kvps.index(kvps.startIndex, offsetBy: offset))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return newIdxs
        }
        XCTAssertURLIsIdempotent(url)
        do {
          let kvps = url.keyValuePairs(in: component, schema: schema)
          XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), newPairIndexes.lowerBound)
          XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset + 1), newPairIndexes.upperBound)
          XCTAssertEqualKeyValuePairs(kvps[newPairIndexes], [newPair])
        }
        do {
          var expected = initialPairs
          expected.insert(KeyValuePair(key: newPair.0, value: newPair.1), at: offset)
          XCTAssertEqualKeyValuePairs(url.keyValuePairs(in: component, schema: schema), expected)
        }
        return url
      }

      var result: WebURL
      var checkpointIdx = 0

      let pairsToTest = [
        ("inserted", "some value"),
        ("cafe\u{0301}", "caf\u{00E9}"),
        ("", Self.SpecialCharacters),
        (Self.SpecialCharacters, ""),
        ("", ""),
      ]

      for pair in pairsToTest {
        // Insert at the front
        result = insert(pair, atOffset: 0)
        XCTAssertEqual(result.serialized(), checkpoints[checkpointIdx])

        // Insert in the middle
        result = insert(pair, atOffset: min(initialPairs.count, 1))
        XCTAssertEqual(result.serialized(), checkpoints[checkpointIdx + 1])

        // Insert at the end.
        result = insert(pair, atOffset: initialPairs.count)
        XCTAssertEqual(result.serialized(), checkpoints[checkpointIdx + 2])

        checkpointIdx += 3
      }
    }

    // Form-encoded in the query (starts with nil query).
    _testInsertOne(
      url: "http://example/",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value",
        "http://example/?inserted=some%20value",
        "http://example/?inserted=some%20value",

        "http://example/?cafe%CC%81=caf%C3%A9",
        "http://example/?cafe%CC%81=caf%C3%A9",
        "http://example/?cafe%CC%81=caf%C3%A9",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",

        "http://example/?=",
        "http://example/?=",
        "http://example/?=",
      ]
    )

    // Form-encoded in the query (starts with empty query).
    _testInsertOne(
      url: "http://example/?",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value",
        "http://example/?inserted=some%20value",
        "http://example/?inserted=some%20value",

        "http://example/?cafe%CC%81=caf%C3%A9",
        "http://example/?cafe%CC%81=caf%C3%A9",
        "http://example/?cafe%CC%81=caf%C3%A9",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",

        "http://example/?=",
        "http://example/?=",
        "http://example/?=",
      ]
    )

    // Form-encoded in the query (starts with non-empty query, but empty list).
    _testInsertOne(
      url: "http://example/?&&&",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value",
        "http://example/?inserted=some%20value",
        "http://example/?inserted=some%20value",

        "http://example/?cafe%CC%81=caf%C3%A9",
        "http://example/?cafe%CC%81=caf%C3%A9",
        "http://example/?cafe%CC%81=caf%C3%A9",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=",

        "http://example/?=",
        "http://example/?=",
        "http://example/?=",
      ]
    )

    // Form-encoded in the query (starts with non-empty query, encodeSpaceAsPlus = true).
    _testInsertOne(
      url: "http://example/?foo=bar&baz=qux",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?inserted=some+value&foo=bar&baz=qux",
        "http://example/?foo=bar&inserted=some+value&baz=qux",
        "http://example/?foo=bar&baz=qux&inserted=some+value",

        "http://example/?cafe%CC%81=caf%C3%A9&foo=bar&baz=qux",
        "http://example/?foo=bar&cafe%CC%81=caf%C3%A9&baz=qux",
        "http://example/?foo=bar&baz=qux&cafe%CC%81=caf%C3%A9",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form_Plus)&foo=bar&baz=qux",
        "http://example/?foo=bar&=\(Self.SpecialCharacters_Escaped_Form_Plus)&baz=qux",
        "http://example/?foo=bar&baz=qux&=\(Self.SpecialCharacters_Escaped_Form_Plus)",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form_Plus)=&foo=bar&baz=qux",
        "http://example/?foo=bar&\(Self.SpecialCharacters_Escaped_Form_Plus)=&baz=qux",
        "http://example/?foo=bar&baz=qux&\(Self.SpecialCharacters_Escaped_Form_Plus)=",

        "http://example/?=&foo=bar&baz=qux",
        "http://example/?foo=bar&=&baz=qux",
        "http://example/?foo=bar&baz=qux&=",
      ]
    )

    // Form-encoded in the query (starts with non-empty query, empty key-value pairs).
    _testInsertOne(
      url: "http://example/?&&&foo=bar&&&baz=qux&&&",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&inserted=some%20value&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&inserted=some%20value",

        "http://example/?cafe%CC%81=caf%C3%A9&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&cafe%CC%81=caf%C3%A9&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&cafe%CC%81=caf%C3%A9",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&=\(Self.SpecialCharacters_Escaped_Form)&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&=\(Self.SpecialCharacters_Escaped_Form)",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&\(Self.SpecialCharacters_Escaped_Form)=&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&\(Self.SpecialCharacters_Escaped_Form)=",

        "http://example/?=&foo=bar&&&baz=qux&&&",
        "http://example/?&&&foo=bar&&&=&baz=qux&&&",
        "http://example/?&&&foo=bar&&&baz=qux&&&=",
      ]
    )

    // Custom schema in the fragment (minimal percent-encoding).
    _testInsertOne(
      url: "http://example/?srch#frag:ment,stuff",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#inserted:some%20value,frag:ment,stuff",
        "http://example/?srch#frag:ment,inserted:some%20value,stuff",
        "http://example/?srch#frag:ment,stuff,inserted:some%20value",

        "http://example/?srch#cafe%CC%81:caf%C3%A9,frag:ment,stuff",
        "http://example/?srch#frag:ment,cafe%CC%81:caf%C3%A9,stuff",
        "http://example/?srch#frag:ment,stuff,cafe%CC%81:caf%C3%A9",

        "http://example/?srch#:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),frag:ment,stuff",
        "http://example/?srch#frag:ment,:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),stuff",
        "http://example/?srch#frag:ment,stuff,:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag)",

        "http://example/?srch#\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):,frag:ment,stuff",
        "http://example/?srch#frag:ment,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):,stuff",
        "http://example/?srch#frag:ment,stuff,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):",

        "http://example/?srch#:,frag:ment,stuff",
        "http://example/?srch#frag:ment,:,stuff",
        "http://example/?srch#frag:ment,stuff,:",
      ]
    )
  }
}

// removeSubrange(_:), remove(at:)

extension KeyValuePairsTests {

  func testRemoveSubrange() {

    func _testRemoveSubrange<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

      func remove(offsets: Range<Int>) -> WebURL {
        var url = url
        let idx = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let lowerBound = kvps.index(kvps.startIndex, offsetBy: offsets.lowerBound)
          let upperBound = kvps.index(kvps.startIndex, offsetBy: offsets.upperBound)
          let idx = kvps.removeSubrange(lowerBound..<upperBound)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return idx
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offsets.upperBound - offsets.count), idx)

        var expected = initialPairs
        expected.removeSubrange(offsets)
        XCTAssertEqualKeyValuePairs(kvps, expected)

        return url
      }

      var result: WebURL

      // Remove from the front.
      result = remove(offsets: 0..<2)
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Remove from the middle.
      result = remove(offsets: 2..<3)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Remove from the end.
      result = remove(offsets: max(initialPairs.count - 2, 0)..<initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Remove all pairs.
      result = remove(offsets: 0..<initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Remove empty range at front.
      result = remove(offsets: 0..<0)
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Remove empty range at end.
      result = remove(offsets: initialPairs.count..<initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[5])
    }

    // Form-encoding in the query (nil query).
    do {
      var url = WebURL("http://example.com/#frag")!
      let idx = url.queryParams.removeSubrange(..<url.queryParams.endIndex)
      XCTAssertEqual(url.queryParams.startIndex, idx)
      XCTAssertEqual(url.queryParams.endIndex, idx)
      XCTAssertEqual(url.serialized(), "http://example.com/#frag")
    }

    // Form-encoding in the query (empty query).
    do {
      var url = WebURL("http://example.com/?#frag")!
      let idx = url.queryParams.removeSubrange(..<url.queryParams.endIndex)
      XCTAssertEqual(url.queryParams.startIndex, idx)
      XCTAssertEqual(url.queryParams.endIndex, idx)
      XCTAssertEqual(url.serialized(), "http://example.com/#frag")
    }

    // Form-encoding in the query (non-empty query, but empty list).
    do {
      var url = WebURL("http://example.com/?&&&#frag")!
      let idx = url.queryParams.removeSubrange(..<url.queryParams.endIndex)
      XCTAssertEqual(url.queryParams.startIndex, idx)
      XCTAssertEqual(url.queryParams.endIndex, idx)
      XCTAssertEqual(url.serialized(), "http://example.com/#frag")
    }

    // Form-encoding in the query (non-empty query).
    _testRemoveSubrange(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?third=2&fourth=3#frag",
        "http://example/?first=0&second=1&fourth=3#frag",
        "http://example/?first=0&second=1#frag",
        "http://example/#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
      ]
    )

    // Form-encoding in the query (extra empty pairs).
    _testRemoveSubrange(
      url: "http://example/?&&&first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&#frag",
        "http://example/#frag",
        // Removing an empty range from the front still trims leading delimiters.
        "http://example/?first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
      ]
    )

    // Custom schema in the fragment.
    _testRemoveSubrange(
      url: "http://example/?srch#first:0,second:1,third:2,fourth:3",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#third:2,fourth:3",
        "http://example/?srch#first:0,second:1,fourth:3",
        "http://example/?srch#first:0,second:1",
        "http://example/?srch",
        "http://example/?srch#first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3",
      ]
    )
  }

  func testRemoveOne() {

    func _testRemoveOne<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

      func remove(offset: Int) -> WebURL {
        var url = url
        let idx = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let idx = kvps.remove(at: kvps.index(kvps.startIndex, offsetBy: offset))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return idx
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), idx)

        var expected = initialPairs
        expected.remove(at: offset)
        XCTAssertEqualKeyValuePairs(kvps, expected)

        return url
      }

      var result: WebURL

      // Remove from the front.
      result = remove(offset: 0)
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Remove from the middle.
      result = remove(offset: 1)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Remove from the end.
      result = remove(offset: initialPairs.count - 1)
      XCTAssertEqual(result.serialized(), checkpoints[2])
    }

    // Form-encoding in the query (non-empty query).
    _testRemoveOne(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?second=1&third=2&fourth=3#frag",
        "http://example/?first=0&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2#frag",
      ]
    )

    // Form-encoding in the query (extra empty pairs).
    _testRemoveOne(
      url: "http://example/?&&&first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?second=1&&&third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&&third=2&&#frag",
      ]
    )

    // Custom schema in the fragment.
    _testRemoveOne(
      url: "http://example/?srch#first:0,second:1,third:2,fourth:3",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#second:1,third:2,fourth:3",
        "http://example/?srch#first:0,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2",
      ]
    )
  }
}

// removeAll(where:)

extension KeyValuePairsTests {

  func testRemoveAllWhere() {

    func _testRemoveWhereElement<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let oldKVPs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let count = oldKVPs.count

      func remove(
        in offset: Range<Int>,
        where predicate: (WebURL.KeyValuePairs<Schema>.Element) -> Bool
      ) -> WebURL {
        var copy = url
        copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let lower = kvps.index(kvps.startIndex, offsetBy: offset.lowerBound)
          let upper = kvps.index(kvps.startIndex, offsetBy: offset.upperBound)
          kvps.removeAll(in: lower..<upper, where: predicate)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
        }
        XCTAssertURLIsIdempotent(copy)
        return copy
      }

      var result: WebURL

      do {
        // Remove nothing (predicate always 'false')

        // From startIndex.

        result = remove(in: 0..<count, where: { _ in false })
        XCTAssertEqual(result.serialized(), checkpoints[0])

        // From middle.

        result = remove(in: 1..<count, where: { _ in false })
        XCTAssertEqual(result.serialized(), checkpoints[1])

        // From endIndex.

        result = remove(in: count..<count, where: { _ in false })
        XCTAssertEqual(result.serialized(), checkpoints[2])
      }

      do {
        // Remove nothing (empty range)

        // At startIndex.

        result = remove(in: 0..<0, where: { _ in XCTFail(); return true })
        XCTAssertEqual(result.serialized(), checkpoints[3])

        // At middle.

        result = remove(in: 1..<1, where: { _ in XCTFail(); return true })
        XCTAssertEqual(result.serialized(), checkpoints[4])

        // At endIndex.

        result = remove(in: count..<count, where: { _ in XCTFail(); return true })
        XCTAssertEqual(result.serialized(), checkpoints[5])
      }

      do {
        // Remove everything (predicate always 'true')

        // From startIndex.

        result = remove(in: 0..<count, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[6])

        result = remove(in: 0..<2, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[7])

        result = remove(in: 0..<3, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[8])

        // From middle.

        result = remove(in: 1..<count, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[9])

        result = remove(in: 1..<3, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[10])
      }

      do {
        // Remove first (predicate returns 'true', then 'false' forever)

        // From start.

        var didRemove_6 = false
        result = remove(in: 0..<count, where: { _ in
          defer { didRemove_6 = true }
          return !didRemove_6
        })
        XCTAssertEqual(result.serialized(), checkpoints[11])

        // From middle.

        var didRemove_7 = false
        result = remove(in: 1..<count, where: { _ in
          defer { didRemove_7 = true }
          return !didRemove_7
        })
        XCTAssertEqual(result.serialized(), checkpoints[12])
      }

      do {
        // Remove first (range has 1 element, predicate always returns 'true')

        // From start.

        result = remove(in: 0..<1, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[13])

        // From middle.

        result = remove(in: 1..<2, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[14])

        result = remove(in: 2..<3, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[15])
      }

      // Remove some, based on key.

      result = remove(in: 0..<count, where: { kvp in kvp.key.starts(with: "b") })
      XCTAssertEqual(result.serialized(), checkpoints[16])

      // Remove some, based on key (includes space).

      result = remove(in: 0..<count, where: { kvp in kvp.key == "sp ace" })
      XCTAssertEqual(result.serialized(), checkpoints[17])

      // Remove some, based on value.

      result = remove(in: 0..<count, where: { kvp in kvp.value.starts(with: "q") })
      XCTAssertEqual(result.serialized(), checkpoints[18])

      // Check that the predicate visits the same KVPs in the same order.
      func _checkSeenKVPs(in offsets: Range<Int>) {
        var seen: [KeyValuePair] = []
        var copy = url
        copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let lower = kvps.index(kvps.startIndex, offsetBy: offsets.lowerBound)
          let upper = kvps.index(kvps.startIndex, offsetBy: offsets.upperBound)
          kvps.removeAll(in: lower..<upper, where: {
            seen.append(KeyValuePair($0))
            return false
          })
        }
        let expected = Array(oldKVPs.dropFirst(offsets.lowerBound).prefix(offsets.count))
        XCTAssertEqual(expected, seen)
      }

      _checkSeenKVPs(in: 0..<count)
      _checkSeenKVPs(in: 1..<count)
      _checkSeenKVPs(in: 0..<count - 1)
      _checkSeenKVPs(in: 1..<count - 1)
      _checkSeenKVPs(in: 0..<0)
      _checkSeenKVPs(in: 1..<1)
      _checkSeenKVPs(in: count..<count)
    }

    // Form-encoded in the query.
    _testRemoveWhereElement(
      url: "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Remove nothing (predicate = false)
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",

        // Remove nothing (empty range)
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",

        // Remove everything (predicate = true)
        "http://example/p#frag",
        "http://example/p?qax=qaz&sp+ace#frag",
        "http://example/p?sp+ace#frag",
        "http://example/p?foo=bar#frag",
        "http://example/p?foo=bar&sp+ace#frag",

        // Remove first (predicate)
        "http://example/p?baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&qax=qaz&sp+ace#frag",

        // Remove first (single-element range)
        "http://example/p?baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&sp+ace#frag",

        // Remove some
        "http://example/p?foo=bar&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz#frag",
        "http://example/p?foo=bar&sp+ace#frag",
      ]
    )

    // Percent-encoded keys and values.
    _testRemoveWhereElement(
      url: "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        // Remove nothing (predicate = false)
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",

        // Remove nothing (empty range)
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",

        // Remove everything (predicate = true)
        "http://example/p#frag",
        "http://example/p?%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%73%70%20%61%63%65#frag",

        // Remove first (predicate)
        "http://example/p?%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",

        // Remove first (single-element range)
        "http://example/p?%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%73%70%20%61%63%65#frag",

        // Remove some
        "http://example/p?%66%6f%6F=%62%61%72&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%73%70%20%61%63%65#frag",
      ]
    )

    // Empty key-value pairs.
    _testRemoveWhereElement(
      url: "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Remove nothing (predicate = false)
        // - Empty pairs from the start location ('from' parameter) onward are removed.
        // - Empty pairs before the start location are left unchanged.
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp%20ace#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&qax=qaz&sp%20ace#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",

        // Remove nothing (empty range)
        // - startIndex..<startIndex trims empty pairs in order to be consistent with removeSubrange.
        "http://example/p?foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",

        // Remove everything (predicate = true)
        "http://example/p#frag",
        "http://example/p?qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&#frag",
        "http://example/p?&&&foo=bar&&&sp%20ace&&&#frag",

        // Remove first (predicate)
        "http://example/p?baz=qux&qax=qaz&sp%20ace#frag",
        "http://example/p?&&&foo=bar&&&qax=qaz&sp%20ace#frag",

        // Remove first (single-element range)
        "http://example/p?baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&sp%20ace&&&#frag",

        // Remove some
        "http://example/p?foo=bar&qax=qaz&sp%20ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz#frag",
        "http://example/p?foo=bar&sp%20ace#frag",
      ]
    )

    // Custom schema in the fragment.
    _testRemoveWhereElement(
      url: "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        // Remove nothing (predicate = false)
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",

        // Remove nothing (empty range)
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",

        // Remove everything (predicate = true)
        "http://example/p?q",
        "http://example/p?q#qax:qaz,sp%20ace",
        "http://example/p?q#sp%20ace",
        "http://example/p?q#foo:bar",
        "http://example/p?q#foo:bar,sp%20ace",

        // Remove first (predicate)
        "http://example/p?q#baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,qax:qaz,sp%20ace",

        // Remove first (single-element range)
        "http://example/p?q#baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,sp%20ace",

        // Remove some
        "http://example/p?q#foo:bar,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz",
        "http://example/p?q#foo:bar,sp%20ace",
      ]
    )
  }

  func testRemoveWhereRemoveSubrangeCompatibility() {

    // Checks that 'removeSubrange(lower..<upper)' and 'removeAll(in: lower..<upper) { _ in true }'
    // produce the same result.

    enum ExpectedResult: ExpressibleByStringLiteral {
      case match(String)
      case mismatch(removeWhereResult: String, removeSubrangeResult: String)

      init(stringLiteral value: StringLiteralType) {
        self = .match(value)
      }

      func check(removeWhere: WebURL, removeSubrange: WebURL, _ index: Int) {
        switch self {
        case .match(let expected):
          XCTAssertEqual(removeWhere, removeSubrange, String(index))
          XCTAssertEqual(removeWhere.serialized(), expected, String(index))
          XCTAssertEqual(removeSubrange.serialized(), expected, String(index))
        case .mismatch(let removeWhereResult, let removeSubrangeResult):
          XCTAssertNotEqual(removeWhere, removeSubrange, String(index))
          XCTAssertEqual(removeWhere.serialized(), removeWhereResult, String(index))
          XCTAssertEqual(removeSubrange.serialized(), removeSubrangeResult, String(index))
        }
      }
    }

    func _testRemoveCompatibility<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [ExpectedResult]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let oldKVPs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let count = oldKVPs.count

      func removeWhere(
        _ offset: Range<Int>
      ) -> WebURL {
        var copy = url
        copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let lower = kvps.index(kvps.startIndex, offsetBy: offset.lowerBound)
          let upper = kvps.index(kvps.startIndex, offsetBy: offset.upperBound)
          kvps.removeAll(in: lower..<upper, where: { _ in true })
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
        }
        XCTAssertURLIsIdempotent(copy)
        return copy
      }

      func removeSubrange(
        _ offset: Range<Int>
      ) -> WebURL {
        var copy = url
        copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let lower = kvps.index(kvps.startIndex, offsetBy: offset.lowerBound)
          let upper = kvps.index(kvps.startIndex, offsetBy: offset.upperBound)
          kvps.removeSubrange(lower..<upper)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
        }
        XCTAssertURLIsIdempotent(copy)
        return copy
      }

      var resultRW: WebURL
      var resultRS: WebURL

      var checkpointIdx = 0

      for i in 0...count {
        resultRW = removeWhere(0..<i)
        resultRS = removeSubrange(0..<i)
        checkpoints[checkpointIdx].check(removeWhere: resultRW, removeSubrange: resultRS, checkpointIdx)
        checkpointIdx += 1
      }

      for i in 1...count {
        resultRW = removeWhere(1..<i)
        resultRS = removeSubrange(1..<i)
        checkpoints[checkpointIdx].check(removeWhere: resultRW, removeSubrange: resultRS, checkpointIdx)
        checkpointIdx += 1
      }

      for i in 2...count {
        resultRW = removeWhere(2..<i)
        resultRS = removeSubrange(2..<i)
        checkpoints[checkpointIdx].check(removeWhere: resultRW, removeSubrange: resultRS, checkpointIdx)
        checkpointIdx += 1
      }

      // Remove last.
      resultRW = removeWhere(count - 1..<count)
      resultRS = removeSubrange(count - 1..<count)
      checkpoints[checkpointIdx].check(removeWhere: resultRW, removeSubrange: resultRS, checkpointIdx)
      checkpointIdx += 1

      // Remove empty range at endIndex.
      resultRW = removeWhere(count..<count)
      resultRS = removeSubrange(count..<count)
      checkpoints[checkpointIdx].check(removeWhere: resultRW, removeSubrange: resultRS, checkpointIdx)
    }

    // Form-encoded in the query.
    _testRemoveCompatibility(
      url: "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?qax=qaz&sp+ace#frag",
        "http://example/p?sp+ace#frag",
        "http://example/p#frag",

        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&sp+ace#frag",
        "http://example/p?foo=bar#frag",

        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux#frag",

        "http://example/p?foo=bar&baz=qux&qax=qaz#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
      ]
    )

    // Empty key-value pairs.
    _testRemoveCompatibility(
      url: "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/p?foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?sp%20ace&&&#frag",
        "http://example/p#frag",

        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&#frag",

        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&#frag",

        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
      ]
    )
  }
}

// append(contentsOf:), append(key:value:)

extension KeyValuePairsTests {

  func testAppendCollection() {

    func _testAppendCollection<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      var url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialCount = url.keyValuePairs(in: component, schema: schema).count

      do {
        let pairsToInsert = [
          // Duplicate keys.
          ("foo", "bar"),
          ("foo", "baz"),
          // Spaces.
          ("the key", "sp ace"),
          // Empty key/value.
          ("", "emptykey"),
          ("emptyval", ""),
          ("", ""),
        ]
        let insertedPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let insertedPairIndexes = kvps.append(contentsOf: pairsToInsert)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return insertedPairIndexes
        }
        XCTAssertURLIsIdempotent(url)
        XCTAssertEqual(url.serialized(), checkpoints[0])

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount), insertedPairIndexes.lowerBound)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount + 6), insertedPairIndexes.upperBound)
        XCTAssertEqual(kvps.endIndex, insertedPairIndexes.upperBound)
        XCTAssertEqual(kvps.count, initialCount + 6)

        XCTAssertEqualKeyValuePairs(kvps[insertedPairIndexes], pairsToInsert)
      }

      do {
        let pairsToInsert = [
          // Duplicate pairs.
          (key: "foo", value: "bar"),
          (key: "", value: ""),
          // Unicode, special characters.
          (key: "cafe\u{0301}", value: "caf\u{00E9}"),
          (key: Self.SpecialCharacters, value: Self.SpecialCharacters),
        ]
        let insertedPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          kvps.append(contentsOf: pairsToInsert)
        }
        XCTAssertURLIsIdempotent(url)
        XCTAssertEqual(url.serialized(), checkpoints[1])

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount + 6), insertedPairIndexes.lowerBound)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount + 10), insertedPairIndexes.upperBound)
        XCTAssertEqual(kvps.endIndex, insertedPairIndexes.upperBound)
        XCTAssertEqual(kvps.count, initialCount + 10)

        XCTAssertEqualKeyValuePairs(kvps[insertedPairIndexes], pairsToInsert)
      }

      do {
        let pairsToInsert = [
          "zip": "zop",
          "abc": "def",
          "CAT": "x",
        ]
        let insertedPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          kvps.append(contentsOf: pairsToInsert)
        }
        XCTAssertURLIsIdempotent(url)
        XCTAssertEqual(url.serialized(), checkpoints[2])

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount + 10), insertedPairIndexes.lowerBound)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount + 13), insertedPairIndexes.upperBound)
        XCTAssertEqual(kvps.endIndex, insertedPairIndexes.upperBound)
        XCTAssertEqual(kvps.count, initialCount + 13)

        XCTAssertEqualKeyValuePairs(kvps[insertedPairIndexes], pairsToInsert.sorted(by: { $0.key < $1.key }))
      }

      XCTAssertEqualKeyValuePairs(url.keyValuePairs(in: component, schema: schema).dropFirst(initialCount), [
        (key: "foo", value: "bar"),
        (key: "foo", value: "baz"),
        (key: "the key", value: "sp ace"),
        (key: "", value: "emptykey"),
        (key: "emptyval", value: ""),
        (key: "", value: ""),
        (key: "foo", value: "bar"),
        (key: "", value: ""),
        (key: "cafe\u{0301}", value: "caf\u{00E9}"),
        (key: Self.SpecialCharacters, value: Self.SpecialCharacters),
        (key: "CAT", value: "x"),
        (key: "abc", value: "def"),
        (key: "zip", value: "zop"),
      ])
    }

    // Form encoded in the query (starts with nil query).
    _testAppendCollection(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&abc=def&zip=zop#frag"
      ]
    )

    // Form encoded in the query (starts with empty query, encodeSpaceAsPlus = true).
    _testAppendCollection(
      url: "http://example/?#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&=emptykey&emptyval=&=#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&CAT=x&abc=def&zip=zop#frag"
      ]
    )

    // Form encoded in the query (starts with non-empty query; existing content must be preserved unchanged).
    _testAppendCollection(
      url: "http://example/?&test[+x%?]~=val^_`&&&x::y#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&abc=def&zip=zop#frag"
      ]
    )

    // Percent encoded in the query (starts with nil query, minimal percent-encoding).
    _testAppendCollection(
      url: "http://example/#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)=\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&foo=bar&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)=\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)&CAT=x&abc=def&zip=zop#frag"
      ]
    )

    // Custom schema in the fragment (starts with nil fragment, minimal percent-encoding).
    _testAppendCollection(
      url: "http://example/?srch",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,:emptykey,emptyval:,:",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,:emptykey,emptyval:,:,foo:bar,:,cafe%CC%81:caf%C3%A9,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag)",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,:emptykey,emptyval:,:,foo:bar,:,cafe%CC%81:caf%C3%A9,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),CAT:x,abc:def,zip:zop"
      ]
    )
  }

  func testAppendCollection_emptyCollection() {

    // Appending an empty collection of pairs does not change the contents of the key-value pair list.
    //
    // However, that does NOT mean it is a no-op - it CAN alter the underlying URL component string,
    // even if the list of pairs that are parsed from that string remains unchanged.
    //
    // In particular, when the list is empty, startIndex == endIndex, and appending effectively becomes
    // 'replaceSubrange(startIndex..<endIndex, with: [])' - i.e. remove-all.
    //
    // There are lots of underlying component strings which can give rise to an empty list,
    // and we want to make sure that a remove-all operation on any of them sets the component to 'nil'.
    // Therefore, the same must happen when appending an empty collection:
    //
    // - "httpx://example/"     -> "httpx://example/"
    // - "httpx://example/?"    -> "httpx://example/"
    // - "httpx://example/?&&&" -> "httpx://example/"

    func _testAppendEmptyCollection<Schema: KeyValueStringSchema>(
      url urlString: String, expected: String, component: KeyValuePairsSupportedComponent, schema: Schema
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let elementsBefore = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

      do {
        var url = url
        let indexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let indexes = kvps.append(contentsOf: [] as Array<(String, String)>)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return indexes
        }
        XCTAssertURLIsIdempotent(url)
        XCTAssertEqual(url.serialized(), expected)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqualKeyValuePairs(kvps, elementsBefore)
        XCTAssertEqual(kvps.endIndex, indexes.lowerBound)
        XCTAssertEqual(kvps.endIndex, indexes.upperBound)
      }
      do {
        var url = url
        let indexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let indexes = kvps.append(contentsOf: [] as Array<(key: String, value: String)>)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return indexes
        }

        XCTAssertURLIsIdempotent(url)
        XCTAssertEqual(url.serialized(), expected)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqualKeyValuePairs(kvps, elementsBefore)
        XCTAssertEqual(kvps.endIndex, indexes.lowerBound)
        XCTAssertEqual(kvps.endIndex, indexes.upperBound)
      }
      do {
        var url = url
        let indexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let indexes = kvps.append(contentsOf: [:] as Dictionary<String, String>)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return indexes
        }

        XCTAssertURLIsIdempotent(url)
        XCTAssertEqual(url.serialized(), expected)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqualKeyValuePairs(kvps, elementsBefore)
        XCTAssertEqual(kvps.endIndex, indexes.lowerBound)
        XCTAssertEqual(kvps.endIndex, indexes.upperBound)
      }
    }

    // Nil query.
    _testAppendEmptyCollection(
      url: "http://example/#frag", expected: "http://example/#frag",
      component: .query, schema: .formEncoded
    )

    // Empty query.
    _testAppendEmptyCollection(
      url: "http://example/?#frag", expected: "http://example/#frag",
      component: .query, schema: .formEncoded
    )

    // Non-empty query (but empty list).
    _testAppendEmptyCollection(
      url: "http://example/?&#frag", expected: "http://example/#frag",
      component: .query, schema: .formEncoded
    )
    _testAppendEmptyCollection(
      url: "http://example/?&&&&#frag", expected: "http://example/#frag",
      component: .query, schema: .formEncoded
    )
    _testAppendEmptyCollection(
      url: "http://example/?&;&;#frag", expected: "http://example/#frag",
      component: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)
    )

    // Non-empty query (non-empty list).
    _testAppendEmptyCollection(
      url: "http://example/?foo=bar&baz=qux#frag", expected: "http://example/?foo=bar&baz=qux#frag",
      component: .query, schema: .formEncoded
    )

    // Nil fragment.
    _testAppendEmptyCollection(
      url: "http://example/?srch", expected: "http://example/?srch",
      component: .fragment, schema: CommaSeparated()
    )

    // Empty fragment.
    _testAppendEmptyCollection(
      url: "http://example/?srch#", expected: "http://example/?srch",
      component: .fragment, schema: CommaSeparated()
    )

    // Non-empty fragment (but empty list).
    _testAppendEmptyCollection(
      url: "http://example/?srch#,,,", expected: "http://example/?srch",
      component: .fragment, schema: CommaSeparated()
    )

    // Non-empty fragment (non-empty list).
    _testAppendEmptyCollection(
      url: "http://example/?srch#foo:bar,baz:qux", expected: "http://example/?srch#foo:bar,baz:qux",
      component: .fragment, schema: CommaSeparated()
    )
  }

  func testAppendCollection_trailingEmptyPairs() {

    let pairsToInsert = [(key: "foo", value: "bar"), (key: "baz", value: "qux")]

    // If the string already ends with a pair delimiter, we won't add another one when appending.

    do {
      var url = WebURL("http://example/?test=ok&")!
      let indexesOfInserted = url.queryParams.append(contentsOf: pairsToInsert)
      XCTAssertEqual(url.serialized(), "http://example/?test=ok&foo=bar&baz=qux")

      let kvps = url.queryParams
      XCTAssertEqualKeyValuePairs(kvps[indexesOfInserted], pairsToInsert)
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 1), indexesOfInserted.lowerBound)
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 3), indexesOfInserted.upperBound)
      XCTAssertEqual(kvps.endIndex, indexesOfInserted.upperBound)
    }

    // In general, appending an element won't delete all trailing pair delimiters, though.

    for n in 1...5 {
      var url = WebURL("http://example/?test=ok\(String(repeating: "&", count: n))")!
      let indexesOfInserted = url.queryParams.append(contentsOf: pairsToInsert)
      XCTAssertEqual(url.serialized(), "http://example/?test=ok\(String(repeating: "&", count: n))foo=bar&baz=qux")

      let kvps = url.queryParams
      XCTAssertEqualKeyValuePairs(kvps[indexesOfInserted], pairsToInsert)
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 1), indexesOfInserted.lowerBound)
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 3), indexesOfInserted.upperBound)
      XCTAssertEqual(kvps.endIndex, indexesOfInserted.upperBound)
    }

    // The exception is when the append location is startIndex (i.e. appending to an empty list).
    // When modifying, startIndex snaps back to the start of the URL component, eating any delimiters
    // that precede the first non-empty key-value pair.

    for i in 0...5 {
      var url = WebURL("http://example/?\(String(repeating: "&", count: i))")!
      let indexesOfInserted = url.queryParams.append(contentsOf: pairsToInsert)
      XCTAssertEqual(url.serialized(), "http://example/?foo=bar&baz=qux")

      let kvps = url.queryParams
      XCTAssertEqualKeyValuePairs(kvps[indexesOfInserted], pairsToInsert)
      XCTAssertEqual(kvps.startIndex, indexesOfInserted.lowerBound)
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 2), indexesOfInserted.upperBound)
      XCTAssertEqual(kvps.endIndex, indexesOfInserted.upperBound)
    }
  }

  func testAppendOne() {

    func _testAppendOne<Schema>(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      var url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialCount = url.keyValuePairs(in: component, schema: schema).count
      var expectedCount = initialCount

      func append(key: String, value: String, checkpointIdx: Int) {

        let appendedPairIndex = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let appendedPairIndex = kvps.append(key: key, value: value)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return appendedPairIndex
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: expectedCount), appendedPairIndex)
        XCTAssertEqual(KeyValuePair(kvps[appendedPairIndex]), KeyValuePair(key: key, value: value))

        expectedCount += 1
        XCTAssertEqual(kvps.count, expectedCount)

        XCTAssertEqual(url.serialized(), checkpoints[checkpointIdx])
      }

      // Append a single key.
      append(key: "foo", value: "bar", checkpointIdx: 0)

      // Same key, different value.
      append(key: "foo", value: "baz", checkpointIdx: 1)

      // Key/Value has a space.
      append(key: "the key", value: "sp ace", checkpointIdx: 2)

      // Another duplicate - same key, same value.
      append(key: "foo", value: "bar", checkpointIdx: 3)

      // Empty key.
      append(key: "", value: "emptykey", checkpointIdx: 4)

      // Empty value.
      append(key: "emptyval", value: "", checkpointIdx: 5)

      // Empty key and value.
      append(key: "", value: "", checkpointIdx: 6)

      // Empty key and value (again).
      append(key: "", value: "", checkpointIdx: 7)

      // Unicode with combining marks. Code-points should be encoded as given.
      append(key: "cafe\u{0301}", value: "caf\u{00E9}", checkpointIdx: 8)

      // Special characters.
      append(key: Self.SpecialCharacters, value: Self.SpecialCharacters, checkpointIdx: 9)

      // Check the contents.
      XCTAssertEqualKeyValuePairs(url.keyValuePairs(in: component, schema: schema).dropFirst(initialCount), [
        (key: "foo", value: "bar"),
        (key: "foo", value: "baz"),
        (key: "the key", value: "sp ace"),
        (key: "foo", value: "bar"),
        (key: "", value: "emptykey"),
        (key: "emptyval", value: ""),
        (key: "", value: ""),
        (key: "", value: ""),
        (key: "cafe\u{0301}", value: "caf\u{00E9}"),
        (key: Self.SpecialCharacters, value: Self.SpecialCharacters),
      ])
    }

    // Form encoded in the query (starts with nil query).
    _testAppendOne(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?foo=bar&foo=baz#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag"
      ]
    )

    // Form encoded in the query (starts with empty query, encodeSpaceAsPlus = true).
    _testAppendOne(
      url: "http://example/?#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?foo=bar&foo=baz#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar&=emptykey#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar&=emptykey&emptyval=#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar&=emptykey&emptyval=&=#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar&=emptykey&emptyval=&=&=#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?foo=bar&foo=baz&the+key=sp+ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)#frag"
      ]
    )

    // Form encoded in the query (starts with non-empty query; existing content must be preserved unchanged).
    _testAppendOne(
      url: "http://example/?test[+x%?]~=val^_`&&&x::y#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?test[+x%?]~=val^_`&&&x::y&foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag"
      ]
    )

    // Percent encoded in the query (starts with nil query, minimal percent-encoding).
    _testAppendOne(
      url: "http://example/#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?foo=bar&foo=baz#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&foo=bar&=emptykey&emptyval=&=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)=\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)#frag"
      ]
    )

    // Custom schema in the fragment (starts with nil fragment, minimal percent-encoding).
    _testAppendOne(
      url: "http://example/?srch",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#foo:bar",
        "http://example/?srch#foo:bar,foo:baz",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar,:emptykey",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar,:emptykey,emptyval:",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar,:emptykey,emptyval:,:",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar,:emptykey,emptyval:,:,:",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar,:emptykey,emptyval:,:,:,cafe%CC%81:caf%C3%A9",
        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,foo:bar,:emptykey,emptyval:,:,:,cafe%CC%81:caf%C3%A9,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag)"
      ]
    )
  }

  func testAppendOne_trailingEmptyPairs() {

    let pairToInsert = (key: "foo", value: "bar")

    // If the string already ends with a pair delimiter, we won't add another one when appending.

    do {
      var url = WebURL("http://example/?test=ok&")!
      let appendedPairIndex = url.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { kvps in
        let appendedPairIndex = kvps.append(key: pairToInsert.key, value: pairToInsert.value)
        XCTAssertKeyValuePairCacheIsAccurate(kvps)
        return appendedPairIndex
      }
      XCTAssertEqual(url.serialized(), "http://example/?test=ok&foo=bar")

      let kvps = url.queryParams
      XCTAssertEqual(KeyValuePair(kvps[appendedPairIndex]), KeyValuePair(pairToInsert))
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 1), appendedPairIndex)
      XCTAssertEqual(kvps.index(appendedPairIndex, offsetBy: 1), kvps.endIndex)
    }

    // In general, appending an element won't delete all trailing pair delimiters, though.

    for n in 1...5 {
      var url = WebURL("http://example/?test=ok\(String(repeating: "&", count: n))")!
      let appendedPairIndex = url.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { kvps in
        let appendedPairIndex = kvps.append(key: pairToInsert.key, value: pairToInsert.value)
        XCTAssertKeyValuePairCacheIsAccurate(kvps)
        return appendedPairIndex
      }
      XCTAssertEqual(url.serialized(), "http://example/?test=ok\(String(repeating: "&", count: n))foo=bar")

      let kvps = url.queryParams
      XCTAssertEqual(KeyValuePair(kvps[appendedPairIndex]), KeyValuePair(pairToInsert))
      XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: 1), appendedPairIndex)
      XCTAssertEqual(kvps.index(appendedPairIndex, offsetBy: 1), kvps.endIndex)
    }

    // The exception is when the append location is startIndex (i.e. appending to an empty list).
    // When modifying, startIndex snaps back to the start of the URL component, eating any delimiters
    // that precede the first non-empty key-value pair.

    for i in 0...5 {
      var url = WebURL("http://example/?\(String(repeating: "&", count: i))")!
      let appendedPairIndex = url.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { kvps in
        let appendedPairIndex = kvps.append(key: pairToInsert.key, value: pairToInsert.value)
        XCTAssertKeyValuePairCacheIsAccurate(kvps)
        return appendedPairIndex
      }
      XCTAssertEqual(url.serialized(), "http://example/?foo=bar")

      let kvps = url.queryParams
      XCTAssertEqual(KeyValuePair(kvps[appendedPairIndex]), KeyValuePair(pairToInsert))
      XCTAssertEqual(kvps.startIndex, appendedPairIndex)
      XCTAssertEqual(kvps.index(appendedPairIndex, offsetBy: 1), kvps.endIndex)
    }
  }
}

// replaceKey(at:with:), replaceValue(at:with:)

extension KeyValuePairsTests {

  func testReplaceKeyAt() {

    func _testReplaceKeyAt<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let count = url.keyValuePairs(in: component, schema: schema).count

      func replaceKey(atOffset offset: Int, with newKey: String) -> WebURL {

        var url = url

        let (expectedValue, returnedIndex) = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let idx = kvps.index(kvps.startIndex, offsetBy: offset)
          let retVal = (kvps[idx].value, kvps.replaceKey(at: idx, with: newKey))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return retVal
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(KeyValuePair(kvps[returnedIndex]), KeyValuePair(key: newKey, value: expectedValue))

        let calculatedIndex = kvps.index(kvps.startIndex, offsetBy: offset)
        XCTAssertEqual(calculatedIndex, returnedIndex)
        XCTAssertEqual(KeyValuePair(kvps[calculatedIndex]), KeyValuePair(key: newKey, value: expectedValue))

        XCTAssertEqual(kvps.count, count)

        return url
      }

      var result: WebURL

      // Replace at the front.
      result = replaceKey(atOffset: 0, with: "some replacement")
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Replace in the middle.
      result = replaceKey(atOffset: 1, with: Self.SpecialCharacters)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Replace in the middle (empty).
      result = replaceKey(atOffset: 1, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Replace at the end.
      result = replaceKey(atOffset: count - 1, with: "end key")
      XCTAssertEqual(result.serialized(), checkpoints[3])
    }

    // Form-encoded in the query.
    _testReplaceKeyAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?some%20replacement=bar&baz=qux&another=value#frag",
        "http://example/?foo=bar&\(Self.SpecialCharacters_Escaped_Form)=qux&another=value#frag",
        "http://example/?foo=bar&=qux&another=value#frag",
        "http://example/?foo=bar&baz=qux&end%20key=value#frag",
      ]
    )

    // Form-encoded in the query (encodeSpaceAsPlus = true).
    _testReplaceKeyAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?some+replacement=bar&baz=qux&another=value#frag",
        "http://example/?foo=bar&\(Self.SpecialCharacters_Escaped_Form_Plus)=qux&another=value#frag",
        "http://example/?foo=bar&=qux&another=value#frag",
        "http://example/?foo=bar&baz=qux&end+key=value#frag",
      ]
    )

    // Empty key-value pairs.
    _testReplaceKeyAt(
      url: "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&&&some%20replacement=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&\(Self.SpecialCharacters_Escaped_Form)=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&end%20key=3&&&#frag",
      ]
    )

    // Empty keys and values.
    _testReplaceKeyAt(
      url: "http://example/?=&=&=#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?some%20replacement=&=&=#frag",
        "http://example/?=&\(Self.SpecialCharacters_Escaped_Form)=&=#frag",
        "http://example/?=&=&=#frag",
        "http://example/?=&=&end%20key=#frag",
      ]
    )

    // No key-value delimiters.
    _testReplaceKeyAt(
      url: "http://example/?foo&baz&another#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?some%20replacement&baz&another#frag",
        "http://example/?foo&\(Self.SpecialCharacters_Escaped_Form)&another#frag",
        "http://example/?foo&=&another#frag",
        "http://example/?foo&baz&end%20key#frag",
      ]
    )

    // Custom schema in the fragment.
    _testReplaceKeyAt(
      url: "http://example/?srch#foo:bar,baz:qux,another:value",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#some%20replacement:bar,baz:qux,another:value",
        "http://example/?srch#foo:bar,\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):qux,another:value",
        "http://example/?srch#foo:bar,:qux,another:value",
        "http://example/?srch#foo:bar,baz:qux,end%20key:value",
      ]
    )
  }

  func testReplaceValueAt() {

    func _testReplaceValueAt<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let count = url.keyValuePairs(in: component, schema: schema).count

      func replaceValue(atOffset offset: Int, with newValue: String) -> WebURL {

        var url = url

        let (expectedKey, returnedIndex) = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let idx = kvps.index(kvps.startIndex, offsetBy: offset)
          let retVal = (kvps[idx].key, kvps.replaceValue(at: idx, with: newValue))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return retVal
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(KeyValuePair(kvps[returnedIndex]), KeyValuePair(key: expectedKey, value: newValue))

        let calculatedIndex = kvps.index(kvps.startIndex, offsetBy: offset)
        XCTAssertEqual(calculatedIndex, returnedIndex)
        XCTAssertEqual(KeyValuePair(kvps[calculatedIndex]), KeyValuePair(key: expectedKey, value: newValue))

        XCTAssertEqual(kvps.count, count)

        return url
      }

      var result: WebURL

      // Replace at the front.
      result = replaceValue(atOffset: 0, with: "some replacement")
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Replace in the middle.
      result = replaceValue(atOffset: 1, with: Self.SpecialCharacters)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Replace in the middle (empty).
      result = replaceValue(atOffset: 1, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Replace at the end.
      result = replaceValue(atOffset: count - 1, with: "end value")
      XCTAssertEqual(result.serialized(), checkpoints[3])
    }

    // Form-encoded in the query.
    _testReplaceValueAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=some%20replacement&baz=qux&another=value#frag",
        "http://example/?foo=bar&baz=\(Self.SpecialCharacters_Escaped_Form)&another=value#frag",
        "http://example/?foo=bar&baz=&another=value#frag",
        "http://example/?foo=bar&baz=qux&another=end%20value#frag",
      ]
    )

    // Form-encoded in the query (encodeSpaceAsPlus = true).
    _testReplaceValueAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?foo=some+replacement&baz=qux&another=value#frag",
        "http://example/?foo=bar&baz=\(Self.SpecialCharacters_Escaped_Form_Plus)&another=value#frag",
        "http://example/?foo=bar&baz=&another=value#frag",
        "http://example/?foo=bar&baz=qux&another=end+value#frag",
      ]
    )

    // Empty key-value pairs.
    _testReplaceValueAt(
      url: "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&&&first[+^x%`?]~=some%20replacement&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=\(Self.SpecialCharacters_Escaped_Form)&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=3&&&#frag",
        "http://example/?&&&first[+^x%`?]~=0&&&second[+^x%`?]~=1&&&third[+^x%`?]~=2&&&fourth[+^x%`?]~=end%20value&&&#frag",
      ]
    )

    // No key-value delimiters.
    _testReplaceValueAt(
      url: "http://example/?foo&baz&another#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=some%20replacement&baz&another#frag",
        "http://example/?foo&baz=\(Self.SpecialCharacters_Escaped_Form)&another#frag",
        "http://example/?foo&baz&another#frag",
        "http://example/?foo&baz&another=end%20value#frag",
      ]
    )

    // Empty keys and values.
    _testReplaceValueAt(
      url: "http://example/?=&=&=#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?=some%20replacement&=&=#frag",
        "http://example/?=&=\(Self.SpecialCharacters_Escaped_Form)&=#frag",
        "http://example/?=&=&=#frag",
        "http://example/?=&=&=end%20value#frag",
      ]
    )

    // Custom schema in the fragment.
    _testReplaceValueAt(
      url: "http://example/?srch#foo:bar,baz:qux,another:value",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        "http://example/?srch#foo:some%20replacement,baz:qux,another:value",
        "http://example/?srch#foo:bar,baz:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),another:value",
        "http://example/?srch#foo:bar,baz:,another:value",
        "http://example/?srch#foo:bar,baz:qux,another:end%20value",
      ]
    )
  }
}


// -------------------------------
// MARK: - Writing: By Key.
// -------------------------------

// set(key:to:)

extension KeyValuePairsTests {

  func testSet() {

    func _testSet<Schema>(
      url urlString: String, component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      func set_method(key: String, to newValue: String) -> WebURL {

        var copy = url
        let returnedIndex = copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let returnedIndex = kvps.set(key: key, to: newValue)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return returnedIndex
        }
        XCTAssertURLIsIdempotent(copy)

        let kvps = copy.keyValuePairs(in: component, schema: schema)

        XCTAssertEqual(kvps[returnedIndex].key, key)
        XCTAssert(kvps[returnedIndex].value.unicodeScalars.elementsEqual(newValue.unicodeScalars))
        XCTAssertEqual(kvps.firstIndex(where: { $0.key == key }), returnedIndex)
        XCTAssertNil(kvps[kvps.index(after: returnedIndex)...].firstIndex(where: { $0.key == key }))

        return copy
      }

      func set_subscript(key: String, to newValue: String?) -> WebURL {

        var copy = url
        copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          kvps[key] = newValue
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
        }
        XCTAssertURLIsIdempotent(copy)

        let kvps = copy.keyValuePairs(in: component, schema: schema)

        if let newValue = newValue {
          let firstMatch = kvps.firstIndex(where: { $0.key == key })!
          XCTAssertEqual(kvps[firstMatch].key, key)
          XCTAssert(kvps[firstMatch].value.unicodeScalars.elementsEqual(newValue.unicodeScalars))
          XCTAssertNil(kvps[kvps.index(after: firstMatch)...].firstIndex(where: { $0.key == key }))
        } else {
          XCTAssertNil(kvps.firstIndex(where: { $0.key == key }))
        }

        return copy
      }

      do {
        // Set a key with a single value.

        let result_method = set_method(key: Self.SpecialCharacters, to: "found")
        let result_subsct = set_subscript(key: Self.SpecialCharacters, to: "found")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[0])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[0])
      }

      do {
        // Set a key with a single value (Unicode).
        // Both ways of writing the key should find the same pair,
        // and keep its current spelling when updating the value.

        var result_method = set_method(key: "cafe\u{0301}", to: "unicode")
        var result_subsct = set_subscript(key: "cafe\u{0301}", to: "unicode")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[1])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[1])

        result_method = set_method(key: "caf\u{00E9}", to: "unicode")
        result_subsct = set_subscript(key: "caf\u{00E9}", to: "unicode")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[1])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[1])
      }

      do {
        // Set the first key.

        let firstKey = url.keyValuePairs(in: component, schema: schema).first!.key

        let result_method = set_method(key: firstKey, to: "first")
        let result_subsct = set_subscript(key: firstKey, to: "first")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[2])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[2])
      }

      do {
        // Set a key with multiple values.

        let result_method = set_method(key: "dup", to: Self.SpecialCharacters)
        let result_subsct = set_subscript(key: "dup", to: Self.SpecialCharacters)

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[3])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[3])
      }

      do {
        // Set a non-present key (insert)

        let result_method = set_method(key: "inserted-" + Self.SpecialCharacters, to: "yes")
        let result_subsct = set_subscript(key: "inserted-" + Self.SpecialCharacters, to: "yes")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[4])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[4])
      }

      do {
        // Set a value to the empty string.

        let result_method = set_method(key: Self.SpecialCharacters, to: "")
        let result_subsct = set_subscript(key: Self.SpecialCharacters, to: "")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[5])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[5])
      }

      do {
        // Associate a value with the empty key.

        let result_method = set_method(key: "", to: "empty")
        let result_subsct = set_subscript(key: "", to: "empty")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[6])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[6])
      }

      do {
        // Associate an empty string with the empty key.
        
        let result_method = set_method(key: "", to: "")
        let result_subsct = set_subscript(key: "", to: "")

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), checkpoints[7])
        XCTAssertEqual(result_subsct.serialized(), checkpoints[7])
      }

      do {
        // [Subscript only]
        // Remove a key with a single value.

        let result = set_subscript(key: Self.SpecialCharacters, to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[8])
      }

      do {
        // [Subscript only]
        // Remove a key with a single value (Unicode).

        var result = set_subscript(key: "cafe\u{0301}", to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[9])

        result = set_subscript(key: "caf\u{00E9}", to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[9])
      }

      do {
        // [Subscript only]
        // Remove the first key.

        let firstKey = url.keyValuePairs(in: component, schema: schema).first!.key

        let result = set_subscript(key: firstKey, to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[10])
      }

      do {
        // [Subscript only]
        // Remove a key with multiple values.

        let result = set_subscript(key: "dup", to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[11])
      }

      do {
        // [Subscript only]
        // Remove a non-present key (no-op).

        let result = set_subscript(key: "doesNotExist", to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[12])
      }

      do {
        // [Subscript only]
        // Remove values for the empty key.

        let result = set_subscript(key: "", to: nil)
        XCTAssertEqual(result.serialized(), checkpoints[13])
      }

      do {
        // [Subscript only]
        // Remove all keys.

        var result = url
        while let key = result.keyValuePairs(in: component, schema: schema).first?.key {
          result.withMutableKeyValuePairs(in: component, schema: schema) {
            $0[key] = nil
            XCTAssertKeyValuePairCacheIsAccurate($0)
          }
          XCTAssertURLIsIdempotent(result)
        }
        XCTAssertEqual(result.serialized(), checkpoints[14])
      }
    }

    // Form-encoded in the query.
    _testSet(
      url: "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Single value.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=found&cafe%CC%81=cheese&dup#frag",
        // Single value (Unicode).
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=unicode&dup#frag",
        // First key.
        "http://example/p?foo=first&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        // Multiple values.
        "http://example/p?foo=bar&dup=\(Self.SpecialCharacters_Escaped_Form)&=x&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",
        // Appended pair.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup&inserted-\(Self.SpecialCharacters_Escaped_Form)=yes#frag",
        // Set value to the empty string.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=&cafe%CC%81=cheese&dup#frag",
        // Set value for empty key.
        "http://example/p?foo=bar&dup&=empty&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        // Set empty value for empty key.
        "http://example/p?foo=bar&dup&=&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",

        // Remove single value.
        "http://example/p?foo=bar&dup&=x&dup&cafe%CC%81=cheese&dup#frag",
        // Remove single value (Unicode).
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&dup#frag",
        // Remove first key.
        "http://example/p?dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        // Remove multiple values.
        "http://example/p?foo=bar&=x&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",
        // Remove non-present key.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        // Remove values for the empty key.
        "http://example/p?foo=bar&dup&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        // Remove all keys.
        "http://example/p#frag",
      ]
    )

    // Percent-encoded in the query.
    _testSet(
      url: "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        // Single value.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)=found&caf%C3%A9=cheese&dup#frag",
        // Single value (Unicode).
        // >> This URL contain the 'caf\u{00E9}' formulation, but it still gets matched.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=unicode&dup#frag",
        // First key.
        "http://example/p?foo=first&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        // Multiple values.
        "http://example/p?foo=bar&dup=\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)&=x&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese#frag",
        // Appended pair.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup&inserted-\(Self.SpecialCharacters_Escaped_MinPctEnc_Query)=yes#frag",
        // Set value to the empty string.
        // >> Since the KVP does not include a key-value delimiter, none is added.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        // Set value for empty key.
        "http://example/p?foo=bar&dup&=empty&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        // Set empty value for empty key.
        "http://example/p?foo=bar&dup&=&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",

        // Remove single value.
        "http://example/p?foo=bar&dup&=x&dup&caf%C3%A9=cheese&dup#frag",
        // Remove single value (Unicode).
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&dup#frag",
        // Remove first key.
        "http://example/p?dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        // Remove multiple values.
        "http://example/p?foo=bar&=x&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese#frag",
        // Remove non-present key.
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        // Remove values for the empty key.
        "http://example/p?foo=bar&dup&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        // Remove all keys.
        "http://example/p#frag",
      ]
    )

    // Empty key-value pairs.
    // This can expose some implementation details.
    _testSet(
      url: "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Single value.
        // >> No empty pairs are removed.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=found&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Single value (Unicode).
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=unicode&&&dup&&&#frag",
        // First key.
        "http://example/p?&&&foo=first&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Multiple values.
        // >> Empty pairs are removed, from after the second match.
        "http://example/p?&&&foo=bar&&&dup=\(Self.SpecialCharacters_Escaped_Form)&&&=x&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",
        // Appended pair.
        // >> Reuses one trailing pair delimiter, as regular 'append' does.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&inserted-\(Self.SpecialCharacters_Escaped_Form)=yes#frag",
        // Set value to the empty string.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Set value for empty key.
        "http://example/p?&&&foo=bar&&&dup&&&=empty&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Set empty value for empty key.
        "http://example/p?&&&foo=bar&&&dup&&&=&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",

        // Remove single value.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Remove single value (Unicode).
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&dup&&&#frag",
        // Remove first key.
        // >> Removes leading empty pairs, as 'replaceSubrange', etc do.
        "http://example/p?dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Remove multiple values.
        // >> Empty pairs are removed, from after the second match.
        "http://example/p?&&&foo=bar&&&=x&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",
        // Remove non-present key.
        // >> Is a complete no-op; leaves the entire string unchanged.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Remove values for the empty key.
        "http://example/p?&&&foo=bar&&&dup&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        // Remove all keys.
        "http://example/p#frag",
      ]
    )

    // Custom schema in the fragment.
    _testSet(
      url: "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
      component: .fragment, schema: CommaSeparated(minimalPercentEncoding: true), checkpoints: [
        // Single value.
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):found,caf%C3%A9:cheese,dup",
        // Single value (Unicode).
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:unicode,dup",
        // First key.
        "http://example/p?q#foo:first,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        // Multiple values.
        "http://example/p?q#foo:bar,dup:\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag),:x,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese",
        // Appended pair.
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup,inserted-\(Self.SpecialCharacters_Escaped_MinCommaSep_Frag):yes",
        // Set value to the empty string.
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):,caf%C3%A9:cheese,dup",
        // Set value for empty key.
        "http://example/p?q#foo:bar,dup,:empty,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        // Set empty value for empty key.
        "http://example/p?q#foo:bar,dup,:,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",

        // Remove single value.
        "http://example/p?q#foo:bar,dup,:x,dup,caf%C3%A9:cheese,dup",
        // Remove single value (Unicode).
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,dup",
        // Remove first key.
        "http://example/p?q#dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        // Remove multiple values.
        "http://example/p?q#foo:bar,:x,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese",
        // Remove non-present key.
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        // Remove values for the empty key.
        "http://example/p?q#foo:bar,dup,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        // Remove all keys.
        "http://example/p?q",
      ]
    )
  }
}


// TODO: More Tests


struct EncodeCommas: PercentEncodeSet {
  func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    codePoint == 0x2C || codePoint == 0x25
  }
}

extension WebURL.KeyValuePairs {

  subscript(commaSeparatedArray key: some StringProtocol) -> [String] {
    get {
      guard let restored = self[key] else { return [] }
      return restored.lazy.split(separator: ",").map { restored[$0.startIndex..<$0.endIndex].percentDecoded() }
    }
    set {
      guard !newValue.isEmpty else {
        self[key] = nil
        return
      }
      let escaped = newValue.lazy.map { $0.percentEncoded(using: EncodeCommas()) }.joined(separator: ",")
      print(escaped)
      self[key] = escaped
    }
  }

  subscript(indexedArray key: some StringProtocol) -> [String] {
    get {
      var entries = compactMap { kvp -> (Int, String)? in
        var _key = kvp.key[...]
        guard _key.starts(with: key) else { return nil }
        _key = _key.dropFirst(key.count)
        guard _key.popFirst() == "[", _key.popLast() == "]" else { return nil }
        guard let idx = Int(_key), idx >= 0 else { return nil }
        return (idx, kvp.value)
      }
      entries.sort(by: { $0.0 < $1.0 })
      return entries.map { $0.1 }
    }
    set {
      guard !newValue.isEmpty else {
        self[key] = nil
        return
      }

      func isIndexedKey(_ _key: String) -> Bool {
        var _key = _key[...]
        guard _key.starts(with: key) else { return false }
        _key = _key.dropFirst(key.count)
        guard _key.popFirst() == "[", _key.popLast() == "]" else { return false }
        return true
      }

      guard var firstMatch = fastFirstIndex(where: { isIndexedKey($0.key) }) else {
        append(contentsOf: newValue.enumerated().lazy.map { (i, val) in ("\(key)[\(i)]", val) })
        return
      }
      if let secondMatch = fastFirstIndex(
        from: index(after: firstMatch),
        to: endIndex,
        where: { isIndexedKey($0.key) }
      ) {
        removeAll(in: Range(uncheckedBounds: (secondMatch, endIndex)), where: { isIndexedKey($0.key) })
      }
      firstMatch = remove(at: firstMatch)
      insert(contentsOf: newValue.enumerated().lazy.map { (i, val) in ("\(key)[\(i)]", val) }, at: firstMatch)
    }
  }
}

extension KeyValuePairsTests {

  func testUTF8Slices() {

     let url = WebURL("http://example/convert?amount=200&from=EUR&to=USD")!
     if let match = url.queryParams.firstIndex(where: { $0.key == "from" }) {
       let slices = url.utf8.keyValuePair(match)
       XCTAssert(slices.key.elementsEqual("from".utf8))
       XCTAssert(slices.value.elementsEqual("EUR".utf8))
     }

    // FIXME: Test no delimiter, Unicode, multiple matches, etc.
  }

  func testEncodedKeyValue() {
    // FIXME: Test KeyValuePairs<S>.Element.encodedKey/encodedValue
  }


  func testA() {

    let configFile = [
      ("apikey", "foobar"),
      ("apiver", "2.2"),
      ("client", "mobapp-2.4"),
    ]

    var kvps = WebURL("p://x/")!.keyValuePairs(in: .query, schema: .percentEncoded)
    XCTAssertEqual(kvps.description, "")

    kvps += configFile
    kvps[indexedArray: "foo"] = ["a", "b", "c"]
    kvps.append(key: "middle", value: "")
    kvps.append(key: "foo[3]", value: "d")
    XCTAssertEqual(kvps.description, "apikey=foobar&apiver=2.2&client=mobapp-2.4&foo[0]=a&foo[1]=b&foo[2]=c&middle=&foo[3]=d")
    XCTAssertEqual(kvps[indexedArray: "foo"], ["a", "b", "c", "d"])

    kvps[indexedArray: "foo"] = ["1", "2", "3"]
    XCTAssertEqual(kvps.description, "apikey=foobar&apiver=2.2&client=mobapp-2.4&foo[0]=1&foo[1]=2&foo[2]=3&middle=")
    XCTAssertEqual(kvps[indexedArray: "foo"], ["1", "2", "3"])
  }

  func testB() {

    var url = WebURL("http://example/?q=test&offset=0")!

    url.queryParams.incrementOffset()
    print(url)

    url.queryParams.append(key: "limit", value: "20")
    print(url)

    url.queryParams.incrementOffset(by: 7)
    print(url)

    url.queryParams.incrementOffset()
    print(url)
  }
}


extension WebURL.KeyValuePairs {
  mutating func incrementOffset(by amount: Int = 10) {
    if let offsetIdx = firstIndex(where: { $0.key == "offset" }) {
      let newValue = Int(self[offsetIdx].value).map { $0 + amount } ?? 0
      replaceValue(at: offsetIdx, with: String(newValue))
    } else {
      append(key: "offset", value: "0")
    }
  }
}



extension KeyValuePairsTests {

  func testAlphaDelimiters() {

    struct AlphaDelimiters: KeyValueStringSchema {
      var preferredPairDelimiter: UInt8 { UInt8(ascii: "x") }
      var preferredKeyValueDelimiter: UInt8 { UInt8(ascii: "t") }
      var decodePlusAsSpace: Bool { false }
    }

    let pairsToAdd = [
      ("Test", "123"),
      ("Another test", "456"),
      ("results", "excellent"),
    ]

    var url = WebURL("p://x/")!
    url.withMutableKeyValuePairs(in: .query, schema: AlphaDelimiters()) { $0 += pairsToAdd }
    XCTAssertEqual(url.serialized(), "p://x/?Tes%74t123xAno%74her%20%74es%74t456xresul%74ste%78cellen%74")

    let retrieved = url.keyValuePairs(in: .query, schema: AlphaDelimiters()).map { KeyValuePair($0) }
    XCTAssertEqual(retrieved, pairsToAdd.map { KeyValuePair($0) })
  }
}












  //  func testAssignment() {
  //
  //    do {
  //      var url0 = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
  //      XCTAssertEqual(url0.serialized(), "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  //      XCTAssertEqual(url0.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  //      XCTAssertFalse(url0.storage.structure.queryIsKnownFormEncoded)
  //
  //      var url1 = WebURL("foo://bar")!
  //      XCTAssertEqual(url1.serialized(), "foo://bar")
  //      XCTAssertNil(url1.query)
  //      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)
  //
  //      // Set url1's formParams from empty to url0's non-empty formParams.
  //      // url1's query string should be the form-encoded version version of url0's query, which itself remains unchanged.
  //      url1.queryParams = url0.queryParams
  //      XCTAssertEqual(url1.serialized(), "foo://bar?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  //      XCTAssertEqual(url1.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  //      XCTAssertEqual(url0.serialized(), "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  //      XCTAssertEqual(url0.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  //      XCTAssertFalse(url0.storage.structure.queryIsKnownFormEncoded)
  //      XCTAssertFalse(url1.storage.structure.queryIsKnownFormEncoded)
  //      XCTAssertURLIsIdempotent(url1)
  //
  //      // Reset url1 to a nil query. Set url0's non-empty params to url1's empty params.
  //      // url0 should now have a nil query, and url1 remains unchanged.
  //      url1 = WebURL("foo://bar")!
  //      XCTAssertEqual(url1.serialized(), "foo://bar")
  //      XCTAssertNil(url1.query)
  //      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)
  //
  //      url0.queryParams = url1.queryParams
  //      XCTAssertEqual(url0.serialized(), "http://example.com/")
  //      XCTAssertNil(url0.query)
  //      XCTAssertTrue(url0.storage.structure.queryIsKnownFormEncoded)
  //      XCTAssertEqual(url1.serialized(), "foo://bar")
  //      XCTAssertNil(url1.query)
  //      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)
  //      XCTAssertURLIsIdempotent(url0)
  //    }
  //
  //    // Assigning a URL's query parameters to itself has no effect.
  //    do {
  //      var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f&&&")!
  //      XCTAssertEqual(
  //        url.serialized(), "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f&&&"
  //      )
  //      XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f&&&")
  //      XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)
  //
  //      url.queryParams = url.queryParams
  //      XCTAssertEqual(
  //        url.serialized(), "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f&&&"
  //      )
  //      XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f&&&")
  //      XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)
  //      XCTAssertURLIsIdempotent(url)
  //    }
  //  }
  //
//}
