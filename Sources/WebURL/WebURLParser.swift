import Algorithms  // for Collection.trim

/// A namespace for deconstructed URL components and operations on them.
/// These types and methods should be wrapped or aliased in to a more user-friendly model.
///
/// See: https://url.spec.whatwg.org/ for more information.
///
public enum WebURLParser {}

extension WebURLParser {

  struct Components: Equatable, Hashable, Codable {
    fileprivate final class Storage: Equatable, Hashable, Codable {
      var scheme: WebURLParser.Scheme
      var username: String
      var password: String
      var host: WebURLParser.Host?
      var port: UInt16?
      var path: [String]
      var query: String?
      var fragment: String?
      var cannotBeABaseURL = false
      // TODO:
      // URL also has an associated blob URL entry that is either null or a blob URL entry. It is initially null.

      init(
        scheme: WebURLParser.Scheme, username: String, password: String, host: WebURLParser.Host?,
        port: UInt16?, path: [String], query: String?, fragment: String?,
        cannotBeABaseURL: Bool
      ) {
        self.scheme = scheme
        self.username = username
        self.password = password
        self.host = host
        self.port = port
        self.path = path
        self.query = query
        self.fragment = fragment
        self.cannotBeABaseURL = cannotBeABaseURL
      }

      func copy() -> Self {
        return Self(
          scheme: scheme, username: username, password: password, host: host,
          port: port, path: path, query: query, fragment: fragment,
          cannotBeABaseURL: cannotBeABaseURL
        )
      }

      static func == (lhs: Storage, rhs: Storage) -> Bool {
        return
          lhs.scheme == rhs.scheme && lhs.username == rhs.username && lhs.password == rhs.password
          && lhs.host == rhs.host && lhs.port == rhs.port && lhs.path == rhs.path && lhs.query == rhs.query
          && lhs.fragment == rhs.fragment && lhs.cannotBeABaseURL == rhs.cannotBeABaseURL
      }

      func hash(into hasher: inout Hasher) {
        scheme.hash(into: &hasher)
        username.hash(into: &hasher)
        password.hash(into: &hasher)
        host.hash(into: &hasher)
        port.hash(into: &hasher)
        path.hash(into: &hasher)
        query.hash(into: &hasher)
        fragment.hash(into: &hasher)
        cannotBeABaseURL.hash(into: &hasher)
      }

      var hasCredentials: Bool {
        !username.isEmpty || !password.isEmpty
      }

      /// Copies the username, password, host and port fields from `other`.
      ///
      func copyAuthority(from other: WebURLParser.Components.Storage) {
        self.username = other.username
        self.password = other.password
        self.host = other.host
        self.port = other.port
      }
    }

    fileprivate var _storage: Storage

    private mutating func ensureUnique() {
      if !isKnownUniquelyReferenced(&_storage) {
        _storage = _storage.copy()
      }
    }

    init(
      scheme: WebURLParser.Scheme = .other(""), username: String = "", password: String = "",
      host: WebURLParser.Host? = nil,
      port: UInt16? = nil, path: [String] = [], query: String? = nil, fragment: String? = nil,
      cannotBeABaseURL: Bool = false
    ) {
      self._storage = Storage(
        scheme: scheme, username: username, password: password, host: host,
        port: port, path: path, query: query, fragment: fragment,
        cannotBeABaseURL: cannotBeABaseURL
      )
    }
  }
}

extension WebURLParser.Components {


  /// A URL’s scheme is an ASCII string that identifies the type of URL and can be used to dispatch a URL for further processing after parsing. It is initially the empty string.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var scheme: WebURLParser.Scheme {
    get { return _storage.scheme }
    set {
      ensureUnique()
      _storage.scheme = newValue
    }
  }

  /// A URL’s username is an ASCII string identifying a username. It is initially the empty string.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var username: String {
    get { return _storage.username }
    set {
      ensureUnique()
      _storage.username = newValue
    }
  }

  /// A URL’s password is an ASCII string identifying a password. It is initially the empty string.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var password: String {
    get { return _storage.password }
    set {
      ensureUnique()
      _storage.password = newValue
    }
  }

  /// A URL’s host is null or a host. It is initially null.
  ///
  /// A host is a domain, an IPv4 address, an IPv6 address, an opaque host, or an empty host.
  /// Typically a host serves as a network address, but it is sometimes used as opaque identifier in URLs where a network address is not necessary.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  /// https://url.spec.whatwg.org/#host-representation as of 14.06.2020
  ///
  var host: WebURLParser.Host? {
    get { return _storage.host }
    set {
      ensureUnique()
      _storage.host = newValue
    }
  }

  /// A URL’s port is either null or a 16-bit unsigned integer that identifies a networking port. It is initially null.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var port: UInt16? {
    get { return _storage.port }
    set {
      ensureUnique()
      _storage.port = newValue
    }
  }

  /// A URL’s path is a list of zero or more ASCII strings, usually identifying a location in hierarchical form. It is initially empty.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var path: [String] {
    get { return _storage.path }
    _modify {
      ensureUnique()
      yield &_storage.path
    }
    set {
      ensureUnique()
      _storage.path = newValue
    }
  }

  /// A URL’s query is either null or an ASCII string. It is initially null.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var query: String? {
    get { return _storage.query }
    set {
      ensureUnique()
      _storage.query = newValue
    }
  }

  /// A URL’s fragment is either null or an ASCII string that can be used for further processing on the resource the URL’s other components identify. It is initially null.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var fragment: String? {
    get { return _storage.fragment }
    set {
      ensureUnique()
      _storage.fragment = newValue
    }
  }

  /// A URL also has an associated cannot-be-a-base-URL flag. It is initially unset.
  ///
  /// https://url.spec.whatwg.org/#url-representation as of 14.06.2020
  ///
  var cannotBeABaseURL: Bool {
    get { return _storage.cannotBeABaseURL }
    set {
      ensureUnique()
      _storage.cannotBeABaseURL = newValue
    }
  }

  /// A parsed view of a URL's `query` string as a mutable collection of name-value pairs.
  ///
  /// Note that changing the URL's query string via this object uses the `application/x-www-form-urlencoded` percent-encoding
  /// set, rather than the typical query/special-query percent-encoding set used by the `query` property. Thus:
  ///
  /// ```swift
  /// var components = WebURLParser.parse("https://example.com/?a=b ~")
  /// print(components.serialized()) // https://example.com/?a=b%20~
  /// components.queryParameters.items.sort()
  /// print(components.serialized()) // https://example.com/?a=b+%7E
  /// ```
  ///
  var queryParameters: WebURLParser.QueryParameters? {
    get { return query?._withUTF8 { WebURLParser.QueryParameters(parsingUTF8: $0) } }
    set { query = newValue?.serialized }
  }

  // TODO:
  // URL also has an associated blob URL entry that is either null or a blob URL entry. It is initially null.
}

// Internal helpers.

extension WebURLParser.Components {

  /// Modifies URL components by parsing a given string from the desired parser state.
  ///
  @discardableResult
  mutating func modify<S>(_ input: S, stateOverride: WebURLParser.ParserState?) -> Bool where S: StringProtocol {
    ensureUnique()
    return input._withUTF8 {
      var buffer = [UInt8]()
      buffer.reserveCapacity(32)
      var callback = IgnoreValidationErrors()
      return WebURLParser._parse(
        $0, base: nil, url: _storage, stateOverride: stateOverride,
        workingBuffer: &buffer, callback: &callback
      )
    }
  }

  /// A URL cannot have a username/password/port if its host is null or the empty string, its cannot-be-a-base-URL flag is set, or its scheme is "file".
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous as seen on 14.06.2020
  ///
  var cannotHaveCredentialsOrPort: Bool {
    return host == nil || host == .empty || self.cannotBeABaseURL || scheme == .file
  }

  /// Copies the username, password, host and port fields from `other`.
  ///
  fileprivate mutating func copyAuthority(from other: Self) {
    self.username = other.username
    self.password = other.password
    self.host = other.host
    self.port = other.port
  }

  func serialized(excludeFragment: Bool = false) -> String {
    var result = ""
    result.append(self.scheme.rawValue)
    result.append(":")

    if let host = self.host {
      result.append("//")
      if self._storage.hasCredentials {
        result.append(self.username)
        if !self.password.isEmpty {
          result.append(":")
          result.append(self.password)
        }
        result.append("@")
      }
      result.append(host.serialized)
      if let port = self.port {
        result.append(":")
        result.append(String(port))
      }
    } else if self.scheme == .file {
      result.append("//")
    }

    if self.cannotBeABaseURL {
      if self.path.isEmpty == false {
        result.append(self.path[0])
      }
    } else {
      for pathComponent in self.path {
        result.append("/\(pathComponent)")
      }
    }

    if let query = self.query {
      result.append("?\(query)")
    }
    if let fragment = self.fragment, excludeFragment == false {
      result.append("#\(fragment)")
    }
    return result
  }
}

extension WebURLParser {

  enum ParserState {
    case schemeStart
    case scheme
    case noScheme
    case specialRelativeOrAuthority
    case pathOrAuthority
    case relative
    case relativeSlash
    case specialAuthoritySlashes
    case specialAuthorityIgnoreSlashes
    case authority
    case host
    case hostname
    case port
    case file
    case fileSlash
    case fileHost
    case pathStart
    case path
    case cannotBeABaseURLPath
    case query
    case fragment
  }

  public struct ValidationError: Equatable {
    private var code: UInt8
    private var hostParserError: AnyHostParserError? = nil

    enum AnyHostParserError: Equatable, CustomStringConvertible {
      case ipv4AddressError(IPv4Address.ValidationError)
      case ipv6AddressError(IPv6Address.ValidationError)
      case opaqueHostError(OpaqueHost.ValidationError)
      case hostParserError(WebURLParser.Host.ValidationError)

      var description: String {
        switch self {
        case .ipv4AddressError(let error):
          return error.description
        case .ipv6AddressError(let error):
          return error.description
        case .opaqueHostError(let error):
          return error.description
        case .hostParserError(let error):
          return error.description
        }
      }
    }

    // Errors and descriptions are at the end of the file.
  }
}

/// An object which is informed by the URL parser if a validation error occurs.
///
/// Most validation errors are non-fatal and parsing can continue regardless. If parsing fails, the last
/// validation error typically describes the issue which caused it to fail.
///
public protocol URLParserCallback: IPv6AddressParserCallback, IPv4ParserCallback {
  mutating func validationError(_ error: WebURLParser.ValidationError)
}

// Wrap host-parser errors in an 'AnyHostParserError'.
extension URLParserCallback {
  // IP address errors.
  public mutating func validationError(ipv4 error: IPv4Address.ValidationError) {
    let wrapped = WebURLParser.ValidationError.AnyHostParserError.ipv4AddressError(error)
    validationError(.hostParserError(wrapped))
  }
  public mutating func validationError(ipv6 error: IPv6Address.ValidationError) {
    let wrapped = WebURLParser.ValidationError.AnyHostParserError.ipv6AddressError(error)
    validationError(.hostParserError(wrapped))
  }
  // Other host-parser errors.
  public mutating func validationError(hostParser error: WebURLParser.Host.ValidationError) {
    let wrapped = WebURLParser.ValidationError.AnyHostParserError.hostParserError(error)
    validationError(.hostParserError(wrapped))
  }
  public mutating func validationError(opaqueHost error: OpaqueHost.ValidationError) {
    let wrapped = WebURLParser.ValidationError.AnyHostParserError.opaqueHostError(error)
    validationError(.hostParserError(wrapped))
  }
}
extension WebURLParser.ValidationError {
  var ipv6Error: IPv6Address.ValidationError? {
    guard case .some(.ipv6AddressError(let error)) = self.hostParserError else { return nil }
    return error
  }
}

/// A `URLParserCallback` which simply ignores all validation errors.
///
public struct IgnoreValidationErrors: URLParserCallback {
  @inlinable @inline(__always) public init() {}
  @inlinable @inline(__always) public mutating func validationError(_ error: WebURLParser.ValidationError) {}
}

/// A `URLParserCallback` which stores the last reported validation error.
///
public struct LastValidationError: URLParserCallback {
  public var error: WebURLParser.ValidationError?
  @inlinable @inline(__always) public init() {}
  @inlinable @inline(__always) public mutating func validationError(_ error: WebURLParser.ValidationError) {
    self.error = error
  }
}

/// A `URLParserCallback` which stores all reported validation errors in an `Array`.
///
public struct CollectValidationErrors: URLParserCallback {
  public var errors: [WebURLParser.ValidationError] = []
  @inlinable @inline(__always) public init() { errors.reserveCapacity(8) }
  @inlinable @inline(__always) public mutating func validationError(_ error: WebURLParser.ValidationError) {
    errors.append(error)
  }
}

// Parser entry-points.

extension WebURLParser {

  // Parse, ignoring validation errors.

  static func parse<S>(
    _ input: S, base: String? = nil
  ) -> Components? where S: StringProtocol {
    var buffer = [UInt8]()
    buffer.reserveCapacity(64)
    if let baseString = base, baseString.isEmpty == false {
      if let baseComps = parse_impl(baseString, baseURL: nil, workingBuffer: &buffer) {
        return parse_impl(input, baseURL: baseComps, workingBuffer: &buffer)
      } else {
        return nil
      }
    }
    return parse_impl(input, baseURL: nil, workingBuffer: &buffer)
  }

  static func parse<S>(
    _ input: S, baseURL: Components?
  ) -> Components? where S: StringProtocol {
    var buffer = [UInt8]()
    buffer.reserveCapacity(64)
    return parse_impl(input, baseURL: baseURL, workingBuffer: &buffer)
  }

  private static func parse_impl<S>(
    _ input: S, baseURL: Components?, workingBuffer: inout [UInt8]
  ) -> Components? where S: StringProtocol {
    return input._withUTF8 {
      let result = Components()
      var callback = IgnoreValidationErrors()
      return _parse(
        $0, base: baseURL, url: result._storage, stateOverride: nil,
        workingBuffer: &workingBuffer, callback: &callback
      ) ? result : nil
    }
  }

  // Parse, reporting validation errors.

  struct Result {
    var components: Components?
    var validationErrors: [ValidationError]
  }

  static func parseAndReport<S>(
    _ input: S, base: String? = nil
  ) -> (url: Result?, base: Result?) where S: StringProtocol {
    var buffer = [UInt8]()
    buffer.reserveCapacity(64)
    if let baseString = base, baseString.isEmpty == false {
      let baseResult = parseAndReport_impl(baseString, baseURL: nil, workingBuffer: &buffer)
      if let baseComponents = baseResult.components {
        return (parseAndReport_impl(input, baseURL: baseComponents, workingBuffer: &buffer), baseResult)
      } else {
        return (nil, baseResult)
      }
    }
    return (parseAndReport_impl(input, baseURL: nil, workingBuffer: &buffer), nil)
  }

  static func parseAndReport<S>(
    _ input: S, baseURL: Components?
  ) -> Result where S: StringProtocol {
    var buffer = [UInt8]()
    buffer.reserveCapacity(64)
    return parseAndReport_impl(input, baseURL: baseURL, workingBuffer: &buffer)
  }

  private static func parseAndReport_impl<S>(
    _ input: S, baseURL: Components?, workingBuffer: inout [UInt8]
  ) -> Result where S: StringProtocol {
    return input._withUTF8 { utf8 in
      var callback = CollectValidationErrors()
      let components = Components()
      return Result(
        components: _parse(
          utf8, base: baseURL, url: components._storage, stateOverride: nil,
          workingBuffer: &workingBuffer, callback: &callback) ? components : nil,
        validationErrors: callback.errors
      )
    }
  }
}

// Parsing algorithm.

extension WebURLParser {

  /// The "Basic URL Parser" algorithm described by:
  /// https://url.spec.whatwg.org/#url-parsing as of 14.06.2020
  ///
  /// - parameters:
  /// 	- input:          A String, as a Collection of UTF8-encoded bytes. Null-termination is not required.
  ///     - base:           The base URL, if `input` is a relative URL string.
  ///     - url:            The URL storage to hold the parser's results.
  ///     - stateOverride:  The starting state of the parser. Used when modifying a URL.
  ///     - workingBuffer:  A uniquely-referenced array for the parser to use as a scratchpad.
  ///     - callback:       A callback for handling any validation errors that occur.
  /// - returns:	`true` if the input was parsed successfully (in which case, `url` has been modified with the results),
  ///  			 or `false` if the input could not be parsed.
  ///
  fileprivate static func _parse<Source, Callback>(
    _ input: Source, base: Components?, url: Components.Storage,
    stateOverride: ParserState?, workingBuffer: inout [UInt8],
    callback: inout Callback
  ) -> Bool where Source: BidirectionalCollection, Source.Element == UInt8, Callback: URLParserCallback {

    var input = input[...]

    // 1. Trim leading/trailing C0 control characters and spaces.
    if stateOverride == nil {
      let trimmedInput = input.trim {
        switch ASCII($0) {
        case ASCII.ranges.controlCharacters?, .space?: return true
        default: return false
        }
      }
      if trimmedInput.startIndex != input.startIndex || trimmedInput.endIndex != input.endIndex {
        callback.validationError(.unexpectedC0ControlOrSpace)
      }
      input = trimmedInput
    }

    // 2. Remove all ASCII newlines and tabs.
    func isASCIITabOrNewline(_ byte: UInt8) -> Bool {
      switch ASCII(byte) {
      case .horizontalTab?, .lineFeed?, .carriageReturn?: return true
      default:
        _onFastPath()
        return false
      }
    }
    if input.contains(where: isASCIITabOrNewline) {
      callback.validationError(.unexpectedASCIITabOrNewline)
      // FIXME: `.lazy.filter` isn't correct for this, because it will check every call to `index(after:)`,
      //        including inside unicode byte sequence checks. This should actually be our *non-unicode* `index(after:)`.
      return _parse_stateMachine(
        input.trim(where: isASCIITabOrNewline).lazy.filter { isASCIITabOrNewline($0) == false },
        base: base, url: url, stateOverride: stateOverride,
        workingBuffer: &workingBuffer, callback: &callback)
    } else {
      return _parse_stateMachine(
        input, base: base, url: url,
        stateOverride: stateOverride, workingBuffer: &workingBuffer, callback: &callback)
    }
  }

  private static func _parse_stateMachine<Source, Callback>(
    _ input: Source, base: Components?, url: Components.Storage,
    stateOverride: ParserState?, workingBuffer buffer: inout [UInt8],
    callback: inout Callback
  ) -> Bool where Source: Collection, Source.Element == UInt8, Callback: URLParserCallback {

    // 3. Begin state machine.
    var state = stateOverride ?? .schemeStart

    var idx = input.startIndex
    let endIndex = input.endIndex
    var flag_at = false  // @flag in spec.
    var flag_passwordTokenSeen = false  // passwordTokenSeenFlag in spec.
    var flag_squareBracket = false  // [] flag in spec.

    buffer.removeAll(keepingCapacity: true)

    inputLoop: while true {
      stateMachine: switch state {
      // Within this switch statement:
      // - inputLoop runs the switch, then advances `idx`, if `idx != input.endIndex`.
      // - stateMachine switches on `state`. It *will* see `idx == endIndex`,
      //   which turns out to be important in some of the parsing logic.
      //
      // In plain English:
      // - `break stateMachine` means "we're done processing this character, exit the switch and let inputLoop advance to the character"
      // - `break inputLoop`    means "we're done processing 'input', return whatever we have (not a failure)".
      //                        typically comes up with `stateOverride`.
      // - `return false`       means failure.
      // - `continue`           means "loop over inputLoop again, from the beginning (**without** first advancing the character)"

      case .schemeStart:
        // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx]) ?? .null : .null
        switch c {
        case _ where c.isAlpha:
          buffer.append(c.lowercased.codePoint)
          state = .scheme
          break stateMachine
        default:
          guard stateOverride == nil else {
            callback.validationError(.invalidSchemeStart)
            return false
          }
          state = .noScheme
          continue  // Do not advance index. Non-ASCII characters go through this path.
        }

      case .scheme:
        // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx]) ?? .null : .null
        switch c {
        case _ where c.isAlphaNumeric, .plus, .minus, .period:
          buffer.append(c.lowercased.codePoint)
          break stateMachine
        case .colon:
          break  // Handled below.
        default:
          guard stateOverride == nil else {
            callback.validationError(.invalidScheme)
            return false
          }
          buffer.removeAll(keepingCapacity: true)
          state = .noScheme
          idx = input.startIndex
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }
        assert(c == .colon)
        let newScheme = WebURLParser.Scheme.parse(asciiBytes: buffer)
        if stateOverride != nil {
          if url.scheme.isSpecial != newScheme.isSpecial {
            break inputLoop
          }
          if newScheme == .file && (url.hasCredentials || url.port != nil) {
            break inputLoop
          }
          if url.scheme == .file && (url.host?.isEmpty ?? true) {
            break inputLoop
          }
        }
        url.scheme = newScheme
        buffer.removeAll(keepingCapacity: true)
        if stateOverride != nil {
          if url.port == url.scheme.defaultPort {
            url.port = nil
          }
          break inputLoop
        }
        switch url.scheme {
        case .file:
          state = .file
          let nextIdx = input.index(after: idx)
          if !URLStringUtils.hasDoubleSolidusPrefix(input[nextIdx...]) {
            callback.validationError(.fileSchemeMissingFollowingSolidus)
          }
        case .other:
          let nextIdx = input.index(after: idx)
          if nextIdx != endIndex, ASCII(input[nextIdx]) == .forwardSlash {
            state = .pathOrAuthority
            idx = nextIdx
          } else {
            url.cannotBeABaseURL = true
            url.path.append("")
            state = .cannotBeABaseURLPath
          }
        default:
          if base?.scheme == url.scheme {
            state = .specialRelativeOrAuthority
          } else {
            state = .specialAuthoritySlashes
          }
        }

      case .noScheme:
        // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx]) ?? .null : .null
        guard let base = base else {
          callback.validationError(.missingSchemeNonRelativeURL)
          return false
        }
        guard base.cannotBeABaseURL == false else {
          guard c == ASCII.numberSign else {
            callback.validationError(.missingSchemeNonRelativeURL)
            return false  // Non-ASCII characters get rejected here.
          }
          url.scheme = base.scheme
          url.path = base.path
          url.query = base.query
          url.fragment = ""
          url.cannotBeABaseURL = true
          state = .fragment
          break stateMachine
        }
        if base.scheme == .file {
          state = .file
        } else {
          state = .relative
        }
        continue  // Do not increment index. Non-ASCII characters go through this path.

      case .specialRelativeOrAuthority:
        guard URLStringUtils.hasDoubleSolidusPrefix(input[idx...]) else {
          callback.validationError(.relativeURLMissingBeginningSolidus)
          state = .relative
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }
        state = .specialAuthorityIgnoreSlashes
        idx = input.index(after: idx)

      case .pathOrAuthority:
        guard idx != endIndex, ASCII(input[idx]) == .forwardSlash else {
          state = .path
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }
        state = .authority

      case .relative:
        guard let base = base else {
          // Note: The spec doesn't say what happens here if base is nil.
          callback.validationError(._baseURLRequired)
          return false
        }
        url.scheme = base.scheme
        guard idx != endIndex else {
          url.copyAuthority(from: base._storage)
          url.path = base.path
          url.query = base.query
          break stateMachine
        }
        // Erase non-ASCII characters to `ASCII.null`.
        let c: ASCII = ASCII(input[idx]) ?? .null
        switch c {
        case .backslash where url.scheme.isSpecial:
          callback.validationError(.unexpectedReverseSolidus)
          state = .relativeSlash
        case .forwardSlash:
          state = .relativeSlash
        case .questionMark:
          url.copyAuthority(from: base._storage)
          url.path = base.path
          url.query = ""
          state = .query
        case .numberSign:
          url.copyAuthority(from: base._storage)
          url.path = base.path
          url.query = base.query
          url.fragment = ""
          state = .fragment
        default:
          url.copyAuthority(from: base._storage)
          url.path = base.path
          if url.path.isEmpty == false {
            url.path.removeLast()
          }
          url.query = nil
          state = .path
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }

      case .relativeSlash:
        // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx]) ?? .null : .null
        switch c {
        case .forwardSlash:
          if url.scheme.isSpecial {
            state = .specialAuthorityIgnoreSlashes
          } else {
            state = .authority
          }
        case .backslash where url.scheme.isSpecial:
          callback.validationError(.unexpectedReverseSolidus)
          state = .specialAuthorityIgnoreSlashes
        default:
          guard let base = base else {
            callback.validationError(._baseURLRequired)
            return false
          }
          url.copyAuthority(from: base._storage)
          state = .path
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }

      case .specialAuthoritySlashes:
        state = .specialAuthorityIgnoreSlashes
        guard URLStringUtils.hasDoubleSolidusPrefix(input[idx...]) else {
          callback.validationError(.missingSolidusBeforeAuthority)
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }
        idx = input.index(after: idx)

      case .specialAuthorityIgnoreSlashes:
        // Erase 'endIndex' and non-ASCII characters to `ASCII.null`.
        // `c` is only checked against known ASCII values and never copied to the result.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx]) ?? .null : .null
        guard c == .forwardSlash || c == .backslash else {
          state = .authority
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }
        callback.validationError(.missingSolidusBeforeAuthority)

      case .authority:
        // Erase 'endIndex' to `ASCII.forwardSlash`, as they are handled the same,
        // and `c` is not copied to the result in that case. Do not erase non-ASCII code-points.
        let c: ASCII? = (idx != endIndex) ? ASCII(input[idx]) : ASCII.forwardSlash
        switch c {
        case .commercialAt?:
          callback.validationError(.unexpectedCommercialAt)
          if flag_at {
            buffer.insert(contentsOf: "%40".utf8, at: buffer.startIndex)
          }
          flag_at = true
          // Parse username and password out of "buffer".
          // `flag_passwordTokenSeen` being true means that while looking ahead for the end of the host,
          // we found another '@'; meaning the _first_ '@' was actually part of the password.
          // e.g. "scheme://user:hello@world@stuff" - the password is actually "hello@world", not "hello".
          if flag_passwordTokenSeen {
            PercentEscaping.encodeIterativelyAsString(
              bytes: buffer,
              escapeSet: .url_userInfo,
              processChunk: { piece in url.password.append(piece) }
            )
          } else {
            let passwordTokenIndex = buffer.firstIndex(where: { $0 == ASCII.colon })
            let passwordStartIndex = passwordTokenIndex.flatMap { buffer.index(after: $0) }
            PercentEscaping.encodeIterativelyAsString(
              bytes: buffer[..<(passwordTokenIndex ?? buffer.endIndex)],
              escapeSet: .url_userInfo,
              processChunk: { piece in url.username.append(piece) }
            )
            PercentEscaping.encodeIterativelyAsString(
              bytes: buffer[(passwordStartIndex ?? buffer.endIndex)...],
              escapeSet: .url_userInfo,
              processChunk: { piece in url.password.append(piece) }
            )
            flag_passwordTokenSeen = (passwordTokenIndex != nil)
          }
          buffer.removeAll(keepingCapacity: true)
        case ASCII.forwardSlash?, ASCII.questionMark?, ASCII.numberSign?,
          ASCII.backslash? where url.scheme.isSpecial:
          if flag_at, buffer.isEmpty {
            callback.validationError(.unexpectedCredentialsWithoutHost)
            return false
          }
          idx = input.index(idx, offsetBy: -1 * buffer.count)
          buffer.removeAll(keepingCapacity: true)
          state = .host
          continue  // Do not increment index.
        default:
          // This may be a non-ASCII codePoint. Append the whole thing to `buffer`.
          guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
            callback.validationError(._invalidUTF8)
            return false
          }
          buffer.append(contentsOf: codePoint)
          idx = codePoint.endIndex
          continue  // We already skipped `idx` to the end of the code-point.
        }
      case .hostname, .host:
        guard !(stateOverride != nil && url.scheme == .file) else {
          state = .fileHost
          continue  // Do not increment index.
        }
        // Erase 'endIndex' to `ASCII.forwardSlash`, as they are handled the same,
        // and `c` is not copied to the result in that case. Do not erase non-ASCII code-points.
        let c: ASCII? = (idx != endIndex) ? ASCII(input[idx]) : ASCII.forwardSlash
        switch c {
        case .colon? where flag_squareBracket == false:
          guard buffer.isEmpty == false else {
            callback.validationError(.unexpectedPortWithoutHost)
            return false
          }
          // swift-format-ignore
          guard let parsedHost = buffer.withUnsafeBufferPointer({
              WebURLParser.Host.parse($0, isNotSpecial: url.scheme.isSpecial == false, callback: &callback)
          }) else {
            return false
          }
          url.host = parsedHost
          buffer.removeAll(keepingCapacity: true)
          state = .port
          if stateOverride == .hostname { break inputLoop }
        case .forwardSlash?, .questionMark?, .numberSign?, /* or endIndex */
          .backslash? where url.scheme.isSpecial:
          if buffer.isEmpty {
            if url.scheme.isSpecial {
              callback.validationError(.emptyHostSpecialScheme)
              return false
            } else if stateOverride != nil, (url.hasCredentials || url.port != nil) {
              callback.validationError(.hostInvalid)
              break inputLoop
            }
          }
          // swift-format-ignore
          guard let parsedHost = buffer.withUnsafeBufferPointer({
              WebURLParser.Host.parse($0, isNotSpecial: url.scheme.isSpecial == false, callback: &callback)
          }) else {
            return false
          }
          url.host = parsedHost
          buffer.removeAll(keepingCapacity: true)
          state = .pathStart
          if stateOverride != nil { break inputLoop }
          continue  // Do not increment index.
        case .leftSquareBracket?:
          flag_squareBracket = true
          buffer.append(ASCII.leftSquareBracket.codePoint)
        case .rightSquareBracket?:
          flag_squareBracket = false	
          buffer.append(ASCII.rightSquareBracket.codePoint)
        default:
          // This may be a non-ASCII codePoint. Append the whole thing to `buffer`.
          guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
            callback.validationError(._invalidUTF8)
            return false
          }
          buffer.append(contentsOf: codePoint)
          idx = codePoint.endIndex
          continue  // We already skipped `idx` to the end of the code-point.
        }

      case .port:
        // Erase 'endIndex' to `ASCII.forwardSlash` as it is handled the same and not copied to output.
        // Erase non-ASCII characters to `ASCII.null` as this state checks for specific ASCII characters/EOF.
        // `c` is only copied if it is known to be within an allowed ASCII range.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx]) ?? ASCII.null : ASCII.forwardSlash
        switch c {
        case ASCII.ranges.digits:
          buffer.append(c.codePoint)
        case .forwardSlash, .questionMark, .numberSign,
          .backslash where url.scheme.isSpecial, _ where stateOverride != nil:
          if buffer.isEmpty == false {
            guard let parsedInteger = UInt16(String(decoding: buffer, as: UTF8.self)) else {
              callback.validationError(.portOutOfRange)
              return false
            }
            url.port = (parsedInteger == url.scheme.defaultPort) ? nil : parsedInteger
            buffer.removeAll(keepingCapacity: true)
          }
          if stateOverride != nil { break inputLoop }
          state = .pathStart
          continue  // Do not increment index. Non-ASCII characters go through this path.
        default:
          callback.validationError(.portInvalid)
          return false
        }

      case .file:
        url.scheme = .file
        if idx != endIndex, let c = ASCII(input[idx]), (c == .forwardSlash || c == .backslash) {
          if c == .backslash {
            callback.validationError(.unexpectedReverseSolidus)
          }
          state = .fileSlash
          break stateMachine
        }
        guard let base = base, base.scheme == .file else {
          state = .path
          continue  // Do not increment index.
        }
        url.host = base.host
        url.path = base.path
        url.query = base.query
        guard idx != endIndex else {
          break stateMachine
        }
        switch ASCII(input[idx]) {
        case .questionMark?:
          url.query = ""
          state = .query
        case .numberSign?:
          url.fragment = ""
          state = .fragment
        default:
          url.query = nil
          if URLStringUtils.hasWindowsDriveLetterPrefix(input[idx...]) {
            callback.validationError(.unexpectedWindowsDriveLetter)
            url.host = nil
            url.path = []
          } else {
            shortenURLPath(&url.path, isFileScheme: true)
          }
          state = .path
          continue  // Do not increment index. Non-ASCII characters go through this path.
        }

      case .fileSlash:
        if idx != endIndex, let c = ASCII(input[idx]), (c == .forwardSlash || c == .backslash) {
          if c == .backslash {
            callback.validationError(.unexpectedReverseSolidus)
          }
          state = .fileHost
          break stateMachine
        }
        if let base = base, base.scheme == .file,
          URLStringUtils.hasWindowsDriveLetterPrefix(input[idx...]) == false
        {
          if let basePathStart = base.path.first, URLStringUtils.isNormalisedWindowsDriveLetter(basePathStart.utf8) {
            url.path.append(basePathStart)
          } else {
            url.host = base.host
          }
        }
        state = .path
        continue  // Do not increment index. Non-ASCII characters go through this path.

      case .fileHost:
        // Erase 'endIndex' to `ASCII.forwardSlash` as it is handled the same and not copied to output.
        // Do not erase non-ASCII characters.
        let c: ASCII? = (idx != endIndex) ? ASCII(input[idx]) : ASCII.forwardSlash
        switch c {
        case .forwardSlash?, .backslash?, .questionMark?, .numberSign?:  // or endIndex.
          if stateOverride == nil, URLStringUtils.isWindowsDriveLetter(buffer) {
            callback.validationError(.unexpectedWindowsDriveLetterHost)
            state = .path
            // Note: buffer is intentionally not reset and used in the path-parsing state.
          } else if buffer.isEmpty {
            url.host = .empty
            if stateOverride != nil { break inputLoop }
            state = .pathStart
          } else {
            // swift-format-ignore
            guard let parsedHost = buffer.withUnsafeBufferPointer({
                WebURLParser.Host.parse($0, isNotSpecial: false, callback: &callback)
            }) else {
              return false
            }
            url.host = (parsedHost == .domain("localhost")) ? .empty : parsedHost
            if stateOverride != nil { break inputLoop }
            buffer.removeAll(keepingCapacity: true)
            state = .pathStart
          }
          continue  // Do not increment index.
        default:
          // This may be a non-ASCII codePoint. Append the whole thing to `buffer`.
          guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
            callback.validationError(._invalidUTF8)
            return false
          }
          buffer.append(contentsOf: codePoint)
          idx = codePoint.endIndex
          continue  // We already skipped `idx` to the end of the code-point.
        }

      case .pathStart:
        guard idx != endIndex else {
          if url.scheme.isSpecial {
            state = .path
            continue  // Do not increment index.
          } else {
            break stateMachine
          }
        }
        // Erase non-ASCII characters to `ASCII.null` as this state checks for specific ASCII characters/EOF.
        let c: ASCII = ASCII(input[idx]) ?? ASCII.null
        switch c {
        case _ where url.scheme.isSpecial:
          if c == .backslash {
            callback.validationError(.unexpectedReverseSolidus)
          }
          state = .path
          if (c == .forwardSlash || c == .backslash) == false {
            continue  // Do not increment index. Non-ASCII characters go through this path.
          } else {
            break stateMachine
          }
        case .questionMark where stateOverride == nil:
          url.query = ""
          state = .query
        case .numberSign where stateOverride == nil:
          url.fragment = ""
          state = .fragment
        default:
          state = .path
          if c != .forwardSlash {
            continue  // Do not increment index. Non-ASCII characters go through this path.
          }
        }

      case .path:
        let isPathComponentTerminator: Bool =
          (idx == endIndex) || (input[idx] == ASCII.forwardSlash)
          || (input[idx] == ASCII.backslash && url.scheme.isSpecial)
          || (stateOverride == nil && (input[idx] == ASCII.questionMark || input[idx] == ASCII.numberSign))

        guard isPathComponentTerminator else {
          // This may be a non-ASCII codePoint.
          guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
            callback.validationError(._invalidUTF8)
            return false
          }
          if URLStringUtils.hasNonURLCodePoints(codePoint, allowPercentSign: true) {
            callback.validationError(.invalidURLCodePoint)
          }
          if ASCII(input[idx]) == .percentSign {
            let nextTwo = input[idx...].dropFirst().prefix(2)
            if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
              callback.validationError(.unescapedPercentSign)
            }
          }
          PercentEscaping.encodeAsBuffer(
            singleUTF8CodePoint: codePoint,
            escapeSet: .url_path,
            processResult: { piece in buffer.append(contentsOf: piece) }
          )
          idx = codePoint.endIndex
          continue  // We already skipped `idx` to the end of the code-point.
        }
        // From here, we know:
        // - idx == endIndex, or
        // - input[idx] is one of a specific set of allowed ASCII characters
        //     (forwardSlash, backslash, questionMark or numberSign), and
        // - if input[idx] is ASCII.backslash, it implies url.isSpecial.
        //
        // To simplify bounds-checking in the following logic, we will encode
        // the state (idx == endIndex) by the ASCII.null character.
        let c: ASCII = (idx != endIndex) ? ASCII(input[idx])! : ASCII.null
        if c == .backslash {
          callback.validationError(.unexpectedReverseSolidus)
        }
        switch buffer {
        case _ where URLStringUtils.isDoubleDotPathSegment(buffer):
          shortenURLPath(&url.path, isFileScheme: url.scheme == .file)
          fallthrough
        case _ where URLStringUtils.isSingleDotPathSegment(buffer):
          if !(c == .forwardSlash || c == .backslash) {
            url.path.append("")
          }
        default:
          if url.scheme == .file, url.path.isEmpty, URLStringUtils.isWindowsDriveLetter(buffer) {
            if !(url.host == nil || url.host == .empty) {
              callback.validationError(.unexpectedHostFileScheme)
              url.host = .empty
            }
            let secondChar = buffer.index(after: buffer.startIndex)
            buffer[secondChar] = ASCII.colon.codePoint
          }
          url.path.append(String(decoding: buffer, as: UTF8.self))
        }
        buffer.removeAll(keepingCapacity: true)
        if url.scheme == .file, (c == .null /* endIndex */ || c == .questionMark || c == .numberSign) {
          while url.path.count > 1, url.path[0].isEmpty {
            callback.validationError(.unexpectedEmptyPath)
            url.path.removeFirst()
          }
        }
        switch c {
        case .questionMark:
          url.query = ""
          state = .query
        case .numberSign:
          url.fragment = ""
          state = .fragment
        default:
          break
        }

      case .cannotBeABaseURLPath:
        func flushBuffer() {
          PercentEscaping.encodeIterativelyAsString(
            bytes: buffer,
            escapeSet: .url_c0,
            processChunk: { piece in url.path[0].append(piece) }
          )
          buffer.removeAll(keepingCapacity: true)
        }

        guard idx != endIndex else {
          flushBuffer()
          break stateMachine
        }
        switch ASCII(input[idx]) {
        case .questionMark?:
          url.query = ""
          state = .query
          flushBuffer()
        case .numberSign?:
          url.fragment = ""
          state = .fragment
          flushBuffer()
        default:
          // This may be a non-ASCII codePoint.
          guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
            callback.validationError(._invalidUTF8)
            return false
          }
          if URLStringUtils.hasNonURLCodePoints(codePoint, allowPercentSign: true) {
            callback.validationError(.invalidURLCodePoint)
          }
          if ASCII(input[idx]) == .percentSign {
            let nextTwo = input[idx...].dropFirst().prefix(2)
            if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
              callback.validationError(.unescapedPercentSign)
            }
          }
          buffer.append(contentsOf: codePoint)
          idx = codePoint.endIndex
          continue  // We already skipped `idx` to the end of the code-point.
        }

      // Note: we only accept the UTF8 encoding option.
      // This parser doesn't even have an argument to choose anything else.
      case .query:
        func flushBuffer() {
          let urlIsSpecial = url.scheme.isSpecial
          let escapeSet = PercentEscaping.EscapeSet(shouldEscape: { asciiChar in
            switch asciiChar {
            case .doubleQuotationMark, .numberSign, .lessThanSign, .greaterThanSign,
              _ where asciiChar.codePoint < ASCII.exclamationMark.codePoint,
              _ where asciiChar.codePoint > ASCII.tilde.codePoint, .apostrophe where urlIsSpecial:
              return true
            default: return false
            }
          })
          PercentEscaping.encodeIterativelyAsString(
            bytes: buffer,
            escapeSet: escapeSet,
            processChunk: { escapedChar in
              if url.query == nil {
                url.query = escapedChar
              } else {
                url.query!.append(escapedChar)
              }
            })
          buffer.removeAll(keepingCapacity: true)
        }

        guard idx != endIndex else {
          flushBuffer()
          break stateMachine
        }
        if stateOverride == nil, ASCII(input[idx]) == .numberSign {
          url.fragment = ""
          state = .fragment
          flushBuffer()
          break stateMachine
        }
        // This may be a non-ASCII codePoint.
        guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
          callback.validationError(._invalidUTF8)
          return false
        }
        if URLStringUtils.hasNonURLCodePoints(codePoint, allowPercentSign: true) {
          callback.validationError(.invalidURLCodePoint)
        }
        if ASCII(input[idx]) == .percentSign {
          let nextTwo = input[idx...].dropFirst().prefix(2)
          if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
            callback.validationError(.unescapedPercentSign)
          }
        }
        buffer.append(contentsOf: codePoint)
        idx = codePoint.endIndex
        continue  // We already skipped `idx` to the end of the code-point.

      case .fragment:
        func flushBuffer() {
          PercentEscaping.encodeIterativelyAsString(
            bytes: buffer,
            escapeSet: .url_fragment,
            processChunk: { escapedChar in
              if url.fragment == nil {
                url.fragment = escapedChar
              } else {
                url.fragment!.append(escapedChar)
              }
            })
          buffer.removeAll(keepingCapacity: true)
        }

        guard idx != endIndex else {
          flushBuffer()
          break stateMachine
        }
        // This may be a non-ASCII codePoint.
        guard let codePoint = UTF8.rangeOfEncodedCodePoint(fromStartOf: input[idx...]) else {
          callback.validationError(._invalidUTF8)
          return false
        }
        if URLStringUtils.hasNonURLCodePoints(codePoint, allowPercentSign: true) {
          callback.validationError(.invalidURLCodePoint)
        }
        if ASCII(input[idx]) == .percentSign {
          let nextTwo = input[idx...].dropFirst().prefix(2)
          if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
            callback.validationError(.unescapedPercentSign)
          }
        }
        buffer.append(contentsOf: codePoint)
        idx = codePoint.endIndex
        continue  // We already skipped `idx` to the end of the code-point.

      }  // end of `stateMachine: switch state {`

      if idx == endIndex { break }
      assert(
        ASCII(input[idx]) != nil,
        """
           This should only be reached if we have an ASCII character.
           Other characters should have been funelled to a unicode-aware state,
           which should consume entire code-points until some other ASCII character.
        """)
      idx = input.index(after: idx)

    }  // end of `inputLoop: while true {`

    return true
  }

  private static func shortenURLPath(_ path: inout [String], isFileScheme: Bool) {
    guard path.isEmpty == false else { return }
    if isFileScheme, path.count == 1, URLStringUtils.isNormalisedWindowsDriveLetter(path[0].utf8) { return }
    path.removeLast()
  }
}

// Parser errors and descriptions.
// swift-format-ignore
extension WebURLParser.ValidationError: CustomStringConvertible {

  // Named errors and their descriptions/examples taken from:
  // https://github.com/whatwg/url/pull/502 on 15.06.2020
  internal static var unexpectedC0ControlOrSpace:         Self { Self(code: 0) }
  internal static var unexpectedASCIITabOrNewline:        Self { Self(code: 1) }
  internal static var invalidSchemeStart:                 Self { Self(code: 2) }
  internal static var fileSchemeMissingFollowingSolidus:  Self { Self(code: 3) }
  internal static var invalidScheme:                      Self { Self(code: 4) }
  internal static var missingSchemeNonRelativeURL:        Self { Self(code: 5) }
  internal static var relativeURLMissingBeginningSolidus: Self { Self(code: 6) }
  internal static var unexpectedReverseSolidus:           Self { Self(code: 7) }
  internal static var missingSolidusBeforeAuthority:      Self { Self(code: 8) }
  internal static var unexpectedCommercialAt:             Self { Self(code: 9) }
  internal static var unexpectedCredentialsWithoutHost:   Self { Self(code: 10) }
  internal static var unexpectedPortWithoutHost:          Self { Self(code: 11) }
  internal static var emptyHostSpecialScheme:             Self { Self(code: 12) }
  internal static var hostInvalid:                        Self { Self(code: 13) }
  internal static var portOutOfRange:                     Self { Self(code: 14) }
  internal static var portInvalid:                        Self { Self(code: 15) }
  internal static var unexpectedWindowsDriveLetter:       Self { Self(code: 16) }
  internal static var unexpectedWindowsDriveLetterHost:   Self { Self(code: 17) }
  internal static var unexpectedHostFileScheme:           Self { Self(code: 18) }
  internal static var unexpectedEmptyPath:                Self { Self(code: 19) }
  internal static var invalidURLCodePoint:                Self { Self(code: 20) }
  internal static var unescapedPercentSign:               Self { Self(code: 21) }

  internal static var hostParserError_errorCode: UInt8 = 22
  internal static func hostParserError(_ err: AnyHostParserError) -> Self {
      Self(code: hostParserError_errorCode, hostParserError: err)
  }
  // TODO: host-related errors. Map these to our existing host-parser errors.
  internal static var unclosedIPv6Address:                Self { Self(code: 22) }
  internal static var domainToASCIIFailure:               Self { Self(code: 23) }
  internal static var domainToASCIIEmptyDomainFailure:    Self { Self(code: 24) }
  internal static var hostForbiddenCodePoint:             Self { Self(code: 25) }
  // This one is not in the spec.
  internal static var _baseURLRequired:                   Self { Self(code: 99) }
  internal static var _invalidUTF8:                       Self { Self(code: 98) }

  public var description: String {
    switch self {
    case .unexpectedC0ControlOrSpace:
      return #"""
        The input to the URL parser contains a leading or trailing C0 control or space.
        The URL parser subsequently strips any matching code points.

        Example: " https://example.org "
        """#
    case .unexpectedASCIITabOrNewline:
      return #"""
        The input to the URL parser contains ASCII tab or newlines.
        The URL parser subsequently strips any matching code points.

        Example: "ht
        tps://example.org"
        """#
    case .invalidSchemeStart:
      return #"""
        The first code point of a URL’s scheme is not an ASCII alpha.

        Example: "3ttps://example.org"
        """#
    case .fileSchemeMissingFollowingSolidus:
      return #"""
        The URL parser encounters a URL with a "file" scheme that is not followed by "//".

        Example: "file:c:/my-secret-folder"
        """#
    case .invalidScheme:
      return #"""
        The URL’s scheme contains an invalid code point.

        Example: "^_^://example.org" and "https//example.org"
        """#
    case .missingSchemeNonRelativeURL:
      return #"""
        The input is missing a scheme, because it does not begin with an ASCII alpha,
        and either no base URL was provided or the base URL cannot be used as a base URL
        because its cannot-be-a-base-URL flag is set.

        Example (Input’s scheme is missing and no base URL is given):
        (url, base) = ("💩", nil)

        Example (Input’s scheme is missing, but the base URL’s cannot-be-a-base-URL flag is set):
        (url, base) = ("💩", "mailto:user@example.org")
        """#
    case .relativeURLMissingBeginningSolidus:
      return #"""
        The input is a relative-URL String that does not begin with U+002F (/).

        Example: (url, base) = ("foo.html", "https://example.org/")
        """#
    case .unexpectedReverseSolidus:
      return #"""
        The URL has a special scheme and it uses U+005C (\) instead of U+002F (/).

        Example: "https://example.org\path\to\file"
        """#
    case .missingSolidusBeforeAuthority:
      return #"""
        The URL includes credentials that are not preceded by "//".

        Example: "https:user@example.org"
        """#
    case .unexpectedCommercialAt:
      return #"""
        The URL includes credentials, however this is considered invalid.

        Example: "https://user@example.org"
        """#
    case .unexpectedCredentialsWithoutHost:
      return #"""
        A U+0040 (@) is found between the URL’s scheme and host, but the URL does not include credentials.

        Example: "https://@example.org"
        """#
    case .unexpectedPortWithoutHost:
      return #"""
        The URL contains a port, but no host.

        Example: "https://:443"
        """#
    case .emptyHostSpecialScheme:
      return #"""
        The URL has a special scheme, but does not contain a host.

        Example: "https://#fragment"
        """#
    case .hostInvalid:
      // FIXME: Javascript example.
      return #"""
        The host portion of the URL is an empty string when it includes credentials or a port and the basic URL parser’s state is overridden.

        Example:
          const url = new URL("https://example:9000");
          url.hostname = "";
        """#
    case .portOutOfRange:
      return #"""
        The input’s port is too big.

        Example: "https://example.org:70000"
        """#
    case .portInvalid:
      return #"""
        The input’s port is invalid.

        Example: "https://example.org:7z"
        """#
    case .unexpectedWindowsDriveLetter:
      return #"""
        The input is a relative-URL string that starts with a Windows drive letter and the base URL’s scheme is "file".

        Example: (url, base) = ("/c:/path/to/file", "file:///c:/")
        """#
    case .unexpectedWindowsDriveLetterHost:
      return #"""
        The file URL’s host is a Windows drive letter.

        Example: "file://c:"
        """#
    case .unexpectedHostFileScheme:
      // FIXME: Javascript example.
      return #"""
        The URL’s scheme is changed to "file" and the existing URL has a host.

        Example:
          const url = new URL("https://example.org");
          url.protocol = "file";
        """#
    case .unexpectedEmptyPath:
      return #"""
        The URL’s scheme is "file" and it contains an empty path segment.

        Example: "file:///c:/path//to/file"
        """#
    case .invalidURLCodePoint:
      return #"""
        A code point is found that is not a URL code point or U+0025 (%), in the URL’s path, query, or fragment.

        Example: "https://example.org/>"
        """#
    case .unescapedPercentSign:
      return #"""
        A U+0025 (%) is found that is not followed by two ASCII hex digits, in the URL’s path, query, or fragment.

        Example: "https://example.org/%s"
        """#
    case ._baseURLRequired:
      return #"""
        A base URL is required.
        """#
    case _ where self.code == Self.hostParserError_errorCode:
      return self.hostParserError!.description
    default:
      return "??"
    }
  }
}
