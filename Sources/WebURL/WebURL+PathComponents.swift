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

extension WebURL {

  /// A read-only view of the components in a URL's path.
  ///
  public struct PathComponents: _PathComponentCollection {
    public typealias Index = PathComponentIndex
    public typealias Element = String
    var _url: WebURL
    public var startIndex: PathComponentIndex
  }

  /// This URL's path components, if it has a hierarchical path.
  ///
  /// This collection gives you efficient, bidirectional access to the URL's path components:
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/swift/packages/swift-url")!
  /// for component in url.pathComponents! {
  ///  print(component) // "swift", "packages", "swift-url"
  /// }
  /// print(url.pathComponents!.last) // "swift-url"
  /// print(url.pathComponents!.dropLast().last) // "packages"
  /// ```
  ///
  /// Note that components are retrieved in their percent-decoded form. Paths which end in a "/" are considered to end with an empty component:
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/swift/packages/🦆/")!
  /// for component in url.pathComponents! {
  ///  print(component) // "swift", "packages", "🦆", ""
  /// }
  /// print(url.pathComponents!.count) // 4
  /// print(url.pathComponents!.last) // ""
  /// print(url.pathComponents!.dropLast().last) // "🦆"
  /// ```
  ///
  /// Mutating the URL, such as by setting its `.path` or any other properties, invalidates all indexes from this collection.
  ///
  /// Almost all URLs have hierarchical paths. The ones which _don't_ are known as "cannot-be-a-base" URLs - and they do not have any slashes
  /// after their scheme. Examples of such URLs are: `mailto:bob@example.com`, `javascript:alert("hello");`, and
  /// `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`. Such URLs tend to be rare, and if you do not expect to deal with them
  /// (for example, because your application exclusively deals with http(s) URLs, which are special and always have a hostname and path),
  /// it is reasonable to force-unwrap this property.
  ///
  public var pathComponents: PathComponents? {
    guard self._cannotBeABaseURL == false else { return nil }
    return PathComponents(_url: self, startIndex: PathComponentIndex(startIndexFor: self))
  }
}

// _PathComponentCollection protocol.

/// This protocol adds a `BidirectionalCollection` conformance over the path components for any type able to provide an immutable WebURL.
/// It is an internal implementation detail, so that we can share an implementation between immutable and mutable path component views.
///
protocol _PathComponentCollection: BidirectionalCollection where Index == PathComponentIndex, Element == String {
  var _url: WebURL { get }
}

public struct PathComponentIndex: Equatable, Comparable {

  /// The range of the component in the overall URL string's code-units.
  /// Note that this includes the leading "/", so directory paths include a trailing empty component before reaching endIndex.
  var range: Range<Int>

  init(codeUnitRange: Range<Int>) {
    self.range = codeUnitRange
  }

  init(startIndexFor url: WebURL) {
    self.range = url.storage.withEntireString { string -> Range<Int> in
      let pathRange = url.storage.structure.rangeForReplacingCodeUnits(of: .path)
      guard pathRange.isEmpty == false else {
        return pathRange  // endIndex
      }
      // There should always be a leading slash for a hierarchical path.
      assert(string[pathRange].first == ASCII.forwardSlash.codePoint)
      let endOfFirstComponent = string[pathRange].dropFirst().firstIndex(of: ASCII.forwardSlash.codePoint)
      return Range(uncheckedBounds: (pathRange.lowerBound, endOfFirstComponent ?? pathRange.upperBound))
    }
  }

  public static func < (lhs: PathComponentIndex, rhs: PathComponentIndex) -> Bool {
    lhs.range.lowerBound < rhs.range.lowerBound
  }
}

// Collection.

extension _PathComponentCollection {

  public var endIndex: PathComponentIndex {
    let pathRange = _url.storage.structure.rangeForReplacingCodeUnits(of: .path)
    return Index(codeUnitRange: Range(uncheckedBounds: (pathRange.upperBound, pathRange.upperBound)))
  }

  public func distance(from start: Index, to end: Index) -> Int {
    guard start <= end else {
      return -1 * distance(from: end, to: start)
    }
    return _url.storage.withEntireString { string in
      var count = 0
      for char in string[start.range.lowerBound..<end.range.lowerBound] {
        if char == ASCII.forwardSlash.codePoint {
          count &+= 1
        }
      }
      return count
    }
  }

  public func formIndex(after i: inout PathComponentIndex) {
    // Note that this doesn't trap when incrementing endIndex; it just keeps returning endIndex.
    // That's fine - Collection imposes no requirement to trap.
    _url.storage.withEntireString { string in
      let pathRange = _url.storage.structure.rangeForReplacingCodeUnits(of: .path)
      let remainingPathRange = pathRange[i.range.upperBound...]
      assert(
        i.range.upperBound == pathRange.upperBound || string[remainingPathRange].first == ASCII.forwardSlash.codePoint,
        "Every path component starts with a '/'"
      )
      let nextSlash = string[remainingPathRange].dropFirst().firstIndex(of: ASCII.forwardSlash.codePoint)
      i.range = Range(uncheckedBounds: (i.range.upperBound, nextSlash ?? pathRange.upperBound))
    }
  }

  public func index(after i: Index) -> Index {
    var copy = i
    formIndex(after: &copy)
    return copy
  }

  public subscript(position: PathComponentIndex) -> String {
    withUTF8(component: position) { $0.urlDecodedString }
  }
}

// BidirectionalCollection.

extension _PathComponentCollection {

  public func formIndex(before i: inout Index) {
    // Note that this doesn't trap when incrementing endIndex; it just keeps returning startIndex.
    // That's fine - Collection imposes no requirement to trap.
    _url.storage.withEntireString { string in
      let pathRange = _url.storage.structure.rangeForReplacingCodeUnits(of: .path)
      let remainingPathRange = pathRange[..<i.range.lowerBound]
      guard remainingPathRange.isEmpty == false else { return }  // Keep returning startIndex.
      let prevSlash = string[remainingPathRange].lastIndex(of: ASCII.forwardSlash.codePoint)
      i.range = Range(uncheckedBounds: (prevSlash ?? pathRange.lowerBound, i.range.lowerBound))
    }
  }

  public func index(before i: Index) -> Index {
    var copy = i
    formIndex(before: &copy)
    return copy
  }
}

extension _PathComponentCollection {

  /// Invokes `body` with a pointer to the UTF8 content of the requested component. The component is not percent-decoded from its form in the URL string.
  ///
  /// - important: The pointer provided to `body` must not escape its execution.
  ///
  public func withUTF8<Result>(
    component: PathComponentIndex, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
  ) rethrows -> Result {

    try _url.storage.withEntireString { string in
      let pathRange = _url.storage.structure.rangeForReplacingCodeUnits(of: .path)
      precondition(
        component.range.lowerBound >= pathRange.lowerBound && component.range.upperBound <= pathRange.upperBound,
        "Invalid index"
      )
      assert(string[component.range.lowerBound] == ASCII.forwardSlash.codePoint)
      return try body(UnsafeBufferPointer(rebasing: string[component.range].dropFirst()))
    }
  }
}
