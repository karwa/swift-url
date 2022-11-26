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

/// A marker which identifies the URL component immediately following the scheme.
///
@usableFromInline
internal enum Sigil {
  case authority
  case path
}

/// Describes the structure of a normalized URL string.
///
/// The string must be of the format:
///
/// ```
/// [scheme + ":"] + [sigil]? + [username]? + [":" + password]? + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
/// ```
///
/// As well as their locations, this object contains information about the contents of some components -
/// for example, the kind of host, and the length of the first path component.
///
@usableFromInline
internal struct URLStructure<SizeType> where SizeType: FixedWidthInteger & UnsignedInteger {

  // Main component lengths.

  /// The length of the scheme, including trailing `:`.
  ///
  /// **Properties:**
  ///
  /// - Must be greater than 1. Every URL must have a non-empty scheme.
  ///
  @usableFromInline
  internal var schemeLength: SizeType

  /// The length of the username component, not including any leading or trailing delimiters.
  ///
  /// **Structural Properties:**
  ///
  /// - If 0, no username is present.
  ///
  /// - A username may only be present if the URL has an authority.
  ///
  /// - If at least one of `usernameLength` or `passwordLength` are non-zero, the URL has credentials,
  ///   and there must be a delimiter between them and the hostname (which must be present and non-empty).
  ///
  @usableFromInline
  internal var usernameLength: SizeType

  /// The length of the password component, including leading `:`.
  ///
  /// **Structural Properties:**
  ///
  /// - If 0, no password is present.
  ///   Note that a password may be present even if there is no username (e.g. `foo://:pass@host.com/`).
  ///
  /// - A password may only be present if the URL has an authority.
  ///
  /// - This value must not be exactly 1, as that would mean a delimiter with no content.
  ///   The normalized form is for empty passwords to be omitted, with no delimiter.
  ///
  /// - If at least one of `usernameLength` or `passwordLength` are non-zero, the URL has credentials,
  ///   and there must be a delimiter between them and the hostname (which must be present and non-empty).
  ///
  @usableFromInline
  internal var passwordLength: SizeType

  /// The length of the hostname component, not including any leading or trailing delimiters.
  ///
  /// **Structural Properties:**
  ///
  /// - If the URL has an authority sigil, a length of 0 indicates an empty hostname (e.g. `foo://?query`).
  ///
  /// - If the URL does not have an authority sigil, this component cannot be present.
  ///
  @usableFromInline
  internal var hostnameLength: SizeType

  /// The length of the port, including leading `:`.
  ///
  /// **Structural Properties:**
  ///
  /// - If 0, no port is present.
  ///
  /// - A port may only be present if the URL has an authority.
  ///
  /// - This value must not be exactly 1, as that would mean a delimiter with no content.
  ///   The normalized form is for empty port numbers to be omitted, with no delimiter.
  ///
  @usableFromInline
  internal var portLength: SizeType

  /// The length of the path, including leading `/` if present.
  ///
  /// **Structural Properties:**
  ///
  /// - The path is always present, although it may be empty.
  ///
  /// - The leading `/`, if present, is considered part of the path, not a delimiter.
  ///
  @usableFromInline
  internal var pathLength: SizeType

  /// The length of the query, including leading `?`.
  ///
  /// **Structural Properties:**
  ///
  /// - If 0, no query is present.
  ///
  @usableFromInline
  internal var queryLength: SizeType

  /// The length of the fragment, including leading `#`.
  ///
  /// **Structural Properties:**
  ///
  /// - If 0, no fragment is present.
  ///
  @usableFromInline
  internal var fragmentLength: SizeType

  // Flags and Sub-components.

  /// The length of the first path component.
  ///
  /// If 0, the path does not contain any components (i.e. the path is opaque or empty).
  ///
  @usableFromInline
  internal var firstPathComponentLength: SizeType

  /// See `.sigil` property
  ///
  @usableFromInline
  internal var __sigil: Optional<Sigil>

  /// A summary of this URL's `scheme`.
  ///
  /// Note that `SchemeKind` only distinguishes between different special schemes,
  /// and all non-special schemes are considered the same ("`.other`").
  ///
  /// While it is useful to quickly check if a URL is a file URL,
  /// two URLs with the same `schemeKind` _only_ have the same scheme **if they are both special**.
  ///
  @usableFromInline
  internal var schemeKind: WebURL.SchemeKind

  /// See `.hostKind` property
  ///
  @usableFromInline
  internal var __hostKind: Optional<WebURL.HostKind>

  /// Whether this URL has an opaque path.
  ///
  /// URLs with opaque paths are "everything-after-the-scheme-URLs";
  /// they do not have authority components (such as usernames, hostnames, or port numbers),
  /// and their path is just an opaque string rather than a list of components.
  ///
  /// Examples of URLs with opaque paths are `mailto:bob@example.com` and `javascript:alert("hello")`.
  ///
  @usableFromInline
  internal var hasOpaquePath: Bool

  /// Whether this URL's query string is known to be `application/x-www-form-urlencoded`.
  ///
  /// **Structural Properties:**
  ///
  /// - If `queryLength` is 0 or 1, this flag must be set.
  ///
  @usableFromInline
  internal var queryIsKnownFormEncoded: Bool

  @inlinable
  internal init(
    schemeLength: SizeType,
    usernameLength: SizeType,
    passwordLength: SizeType,
    hostnameLength: SizeType,
    portLength: SizeType,
    pathLength: SizeType,
    queryLength: SizeType,
    fragmentLength: SizeType,
    firstPathComponentLength: SizeType,
    sigil: Sigil?,
    schemeKind: WebURL.SchemeKind,
    hostKind: WebURL.HostKind?,
    hasOpaquePath: Bool,
    queryIsKnownFormEncoded: Bool
  ) {
    self.schemeLength = schemeLength
    self.usernameLength = usernameLength
    self.passwordLength = passwordLength
    self.hostnameLength = hostnameLength
    self.portLength = portLength
    self.pathLength = pathLength
    self.queryLength = queryLength
    self.fragmentLength = fragmentLength
    self.firstPathComponentLength = firstPathComponentLength
    self.__sigil = sigil
    self.schemeKind = schemeKind
    self.__hostKind = hostKind
    self.hasOpaquePath = hasOpaquePath
    self.queryIsKnownFormEncoded = queryIsKnownFormEncoded
  }
}

extension URLStructure {

  // These properties work around expensive 'outlined init with take' calls which occur in some simple getters.
  // Note that we don't see the same expensive runtime calls for setters.
  //
  // More information:
  // - https://github.com/apple/swift/issues/57537
  // - https://forums.swift.org/t/expensive-calls-to-outlined-init-with-take/52187

  /// The sigil, if present. The sigil comes immediately after the scheme's trailing delimiter
  /// and identifies the component(s) following it.
  ///
  /// **Structural Properties:**
  ///
  /// - If `sigil == .authority`:
  ///
  ///   The URL has an authority, and username/password/hostname/port components follow the sigil.
  ///
  /// - If `sigil == .path` or `sigil == .none`:
  ///
  ///   The URL has no authority, and a path/query/fragment follows the sigil.
  ///
  @inlinable @inline(__always)
  internal var sigil: Optional<Sigil> {
    get {
      guard let offset = MemoryLayout.offset(of: \Self.__sigil) else { return __sigil }
      return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<Sigil>.self) }
    }
    set {
      __sigil = newValue
    }
  }

  /// A summary of this URL's `host`.
  ///
  /// Note that `HostKind` only distinguishes the _kind_ of host this URL has.
  /// Two URLs with the same `hostKind` do not necessarily have the same host.
  ///
  @inlinable @inline(__always)
  internal var hostKind: Optional<WebURL.HostKind> {
    get {
      guard let offset = MemoryLayout.offset(of: \Self.__hostKind) else { return __hostKind }
      return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<WebURL.HostKind>.self) }
    }
    set {
      __hostKind = newValue
    }
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLStructure: Sendable where SizeType: Sendable {}
  extension Sigil: Sendable {}
#endif


// --------------------------------------------
// MARK: - Computed Flags
// --------------------------------------------


extension URLStructure {

  // Structural flags.

  /// Whether this URL has an authority.
  ///
  /// If `false`, no authority components may be present.
  ///
  @inlinable
  internal var hasAuthority: Bool {
    if case .authority = sigil {
      return true
    } else {
      return false
    }
  }

  /// Whether this URL's path requires a path sigil when no authority is present.
  ///
  @inlinable
  internal var pathRequiresSigil: Bool {
    firstPathComponentLength == 1 && pathLength > 1
  }

  /// Whether this URL contains an '@' delimiter between the end of the credentials and start of the hostname.
  ///
  @inlinable
  internal var hasCredentialSeparator: Bool {
    usernameLength != 0 || passwordLength != 0
  }

  /// Whether this URL has a username, password, or port number.
  ///
  @inlinable
  internal var hasCredentialsOrPort: Bool {
    usernameLength != 0 || passwordLength != 0 || portLength != 0
  }

  // Semantics flags.

  /// Whether this URL is forbidden from containing credentials or a port number.
  ///
  /// > A URL cannot have a username/password/port if its host is null or the empty string, or its scheme is "file".
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal var cannotHaveCredentialsOrPort: Bool {
    hostnameLength == 0 || schemeKind == .file
  }
}


// --------------------------------------------
// MARK: - Locations and Ranges
// --------------------------------------------


extension URLStructure {

  /// The location of the code-unit from which the scheme starts. Always 0.
  ///
  /// ```
  /// http://example/path?query#fragment
  /// ^
  /// ```
  ///
  @inlinable
  internal var schemeStart: SizeType {
    0
  }

  /// The location of the code-unit after the scheme's trailing delimiter.
  ///
  /// ```
  /// http://example/path?query#fragment
  ///      ^
  /// ```
  ///
  @inlinable
  internal var schemeEnd: SizeType {
    schemeStart &+ schemeLength
  }

  /// The location of the code-unit after the URL's sigil, if one is present.
  ///
  /// If `sigil == .authority`, the authority components have meaningful values
  /// and begin at this point; otherwise, the path begins here.
  ///
  /// ```
  /// [Authority sigil]
  /// http://user:pass@example/path?query#fragment
  ///        ^
  ///
  /// [Path sigil]
  /// scheme:/.//path-with-leading-slashes?query#fragment
  ///          ^
  ///
  /// [No sigil]
  /// scheme:/no-authority-path-only?query#fragment
  ///        ^
  /// scheme:opaque-path
  ///        ^
  /// ```
  ///
  @inlinable
  internal var afterSigil: SizeType {
    switch sigil {
    case .none: return schemeEnd
    case .path, .authority: return schemeEnd &+ 2
    }
  }

  // Locations of authority components.
  // If there is no authority, these should all equal 'afterSigil'.

  /// The location of the code-unit from which the username starts.
  ///
  /// ```
  /// http://user:pass@example/path?query#fragment
  ///        ^
  /// ```
  ///
  @inlinable
  internal var usernameStart: SizeType {
    afterSigil
  }

  /// The location of the code-unit which, if a password is present,
  /// contains the password component's leading delimiter.
  ///
  /// ```
  /// http://user:pass@example/path?query#fragment
  ///            ^
  /// ```
  ///
  @inlinable
  internal var passwordStart: SizeType {
    usernameStart &+ usernameLength
  }

  /// The location of the code-unit from which the hostname starts.
  ///
  /// ```
  /// http://user:pass@example.com/path?query#fragment
  ///                  ^
  /// ```
  ///
  @inlinable
  internal var hostnameStart: SizeType {
    passwordStart &+ passwordLength &+ (hasCredentialSeparator ? 1 : 0) /* @ */
  }

  /// The location of the code-unit which, if a port is present,
  /// contains the port component's leading delimiter.
  ///
  /// ```
  /// http://example:8080/path?query#fragment
  ///               ^
  /// ```
  ///
  @inlinable
  internal var portStart: SizeType {
    hostnameStart &+ hostnameLength
  }

  // Locations of other components.

  /// The location of the code-unit from which the path starts.
  ///
  /// If the path is hierarchical, its leading `/` is considered part of the path.
  ///
  /// ```
  /// [Has Authority]
  /// http://example/path?query#fragment
  ///               ^
  ///
  /// [No Authority]
  /// scheme:/no-authority-path-only?query#fragment
  ///        ^
  /// scheme:opaque-path
  ///        ^
  /// ```
  ///
  @inlinable
  internal var pathStart: SizeType {
    hasAuthority ? portStart &+ portLength : afterSigil
  }

  /// The location of the code-unit from which the query starts.
  ///
  /// If present, the first character of the query is '?'.
  ///
  /// ```
  /// http://example/path?query#fragment
  ///                    ^
  /// ```
  ///
  @inlinable
  internal var queryStart: SizeType {
    pathStart &+ pathLength
  }

  /// The location of the code-unit from which the fragment starts.
  ///
  /// If present, the first character of the fragment is "#".
  ///
  /// ```
  /// http://example/path?query#fragment
  ///                          ^
  /// ```
  ///
  @inlinable
  internal var fragmentStart: SizeType {
    queryStart &+ queryLength
  }

  // Ranges.

  /// The location of the sigil's code-units.
  ///
  /// If this URL does not have a sigil, this property returns an empty range
  /// at the location where the sigil _would_ go.
  ///
  @inlinable
  internal var rangeForReplacingSigil: Range<SizeType> {
    Range(uncheckedBounds: (schemeEnd, afterSigil))
  }

  /// The location of the code-units for a given URL component.
  ///
  /// If the component is not present, this function returns an empty range
  /// at the location where the component _would_ go.
  ///
  /// The returned range may include some leading or trailing delimiters,
  /// depending on the component.
  ///
  /// - important: Great care must be taken when replacing a component's code-units,
  ///              so as not to produce a non-normalized URL string.
  ///              Modifying one component may also require modifying other components.
  ///
  @inlinable
  internal func rangeForReplacingCodeUnits(of component: WebURL.Component) -> Range<SizeType> {

    checkInvariants()

    let (start, length): (SizeType, SizeType)
    switch component {
    case .scheme:
      (start, length) = (schemeStart, schemeLength)
    case .username:
      (start, length) = (usernameStart, usernameLength)
    case .password:
      (start, length) = (passwordStart, passwordLength)
    case .hostname:
      (start, length) = (hostnameStart, hostnameLength)
    case .port:
      (start, length) = (portStart, portLength)
    case .path:
      (start, length) = (pathStart, pathLength)
    case .query:
      (start, length) = (queryStart, queryLength)
    case .fragment:
      (start, length) = (fragmentStart, fragmentLength)
    default:
      fatalError("Unknown component")
    }
    return Range(uncheckedBounds: (start, start &+ length))
  }

  /// The location of the code-units for a given URL component, if it is present.
  ///
  /// The returned range may include some leading or trailing delimiters,
  /// depending on the component.
  ///
  @inlinable
  internal func range(of component: WebURL.Component) -> Range<SizeType>? {

    let range = rangeForReplacingCodeUnits(of: component)
    switch component {
    // Always present.
    case .scheme, .path:
      return range
    // Presence depends on authority sigil.
    case .hostname:
      return hasAuthority ? range : nil
    // For all other components, a length of 0 means "not present"/nil.
    default:
      return range.isEmpty ? nil : range
    }
  }
}


// --------------------------------------------
// MARK: - Conversions
// --------------------------------------------


extension URLStructure {

  /// Creates a URL structure with the same information as `other`,
  /// but whose values are stored using a different integer type.
  ///
  /// If the new integer type is not capable of exactly representing `other`,
  /// the initializer fails and returns `nil`.
  ///
  @inlinable
  internal init?<OtherSize>(converting other: URLStructure<OtherSize>) {

    if let sameType = other as? Self {
      self = sameType
      return
    }

    guard
      let schemeLength = SizeType(exactly: other.schemeLength),
      let usernameLength = SizeType(exactly: other.usernameLength),
      let passwordLength = SizeType(exactly: other.passwordLength),
      let hostnameLength = SizeType(exactly: other.hostnameLength),
      let portLength = SizeType(exactly: other.portLength),
      let pathLength = SizeType(exactly: other.pathLength),
      let queryLength = SizeType(exactly: other.queryLength),
      let fragmentLength = SizeType(exactly: other.fragmentLength),
      let firstPathComponentLength = SizeType(exactly: other.firstPathComponentLength)
    else {
      return nil
    }

    self.init(
      schemeLength: schemeLength,
      usernameLength: usernameLength,
      passwordLength: passwordLength,
      hostnameLength: hostnameLength,
      portLength: portLength,
      pathLength: pathLength,
      queryLength: queryLength,
      fragmentLength: fragmentLength,
      firstPathComponentLength: firstPathComponentLength,
      sigil: other.sigil,
      schemeKind: other.schemeKind,
      hostKind: other.hostKind,
      hasOpaquePath: other.hasOpaquePath,
      queryIsKnownFormEncoded: other.queryIsKnownFormEncoded
    )
    checkInvariants()
  }
}


// --------------------------------------------
// MARK: - Testing and Debugging
// --------------------------------------------


extension URLStructure {

  /// Whether this and `other` describe the same URL structure.
  ///
  /// This is useful for testing idempotence - re-parsing a normalized URL string should always
  /// produce the same structure.
  ///
  @usableFromInline
  internal func describesSameStructure(as other: Self) -> Bool {
    schemeLength == other.schemeLength && usernameLength == other.usernameLength
      && passwordLength == other.passwordLength && hostnameLength == other.hostnameLength
      && portLength == other.portLength && pathLength == other.pathLength
      && firstPathComponentLength == other.firstPathComponentLength && queryLength == other.queryLength
      && fragmentLength == other.fragmentLength && sigil == other.sigil && schemeKind == other.schemeKind
      && hostKind == other.hostKind && hasOpaquePath == other.hasOpaquePath
  }

  /// Ensures that this URL structure does not contain invalid combinations of values.
  /// **Only active in debug builds**.
  ///
  /// This method does not check the contents of the URL string -
  /// for instance, it does not check that `schemeKind` is an accurate reflection of the contents of the scheme,
  /// or that any expected delimiters are actually present.
  ///
  #if DEBUG

    @usableFromInline
    internal func checkInvariants() {

      // Invalid lengths.

      assert(schemeLength > 1, "Scheme cannot be empty")

      assert(passwordLength != 1, "Password length may not be exactly 1")
      assert(portLength != 1, "Port length may not be exactly 1")

      // Sigil and Authority components.

      switch sigil {
      case .authority:
        assert(hostKind != nil, "A URL with authority cannot have a 'nil' hostKind")

      case .path:
        assert(firstPathComponentLength == 1, "Path sigil present, but path does not begin with an empty component")
        assert(pathLength > 1, "Path sigil present, but path is too short to need one")
        fallthrough

      default:
        assert(hostKind == nil, "A URL without authority must have a 'nil' hostKind")
        assert(usernameLength == 0, "A URL without authority cannot have a username")
        assert(passwordLength == 0, "A URL without authority cannot have a password")
        assert(hostnameLength == 0, "A URL without authority cannot have a hostname")
        assert(portLength == 0, "A URL without authority cannot have a port")
      }

      switch hostKind {
      case .domainWithIDN:
        assert(hostnameLength >= 5, "A domain with IDN label cannot have fewer than 5 characters ('xn--' + 1)")
        fallthrough

      case .ipv4Address, .domain:
        assert(schemeKind.isSpecial, "Only URLs with special schemes can have IPv4 or domain hosts")
        assert(hostnameLength > 0, "IPv4/domain hostKinds cannot have empty hostnames")

      case .empty:
        assert(schemeKind == .file || schemeKind == .other, "The file URLs and non-special URLs may have empty hosts")
        assert(hostnameLength == 0, "Empty hostKind must have zero-length hostname")

      case .ipv6Address:
        assert(hostnameLength > 2, "IPv6 literals must be more than 2 characters")

      case .opaque:
        assert(hostnameLength > 0, "Opaque hostKinds cannot have empty hostnames")

      case .none:
        assert(hostnameLength == 0, "Nil hostKind must have zero-length hostname")
      }

      // Paths.

      switch hasOpaquePath {
      case true:
        assert(sigil == nil, "URLs with opaque paths cannot have an authority or path sigil")
        assert(firstPathComponentLength == 0, "Opaque paths do not have path components")
      case false:
        assert(firstPathComponentLength <= pathLength, "First path component is longer than the entire path")
        assert(pathLength == 0 || firstPathComponentLength != 0, "First path component length not set")
      }

      // Special URLs.

      if schemeKind.isSpecial {
        assert(sigil == .authority, "URLs with special schemes must have an authority")
        assert(pathLength != 0, "URLs with special schemes must have a path")
        assert(!hasOpaquePath, "URLs with special schemes cannot have opaque paths")
      }

      // Cannot have credentials or port.

      if cannotHaveCredentialsOrPort {
        assert(usernameLength == 0, "URL cannot have credentials or port, but has a username")
        assert(passwordLength == 0, "URL cannot have credentials or port, but has a password")
        assert(portLength == 0, "URL cannot have credentials or port, but has a port")
      }

      // Other flags.

      if queryLength == 0 || queryLength == 1 {
        assert(queryIsKnownFormEncoded, "Empty and nil queries must always be flagged as being form-encoded")
      }
    }

  #else

    @inlinable @inline(__always)
    func checkInvariants() {}

  #endif
}


// --------------------------------------------
// MARK: - Writing Sigils
// --------------------------------------------


extension Sigil {

  /// The number of bytes required to write the sigil's code-units.
  ///
  @inlinable
  internal var length: URLStorage.SizeType {
    return 2
  }

  /// Writes the sigil's code-units to the given buffer. The buffer must contain at least 2 bytes of space.
  ///
  /// - returns: The actual number of bytes written (always 2, unless the buffer is `nil`).
  ///
  @inlinable
  internal static func unsafeWrite(_ sigil: Sigil) -> (_ buffer: inout UnsafeMutableBufferPointer<UInt8>) -> Int {
    switch sigil {
    case .authority:
      return { buffer in
        guard let ptr = buffer.baseAddress else { return 0 }
        ptr.initialize(repeating: ASCII.forwardSlash.codePoint, count: 2)
        return 2
      }
    case .path:
      return { buffer in
        guard let ptr = buffer.baseAddress else { return 0 }
        ptr.initialize(to: ASCII.forwardSlash.codePoint)
        (ptr + 1).initialize(to: ASCII.period.codePoint)
        return 2
      }
    }
  }
}
