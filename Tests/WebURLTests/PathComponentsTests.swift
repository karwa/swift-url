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

final class PathComponentsTests: XCTestCase {}

extension PathComponentsTests {

  func testDocumentationExamples() {
    do {
      let url = WebURL("http://example.com/swift/packages/swift-url")!
      XCTAssertEqualElements(url.pathComponents!, ["swift", "packages", "swift-url"])
      XCTAssertEqual(url.pathComponents!.last, "swift-url")
      XCTAssertEqual(url.pathComponents!.dropLast().last, "packages")
    }
    do {
      let url = WebURL("http://example.com/swift/packages/🦆/")!
      XCTAssertEqualElements(url.pathComponents!, ["swift", "packages", "🦆", ""])
      XCTAssertEqual(url.pathComponents!.count, 4)
      XCTAssertEqual(url.pathComponents!.last, "")
      XCTAssertEqual(url.pathComponents!.dropLast().last, "🦆")
    }
  }

  func testCannotBeABaseURL() {
    let url = WebURL("mailto:bob")!
    XCTAssertEqual(url.serialized, "mailto:bob")
    XCTAssertEqual(url.path, "bob")
    XCTAssertTrue(url._cannotBeABaseURL)
    XCTAssertNil(url.pathComponents)
  }

  func testURLWithNoPath() {
    let url = WebURL("foo://somehost?someQuery")!
    XCTAssertEqual(url.serialized, "foo://somehost?someQuery")
    XCTAssertEqual(url.path, "")
    XCTAssertFalse(url._cannotBeABaseURL)
    if let pathComponents = url.pathComponents {
      XCTAssertEqualElements(pathComponents, [])
      XCTAssertEqual(pathComponents.count, 0)
      XCTAssertTrue(pathComponents.isEmpty)
      CollectionChecker.check(pathComponents)
    } else {
      XCTFail("Expected empty, non-nil path components")
    }
  }

  func testURLWithRootPath() {
    let url = WebURL("http://example.com/?someQuery")!
    XCTAssertEqual(url.serialized, "http://example.com/?someQuery")
    XCTAssertEqual(url.path, "/")
    XCTAssertFalse(url._cannotBeABaseURL)
    if let pathComponents = url.pathComponents {
      XCTAssertEqualElements(pathComponents, [""])
      XCTAssertEqual(pathComponents.count, 1)
      XCTAssertFalse(pathComponents.isEmpty)
      CollectionChecker.check(pathComponents)
    } else {
      XCTFail("Expected empty, non-nil path components")
    }
  }

  func testPathOnlyURL() {
    let url = WebURL("foo:/a/b/c")!
    XCTAssertEqual(url.serialized, "foo:/a/b/c")
    XCTAssertEqual(url.path, "/a/b/c")
    XCTAssertFalse(url._cannotBeABaseURL)
    if let pathComponents = url.pathComponents {
      XCTAssertEqualElements(pathComponents, ["a", "b", "c"])
      XCTAssertEqual(pathComponents.count, 3)
      XCTAssertFalse(pathComponents.isEmpty)
      CollectionChecker.check(pathComponents)
    } else {
      XCTFail("Expected empty, non-nil path components")
    }
  }

  func testEmptyComponents() {
    // 2 empty components.
    do {
      let url = WebURL("http://example.com//?someQuery")!
      XCTAssertEqual(url.serialized, "http://example.com//?someQuery")
      XCTAssertEqual(url.path, "//")
      XCTAssertFalse(url._cannotBeABaseURL)
      if let pathComponents = url.pathComponents {
        XCTAssertEqualElements(pathComponents, ["", ""])
        XCTAssertEqual(pathComponents.count, 2)
        XCTAssertFalse(pathComponents.isEmpty)
        CollectionChecker.check(pathComponents)
      } else {
        XCTFail("Expected empty, non-nil path components")
      }
    }
    // 3 empty components.
    do {
      let url = WebURL("http://example.com///?someQuery")!
      XCTAssertEqual(url.serialized, "http://example.com///?someQuery")
      XCTAssertEqual(url.path, "///")
      XCTAssertFalse(url._cannotBeABaseURL)
      if let pathComponents = url.pathComponents {
        XCTAssertEqualElements(pathComponents, ["", "", ""])
        XCTAssertEqual(pathComponents.count, 3)
        XCTAssertFalse(pathComponents.isEmpty)
        CollectionChecker.check(pathComponents)
      } else {
        XCTFail("Expected empty, non-nil path components")
      }
    }
    // 4 empty components.
    do {
      let url = WebURL("http://example.com////?someQuery")!
      XCTAssertEqual(url.serialized, "http://example.com////?someQuery")
      XCTAssertEqual(url.path, "////")
      XCTAssertFalse(url._cannotBeABaseURL)
      if let pathComponents = url.pathComponents {
        XCTAssertEqualElements(pathComponents, ["", "", "", ""])
        XCTAssertEqual(pathComponents.count, 4)
        XCTAssertFalse(pathComponents.isEmpty)
        CollectionChecker.check(pathComponents)
      } else {
        XCTFail("Expected empty, non-nil path components")
      }
    }
    // 1 empty + 1 non-empty + 3 empty.
    do {
      let url = WebURL("http://example.com//p///?someQuery")!
      XCTAssertEqual(url.serialized, "http://example.com//p///?someQuery")
      XCTAssertEqual(url.path, "//p///")
      XCTAssertFalse(url._cannotBeABaseURL)
      if let pathComponents = url.pathComponents {
        XCTAssertEqualElements(pathComponents, ["", "p", "", "", ""])
        XCTAssertEqual(pathComponents.count, 5)
        XCTAssertFalse(pathComponents.isEmpty)
        CollectionChecker.check(pathComponents)
      } else {
        XCTFail("Expected empty, non-nil path components")
      }
    }
  }

  func testDirectoryPath() {
    // File paths (i.e. without trailing slash).
    do {
      let url = WebURL("http://example.com/a/b/c?someQuery")!
      XCTAssertEqual(url.serialized, "http://example.com/a/b/c?someQuery")
      XCTAssertEqual(url.path, "/a/b/c")
      XCTAssertFalse(url._cannotBeABaseURL)
      if let pathComponents = url.pathComponents {
        XCTAssertEqualElements(pathComponents, ["a", "b", "c"])
        XCTAssertEqual(pathComponents.count, 3)
        XCTAssertFalse(pathComponents.isEmpty)
        CollectionChecker.check(pathComponents)
      } else {
        XCTFail("Expected empty, non-nil path components")
      }
    }
    // Directory paths (i.e. with trailing slash) have an empty final component.
    do {
      let url = WebURL("http://example.com/a/b/c/?someQuery")!
      XCTAssertEqual(url.serialized, "http://example.com/a/b/c/?someQuery")
      XCTAssertEqual(url.path, "/a/b/c/")
      XCTAssertFalse(url._cannotBeABaseURL)
      if let pathComponents = url.pathComponents {
        XCTAssertEqualElements(pathComponents, ["a", "b", "c", ""])
        XCTAssertEqual(pathComponents.count, 4)
        XCTAssertFalse(pathComponents.isEmpty)
        CollectionChecker.check(pathComponents)
      } else {
        XCTFail("Expected empty, non-nil path components")
      }
    }
  }

  func testComponentEscaping() {
    let url = WebURL("file:///C:/Windows/🦆/System 32/somefile.dll")!
    XCTAssertEqual(url.serialized, "file:///C:/Windows/%F0%9F%A6%86/System%2032/somefile.dll")
    XCTAssertEqual(url.path, "/C:/Windows/%F0%9F%A6%86/System%2032/somefile.dll")
    XCTAssertFalse(url._cannotBeABaseURL)
    if let pathComponents = url.pathComponents {
      XCTAssertEqualElements(pathComponents, ["C:", "Windows", "🦆", "System 32", "somefile.dll"])
      XCTAssertEqual(pathComponents.count, 5)
      XCTAssertFalse(pathComponents.isEmpty)
      CollectionChecker.check(pathComponents)

      for (num, index) in pathComponents.indices.enumerated() {
        switch num {
        case 0: pathComponents.withUTF8(component: index) { XCTAssertEqualElements($0, "C:".utf8) }
        case 1: pathComponents.withUTF8(component: index) { XCTAssertEqualElements($0, "Windows".utf8) }
        case 2: pathComponents.withUTF8(component: index) { XCTAssertEqualElements($0, "%F0%9F%A6%86".utf8) }
        case 3: pathComponents.withUTF8(component: index) { XCTAssertEqualElements($0, "System%2032".utf8) }
        case 4: pathComponents.withUTF8(component: index) { XCTAssertEqualElements($0, "somefile.dll".utf8) }
        default: XCTFail("Too many path components")
        }
      }
    } else {
      XCTFail("Expected empty, non-nil path components")
    }
  }

  func testPastBounds() {
    let url = WebURL("http://example.com/a/b/c/?someQuery")!
    XCTAssertEqual(url.serialized, "http://example.com/a/b/c/?someQuery")
    XCTAssertEqual(url.path, "/a/b/c/")
    XCTAssertFalse(url._cannotBeABaseURL)
    if let pathComponents = url.pathComponents {
      XCTAssertEqualElements(pathComponents, ["a", "b", "c", ""])
      XCTAssertEqual(pathComponents.count, 4)
      XCTAssertFalse(pathComponents.isEmpty)
      CollectionChecker.check(pathComponents)
      // Incrementing endIndex always returns endIndex.
      var index = pathComponents.endIndex
      for _ in 0..<5 {
        index = pathComponents.index(after: index)
        XCTAssertEqual(index, pathComponents.endIndex)
      }
      // Decrementing startIndex always returns startIndex.
      index = pathComponents.startIndex
      for _ in 0..<5 {
        index = pathComponents.index(before: index)
        XCTAssertEqual(index, pathComponents.startIndex)
      }
    } else {
      XCTFail("Expected empty, non-nil path components")
    }
  }

  func testCollectionDistance() {
    let url = WebURL("http://example.com/a/b/c/?someQuery")!
    XCTAssertEqual(url.serialized, "http://example.com/a/b/c/?someQuery")
    XCTAssertEqual(url.path, "/a/b/c/")
    XCTAssertFalse(url._cannotBeABaseURL)
    if let pathComponents = url.pathComponents {
      XCTAssertEqualElements(pathComponents, ["a", "b", "c", ""])
      XCTAssertEqual(pathComponents.count, 4)
      XCTAssertFalse(pathComponents.isEmpty)

      var index = pathComponents.startIndex
      for step in 0..<5 {
        XCTAssertEqual(pathComponents.distance(from: pathComponents.startIndex, to: index), step)
        XCTAssertEqual(pathComponents.distance(from: index, to: pathComponents.startIndex), -step)
        index = pathComponents.index(after: index)
      }
      XCTAssertEqual(index, pathComponents.endIndex)

    } else {
      XCTFail("Expected empty, non-nil path components")
    }
  }
}
