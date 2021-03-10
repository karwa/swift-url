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

  func testGet_Contains() {
    let url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")

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
    var url0 = WebURL("http://example.com")!
    XCTAssertEqual(url0.serialized, "http://example.com/")
    XCTAssertNil(url0.query)
    XCTAssertNil(url0.queryParams.get(""))
    XCTAssertNil(url0.queryParams.get("?"))
    url0.query = ""
    XCTAssertEqual(url0.serialized, "http://example.com/?")
    XCTAssertEqual(url0.query, "")
    XCTAssertNil(url0.queryParams.get(""))
    XCTAssertNil(url0.queryParams.get("?"))

    // When emptying the queryItems, the URL's query gets set to nil rather than empty.
    //    var url1 = WebURL("http://example.com?a=b&c is the key=d&&e=&e&=foo&e=g&h=👀&e=f")!
    //    XCTAssertEqual(url1.serialized, "http://example.com/?a=b&c%20is%20the%20key=d&&e=&e&=foo&e=g&h=%F0%9F%91%80&e=f")
    //    XCTAssertEqual(url1.query, "a=b&c%20is%20the%20key=d&&e=&e&=foo&e=g&h=%F0%9F%91%80&e=f")
    //    XCTAssertEqual(url1.queryItems.count, 8)
    //    url1.queryItems.removeAll()
    //    XCTAssertEqual(url1.serialized, "http://example.com/")
    //    XCTAssertNil(url1.query)
    //    XCTAssertEqual(url1.queryItems, [])
  }

  func testAppend() {
    // Start with a URL without query, use 'append' to build one.
    var url = WebURL("http://example.com")!
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertNil(url.query)
    url.queryParams.append(key: "search query", value: "why are 🦆 so awesome?")
    url.queryParams.append(key: "`back`'tick'", value: "")  // U+0027 is encoded by forms, and only by forms.
    XCTAssertEqual(
      url.serialized,
      "http://example.com/?search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27="
    )
    XCTAssertEqual(url.query, "search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27=")
    XCTAssertEqual(url.queryParams.get("search query"), "why are 🦆 so awesome?")
    XCTAssertEqual(url.queryParams.get("`back`'tick'"), "")

    // Store the params object and reset the query.
    var storedParams = url.queryParams
    url.query = nil
    url.hostname = "foobar.org"
    XCTAssertEqual(url.serialized, "http://foobar.org/")
    XCTAssertNil(url.query)
    XCTAssertFalse(url.queryParams.contains("search query"))
    XCTAssertTrue(storedParams.contains("search query"))
    // Append to the free-standing copy.
    storedParams.append(key: "still alive?", value: "should be!")
    storedParams.append(key: "owned and mutable?", value: "sure thing!")
    XCTAssertEqual(storedParams.get("still alive?"), "should be!")
    XCTAssertEqual(storedParams.get("owned and mutable?"), "sure thing!")
    // Assign it to the URL.
    url.queryParams = storedParams
    XCTAssertEqual(
      url.serialized,
      "http://foobar.org/?search+query=why+are+%F0%9F%A6%86+so+awesome%3F&%60back%60%27tick%27=&still+alive%3F=should+be%21&owned+and+mutable%3F=sure+thing%21"
    )
  }

  func testRemove() {
    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")

    // Removal from the front.
    XCTAssertEqual(url.queryParams.a, "b")
    url.queryParams.remove(key: "a")
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertNil(url.queryParams.a)

    // Removal of a key with multiple entries.
    XCTAssertEqual(url.queryParams.e, "")
    XCTAssertEqual(url.queryParams.getAll("e"), ["", "g", "", "f"])
    url.queryParams.remove(key: "e")
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&=foo&h=%F0%9F%91%80")
    XCTAssertEqual(url.query, "c+is+the+key=d&=foo&h=%F0%9F%91%80")
    XCTAssertNil(url.queryParams.e)

    // Removal from the back.
    XCTAssertEqual(url.queryParams.h, "👀")
    url.queryParams.remove(key: "h")
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&=foo")
    XCTAssertEqual(url.query, "c+is+the+key=d&=foo")
    XCTAssertNil(url.queryParams.h)

    // Removing all key-value pairs results in a 'nil' query.
    XCTAssertEqual(url.queryParams.get("c is the key"), "d")
    XCTAssertEqual(url.queryParams.get(""), "foo")
    url.queryParams.remove(key: "c is the key")
    url.queryParams.remove(key: "")
    XCTAssertEqual(url.serialized, "http://example.com/")
    XCTAssertNil(url.query)
    XCTAssertNil(url.queryParams.get("c is the key"))
    XCTAssertNil(url.queryParams.get(""))
  }

  func testSet() {
    var url = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")

    // Set unique, pre-existing keys. Relative position of KVP within the string is maintained.
    XCTAssertEqual(url.queryParams.a, "b")
    url.queryParams.a = "THIS ONE"
    XCTAssertEqual(url.serialized, "http://example.com/?a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.query, "a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url.queryParams.a, "THIS ONE")

    XCTAssertEqual(url.queryParams.h, "👀")
    url.queryParams.set(key: "h", to: "ALSO THIS ONE")
    XCTAssertEqual(url.serialized, "http://example.com/?a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=ALSO+THIS+ONE&e=f")
    XCTAssertEqual(url.query, "a=THIS+ONE&c+is+the+key=d&e=&=foo&e=g&e=&h=ALSO+THIS+ONE&e=f")
    XCTAssertEqual(url.queryParams.h, "ALSO THIS ONE")

    // Set a key with multiple entries.
    XCTAssertEqual(url.queryParams.e, "")
    url.queryParams.e = "collapsed"
    XCTAssertEqual(url.serialized, "http://example.com/?a=THIS+ONE&c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertEqual(url.query, "a=THIS+ONE&c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertEqual(url.queryParams.e, "collapsed")

    // Setting to 'nil' removes the key.
    XCTAssertEqual(url.queryParams.a, "THIS ONE")
    url.queryParams.a = nil
    XCTAssertEqual(url.serialized, "http://example.com/?c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertEqual(url.query, "c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE")
    XCTAssertNil(url.queryParams.a)

    // Setting a non-existent key appends it.
    XCTAssertNil(url.queryParams.doesNotExist)
    url.queryParams.doesNotExist = "Yes, it does!"
    XCTAssertEqual(
      url.serialized,
      "http://example.com/?c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE&doesNotExist=Yes%2C+it+does%21")
    XCTAssertEqual(url.query, "c+is+the+key=d&e=collapsed&=foo&h=ALSO+THIS+ONE&doesNotExist=Yes%2C+it+does%21")
  }

  func testAssignment() {
    var url0 = WebURL("http://example.com?a=b&c+is the key=d&&e=&=foo&e=g&e&h=👀&e=f")!
    XCTAssertEqual(url0.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url0.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")

    var url1 = WebURL("foo://bar")!
    XCTAssertEqual(url1.serialized, "foo://bar")
    XCTAssertNil(url1.query)

    // Set url1's queryParams from empty to url0's non-empty queryParams.
    // url1's query string should be the form-encoded version version of url0's query, which itself remains unchanged.
    url1.queryParams = url0.queryParams
    XCTAssertEqual(url1.serialized, "foo://bar?a=b&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url1.query, "a=b&c+is+the+key=d&e=&=foo&e=g&e=&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url0.serialized, "http://example.com/?a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")
    XCTAssertEqual(url0.query, "a=b&c+is%20the%20key=d&&e=&=foo&e=g&e&h=%F0%9F%91%80&e=f")

    // Reset url1 to a nil query. Set url0's non-empty params to url1's empty params.
    // url0 should now have a nil query, and url1 remains unchanged.
    url1 = WebURL("foo://bar")!
    XCTAssertEqual(url1.serialized, "foo://bar")
    XCTAssertNil(url1.query)
    url0.queryParams = url1.queryParams
    XCTAssertEqual(url0.serialized, "http://example.com/")
    XCTAssertNil(url0.query)
    XCTAssertEqual(url1.serialized, "foo://bar")
    XCTAssertNil(url1.query)
  }
}
