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

final class QueryParametersTests: XCTestCase {

  func testDocumentationExamples() {

    // From documentation for `WebURL.queryParams`:
    var url = WebURL("http://example.com/shopping/deals?category=food&limit=25")!
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertEqual(url.queryParams.category, "food")

    url.queryParams.distance = "10km"
    XCTAssertEqual(url.serialized, "http://example.com/shopping/deals?category=food&limit=25&distance=10km")

    url.queryParams.limit = nil
    XCTAssertEqual(url.serialized, "http://example.com/shopping/deals?category=food&distance=10km")

    url.queryParams.set("cuisine", to: "🇮🇹")
    XCTAssertEqual(
      url.serialized, "http://example.com/shopping/deals?category=food&distance=10km&cuisine=%F0%9F%87%AE%F0%9F%87%B9"
    )
    XCTAssertURLIsIdempotent(url)
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)

    let expected = [
      ("category", "food"),
      ("distance", "10km"),
      ("cuisine", "🇮🇹"),
    ]
    for (i, (key, value)) in url.queryParams.allKeyValuePairs.enumerated() {
      XCTAssertEqual(key, expected[i].0)
      XCTAssertEqual(value, expected[i].1)
    }
  }

  func testGet_Contains() {

    let url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)

    // Check that we can look up a simple key, and the value is decoded.
    XCTAssertEqual(url.queryParams.a, "b")
    XCTAssertEqual(url.queryParams.h, "👀")
    // Check we can find a key which requires encoding.
    XCTAssertEqual(url.queryParams.get("c is the key"), "d")
    // If a key has multiple values, the first one is returned.
    // Also, check we can find a key with an empty value.
    XCTAssertEqual(url.queryParams.e, "")
    // Empty keys can also be found.
    XCTAssertEqual(url.queryParams.get(""), "foo")

    // Non-present keys return nil.
    XCTAssertNil(url.queryParams.doesNotExist)
    XCTAssertNil(url.queryParams.get("nope"))

    // 'contains' returns the same information.
    XCTAssertTrue(url.queryParams.contains("a"))
    XCTAssertTrue(url.queryParams.contains("c is the key"))
    XCTAssertTrue(url.queryParams.contains(""))
    XCTAssertFalse(url.queryParams.contains("doesNotExist"))

    // 'getAll' finds all values for a key, returns them in correct order.
    XCTAssertEqual(url.queryParams.getAll("e"), ["", "g", "", "f"])
    XCTAssertEqual(url.queryParams.getAll("doesNotExist"), [])

    // All of this is read-only; the URL's query string remains as it was.
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
  }

  func testEmptyAndNil() {

    // Both nil and empty query strings present as empty query parameters.
    do {
      var url = WebURL("http://example.com")!
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.query)
      XCTAssertNil(url.queryParams.get(""))
      XCTAssertNil(url.queryParams.get("?"))
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)

      url.query = ""
      XCTAssertEqual(url.serialized, "http://example.com/?")
      XCTAssertEqual(url.query, "")
      XCTAssertNil(url.queryParams.get(""))
      XCTAssertNil(url.queryParams.get("?"))
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }

    // When emptying the queryParams, the URL's query gets set to nil rather than empty.
    do {
      var url = WebURL("http://example.com?a=b&c is the key=d&&e=&e&=foo&e=g&h=👀&e=f")!
      XCTAssertEqual(url.serialized, "http://example.com/?a=b&c%20is%20the%20key=d&&e=&e&=foo&e=g&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url.query, "a=b&c%20is%20the%20key=d&&e=&e&=foo&e=g&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url.queryParams.h, "👀")
      XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)

      url.queryParams.removeAll()
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.query)
      XCTAssertNil(url.queryParams.h)
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }

    // KVPs without keys or values (so strings of "&" characters in the query) get removed by form-encoding
    // and are the equivalent of an empty query.
    do {
      var url = WebURL("http://example.com?&&&")!
      XCTAssertEqual(url.serialized, "http://example.com/?&&&")
      XCTAssertEqual(url.query, "&&&")
      XCTAssertNil(url.queryParams.get(""))

      url.queryParams = url.queryParams
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.query)
      XCTAssertNil(url.queryParams.get(""))
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testAppend() {

    // Start with a URL without query, use 'append' to build one.
    do {
      var url = WebURL("http://example.com")!
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.query)
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)

      url.queryParams.append("non_escaped", value: "true")  // Neither key or value need escaping.
      url.queryParams.append("spa ce", value: "")  // key needs escaping due to substitution only.
      url.queryParams.append("search query", value: "why are 🦆 so awesome?")  // both need escaping.
      url.queryParams.append("`back`'tick'", value: "")  // U+0027 is encoded by forms, and only by forms.
      XCTAssertEqual(
        url.serialized,
        "http://example.com/?non_escaped=true&spa+ce=&search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27="
      )
      XCTAssertEqual(
        url.query, "non_escaped=true&spa+ce=&search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27="
      )
      XCTAssertEqual(url.queryParams.get("non_escaped"), "true")
      XCTAssertEqual(url.queryParams.get("search query"), "why are 🦆 so awesome?")
      XCTAssertEqual(url.queryParams.get("`back`'tick'"), "")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)

      // Store the params object and reset the query.
      var storedParams = url.queryParams
      url.query = nil
      url.hostname = "foobar.org"
      XCTAssertEqual(url.serialized, "http://foobar.org/")
      XCTAssertNil(url.query)
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertFalse(url.queryParams.contains("search query"))
      XCTAssertTrue(storedParams.contains("search query"))
      // Append to the free-standing copy.
      storedParams.append("still alive?", value: "should be!")
      storedParams.append("owned and mutable?", value: "sure thing!")
      XCTAssertEqual(storedParams.get("still alive?"), "should be!")
      XCTAssertEqual(storedParams.get("owned and mutable?"), "sure thing!")
      // Assign it to the URL.
      url.queryParams = storedParams
      XCTAssertEqual(
        url.serialized,
        "http://foobar.org/?non_escaped=true&spa+ce=&search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27=&still+alive%3F=should+be%21&owned+and+mutable%3F=sure+thing%21"
      )
      XCTAssertEqual(url.queryParams.get("still alive?"), "should be!")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }

    // Ensure that we can append to an empty (not 'nil') query.
    do {
      var url = WebURL("foo://bar?")!
      XCTAssertEqual(url.serialized, "foo://bar?")
      XCTAssertEqual(url.query, "")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)

      url.queryParams.append("test", value: "works!")
      XCTAssertEqual(url.serialized, "foo://bar?test=works%21")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testAppendSequence() {

    do {
      // Start with a URL without query, use 'append' to build one.
      var url = WebURL("http://example.com")!
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.query)
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)

      url.queryParams += [
        ("search query", "why are 🦆 so awesome?"),
        ("`back`'tick'", ""),  // U+0027 is encoded by forms, and only by forms.
      ]
      XCTAssertEqual(
        url.serialized,
        "http://example.com/?search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27="
      )
      XCTAssertEqual(url.query, "search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27=")
      XCTAssertEqual(url.queryParams.get("search query"), "why are 🦆 so awesome?")
      XCTAssertEqual(url.queryParams.get("`back`'tick'"), "")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)

      // Store the params object and reset the query.
      var storedParams = url.queryParams
      url.query = nil
      url.hostname = "foobar.org"
      XCTAssertEqual(url.serialized, "http://foobar.org/")
      XCTAssertNil(url.query)
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertFalse(url.queryParams.contains("search query"))
      XCTAssertTrue(storedParams.contains("search query"))
      // Append to the free-standing copy.
      storedParams.append(contentsOf: [
        (key: "still alive?", value: "should be!"),
        (key: "owned and mutable?", value: "sure thing!"),
      ])
      XCTAssertEqual(storedParams.get("still alive?"), "should be!")
      XCTAssertEqual(storedParams.get("owned and mutable?"), "sure thing!")
      // Assign it to the URL.
      url.queryParams = storedParams
      XCTAssertEqual(
        url.serialized,
        "http://foobar.org/?search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27=&still+alive%3F=should+be%21&owned+and+mutable%3F=sure+thing%21"
      )
      XCTAssertEqual(url.queryParams.get("still alive?"), "should be!")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }

    // Dictionary has a concrete overload which sorts its key-value pairs,
    // so appending a dictionary always gives predictable results.
    do {
      var url = WebURL("http://example.com")!
      XCTAssertEqual(url.serialized, "http://example.com/")
      XCTAssertNil(url.query)
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)

      let dictionary: [String: String] = [
        "key one": "value one",
        "key 2️⃣": "value %02",
      ]
      url.queryParams += dictionary
      XCTAssertEqual(url.serialized, "http://example.com/?key+2%EF%B8%8F%E2%83%A3=value+%2502&key+one=value+one")
      XCTAssertEqual(url.query, "key+2%EF%B8%8F%E2%83%A3=value+%2502&key+one=value+one")
      XCTAssertEqual(url.queryParams.get("key one"), "value one")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testRemove() {

    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)

    // Removal from the front.
    XCTAssertEqual(url.queryParams.a, "b")
    url.queryParams.remove("a")
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertNil(url.queryParams.a)
    XCTAssertURLIsIdempotent(url)

    // Removal of a key with multiple entries.
    XCTAssertEqual(url.queryParams.e, "")
    XCTAssertEqual(url.queryParams.getAll("e"), ["", "g", "", "f"])
    url.queryParams.remove("e")
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&=foo&h=%F0%9F%91%80")
    XCTAssertEqual(url.query, "c+is+the+key=d&=foo&h=%F0%9F%91%80")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertNil(url.queryParams.e)
    XCTAssertURLIsIdempotent(url)

    // Removal from the back.
    XCTAssertEqual(url.queryParams.h, "👀")
    url.queryParams.remove("h")
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&=foo")
    XCTAssertEqual(url.query, "c+is+the+key=d&=foo")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertNil(url.queryParams.h)
    XCTAssertURLIsIdempotent(url)

    // Removing all key-value pairs results in a 'nil' query.
    XCTAssertEqual(url.queryParams.get("c is the key"), "d")
    XCTAssertEqual(url.queryParams.get(""), "foo")
    url.queryParams.remove("c is the key")
    url.queryParams.remove("")
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertNil(url.query)
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertNil(url.queryParams.get("c is the key"))
    XCTAssertNil(url.queryParams.get(""))
    XCTAssertURLIsIdempotent(url)
  }

  func testRemoveAll() {

    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertEqual(url.queryParams.e, "")
    XCTAssertEqual(url.queryParams.a, "b")

    url.queryParams.removeAll()
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertNil(url.query)
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertNil(url.queryParams.e)
    XCTAssertNil(url.queryParams.a)
    XCTAssertURLIsIdempotent(url)
  }

  func testSet() {

    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)

    // Set unique, pre-existing keys. Relative position of KVP within the string is maintained.
    XCTAssertEqual(url.queryParams.a, "b")
    url.queryParams.a = "THIS ONE"
    XCTAssertEqual(url.serialized, "http://example.com/?a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.queryParams.a, "THIS ONE")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)

    XCTAssertEqual(url.queryParams.h, "👀")
    url.queryParams.set("h", to: "ALSO THIS ONE")
    XCTAssertEqual(url.serialized, "http://example.com/?a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=ALSO+THIS+ONE&e=f")
    XCTAssertEqual(url.query, "a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=ALSO+THIS+ONE&e=f")
    XCTAssertEqual(url.queryParams.h, "ALSO THIS ONE")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)

    // Set a key with multiple entries.
    XCTAssertEqual(url.queryParams.e, "")
    url.queryParams.e = "collapsed"
    XCTAssertEqual(url.serialized, "http://example.com/?a=THIS+ONE&c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertEqual(url.query, "a=THIS+ONE&c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertEqual(url.queryParams.e, "collapsed")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)

    // Setting to 'nil' removes the key.
    XCTAssertEqual(url.queryParams.a, "THIS ONE")
    url.queryParams.a = nil
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertEqual(url.query, "c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertNil(url.queryParams.a)
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)

    // Setting a non-existent key appends it.
    XCTAssertNil(url.queryParams.doesNotExist)
    url.queryParams.doesNotExist = "Yes, it does!"
    XCTAssertEqual(
      url.serialized,
      "http://example.com/?c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE&doesNotExist=Yes%2C+it+does%21")
    XCTAssertEqual(url.query, "c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE&doesNotExist=Yes%2C+it+does%21")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)
  }

  func testAssignment() {

    do {
      var url0 = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
      XCTAssertEqual(url0.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url0.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
      XCTAssertFalse(url0.storage.structure.queryIsKnownFormEncoded)

      var url1 = WebURL("foo://bar")!
      XCTAssertEqual(url1.serialized, "foo://bar")
      XCTAssertNil(url1.query)
      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)

      // Set url1's queryParams from empty to url0's non-empty queryParams.
      // url1's query string should be the form-encoded version version of url0's query, which itself remains unchanged.
      url1.queryParams = url0.queryParams
      XCTAssertEqual(url1.serialized, "foo://bar?a=b&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url1.query, "a=b&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url0.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url0.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
      XCTAssertFalse(url0.storage.structure.queryIsKnownFormEncoded)
      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url1)

      // Reset url1 to a nil query. Set url0's non-empty params to url1's empty params.
      // url0 should now have a nil query, and url1 remains unchanged.
      url1 = WebURL("foo://bar")!
      XCTAssertEqual(url1.serialized, "foo://bar")
      XCTAssertNil(url1.query)
      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)

      url0.queryParams = url1.queryParams
      XCTAssertEqual(url0.serialized, "http://example.com/")
      XCTAssertNil(url0.query)
      XCTAssertTrue(url0.storage.structure.queryIsKnownFormEncoded)
      XCTAssertEqual(url1.serialized, "foo://bar")
      XCTAssertNil(url1.query)
      XCTAssertTrue(url1.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url0)
    }

    // Assigning a URL's query parameters to itself causes the string to be re-encoded.
    do {
      var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f&&&")!
      XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f&&&")
      XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f&&&")
      XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)

      url.queryParams = url.queryParams
      XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
      XCTAssertEqual(url.query, "a=b&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
      XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testKeyValuePairsSequence() {

    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertFalse(url.queryParams.allKeyValuePairs.isEmpty)

    // Tuples are not Equatable :(
    struct KeyValuePair: Equatable {
      var key: String
      var value: String
    }
    // Check that all elements are returned (even duplicates), and in the correct order.
    let actualKVPs = url.queryParams.allKeyValuePairs.map { KeyValuePair(key: $0.0, value: $0.1) }
    let expectedKVPs = [
      ("a", "b"), ("c is the key", "d"), ("e", ""), ("", "foo"), ("e", "g"), ("e", ""), ("h", "👀"), ("e", "f"),
    ].map { KeyValuePair(key: $0.0, value: $0.1) }

    XCTAssertEqualElements(actualKVPs, expectedKVPs)

    // Check that we can iterate again, with the same results.
    let actualKVPs_secondIteration = url.queryParams.allKeyValuePairs.map { KeyValuePair(key: $0.0, value: $0.1) }
    XCTAssertEqualElements(actualKVPs, actualKVPs_secondIteration)

    // Dictionary construction.
    let dictionary = Dictionary(url.queryParams.allKeyValuePairs, uniquingKeysWith: { earlier, later in earlier })
    XCTAssertEqual(dictionary.count, 5)
    XCTAssertEqual(dictionary["c is the key"], "d")

    // 'isEmpty' property.
    url.queryParams.removeAll()
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertNil(url.query)
    XCTAssertTrue(url.queryParams.allKeyValuePairs.isEmpty)

    url.queryParams.someKey = "someValue"
    XCTAssertEqual(url.serialized, "http://example.com/?someKey=someValue")
    XCTAssertEqual(url.query, "someKey=someValue")
    XCTAssertFalse(url.queryParams.allKeyValuePairs.isEmpty)

    // Empty KVPs are ignored by form encoding.
    url = WebURL("http://example.com/?&&&&")!
    XCTAssertEqual(url.serialized, "http://example.com/?&&&&")
    XCTAssertEqual(url.query, "&&&&")
    XCTAssertTrue(url.queryParams.allKeyValuePairs.isEmpty)
    for _ in url.queryParams.allKeyValuePairs {
      XCTFail("Expected queryParams to be empty")
    }
  }

  func testKnownFormEncodedFlag() {

    // For a non-empty query, the flag should start at 'false'.
    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)

    // Modifying via 'queryParams' sets the flag to true, as the query is re-encoded.
    url.queryParams.h = nil
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is+the+key=d&e=&=foo&e=g&e=&e=f")
    XCTAssertEqual(url.query, "a=b&c+is+the+key=d&e=&=foo&e=g&e=&e=f")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)

    // Setting via '.query' to a non-empty value sets the flag back to false.
    url.query = "foobar"
    XCTAssertEqual(url.serialized, "http://example.com/?foobar")
    XCTAssertEqual(url.query, "foobar")
    XCTAssertFalse(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)

    // Setting via '.query' to an empty/nil value sets the flag to true.
    url.query = ""
    XCTAssertEqual(url.serialized, "http://example.com/?")
    XCTAssertEqual(url.query, "")
    XCTAssertTrue(url.storage.structure.queryIsKnownFormEncoded)
    XCTAssertURLIsIdempotent(url)
  }
}
