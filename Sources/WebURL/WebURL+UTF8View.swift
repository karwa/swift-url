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

  /// A view of the UTF-8 code-units in a serialized URL.
  ///
  /// This view provides efficient random-access as well as read-write access to the code-units of a serialized URL string,
  /// including information about where each URL component is situated. The code-units are guaranteed to only contain ASCII code-points.
  ///
  /// Component properties (such as `scheme`, `path`, and `query`) and setter methods (such as `setQuery`), have the same semantics and
  /// behaviour as the corresponding methods on `WebURL`.
  ///
  public struct UTF8View {

    @usableFromInline
    internal var storage: AnyURLStorage

    @inlinable
    internal init(_ storage: AnyURLStorage) {
      self.storage = storage
    }
  }

  /// A mutable view of the UTF-8 code-units of this URL's serialization.
  ///
  @inlinable
  public var utf8: UTF8View {
    get { storage.utf8 }
    _modify { yield &storage.utf8 }
    set { storage.utf8 = newValue }
  }
}

extension AnyURLStorage {

  @inlinable
  internal var utf8: WebURL.UTF8View {
    get {
      WebURL.UTF8View(self)
    }
    _modify {
      var view = WebURL.UTF8View(self)
      self = _tempStorage
      defer { self = view.storage }
      yield &view
    }
    set {
      self = newValue.storage
    }
  }
}


// --------------------------------------------
// MARK: - RandomAccessCollection
// --------------------------------------------


extension WebURL.UTF8View: RandomAccessCollection {

  public typealias Index = Int
  public typealias Element = UInt8

  @inlinable
  public var startIndex: Index {
    0
  }

  @inlinable
  public var endIndex: Index {
    switch storage {
    case .small(let small): return small.codeUnits.count
    case .large(let large): return large.codeUnits.count
    }
  }

  @inlinable
  public subscript(position: Index) -> Element {
    // bounds-checking is performed by `ManagedArrayBuffer`.
    switch storage {
    case .small(let small): return small.codeUnits[position]
    case .large(let large): return large.codeUnits[position]
    }
  }

  @inlinable
  public func index(after i: Index) -> Index {
    i &+ 1
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    i &+= 1
  }

  @inlinable
  public func index(before i: Index) -> Index {
    i &- 1
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    i &-= 1
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Index) -> Index {
    i &+ distance
  }

  @inlinable
  public func formIndex(_ i: inout Index, offsetBy distance: Index) {
    i &+= distance
  }

  @inlinable
  public var count: Int {
    endIndex
  }

  @inlinable
  public func distance(from start: Index, to end: Index) -> Int {
    end &- start
  }

  @inlinable @inline(__always)
  public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R? {
    try withUnsafeBufferPointer(body)
  }

  /// Invokes `body` with a pointer to the contiguous UTF-8 code-units of the serialized URL string.
  ///
  /// - important: The provided pointer is valid only for the duration of `body`. Do not store or return the pointer for later use.
  /// - complexity: O(*1*)
  /// - parameters:
  ///   - body: A closure which processes the content of the serialized URL.
  ///
  @inlinable @inline(__always)
  public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    switch storage {
    case .small(let small): return try small.codeUnits.withUnsafeBufferPointer(body)
    case .large(let large): return try large.codeUnits.withUnsafeBufferPointer(body)
    }
  }
}

extension Slice where Base == WebURL.UTF8View {

  /// Invokes `body` with a pointer to the contiguous UTF-8 code-units of this portion of the serialized URL string.
  ///
  /// - important: The provided pointer is valid only for the duration of `body`. Do not store or return the pointer for later use.
  /// - complexity: O(*1*)
  /// - parameters:
  ///   - body: A closure which processes the content of the serialized URL.
  ///
  @inlinable @inline(__always)
  public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    switch base.storage {
    case .small(let small): return try small.codeUnits.withUnsafeBufferPointer(range: startIndex..<endIndex, body)
    case .large(let large): return try large.codeUnits.withUnsafeBufferPointer(range: startIndex..<endIndex, body)
    }
  }
}


// --------------------------------------------
// MARK: - Components
// --------------------------------------------


extension WebURL.UTF8View {

  /// The UTF-8 code-units containing this URL's `scheme`.
  ///
  /// - seealso: `WebURL.scheme`
  ///
  public var scheme: SubSequence {
    guard let range = storage.structure.range(of: .scheme), range.count > 1 else {
      preconditionFailure("URL does not have a scheme, or scheme is empty")
    }
    return self[range.dropLast()]
  }

  /// Replaces this URL's `scheme` with the given UTF-8 code-units.
  ///
  @inlinable
  public mutating func setScheme<UTF8Bytes>(
    _ newScheme: UTF8Bytes
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    try storage.withUnwrappedMutableStorage(
      { small in small.setScheme(to: newScheme) },
      { large in large.setScheme(to: newScheme) }
    )
  }

  /// The UTF-8 code-units containing this URL's `username`, if present.
  ///
  /// - seealso: `WebURL.username`
  ///
  public var username: SubSequence? {
    storage.structure.range(of: .username).map { self[$0] }
  }

  /// Replaces this URL's `username` with the given UTF-8 code-units.
  ///
  /// Any code-points which are not valid for use in the URL's user-info section will be percent-encoded.
  ///
  @inlinable
  public mutating func setUsername<UTF8Bytes>(
    _ newUsername: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    try storage.withUnwrappedMutableStorage(
      { small in small.setUsername(to: newUsername) },
      { large in large.setUsername(to: newUsername) }
    )
  }

  /// The UTF-8 code-units containing this URL's `password`, if present.
  ///
  /// - seealso: `WebURL.password`
  ///
  public var password: SubSequence? {
    guard let range = storage.structure.range(of: .password) else { return nil }
    assert(range.count > 1)
    return self[range.dropFirst()]
  }

  /// Replaces this URL's `password` with the given UTF-8 code-units.
  ///
  /// Any code-points which are not valid for use in the URL's user-info section will be percent-encoded.
  ///
  @inlinable
  public mutating func setPassword<UTF8Bytes>(
    _ newPassword: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    try storage.withUnwrappedMutableStorage(
      { small in small.setPassword(to: newPassword) },
      { large in large.setPassword(to: newPassword) }
    )
  }

  /// The UTF-8 code-units containing this URL's `hostname`, if present.
  ///
  /// - seealso: `WebURL.hostname`
  ///
  public var hostname: SubSequence? {
    storage.structure.range(of: .hostname).map { self[$0] }
  }

  /// Replaces this URL's `hostname` with the given UTF-8 code-units.
  ///
  /// Unlike other setters, not all code-points which are invalid for use in hostnames will be percent-encoded.
  /// If the new content contains a [forbidden host code-point][URL-fhcp], the operation will fail.
  ///
  /// [URL-fhcp]: https://url.spec.whatwg.org/#forbidden-host-code-point
  ///
  @inlinable
  public mutating func setHostname<UTF8Bytes>(
    _ newHostname: UTF8Bytes?
  ) throws where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    try storage.withUnwrappedMutableStorage(
      { small in small.setHostname(to: newHostname) },
      { large in large.setHostname(to: newHostname) }
    )
  }

  /// The UTF-8 code-units containing this URL's `port`, if present.
  ///
  /// - seealso: `WebURL.port`
  ///
  public var port: SubSequence? {
    guard let range = storage.structure.range(of: .port) else { return nil }
    assert(range.count > 1)
    return self[range.dropFirst()]
  }

  /// The UTF-8 code-units containing this URL's `path`.
  ///
  /// - seealso: `WebURL.path`
  ///
  public var path: SubSequence {
    self[storage.structure.rangeForReplacingCodeUnits(of: .path)]
  }

  /// Replaces this URL's `path` with the given UTF-8 code-units.
  ///
  /// The given path string will be lexically simplified, and any code-points in the path's components that are not valid for use will be percent-encoded.
  ///
  @inlinable
  public mutating func setPath<UTF8Bytes>(
    _ newPath: UTF8Bytes
  ) throws where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    try storage.withUnwrappedMutableStorage(
      { small in small.setPath(to: newPath) },
      { large in large.setPath(to: newPath) }
    )
  }

  /// The UTF-8 code-units containing this URL's `query`, if present.
  ///
  /// - seealso: `WebURL.query`
  ///
  public var query: SubSequence? {
    guard let range = storage.structure.range(of: .query) else { return nil }
    assert(!range.isEmpty)
    return self[range.dropFirst()]
  }

  /// Replaces this URL's `query` with the given UTF-8 code-units.
  ///
  /// Any code-points which are not valid for use in the URL's query will be percent-encoded.
  /// Note that the set of code-points which are valid depends on the URL's `scheme`.
  ///
  @inlinable
  public mutating func setQuery<UTF8Bytes>(
    _ newQuery: UTF8Bytes?
  ) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    storage.withUnwrappedMutableStorage(
      { small in small.setQuery(to: newQuery) },
      { large in large.setQuery(to: newQuery) }
    )
  }

  /// The UTF-8 code-units containing this URL's `fragment`, if present.
  ///
  /// - seealso: `WebURL.fragment`
  ///
  public var fragment: SubSequence? {
    guard let range = storage.structure.range(of: .fragment) else { return nil }
    assert(!range.isEmpty)
    return self[range.dropFirst()]
  }

  /// Replaces this URL's `fragment` with the given UTF-8 code-units.
  ///
  /// Any code-points which are not valid for use in the URL's fragment will be percent-encoded.
  ///
  @inlinable
  public mutating func setFragment<UTF8Bytes>(
    _ newFragment: UTF8Bytes?
  ) where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    storage.withUnwrappedMutableStorage(
      { small in small.setFragment(to: newFragment) },
      { large in large.setFragment(to: newFragment) }
    )
  }
}
