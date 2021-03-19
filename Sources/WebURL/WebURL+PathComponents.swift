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

/// The position of a path component within a URL string.
///
public struct PathComponentIndex: Equatable, Comparable {

  /// The range of the component in the overall URL string's code-units.
  /// Note that this includes the leading "/", so paths which end in a "/" include a trailing empty component before reaching endIndex.
  internal var range: Range<Int>

  internal init(codeUnitRange: Range<Int>) {
    self.range = codeUnitRange
  }

  public static func < (lhs: PathComponentIndex, rhs: PathComponentIndex) -> Bool {
    lhs.range.lowerBound < rhs.range.lowerBound
  }
}


// --------------------------------------------
// MARK: - PathComponents
// --------------------------------------------


extension WebURL {

  /// This URL's path components, if it has a hierarchical path.
  ///
  /// This collection gives you efficient, bidirectional access to the URL's path components:
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/swift/packages/swift-url")!
  /// for component in url.pathComponents! {
  ///  print(component) // Prints "swift", "packages", "swift-url"
  /// }
  /// print(url.pathComponents!.first!) // Prints "swift"
  /// print(url.pathComponents!.last!) // Prints "swift-url"
  /// ```
  ///
  /// Components are retrieved in their percent-decoded form. Paths which end in a "/" are considered to end with an empty component:
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
  /// Almost all URLs have hierarchical paths. The ones which _don't_ are known as "cannot-be-a-base" URLs - and they can be recognized by the lack of slashes
  /// immediately following their scheme. Examples of such URLs are:
  ///
  /// - `mailto:bob@example.com`
  /// - `javascript:alert("hello");`
  /// - `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`
  ///
  /// These URLs tend to be rare, and if you do not expect to deal with them, it is reasonable to force-unwrap this property.
  /// URLs with _special_ schemes, such as http(s) and file URLs, always have a hostname and non-empty, hierarchical path.
  ///
  public var pathComponents: PathComponents? {
    guard self._cannotBeABaseURL == false else { return nil }
    return PathComponents(_url: self, startIndex: self.storage.pathComponentsStartIndex)
  }

  /// A read-only view of the components in a URL's path.
  ///
  public struct PathComponents: _PathComponentCollection {

    public let _url: WebURL
    public let startIndex: PathComponentIndex

    public typealias Index = PathComponentIndex
    public typealias Element = String
  }
}

/// This is an internal `WebURL` implementation detail. ** Do not conform to this protocol. **
///
public protocol _PathComponentCollection: BidirectionalCollection where Index == PathComponentIndex, Element == String {
  var _url: WebURL { get }
}

extension _PathComponentCollection {

  public var endIndex: PathComponentIndex {
    _url.storage.pathComponentsEndIndex
  }

  public subscript(position: PathComponentIndex) -> String {
    withUTF8(component: position) { $0.urlDecodedString }
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
    // Collection does not require us to trap on incrementing endIndex; this just keeps returning endIndex.
    i.range = Range(
      uncheckedBounds: (i.range.upperBound, _url.storage.endOfPathComponent(startingAt: i.range.upperBound))
    )
  }

  public func formIndex(before i: inout Index) {
    // Collection does not require us to trap on decrementing startIndex; this just keeps returning startIndex.
    guard let newStart = _url.storage.startOfPathComponent(endingAt: i.range.lowerBound) else { return }
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

extension _PathComponentCollection {

  /// Invokes `body` with a pointer to the UTF8 content of the requested component. The component is not percent-decoded from its form in the URL string.
  ///
  /// - important: The provided pointer is valid only for the duration of `body`. Do not store or return the pointer for later use.
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


// --------------------------------------------
// MARK: - UnsafeMutablePathComponents
// --------------------------------------------


extension WebURL {

  /// Calls the given closure with a view through which it may read and modify the URL's path components.
  ///
  /// The following example shows how modifying the contents of the `UnsafeMutablePathComponents` argument to `body` alters the contents of
  /// the URL:
  ///
  ///     var url = WebURL("http://example.com/foo/bar")!
  ///     url.withMutablePathComponents { path in
  ///       if path.last == "bar" {
  ///         path.appendComponent("cheese")
  ///       }
  ///     }
  ///     print(url)
  ///     // Prints "http://example.com/foo/bar/cheese"
  ///
  /// The view passed as an argument to `body` is valid only during the execution of `withMutablePathComponents(_:)`.
  /// Do not store or return the view for later use.
  ///
  public mutating func withMutablePathComponents<Result>(
    _ body: (inout UnsafeMutablePathComponents) throws -> Result
  ) rethrows -> Result {

    precondition(_cannotBeABaseURL == false, "Cannot view or edit path components on a cannot-be-a-base URL")

    return try withUnsafeMutablePointer(to: &self) {
      var pathEditor = UnsafeMutablePathComponents(pointer: $0)
      return try body(&pathEditor)
    }
  }

  /// A view which allows both reading and writing a URL's path components.
  ///
  /// Instances of `UnsafeMutablePathComponents` are valid only during the execution of `WebURL.withMutablePathComponents(_:)`.
  /// Do not store or return the instance for later use.
  ///
  public struct UnsafeMutablePathComponents: _PathComponentCollection {

    private let pointer: UnsafeMutablePointer<WebURL>
    public private(set) var startIndex: Index

    public typealias Index = PathComponentIndex
    public typealias Element = String

    internal init(pointer: UnsafeMutablePointer<WebURL>) {
      self.pointer = pointer
      self.startIndex = pointer.pointee.storage.pathComponentsStartIndex
    }

    public var _url: WebURL {
      pointer.pointee
    }
  }
}

extension WebURL.UnsafeMutablePathComponents {

  private mutating func withMutableURL<Result>(
    _ body: (_ urlPtr: UnsafeMutablePointer<WebURL>, _ startIndex: inout PathComponentIndex) -> Result
  ) -> Result {
    body(pointer, &startIndex)
  }

  /// Replaces the specified subrange of path components with the contents of the given collection.
  ///
  /// This method has the effect of removing the specified range of components from the path and inserting the new components at the same location.
  /// The number of new components need not match the number of elements being removed, and will be percent-encoded, if necessary, upon insertion.
  ///
  /// The following example shows replacing the last 2 components of a `file:` URL with an array of strings.
  ///
  /// ```
  /// var url = WebURL("file:///usr/bin/swift")!
  /// url.withMutablePathComponents { path in
  ///     path.replaceComponents(path.index(after: path.startIndex)..<path.endIndex, with: [
  ///       "lib",
  ///       "swift-6.0",
  ///       "linux",
  ///       "libswiftCore.so"
  ///     ])
  /// }
  /// print(url) // Prints "file:///usr/lib/swift-6.0/linux/libswiftCore.so"
  /// ```
  ///
  /// If you pass a zero-length range as the `range` parameter, this method inserts the elements of `newComponents` at `range.lowerBound`.
  /// Calling the `insert(contentsOf:at:)` method instead is preferred.
  ///
  /// Likewise, if you pass a zero-length collection as the `newComponents` parameter, this method removes the components in the given subrange
  /// without replacement. Calling the `removeSubrange(_:)` method instead is preferred. Some URLs may not have empty paths; attempting to remove
  /// all components from such a URL will instead set its path to the root path ("/").
  ///
  /// If any of the new components are "." or ".." (or their percent-encoded versions, "%2E" or "%2E%2E", case insensitive), those components are skipped.
  /// Otherwise, the contents of the new components are percent-encoded as they are written to the URL's path.
  ///
  /// Calling this method invalidates any existing indices for use with this `UnsafeMutablePathComponents`. The method returns a new range of indices
  /// which correspond to the locations of the replaced components in the modified path.
  ///
  /// - Parameters:
  ///   - range: The range of the path to replace. The bounds of the range must be valid path-component indices.
  ///   - newComponents: The new components to add to the path.
  ///
  @discardableResult
  public mutating func replaceComponents<Components>(
    _ range: Range<Index>, with newComponents: Components
  ) -> Range<Index> where Components: Collection, Components.Element: StringProtocol {
    return replaceComponents(range, withUTF8: newComponents.lazy.map { $0.utf8 })
  }

  internal mutating func replaceComponents<Components>(
    _ range: Range<Index>, withUTF8 newComponents: Components
  ) -> Range<Index>
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    return withMutableURL { ptr, newStart in
      var newSubrange: Range<PathComponentIndex>?
      ptr.pointee.withMutableStorage(
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
      newStart = ptr.pointee.storage.pathComponentsStartIndex
      return newSubrange!
    }
  }
}


// --------------------------------------------
// MARK: - URLStorage + PathComponents
// --------------------------------------------


extension AnyURLStorage {

  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int {
    switch self {
    case .small(let small): return small.endOfPathComponent(startingAt: componentStartOffset)
    case .generic(let generic): return generic.endOfPathComponent(startingAt: componentStartOffset)
    }
  }

  internal func startOfPathComponent(endingAt componentEndOffset: Int) -> Int? {
    switch self {
    case .small(let small): return small.startOfPathComponent(endingAt: componentEndOffset)
    case .generic(let generic): return generic.startOfPathComponent(endingAt: componentEndOffset)
    }
  }

  internal var pathComponentsStartIndex: PathComponentIndex {
    switch self {
    case .small(let small): return small.pathComponentsStartIndex
    case .generic(let generic): return generic.pathComponentsStartIndex
    }
  }

  internal var pathComponentsEndIndex: PathComponentIndex {
    switch self {
    case .small(let small): return small.pathComponentsEndIndex
    case .generic(let generic): return generic.pathComponentsEndIndex
    }
  }
}

extension URLStorage {

  internal var pathComponentsStartIndex: PathComponentIndex {
    let pathStart = header.structure.rangeForReplacingCodeUnits(of: .path).lowerBound
    return PathComponentIndex(codeUnitRange: pathStart..<endOfPathComponent(startingAt: pathStart))
  }

  internal var pathComponentsEndIndex: PathComponentIndex {
    let pathEnd = header.structure.rangeForReplacingCodeUnits(of: .path).upperBound
    return PathComponentIndex(codeUnitRange: pathEnd..<pathEnd)
  }

  internal func endOfPathComponent(startingAt componentStartOffset: Int) -> Int {
    withEntireString { utf8 in
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
    withEntireString { utf8 in
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
    _ replacedIndices: Range<PathComponentIndex>,
    with components: Components
  ) -> (AnyURLStorage, firstComponentOrError: Either<Range<PathComponentIndex>, URLSetterError>)
  where Components: Collection, Components.Element: Collection, Components.Element.Element == UInt8 {

    let oldStructure = header.structure

    if oldStructure.cannotBeABaseURL {
      return (AnyURLStorage(self), .right(.error(.cannotSetPathOnCannotBeABaseURL)))
    }

    let components = components.lazy.filter { utf8 in
      !PathComponentParser.isSingleDotPathSegment(utf8) && !PathComponentParser.isDoubleDotPathSegment(utf8)
    }
    // This value being nil is taken as meaning the components are empty.
    let firstNewComponentLength = components.first.map {
      1 + $0.lazy.percentEncoded(using: URLEncodeSet.Path.self).joined().count
    }

    let oldPathRange = oldStructure.rangeForReplacingCodeUnits(of: .path)
    let replacedRange = replacedIndices.lowerBound.range.lowerBound..<replacedIndices.upperBound.range.lowerBound

    if replacedRange == oldPathRange {
      guard firstNewComponentLength != nil else {
        // We can only set an empty path if this is a non-special scheme with authority ("foo://host?query").
        // Everything else (special, path-only) requires at least a lone "/".
        let replaced: AnyURLStorage
        if !oldStructure.schemeKind.isSpecial, oldStructure.hasAuthority {
          var newStructure = oldStructure
          newStructure.pathLength = 0
          replaced = removeSubrange(oldPathRange, newStructure: newStructure).newStorage
        } else {
          var commands = [ReplaceSubrangeOperation]()
          var newStructure = oldStructure
          if case .path = oldStructure.sigil {
            commands.append(.remove(subrange: oldStructure.rangeForReplacingSigil))
            newStructure.sigil = .none
          }
          newStructure.pathLength = 1
          commands.append(
            .replace(
              subrange: oldPathRange, withCount: 1,
              writer: { buffer in
                buffer.baseAddress.unsafelyUnwrapped.initialize(to: ASCII.forwardSlash.codePoint)
                return 1
              })
          )
          replaced = multiReplaceSubrange(commands: commands, newStructure: newStructure)
        }
        let newPathStart = replaced.structure.pathStart
        let newPathEnd = replaced.structure.pathStart &+ replaced.structure.pathLength
        let newLowerBound = PathComponentIndex(codeUnitRange: newPathStart..<newPathEnd)
        let newUpperBound = PathComponentIndex(codeUnitRange: newPathEnd..<newPathEnd)
        return (replaced, .left(Range(uncheckedBounds: (newLowerBound, newUpperBound))))
      }
    }

    var newStructure = oldStructure
    var commands = [ReplaceSubrangeOperation]()
    var pathStartOffset = 0

    let insertedPathLength = components.dropFirst().reduce(into: firstNewComponentLength ?? 0) { counter, component in
      counter += 1 + component.lazy.percentEncoded(using: URLEncodeSet.Path.self).joined().count
    }

    // Find out if the new path requires adding/removing a path sigil.
    // We need a sigil if there is no authority, the path has >1 component, and the first component is empty.
    if oldStructure.hasAuthority == false {
      if replacedRange.lowerBound == oldPathRange.lowerBound {
        if let firstInsertedComponentLength = firstNewComponentLength {
          // Inserting at the front of the path. The first component is from the new components.
          let firstComponentEmpty = (firstInsertedComponentLength == 1)
          let hasCmptsAfter =
            (replacedRange.upperBound != oldPathRange.upperBound)
            || (insertedPathLength != firstInsertedComponentLength)
          newStructure.sigil = firstComponentEmpty && hasCmptsAfter ? .path : .none
        } else {
          // Removing at the front of the path. The first component (if any) is at the end of the range.
          let firstComponentEmpty = (replacedIndices.upperBound.range.count == 1)
          let hasCmptsAfter = (replacedIndices.upperBound.range.upperBound != oldPathRange.upperBound)
          newStructure.sigil = firstComponentEmpty && hasCmptsAfter ? .path : .none
        }
      } else {
        let oldStartIndex = pathComponentsStartIndex
        let firstComponentEmpty = (oldStartIndex.range.count == 1)
        let hasCmptsAfter: Bool
        if firstNewComponentLength != nil {
          // Inserting after the first component means there will certainly be >1 component.
          hasCmptsAfter = true
        } else {
          // When removing, unless removing everything after the first component, there will be >1 component.
          hasCmptsAfter =
            (replacedRange.lowerBound != oldStartIndex.range.upperBound)
            || (replacedRange.upperBound != oldPathRange.upperBound)
        }
        newStructure.sigil = firstComponentEmpty && hasCmptsAfter ? .path : .none
      }
      switch (oldStructure.sigil, newStructure.sigil) {
      case (.authority, _), (_, .authority):
        fatalError()
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
      }
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
              .initialize(from: component.lazy.percentEncoded(using: URLEncodeSet.Path.self).joined()).1
          }
          return bytesWritten
        })
    )

    let replaced = multiReplaceSubrange(commands: commands, newStructure: newStructure)

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
    let newLowerBound = PathComponentIndex(codeUnitRange: lowerBoundStartPosition..<lowerBoundEndPosition)
    let newUpperBound = PathComponentIndex(codeUnitRange: upperBoundStartPosition..<upperBoundEndPosition)
    return (replaced, .left(Range(uncheckedBounds: (newLowerBound, newUpperBound))))
  }
}
