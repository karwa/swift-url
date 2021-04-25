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
/// Parsing and manipulation of URLs is compatible with the [WHATWG URL Specification][url-spec].
/// The `WebURL` API differs slightly from the Javascript API described in the standard, which is available via the `.jsModel` property.
///
/// [url-spec]: https://url.spec.whatwg.org/
///
public struct WebURL {

  @usableFromInline
  internal var storage: AnyURLStorage

  @inlinable
  internal init(storage: AnyURLStorage) {
    self.storage = storage
  }

  /// Attempt to construct a URL by parsing the given string.
  ///
  /// The created URL is normalized in a number of ways - for instance, whitespace characters may be removed, other characters may be percent-encoded,
  /// hostnames may be IDNA-encoded, or rewritten in a canonical notation if they are IP addresses, paths may be lexically simplified, etc. This means that the
  /// resulting object's serialized string may look different to the original contents. These transformations are defined in the URL standard.
  ///
  @inlinable @inline(__always)
  public init?<S>(_ string: S) where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    self.init(utf8: string.utf8)
  }

  /// Attempt to construct a URL by parsing the given string, provided as a collection of UTF-8 code-units.
  ///
  /// The created URL is normalized in a number of ways - for instance, whitespace characters may be removed, other characters may be percent-encoded,
  /// hostnames may be IDNA-encoded, or rewritten in a canonical notation if they are IP addresses, paths may be lexically simplified, etc. This means that the
  /// resulting object's serialized string may look different to the original contents. These transformations are defined in the URL standard.
  ///
  @inlinable @inline(__always)
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    guard let url = urlFromBytes(utf8, baseURL: nil) else { return nil }
    self = url
  }

  /// Attempt to create a URL by parsing the given string with this URL as its base.
  ///
  /// This function supports a wide range of relative URL strings, producing the same result as an HTML `<a>` tag on the page given by this URL.
  /// In particular, users should note that the resulting URL may have a different host to this one, and may even have a different scheme if the given string
  /// is an absolute URL string.
  ///
  /// ```swift
  /// let base = WebURL("http://example.com/karl/index.html")!
  ///
  /// base.resolve("img.jpg?size=200x200")! // "http://example.com/karl/img.jpg?size=200x200"
  /// base.resolve("/mary/lambs/")! // "http://example.com/mary/lambs/"
  /// base.resolve("//test.com")! // "http://test.com/"
  /// base.resolve("ftp://test.com/some/file")! // "ftp://test.com/some/file"
  /// ```
  ///
  @inlinable @inline(__always)
  public func resolve<S>(_ string: S) -> WebURL? where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    resolve(utf8: string.utf8)
  }

  /// Attempt to create a URL by parsing the given string, provided as a collection of UTF-8 code-units, with this URL as its base.
  ///
  /// This function supports a wide range of relative URL strings, producing the same result as an HTML `<a>` tag on the page given by this URL.
  /// In particular, users should note that the resulting URL may have a different host to this one, and may even have a different scheme if the given string
  /// is an absolute URL string.
  ///
  @inlinable @inline(__always)
  public func resolve<UTF8Bytes>(
    utf8: UTF8Bytes
  ) -> WebURL? where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    urlFromBytes(utf8, baseURL: self)
  }
}


// --------------------------------------------
// MARK: - Standard protocols
// --------------------------------------------


extension WebURL: Equatable, Hashable, Comparable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.utf8.withUnsafeBufferPointer { lhsBuffer in
      rhs.utf8.withUnsafeBufferPointer { rhsBuffer in
        (lhsBuffer.baseAddress == rhsBuffer.baseAddress && lhsBuffer.count == rhsBuffer.count)
          || lhsBuffer.elementsEqual(rhsBuffer)
      }
    }
  }

  public func hash(into hasher: inout Hasher) {
    utf8.withUnsafeBufferPointer { buffer in
      hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.utf8.withUnsafeBufferPointer { lhsBuffer in
      rhs.utf8.withUnsafeBufferPointer { rhsBuffer in
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


// --------------------------------------------
// MARK: - Properties
// --------------------------------------------


extension WebURL {

  // Required by the parser.
  @inlinable
  internal var schemeKind: WebURL.SchemeKind {
    storage.schemeKind
  }
}

extension WebURL {

  /// The string representation of this URL.
  ///
  public var serialized: String {
    String(decoding: utf8, as: UTF8.self)
  }

  /// The string representation of this URL, excluding the URL's fragment.
  ///
  public var serializedExcludingFragment: String {
    utf8.withUnsafeBufferPointer { String(decoding: $0[..<storage.structure.fragmentStart], as: UTF8.self) }
  }

  /// The scheme of this URL, for example `https` or `file`.
  ///
  /// A URL’s `scheme` is a non-empty ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing.
  /// For example, software that speaks the HTTP protocol will know how to process requests for URLs with the "http" scheme. Every URL must have a scheme.
  ///
  /// Some schemes (http, https, ws, wss, ftp, and file) are referred to as being "special"; the components of URLs with these schemes may have unique
  /// encoding requirements, or additional meaning. Scheme usage is co-ordinated by the [Internet Assigned Numbers Authority][iana-schemes].
  ///
  /// Setting this property may fail if the new scheme is invalid, or if the URL cannot be adjusted to the new scheme.
  ///
  /// [iana-schemes]: https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
  ///
  public var scheme: String {
    get { String(decoding: utf8.scheme, as: UTF8.self) }
    set { try? setScheme(newValue) }
  }

  /// The username of this URL, if present, as a non-empty, percent-encoded ASCII string.
  ///
  /// When setting this property, the new contents will be percent-encoded if necessary.
  /// Setting this property may fail if the URL does not allow credentials.
  ///
  public var username: String? {
    get { utf8.username.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setUsername(newValue) }
  }

  /// The password of this URL, if present, as a non-empty, percent-encoded string.
  ///
  /// When setting this property, the new contents will be percent-encoded if necessary.
  /// Setting this property may fail if the URL does not allow credentials.
  ///
  public var password: String? {
    get { utf8.password.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setPassword(newValue) }
  }

  /// The string representation of this URL's host, if present.
  ///
  /// A URL's host which can be a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
  /// Typically a host serves as a network address, but is sometimes used as an opaque identifier in URLs where a network address is not necessary.
  ///
  /// When setting this property, the new contents will be parsed and normalized (e.g. domains will be percent-decoded and lowercased, and IP addresses
  /// rewritten in a canonical format). Setting this property will fail if the new contents contain invalid host code-points or a malformed IP address.
  ///
  public var hostname: String? {
    get { utf8.hostname.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setHostname(newValue) }
  }

  /// The port of this URL, if present. Valid port numbers are in the range `0 ..< 65536`.
  ///
  /// Setting this property may fail if the new value is out of range, or if the URL does not support port numbers.
  /// If the URL has a "special" scheme, setting the port to its known default value will remove the port.
  ///
  public var port: Int? {
    get { utf8.port.map { Int(String(decoding: $0, as: UTF8.self), radix: 10)! } }
    set { try? setPort(newValue) }
  }

  /// The port of this URL, if present, or the default port of its scheme, if it has one.
  ///
  public var portOrKnownDefault: Int? {
    port ?? schemeKind.defaultPort.map { Int($0) }
  }

  /// The string representation of this URL's path.
  ///
  /// A URL's path is a list of zero or more ASCII strings, usually identifying a location in hierarchical form. Hierarchical paths begin with a "/".
  ///
  /// URLs with "special" schemes always have non-empty, hierarchical paths, and attempting to set the path to an empty string will instead set it to "/".
  /// URLs with non-special schemes may have an empty path under certain circumstances.
  /// URLs with non-hierarchical paths are referred to as `cannotBeABase` URLs.
  ///
  /// ```swift
  /// let file = WebURL("file:///usr/bin/swift")!
  /// print(file) // "file:///usr/bin/swift"
  /// print(file.path) // "/usr/bin/swift"
  /// print(file.cannotBeABase) // false
  ///
  /// let hasImplictPath = WebURL("http://example.com")!
  /// print(hasImplictPath) // "http://example.com/"
  /// print(hasImplictPath.path) // "/"
  /// print(hasImplictPath.cannotBeABase) // false
  ///
  /// let mailURL = WebURL("mailto:bob@example.com")!
  /// print(mailURL) // "mailto:bob@example.com"
  /// print(mailURL.path) // "bob@example.com"
  /// print(mailURL.cannotBeABase) // true
  /// ```
  ///
  /// When setting this property, the new contents will be parsed, lexically simplified, and percent-encoded if necessary.
  /// Setting this property will fail if the URL `cannotBeABase`.
  ///
  public var path: String {
    get { String(decoding: utf8.path, as: UTF8.self) }
    set { try? setPath(newValue) }
  }

  /// The string representation of this URL's query, if present.
  ///
  /// A URL's `query` contains non-hierarchical data that, along with the `path`, serves to identify a resource. The precise structure of the query string is not
  /// standardized, but is often used to store a list of key-value pairs ("parameters").
  ///
  /// This string representation does not include the leading `?` delimiter.
  /// When setting this property, the new contents will be percent-encoded if necessary. Setting this property does not fail.
  ///
  public var query: String? {
    get { utf8.query.map { String(decoding: $0, as: UTF8.self) } }
    set { setQuery(newValue) }
  }

  /// The fragment of this URL, if present, as a percent-encoded string.
  ///
  /// A URL's `fragment` is an optional string which may be used for further processing on the resource identified by the other components.
  ///
  /// This string representation does not include the leading `#` delimiter.
  /// When setting this property, the new contents will be percent-encoded if necessary. Setting this property does not fail.
  ///
  public var fragment: String? {
    get { utf8.fragment.map { String(decoding: $0, as: UTF8.self) } }
    set { setFragment(newValue) }
  }

  /// Whether this URL cannot be a base.
  ///
  /// URLs which 'cannot be a base' do not have special schemes (such as http or file), authority components or hierarchical paths.
  /// When parsing a relative URL string against such a URL, only strings which set the fragment are allowed, and any modifications which would change
  /// a URL's structure to be a valid base URL (or vice versa) are not allowed.
  /// Examples of URLs which cannot be a base are:
  ///
  /// - `mailto:bob@example.com`
  /// - `javascript:alert("hello");`
  /// - `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`
  ///
  public var cannotBeABase: Bool {
    storage.cannotBeABaseURL
  }
}


// --------------------------------------------
// MARK: - Setters
// --------------------------------------------


extension WebURL {

  /// Replaces this URL's `scheme` with the given string.
  ///
  /// - seealso: `scheme`
  ///
  @inlinable
  public mutating func setScheme<S>(_ newScheme: S) throws where S: StringProtocol {
    try utf8.setScheme(newScheme.utf8)
  }

  /// Replaces this URL's `username` with the given string.
  ///
  /// - seealso: `username`
  ///
  @inlinable
  public mutating func setUsername<S>(_ newUsername: S?) throws where S: StringProtocol {
    try utf8.setUsername(newUsername?.utf8)
  }

  /// Replaces this URL's `password` with the given string.
  ///
  /// - seealso: `password`
  ///
  @inlinable
  public mutating func setPassword<S>(_ newPassword: S?) throws where S: StringProtocol {
    try utf8.setPassword(newPassword?.utf8)
  }

  /// Replaces this URL's `hostname` with the given string.
  ///
  /// - seealso: `hostname`
  ///
  @inlinable
  public mutating func setHostname<S>(_ newHostname: S?) throws
  where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    try utf8.setHostname(newHostname?.utf8)
  }

  /// Replaces this URL's `port`.
  ///
  /// - seealso: `port`
  ///
  public mutating func setPort(_ newPort: Int?) throws {
    guard let newPort = newPort else {
      try storage.withUnwrappedMutableStorage(
        { small in small.setPort(to: nil) },
        { large in large.setPort(to: nil) }
      )
      return
    }
    guard let uint16Port = UInt16(exactly: newPort) else {
      throw URLSetterError.portValueOutOfBounds
    }
    try storage.withUnwrappedMutableStorage(
      { small in small.setPort(to: uint16Port) },
      { large in large.setPort(to: uint16Port) }
    )
  }

  /// Replaces this URL's `path` with the given string.
  ///
  /// - seealso: `path`
  ///
  @inlinable
  public mutating func setPath<S>(_ newPath: S) throws where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    try utf8.setPath(newPath.utf8)
  }

  /// Replaces this URL's `query` with the given string.
  ///
  /// - seealso: `query`
  ///
  @inlinable
  public mutating func setQuery<S>(_ newQuery: S?) where S: StringProtocol {
    utf8.setQuery(newQuery?.utf8)
  }

  /// Replaces this URL's `fragment` with the given string.
  ///
  /// - seealso: `fragment`
  ///
  @inlinable
  public mutating func setFragment<S>(_ newFragment: S?) where S: StringProtocol {
    utf8.setFragment(newFragment?.utf8)
  }
}
