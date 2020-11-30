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
///  [scheme + ":"] + ["//"]? + [username]? + [":" + password]? + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
struct URLStructure<SizeType: FixedWidthInteger> {

  var schemeLength: SizeType
  var usernameLength: SizeType
  var passwordLength: SizeType
  var hostnameLength: SizeType
  var portLength: SizeType
  // if path, query or fragment are not 0, they must contain their leading separators ('/', '?', '#').
  var pathLength: SizeType
  var queryLength: SizeType
  var fragmentLength: SizeType

  var hasAuthority: Bool
  var schemeKind: WebURL.SchemeKind
  var cannotBeABaseURL: Bool

  func checkInvariants() -> Bool {
    guard schemeLength >= 1 else { return false }
    guard passwordLength != 1 else { return false }
    guard portLength != 1 else { return false }
    guard pathLength != 1 else { return false }
    guard queryLength != 1 else { return false }
    guard fragmentLength != 1 else { return false }
    return true
  }
}

extension URLStructure {

  init() {
    self.schemeLength = 0
    self.usernameLength = 0
    self.passwordLength = 0
    self.hostnameLength = 0
    self.portLength = 0
    self.pathLength = 0
    self.queryLength = 0
    self.fragmentLength = 0
    self.hasAuthority = false
    self.schemeKind = .other
    self.cannotBeABaseURL = false
  }

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
      hasAuthority: otherStructure.hasAuthority,
      schemeKind: otherStructure.schemeKind,
      cannotBeABaseURL: otherStructure.cannotBeABaseURL
    )
  }
}

extension URLStructure {

  var schemeStart: SizeType {
    assert(schemeLength >= 1, "URLs must always have a scheme")
    return 0
  }
  var schemeEnd: SizeType {
    assert(schemeLength >= 1, "URLs must always have a scheme")
    return schemeStart &+ schemeLength
  }

  // Authority may or may not be present.
  // - If present, it starts at schemeEnd + 2 ('//').
  //   - It may be an empty string for non-special URLs ("pop://?hello").
  // - If not present, do not add double solidus ("pop:?hello").

  var authorityStart: SizeType {
    return schemeEnd &+ (hasAuthority ? 2 : 0 /* // */)
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

  // Components with leading separators.
  // The 'start' position is the offset of the separator character ('/','?','#'), and
  // this additional character is included in the component's length.
  // Non-present components have a length of 0.

  // For example, "pop://example.com" has a queryLength of 0, but "pop://example.com?" has a queryLength of 1.
  // The former has a 'nil'' query component, the latter has an empty query component.
  // The parser has to preserve the separator, even if the component is empty.

  /// Returns the end of the authority section, if one is present.
  /// Any trailing components (path, query, fragment) start from here.
  ///
  var pathStart: SizeType {
    return hasAuthority ? (portStart &+ portLength) : schemeEnd
  }

  /// Returns the position of the leading '?' in the query-string, if one is present. Otherwise, returns the position after the path.
  /// All query strings start with a '?'.
  ///
  var queryStart: SizeType {
    return pathStart &+ pathLength
  }

  /// Returns the position of the leading '#' in the fragment, if one is present. Otherwise, returns the position after the query-string.
  /// All fragments start with a '#'.
  ///
  var fragmentStart: SizeType {
    return queryStart &+ queryLength
  }

  /// Returns the range of bytes which contain the given component.
  ///
  /// If the component is not present, this method returns an empty range starting at the place where component was expected to be found.
  ///
  func rangeForReplacement(of component: WebURL.Component) -> Range<SizeType> {
    let start: SizeType
    let length: SizeType
    switch component {
    case .scheme:
      assert(schemeLength > 1)
      return Range(uncheckedBounds: (schemeStart, schemeEnd))
    case .hostname:
      start = hostnameStart
      length = hostnameLength
    case .username:
      start = usernameStart
      length = usernameLength
    case .password:
      assert(passwordLength != 1, "Lone ':' separator is not a valid password component")
      start = passwordStart
      length = passwordLength
    case .port:
      assert(portLength != 1, "Lone ':' separator is not a valid port component")
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
      preconditionFailure("Unknown component")
    }
    return Range(uncheckedBounds: (start, start &+ length))
  }

  /// Returns the range of the entire authority string, if one is present.
  ///
  var rangeOfAuthorityString: Range<SizeType>? {
    guard hasAuthority else { return nil }
    return Range(uncheckedBounds: (authorityStart, pathStart))
  }

  /// Returns the range of bytes which contain the given component.
  ///
  /// If the component is not present, this method returns `nil`.
  ///
  func range(of component: WebURL.Component) -> Range<SizeType>? {
    let range = rangeForReplacement(of: component)
    switch component {
    // Hostname may be empty.
    case .hostname:
      guard hasAuthority else { return nil }
    // Username may not be empty.
    case .username:
      guard usernameLength != 0 else { return nil }
      assert(hasAuthority)
    // The following components always have a leading separator, so:
    // - (length == 0) -> not present.
    // - (length == 1) -> separator with no content (e.g. "sc://x?" has a present, empty query).
    case .password:
      guard passwordLength != 0 else { return nil }
      assert(hasAuthority)
    case .port:
      guard portLength != 0 else { return nil }
      assert(hasAuthority)
    case .path:
      guard pathLength != 0 else { return nil }
    case .query:
      guard queryLength != 0 else { return nil }
    case .fragment:
      guard fragmentLength != 0 else { return nil }
    default:
      assert(component == .scheme, "Unknown component")
    }
    return range
  }
}

extension URLStructure {

  // If the string has credentials, it must contain a '@' separating them from the hostname.
  var hasCredentialSeparator: Bool {
    return usernameLength != 0 || passwordLength != 0
  }

  var cannotHaveCredentialsOrPort: Bool {
    return schemeKind == .file || cannotBeABaseURL || hostnameLength == 0
  }
}


// MARK: - URLStorage.


/// A `ManagedBufferHeader` which stores information about a URL string.
///
/// URLs are stored in `URLStorage` objects, which are managed buffers containing the string's contiguous code-units, prefixed by
/// an instance of a type conforming to `URLHeader`. The `AnyURLStorage` wrapper allows this header type to be erased, so that the
/// optimal header can be chosen for a given URL string.
///
/// For example, small URL strings might wish to store their header information in a smaller integer type than `Int64` on 64-bit platforms.
/// Similarly, some common URL patterns (e.g. `file://` URLs with only a path) might warrant their own headers: with the string's structure essentially
/// being completely described by the header type, we might decide to store some other information in the header, such as path metrics.
///
/// When a URL String is parsed, or when a mutation on an already-parsed URL is planned, the parser or setter function first calculates
/// a _required capacity_, and a `URLStructure<Int>`.
///
/// - For mutations, `AnyURLStorage.isOptimalStorageType(_:requiredCapacity:structure:)` is consulted to check if the existing
///   header type is also the desired header for the result. If it is, the capacity is sufficient and the storage reference is unique, the modification happens in-place.
/// - Otherwise, if the storage types do not match, or there is no existing storage to mutate (in the case of the parser),
///   `AnyURLStorage(optimalStorageForCapacity:structure:initializingCodeUnitsWith:)` is used to create storage with a compatible
///   header type.
///
/// But very bad things are likely to happen if that logic ever goes out of sync. So headers **must** double-check it.
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
/// `URLStorage` wraps a `ManagedArrayBuffer` containing the string's contiguous code-units, together with a header structure that encodes the URL's
/// structure. It composes operations on each component in to URL-level operations (such as getting or setting the 'username' component).
/// `URLStorage` is a value-type, with attempted mutations happening in-place where possible and copying to new storage only when the buffer is shared
/// or if its capacity is insufficient to hold the result.
///
/// Mutating functions must take care of the following notes:
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

  var schemeKind: WebURL.SchemeKind {
    return header.structure.schemeKind
  }

  var cannotBeABaseURL: Bool {
    return header.structure.cannotBeABaseURL
  }

  func withEntireString<T>(_ block: (UnsafeBufferPointer<UInt8>) -> T) -> T {
    return codeUnits.withUnsafeBufferPointer(block)
  }

  var entireString: String {
    return withEntireString { String(decoding: $0, as: UTF8.self) }
  }

  func withComponentBytes<T>(_ component: WebURL.Component, _ block: (UnsafeBufferPointer<UInt8>?) -> T) -> T {
    guard let range = header.structure.range(of: component) else { return block(nil) }
    return codeUnits.withElements(range: Range(uncheckedBounds: (range.lowerBound, range.upperBound)), block)
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


// MARK: - Setters.


extension URLStorage {

  /// Replaces the given range of code-units with an uninitialized space, which is then initialized by the given closure.
  /// The URL's structure is also replaced with the given new structure. If the existing storage is not optimal for the new structure,
  /// the storage will be replaced with the optimal kind.
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
  private mutating func replaceSubrange(
    _ subrangeToReplace: Range<Int>,
    withUninitializedSpace insertCount: Int,
    newStructure: URLStructure<Int>,
    initializer: (inout UnsafeMutableBufferPointer<UInt8>) -> Int
  ) -> AnyURLStorage {

    let newCount = codeUnits.count - subrangeToReplace.count + insertCount

    if AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: newCount, structure: newStructure) {
      codeUnits.unsafeReplaceSubrange(
        subrangeToReplace, withUninitializedCapacity: insertCount, initializingWith: initializer
      )
      guard header.copyStructure(from: newStructure) else {
        preconditionFailure("AnyURLStorage.isOptimalStorageType returned true for an incompatible header/string")
      }
      return AnyURLStorage(self)
    }
    let newStorage = AnyURLStorage(optimalStorageForCapacity: newCount, structure: newStructure) { dest in
      return codeUnits.withUnsafeBufferPointer { src in
        dest.initialize(from: src, replacingSubrange: subrangeToReplace, withElements: insertCount) { rgnStart, count in
          var rgnPtr = UnsafeMutableBufferPointer(start: rgnStart, count: count)
          let written = initializer(&rgnPtr)
          precondition(written == count)
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
  private mutating func removeSubrange(
    _ subrangeToRemove: Range<Int>, newStructure: URLStructure<Int>
  ) -> AnyURLStorage {
    return replaceSubrange(subrangeToRemove, withUninitializedSpace: 0, newStructure: newStructure) { _ in 0 }
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
  private mutating func setSimpleComponent<Input>(
    _ component: WebURL.Component,
    to newValue: Input?,
    prefix: ASCII,
    lengthKey: WritableKeyPath<URLStructure<Int>, Int>,
    encoder: (_ bytes: Input, _ scheme: WebURL.SchemeKind, _ callback: (UnsafeBufferPointer<UInt8>) -> Void) -> Bool
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure

    guard let newBytes = newValue else {
      guard let existingFragment = oldStructure.range(of: component) else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure[keyPath: lengthKey] = 0
      return (true, removeSubrange(existingFragment, newStructure: newStructure))
    }

    var bytesToWrite = 1  // leading separator.
    let needsEncoding = encoder(newBytes, oldStructure.schemeKind) { bytesToWrite += $0.count }
    let subrangeToReplace = oldStructure.rangeForReplacement(of: component)
    var newStructure = oldStructure
    newStructure[keyPath: lengthKey] = bytesToWrite

    let result = replaceSubrange(
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
    return (true, result)
  }
}

extension URLStorage {

  /// Attempts to set the scheme component to the given UTF8-encoded string.
  /// The new value may contain a trailing colon (e.g. `http`, `http:`). Colons are only allowed as the last character of the string.
  ///
  /// - Note: Filtering ASCII tab and newline characters is not needed as those characters cannot be included in a scheme, and schemes cannot
  ///         contain percent encoding.
  ///
  mutating func setScheme<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    guard let idx = findScheme(newValue),  // Checks scheme contents.
      idx == newValue.endIndex || newValue.index(after: idx) == newValue.endIndex,  // No content after scheme.
      idx != newValue.startIndex  // Scheme cannot be empty.
    else {
      return (false, AnyURLStorage(self))
    }
    let newSchemeBytes = newValue[..<idx]

    let oldStructure = header.structure
    var newStructure = oldStructure
    newStructure.schemeKind = WebURL.SchemeKind(parsing: newSchemeBytes)
    newStructure.schemeLength = newSchemeBytes.count + 1

    if newStructure.schemeKind.isSpecial != oldStructure.schemeKind.isSpecial {
      return (false, AnyURLStorage(self))
    }
    if newStructure.schemeKind == .file, oldStructure.hasCredentialSeparator || oldStructure.portLength != 0 {
      return (false, AnyURLStorage(self))
    }
    if oldStructure.schemeKind == .file, oldStructure.hostnameLength == 0 {
      return (false, AnyURLStorage(self))
    }
    // The operation is semantically valid.

    // If the current port is the default for the new scheme, it must be removed as part of the scheme change operation
    // (e.g. "http://example.com:21" -> "ftp://example.com").
    // If we don't need to remove the port, this operation is just a simple code-unit replacement.
    let mustRemovePort: Bool = withComponentBytes(.port) {
      guard let portBytes = $0 else { return false }
      assert(portBytes.count > 1, "invalid URLStructure: port must either be nil or >1 character")
      return newStructure.schemeKind.isDefaultPortString(portBytes.dropFirst())
    }
    guard mustRemovePort else {
      let result = replaceSubrange(
        oldStructure.rangeForReplacement(of: .scheme),
        withUninitializedSpace: newStructure.schemeLength,
        newStructure: newStructure
      ) { subrange in
        let bytesWritten = subrange.initialize(from: ASCII.Lowercased(newSchemeBytes)).1
        subrange[bytesWritten] = ASCII.colon.codePoint
        return bytesWritten + 1
      }
      return (true, result)
    }

    newStructure.portLength = 0
    let newCount = header.count + (newStructure.schemeLength - oldStructure.schemeLength) - oldStructure.portLength

    if AnyURLStorage.isOptimalStorageType(Self.self, requiredCapacity: newCount, structure: newStructure) {
      // Remove port first to avoid clobbering.
      codeUnits.removeSubrange(oldStructure.rangeForReplacement(of: .port))
      codeUnits.unsafeReplaceSubrange(
        oldStructure.rangeForReplacement(of: .scheme),
        withUninitializedCapacity: newStructure.schemeLength
      ) { buffer in
        let bytesWritten = buffer.initialize(from: ASCII.Lowercased(newSchemeBytes)).1
        buffer[bytesWritten] = ASCII.colon.codePoint
        return bytesWritten + 1
      }
      guard header.copyStructure(from: newStructure) else {
        preconditionFailure("Failed to update URL structure")
      }
      return (true, AnyURLStorage(self))
    }
    // swift-format-ignore
    let result = AnyURLStorage(optimalStorageForCapacity: newCount, structure: newStructure) { dest in
      self.codeUnits.withUnsafeBufferPointer { src in
        let srcSchemeRange = oldStructure.rangeForReplacement(of: .scheme)
        let srcPortRange = oldStructure.rangeForReplacement(of: .port)

        var bytesWritten = dest.initialize(from: ASCII.Lowercased(newSchemeBytes)).1
        dest[bytesWritten] = ASCII.colon.codePoint
        bytesWritten += 1
        bytesWritten += UnsafeMutableBufferPointer(rebasing: dest.suffix(from: bytesWritten))
          .initialize(from: UnsafeBufferPointer(rebasing: src[srcSchemeRange.upperBound..<srcPortRange.lowerBound])).1
        bytesWritten += UnsafeMutableBufferPointer(rebasing: dest.suffix(from: bytesWritten))
          .initialize(from: UnsafeBufferPointer(rebasing: src[srcPortRange.upperBound...])).1
        return bytesWritten
      }
    }
    return (true, result)
  }

  /// Attempts to set the username component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  mutating func setUsername<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }
    // The operation is semantically valid.

    guard newValue.isEmpty == false else {
      guard let oldUsername = oldStructure.range(of: .username) else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure.usernameLength = 0
      let toRemove = oldUsername.lowerBound..<(oldUsername.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (true, removeSubrange(toRemove, newStructure: newStructure))
    }

    var newStructure = oldStructure
    newStructure.usernameLength = 0
    let needsEncoding = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered {
      newStructure.usernameLength += $0.count
    }
    let shouldAddSeparator = (oldStructure.hasCredentialSeparator == false)
    let bytesToWrite = newStructure.usernameLength + (shouldAddSeparator ? 1 : 0)
    let toReplace = oldStructure.rangeForReplacement(of: .username)
    let result = replaceSubrange(toReplace, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      if needsEncoding {
        newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered { piece in
          ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
          ptr += piece.count
        }
      } else {
        ptr += UnsafeMutableBufferPointer(start: ptr, count: newStructure.usernameLength).initialize(from: newValue).1
      }
      if shouldAddSeparator {
        ptr.pointee = ASCII.commercialAt.codePoint
        ptr += 1
      }
      return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
    }
    return (true, result)
  }

  /// Attempts to set the password component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// - Note: Usernames and Passwords are never filtered of ASCII tab or newline characters.
  ///         If the given `newValue` contains any such characters, they will be percent-encoded in to the result.
  ///
  mutating func setPassword<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }
    // The operation is semantically valid.

    guard newValue.isEmpty == false else {
      guard let oldPassword = oldStructure.range(of: .password) else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure.passwordLength = 0
      let toRemove = oldPassword.lowerBound..<(oldPassword.upperBound + (newStructure.hasCredentialSeparator ? 0 : 1))
      return (true, removeSubrange(toRemove, newStructure: newStructure))
    }

    var newStructure = oldStructure
    newStructure.passwordLength = 1  // leading ":"
    let needsEncoding = newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered {
      newStructure.passwordLength += $0.count
    }
    let bytesToWrite = newStructure.passwordLength + 1  // Always write the trailing "@".
    var toReplace = oldStructure.rangeForReplacement(of: .password)
    toReplace = toReplace.lowerBound..<toReplace.upperBound + (oldStructure.hasCredentialSeparator ? 1 : 0)

    let result = replaceSubrange(toReplace, withUninitializedSpace: bytesToWrite, newStructure: newStructure) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      ptr.pointee = ASCII.colon.codePoint
      ptr += 1
      if needsEncoding {
        newValue.lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).writeBuffered { piece in
          ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
          ptr += piece.count
        }
      } else {
        // swift-format-ignore
        ptr += UnsafeMutableBufferPointer(start: ptr, count: newStructure.passwordLength - 1)
          .initialize(from: newValue).1
      }
      ptr.pointee = ASCII.commercialAt.codePoint
      ptr += 1
      return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
    }
    return (true, result)
  }

  /// Attempts to set the hostname component to the given UTF8-encoded string. The value will be percent-encoded as appropriate.
  ///
  /// Setting the hostname to an empty or `nil` value is only possible when there are no other authority components (credentials or port).
  /// An empty hostname preserves the `//` separator after the scheme, but the authority component will be empty (e.g. `unix://oldhost/some/path` -> `unix:///some/path`).
  /// A `nil` hostname removes the `//` separator after the scheme, resulting in a so-called "path-only" URL (e.g. `unix://oldhost/some/path` -> `unix:/some/path`).
  ///
  mutating func setHostname<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: BidirectionalCollection, Input.Element == UInt8 {

    precondition(newValue != nil, "Removing authority sigil has not been tested")
    guard filter == false || newValue == nil else {
      return setHostname(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (newValue == nil, AnyURLStorage(self))
    }
    // Excluding 'cannotBeABaseURL' URLs doesn't mean we always have an authority separator.
    // There are also path-only URLs (e.g. "hello:/some/path" is not a cannotBeABaseURL).
    let hasCredentialsOrPort =
      oldStructure.usernameLength != 0 || oldStructure.passwordLength != 0 || oldStructure.portLength != 0

    guard let newHostnameBytes = newValue, newHostnameBytes.isEmpty == false else {
      if oldStructure.schemeKind.isSpecial, oldStructure.schemeKind != .file {
        return (false, AnyURLStorage(self))
      }
      guard hasCredentialsOrPort == false else {
        return (false, AnyURLStorage(self))
      }
      switch oldStructure.range(of: .hostname) {
      case .none:
        assert(oldStructure.hasAuthority == false)
        guard newValue != nil else {
          return (true, AnyURLStorage(self))
        }
        // 'nil' -> empty host. Insert authority sigil.
        var newStructure = oldStructure
        newStructure.hostnameLength = 0
        newStructure.hasAuthority = true
        let result = replaceSubrange(
          oldStructure.authorityStart..<oldStructure.authorityStart,
          withUninitializedSpace: 2,
          newStructure: newStructure
        ) { buffer in
          buffer.initialize(repeating: ASCII.forwardSlash.codePoint)
          return 2
        }
        return (true, result)

      case .some(var hostnameRange):
        assert(oldStructure.hasAuthority)
        var newStructure = oldStructure
        newStructure.hostnameLength = 0
        if newValue == nil {
          // * -> 'nil' host. Remove authority sigil.
          newStructure.hasAuthority = false
          hostnameRange = (hostnameRange.lowerBound - 2)..<hostnameRange.upperBound
        }
        return (true, removeSubrange(hostnameRange, newStructure: newStructure))
      }
    }

    var callback = IgnoreValidationErrors()
    guard let newHost = ParsedHost(newHostnameBytes, schemeKind: oldStructure.schemeKind, callback: &callback) else {
      return (false, AnyURLStorage(self))
    }

    var newStructure = oldStructure
    newStructure.hasAuthority = true

    var counter = HostnameLengthCounter()
    newHost.write(bytes: newHostnameBytes, using: &counter)
    newStructure.hostnameLength = counter.length

    let shouldAddAuthoritySigil = (oldStructure.hasAuthority == false)
    let bytesToWrite = (shouldAddAuthoritySigil ? 2 : 0) + newStructure.hostnameLength

    let result = replaceSubrange(
      oldStructure.rangeForReplacement(of: .hostname),
      withUninitializedSpace: bytesToWrite,
      newStructure: newStructure
    ) { dest in
      guard var ptr = dest.baseAddress else { return 0 }
      if shouldAddAuthoritySigil {
        // 'nil' -> non-empty host. Insert authority sigil.
        // TODO: Strip discriminator from path if present.
        ptr.initialize(repeating: ASCII.forwardSlash.codePoint, count: 2)
        ptr = ptr + 2
      }
      var writer = UnsafeBufferHostnameWriter(buffer: UnsafeMutableBufferPointer(start: ptr, count: counter.length))
      newHost.write(bytes: newHostnameBytes, using: &writer)
      ptr = writer.buffer.baseAddress.unsafelyUnwrapped
      return dest.baseAddress.unsafelyUnwrapped.distance(to: ptr)
    }
    return (true, result)
  }

  /// Attempts to set the port component to the given value. A value of `nil` removes the port.
  ///
  mutating func setPort(
    to newValue: UInt16?
  ) -> (Bool, AnyURLStorage) {

    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }

    var newValue = newValue
    if newValue == oldStructure.schemeKind.defaultPort {
      newValue = nil
    }

    guard let newPort = newValue else {
      return setSimpleComponent(
        .port,
        to: UnsafeBufferPointer?.none,
        prefix: .colon,
        lengthKey: \.portLength,
        encoder: { _, _, _ in preconditionFailure("Cannot encode 'nil' contents") }
      )
    }
    // TODO: More efficient UInt16 serialisation.
    var serialized = String(newPort)
    return serialized.withUTF8 { ptr in
      assert(ptr.isEmpty == false)
      return setSimpleComponent(
        .port,
        to: ptr,
        prefix: .colon,
        lengthKey: \.portLength,
        encoder: { bytes, _, callback in
          callback(bytes)
          return false
        }
      )
    }
  }

  /// Attempts to set the path component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the path.
  /// If `filter` is `true`, ASCII tab and newline characters in the given value will be ignored.
  ///
  mutating func setPath<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: BidirectionalCollection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setPath(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }

    let oldStructure = header.structure
    guard oldStructure.cannotBeABaseURL == false else {
      return (false, AnyURLStorage(self))
    }

    guard let newPath = newValue else {
      // URLs with special schemes must always have a path. Possibly replace this with an empty path?
      guard schemeKind.isSpecial == false else {
        return (false, AnyURLStorage(self))
      }
      return setSimpleComponent(
        .path,
        to: UnsafeBufferPointer?.none,
        prefix: .forwardSlash,
        lengthKey: \.pathLength,
        encoder: { _, _, _ in preconditionFailure("Cannot encode nil input") }
      )
    }

    let pathInfo = PathMetrics(
      parsing: newPath, schemeKind: oldStructure.schemeKind, hasAuthority: oldStructure.hasAuthority, baseURL: nil
    )
    var newStructure = oldStructure
    newStructure.pathLength = pathInfo.requiredCapacity
    let result = replaceSubrange(
      oldStructure.rangeForReplacement(of: .path),
      withUninitializedSpace: pathInfo.requiredCapacity,
      newStructure: newStructure
    ) { dest in
      return dest.writeNormalizedPath(
        parsing: newPath, schemeKind: newStructure.schemeKind, hasAuthority: newStructure.hasAuthority,
        baseURL: nil, needsEscaping: pathInfo.needsEscaping
      )
    }
    return (true, result)
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query. If `filter` is `true`, ASCII tab and newline characters will be removed from the given string.
  ///
  mutating func setQuery<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setQuery(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }
    return setSimpleComponent(
      .query,
      to: newValue,
      prefix: .questionMark,
      lengthKey: \.queryLength,
      encoder: { writeBufferedPercentEncodedQuery($0, isSpecial: $1.isSpecial, $2) }
    )
  }

  /// Attempts to set the query component to the given UTF8-encoded string.
  ///
  /// A value of `nil` removes the query. If `filter` is `true`, ASCII tab and newline characters will be removed from the given string.
  ///
  mutating func setFragment<Input>(
    to newValue: Input?,
    filter: Bool = false
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {

    guard filter == false || newValue == nil else {
      return setFragment(to: newValue.map { ASCII.NewlineAndTabFiltered($0) }, filter: false)
    }
    return setSimpleComponent(
      .fragment,
      to: newValue,
      prefix: .numberSign,
      lengthKey: \.fragmentLength,
      encoder: { $0.lazy.percentEncoded(using: URLEncodeSet.Fragment.self).writeBuffered($2) }
    )
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

  var schemeKind: WebURL.SchemeKind {
    switch self {
    case .small(let storage): return storage.schemeKind
    case .generic(let storage): return storage.schemeKind
    }
  }

  var cannotBeABaseURL: Bool {
    switch self {
    case .small(let storage): return storage.cannotBeABaseURL
    case .generic(let storage): return storage.cannotBeABaseURL
    }
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
