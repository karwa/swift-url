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

// This file contains the primary types relating to storage and manipulation of URL strings.
//
// - URLStructure: The basic description of where the components are.
//
// - URLHeader [protocol]: A type which stores a particular kind of URLStructure.
// - URLStorage<Header>: A type which owns a ManagedBuffer containing the header and URL code-units.
// - AnyURLStorage: A wrapper around URLStorage which erases its header type so you can use the URL without
//                  caring about that detail.
//
// - GenericURLHeader<SizeType>: A basic URLHeader which stores a URLStructure in its entirety.
//

// MARK: - URLStructure

/// An object which can store the structure of any normalized URL string whose size is not greater than `SizeType.max`.
///
/// The stored URL must be of the format:
///  [scheme + ":"] + [sigil]? + [username]? + [":" + password]? + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
///  If present, `sigil` must be either "//" to mark the beginning of an authority, or "/." to mark the beginning of the path.
///  A URL with an authority component requires an authority sigil; a URL without only an authority only requires a path sigil if the beginning if the path begins with "//".
///
struct URLStructure<SizeType: FixedWidthInteger> {

  /// The length of the scheme, including trailing `:`. Must be greater than 1.
  ///
  var schemeLength: SizeType

  /// The length of the username component, not including any username-password or username-hostname separator which may be present.
  /// If zero, no username is present. If the URL does not have an authority, this component cannot be present.
  ///
  /// If _either_ `usernameLength` or `passwordLength` are non-zero, there is a separator before the hostname.
  /// Otherwise, there is no separator before the hostname.
  ///
  var usernameLength: SizeType

  /// The length of the password component, including leading `:`. Must be either 0 or greater than 1.
  /// If zero, no password is present. A password may be present even if a username is not (e.g. `foo://:pass@host.com/`).
  /// If the URL does not have an authority, this component cannot be present.
  ///
  /// If _either_ `usernameLength` or `passwordLength` are non-zero, there is a separator before the hostname.
  /// Otherwise, there is no separator before the hostname.
  ///
  var passwordLength: SizeType

  /// The length of the hostname, not including any leading or trailing separators.
  ///
  /// The difference between an empty and not-present host is the presence of an authority (as denoted by the presence of an authority sigil).
  /// If `sigil == .authority`, a length of zero indicates an empty hostname (e.g. `foo://?query`).
  /// If the URL does not have an authority, this component cannot be present.
  ///
  var hostnameLength: SizeType

  /// The length of the port, including leading `:`. Must be either 0 or greater than 1.
  /// If zero, no port is present. If the URL does not have an authority, this component cannot be present.
  ///
  var portLength: SizeType

  /// The length of the path. If zero, no path is present.
  ///
  var pathLength: SizeType

  /// The length of the query. If zero, no query is present.
  ///
  var queryLength: SizeType

  /// The length of the fragment. If zero, no query is present.
  ///
  var fragmentLength: SizeType

  /// The sigil, if present. The sigil comes immediately after the scheme and identifies the component following it.
  ///
  /// If `sigil == .authority`, the next component is an authority, consisting of username/password/hostname/port components.
  /// If `sigil == .path` or `sigil == nil`, the next component is a path/query/fragment and no username/password/hostname/port is present.
  ///
  var sigil: Sigil?

  /// A summary of this URL's `scheme`.
  ///
  /// `SchemeKind` only contains information about which kind of special scheme this URL has. All non-special schemes are represented as the same,
  /// so comparing the `schemeKind` doesn't necessarily mean that they have the same scheme.
  ///
  var schemeKind: WebURL.SchemeKind

  /// Whether this is a 'cannot-be-a-base' URL.
  ///
  /// Parsing a relative URL string against 'cannot-be-a-base' URLs will fail. This is the case for non-special URLs without an authority and whose path
  /// does not begin with a `/` (e.g. `mailto:somebody@somehost.com` or `javascript:alert("hello")`.
  ///
  var cannotBeABaseURL: Bool
}

enum Sigil {
  case authority
  case path
}

extension URLStructure {

  /// Creates an empty URL structure. Note that this structure does not represent a valid URL.
  ///
  init() {
    self.schemeLength = 0
    self.usernameLength = 0
    self.passwordLength = 0
    self.hostnameLength = 0
    self.portLength = 0
    self.pathLength = 0
    self.queryLength = 0
    self.fragmentLength = 0
    self.sigil = .none
    self.schemeKind = .other
    self.cannotBeABaseURL = false
  }

  /// Creates a new URL structure with the same information as `otherStructure`, but whose values are stored using a different integer type.
  /// This initializer will trigger a runtime error if the new size is not capable of exactly representing `otherStructure`'s values.
  ///
  init<OtherSize: FixedWidthInteger>(copying otherStructure: URLStructure<OtherSize>) {
    if let sameTypeOtherStructure = otherStructure as? Self {
      self = sameTypeOtherStructure
      return
    }
    self = .init(
      schemeLength: SizeType(otherStructure.schemeLength),
      usernameLength: SizeType(otherStructure.usernameLength),
      passwordLength: SizeType(otherStructure.passwordLength),
      hostnameLength: SizeType(otherStructure.hostnameLength),
      portLength: SizeType(otherStructure.portLength),
      pathLength: SizeType(otherStructure.pathLength),
      queryLength: SizeType(otherStructure.queryLength),
      fragmentLength: SizeType(otherStructure.fragmentLength),
      sigil: otherStructure.sigil,
      schemeKind: otherStructure.schemeKind,
      cannotBeABaseURL: otherStructure.cannotBeABaseURL
    )
    // Cannot check invariants here because of the 'tempStorage' hack we use to implement COW.
    // checkInvariants()
  }
}

extension URLStructure {

  /// Performs debug-mode checks to ensure that this URL structure does not contain invalid combinations of values.
  ///
  /// This method does not check the _contents_ of the URL string (e.g. it does not check that `schemeKind` matches the code-units of the scheme, that the sigil
  /// or any other expected separators are actually present, etc).
  ///
  func checkInvariants() {

    // No values may be negative.
    assert(schemeLength >= 0, "scheme has negative length")
    assert(usernameLength >= 0, "username has negative length")
    assert(passwordLength >= 0, "password has negative length")
    assert(hostnameLength >= 0, "hostname has negative length")
    assert(portLength >= 0, "port has negative length")
    assert(pathLength >= 0, "path has negative length")
    assert(queryLength >= 0, "query has negative length")
    assert(fragmentLength >= 0, "fragment has negative length")

    // Scheme must be present and not empty.
    assert(schemeLength > 1, "Scheme not present or empty")

    // Some components with separators included in their lengths cannot have a length of 1.
    assert(passwordLength != 1, "Password is empty but leading separator is present")
    assert(portLength != 1, "Port is empty but leading separator is present")

    // If this URL cannot be a base URL, it can't have an authority.
    if cannotBeABaseURL, case .authority = sigil {
      assertionFailure("cannot-be-a-base URLs cannot have an authority")
    }

    // Special schemes must have an authority and non-empty path.
    if schemeKind.isSpecial {
      assert(sigil == .authority, "Special URL must have an authority")
      assert(pathLength != 0, "Special URL must have a path")
    }

    // Certain URLs may not have credentials or a port.
    if cannotHaveCredentialsOrPort {
      assert(usernameLength == 0, "URL cannot have credentials or port, but has a username")
      assert(passwordLength == 0, "URL cannot have credentials or port, but has a password")
      assert(portLength == 0, "URL cannot have credentials or port, but has a port")
    }

    // If there is no authority, all authority components must be 0.
    switch sigil {
    case .authority:
      break
    case .path:
      assert(pathLength >= 2, "Path sigil present, but path is too short to need one")
      fallthrough
    default:
      assert(usernameLength == 0, "A URL without authority sigil cannot have a username")
      assert(passwordLength == 0, "A URL without authority sigil cannot have a password")
      assert(hostnameLength == 0, "A URL without authority sigil cannot have a hostname")
      assert(portLength == 0, "A URL without authority sigil cannot have a port")
    }
  }
}

extension URLStructure {

  /// Whether or not this URL has an authority, as denoted by the presence of an authority sigil.
  ///
  var hasAuthority: Bool {
    if case .authority = sigil {
      return true
    } else {
      return false
    }
  }

  var hasPathSigil: Bool {
    if case .path = sigil {
      return true
    } else {
      return false
    }
  }

  /// If the string has credentials, it must contain a '@' separating them from the hostname. If it doesn't, it mustn't.
  ///
  var hasCredentialSeparator: Bool {
    return usernameLength != 0 || passwordLength != 0
  }

  /// > A URL cannot have a username/password/port if its host is null or the empty string,
  /// > its cannot-be-a-base-URL is true, or its scheme is "file".
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  var cannotHaveCredentialsOrPort: Bool {
    return schemeKind == .file || cannotBeABaseURL || hostnameLength == 0
  }
}

extension URLStructure {

  /// The code-unit offset where the scheme starts. Always 0.
  ///
  var schemeStart: SizeType {
    return 0
  }

  /// The code-unit offset after the scheme terminator.
  /// For example, the string in `codeUnits[schemeStart..<schemeEnd]` may be `https:` or `myscheme:`.
  ///
  var schemeEnd: SizeType {
    return schemeStart &+ schemeLength
  }

  /// The code-unit offset after the sigil, if there is one.
  ///
  /// If `sigil` is `.authority`, the authority components have meaningful values and begin at this point;
  /// otherwise, the path and subsequent components begin here.
  ///
  var afterSigil: SizeType {
    return schemeEnd &+ (sigil == .none ? 0 : 2)
  }

  // Authority components.
  // Only meaningful if sigil == .authority.

  var authorityStart: SizeType {
    return afterSigil
  }
  var usernameStart: SizeType {
    return authorityStart
  }
  var passwordStart: SizeType {
    return usernameStart &+ usernameLength
  }
  var hostnameStart: SizeType {
    return passwordStart &+ passwordLength &+ (hasCredentialSeparator ? 1 : 0) /* @ */
  }
  var portStart: SizeType {
    return hostnameStart &+ hostnameLength
  }

  // Other components.
  // A length of 0 means the component is not present at all (not even a separator).

  /// Returns the code-unit offset where the path starts, or would start if present.
  ///
  var pathStart: SizeType {
    return sigil == .authority ? portStart &+ portLength : afterSigil
  }

  /// Returns the code-unit offset where the query starts, or would start if present.
  /// If present, the first character of the query is '?'.
  ///
  var queryStart: SizeType {
    return pathStart &+ pathLength
  }

  /// Returns the code-unit offset where the fragment starts, or would start if present.
  /// If present, the first character of the fragment is "#".
  ///
  var fragmentStart: SizeType {
    return queryStart &+ queryLength
  }

  /// The range of code-units covering all authority components, if an authority is present.
  ///
  var rangeOfAuthorityString: Range<SizeType>? {
    checkInvariants()
    guard hasAuthority else { return nil }
    return Range(uncheckedBounds: (authorityStart, pathStart))
  }

  /// The range of code-units which must be replaced in order to change the URL's sigil.
  /// If the URL does not contain a sigil, this property returns an empty range starting at the place where the sigil would go.
  ///
  var rangeForReplacingSigil: Range<SizeType> {
    checkInvariants()
    let start = schemeEnd
    let length: SizeType
    switch sigil {
    case .none: length = 0
    case .authority, .path: length = 2
    }
    return Range(uncheckedBounds: (start, start &+ length))
  }

  /// Returns the range of code-units which must be replaced in order to change the content of the given component.
  /// If the component is not present, this method returns an empty range starting at the place where component was expected to be found.
  ///
  /// - important: Replacing/inserting code-units alone may not be sufficient to produce a normalised URL string.
  ///              For example, inserting a `username` where there was none before may require a credentials separator (@) to be inserted
  ///              between the credentials and the hostname, removing an authority may require the introduction of a path sigil, etc.
  ///
  func rangeForReplacingCodeUnits(of component: WebURL.Component) -> Range<SizeType> {
    checkInvariants()
    let start: SizeType
    let length: SizeType
    switch component {
    case .scheme:
      return Range(uncheckedBounds: (schemeStart, schemeEnd))
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

  /// Returns the range of bytes containing the content of the given component.
  /// If the component is not present, this method returns `nil`.
  ///
  func range(of component: WebURL.Component) -> Range<SizeType>? {
    checkInvariants()
    let range = rangeForReplacingCodeUnits(of: component)
    switch component {
    case .scheme:
      break
    // Hostname may be empty. Presence is indicated by authority sigil.
    case .hostname:
      guard hasAuthority else { return nil }
    // Other components may not be empty. A length of 0 means "not present"/nil.
    case .username:
      guard usernameLength != 0 else { return nil }
    case .password:
      guard passwordLength != 0 else { return nil }
    case .port:
      guard portLength != 0 else { return nil }
    case .path:
      guard pathLength != 0 else { return nil }
    case .query:
      guard queryLength != 0 else { return nil }
    case .fragment:
      guard fragmentLength != 0 else { return nil }
    default:
      preconditionFailure("Invalid component")
    }
    return range
  }
}

extension Sigil {

  var length: Int {
    return 2
  }

  func unsafeWrite(to buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
    guard let ptr = buffer.baseAddress else { return 0 }
    switch self {
    case .authority:
      ptr.initialize(repeating: ASCII.forwardSlash.codePoint, count: 2)
    case .path:
      ptr[0] = ASCII.forwardSlash.codePoint
      ptr[1] = ASCII.period.codePoint
    }
    return 2
  }
}


// MARK: - URLStorage.


/// A `ManagedBufferHeader` which stores information about a URL string.
///
/// URLs are stored in `URLStorage` objects, which are managed buffers containing the string's contiguous code-units, prefixed by
/// a header conforming to `URLHeader`. The `AnyURLStorage` wrapper allows this header type to be erased, so that the
/// optimal header can be chosen for a given URL string.
///
/// For example, small URL strings might wish to store their header information in a smaller integer type than `Int64` on 64-bit platforms.
/// Similarly, some common URL patterns might warrant their own headers: with the URL's structure essentially being encoded in the header type.
///
/// When a URL String is parsed, or when a mutation on an already-parsed URL is planned, the parser or setter function first calculates
/// a _required capacity_, and a `URLStructure<Int>` describing the new URL string.
///
/// - For mutations, `AnyURLStorage.isOptimalStorageType(_:requiredCapacity:structure:)` is consulted to check if the existing
///   header type is also the desired header for the result. If it is, the capacity is sufficient, and the storage reference is unique, the modification happens in-place.
/// - Otherwise, if the storage types do not match, or there is no existing storage to mutate (in the case of the parser),
///   `AnyURLStorage(optimalStorageForCapacity:structure:initializingCodeUnitsWith:)` is used to create storage with a compatible
///   header type.
///
protocol URLHeader: ManagedBufferHeader {

  /// Returns a `AnyURLStorage` which erases this header type from the given `URLStorage` instance.
  ///
  /// - Note: This means the only types that may conform to this protocol are those supported by `AnyURLStorage`.
  ///
  static func eraseToAnyURLStorage(_ storage: URLStorage<Self>) -> AnyURLStorage

  /// Creates a new header with the given count and structure. The header does not assume any available capacity beyond `count`.
  ///
  /// This initializer must return `nil` if it is unable to store the given count and structure.
  ///
  init?(count: Int, structure: URLStructure<Int>)

  /// Updates the header's structure and metrics to reflect some prior change to the associated code-units.
  ///
  /// This method only updates metadata about the represented URL structure; it **does not** update the header's `count` or `capacity`,
  /// which the code modifying the code-units is expected to maintain as it goes. If the header is unable to store the new structure without loss
  /// (because it models a limits subset of URL strings), this method returns `false` and does not update the URL structure data.
  ///
  mutating func copyStructure(from newStructure: URLStructure<Int>) -> Bool

  /// The structure of the URL string contained in this header's associated buffer.
  ///
  var structure: URLStructure<Int> { get }
}

/// The primary type responsible for URL storage.
///
/// URLs are stored in `URLStorage` objects, which are managed buffers containing the string's contiguous code-units, prefixed by
/// a header conforming to `URLHeader`. The `AnyURLStorage` wrapper allows this header type to be erased, so that the
/// optimal header can be chosen for a given URL string.
///
/// `URLStorage` has value semantics via `ManagedArrayBuffer`, with attempted mutations happening in-place where possible
/// and copying to new storage only when the buffer is shared or if the existing header does not support the new structure.
///
/// Mutating functions must take care to observe the following:
///
/// - The header type may not be able to support arbitrary URLs. Setters should calculate the `URLStructure`
///   of the final URL string and call `AnyURLStorage.isOptimalStorageType(_:for:)` before making any changes.
/// - Should a change of header be required, `AnyURLStorage(creatingOptimalStorageFor:initializingCodeUnitsWith:)`
///   should be used to create and initialize the new storage.
/// - Given the possibility of changing storage type, functions must _return_ an `AnyURLStorage` wrapping the result (either `self` or the new storage
///   that was created).
///
struct URLStorage<Header: URLHeader> {

  var codeUnits: ManagedArrayBuffer<Header, UInt8>

  var header: Header {
    get { return codeUnits.header }
    _modify { yield &codeUnits.header }
    set { codeUnits.header = newValue }
  }

  /// Allocates new storage, with the capacity sufficient for storing `count` code-units, and initializes the header using the given `structure`.
  /// The `initializer` closure is invoked to write the code-units, and must return the number of code-units initialized.
  ///
  /// This initializer fails if the header cannot be constructed from the given `count` and `structure`.
  ///
  init?(
    count: Int,
    structure: URLStructure<Int>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    guard let header = Header(count: count, structure: structure) else {
      return nil
    }
    self.codeUnits = ManagedArrayBuffer(minimumCapacity: count, initialHeader: header)
    assert(self.codeUnits.count == 0)
    assert(self.codeUnits.header.capacity >= count)
    self.codeUnits.unsafeAppend(uninitializedCapacity: count) { buffer in
      var buffer = buffer
      return initializer(&buffer)
    }
  }
}


// MARK: - Getters.


extension URLStorage {

  func withEntireString<T>(_ block: (UnsafeBufferPointer<UInt8>) -> T) -> T {
    return codeUnits.withUnsafeBufferPointer(block)
  }

  var entireString: String {
    return withEntireString { String(decoding: $0, as: UTF8.self) }
  }

  func withComponentBytes<T>(_ component: WebURL.Component, _ block: (UnsafeBufferPointer<UInt8>?) -> T) -> T {
    guard let range = header.structure.range(of: component) else { return block(nil) }
    return codeUnits.withElements(range: range, block)
  }

  func stringForComponent(_ component: WebURL.Component) -> String? {
    return withComponentBytes(component) { maybeBuffer in
      return maybeBuffer.map { buffer in String(decoding: buffer, as: UTF8.self) }
    }
  }

  func withAllAuthorityComponentBytes<T>(
    _ block: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    ) -> T
  ) -> T {
    let urlStructure = header.structure
    guard let range = urlStructure.rangeOfAuthorityString else { return block(nil, 0, 0, 0, 0) }
    return codeUnits.withElements(range: Range(uncheckedBounds: (range.lowerBound, range.upperBound))) {
      buffer in
      block(
        buffer,
        urlStructure.usernameLength,
        urlStructure.passwordLength,
        urlStructure.hostnameLength,
        urlStructure.portLength
      )
    }
  }
}


// MARK: - Setter Utilities.


extension URLStorage {

  /// Replaces the given range of code-units with an uninitialized space, which is then initialized by the given closure.
  /// The URL's structure is also replaced with the given new structure. If the existing storage is not optimal for the new structure,
  /// the storage will be replaced with the optimal kind.
  ///
  /// This method fails at runtime if the `initializer` closure does not initialize exactly `insertCount` code-units.
  /// `initializer`'s return value should be calculated independently as it writes to the buffer, to ensure that it does not leave uninitialized gaps.
  ///
  /// - parameters:
  ///   - subrangeToReplace:  The range of code-units to replace
  ///   - insertCount:        The size of the uninitialized space to replace the subrange with. If 0, the subrange's contents are removed.
  ///   - newStructure:       The new structure of the URL after replacement.
  ///   - initializer:        A closure which initializes the new content of the given subrange and returns the number of elements initialized.
  ///                         The initializer **must** initialize exactly `insertCount` elements, or this method will trap.
  ///
  /// - returns: An `AnyURLStorage` with the given range of code-units replaced and with the new structure. If the existing storage was already optimal
  ///            for the new structure and the mutation occurred in-place, this will wrap `self`. Otherwise, it will wrap a new storage object.
  ///
  mutating func replaceSubrange(
    _ subrangeToReplace: Range<Int>,
    withUninitializedSpace insertCount: Int,
    newStructure: URLStructure<Int>,
    initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> AnyURLStorage {

    newStructure.checkInvariants()
    let newCount = codeUnits.count - subrangeToReplace.count + insertCount

    if AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: newCount, structure: newStructure) {
      codeUnits.unsafeReplaceSubrange(
        subrangeToReplace, withUninitializedCapacity: insertCount, initializingWith: initializer
      )
      guard header.copyStructure(from: newStructure) else {
        preconditionFailure("Header didn't accept the new structure")
      }
      return AnyURLStorage(self)
    }
    let newStorage = AnyURLStorage(optimalStorageForCapacity: newCount, structure: newStructure) { dest in
      return codeUnits.withUnsafeBufferPointer { src in
        dest.initialize(from: src, replacingSubrange: subrangeToReplace, withElements: insertCount) { rgnStart, count in
          var rgnPtr = UnsafeMutableBufferPointer(start: rgnStart, count: count)
          let written = initializer(&rgnPtr)
          precondition(written == count, "Subrange initializer did not initialize the expected number of code-units")
        }
      }
    }
    return newStorage
  }

  /// Removes the given range of code-units.
  /// The URL's structure is also replaced with the given new structure. If the existing storage is not optimal for the new structure,
  /// the storage will be replaced with the optimal kind.
  ///
  /// - parameters:
  ///   - subrangeToRemove:  The range of code-units to remove
  ///   - newStructure:      The new structure of the URL after removing the given code-units.
  ///
  /// - returns: An `AnyURLStorage` with the given range of code-units removed and with the new structure. If the existing storage was already optimal
  ///            for the new structure and the mutation occurred in-place, this will wrap `self`. Otherwise, it will wrap a new storage object.
  ///
  mutating func removeSubrange(
    _ subrangeToRemove: Range<Int>, newStructure: URLStructure<Int>
  ) -> AnyURLStorage {
    return replaceSubrange(subrangeToRemove, withUninitializedSpace: 0, newStructure: newStructure) { _ in 0 }
  }

  /// A command object which represents a replacement operation on some URL code-units.
  ///
  struct ReplaceSubrangeOperation {
    var subrange: Range<Int>
    var insertedCount: Int
    var writer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int

    /// - seealso: `URLStorage.replaceSubrange`
    static func replace(
      subrange: Range<Int>, withCount: Int, writer: @escaping (inout UnsafeMutableBufferPointer<UInt8>) -> Int
    ) -> Self {
      return .init(subrange: subrange, insertedCount: withCount, writer: writer)
    }

    /// - seealso: `URLStorage.removeSubrange`
    static func remove(subrange: Range<Int>) -> Self {
      return .replace(subrange: subrange, withCount: 0, writer: { _ in return 0 })
    }
  }

  /// Performs the given list of code-unit replacement operations while updating the URL's header to reflect the given structure.
  /// If the current storage type supports the new structure, the operations will be performed in-place.
  /// Otherwise, appropriate storage will be allocated and initialized with the result of applying the given operations to this storage's code-units.
  ///
  /// - parameters:
  ///   - commands:      The list of code-unit replacement operations to perform.
  ///                    This list must be sorted by the operations' subrange, and operations may not work on overlapping subranges.
  ///   - newStructure:  The new structure of the URL after all replacement operations have been performed.
  ///
  /// - returns: An `AnyURLStorage` with the new code-units and structure. If the existing storage was already optimal
  ///            for the new structure and the mutation occurred in-place, this will wrap `self`. Otherwise, it will wrap a new storage object.
  ///
  mutating func multiReplaceSubrange(
    commands: [ReplaceSubrangeOperation],
    newStructure: URLStructure<Int>
  ) -> AnyURLStorage {

    newStructure.checkInvariants()
    let newCount = commands.reduce(into: codeUnits.count) { c, op in
      c += (op.insertedCount - op.subrange.count)
    }

    if AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: newCount, structure: newStructure) {
      // Perform the operations in reverse order to avoid clobbering.
      for command in commands.reversed() {
        codeUnits.unsafeReplaceSubrange(
          command.subrange,
          withUninitializedCapacity: command.insertedCount,
          initializingWith: command.writer
        )
      }
      guard header.copyStructure(from: newStructure) else {
        preconditionFailure("Header didn't accept new structure")
      }
      return AnyURLStorage(self)
    }
    let newStorage = AnyURLStorage(optimalStorageForCapacity: newCount, structure: newStructure) { dest in
      return codeUnits.withUnsafeBufferPointer { src in
        let srcBase = src.baseAddress.unsafelyUnwrapped
        var destHead = dest.baseAddress.unsafelyUnwrapped
        var srcIdx = 0
        for command in commands {
          // Copy from src until command range.
          let bytesToCopyFromSrc = command.subrange.lowerBound - srcIdx
          destHead.initialize(from: srcBase + srcIdx, count: bytesToCopyFromSrc)
          destHead += bytesToCopyFromSrc
          srcIdx += bytesToCopyFromSrc
          assert(srcIdx == command.subrange.lowerBound)
          // Execute command.
          var buffer = UnsafeMutableBufferPointer(start: destHead, count: command.insertedCount)
          let actualBytesWritten = command.writer(&buffer)
          precondition(
            actualBytesWritten == command.insertedCount,
            "Subrange initializer did not initialize the expected number of code-units")
          destHead += actualBytesWritten
          // Advance srcIdx to command end.
          srcIdx = command.subrange.upperBound
        }
        // Copy from end of last command until end of src.
        let bytesToCopyFromSrc = src.endIndex - srcIdx
        destHead.initialize(from: srcBase + srcIdx, count: bytesToCopyFromSrc)
        destHead += bytesToCopyFromSrc
        return dest.baseAddress.unsafelyUnwrapped.distance(to: destHead)
      }
    }
    return newStorage
  }

  /// A generic setter which works for _some_ URL components.
  ///
  /// This is sufficient for components which do not change other components when they are modified.
  /// For example, the query, fragment and port components may be changed without modifying any other parts of the URL.
  /// However, components such as scheme, hostname, username and password require more complex logic
  /// (e.g. when changing the scheme, the port component may also need to be modified; the hostname setter needs to deal with the "//" authority sigil,
  /// and credentials have additional logic for separators). This setter is sufficient for the former kind of components, but **does not include component-specific
  /// logic for the latter kind**.
  ///
  /// If the new value is `nil`, the component is removed (code-units deleted and `URLStructure`'s length-key set to 0).
  /// Otherwise, the component is replaced by `[prefix][encoded-content]`, where `prefix` is a single ASCII character and
  /// `encoded-content` is the accumulated result of transforming the new value by the `encoder` closure.
  /// The `URLStructure`'s length-key is updated to reflect the total length of the new component, including the single-character prefix.
  ///
  ///
  /// - parameters:
  ///   - component: The component to modify.
  ///   - newValue:  The new value of the component.
  ///   - prefix:    A single ASCII character to write before the new value. If `newValue` is not `nil`, this is _always_ written.
  ///   - lengthKey: The `URLStructure` field to update with the component's new length. Said length will include the single-character prefix.
  ///   - encoder:   A closure which encodes the new value for writing in a URL string.
  ///
  ///   - bytes:     The bytes to encode as the component's new content.
  ///   - scheme:    The scheme of the final URL.
  ///   - callback:  A callback through which the `encoder` provides this function with buffers of encoded content to process.
  ///                `callback` does not escape the pointer value, and may be called as many times as needed to encode the content.
  ///
  mutating func setSimpleComponent<Input>(
    _ component: WebURL.Component,
    to newValue: Input?,
    prefix: ASCII,
    lengthKey: WritableKeyPath<URLStructure<Int>, Int>,
    encoder: (_ bytes: Input, _ scheme: WebURL.SchemeKind, _ callback: (UnsafeBufferPointer<UInt8>) -> Void) -> Bool
  ) -> AnyURLStorage where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure

    guard let newBytes = newValue else {
      guard let existingFragment = oldStructure.range(of: component) else {
        return AnyURLStorage(self)
      }
      var newStructure = oldStructure
      newStructure[keyPath: lengthKey] = 0
      return removeSubrange(existingFragment, newStructure: newStructure)
    }

    var bytesToWrite = 1  // leading separator.
    let needsEncoding = encoder(newBytes, oldStructure.schemeKind) { bytesToWrite += $0.count }
    let subrangeToReplace = oldStructure.rangeForReplacingCodeUnits(of: component)
    var newStructure = oldStructure
    newStructure[keyPath: lengthKey] = bytesToWrite

    return replaceSubrange(
      subrangeToReplace,
      withUninitializedSpace: bytesToWrite,
      newStructure: newStructure
    ) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      ptr.pointee = prefix.codePoint
      ptr += 1
      if needsEncoding {
        _ = encoder(newBytes, oldStructure.schemeKind) { piece in
          ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
          ptr += piece.count
        }
      } else {
        let n = UnsafeMutableBufferPointer(start: ptr, count: bytesToWrite - 1).initialize(from: newBytes).1
        ptr += n
      }
      return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
    }
  }
}


// MARK: - AnyURLStorage


/// This enum serves like an existential for a `URLStorage` whose header is one a few known types.
/// It also decides the optimal header type for a URL string with a given structure.
///
/// So why have this type instead of a real existential?
///
/// 1. Existentials don't support generic types. A `URLStorage<?>` is not expressible in Swift (we'd need to duplicate the interface as a protocol).
/// 2. `ManagedArrayBuffer` is a non-trivial struct (it wraps a `ManagedBuffer`), so our protocol couldn't use a `: class` constraint
///   for a more efficient existential.
///
/// And we might as well use the fact that we know the exact header types.
/// It even gets encoded it in the spare bits of the ManagedBuffer pointer (so `MemoryLayout<AnyURLStorage>.stride == 8` on 64-bit),
/// which is pretty cool and reduces our footprint.
///
enum AnyURLStorage {
  case small(URLStorage<GenericURLHeader<UInt8>>)
  case generic(URLStorage<GenericURLHeader<Int>>)
}

// Allocation/Optimal storage types.

extension AnyURLStorage {

  /// Creates a new URL storage object, with the header best suited for a string with the given size and structure.
  ///
  /// The initializer closure must initialize exactly `count` code-units.
  ///
  init(
    optimalStorageForCapacity count: Int,
    structure: URLStructure<Int>,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {

    if count <= UInt8.max {
      let newStorage = URLStorage<GenericURLHeader<UInt8>>(
        count: count, structure: structure, initializingCodeUnitsWith: initializer
      )
      guard let _newStorage = newStorage else {
        preconditionFailure("AnyURLStorage created incorrect header")
      }
      self = .small(_newStorage)
      return
    }
    let genericStorage = URLStorage<GenericURLHeader<Int>>(
      count: count, structure: structure, initializingCodeUnitsWith: initializer
    )
    guard let _genericStorage = genericStorage else {
      preconditionFailure("Failed to create generic URL header")
    }
    self = .generic(_genericStorage)
  }

  static func isOptimalStorageType<T>(
    _ type: URLStorage<T>.Type, requiredCapacity: Int, structure: URLStructure<Int>
  ) -> Bool {
    if requiredCapacity <= UInt8.max {
      return type == URLStorage<GenericURLHeader<UInt8>>.self
    }
    return type == URLStorage<GenericURLHeader<Int>>.self
  }
}

// Erasure.

extension AnyURLStorage {

  init<T>(_ storage: URLStorage<T>) {
    self = T.eraseToAnyURLStorage(storage)
  }
}

// Forwarding.

extension AnyURLStorage {

  var structure: URLStructure<Int> {
    switch self {
    case .small(let storage): return storage.header.structure
    case .generic(let storage): return storage.header.structure
    }
  }

  var schemeKind: WebURL.SchemeKind {
    return structure.schemeKind
  }

  var cannotBeABaseURL: Bool {
    return structure.cannotBeABaseURL
  }

  var pathIncludesDiscriminator: Bool {
    return structure.hasPathSigil
  }

  var entireString: String {
    switch self {
    case .small(let storage): return storage.entireString
    case .generic(let storage): return storage.entireString
    }
  }

  func withEntireString<T>(_ block: (UnsafeBufferPointer<UInt8>) -> T) -> T {
    switch self {
    case .small(let storage): return storage.withEntireString(block)
    case .generic(let storage): return storage.withEntireString(block)
    }
  }

  func withComponentBytes<T>(_ component: WebURL.Component, _ block: (UnsafeBufferPointer<UInt8>?) -> T) -> T {
    switch self {
    case .small(let storage): return storage.withComponentBytes(component, block)
    case .generic(let storage): return storage.withComponentBytes(component, block)
    }
  }

  func stringForComponent(_ component: WebURL.Component) -> String? {
    switch self {
    case .small(let storage): return storage.stringForComponent(component)
    case .generic(let storage): return storage.stringForComponent(component)
    }
  }

  func withAllAuthorityComponentBytes<T>(
    _ block: (
      _ authorityString: UnsafeBufferPointer<UInt8>?,
      _ usernameLength: Int,
      _ passwordLength: Int,
      _ hostnameLength: Int,
      _ portLength: Int
    ) -> T
  ) -> T {
    switch self {
    case .small(let storage): return storage.withAllAuthorityComponentBytes(block)
    case .generic(let storage): return storage.withAllAuthorityComponentBytes(block)
    }
  }
}


// MARK: - GenericURLHeader


/// A marker protocol for integer types supported by `AnyURLStorage` when wrapping a `URLStorage<GenericURLHeader<T>>`.
///
protocol AnyURLStorageErasableGenericHeaderSize: FixedWidthInteger {

  /// Wraps the given `storage` in the appropriate `AnyURLStorage`.
  ///
  static func _eraseToAnyURLStorage(_ storage: URLStorage<GenericURLHeader<Self>>) -> AnyURLStorage
}

extension Int: AnyURLStorageErasableGenericHeaderSize {
  static func _eraseToAnyURLStorage(_ storage: URLStorage<GenericURLHeader<Int>>) -> AnyURLStorage {
    return .generic(storage)
  }
}

extension UInt8: AnyURLStorageErasableGenericHeaderSize {
  static func _eraseToAnyURLStorage(_ storage: URLStorage<GenericURLHeader<UInt8>>) -> AnyURLStorage {
    return .small(storage)
  }
}

/// A `ManagedBufferHeader` containing a complete `URLStructure` and size-appropriate `count` and `capacity` fields.
///
struct GenericURLHeader<SizeType: FixedWidthInteger> {
  private var _count: SizeType
  private var _capacity: SizeType
  private var _structure: URLStructure<SizeType>

  init(_count: SizeType, _capacity: SizeType, structure: URLStructure<SizeType>) {
    self._count = _count
    self._capacity = _capacity
    self._structure = structure
  }

  init() {
    self = .init(_count: 0, _capacity: 0, structure: .init())
  }

  private static func closestAddressableCapacity(to idealCapacity: Int) -> SizeType {
    if idealCapacity <= Int(SizeType.max) {
      return SizeType(idealCapacity)
    } else {
      return SizeType.max
    }
  }

  private static func supports(count: Int) -> Bool {
    return Int(Self.closestAddressableCapacity(to: count)) >= count
  }
}

extension GenericURLHeader: ManagedBufferHeader {

  var count: Int {
    get { return Int(_count) }
    set { _count = SizeType(newValue) }
  }

  var capacity: Int {
    return Int(_capacity)
  }

  func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> Self? {
    let newCapacity = Self.closestAddressableCapacity(to: maximumCapacity)
    guard newCapacity >= minimumCapacity else {
      return nil
    }
    return Self(_count: _count, _capacity: newCapacity, structure: _structure)
  }
}

extension GenericURLHeader: URLHeader where SizeType: AnyURLStorageErasableGenericHeaderSize {

  static func eraseToAnyURLStorage(_ storage: URLStorage<Self>) -> AnyURLStorage {
    return SizeType._eraseToAnyURLStorage(storage)
  }

  init?(count: Int, structure: URLStructure<Int>) {
    guard Self.supports(count: count) else { return nil }
    let sz_count = SizeType(truncatingIfNeeded: count)
    self = .init(
      _count: sz_count,
      _capacity: sz_count,
      structure: URLStructure<SizeType>(copying: structure)
    )
  }

  mutating func copyStructure(from newStructure: URLStructure<Int>) -> Bool {
    self._structure = .init(copying: newStructure)
    return true
  }

  var structure: URLStructure<Int> {
    return URLStructure(copying: _structure)
  }
}
