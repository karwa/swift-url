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

/// A Uniform Resource Locator (URL) is a universal identifier, which often describes the location of a resource.
///
/// - A URL’s `scheme` is an ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing after parsing.
///   For example, software that speaks the HTTP protocol will know how to process requests involving URLs with the "http" scheme.
///   A scheme is always required, and determines the way in which other components are encoded in the URL.
///   Some schemes ("http", "https", "ws", "wss", "ftp", and "file") are referred to as being "special"; their components may be encoded differently,
///   or gain additional semantic meaning.
///   Scheme usage is coordinated by the [Internet Assigned Numbers Authority][iana-schemes].
///
/// - The `hostname` is an optional component which can be a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
///   Typically a host serves as a network address, but it is sometimes used as opaque identifier in URLs where a network address is not necessary.
///   Domains may be resolved to IP addresses using the [Domain Name System (DNS)][dns] .
///
/// - Additionally, the hostname may be augmented by a `username`, `password` or `port`. Collectively, these are known as the URL's "authority".
///
/// - The `path` is a list of zero or more ASCII strings, usually identifying a location in hierarchical form.
///   Hierarchical paths will be lexically simplified according to the `scheme`.
///
/// - The `query` is an optional, ordered sequence of key-value pairs.
///
/// - The `fragment` is an optional string which may be used for further processing on the resource identified by the other components.
///   It is typically used for client-side information and not sent to the host, although this is a scheme- and implementation-specific detail.
///
/// Additionally, URLs without a host and with a non-hierarchical path are said to be "cannot be a base" URLs.
/// (e.g. `mailto:somebody@example.com`, or `javascript:alert("hello")`). Joining a relative URL string to such a URL will always fail,
/// unless that string consists only of a fragment (e.g. "#my-fragment").
///
/// URLs are always ASCII Strings. Non-ASCII characters must be percent-encoded, except in domains, where they are encoded as ASCII by
/// the [IDNA transformation][idna-spec] .
///
/// Parsing of URL strings is compatible with the [WHATWG URL Specification][url-spec].
/// The model exposed here differs slightly from the Javascript model described in the standard, which is available via the `.jsModel` view.
///
/// [iana-schemes]: https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
/// [dns]: https://en.wikipedia.org/wiki/Domain_Name_System
/// [idna-spec]: https://unicode.org/reports/tr46/
/// [url-spec]: https://url.spec.whatwg.org/
///
public struct WebURL {
  internal var storage: AnyURLStorage

  internal init(storage: AnyURLStorage) {
    self.storage = storage
  }

  /// Attempts to create a URL by parsing the given absolute URL string.
  ///
  /// The created URL is normalized in a number of ways - for instance, whitespace characters may be stripped, other characters may be percent-encoded,
  /// hostnames may be IDNA-encoded, or rewritten in a canonical notation if they are IP addresses, paths may be lexically simplified, etc. This means that the
  /// serialized result may look different to the original contents. These transformations are defined in the URL specification.
  ///
  @inlinable @inline(__always)
  public init?<S>(_ string: S) where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    self.init(utf8: string.utf8)
  }

  @inlinable @inline(__always)
  init?<C>(utf8 bytes: C) where C: BidirectionalCollection, C.Element == UInt8 {
    guard let url = urlFromBytes(bytes, baseURL: nil) else {
      return nil
    }
    self = url
  }

  /// Attempts to create a URL by parsing the given absolute or relative URL string with this URL as its base.
  ///
  /// The created URL is normalized in a number of ways - for instance, whitespace characters may be stripped, other characters may be percent-encoded,
  /// hostnames may be IDNA-encoded, or rewritten in a canonical notation if they are IP addresses, paths may be lexically simplified, etc. This means that the
  /// serialized result may look different to the original contents. These transformations are defined in the URL specification.
  ///
  @inlinable @inline(__always)
  public func join<S>(_ string: S) -> WebURL? where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    return join(utf8: string.utf8)
  }

  @inlinable @inline(__always)
  func join<C>(utf8 bytes: C) -> WebURL? where C: BidirectionalCollection, C.Element == UInt8 {
    guard let url = urlFromBytes(bytes, baseURL: self) else {
      return nil
    }
    return url
  }
}

extension WebURL {

  // Flags used by the parser.

  internal var _schemeKind: WebURL.SchemeKind {
    storage.schemeKind
  }

  internal var _cannotBeABaseURL: Bool {
    storage.cannotBeABaseURL
  }
}


// MARK: - Standard protocols.


extension WebURL: Equatable, Hashable, Comparable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage.withEntireString { lhsBuffer in
      rhs.storage.withEntireString { rhsBuffer in
        (lhsBuffer.baseAddress == rhsBuffer.baseAddress && lhsBuffer.count == rhsBuffer.count)
          || lhsBuffer.elementsEqual(rhsBuffer)
      }
    }
  }

  public func hash(into hasher: inout Hasher) {
    storage.withEntireString { buffer in
      hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.storage.withEntireString { lhsBuffer in
      rhs.storage.withEntireString { rhsBuffer in
        return lhsBuffer.lexicographicallyPrecedes(rhsBuffer)
      }
    }
  }
}

extension WebURL: CustomStringConvertible, LosslessStringConvertible {

  public var description: String {
    serialized
  }
}

extension WebURL: Codable {

  public init(from decoder: Decoder) throws {
    let box = try decoder.singleValueContainer()
    guard let decoded = WebURL(try box.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: box, debugDescription: "Invalid URL")
    }
    self = decoded
  }

  public func encode(to encoder: Encoder) throws {
    var box = encoder.singleValueContainer()
    try box.encode(serialized)
  }
}


// MARK: - Properties.


extension WebURL {

  /// The string representation of this URL.
  ///
  public var serialized: String {
    storage.entireString
  }

  /// The scheme of this URL, for example `https` or `file`.
  ///
  /// A URL’s `scheme` is an ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing after parsing.
  /// All URLs have a scheme, which is never the empty string.
  /// Setting this property may fail if the URL does not support the new value.
  ///
  public var scheme: String {
    get {
      storage.withComponentBytes(.scheme) { maybeBytes in
        guard let bytes = maybeBytes, bytes.count > 1 else { preconditionFailure("Invalid scheme") }
        return String(decoding: bytes.dropLast(), as: UTF8.self)
      }
    }
    set {
      try? setScheme(to: newValue)
    }
  }

  /// The username of this URL, if present, as a percent-encoded string.
  ///
  /// If present, the username is never the empty sring.
  /// When setting this property, disallowed characters will be percent-encoded.
  /// However, the operation may still fail if the URL does not support the new value for other reasons.
  ///
  public var username: String? {
    get { storage.stringForComponent(.username) }
    set { try? setUsername(to: newValue) }
  }

  /// The password of this URL, if present, as a percent-encoded string.
  ///
  /// If present, the password is never the empty sring.
  /// When setting this property, disallowed characters will be percent-encoded.
  /// However, the operation may still fail if the URL does not support the new value for other reasons.
  ///
  public var password: String? {
    get {
      storage.withComponentBytes(.password) { maybeBytes in
        guard let bytes = maybeBytes, bytes.count > 1 else { return nil }
        return String(decoding: bytes.dropFirst(), as: UTF8.self)
      }
    }
    set {
      try? setPassword(to: newValue)
    }
  }

  /// The string representation of this URL's host, if present.
  ///
  /// A URL's host may be a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
  /// Typically a host serves as a network address, but it is sometimes used as opaque identifier in URLs where a network address is not necessary.
  /// When setting this property, disallowed characters will **not** be percent-encoded, and will cause the operation to fail.
  ///
  public var hostname: String? {
    get { storage.stringForComponent(.hostname) }
    set { try? setHostname(to: newValue) }
  }

  /// The port of this URL, if present. Valid port numbers are in the range `0 ..< 65536`.
  ///
  /// Setting this property may fail if the URL does not support the new value.
  ///
  public var port: Int? {
    get {
      storage.withComponentBytes(.port) { maybeBytes in
        guard let bytes = maybeBytes, bytes.count > 1 else { return nil }
        return Int(String(decoding: bytes.dropFirst(), as: UTF8.self), radix: 10)!
      }
    }
    set {
      try? setPort(to: newValue)
    }
  }

  /// The string representation of this URL's path.
  ///
  /// A URL's path is a list of zero or more ASCII strings, usually identifying a location in hierarchical form.
  /// URLs with special schemes have an implicit path "/", which cannot be removed. URLs with other schemes may have an empty path.
  /// When setting this property, disallowed characters will be percent-encoded.
  /// However, the operation may still fail if the URL does not support the new value for other reasons.
  ///
  public var path: String {
    get { return storage.stringForComponent(.path) ?? "" }
    set { try? setPath(to: newValue) }
  }

  /// The string representation of this URL's query, if present.
  ///
  /// A URL's `query` is an optional, ordered sequence of key-value pairs. This string representation does not include the leading `?`.
  /// When setting this property, disallowed characters will be percent-encoded.
  ///
  public var query: String? {
    get {
      storage.withComponentBytes(.query) { maybeBytes in
        guard let bytes = maybeBytes else { return nil }
        guard bytes.count != 1 else {
          assert(bytes.first == ASCII.questionMark.codePoint)
          return ""
        }
        return String(decoding: bytes.dropFirst(), as: UTF8.self)
      }
    }
    set {
      setQuery(to: newValue)
    }
  }

  /// The fragment of this URL, if present, as a percent-encoded string.
  ///
  /// A URL's `fragment` is an optional string which may be used for further processing on the resource identified by the other components.
  /// This string representation does not include the leading `#`.
  /// When setting this property, disallowed characters will be percent-encoded.
  ///
  public var fragment: String? {
    get {
      storage.withComponentBytes(.fragment) { maybeBytes in
        guard let bytes = maybeBytes else { return nil }
        guard bytes.count != 1 else {
          assert(bytes.first == ASCII.numberSign.codePoint)
          return ""
        }
        return String(decoding: bytes.dropFirst(), as: UTF8.self)
      }
    }
    set {
      setFragment(to: newValue)
    }
  }
}


// MARK: - Setters


internal let _tempStorage = AnyURLStorage(
  URLStorage<GenericURLHeader<UInt8>>(
    count: 0, structure: .init(), initializingCodeUnitsWith: { _ in return 0 }
  )!
)

extension WebURL {

  internal mutating func withMutableStorage(
    _ small: (inout URLStorage<GenericURLHeader<UInt8>>) -> (AnyURLStorage),
    _ generic: (inout URLStorage<GenericURLHeader<Int>>) -> (AnyURLStorage)
  ) {
    try! withMutableStorage({ (small(&$0), nil) }, { (generic(&$0), nil) })
  }

  internal mutating func withMutableStorage(
    _ small: (inout URLStorage<GenericURLHeader<UInt8>>) -> (AnyURLStorage, URLSetterError?),
    _ generic: (inout URLStorage<GenericURLHeader<Int>>) -> (AnyURLStorage, URLSetterError?)
  ) throws {

    var error: URLSetterError?

    // We need to go through a bit of a dance in order to get a unique reference to the storage.
    // It's like if you have something stuck to one hand and try to remove it with the other hand.
    //
    // Basically:
    // 1. Swap our storage to temporarily point to some read-only global, so our only storage reference is
    //    via a local variable.
    // 2. Extract the URLStorage (which is a COW value type) from local variable's enum payload, and set
    //    the local to also point that read-only global.
    // 3. Hand that extracted storage off to closure (`inout`, but `__consuming` might also work),
    //    which returns a storage object back (possibly the same storage object).
    // 4. We round it all off by assigning that value as our new storage. Phew.
    var localRef = self.storage
    self.storage = _tempStorage
    switch localRef {
    case .generic(var extracted_storage):
      localRef = _tempStorage
      (self.storage, error) = generic(&extracted_storage)
    case .small(var extracted_storage):
      localRef = _tempStorage
      (self.storage, error) = small(&extracted_storage)
    }
    if let error = error {
      throw error
    }
  }
}

extension WebURL {

  // UTF-8 setters.

  mutating func setScheme<C>(utf8 newScheme: C) throws where C: Collection, C.Element == UInt8 {
    try withMutableStorage(
      { small in small.setScheme(to: newScheme) },
      { generic in generic.setScheme(to: newScheme) }
    )
  }

  mutating func setUsername<C>(utf8 newUsername: C?) throws where C: Collection, C.Element == UInt8 {
    try withMutableStorage(
      { small in small.setUsername(to: newUsername) },
      { generic in generic.setUsername(to: newUsername) }
    )
  }

  mutating func setPassword<C>(utf8 newPassword: C?) throws where C: Collection, C.Element == UInt8 {
    try withMutableStorage(
      { small in small.setPassword(to: newPassword) },
      { generic in generic.setPassword(to: newPassword) }
    )
  }

  mutating func setHostname<C>(utf8 newHostname: C?) throws where C: BidirectionalCollection, C.Element == UInt8 {
    try withMutableStorage(
      { small in small.setHostname(to: newHostname) },
      { generic in generic.setHostname(to: newHostname) }
    )
  }

  mutating func setPath<C>(utf8 newPath: C) throws where C: BidirectionalCollection, C.Element == UInt8 {
    try withMutableStorage(
      { small in small.setPath(to: newPath) },
      { generic in generic.setPath(to: newPath) }
    )
  }

  mutating func setQuery<C>(utf8 newQuery: C?) where C: Collection, C.Element == UInt8 {
    withMutableStorage(
      { small in small.setQuery(to: newQuery) },
      { generic in generic.setQuery(to: newQuery) }
    )
  }

  mutating func setFragment<C>(utf8 newFragment: C?) where C: Collection, C.Element == UInt8 {
    withMutableStorage(
      { small in small.setFragment(to: newFragment) },
      { generic in generic.setFragment(to: newFragment) }
    )
  }

  // StringProtocol/Int setters.

  /// Sets this URL's `scheme`, throwing an error if the operation fails.
  ///
  /// - seealso: `scheme`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setScheme<S>(to newScheme: S) throws where S: StringProtocol {
    try setScheme(utf8: newScheme.utf8)
  }

  /// Sets this URL's `username`, throwing an error if the operation fails.
  ///
  /// - seealso: `username`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setUsername<S>(to newUsername: S?) throws where S: StringProtocol {
    try setUsername(utf8: newUsername?.utf8)
  }

  /// Sets this URL's `password`, throwing an error if the operation fails.
  ///
  /// - seealso: `password`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setPassword<S>(to newPassword: S?) throws where S: StringProtocol {
    try setPassword(utf8: newPassword?.utf8)
  }

  /// Sets this URL's `hostname`, throwing an error if the operation fails.
  ///
  /// - seealso: `hostname`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setHostname<S>(to newHostname: S?) throws
  where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    try setHostname(utf8: newHostname?.utf8)
  }

  /// Sets this URL's `port`, throwing an error if the operation fails.
  ///
  /// - seealso: `port`
  ///
  public mutating func setPort(to newPort: Int?) throws {
    guard let newPort = newPort else {
      try withMutableStorage(
        { small in small.setPort(to: nil) },
        { generic in generic.setPort(to: nil) }
      )
      return
    }
    guard let uint16Port = UInt16(exactly: newPort) else {
      throw URLSetterError.error(.portValueOutOfBounds)
    }
    try withMutableStorage(
      { small in small.setPort(to: uint16Port) },
      { generic in generic.setPort(to: uint16Port) }
    )
  }

  /// Sets this URL's `path`, throwing an error if the operation fails.
  ///
  /// - seealso: `path`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setPath<S>(to newPath: S) throws where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    try setPath(utf8: newPath.utf8)
  }

  /// Sets this URL's `query`.
  ///
  /// - seealso: `query`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setQuery<S>(to newQuery: S?) where S: StringProtocol {
    setQuery(utf8: newQuery?.utf8)
  }

  /// Sets this URL's `fragment`.
  ///
  /// - seealso: `fragment`
  ///
  @_specialize(where S == String)
  @_specialize(where S == Substring)
  public mutating func setFragment<S>(to newFragment: S?) where S: StringProtocol {
    setFragment(utf8: newFragment?.utf8)
  }
}
