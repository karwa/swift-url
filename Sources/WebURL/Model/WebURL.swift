/// A Uniform Resource Locator (URL) is a value which identifies the location of a resource.
///
/// A URL is a `String` that can be deconstructed in to components which describe how to access the resource.
///
/// - The `scheme` (or "protocol") describes how to communicate with the resource's location.
///   For example, a URL with an "http" scheme must be used with software that speaks the HTTP protocol.
///   A scheme is always required, and the way in which other components are encoded depends on the scheme.
///   Some schemes ("http", "https", "ws", "wss", "ftp", and "file") are referred to as being "special".
///   Scheme usage is coordinated by the [Internet Assigned Numbers Authority][iana-schemes].
///
/// - The `hostname` is an optional component which describes which computer has the resource information.
///   For URLs with special schemes, the hostname may be an IP address, a _domain_, or empty.
///   For URLs with non-special schemes, the hostname is an opaque identifier.
///   Domains may be resolved to IP addresses using the [Domain Name System (DNS)][dns] .
///
/// - Additionally, the hostname may be augmented by a `username`, `password` or `port`. Collectively, these are known as the URL's "authority".
///
/// - The `path` is an optional component which describes the location of the resource on the host.
///   It models descending a tree of 'components', each of which is separated by a "/" character, with "." referring to the current node and ".." referring to the parent.
///   It is important to note that the way these model paths are mapped to actual resources is a host- or scheme-specific detail
///   (for example, if the host uses a case-insensitive filesystem, two "file" URLs with different model paths may map to the same filesystem path).
///
/// - The `query` is an optional, ordered sequence of key-value pairs which the host may use when processing a request.
///
/// - The `fragment` is an optional string which may be used for further processing on the resource identified by the other components.
///   It is typically used for client-side information and not sent to the host, although this is a scheme- and implementation-specific detail.
///
/// URLs are always ASCII Strings. Non-ASCII characters must be percent-encoded, except in domains, where they are encoded as ASCII by
/// the [IDNA transformation][idna-spec] .
///
/// Parsing of URL strings is compatible with the [WHATWG URL Specification][url-spec] as it was on 14.06.2020, although
/// the object model is different. The Javascript model described in the specification is available via the `.jsModel` view.
///
/// [iana-schemes]: https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
/// [dns]: https://en.wikipedia.org/wiki/Domain_Name_System
/// [idna-spec]: https://unicode.org/reports/tr46/
/// [url-spec]: https://url.spec.whatwg.org/
///
public struct WebURL {
  var storage: AnyURLStorage

  init(storage: AnyURLStorage) {
    self.storage = storage
  }

  public init?(_ input: String) {
    var input = input
    guard let url = input.withUTF8({ urlFromBytes($0, baseURL: nil) }) else {
      return nil
    }
    self = url
  }

  public init?(_ input: String, base: String?) {
    var baseURL: WebURL?
    var input = input
    if var baseString = base {
      baseURL = baseString.withUTF8 { urlFromBytes($0, baseURL: nil) }
      guard baseURL != nil else { return nil }
    }
    guard let url = input.withUTF8({ urlFromBytes($0, baseURL: baseURL) }) else {
      return nil
    }
    self = url
  }
}

extension WebURL {

  // Flags used by the parser.

  var _schemeKind: WebURL.SchemeKind {
    return storage.schemeKind
  }

  var _cannotBeABaseURL: Bool {
    return storage.cannotBeABaseURL
  }
}

// Standard protocols.

extension WebURL: CustomStringConvertible, LosslessStringConvertible, TextOutputStreamable {

  public var description: String {
    return storage.entireString
  }

  public func write<Target>(to target: inout Target) where Target: TextOutputStream {
    target.write(description)
  }
}

extension WebURL: Equatable, Hashable {

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage.withEntireString { lhsBuffer in
      rhs.storage.withEntireString { rhsBuffer in
        return (lhsBuffer.baseAddress == rhsBuffer.baseAddress && lhsBuffer.count == rhsBuffer.count)
          || lhsBuffer.elementsEqual(rhsBuffer)
      }
    }
  }

  public func hash(into hasher: inout Hasher) {
    storage.withEntireString { buffer in
      hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
    }
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
    try box.encode(self.description)
  }
}


// Note: All of these are now dead. To be replaced with a new object model.
// It might be worth having the JS model call through and make any adjustments that it needs,
// to improve test coverage.
extension WebURL {

  // Components.
  // Note: erasure to empty strings is done to fit the Javascript model for WHATWG tests.

  public var href: String {
    return storage.entireString
  }

  func stringForComponent(_ component: Component) -> String? {
    return storage.withComponentBytes(component) { maybeBuffer in
      return maybeBuffer.map { buffer in String(decoding: buffer, as: UTF8.self) }
    }
  }

  public var scheme: String {
    return stringForComponent(.scheme)!
  }

  public var username: String {
    return stringForComponent(.username) ?? ""
  }

  public var password: String {
    var string = stringForComponent(.password)
    if !(string?.isEmpty ?? true) {
      let separator = string?.removeFirst()
      assert(separator == ":")
    }
    return string ?? ""
  }

  public var hostname: String {
    return stringForComponent(.hostname) ?? ""
  }

  public var port: String {
    var string = stringForComponent(.port)
    if !(string?.isEmpty ?? true) {
      let separator = string?.removeFirst()
      assert(separator == ":")
    }
    return string ?? ""
  }

  public var path: String {
    return stringForComponent(.path) ?? ""
  }

  public var query: String {
    let string = stringForComponent(.query)
    guard string != "?" else { return "" }
    return string ?? ""
  }

  public var fragment: String {
    let string = stringForComponent(.fragment)
    guard string != "#" else { return "" }
    return string ?? ""
  }
}
