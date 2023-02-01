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

#if swift(<5.7)
  #error("WebURL.KeyValuePairs requires Swift 5.7 or newer")
#endif

import XCTest
import Checkit
@testable import WebURL

final class KeyValuePairsTests: XCTestCase {}

extension KeyValuePairsTests {

  static let SpecialCharacters = "\u{0000}\u{0001}\u{0009}\u{000A}\u{000D} !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
  static let SpecialCharacters_Escaped_Form = "%00%01%09%0A%0D%20%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D%7E"
  static let SpecialCharacters_Escaped_Form_Plus = "%00%01%09%0A%0D+%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D%7E"
  static let SpecialCharacters_Escaped_PrctEnc_Query = #"%00%01%09%0A%0D%20!%22%23$%25%26%27()*%2B,-./:;%3C%3D%3E?@[\]^_`{|}~"#
  static let SpecialCharacters_Escaped_PrctEnc_Query_NoSemiColon = #"%00%01%09%0A%0D%20!%22%23$%25%26%27()*%2B,-./:%3B%3C%3D%3E?@[\]^_`{|}~"#
  static let SpecialCharacters_Escaped_CommaSep_Frag = #"%00%01%09%0A%0D%20!%22#$%25&'()*%2B%2C-./%3A;%3C=%3E?@[\]^_%60{|}~"#

  // For PercentEncodedKeyValueString.shouldPercentEncode == true when !isNonURLCodePoint:
  //  static let SpecialCharacters_Escaped_PrctEnc_Query = #"%00%01%09%0A%0D%20!%22%23$%25%26%27()*%2B,-./:;%3C%3D%3E?@%5B%5C%5D%5E_%60%7B%7C%7D~"#
  //  static let SpecialCharacters_Escaped_CommaSep_Frag = #"%00%01%09%0A%0D%20!%22%23$%25&'()*%2B%2C-./%3A;%3C=%3E?@%5B%5C%5D%5E_%60%7B%7C%7D~"#
}


// --------------------------------------------
// MARK: - Reading: By Location
// --------------------------------------------


extension KeyValuePairsTests {

  /// Tests the KeyValuePairs conformance to Collection.
  ///
  /// This includes testing that the view contains the expected elements on multiple passes,
  /// and that indexing works as required by the protocol (via `swift-checkit`).
  ///
  /// Many of the key-value pairs have interesting features, such as special characters,
  /// pairs with the same key, pairs whose key differs in Unicode normalization,
  /// empty key names or values, etc.
  ///
  /// Tests are repeated:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testCollectionConformance() {

    func _testCollectionConformance(_ kvps: WebURL.KeyValuePairs<some KeyValueStringSchema>) {
      let expected = [
        (key: "a", value: "b"),
        (key: "sp ac & es", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "👀"),
        (key: "jalapen\u{0303}os", value: "nfd"),
        (key: "specials", value: Self.SpecialCharacters),
        (key: "dup", value: "f"),
        (key: "jalape\u{00F1}os", value: "nfc"),
        (key: "1+1", value: "2"),
      ]
      XCTAssertEqualKeyValuePairs(kvps, expected)
      CollectionChecker.check(kvps)
      XCTAssertEqualKeyValuePairs(kvps, expected)
    }

    // Empty key-value pairs should be skipped. There is no Index which covers that range of the string,
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
        let url = WebURL("http://example/?\(start)a=b&sp%20ac+%26+es=d&dup=e\(middle)&=foo&noval&emoji=👀&jalapen\u{0303}os=nfd&specials=\(Self.SpecialCharacters_Escaped_Form)&dup=f&jalape\u{00F1}os=nfc&1%2B1=2\(end)#a=z")!
        XCTAssertEqual(url.query, "\(start)a=b&sp%20ac+%26+es=d&dup=e\(middle)&=foo&noval&emoji=%F0%9F%91%80&jalapen%CC%83os=nfd&specials=\(Self.SpecialCharacters_Escaped_Form)&dup=f&jalape%C3%B1os=nfc&1%2B1=2\(end)")
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
        let url = WebURL("http://example/?\(start)a=b&sp%20ac+%26+es=d;dup=e\(middle)&=foo&noval&emoji=👀;jalapen\u{0303}os=nfd;specials=\(Self.SpecialCharacters_Escaped_Form)&dup=f&jalape\u{00F1}os=nfc&1%2B1=2\(end)#a=z")!
        XCTAssertEqual(url.query, "\(start)a=b&sp%20ac+%26+es=d;dup=e\(middle)&=foo&noval&emoji=%F0%9F%91%80;jalapen%CC%83os=nfd;specials=\(Self.SpecialCharacters_Escaped_Form)&dup=f&jalape%C3%B1os=nfc&1%2B1=2\(end)")
        _testCollectionConformance(url.keyValuePairs(in: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)))
      }
    }

    // Custom schema in the fragment.
    // Note the use of unescaped '&' and '+' characters.

    do {
      let injections = [
        (start: "", middle: "", end: ""),
        (start: ",,,", middle: "", end: ""),
        (start: "", middle: ",,,", end: ""),
        (start: "", middle: "", end: ",,,"),
        (start: ",,,,", middle: ",,,,", end: ",,,,")
      ]
      for (start, middle, end) in injections {
        let url = WebURL("http://example/?a:z#\(start)a:b,sp%20ac%20&%20es:d,dup:e\(middle),:foo,noval,emoji:👀,jalapen\u{0303}os:nfd,specials:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),dup:f,jalape\u{00F1}os:nfc,1+1:2\(end)")!
        XCTAssertEqual(url.fragment, "\(start)a:b,sp%20ac%20&%20es:d,dup:e\(middle),:foo,noval,emoji:%F0%9F%91%80,jalapen%CC%83os:nfd,specials:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),dup:f,jalape%C3%B1os:nfc,1+1:2\(end)")
        _testCollectionConformance(url.keyValuePairs(in: .fragment, schema: CommaSeparated()))
      }
    }
  }

  /// Tests situations where KeyValuePairs is expected to be empty.
  ///
  /// Also checks that a list of pairs, each of which has an empty key and value,
  /// is not the same as an empty list.
  ///
  /// Tests are repeated:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  ///
  func testEmptyCollection() {

    func _testEmptyCollection(
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      func assertKeyValuePairsIsEmptyList(_ url: WebURL) {
        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.isEmpty, true)
        CollectionChecker.check(kvps)
        for kvp in kvps {
          XCTFail("KeyValuePairs was not empty - found \(kvp)")
        }
      }

      let componentKeyPath: WritableKeyPath<WebURL, String?>
      switch component.value {
      case .query: componentKeyPath = \.query
      case .fragment: componentKeyPath = \.fragment
      }

      // URL Component is nil. Should be an empty list.

      do {
        let url = WebURL(checkpoints[0])!
        XCTAssertEqual(url.serialized(), checkpoints[0])
        XCTAssertEqual(url[keyPath: componentKeyPath], nil)
        assertKeyValuePairsIsEmptyList(url)
      }

      // URL component is the empty string. Should be an empty list.

      do {
        let url = WebURL(checkpoints[1])!
        XCTAssertEqual(url.serialized(), checkpoints[1])
        XCTAssertEqual(url[keyPath: componentKeyPath], "")
        assertKeyValuePairsIsEmptyList(url)
      }

      // URL component consists only of empty key-value pairs (e.g. "&&&"). Should be an empty list. (x4)

      for i in 2..<6 {
        let url = WebURL(checkpoints[i])!
        XCTAssertEqual(url.serialized(), checkpoints[i])
        XCTAssertFalse(url[keyPath: componentKeyPath]!.contains(where: { !schema.isPairDelimiter($0.asciiValue!) }))
        assertKeyValuePairsIsEmptyList(url)
      }

      // URL component consists of a string of pairs with empty keys and values (e.g. "=&=&=").
      // Should NOT be an empty list. (x4)

      for i in 6..<10 {
        let url = WebURL(checkpoints[i])!
        XCTAssertEqual(url.serialized(), checkpoints[i])

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.count, 1 + i - 6)
        for pair in kvps {
          XCTAssertEqual(pair.encodedKey, "")
          XCTAssertEqual(pair.encodedValue, "")
          XCTAssertEqual(pair.key, "")
          XCTAssertEqual(pair.value, "")
        }
        CollectionChecker.check(kvps)
      }
    }

    // Form encoding in the query.

    _testEmptyCollection(
      component: .query, schema: .formEncoded, checkpoints: [
      "http://example/",
      "http://example/?",

      "http://example/?&",
      "http://example/?&&",
      "http://example/?&&&",
      "http://example/?&&&&",

      "http://example/?=",
      "http://example/?=&=",
      "http://example/?=&=&=",
      "http://example/?=&=&=&=",
    ])

    // Form encoding in the query (2).
    // Semicolons are also allowed as pair delimiters.

    _testEmptyCollection(
      component: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true), checkpoints: [
      "http://example/",
      "http://example/?",

      "http://example/?;",
      "http://example/?&;",
      "http://example/?&;&",
      "http://example/?;&;&",

      "http://example/?=",
      "http://example/?=;=",
      "http://example/?=&=;=",
      "http://example/?=;=;=;=",
    ])

    // Custom schema in the fragment.

    _testEmptyCollection(
      component: .fragment, schema: CommaSeparated(), checkpoints: [
      "http://example/",
      "http://example/#",

      "http://example/#,",
      "http://example/#,,",
      "http://example/#,,,",
      "http://example/#,,,,",

      "http://example/#:",
      "http://example/#:,:",
      "http://example/#:,:,:",
      "http://example/#:,:,:,:",
    ])
  }
}


// -------------------------------
// MARK: - Writing: By Location
// -------------------------------


// replaceSubrange(_:with:)

extension KeyValuePairsTests {

  /// Tests using `replaceSubrange(_:with:)` to replace a contiguous region of key-value pairs.
  ///
  /// This test only covers partial replacements: the list of pairs does not start empty,
  /// and some of its initial elements will be present in the result.
  ///
  /// **Test ranges**:
  ///
  /// - Anchored to the start
  /// - Not anchored (floating in the middle)
  /// - Anchored to the end
  ///
  /// **Operations**:
  ///
  /// | Operation | Removing      | Inserting      |
  /// |-----------|---------------|----------------|
  /// | No-Op     | No elements   | No elements    |
  /// | Insertion | No elements   | Some elements  |
  /// |-----------|---------------|----------------|
  /// | Deletion  | Some elements | No elements    |
  /// | Shrink    | Some elements | Fewer elements |
  /// | Grow      | Some elements | More elements  |
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testReplaceSubrange_partialReplacement() {

    func _testReplaceSubrange(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let initialCount = initialPairs.count
      precondition(initialCount >= 4, "URL component must contain at least 4 key-value pairs to run this test")

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

        let kvps = url.keyValuePairs(in: component, schema: schema)
        let expectedNewPairs = newPairs.map { KeyValuePair(key: $0.0, value: $0.1) }

        // Check that the returned indexes are at the expected offsets,
        // and contain the expected new pairs.

        XCTAssertEqual(
          kvps.index(kvps.startIndex, offsetBy: offsets.lowerBound),
          newPairIndexes.lowerBound
        )
        XCTAssertEqual(
          kvps.index(kvps.startIndex, offsetBy: offsets.upperBound - offsets.count + newPairs.count),
          newPairIndexes.upperBound
        )
        XCTAssertEqualKeyValuePairs(kvps[newPairIndexes], expectedNewPairs)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.replaceSubrange(offsets, with: expectedNewPairs)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      var result: WebURL

      // Do nothing at the start.
      result = replace(offsets: 0..<0, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Do nothing in the middle.
      result = replace(offsets: 2..<2, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Do nothing at the end.
      result = replace(offsets: initialCount..<initialCount, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Insertion at the start.
      result = replace(offsets: 0..<0, with: [("inserted", "one"), (Self.SpecialCharacters, "two")])
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Insertion in the middle.
      result = replace(offsets: 2..<2, with: [("inserted", "one"), ("another insert", Self.SpecialCharacters)])
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Insertion at the end.
      result = replace(offsets: initialCount..<initialCount, with: [("inserted", "one"), ("another insert", "two")])
      XCTAssertEqual(result.serialized(), checkpoints[5])

      // Removal from the start.
      result = replace(offsets: 0..<2, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[6])

      // Removal from the middle.
      result = replace(offsets: 1..<3, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[7])

      // Removal from the end.
      result = replace(offsets: initialCount - 2..<initialCount, with: [])
      XCTAssertEqual(result.serialized(), checkpoints[8])

      // Shrink at the start.
      result = replace(offsets: 0..<2, with: [("shrink", "start")])
      XCTAssertEqual(result.serialized(), checkpoints[9])

      // Shrink in the middle.
      result = replace(offsets: 1..<3, with: [("shrink", Self.SpecialCharacters)])
      XCTAssertEqual(result.serialized(), checkpoints[10])

      // Shrink at the end.
      result = replace(offsets: initialCount - 2..<initialCount, with: [("shrink", "end")])
      XCTAssertEqual(result.serialized(), checkpoints[11])

      // Grow at the start.
      result = replace(offsets: 0..<2, with: [("grow", "start"), ("grow s", "sp ace"), (Self.SpecialCharacters, "🥸")])
      XCTAssertEqual(result.serialized(), checkpoints[12])

      // Grow in the middle.
      result = replace(offsets: 2..<3, with: [("grow", "mid"), ("🌱", "🌻"), ("grow", Self.SpecialCharacters)])
      XCTAssertEqual(result.serialized(), checkpoints[13])

      // Grow at the end.
      result = replace(offsets: initialCount - 1..<initialCount, with: [("grow", "end"), ("", "noname"), ("", "")])
      XCTAssertEqual(result.serialized(), checkpoints[14])
    }

    // Form encoded in the query.

    _testReplaceSubrange(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",

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

    // Form encoded in the query (2).
    // Inserted spaces are encoded using "+" signs.

    _testReplaceSubrange(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",

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

    // Custom schema in the fragment.

    _testReplaceSubrange(
      url: "http://example/?srch#first:0,second:1,third:2,fourth:3",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3",

        "http://example/?srch#inserted:one,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):two,first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,inserted:one,another%20insert:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3,inserted:one,another%20insert:two",

        "http://example/?srch#third:2,fourth:3",
        "http://example/?srch#first:0,fourth:3",
        "http://example/?srch#first:0,second:1",

        "http://example/?srch#shrink:start,third:2,fourth:3",
        "http://example/?srch#first:0,shrink:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),fourth:3",
        "http://example/?srch#first:0,second:1,shrink:end",

        "http://example/?srch#grow:start,grow%20s:sp%20ace,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):%F0%9F%A5%B8,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,grow:mid,%F0%9F%8C%B1:%F0%9F%8C%BB,grow:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),fourth:3",
        "http://example/?srch#first:0,second:1,third:2,grow:end,:noname,:",
      ]
    )

    // Empty key-value pairs, special characters in existing content.
    //
    // - Empty key-value pairs.
    //
    //   Empty pairs ("&&&") are skipped; they exist in the underlying component string,
    //   but they do NOT exist in the list of pairs. No KeyValuePairs.Index points to them.
    //   However, the range `x..<y` may cover a region of the string which _does_ include some empty pairs.
    //   So what happens to empty pairs when we replace the contents of `x..<y`?
    //
    //   We have two choices:
    //
    //   a) Replace the non-empty pairs (those with indexes) and leave the empty pairs intact.
    //      This is bad, because the empty pairs end up accumulating and you can't easily remove them.
    //        "url:/?one=a&&&two=b&&&&three=c" -> (remove middle pair) -> "url:/?one=a&&&&&&&three=c"
    //
    //   b) Replace the region of the string from the start of x's key, up to the start of y's key,
    //      and removing any empty pairs in that space.
    //        "url:/?one=a&&&two=b&&&&three=c" -> (remove middle pair) -> "url:/?one=a&&&three=c"
    //                       | x |    |  y  |
    //                       | x..<y |
    //
    //   We don't expect empty pairs to have meaning or be worth preserving, therefore we choose (b).
    //   For replacements, this means:
    //
    //     1. Any empty pairs before the start of x's key are not modified by the operation,
    //        nor are any empty pairs after the start of y's key.
    //
    //     2. When replacing `x..<y` with a non-empty list of pairs,
    //        there will always be one delimiter before the start of y's key.
    //
    //   However, there are some special cases:
    //
    //     3. Empty pairs at the start of the string ("?&&&first=...") occupy positions before the list's startIndex,
    //        so there would be no 'replaceSubrange' operation that would remove them.
    //
    //        This can be very awkward, leading to accumulation as in situation (a) - so instead,
    //        replacements involving 'startIndex' snap to the start of the URL component string,
    //        and will replace content before the first indexed pair.
    //
    //        This leads to an interesting situation where 'replaceSubrange(0..<0, with: [])' is NOT always a no-op.
    //
    //     4. When appending, if the existing content ends with a trailing pair delimiter, we reuse it.
    //          "url:/?foo&" -> (append "bar") -> "url:/?foo&bar" NOT "url:/?foo&&bar"
    //                                                      ^                   ^^
    //
    //   Examples of this happening can be seen in the strings below, annotated [1], [2], [3], and [4].
    //
    // - Special Characters in existing content.
    //
    //   Notwithstanding [3] above, content outside of the range `x..<y` should not be modified by the operation.
    //   The existing content in this URL is full of special characters which are tolerated without escaping,
    //   but would be percent-encoded by the form-encoding schema. It should be preserved exactly.

    let s = "[+^x%`/?]~"
    _testReplaceSubrange(
      url: "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        //             [3]
        "http://example/?first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",

        "http://example/?inserted=one&\(Self.SpecialCharacters_Escaped_Form)=two&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        //                                            [1]                                                                   [2]
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&inserted=one&another%20insert=\(Self.SpecialCharacters_Escaped_Form)&third\(s)=2&&&fourth\(s)=3&&&#frag",
        //                                                                         [4]
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&inserted=one&another%20insert=two#frag",

        "http://example/?third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&#frag",

        "http://example/?shrink=start&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&shrink=\(Self.SpecialCharacters_Escaped_Form)&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&shrink=end#frag",

        "http://example/?grow=start&grow%20s=sp%20ace&\(Self.SpecialCharacters_Escaped_Form)=%F0%9F%A5%B8&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&grow=mid&%F0%9F%8C%B1=%F0%9F%8C%BB&grow=\(Self.SpecialCharacters_Escaped_Form)&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&grow=end&=noname&=#frag",
      ]
    )
  }

  /// Tests using `replaceSubrange(_:with:)` to replace a contiguous region of key-value pairs.
  ///
  /// This test covers replacements over the range `kvps.startIndex..<kvps.endIndex`.
  ///
  /// **Replacement Pairs**:
  ///
  /// 1. An empty collection
  /// 2. A single key-value pair
  /// 3. A collection of multiple key-value pairs.
  ///
  /// **Initial list of pairs**:
  ///
  /// 1. Empty, or
  /// 2. Non-empty
  ///
  /// In any of the ways that can occur (nil component/empty component/string of empty pairs).
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testReplaceSubrange_fullReplacement() {

    func _testReplaceSubrange(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      // Replace everything with an empty collection.

      do {
        var url = url
        let range = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let range = kvps.replaceSubrange(kvps.startIndex..<kvps.endIndex, with: EmptyCollection<(String, String)>())
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return range
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqual(kvps.startIndex..<kvps.endIndex, range)
        XCTAssertEqual(range.upperBound, range.lowerBound)
        for kvp in kvps { XCTFail("Unexpected pair: \(kvp)") }

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
        XCTAssertEqual(kvps.startIndex..<kvps.endIndex, range)
        XCTAssertEqualKeyValuePairs(kvps, newContent)

        XCTAssertEqual(url.serialized(), checkpoints[1])
      }

      // Replace everything with a collection of multiple pairs.

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
        XCTAssertEqual(kvps.startIndex..<kvps.endIndex, range)
        XCTAssertEqualKeyValuePairs(kvps, newContent)

        XCTAssertEqual(url.serialized(), checkpoints[2])
      }
    }

    // Form encoded in the query.
    // Initial query = nil.

    _testReplaceSubrange(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (2).
    // Initial query = empty string.

    _testReplaceSubrange(
      url: "http://example/?#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (3).
    // Initial query = non-empty string, empty list of pairs.

    _testReplaceSubrange(
      url: "http://example/?&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (4).
    // Initial query = non-empty list of pairs.

    _testReplaceSubrange(
      url: "http://example/?foo=bar&baz=qux#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (5).
    // Initial query = non-empty list of pairs. Component includes leading and trailing empty pairs.
    // Semicolons are also allowed as pair delimiters.

    _testReplaceSubrange(
      url: "http://example/?;;;foo=bar&;&baz=qux&;&#frag",
      component: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true), checkpoints: [
        "http://example/#frag",
        "http://example/?hello=world#frag",
        "http://example/?hello=world&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&the%20key=sp%20ace#frag",
      ]
    )

    // Custom schema in the fragment.

    _testReplaceSubrange(
      url: "http://example/?srch#,,frag:ment,stuff",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch",
        "http://example/?srch#hello:world",
        "http://example/?srch#hello:world,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),the%20key:sp%20ace",
      ]
    )
  }
}

// insert(contentsOf:at:), insert(key:value:at:)

extension KeyValuePairsTests {

  /// Tests using `insert(contentsOf:at:)` to insert a Collection of key-value pairs.
  ///
  /// The key-value pairs have interesting features, such as special characters,
  /// empty key names or values, Unicode, etc.
  ///
  /// **Inserted pairs**:
  ///
  /// 1. Multiple pairs
  /// 2. A single pair
  /// 3. No pairs (an empty collection)
  ///
  /// **Insertion Point**:
  ///
  /// 1. At the start of the list
  /// 2. In the middle of the list
  /// 3. At the end of the list (appending)
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testInsertCollection() {

    func _testInsertCollection(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

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

        let kvps = url.keyValuePairs(in: component, schema: schema)
        let expectedNewPairs = newPairs.map { KeyValuePair(key: $0.0, value: $0.1) }

        // Check that the returned indexes are at the expected offsets,
        // and contain the expected new pairs.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), newPairIndexes.lowerBound)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset + newPairs.count), newPairIndexes.upperBound)
        XCTAssertEqualKeyValuePairs(kvps[newPairIndexes], expectedNewPairs)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.insert(contentsOf: expectedNewPairs, at: offset)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      var result: WebURL

      let pairsToInsert = [
        ("inserted", "some value"),
        (Self.SpecialCharacters, Self.SpecialCharacters),
        ("", ""),
        ("cafe\u{0301}", "caf\u{00E9}")
      ]

      // Insert multiple elements at the front.
      result = insert(pairsToInsert, atOffset: 0)
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Insert multiple elements in the middle.
      result = insert(pairsToInsert, atOffset: min(initialPairs.count, 1))
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Insert multiple elements at the end.
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

    // Form-encoded in the query.
    // Initial query = nil.

    _testInsertCollection(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?some=element#frag",
        "http://example/?some=element#frag",
        "http://example/?some=element#frag",

        "http://example/#frag",
        "http://example/#frag",
        "http://example/#frag",
      ]
    )

    // Form-encoded in the query (2).
    // Initial query = empty string.

    _testInsertCollection(
      url: "http://example/?#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?some=element#frag",
        "http://example/?some=element#frag",
        "http://example/?some=element#frag",

        "http://example/#frag",
        "http://example/#frag",
        "http://example/#frag",
      ]
    )

    // Form-encoded in the query (3).
    // Initial query = non-empty string, empty list of pairs.

    _testInsertCollection(
      url: "http://example/?&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?some=element#frag",
        "http://example/?some=element#frag",
        "http://example/?some=element#frag",

        "http://example/#frag",
        "http://example/#frag",
        "http://example/#frag",
      ]
    )

    // Form-encoded in the query (4).
    // Initial query = non-empty list of pairs. Inserted spaces are encoded using "+" signs.

    _testInsertCollection(
      url: "http://example/?foo=bar&baz=qux#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?inserted=some+value&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&=&cafe%CC%81=caf%C3%A9&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&inserted=some+value&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&=&cafe%CC%81=caf%C3%A9&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&inserted=some+value&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&=&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?some=element&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&some=element&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&some=element#frag",

        "http://example/?foo=bar&baz=qux#frag",
        "http://example/?foo=bar&baz=qux#frag",
        "http://example/?foo=bar&baz=qux#frag",
      ]
    )

    // Form-encoded in the query (5).
    // Initial query = non-empty list of pairs. Component includes empty pairs.

    _testInsertCollection(
      url: "http://example/?&&&foo=bar&&&baz=qux&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&inserted=some%20value&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&=&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?some=element&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&some=element&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&some=element#frag",

        "http://example/?foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&#frag",
      ]
    )

    // Custom schema in the fragment.

    _testInsertCollection(
      url: "http://example/?srch#frag:ment,stuff",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#inserted:some%20value,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),:,cafe%CC%81:caf%C3%A9,frag:ment,stuff",
        "http://example/?srch#frag:ment,inserted:some%20value,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),:,cafe%CC%81:caf%C3%A9,stuff",
        "http://example/?srch#frag:ment,stuff,inserted:some%20value,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),:,cafe%CC%81:caf%C3%A9",

        "http://example/?srch#some:element,frag:ment,stuff",
        "http://example/?srch#frag:ment,some:element,stuff",
        "http://example/?srch#frag:ment,stuff,some:element",

        "http://example/?srch#frag:ment,stuff",
        "http://example/?srch#frag:ment,stuff",
        "http://example/?srch#frag:ment,stuff",
      ]
    )
  }

  /// Tests using `insert(key:value:at:)` to insert a single key-value pair.
  ///
  /// The inserted pairs have interesting features, such as special characters,
  /// empty key names or values, Unicode, etc.
  ///
  /// **Insertion Points**:
  ///
  /// 1. At the start of the list
  /// 2. In the middle of the list
  /// 3. At the end of the list (appending)
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testInsertOne() {

    func _testInsertOne(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

      func insert(_ newPair: (String, String), atOffset offset: Int) -> WebURL {

        var url = url
        let newPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let insertionPoint = kvps.index(kvps.startIndex, offsetBy: offset)
          let newPairIndexes = kvps.insert(key: newPair.0, value: newPair.1, at: insertionPoint)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return newPairIndexes
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        let expectedNewPair = KeyValuePair(key: newPair.0, value: newPair.1)

        // Check that the returned indexes are at the expected offsets,
        // and contain the expected new pairs.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), newPairIndexes.lowerBound)
        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset + 1), newPairIndexes.upperBound)
        XCTAssertEqualKeyValuePairs(kvps[newPairIndexes], [expectedNewPair])

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.insert(expectedNewPair, at: offset)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

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
        var result = insert(pair, atOffset: 0)
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

    // Form-encoded in the query.
    // Initial query = nil.

    _testInsertOne(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value#frag",
        "http://example/?inserted=some%20value#frag",
        "http://example/?inserted=some%20value#frag",

        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",

        "http://example/?=#frag",
        "http://example/?=#frag",
        "http://example/?=#frag",
      ]
    )

    // Form-encoded in the query (2).
    // Initial query = empty string.

    _testInsertOne(
      url: "http://example/?#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value#frag",
        "http://example/?inserted=some%20value#frag",
        "http://example/?inserted=some%20value#frag",

        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",

        "http://example/?=#frag",
        "http://example/?=#frag",
        "http://example/?=#frag",
      ]
    )

    // Form-encoded in the query (3).
    // Initial query = non-empty string, empty list of pairs.

    _testInsertOne(
      url: "http://example/?&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value#frag",
        "http://example/?inserted=some%20value#frag",
        "http://example/?inserted=some%20value#frag",

        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",
        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)#frag",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=#frag",

        "http://example/?=#frag",
        "http://example/?=#frag",
        "http://example/?=#frag",
      ]
    )

    // Form-encoded in the query (4).
    // Initial query = non-empty list of pairs. Inserted spaces are encoded using "+" signs.

    _testInsertOne(
      url: "http://example/?foo=bar&baz=qux#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?inserted=some+value&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&inserted=some+value&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&inserted=some+value#frag",

        "http://example/?cafe%CC%81=caf%C3%A9&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&cafe%CC%81=caf%C3%A9&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form_Plus)&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&=\(Self.SpecialCharacters_Escaped_Form_Plus)&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&=\(Self.SpecialCharacters_Escaped_Form_Plus)#frag",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form_Plus)=&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&\(Self.SpecialCharacters_Escaped_Form_Plus)=&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&\(Self.SpecialCharacters_Escaped_Form_Plus)=#frag",

        "http://example/?=&foo=bar&baz=qux#frag",
        "http://example/?foo=bar&=&baz=qux#frag",
        "http://example/?foo=bar&baz=qux&=#frag",
      ]
    )

    // Form-encoded in the query (5).
    // Initial query = non-empty list of pairs. Component includes empty pairs.

    _testInsertOne(
      url: "http://example/?&&&foo=bar&&&baz=qux&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?inserted=some%20value&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&inserted=some%20value&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&inserted=some%20value#frag",

        "http://example/?cafe%CC%81=caf%C3%A9&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&cafe%CC%81=caf%C3%A9&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&cafe%CC%81=caf%C3%A9#frag",

        "http://example/?=\(Self.SpecialCharacters_Escaped_Form)&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&=\(Self.SpecialCharacters_Escaped_Form)&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&=\(Self.SpecialCharacters_Escaped_Form)#frag",

        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&\(Self.SpecialCharacters_Escaped_Form)=&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&\(Self.SpecialCharacters_Escaped_Form)=#frag",

        "http://example/?=&foo=bar&&&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&=&baz=qux&&&#frag",
        "http://example/?&&&foo=bar&&&baz=qux&&&=#frag",
      ]
    )

    // Custom schema in the fragment.

    _testInsertOne(
      url: "http://example/?srch#frag:ment,stuff",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#inserted:some%20value,frag:ment,stuff",
        "http://example/?srch#frag:ment,inserted:some%20value,stuff",
        "http://example/?srch#frag:ment,stuff,inserted:some%20value",

        "http://example/?srch#cafe%CC%81:caf%C3%A9,frag:ment,stuff",
        "http://example/?srch#frag:ment,cafe%CC%81:caf%C3%A9,stuff",
        "http://example/?srch#frag:ment,stuff,cafe%CC%81:caf%C3%A9",

        "http://example/?srch#:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),frag:ment,stuff",
        "http://example/?srch#frag:ment,:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),stuff",
        "http://example/?srch#frag:ment,stuff,:\(Self.SpecialCharacters_Escaped_CommaSep_Frag)",

        "http://example/?srch#\(Self.SpecialCharacters_Escaped_CommaSep_Frag):,frag:ment,stuff",
        "http://example/?srch#frag:ment,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):,stuff",
        "http://example/?srch#frag:ment,stuff,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):",

        "http://example/?srch#:,frag:ment,stuff",
        "http://example/?srch#frag:ment,:,stuff",
        "http://example/?srch#frag:ment,stuff,:",
      ]
    )
  }
}

// removeSubrange(_:), remove(at:)

extension KeyValuePairsTests {

  /// Tests using `removeSubrange(_:)` to remove a contiguous region of key-value pairs.
  ///
  /// **Range locations**:
  ///
  /// - Anchored to the start
  /// - Not anchored (floating in the middle)
  /// - Anchored to the end
  ///
  /// **Range sizes**:
  ///
  /// - Empty
  /// - Non-empty
  /// - All elements (`startIndex..<endIndex`)
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testRemoveSubrange() {

    func _testRemoveSubrange(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

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

        // Check that the returned indexes are at the expected offsets,
        // and contain the expected new pairs.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offsets.upperBound - offsets.count), idx)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.removeSubrange(offsets)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      var result: WebURL

      // Remove non-empty range from the front.
      result = remove(offsets: 0..<2)
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Remove non-empty range from the middle.
      result = remove(offsets: 2..<3)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Remove non-empty range from the end.
      result = remove(offsets: max(initialPairs.count - 2, 0)..<initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Remove empty range at front.
      result = remove(offsets: 0..<0)
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Remove empty range in the middle.
      result = remove(offsets: 1..<1)
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Remove empty range at end.
      result = remove(offsets: initialPairs.count..<initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[5])

      // Remove all pairs.
      result = remove(offsets: 0..<initialPairs.count)
      XCTAssertEqual(result.serialized(), checkpoints[6])
    }

    // Form-encoding in the query.
    // Initial query = nil.

    do {
      var url = WebURL("http://example.com/#frag")!
      let idx = url.queryParams.removeSubrange(..<url.queryParams.endIndex)
      XCTAssertEqual(url.queryParams.startIndex, idx)
      XCTAssertEqual(url.queryParams.endIndex, idx)
      XCTAssertEqual(url.serialized(), "http://example.com/#frag")
    }

    // Form-encoding in the query (2).
    // Initial query = empty string.

    do {
      var url = WebURL("http://example.com/?#frag")!
      let idx = url.queryParams.removeSubrange(..<url.queryParams.endIndex)
      XCTAssertEqual(url.queryParams.startIndex, idx)
      XCTAssertEqual(url.queryParams.endIndex, idx)
      XCTAssertEqual(url.serialized(), "http://example.com/#frag")
    }

    // Form-encoding in the query (3).
    // Initial query = non-empty string, empty list of pairs.

    do {
      var url = WebURL("http://example.com/?&&&#frag")!
      let idx = url.queryParams.removeSubrange(..<url.queryParams.endIndex)
      XCTAssertEqual(url.queryParams.startIndex, idx)
      XCTAssertEqual(url.queryParams.endIndex, idx)
      XCTAssertEqual(url.serialized(), "http://example.com/#frag")
    }

    // Form-encoding in the query (4).
    // Initial query = non-empty list of pairs.

    _testRemoveSubrange(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?third=2&fourth=3#frag",
        "http://example/?first=0&second=1&fourth=3#frag",
        "http://example/?first=0&second=1#frag",

        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2&fourth=3#frag",

        "http://example/#frag",
      ]
    )

    // Form-encoding in the query (5).
    // Initial query = non-empty list of pairs. Component includes empty pairs.

    _testRemoveSubrange(
      url: "http://example/?&&&first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&#frag",

        // Removing empty range from the front removes leading delimiters (consistent with replaceSubrange).
        "http://example/?first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",
        "http://example/?&&&first=0&&&second=1&&&third=2&&&fourth=3&&&#frag",

        "http://example/#frag",
      ]
    )

    // Custom schema in the fragment.

    _testRemoveSubrange(
      url: "http://example/?srch#first:0,second:1,third:2,fourth:3",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#third:2,fourth:3",
        "http://example/?srch#first:0,second:1,fourth:3",
        "http://example/?srch#first:0,second:1",

        "http://example/?srch#first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3",
        "http://example/?srch#first:0,second:1,third:2,fourth:3",

        "http://example/?srch",
      ]
    )
  }

  /// Tests using `remove(at:)` to remove a single key-value pair at a given location.
  ///
  /// **Removal locations**:
  ///
  /// - At the start
  /// - In the middle
  /// - At the end
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testRemoveOne() {

    func _testRemoveOne(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

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

        // Check that the returned indexes are at the expected offsets,
        // and contain the expected new pairs.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), idx)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.remove(at: offset)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

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

    // Form-encoding in the query.
    // Initial query = non-empty list of pairs.

    _testRemoveOne(
      url: "http://example/?first=0&second=1&third=2&fourth=3#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?second=1&third=2&fourth=3#frag",
        "http://example/?first=0&third=2&fourth=3#frag",
        "http://example/?first=0&second=1&third=2#frag",
      ]
    )

    // Form-encoding in the query (2).
    // Initial query = non-empty list of pairs. Component includes empty pairs.

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

// removeAll(in:where:)

extension KeyValuePairsTests {

  /// Tests using `removeAll(in:where:)` to remove key-value pairs in a given range which match a predicate.
  ///
  /// Tests a variety of empty and non-empty ranges at various points within the list,
  /// including full- and single-element ranges, with always-true and always-false predicates.
  /// Also tests some more interesting predicates which depend on the decoded content of the key-value pairs.
  ///
  /// Finally, tests that the predicate visits only elements within the given range, and in the correct order.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters,
  /// 3. With empty pairs inserted at various points in the URL component, and
  /// 4. With over-encoded content.
  ///
  func testRemoveAllWhere() {

    func _testRemoveWhereElement<Schema>(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let initialCount = initialPairs.count
      precondition(initialCount >= 4, "Minimum 4 pairs needed for this test")

      func remove(in range: Range<Int>, where predicate: (WebURL.KeyValuePairs<Schema>.Element) -> Bool) -> WebURL {

        var copy = url
        copy.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let lower = kvps.index(kvps.startIndex, offsetBy: range.lowerBound)
          let upper = kvps.index(kvps.startIndex, offsetBy: range.upperBound)
          kvps.removeAll(in: lower..<upper, where: predicate)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
        }
        XCTAssertURLIsIdempotent(copy)

        return copy
      }

      var result: WebURL

      // Empty Range. The predicate should never be invoked.
      // Should not remove any pairs.

      do {
        // At startIndex.
        result = remove(in: 0..<0, where: { _ in XCTFail(); return true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[0])

        // In the middle.
        result = remove(in: 1..<1, where: { _ in XCTFail(); return true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[1])

        // At endIndex.
        result = remove(in: initialCount..<initialCount, where: { _ in XCTFail(); return true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[2])
      }

      // Non-empty Range; Predicate always 'false'.
      // Should not remove any pairs.

      do {
        // From startIndex.
        result = remove(in: 0..<1, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[3])

        result = remove(in: 0..<2, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[4])

        result = remove(in: 0..<3, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[5])
        
        result = remove(in: 0..<initialCount, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[6])

        // In the middle.
        result = remove(in: 1..<2, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[7])

        result = remove(in: 1..<3, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[8])

        result = remove(in: 1..<initialCount, where: { _ in false })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs)
        XCTAssertEqual(result.serialized(), checkpoints[9])
      }

      // Non-empty Range; Predicate always 'true'.
      // Should remove all pairs in range.

      do {
        // From startIndex.
        result = remove(in: 0..<1, where: { _ in true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs[1...])
        XCTAssertEqual(result.serialized(), checkpoints[10])

        result = remove(in: 0..<2, where: { _ in true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs[2...])
        XCTAssertEqual(result.serialized(), checkpoints[11])

        result = remove(in: 0..<3, where: { _ in true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), initialPairs[3...])
        XCTAssertEqual(result.serialized(), checkpoints[12])

        result = remove(in: 0..<initialCount, where: { _ in true })
        XCTAssertEqualKeyValuePairs(result.keyValuePairs(in: component, schema: schema), EmptyCollection())
        XCTAssertEqual(result.serialized(), checkpoints[13])

        // In the middle.
        result = remove(in: 1..<2, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[14])

        result = remove(in: 1..<3, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[15])

        result = remove(in: 1..<initialCount, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[16])

        result = remove(in: 2..<3, where: { _ in true })
        XCTAssertEqual(result.serialized(), checkpoints[17])
      }

      // Non-empty Range; remove every other pair.

      do {
        // From startIndex.
        var didRemove = true
        result = remove(in: 0..<initialCount) { _ in
          didRemove.toggle()
          return didRemove
        }
        XCTAssertEqual(result.serialized(), checkpoints[18])

        // From the middle.
        didRemove = true
        result = remove(in: 1..<initialCount) { _ in
          didRemove.toggle()
          return didRemove
        }
        XCTAssertEqual(result.serialized(), checkpoints[19])
      }

      // Non-empty Range; remove based on decoded key/value.

      do {
        result = remove(in: 0..<initialCount, where: { kvp in kvp.key.starts(with: "b") })
        XCTAssertEqual(result.serialized(), checkpoints[20])

        result = remove(in: 0..<initialCount, where: { kvp in kvp.key == "sp ace" })
        XCTAssertEqual(result.serialized(), checkpoints[21])

        result = remove(in: 0..<initialCount, where: { kvp in kvp.value.starts(with: "q") })
        XCTAssertEqual(result.serialized(), checkpoints[22])
      }

      // Check that the predicate visits only the expected KVPs, and in the correct order.

      func _checkKVPsVisitedByPredicate(in offsets: Range<Int>) {
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
        let expected = Array(initialPairs.dropFirst(offsets.lowerBound).prefix(offsets.count))
        XCTAssertEqual(expected, seen)
      }

      _checkKVPsVisitedByPredicate(in: 0..<initialCount)
      _checkKVPsVisitedByPredicate(in: 1..<initialCount)
      _checkKVPsVisitedByPredicate(in: 0..<initialCount - 1)
      _checkKVPsVisitedByPredicate(in: 1..<initialCount - 1)
      _checkKVPsVisitedByPredicate(in: 0..<0)
      _checkKVPsVisitedByPredicate(in: 1..<1)
      _checkKVPsVisitedByPredicate(in: initialCount..<initialCount)
    }

    // Form-encoded in the query.

    _testRemoveWhereElement(
      url: "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Empty range.
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",

        // Remove nothing (predicate = false).
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp+ace#frag",

        // Remove all in range (predicate = true).
        "http://example/p?baz=qux&qax=qaz&sp+ace#frag",
        "http://example/p?qax=qaz&sp+ace#frag",
        "http://example/p?sp+ace#frag",
        "http://example/p#frag",
        "http://example/p?foo=bar&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&sp+ace#frag",
        "http://example/p?foo=bar#frag",
        "http://example/p?foo=bar&baz=qux&sp+ace#frag",

        // Remove every other pair.
        "http://example/p?foo=bar&qax=qaz#frag",
        "http://example/p?foo=bar&baz=qux&sp+ace#frag",

        // Remove based on decoded key/value.
        "http://example/p?foo=bar&qax=qaz&sp+ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz#frag",
        "http://example/p?foo=bar&sp+ace#frag",
      ]
    )

    // Percent-encoded in the query.
    // Keys and values are over-encoded. Non-removed pairs should be retained as they are.

    _testRemoveWhereElement(
      url: "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        // Empty range.
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",

        // Remove nothing (predicate = false).
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",

        // Remove all in range (predicate = true).
        "http://example/p?%62%61%7A=%71%75%78&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%73%70%20%61%63%65#frag",
        "http://example/p#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%73%70%20%61%63%65#frag",

        // Remove every other pair.
        "http://example/p?%66%6f%6F=%62%61%72&%71%61%78=%71%61%7A#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%73%70%20%61%63%65#frag",

        // Remove based on decoded key/value.
        "http://example/p?%66%6f%6F=%62%61%72&%71%61%78=%71%61%7A&%73%70%20%61%63%65#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%62%61%7A=%71%75%78&%71%61%78=%71%61%7A#frag",
        "http://example/p?%66%6f%6F=%62%61%72&%73%70%20%61%63%65#frag",
      ]
    )

    // Form-encoding in the query (2).
    // Component includes empty pairs.

    _testRemoveWhereElement(
      url: "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Empty range.
        // `startIndex..<startIndex` trims empty pairs in order to be consistent with removeSubrange.
        "http://example/p?foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",

        // Remove nothing (predicate = false).
        // Empty pairs within the range are removed, but no elements of the list are removed.
        "http://example/p?foo=bar&baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp%20ace&&&#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz&sp%20ace#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&qax=qaz&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&qax=qaz&sp%20ace#frag",

        // Remove all in range (predicate = true).
        "http://example/p?baz=qux&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?sp%20ace&&&#frag",
        "http://example/p#frag",
        "http://example/p?&&&foo=bar&&&qax=qaz&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&&sp%20ace&&&#frag",
        "http://example/p?&&&foo=bar&&#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&&&sp%20ace&&&#frag",

        // Remove every other pair.
        "http://example/p?foo=bar&qax=qaz#frag",
        "http://example/p?&&&foo=bar&&&baz=qux&sp%20ace#frag",

        // Remove based on decoded key/value.
        "http://example/p?foo=bar&qax=qaz&sp%20ace#frag",
        "http://example/p?foo=bar&baz=qux&qax=qaz#frag",
        "http://example/p?foo=bar&sp%20ace#frag",
      ]
    )

    // Custom schema in the fragment.

    _testRemoveWhereElement(
      url: "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        // Empty range.
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",

        // Remove nothing (predicate = false).
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz,sp%20ace",

        // Remove all in range (predicate = true).
        "http://example/p?q#baz:qux,qax:qaz,sp%20ace",
        "http://example/p?q#qax:qaz,sp%20ace",
        "http://example/p?q#sp%20ace",
        "http://example/p?q",
        "http://example/p?q#foo:bar,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,sp%20ace",
        "http://example/p?q#foo:bar",
        "http://example/p?q#foo:bar,baz:qux,sp%20ace",

        // Remove every other pair.
        "http://example/p?q#foo:bar,qax:qaz",
        "http://example/p?q#foo:bar,baz:qux,sp%20ace",

        // Remove based on decoded key/value.
        "http://example/p?q#foo:bar,qax:qaz,sp%20ace",
        "http://example/p?q#foo:bar,baz:qux,qax:qaz",
        "http://example/p?q#foo:bar,sp%20ace",
      ]
    )
  }

  /// Tests that `removeSubrange(lower..<upper)` and `removeAll(in: lower..<upper, where: { _ in true })`
  /// produce the same result.
  ///
  /// Tests empty, single-element, and non-empty ranges at the start, middle, and end of the list.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testRemoveWhereRemoveSubrangeCompatibility() {

    func _testRemoveCompatibility(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialCount = url.keyValuePairs(in: component, schema: schema).count
      precondition(initialCount >= 3, "Minimum 3 pairs required for this test")

      func removeWhere(_ offset: Range<Int>) -> WebURL {
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

      func removeSubrange(_ offset: Range<Int>) -> WebURL {
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

      var checkpointIdx = 0

      for start in 0...2 {
        for end in start...initialCount {
          let resultRW = removeWhere(start..<end)
          let resultRS = removeSubrange(start..<end)
          XCTAssertEqual(resultRW.serialized(), checkpoints[checkpointIdx])
          XCTAssertEqual(resultRS.serialized(), checkpoints[checkpointIdx])
          checkpointIdx += 1
        }
      }

      // Remove last (non-empty range ending at endIndex)

      var resultRW = removeWhere(initialCount - 1..<initialCount)
      var resultRS = removeSubrange(initialCount - 1..<initialCount)
      XCTAssertEqual(resultRW.serialized(), checkpoints[checkpointIdx])
      XCTAssertEqual(resultRS.serialized(), checkpoints[checkpointIdx])
      checkpointIdx += 1

      // Remove empty range at endIndex.

      resultRW = removeWhere(initialCount..<initialCount)
      resultRS = removeSubrange(initialCount..<initialCount)
      XCTAssertEqual(resultRW.serialized(), checkpoints[checkpointIdx])
      XCTAssertEqual(resultRS.serialized(), checkpoints[checkpointIdx])
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

    // Form-encoding in the query (2).
    // Component includes empty pairs.

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

    // Custom schema in the fragment.

    _testRemoveCompatibility(
      url: "http://example/p?srch#foo:bar,baz:qux,qax:qaz,sp+ace",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/p?srch#foo:bar,baz:qux,qax:qaz,sp+ace",
        "http://example/p?srch#baz:qux,qax:qaz,sp+ace",
        "http://example/p?srch#qax:qaz,sp+ace",
        "http://example/p?srch#sp+ace",
        "http://example/p?srch",

        "http://example/p?srch#foo:bar,baz:qux,qax:qaz,sp+ace",
        "http://example/p?srch#foo:bar,qax:qaz,sp+ace",
        "http://example/p?srch#foo:bar,sp+ace",
        "http://example/p?srch#foo:bar",

        "http://example/p?srch#foo:bar,baz:qux,qax:qaz,sp+ace",
        "http://example/p?srch#foo:bar,baz:qux,sp+ace",
        "http://example/p?srch#foo:bar,baz:qux",

        "http://example/p?srch#foo:bar,baz:qux,qax:qaz",
        "http://example/p?srch#foo:bar,baz:qux,qax:qaz,sp+ace",
      ]
    )
  }
}

// append(contentsOf:), append(key:value:)

extension KeyValuePairsTests {

  /// Tests using `append(contentsOf:)` or the `+=` operator to append a collection of key-value pairs
  /// to the list.
  ///
  /// The appended collection may be empty, or non-empty. If it is non-empty, the key-value pairs
  /// have interesting features, such as special characters, empty key names or values, Unicode, etc.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters,
  /// 3. With empty pairs inserted at various points in the URL component,
  /// 4. With one or more trailing delimiters,
  /// 5. For all overloads of `append(contentsOf:)` and the `+=` operator.
  ///
  func testAppendCollection() {

    func _testAppendCollection<Schema>(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: Schema, checkpoints: [String]
    ) where Schema: KeyValueStringSchema {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let initialCount = initialPairs.count

      func checkAppendSingleOverload<Input>(
        _ newPairs: Input,
        operation: (inout WebURL.KeyValuePairs<Schema>, Input) -> Range<WebURL.KeyValuePairs<Schema>.Index>?,
        expectedResult: String,
        expectedNewPairs: [KeyValuePair]
      ) where Input: Collection {

        var url = url
        let insertedPairIndexes = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let insertedPairIndexes = operation(&kvps, newPairs)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return insertedPairIndexes
        }
        XCTAssertURLIsIdempotent(url)

        XCTAssertEqual(url.serialized(), expectedResult)
        let kvps = url.keyValuePairs(in: component, schema: schema)

        // Check that the returned indexes are at the expected offsets,
        // and contain the expected new pairs.

        if let insertedPairIndexes = insertedPairIndexes {
          XCTAssertEqual(
            kvps.index(kvps.startIndex, offsetBy: initialCount),
            insertedPairIndexes.lowerBound
          )
          XCTAssertEqual(
            kvps.index(kvps.startIndex, offsetBy: initialCount + expectedNewPairs.count),
            insertedPairIndexes.upperBound
          )
          XCTAssertEqual(kvps.endIndex, insertedPairIndexes.upperBound)
          XCTAssertEqualKeyValuePairs(kvps[insertedPairIndexes], expectedNewPairs)
        }

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.append(contentsOf: expectedNewPairs)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)
      }

      func checkAppendAllOverloads(_ newPairs: [(String, String)], checkpointIndex: inout Int) {

        let expectedNewPairs_Tuple = newPairs.map { KeyValuePair(key: $0.0, value: $0.1) }

        // Overload: Unlabelled Tuples.

        checkAppendSingleOverload(
          newPairs,
          operation: { kvps, pairs in kvps.append(contentsOf: pairs) },
          expectedResult: checkpoints[checkpointIndex],
          expectedNewPairs: expectedNewPairs_Tuple
        )

        checkAppendSingleOverload(
          newPairs,
          operation: { kvps, pairs in
            kvps += pairs
            return nil
          },
          expectedResult: checkpoints[checkpointIndex],
          expectedNewPairs: expectedNewPairs_Tuple
        )

        // Overload: Labelled Tuples.
        // Don't use Array because it has special magic which allows implicit stripping/inserting of tuple labels.

        checkAppendSingleOverload(
          newPairs.lazy.map { (key: $0.0, value: $0.1) },
          operation: { kvps, pairs in kvps.append(contentsOf: pairs) },
          expectedResult: checkpoints[checkpointIndex],
          expectedNewPairs: expectedNewPairs_Tuple
        )

        checkAppendSingleOverload(
          newPairs.lazy.map { (key: $0.0, value: $0.1) },
          operation: { kvps, pairs in
            kvps += pairs
            return nil
          },
          expectedResult: checkpoints[checkpointIndex],
          expectedNewPairs: expectedNewPairs_Tuple
        )

        // Overload: Dictionary.
        // If there are duplicate key-value pairs, the first one is kept.

        let dict = Dictionary(newPairs, uniquingKeysWith: { first, _ in first })
        let expectedNewPairs_dict = dict.sorted { $0.key < $1.key }.map { KeyValuePair(key: $0.key, value: $0.value) }

        checkAppendSingleOverload(
          dict,
          operation: { kvps, pairs in kvps.append(contentsOf: pairs) },
          expectedResult: checkpoints[checkpointIndex + 1],
          expectedNewPairs: expectedNewPairs_dict
        )

        checkAppendSingleOverload(
          dict,
          operation: { kvps, pairs in
            kvps += pairs
            return nil
          },
          expectedResult: checkpoints[checkpointIndex + 1],
          expectedNewPairs: expectedNewPairs_dict
        )

        checkpointIndex += 2
      }

      var checkpointIndex = 0

      // Empty collection.
      checkAppendAllOverloads(
        [],
        checkpointIndex: &checkpointIndex
      )

      // Non-empty collection.
      checkAppendAllOverloads(
        [
          ("foo", "bar"),
          ("foo", "baz"),
          ("the key", "sp ace"),
          ("", "emptykey"),
          ("emptyval", ""),
          ("", ""),
          ("cafe\u{0301}", "caf\u{00E9}"),
          (Self.SpecialCharacters, Self.SpecialCharacters),
          ("CAT", "x"),
        ],
        checkpointIndex: &checkpointIndex
      )
    }

    // Form encoded in the query.
    // Initial query = nil.

    _testAppendCollection(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/#frag",

        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x#frag",
        "http://example/?=emptykey&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (2).
    // Initial query = empty string. Inserted spaces are encoded using "+" signs.

    _testAppendCollection(
      url: "http://example/?#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/#frag",
        "http://example/#frag",

        "http://example/?foo=bar&foo=baz&the+key=sp+ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&CAT=x#frag",
        "http://example/?=emptykey&\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the+key=sp+ace#frag",
      ]
    )

    // Form encoded in the query (3).
    // Initial query = non-empty list of pairs. Component includes empty pairs and special characters.

    _testAppendCollection(
      url: "http://example/?&test[+x%?]~=val^_`&&&x:y#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&test[+x%?]~=val^_`&&&x:y#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y#frag",

        "http://example/?&test[+x%?]~=val^_`&&&x:y&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&=emptykey&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (4).
    // Initial query = non-empty string, empty list of pairs.

    _testAppendCollection(
      url: "http://example/?&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/#frag",

        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x#frag",
        "http://example/?=emptykey&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (5).
    // Initial query = non-empty list of pairs. Component ends with a single trailing pair delimiter.
    // The single delimiter is re-used when appending new pairs.

    _testAppendCollection(
      url: "http://example/?test=ok&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test=ok&#frag",
        "http://example/?test=ok&#frag",

        "http://example/?test=ok&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x#frag",
        "http://example/?test=ok&=emptykey&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (6).
    // Initial query = non-empty list of pairs. Component ends with a single trailing key-value delimiter.
    // Since it is not a pair delimiter, it should not be reused.

    _testAppendCollection(
      url: "http://example/?test=#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test=#frag",
        "http://example/?test=#frag",

        "http://example/?test=&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x#frag",
        "http://example/?test=&=emptykey&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Form encoded in the query (7).
    // Initial query = non-empty list of pairs. Component ends with multiple trailing delimiters.
    // Only one trailing delimiter is re-used when appending new pairs.

    _testAppendCollection(
      url: "http://example/?test=ok&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test=ok&&&#frag",
        "http://example/?test=ok&&&#frag",

        "http://example/?test=ok&&&foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x#frag",
        "http://example/?test=ok&&&=emptykey&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Percent encoded in the query.
    // Initial query = nil.

    _testAppendCollection(
      url: "http://example/#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        "http://example/#frag",
        "http://example/#frag",

        "http://example/?foo=bar&foo=baz&the%20key=sp%20ace&=emptykey&emptyval=&=&cafe%CC%81=caf%C3%A9&\(Self.SpecialCharacters_Escaped_PrctEnc_Query)=\(Self.SpecialCharacters_Escaped_PrctEnc_Query)&CAT=x#frag",
        "http://example/?=emptykey&\(Self.SpecialCharacters_Escaped_PrctEnc_Query)=\(Self.SpecialCharacters_Escaped_PrctEnc_Query)&CAT=x&cafe%CC%81=caf%C3%A9&emptyval=&foo=bar&the%20key=sp%20ace#frag",
      ]
    )

    // Custom schema in the fragment.

    _testAppendCollection(
      url: "http://example/?srch",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch",
        "http://example/?srch",

        "http://example/?srch#foo:bar,foo:baz,the%20key:sp%20ace,:emptykey,emptyval:,:,cafe%CC%81:caf%C3%A9,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),CAT:x",
        "http://example/?srch#:emptykey,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),CAT:x,cafe%CC%81:caf%C3%A9,emptyval:,foo:bar,the%20key:sp%20ace",
      ]
    )

    // Custom schema in the fragment (2).
    // Component ends with single trailing delimiter.

    _testAppendCollection(
      url: "http://example/?srch#test:ok,",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#test:ok,",
        "http://example/?srch#test:ok,",

        "http://example/?srch#test:ok,foo:bar,foo:baz,the%20key:sp%20ace,:emptykey,emptyval:,:,cafe%CC%81:caf%C3%A9,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),CAT:x",
        "http://example/?srch#test:ok,:emptykey,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag),CAT:x,cafe%CC%81:caf%C3%A9,emptyval:,foo:bar,the%20key:sp%20ace",
      ]
    )
  }

  /// Tests using `append(key:value:)` to append a single key-value pair to the list.
  ///
  /// The appended pair will have interesting features, such as special characters,
  /// empty key name or value, Unicode, etc.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters,
  /// 3. With empty pairs inserted at various points in the URL component, and
  /// 4. With one or more trailing delimiters.
  ///
  func testAppendOne() {

    func _testAppendOne(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let initialCount = initialPairs.count

      func append(key: String, value: String) -> WebURL {

        var url = url
        let appendedPairIndex = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let appendedPairIndex = kvps.append(key: key, value: value)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return appendedPairIndex
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        let expectedPair = KeyValuePair(key: key, value: value)

        // Check that the returned index is at the expected offset,
        // and contains the expected new pair.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: initialCount), appendedPairIndex)
        XCTAssertEqual(KeyValuePair(kvps[appendedPairIndex]), expectedPair)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList.append(expectedPair)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      var result: WebURL

      result = append(key: "foo", value: "bar")
      XCTAssertEqual(result.serialized(), checkpoints[0])

      result = append(key: "the key", value: "sp ace")
      XCTAssertEqual(result.serialized(), checkpoints[1])

      result = append(key: "", value: "emptykey")
      XCTAssertEqual(result.serialized(), checkpoints[2])

      result = append(key: "emptyval", value: "")
      XCTAssertEqual(result.serialized(), checkpoints[3])

      result = append(key: "", value: "")
      XCTAssertEqual(result.serialized(), checkpoints[4])

      result = append(key: "cafe\u{0301}", value: "caf\u{00E9}")
      XCTAssertEqual(result.serialized(), checkpoints[5])

      result = append(key: Self.SpecialCharacters, value: Self.SpecialCharacters)
      XCTAssertEqual(result.serialized(), checkpoints[6])
    }

    // Form encoded in the query.
    // Initial query = nil.

    _testAppendOne(
      url: "http://example/#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?the%20key=sp%20ace#frag",
        "http://example/?=emptykey#frag",
        "http://example/?emptyval=#frag",
        "http://example/?=#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
      ]
    )

    // Form encoded in the query (2).
    // Initial query = empty string. Inserted spaces are encoded using "+" signs.

    _testAppendOne(
      url: "http://example/?#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?the+key=sp+ace#frag",
        "http://example/?=emptykey#frag",
        "http://example/?emptyval=#frag",
        "http://example/?=#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form_Plus)=\(Self.SpecialCharacters_Escaped_Form_Plus)#frag",
      ]
    )

    // Form encoded in the query (3).
    // Initial query = non-empty list of pairs. Component includes empty pairs and special characters.

    _testAppendOne(
      url: "http://example/?&test[+x%?]~=val^_`&&&x:y#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&test[+x%?]~=val^_`&&&x:y&foo=bar#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&the%20key=sp%20ace#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&=emptykey#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&emptyval=#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&=#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?&test[+x%?]~=val^_`&&&x:y&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
      ]
    )

    // Form encoded in the query (4).
    // Initial query = non-empty string, empty list of pairs.

    _testAppendOne(
      url: "http://example/?&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?the%20key=sp%20ace#frag",
        "http://example/?=emptykey#frag",
        "http://example/?emptyval=#frag",
        "http://example/?=#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
      ]
    )

    // Form encoded in the query (5).
    // Initial query = non-empty list of pairs. Component ends with a single trailing pair delimiter.
    // The single delimiter is re-used when appending new pairs.

    _testAppendOne(
      url: "http://example/?test=ok&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test=ok&foo=bar#frag",
        "http://example/?test=ok&the%20key=sp%20ace#frag",
        "http://example/?test=ok&=emptykey#frag",
        "http://example/?test=ok&emptyval=#frag",
        "http://example/?test=ok&=#frag",
        "http://example/?test=ok&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?test=ok&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
      ]
    )

    // Form encoded in the query (6).
    // Initial query = non-empty list of pairs. Component ends with a single trailing key-value delimiter.
    // Since it is not a pair delimiter, it should not be reused.

    _testAppendOne(
      url: "http://example/?test=#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test=&foo=bar#frag",
        "http://example/?test=&the%20key=sp%20ace#frag",
        "http://example/?test=&=emptykey#frag",
        "http://example/?test=&emptyval=#frag",
        "http://example/?test=&=#frag",
        "http://example/?test=&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?test=&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
      ]
    )

    // Form encoded in the query (7).
    // Initial query = non-empty list of pairs. Component ends with multiple trailing delimiters.
    // Only one trailing delimiter is re-used when appending new pairs.

    _testAppendOne(
      url: "http://example/?test=ok&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?test=ok&&&foo=bar#frag",
        "http://example/?test=ok&&&the%20key=sp%20ace#frag",
        "http://example/?test=ok&&&=emptykey#frag",
        "http://example/?test=ok&&&emptyval=#frag",
        "http://example/?test=ok&&&=#frag",
        "http://example/?test=ok&&&cafe%CC%81=caf%C3%A9#frag",
        "http://example/?test=ok&&&\(Self.SpecialCharacters_Escaped_Form)=\(Self.SpecialCharacters_Escaped_Form)#frag",
      ]
    )

    // Percent encoded in the query.
    // Initial query = nil.

    _testAppendOne(
      url: "http://example/#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        "http://example/?foo=bar#frag",
        "http://example/?the%20key=sp%20ace#frag",
        "http://example/?=emptykey#frag",
        "http://example/?emptyval=#frag",
        "http://example/?=#frag",
        "http://example/?cafe%CC%81=caf%C3%A9#frag",
        "http://example/?\(Self.SpecialCharacters_Escaped_PrctEnc_Query)=\(Self.SpecialCharacters_Escaped_PrctEnc_Query)#frag",
      ]
    )

    // Custom schema in the fragment.

    _testAppendOne(
      url: "http://example/?srch",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#foo:bar",
        "http://example/?srch#the%20key:sp%20ace",
        "http://example/?srch#:emptykey",
        "http://example/?srch#emptyval:",
        "http://example/?srch#:",
        "http://example/?srch#cafe%CC%81:caf%C3%A9",
        "http://example/?srch#\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag)",
      ]
    )

    // Custom schema in the fragment (2).
    // Component ends with single trailing delimiter.

    _testAppendOne(
      url: "http://example/?srch#test:ok,",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#test:ok,foo:bar",
        "http://example/?srch#test:ok,the%20key:sp%20ace",
        "http://example/?srch#test:ok,:emptykey",
        "http://example/?srch#test:ok,emptyval:",
        "http://example/?srch#test:ok,:",
        "http://example/?srch#test:ok,cafe%CC%81:caf%C3%A9",
        "http://example/?srch#test:ok,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):\(Self.SpecialCharacters_Escaped_CommaSep_Frag)",
      ]
    )
  }
}

// replaceKey(at:with:), replaceValue(at:with:)

extension KeyValuePairsTests {

  /// Tests using `replaceKey(at:with:)` to replace the key component of a single key-value pair.
  ///
  /// The new key is either an empty string, or an interesting non-empty string (special characters, Unicode, etc).
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters,
  /// 3. With empty pairs inserted at various points in the URL component, and
  /// 4. With pairs containing empty keys and/or values.
  ///
  func testReplaceKeyAt() {

    func _testReplaceKeyAt(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let initialCount = initialPairs.count
      precondition(initialCount >= 3, "Minimum 3 pairs required for this test")

      func replaceKey(atOffset offset: Int, with newKey: String) -> WebURL {

        var url = url
        let (valueComponent, returnedIndex) = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let index = kvps.index(kvps.startIndex, offsetBy: offset)
          let oldValue = kvps[index].encodedValue
          let result = (kvps[index].value, kvps.replaceKey(at: index, with: newKey))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          XCTAssertEqual(kvps[result.1].encodedValue, oldValue)
          return result
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        let expectedPair = KeyValuePair(key: newKey, value: valueComponent)

        // Check that the returned index is at the expected offset,
        // and contains the expected new pair.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), returnedIndex)
        XCTAssertEqual(KeyValuePair(kvps[returnedIndex]), expectedPair)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList[offset].key = newKey
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      var result: WebURL

      // Replace at the front.
      result = replaceKey(atOffset: 0, with: "some replacement")
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Replace in the middle.
      result = replaceKey(atOffset: 1, with: Self.SpecialCharacters)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Replace at the end.
      result = replaceKey(atOffset: initialCount - 1, with: "end key")
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Replace at the front (empty).
      result = replaceKey(atOffset: 0, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Replace in the middle (empty).
      result = replaceKey(atOffset: 1, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Replace at the end (empty).
      result = replaceKey(atOffset: initialCount - 1, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[5])
    }

    // Form encoded in the query.

    _testReplaceKeyAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?some%20replacement=bar&baz=qux&another=value#frag",
        "http://example/?foo=bar&\(Self.SpecialCharacters_Escaped_Form)=qux&another=value#frag",
        "http://example/?foo=bar&baz=qux&end%20key=value#frag",

        "http://example/?=bar&baz=qux&another=value#frag",
        "http://example/?foo=bar&=qux&another=value#frag",
        "http://example/?foo=bar&baz=qux&=value#frag",
      ]
    )

    // Form encoded in the query (2).
    // Inserted spaces are encoded using "+" signs.

    _testReplaceKeyAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?some+replacement=bar&baz=qux&another=value#frag",
        "http://example/?foo=bar&\(Self.SpecialCharacters_Escaped_Form_Plus)=qux&another=value#frag",
        "http://example/?foo=bar&baz=qux&end+key=value#frag",

        "http://example/?=bar&baz=qux&another=value#frag",
        "http://example/?foo=bar&=qux&another=value#frag",
        "http://example/?foo=bar&baz=qux&=value#frag",
      ]
    )

    // Form encoded in the query (3).
    // Component contains empty pairs. Unlike some other APIs, empty pairs are never removed.

    let s = "[+^x%`/?]~"
    _testReplaceKeyAt(
      url: "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&&&some%20replacement=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&\(Self.SpecialCharacters_Escaped_Form)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&end%20key=3&&&#frag",

        "http://example/?&&&=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&=3&&&#frag",
      ]
    )

    // Form encoded in the query (4).
    // Pairs have empty keys and values.

    _testReplaceKeyAt(
      url: "http://example/?=&=&=#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?some%20replacement=&=&=#frag",
        "http://example/?=&\(Self.SpecialCharacters_Escaped_Form)=&=#frag",
        "http://example/?=&=&end%20key=#frag",

        "http://example/?=&=&=#frag",
        "http://example/?=&=&=#frag",
        "http://example/?=&=&=#frag",
      ]
    )

    // Form encoded in the query (5).
    // Pairs do not have any key-value delimiters.
    // When setting the key to the empty string, a delimiter must be inserted.

    _testReplaceKeyAt(
      url: "http://example/?foo&baz&another#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?some%20replacement&baz&another#frag",
        "http://example/?foo&\(Self.SpecialCharacters_Escaped_Form)&another#frag",
        "http://example/?foo&baz&end%20key#frag",

        "http://example/?=&baz&another#frag",
        "http://example/?foo&=&another#frag",
        "http://example/?foo&baz&=#frag",
      ]
    )

    // Custom schema in the fragment.

    _testReplaceKeyAt(
      url: "http://example/?srch#foo:bar,baz:qux,another:value",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#some%20replacement:bar,baz:qux,another:value",
        "http://example/?srch#foo:bar,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):qux,another:value",
        "http://example/?srch#foo:bar,baz:qux,end%20key:value",

        "http://example/?srch#:bar,baz:qux,another:value",
        "http://example/?srch#foo:bar,:qux,another:value",
        "http://example/?srch#foo:bar,baz:qux,:value",
      ]
    )
  }

  /// Tests using `replaceValue(at:with:)` to replace the value component of a single key-value pair.
  ///
  /// The new value is either an empty string, or an interesting non-empty string (special characters, Unicode, etc).
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters,
  /// 3. With empty pairs inserted at various points in the URL component, and
  /// 4. With pairs containing empty keys and/or values.
  ///
  func testReplaceValueAt() {

    func _testReplaceValueAt(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let initialPairs = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }
      let initialCount = initialPairs.count
      precondition(initialCount >= 3, "Minimum 3 pairs required for this test")

      func replaceValue(atOffset offset: Int, with newValue: String) -> WebURL {

        var url = url
        let (keyComponent, returnedIndex) = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let index = kvps.index(kvps.startIndex, offsetBy: offset)
          let oldKey = kvps[index].encodedKey
          let result = (kvps[index].key, kvps.replaceValue(at: index, with: newValue))
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          XCTAssertEqual(kvps[result.1].encodedKey, oldKey)
          return result
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)
        let expectedPair = KeyValuePair(key: keyComponent, value: newValue)

        // Check that the returned index is at the expected offset,
        // and contains the expected new pair.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: offset), returnedIndex)
        XCTAssertEqual(KeyValuePair(kvps[returnedIndex]), expectedPair)

        // Perform the same operation on an Array<KeyValuePair>,
        // and check that our operation is consistent with those semantics.

        var expectedList = initialPairs
        expectedList[offset].value = newValue
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      var result: WebURL

      // Replace at the front.
      result = replaceValue(atOffset: 0, with: "some replacement")
      XCTAssertEqual(result.serialized(), checkpoints[0])

      // Replace in the middle.
      result = replaceValue(atOffset: 1, with: Self.SpecialCharacters)
      XCTAssertEqual(result.serialized(), checkpoints[1])

      // Replace at the end.
      result = replaceValue(atOffset: initialCount - 1, with: "end value")
      XCTAssertEqual(result.serialized(), checkpoints[2])

      // Replace at the front (empty).
      result = replaceValue(atOffset: 0, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[3])

      // Replace in the middle (empty).
      result = replaceValue(atOffset: 1, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[4])

      // Replace at the end (empty).
      result = replaceValue(atOffset: initialCount - 1, with: "")
      XCTAssertEqual(result.serialized(), checkpoints[5])
    }

    // Form-encoded in the query.

    _testReplaceValueAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=some%20replacement&baz=qux&another=value#frag",
        "http://example/?foo=bar&baz=\(Self.SpecialCharacters_Escaped_Form)&another=value#frag",
        "http://example/?foo=bar&baz=qux&another=end%20value#frag",

        "http://example/?foo=&baz=qux&another=value#frag",
        "http://example/?foo=bar&baz=&another=value#frag",
        "http://example/?foo=bar&baz=qux&another=#frag",
      ]
    )

    // Form encoded in the query (2).
    // Inserted spaces are encoded using "+" signs.

    _testReplaceValueAt(
      url: "http://example/?foo=bar&baz=qux&another=value#frag",
      component: .query, schema: ExtendedForm(encodeSpaceAsPlus: true), checkpoints: [
        "http://example/?foo=some+replacement&baz=qux&another=value#frag",
        "http://example/?foo=bar&baz=\(Self.SpecialCharacters_Escaped_Form_Plus)&another=value#frag",
        "http://example/?foo=bar&baz=qux&another=end+value#frag",

        "http://example/?foo=&baz=qux&another=value#frag",
        "http://example/?foo=bar&baz=&another=value#frag",
        "http://example/?foo=bar&baz=qux&another=#frag",
      ]
    )

    // Form encoded in the query (3).
    // Component contains empty pairs. Unlike some other APIs, empty pairs are never removed.

    let s = "[+^x%`/?]~"
    _testReplaceValueAt(
      url: "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?&&&first\(s)=some%20replacement&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=\(Self.SpecialCharacters_Escaped_Form)&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=end%20value&&&#frag",

        "http://example/?&&&first\(s)=&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=&&&third\(s)=2&&&fourth\(s)=3&&&#frag",
        "http://example/?&&&first\(s)=0&&&second\(s)=1&&&third\(s)=2&&&fourth\(s)=&&&#frag",
      ]
    )

    // Form encoded in the query (4).
    // Pairs have empty keys and values.

    _testReplaceValueAt(
      url: "http://example/?=&=&=#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?=some%20replacement&=&=#frag",
        "http://example/?=&=\(Self.SpecialCharacters_Escaped_Form)&=#frag",
        "http://example/?=&=&=end%20value#frag",

        "http://example/?=&=&=#frag",
        "http://example/?=&=&=#frag",
        "http://example/?=&=&=#frag",
      ]
    )

    // Form encoded in the query (5).
    // Pairs do not have any key-value delimiters.

    _testReplaceValueAt(
      url: "http://example/?foo&baz&another#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/?foo=some%20replacement&baz&another#frag",
        "http://example/?foo&baz=\(Self.SpecialCharacters_Escaped_Form)&another#frag",
        "http://example/?foo&baz&another=end%20value#frag",

        "http://example/?foo&baz&another#frag",
        "http://example/?foo&baz&another#frag",
        "http://example/?foo&baz&another#frag",
      ]
    )

    // Custom schema in the fragment.

    _testReplaceValueAt(
      url: "http://example/?srch#foo:bar,baz:qux,another:value",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/?srch#foo:some%20replacement,baz:qux,another:value",
        "http://example/?srch#foo:bar,baz:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),another:value",
        "http://example/?srch#foo:bar,baz:qux,another:end%20value",

        "http://example/?srch#foo:,baz:qux,another:value",
        "http://example/?srch#foo:bar,baz:,another:value",
        "http://example/?srch#foo:bar,baz:qux,another:",
      ]
    )
  }
}


// --------------------------------------------
// MARK: - Reading: By Key
// --------------------------------------------


extension KeyValuePairsTests {

  /// Tests using the key lookup subscripts to find the first value associated with one or more keys.
  ///
  /// Checks looking up:
  ///
  /// - Unique keys
  /// - Duplicate keys
  /// - Not-present keys
  /// - Empty keys
  /// - Keys which need unescaping, and
  /// - Unicode keys
  ///
  /// With the single and batched lookup subscripts.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components, and
  /// 2. Using a variety of schemas with different escaping rules and delimiters.
  ///
  func testKeyLookupSubscript() {

    func _testKeyLookupSubscript(_ kvps: WebURL.KeyValuePairs<some KeyValueStringSchema>) {

      // Check the overall list of pairs is what we expect.

      let expected = [
        (key: "a", value: "b"),
        (key: "sp ac & es", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "👀"),
        (key: "jalapen\u{0303}os", value: "nfd"),
        (key: Self.SpecialCharacters, value: "specials"),
        (key: "dup", value: "f"),
        (key: "jalape\u{00F1}os", value: "nfc"),
        (key: "1+1", value: "2"),
      ]
      XCTAssertEqualKeyValuePairs(kvps, expected)

      // Single key lookup.
      // This should be equivalent to 'kvps.first { $0.key == TheKey }?.value'
      // (in other words, Unicode canonical equivalence of the percent-decoded key, interpreted as UTF-8).

      // Unique key (unescaped).
      XCTAssertEqual(kvps["a"], "b")
      XCTAssertEqual(kvps["emoji"], "👀")

      // Duplicate key (unescaped).
      // Lookup returns the first value.
      XCTAssertEqual(kvps["dup"], "e")

      // Not-present key.
      XCTAssertEqual(kvps["doesNotExist"], nil)
      XCTAssertEqual(kvps["jalapenos"], nil)
      XCTAssertEqual(kvps["DUP"], nil)

      // Empty key/value.
      XCTAssertEqual(kvps[""], "foo")
      XCTAssertEqual(kvps["noval"], "")

      // Keys which need unescaping.
      XCTAssertEqual(kvps["sp ac & es"], "d")
      XCTAssertEqual(kvps["1+1"], "2")
      XCTAssertEqual(kvps[Self.SpecialCharacters], "specials")

      // Unicode keys.
      // Lookup uses canonical equivalence, so these match the same pair.
      XCTAssertEqual(kvps["jalapen\u{0303}os"], "nfd")
      XCTAssertEqual(kvps["jalape\u{00F1}os"], "nfd")

      // Multiple key lookup.
      // Each key should be looked up as above.

      XCTAssertEqual(kvps["dup", "dup"], ("e", "e"))
      XCTAssertEqual(kvps["jalapen\u{0303}os", "emoji", "jalape\u{00F1}os"], ("nfd", "👀", "nfd"))
      XCTAssertEqual(kvps["1+1", "dup", "", "sp ac & es"], ("2", "e", "foo", "d"))
      XCTAssertEqual(kvps["noval", "doesNotExist", "DUP"], ("", nil, nil))
    }

    // Form encoding in the query.

    do {
      let url = WebURL("http://example/?a=b&sp%20ac+%26+es=d&dup=e&=foo&noval&emoji=👀&jalapen\u{0303}os=nfd&\(Self.SpecialCharacters_Escaped_Form)=specials&dup=f&jalape\u{00F1}os=nfc&1%2B1=2#frag")!
      _testKeyLookupSubscript(url.queryParams)
    }

    // Form encoding in the query (2).
    // Semicolons are also allowed as pair delimiters.

    do {
      let url = WebURL("http://example/?a=b&sp%20ac+%26+es=d;dup=e&=foo&noval&emoji=👀;jalapen\u{0303}os=nfd;\(Self.SpecialCharacters_Escaped_Form)=specials&dup=f&jalape\u{00F1}os=nfc&1%2B1=2#frag")!
      _testKeyLookupSubscript(url.keyValuePairs(in: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)))
    }

    // Custom schema in the fragment.

    do {
      let url = WebURL("http://example/?srch#a:b,sp%20ac%20&%20es:d,dup:e,:foo,noval,emoji:👀,jalapen\u{0303}os:nfd,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):specials,dup:f,jalape\u{00F1}os:nfc,1+1:2")!
      _testKeyLookupSubscript(url.keyValuePairs(in: .fragment, schema: CommaSeparated()))
    }
  }

  /// Tests using `allValues(forKey:)` to find all values associated with a given key.
  ///
  /// Checks looking up values for:
  ///
  /// - Unique keys
  /// - Duplicate keys
  /// - Not-present keys
  /// - Empty keys
  /// - Keys which need unescaping, and
  /// - Unicode keys
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components, and
  /// 2. Using a variety of schemas with different escaping rules and delimiters.
  ///
  func testAllValuesForKey() {

    func _testAllValuesForKey(_ kvps: WebURL.KeyValuePairs<some KeyValueStringSchema>) {

      // Check the overall list of pairs is what we expect.

      let expected = [
        (key: "a", value: "b"),
        (key: "sp ac & es", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "👀"),
        (key: "jalapen\u{0303}os", value: "nfd"),
        (key: Self.SpecialCharacters, value: "specials"),
        (key: "dup", value: "f"),
        (key: "jalape\u{00F1}os", value: "nfc"),
        (key: "1+1", value: "2"),
        (key: "DUP", value: "no"),
      ]
      XCTAssertEqualKeyValuePairs(kvps, expected)

      // Unique keys.
      XCTAssertEqual(kvps.allValues(forKey: "sp ac & es"), ["d"])
      XCTAssertEqual(kvps.allValues(forKey: "1+1"), ["2"])
      XCTAssertEqual(kvps.allValues(forKey: Self.SpecialCharacters), ["specials"])

      // Duplicate keys.
      // Values must be in the same order as in the list.
      XCTAssertEqual(kvps.allValues(forKey: "dup"), ["e", "f"])

      // Not-present keys.
      XCTAssertEqual(kvps.allValues(forKey: "doesNotExist"), [])
      XCTAssertEqual(kvps.allValues(forKey: "EMOJI"), [])

      // Empty keys/values.
      XCTAssertEqual(kvps.allValues(forKey: ""), ["foo"])
      XCTAssertEqual(kvps.allValues(forKey: "noval"), [""])

      // Unicode keys.
      // Lookup uses canonical equivalence.
      XCTAssertEqual(kvps.allValues(forKey: "jalapen\u{0303}os"), ["nfd", "nfc"])
      XCTAssertEqual(kvps.allValues(forKey: "jalape\u{00F1}os"), ["nfd", "nfc"])
    }

    // Form encoding in the query.

    do {
      let url = WebURL("http://example/?a=b&sp%20ac+%26+es=d&dup=e&=foo&noval&emoji=👀&jalapen\u{0303}os=nfd&\(Self.SpecialCharacters_Escaped_Form)=specials&dup=f&jalape\u{00F1}os=nfc&1%2B1=2&DUP=no#frag")!
      _testAllValuesForKey(url.queryParams)
    }

    // Form encoding in the query (2).
    // Semi-colons allowed as pair delimiters.

    do {
      let url = WebURL("http://example/?a=b&sp%20ac+%26+es=d;dup=e&=foo&noval&emoji=👀;jalapen\u{0303}os=nfd;\(Self.SpecialCharacters_Escaped_Form)=specials&dup=f&jalape\u{00F1}os=nfc&1%2B1=2&DUP=no#frag")!
      _testAllValuesForKey(url.keyValuePairs(in: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true)))
    }

    // Custom schema in the fragment.

    do {
      let url = WebURL("http://example/?srch#a:b,sp%20ac%20&%20es:d,dup:e,:foo,noval,emoji:👀,jalapen\u{0303}os:nfd,\(Self.SpecialCharacters_Escaped_CommaSep_Frag):specials,dup:f,jalape\u{00F1}os:nfc,1+1:2,DUP:no")!
      _testAllValuesForKey(url.keyValuePairs(in: .fragment, schema: CommaSeparated()))
    }
  }
}


// -------------------------------
// MARK: - Writing: By Key.
// -------------------------------

// set(key:to:)

extension KeyValuePairsTests {

  /// Tests using `set(key:to:)` and key-based subscripts to replace the values associated with a key.
  ///
  /// Checks replacing the values for:
  ///
  /// - Unique keys
  /// - Duplicate keys
  /// - Unicode keys
  /// - Not-present keys
  /// - Empty keys, and
  /// - Keys which need unescaping
  ///
  /// For each of the above, checks using a replacement value of:
  ///
  /// - Non-nil (`set(key:to:)` and subscript)
  /// - Nil (subscript only)
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testSet() {

    func _testSet(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, checkpoints: [String]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      /// Simulates the 'set' operation using an array of key-value pairs,
      /// and returns the expected resulting list of pairs.
      ///
      func _expectedListAfterSetting(key: String, to newValue: String?) -> [KeyValuePair] {

        var expectedList = url.keyValuePairs(in: component, schema: schema).map { KeyValuePair($0) }

        // Setting a nil value should remove all entries with a canonically-equivalent key.

        guard let newValue = newValue else {
          expectedList.removeAll(where: { $0.key == key })
          return expectedList
        }

        // Setting a non-nil value should replace the value of the first matching pair,
        // and remove all other entries. If no pairs match, it should append a new pair.

        if let i = expectedList.firstIndex(where: { $0.key == key }) {
          expectedList[i].value = newValue
          expectedList[(i + 1)...].removeAll(where: { $0.key == key })
        } else {
          expectedList.append(KeyValuePair(key: key, value: newValue))
        }

        return expectedList
      }

      /// Sets a key-value pair using the `set(key:to:)` method.
      ///
      /// The method only accepts non-nil values and returns the index of the matching pair.
      ///
      func _setViaMethod(key: String, to newValue: String, expectedList: [KeyValuePair]) -> WebURL {

        var url = url

        let expectedOffset = url.keyValuePairs(in: component, schema: schema).prefix(while: { $0.key != key }).count
        let returnedIndex = url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          let returnedIndex = kvps.set(key: key, to: newValue)
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
          return returnedIndex
        }
        XCTAssertURLIsIdempotent(url)

        let kvps = url.keyValuePairs(in: component, schema: schema)

        // Check that the returned index is at the expected offset,
        // and contains the expected new pair.

        XCTAssertEqual(kvps.index(kvps.startIndex, offsetBy: expectedOffset), returnedIndex)
        XCTAssertEqual(kvps[returnedIndex].key, key)
        XCTAssertTrue(kvps[returnedIndex].value.utf8.elementsEqual(newValue.utf8))

        // Check that the list has the expected contents.

        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      /// Sets a key-value pair using the key-based subscript.
      ///
      /// The subscript accepts nil as a new value and does not return the index of the matching pair.
      ///
      func _setViaSubscript(key: String, to newValue: String?, expectedList: [KeyValuePair]) -> WebURL {

        var url = url
        url.withMutableKeyValuePairs(in: component, schema: schema) { kvps in
          kvps[key] = newValue
          XCTAssertKeyValuePairCacheIsAccurate(kvps)
        }
        XCTAssertURLIsIdempotent(url)

        // Check that the list has the expected contents.

        let kvps = url.keyValuePairs(in: component, schema: schema)
        XCTAssertEqualKeyValuePairs(kvps, expectedList)

        return url
      }

      /// Tests setting a key to a non-nil value, using both the `set` method and keyed subscript.
      ///
      func setBothWays(key: String, to newValue: String, expectedURL: String) {

        let expectedList = _expectedListAfterSetting(key: key, to: newValue)

        let result_method = _setViaMethod(key: key, to: newValue, expectedList: expectedList)
        let result_subsct = _setViaSubscript(key: key, to: newValue, expectedList: expectedList)

        XCTAssertEqual(result_method, result_subsct)
        XCTAssertEqual(result_method.serialized(), expectedURL)
        XCTAssertEqual(result_subsct.serialized(), expectedURL)
      }

      /// Tests setting a key to nil value, using the keyed subscript only.
      ///
      func setToNil(key: String, expectedURL: String) {

        let expectedList = _expectedListAfterSetting(key: key, to: nil)

        let result = _setViaSubscript(key: key, to: nil, expectedList: expectedList)

        XCTAssertEqual(result.serialized(), expectedURL)
      }

      // Unique key.

      setBothWays(key: Self.SpecialCharacters, to: "found", expectedURL: checkpoints[0])
      setToNil(key: Self.SpecialCharacters, expectedURL: checkpoints[1])

      // First key.

      let firstKey = url.keyValuePairs(in: component, schema: schema).first!.key
      setBothWays(key: firstKey, to: "first", expectedURL: checkpoints[2])
      setToNil(key: firstKey, expectedURL: checkpoints[3])

      // Duplicate key.

      setBothWays(key: "dup", to: Self.SpecialCharacters, expectedURL: checkpoints[4])
      setToNil(key: "dup", expectedURL: checkpoints[5])

      // Unicode key.
      // Both ways of writing the key match the same pairs.
      // Since the key already exists, they produce the same result.

      setBothWays(key: "cafe\u{0301}", to: "unicode", expectedURL: checkpoints[6])
      setBothWays(key: "caf\u{00E9}", to: "unicode", expectedURL: checkpoints[6])
      setToNil(key: "cafe\u{0301}", expectedURL: checkpoints[7])
      setToNil(key: "caf\u{00E9}", expectedURL: checkpoints[7])

      // Non-present key.

      setBothWays(key: "inserted-" + Self.SpecialCharacters, to: "yes", expectedURL: checkpoints[8])
      setToNil(key: "doesNotExist", expectedURL: checkpoints[9])

      // Empty key.

      setBothWays(key: "", to: "empty", expectedURL: checkpoints[10])
      setToNil(key: "", expectedURL: checkpoints[11])

      // New value is the empty string.

      setBothWays(key: Self.SpecialCharacters, to: "", expectedURL: checkpoints[12])

      // Set empty key to the empty string.

      setBothWays(key: "", to: "", expectedURL: checkpoints[13])

      // Remove all keys (subscript only).

      do {
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
    // Unicode key uses the "cafe\u{0301}" formulation.

    _testSet(
      url: "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=found&cafe%CC%81=cheese&dup#frag",
        "http://example/p?foo=bar&dup&=x&dup&cafe%CC%81=cheese&dup#frag",

        "http://example/p?foo=first&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        "http://example/p?dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",

        "http://example/p?foo=bar&dup=\(Self.SpecialCharacters_Escaped_Form)&=x&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",
        "http://example/p?foo=bar&=x&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",

        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=unicode&dup#frag",
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&dup#frag",

        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup&inserted-\(Self.SpecialCharacters_Escaped_Form)=yes#frag",
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",

        "http://example/p?foo=bar&dup&=empty&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
        "http://example/p?foo=bar&dup&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",

        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=&cafe%CC%81=cheese&dup#frag",
        "http://example/p?foo=bar&dup&=&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",

        "http://example/p#frag",
      ]
    )

    // Percent-encoded in the query.
    // Unicode key uses the "caf\u{00E9}" formulation.

    _testSet(
      url: "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
      component: .query, schema: .percentEncoded, checkpoints: [
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)=found&caf%C3%A9=cheese&dup#frag",
        "http://example/p?foo=bar&dup&=x&dup&caf%C3%A9=cheese&dup#frag",

        "http://example/p?foo=first&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        "http://example/p?dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",

        "http://example/p?foo=bar&dup=\(Self.SpecialCharacters_Escaped_PrctEnc_Query)&=x&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese#frag",
        "http://example/p?foo=bar&=x&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese#frag",

        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=unicode&dup#frag",
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&dup#frag",

        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup&inserted-\(Self.SpecialCharacters_Escaped_PrctEnc_Query)=yes#frag",
        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",

        "http://example/p?foo=bar&dup&=empty&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        "http://example/p?foo=bar&dup&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",

        "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",
        "http://example/p?foo=bar&dup&=&dup&\(Self.SpecialCharacters_Escaped_Form)&caf%C3%A9=cheese&dup#frag",

        "http://example/p#frag",
      ]
    )

    // Form-encoded in the query (2).
    // Component contains empty pairs.
    //
    // Some empty pairs are removed, while others are not.
    // Unfortunately, this exposes some implementation details.

    _testSet(
      url: "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
      component: .query, schema: .formEncoded, checkpoints: [
        // Unique key.
        // - Non-nil: Behaves like 'replaceValue(at:)' - replaces value component, without removing any empty pairs.
        // - Nil:     Behaves like 'remove(at:) - removes empty pairs only until next index.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=found&&&cafe%CC%81=cheese&&&dup&&&#frag",
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&cafe%CC%81=cheese&&&dup&&&#frag",

        // First key.
        // - Nil:     Behaves like 'remove(at:)'/'replaceSubrange' - removes leading empty pairs.
        "http://example/p?&&&foo=first&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        "http://example/p?dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",

        // Duplicate key.
        // - Non-nil: Behaves like 'removeAll(where:)' from the second match - removes empty pairs.
        // - Nil:     Behaves like 'removeAll(where:)' from the second match - removes empty pairs.
        //            Behaves like 'remove(at:)' for the first match though.
        "http://example/p?&&&foo=bar&&&dup=\(Self.SpecialCharacters_Escaped_Form)&&&=x&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",
        "http://example/p?&&&foo=bar&&&=x&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese#frag",

        // Unicode key.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=unicode&&&dup&&&#frag",
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&dup&&&#frag",

        // Non-present key.
        // - Non-nil: Behaves like 'append' - reuses one trailing pair delimiter.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&inserted-\(Self.SpecialCharacters_Escaped_Form)=yes#frag",
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",

        // Empty key.
        "http://example/p?&&&foo=bar&&&dup&&&=empty&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",
        "http://example/p?&&&foo=bar&&&dup&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",

        // Empty value.
        "http://example/p?&&&foo=bar&&&dup&&&=x&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=&&&cafe%CC%81=cheese&&&dup&&&#frag",
        "http://example/p?&&&foo=bar&&&dup&&&=&&&dup&&&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&&&cafe%CC%81=cheese&&&dup&&&#frag",

        // Remove all keys.
        "http://example/p#frag",
      ]
    )

    // Custom schema in the fragment.

    _testSet(
      url: "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
      component: .fragment, schema: CommaSeparated(), checkpoints: [
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):found,caf%C3%A9:cheese,dup",
        "http://example/p?q#foo:bar,dup,:x,dup,caf%C3%A9:cheese,dup",

        "http://example/p?q#foo:first,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        "http://example/p?q#dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",

        "http://example/p?q#foo:bar,dup:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),:x,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese",
        "http://example/p?q#foo:bar,:x,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese",

        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:unicode,dup",
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,dup",

        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup,inserted-\(Self.SpecialCharacters_Escaped_CommaSep_Frag):yes",
        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",

        "http://example/p?q#foo:bar,dup,:empty,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",
        "http://example/p?q#foo:bar,dup,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",

        "http://example/p?q#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form):,caf%C3%A9:cheese,dup",
        "http://example/p?q#foo:bar,dup,:,dup,\(Self.SpecialCharacters_Escaped_Form):test,caf%C3%A9:cheese,dup",

        "http://example/p?q",
      ]
    )
  }
}


// -------------------------------
// MARK: - Additional tests
// -------------------------------


extension KeyValuePairsTests {

  /// Tests using `WebURL.UTF8View.keyValuePair(_:)` to determine the UTF-8 range of a key-value pair.
  ///
  /// Checks a variety of pair formats:
  ///
  /// - Standard pairs with escaping
  /// - Pairs with no key-value delimiter
  /// - Pairs with an empty key or value
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testUTF8Slice() {

    func _testUTF8Slice(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema, ranges: [(Range<Int>, Range<Int>)]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      // Check that the component has the expected pairs.

      let kvps = url.keyValuePairs(in: component, schema: schema)
      let expectedPairs = [
        (key: "sp ac & es", value: "foo-bar"),
        (key: "nodelim", value: ""),
        (key: "emptyval", value: ""),
        (key: "", value: "emptykey"),
        (key: "jalapen\u{0303}os", value: "nfd"),
      ]
      XCTAssertEqualKeyValuePairs(kvps, expectedPairs)

      // Check each pair.

      var kvpIndex = kvps.startIndex
      var rangeIndex = ranges.startIndex
      while kvpIndex < kvps.endIndex {
        let utf8Slice = url.utf8.keyValuePair(kvpIndex)

        // The slice should cover the expected portion of the string.

        let keyRange = utf8Slice.key.startIndex..<utf8Slice.key.endIndex
        let valRange = utf8Slice.value.startIndex..<utf8Slice.value.endIndex
        XCTAssertEqual(keyRange, ranges[rangeIndex].0)
        XCTAssertEqual(valRange, ranges[rangeIndex].1)

        // Its content should be the same as '.encodedKey/Value'.

        XCTAssertEqualElements(kvps[kvpIndex].encodedKey.utf8, utf8Slice.key)
        XCTAssertEqualElements(kvps[kvpIndex].encodedValue.utf8, utf8Slice.value)

        kvps.formIndex(after: &kvpIndex)
        ranges.formIndex(after: &rangeIndex)
      }
      precondition(rangeIndex == ranges.count)
    }

    // Form encoded in the query.

    _testUTF8Slice(
      url: "http://example/?sp%20ac+%26+es=foo-bar&nodelim&emptyval=&=emptykey&jalapen%CC%83os=nfd#frag",
      component: .query, schema: .formEncoded, ranges: [
        (16..<30, 31..<38),
        (39..<46, 46..<46),  // No key-value delimiter.
        (47..<55, 56..<56),  // Empty value.
        (57..<57, 58..<66),  // Empty key.
        (67..<82, 83..<86),
      ]
    )

    // Form encoded in the query (2).
    // Component contains empty pairs. Semicolons are interpreted as pair delimiters.

    _testUTF8Slice(
      url: "http://example/?&;&sp%20ac+%26+es=foo-bar&&;nodelim;;;emptyval=;&;=emptykey&&&jalapen%CC%83os=nfd&&&#frag",
      component: .query, schema: ExtendedForm(semicolonIsPairDelimiter: true), ranges: [
        (19..<33, 34..<41),
        (44..<51, 51..<51),  // No key-value delimiter.
        (54..<62, 63..<63),  // Empty value.
        (66..<66, 67..<75),  // Empty key.
        (78..<93, 94..<97),
      ]
    )

    // Custom schema in the fragment.

    _testUTF8Slice(
      url: "http://example/?srch#sp%20ac%20%26%20es:foo-bar,nodelim,emptyval:,:emptykey,jalapen%CC%83os:nfd",
      component: .fragment, schema: CommaSeparated(), ranges: [
        (21..<39, 40..<47),
        (48..<55, 55..<55),  // No key-value delimiter.
        (56..<64, 65..<65),  // Empty value.
        (66..<66, 67..<75),  // Empty key.
        (76..<91, 92..<95),
      ]
    )
  }

  /// Tests the KeyValuePairs view's `CustomStringConvertible` conformance.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components, and
  /// 2. Using a variety of schemas with different escaping rules and delimiters.
  ///
  func testCustomStringConvertible() {

    func _testCustomStringConvertible(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema
    ) {
      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let kvps = url.keyValuePairs(in: component, schema: schema)
      switch component.value {
      case .query:
        XCTAssertEqual(String(describing: kvps), url.query)
      case .fragment:
        XCTAssertEqual(String(describing: kvps), url.fragment)
      }
    }

    // The description of the KeyValuePairs view is the URL component (without leading delimiter).
    // It should not depend on the schema.

    let schemas: [any KeyValueStringSchema] = [
      FormCompatibleKeyValueString(),
      PercentEncodedKeyValueString(),
      ExtendedForm(semicolonIsPairDelimiter: true),
      CommaSeparated(),
    ]

    let urlStrings = [
      "http://example/p?something#frag",
      "http://example/p?foo=bar&dup&=x&dup&\(Self.SpecialCharacters_Escaped_Form_Plus)=test&cafe%CC%81=cheese&dup#frag",
      "http://example/p?srch#something",
      "http://example/p?srch#foo:bar,dup,:x,dup,\(Self.SpecialCharacters_Escaped_Form_Plus):test,cafe%CC%81:cheese,dup",
    ]

    for schema in schemas {
      for urlString in urlStrings {
        _testCustomStringConvertible(url: urlString, component: .query, schema: schema)
        _testCustomStringConvertible(url: urlString, component: .fragment, schema: schema)
      }
    }
  }

  /// Tests using the `.encodedKey` and `.encodedValue` properties to read a key-value pair's components
  /// as they are in the URL string (including escaping).
  ///
  /// Checks a variety of escaped and unescaped key value pairs, including pairs with empty keys and values.
  ///
  /// **Tests are repeated**:
  ///
  /// 1. In various URL components,
  /// 2. Using a variety of schemas with different escaping rules and delimiters, and
  /// 3. With empty pairs inserted at various points in the URL component.
  ///
  func testEncodedKeyValue() {

    func _testEncodedKeyValue(
      url urlString: String,
      component: KeyValuePairsSupportedComponent, schema: some KeyValueStringSchema,
      expected: [(key: String, value: String)]
    ) {

      let url = WebURL(urlString)!
      XCTAssertEqual(url.serialized(), urlString)

      let kvps = url.keyValuePairs(in: component, schema: schema)
      XCTAssertEqualElements(kvps.lazy.map { $0.encodedKey }, expected.lazy.map { $0.key })
      XCTAssertEqualElements(kvps.lazy.map { $0.encodedValue }, expected.lazy.map { $0.value })
    }

    // Form encoding in the query.

    _testEncodedKeyValue(
      url: "http://example/?a=b&sp%20ac+%26+es=d&dup=e&=foo&noval&emoji=%F0%9F%91%80&jalapen%CC%83os=nfd&specials=\(Self.SpecialCharacters_Escaped_Form)&dup=f&jalape%C3%B1os=nfc&1%2B1=2#a=z",
      component: .query,
      schema: .formEncoded,
      expected: [
        (key: "a", value: "b"),
        (key: "sp%20ac+%26+es", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "%F0%9F%91%80"),
        (key: "jalapen%CC%83os", value: "nfd"),
        (key: "specials", value: Self.SpecialCharacters_Escaped_Form),
        (key: "dup", value: "f"),
        (key: "jalape%C3%B1os", value: "nfc"),
        (key: "1%2B1", value: "2"),
      ]
    )

    // Form encoding in the query (2).
    // Semicolons are also allowed as pair delimiters. Component contains empty pairs.

    _testEncodedKeyValue(
      url: "http://example/?;;;a=b&;&sp%20ac+%26+es=d&;&&dup=e;=foo&&noval;&;emoji=%F0%9F%91%80;&;&jalapen%CC%83os=nfd&&&specials=\(Self.SpecialCharacters_Escaped_PrctEnc_Query_NoSemiColon);;dup=f&;&jalape%C3%B1os=nfc&1%2B1=2&&;#a=z",
      component: .query,
      schema: ExtendedForm(semicolonIsPairDelimiter: true),
      expected: [
        (key: "a", value: "b"),
        (key: "sp%20ac+%26+es", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "%F0%9F%91%80"),
        (key: "jalapen%CC%83os", value: "nfd"),
        (key: "specials", value: Self.SpecialCharacters_Escaped_PrctEnc_Query_NoSemiColon),
        (key: "dup", value: "f"),
        (key: "jalape%C3%B1os", value: "nfc"),
        (key: "1%2B1", value: "2"),
      ]
    )

    // Custom schema in the fragment.
    // Note the use of unescaped '&' and '+' characters.

    _testEncodedKeyValue(
      url: "http://example/?srch#a:b,sp%20ac%20&%20es:d,dup:e,:foo,noval,emoji:%F0%9F%91%80,jalapen%CC%83os:nfd,specials:\(Self.SpecialCharacters_Escaped_CommaSep_Frag),dup:f,jalape%C3%B1os:nfc,1+1:2",
      component: .fragment,
      schema: CommaSeparated(),
      expected: [
        (key: "a", value: "b"),
        (key: "sp%20ac%20&%20es", value: "d"),
        (key: "dup", value: "e"),
        (key: "", value: "foo"),
        (key: "noval", value: ""),
        (key: "emoji", value: "%F0%9F%91%80"),
        (key: "jalapen%CC%83os", value: "nfd"),
        (key: "specials", value: Self.SpecialCharacters_Escaped_CommaSep_Frag),
        (key: "dup", value: "f"),
        (key: "jalape%C3%B1os", value: "nfc"),
        (key: "1+1", value: "2"),
      ]
    )
  }

  /// Tests using a key-value string schema with ASCII alpha delimiters.
  ///
  /// While not recommended, in theory it should work.
  ///
  func testAlphaDelimiters() {

    struct AlphaDelimiters: KeyValueStringSchema {
      var preferredPairDelimiter: UInt8 { UInt8(ascii: "x") }
      var preferredKeyValueDelimiter: UInt8 { UInt8(ascii: "t") }
      var decodePlusAsSpace: Bool { false }
    }

    for component in KeyValuePairsSupportedComponent.allCases {
      XCTAssertNoThrow(try AlphaDelimiters().verify(for: component))
    }

    let pairsToAdd = [
      ("Test", "123"),
      ("Another test", "456"),
      ("results", "excellent"),
      ("t\u{0342}est2", "x\u{0313}\u{032b}-23"),  // (combining chars)
    ]
    var url = WebURL("p://x/")!
    url.withMutableKeyValuePairs(in: .query, schema: AlphaDelimiters()) { $0 += pairsToAdd }
    XCTAssertEqual(url.serialized(), "p://x/?Tes%74t123xAno%74her%20%74es%74t456xresul%74ste%78cellen%74x%74%CD%82es%742t%78%CC%93%CC%AB-23")

    let kvps = url.keyValuePairs(in: .query, schema: AlphaDelimiters())
    XCTAssertEqualKeyValuePairs(kvps, pairsToAdd)

    XCTAssertEqual(kvps["results"], "excellent")
    XCTAssertEqual(kvps["t\u{0342}est2"], "x\u{0313}\u{032b}-23")
  }
}

extension KeyValuePairsTests {

  /// Tests assigning a KeyValuePairs view from one URL to another.
  ///
  /// This is not generally allowed, but there are a handful of situations where it works.
  /// Unfortunately we can't test the situations where it doesn't work, because they trigger a fatal error
  /// and XCTest doesn't support testing such things.
  ///
  func testAssignment() {

    // Straightforward 'queryParams' assignment.
    // This works because 'queryParams' includes a 'set' accessor, in addition to 'modify'.

    do {
      let srcQuery = "test=src&foo=bar&specials=\(Self.SpecialCharacters_Escaped_PrctEnc_Query)"

      let src = WebURL("http://src/?\(srcQuery)")!
      var dst = WebURL("file://dst/")!
      XCTAssertEqual(src.queryParams.count, 3)
      XCTAssertEqual(dst.queryParams.count, 0)

      dst.queryParams = src.queryParams

      XCTAssertEqual(src.serialized(), "http://src/?\(srcQuery)")
      XCTAssertEqual(dst.serialized(), "file://dst/?\(srcQuery)")
      XCTAssertEqual(src.queryParams.count, 3)
      XCTAssertEqual(dst.queryParams.count, 3)
    }

    // Assigning different views originating from the same storage.
    // This works basically as a side-effect of how the mutating scope ID is calculated 😕,
    // but it's also not _really_ a problem because data outside the viewed component cannot be changed.

    do {
      var url1 = WebURL("file://xyz/")!
      var url2 = url1

      url2.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { kvps2 in
        url1.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { kvps1 in
          kvps2 += [("hello", "world")]
          kvps1 = kvps2
          kvps2 += [("after", "wards")]
        }
      }

      XCTAssertEqual(url1.serialized(), "file://xyz/?hello=world")
      XCTAssertEqual(url2.serialized(), "file://xyz/?hello=world&after=wards")
    }

    // These should all cause runtime traps.
    // Unfortunately we can't test that with XCTest :(

    #if false

      let check = 0

      // Reassignment via modify accessor. Different source URLs.

      if check == 0 {
        let src = WebURL("http://src/")!
        var dst = WebURL("file://dst/")!

        @inline(never)
        func assign<T>(_ x: inout T, to y: T) {
          x = y
        }

        assign(&dst.queryParams, to: src.queryParams)
        XCTFail("Should have trapped")
      }

      // Reassignment via modify accessor. Same source URLs, different components.

      if check == 1 {
        let url1 = WebURL("http://xyz/")!
        var url2 = url1

        @inline(never)
        func assign<T>(_ x: inout T, to y: T) {
          x = y
        }

        assign(&url2.queryParams, to: url1.keyValuePairs(in: .fragment, schema: .formEncoded))
        XCTFail("Should have trapped")
      }

      // Reassignment via scoped method. Different source URLs.

      if check == 2 {
        let src = WebURL("http://src/")!
        var dst = WebURL("file://dst/")!

        dst.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { $0 = src.queryParams }
        XCTFail("Should have trapped")
      }

      // Reassignment via scoped method. Same source URLs, different components.

      if check == 3 {
        var url1 = WebURL("file://xyz/")!
        var url2 = url1

        url1.withMutableKeyValuePairs(in: .query, schema: .formEncoded) { kvps1 in
          url2.withMutableKeyValuePairs(in: .fragment, schema: .formEncoded) { kvps2 in
            kvps2 += [("hello", "world")]
            kvps1 = kvps2
          }
        }
        XCTFail("Should have trapped")
      }

    #endif
  }
}
