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


// --------------------------------------------
// MARK: - Reading components
// --------------------------------------------


extension PathComponentsTests {

  func testPathComponents_documentationExamples() {
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


// --------------------------------------------
// MARK: - Modifying components
// --------------------------------------------


extension PathComponentsTests {

  func testInPlaceMutation() {
    var url = WebURL("http://example.com/a/b/c/d#someFragmentJustForCapacity")!
    url.fragment = nil  // just to reserve capacity.
    checkDoesNotCopy(&url) { url in
      url.withMutablePathComponents { path in
        let range = path.dropFirst().prefix(2)
        let newRange = path.replaceComponents(
          range.startIndex..<range.endIndex,
          with: [
            "MAKE",
            "S O M E",
            "🔊",
          ])
        XCTAssertEqualElements(path[newRange], ["MAKE", "S O M E", "🔊"])
      }
    }
    XCTAssertEqual(url.serialized, "http://example.com/a/MAKE/S%20O%20M%20E/%F0%9F%94%8A/d")
    XCTAssertEqualElements(url.pathComponents!, ["a", "MAKE", "S O M E", "🔊", "d"])
    XCTAssertURLIsIdempotent(url)

    // Check that COW still happens.
    let copy = url
    url.withMutablePathComponents { path in
      _ = path.replaceComponents(path.startIndex..<path.endIndex, with: ["hello", "world"])
    }
    XCTAssertEqual(url.serialized, "http://example.com/hello/world")
    XCTAssertEqualElements(url.pathComponents!, ["hello", "world"])
    XCTAssertURLIsIdempotent(url)

    XCTAssertEqual(copy.serialized, "http://example.com/a/MAKE/S%20O%20M%20E/%F0%9F%94%8A/d")
    XCTAssertEqualElements(copy.pathComponents!, ["a", "MAKE", "S O M E", "🔊", "d"])
  }

  func testReplaceComponents_Empty() {

    // We cannot set an empty path on a special URL.
    do {
      var url = WebURL("http://example.com/a/b/c/d?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.endIndex, with: [String]())
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "http://example.com/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)
    }
    // "."/".." components are skipped and do not make a path non-empty.
    do {
      var url = WebURL("http://example.com/a/b/c/d?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.endIndex, with: ["%2e%2E", "..", "%2e", "."])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "http://example.com/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)
    }
    // We cannot set an empty path on a non-special URL, unless it has an authority.
    do {
      var url = WebURL("foo:/a/b/c/d?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.endIndex, with: [String]())
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "foo:/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)
    }
    // If the URL has a path sigil, it is removed.
    do {
      var url = WebURL("foo:/.//a/b/c/d?aQuery#someFragment")!
      XCTAssertEqual(url.path, "//a/b/c/d")
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.endIndex, with: [String]())
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "foo:/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)
    }
    do {
      var url = WebURL("foo://example.com/a/b/c/d?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.endIndex, with: [String]())
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], [])
      }
      XCTAssertEqual(url.serialized, "foo://example.com?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [])
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceComponents_RootPath() {

    // If the URL has a root path, the only operations which can be expressed are:
    // - Replacing the entire thing.
    //     Works as any other path - checking that we don't make the path empty, sigils are inserted/removed, etc.
    // - Prepending
    //     Works as any other path - the empty component previously at startIndex moves to startIndex + 1.
    // - Appending
    //     If inserting after the leading "/", the leading component is replaced rather than added to.
    //     e.g. "/" -> append "foo" -> "/foo", not "//foo"

    // Append a non-empty component to a root path.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.endIndex..<editor.endIndex,
          with: [
            "test"
          ])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertNotEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], ["test"])
      }
      XCTAssertEqual(url.serialized, "foo://example.com/test?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["test"])
      XCTAssertURLIsIdempotent(url)
    }

    // Appending an empty component to a root path is a no-op as it is really a replacement.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.endIndex..<editor.endIndex,
          with: [
            ""
          ])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertNotEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "foo://example.com/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)
    }
    // Appending 2 empty components to a root path results in 2 empty components.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.endIndex..<editor.endIndex,
          with: [
            "", "",
          ])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertNotEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], ["", ""])
      }
      XCTAssertEqual(url.serialized, "foo://example.com//?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["", ""])
      XCTAssertURLIsIdempotent(url)
    }

    // Removing the empty subrange after the leading "/" is also a no-op; doesn't remove the path.
    do {
      var url = WebURL("foo://host/?query")!
      url.withMutablePathComponents { path in
        let range = path.replaceComponents(path.endIndex..<path.endIndex, with: [String]())
        XCTAssertEqual(range.lowerBound, path.endIndex)
        XCTAssertEqual(range.upperBound, path.endIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
      }
      XCTAssertEqual(url.serialized, "foo://host/?query")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)
    }

    // Prepending to a root path works as it does for other paths.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.startIndex..<editor.startIndex,
          with: [
            "test"
          ])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.index(after: editor.startIndex))
        XCTAssertNotEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], ["test"])
      }
      XCTAssertEqual(url.serialized, "foo://example.com/test/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["test", ""])
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceComponents_WindowsDriveLetters() {

    // Inserting a non-normalized Windows drive letter.
    // Must be normalized to be idempotent.
    do {
      var url = WebURL("file:///")!
      XCTAssertEqualElements(url.pathComponents!, [""])
      url.withMutablePathComponents { path in
        let range = path.replaceComponents(path.endIndex..<path.endIndex, with: ["C|", "Windows"])
        XCTAssertEqual(range.lowerBound, path.startIndex)
        XCTAssertEqual(range.upperBound, path.endIndex)
        XCTAssertNotEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(path[range], ["C:", "Windows"])
      }
      XCTAssertEqual(url.serialized, "file:///C:/Windows")
      XCTAssertEqualElements(url.pathComponents!, ["C:", "Windows"])
      XCTAssertURLIsIdempotent(url)
    }

    // Does not apply to non-file URLs.
    do {
      var url = WebURL("http://example/")!
      XCTAssertEqualElements(url.pathComponents!, [""])
      url.withMutablePathComponents { path in
        let range = path.replaceComponents(path.endIndex..<path.endIndex, with: ["C|", "Windows"])
        XCTAssertEqual(range.lowerBound, path.startIndex)
        XCTAssertEqual(range.upperBound, path.endIndex)
        XCTAssertNotEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(path[range], ["C|", "Windows"])
      }
      XCTAssertEqual(url.serialized, "http://example/C|/Windows")
      XCTAssertEqualElements(url.pathComponents!, ["C|", "Windows"])
      XCTAssertURLIsIdempotent(url)
    }

    // Removing components which lead to a non-normalized Windows drive letter becoming first.
    // Must be normalized to be idempotent.
    do {
      var url = WebURL("file://host/windrive-blocker/C|/foo/")!
      XCTAssertEqualElements(url.pathComponents!, ["windrive-blocker", "C|", "foo", ""])
      url.withMutablePathComponents { path in
        let range = path.replaceComponents(path.startIndex..<path.index(after: path.startIndex), with: [String]())
        XCTAssertEqual(range.lowerBound, path.startIndex)
        XCTAssertEqual(range.upperBound, path.startIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(path[range], [])
      }
      XCTAssertEqual(url.serialized, "file://host/C:/foo/")
      XCTAssertEqualElements(url.pathComponents!, ["C:", "foo", ""])
      XCTAssertURLIsIdempotent(url)
    }

    // Does not apply to non-file URLs.
    do {
      var url = WebURL("http://host/windrive-blocker/C|/foo/")!
      XCTAssertEqualElements(url.pathComponents!, ["windrive-blocker", "C|", "foo", ""])
      url.withMutablePathComponents { path in
        let range = path.replaceComponents(path.startIndex..<path.index(after: path.startIndex), with: [String]())
        XCTAssertEqual(range.lowerBound, path.startIndex)
        XCTAssertEqual(range.upperBound, path.startIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(path[range], [])
      }
      XCTAssertEqual(url.serialized, "http://host/C|/foo/")
      XCTAssertEqualElements(url.pathComponents!, ["C|", "foo", ""])
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceComponents_Slashes() {

    // Slashes are percent-encoded in inserted components, even though they are not technically
    // part of the 'path' encode-set.
    do {
      var url = WebURL("foo://example.com/a/b?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["//boo/"])
        XCTAssertEqual(range.lowerBound, editor.index(before: editor.endIndex))
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["//boo/"])
      }
      XCTAssertEqual(url.serialized, "foo://example.com/a/b/%2F%2Fboo%2F?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "//boo/"])
      XCTAssertURLIsIdempotent(url)
    }

    // Slashes cannot be used to sneak a "." or ".." component through - at least,
    // not in such a way that it would cause an idempotence failure when reparsed.
    do {
      var url = WebURL("foo://example.com/a/b?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["/.."])
        XCTAssertEqual(range.lowerBound, editor.index(before: editor.endIndex))
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["/.."])
      }
      XCTAssertEqual(url.serialized, "foo://example.com/a/b/%2F..?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "/.."])
      XCTAssertURLIsIdempotent(url)
    }

    // Backslashes are also encoded, as they are treated like regular slashes in special URLs.
    do {
      var url = WebURL("foo://example.com/a/b?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["\\"])
        XCTAssertEqual(range.lowerBound, editor.index(before: editor.endIndex))
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["\\"])
      }
      XCTAssertEqual(url.serialized, "foo://example.com/a/b/%5C?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "\\"])
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceComponents_PathSigil() {
    // A path sigil is required when a non-special URL has:
    // - No authority
    // - More than 1 path component, and
    // - The first path component is empty

    // Insertions at the front of the path.
    do {
      // Sigil should be added when inserting an empty component at the front of the path.
      var url = WebURL("foo:/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "c", "d"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.startIndex, with: [""])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.index(after: editor.startIndex))
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "foo:/.//a/b/c/d?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["", "a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is not added/removed when inserting a non-empty component at the front of the path.
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.startIndex, with: ["not empty"])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.index(after: editor.startIndex))
        XCTAssertEqualElements(editor[range], ["not empty"])
      }
      XCTAssertEqual(url.serialized, "foo:/not%20empty//a/b/c/d?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["not empty", "", "a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is not added/is removed when replacing the empty component at the front of the path with a non-empty one.
      url = WebURL("foo:/.//a/b/c/d?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.index(after: editor.startIndex), with: ["book"])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.index(after: editor.startIndex))
        XCTAssertEqualElements(editor[range], ["book"])
      }
      XCTAssertEqual(url.serialized, "foo:/book/a/b/c/d?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["book", "a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is _not_ added when inserting an empty component at the front of the path _if authority present_.
      url = WebURL("foo://host/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "c", "d"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.startIndex, with: [""])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.index(after: editor.startIndex))
        XCTAssertEqualElements(editor[range], [""])
      }
      XCTAssertEqual(url.serialized, "foo://host//a/b/c/d?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["", "a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)
    }

    // Removals at the front of the path.
    do {
      // Sigil is removed if the empty component at the front is removed.
      var url = WebURL("foo:/.//a/b/c/d?aQuery#someFragment")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.startIndex..<editor.index(after: editor.startIndex),
          with: [String]()
        )
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.startIndex)
        XCTAssertEqualElements(editor[range], [])
      }
      XCTAssertEqual(url.serialized, "foo:/a/b/c/d?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is inserted when a removal at the front causes an empty component to become first.
      url = WebURL("foo:/a/b//c")!
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "", "c"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.startIndex..<editor.index(editor.startIndex, offsetBy: 2),
          with: [String]()
        )
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.startIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], [])
      }
      XCTAssertEqual(url.serialized, "foo:/.//c")
      XCTAssertEqualElements(url.pathComponents!, ["", "c"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is _not_ inserted when a removal at the front causes an empty component to become first _if authority present_.
      url = WebURL("foo://host/a/b//c")!
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "", "c"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.startIndex..<editor.index(editor.startIndex, offsetBy: 2),
          with: [String]()
        )
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.startIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], [])
      }
      XCTAssertEqual(url.serialized, "foo://host//c")
      XCTAssertEqualElements(url.pathComponents!, ["", "c"])
      XCTAssertURLIsIdempotent(url)
    }

    // Insertions after the first path component.
    do {
      // Sigil is inserted if appending components beginning with an empty to a root path.
      var url = WebURL("foo:/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, [""])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["", "f"])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["", "f"])
      }
      XCTAssertEqual(url.serialized, "foo:/.//f?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["", "f"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is unaffected by appending a component to a root path, due to special-casing appends to root paths.
      url = WebURL("foo:/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, [""])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["f"])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["f"])
      }
      XCTAssertEqual(url.serialized, "foo:/f?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["f"])
      XCTAssertURLIsIdempotent(url)

      // Sigil is unaffected by appending components after the 2nd component.
      url = WebURL("foo:/.//a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, ["", "a", "b"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["c"])
        XCTAssertEqual(range.lowerBound, editor.index(before: editor.endIndex))
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["c"])
      }
      XCTAssertEqual(url.serialized, "foo:/.//a/b/c?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["", "a", "b", "c"])
      XCTAssertURLIsIdempotent(url)

      url = WebURL("foo:/a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, ["a", "b"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.endIndex..<editor.endIndex, with: ["c"])
        XCTAssertEqual(range.lowerBound, editor.index(before: editor.endIndex))
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["c"])
      }
      XCTAssertEqual(url.serialized, "foo:/a/b/c?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["a", "b", "c"])
      XCTAssertURLIsIdempotent(url)
    }

    // Removals after the first component.
    do {
      // Sigil is removed if every component but the first is removed.
      var url = WebURL("foo:/.//a?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, ["", "a"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.index(after: editor.startIndex)..<editor.endIndex, with: [String]())
        XCTAssertEqual(range.lowerBound, editor.endIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], [])
      }
      XCTAssertEqual(url.serialized, "foo:/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, [""])
      XCTAssertURLIsIdempotent(url)

      // Sigil is unaffected when removing components after the 2nd one.
      url = WebURL("foo:/.//a/b/c?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents!, ["", "a", "b", "c"])
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(
          editor.index(editor.startIndex, offsetBy: 2)..<editor.endIndex,
          with: [String]()
        )
        XCTAssertEqual(range.lowerBound, editor.index(editor.startIndex, offsetBy: 2))
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertEqualElements(editor[range], [])
      }
      XCTAssertEqual(url.serialized, "foo:/.//a?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents!, ["", "a"])
      XCTAssertURLIsIdempotent(url)
    }

    // Entire path replacement.
    do {
      // Sigil is inserted when replacing the entire path contents.
      var url = WebURL("foo:/a/b/c")!
      url.withMutablePathComponents { editor in
        let range = editor.replaceComponents(editor.startIndex..<editor.endIndex, with: ["", "g"])
        XCTAssertEqual(range.lowerBound, editor.startIndex)
        XCTAssertEqual(range.upperBound, editor.endIndex)
        XCTAssertEqualElements(editor[range], ["", "g"])
      }
      XCTAssertEqual(url.serialized, "foo:/.//g")
      XCTAssertEqualElements(url.pathComponents!, ["", "g"])
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceComponents() {
    // Test replacement:
    // - At the start
    // - In the middle
    // - At the end
    // and with the given range:
    // - Shrinking (removing some elements, inserting fewer elements)
    // - Growing   (removing some elements, inserting more elements)
    // - Removing  (removing some elements, inserting no elements)
    // - Inserting (removing no elements)

    // Shrink at the start.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.startIndex..<path.index(path.startIndex, offsetBy: 2),
          with: [
            "a"
          ])
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/3")
      XCTAssertEqual(url.path, "/a/3")
      XCTAssertEqual(url.pathComponents!.count, 2)
      XCTAssertEqual(url.pathComponents!.startIndex, range.lowerBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a"])
      XCTAssertURLIsIdempotent(url)
    }

    // Shrink in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.index(after: path.startIndex)..<path.index(path.startIndex, offsetBy: 3),
          with: [
            "a"
          ])
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/a/4")
      XCTAssertEqual(url.path, "/1/a/4")
      XCTAssertEqual(url.pathComponents!.count, 3)
      XCTAssertEqual(url.pathComponents!.index(after: url.pathComponents!.startIndex), range.lowerBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a"])
      XCTAssertURLIsIdempotent(url)
    }

    // Shrink at the end.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.index(path.endIndex, offsetBy: -2)..<path.endIndex,
          with: [
            "a"
          ])
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2/a")
      XCTAssertEqual(url.path, "/1/2/a")
      XCTAssertEqual(url.pathComponents!.count, 3)
      XCTAssertEqual(url.pathComponents!.index(before: url.pathComponents!.endIndex), range.lowerBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a"])
      XCTAssertURLIsIdempotent(url)
    }

    // Grow at the start.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.startIndex..<path.index(path.startIndex, offsetBy: 2),
          with: [
            "a", "b", "c", "d",
          ])
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b/c/d/3")
      XCTAssertEqual(url.path, "/a/b/c/d/3")
      XCTAssertEqual(url.pathComponents!.count, 5)
      XCTAssertEqual(url.pathComponents!.startIndex, range.lowerBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)
    }

    // Grow in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.index(after: path.startIndex)..<path.index(before: path.endIndex),
          with: [
            "a", "b", "c", "d",
          ])
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/a/b/c/d/3")
      XCTAssertEqual(url.path, "/1/a/b/c/d/3")
      XCTAssertEqual(url.pathComponents!.count, 6)
      XCTAssertEqual(url.pathComponents!.index(after: url.pathComponents!.startIndex), range.lowerBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)
    }

    // Grow at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.index(before: path.endIndex)..<path.endIndex,
          with: [
            "a", "b", "c", "d",
          ])
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2/a/b/c/d")
      XCTAssertEqual(url.path, "/1/2/a/b/c/d")
      XCTAssertEqual(url.pathComponents!.count, 6)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 2), range.lowerBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b", "c", "d"])
      XCTAssertURLIsIdempotent(url)
    }

    // Remove from the start.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.startIndex..<path.index(path.startIndex, offsetBy: 2),
          with: [String]())
      }
      XCTAssertEqual(url.serialized, "http://example.com/3/4")
      XCTAssertEqual(url.path, "/3/4")
      XCTAssertEqual(url.pathComponents!.count, 2)
      XCTAssertEqual(url.pathComponents!.startIndex, range.lowerBound)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], [])
      XCTAssertURLIsIdempotent(url)
    }

    // Remove from the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.index(after: path.startIndex)..<path.index(before: path.endIndex),
          with: [String]())
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/4")
      XCTAssertEqual(url.path, "/1/4")
      XCTAssertEqual(url.pathComponents!.count, 2)
      XCTAssertEqual(url.pathComponents!.index(after: url.pathComponents!.startIndex), range.lowerBound)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], [])
      XCTAssertURLIsIdempotent(url)
    }

    // Remove from the end.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(
          path.index(path.endIndex, offsetBy: -2)..<path.endIndex,
          with: [String]())
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2")
      XCTAssertEqual(url.path, "/1/2")
      XCTAssertEqual(url.pathComponents!.count, 2)
      XCTAssertEqual(url.pathComponents!.endIndex, range.lowerBound)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], [])
      XCTAssertURLIsIdempotent(url)
    }

    // Insert elements at the start.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path in
        path.replaceComponents(path.startIndex..<path.startIndex, with: ["a", "b"])
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b/1/2/3")
      XCTAssertEqual(url.path, "/a/b/1/2/3")
      XCTAssertEqual(url.pathComponents!.count, 5)
      XCTAssertEqual(url.pathComponents!.startIndex, range.lowerBound)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 2), range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b"])
      XCTAssertURLIsIdempotent(url)
    }

    // Insert in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path -> Range<PathComponentIndex> in
        let insertionPoint = path.index(path.startIndex, offsetBy: 2)
        return path.replaceComponents(insertionPoint..<insertionPoint, with: ["a", "b"])
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2/a/b/3/4")
      XCTAssertEqual(url.path, "/1/2/a/b/3/4")
      XCTAssertEqual(url.pathComponents!.count, 6)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 2), range.lowerBound)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 4), range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b"])
      XCTAssertURLIsIdempotent(url)
    }

    // Insert at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path -> Range<PathComponentIndex> in
        return path.replaceComponents(path.endIndex..<path.endIndex, with: ["a", "b"])
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2/3/a/b")
      XCTAssertEqual(url.path, "/1/2/3/a/b")
      XCTAssertEqual(url.pathComponents!.count, 5)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 3), range.lowerBound)
      XCTAssertEqual(url.pathComponents!.endIndex, range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b"])
      XCTAssertURLIsIdempotent(url)
    }
  }
}

extension PathComponentsTests {

  func testInsertContents() {
    // Insert at the front.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path in
        path.insert(contentsOf: ["a", "b"], at: path.startIndex)
      }
      XCTAssertEqual(url.serialized, "http://example.com/a/b/1/2/3")
      XCTAssertEqual(url.path, "/a/b/1/2/3")
      XCTAssertEqual(url.pathComponents!.count, 5)
      XCTAssertEqual(url.pathComponents!.startIndex, range.lowerBound)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 2), range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b"])
      XCTAssertURLIsIdempotent(url)
    }

    // Insert in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      let range = url.withMutablePathComponents { path -> Range<PathComponentIndex> in
        return path.insert(contentsOf: ["a", "b"], at: path.index(path.startIndex, offsetBy: 2))
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2/a/b/3/4")
      XCTAssertEqual(url.path, "/1/2/a/b/3/4")
      XCTAssertEqual(url.pathComponents!.count, 6)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 2), range.lowerBound)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 4), range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b"])
      XCTAssertURLIsIdempotent(url)
    }

    // Insert at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      let range = url.withMutablePathComponents { path -> Range<PathComponentIndex> in
        return path.insert(contentsOf: ["a", "b"], at: path.endIndex)
      }
      XCTAssertEqual(url.serialized, "http://example.com/1/2/3/a/b")
      XCTAssertEqual(url.path, "/1/2/3/a/b")
      XCTAssertEqual(url.pathComponents!.count, 5)
      XCTAssertEqual(url.pathComponents!.index(url.pathComponents!.startIndex, offsetBy: 3), range.lowerBound)
      XCTAssertEqual(url.pathComponents!.endIndex, range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], ["a", "b"])
      XCTAssertURLIsIdempotent(url)
    }

    // Insert to introduce path sigil.
    do {
      var url = WebURL("foo:/1/2/3")!
      let range = url.withMutablePathComponents { path -> Range<PathComponentIndex> in
        return path.insert(contentsOf: [""], at: path.startIndex)
      }
      XCTAssertEqual(url.serialized, "foo:/.//1/2/3")
      XCTAssertEqual(url.path, "//1/2/3")
      XCTAssertEqual(url.pathComponents!.count, 4)
      XCTAssertEqual(url.pathComponents!.startIndex, range.lowerBound)
      XCTAssertEqual(url.pathComponents!.index(after: url.pathComponents!.startIndex), range.upperBound)
      XCTAssertEqualElements(url.pathComponents![range], [""])
      XCTAssertURLIsIdempotent(url)
    }
  }
}
