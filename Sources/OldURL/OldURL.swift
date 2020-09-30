// Javascript-y object model.
// Documentation comments adapted from Mozilla (https://developer.mozilla.org/en-US/docs/Web/API/URL)

/// The `OldURL` interface is used to parse, construct, normalize, and encode URLs.
///
/// It works by providing properties which allow you to easily read and modify the components of a URL.
/// You normally create a new URL object by specifying the URL as a string when calling its initializer,
/// or by providing a relative URL and a base URL.
/// You can then easily read the parsed components of the URL or make changes to the URL.
///
/// The parser and API are designed according to the WHATWG specification (https://url.spec.whatwg.org/)
/// as it was on 14.06.2020. Therefore, it should match the expectations of web developers and more accurately reflect
/// the kinds of URLs a browser will accept or reject.
///
public struct OldURL {
  private var components: OldURLParser.Components

  // @testable
  internal init(components: OldURLParser.Components) {
    self.components = components
  }

  public init?(_ url: String, base: String?) {
    guard let components = OldURLParser.parse(url, base: base) else {
      return nil
    }
    self.init(components: components)
  }

  public init?(_ url: String, baseURL: OldURL) {
    guard let components = OldURLParser.parse(url, baseURL: baseURL.components) else {
      return nil
    }
    self.init(components: components)
  }
}

extension OldURL {
  public typealias Scheme = OldURLParser.Scheme
  public typealias Host = OldURLParser.Host
  public typealias Origin = OldURLParser.Origin
  public typealias SearchParams = OldURLParser.QueryParameters

  /// A stringifier that returns a `String` containing the whole URL.
  ///
  public var href: String {
    get { return components.serialized(excludeFragment: false) }
    set {
      guard let newComponents = OldURL(newValue)?.components else { return }
      components = newComponents
    }
  }

  /// Returns an `Origin` object containing the origin of the URL, that is its scheme, its domain and its port.
  ///
  public var origin: Origin {
    return components.origin
  }

  /// A `String` containing the protocol scheme of the URL, including the final ':'.
  /// Called `protocol` in JavaScript.
  ///
  public var scheme: String {
    get { return components.scheme.rawValue + ":" }
    set { components.modify(newValue + ":", stateOverride: .schemeStart) }
  }

  /// A `String` containing the username specified before the domain name.
  ///
  public var username: String {
    get { return components.username }
    set {
      guard components.cannotHaveCredentialsOrPort == false else { return }
      components.username = ""
      PercentEscaping.encodeIterativelyAsString(bytes: newValue.utf8, escapeSet: .url_userInfo) {
        components.username.append($0)
      }
    }
  }

  /// A `String` containing the password specified before the domain name.
  ///
  public var password: String {
    get { return components.password }
    set {
      guard components.cannotHaveCredentialsOrPort == false else { return }
      components.password = ""
      PercentEscaping.encodeIterativelyAsString(bytes: newValue.utf8, escapeSet: .url_userInfo) {
        components.password.append($0)
      }
    }
  }

  /// A `String` containing the domain (that is the hostname) followed by (if a port was specified) a ':' and the port of the URL.
  ///
  public var host: String {
    get {
      guard let host = components.host else { return "" }
      guard let port = components.port else { return host.serialized }
      return "\(host):\(port)"
    }
    set {
      guard components.cannotBeABaseURL == false else { return }
      components.modify(newValue, stateOverride: .host)
    }
  }

  /// A `String` containing the domain of the URL.
  ///
  public var hostname: String {
    get { return components.host?.serialized ?? "" }
    set {
      guard components.cannotBeABaseURL == false else { return }
      components.modify(newValue, stateOverride: .hostname)
    }
  }

  /// The port number of the URL
  ///
  public var port: UInt16? {
    get { return components.port }
    set {
      guard components.cannotHaveCredentialsOrPort == false else { return }
      components.port = (newValue == components.scheme.defaultPort) ? nil : newValue
    }
  }

  /// A `String` containing an initial '/' followed by the path of the URL.
  ///
  public var pathname: String {
    get {
      if components.cannotBeABaseURL || components.path.isEmpty {
        return components.path.first ?? ""
      }
      return "/" + components.path.joined(separator: "/")
    }
    set {
      guard components.cannotBeABaseURL == false else { return }
      components.path.removeAll()
      components.modify(newValue, stateOverride: .pathStart)
    }
  }

  /// A `String` indicating the URL's parameter string; if any parameters are provided,
  /// this string includes all of them, beginning with the leading '?' character.
  ///
  public var search: String {
    get {
      guard let query = components.query, query.isEmpty == false else { return "" }
      return "?" + query
    }
    set {
      guard newValue.isEmpty == false else {
        components.query = nil
        return
      }
      let input: Substring
      if newValue.hasPrefix("?") {
        input = newValue.dropFirst()
      } else {
        input = newValue[...]
      }
      components.query = ""
      components.modify(input, stateOverride: .query)
    }
  }

  /// A `SearchParams` object which can be used to access the individual query parameters found in `search`.
  ///
  public var searchParams: SearchParams? {
    get { components.queryParameters }
    set { components.queryParameters = newValue }
  }

  /// A `String` containing a '#' followed by the fragment identifier of the URL.
  /// Called `hash` in JavaScript.
  ///
  public var fragment: String {
    get {
      guard let fragment = components.fragment, fragment.isEmpty == false else { return "" }
      return "#" + fragment
    }
    set {
      guard newValue.isEmpty == false else {
        components.fragment = nil
        return
      }
      let input: Substring
      if newValue.hasPrefix("#") {
        input = newValue.dropFirst()
      } else {
        input = newValue[...]
      }
      components.fragment = ""
      components.modify(input, stateOverride: .fragment)
    }
  }
}

// Standard protocols.

extension OldURL: Equatable, Hashable, Codable, LosslessStringConvertible {

  public static func == (lhs: OldURL, rhs: OldURL) -> Bool {
    return lhs.href == rhs.href
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(href)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let parsed = OldURL(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a valid URL string")
    }
    self = parsed
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(href)
  }

  public init?(_ description: String) {
    guard let parsed = OldURL(description, base: nil) else { return nil }
    self = parsed
  }

  public var description: String {
    return href
  }
}

// Not `CustomDebugStringConvertible` because we never want `String(describing: someURL)` to return this String.

extension OldURL {

  public var debugDescription: String {
    return """
      \n{
      \t.href:     \(href)
      \t.scheme:   \(scheme)
      \t.username: \(username)
      \t.password: \(password)
      \t.host:     \(host)
      \t.hostname: \(hostname)
      \t.origin:   \(origin)
      \t.port:     \(port.map { String($0) } ?? "<nil>")
      \t.pathname: \(pathname)
      \t.search:   \(search)
      \t.fragment: \(fragment)
      }
      """
  }
}

// Extensions for async-http-client.

extension StringProtocol {
  
  /// Returns a version of this String with any percent-encoded characters replaced by their
  /// decoded counterparts.
  ///
  public var percentUnescaped: String {
    return PercentEscaping.decodeString(self)
  }
}

extension OldURL {
  
  /// Returns a version of the given String with all characters that are not allowed in URL hosts
  /// replaced by their percent-escaped counterparts.
  ///
  public static func percentEscapeHostname(_ hostname: String) -> String {
    var newHost = ""
    PercentEscaping.encodeIterativelyAsString(
      bytes: hostname.utf8,
      escapeSet: .url_host_forbidden,
      processChunk: { newHost.append($0) }
    )
    return newHost
  }
  
  /// Returns the `Scheme` object representing this URL's `scheme`.
  ///
  public var schemeObject: Scheme {
    return components.scheme
  }
  
  /// Returns the `Host` object representing this URL's `hostname`.
  ///
  public var hostObject: Host? {
    return components.host
  }
}

