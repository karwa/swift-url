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
/// URL parsing and serialization is compatible with the [WHATWG URL Standard][URL-spec].
///
/// The `WebURL` API is designed to meet the needs and expectations of Swift developers, expanding on the JavaScript API described in the standard
/// to add path-component manipulation, host objects, and more. Some of the component values have been tweaked to not include their leading or
/// trailing delimiters, and component setters are little stricter and more predictable, but in all other respects they should have the same behaviour.
///
/// For more information on the differences between this API and the JavaScript `URL` class, see the `WebURL.JSModel` type.
///
/// [URL-spec]: https://url.spec.whatwg.org/
///
public struct WebURL {

  @usableFromInline
  internal var storage: URLStorage

  @inlinable
  internal init(storage: URLStorage) {
    self.storage = storage
  }

  /// Constructs a URL by parsing the given string.
  ///
  /// This parser is compatible with the [WHATWG URL Standard][URL-spec]; this means that whitespace characters may be removed from the given string,
  /// other characters may be percent-encoded based on which component they belong to, IP addresses rewritten in canonical notation,
  /// and paths lexically simplified, among other transformations defined by the standard.
  ///
  /// [URL-spec]: https://url.spec.whatwg.org/
  ///
  @inlinable @inline(__always)
  public init?<S>(_ string: S) where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    self.init(utf8: string.utf8)
  }

  /// Constructs a URL by parsing the given string, which is provided as a collection of UTF-8 code-units.
  ///
  /// This parser is compatible with the [WHATWG URL Standard][URL-spec]; this means that whitespace characters may be removed from the given string,
  /// other characters may be percent-encoded based on which component they belong to, IP addresses rewritten in canonical notation,
  /// and paths lexically simplified, among other transformations defined by the standard.
  ///
  /// [URL-spec]: https://url.spec.whatwg.org/
  ///
  @inlinable @inline(__always)
  public init?<UTF8Bytes>(utf8: UTF8Bytes) where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {
    guard let url = urlFromBytes(utf8, baseURL: nil) else { return nil }
    self = url
  }

  /// Parses the given string with this URL as its base.
  ///
  /// This function supports a wide range of relative URL strings, producing the same result as an HTML `<a>` tag on the page given by this URL.
  ///
  /// ```swift
  /// let base = WebURL("http://example.com/karl/index.html")!
  ///
  /// base.resolve("photos/img.jpg?size=200x200")! // "http://example.com/karl/photos/img.jpg?size=200x200"
  /// base.resolve("/mary/lambs/1/fleece.txt")! // "http://example.com/mary/lambs/1/fleece.txt"
  /// ```
  ///
  /// It should be noted that this method accepts protocol-relative URLs, which are able to direct to a different hostname, as well as absolute URL strings,
  /// which do not copy any information from their base URLs.
  ///
  @inlinable @inline(__always)
  public func resolve<S>(_ string: S) -> WebURL? where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    utf8.resolve(string.utf8)
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
        lhsBuffer.lexicographicallyPrecedes(rhsBuffer)
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
    let container = try decoder.singleValueContainer()
    guard let decoded = WebURL(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid URL")
    }
    self = decoded
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(serialized)
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
  /// For example, a URL with the "http" scheme should be processed by software that understands the HTTP protocol. Every URL must have a scheme.
  ///
  /// Some schemes (http, https, ws, wss, ftp, and file) are referred to as being "special"; the components of URLs with these schemes may have unique
  /// encoding requirements, or the components may carry additional meaning.
  /// Scheme usage is co-ordinated by the [Internet Assigned Numbers Authority][iana-schemes].
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
  /// When setting this property, any code-points which are not valid for use in the URL's user-info section will be percent-encoded.
  /// Setting this property may fail if the URL does not allow credentials.
  ///
  public var username: String? {
    get { utf8.username.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setUsername(newValue) }
  }

  /// The password of this URL, if present, as a non-empty, percent-encoded string.
  ///
  /// When setting this property, any code-points which are not valid for use in the URL's user-info section will be percent-encoded.
  /// Setting this property may fail if the URL does not allow credentials.
  ///
  public var password: String? {
    get { utf8.password.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setPassword(newValue) }
  }

  /// The string representation of this URL's host, if present.
  ///
  /// A URL's host can be a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
  /// Typically a host serves as a network address, but is sometimes used as an opaque identifier in URLs where a network address is not necessary.
  ///
  /// When setting this property, the new contents will be parsed and normalized (e.g. domains will be percent-decoded and lowercased, and IP addresses
  /// will be rewritten in their canonical form). Unlike setting other components, not all code-points which are invalid for use in hostnames will be percent-encoded.
  /// If the new content contains a [forbidden host code-point][URL-fhcp], the operation will fail.
  ///
  /// [URL-fhcp]: https://url.spec.whatwg.org/#forbidden-host-code-point
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
  /// A URL's path is a list of zero or more ASCII strings, usually identifying a location in hierarchical form.
  /// Hierarchical paths are those that begin with a "/". Empty paths are assumed to be hierarchical if the URL has a `hostname`.
  ///
  /// When setting this property, the given path string will be lexically simplified, and any code-points in the path's components that are not valid
  /// for use will be percent-encoded. Setting this property may fail if the URL is non-hierarchical (see `WebURL.isHierarchical`).
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
  /// When setting this property, any code-points which are not valid for use in the URL's query will be percent-encoded.
  /// Note that the set of code-points which are valid depends on the URL's `scheme`.
  ///
  public var query: String? {
    get { utf8.query.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setQuery(newValue) }
  }

  /// The fragment of this URL, if present, as a percent-encoded string.
  ///
  /// A URL's `fragment` is an optional string which may be used for further processing on the resource identified by the other components.
  ///
  /// This string representation does not include the leading `#` delimiter.
  /// When setting this property, any code-points which are not valid for use in the URL's fragment will be percent-encoded.
  ///
  public var fragment: String? {
    get { utf8.fragment.map { String(decoding: $0, as: UTF8.self) } }
    set { try? setFragment(newValue) }
  }

  /// Whether this is a hierarchical URL.
  ///
  /// Hierarchical URLs have an authority component or hierarchical path.
  /// URLs with special schemes (such as http or file) are always hierarchical.
  ///
  /// Non-hierarchical URLs can be recognized by the lack of slashes immediately following their scheme, and support only a very
  /// limited subset of URL operations. Attempting to set any authority components, such as `username`, `password`, `hostname` or `port`,
  /// will fail, as will attempts to set the `path`. Non-hierarchical URLs do not have path components, so accessing the `pathComponents` property
  /// will trigger a runtime error. When resolving a relative URL string against a non-hierarchical URL, only replacing the fragment is allowed.
  ///
  /// Examples of non-hierarchical URLs are:
  ///
  /// - `mailto:bob@example.com`
  /// - `javascript:alert("hello");`
  /// - `data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==`
  ///
  public var isHierarchical: Bool {
    storage.isHierarchical
  }
}


// --------------------------------------------
// MARK: - Setters
// --------------------------------------------


extension WebURL {

  /// Replaces this URL's `scheme` with the given string.
  ///
  /// Setting this component may fail if the new scheme is invalid, or if the URL cannot be adjusted to the new scheme.
  ///
  /// - seealso: `scheme`
  ///
  @inlinable
  public mutating func setScheme<S>(_ newScheme: S) throws where S: StringProtocol {
    try utf8.setScheme(newScheme.utf8)
  }

  /// Replaces this URL's `username` with the given string.
  ///
  /// Any code-points which are not valid for use in the URL's user-info section will be percent-encoded.
  /// Setting this component may fail if the URL does not allow credentials.
  ///
  /// - seealso: `username`
  ///
  @inlinable
  public mutating func setUsername<S>(_ newUsername: S?) throws where S: StringProtocol {
    try utf8.setUsername(newUsername?.utf8)
  }

  /// Replaces this URL's `password` with the given string.
  ///
  /// Any code-points which are not valid for use in the URL's user-info section will be percent-encoded.
  /// Setting this component may fail if the URL does not allow credentials.
  ///
  /// - seealso: `password`
  ///
  @inlinable
  public mutating func setPassword<S>(_ newPassword: S?) throws where S: StringProtocol {
    try utf8.setPassword(newPassword?.utf8)
  }

  /// Replaces this URL's `hostname` with the given string.
  ///
  /// When setting this component, the new contents will be parsed and normalized (e.g. domains will be percent-decoded and lowercased, and IP addresses
  /// will be rewritten in their canonical form). Unlike setting other components, not all code-points which are invalid for use in hostnames will be percent-encoded.
  /// If the new content contains a [forbidden host code-point][URL-fhcp], the operation will fail.
  ///
  /// [URL-fhcp]: https://url.spec.whatwg.org/#forbidden-host-code-point
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
  /// Setting this component may fail if the new value is out of range, or if the URL does not support port numbers.
  /// If the URL has a "special" scheme, setting the port to its known default value will remove the port.
  ///
  /// - seealso: `port`
  ///
  public mutating func setPort(_ newPort: Int?) throws {
    guard let newPort = newPort else {
      return try storage.setPort(to: nil).get()
    }
    guard let uint16Port = UInt16(exactly: newPort) else {
      throw URLSetterError.portValueOutOfBounds
    }
    try storage.setPort(to: uint16Port).get()
  }

  /// Replaces this URL's `path` with the given string.
  ///
  /// When setting this component, the given path string will be lexically simplified, and any code-points in the path's components that are not valid
  /// for use will be percent-encoded. Setting this component will fail if the URL is non-hierarchical (see `WebURL.isHierarchical` for more information).
  ///
  /// - seealso: `path`
  ///
  @inlinable
  public mutating func setPath<S>(_ newPath: S) throws where S: StringProtocol, S.UTF8View: BidirectionalCollection {
    try utf8.setPath(newPath.utf8)
  }

  /// Replaces this URL's `query` with the given string.
  ///
  /// When setting this property, any code-points which are not valid for use in the URL's query will be percent-encoded.
  /// Note that the set of code-points which are valid depends on the URL's `scheme`.
  ///
  /// - seealso: `query`
  ///
  @inlinable
  public mutating func setQuery<S>(_ newQuery: S?) throws where S: StringProtocol {
    try utf8.setQuery(newQuery?.utf8)
  }

  /// Replaces this URL's `fragment` with the given string.
  ///
  /// When setting this property, any code-points which are not valid for use in the URL's fragment will be percent-encoded.
  ///
  /// - seealso: `fragment`
  ///
  @inlinable
  public mutating func setFragment<S>(_ newFragment: S?) throws where S: StringProtocol {
    try utf8.setFragment(newFragment?.utf8)
  }
}
