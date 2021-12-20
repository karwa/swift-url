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

  /// A read-write view of the serialized URL's UTF-8 code-units.
  ///
  /// This view provides efficient access to the code-units of a serialized URL string,
  /// and enables a variety of optimizations for developers comfortable with low-level text processing.
  /// Through `UTF8View`, you can inspect, modify, and perform a variety of other operations on a URL,
  /// while avoiding allocations and Unicode processing inherent to APIs which accept and return data
  /// using Swift's `String` type.
  ///
  /// > Tip:
  /// > The contents of this collection are always ASCII code-points.
  ///
  /// ### Reading Components and Creating Slices
  ///
  /// The URL components provided by this view are slices, so they include positional information
  /// and can be used to create custom slices. For example, HTTP requests often include a "request target", which
  /// is composed of the URL's path and query concatenated. The following demonstrates how such a slice might be
  /// constructed:
  ///
  /// ```swift
  /// let url  = WebURL("https://example.com/foo?bar")!
  /// let path = url.utf8.path
  /// assert(!path.isEmpty, "The URL Standard ensures http(s) URLs never have empty paths")
  ///
  /// let requestTarget = url.utf8[
  ///   path.startIndex..<(url.utf8.query?.endIndex ?? path.endIndex)
  /// ]
  /// String(decoding: requestTarget, as: UTF8.self)
  /// // ✅ "/foo?bar"
  /// // Alternatively, 'requestTarget' could be written directly to the network.
  /// ```
  ///
  /// Another interesting use-case is percent-decoding a URL component. For example, the following demonstrates
  /// forming a percent-decoded `String` from a URL's fragment. By decoding the code-units directly rather than
  /// the result of WebURL's ``WebURL/fragment`` property, we are able to save a `String` allocation
  /// and UTF-8 validation.
  ///
  /// ```swift
  /// let url = WebURL(...)!
  /// url.fragment.percentDecoded()
  /// //  ^        ^ - 2 String allocations.
  /// url.utf8.fragment.percentDecodedString()
  /// //                ^ - 1 String allocation.
  /// ```
  ///
  /// Depending on what you wish to do with the URL component, it may even be beneficial to use lazy percent-decoding,
  /// and avoid all additional allocations. See <doc:PercentEncoding> for more information about the percent-decoding
  /// APIs offered by WebURL.
  ///
  /// ```swift
  /// let url = WebURL(...)!
  /// if url.utf8.fragment.lazy.percentDecoded().elementsEqual("title".utf8) {
  ///   // ...
  /// }
  /// ```
  ///
  /// ### Modifying Components and Resolving Relative References
  ///
  /// The `UTF8View` functions as a write-though wrapper, meaning that it can modify a URL's contents when accessed
  /// on a mutable value. It provides the same URL component setters as ``WebURL/WebURL``, but allows the new value
  /// to be provided using any generic `Collection` of UTF-8 encoded bytes.
  ///
  /// ```swift
  /// var url     = WebURL("https://example.com/foo/bar?baz")!
  /// let newPath = Data(...)
  ///
  /// try url.utf8.setPath(newPath)
  /// ```
  ///
  /// There is also the ability to resolve relative references specified as generic collections of bytes.
  /// One example of where this could be useful is in processing HTTP redirects, without requiring that
  /// a `String` be allocated simply to pass data from the received HTTP headers to WebURL.
  ///
  /// ```swift
  /// var requestURL      = WebURL(...)!
  /// let responseHeaders = ...
  ///
  /// let newURL: WebURL? = responseHeaders.withBytes(of: "Location") { bytes in
  ///   requestURL.utf8.resolve(bytes)
  /// }
  /// ```
  ///
  /// ## Topics
  ///
  /// ### Reading a URL's Components
  ///
  /// - ``WebURL/UTF8View/scheme``
  /// - ``WebURL/UTF8View/username``
  /// - ``WebURL/UTF8View/password``
  /// - ``WebURL/UTF8View/hostname``
  /// - ``WebURL/UTF8View/port``
  /// - ``WebURL/UTF8View/path``
  /// - ``WebURL/UTF8View/query``
  /// - ``WebURL/UTF8View/fragment``
  /// - ``WebURL/UTF8View/pathComponent(_:)``
  ///
  /// ### Replacing a URL's Components
  ///
  /// - ``WebURL/UTF8View/setScheme(_:)``
  /// - ``WebURL/UTF8View/setUsername(_:)``
  /// - ``WebURL/UTF8View/setPassword(_:)``
  /// - ``WebURL/UTF8View/setHostname(_:)``
  /// - ``WebURL/UTF8View/setPath(_:)``
  /// - ``WebURL/UTF8View/setQuery(_:)``
  /// - ``WebURL/UTF8View/setFragment(_:)``
  ///
  /// ### Resolving Relative References
  ///
  ///  - ``WebURL/UTF8View/resolve(_:)``
  ///
  /// ### Instance Methods
  ///
  /// - ``WebURL/WebURL/UTF8View/withUnsafeBufferPointer(_:)``
  ///
  /// ### View Type
  ///
  /// - ``WebURL/WebURL/UTF8View``
  ///
  @inlinable
  public var utf8: UTF8View {
    get { storage.utf8 }
    _modify { yield &storage.utf8 }
    set { storage.utf8 = newValue }
  }

  /// A read-write view of the UTF-8 code-units in a serialized URL.
  ///
  /// This view provides efficient access to the code-units of a serialized URL string,
  /// and enables a variety of optimizations for developers comfortable with low-level text processing.
  /// Through `UTF8View`, you can inspect, modify, and perform a variety of other operations on a URL,
  /// while avoiding allocations and Unicode processing inherent to APIs which accept and return data
  /// using Swift's `String` type.
  ///
  /// Access a URL's `UTF8View` through the ``WebURL/utf8`` property.
  ///
  /// ```swift
  /// let url  = WebURL("https://example.com/foo/bar")!
  /// let path = url.utf8.path
  /// String(decoding: path, as: UTF8.self)
  /// // ✅ "/foo/bar"
  /// ```
  ///
  /// > Tip:
  /// > The documentation for this type can be found at: ``WebURL/utf8``.
  ///
  public struct UTF8View {

    @usableFromInline
    internal var storage: URLStorage

    @inlinable
    internal init(_ storage: URLStorage) {
      self.storage = storage
    }
  }
}

extension URLStorage {

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
// MARK: - Standard Protocols
// --------------------------------------------


#if swift(>=5.5) && canImport(_Concurrency)
  extension WebURL.UTF8View: Sendable {}
#endif


// --------------------------------------------
// MARK: - RandomAccessCollection
// --------------------------------------------


extension WebURL.UTF8View: RandomAccessCollection {

  public typealias Index = Int
  public typealias Indices = Range<Index>
  public typealias Element = UInt8

  @inlinable
  public var startIndex: Index {
    0
  }

  @inlinable
  public var endIndex: Index {
    storage.codeUnits.count
  }

  @inlinable
  public var indices: Range<Index> {
    Range(uncheckedBounds: (startIndex, endIndex))
  }

  @inlinable
  public subscript(position: Index) -> Element {
    // bounds-checking is performed by `ManagedArrayBuffer`.
    storage.codeUnits[position]
  }

  @inlinable
  public subscript(bounds: Range<Index>) -> Slice<Self> {
    Slice(base: self, bounds: bounds)
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
  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    i &+ distance
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
  /// > Important:
  /// > The provided pointer is valid only for the duration of `body`.
  /// > Do not store or return the pointer for later use.
  ///
  /// > Complexity: O(*1*)
  ///
  /// - parameters:
  ///   - body: A closure which processes the content of the serialized URL.
  ///
  @inlinable @inline(__always)
  public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    try storage.codeUnits.withUnsafeBufferPointer(body)
  }
}

extension Slice where Base == WebURL.UTF8View {

  /// Invokes `body` with a pointer to the contiguous UTF-8 code-units of this portion of the serialized URL string.
  ///
  /// > Important:
  /// > The provided pointer is valid only for the duration of `body`.
  /// > Do not store or return the pointer for later use.
  ///
  /// > Complexity: O(*1*)
  ///
  /// - parameters:
  ///   - body: A closure which processes the content of the serialized URL.
  ///
  @inlinable @inline(__always)
  public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    try base.storage.codeUnits.withUnsafeBufferPointer(range: startIndex..<endIndex, body)
  }
}


// --------------------------------------------
// MARK: - Method variants for UTF8 code-units
// --------------------------------------------


extension WebURL.UTF8View {

  /// Resolves a relative reference from a collection of UTF-8 code-units, with this as the base URL.
  ///
  /// This function supports a wide range of relative URL strings, producing the same result as following
  /// an HTML `<a>` tag on this URL's "page". It has precisely the same behavior as WebURL's ``WebURL/resolve(_:)``
  /// function.
  ///
  /// The following example demonstrates how this can be used to resolve HTTP redirects using raw
  /// bytes from the response header.
  ///
  /// ```swift
  /// var requestURL      = WebURL(...)!
  /// let responseHeaders = ...
  ///
  /// let newURL: WebURL? = responseHeaders.withBytes(of: "Location") { bytes in
  ///   requestURL.utf8.resolve(bytes)
  /// }
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/resolve(_:)``
  ///
  @inlinable @inline(__always)
  public func resolve<UTF8Bytes>(
    _ utf8: UTF8Bytes
  ) -> WebURL? where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    urlFromBytes(utf8, baseURL: WebURL(storage: storage))
  }
}


// --------------------------------------------
// MARK: - Components
// --------------------------------------------


// Inlining:
// The setter implementations in URLStorage are all `@inlinable @inline(never)`, so they will be specialized
// but never inlined. The generic entrypoints here use `@inline(__always)`, so withContiguousStorageIfAvailable
// can be eliminated and call the correct specialization directly.


extension WebURL.UTF8View {

  /// A slice containing the scheme of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/scheme`` property.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/music/genres/electronic")!
  /// url.utf8.scheme.elementsEqual("https".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/scheme``
  ///
  public var scheme: SubSequence {
    guard let range = storage.structure.range(of: .scheme), range.count > 1 else {
      preconditionFailure("URL does not have a scheme, or scheme is empty")
    }
    return self[range.dropLast()]
  }

  /// Replaces this URL's scheme using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setScheme(_:)`` function.
  ///
  /// ```swift
  /// var url = WebURL("ftp://example.com/foo")!
  ///
  /// // This is just showing off; don't use integers for this.
  /// try withUnsafeBytes(of: UInt32(bigEndian: 0x68747470)) {
  ///   try url.utf8.setScheme($0)
  /// }
  /// // ✅ "http://example.com/foo"
  /// //     ^^^^
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setScheme(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setScheme<UTF8Bytes>(
    _ newScheme: UTF8Bytes
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    // swift-format-ignore
    let result = newScheme.withContiguousStorageIfAvailable {
      storage.setScheme(to: $0.boundsChecked)
    } ?? storage.setScheme(to: newScheme)
    try result.get()
  }

  /// A slice containing the username of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/username`` property.
  ///
  /// ```swift
  /// let url = WebURL("ftp://user@ftp.example.com/")!
  /// url.utf8.username?.elementsEqual("user".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/username``
  ///
  public var username: SubSequence? {
    storage.structure.range(of: .username).map { self[$0] }
  }

  /// Replaces this URL's `username` using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setUsername(_:)`` function.
  ///
  /// ```swift
  /// var url     = WebURL("ftp://example.com/foo")!
  /// let newUser = Data(...)
  /// try url.utf8.setUsername(newUser)
  /// // ✅ "ftp://jenny@example.com/foo"
  /// //           ^^^^^
  /// ```
  ///
  /// When setting this component, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setUsername(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setUsername<UTF8Bytes>(
    _ newUsername: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    guard let newValue = newUsername else {
      return try storage.setUsername(to: UnsafeBoundsCheckedBufferPointer?.none).get()
    }
    // swift-format-ignore
    let result = newValue.withContiguousStorageIfAvailable {
      storage.setUsername(to: $0.boundsChecked)
    } ?? storage.setUsername(to: newValue)
    try result.get()
  }

  /// A slice containing the password of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/password`` property.
  ///
  /// ```swift
  /// let url = WebURL("ftp://user:itsasecret@ftp.example.com/")!
  /// url.utf8.password?.elementsEqual("itsasecret".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/password``
  ///
  public var password: SubSequence? {
    guard let range = storage.structure.range(of: .password) else { return nil }
    assert(range.count > 1)
    return self[range.dropFirst()]
  }

  /// Replaces this URL's `password` using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setPassword(_:)`` function.
  ///
  /// ```swift
  /// var url     = WebURL("ftp://jenny@example.com/foo")!
  /// let newPass = Data(...)
  /// try url.utf8.setPassword(newPass)
  /// // ✅ "ftp://jenny:itsasecret@example.com/foo"
  /// //                 ^^^^^^^^^^
  /// ```
  ///
  /// When setting this component, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setPassword(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setPassword<UTF8Bytes>(
    _ newPassword: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    guard let newValue = newPassword else {
      return try storage.setPassword(to: UnsafeBoundsCheckedBufferPointer?.none).get()
    }
    // swift-format-ignore
    let result = newValue.withContiguousStorageIfAvailable {
      storage.setPassword(to: $0.boundsChecked)
    } ?? storage.setPassword(to: newValue)
    try result.get()
  }

  /// A slice containing the hostname of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/hostname`` property.
  ///
  /// ```swift
  /// let url = WebURL("http://example.com/foo?bar")!
  /// url.utf8.hostname?.elementsEqual("example.com".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/hostname``
  ///
  public var hostname: SubSequence? {
    storage.structure.range(of: .hostname).map { self[$0] }
  }

  /// Replaces this URL's `hostname` using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setHostname(_:)`` function.
  ///
  /// ```swift
  /// var url     = WebURL("http://github.com/karwa/swift-url")!
  /// let newHost = Data(...)
  /// try url.utf8.setHostname(newHost)
  /// // ✅ "http://example.com/karwa/swift-url"
  /// //            ^^^^^^^^^^^
  /// ```
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// otherwise it may be considered invalid. See ``WebURL/hostname`` for more information.
  ///
  /// > Note:
  /// > Depending on the URL's scheme, this function may reject invalid UTF-8.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setHostname(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setHostname<UTF8Bytes>(
    _ newHostname: UTF8Bytes?
  ) throws where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    guard let newValue = newHostname else {
      return try storage.setHostname(to: UnsafeBoundsCheckedBufferPointer?.none).get()
    }
    // swift-format-ignore
    let result = newValue.withContiguousStorageIfAvailable {
      storage.setHostname(to: $0.boundsChecked)
    } ?? storage.setHostname(to: newValue)
    try result.get()
  }

  /// A slice containing the textual representation of this URL's port number.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/port`` property,
  /// and contains an ASCII representation of the URL's port number.
  ///
  /// ```swift
  /// let url = WebURL("http://localhost:8000/my_site/foo")!
  /// url.utf8.port?.elementsEqual("8000".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/port``
  ///
  public var port: SubSequence? {
    guard let range = storage.structure.range(of: .port) else { return nil }
    assert(range.count > 1)
    return self[range.dropFirst()]
  }

  /// A slice containing the path of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/path`` property.
  ///
  /// ```swift
  /// let url = WebURL("https://github.com/karwa/swift-url")!
  /// url.utf8.path.elementsEqual("/karwa/swift-url".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/path``
  ///
  public var path: SubSequence {
    self[storage.structure.rangeForReplacingCodeUnits(of: .path)]
  }

  /// Replaces this URL's `path` using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setPath(_:)`` function.
  ///
  /// ```swift
  /// var url     = WebURL("http://github.com/karwa/swift-url")!
  /// let newPath = Data(...)
  /// try url.utf8.setPath(newPath)
  /// // ✅ "http://github.com/apple/swift"
  /// //                       ^^^^^^^^^^^
  /// ```
  ///
  /// When setting this property, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. Constructing a correctly-encoded path string
  /// is non-trivial; see ``WebURL/path`` for more information.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setPath(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setPath<UTF8Bytes>(
    _ newPath: UTF8Bytes
  ) throws where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    // swift-format-ignore
    let result = newPath.withContiguousStorageIfAvailable {
      storage.setPath(to: $0.boundsChecked)
    } ?? storage.setPath(to: newPath)
    try result.get()
  }

  /// A slice containing the query of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/query`` property.
  ///
  /// ```swift
  /// let url = WebURL("https://example.com/currency?v=20&from=USD&to=EUR")!
  /// url.utf8.query?.elementsEqual("v=20&from=USD&to=EUR".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/query``
  ///
  public var query: SubSequence? {
    guard let range = storage.structure.range(of: .query) else { return nil }
    assert(!range.isEmpty)
    return self[range.dropFirst()]
  }

  /// Replaces this URL's `query` using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setQuery(_:)`` function.
  ///
  /// ```swift
  /// var url      = WebURL("http://github.com/karwa/swift-url")!
  /// let newQuery = Data(...)
  /// try url.utf8.setQuery(newQuery)
  /// // ✅ "https://example.com/currency?v=20&from=USD&to=EUR"
  /// //                                  ^^^^^^^^^^^^^^^^^^^^
  /// ```
  ///
  /// When setting this component, the new value is expected to be percent-encoded or form-encoded,
  /// although additional percent-encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setQuery(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setQuery<UTF8Bytes>(
    _ newQuery: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    guard let newValue = newQuery else {
      return try storage.setQuery(to: UnsafeBoundsCheckedBufferPointer?.none).get()
    }
    // swift-format-ignore
    let result = newValue.withContiguousStorageIfAvailable {
      storage.setQuery(to: $0.boundsChecked)
    } ?? storage.setQuery(to: newValue)
    try result.get()
  }

  /// A slice containing the fragment of this URL.
  ///
  /// This slice covers precisely the same portion of the URL as WebURL's ``WebURL/fragment`` property.
  ///
  /// ```swift
  /// let url = WebURL("my.app:/docs/shopping_list#groceries")!
  /// url.utf8.fragment?.elementsEqual("groceries".utf8) // ✅ True
  /// ```
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/fragment``
  ///
  public var fragment: SubSequence? {
    guard let range = storage.structure.range(of: .fragment) else { return nil }
    assert(!range.isEmpty)
    return self[range.dropFirst()]
  }

  /// Replaces this URL's `fragment` using a collection of UTF-8 code-units.
  ///
  /// This function has precisely the same behavior as WebURL's ``WebURL/setFragment(_:)`` function.
  ///
  /// ```swift
  /// var url         = WebURL("my.app:/docs/shopping_list#groceries")!
  /// let newFragment = Data(...)
  /// try url.utf8.setFragment(newFragment)
  /// // ✅ "my.app:/docs/shopping_list#bathroom"
  /// //                                ^^^^^^^^
  /// ```
  ///
  /// When setting this component, the new value is expected to be percent-encoded,
  /// although additional encoding will be added if necessary. If the value derives from runtime data
  /// (for example, user input), you must at least encode the percent-sign in order to ensure the value
  /// is represented accurately in the URL. The ``PercentEncodeSet/urlComponentSet`` includes the percent-sign
  /// and is suitable for encoding arbitrary strings. See <doc:PercentEncoding> to learn more.
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/setFragment(_:)``
  ///
  @inlinable @inline(__always)
  public mutating func setFragment<UTF8Bytes>(
    _ newFragment: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    guard let newValue = newFragment else {
      return try storage.setFragment(to: UnsafeBoundsCheckedBufferPointer?.none).get()
    }
    // swift-format-ignore
    let result = newValue.withContiguousStorageIfAvailable {
      storage.setFragment(to: $0.boundsChecked)
    } ?? storage.setFragment(to: newValue)
    try result.get()
  }
}


// --------------------------------------------
// MARK: - Internal helpers
// --------------------------------------------


extension WebURL.UTF8View {

  /// Set the query component to the given UTF8-encoded string, assuming that the string is already `application/x-www-form-urlencoded`.
  ///
  internal mutating func setQuery<UTF8Bytes>(
    toKnownFormEncoded newQuery: UTF8Bytes?
  ) throws where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {
    guard let newValue = newQuery else {
      return try storage.setQuery(toKnownFormEncoded: UnsafeBoundsCheckedBufferPointer?.none).get()
    }
    // swift-format-ignore
    let result = newValue.withContiguousStorageIfAvailable {
      storage.setQuery(toKnownFormEncoded: $0.boundsChecked)
    } ?? storage.setQuery(toKnownFormEncoded: newValue)
    try result.get()
  }

  @inlinable @inline(__always)
  internal subscript(bounds: Range<URLStorage.SizeType>) -> Slice<WebURL.UTF8View> {
    self[bounds.toCodeUnitsIndices()]
  }
}
