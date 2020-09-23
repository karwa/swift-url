/// An interface through which `ScannedURLString` constructs a new URL object.
///
/// Conformers accept UTF8 bytes as given by the construction function, write them to storage, and mark
/// relevant information in a header structure.
///
/// Conformers may be specialised to only accepting certain kinds of URLs - and they might, for example, omit or replace certain fields
/// in their header structures for their use-case.
///
protocol URLWriter {
  
  /// Notes the given information about the URL. This is always the first function to be called.
  mutating func writeFlags(schemeKind: NewURL.Scheme, cannotBeABaseURL: Bool)
  
  /// A function which appends the given bytes to storage.
  ///
  /// Functions using this pattern typically look like the following:
  /// ```swift
  /// func writeUsername<T>(_ usernameWriter: (WriterFunc<T>)->Void)
  /// ```
  ///
  /// Callers typically use this as shown:
  /// ```swift
  /// writeUsername { writePiece in
  ///   PercentEncoding.encodeIteratively(..., handlePiece: { writePiece($0) })
  /// }
  /// ```
  /// in this example, `writePiece` is a `WriterFunc`, and its type is inferred by the call to `PercentEncoding.encodeIteratively(...)`.
  ///
  typealias WriterFunc<T> = (T)->Void
 
  /// Appends the given bytes to storage, followed by the scheme separator character (`:`).
  /// This is always the first call to the writer after `writeFlags`.
  mutating func writeSchemeContents<T>(_ schemeBytes: T, countIfKnown: Int?) where T: Collection, T.Element == UInt8
  
  /// Appends the authority header (`//`) to storage.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  mutating func writeAuthorityHeader()
  
  /// Appends the bytes provided by `usernameWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeAuthorityHeader`.
  mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8
  
  /// Appends the password separator character (`:`), followed by the bytes provided by `passwordWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeUsernameContents`.
  mutating func writePasswordContents<T>(_ passwordWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8
  
  /// Appends the credential terminator byte (`@`).
  /// If called, this must always be the immediate successor to either `writeUsernameContents` or `writePasswordContents`.
  mutating func writeCredentialsTerminator()
  
  /// Appends the given bytes to storage.
  /// The content must already be percent-encoded/IDNA-transformed and not include any separators.
  /// If called, this must always have been preceded by a call to `writeAuthorityHeader`.
  mutating func writeHostname<T>(_ hostname: T) where T: RandomAccessCollection, T.Element == UInt8
  
  /// Appends the port separator character (`:`), followed by the textual representation of the given port number to storage.
  /// If called, this must always be the immediate successor to `writeHostname`.
  mutating func writePort(_ port: UInt16)
  
  /// Appends an entire authority string (username + password + hostname + port) to storage.
  /// The content must already be percent-encoded/IDNA-transformed.
  /// If called, this must always be the immediate successor to `writeAuthorityHeader`.
  /// - important: `passwordLength` and `portLength` include their required leading separators (so a port component of `:8080` has a length of 5).
  mutating func writeKnownAuthorityString(_ authority: UnsafeBufferPointer<UInt8>,
                                           usernameLength: Int, passwordLength: Int,
                                           hostnameLength: Int, portLength: Int)
  
  /// Appends the bytes given by `pathWriter`.
  /// The content must already be percent-encoded. No separators are added before or after the content.
  mutating func writePathSimple<T>(_ pathWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8
  
  /// Appends an uninitialized space of size `length` and calls the given closure to allow for the path content to be written out of order.
  /// The `writer` closure must return the number of bytes written (`bytesWritten`), and all bytes from `0..<bytesWritten` must be initialized.
  /// Content written in to the buffer must already be percent-encoded. No separators are added before or after the content.
  mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int)
  
  /// Appends the query separator character (`?`), followed by the bytes provided by `queryWriter`.
  /// The content must already be percent-encoded.
  mutating func writeQueryContents<T>(_ queryWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8
  
  /// Appends the fragment separator character (`#`), followed by the bytes provided by `fragmentWriter`
  /// The content must already be percent-encoded.
  mutating func writeFragmentContents<T>(_ fragmentWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8
}

// MARK: - GenericURLHeader

/// A header which can support any kind of valid URL string.
///
/// The stored URL must be of the format:
///  [scheme + ":"] + ["//"]? + [username]? + [":" + password] + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
struct GenericURLHeader<SizeType: BinaryInteger>: InlineArrayHeader {
  var _count: SizeType = 0
  
  var components: ComponentsToCopy = [] // TODO: Rename type.
  var schemeKind: NewURL.Scheme = .other
  var schemeLength: SizeType = 0
  var usernameLength: SizeType = 0
  var passwordLength: SizeType = 0
  var hostnameLength: SizeType = 0
  var portLength: SizeType = 0
  // if path, query or fragment are not 0, they must contain their leading separators ('/', '?', '#').
  var pathLength: SizeType = 0
  var queryLength: SizeType = 0
  var fragmentLength: SizeType = 0
  var cannotBeABaseURL: Bool = false
  
  var count: Int {
    get { return Int(_count) }
    set { _count = SizeType(newValue) }
  }
  
  // Scheme is always present and starts at byte 0.
  
  var schemeStart: SizeType {
    assert(components.contains(.scheme), "URLs must always have a scheme")
    return 0
  }
    
  var schemeEnd: SizeType {
    schemeStart + schemeLength
  }
  
  // Authority may or may not be present.
  
  // - If present, it starts at schemeEnd + 2 ('//').
  //   - It may be an empty string for non-special URLs ("pop://?hello").
  // - If not present, do not add double solidus ("pop:?hello").
  //
  // The difference is that "pop://?hello" has an empty authority, and "pop:?hello" has a nil authority.
  // The output of the URL parser preserves that, so we need to factor that in to our component offset calculations.
  
  var authorityStart: SizeType {
    return schemeEnd + (components.contains(.authority) ? 2 : 0 /* // */)
  }
  
  var usernameStart: SizeType {
    return authorityStart
  }
  var passwordStart: SizeType {
    return usernameStart + usernameLength
  }
  var hostnameStart: SizeType {
    return passwordStart + passwordLength
      + (usernameLength == 0 && passwordLength == 0 ? 0 : 1) /* @ */
  }
  var portStart: SizeType {
    return hostnameStart + hostnameLength
  }
  
  // Components with leading separators.
  // The 'start' position is the offset of the separator character ('/','?','#'), and
  // this additional character is included in the component's length.
  // Non-present components have a length of 0.
  
  // For example, "pop://example.com" has a queryLength of 0, but "pop://example.com?" has a queryLength of 1.
  // The former has an empty query component, the latter has a 'nil' query component.
  // The parser has to preserve the separator, even if the component is empty.
  
  /// Returns the end of the authority section, if one is present.
  /// Any trailing components (path, query, fragment) start from here.
  ///
  var pathStart: SizeType {
    return components.contains(.authority) ? (portStart + portLength) : schemeEnd
  }
  
  /// Returns the position of the leading '?' in the query-string, if one is present. Otherwise, returns the position after the path.
  /// All query strings start with a '?'.
  ///
  var queryStart: SizeType {
    return pathStart + pathLength
  }
  
  /// Returns the position of the leading '#' in the fragment, if one is present. Otherwise, returns the position after the query-string.
  /// All fragments start with a '#'.
  ///
  var fragmentStart: SizeType {
    return queryStart + queryLength
  }
  
  /// Returns the range of the entire authority string, if one is present.
  ///
  var rangeOfAuthorityString: Range<SizeType>? {
    guard components.contains(.authority) else { return nil }
    return authorityStart ..< pathStart
  }
  
  func rangeOfComponent(_ component: NewURL.Component) -> Range<SizeType>? {
    let start: SizeType
    let length: SizeType
    switch component {
    case .scheme:
      assert(schemeLength > 1)
      return Range(uncheckedBounds: (schemeStart, schemeEnd))
      
    case .hostname:
      guard components.contains(.authority) else { return nil }
      start = hostnameStart
      length = hostnameLength
      
    // Optional authority details.
    // These have no distinction between empty and nil values, because lone separators are not preserved.
    // e.g. "http://:@test.com" -> "http://test.com".
    case .username:
      guard components.contains(.authority), usernameLength != 0 else { return nil }
      start = usernameStart
      length = usernameLength
    // Password and port have leading separators, but lone separators should never exist.
    case .password:
      assert(passwordLength != 1)
      guard components.contains(.authority), passwordLength > 1 else { return nil }
      start = passwordStart
      length = passwordLength
    case .port:
      assert(portLength != 1)
      guard components.contains(.authority), portLength > 1 else { return nil }
      start = portStart
      length = portLength

    // Components with leading separators.
    // Lone separators are preserved in some cases, which is marked by a length of 1.
    // A length of 0 means a nil value.
    case .path:
      guard components.contains(.path), pathLength != 0 else { return nil }
      start = pathStart
      length = pathLength
    case .query:
      guard components.contains(.query), queryLength != 0 else { return nil }
      start = queryStart
      length = queryLength
    case .fragment:
      guard components.contains(.fragment), fragmentLength != 0 else { return nil }
      start = fragmentStart
      length = fragmentLength
    }
    return start ..< (start + length)
  }
}

protocol HasGenericURLHeaderVariant: BinaryInteger {
  
  /// Wraps the given `buffer` in the appropriate `NewURL.Variant`.
  ///
  static func makeVariant(wrapping buffer: ArrayWithInlineHeader<GenericURLHeader<Self>, UInt8>) -> NewURL.Variant
}

extension Int: HasGenericURLHeaderVariant {
  static func makeVariant(wrapping buffer: ArrayWithInlineHeader<GenericURLHeader<Int>, UInt8>) -> NewURL.Variant {
    return .generic(buffer)
  }
}

extension UInt8: HasGenericURLHeaderVariant {
  static func makeVariant(wrapping buffer: ArrayWithInlineHeader<GenericURLHeader<UInt8>, UInt8>) -> NewURL.Variant {
    return .small(buffer)
  }
}

extension GenericURLHeader where SizeType: HasGenericURLHeaderVariant {
  
  struct Writer: URLWriter {
    var storage: ArrayWithInlineHeader<GenericURLHeader, UInt8>
    
    init(capacity: Int) {
      self.storage = .init(capacity: capacity, initialHeader: .init())
    }
    
    mutating func buildURL() -> NewURL {
      return NewURL(variant: SizeType.makeVariant(wrapping: storage))
    }
    
    mutating func writeFlags(schemeKind: NewURL.Scheme, cannotBeABaseURL: Bool) {
      storage.header.schemeKind = schemeKind
      storage.header.cannotBeABaseURL = cannotBeABaseURL
    }
    
    mutating func writeSchemeContents<T>(_ schemeBytes: T, countIfKnown: Int?) where T : Collection, T.Element == UInt8 {
      storage.append(contentsOf: schemeBytes)
      storage.append(ASCII.colon.codePoint)
      storage.header.schemeLength = SizeType(countIfKnown.map { $0 + 1 } ?? storage.header.count)
      storage.header.components = .scheme
    }
    
    mutating func writeAuthorityHeader() {
      storage.append(repeated: ASCII.forwardSlash.codePoint, count: 2)
      storage.header.components.insert(.authority)
    }
    
    mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
      usernameWriter { piece in
        storage.append(contentsOf: piece)
        storage.header.usernameLength += SizeType(piece.count)
      }
    }
    
    mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
      storage.append(ASCII.colon.codePoint)
      storage.header.passwordLength = 1
      passwordWriter { piece in
        storage.append(contentsOf: piece)
        storage.header.passwordLength += SizeType(piece.count)
      }
    }
    
    mutating func writeCredentialsTerminator() {
      storage.append(ASCII.commercialAt.codePoint)
    }
    
    mutating func writeHostname<T>(_ hostname: T) where T : RandomAccessCollection, T.Element == UInt8 {
      storage.append(contentsOf: hostname)
      storage.header.hostnameLength = SizeType(hostname.count)
    }
    
    mutating func writePort(_ port: UInt16) {
      storage.append(ASCII.colon.codePoint)
      var portString = String(port)
      portString.withUTF8 {
        storage.append(contentsOf: $0)
        storage.header.portLength = SizeType(1 + $0.count)
      }
    }
    
    mutating func writeKnownAuthorityString(_ authority: UnsafeBufferPointer<UInt8>, usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int) {
      storage.append(contentsOf: authority)
      storage.header.usernameLength = SizeType(usernameLength)
      storage.header.passwordLength = SizeType(passwordLength)
      storage.header.hostnameLength = SizeType(hostnameLength)
      storage.header.portLength = SizeType(portLength)
    }
    
    mutating func writePathSimple<T>(_ pathWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
      storage.header.components.insert(.path)
      pathWriter {
        storage.append(contentsOf: $0)
        storage.header.pathLength += SizeType($0.count)
      }
    }
    
    mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int) {
      storage.header.components.insert(.path)
      storage.append(uninitializedCapacity: length) { buffer in
        return writer(buffer)
      }
      storage.header.pathLength = SizeType(length)
    }
    
    mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
      storage.header.components.insert(.query)
      storage.append(ASCII.questionMark.codePoint)
      storage.header.queryLength = 1
      queryWriter {
        storage.append(contentsOf: $0)
        storage.header.queryLength += SizeType($0.count)
      }
    }
    
    mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
      storage.header.components.insert(.fragment)
      storage.append(ASCII.numberSign.codePoint)
      storage.header.fragmentLength = 1
      fragmentWriter {
        storage.append(contentsOf: $0)
        storage.header.fragmentLength += SizeType($0.count)
      }
    }
  }
}

// MARK: - Metrics collector.

/// A `URLWriter` which collects various metrics so that storage can be optimally allocated and written.
///
/// Currently, it collects the total required capacity of the string (post any percent-encoding) and the length of the path component.
/// It may collect other data in the future. In particular, it might be interesting to know if we can skip percent-encoding any components, or how many path
/// components are in the final string (perhaps we'll have a URL storage type with random access to path components).
///
struct URLMetricsCollector: URLWriter {
  var requiredCapacity: Int = 0
  var pathLength: Int = 0
  
  init() {
  }
  
  mutating func writeFlags(schemeKind: NewURL.Scheme, cannotBeABaseURL: Bool) {
    // Nothing to do.
  }

  mutating func writeSchemeContents<T>(_ schemeBytes: T, countIfKnown: Int?) where T : Collection, T.Element == UInt8 {
    requiredCapacity = countIfKnown ?? schemeBytes.count
    requiredCapacity += 1
  }
  
  mutating func writeAuthorityHeader() {
    requiredCapacity += 2
  }
  
  mutating func writeUsernameContents<T>(_ usernameWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    usernameWriter {
      requiredCapacity += $0.count
    }
  }
  
  mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    requiredCapacity += 1
    passwordWriter {
      requiredCapacity += $0.count
    }
  }
  
  mutating func writeCredentialsTerminator() {
    requiredCapacity += 1
  }
  
  mutating func writeHostname<T>(_ hostname: T) where T : RandomAccessCollection, T.Element == UInt8 {
    requiredCapacity += hostname.count
  }
  
  mutating func writePort(_ port: UInt16) {
    requiredCapacity += 1
    requiredCapacity += String(port).utf8.count
  }
  
  mutating func writeKnownAuthorityString(_ authority: UnsafeBufferPointer<UInt8>, usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int) {
    requiredCapacity += authority.count
  }
  
  mutating func writePathSimple<T>(_ pathWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    pathWriter {
      requiredCapacity += $0.count
      pathLength += $0.count
    }
  }
  
  mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int) {
    self.requiredCapacity += length
    pathLength = length
  }
  
  mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    requiredCapacity += 1
    queryWriter {
      requiredCapacity += $0.count
    }
  }
  
  mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    requiredCapacity += 1
    fragmentWriter {
      requiredCapacity += $0.count
    }
  }
}
