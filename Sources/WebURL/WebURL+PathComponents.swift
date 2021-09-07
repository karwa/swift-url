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

  /// A mutable view of this URL's path components.
  ///
  /// Use of this view requires that the URL is hierarchical (see `WebURL.isHierarchical`).
  /// Using this view with a non-hierachical URL will trigger a runtime error.
  ///
  public var pathComponents: PathComponents {
    get {
      precondition(isHierarchical, "Non-hierarchical URLs do not have path components")
      return PathComponents(storage: storage)
    }
    _modify {
      precondition(isHierarchical, "Non-hierarchical URLs do not have path components")
      var view = PathComponents(storage: storage)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      precondition(isHierarchical, "Non-hierarchical URLs do not have path components")
      try! utf8.setPath(newValue.storage.utf8.path)
    }
  }

  /// A view of the components in a hierarchical URL's path.
  ///
  /// This collection provides efficient, bidirectional, read-write access to the URL's path components.
  /// Components are percent-decoded when they are returned and percent-encoded when they are replaced.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/swift/packages/%F0%9F%A6%86%20tracker")!
  /// url.pathComponents.first! // "swift"
  /// url.pathComponents.last! // "🦆 tracker"
  ///
  /// url.pathComponents.removeLast()
  /// url.pathComponents.append("swift-url")
  /// print(url) // Prints "http://example.com/swift/packages/swift-url"
  /// ```
  ///
  /// Path components extend from their leading slash until the leading slash of the next component (or the end of the path). That means that a URL whose
  /// path is "/" contains a single, empty path component, and paths which end with a "/" (also referred to as directory paths) end with an empty component.
  /// When appending to a directory path (through `append` or any other function which replaces path components), this empty component is dropped
  /// so that the result does not contain excessive empties. To create a directory path, append an empty component or call `ensureDirectoryPath`.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents.last! // ""
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents.append("usr") // file:///usr
  /// url.pathComponents.count // 1, because the trailing empty component was dropped.
  ///
  /// url.pathComponents += ["bin", "swift"] // file:///usr/bin/swift
  /// url.pathComponents.last! // "swift"
  /// url.pathComponents.count // 3
  ///
  /// url.pathComponents.ensureDirectoryPath() // file:///usr/bin/swift/
  /// url.pathComponents.last! // ""
  /// url.pathComponents.count // 4
  /// ```
  ///
  /// Modifying the URL, such as by setting its `path` or any other properties, invalidates all previously obtained path component indices.
  /// Functions which modify the path components return new indices which may be used to maintain position across modifications.
  ///
  /// It is best to avoid making assumptions about how this collection's `count` is affected by a modification. In addition to the dropping of trailing empty
  /// components described above, URLs with particular schemes are forbidden from ever having empty paths; attempting to remove all of the path components
  /// from such a URL will result in a path with a single, empty component, just like setting the empty string to the URL's `path` property.
  ///
  /// Accessing this view triggers a runtime error if the URL is non-hierarchical.
  /// Almost all URLs _are_ hierarchical (in particular, URLs with special schemes, such as http(s) and file, are always hierarchical).
  /// Non-hierarchical URLs can be recognized by the lack of slashes immediately following their scheme. Examples of such URLs are:
  ///
  /// - `mailto:bob@example.com`
  /// - `javascript:alert("hello");`
  /// - `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`
  ///
  /// See the `WebURL.isHierarchical` property for more information.
  ///
  public struct PathComponents {

    @usableFromInline
    internal var storage: URLStorage

    internal init(storage: URLStorage) {
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

  /// The UTF-8 code-units containing the given path component.
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
  /// upon insertion. If any of the new components in `newComponents` are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive),
  /// those components are ignored.
  ///
  /// The following example shows replacing the last 2 components of a `file:` URL with an array of 4 strings.
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
  /// If you pass a zero-length range as the `bounds` parameter, this method inserts the elements of `newComponents` at `bounds.lowerBound`.
  /// Calling the `insert(contentsOf:at:)` method instead is preferred. If inserting at the end of a path whose last component is empty (i.e. a directory path),
  /// the trailing empty component will be dropped and replaced by the first inserted component.
  ///
  /// Note how the following example inserts 2 components at the end of a path which already contains 2 components (the last of which is empty),
  /// resulting in a path with only 3 components:
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/")!
  /// url.pathComponents.last! // ""
  /// url.pathComponents.count // 2
  ///
  /// url.pathComponents.replaceSubrange(
  ///   url.pathComponents.endIndex..<url.pathComponents.endIndex, with: ["bin", "swift"]
  /// )
  ///
  /// print(url) // Prints "file:///usr/bin/swift"
  /// url.pathComponents.last! // "swift"
  /// url.pathComponents.count // 3
  /// ```
  ///
  /// If the collection passed as the `newComponents` parameter does not contain any insertable components (i.e. it has a `count` of 0, or contains only
  /// "." or ".." components), this method removes the components in the given subrange without replacement.
  /// Calling the `removeSubrange(_:)` method instead is preferred.
  /// URLs with particular schemes are forbidden from ever having empty paths; attempting to remove all of the path components
  /// from such a URL will result in a path with a single, empty component, just like setting the empty string to the URL's `path` property.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/awesome_product/index.html")!
  /// url.pathComponents.first! // "awesome_product"
  /// url.pathComponents.count // 2
  ///
  /// url.pathComponents.replaceSubrange(
  ///   url.pathComponents.startIndex..<url.pathComponents.endIndex, with: [] as [String]
  /// )
  ///
  /// print(url) // Prints "http://example.com/"
  /// url.pathComponents.first! // ""
  /// url.pathComponents.count // 1
  /// ```
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
    // TODO: [performance]: Create a specialized StringProtocol -> UTF8View projection wrapper.
    replaceComponents(bounds, withUTF8: newComponents.lazy.map { $0.utf8 })
  }

  @inlinable
  @discardableResult
  internal mutating func replaceComponents<Components>(
    _ range: Range<Index>, withUTF8 newComponents: Components
  ) -> Range<Index>
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {
    storage.replacePathComponents(range, with: newComponents)
  }
}

// Insert, Append, Remove, Replace.

extension WebURL.PathComponents {

  /// Inserts the elements of a collection into the path at the specified position.
  ///
  /// The new components are inserted before the component currently at the specified index, and their contents will be percent-encoded, if necessary.
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive), those components are ignored.
  ///
  /// The following example inserts an array of path components in the middle of a path:
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/swift")!
  /// url.pathComponents.insert(
  ///   contentsOf: ["local", "bin"], at: url.pathComponents.index(after: url.pathComponents.startIndex)
  /// )
  /// print(url) // Prints "file:///usr/local/bin/swift"
  /// ```
  ///
  /// If you pass the path's `endIndex` property as the `position` parameter, the new elements are appended to the path.
  /// Calling the `append(contentsOf:)` method instead is preferred. If inserting at the end of a path whose last component is empty (i.e. a directory path),
  /// the trailing empty component will be dropped and replaced by the first inserted component.
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
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive), those components are ignored.
  ///
  /// If appending to a path whose last component is empty (i.e. a directory path),
  /// the trailing empty component will be dropped and replaced by the first inserted component.
  ///
  /// The following example builds a path by appending path components. Note that the first `append` does not change the `count`, as the URL initially
  /// has a directory path.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents.last! // ""
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents.append(contentsOf: ["tmp"])
  /// url.pathComponents.last! // "tmp"
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents.append(contentsOf: ["my_app", "data.json"])
  /// url.pathComponents.last! // "data.json"
  /// url.pathComponents.count // 3
  ///
  /// print(url) // Prints "file:///tmp/my_app/data.json"
  /// ```
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
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive), those components are ignored.
  ///
  /// If appending to a path whose last component is empty (i.e. a directory path),
  /// the trailing empty component will be dropped and replaced by the first inserted component.
  ///
  /// The following example builds a path by appending path components. Note that the first `+=` does not change the `count`, as the URL initially
  /// has a directory path.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents.last! // ""
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents += ["tmp"]
  /// url.pathComponents.last! // "tmp"
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents += ["my_app", "data.json"]
  /// url.pathComponents.last! // "data.json"
  /// url.pathComponents.count // 3
  ///
  /// print(url) // Prints "file:///tmp/my_app/data.json"
  /// ```
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
  /// URLs with particular schemes are forbidden from ever having empty paths; attempting to remove all of the path components
  /// from such a URL will result in a path with a single, empty component, just like setting the empty string to the URL's `path` property.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/awesome_product/index.html")!
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
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive), the component at `position` is removed -
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
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive), it is ignored.
  ///
  /// The following example inserts a component in the middle of a path:
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/swift")!
  /// url.pathComponents.insert(
  ///   "bin",
  ///   at: url.pathComponents.index(after: url.pathComponents.startIndex)
  /// )
  /// print(url) // Prints "file:///usr/bin/swift"
  /// ```
  ///
  /// If you pass the path's `endIndex` property as the `position` parameter, the new component is appended to the path.
  /// Calling the `append(_:)` method instead is preferred. If inserting at the end of a path whose last component is empty (i.e. a directory path),
  /// the trailing empty component will be dropped and replaced by the new component.
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
  /// If the new component is "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case-insensitive), it will be ignored.
  ///
  /// If appending to a path whose last component is empty (i.e. a directory path),
  /// the trailing empty component will be dropped and replaced by the new component.
  ///
  /// The following example builds a path by appending components. Note that the first `append` does not change the `count`, as the URL initially
  /// has a directory path.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents.last! // ""
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents.append("tmp")
  /// url.pathComponents.last! // "tmp"
  /// url.pathComponents.count // 1
  ///
  /// url.pathComponents.append("data.json")
  /// url.pathComponents.last! // "data.json"
  /// url.pathComponents.count // 2
  ///
  /// print(url) // Prints "file:///tmp/data.json"
  /// ```
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
  /// url.pathComponents.remove(
  ///   at: url.pathComponents.index(after: url.pathComponents.startIndex)
  /// )
  /// print(url) // Prints "http://example.com/projects/swift-url/Sources/"
  /// ```
  ///
  /// URLs with particular schemes are forbidden from ever having empty paths; attempting to remove all of the path components
  /// from such a URL will result in a path with a single, empty component, just like setting the empty string to the URL's `path` property.
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
  /// URLs with particular schemes are forbidden from ever having empty paths; attempting to remove all of the path components
  /// from such a URL will result in a path with a single, empty component, just like setting the empty string to the URL's `path` property.
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
  /// The following example demonstrates building a file path by appending components,
  /// and finishes by using `ensureDirectoryPath` to ensure the path ends in a trailing slash:
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents += ["Users", "karl", "Desktop"] // "file:///Users/karl/Desktop"
  /// url.pathComponents.ensureDirectoryPath() // "file:///Users/karl/Desktop/"
  /// ```
  ///
  /// If the path is already a directory path, this method has no effect.
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
  /// If this URL is non-hierarchical, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func _clearPath() -> Range<WebURL.PathComponents.Index> {

    let oldStructure = header.structure
    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)
    precondition(oldStructure.isHierarchical, "Cannot replace components of a non-hierarchical URL")

    // We can only set an empty path if this is a non-special scheme with authority ("foo://host?query").
    // Everything else (special, path-only) requires at least a lone "/".
    if !oldStructure.schemeKind.isSpecial, oldStructure.hasAuthority {
      var newStructure = oldStructure
      newStructure.pathLength = 0
      newStructure.firstPathComponentLength = 0
      removeSubrange(oldPathRange, newStructure: newStructure)
    } else {
      withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
        var newStructure = oldStructure
        if case .path = oldStructure.sigil {
          commands += .remove(oldStructure.rangeForReplacingSigil)
          newStructure.sigil = .none
        }
        newStructure.pathLength = 1
        newStructure.firstPathComponentLength = 1
        commands += .replace(oldPathRange, withCount: 1) { buffer in
          buffer.baseAddress.unsafelyUnwrapped.initialize(to: ASCII.forwardSlash.codePoint)
          return 1
        }
        try! multiReplaceSubrange(commands, newStructure: newStructure).get()
      }
    }
    let newPathStart = self.structure.pathStart
    let newPathEnd = self.structure.pathStart &+ self.structure.pathLength
    let newLowerBound = WebURL.PathComponents.Index(codeUnitRange: newPathStart..<newPathEnd)
    let newUpperBound = WebURL.PathComponents.Index(codeUnitRange: newPathEnd..<newPathEnd)
    return Range(uncheckedBounds: (newLowerBound, newUpperBound))
  }

  /// Replaces the path components in the given range with the given new components.
  /// Analogous to `replaceSubrange` from `RangeReplaceableCollection`.
  ///
  /// If this URL is non-hierarchical, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func replacePathComponents<Components>(
    _ replacedIndices: Range<WebURL.PathComponents.Index>,
    with components: Components
  ) -> Range<WebURL.PathComponents.Index>
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    let oldStructure = header.structure
    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)
    precondition(oldStructure.isHierarchical, "Cannot replace components of a non-hierarchical URL")

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
    var pathOffsetFromModifiedSigil = 0

    withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
      var newStructure = oldStructure
      switch (oldStructure.sigil, newPathRequiresSigil) {
      case (.authority, _), (.none, false), (.path, true):
        break
      case (.none, true):
        commands += .replace(
          oldStructure.rangeForReplacingSigil,
          withCount: Sigil.path.length,
          writer: Sigil.unsafeWrite(.path))
        newStructure.sigil = .path
        pathOffsetFromModifiedSigil = 2
      case (.path, false):
        commands += .remove(oldStructure.rangeForReplacingSigil)
        newStructure.sigil = .none
        pathOffsetFromModifiedSigil = -2
      }

      newStructure.firstPathComponentLength = newPathFirstComponentLength
      newStructure.pathLength -= replacedRange.count
      newStructure.pathLength += insertedPathLength

      commands += .replace(replacedRange, withCount: insertedPathLength) { buffer in
        var bytesWritten = 0
        for component in components {
          buffer[bytesWritten] = ASCII.forwardSlash.codePoint
          bytesWritten &+= 1
          bytesWritten &+=
            UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...])
            .fastInitialize(from: component.lazy.percentEncoded(as: \.pathComponent))
        }
        return bytesWritten
      }
      try! multiReplaceSubrange(commands, newStructure: newStructure).get()
    }

    // Post-replacement normalization of Windows drive letters.
    // This is necessary to preserve idempotence, but doesn't modify the URLStructure.
    if case .file = header._structure.schemeKind {
      _normalizeWindowsDriveLetterIfPresent()
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
    return Range(uncheckedBounds: (newLowerBound, newUpperBound))
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
