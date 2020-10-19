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
  var schemeKind: WebURL.Scheme
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

  /// Returns the range of the entire authority string, if one is present.
  ///
  var rangeOfAuthorityString: Range<SizeType>? {
    guard hasAuthority else { return nil }
    return Range(uncheckedBounds: (authorityStart, pathStart))
  }

  func rangeOfComponent(_ component: WebURL.Component) -> Range<SizeType>? {
    let start: SizeType
    let length: SizeType
    switch component {
    case .scheme:
      assert(schemeLength > 1)
      return Range(uncheckedBounds: (schemeStart, schemeEnd))
    case .hostname:
      guard hasAuthority else { return nil }
      start = hostnameStart
      length = hostnameLength

    // Components with leading/trailing separators.
    //
    // Username & Password make no distinction between empty and nil values, because lone separators are not preserved.
    // e.g. "http://:@test.com" -> "http://test.com".
    case .username:
      guard usernameLength != 0 else { return nil }
      assert(hasAuthority)
      start = usernameStart
      length = usernameLength
    // passwordLength and portLength include the leading separator, but lone separators are removed.
    // i.e. we should never see a length of 1. A length of 0 means a nil value.
    case .password:
      assert(passwordLength != 1)
      guard passwordLength != 0 else { return nil }
      assert(hasAuthority)
      start = passwordStart
      length = passwordLength
    case .port:
      assert(portLength != 1)
      guard portLength != 0 else { return nil }
      assert(hasAuthority)
      start = portStart
      length = portLength
    // Lone separators may be preserved for these components. We may see a length of 1.
    case .path:
      guard pathLength != 0 else { return nil }
      start = pathStart
      length = pathLength
    case .query:
      guard queryLength != 0 else { return nil }
      start = queryStart
      length = queryLength
    case .fragment:
      guard fragmentLength != 0 else { return nil }
      start = fragmentStart
      length = fragmentLength
    default:
      preconditionFailure("Unknown component")
    }
    return Range(uncheckedBounds: (start, start &+ length))
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
/// Headers must ensure that they can losslessly encode the structure given in their initializers or set via `copyStructure`.
/// This should never happen in practice, due to logic in:
///
/// - `AnyURLStorage(creatingOptimalStorageFor:metrics:initializingCodeUnitsWith:)`, which must always allocate storage which
///    supports the URL structure it was given, and
/// - `AnyURLStorage.isOptimalStorageType(_:for:metrics:)`, which must always consider an incompatible header/structure combination
///    _sub-optimal_.
///
/// But very bad things are likely to happen if that logic ever goes out of sync. So headers **must** double-check it.
///
protocol URLHeader: ManagedBufferHeader {
  
  /// Returns a `AnyURLStorage` which erases this header type from the given `URLStorage` instance.
  ///
  /// - Note: This means the only types that may conform to this protocol are those supported by `AnyURLStorage`.
  ///
  static func eraseToAnyURLStorage(_ storage: URLStorage<Self>) -> AnyURLStorage
    
  /// Creates a new header with the given count, capacity, structure and metrics.
  ///
  /// This initializer must return `nil` if it is unable to losslessly store the count, capacity and structure.
  /// It is not required to losslessly store the given metrics.
  ///
  init?(count: Int, capacity: Int, structure: URLStructure<Int>, metrics: URLMetrics)

  /// Updates the header's structure and metrics to reflect some change to the code-units before or after this call.
  ///
  /// This initializer must return `false` if it is unable to losslessly store the structure.
  /// It is not required to losslessly store the given metrics.
  ///
  /// - Note: This does not change the header's `count` or `capacity`, which the code modifying the code-units is expected to maintain.
  ///
  mutating func copyStructure(from newStructure: URLStructure<Int>, metrics: URLMetrics) -> Bool
  
  /// The structure of the URL string contained in this header's associated buffer.
  ///
  var structure: URLStructure<Int> { get }
  
  /// Metrics about the URL string contained in this header's associated buffer.
  /// The default implementation returns a metrics object whose `requiredCapacity` is equal to the header's `count`.
  ///
  var metrics: URLMetrics { get }
}

extension URLHeader {
  
  var metrics: URLMetrics {
    return URLMetrics(requiredCapacity: count)
  }
}

/// The primary type responsible for URL storage.
///
/// `URLStorage` wraps a `ManagedArrayBuffer` containing the string's contiguous code-units, prefixed by an instance of some `URLHeader`.
/// It coordinates changes to the code-units with changes to the `URLStructure` stored by the header to enable URL-level operations
/// (such as setting the 'username' component). `URLStorage` is a value-type, with attempted mutations to non-uniquely-referenced storage triggering
/// a copy to unique storage.
///
/// Mutating functions must take care of the following notes:
///
/// - The header type may not be able to support arbitrary URLs. Setters should calculate the `URLStructure` (and, if possible, the `URLMetrics`)
///   of the final URL string and call `AnyURLStorage.isOptimalStorageType(_:for:metrics:)` before making any changes.
/// - Should a change of header be required, `AnyURLStorage(creatingOptimalStorageFor:metrics:initializingCodeUnitsWith:)`
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
  
  /// Allocates new storage, with the capacity given by `metrics.requiredCapacity`,
  /// and initializes the header using the given `structure` and `metrics`.
  /// The `initializer` closure is invoked to write the code-units, and must return the number of code-units initialized.
  ///
  /// This initializer fails if the header cannot be constructed from the given `structure` and `metrics`.
  ///
  init?(
    structure: URLStructure<Int>,
    metrics: URLMetrics,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>)->Int
  ) {
    do {
      self.codeUnits = try ManagedArrayBuffer(unsafeUninitializedCapacity: metrics.requiredCapacity) { buffer in
        let count = initializer(&buffer)
        guard let header = Header(count: count, capacity: buffer.count, structure: structure, metrics: metrics) else {
          buffer.baseAddress.unsafelyUnwrapped.deinitialize(count: count)
          throw HeaderCreationError.unsupportedURLString
        }
        return header
      }
    } catch {
      return nil
    }
  }
}

/// An error thrown and caught within `URLStorage.init?(structure:metrics:initializingCodeUnitsWith:)`,
/// in order to abort construction of its `ManagedArrayBuffer`.
///
private enum HeaderCreationError: Error {
  case unsupportedURLString
}


// MARK: - Getters.


extension URLStorage {
  
  var schemeKind: WebURL.Scheme {
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
    guard let range = header.structure.rangeOfComponent(component) else { return block(nil) }
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
  
  fileprivate mutating func replaceSubrange(
    _ subrangeToReplace: Range<Int>,
    newElementCount: Int,
    newStructure: URLStructure<Int>, newMetrics: URLMetrics,
    initializingSubrangeWith subrangeInitializer: (inout UnsafeMutableBufferPointer<UInt8>)->Int
  ) -> AnyURLStorage {
    
    if AnyURLStorage.isOptimalStorageType(Self.self, for: newStructure, metrics: newMetrics) {
      codeUnits.unsafeReplaceSubrange(subrangeToReplace, withUninitializedCapacity: newElementCount,
                                      initializingWith: subrangeInitializer)
      guard header.copyStructure(from: newStructure, metrics: newMetrics) else {
        preconditionFailure("AnyURLStorage.isOptimalStorageType returned true for an incompatible header/string")
      }
      return AnyURLStorage(self)
    } else {
      let newStorage = AnyURLStorage(creatingOptimalStorageFor: newStructure, metrics: newMetrics) { dest in
        return codeUnits.withUnsafeBufferPointer { src in
          dest.initialize(from: src, replacingSubrange: subrangeToReplace, withElements: newElementCount) { rgnStart, count in
            var rgnPtr = UnsafeMutableBufferPointer(start: rgnStart, count: count)
            let written = subrangeInitializer(&rgnPtr)
            precondition(written == count)
          }
        }
      }
      assert(newStorage.withEntireString { $0.count } == newMetrics.requiredCapacity)
      return newStorage
    }
  }
  
  fileprivate mutating func removeSubrange(
    _ subrangeToRemove: Range<Int>, newStructure: URLStructure<Int>, newMetrics: URLMetrics
  ) -> AnyURLStorage {
    return replaceSubrange(subrangeToRemove, newElementCount: 0, newStructure: newStructure, newMetrics: newMetrics,
                           initializingSubrangeWith: { _ in 0 })
  }
  
  
  
  mutating func setUsername<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {
    
    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }
    
    // Empty usernames are removed.
    guard newValue.isEmpty == false else {
      guard oldStructure.usernameLength != 0 else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure.usernameLength = 0
      let subrangeToRemove = oldStructure.usernameStart..<(oldStructure.passwordStart + (newStructure.hasCredentialSeparator ? 0 : 1))
      let newMetrics = URLMetrics(requiredCapacity: header.count - subrangeToRemove.count)
      
      return (true, removeSubrange(subrangeToRemove, newStructure: newStructure, newMetrics: newMetrics))
    }
    
    var newStructure = oldStructure
    newStructure.usernameLength = 0
    let needsEncoding = PercentEncoding.encode(bytes: newValue, using: URLEncodeSet.UserInfo.self) {
      newStructure.usernameLength += $0.count
    }
    let insertSeparator = (oldStructure.hasCredentialSeparator == false)
    let bytesToWrite = newStructure.usernameLength + (insertSeparator ? 1 : 0)
    let subrangeToReplace = oldStructure.usernameStart..<oldStructure.passwordStart
    let newMetrics = URLMetrics(requiredCapacity: header.count + (bytesToWrite - subrangeToReplace.count))
    let result = replaceSubrange(
      subrangeToReplace, newElementCount: bytesToWrite,
      newStructure: newStructure, newMetrics: newMetrics,
      initializingSubrangeWith: { dest in
        guard var ptr = dest.baseAddress else { return 0 }
        // Contents.
        if needsEncoding {
          PercentEncoding.encode(bytes: newValue, using: URLEncodeSet.UserInfo.self) { piece in
            ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
            ptr += piece.count
          }
        } else {
          let n = UnsafeMutableBufferPointer(start: ptr, count: newStructure.usernameLength)
            .initialize(from: newValue).1
          ptr += n
        }
        // Trailing "@".
        if insertSeparator {
          ptr.pointee = ASCII.commercialAt.codePoint
          ptr += 1
        }
        precondition(ptr == dest.baseAddress.unsafelyUnwrapped + dest.count)
        return bytesToWrite
      })
      return (true, result)
    }
  
  mutating func setPassword<Input>(
    to newValue: Input
  ) -> (Bool, AnyURLStorage) where Input: Collection, Input.Element == UInt8 {
    
    let oldStructure = header.structure
    guard oldStructure.cannotHaveCredentialsOrPort == false else {
      return (false, AnyURLStorage(self))
    }
    
    // Empty passwords are removed.
    guard newValue.isEmpty == false else {
      guard oldStructure.passwordLength != 0 else {
        return (true, AnyURLStorage(self))
      }
      var newStructure = oldStructure
      newStructure.passwordLength = 0
      let subrangeToRemove = oldStructure.passwordStart..<(oldStructure.hostnameStart - (newStructure.hasCredentialSeparator ? 1 : 0))
      let newMetrics = URLMetrics(requiredCapacity: header.count - subrangeToRemove.count)
      
      return (true, removeSubrange(subrangeToRemove, newStructure: newStructure, newMetrics: newMetrics))
    }
    
    var newStructure = oldStructure
    newStructure.passwordLength = 1 // leading ":"
    let needsEncoding = PercentEncoding.encode(bytes: newValue, using: URLEncodeSet.UserInfo.self) {
      newStructure.passwordLength += $0.count
    }
    let bytesToWrite = newStructure.passwordLength + 1 // We always (over-)write the trailing "@".
    let subrangeToReplace = oldStructure.passwordStart..<oldStructure.hostnameStart
    let newMetrics = URLMetrics(requiredCapacity: header.count + (bytesToWrite - subrangeToReplace.count))
    let result = replaceSubrange(
      subrangeToReplace, newElementCount: bytesToWrite,
      newStructure: newStructure, newMetrics: newMetrics,
      initializingSubrangeWith: { dest in
        guard var ptr = dest.baseAddress else { return 0 }
        // Leading ":"
        ptr.pointee = ASCII.colon.codePoint
        ptr += 1
        // Contents.
        if needsEncoding {
          PercentEncoding.encode(bytes: newValue, using: URLEncodeSet.UserInfo.self) { piece in
            ptr.initialize(from: piece.baseAddress.unsafelyUnwrapped, count: piece.count)
            ptr += piece.count
          }
        } else {
          let n = UnsafeMutableBufferPointer(start: ptr, count: newStructure.passwordLength - 1)
            .initialize(from: newValue).1
          ptr += n
        }
        // Trailing "@".
        ptr.pointee = ASCII.commercialAt.codePoint
        ptr += 1
        precondition(ptr == dest.baseAddress.unsafelyUnwrapped + dest.count)
        return bytesToWrite
      })
      return (true, result)
  }
}


// MARK: - AnyURLStorage


/// This enum serves like an existential for a `URLStorage` whose header is one a few known types.
///
/// It does one very important job, which is to decide the optimal header type for a given `URLStructure` and `URLMetrics`,
/// and the most important thing about that job is that it must not get it wrong! The headers themselves will check compatibility when they are created or modified,
/// but errors lead to a runtime failure.
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
  
  /// Creates new canonical URL storage for a string with the given metrics.
  ///
  /// - important: The header's `count` and `capacity` fields are ignored. The required capacity is given by `metrics`.
  ///              Immediately after allocation, the `capacity` is set to the true allocated capacity, and the `count` is set to 0
  ///              (as there are no initialized elements in the new allocation). The `initializer` closure must write all of the code-units
  ///              and return the new `count`.
  ///
  init(
    creatingOptimalStorageFor structure: URLStructure<Int>,
    metrics: URLMetrics,
    initializingCodeUnitsWith initializer: (inout UnsafeMutableBufferPointer<UInt8>)->Int
  ) {
    
    if metrics.requiredCapacity <= UInt8.max {
      let newStorage = URLStorage<GenericURLHeader<UInt8>>(
        structure: structure, metrics: metrics, initializingCodeUnitsWith: initializer
      )
      guard let _newStorage = newStorage else {
        preconditionFailure("AnyURLStorage created incorrect header")
      }
      self = .small(_newStorage)
      return
    }
    let genericStorage = URLStorage<GenericURLHeader<Int>>(
      structure: structure, metrics: metrics, initializingCodeUnitsWith: initializer
    )
    guard let _genericStorage = genericStorage else {
      preconditionFailure("Failed to create generic URL header")
    }
    self = .generic(_genericStorage)
  }
  
  static func isOptimalStorageType<T>(_ type: URLStorage<T>.Type, for structure: URLStructure<Int>, metrics: URLMetrics) -> Bool {
    if metrics.requiredCapacity <= UInt8.max {
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
  
  var schemeKind: WebURL.Scheme {
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
}

extension GenericURLHeader: ManagedBufferHeader {
  
  var count: Int {
    get { return Int(_count) }
    set { _count = SizeType(newValue) }
  }
  
  mutating func bindToCapacity(minimumCapacity: Int, actualCapacity: Int) {
    if actualCapacity <= Int(SizeType.max) {
      _capacity = SizeType(actualCapacity)
    } else {
      // Even if we have been careful and ensured that minimumCapacity <= SizeType.max,
      // the actual capacity from the operating system might still overflow. In that case,
      // set the capacity to SizeType.max (unfortunately discarding the unaddressable capacity).
      _capacity = .max
    }
  }

  var capacity: Int {
    return Int(_capacity)
  }
}

extension GenericURLHeader: URLHeader where SizeType: AnyURLStorageErasableGenericHeaderSize {
  
  static func eraseToAnyURLStorage(_ storage: URLStorage<Self>) -> AnyURLStorage {
    return SizeType._eraseToAnyURLStorage(storage)
  }
  
  static func supports(structure: URLStructure<Int>, metrics: URLMetrics) -> Bool {
    return metrics.requiredCapacity <= SizeType.max
  }
  
  init?(count: Int, capacity: Int, structure: URLStructure<Int>, metrics: URLMetrics) {
    guard Self.supports(structure: structure, metrics: metrics) else { return nil }
    self = .init(
      _count: SizeType(truncatingIfNeeded: count),
      _capacity: SizeType(truncatingIfNeeded: capacity),
      structure: URLStructure<SizeType>(copying: structure)
    )
  }
  
  mutating func copyStructure(from newStructure: URLStructure<Int>, metrics: URLMetrics) -> Bool {
    guard Self.supports(structure: newStructure, metrics: metrics) else { return false }
    self._structure = .init(copying: newStructure)
    return true
  }
  
  var structure: URLStructure<Int> {
    return URLStructure(copying: _structure)
  }
}
