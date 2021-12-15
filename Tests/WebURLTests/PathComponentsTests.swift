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

    // WebURL.PathComponents type.
    do {
      var url = WebURL("http://example.com/swift/packages/%F0%9F%A6%86%20tracker")!
      XCTAssertEqual(url.pathComponents.first, "swift")
      XCTAssertEqual(url.pathComponents.last, "🦆 tracker")

      url.pathComponents.removeLast()
      url.pathComponents.append("swift-url")
      XCTAssertEqual(url.serialized(), "http://example.com/swift/packages/swift-url")
    }
    do {
      var url = WebURL("file:///")!
      XCTAssertEqual(url.pathComponents.last, "")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents.append("usr")
      XCTAssertEqual(url.serialized(), "file:///usr")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents += ["bin", "swift"]
      XCTAssertEqual(url.serialized(), "file:///usr/bin/swift")
      XCTAssertEqual(url.pathComponents.last, "swift")
      XCTAssertEqual(url.pathComponents.count, 3)

      url.pathComponents.ensureDirectoryPath()
      XCTAssertEqual(url.serialized(), "file:///usr/bin/swift/")
      XCTAssertEqual(url.pathComponents.last, "")
      XCTAssertEqual(url.pathComponents.count, 4)
    }
    // WebURL.PathComponents.subscript(raw)
    do {
      let url = WebURL("https://example.com/music/bands/AC%2FDC")!
      XCTAssertEqual(url.pathComponents[url.pathComponents.indices.last!], "AC/DC")
      XCTAssertEqual(url.pathComponents[raw: url.pathComponents.indices.last!], "AC%2FDC")
    }
    // WebURL.PathComponents.replaceSubrange
    do {
      var url = WebURL("file:///usr/bin/swift")!
      let lastTwo = url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2)..<url.pathComponents.endIndex
      url.pathComponents.replaceSubrange(
        lastTwo,
        with: [
          "lib",
          "swift",
          "linux",
          "libswiftCore.so",
        ])
      XCTAssertEqual(url.serialized(), "file:///usr/lib/swift/linux/libswiftCore.so")
    }
    do {
      var url = WebURL("file:///usr/")!
      XCTAssertEqual(url.pathComponents.last, "")
      XCTAssertEqual(url.pathComponents.count, 2)
      url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["bin", "swift"]
      )
      XCTAssertEqual(url.serialized(), "file:///usr/bin/swift")
      XCTAssertEqual(url.pathComponents.last, "swift")
      XCTAssertEqual(url.pathComponents.count, 3)
    }
    do {
      var url = WebURL("http://example.com/awesome_product/index.html")!
      XCTAssertEqual(url.pathComponents.first, "awesome_product")
      XCTAssertEqual(url.pathComponents.count, 2)
      url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [] as [String]
      )
      XCTAssertEqual(url.serialized(), "http://example.com/")
      XCTAssertEqual(url.pathComponents.first, "")
      XCTAssertEqual(url.pathComponents.count, 1)
    }
    // WebURL.PathComponents.replaceSubrange(_:withPercentEncodedComponents:)
    do {
      let url = WebURL("http://example.com/music/bands")!

      var urlA = url
      urlA.pathComponents.replaceSubrange(
        urlA.pathComponents.endIndex..<urlA.pathComponents.endIndex,
        with: ["The%20Beatles"]
      )
      XCTAssertEqual(urlA.serialized(), "http://example.com/music/bands/The%2520Beatles")
      //---
      var urlB = url
      urlB.pathComponents.replaceSubrange(
        urlB.pathComponents.endIndex..<urlB.pathComponents.endIndex,
        withPercentEncodedComponents: ["The%20Beatles"]
      )
      XCTAssertEqual(urlB.serialized(), "http://example.com/music/bands/The%20Beatles")
    }
    // WebURL.PathComponents.insert(contentsOf:at:)
    do {
      var url = WebURL("file:///usr/swift")!
      url.pathComponents.insert(
        contentsOf: ["local", "bin"], at: url.pathComponents.index(after: url.pathComponents.startIndex)
      )
      XCTAssertEqual(url.serialized(), "file:///usr/local/bin/swift")
    }
    // WebURL.PathComponents.append(contentsOf:)
    do {
      var url = WebURL("file:///")!
      XCTAssertEqual(url.pathComponents.last, "")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents.append(contentsOf: ["tmp"])
      XCTAssertEqual(url.pathComponents.last, "tmp")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents.append(contentsOf: ["my_app", "data.json"])
      XCTAssertEqual(url.serialized(), "file:///tmp/my_app/data.json")
      XCTAssertEqual(url.pathComponents.last, "data.json")
      XCTAssertEqual(url.pathComponents.count, 3)
    }
    // WebURL.PathComponents.+=
    do {
      var url = WebURL("file:///")!
      XCTAssertEqual(url.pathComponents.last, "")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents += ["tmp"]
      XCTAssertEqual(url.pathComponents.last, "tmp")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents += ["my_app", "data.json"]
      XCTAssertEqual(url.serialized(), "file:///tmp/my_app/data.json")
      XCTAssertEqual(url.pathComponents.last, "data.json")
      XCTAssertEqual(url.pathComponents.count, 3)
    }
    // WebURL.PathComponents.removeSubrange(_:)
    do {
      var url = WebURL("http://example.com/projects/swift/swift-url/")!
      url.pathComponents.removeSubrange(
        url.pathComponents.index(after: url.pathComponents.startIndex)..<url.pathComponents.endIndex
      )
      XCTAssertEqual(url.serialized(), "http://example.com/projects")
    }
    do {
      var url = WebURL("http://example.com/awesome_product/index.html")!
      url.pathComponents.removeSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex
      )
      XCTAssertEqual(url.serialized(), "http://example.com/")
    }
    // WebURL.PathComponents.replaceComponent(at:with:)
    do {
      var url = WebURL("file:///usr/bin/swift")!
      url.pathComponents.replaceComponent(
        at: url.pathComponents.index(after: url.pathComponents.startIndex),
        with: "lib"
      )
      XCTAssertEqual(url.serialized(), "file:///usr/lib/swift")
    }
    // WebURL.PathComponents.insert(_:at:)
    do {
      var url = WebURL("file:///usr/swift")!
      url.pathComponents.insert("bin", at: url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(url.serialized(), "file:///usr/bin/swift")
    }
    // WebURL.PathComponents.append(_:)
    do {
      var url = WebURL("file:///")!
      XCTAssertEqual(url.pathComponents.last, "")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents.append("tmp")
      XCTAssertEqual(url.pathComponents.last!, "tmp")
      XCTAssertEqual(url.pathComponents.count, 1)

      url.pathComponents.append("data.json")
      XCTAssertEqual(url.serialized(), "file:///tmp/data.json")
      XCTAssertEqual(url.pathComponents.last, "data.json")
      XCTAssertEqual(url.pathComponents.count, 2)
    }
    // WebURL.PathComponents.remove(at:)
    do {
      var url = WebURL("http://example.com/projects/swift/swift-url/Sources/")!
      url.pathComponents.remove(at: url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(url.serialized(), "http://example.com/projects/swift-url/Sources/")
    }
    do {
      var url = WebURL("http://example.com/foo")!
      url.pathComponents.remove(at: url.pathComponents.startIndex)
      XCTAssertEqual(url.serialized(), "http://example.com/")
    }
    // WebURL.PathComponents.removeLast(_:)
    do {
      var url = WebURL("http://example.com/foo/bar")!
      url.pathComponents.removeLast()
      XCTAssertEqual(url.serialized(), "http://example.com/foo")

      url.pathComponents.removeLast()
      XCTAssertEqual(url.serialized(), "http://example.com/")
    }
    // WebURL.PathComponents.ensureDirectoryPath()
    do {
      var url = WebURL("file:///")!

      url.pathComponents += ["Users", "karl", "Desktop"]
      XCTAssertEqual(url.serialized(), "file:///Users/karl/Desktop")

      url.pathComponents.ensureDirectoryPath()
      XCTAssertEqual(url.serialized(), "file:///Users/karl/Desktop/")
    }
  }

  func testURLWithNoPath() {

    let url = WebURL("foo://somehost?someQuery")!
    XCTAssertEqual(url.serialized(), "foo://somehost?someQuery")
    XCTAssertEqual(url.path, "")
    XCTAssertFalse(url.hasOpaquePath)

    XCTAssertEqualElements(url.pathComponents, [])
    XCTAssertEqual(url.pathComponents.count, 0)
    XCTAssertTrue(url.pathComponents.isEmpty)
    CollectionChecker.check(url.pathComponents)
  }

  func testURLWithRootPath() {

    let url = WebURL("http://example.com/?someQuery")!
    XCTAssertEqual(url.serialized(), "http://example.com/?someQuery")
    XCTAssertEqual(url.path, "/")
    XCTAssertFalse(url.hasOpaquePath)

    XCTAssertEqualElements(url.pathComponents, [""])
    XCTAssertEqual(url.pathComponents.count, 1)
    XCTAssertFalse(url.pathComponents.isEmpty)
    CollectionChecker.check(url.pathComponents)
  }

  func testPathOnlyURL() {

    let url = WebURL("foo:/a/b/c")!
    XCTAssertEqual(url.serialized(), "foo:/a/b/c")
    XCTAssertEqual(url.path, "/a/b/c")
    XCTAssertFalse(url.hasOpaquePath)

    XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])
    XCTAssertEqual(url.pathComponents.count, 3)
    XCTAssertFalse(url.pathComponents.isEmpty)
    CollectionChecker.check(url.pathComponents)
  }

  func testEmptyComponents() {

    // 2 empty components.
    do {
      let url = WebURL("http://example.com//?someQuery")!
      XCTAssertEqual(url.serialized(), "http://example.com//?someQuery")
      XCTAssertEqual(url.path, "//")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertEqualElements(url.pathComponents, ["", ""])
      XCTAssertEqual(url.pathComponents.count, 2)
      XCTAssertFalse(url.pathComponents.isEmpty)
      CollectionChecker.check(url.pathComponents)
    }
    // 3 empty components.
    do {
      let url = WebURL("http://example.com///?someQuery")!
      XCTAssertEqual(url.serialized(), "http://example.com///?someQuery")
      XCTAssertEqual(url.path, "///")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertEqualElements(url.pathComponents, ["", "", ""])
      XCTAssertEqual(url.pathComponents.count, 3)
      XCTAssertFalse(url.pathComponents.isEmpty)
      CollectionChecker.check(url.pathComponents)
    }
    // 4 empty components.
    do {
      let url = WebURL("http://example.com////?someQuery")!
      XCTAssertEqual(url.serialized(), "http://example.com////?someQuery")
      XCTAssertEqual(url.path, "////")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertEqualElements(url.pathComponents, ["", "", "", ""])
      XCTAssertEqual(url.pathComponents.count, 4)
      XCTAssertFalse(url.pathComponents.isEmpty)
      CollectionChecker.check(url.pathComponents)
    }
    // 1 empty + 1 non-empty + 3 empty.
    do {
      let url = WebURL("http://example.com//p///?someQuery")!
      XCTAssertEqual(url.serialized(), "http://example.com//p///?someQuery")
      XCTAssertEqual(url.path, "//p///")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertEqualElements(url.pathComponents, ["", "p", "", "", ""])
      XCTAssertEqual(url.pathComponents.count, 5)
      XCTAssertFalse(url.pathComponents.isEmpty)
      CollectionChecker.check(url.pathComponents)
    }
  }

  func testDirectoryPath() {

    // File paths (i.e. without trailing slash).
    do {
      let url = WebURL("http://example.com/a/b/c?someQuery")!
      XCTAssertEqual(url.serialized(), "http://example.com/a/b/c?someQuery")
      XCTAssertEqual(url.path, "/a/b/c")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])
      XCTAssertEqual(url.pathComponents.count, 3)
      XCTAssertFalse(url.pathComponents.isEmpty)
      CollectionChecker.check(url.pathComponents)
    }
    // Directory paths (i.e. with trailing slash) have an empty final component.
    do {
      let url = WebURL("http://example.com/a/b/c/?someQuery")!
      XCTAssertEqual(url.serialized(), "http://example.com/a/b/c/?someQuery")
      XCTAssertEqual(url.path, "/a/b/c/")
      XCTAssertFalse(url.hasOpaquePath)

      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", ""])
      XCTAssertEqual(url.pathComponents.count, 4)
      XCTAssertFalse(url.pathComponents.isEmpty)
      CollectionChecker.check(url.pathComponents)
    }
  }

  func testComponentEscaping() {
    // Check that components are unescaped when reading.
    let url = WebURL("file:///C:/Windows/🦆/System 32/somefile.dll")!
    XCTAssertEqual(url.serialized(), "file:///C:/Windows/%F0%9F%A6%86/System%2032/somefile.dll")
    XCTAssertEqual(url.path, "/C:/Windows/%F0%9F%A6%86/System%2032/somefile.dll")
    XCTAssertFalse(url.hasOpaquePath)

    XCTAssertEqualElements(url.pathComponents, ["C:", "Windows", "🦆", "System 32", "somefile.dll"])
    XCTAssertEqual(url.pathComponents.count, 5)
    XCTAssertFalse(url.pathComponents.isEmpty)
    CollectionChecker.check(url.pathComponents)

    for (num, index) in url.pathComponents.indices.enumerated() {
      switch num {
      case 0: XCTAssertEqualElements(url.utf8.pathComponent(index), "C:".utf8)
      case 1: XCTAssertEqualElements(url.utf8.pathComponent(index), "Windows".utf8)
      case 2: XCTAssertEqualElements(url.utf8.pathComponent(index), "%F0%9F%A6%86".utf8)
      case 3: XCTAssertEqualElements(url.utf8.pathComponent(index), "System%2032".utf8)
      case 4: XCTAssertEqualElements(url.utf8.pathComponent(index), "somefile.dll".utf8)
      default: XCTFail("Too many path components")
      }
    }
  }

  func testPassingBounds() {

    let url = WebURL("http://example.com/a/b/c/?someQuery")!
    XCTAssertEqual(url.serialized(), "http://example.com/a/b/c/?someQuery")
    XCTAssertEqual(url.path, "/a/b/c/")
    XCTAssertFalse(url.hasOpaquePath)

    XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", ""])
    XCTAssertEqual(url.pathComponents.count, 4)
    XCTAssertFalse(url.pathComponents.isEmpty)
    CollectionChecker.check(url.pathComponents)
    // Incrementing endIndex always returns endIndex.
    var index = url.pathComponents.endIndex
    for _ in 0..<5 {
      index = url.pathComponents.index(after: index)
      XCTAssertEqual(index, url.pathComponents.endIndex)
    }
    // Decrementing startIndex always returns startIndex.
    index = url.pathComponents.startIndex
    for _ in 0..<5 {
      index = url.pathComponents.index(before: index)
      XCTAssertEqual(index, url.pathComponents.startIndex)
    }
  }

  func testCollectionDistance() {

    let url = WebURL("http://example.com/a/b/c/?someQuery")!
    XCTAssertEqual(url.serialized(), "http://example.com/a/b/c/?someQuery")
    XCTAssertEqual(url.path, "/a/b/c/")
    XCTAssertFalse(url.hasOpaquePath)

    XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", ""])
    XCTAssertEqual(url.pathComponents.count, 4)
    XCTAssertFalse(url.pathComponents.isEmpty)

    var index = url.pathComponents.startIndex
    for step in 0..<5 {
      XCTAssertEqual(url.pathComponents.distance(from: url.pathComponents.startIndex, to: index), step)
      XCTAssertEqual(url.pathComponents.distance(from: index, to: url.pathComponents.startIndex), -step)
      index = url.pathComponents.index(after: index)
    }
    XCTAssertEqual(index, url.pathComponents.endIndex)
  }
}


// --------------------------------------------
// MARK: - Modifying components
// --------------------------------------------


extension PathComponentsTests {

  func testInPlaceMutation() {

    // Check that we can modify a URL in-place via the '.pathComponents' view.
    var url = WebURL("http://example.com/a/b/c/d")!
    XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

    let slice = url.pathComponents.dropFirst().prefix(2)
    let range = url.pathComponents.replaceSubrange(slice.startIndex..<slice.endIndex, with: ["MAKE", "S O M E", "🔊"])

    XCTAssertEqualElements(url.pathComponents, ["a", "MAKE", "S O M E", "🔊", "d"])
    XCTAssertEqualElements(url.pathComponents[range], ["MAKE", "S O M E", "🔊"])
    XCTAssertEqual(url.serialized(), "http://example.com/a/MAKE/S%20O%20M%20E/%F0%9F%94%8A/d")
    XCTAssertURLIsIdempotent(url)

    // Check that COW still happens if the storage is not uniquely-referenced.
    let copy = url
    url.pathComponents.replaceSubrange(
      url.pathComponents.startIndex..<url.pathComponents.endIndex, with: ["hello", "world"]
    )
    XCTAssertEqualElements(url.pathComponents, ["hello", "world"])
    XCTAssertEqual(url.serialized(), "http://example.com/hello/world")
    XCTAssertURLIsIdempotent(url)

    XCTAssertEqualElements(copy.pathComponents, ["a", "MAKE", "S O M E", "🔊", "d"])
    XCTAssertEqual(copy.serialized(), "http://example.com/a/MAKE/S%20O%20M%20E/%F0%9F%94%8A/d")
    XCTAssertURLIsIdempotent(copy)
  }

  func testStorageAndAssignment() {

    // Basic storage and assignment.
    do {
      // Check that we can store a freestanding path components object and mutate it independently.
      var url = WebURL("http://example.com/a/b/c/d")!
      XCTAssertEqual(url.serialized(), "http://example.com/a/b/c/d")
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      var freestandingComponents = url.pathComponents
      freestandingComponents.append("e")
      XCTAssertEqualElements(freestandingComponents, ["a", "b", "c", "d", "e"])
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])
      XCTAssertEqual(url.serialized(), "http://example.com/a/b/c/d")
      XCTAssertURLIsIdempotent(url)

      url.path = ""
      url.pathComponents.append("test")

      XCTAssertEqualElements(freestandingComponents, ["a", "b", "c", "d", "e"])
      XCTAssertEqualElements(url.pathComponents, ["test"])
      XCTAssertEqual(url.serialized(), "http://example.com/test")
      XCTAssertURLIsIdempotent(url)

      // Check that we can assign path components to a different URL.
      var otherURL = WebURL("file://my-pc/some/path/")!
      XCTAssertEqual(otherURL.serialized(), "file://my-pc/some/path/")
      XCTAssertEqualElements(otherURL.pathComponents, ["some", "path", ""])

      otherURL.pathComponents = freestandingComponents
      XCTAssertEqual(otherURL.serialized(), "file://my-pc/a/b/c/d/e")
      XCTAssertEqualElements(otherURL.pathComponents, ["a", "b", "c", "d", "e"])
      XCTAssertURLIsIdempotent(otherURL)
    }

    // Path components (and the resulting path string) are largely independent of the rest of the URL,
    // which makes assignment between URLs possible. The only elements which take the surrounding URL
    // in to consideration are:
    //
    // - Path sigil (may be required or not depending on the path contents)
    // - Empty paths (may/may not be allowed, depending on scheme and presence of an authority).

    // Path sigil.
    do {
      let componentsRequiringSigil = WebURL("file:////test")!.pathComponents
      XCTAssertEqualElements(componentsRequiringSigil, ["", "test"])

      let componentsWithoutSigil = WebURL("file:///boo")!.pathComponents
      XCTAssertEqualElements(componentsWithoutSigil, ["boo"])

      // Sigil is added/removed based on the combination of components and surrounding context.
      do {
        var url = WebURL("foo:/")!
        XCTAssertEqual(url.serialized(), "foo:/")
        XCTAssertEqualElements(url.pathComponents, [""])

        url.pathComponents = componentsRequiringSigil
        XCTAssertEqual(url.serialized(), "foo:/.//test")
        XCTAssertEqualElements(url.pathComponents, ["", "test"])
        XCTAssertURLIsIdempotent(url)

        url.pathComponents = componentsWithoutSigil
        XCTAssertEqual(url.serialized(), "foo:/boo")
        XCTAssertEqualElements(url.pathComponents, ["boo"])
        XCTAssertURLIsIdempotent(url)
      }
      // As above, but in a context where no sigil is required.
      do {
        var url = WebURL("foo://host")!
        XCTAssertEqual(url.serialized(), "foo://host")
        XCTAssertEqualElements(url.pathComponents, [])

        url.pathComponents = componentsRequiringSigil
        XCTAssertEqual(url.serialized(), "foo://host//test")
        XCTAssertEqualElements(url.pathComponents, ["", "test"])
        XCTAssertURLIsIdempotent(url)

        url.pathComponents = componentsWithoutSigil
        XCTAssertEqual(url.serialized(), "foo://host/boo")
        XCTAssertEqualElements(url.pathComponents, ["boo"])
        XCTAssertURLIsIdempotent(url)
      }
    }
    // Empty paths.
    do {
      let emptyComponents = WebURL("foo://host")!.pathComponents
      XCTAssertEqualElements(emptyComponents, [])

      // Empty components allowed for non-special schemes with host.
      do {
        var url = WebURL("ssh://my-pc/some/path")!
        XCTAssertEqual(url.serialized(), "ssh://my-pc/some/path")
        XCTAssertEqualElements(url.pathComponents, ["some", "path"])

        url.pathComponents = emptyComponents
        XCTAssertEqual(url.serialized(), "ssh://my-pc")
        XCTAssertEqualElements(url.pathComponents, [])
        XCTAssertURLIsIdempotent(url)
      }
      // Empty components not allowed for non-special schemes without host.
      do {
        var url = WebURL("bar:/a/path")!
        XCTAssertEqual(url.serialized(), "bar:/a/path")
        XCTAssertEqualElements(url.pathComponents, ["a", "path"])

        url.pathComponents = emptyComponents
        XCTAssertEqual(url.serialized(), "bar:/")
        XCTAssertEqualElements(url.pathComponents, [""])
        XCTAssertURLIsIdempotent(url)
      }
      // Empty components not allowed for special schemes.
      do {
        var url = WebURL("http://example.com/paul/john/george/ringo")!
        XCTAssertEqual(url.serialized(), "http://example.com/paul/john/george/ringo")
        XCTAssertEqualElements(url.pathComponents, ["paul", "john", "george", "ringo"])

        url.pathComponents = emptyComponents
        XCTAssertEqual(url.serialized(), "http://example.com/")
        XCTAssertEqualElements(url.pathComponents, [""])
        XCTAssertURLIsIdempotent(url)
      }
    }
  }

  func testReplaceSubrange_EmptyPaths() {

    // We cannot set an empty path on a special URL.
    do {
      var url = WebURL("http://example.com/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "http://example.com/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // "."/".." components are skipped and do not make a path non-empty.
    do {
      var url = WebURL("http://example.com/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: ["%2e%2E", "..", "%2e", "."]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "http://example.com/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // We cannot set an empty path on a non-special URL, unless it has an authority.
    do {
      var url = WebURL("foo:/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "foo:/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Non-special URLs with an authority support empty paths.
    do {
      var url = WebURL("foo://example.com/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertEqualElements(url.pathComponents[range], [])

      XCTAssertEqual(url.serialized(), "foo://example.com?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // If the URL has a path sigil, it is removed when setting an empty path.
    do {
      var url = WebURL("foo:/.//a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "foo:/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // We can add components to a non-opaque, empty path.
    do {
      var url = WebURL("foo://somehost?someQuery")!
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertFalse(url.hasOpaquePath)

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: ["a", "b", "c"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b", "c"])

      XCTAssertEqual(url.serialized(), "foo://somehost/a/b/c?someQuery")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange_DirectoryPath() {

    // Append a non-empty component to a directory path.
    do {
      var url = WebURL("file:///usr/lib/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["swift"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", "swift"])
      XCTAssertEqualElements(url.pathComponents[range], ["swift"])

      XCTAssertEqual(url.serialized(), "file:///usr/lib/swift?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Appending a single empty component to a directory path does not actually change the path.
    do {
      var url = WebURL("file:///usr/lib/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "file:///usr/lib/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // You can even append multiple times and they all result in no change.
      _ = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(url.serialized(), "file:///usr/lib/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      _ = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(url.serialized(), "file:///usr/lib/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      _ = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(url.serialized(), "file:///usr/lib/?aQuery#someFragment")
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])
      XCTAssertURLIsIdempotent(url)
    }
    // In order to maintain the empty component, it needs to be included in the appended contents.
    do {
      var url = WebURL("file:///usr/lib/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["", "swift"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", "", "swift"])
      XCTAssertEqualElements(url.pathComponents[range], ["", "swift"])

      XCTAssertEqual(url.serialized(), "file:///usr/lib//swift?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // A trailing empty can be ensured by appending an empty component to any path.
    do {
      var url = WebURL("file:///usr/lib?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "file:///usr/lib/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // As before, subsequent single-empty appends have no effect.
      let range2 = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(range2.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range2.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range2.lowerBound, range2.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])
      XCTAssertEqualElements(url.pathComponents[range2], [""])

      XCTAssertEqual(url.serialized(), "file:///usr/lib/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange_RootPath() {

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
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["test"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["test"])
      XCTAssertEqualElements(url.pathComponents[range], ["test"])

      XCTAssertEqual(url.serialized(), "foo://example.com/test?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Appending an empty component to a root path does not actually change the path.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [""]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "foo://example.com/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Appending 2 empty components to a root path results in 2 empty components.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["", ""]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", ""])
      XCTAssertEqualElements(url.pathComponents[range], ["", ""])

      XCTAssertEqual(url.serialized(), "foo://example.com//?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Removing the empty subrange from endIndex..<endIdex also does not change the path.
    do {
      var url = WebURL("foo://host/?query")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [])

      XCTAssertEqual(url.serialized(), "foo://host/?query")
      XCTAssertURLIsIdempotent(url)
    }
    // Inserting in the range startIndex..<startIndex works as it does for other paths.
    do {
      var url = WebURL("foo://example.com/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.startIndex, with: ["test"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["test", ""])
      XCTAssertEqualElements(url.pathComponents[range], ["test"])

      XCTAssertEqual(url.serialized(), "foo://example.com/test/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange_WindowsDriveLetters() {

    // Inserting a non-normalized Windows drive letter.
    // Must be normalized to be idempotent.
    do {
      var url = WebURL("file:///")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["C|", "Windows"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["C:", "Windows"])
      XCTAssertEqualElements(url.pathComponents[range], ["C:", "Windows"])

      XCTAssertEqual(url.serialized(), "file:///C:/Windows")
      XCTAssertURLIsIdempotent(url)
    }
    // Does not apply to non-file URLs.
    do {
      var url = WebURL("http://example/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["C|", "Windows"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["C|", "Windows"])
      XCTAssertEqualElements(url.pathComponents[range], ["C|", "Windows"])

      XCTAssertEqual(url.serialized(), "http://example/C|/Windows")
      XCTAssertURLIsIdempotent(url)
    }

    // Removing components which lead to a non-normalized Windows drive letter becoming the first component.
    // Must be normalized to be idempotent.
    do {
      var url = WebURL("file://host/windrive-blocker/C|/foo/")!
      XCTAssertEqualElements(url.pathComponents, ["windrive-blocker", "C|", "foo", ""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(after: url.pathComponents.startIndex), with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["C:", "foo", ""])
      XCTAssertEqualElements(url.pathComponents[range], [])

      XCTAssertEqual(url.serialized(), "file://host/C:/foo/")
      XCTAssertURLIsIdempotent(url)
    }
    // Does not apply to non-file URLs.
    do {
      var url = WebURL("http://host/windrive-blocker/C|/foo/")!
      XCTAssertEqualElements(url.pathComponents, ["windrive-blocker", "C|", "foo", ""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(after: url.pathComponents.startIndex), with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["C|", "foo", ""])
      XCTAssertEqualElements(url.pathComponents[range], [])

      XCTAssertEqual(url.serialized(), "http://host/C|/foo/")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange_Slashes() {

    // Slashes are percent-encoded in inserted components, even though they are not technically
    // part of the 'path' encode-set.
    do {
      var url = WebURL("foo://example.com/a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["//boo/"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "//boo/"])
      XCTAssertEqualElements(url.pathComponents[range], ["//boo/"])

      XCTAssertEqual(url.serialized(), "foo://example.com/a/b/%2F%2Fboo%2F?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Slashes cannot be used to sneak a "." or ".." component through - at least,
    // not in such a way that it would cause an idempotence failure when reparsed.
    do {
      var url = WebURL("foo://example.com/a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["/.."]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "/.."])
      XCTAssertEqualElements(url.pathComponents[range], ["/.."])

      XCTAssertEqual(url.serialized(), "foo://example.com/a/b/%2F..?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
    // Backslashes are also encoded, as they are treated like regular slashes in special URLs.
    do {
      var url = WebURL("foo://example.com/a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["\\"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "\\"])
      XCTAssertEqualElements(url.pathComponents[range], ["\\"])

      XCTAssertEqual(url.serialized(), "foo://example.com/a/b/%5C?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange_PathSigil() {

    // A path sigil is required when a non-special URL has:
    // - No authority
    // - More than 1 path component, and
    // - The first path component is empty

    // Insertions at the front of the path.
    do {
      // Sigil should be added when inserting an empty component at the front of the path.
      var url = WebURL("foo:/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.startIndex, with: [""]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range], [""])

      XCTAssertEqual(url.serialized(), "foo:/.//a/b/c/d?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is not added/removed when inserting a non-empty component at the front of the path.
      let range2 = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.startIndex, with: ["not empty"]
      )
      XCTAssertEqual(range2.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range2.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["not empty", "", "a", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range2], ["not empty"])

      XCTAssertEqual(url.serialized(), "foo:/not%20empty//a/b/c/d?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is not added/is removed when replacing the empty component at the front of the path with a non-empty one.
      url = WebURL("foo:/.//a/b/c/d?aQuery#someFragment")!
      let range3 = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(after: url.pathComponents.startIndex), with: ["book"]
      )
      XCTAssertEqual(range3.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range3.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertNotEqual(range3.lowerBound, range3.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["book", "a", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range3], ["book"])

      XCTAssertEqual(url.serialized(), "foo:/book/a/b/c/d?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is _not_ added when inserting an empty component at the front of the path _if authority present_.
      url = WebURL("foo://host/a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])
      let range4 = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.startIndex, with: [""]
      )
      XCTAssertEqual(range4.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range4.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertNotEqual(range4.lowerBound, range4.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range4], [""])

      XCTAssertEqual(url.serialized(), "foo://host//a/b/c/d?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }

    // Removals at the front of the path.
    do {
      // Sigil is removed if the empty component at the front is removed.
      var url = WebURL("foo:/.//a/b/c/d?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b", "c", "d"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(after: url.pathComponents.startIndex), with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range], [])

      XCTAssertEqual(url.serialized(), "foo:/a/b/c/d?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is inserted when a removal at the front causes an empty component to become first.
      url = WebURL("foo:/a/b//c")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "", "c"])

      let range2 = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2),
        with: [String]()
      )
      XCTAssertEqual(range2.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range2.upperBound, url.pathComponents.startIndex)
      XCTAssertEqual(range2.lowerBound, range2.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "c"])
      XCTAssertEqualElements(url.pathComponents[range2], [])

      XCTAssertEqual(url.serialized(), "foo:/.//c")
      XCTAssertURLIsIdempotent(url)

      // Sigil is _not_ inserted when a removal at the front causes an empty component to become first _if authority present_.
      url = WebURL("foo://host/a/b//c")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "", "c"])

      let range3 = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2),
        with: [String]()
      )
      XCTAssertEqual(range3.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range3.upperBound, url.pathComponents.startIndex)
      XCTAssertEqual(range3.lowerBound, range3.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "c"])
      XCTAssertEqualElements(url.pathComponents[range3], [])

      XCTAssertEqual(url.serialized(), "foo://host//c")
      XCTAssertURLIsIdempotent(url)
    }

    // Insertions after the first path component.
    do {
      // Sigil is inserted if appending components beginning with an empty to a root path.
      var url = WebURL("foo:/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["", "f"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "f"])
      XCTAssertEqualElements(url.pathComponents[range], ["", "f"])

      XCTAssertEqual(url.serialized(), "foo:/.//f?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is unaffected by appending a component to a root path, due to special-casing appends to root paths.
      url = WebURL("foo:/?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range2 = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["f"]
      )
      XCTAssertEqual(range2.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range2.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range2.lowerBound, range2.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["f"])
      XCTAssertEqualElements(url.pathComponents[range2], ["f"])

      XCTAssertEqual(url.serialized(), "foo:/f?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is unaffected by appending components after the 2nd component.
      url = WebURL("foo:/.//a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b"])

      let range3 = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["c"]
      )
      XCTAssertEqual(range3.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range3.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range3.lowerBound, range3.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b", "c"])
      XCTAssertEqualElements(url.pathComponents[range3], ["c"])

      XCTAssertEqual(url.serialized(), "foo:/.//a/b/c?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      url = WebURL("foo:/a/b?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b"])

      let range4 = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["c"]
      )
      XCTAssertEqual(range4.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range4.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range4.lowerBound, range4.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])
      XCTAssertEqualElements(url.pathComponents[range4], ["c"])

      XCTAssertEqual(url.serialized(), "foo:/a/b/c?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }

    // Removals after the first component.
    do {
      // Sigil is removed if every component but the first is removed.
      var url = WebURL("foo:/.//a?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["", "a"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(after: url.pathComponents.startIndex)..<url.pathComponents.endIndex, with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[range], [])

      XCTAssertEqual(url.serialized(), "foo:/?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)

      // Sigil is unaffected when removing components after the 2nd one.
      url = WebURL("foo:/.//a/b/c?aQuery#someFragment")!
      XCTAssertEqualElements(url.pathComponents, ["", "a", "b", "c"])

      let range2 = url.pathComponents.replaceSubrange(
        url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2)..<url.pathComponents.endIndex,
        with: [String]()
      )
      XCTAssertEqual(range2.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqual(range2.upperBound, url.pathComponents.endIndex)
      XCTAssertEqual(range2.lowerBound, range2.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "a"])
      XCTAssertEqualElements(url.pathComponents[range2], [])

      XCTAssertEqual(url.serialized(), "foo:/.//a?aQuery#someFragment")
      XCTAssertURLIsIdempotent(url)
    }

    // Entire path replacement.
    do {
      // Sigil is inserted when replacing the entire path contents.
      var url = WebURL("foo:/a/b/c")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.endIndex, with: ["", "g"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertNotEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["", "g"])
      XCTAssertEqualElements(url.pathComponents[range], ["", "g"])

      XCTAssertEqual(url.serialized(), "foo:/.//g")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange() {

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
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2),
        with: ["a"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["a", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/a/3")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/a/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Shrink in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let startIndex = url.pathComponents.startIndex
      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(after: startIndex)..<url.pathComponents.index(startIndex, offsetBy: 3),
        with: ["a"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqualElements(url.pathComponents, ["1", "a", "4"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/1/a/4")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/a/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Shrink at the end.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2)..<url.pathComponents.endIndex, with: ["a"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "a"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/1/2/a")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/a")
      XCTAssertURLIsIdempotent(url)
    }

    // Grow at the start.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2),
        with: ["a", "b", "c", "d"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b", "c", "d"])
      XCTAssertEqual(url.path, "/a/b/c/d/3")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/a/b/c/d/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Grow in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let startIndex = url.pathComponents.startIndex
      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(after: startIndex)..<url.pathComponents.index(before: url.pathComponents.endIndex),
        with: ["a", "b", "c", "d"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqualElements(url.pathComponents, ["1", "a", "b", "c", "d", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b", "c", "d"])
      XCTAssertEqual(url.path, "/1/a/b/c/d/3")
      XCTAssertEqual(url.pathComponents.count, 6)

      XCTAssertEqual(url.serialized(), "http://example.com/1/a/b/c/d/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Grow at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(before: url.pathComponents.endIndex)..<url.pathComponents.endIndex,
        with: ["a", "b", "c", "d"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "a", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b", "c", "d"])
      XCTAssertEqual(url.path, "/1/2/a/b/c/d")
      XCTAssertEqual(url.pathComponents.count, 6)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/a/b/c/d")
      XCTAssertURLIsIdempotent(url)
    }

    // Remove from the start.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2),
        with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["3", "4"])
      XCTAssertEqualElements(url.pathComponents[range], [])
      XCTAssertEqual(url.path, "/3/4")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/3/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Remove from the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let startIndex = url.pathComponents.startIndex
      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(after: startIndex)..<url.pathComponents.index(before: url.pathComponents.endIndex),
        with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["1", "4"])
      XCTAssertEqualElements(url.pathComponents[range], [])
      XCTAssertEqual(url.path, "/1/4")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/1/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Remove from the end.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2)..<url.pathComponents.endIndex,
        with: [String]()
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["1", "2"])
      XCTAssertEqualElements(url.pathComponents[range], [])
      XCTAssertEqual(url.path, "/1/2")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert elements at the start.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.startIndex..<url.pathComponents.startIndex, with: ["a", "b"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "1", "2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/a/b/1/2/3")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/a/b/1/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let insertionPoint = url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2)
      let range = url.pathComponents.replaceSubrange(insertionPoint..<insertionPoint, with: ["a", "b"])
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 4))
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "a", "b", "3", "4"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/1/2/a/b/3/4")
      XCTAssertEqual(url.pathComponents.count, 6)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/a/b/3/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["a", "b"]
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 3))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "a", "b"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/1/2/3/a/b")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/a/b")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSubrange_percentEncoding() {

    // `replaceSubrange(_:with:)` assumes new components are not percent-encoded,
    // will percent encode "%XX" to "%25XX".
    do {
      var url = WebURL("http://example.com/%2561")!
      XCTAssertEqual(url.serialized(), "http://example.com/%2561")
      XCTAssertEqual(url.path, "/%2561")
      XCTAssertEqualElements(url.pathComponents, ["%61"])

      // The component is automatically decoded when reading, but fully encoded again when writing.
      url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex,
        with: [url.pathComponents.first!, "hello to%3A the world!"]
      )

      XCTAssertEqual(url.serialized(), "http://example.com/%2561/%2561/hello%20to%253A%20the%20world!")
      XCTAssertEqual(url.path, "/%2561/%2561/hello%20to%253A%20the%20world!")
      XCTAssertEqualElements(url.pathComponents, ["%61", "%61", "hello to%3A the world!"])
      XCTAssertURLIsIdempotent(url)
    }

    // `replaceSubrange(_:withPercentEncoded:)` assumes new components are percent encoded,
    // will not double-encode "%XX".
    do {
      var url = WebURL("http://example.com/%2561")!
      XCTAssertEqual(url.serialized(), "http://example.com/%2561")
      XCTAssertEqual(url.path, "/%2561")
      XCTAssertEqualElements(url.pathComponents, ["%61"])

      // The component is automatically decoded when reading, but not re-encoded when writing.
      url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex,
        withPercentEncodedComponents: [url.pathComponents.first!, "hello to%3A the world!"]
      )

      XCTAssertEqual(url.serialized(), "http://example.com/%2561/%61/hello%20to%3A%20the%20world!")
      XCTAssertEqual(url.path, "/%2561/%61/hello%20to%3A%20the%20world!")
      XCTAssertEqualElements(url.pathComponents, ["%61", "a", "hello to: the world!"])
      XCTAssertURLIsIdempotent(url)
    }

    // That said, both methods work the same way in ignoring percent-encoded double-dot components,
    // as this is checked before encoding. This is a slight defect, but fixing it would significantly complicate
    // the implementation so fixing it is a low priority.
    do {
      var url = WebURL("http://example.com/foo/bar")!
      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar")
      XCTAssertEqual(url.path, "/foo/bar")
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar"])

      url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex,
        with: ["baz", "%2E%2E", "qux"]  // Should technically be encoded as "%252E%252E".
      )

      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar/baz/qux")
      XCTAssertEqual(url.path, "/foo/bar/baz/qux")
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", "baz", "qux"])
      XCTAssertURLIsIdempotent(url)
    }
    do {
      var url = WebURL("http://example.com/foo/bar")!
      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar")
      XCTAssertEqual(url.path, "/foo/bar")
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar"])

      url.pathComponents.replaceSubrange(
        url.pathComponents.endIndex..<url.pathComponents.endIndex,
        withPercentEncodedComponents: ["baz", "%2E%2E", "qux"]
      )

      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar/baz/qux")
      XCTAssertEqual(url.path, "/foo/bar/baz/qux")
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", "baz", "qux"])
      XCTAssertURLIsIdempotent(url)
    }

  }
}

extension PathComponentsTests {

  func testInsertContents() {

    // Insert at the front.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.insert(contentsOf: ["a", "b"], at: url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "1", "2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/a/b/1/2/3")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/a/b/1/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let range = url.pathComponents.insert(
        contentsOf: ["a", "b"], at: url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2)
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 4))
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "a", "b", "3", "4"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/1/2/a/b/3/4")
      XCTAssertEqual(url.pathComponents.count, 6)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/a/b/3/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.insert(contentsOf: ["a", "b"], at: url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 3))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "a", "b"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/1/2/3/a/b")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/a/b")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert after root path.
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.insert(contentsOf: ["hello", "world"], at: url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["hello", "world"])
      XCTAssertEqualElements(url.pathComponents[range], ["hello", "world"])
      XCTAssertEqual(url.path, "/hello/world")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/hello/world")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert to a non-opaque, empty path.
    do {
      var url = WebURL("foo://example.com")!
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertFalse(url.hasOpaquePath)

      let range = url.pathComponents.insert(contentsOf: ["hello", "world"], at: url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["hello", "world"])
      XCTAssertEqualElements(url.pathComponents[range], ["hello", "world"])
      XCTAssertEqual(url.path, "/hello/world")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "foo://example.com/hello/world")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert after directory path.
    do {
      var url = WebURL("http://example.com/foo/bar/")!
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", ""])

      let range = url.pathComponents.insert(contentsOf: ["hello", "world"], at: url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", "hello", "world"])
      XCTAssertEqualElements(url.pathComponents[range], ["hello", "world"])
      XCTAssertEqual(url.path, "/foo/bar/hello/world")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar/hello/world")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert to introduce path sigil.
    do {
      var url = WebURL("foo:/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.insert(contentsOf: [""], at: url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["", "1", "2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], [""])
      XCTAssertEqual(url.path, "//1/2/3")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "foo:/.//1/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert non-normalized Windows drive letter.
    do {
      var url = WebURL("file:///Users/jim/")!
      XCTAssertEqualElements(url.pathComponents, ["Users", "jim", ""])

      let range = url.pathComponents.insert(contentsOf: ["C|"], at: url.pathComponents.startIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["C:", "Users", "jim", ""])
      XCTAssertEqualElements(url.pathComponents[range], ["C:"])
      XCTAssertEqual(url.path, "/C:/Users/jim/")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "file:///C:/Users/jim/")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert ".." components.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.insert(contentsOf: ["..", ".."], at: url.pathComponents.endIndex)
      XCTAssertEqual(range.lowerBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], [])
      XCTAssertEqual(url.path, "/1/2/3")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert components with slashes.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.insert(contentsOf: ["/a", #"\b"#], at: url.pathComponents.endIndex)
      XCTAssertEqual(url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2), range.lowerBound)
      XCTAssertEqual(url.pathComponents.endIndex, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "/a", #"\b"#])
      XCTAssertEqualElements(url.pathComponents[range], ["/a", #"\b"#])
      XCTAssertEqual(url.path, "/1/2/3/%2Fa/%5Cb")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/%2Fa/%5Cb")
      XCTAssertURLIsIdempotent(url)
    }

    // Insert components with non-percent-encoding "%XX" sequences.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.insert(contentsOf: ["folder-%61", "w%61m"], at: url.pathComponents.endIndex)
      XCTAssertEqual(url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2), range.lowerBound)
      XCTAssertEqual(url.pathComponents.endIndex, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "folder-%61", "w%61m"])
      XCTAssertEqualElements(url.pathComponents[range], ["folder-%61", "w%61m"])
      XCTAssertEqual(url.path, "/1/2/3/folder-%2561/w%2561m")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/folder-%2561/w%2561m")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testAppendContents() {

    // Regular append on to non-root path.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.append(contentsOf: ["a", "b"])
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "a", "b"])
      XCTAssertEqualElements(url.pathComponents[range], ["a", "b"])
      XCTAssertEqual(url.path, "/1/2/3/a/b")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/a/b")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to root path.
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.append(contentsOf: ["hello", "world"])
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["hello", "world"])
      XCTAssertEqualElements(url.pathComponents[range], ["hello", "world"])
      XCTAssertEqual(url.path, "/hello/world")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/hello/world")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to a non-opaque, empty path.
    do {
      var url = WebURL("foo://example.com")!
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertFalse(url.hasOpaquePath)

      let range = url.pathComponents.append(contentsOf: ["hello", "world"])
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["hello", "world"])
      XCTAssertEqualElements(url.pathComponents[range], ["hello", "world"])
      XCTAssertEqual(url.path, "/hello/world")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "foo://example.com/hello/world")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to directory path.
    do {
      var url = WebURL("http://example.com/foo/bar/")!
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", ""])

      let range = url.pathComponents.append(contentsOf: ["hello", "world"])
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", "hello", "world"])
      XCTAssertEqualElements(url.pathComponents[range], ["hello", "world"])
      XCTAssertEqual(url.path, "/foo/bar/hello/world")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar/hello/world")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to introduce path sigil.
    do {
      var url = WebURL("foo:/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.append(contentsOf: ["", "bar"])
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["", "bar"])
      XCTAssertEqualElements(url.pathComponents[range], ["", "bar"])
      XCTAssertEqual(url.path, "//bar")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "foo:/.//bar")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending non-normalized Windows drive letter to root path.
    do {
      var url = WebURL("file://host/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.append(contentsOf: ["C|", "Windows", "System32", ""])
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["C:", "Windows", "System32", ""])
      XCTAssertEqualElements(url.pathComponents[range], ["C:", "Windows", "System32", ""])
      XCTAssertEqual(url.path, "/C:/Windows/System32/")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "file://host/C:/Windows/System32/")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending non-normalized Windows drive letter to root path (non-file).
    do {
      var url = WebURL("not-file://host/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.append(contentsOf: ["C|", "Windows", "System32", ""])
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["C|", "Windows", "System32", ""])
      XCTAssertEqualElements(url.pathComponents[range], ["C|", "Windows", "System32", ""])
      XCTAssertEqual(url.path, "/C|/Windows/System32/")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "not-file://host/C|/Windows/System32/")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending ".." components.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.append(contentsOf: ["..", ".."])
      XCTAssertEqual(range.lowerBound, url.pathComponents.endIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], [])
      XCTAssertEqual(url.path, "/1/2/3")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending components with slashes.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.append(contentsOf: ["/a", #"\b"#])
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "/a", #"\b"#])
      XCTAssertEqualElements(url.pathComponents[range], ["/a", #"\b"#])
      XCTAssertEqual(url.path, "/1/2/3/%2Fa/%5Cb")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/%2Fa/%5Cb")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending components with non-percent-encoding "%XX" sequences.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.append(contentsOf: ["folder-%61", "w%61m"])
      XCTAssertEqual(url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2), range.lowerBound)
      XCTAssertEqual(url.pathComponents.endIndex, range.upperBound)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "folder-%61", "w%61m"])
      XCTAssertEqualElements(url.pathComponents[range], ["folder-%61", "w%61m"])
      XCTAssertEqual(url.path, "/1/2/3/folder-%2561/w%2561m")
      XCTAssertEqual(url.pathComponents.count, 5)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/folder-%2561/w%2561m")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testRemoveSubrange() {

    // Removal from the front.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let idx = url.pathComponents.removeSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(after: url.pathComponents.startIndex)
      )
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["2", "3"])
      XCTAssertEqual(url.pathComponents[idx], "2")
      XCTAssertEqual(url.path, "/2/3")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal from the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let startIndex = url.pathComponents.startIndex
      let idx = url.pathComponents.removeSubrange(
        url.pathComponents.index(after: startIndex)..<url.pathComponents.index(startIndex, offsetBy: 3)
      )
      XCTAssertEqual(idx, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["1", "4"])
      XCTAssertEqual(url.pathComponents[idx], "4")
      XCTAssertEqual(url.path, "/1/4")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/1/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal from the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let idx = url.pathComponents.removeSubrange(
        url.pathComponents.index(after: url.pathComponents.startIndex)..<url.pathComponents.endIndex
      )
      XCTAssertEqual(idx, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1"])
      XCTAssertEqual(url.path, "/1")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "http://example.com/1")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal from root path.
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let idx = url.pathComponents.removeSubrange(url.pathComponents.startIndex..<url.pathComponents.endIndex)
      XCTAssertEqual(idx, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "http://example.com/")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal from a non-opaque, empty path.
    do {
      var url = WebURL("foo://example.com")!
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertFalse(url.hasOpaquePath)

      let idx = url.pathComponents.removeSubrange(url.pathComponents.startIndex..<url.pathComponents.endIndex)
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqual(idx, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertEqual(url.path, "")
      XCTAssertEqual(url.pathComponents.count, 0)

      XCTAssertEqual(url.serialized(), "foo://example.com")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal which introduces path sigil.
    do {
      var url = WebURL("foo:/a/b//c/d")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "", "c", "d"])

      let idx = url.pathComponents.removeSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2)
      )
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["", "c", "d"])
      XCTAssertEqual(url.pathComponents[idx], "")
      XCTAssertEqual(url.path, "//c/d")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "foo:/.//c/d")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal which introduces non-normalized Windows drive letter.
    do {
      var url = WebURL("file:///a/b/C|/d")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "C|", "d"])

      let idx = url.pathComponents.removeSubrange(
        url.pathComponents.startIndex..<url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2)
      )
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["C:", "d"])
      XCTAssertEqual(url.pathComponents[idx], "C:")
      XCTAssertEqual(url.path, "/C:/d")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "file:///C:/d")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal which erases the entire path (non-special URL, with hostname).
    do {
      var url = WebURL("foo://example.com/a/b/c")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])

      let idx = url.pathComponents.removeSubrange(url.pathComponents.startIndex..<url.pathComponents.endIndex)
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqual(idx, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertEqual(url.path, "")
      XCTAssertEqual(url.pathComponents.count, 0)

      XCTAssertEqual(url.serialized(), "foo://example.com")
      XCTAssertURLIsIdempotent(url)
    }

    // Removal which erases the entire path (non-special URL, no hostname).
    do {
      var url = WebURL("foo:/a/b/c")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c"])

      let idx = url.pathComponents.removeSubrange(url.pathComponents.startIndex..<url.pathComponents.endIndex)
      XCTAssertEqual(idx, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "foo:/")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testReplaceSingle() {

    // Replacement at the front.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceComponent(at: url.pathComponents.startIndex, with: "a")
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["a", "2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/a/2/3")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/a/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement in the middle.
    do {
      var url = WebURL("http://example.com/1/2/3/4")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "4"])

      let range = url.pathComponents.replaceComponent(
        at: url.pathComponents.index(after: url.pathComponents.startIndex), with: "a"
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqualElements(url.pathComponents, ["1", "a", "3", "4"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/1/a/3/4")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "http://example.com/1/a/3/4")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement at the end.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceComponent(
        at: url.pathComponents.index(before: url.pathComponents.endIndex), with: "a"
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "a"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/1/2/a")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/a")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement of root path.
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let range = url.pathComponents.replaceComponent(at: url.pathComponents.startIndex, with: "a")
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["a"])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/a")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "http://example.com/a")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement of directory path.
    do {
      var url = WebURL("http://example.com/foo/bar/")!
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", ""])

      let range = url.pathComponents.replaceComponent(
        at: url.pathComponents.index(after: url.pathComponents.startIndex), with: "a"
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(before: url.pathComponents.endIndex))
      XCTAssertEqualElements(url.pathComponents, ["foo", "a", ""])
      XCTAssertEqualElements(url.pathComponents[range], ["a"])
      XCTAssertEqual(url.path, "/foo/a/")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/foo/a/")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement which introduces path sigil.
    do {
      var url = WebURL("foo:/a/b/c/d")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceComponent(at: url.pathComponents.startIndex, with: "")
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range], [""])
      XCTAssertEqual(url.path, "//b/c/d")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "foo:/.//b/c/d")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement which introduces non-normalized Windows drive letter.
    do {
      var url = WebURL("file:///a/b/c/d")!
      XCTAssertEqualElements(url.pathComponents, ["a", "b", "c", "d"])

      let range = url.pathComponents.replaceComponent(at: url.pathComponents.startIndex, with: "C|")
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqualElements(url.pathComponents, ["C:", "b", "c", "d"])
      XCTAssertEqualElements(url.pathComponents[range], ["C:"])
      XCTAssertEqual(url.path, "/C:/b/c/d")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "file:///C:/b/c/d")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement with ".." component.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceComponent(at: url.pathComponents.startIndex, with: "..")
      XCTAssertEqual(range.lowerBound, url.pathComponents.startIndex)
      XCTAssertEqual(range.upperBound, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["2", "3"])
      XCTAssertEqualElements(url.pathComponents[range], [])
      XCTAssertEqual(url.path, "/2/3")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement containing with slashes.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceComponent(
        at: url.pathComponents.index(after: url.pathComponents.startIndex), with: #"\b"#
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqualElements(url.pathComponents, ["1", #"\b"#, "3"])
      XCTAssertEqualElements(url.pathComponents[range], [#"\b"#])
      XCTAssertEqual(url.path, "/1/%5Cb/3")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/%5Cb/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Replacement containing non-percent-encoding "%XX" sequence.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let range = url.pathComponents.replaceComponent(
        at: url.pathComponents.index(after: url.pathComponents.startIndex), with: "folder-%61"
      )
      XCTAssertEqual(range.lowerBound, url.pathComponents.index(after: url.pathComponents.startIndex))
      XCTAssertEqual(range.upperBound, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqualElements(url.pathComponents, ["1", "folder-%61", "3"])
      XCTAssertEqualElements(url.pathComponents[range], ["folder-%61"])
      XCTAssertEqual(url.path, "/1/folder-%2561/3")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/folder-%2561/3")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testAppendSingle() {

    // Regular append on to non-root path.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let idx = url.pathComponents.append("a")
      XCTAssertEqual(idx, url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -1))
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "a"])
      XCTAssertEqualElements(url.pathComponents[idx], "a")
      XCTAssertEqual(url.path, "/1/2/3/a")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/a")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to root path.
    do {
      var url = WebURL("http://example.com/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let idx = url.pathComponents.append("hello")
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["hello"])
      XCTAssertEqualElements(url.pathComponents[idx], "hello")
      XCTAssertEqual(url.path, "/hello")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "http://example.com/hello")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to a non-opaque, empty path.
    do {
      var url = WebURL("foo://example.com")!
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertFalse(url.hasOpaquePath)

      let idx = url.pathComponents.append("hello")
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["hello"])
      XCTAssertEqualElements(url.pathComponents[idx], "hello")
      XCTAssertEqual(url.path, "/hello")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "foo://example.com/hello")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending to directory path.
    do {
      var url = WebURL("http://example.com/foo/bar/")!
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", ""])

      let idx = url.pathComponents.append("hello")
      XCTAssertEqual(idx, url.pathComponents.index(url.pathComponents.startIndex, offsetBy: 2))
      XCTAssertEqualElements(url.pathComponents, ["foo", "bar", "hello"])
      XCTAssertEqualElements(url.pathComponents[idx], "hello")
      XCTAssertEqual(url.path, "/foo/bar/hello")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/foo/bar/hello")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending an empty component on to a root path (should be a no-op).
    do {
      var url = WebURL("foo:/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let idx = url.pathComponents.append("")
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqualElements(url.pathComponents[idx], "")
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "foo:/")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending non-normalized Windows drive letter to root path.
    do {
      var url = WebURL("file://host/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let idx = url.pathComponents.append("C|")
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["C:"])
      XCTAssertEqualElements(url.pathComponents[idx], "C:")
      XCTAssertEqual(url.path, "/C:")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "file://host/C:")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending non-normalized Windows drive letter to root path (non-file).
    do {
      var url = WebURL("not-file://host/")!
      XCTAssertEqualElements(url.pathComponents, [""])

      let idx = url.pathComponents.append("C|")
      XCTAssertEqual(idx, url.pathComponents.startIndex)
      XCTAssertEqualElements(url.pathComponents, ["C|"])
      XCTAssertEqualElements(url.pathComponents[idx], "C|")
      XCTAssertEqual(url.path, "/C|")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "not-file://host/C|")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending ".." components (should be a no-op).
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let idx = url.pathComponents.append("..")
      XCTAssertEqual(idx, url.pathComponents.endIndex)
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])
      XCTAssertEqual(url.path, "/1/2/3")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending components with slashes.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let idx = url.pathComponents.append("/a")
      XCTAssertEqual(idx, url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -1))
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "/a"])
      XCTAssertEqualElements(url.pathComponents[idx], "/a")
      XCTAssertEqual(url.path, "/1/2/3/%2Fa")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/%2Fa")
      XCTAssertURLIsIdempotent(url)
    }

    // Appending components with non-percent-encoding "%XX" sequences.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      let idx = url.pathComponents.append("folder-%61")
      XCTAssertEqual(idx, url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -1))
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3", "folder-%61"])
      XCTAssertEqualElements(url.pathComponents[idx], "folder-%61")
      XCTAssertEqual(url.path, "/1/2/3/folder-%2561")
      XCTAssertEqual(url.pathComponents.count, 4)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2/3/folder-%2561")
      XCTAssertURLIsIdempotent(url)
    }
  }
}

extension PathComponentsTests {

  func testRemoveLast() {

    // Remove 1, non-empty component.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      url.pathComponents.removeLast()
      XCTAssertEqualElements(url.pathComponents, ["1", "2"])
      XCTAssertEqual(url.path, "/1/2")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "http://example.com/1/2")
      XCTAssertURLIsIdempotent(url)
    }
    // Remove 2, non-empty components.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      url.pathComponents.removeLast(2)
      XCTAssertEqualElements(url.pathComponents, ["1"])
      XCTAssertEqual(url.path, "/1")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "http://example.com/1")
      XCTAssertURLIsIdempotent(url)
    }
    // Remove all components, special URL.
    do {
      var url = WebURL("http://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      url.pathComponents.removeLast(3)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "http://example.com/")
      XCTAssertURLIsIdempotent(url)
    }
    // Remove all components, non-special URL with hostname.
    do {
      var url = WebURL("foo://example.com/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      url.pathComponents.removeLast(3)
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertEqual(url.path, "")
      XCTAssertEqual(url.pathComponents.count, 0)

      XCTAssertEqual(url.serialized(), "foo://example.com")
      XCTAssertURLIsIdempotent(url)
    }
    // Remove all components, non-special URL without hostname.
    do {
      var url = WebURL("foo:/1/2/3")!
      XCTAssertEqualElements(url.pathComponents, ["1", "2", "3"])

      url.pathComponents.removeLast(3)
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "foo:/")
      XCTAssertURLIsIdempotent(url)
    }
    // Remove 1, empty component.
    do {
      var url = WebURL("file:///usr/lib/")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      url.pathComponents.removeLast()
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib"])
      XCTAssertEqual(url.path, "/usr/lib")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "file:///usr/lib")
      XCTAssertURLIsIdempotent(url)
    }
    // Remove 2 empty components.
    do {
      var url = WebURL("file:///usr/lib//")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", "", ""])

      url.pathComponents.removeLast(2)
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib"])
      XCTAssertEqual(url.path, "/usr/lib")
      XCTAssertEqual(url.pathComponents.count, 2)

      XCTAssertEqual(url.serialized(), "file:///usr/lib")
      XCTAssertURLIsIdempotent(url)
    }
  }

  func testEnsureDirectoryPath() {

    // Appends an empty component if the last component isn't empty.
    do {
      var url = WebURL("file:///usr/lib")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib"])

      url.pathComponents.ensureDirectoryPath()
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])
      XCTAssertEqual(url.path, "/usr/lib/")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "file:///usr/lib/")
      XCTAssertURLIsIdempotent(url)
    }
    // Does not append an empty component if the last component is already empty.
    do {
      var url = WebURL("file:///usr/lib/")!
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])

      url.pathComponents.ensureDirectoryPath()
      XCTAssertEqualElements(url.pathComponents, ["usr", "lib", ""])
      XCTAssertEqual(url.path, "/usr/lib/")
      XCTAssertEqual(url.pathComponents.count, 3)

      XCTAssertEqual(url.serialized(), "file:///usr/lib/")
      XCTAssertURLIsIdempotent(url)
    }
    // Does not append an empty component to root paths.
    do {
      var url = WebURL("file:///")!
      XCTAssertEqualElements(url.pathComponents, [""])

      url.pathComponents.ensureDirectoryPath()
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "file:///")
      XCTAssertURLIsIdempotent(url)
    }
    // Appends an empty component if the path is non-opaque and empty.
    do {
      var url = WebURL("foo://example")!
      XCTAssertEqualElements(url.pathComponents, [])
      XCTAssertFalse(url.hasOpaquePath)

      url.pathComponents.ensureDirectoryPath()
      XCTAssertEqualElements(url.pathComponents, [""])
      XCTAssertEqual(url.path, "/")
      XCTAssertEqual(url.pathComponents.count, 1)

      XCTAssertEqual(url.serialized(), "foo://example/")
      XCTAssertURLIsIdempotent(url)
    }
  }
}
