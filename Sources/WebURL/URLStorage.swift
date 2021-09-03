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
// - URLStructure: The basic description of where the components are.
//
// - URLHeader [protocol]: A type which stores a particular kind of URLStructure.
// - URLStorage<Header>: A type which owns a ManagedBuffer containing the header and URL code-units.
// - AnyURLStorage: A wrapper around URLStorage which erases its header type so you can use the URL without
//                  caring about that detail.
//
// - BasicURLHeader<SizeType>: A basic URLHeader which stores a URLStructure in its entirety.
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

  /// The length of the first path component. If zero, the path does not contain any components (e.g. it may not have a path, or may be a non-hierarchical URL).
  ///
  @usableFromInline
  internal var firstPathComponentLength: SizeType

  /// The sigil, if present. The sigil comes immediately after the scheme and identifies the component following it.
  ///
  /// If `sigil == .authority`, the next component is an authority, consisting of username/password/hostname/port components.
  /// If `sigil == .path` or `sigil == nil`, the next component is a path/query/fragment and no username/password/hostname/port is present.
  ///
  @usableFromInline
  internal var sigil: Sigil?

  /// A summary of this URL's `scheme`.
  ///
  /// `SchemeKind` only contains information about which kind of special scheme this URL has. All non-special schemes are represented as the same,
  /// so comparing the `schemeKind` doesn't necessarily mean that they have the same scheme.
  ///
  @usableFromInline
  internal var schemeKind: WebURL.SchemeKind

  /// Whether this is a hierarchical URL.
  ///
  /// A non-hierarchical URL essentially means the URL does not contain an authority and, if it has a path, that path does not begin with a `/`.
  /// (e.g. `mailto:somebody@somehost.com` or `javascript:alert("hello")`.
  ///
  @usableFromInline
  internal var isHierarchical: Bool

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
    isHierarchical: Bool,
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
    self.sigil = sigil
    self.schemeKind = schemeKind
    self.isHierarchical = isHierarchical
    self.queryIsKnownFormEncoded = queryIsKnownFormEncoded
  }
}

@usableFromInline
internal enum Sigil {
  case authority
  case path
}

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

  /// > A URL cannot have a username/password/port if its host is null or the empty string,
  /// > its cannot-be-a-base-URL is true, or its scheme is "file".
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  @inlinable
  internal var cannotHaveCredentialsOrPort: Bool {
    schemeKind == .file || isHierarchical == false || hostnameLength == 0
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
      isHierarchical: other.isHierarchical,
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
      isHierarchical: false,
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
      && isHierarchical == other.isHierarchical
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
        break
      case .path:
        assert(firstPathComponentLength == 1, "Path sigil present, but path does not begin with an empty component")
        assert(pathLength > 1, "Path sigil present, but path is too short to need one")
        fallthrough
      default:
        assert(usernameLength == 0, "A URL without authority cannot have a username")
        assert(passwordLength == 0, "A URL without authority cannot have a password")
        assert(hostnameLength == 0, "A URL without authority cannot have a hostname")
        assert(portLength == 0, "A URL without authority cannot have a port")
      }

      if !isHierarchical {
        assert(sigil == nil, "Non-hierarchical URLs cannot have an authority or path sigil")
      }
      if schemeKind.isSpecial {
        assert(sigil == .authority, "URLs with special schemes must have an authority")
        assert(pathLength != 0, "URLs with special schemes must have a path")
        assert(isHierarchical, "URLs with special schemes must always be hierarchical")
      }

      if cannotHaveCredentialsOrPort {
        assert(usernameLength == 0, "URL cannot have credentials or port, but has a username")
        assert(passwordLength == 0, "URL cannot have credentials or port, but has a password")
        assert(portLength == 0, "URL cannot have credentials or port, but has a port")
      }

      if queryLength == 0 || queryLength == 1 {
        assert(queryIsKnownFormEncoded, "Empty and nil queries must always be flagged as being form-encoded")
      }

      if isHierarchical {
        assert(firstPathComponentLength <= pathLength, "First path component is longer than the entire path")
        if pathLength != 0 {
          assert(firstPathComponentLength != 0, "First path component length not set")
        }
      } else {
        assert(firstPathComponentLength == 0, "Non-hierarchical URLs do not have path components")
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
  internal var length: Int {
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
// MARK: - URLStorage
// --------------------------------------------


/// A `ManagedBufferHeader` which stores a URL's structure.
///
/// When a URL is constructed or mutated, the parser or setter function first calculates the structure and required capacity of the resulting normalized URL string.
///
/// For mutations, `AnyURLStorage.isOptimalStorageType(_:requiredCapacity:structure:)` is consulted to check if the existing
/// header type is appropriate for the resulting string. If it is, the existing capacity is sufficient, and the storage is uniquely referenced, the modification occurs in-place.
/// Otherwise, `AnyURLStorage(optimalStorageForCapacity:structure:initializingCodeUnitsWith:)` is used to create storage with
/// the appropriate header type.
///
@usableFromInline
internal protocol URLHeader: ManagedBufferHeader {

  /// Returns an `AnyURLStorage` which wraps the given storage object.
  ///
  /// - Important: This means the only types that may conform to `URLHeader` are those supported by `AnyURLStorage`.
  ///
  static func eraseToAnyURLStorage(_ storage: URLStorage<Self>) -> AnyURLStorage

  /// Creates a new header with the given structure. The header's `capacity` and `count` are not specified, and through the `ManagedBufferHeader`
  /// interface when the header is attached to storage and that storage populated with code-units.
  ///
  /// The header must be capable of exactly reproducing the given structure. Otherwise, this initializer must trigger a runtime error.
  ///
  init(structure: URLStructure<Int>)

  /// Updates the URL structure stored by this header to reflect some prior change to the associated code-units.
  ///
  /// This method only updates the description of the URL's structure; it **does not** alter the header's `count` or `capacity`,
  /// which the operations modifying the code-units are expected to keep accurate.
  ///
  /// The header must be capable of exactly reproducing the given structure. Otherwise, this initializer must trigger a runtime error.
  ///
  mutating func copyStructure(from newStructure: URLStructure<Int>)

  /// The structure of the URL string stored in the code-units associated with this header.
  ///
  var structure: URLStructure<Int> { get }
}

/// The primary type responsible for URL storage.
///
/// An `URLStorage` object wraps a `ManagedArrayBuffer`, containing the normalized URL string's contiguous code-units, together
/// with a header describing the structure of the URL components within those code-units. Headers may store that description in different ways,
/// and may not support all possible URL strings; mutating functions must make sure to allocate storage with an appropriate header type for the
/// resulting URL string. The `AnyURLStorage` type is able to advise, create, and abstract over variations in header type.
///
/// `URLStorage` has value semantics via `ManagedArrayBuffer`, with modifications to multiply-referenced storage copying on write.
///
@usableFromInline
internal struct URLStorage<Header: URLHeader> {

  @usableFromInline
  internal var codeUnits: ManagedArrayBuffer<Header, UInt8>

  @inlinable
  internal var header: Header {
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
    count: Int,
    structure: URLStructure<Int>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    self.codeUnits = ManagedArrayBuffer(minimumCapacity: count, initialHeader: Header(structure: structure))
    assert(self.codeUnits.count == 0)
    assert(self.codeUnits.header.capacity >= count)
    self.codeUnits.unsafeAppend(uninitializedCapacity: count) { buffer in initializer(&buffer) }
    assert(self.codeUnits.header.count == count)
  }
}

extension URLStorage {

  @inlinable
  internal func withUTF8OfAllAuthorityComponents<T>(
    _ body: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    ) -> T
  ) -> T {
    let structure = header.structure
    guard let range = structure.rangeOfAuthorityString else { return body(nil, 0, 0, 0, 0) }
    // Note: ManagedArrayBuffer.withUnsafeBufferPointer(range:) is bounds-checked.
    return codeUnits.withUnsafeBufferPointer(range: range) { buffer in
      body(buffer, structure.usernameLength, structure.passwordLength, structure.hostnameLength, structure.portLength)
    }
  }
}


// --------------------------------------------
// MARK: - AnyURLStorage
// --------------------------------------------


/// This enum serves like an existential for `URLStorage` with a limited set of supported header types.
/// It is also able to determine the optimal header type for a `URLStructure`.
///
@usableFromInline
internal enum AnyURLStorage {
  case small(URLStorage<BasicURLHeader<UInt8>>)
  case large(URLStorage<BasicURLHeader<Int>>)

  @inlinable
  internal init<T>(_ storage: URLStorage<T>) {
    self = T.eraseToAnyURLStorage(storage)
  }
}

extension AnyURLStorage {

  /// Allocates a new storage object, with the header type best-suited for a normalized URL string with the given size and structure.
  /// The `initializer` closure is invoked to write the code-units, and must return the number of code-units initialized.
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
    optimalStorageForCapacity count: Int,
    structure: URLStructure<Int>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    if count <= UInt8.max {
      self = .small(
        URLStorage<BasicURLHeader<UInt8>>(count: count, structure: structure, initializingCodeUnitsWith: initializer)
      )
    } else {
      self = .large(
        URLStorage<BasicURLHeader<Int>>(count: count, structure: structure, initializingCodeUnitsWith: initializer)
      )
    }
  }

  /// Whether or not `type` is the optimal storage type for a normalized URL string of the given size and structure.
  /// It should be assumed that types which return `false` cannot store a URL with the given structure at all,
  /// and that attempting to do so will trigger a runtime error.
  ///
  @inlinable
  internal static func isOptimalStorageType<T>(
    _ type: URLStorage<T>.Type, requiredCapacity: Int, structure: URLStructure<Int>
  ) -> Bool {
    if requiredCapacity <= UInt8.max {
      return type == URLStorage<BasicURLHeader<UInt8>>.self
    }
    return type == URLStorage<BasicURLHeader<Int>>.self
  }
}

extension AnyURLStorage {

  @inlinable
  internal var structure: URLStructure<Int> {
    switch self {
    case .small(let storage): return storage.header.structure
    case .large(let storage): return storage.header.structure
    }
  }

  @inlinable
  internal var schemeKind: WebURL.SchemeKind {
    structure.schemeKind
  }

  @inlinable
  internal var isHierarchical: Bool {
    structure.isHierarchical
  }

  @inlinable
  internal func withUTF8OfAllAuthorityComponents<R>(
    _ body: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    ) -> R
  ) -> R {
    switch self {
    case .small(let storage): return storage.withUTF8OfAllAuthorityComponents(body)
    case .large(let storage): return storage.withUTF8OfAllAuthorityComponents(body)
    }
  }
}

/// The URL `a:` - essentially the smallest valid URL string. This is a used to temporarily occupy an `AnyURLStorage`,
/// so that its _actual_ storage can be moved to a uniquely-referenced local variable.
///
/// It should not be possible to observe a URL whose storage is set to this object.
///
@usableFromInline
internal let _tempStorage = AnyURLStorage(
  URLStorage<BasicURLHeader<UInt8>>(
    count: 2,
    structure: URLStructure(
      schemeLength: 2, usernameLength: 0, passwordLength: 0, hostnameLength: 0,
      portLength: 0, pathLength: 0, queryLength: 0, fragmentLength: 0, firstPathComponentLength: 0,
      sigil: nil, schemeKind: .other, isHierarchical: false, queryIsKnownFormEncoded: true),
    initializingCodeUnitsWith: { buffer in
      buffer[0] = ASCII.a.codePoint
      buffer[1] = ASCII.colon.codePoint
      return 2
    }
  )
)

extension AnyURLStorage {

  @inlinable
  internal mutating func withUnwrappedMutableStorage(
    _ small: (inout URLStorage<BasicURLHeader<UInt8>>) -> (AnyURLStorage),
    _ large: (inout URLStorage<BasicURLHeader<Int>>) -> (AnyURLStorage)
  ) {
    // We need to go through a bit of a dance in order to get a unique reference to the storage.
    // It's like if you have something stuck to one hand and try to remove it with the other hand.
    //
    // Basically:
    // 1. Swap our storage to temporarily point to some read-only global, so our only storage reference is
    //    via a local variable.
    // 2. Extract the URLStorage (which is a COW value type) from local variable's enum payload, and set
    //    the local to also point that read-only global.
    // 3. Hand that extracted storage off to closure `inout`, which does what it wants and
    //    returns a storage object back (possibly the same storage object).
    // 4. We round it all off by assigning that value as our new storage. Phew.
    var localRef = self
    self = _tempStorage
    switch localRef {
    case .large(var extracted_storage):
      localRef = _tempStorage
      self = large(&extracted_storage)
    case .small(var extracted_storage):
      localRef = _tempStorage
      self = small(&extracted_storage)
    }
  }

  @inlinable
  internal mutating func withUnwrappedMutableStorage(
    _ small: (inout URLStorage<BasicURLHeader<UInt8>>) -> (AnyURLStorage, URLSetterError?),
    _ large: (inout URLStorage<BasicURLHeader<Int>>) -> (AnyURLStorage, URLSetterError?)
  ) throws {
    // As above, but allows the closure to return a URLSetterError.
    var error: URLSetterError?
    var localRef = self
    self = _tempStorage
    switch localRef {
    case .large(var extracted_storage):
      localRef = _tempStorage
      (self, error) = large(&extracted_storage)
    case .small(var extracted_storage):
      localRef = _tempStorage
      (self, error) = small(&extracted_storage)
    }
    if let error = error {
      throw error
    }
  }
}


// --------------------------------------------
// MARK: - BasicURLHeader
// --------------------------------------------


/// A marker protocol for integer types supported by `AnyURLStorage` when wrapping a `URLStorage<BasicURLHeader<T>>`.
///
@usableFromInline
internal protocol AnyURLStorageSupportedBasicHeaderSize: FixedWidthInteger {

  /// Wraps the given `storage` in the appropriate `AnyURLStorage`.
  ///
  static func _eraseToAnyURLStorage(_ storage: URLStorage<BasicURLHeader<Self>>) -> AnyURLStorage
}

extension Int: AnyURLStorageSupportedBasicHeaderSize {

  @inlinable
  internal static func _eraseToAnyURLStorage(_ storage: URLStorage<BasicURLHeader<Int>>) -> AnyURLStorage {
    return .large(storage)
  }
}

extension UInt8: AnyURLStorageSupportedBasicHeaderSize {

  @inlinable
  internal static func _eraseToAnyURLStorage(_ storage: URLStorage<BasicURLHeader<UInt8>>) -> AnyURLStorage {
    return .small(storage)
  }
}

/// A `ManagedBufferHeader` containing a complete `URLStructure` and size-appropriate `count` and `capacity` fields.
///
@usableFromInline
internal struct BasicURLHeader<SizeType: FixedWidthInteger> {

  @usableFromInline
  internal var _count: SizeType

  @usableFromInline
  internal var _capacity: SizeType

  @usableFromInline
  internal var _structure: URLStructure<SizeType>

  @inlinable
  internal init(_count: SizeType, _capacity: SizeType, structure: URLStructure<SizeType>) {
    self._count = _count
    self._capacity = _capacity
    self._structure = structure
  }

  @inlinable
  internal static func _closestAddressableCapacity(to idealCapacity: Int) -> SizeType {
    if idealCapacity <= Int(SizeType.max) {
      return SizeType(idealCapacity)
    } else {
      return SizeType.max
    }
  }
}

extension BasicURLHeader: ManagedBufferHeader {

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
    let newCapacity = Self._closestAddressableCapacity(to: maximumCapacity)
    guard newCapacity >= minimumCapacity else {
      return nil
    }
    return Self(_count: _count, _capacity: newCapacity, structure: _structure)
  }
}

extension BasicURLHeader: URLHeader where SizeType: AnyURLStorageSupportedBasicHeaderSize {

  @inlinable
  internal static func eraseToAnyURLStorage(_ storage: URLStorage<Self>) -> AnyURLStorage {
    return SizeType._eraseToAnyURLStorage(storage)
  }

  @inlinable
  internal init(structure: URLStructure<Int>) {
    self = .init(_count: 0, _capacity: 0, structure: URLStructure<SizeType>(copying: structure))
  }

  @inlinable
  internal mutating func copyStructure(from newStructure: URLStructure<Int>) {
    self._structure = URLStructure(copying: newStructure)
  }

  @inlinable
  internal var structure: URLStructure<Int> {
    return URLStructure(copying: _structure)
  }
}
