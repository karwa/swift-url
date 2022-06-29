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
// --------------------------------------------
// This file contains the primary types relating to storage and manipulation of URL strings.
//
// - URLStructure<SizeType>: The basic description of where the components are.
// - URLHeader<SizeType>: A ManagedBufferHeader which stores a URLStructure.
// - URLStorage: The main storage type. Defines a particular SizeType to be used for all URL strings and components,
//               and wraps a ManagedArrayBuffer<URLHeader> containing the structure and URL code-units.
// --------------------------------------------


// --------------------------------------------
// MARK: - URLStructure
// --------------------------------------------


/// An object which can store the structure of any normalized URL string whose size is not greater than `SizeType.max`.
///
/// The stored URL must be of the format:
///  [scheme + ":"] + [sigil]? + [username]? + [":" + password]? + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
///  If present, `sigil` must be either "//" to mark the beginning of an authority, or "/." to mark the beginning of the path.
///  A URL with an authority component requires an authority sigil; a URL without only an authority only requires a path sigil if the beginning if the path begins with "//".
///
@usableFromInline
internal struct URLStructure<SizeType: FixedWidthInteger> {

  /// The length of the scheme, including trailing `:`. Must be greater than 1.
  ///
  @usableFromInline
  internal var schemeLength: SizeType

  /// The length of the username component, not including any username-password or username-hostname separator which may be present.
  /// If zero, no username is present. If the URL does not have an authority, this component cannot be present.
  ///
  /// If _either_ `usernameLength` or `passwordLength` are non-zero, there is a separator before the hostname.
  /// Otherwise, there is no separator before the hostname.
  ///
  @usableFromInline
  internal var usernameLength: SizeType

  /// The length of the password component, including leading `:`. Must be either 0 or greater than 1.
  /// If zero, no password is present. A password may be present even if a username is not (e.g. `foo://:pass@host.com/`).
  /// If the URL does not have an authority, this component cannot be present.
  ///
  /// If _either_ `usernameLength` or `passwordLength` are non-zero, there is a separator before the hostname.
  /// Otherwise, there is no separator before the hostname.
  ///
  @usableFromInline
  internal var passwordLength: SizeType

  /// The length of the hostname, not including any leading or trailing separators.
  ///
  /// The difference between an empty and not-present host is the presence of an authority (as denoted by the presence of an authority sigil).
  /// If `sigil == .authority`, a length of zero indicates an empty hostname (e.g. `foo://?query`).
  /// If the URL does not have an authority, this component cannot be present.
  ///
  @usableFromInline
  internal var hostnameLength: SizeType

  /// The length of the port, including leading `:`. Must be either 0 or greater than 1.
  /// If zero, no port is present. If the URL does not have an authority, this component cannot be present.
  ///
  @usableFromInline
  internal var portLength: SizeType

  /// The length of the path. If zero, no path is present.
  ///
  @usableFromInline
  internal var pathLength: SizeType

  /// The length of the query. If zero, no query is present.
  ///
  @usableFromInline
  internal var queryLength: SizeType

  /// The length of the fragment. If zero, no query is present.
  ///
  @usableFromInline
  internal var fragmentLength: SizeType

  /// The length of the first path component. If zero, the path does not contain any components (e.g. it may not have a path, or the path may be opaque).
  ///
  @usableFromInline
  internal var firstPathComponentLength: SizeType

  /// The sigil, if present. The sigil comes immediately after the scheme and identifies the component following it.
  ///
  /// If `sigil == .authority`, the next component is an authority, consisting of username/password/hostname/port components.
  /// If `sigil == .path` or `sigil == nil`, the next component is a path/query/fragment and no username/password/hostname/port is present.
  ///
  @usableFromInline
  internal var __sigil: Optional<Sigil>

  /// A summary of this URL's `scheme`.
  ///
  /// `SchemeKind` only contains information about which kind of special scheme this URL has. All non-special schemes are represented as the same,
  /// so comparing the `schemeKind` doesn't necessarily mean that they have the same scheme.
  ///
  @usableFromInline
  internal var schemeKind: WebURL.SchemeKind

  /// A summary of this URL's `host`.
  ///
  /// `HostKind` only contains information about which kind of host this URL has. All hosts with the same kind are represented as the same,
  /// so comparing the `hostKind` doesn't necessarily mean that they have the same host.
  ///
  @usableFromInline
  internal var __hostKind: Optional<WebURL.HostKind>

  /// Whether this URL's path is opaque.
  ///
  /// An opaque path is just a string, rather than a list of components (e.g. `mailto:bob@example.com` or `javascript:alert("hello")`.
  ///
  @usableFromInline
  internal var hasOpaquePath: Bool

  /// Whether this URL's query string is known to be `application/x-www-form-urlencoded`.
  ///
  /// Only URLs without a query, or with an empty query, are required to set this flag when they are constructed.
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

  // This is a workaround to avoid expensive 'outlined init with take' calls.
  // https://bugs.swift.org/browse/SR-15215
  // https://forums.swift.org/t/expensive-calls-to-outlined-init-with-take/52187

  /// The sigil, if present. The sigil comes immediately after the scheme and identifies the component following it.
  ///
  /// If `sigil == .authority`, the next component is an authority, consisting of username/password/hostname/port components.
  /// If `sigil == .path` or `sigil == nil`, the next component is a path/query/fragment and no username/password/hostname/port is present.
  ///
  @inlinable @inline(__always)
  internal var sigil: Optional<Sigil> {
    get {
      // This field should be loadable from an offset, but perhaps the compiler will decide to pack it
      // and use the spare bits.
      guard let offset = MemoryLayout.offset(of: \Self.__sigil) else { return __sigil }
      return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<Sigil>.self) }
    }
    set {
      // We're not seeing the same expensive runtime calls for the setter, so there's nothing to work around here.
      __sigil = newValue
    }
  }

  /// A summary of this URL's `host`.
  ///
  /// `HostKind` only contains information about which kind of host this URL has. All hosts with the same kind are represented as the same,
  /// so comparing the `hostKind` doesn't necessarily mean that they have the same host.
  ///
  @inlinable @inline(__always)
  internal var hostKind: Optional<WebURL.HostKind> {
    get {
      // This field should be loadable from an offset, but perhaps the compiler will decide to pack it
      // and use the spare bits.
      guard let offset = MemoryLayout.offset(of: \Self.__hostKind) else { return __hostKind }
      return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<WebURL.HostKind>.self) }
    }
    set {
      // We're not seeing the same expensive runtime calls for the setter, so there's nothing to work around here.
      __hostKind = newValue
    }
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLStructure: Sendable where SizeType: Sendable {}
#endif

@usableFromInline
internal enum Sigil {
  case authority
  case path
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension Sigil: Sendable {}
#endif

extension URLStructure {

  /// The code-unit offset where the scheme starts. Always 0.
  ///
  @inlinable
  internal var schemeStart: SizeType {
    0
  }

  /// The code-unit offset after the scheme terminator.
  /// For example, the string in `codeUnits[schemeStart..<schemeEnd]` may be `https:` or `myscheme:`.
  ///
  @inlinable
  internal var schemeEnd: SizeType {
    schemeStart &+ schemeLength
  }

  /// The code-unit offset after the sigil, if there is one.
  ///
  /// If `sigil` is `.authority`, the authority components have meaningful values and begin at this point;
  /// otherwise, the path and subsequent components begin here.
  ///
  @inlinable
  internal var afterSigil: SizeType {
    schemeEnd &+ (sigil == .none ? 0 : 2)
  }

  // Authority components.
  // Only meaningful if sigil == .authority.

  @inlinable
  internal var authorityStart: SizeType {
    afterSigil
  }

  @inlinable
  internal var usernameStart: SizeType {
    authorityStart
  }

  @inlinable
  internal var passwordStart: SizeType {
    usernameStart &+ usernameLength
  }

  @inlinable
  internal var hostnameStart: SizeType {
    passwordStart &+ passwordLength &+ (hasCredentialSeparator ? 1 : 0) /* @ */
  }

  @inlinable
  internal var portStart: SizeType {
    hostnameStart &+ hostnameLength
  }

  // Other components.
  // A length of 0 means the component is not present at all (not even a separator).

  /// Returns the code-unit offset where the path starts, or would start if present.
  ///
  @inlinable
  internal var pathStart: SizeType {
    sigil == .authority ? portStart &+ portLength : afterSigil
  }

  /// Returns the code-unit offset where the query starts, or would start if present.
  /// If present, the first character of the query is '?'.
  ///
  @inlinable
  internal var queryStart: SizeType {
    pathStart &+ pathLength
  }

  /// Returns the code-unit offset where the fragment starts, or would start if present.
  /// If present, the first character of the fragment is "#".
  ///
  @inlinable
  internal var fragmentStart: SizeType {
    queryStart &+ queryLength
  }

  /// If an authority is present, returns the range of code-units starting at the first component of the authority
  /// and ending at the start of the first non-authority component. Otherwise, returns `nil`.
  ///
  @inlinable
  internal var rangeOfAuthorityString: Range<SizeType>? {
    guard hasAuthority else { return nil }
    return Range(uncheckedBounds: (authorityStart, pathStart))
  }

  /// The range of code-units which must be replaced in order to change the URL's sigil.
  /// If the URL does not contain a sigil, this property returns an empty range starting at the place where the sigil would go.
  ///
  @inlinable
  internal var rangeForReplacingSigil: Range<SizeType> {
    let start = schemeEnd
    let length: SizeType
    switch sigil {
    case .none: length = 0
    case .authority, .path: length = 2
    }
    return Range(uncheckedBounds: (start, start &+ length))
  }

  /// Returns the range of code-units which must be replaced in order to change the content of the given component.
  /// If the component is not present, this method returns an empty range starting at the place where the component would go.
  ///
  /// - important: Replacing/inserting code-units alone may not be sufficient to produce a normalized URL string.
  ///              For example, inserting a `username` where there was none before may require a credentials separator (@) to be inserted,
  ///              and removing an authority may require the introduction of a path sigil, etc.
  ///
  @inlinable
  internal func rangeForReplacingCodeUnits(of component: WebURL.Component) -> Range<SizeType> {
    checkInvariants()
    let start: SizeType
    let length: SizeType
    switch component {
    case .scheme:
      start = schemeStart
      length = schemeLength
    case .hostname:
      start = hostnameStart
      length = hostnameLength
    case .username:
      start = usernameStart
      length = usernameLength
    case .password:
      start = passwordStart
      length = passwordLength
    case .port:
      start = portStart
      length = portLength
    case .path:
      start = pathStart
      length = pathLength
    case .query:
      start = queryStart
      length = queryLength
    case .fragment:
      start = fragmentStart
      length = fragmentLength
    default:
      preconditionFailure("Invalid component")
    }
    return Range(uncheckedBounds: (start, start &+ length))
  }

  /// Returns the range of code-units containing the content of the given component. If the component is not present, this method returns `nil`.
  /// The returned range may contain leading/trailing separators, depending on the component.
  ///
  @inlinable
  internal func range(of component: WebURL.Component) -> Range<SizeType>? {
    let range = rangeForReplacingCodeUnits(of: component)
    switch component {
    case .scheme:
      break
    // Hostname may be empty. Presence is indicated by authority sigil.
    case .hostname:
      guard hasAuthority else { return nil }
    // Other components may not be both present and empty.
    // A length of 0 means "not present"/nil.
    case .username:
      guard usernameLength > 0 else { return nil }
    case .password:
      guard passwordLength > 0 else { return nil }
    case .port:
      guard portLength > 0 else { return nil }
    case .path:
      guard pathLength > 0 else { return nil }
    case .query:
      guard queryLength > 0 else { return nil }
    case .fragment:
      guard fragmentLength > 0 else { return nil }
    default:
      preconditionFailure("Invalid component")
    }
    return range
  }
}

extension URLStructure {

  /// Whether or not this URL has an authority, as denoted by the presence of an authority sigil.
  ///
  @inlinable
  internal var hasAuthority: Bool {
    if case .authority = sigil {
      return true
    } else {
      return false
    }
  }

  @inlinable
  internal var hasPathSigil: Bool {
    if case .path = sigil {
      return true
    } else {
      return false
    }
  }

  /// Whether the path described by this structure requires a path sigil when no authority is present.
  ///
  @inlinable
  internal var pathRequiresSigil: Bool {
    firstPathComponentLength == 1 && pathLength > 1
  }

  /// If the string has credentials, it must contain a '@' separating them from the hostname. If it doesn't, it mustn't.
  ///
  @inlinable
  internal var hasCredentialSeparator: Bool {
    usernameLength != 0 || passwordLength != 0
  }

  /// Whether the URL string has one or more of username/password/port.
  ///
  @inlinable
  internal var hasCredentialsOrPort: Bool {
    usernameLength != 0 || passwordLength != 0 || portLength != 0
  }

  /// > A URL cannot have a username/password/port if its host is null or the empty string, or its scheme is "file".
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal var cannotHaveCredentialsOrPort: Bool {
    hostnameLength == 0 || schemeKind == .file
  }
}

extension URLStructure {

  /// Creates a new URL structure with the same information as `other`, but whose values are stored using this structure's integer type.
  /// This initializer will trigger a runtime error if this structure's integer type is not capable of exactly representing the structure described by `other`.
  ///
  @inlinable
  internal init<OtherSize: FixedWidthInteger>(copying other: URLStructure<OtherSize>) {
    if let sameTypeOtherStructure = other as? Self {
      self = sameTypeOtherStructure
      return
    }
    self.init(
      schemeLength: SizeType(other.schemeLength),
      usernameLength: SizeType(other.usernameLength),
      passwordLength: SizeType(other.passwordLength),
      hostnameLength: SizeType(other.hostnameLength),
      portLength: SizeType(other.portLength),
      pathLength: SizeType(other.pathLength),
      queryLength: SizeType(other.queryLength),
      fragmentLength: SizeType(other.fragmentLength),
      firstPathComponentLength: SizeType(other.firstPathComponentLength),
      sigil: other.sigil,
      schemeKind: other.schemeKind,
      hostKind: other.hostKind,
      hasOpaquePath: other.hasOpaquePath,
      queryIsKnownFormEncoded: other.queryIsKnownFormEncoded
    )
    checkInvariants()
  }

  /// An `URLStructure` whose component lengths are all 0 and flags are bogus values.
  /// Since the scheme length is 0, this structure **does not describe a valid URL string**.
  ///
  /// This should only be used by the `StructureAndMetricsCollector`.
  ///
  @inlinable
  internal static func invalidEmptyStructure() -> URLStructure {
    return URLStructure(
      schemeLength: 0,
      usernameLength: 0,
      passwordLength: 0,
      hostnameLength: 0,
      portLength: 0,
      pathLength: 0,
      queryLength: 0,
      fragmentLength: 0,
      firstPathComponentLength: 0,
      sigil: nil,
      schemeKind: .other,
      hostKind: nil,
      hasOpaquePath: true,
      queryIsKnownFormEncoded: false
    )
  }
}

extension URLStructure {

  @usableFromInline
  internal func describesSameStructure(as other: Self) -> Bool {
    schemeLength == other.schemeLength && usernameLength == other.usernameLength
      && passwordLength == other.passwordLength && hostnameLength == other.hostnameLength
      && portLength == other.portLength && pathLength == other.pathLength
      && firstPathComponentLength == other.firstPathComponentLength && queryLength == other.queryLength
      && fragmentLength == other.fragmentLength && sigil == other.sigil && schemeKind == other.schemeKind
      && hostKind == other.hostKind && hasOpaquePath == other.hasOpaquePath
  }

  /// Performs debug-mode checks to ensure that this URL structure does not contain invalid combinations of values.
  ///
  /// This method does not check the _contents_ of the URL string (e.g. it does not check that `schemeKind` matches the code-units of the scheme, that the sigil
  /// or any other expected separators are actually present, etc).
  ///
  #if DEBUG
    @usableFromInline
    internal func checkInvariants() {

      // No values may be negative.
      assert(schemeLength >= 0, "Scheme has negative length")
      assert(usernameLength >= 0, "Username has negative length")
      assert(passwordLength >= 0, "Password has negative length")
      assert(hostnameLength >= 0, "Hostname has negative length")
      assert(portLength >= 0, "Port has negative length")
      assert(pathLength >= 0, "Path has negative length")
      assert(queryLength >= 0, "Query has negative length")
      assert(fragmentLength >= 0, "Fragment has negative length")
      assert(firstPathComponentLength >= 0, "First Path Component has negative length")

      assert(schemeLength > 1, "Scheme must be present, cannot be empty")
      assert(passwordLength != 1, "Password is an orphaned separator, which is invalid")
      assert(portLength != 1, "Port is an orphaned separator, which is invalid")

      switch sigil {
      case .authority:
        assert(hostKind != nil, "Cannot have nil hostKind with authority")
      case .path:
        assert(firstPathComponentLength == 1, "Path sigil present, but path does not begin with an empty component")
        assert(pathLength > 1, "Path sigil present, but path is too short to need one")
        fallthrough
      default:
        assert(hostKind == nil, "A URL without authority has a nil hostKind")
        assert(usernameLength == 0, "A URL without authority cannot have a username")
        assert(passwordLength == 0, "A URL without authority cannot have a password")
        assert(hostnameLength == 0, "A URL without authority cannot have a hostname")
        assert(portLength == 0, "A URL without authority cannot have a port")
      }

      if hasOpaquePath {
        assert(sigil == nil, "URLs with opaque paths cannot have an authority or path sigil")
      }
      if schemeKind.isSpecial {
        assert(sigil == .authority, "URLs with special schemes must have an authority")
        assert(pathLength != 0, "URLs with special schemes must have a path")
        assert(!hasOpaquePath, "URLs with special schemes cannot have opaque paths")
      }

      switch hostKind {
      case .ipv4Address, .domain, .domainWithIDN:
        assert(schemeKind.isSpecial, "Only URLs with special schemes can have IPv4 or domain hosts")
        assert(hostnameLength > 0, "IPv4/domain hostKinds cannot have empty hostnames")
        if case .domainWithIDN = hostKind {
          assert(hostnameLength >= 5, "A domain with IDN label cannot have fewer than 5 characters ('xn--' + 1)")
        }
      case .empty:
        if schemeKind.isSpecial {
          assert(schemeKind == .file, "The only special URL which allows empty hostnames is file")
        }
        assert(hostnameLength == 0, "Empty hostKind must have zero-length hostname")
      case .ipv6Address:
        assert(hostnameLength > 2, "IPv6 literals must be more than 2 characters")
      case .opaque:
        assert(hostnameLength > 0, "Opaque hostKinds cannot have empty hostnames")
      case .none:
        assert(hostnameLength == 0, "Nil hostKind must have zero-length hostname")
      }

      if cannotHaveCredentialsOrPort {
        assert(usernameLength == 0, "URL cannot have credentials or port, but has a username")
        assert(passwordLength == 0, "URL cannot have credentials or port, but has a password")
        assert(portLength == 0, "URL cannot have credentials or port, but has a port")
      }

      if queryLength == 0 || queryLength == 1 {
        assert(queryIsKnownFormEncoded, "Empty and nil queries must always be flagged as being form-encoded")
      }

      if hasOpaquePath {
        assert(firstPathComponentLength == 0, "Opaque paths do not have path components")
      } else {
        assert(firstPathComponentLength <= pathLength, "First path component is longer than the entire path")
        if pathLength != 0 {
          assert(firstPathComponentLength != 0, "First path component length not set")
        }
      }
    }
  #else
    @inlinable @inline(__always)
    func checkInvariants() {}
  #endif
}

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


// --------------------------------------------
// MARK: - URLHeader
// --------------------------------------------


/// A `ManagedBufferHeader` containing a complete `URLStructure` and size-appropriate `count` and `capacity` fields.
///
@usableFromInline
internal struct URLHeader<SizeType: FixedWidthInteger> {

  @usableFromInline
  internal var _count: SizeType

  @usableFromInline
  internal var _capacity: SizeType

  @usableFromInline
  internal var _structure: URLStructure<SizeType>

  @inlinable
  internal init(_count: SizeType, _capacity: SizeType, _structure: URLStructure<SizeType>) {
    self._count = _count
    self._capacity = _capacity
    self._structure = _structure
  }

  @inlinable
  internal init(structure: URLStructure<SizeType>) {
    self = .init(_count: 0, _capacity: 0, _structure: structure)
  }
}

extension URLHeader: ManagedBufferHeader {

  @inlinable
  internal var count: Int {
    get { return Int(_count) }
    set { _count = SizeType(newValue) }
  }

  @inlinable
  internal var capacity: Int {
    return Int(_capacity)
  }

  @inlinable
  internal func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> Self? {
    let newCapacity = SizeType(clamping: maximumCapacity)
    guard newCapacity >= minimumCapacity else {
      return nil
    }
    return Self(_count: _count, _capacity: newCapacity, _structure: _structure)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLHeader: Sendable where SizeType: Sendable {}
#endif


// --------------------------------------------
// MARK: - URLStorage
// --------------------------------------------


/// The primary type responsible for URL storage.
///
/// An `URLStorage` object wraps a `ManagedArrayBuffer`, containing the normalized URL string's contiguous code-units, together
/// with a header describing the structure of the URL components within those code-units. `URLStorage` has value semantics
/// via `ManagedArrayBuffer`, with modifications to multiply-referenced storage copying on write.
///
@usableFromInline
internal struct URLStorage {

  /// The type used to represent dimensions of the URL string and its components.
  ///
  /// The URL string, and any of its components, may not be larger than `SizeType.max`.
  ///
  @usableFromInline
  internal typealias SizeType = UInt32

  @usableFromInline
  internal var codeUnits: ManagedArrayBuffer<URLHeader<SizeType>, UInt8>

  @inlinable
  internal var header: URLHeader<SizeType> {
    get { return codeUnits.header }
    _modify { yield &codeUnits.header }
  }

  /// Allocates new storage with sufficient capacity to store `count` code-units, and a header describing the given `structure`.
  /// The `initializer` closure is invoked to write the code-units, and must return the number of code-units initialized.
  ///
  /// If the header cannot exactly reproduce the given `structure`, a runtime error is triggered.
  /// Use `AnyURLStorage` to allocate storage with the appropriate header for a given structure.
  ///
  /// - parameters:
  ///   - count:       The number of UTF8 code-units contained in the normalized URL string that `initializer` will write to the new storage.
  ///   - structure:   The structure of the normalized URL string that `initializer` will write to the new storage.
  ///   - initializer: A closure which must initialize exactly `count` code-units in the buffer pointer it is given, matching the normalized URL string
  ///                  described by `structure`. The closure returns the number of bytes actually written to storage, which should be
  ///                  calculated by the closure independently as it writes the contents, which serves as a safety check to avoid exposing uninitialized storage.
  ///
  @inlinable
  internal init(
    count: SizeType,
    structure: URLStructure<SizeType>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    self.codeUnits = ManagedArrayBuffer(minimumCapacity: Int(count), initialHeader: URLHeader(structure: structure))
    assert(self.codeUnits.count == 0)
    assert(self.codeUnits.header.capacity >= count)
    self.codeUnits.unsafeAppend(uninitializedCapacity: Int(count)) { buffer in initializer(&buffer) }
    assert(self.codeUnits.header.count == count)
  }
}

#if swift(>=5.5) && canImport(_Concurrency)
  extension URLStorage: Sendable {}
#endif

extension URLStorage {

  @inlinable
  internal var structure: URLStructure<URLStorage.SizeType> {
    get {
      header._structure
    }
    _modify {
      yield &header._structure
    }
    set {
      header._structure = newValue
    }
  }

  @inlinable
  internal var schemeKind: WebURL.SchemeKind {
    structure.schemeKind
  }

  @inlinable
  internal var hasOpaquePath: Bool {
    structure.hasOpaquePath
  }

  @inlinable
  internal func withUTF8OfAllAuthorityComponents<T>(
    _ body: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ hostKind: WebURL.HostKind?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    ) -> T
  ) -> T {
    guard let range = structure.rangeOfAuthorityString else { return body(nil, nil, 0, 0, 0, 0) }
    // Note: ManagedArrayBuffer.withUnsafeBufferPointer(range:) is bounds-checked.
    return codeUnits.withUnsafeBufferPointer(range: range.toCodeUnitsIndices()) { buffer in
      body(
        buffer, structure.hostKind,
        Int(structure.usernameLength), Int(structure.passwordLength),
        Int(structure.hostnameLength), Int(structure.portLength)
      )
    }
  }
}

/// The URL `a:` - essentially the smallest valid URL string. This is a used to temporarily occupy a `URLStorage` variable,
/// so its previous value can be moved to a uniquely-referenced local variable.
///
/// It should not be possible to observe a URL whose storage is set to this object.
///
@usableFromInline
internal let _tempStorage = URLStorage(
  count: 2,
  structure: URLStructure(
    schemeLength: 2, usernameLength: 0, passwordLength: 0, hostnameLength: 0,
    portLength: 0, pathLength: 0, queryLength: 0, fragmentLength: 0, firstPathComponentLength: 0,
    sigil: nil, schemeKind: .other, hostKind: nil, hasOpaquePath: true, queryIsKnownFormEncoded: true),
  initializingCodeUnitsWith: { buffer in
    buffer[0] = ASCII.a.codePoint
    buffer[1] = ASCII.colon.codePoint
    return 2
  }
)


// --------------------------------------------
// MARK: - Index conversion utilities
// --------------------------------------------


extension Range where Bound == URLStorage.SizeType {

  @inlinable
  internal func toCodeUnitsIndices() -> Range<Int> {
    Range<Int>(uncheckedBounds: (Int(lowerBound), Int(upperBound)))
  }
}

extension Range where Bound == ManagedArrayBuffer<URLHeader<URLStorage.SizeType>, UInt8>.Index {

  @inlinable
  internal func toURLStorageIndices() -> Range<URLStorage.SizeType> {
    Range<URLStorage.SizeType>(uncheckedBounds: (URLStorage.SizeType(lowerBound), URLStorage.SizeType(upperBound)))
  }
}

extension ManagedArrayBuffer where Header == URLHeader<URLStorage.SizeType> {

  @inlinable
  internal subscript(position: URLStorage.SizeType) -> Element {
    self[Index(position)]
  }

  @inlinable
  internal subscript(bounds: Range<URLStorage.SizeType>) -> Slice<Self> {
    Slice(base: self, bounds: bounds.toCodeUnitsIndices())
  }
}
