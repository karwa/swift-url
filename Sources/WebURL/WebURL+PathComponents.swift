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

  /// The URL's path components. The URL must have a hierarchical path (`cannotBeABase` is `false`).
  ///
  public var pathComponents: PathComponents {
    get {
      precondition(!cannotBeABase, "cannot-be-a-base URLs do not have path components")
      return PathComponents(storage: storage)
    }
    _modify {
      precondition(!cannotBeABase, "cannot-be-a-base URLs do not have path components")
      var view = PathComponents(storage: storage)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      precondition(!cannotBeABase, "cannot-be-a-base URLs do not have path components")
      try! utf8.setPath(newValue.storage.utf8.path)
    }
  }

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
  public struct PathComponents {

    @usableFromInline
    internal var storage: AnyURLStorage

    internal init(storage: AnyURLStorage) {
      self.storage = storage
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
    @usableFromInline
    internal var range: Range<Int>

    @inlinable
    internal init(codeUnitRange: Range<Int>) {
      self.range = codeUnitRange
    }

    @inlinable
    public static func < (lhs: Index, rhs: Index) -> Bool {
      lhs.range.lowerBound < rhs.range.lowerBound
    }
  }
}

extension WebURL.UTF8View {

  /// The UTF-8 code-units of the given path component.
  ///
  public func pathComponent(_ component: WebURL.PathComponents.Index) -> SubSequence {
    // These bounds checks are only for semantics, not for memory safety; the slicing subscript handles that.
    assert(component.range.lowerBound >= path.startIndex && component.range.lowerBound <= path.endIndex)
    assert(self[component.range.lowerBound] == ASCII.forwardSlash.codePoint)
    return self[component.range.dropFirst()]
  }
}

extension WebURL.PathComponents: BidirectionalCollection {

  public var startIndex: Index {
    storage.pathComponentsStartIndex
  }

  public var endIndex: Index {
    storage.pathComponentsEndIndex
  }

  public subscript(position: Index) -> String {
    storage.utf8.pathComponent(position).percentDecodedString
  }

  public func distance(from start: Index, to end: Index) -> Int {
    guard start <= end else {
      return -1 * distance(from: end, to: start)
    }
    return storage.utf8[start.range.lowerBound..<end.range.lowerBound].lazy.filter {
      $0 == ASCII.forwardSlash.codePoint
    }.count
  }

  public func index(after i: Index) -> Index {
    var copy = i
    formIndex(after: &copy)
    return copy
  }

  public func formIndex(after i: inout Index) {
    let newEnd = storage.endOfPathComponent(startingAt: i.range.upperBound) ?? i.range.upperBound
    i.range = i.range.upperBound..<newEnd
  }

  public func index(before i: Index) -> Index {
    var copy = i
    formIndex(before: &copy)
    return copy
  }

  public func formIndex(before i: inout Index) {
    guard let newStart = storage.startOfPathComponent(endingAt: i.range.lowerBound) else { return }
    i.range = newStart..<i.range.lowerBound
  }
}


// --------------------------------------------
// MARK: - Writing
// --------------------------------------------


extension WebURL.PathComponents {

  /// Replaces the specified subrange of path components with the contents of the given collection.
  ///
  /// This method has the effect of removing the specified range of components from the path and inserting the new components at the same location.
  /// The number of new components need not match the number of elements being removed, and their contents will be percent-encoded, if necessary,
  /// upon insertion.
  ///
  /// The following example shows replacing the last 2 components of a `file:` URL with an array of strings.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/bin/swift")!
  ///
  /// let lastTwo = url.pathComponents.index(url.pathComponents.endIndex, offsetBy: -2)..<url.pathComponents.endIndex
  /// url.pathComponents.replaceSubrange(lastTwo, with: [
  ///   "lib",
  ///   "swift",
  ///   "linux",
  ///   "libswiftCore.so"
  /// ])
  /// print(url) // Prints "file:///usr/lib/swift/linux/libswiftCore.so"
  /// ```
  ///
  /// If you pass a zero-length range as the `range` parameter, this method inserts the elements of `newComponents` at `range.lowerBound`.
  /// Calling the `insert(contentsOf:at:)` method instead is preferred. If appending to a path which ends in a "/" (i.e. a directory path),
  /// the trailing empty component will be replaced by the first appended component.
  ///
  /// Note how the following example appends 2 components to a path with 2 components (the last of which is empty), and emerges with 3 components rather than 4:
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/")!
  /// print(url.pathComponents.last!) // Prints ""
  /// print(url.pathComponents.count) // Prints 2
  ///
  /// url.pathComponents.replaceSubrange(
  ///   url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["bin", "swift"]
  /// )
  ///
  /// print(url) // Prints "file:///usr/bin/swift"
  /// print(url.pathComponents.last!) // Prints "swift"
  /// print(url.pathComponents.count) // Prints 3
  /// ```
  ///
  /// If you pass a zero-length collection as the `newComponents` parameter, this method removes the components in the given subrange without replacement.
  /// Calling the `removeSubrange(_:)` method instead is preferred. Some URLs may not allow empty paths; attempting to remove
  /// all components from such a URL will instead set its path to the root path ("/").
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/foo/index.html")!
  /// print(url.pathComponents.first!) // Prints "foo"
  /// print(url.pathComponents.count) // Prints 2
  ///
  /// url.pathComponents.replaceSubrange(
  ///   url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [] as [String]
  /// )
  ///
  /// print(url) // Prints "http://example.com/"
  /// print(url.pathComponents.first!) // Prints ""
  /// print(url.pathComponents.count) // Prints 1
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - bounds: The subrange of the path to replace. The bounds of the range must be valid path-component indices.
  ///   - newComponents: The new components to add to the path.
  /// -  returns: A new range of indices corresponding to the location of the new components in the path.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceSubrange<Components>(
    _ bounds: Range<Index>, with newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    replaceComponents(bounds, withUTF8: newComponents.lazy.map { $0.utf8 })
  }

  @inlinable
  @discardableResult
  internal mutating func replaceComponents<Components>(
    _ range: Range<Index>, withUTF8 newComponents: Components
  ) -> Range<Index>
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    var newSubrange: Range<Index>?
    storage.withUnwrappedMutableStorage(
      { small -> AnyURLStorage in
        let result = small.replacePathComponents(range, with: newComponents)
        newSubrange = result.1
        return result.0
      },
      { large -> AnyURLStorage in
        let result = large.replacePathComponents(range, with: newComponents)
        newSubrange = result.1
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
  /// The new components are inserted before the component currently at the specified index, and their contents will be percent-encoded, if necessary.
  /// If you pass the path's `endIndex` property as the `index` parameter, the new elements are appended to the path.
  /// If appending to a path which ends in a "/" (i.e. a directory path), the trailing empty component will be replaced by the first appended component.
  ///
  /// Here's an example of inserting an array of path components in the middle of a path:
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/swift")!
  /// url.pathComponents.insert(
  ///   contentsOf: ["local", "bin"], at: url.pathComponents.index(after: url.pathComponents.startIndex)
  /// )
  /// print(url) // Prints "file:///usr/local/bin/swift"
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - newComponents: The new components to insert into the path.
  ///   - position: The position at which to insert the new components. `position` must be a valid path component index.
  /// - returns: A new range of indices corresponding to the location of the new components in the path.
  ///
  @inlinable
  @discardableResult
  public mutating func insert<Components>(
    contentsOf newComponents: Components, at position: Index
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    replaceSubrange(position..<position, with: newComponents)
  }

  /// Adds the elements of a collection to the end of this path.
  ///
  /// The contents of the appended components will be percent-encoded, if necessary.
  /// If appending to a path which ends in a "/" (i.e. a directory path), the trailing empty component will be replaced by the first appended component.
  /// Here's an example of building a path by appending path components. Note that the first `append` does not change the `count`.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// print(url.pathComponents.last!) // Prints ""
  /// print(url.pathComponents.count) // Prints 1
  ///
  /// url.pathComponents.append(contentsOf: ["tmp"])
  /// print(url.pathComponents.last!) // Prints "tmp"
  /// print(url.pathComponents.count) // Prints 1
  ///
  /// url.pathComponents.append(contentsOf: ["my_app", "data.json"])
  /// print(url) // Prints "file:///tmp/my_app/data.json"
  /// print(url.pathComponents.last!) // Prints "data.json"
  /// print(url.pathComponents.count) // Prints 3
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter newComponents: The new components to add to end of the path.
  /// - returns: A new range of indices corresponding to the location of the new components in the path.
  ///
  @inlinable
  @discardableResult
  public mutating func append<Components>(
    contentsOf newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    insert(contentsOf: newComponents, at: endIndex)
  }

  /// Adds the elements of a collection to the end of this path.
  ///
  /// The contents of the appended components will be percent-encoded, if necessary.
  /// If appending to a path which ends in a "/" (i.e. a directory path), the trailing empty component will be replaced by the first appended component.
  /// Here's an example of building a path by appending path components. Note that the first append does not change the `count`.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// print(url.pathComponents.last!) // Prints ""
  /// print(url.pathComponents.count) // Prints 1
  ///
  /// url.pathComponents += ["tmp"]
  /// print(url.pathComponents.last!) // Prints "tmp"
  /// print(url.pathComponents.count) // Prints 1
  ///
  /// url.pathComponents += ["my_app", "data.json"]
  /// print(url) // Prints "file:///tmp/my_app/data.json"
  /// print(url.pathComponents.last!) // Prints "data.json"
  /// print(url.pathComponents.count) // Prints 3
  /// ```
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are ignored.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  @inlinable
  public static func += <Components>(
    lhs: inout WebURL.PathComponents, rhs: Components
  ) where Components: Collection, Components.Element: StringProtocol {
    lhs.append(contentsOf: rhs)
  }

  /// Removes the specified subrange of components from the path.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/projects/swift/swift-url/")!
  /// url.pathComponents.removeSubrange(
  ///   url.pathComponents.index(after: url.pathComponents.startIndex)..<url.pathComponents.endIndex
  /// )
  /// print(url) // Prints "http://example.com/projects"
  /// ```
  ///
  /// Some URLs may not allow empty paths; attempting to remove all components from such a URL will instead set its path to the root path ("/"):
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/foo/index.html")!
  /// url.pathComponents.removeSubrange(
  ///   url.pathComponents.startIndex..<url.pathComponents.endIndex
  /// )
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
    replaceComponents(bounds, withUTF8: EmptyCollection<EmptyCollection<UInt8>>()).upperBound
  }

  /// Replaces the path component at the specified position.
  ///
  /// The contents of the new component will be percent-encoded, if necessary.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/bin/swift")!
  /// url.pathComponents.replaceComponent(
  ///   at: url.pathComponents.index(after: url.pathComponents.startIndex),
  ///   with: "lib"
  /// )
  /// print(url) // Prints "file:///usr/lib/swift"
  /// ```
  ///
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), the component is removed -
  /// as if calling `replaceSubrange` with an empty collection.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameters:
  ///   - position: The position of the component to replace. `position` must be a valid path component index.
  ///   - newComponent: The value to set the component to.
  /// - returns: A new range of indices encompassing the replaced component.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceComponent<Component>(
    at position: Index, with newComponent: Component
  ) -> Range<Index> where Component: StringProtocol {
    precondition(position != endIndex, "Cannot replace component at endIndex")
    return replaceSubrange(position..<index(after: position), with: CollectionOfOne(newComponent))
  }

  /// Inserts a component into the path at the specified position.
  ///
  /// The new component is inserted before the component currently at the specified index, and its contents will be percent-encoded, if necessary.
  /// If you pass the path's `endIndex` property as the `index` parameter, the new component is appended to the path.
  /// If appending to a path which ends in a "/" (i.e. a directory path), the trailing empty component will be replaced by the first appended component.
  /// See `append` for more information.
  ///
  /// Here's an example of inserting a path component in the middle of a path:
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/swift")!
  /// url.pathComponents.insert("bin", at: url.pathComponents.index(after: url.pathComponents.startIndex))
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
  @inlinable
  @discardableResult
  public mutating func insert<Component>(
    _ newComponent: Component, at position: Index
  ) -> Range<Index> where Component: StringProtocol {
    insert(contentsOf: CollectionOfOne(newComponent), at: position)
  }

  /// Adds a component to the end of this path.
  ///
  /// The contents of the appended component will be percent-encoded, if necessary.
  /// If appending to a path which ends in a "/" (i.e. a directory path), the trailing empty component will be replaced by the appended component.
  /// Here's an example of building a path by appending path components. Note that the first `append` does not change the `count`.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// print(url.pathComponents.last!) // Prints ""
  /// print(url.pathComponents.count) // Prints 1
  ///
  /// url.pathComponents.append("tmp")
  /// print(url.pathComponents.last!) // Prints "tmp"
  /// print(url.pathComponents.count) // Prints 1
  ///
  /// url.pathComponents.append("data.json")
  /// print(url) // Prints "file:///tmp/data.json"
  /// print(url.pathComponents.last!) // Prints "data.json"
  /// print(url.pathComponents.count) // Prints 2
  /// ```
  ///
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), it is ignored.
  ///
  /// Calling this method invalidates any existing indices for this URL.
  ///
  /// - parameter newComponent: The new component to add to end of the path.
  /// - returns: A new range of indices corresponding to the location of the new component in the path.
  ///
  @inlinable
  @discardableResult
  public mutating func append<Component>(
    _ newComponent: Component
  ) -> Range<Index> where Component: StringProtocol {
    append(contentsOf: CollectionOfOne(newComponent))
  }

  /// Removes the component at the given index from the path.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/projects/swift/swift-url/Sources/")!
  /// url.pathComponents.remove(at: url.pathComponents.index(after: url.pathComponents.startIndex))
  /// print(url) // Prints "http://example.com/projects/swift-url/Sources/"
  /// ```
  ///
  /// Some URLs may not allow empty paths; attempting to remove the last component from such a URL will instead set its path to the root path ("/"):
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/foo")!
  /// url.pathComponents.remove(at: url.pathComponents.startIndex)
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
  /// Attempting to remove more components than exist in the path triggers a runtime error.
  /// Some URLs may not allow empty paths; attempting to remove all components from such a URL will instead set its path to the root path ("/"):
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/foo/bar")!
  /// url.pathComponents.removeLast()
  /// print(url) // Prints "http://example.com/foo"
  ///
  /// url.pathComponents.removeLast()
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
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents += ["Users", "karl", "Desktop"] // "file:///Users/karl/Desktop"
  /// url.pathComponents.ensureDirectoryPath() // "file:///Users/karl/Desktop/"
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

  @inlinable
  internal var pathComponentsStartIndex: WebURL.PathComponents.Index {
    switch self {
    case .small(let storage): return storage.pathComponentsStartIndex
    case .large(let storage): return storage.pathComponentsStartIndex
    }
  }

  @inlinable
  internal var pathComponentsEndIndex: WebURL.PathComponents.Index {
    switch self {
    case .small(let storage): return storage.pathComponentsEndIndex
    case .large(let storage): return storage.pathComponentsEndIndex
    }
  }

  @inlinable
  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int? {
    switch self {
    case .small(let storage): return storage.endOfPathComponent(startingAt: componentStartOffset)
    case .large(let storage): return storage.endOfPathComponent(startingAt: componentStartOffset)
    }
  }

  @inlinable
  internal func startOfPathComponent(endingAt componentEndOffset: Int) -> Int? {
    switch self {
    case .small(let storage): return storage.startOfPathComponent(endingAt: componentEndOffset)
    case .large(let storage): return storage.startOfPathComponent(endingAt: componentEndOffset)
    }
  }
}

extension URLStorage {

  @inlinable
  internal var pathComponentsStartIndex: WebURL.PathComponents.Index {
    let pathStart = header.structure.rangeForReplacingCodeUnits(of: .path).lowerBound
    return WebURL.PathComponents.Index(codeUnitRange: pathStart..<pathStart + header.structure.firstPathComponentLength)
  }

  @inlinable
  internal var pathComponentsEndIndex: WebURL.PathComponents.Index {
    let pathEnd = header.structure.rangeForReplacingCodeUnits(of: .path).upperBound
    return WebURL.PathComponents.Index(codeUnitRange: pathEnd..<pathEnd)
  }

  /// Returns the code-unit offset at which the component ends whose `startIndex` is `componentStartOffset`.
  ///
  /// If `componentStartOffset` is the `endIndex` of the path range, the returned offset is `nil`.
  ///
  @inlinable
  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int? {
    let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
    guard !pathRange.isEmpty, pathRange.contains(componentStartOffset) else { return nil }
    assert(codeUnits[componentStartOffset] == ASCII.forwardSlash.codePoint, "UTF8 position not aligned to a component")
    return codeUnits[componentStartOffset + 1..<pathRange.upperBound].firstIndex(of: ASCII.forwardSlash.codePoint)
      ?? pathRange.upperBound
  }

  /// Returns the code-unit offset at which the component starts whose `endIndex` is `componentEndOffset`.
  ///
  /// - If `componentEndOffset` is the `endIndex` of the path range, the returned offset is the start of the last path component
  ///   (since the last component's `endIndex` is the `endIndex` of the path range).
  /// - If `componentEndOffset` is the `startIndex` of the path range, the returned offset is `nil`
  ///   (as there is no component whose `endIndex` is the `startIndex` of the path range).
  ///
  @inlinable
  internal func startOfPathComponent(endingAt componentEndOffset: Int) -> Int? {
    let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
    guard !pathRange.isEmpty, componentEndOffset > pathRange.lowerBound else { return nil }
    if pathRange.contains(componentEndOffset) {
      assert(codeUnits[componentEndOffset] == ASCII.forwardSlash.codePoint, "UTF8 position not aligned to a component")
    } else {
      assert(componentEndOffset == pathRange.upperBound, "UTF8 position is not within the path")
    }
    return codeUnits[pathRange.lowerBound..<componentEndOffset].lastIndex(of: ASCII.forwardSlash.codePoint)
      ?? pathRange.lowerBound
  }
}

extension URLStorage {

  /// Removes all components from the path, to the extent that is allowed. URLs which cannot have an empty path will have their path set to "/".
  ///
  /// If this URL `cannotBeABase`, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func _clearPath() -> (AnyURLStorage, Range<WebURL.PathComponents.Index>) {

    let oldStructure = header.structure
    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)
    precondition(!oldStructure.cannotBeABaseURL, "Cannot replace components of a cannot-be-a-base URL")

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
    return (replaced, Range(uncheckedBounds: (newLowerBound, newUpperBound)))
  }

  /// Replaces the path components in the given range with the given new components.
  /// Analogous to `replaceSubrange` from `RangeReplaceableCollection`.
  ///
  /// If this URL `cannotBeABase`, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func replacePathComponents<Components>(
    _ replacedIndices: Range<WebURL.PathComponents.Index>,
    with components: Components
  ) -> (AnyURLStorage, Range<WebURL.PathComponents.Index>)
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    let oldStructure = header.structure
    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)
    precondition(!oldStructure.cannotBeABaseURL, "Cannot replace components of a cannot-be-a-base URL")

    // If 'firstNewComponentLength' is nil, we infer that the components are empty (i.e. removal operation).
    let components = components.lazy.filter { utf8 in
      !PathComponentParser.isSingleDotPathSegment(utf8) && !PathComponentParser.isDoubleDotPathSegment(utf8)
    }
    let firstNewComponentLength = components.first.map { 1 + $0.lazy.percentEncoded(as: \.pathComponent).count }

    // If inserting elements at the end of a path which ends in a trailing slash, widen the replacement range
    // so we drop the trailing empty component. This means appending "foo" to "/" results in "/foo" rather than "//foo",
    // and "foo" to "/usr/" results in "/usr/foo" rather than "/usr//foo".
    var replacedIndices = replacedIndices
    if replacedIndices.lowerBound.range.lowerBound == oldPathRange.upperBound,
      firstNewComponentLength != nil, _hasDirectoryPath
    {
      let newLowerBound = replacedIndices.lowerBound.range.lowerBound - 1..<replacedIndices.lowerBound.range.lowerBound
      replacedIndices = WebURL.PathComponents.Index(codeUnitRange: newLowerBound)..<replacedIndices.upperBound
    }
    let replacedRange = replacedIndices.lowerBound.range.lowerBound..<replacedIndices.upperBound.range.lowerBound

    if replacedRange == oldPathRange, firstNewComponentLength == nil {
      return _clearPath()
    }

    let insertedPathLength = components.dropFirst().reduce(into: firstNewComponentLength ?? 0) { counter, component in
      counter += 1 + component.lazy.percentEncoded(as: \.pathComponent).count
    }

    // Calculate what the new first component will be, and whether the URL might require a path sigil.
    // A URL requires a sigil if there is no authority, the path has >1 component, and the first component is empty.
    let newPathFirstComponentLength: Int
    let newPathRequiresSigil: Bool
    if replacedRange.lowerBound == oldPathRange.lowerBound {
      // Modifying the front of the path.
      if let firstInsertedComponentLength = firstNewComponentLength {
        // Inserting/replacing. The first component will be from the new components.
        let firstComponentEmpty = (firstInsertedComponentLength == 1)
        let hasComponentsAfter =
          (replacedRange.upperBound != oldPathRange.upperBound) || (insertedPathLength != firstInsertedComponentLength)
        newPathRequiresSigil = firstComponentEmpty && hasComponentsAfter
        newPathFirstComponentLength = firstInsertedComponentLength
      } else {
        // Removing. The first component will be at replacedIndices.upperBound.
        let firstComponentEmpty = (replacedIndices.upperBound.range.count == 1)
        assert(replacedRange.upperBound != oldPathRange.upperBound, "Full path removals should have been handled above")
        newPathRequiresSigil = firstComponentEmpty
        newPathFirstComponentLength = replacedIndices.upperBound.range.count
      }
    } else {
      // Modifying the middle/end of the path. The current first component will be maintained.
      let oldStartIndex = pathComponentsStartIndex
      let firstComponentEmpty = (oldStartIndex.range.count == 1)
      let hasComponentsAfter: Bool
      if firstNewComponentLength != nil {
        // Inserting/replacing. There will certainly be components after the first one.
        hasComponentsAfter = true
      } else {
        // Removing. Unless the entire rest of the path is removed, there will be components remaining.
        hasComponentsAfter = (replacedRange != oldStartIndex.range.upperBound..<oldPathRange.upperBound)
      }
      newPathRequiresSigil = firstComponentEmpty && hasComponentsAfter
      newPathFirstComponentLength = oldStructure.firstPathComponentLength
    }

    // Calculate the new structure and replace the code-units.
    var newStructure = oldStructure
    var commands = [ReplaceSubrangeOperation]()

    var pathOffsetFromModifiedSigil = 0
    switch (oldStructure.sigil, newPathRequiresSigil) {
    case (.authority, _), (.none, false), (.path, true):
      break
    case (.none, true):
      commands.append(
        .replace(
          subrange: oldStructure.rangeForReplacingSigil,
          withCount: Sigil.path.length,
          writer: Sigil.path.unsafeWrite)
      )
      newStructure.sigil = .path
      pathOffsetFromModifiedSigil = 2
    case (.path, false):
      commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
      newStructure.sigil = .none
      pathOffsetFromModifiedSigil = -2
    }

    newStructure.firstPathComponentLength = newPathFirstComponentLength
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

    // Post-replacement normalization of Windows drive letters.
    //
    // This is necessary to preserve idempotence. It is much simpler to fix this up after replacing the code-units.
    // Luckily, it doesn't change the length of the URL or any of its components, so it doesn't modify the URLStructure.
    // That means we don't need to worry about possibly switching header representations,
    // and can do a straight code-unit swap.
    if case .file = newStructure.schemeKind {
      switch replaced {
      case .small(var small):
        replaced = _tempStorage
        small._normalizeWindowsDriveLetterIfPresent()
        replaced = AnyURLStorage(small)
      case .large(var large):
        replaced = _tempStorage
        large._normalizeWindowsDriveLetterIfPresent()
        replaced = AnyURLStorage(large)
      }
    }

    // Calculate the updated path component indices to return.
    let lowerBoundStartPosition = replacedRange.lowerBound + pathOffsetFromModifiedSigil
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
    return (replaced, Range(uncheckedBounds: (newLowerBound, newUpperBound)))
  }

  @inlinable
  internal var _hasDirectoryPath: Bool {
    let pathRange = header.structure.rangeForReplacingCodeUnits(of: .path)
    return pathRange.count >= 1 && codeUnits[pathRange.upperBound - 1] == ASCII.forwardSlash.codePoint
  }

  @inlinable
  internal mutating func _normalizeWindowsDriveLetterIfPresent() {
    guard case .file = header.structure.schemeKind else { return }
    let path = codeUnits[header.structure.rangeForReplacingCodeUnits(of: .path)].dropFirst()
    if PathComponentParser.isWindowsDriveLetter(path.prefix(2)),
      path.count == 2 || path.dropFirst(2).first == ASCII.forwardSlash.codePoint
    {
      codeUnits[path.startIndex + 1] = ASCII.colon.codePoint
    }
  }
}
