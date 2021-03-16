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
    public var _url: WebURL
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
public protocol _PathComponentCollection: BidirectionalCollection where Index == PathComponentIndex, Element == String {
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
    let pathRange = url.storage.structure.rangeForReplacingCodeUnits(of: .path)
    self.range = pathRange.lowerBound ..< url.storage.rangeOfPathComponent(startingAt: pathRange.lowerBound)
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
    i.range = Range(uncheckedBounds: (i.range.upperBound, _url.storage.rangeOfPathComponent(startingAt: i.range.upperBound)))
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


// ----------------------------
// MARK: Mutable Path Components
// ----------------------------

extension WebURL {

  public struct UnsafeMutablePathComponents: _MutablePathComponentCollection {
    public typealias Index = PathComponentIndex
    public typealias Element = String

    var pointer: UnsafeMutablePointer<WebURL>
    public var startIndex: Index

    public var _url: WebURL { pointer.pointee }
    public mutating func withMutableURL(_ body: (UnsafeMutablePointer<WebURL>)->Void) {
			body(pointer)
    }
  }

  public mutating func withMutablePathComponents<Result>(_ body: (inout UnsafeMutablePathComponents) throws -> Result) rethrows -> Result {
    // TODO: What if cannot-be-a-base URL?
    try withUnsafeMutablePointer(to: &self) {
      var pathEditor = UnsafeMutablePathComponents(pointer: $0, startIndex: PathComponentIndex(startIndexFor: $0.pointee))
      return try body(&pathEditor)
    }
  }
}

public protocol _MutablePathComponentCollection: _PathComponentCollection {
  mutating func withMutableURL(_ body: (UnsafeMutablePointer<WebURL>)->Void)
}

extension _MutablePathComponentCollection {

  public mutating func replacePathComponents<Components>(_ range: Range<Index>, with components: Components)
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    let utf8Range = range.lowerBound.range.lowerBound ..< range.upperBound.range.lowerBound
    withMutableURL { ptr in
      ptr.pointee.withMutableStorage(
        { small in small.replacePathComponents(utf8Range: utf8Range, with: components).0 },
        { generic in generic.replacePathComponents(utf8Range: utf8Range, with: components).0 }
      )
    }
  }
}

// --- URLStorage mutations.

extension AnyURLStorage {
  func rangeOfPathComponent(startingAt componentStartIndex: Int) -> Int {
    switch self {
    case .small(let small): return small.rangeOfPathComponent(startingAt: componentStartIndex)
    case .generic(let generic): return generic.rangeOfPathComponent(startingAt: componentStartIndex)
    }
  }
}

extension URLStorage {

  func rangeOfPathComponent(startingAt componentStartIndex: Int) -> Int {
    assert(header.structure.cannotBeABaseURL == false)
    return withEntireString { utf8 in
      let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
      guard !pathRange.isEmpty else { return componentStartIndex }
      if componentStartIndex == pathRange.upperBound { return componentStartIndex }
      assert(pathRange.contains(componentStartIndex))
      assert(utf8[componentStartIndex] == ASCII.forwardSlash.codePoint)
      return utf8[componentStartIndex..<pathRange.endIndex].dropFirst().firstIndex(of: ASCII.forwardSlash.codePoint)
        ?? pathRange.endIndex
    }
  }

  mutating func replacePathComponents<Components>(
    utf8Range: Range<Int>,
    with components: Components
  ) -> (AnyURLStorage, firstComponentOrError: Either<Range<Int>, URLSetterError>)
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (AnyURLStorage(self), .right(.error(.cannotSetPathOnCannotBeABaseURL)))
    }

    // What to do about '.' and '..' components (and percent-encoded, "%2e%2E" etc)?
    // We can't leave them in, else we'd be creating URLs which change when you re-parse them.
    // - '.' components can just always be skipped. Yay.
    // - '..' components are more interesting:
    //   * Allow them to pop components from the path outside of the given range. Possible, but the parser doesn't
    //     expect baseURL to be written to as it parses components from it. Might be difficult to avoid clobbering.
    //     So at least for now, ".." components can't pop anything outside of the given set of components.
    //   * Allow them to pop from inside the given components (["one", ".."] -> []).
    //     Possible future direction, iterating in reverse and using a custom lazy filter as the path parser does.
    //   * Just skip them. That's what rust-url does, and it's much easier to implement. Let's do that, for now.
    let filteredComponents = components.lazy.filter { utf8 in
      !PathComponentParser.isSingleDotPathSegment(utf8) && !PathComponentParser.isDoubleDotPathSegment(utf8)
    }

    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)

    let firstNewComponentLength = filteredComponents.first.map {
      1 + $0.lazy.percentEncoded(using: URLEncodeSet.Path.self).joined().count
    }

    // If this is an entire-path replacement, we need to check for empty paths.

    if utf8Range == oldPathRange {
      guard firstNewComponentLength != nil else {
        // We can only set an empty path if this is a non-special scheme with authority.
        if !oldStructure.schemeKind.isSpecial, oldStructure.hasAuthority {
          var newStructure = oldStructure
          newStructure.pathLength = 0
          return (removeSubrange(oldPathRange, newStructure: newStructure), .left(oldPathRange.lowerBound..<oldPathRange.lowerBound))
        // Otherwise, set to "/".
        } else {
          // TODO: (performance): Shouldn't need to go through the path parser. Refactor sigil logic so we can use it here.
          let new = setPath(to: CollectionOfOne(ASCII.forwardSlash.codePoint))
          assert(new.1 == nil)
          return (new.0, .left(new.0.structure.rangeForReplacingCodeUnits(of: .path)))
        }
      }
    }

    // Find out if the new path will need a sigil.
    // We need a sigil if there is no authority, the path has >1 component, and the first one is empty.

    var operations = [ReplaceSubrangeOperation]()
    var newStructure = oldStructure

    let remainingNewComponents = filteredComponents.dropFirst()

    if oldStructure.hasAuthority == false {
      if utf8Range.lowerBound == oldPathRange.lowerBound {
        if let firstInsertedComponentLength = firstNewComponentLength {
          // Inserting at the front of the path. The first component is from the new components.
          let firstComponentEmpty = firstInsertedComponentLength == 1
          let hasComponentsAfter = (utf8Range.upperBound != oldPathRange.upperBound) || !remainingNewComponents.isEmpty
          newStructure.sigil = firstComponentEmpty && hasComponentsAfter ? .path : .none
        } else {
          // Removing at the front of the path. The first component (if any) is at the end of the range.
          let firstComponentEnd = rangeOfPathComponent(startingAt: utf8Range.upperBound)
          let firstComponentEmpty = firstComponentEnd &- 1 == utf8Range.upperBound
          let hasComponentsAfter = (firstComponentEnd != oldPathRange.upperBound)
          newStructure.sigil = firstComponentEmpty && hasComponentsAfter ? .path : .none
        }
      } else {
        let firstComponentEnd = rangeOfPathComponent(startingAt: oldPathRange.lowerBound)
        let firstComponentEmpty = firstComponentEnd &- 1 == oldPathRange.lowerBound
        assert(utf8Range.lowerBound >= firstComponentEnd)
        let hasComponentsAfter: Bool
        if firstNewComponentLength != nil {
          // Inserting after the first component means there will be >1 component.
					hasComponentsAfter = true
        } else {
          // Unless removing everything after the first component, there will be >1 component.
          hasComponentsAfter = (utf8Range.lowerBound != firstComponentEnd) || (utf8Range.upperBound != oldPathRange.upperBound)
        }
        newStructure.sigil = firstComponentEmpty && hasComponentsAfter ? .path : .none
      }
      switch (oldStructure.sigil, newStructure.sigil) {
      case (.authority, _), (_, .authority):
        fatalError()
      case (.none, .none), (.path, .path):
        break
      case (.none, .path):
        operations.append(.replace(subrange: oldStructure.rangeForReplacingSigil, withCount: Sigil.path.length, writer: Sigil.path.unsafeWrite))
      case (.path, .none):
        operations.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
      }
    }

		// TODO: first can't be nil if there are remaining components.
    let insertedPathLength = remainingNewComponents.reduce(into: firstNewComponentLength ?? 0) { counter, component in
      counter += 1 + component.lazy.percentEncoded(using: URLEncodeSet.Path.self).joined().count
    }
    newStructure.pathLength -= utf8Range.count
    newStructure.pathLength += insertedPathLength

    operations.append(.replace(subrange: utf8Range, withCount: insertedPathLength, writer: { buffer in
      var bytesWritten = 0
      for component in filteredComponents {
        buffer[bytesWritten] = ASCII.forwardSlash.codePoint
        bytesWritten &+= 1
        bytesWritten &+= UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...])
          .initialize(from: component.lazy.percentEncoded(using: URLEncodeSet.Path.self).joined()).1
      }
      return bytesWritten
    }))

    let replaced = multiReplaceSubrange(commands: operations, newStructure: newStructure)
    return (replaced, .left(utf8Range.lowerBound..<utf8Range.lowerBound + (firstNewComponentLength ?? 0)))
  }
}
