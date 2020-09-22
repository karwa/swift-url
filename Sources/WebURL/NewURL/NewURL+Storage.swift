/// An interface through which `ScannedURLString` constructs a new URL object.
///
/// Conformers accept UTF8 bytes as given by the construction function, write them to storage, and mark
/// relevant information in a header structure. Finally, they return a URL object wrapping that storage via the `buildURL()` method.
///
/// Conformers may be specialised to only accepting certain kinds of URLs - and they might, for example, omit or replace certain fields
/// in their header structures for their use-case.
///
protocol URLWriter {
  
  init(schemeKind: NewURL.Scheme, cannotBeABaseURL: Bool)
  mutating func buildURL() -> NewURL
  
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
  /// This is always the first call to the writer.
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

// MARK: - GenericURLStorage

/// A header for storing a generic absolute URL.
///
/// The stored URL must be of the format:
///  [scheme + ":"] + ["//"]? + [username]? + [":" + password] + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
struct GenericURLStorage<SizeType: BinaryInteger>: InlineArrayHeader {
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
      
    // FIXME: Move this to its own function instead of making it a fake component.
    // Convenience component for copying a URL's entire authority string.
    case .authority:
      guard components.contains(.authority) else { return nil }
      return authorityStart ..< pathStart
    
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

extension GenericURLStorage {
  struct Writer: URLWriter {
    var storage: ArrayWithInlineHeader<GenericURLStorage, UInt8>
    
    init(schemeKind: NewURL.Scheme, cannotBeABaseURL: Bool) {
      storage = .init(capacity: 10, initialHeader: .init())
      storage.header.schemeKind = schemeKind
      storage.header.cannotBeABaseURL = cannotBeABaseURL
    }
    
    mutating func buildURL() -> NewURL {
      // FIXME
      if let storage = storage as? ArrayWithInlineHeader<GenericURLStorage<Int>, UInt8> {
        return NewURL(storage: storage)
      }
      fatalError()
    }
    
    mutating func writeSchemeContents<T>(_ schemeBytes: T, countIfKnown: Int?) where T : Collection, T.Element == UInt8 {
      storage.append(contentsOf: schemeBytes)
      storage.append(ASCII.colon.codePoint)
      storage.header.schemeLength = SizeType(countIfKnown.map { $0 + 1 } ?? storage.header.count)
      storage.header.components = [.scheme]
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
