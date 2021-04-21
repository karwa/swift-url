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

  /// The URL's path components, if it has a hierarchical path.
  ///
  /// This collection gives you efficient, bidirectional, read-write access to the URL's path components. Components are retrieved in their percent-decoded form.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/swift/packages/%F0%9F%A6%86%20tracker")!
  /// print(url.pathComponents.first!) // Prints "swift"
  /// print(url.pathComponents.last!) // Prints "🦆 tracker"
  ///
  /// url.pathComponents.removeLast()
  /// url.pathComponents.append("swift-url")
  /// print(url) // Prints "http://example.com/swift/packages/swift-url"
  /// ```
  /// Mutating the URL, such as by setting its `.path` or any other properties, invalidates all path component indices.
  ///
  /// Path components run from their leading slash until the leading slash of the next component (or the end of the path). That means that a URL whose
  /// path is "/" contains a single, empty path component, and paths which end with a "/" (also referred to as directory paths) end with an empty path component.
  /// When appending to a path whose last component is empty, this empty component is merged with the new components.
  /// To create a directory path, append an empty component or call `ensureDirectoryPath`.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/")!
  /// print(url.pathComponents.last!) // Prints ""
  /// print(url.pathComponents.count) // Prints "1"
  ///
  /// url.pathComponents.append("swift") // http://example.com/swift
  /// print(url.pathComponents.count) // Prints "1", because the empty component was merged.
  ///
  /// url.pathComponents.append(contentsOf: ["packages", "swift-url"]) // "http://example.com/swift/packages/swift-url"
  /// print(url.pathComponents.count) // Prints "3"
  ///
  /// url.pathComponents.ensureDirectoryPath() // "http://example.com/swift/packages/swift-url/"
  /// print(url.pathComponents.last!) // Prints ""
  /// print(url.pathComponents.count) // Prints "4"
  /// ```
  ///
  /// Paths can be difficult. In order to manipulate them reliably, you should adhere strictly to the principle that every modification invalidates every path-component
  /// index. Additionally, try to avoid making assumptions about how the number of path components (or `count`) is affected by a modification. For instance,
  /// URLs with special schemes are forbidden from ever having empty paths, and if you have such a URL and attempt to remove all of its path components,
  /// the result will be a path with a single, empty component (as above). These are the same caveats which apply to the `WebURL.path` property.
  ///
  /// This view does not support URLs with non-hierarchical paths (`cannotBeABase` is `true`), and triggers a runtime error if it is accessed on such a URL.
  ///
  /// Almost all URLs _do_ have hierarchical paths (in particular, URLs with special schemes, such as http(s) and file, always have hierarchical paths).
  /// The ones which _don't_ are known as "cannot-be-a-base" URLs - and they can be recognized by the lack of slashes immediately following their scheme.
  /// Examples of such URLs are:
  ///
  /// - `mailto:bob@example.com`
  /// - `javascript:alert("hello");`
  /// - `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`
  ///
  /// See the `cannotBeABase` property for more information about these URLs.
  ///
  public var pathComponents: PathComponents {
    get {
      precondition(!cannotBeABase, "cannot-be-a-base URLs do not have path components")
      return PathComponents(url: self)
    }
    _modify {
      precondition(!cannotBeABase, "cannot-be-a-base URLs do not have path components")
      var view = PathComponents(url: self)
      storage = _tempStorage
      defer { storage = view.url.storage }
      yield &view
    }
    set {
      precondition(!cannotBeABase, "cannot-be-a-base URLs do not have path components")
      path = newValue.url.path
    }
  }

  /// A view of the components in a URL's `path`.
  ///
  public struct PathComponents {

    @usableFromInline
    internal var url: WebURL

    internal init(url: WebURL) {
      self.url = url
    }
  }
}


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension WebURL.PathComponents {

  /// The position of a path component within a URL string.
  ///
  public struct Index: Equatable, Comparable {

    /// The range of the component in the overall URL string's code-units.
    /// Note that this includes the leading "/", so paths which end in a "/" include a trailing empty component before reaching endIndex.
    ///
    internal var range: Range<Int>

    internal init(codeUnitRange: Range<Int>) {
      self.range = codeUnitRange
    }

    public static func < (lhs: Index, rhs: Index) -> Bool {
      lhs.range.lowerBound < rhs.range.lowerBound
    }
  }

  /// Invokes `body` with a pointer to the contiguous UTF8 content of the requested component.
  /// The component is not percent-decoded from its form in the URL string.
  ///
  /// - important: The provided pointer is valid only for the duration of `body`. Do not store or return the pointer for later use.
  /// - complexity: O(*1*)
  /// - parameters:
  ///   - component: The index of the component to be read. Must be a valid path-component index.
  ///   - body: A closure which processes the content of the path component.
  ///
  public func withUTF8<Result>(
    component: Index, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
  ) rethrows -> Result {

    try url.storage.withUTF8 { string in
      let pathRange = url.storage.structure.rangeForReplacingCodeUnits(of: .path)
      precondition(
        component.range.lowerBound >= pathRange.lowerBound && component.range.upperBound <= pathRange.upperBound,
        "Index does not refer to a location within the path"
      )
      assert(string[component.range.lowerBound] == ASCII.forwardSlash.codePoint)
      return try body(UnsafeBufferPointer(rebasing: string[component.range].dropFirst()))
    }
  }
}

extension WebURL.PathComponents: BidirectionalCollection {

  public var startIndex: Index {
    url.storage.pathComponentsStartIndex
  }

  public var endIndex: Index {
    url.storage.pathComponentsEndIndex
  }

  public subscript(position: Index) -> String {
    withUTF8(component: position) { $0.percentDecodedString }
  }

  public func distance(from start: Index, to end: Index) -> Int {
    guard start <= end else {
      return -1 * distance(from: end, to: start)
    }
    return url.storage.withUTF8 { string in
      var count = 0
      for char in string[start.range.lowerBound..<end.range.lowerBound] {
        if char == ASCII.forwardSlash.codePoint {
          count &+= 1
        }
      }
      return count
    }
  }

  public func formIndex(after i: inout Index) {
    // Collection does not require us to trap on incrementing endIndex; this just keeps returning endIndex.
    i.range = Range(
      uncheckedBounds: (i.range.upperBound, url.storage.endOfPathComponent(startingAt: i.range.upperBound))
    )
  }

  public func formIndex(before i: inout Index) {
    // Collection does not require us to trap on decrementing startIndex; this just keeps returning startIndex.
    guard let newStart = url.storage.startOfPathComponent(endingAt: i.range.lowerBound) else { return }
    i.range = Range(uncheckedBounds: (newStart, i.range.lowerBound))
  }

  public func index(after i: Index) -> Index {
    var copy = i
    formIndex(after: &copy)
    return copy
  }

  public func index(before i: Index) -> Index {
    var copy = i
    formIndex(before: &copy)
    return copy
  }
}


// --------------------------------------------
// MARK: - Writing
// --------------------------------------------


extension WebURL.PathComponents {

  /// Replaces the specified subrange of path components with the contents of the given collection.
  ///
  /// This method has the effect of removing the specified range of components from the path and inserting the new components at the same location.
  /// The number of new components need not match the number of elements being removed, and will be percent-encoded, if necessary, upon insertion.
  ///
  /// The following example shows replacing the last 2 components of a `file:` URL with an array of strings.
  ///
  /// ```
  /// var url = WebURL("file:///usr/bin/swift")!
  /// url.pathComponents.modify { path in
  ///   let lastTwo = path.index(path.endIndex, offsetBy: -2)..<path.endIndex
  ///   path.replaceSubrange(lastTwo, with: [
  ///     "lib",
  ///     "swift",
  ///     "linux",
  ///     "libswiftCore.so"
  ///   ])
  /// }
  /// print(url) // Prints "file:///usr/lib/swift/linux/libswiftCore.so"
  /// ```
  ///
  /// If you pass a zero-length range as the `range` parameter, this method inserts the elements of `newComponents` at `range.lowerBound`.
  /// Calling the `insert(contentsOf:at:)` method instead is preferred. If appending to a path which ends in a "/" (i.e. an empty component),
  /// the empty component will be replaced by the first appended component. Note how the following example appends 2 components to a path with 2 components
  /// (the last component of which is empty), and emerges with 3 components rather than 4:
  ///
  /// ```
  /// var url = WebURL("file:///usr/")!
  /// print(url.pathComponents!.count, url.pathComponents!.last!) // Prints (2, "")
  ///
  /// url.pathComponents.modify { path in
  ///   path.replaceSubrange(path.endIndex..<path.endIndex, with: ["bin", "swift"])
  /// }
  ///
  /// print(url.pathComponents!.count, url.pathComponents!.last!) // Prints (3, "swift")
  /// print(url) // Prints "file:///usr/bin/swift"
  /// ```
  ///
  /// If you pass a zero-length collection as the `newComponents` parameter, this method removes the components in the given subrange
  /// without replacement. Calling the `removeSubrange(_:)` method instead is preferred. Some URLs may not allow empty paths; attempting to remove
  /// all components from such a URL will instead set its path to the root path ("/").
  ///
  /// ```
  /// var url = WebURL("http://example.com/foo/index.html")!
  /// print(url.pathComponents!.count, url.pathComponents!.first!) // Prints (2, "foo")
  ///
  /// url.pathComponents.modify { path in
  ///   path.replaceSubrange(path.startIndex..<path.endIndex, with: [] as [String])
  /// }
  ///
  /// print(url) // Prints "http://example.com/"
  /// print(url.pathComponents!.count, url.pathComponents!.first!) // Prints (1, "")
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  /// Otherwise, the contents of the new components are percent-encoded as they are written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - bounds: The subrange of the path to replace. The bounds of the range must be valid path-component indices.
  ///   - newComponents: The new components to add to the path.
  /// -  returns: A new range of indices corresponding to the location of the new components in the path.
  ///
  @_specialize(where Components == [String])
  @_specialize(where Components == [Substring])
  @_specialize(where Components == CollectionOfOne<String>)
  @_specialize(where Components == CollectionOfOne<Substring>)
  @discardableResult
  public mutating func replaceSubrange<Components>(
    _ bounds: Range<Index>, with newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    return replaceComponents(bounds, withUTF8: newComponents.lazy.map { $0.utf8 })
  }

  @_specialize(where Components == EmptyCollection<EmptyCollection<UInt8>>)
  @discardableResult
  internal mutating func replaceComponents<Components>(
    _ range: Range<Index>, withUTF8 newComponents: Components
  ) -> Range<Index>
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    var newSubrange: Range<Index>?
    url.withMutableStorage(
      { small -> AnyURLStorage in
        let result = small.replacePathComponents(range, with: newComponents)
        switch result.firstComponentOrError {
        case .left(let _newSubrange): newSubrange = _newSubrange
        case .right(let error): fatalError("Unxpected error replacing path components: \(error)")
        }
        return result.0
      },
      { generic -> AnyURLStorage in
        let result = generic.replacePathComponents(range, with: newComponents)
        switch result.firstComponentOrError {
        case .left(let _newSubrange): newSubrange = _newSubrange
        case .right(let error): fatalError("Unxpected error replacing path components: \(error)")
        }
        return result.0
      }
    )
    return newSubrange!
  }
}

// Insert, Append, Remove, Replace.

extension WebURL.PathComponents {

  /// Inserts the elements of a collection into the path at the specified position.
  ///
  /// The new components are inserted before the component currently at the specified index.
  /// If you pass the path's `endIndex` property as the `index` parameter, the new elements are appended to the path.
  /// If appending to a path which ends in a "/" (i.e. an empty component), the empty component will be replaced by the first appended component.
  ///
  /// Here's an example of inserting an array of path components in the middle of a path:
  ///
  /// ```
  /// var url = WebURL("file:///usr/swift")!
  /// url.pathComponents.modify { path in
  ///   path.insert(contentsOf: ["local", "bin"], at: path.index(after: path.startIndex))
  /// }
  /// print(url) // Prints "file:///usr/local/bin/swift"
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  /// Otherwise, the contents of the new components are percent-encoded as they are written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - newComponents: The new components to insert into the path.
  ///   - position: The position at which to insert the new components. `position` must be a valid path component index.
  /// - returns: A new range of indices corresponding to the location of the new components in the path.
  ///
  @discardableResult
  public mutating func insert<Components>(
    contentsOf newComponents: Components, at position: Index
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    return replaceSubrange(position..<position, with: newComponents)
  }

  /// Adds the elements of a collection to the end of this path.
  ///
  /// If appending to a path which ends in a "/" (i.e. an empty component), the empty component will be replaced by the first appended component.
  /// Here's an example of building a path by appending path components. Note that the first `append` does not change the `count`.
  ///
  /// ```
  /// var url = WebURL("file:///")!
  /// print(url.pathComponents!.count, url.pathComponents!.first!) // Prints (1, "")
  ///
  /// url.pathComponents!.append(contentsOf: ["tmp"])
  /// print(url.pathComponents!.count, url.pathComponents!.first!) // Prints (1, "tmp")
  ///
  /// url.pathComponents!.append(contentsOf: ["my_app", "data.json"])
  /// print(url) // Prints "file:///tmp/my_app/data.json"
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  /// Otherwise, the contents of the new components are percent-encoded as they are written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter newComponents: The new components to add to end of the path.
  /// - returns: A new range of indices corresponding to the location of the new components in the path.
  ///
  @discardableResult
  public mutating func append<Components>(
    contentsOf newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    return insert(contentsOf: newComponents, at: endIndex)
  }

  /// Removes the specified subrange of components from the path.
  ///
  /// ```
  /// var url = WebURL("http://example.com/projects/swift/swift-url/")!
  /// url.pathComponents.modify { path in
  ///   path.removeSubrange(path.index(after: path.startIndex)..<path.endIndex)
  /// }
  /// print(url) // Prints "http://example.com/projects"
  /// ```
  ///
  /// Some URLs may not allow empty paths; attempting to remove all components from such a URL will instead set its path to the root path ("/"):
  ///
  /// ```
  /// var url = WebURL("http://example.com/foo/index.html")!
  /// url.pathComponents.modify { path in
  ///   path.removeSubrange(path.startIndex..<path.endIndex)
  /// }
  /// print(url) // Prints "http://example.com/"
  /// ```
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter bounds: The subrange of the path to remove. The bounds of the range must be valid path component indices.
  /// - returns: The index corresponding to the subrange's `upperBound` after modification.
  ///
  @discardableResult
  public mutating func removeSubrange(_ bounds: Range<Index>) -> Index {
    return replaceComponents(bounds, withUTF8: EmptyCollection<EmptyCollection<UInt8>>()).upperBound
  }

  /// Replaces the path component at the specified position.
  ///
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), the component is removed.
  ///
  /// ```
  /// var url = WebURL("file:///usr/bin/swift")!
  /// url.pathComponents.modify { path in
  ///   path.replaceComponent(at: path.index(after: path.startIndex), with: "lib")
  /// }
  /// print(url) // Prints "file:///usr/lib/swift"
  /// ```
  ///
  /// The contents of the new component are percent-encoded as they are written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - position: The position of the component to replace. `position` must be a valid path component index.
  ///   - newComponent: The value to set the component to.
  /// - returns: A new range of indices encompassing the replaced component.
  ///
  @discardableResult
  public mutating func replaceComponent<Component>(
    at position: Index, with newComponent: Component
  ) -> Range<Index> where Component: StringProtocol {
    precondition(position != endIndex, "Cannot replace component at endIndex")
    return replaceSubrange(position..<index(after: position), with: CollectionOfOne(newComponent))
  }

  /// Inserts a component into the path at the specified position.
  ///
  /// The new component is inserted before the component currently at the specified index.
  /// If you pass the path's `endIndex` property as the `index` parameter, the new component is appended to the path.
  /// If appending to a path which ends in a "/" (i.e. an empty component), the empty component will be replaced by the first appended component.
  /// See `append` for more information.
  ///
  /// Here's an example of inserting a path component in the middle of a path:
  ///
  /// ```
  /// var url = WebURL("file:///usr/swift")!
  /// url.pathComponents.modify { path in
  ///   path.insert("bin", at: path.index(after: path.startIndex))
  /// }
  /// print(url) // Prints "file:///usr/bin/swift"
  /// ```
  ///
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), it is ignored.
  /// Otherwise, the contents of the new component are percent-encoded as it is written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - newComponent: The new component to insert into the path.
  ///   - position: The position at which to insert the new component. `position` must be a valid path component index.
  /// - returns: A new range of indices corresponding to the location of the new component in the path.
  ///
  @discardableResult
  public mutating func insert<Component>(
    _ newComponent: Component, at position: Index
  ) -> Range<Index> where Component: StringProtocol {
    return insert(contentsOf: CollectionOfOne(newComponent), at: position)
  }

  /// Adds a component to the end of this path.
  ///
  /// If appending to a path which ends in a "/" (i.e. an empty component), the empty component will be replaced by the first appended component.
  /// Here's an example of building a path by appending path components. Note that the first `append` does not change the `count`.
  ///
  /// ```
  /// var url = WebURL("file:///")!
  /// print(url.pathComponents!.count, url.pathComponents!.first!) // Prints (1, "")
  ///
  /// url.pathComponents!.append("tmp")
  /// print(url.pathComponents!.count, url.pathComponents!.first!) // Prints (1, "tmp")
  ///
  /// url.pathComponents!.append("data.json")
  /// print(url) // Prints "file:///tmp/data.json"
  /// ```
  ///
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), it is ignored.
  /// Otherwise, the contents of the new component are percent-encoded as it is written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter newComponent: The new component to add to end of the path.
  /// - returns: A new range of indices corresponding to the location of the new component in the path.
  ///
  @discardableResult
  public mutating func append<Component>(
    _ newComponent: Component
  ) -> Range<Index> where Component: StringProtocol {
    return append(contentsOf: CollectionOfOne(newComponent))
  }

  /// Removes the component at the given index from the path.
  ///
  /// ```
  /// var url = WebURL("http://example.com/projects/swift/swift-url/Sources/")!
  /// url.pathComponents.modify { path in
  ///   path.remove(at: path.index(after: path.startIndex))
  /// }
  /// print(url) // Prints "http://example.com/projects/swift-url/Sources/"
  /// ```
  ///
  /// Some URLs may not allow empty paths; attempting to remove the last component from such a URL will instead set its path to the root path ("/"):
  ///
  /// ```
  /// var url = WebURL("http://example.com/foo")!
  /// url.pathComponents!.remove(at: url.pathComponents!.startIndex)
  /// print(url) // Prints "http://example.com/"
  /// ```
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter position: The index of the component to remove. `position` must be a valid path component index.
  /// - returns: The index corresponding to the component following `position`, after modification.
  ///
  @discardableResult
  public mutating func remove(at position: Index) -> Index {
    precondition(position != endIndex, "Cannot remove component at endIndex")
    return removeSubrange(position..<index(after: position))
  }
}

extension WebURL.PathComponents {

  /// Removes the specified number of components from the end of the path.
  ///
  /// Attempting to remove more elements than exist in the collection triggers a runtime error.
  /// Some URLs may not allow empty paths; attempting to remove all components from such a URL will instead set its path to the root path ("/"):
  ///
  /// ```
  /// var url = WebURL("http://example.com/foo/bar")!
  /// url.pathComponents!.removeLast(2)
  /// print(url) // Prints "http://example.com/"
  /// ```
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter k: The number of elements to remove from the path.
  ///                `k` must be greater than or equal to zero and must not exceed the number of components in the path.
  ///
  public mutating func removeLast(_ k: Int = 1) {
    precondition(k >= 0, "Cannot remove a negative number of path components")
    removeSubrange(index(endIndex, offsetBy: -k, limitedBy: startIndex)!..<endIndex)
  }

  /// Appends an empty component to the path, if it does not already end with an empty component.
  /// This has the effect of ensuring the path ends with a trailing slash.
  ///
  /// The following example demonstrates building a file path by appending, followed by `ensureDirectoryPath` to finish the path
  /// with a trailing slash:
  ///
  /// ```
  /// var url = WebURL("file:///")!
  /// url.pathComponents!.append(contentsOf: ["Users", "karl", "Desktop"]) // url: "file:///Users/karl/Desktop"
  /// url.pathComponents!.ensureDirectoryPath() // url: "file:///Users/karl/Desktop/"
  /// ```
  ///
  /// If the path already ends in a trailing slash (or is a root path), this method has no effect.
  ///
  /// - returns: The index of the last component, which will be an empty component.
  ///
  @discardableResult
  public mutating func ensureDirectoryPath() -> Index {
    let range = append("")
    assert(range.upperBound == endIndex)
    return range.lowerBound
  }
}


// --------------------------------------------
// MARK: - URLStorage + PathComponents
// --------------------------------------------


extension AnyURLStorage {

  internal var pathComponentsStartIndex: WebURL.PathComponents.Index {
    switch self {
    case .small(let storage): return storage.pathComponentsStartIndex
    case .large(let storage): return storage.pathComponentsStartIndex
    }
  }

  internal var pathComponentsEndIndex: WebURL.PathComponents.Index {
    switch self {
    case .small(let storage): return storage.pathComponentsEndIndex
    case .large(let storage): return storage.pathComponentsEndIndex
    }
  }

  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int {
    switch self {
    case .small(let storage): return storage.endOfPathComponent(startingAt: componentStartOffset)
    case .large(let storage): return storage.endOfPathComponent(startingAt: componentStartOffset)
    }
  }

  internal func startOfPathComponent(endingAt componentEndOffset: Int) -> Int? {
    switch self {
    case .small(let storage): return storage.startOfPathComponent(endingAt: componentEndOffset)
    case .large(let storage): return storage.startOfPathComponent(endingAt: componentEndOffset)
    }
  }
}

extension URLStorage {

  internal var pathComponentsStartIndex: WebURL.PathComponents.Index {
    let pathStart = header.structure.rangeForReplacingCodeUnits(of: .path).lowerBound
    return WebURL.PathComponents.Index(codeUnitRange: pathStart..<pathStart + header.structure.firstPathComponentLength)
  }

  internal var pathComponentsEndIndex: WebURL.PathComponents.Index {
    let pathEnd = header.structure.rangeForReplacingCodeUnits(of: .path).upperBound
    return WebURL.PathComponents.Index(codeUnitRange: pathEnd..<pathEnd)
  }

  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int {
    withUTF8 { utf8 in
      let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
      guard !pathRange.isEmpty else { return componentStartOffset }
      if componentStartOffset == pathRange.upperBound { return componentStartOffset }
      assert(pathRange.contains(componentStartOffset), "UTF8 position is not within the path")
      assert(utf8[componentStartOffset] == ASCII.forwardSlash.codePoint, "UTF8 position is not aligned to a component")
      return utf8[componentStartOffset..<pathRange.upperBound].dropFirst().firstIndex(of: ASCII.forwardSlash.codePoint)
        ?? pathRange.upperBound
    }
  }

  internal func startOfPathComponent(endingAt componentEndOffset: Int) -> Int? {
    withUTF8 { utf8 in
      let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
      guard !pathRange.isEmpty else { return componentEndOffset }
      if componentEndOffset == pathRange.lowerBound { return nil }
      if pathRange.contains(componentEndOffset) {
        assert(utf8[componentEndOffset] == ASCII.forwardSlash.codePoint, "UTF8 position is not aligned to a component")
      } else {
        assert(componentEndOffset == pathRange.upperBound, "UTF8 position is not within the path")
      }
      return utf8[pathRange.lowerBound..<componentEndOffset].lastIndex(of: ASCII.forwardSlash.codePoint)
        ?? pathRange.lowerBound
    }
  }
}

extension URLStorage {

  /// Replaces the path components in the given range with the given new components.
  /// Analogous to `replaceSubrange` from `RangeReplaceableCollection`.
  ///
  internal mutating func replacePathComponents<Components>(
    _ replacedIndices: Range<WebURL.PathComponents.Index>,
    with components: Components
  ) -> (AnyURLStorage, firstComponentOrError: Either<Range<WebURL.PathComponents.Index>, URLSetterError>)
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    let oldStructure = header.structure
    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)
    if oldStructure.cannotBeABaseURL {
      return (AnyURLStorage(self), .right(.cannotSetPathOnCannotBeABaseURL))
    }

    let components = components.lazy.filter { utf8 in
      !PathComponentParser.isSingleDotPathSegment(utf8) && !PathComponentParser.isDoubleDotPathSegment(utf8)
    }
    // This value being nil is taken as meaning the components are empty.
    let firstNewComponentLength = components.first.map {
      1 + $0.lazy.percentEncoded(as: \.pathComponent).count
    }

    // If inserting elements at the end of a path which ends in a trailing slash,
    // widen the replacement range so we drop the trailing empty component.
    // This means that appending "foo" to "/" or "/usr/" results in "/foo" or "/usr/foo",
    // rather than "//foo" or "/usr//foo".
    var replacedIndices = replacedIndices
    if replacedIndices.lowerBound.range.lowerBound == oldPathRange.upperBound, firstNewComponentLength != nil,
      pathEndsWithTrailingSlash
    {
      let newLowerBound = replacedIndices.lowerBound.range.lowerBound - 1..<replacedIndices.lowerBound.range.lowerBound
      replacedIndices = WebURL.PathComponents.Index(codeUnitRange: newLowerBound)..<replacedIndices.upperBound
    }
    let replacedRange = replacedIndices.lowerBound.range.lowerBound..<replacedIndices.upperBound.range.lowerBound

    if replacedRange == oldPathRange {
      guard firstNewComponentLength != nil else {
        // We can only set an empty path if this is a non-special scheme with authority ("foo://host?query").
        // Everything else (special, path-only) requires at least a lone "/".
        let replaced: AnyURLStorage
        if !oldStructure.schemeKind.isSpecial, oldStructure.hasAuthority {
          var newStructure = oldStructure
          newStructure.pathLength = 0
          newStructure.firstPathComponentLength = 0
          replaced = removeSubrange(oldPathRange, newStructure: newStructure).newStorage
        } else {
          var commands = [ReplaceSubrangeOperation]()
          var newStructure = oldStructure
          if case .path = oldStructure.sigil {
            commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
            newStructure.sigil = .none
          }
          newStructure.pathLength = 1
          newStructure.firstPathComponentLength = 1
          commands.append(
            .replace(
              subrange: oldPathRange, withCount: 1,
              writer: { buffer in
                buffer.baseAddress.unsafelyUnwrapped.initialize(to: ASCII.forwardSlash.codePoint)
                return 1
              })
          )
          replaced = multiReplaceSubrange(commands, newStructure: newStructure)
        }
        let newPathStart = replaced.structure.pathStart
        let newPathEnd = replaced.structure.pathStart &+ replaced.structure.pathLength
        let newLowerBound = WebURL.PathComponents.Index(codeUnitRange: newPathStart..<newPathEnd)
        let newUpperBound = WebURL.PathComponents.Index(codeUnitRange: newPathEnd..<newPathEnd)
        return (replaced, .left(Range(uncheckedBounds: (newLowerBound, newUpperBound))))
      }
    }

    var newStructure = oldStructure
    var commands = [ReplaceSubrangeOperation]()
    var pathStartOffset = 0

    let insertedPathLength = components.dropFirst().reduce(into: firstNewComponentLength ?? 0) { counter, component in
      counter += 1 + component.lazy.percentEncoded(as: \.pathComponent).count
    }

    // Calculate what the new first component will be, and whether the URL might require a path sigil.
    // A URL requires a sigil if there is no authority, the path has >1 component, and the first component is empty.

    if replacedRange.lowerBound == oldPathRange.lowerBound {
      if let firstInsertedComponentLength = firstNewComponentLength {
        // Inserting at the front of the path.
        // The first component will be from the inserted content.
        let firstComponentEmpty = (firstInsertedComponentLength == 1)
        let hasCmptsAfter =
          (replacedRange.upperBound != oldPathRange.upperBound)
          || (insertedPathLength != firstInsertedComponentLength)
        newStructure.sigil = firstComponentEmpty && hasCmptsAfter ? .path : .none
        newStructure.firstPathComponentLength = firstInsertedComponentLength
      } else {
        // Removing at the front of the path.
        // The first component (if any) will be at replacedIndices.upperBound.
        let firstComponentEmpty = (replacedIndices.upperBound.range.count == 1)
        let hasCmptsAfter = (replacedIndices.upperBound.range.upperBound != oldPathRange.upperBound)
        newStructure.sigil = firstComponentEmpty && hasCmptsAfter ? .path : .none
        newStructure.firstPathComponentLength = replacedIndices.upperBound.range.count
      }
    } else {
      // Insertion/removal elsewhere in the path.
      // The current first component will be maintained.
      let oldStartIndex = pathComponentsStartIndex
      let firstComponentEmpty = (oldStartIndex.range.count == 1)
      let hasCmptsAfter: Bool
      if firstNewComponentLength != nil {
        // Inserting after the first component means there will certainly be >1 component.
        hasCmptsAfter = true
      } else {
        // Unless removing everything after the first component, there will be >1 component remaining.
        hasCmptsAfter =
          (replacedRange.lowerBound != oldStartIndex.range.upperBound)
          || (replacedRange.upperBound != oldPathRange.upperBound)
      }
      newStructure.sigil = firstComponentEmpty && hasCmptsAfter ? .path : .none
    }
    switch (oldStructure.sigil, newStructure.sigil) {
    case (.authority, _):
      newStructure.sigil = .authority
    case (.none, .none), (.path, .path):
      break
    case (.none, .path):
      commands.append(
        .replace(
          subrange: oldStructure.rangeForReplacingSigil,
          withCount: Sigil.path.length,
          writer: Sigil.path.unsafeWrite)
      )
      pathStartOffset = 2
    case (.path, .none):
      commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
      pathStartOffset = -2
    case (_, .authority):
      preconditionFailure("Modifying the path cannot cause an authority sigil to be inserted")
    }

    newStructure.pathLength -= replacedRange.count
    newStructure.pathLength += insertedPathLength
    commands.append(
      .replace(
        subrange: replacedRange, withCount: insertedPathLength,
        writer: { buffer in
          var bytesWritten = 0
          for component in components {
            buffer[bytesWritten] = ASCII.forwardSlash.codePoint
            bytesWritten &+= 1
            bytesWritten &+=
              UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...])
              .fastInitialize(from: component.lazy.percentEncoded(as: \.pathComponent))
          }
          return bytesWritten
        })
    )

    var replaced = multiReplaceSubrange(commands, newStructure: newStructure)

    // Normalize Windows drive letters.
    // It is much simpler to fix this up after the replacement, as the first component could come from either
    // the user-provided components or the existing path. Luckily, it doesn't change the length or structure of the URL,
    // so we don't need to worry about switching URLStorage representations and can do a simple code-unit swap.
    if case .file = newStructure.schemeKind {
      switch replaced {
      case .small(var small):
        replaced = _tempStorage
        small.normalizeWindowsDriveLetterIfPresent()
        replaced = AnyURLStorage(small)
      case .large(var generic):
        replaced = _tempStorage
        generic.normalizeWindowsDriveLetterIfPresent()
        replaced = AnyURLStorage(generic)
      }
    }

    // Calculate the path component ranges for the new lower/upperBound.
    let lowerBoundStartPosition = replacedRange.lowerBound + pathStartOffset
    let upperBoundStartPosition = lowerBoundStartPosition + insertedPathLength
    let lowerBoundEndPosition: Int
    let upperBoundEndPosition: Int
    if let firstComponentLenth = firstNewComponentLength {
      lowerBoundEndPosition = lowerBoundStartPosition + firstComponentLenth
      upperBoundEndPosition = upperBoundStartPosition + replacedIndices.upperBound.range.count
    } else {
      assert(lowerBoundStartPosition == upperBoundStartPosition)
      lowerBoundEndPosition = lowerBoundStartPosition + replacedIndices.upperBound.range.count
      upperBoundEndPosition = lowerBoundEndPosition
    }
    let newLowerBound = WebURL.PathComponents.Index(codeUnitRange: lowerBoundStartPosition..<lowerBoundEndPosition)
    let newUpperBound = WebURL.PathComponents.Index(codeUnitRange: upperBoundStartPosition..<upperBoundEndPosition)
    return (replaced, .left(Range(uncheckedBounds: (newLowerBound, newUpperBound))))
  }

  private var pathEndsWithTrailingSlash: Bool {
    let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
    return pathRange.count >= 1 && withUTF8 { $0[pathRange.upperBound - 1] == ASCII.forwardSlash.codePoint }
  }

  private mutating func normalizeWindowsDriveLetterIfPresent() {
    guard case .file = header.structure.schemeKind else { return }
    let path = codeUnits[header.structure.rangeForReplacingCodeUnits(of: .path)]
    if PathComponentParser.isWindowsDriveLetter(path.dropFirst().prefix(2)),
      path.dropFirst(3).first == nil || path.dropFirst(3).first == ASCII.forwardSlash.codePoint
    {
      codeUnits[path.startIndex + 2] = ASCII.colon.codePoint
    }
  }
}
