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

final class OtherURLTests: XCTestCase {}

// This file contains tests which document "questionable behaviour" in the URL Standard.
// Web compatibility means these things might never change, but it may also be worth raising them
// with the WHATWG at some point. In any case, it's worth adding a test so we don't forget about them
// and don't mistakenly think they are bugs with WebURL.

extension OtherURLTests {

  func testPathSetterBackslash() {

    // Backslashes are not percent-encoded in non-special URLs,
    // so copying the path to a special URL can cause it to be interpreted differently.
    do {
      var specialURL = WebURL("https://example.com/")!
      XCTAssertEqual(specialURL.serialized(), "https://example.com/")
      XCTAssertEqual(specialURL.path, "/")
      XCTAssertEqual(specialURL.pathComponents.count, 1)

      let nonSpecialURL = WebURL(#"foo://example.com/baz\qux"#)!
      XCTAssertEqual(nonSpecialURL.serialized(), #"foo://example.com/baz\qux"#)
      XCTAssertEqual(nonSpecialURL.path, #"/baz\qux"#)
      XCTAssertEqual(nonSpecialURL.pathComponents.count, 1)

      specialURL.path = nonSpecialURL.path
      XCTAssertEqual(specialURL.serialized(), "https://example.com/baz/qux")
      XCTAssertEqual(specialURL.path, "/baz/qux")
      XCTAssertEqual(specialURL.pathComponents.count, 2)
    }

    // Our pathComponents view happens to work around this.
    // (covered already in PathComponentsTests.testReplaceSubrange_Slashes, .testAppendContents, etc)
    do {
      var specialURL = WebURL("https://example.com/")!
      XCTAssertEqual(specialURL.serialized(), "https://example.com/")
      XCTAssertEqual(specialURL.path, "/")
      XCTAssertEqual(specialURL.pathComponents.count, 1)

      let nonSpecialURL = WebURL(#"foo://example.com/baz\qux"#)!
      XCTAssertEqual(nonSpecialURL.serialized(), #"foo://example.com/baz\qux"#)
      XCTAssertEqual(nonSpecialURL.path, #"/baz\qux"#)
      XCTAssertEqual(nonSpecialURL.pathComponents.count, 1)

      specialURL.pathComponents.append(contentsOf: nonSpecialURL.pathComponents)
      XCTAssertEqual(specialURL.serialized(), "https://example.com/baz%5Cqux")
      XCTAssertEqual(specialURL.path, "/baz%5Cqux")
      XCTAssertEqual(specialURL.pathComponents.count, 1)
    }
  }
}
