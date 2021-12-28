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

  /// A read-write view of the URL's path components.
  ///
  /// This view provides a convenient, bidirectional `Collection` interface to a URL's path components.
  /// Path components are automatically percent-decoded when they are returned and encoded when they are inserted.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/swift/packages/%F0%9F%A6%86%20tracker")!
  /// for component in url.pathComponents {
  ///   // component = "swift", "packages", "🦆 tracker"
  /// }
  ///
  /// url.pathComponents.removeLast()
  /// url.pathComponents.append("swift-url")
  /// print(url)
  /// // ✅ "https://example.com/swift/packages/swift-url"
  ///
  /// url.pathComponents += ["releases", "1.0", "readme"]
  /// // ✅ "https://example.com/swift/packages/swift-url/releases/1.0/readme"
  /// ```
  ///
  /// Because this view is a Collection, it inherits a number of useful algorithms and functionality
  /// from the standard library, such as searching, map/reduce/filter and slicing, and can be used with many
  /// other generic algorithms and data structures.
  ///
  /// > Note:
  /// > If the URL has an opaque path, accessing this view is invalid and triggers a runtime error.
  /// > See the ``WebURL/hasOpaquePath`` property for more information.
  /// > http, https, and file URLs never have opaque paths and can always be used with this view.
  ///
  /// ### Indexes
  ///
  /// Advanced algorithms may use indexes to identify path components positionally.
  ///
  /// Modifying the URL, such as modifying its path components, setting its ``path`` or any other properties,
  /// invalidates all previously-obtained indexes. All functions on this view which mutate the path return
  /// new indexes, which can be used to maintain position across modifications. The following example demonstrates
  /// how indexes can be used to create an algorithm which removes trailing periods from a URL's path components.
  ///
  /// ```swift
  /// func trimDots(in url: inout WebURL) {
  ///   var idx = url.pathComponents.startIndex
  ///   while idx < url.pathComponents.endIndex {
  ///     let component = url.pathComponents[idx]
  ///     guard component.last == "." else {
  ///       url.pathComponents.formIndex(after: &idx)
  ///       continue
  ///     }
  ///     // Replace the component with its trimmed version.
  ///     // This invalidates 'idx', but the 'replaceComponent' function
  ///     // returns a new index so we can continue iterating.
  ///     let lastNonDot = component.lastIndex(where: { $0 != "." }) ?? component.startIndex
  ///     idx = url.pathComponents.replaceComponent(
  ///       at: idx, with: component[...lastNonDot]
  ///     ).upperBound
  ///   }
  /// }
  ///
  /// var url = WebURL("https://example.com/foo./bar/baz..")!
  /// trimDots(in: &url)
  /// // ✅ "https://example.com/foo/bar/baz"
  /// //                           ^       ^
  /// ```
  ///
  /// ## Topics
  ///
  /// ### Appending or Inserting Path Components
  ///
  /// - ``WebURL/WebURL/PathComponents-swift.struct/append(_:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/append(contentsOf:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/insert(_:at:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/insert(contentsOf:at:)``
  ///
  /// ### Removing Path Components
  ///
  /// - ``WebURL/WebURL/PathComponents-swift.struct/removeLast(_:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/remove(at:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/removeSubrange(_:)``
  ///
  /// ### Replacing Path Components
  ///
  /// - ``WebURL/WebURL/PathComponents-swift.struct/replaceComponent(at:with:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/replaceSubrange(_:with:)``
  ///
  /// ### Directory Paths
  ///
  /// - ``WebURL/WebURL/PathComponents-swift.struct/ensureDirectoryPath()``
  ///
  /// ### Manually Percent-Encoding or Decoding
  ///
  /// - ``WebURL/WebURL/PathComponents-swift.struct/replaceSubrange(_:withPercentEncodedComponents:)``
  /// - ``WebURL/WebURL/PathComponents-swift.struct/subscript(raw:)``
  ///
  /// ### View Type
  ///
  /// - ``WebURL/WebURL/PathComponents-swift.struct``
  ///
  public var pathComponents: PathComponents {
    get {
      precondition(!hasOpaquePath, "URLs with opaque paths do not have path components")
      return PathComponents(storage: storage)
    }
    _modify {
      precondition(!hasOpaquePath, "URLs with opaque paths do not have path components")
      var view = PathComponents(storage: storage)
      storage = _tempStorage
      defer { storage = view.storage }
      yield &view
    }
    set {
      precondition(!hasOpaquePath, "URLs with opaque paths do not have path components")
      try! utf8.setPath(newValue.storage.utf8.path)
    }
  }

  /// A read-write view of the URL's path components.
  ///
  /// This view provides a convenient, bidirectional `Collection` interface to a URL's path components.
  /// Path components are automatically percent-decoded when they are returned and encoded when they are inserted.
  ///
  /// Access a URL's path components through its ``WebURL/pathComponents-swift.property`` property.
  ///
  /// ```swift
  /// var url = WebURL("https://example.com/swift/packages/%F0%9F%A6%86%20tracker")!
  /// for component in url.pathComponents {
  ///   // component = "swift", "packages", "🦆 tracker"
  /// }
  ///
  /// url.pathComponents.removeLast()
  /// url.pathComponents.append("swift-url")
  /// print(url)
  /// // ✅ "https://example.com/swift/packages/swift-url"
  ///
  /// url.pathComponents += ["releases", "1.0", "readme"]
  /// // ✅ "https://example.com/swift/packages/swift-url/releases/1.0/readme"
  /// ```
  ///
  /// > Tip:
  /// > The documentation for this type can be found at: ``WebURL/pathComponents-swift.property``.
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
// MARK: - Standard Protocols
// --------------------------------------------


#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.PathComponents: Sendable {}
#endif


// --------------------------------------------
// MARK: - Reading
// --------------------------------------------


extension WebURL.PathComponents {

  /// The position of a path component within a URL string.
  ///
  public struct Index: Equatable, Comparable {

    /// The range of the component in the overall URL string's code-units.
    /// Note that this includes the leading "/", so paths which end in a "/" include a trailing empty component
    /// before reaching endIndex.
    ///
    @usableFromInline
    internal var range: Range<Int>

    @inlinable
    internal init(codeUnitRange: Range<Int>) {
      self.range = codeUnitRange
    }

    @inlinable
    internal init(codeUnitRange: Range<URLStorage.SizeType>) {
      self.range = codeUnitRange.toCodeUnitsIndices()
    }

    @inlinable
    public static func < (lhs: Index, rhs: Index) -> Bool {
      lhs.range.lowerBound < rhs.range.lowerBound
    }
  }
}

extension WebURL.UTF8View {

  /// A slice containing the contents of the given path component.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/music/genres/electronic")!
  /// let genreIndex = url.pathComponents.indices.last!
  /// print(url.pathComponents[genreIndex]) // "electronic"
  ///
  /// let genreUTF8  = url.utf8.pathComponent(genreIndex)
  /// assert(genreUTF8.elementsEqual("electronic".utf8)) // ✅
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/pathComponents-swift.property``
  ///
  public func pathComponent(_ component: WebURL.PathComponents.Index) -> SubSequence {
    // These bounds checks are only for semantics, not for memory safety; the slicing subscript handles that.
    assert(component.range.lowerBound >= path.startIndex && component.range.lowerBound <= path.endIndex)
    assert(self[Int(component.range.lowerBound)] == ASCII.forwardSlash.codePoint)
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
    storage.utf8.pathComponent(position).percentDecodedString(substitutions: .none)
  }

  public func distance(from start: Index, to end: Index) -> Int {
    guard start <= end else {
      return -1 * distance(from: end, to: start)
    }
    let pathSlice = storage.utf8[start.range.lowerBound..<end.range.lowerBound]
    var n = 0
    var idx = pathSlice.startIndex
    while idx < pathSlice.endIndex {
      if pathSlice[idx] == ASCII.forwardSlash.codePoint {
        n &+= 1
      }
      pathSlice.formIndex(after: &idx)
    }
    return n
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

extension WebURL.PathComponents {

  /// Returns the path component at a given location, without percent-decoding it.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/music/bands/AC%2FDC")!
  ///
  /// // The regular subscript returns decoded components.
  /// url.pathComponents[url.pathComponents.indices.last!]
  /// // "AC/DC"
  ///
  /// // The 'raw' subscript maintains percent-encoding.
  /// url.pathComponents[raw: url.pathComponents.indices.last!]
  /// // "AC%2FDC"
  /// ```
  ///
  public subscript(raw position: Index) -> String {
    String(decoding: storage.utf8.pathComponent(position), as: UTF8.self)
  }
}


// --------------------------------------------
// MARK: - Writing
// --------------------------------------------


extension WebURL.PathComponents {

  /// Replaces the path components at a range of locations.
  ///
  /// The following example demonstrates replacing multiple components in the middle of the path.
  /// The number of new components does not need to equal the number of components being replaced.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/bin/swift")!
  /// let secondPosition = url.pathComponents.index(after: url.pathComponents.startIndex)
  /// url.pathComponents.replaceSubrange(
  ///   secondPosition..<url.pathComponents.endIndex,
  ///   with: ["lib", "swift", "linux", "libswiftCore.so"]
  /// )
  /// print(url)
  /// // ✅ "file:///usr/lib/swift/linux/libswiftCore.so"
  /// //                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The inserted components must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If any of the new components are `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// those components are ignored.
  ///
  /// If `bounds` is an empty range, this method inserts the new components at `bounds.lowerBound`.
  /// Calling ``insert(contentsOf:at:)`` instead is preferred.
  ///
  /// If `newComponents` does not contain any insertable components, this method removes the components at `bounds`
  /// without replacement. Calling ``removeSubrange(_:)`` instead is preferred.
  ///
  /// Some URLs are forbidden from having empty paths; removing all path components from such URLs
  /// will result in a path with a single, empty component. This matches the behavior of setting
  /// the URL's ``WebURL/path`` property to the empty string.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - bounds: The range of components to replace.
  ///   - newComponents: The components to insert into the path.
  /// -  returns: The locations of the inserted components in the URL's path.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceSubrange<Components>(
    _ bounds: Range<Index>, with newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    // TODO: [performance]: Create a specialized StringProtocol -> UTF8View projection wrapper.
    storage.replacePathComponents(
      bounds, with: newComponents.lazy.map { $0.utf8 }, encodeSet: PathComponentEncodeSet()
    )
  }

  /// Replaces the path components at a range of locations with components that are already percent-encoded.
  ///
  /// This method behaves identically to ``replaceSubrange(_:with:)``, except that the elements of `newComponents`
  /// are assumed to be percent-encoded. Additional percent-encoding will be added as necessary, but any existing
  /// percent-encoded bytes will not be double-encoded. The following example demonstrates this difference.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/music/bands")!
  ///
  /// // replaceSubrange(_:with:) preserves the given components exactly,
  /// // so components containing percent-encoding end up being encoded twice.
  /// var urlA = url
  /// urlA.pathComponents.replaceSubrange(
  ///   urlA.pathComponents.endIndex..<urlA.pathComponents.endIndex,
  ///   with: ["The%20Beatles"]
  /// )
  /// print(urlA)
  /// // ❗️ "http://example.com/music/bands/The%2520Beatles"
  /// //                                       ^^^^^
  ///
  /// // Use replaceSubrange(_:withPercentEncodedComponents:) to avoid double-encoding
  /// // components which are already percent-encoded.
  /// var urlB = url
  /// urlB.pathComponents.replaceSubrange(
  ///   urlB.pathComponents.endIndex..<urlB.pathComponents.endIndex,
  ///   withPercentEncodedComponents: ["The%20Beatles"]
  /// )
  /// print(urlB)
  /// // ✅ "http://example.com/music/bands/The%20Beatles"
  /// //                                       ^^^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - bounds: The range of components to replace.
  ///   - newComponents: The components to insert into the path. Assumed to already be percent-encoded.
  /// -  returns: The locations of the inserted components in the URL's path.
  ///
  @inlinable
  @discardableResult
  public mutating func replaceSubrange<Components>(
    _ range: Range<Index>, withPercentEncodedComponents newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    storage.replacePathComponents(
      range, with: newComponents.lazy.map { $0.utf8 }, encodeSet: PreencodedPathComponentEncodeSet()
    )
  }
}

// Insert, Append, Remove, Replace.

extension WebURL.PathComponents {

  /// Inserts multiple path components at a given location.
  ///
  /// The new components are inserted before the component currently at `position`.
  /// The following example demonstrates inserting an array of components in the middle of a path.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/swift")!
  /// let secondPosition = url.pathComponents.index(after: url.pathComponents.startIndex)
  /// url.pathComponents.insert(contentsOf: ["local", "bin"], at: secondPosition)
  /// print(url)
  /// // ✅ "file:///usr/local/bin/swift"
  /// //                 ^^^^^^^^^
  /// ```
  ///
  /// The inserted components must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If any of the new components are `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// those components are ignored.
  ///
  /// If `position` is the path's `endIndex`, the new components are appended to the path.
  /// Calling ``append(contentsOf:)`` instead is preferred.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - newComponents: The components to insert into the path.
  ///   - position: The position at which to insert the components.
  /// - returns: The locations of the inserted components in the URL's path.
  ///
  @inlinable
  @discardableResult
  public mutating func insert<Components>(
    contentsOf newComponents: Components, at position: Index
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    replaceSubrange(position..<position, with: newComponents)
  }

  /// Adds multiple components to the end of the path.
  ///
  /// The following example demonstrates building a path by appending multiple path components at a time.
  /// Alternatively, using the `+=` operator is equivalent to calling this function.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents.append(contentsOf: ["private", "tmp"])
  /// print(url)
  /// // ✅ "file:///private/tmp"
  /// //             ^^^^^^^^^^^
  /// url.pathComponents += ["my_app", "data.json"]
  /// print(url)
  /// // ✅ "file:///private/tmp/my_app/data.json"
  /// //                         ^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The added components must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If any of the new components are `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// those components are ignored.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameter newComponents: The components to add to end of the path.
  /// - returns: The locations of the appended components in the URL's path.
  ///
  @inlinable
  @discardableResult
  public mutating func append<Components>(
    contentsOf newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    insert(contentsOf: newComponents, at: endIndex)
  }

  /// Adds multiple components to the end of the path.
  ///
  /// The following example demonstrates building a path by appending multiple path components at a time.
  /// This operator is equivalent to calling the ``append(contentsOf:)`` function.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents.append(contentsOf: ["private", "tmp"])
  /// print(url)
  /// // ✅ "file:///private/tmp"
  /// //             ^^^^^^^^^^^
  /// url.pathComponents += ["my_app", "data.json"]
  /// print(url)
  /// // ✅ "file:///private/tmp/my_app/data.json"
  /// //                         ^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// The added components must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If any of the new components are `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// those components are ignored.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - lhs: The URL's ``WebURL/pathComponents-swift.property`` view.
  ///   - rhs: The components to add to end of the path.
  ///
  @inlinable
  public static func += <Components>(
    lhs: inout WebURL.PathComponents, rhs: Components
  ) where Components: Collection, Components.Element: StringProtocol {
    lhs.append(contentsOf: rhs)
  }

  /// Removes the path components from a range of locations.
  ///
  /// The following example demonstrates removing multiple components from the middle of the path.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/projects/swift/swift-url/README.md")!
  /// let secondPosition = url.pathComponents.index(after: url.pathComponents.startIndex)
  /// let thirdPosition  = url.pathComponents.index(after: secondPosition)
  /// url.pathComponents.removeSubrange(secondPosition..<thirdPosition)
  /// print(url)
  /// // ✅ "http://example.com/projects/README.md"
  /// //                               ^
  /// ```
  ///
  /// Some URLs are forbidden from having empty paths; removing all path components from such URLs
  /// will result in a path with a single, empty component. This matches the behavior of setting
  /// the URL's ``WebURL/path`` property to the empty string.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameter bounds: The range of components to remove.
  /// - returns: The index of the component after those that were removed.
  ///
  @discardableResult
  public mutating func removeSubrange(_ bounds: Range<Index>) -> Index {
    storage.replacePathComponents(
      bounds, with: EmptyCollection<EmptyCollection<UInt8>>(), encodeSet: PathComponentEncodeSet()
    ).upperBound
  }

  /// Replaces the path component at a given location.
  ///
  /// The following example demonstrates replacing a single component in the middle of the path.
  /// To replace multiple components, use ``replaceSubrange(_:with:)``.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/bin/swift")!
  /// let secondPosition = url.pathComponents.index(after: url.pathComponents.startIndex)
  /// url.pathComponents.replaceComponent(at: secondPosition, with: "lib")
  /// print(url)
  /// // ✅ "file:///usr/lib/swift"
  /// //                 ^^^
  /// ```
  ///
  /// The inserted component must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If the new component is `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// the component at `position` is removed. This matches calling `replaceSubrange` with an empty collection.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - position: The position of the component to replace.
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

  /// Inserts a path component at a given location.
  ///
  /// The new component is inserted before the component currently at `position`.
  /// The following example demonstrates inserting a single component in the middle of a path.
  /// To insert multiple components, use ``insert(contentsOf:at:)``.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/swift")!
  /// let secondPosition = url.pathComponents.index(after: url.pathComponents.startIndex)
  /// url.pathComponents.insert("bin", at: secondPosition)
  /// print(url)
  /// // ✅ "file:///usr/bin/swift"
  /// //                 ^^^
  /// ```
  ///
  /// The inserted component must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If the new component is `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// it will be ignored.
  ///
  /// If `position` is the path's `endIndex`, the component is appended to the path.
  /// Calling ``append(_:)`` instead is preferred.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameters:
  ///   - newComponent: The component to insert into the path.
  ///   - position: The position at which to insert the component.
  /// - returns: A range of indexes which include the inserted component.
  ///            The range's `lowerBound` is the index of the inserted component,
  ///            and its `upperBound` is the new location of the component previously at `position`.
  ///
  @inlinable
  @discardableResult
  public mutating func insert<Component>(
    _ newComponent: Component, at position: Index
  ) -> Range<Index> where Component: StringProtocol {
    insert(contentsOf: CollectionOfOne(newComponent), at: position)
  }

  /// Adds a component to the end of the path.
  ///
  /// The following example demonstrates appending a single path component.
  /// To append multiple components, use ``append(contentsOf:)`` or the `+=` operator.
  ///
  /// ```swift
  /// var url = WebURL("file:///usr/bin")!
  /// url.pathComponents.append("swift")
  /// print(url)
  /// // ✅ "file:///usr/bin/swift"
  /// //                     ^^^^^
  /// ```
  ///
  /// The added component must **not** be percent-encoded, as this function will add its own percent-encoding.
  ///
  /// If the new component is `"."` or `".."` (or their percent-encoded versions, `"%2E"` or `"%2E%2E"`),
  /// it will be ignored and this function will return `endIndex`.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameter newComponents: The component to add to end of the path.
  /// - returns: The location of the new component in the path, or `endIndex` if the component was ignored.
  ///
  @inlinable
  @discardableResult
  public mutating func append<Component>(
    _ newComponent: Component
  ) -> Index where Component: StringProtocol {
    append(contentsOf: CollectionOfOne(newComponent)).lowerBound
  }

  /// Removes the path component at a given location.
  ///
  /// The following example demonstrates removing a single component from the middle of the path.
  /// To remove multiple components, use ``removeSubrange(_:)``.
  ///
  /// ```swift
  /// var url = WebURL("http://example.com/projects/swift/swift-url/")!
  /// let secondPosition = url.pathComponents.index(after: url.pathComponents.startIndex)
  /// url.pathComponents.remove(at: secondPosition)
  /// print(url)
  /// // ✅ "http://example.com/projects/swift-url/"
  /// //                               ^
  /// ```
  ///
  /// Some URLs are forbidden from having empty paths; removing all path components from such URLs
  /// will result in a path with a single, empty component. This matches the behavior of setting
  /// the URL's ``WebURL/path`` property to the empty string.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameter position: The position of the component to remove.
  /// - returns: The index of the component after the one that was removed.
  ///
  @discardableResult
  public mutating func remove(at position: Index) -> Index {
    precondition(position != endIndex, "Cannot remove component at endIndex")
    return removeSubrange(position..<index(after: position))
  }
}

extension WebURL.PathComponents {

  /// Removes a number of components from the end of the path.
  ///
  /// ```swift
  /// var url = WebURL("https://github.com/karwa/swift-url/pulls")!
  /// url.pathComponents.removeLast()
  /// print(url)
  /// // ✅ "https://github.com/karwa/swift-url"
  /// //                                      ^
  /// url.pathComponents.removeLast(2)
  /// print(url)
  /// // ✅ "https://github.com/"
  /// //                       ^
  /// ```
  ///
  /// Attempting to remove more components than exist in the path triggers a runtime error.
  ///
  /// Some URLs are forbidden from having empty paths; removing all path components from such URLs
  /// will result in a path with a single, empty component. This matches the behavior of setting
  /// the URL's ``WebURL/path`` property to the empty string.
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  /// - parameter k: The number of components to remove from the path.
  ///                Must not be negative, nor exceed the number of components that exist in the path.
  ///                The default is 1.
  ///
  public mutating func removeLast(_ k: Int = 1) {
    precondition(k >= 0, "Cannot remove a negative number of path components")
    removeSubrange(index(endIndex, offsetBy: -k, limitedBy: startIndex)!..<endIndex)
  }

  /// Adds a slash at the end of the path, if it does not already end with one.
  ///
  /// The following example demonstrates building a file path by appending multiple components,
  /// followed by `ensureDirectoryPath` to ensure the path ends with a trailing slash.
  /// This is equivalent to appending an empty path component.
  ///
  /// ```swift
  /// var url = WebURL("file:///")!
  /// url.pathComponents += ["Users", "karl", "Desktop"]
  /// // ✅ "file:///Users/karl/Desktop"
  /// url.pathComponents.ensureDirectoryPath()
  /// // ✅ "file:///Users/karl/Desktop/"
  /// //                               ^
  /// ```
  ///
  /// > Note:
  /// > This function invalidates any existing indexes for this URL.
  ///
  public mutating func ensureDirectoryPath() {
    append("")
  }
}


// --------------------------------------------
// MARK: - URLStorage + PathComponents
// --------------------------------------------


extension URLStorage {

  @inlinable
  internal var pathComponentsStartIndex: WebURL.PathComponents.Index {
    let pathStart = structure.rangeForReplacingCodeUnits(of: .path).lowerBound
    return WebURL.PathComponents.Index(codeUnitRange: pathStart..<pathStart + structure.firstPathComponentLength)
  }

  @inlinable
  internal var pathComponentsEndIndex: WebURL.PathComponents.Index {
    let pathEnd = structure.rangeForReplacingCodeUnits(of: .path).upperBound
    return WebURL.PathComponents.Index(codeUnitRange: pathEnd..<pathEnd)
  }

  /// Returns the code-unit offset at which the component ends whose `startIndex` is `componentStartOffset`.
  ///
  /// If `componentStartOffset` is the `upperBound` of the path range, the returned offset is `nil`.
  ///
  @inlinable
  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int? {
    let pathRange = structure.rangeForReplacingCodeUnits(of: .path).toCodeUnitsIndices()
    guard pathRange.contains(componentStartOffset) else { return nil }
    assert(codeUnits[componentStartOffset] == ASCII.forwardSlash.codePoint, "UTF8 position not aligned to a component")
    return codeUnits[componentStartOffset + 1..<pathRange.upperBound].fastFirstIndex(of: ASCII.forwardSlash.codePoint)
      ?? pathRange.upperBound
  }

  /// Returns the code-unit offset at which the component starts whose `endIndex` is `componentEndOffset`.
  ///
  /// - If `componentEndOffset` is the `upperBound` of the path string, the returned offset is
  ///   the start of the last path component (the last component's `endIndex` is the `upperBound` of the path string).
  ///
  /// - If `componentEndOffset` is the `lowerBound` of the path range, the returned offset is `nil`
  ///   (as there is no component whose `endIndex` is the `lowerBound` of the path range).
  ///
  @inlinable
  internal func startOfPathComponent(endingAt componentEndOffset: Int) -> Int? {
    let pathRange = structure.rangeForReplacingCodeUnits(of: .path).toCodeUnitsIndices()
    guard componentEndOffset > pathRange.lowerBound, componentEndOffset <= pathRange.upperBound else { return nil }
    assert(
      componentEndOffset == pathRange.upperBound || codeUnits[componentEndOffset] == ASCII.forwardSlash.codePoint,
      "UTF8 position not aligned to a path component"
    )
    return codeUnits[pathRange.lowerBound..<componentEndOffset].fastLastIndex(of: ASCII.forwardSlash.codePoint)
      ?? pathRange.lowerBound
  }
}

extension URLStorage {

  /// Removes all components from the path, to the extent that is allowed.
  /// URLs which cannot have an empty path will have their path set to "/".
  ///
  /// If this URL has an opaque path, a runtime error is triggered.
  ///
  @inlinable @inline(never)
  internal mutating func _clearPath() -> Range<WebURL.PathComponents.Index> {

    let oldPathRange = structure.rangeForReplacingCodeUnits(of: .path)
    precondition(!structure.hasOpaquePath, "Cannot replace components of an opaque path")

    // We can only set an empty path if this is a non-special scheme with authority ("foo://host?query").
    // Everything else (special, path-only) requires at least a lone "/".
    if !structure.schemeKind.isSpecial, structure.hasAuthority {
      var newStructure = structure
      newStructure.pathLength = 0
      newStructure.firstPathComponentLength = 0
      removeSubrange(oldPathRange, newStructure: newStructure)
    } else {
      withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
        var newStructure = structure
        if case .path = structure.sigil {
          commands += .remove(structure.rangeForReplacingSigil)
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
    let newPathStart = structure.pathStart
    let newPathEnd = structure.pathStart &+ structure.pathLength
    let newLowerBound = WebURL.PathComponents.Index(codeUnitRange: newPathStart..<newPathEnd)
    let newUpperBound = WebURL.PathComponents.Index(codeUnitRange: newPathEnd..<newPathEnd)
    return Range(uncheckedBounds: (newLowerBound, newUpperBound))
  }

  /// Replaces the path components in the given range with the given new components.
  /// Analogous to `replaceSubrange` from `RangeReplaceableCollection`.
  ///
  /// If this URL has an opaque path, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func replacePathComponents<Components, EncodeSet>(
    _ replacedIndices: Range<WebURL.PathComponents.Index>,
    with components: Components,
    encodeSet: EncodeSet
  ) -> Range<WebURL.PathComponents.Index>
  where
    Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8,
    EncodeSet: PercentEncodeSet
  {

    let oldPathRange = structure.rangeForReplacingCodeUnits(of: .path).toCodeUnitsIndices()
    precondition(!structure.hasOpaquePath, "Cannot replace components of an opaque path")

    // If 'firstGivenComponentLength' is nil, we infer that the components are empty (i.e. removal operation).
    let components = components.lazy.filter { utf8 in PathComponentParser.parseDotPathComponent(utf8) == nil }
    let firstGivenComponentLength = components.first.map { 1 + $0.lazy.percentEncoded(using: encodeSet).count }

    // If the URL's path ends with a trailing slash and we're inserting elements at the end,
    // widen the replacement range so we drop that trailing slash.
    // This means if the URL's path is "/" and we append "foo" to it, we get "/foo" rather than "//foo".
    var replacedIndices = replacedIndices
    if replacedIndices.lowerBound.range.lowerBound == oldPathRange.upperBound,
      firstGivenComponentLength != nil, _hasDirectoryPath
    {
      let newLowerBound = replacedIndices.lowerBound.range.lowerBound - 1..<replacedIndices.lowerBound.range.lowerBound
      replacedIndices = WebURL.PathComponents.Index(codeUnitRange: newLowerBound)..<replacedIndices.upperBound
    }

    let codeUnitsToReplace = replacedIndices.lowerBound.range.lowerBound..<replacedIndices.upperBound.range.lowerBound

    if codeUnitsToReplace == oldPathRange, firstGivenComponentLength == nil {
      return _clearPath()
    }
    // swift-format-ignore
    let insertedPathLength = firstGivenComponentLength.map { components.dropFirst().reduce(into: $0)
      { count, component in count += 1 + component.lazy.percentEncoded(using: encodeSet).count }
    } ?? 0

    // Calculate what the path will look like after the replacement. In particular, we need to know:
    //
    // - The length of the first component, and
    // - Whether the URL will require a path sigil.
    //
    // A path sigil is used to escape paths which start with "//", so they are not parsed as hostnames, but is
    // not technically part of the path. For example, the URL "foo:/.//foo" has no hostname, and its path is "//foo".
    // A URL requires a sigil if there is no authority, the path has >1 component, and the first component is empty.
    // Figuring this out before doing the actual code-unit replacement is tricky, but doable.
    let newFirstComponentLength: Int
    let newPathRequiresSigil: Bool
    if codeUnitsToReplace.lowerBound == oldPathRange.lowerBound {
      // Modifying the front of the path.
      if let firstGivenComponentLength = firstGivenComponentLength {
        // Inserting/replacing. The first component will be from the new components.
        let firstComponentWillBeEmpty = firstGivenComponentLength == 1
        let willHaveMoreThanOneComponent =
          codeUnitsToReplace.upperBound != oldPathRange.upperBound
          || insertedPathLength != firstGivenComponentLength
        newPathRequiresSigil = firstComponentWillBeEmpty && willHaveMoreThanOneComponent
        newFirstComponentLength = firstGivenComponentLength

      } else {
        // Removing. The first component will be at replacedIndices.upperBound.
        // We know the entire path is not being removed.
        let firstComponentWillBeEmpty = replacedIndices.upperBound.range.count == 1
        assert(codeUnitsToReplace.upperBound != oldPathRange.upperBound, "Full path removals are handled above")
        newPathRequiresSigil = firstComponentWillBeEmpty
        newFirstComponentLength = replacedIndices.upperBound.range.count
      }

    } else {
      // Modifying the middle/end of the path. The current first component will be maintained.
      let firstCmptRange = pathComponentsStartIndex.range
      let firstComponentWillBeEmpty = firstCmptRange.count == 1
      let willHaveMoreThanOneComponent: Bool
      if firstGivenComponentLength != nil {
        // Inserting/replacing. There will certainly be >1 component in the result.
        willHaveMoreThanOneComponent = true
      } else {
        // Removing. Unless every component after the first one is removed, there will be >1 components in the result.
        willHaveMoreThanOneComponent = (codeUnitsToReplace != firstCmptRange.upperBound..<oldPathRange.upperBound)
      }
      newPathRequiresSigil = firstComponentWillBeEmpty && willHaveMoreThanOneComponent
      newFirstComponentLength = firstCmptRange.count
    }

    // Calculate the new structure and replace the code-units.
    var pathOffsetFromSigilChange = 0

    withUnsafeSmallStack_2(of: ReplaceSubrangeOperation.self) { commands in
      var newStructure = structure
      switch (structure.sigil, newPathRequiresSigil) {
      case (.authority, _), (.none, false), (.path, true):
        break
      case (.none, true):
        commands += .replace(
          structure.rangeForReplacingSigil,
          withCount: Sigil.path.length,
          writer: Sigil.unsafeWrite(.path)
        )
        newStructure.sigil = .path
        pathOffsetFromSigilChange = 2
      case (.path, false):
        commands += .remove(structure.rangeForReplacingSigil)
        newStructure.sigil = .none
        pathOffsetFromSigilChange = -2
      }

      guard let newFirstComponentLength = URLStorage.SizeType(exactly: newFirstComponentLength),
        let insertedPathLength = URLStorage.SizeType(exactly: insertedPathLength)
      else {
        fatalError(URLSetterError.exceedsMaximumSize.description)
      }
      newStructure.firstPathComponentLength = newFirstComponentLength
      newStructure.pathLength -= URLStorage.SizeType(codeUnitsToReplace.count)
      newStructure.pathLength += insertedPathLength

      commands += .replace(
        codeUnitsToReplace.toURLStorageIndices(),
        withCount: insertedPathLength
      ) { buffer in
        var bytesWritten = 0
        for component in components {
          buffer[bytesWritten] = ASCII.forwardSlash.codePoint
          bytesWritten &+= 1
          bytesWritten &+=
            UnsafeMutableBufferPointer(rebasing: buffer[bytesWritten...])
            .fastInitialize(from: component.lazy.percentEncoded(using: encodeSet))
        }
        return bytesWritten
      }
      try! multiReplaceSubrange(commands, newStructure: newStructure).get()
    }

    // Post-replacement normalization of Windows drive letters.
    // This is necessary to preserve idempotence, but doesn't modify the URLStructure.
    if case .file = structure.schemeKind {
      _normalizeWindowsDriveLetterIfPresent()
    }

    // Calculate the updated path component indices to return.
    let lowerBoundStartPosition = codeUnitsToReplace.lowerBound + pathOffsetFromSigilChange
    let upperBoundStartPosition = lowerBoundStartPosition + insertedPathLength
    let lowerBoundEndPosition: Int
    let upperBoundEndPosition: Int
    if let firstComponentLenth = firstGivenComponentLength {
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
    utf8.path.last == ASCII.forwardSlash.codePoint
  }

  @inlinable
  internal mutating func _normalizeWindowsDriveLetterIfPresent() {
    guard case .file = structure.schemeKind, structure.firstPathComponentLength == 3 else { return }
    let firstComponent = utf8.path.dropFirst().prefix(2)
    if PathComponentParser.isWindowsDriveLetter(firstComponent) {
      codeUnits[firstComponent.startIndex + 1] = ASCII.colon.codePoint
    }
  }
}


// --------------------------------------------
// MARK: - PercentEncodeSets
// --------------------------------------------


/// An encode-set used for escaping the contents of individual path components. **Not defined by the URL standard.**
///
/// The URL 'path' encode-set, as defined in the standard, does not include slashes,
/// as the URL parser won't ever see them in a path component. This encode-set adds them,
/// ensuring inserted path components like "AC/DC" get encoded as "AC%2FDC".
///
/// This encode-set **does not** include the "%" character, so any sequences of "%XX" (where X is a hex character)
/// are interpreted as intentional percent-encoding and will not be percent-encoded again.
///
@usableFromInline
internal struct PreencodedPathComponentEncodeSet: PercentEncodeSet {

  @inlinable
  internal init() {}

  @inlinable
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    __shouldPercentEncode(URLEncodeSet.Path.self, ascii: codePoint)
      || codePoint == ASCII.forwardSlash.codePoint
      || codePoint == ASCII.backslash.codePoint
  }
}

/// An encode-set used for escaping the contents of individual path components. **Not defined by the URL standard.**
///
/// The URL 'path' encode-set, as defined in the standard, does not include slashes,
/// as the URL parser won't ever see them in a path component. This encode-set adds them,
/// ensuring inserted path components like "AC/DC" get encoded as "AC%2FDC".
///
/// This encode-set **includes** the "%" character, so any sequences of "%XX" (where X is a hex character)
/// are interpreted as coincidence and will be percent-encoded to "%25XX".
///
@usableFromInline
internal struct PathComponentEncodeSet: PercentEncodeSet {

  @inlinable
  internal init() {}

  @inlinable @inline(__always)
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    PreencodedPathComponentEncodeSet().shouldPercentEncode(ascii: codePoint)
      || codePoint == ASCII.percentSign.codePoint
  }
}
