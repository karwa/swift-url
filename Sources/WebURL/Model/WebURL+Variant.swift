extension WebURL {

  enum Variant {
    case small(ManagedArrayBuffer<GenericURLHeader<UInt8>, UInt8>)
    case generic(ManagedArrayBuffer<GenericURLHeader<Int>, UInt8>)

    var schemeKind: WebURL.Scheme {
      switch self {
      case .small(let storage): return storage.header.schemeKind
      case .generic(let storage): return storage.header.schemeKind
      }
    }

    var cannotBeABaseURL: Bool {
      switch self {
      case .small(let storage): return storage.header.cannotBeABaseURL
      case .generic(let storage): return storage.header.cannotBeABaseURL
      }
    }

    var entireString: String {
      switch self {
      case .small(let storage): return String(decoding: storage, as: UTF8.self)
      case .generic(let storage): return String(decoding: storage, as: UTF8.self)
      }
    }
    
    func withEntireString<T>(_ block: (UnsafeBufferPointer<UInt8>) -> T) -> T {
      switch self {
      case .small(let storage): return storage.withUnsafeBufferPointer(block)
      case .generic(let storage): return storage.withUnsafeBufferPointer(block)
      }
    }

    func withComponentBytes<T>(_ component: Component, _ block: (UnsafeBufferPointer<UInt8>?) -> T) -> T {
      switch self {
      case .small(let storage):
        guard let range = storage.header.rangeOfComponent(component) else { return block(nil) }
        return storage.withElements(range: Range(uncheckedBounds: (Int(range.lowerBound), Int(range.upperBound)))) {
          buffer in block(buffer)
        }
      case .generic(let storage):
        guard let range = storage.header.rangeOfComponent(component) else { return block(nil) }
        return storage.withElements(range: range) { buffer in block(buffer) }
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
      case .small(let storage):
        guard let range = storage.header.rangeOfAuthorityString else { return block(nil, 0, 0, 0, 0) }
        return storage.withElements(range: Range(uncheckedBounds: (Int(range.lowerBound), Int(range.upperBound)))) {
          buffer in
          block(
            buffer,
            Int(storage.header.usernameLength),
            Int(storage.header.passwordLength),
            Int(storage.header.hostnameLength),
            Int(storage.header.portLength)
          )
        }
      case .generic(let storage):
        guard let range = storage.header.rangeOfAuthorityString else { return block(nil, 0, 0, 0, 0) }
        return storage.withElements(range: range) { buffer in
          block(
            buffer,
            storage.header.usernameLength,
            storage.header.passwordLength,
            storage.header.hostnameLength,
            storage.header.portLength
          )
        }
      }
    }
  }
}

// MARK: - GenericURLHeader

/// A header which can support any kind of valid URL string.
///
/// The stored URL must be of the format:
///  [scheme + ":"] + ["//"]? + [username]? + [":" + password] + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
struct GenericURLHeader<SizeType: FixedWidthInteger>: ManagedBufferHeader {
  var _count: SizeType = 0
  var _capacity: SizeType = 0
  
  var schemeLength: SizeType = 0
  var usernameLength: SizeType = 0
  var passwordLength: SizeType = 0
  var hostnameLength: SizeType = 0
  var portLength: SizeType = 0
  // if path, query or fragment are not 0, they must contain their leading separators ('/', '?', '#').
  var pathLength: SizeType = 0
  var queryLength: SizeType = 0
  var fragmentLength: SizeType = 0

  var hasAuthority: Bool = false
  var schemeKind: WebURL.Scheme = .other
  var cannotBeABaseURL: Bool = false

  var count: Int {
    get { return Int(_count) }
    set { _count = SizeType(newValue) }
  }

  var capacity: Int {
    get { return Int(_capacity) }
    set { _capacity = SizeType(newValue) }
  }

  // Scheme is always present and starts at byte 0.

  var schemeStart: SizeType {
    assert(schemeLength != 0, "URLs must always have a scheme")
    return 0
  }

  var schemeEnd: SizeType {
    schemeStart &+ schemeLength
  }

  // Authority may or may not be present.

  // - If present, it starts at schemeEnd + 2 ('//').
  //   - It may be an empty string for non-special URLs ("pop://?hello").
  // - If not present, do not add double solidus ("pop:?hello").
  //
  // The difference is that "pop://?hello" has an empty authority, and "pop:?hello" has a nil authority.
  // The output of the URL parser preserves that, so we need to factor that in to our component offset calculations.

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
    return passwordStart &+ passwordLength
      + (usernameLength == 0 && passwordLength == 0 ? 0 : 1) /* @ */
  }
  var portStart: SizeType {
    return hostnameStart &+ hostnameLength
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

protocol HasGenericURLHeaderVariant: FixedWidthInteger {

  /// Wraps the given `buffer` in the appropriate `WebURL.Variant`.
  ///
  static func makeVariant(wrapping buffer: ManagedArrayBuffer<GenericURLHeader<Self>, UInt8>) -> WebURL.Variant
}

extension Int: HasGenericURLHeaderVariant {
  static func makeVariant(wrapping buffer: ManagedArrayBuffer<GenericURLHeader<Int>, UInt8>) -> WebURL.Variant {
    return .generic(buffer)
  }
}

extension UInt8: HasGenericURLHeaderVariant {
  static func makeVariant(wrapping buffer: ManagedArrayBuffer<GenericURLHeader<UInt8>, UInt8>) -> WebURL.Variant {
    return .small(buffer)
  }
}

extension GenericURLHeader where SizeType: HasGenericURLHeaderVariant {

  static func writeURLToNewStorage(capacity: Int, _ body: (inout Writer) -> Void) -> WebURL {
    let storage = ManagedArrayBuffer<GenericURLHeader, UInt8>(unsafeUninitializedCapacity: capacity) { elements in
      var writer = Writer(header: .init(), buffer: elements)
      writer.header.capacity = elements.count
      body(&writer)
      precondition(writer.header.count == capacity)
      return writer.header
    }
    return WebURL(variant: SizeType.makeVariant(wrapping: storage))
  }

  // Note: use of wrapping arithmetic is safe here because are writing to a fixed-size buffer,
  //       meaning the count, capacity, and the lengths of all components must fit in `SizeType`.
  //       Additionally, 'writeURLToNewStorage' checks that the final count is equal to the expected length,
  //       so any wrapping will be detected before handing the written storage over.
  struct Writer: URLWriter {
    var header: GenericURLHeader
    var buffer: UnsafeMutableBufferPointer<UInt8>

    init(header: GenericURLHeader, buffer: UnsafeMutableBufferPointer<UInt8>) {
      self.header = header
      self.buffer = buffer
      precondition(buffer.baseAddress != nil, "Invalid buffer")
    }

    private mutating func writeByte(_ byte: UInt8) -> SizeType {
      buffer.baseAddress.unsafelyUnwrapped.pointee = byte
      buffer = UnsafeMutableBufferPointer(rebasing: buffer.dropFirst(1))
      header.count &+= 1
      return 1
    }

    private mutating func writeByte(_ byte: UInt8, count: Int) -> SizeType {
      buffer.baseAddress.unsafelyUnwrapped.initialize(repeating: byte, count: count)
      buffer = UnsafeMutableBufferPointer(rebasing: buffer.dropFirst(count))
      header.count &+= count
      return SizeType(truncatingIfNeeded: count)
    }

    private mutating func writeBytes<T>(_ bytes: T) -> SizeType where T: Collection, T.Element == UInt8 {
      let count = buffer.initialize(from: bytes).1
      buffer = UnsafeMutableBufferPointer(rebasing: buffer.dropFirst(count))
      header.count &+= count
      return SizeType(truncatingIfNeeded: count)
    }

    mutating func writeFlags(schemeKind: WebURL.Scheme, cannotBeABaseURL: Bool) {
      header.schemeKind = schemeKind
      header.cannotBeABaseURL = cannotBeABaseURL
    }

    mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8 {
      header.schemeLength = writeBytes(schemeBytes) + 1
      _ = writeByte(ASCII.colon.codePoint)
    }

    mutating func writeAuthorityHeader() {
      _ = writeByte(ASCII.forwardSlash.codePoint, count: 2)
      header.hasAuthority = true
    }

    mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void)
    where T: Collection, T.Element == UInt8 {
      usernameWriter { piece in
        header.usernameLength &+= writeBytes(piece)
      }
    }

    mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      header.passwordLength = writeByte(ASCII.colon.codePoint)
      passwordWriter { piece in
        header.passwordLength &+= writeBytes(piece)
      }
    }

    mutating func writeCredentialsTerminator() {
      _ = writeByte(ASCII.commercialAt.codePoint)
    }

    mutating func writeHostname<T>(_ hostnameWriter: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
      hostnameWriter { piece in
        header.hostnameLength &+= writeBytes(piece)
      }
    }

    mutating func writePort(_ port: UInt16) {
      header.portLength = writeByte(ASCII.colon.codePoint)
      var portString = String(port)
      portString.withUTF8 {
        header.portLength &+= writeBytes($0)
      }
    }

    mutating func writeKnownAuthorityString(
      _ authority: UnsafeBufferPointer<UInt8>,
      usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
    ) {
      _ = writeBytes(authority)
      header.usernameLength = SizeType(truncatingIfNeeded: usernameLength)
      header.passwordLength = SizeType(truncatingIfNeeded: passwordLength)
      header.hostnameLength = SizeType(truncatingIfNeeded: hostnameLength)
      header.portLength = SizeType(truncatingIfNeeded: portLength)
    }

    mutating func writePathSimple<T>(_ pathWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      pathWriter { piece in
        header.pathLength &+= writeBytes(piece)
      }
    }

    mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int) {
      let bytesWritten = writer(UnsafeMutableBufferPointer(rebasing: buffer.prefix(length)))
      assert(bytesWritten == length)
      buffer = UnsafeMutableBufferPointer(rebasing: buffer.dropFirst(length))
      header.count &+= length

      header.pathLength = SizeType(truncatingIfNeeded: length)
    }

    mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      header.queryLength = writeByte(ASCII.questionMark.codePoint)
      queryWriter {
        header.queryLength &+= writeBytes($0)
      }
    }

    mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      header.fragmentLength = writeByte(ASCII.numberSign.codePoint)
      fragmentWriter {
        header.fragmentLength &+= writeBytes($0)
      }
    }
  }
}
