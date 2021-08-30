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

final class WebURLAPITests_Deprecated: XCTestCase {

  func testCannotBeABase() {
    // Non-hierarchical URLs.
    if let url = WebURL("javascript:alert('hello');") {
      XCTAssertFalse(url.isHierarchical)
      XCTAssertTrue(url.cannotBeABase)
    } else {
      XCTFail()
    }
    if let url = WebURL("mailto:jim@example.com") {
      XCTAssertFalse(url.isHierarchical)
      XCTAssertTrue(url.cannotBeABase)
    } else {
      XCTFail()
    }
    // Hierarchical URLs.
    if let url = WebURL("http://example.com") {
      XCTAssertTrue(url.isHierarchical)
      XCTAssertFalse(url.cannotBeABase)
    } else {
      XCTFail()
    }
    if let url = WebURL("foo:/path/only") {
      XCTAssertTrue(url.isHierarchical)
      XCTAssertFalse(url.cannotBeABase)
    } else {
      XCTFail()
    }
  }
}
