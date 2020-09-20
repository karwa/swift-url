
public struct NewURL {
  var storage: Storage = .init(capacity: 0, initialHeader: .init())
  
  init(storage: Storage) {
    self.storage = storage
  }
  
  public init?(_ input: String, base: String?) {
    var baseURL: NewURL?
    var input = input
    if var baseString = base {
      baseURL = baseString.withUTF8 { NewURLParser().constructURL(input: $0, baseURL: nil) }
      guard baseURL != nil else { return nil }
    }
    guard let url = input.withUTF8({ NewURLParser().constructURL(input: $0, baseURL: baseURL) }) else {
      return nil
    }
    self = url
  }
}

extension NewURL {
  
  typealias Storage = ArrayWithInlineHeader<URLHeader<Int>, UInt8>
  
  enum Component {
    case scheme, username, password, hostname, port, path, query, fragment
    case authority
  }
  
  func withComponentBytes<T>(_ component: Component, _ block: (UnsafeBufferPointer<UInt8>?) -> T) -> T {
    guard let range = storage.header.rangeOfComponent(component) else { return block(nil) }
    return storage.withElements(range: range) { buffer in block(buffer) }
  }
  
  func stringForComponent(_ component: Component) -> String? {
    return withComponentBytes(component) { maybeBuffer in
      return maybeBuffer.map { buffer in String(decoding: buffer, as: UTF8.self) }
    }
  }

  var schemeKind: NewURLParser.Scheme {
    return storage.header.schemeKind
  }
  
  public var scheme: String {
    return stringForComponent(.scheme)!
  }
  
  // Note: erasure to empty strings is done to fit the Javascript model for WHATWG tests.
  
  public var username: String {
    return stringForComponent(.username) ?? ""
  }
  
  public var password: String {
    var string = stringForComponent(.password)
    if !(string?.isEmpty ?? true) {
      let separator = string?.removeFirst()
      assert(separator == ":")
    }
    return string ?? ""
  }
  
  public var hostname: String {
    return stringForComponent(.hostname) ?? ""
  }
  
  public var port: String {
    var string = stringForComponent(.port)
    if !(string?.isEmpty ?? true) {
      let separator = string?.removeFirst()
      assert(separator == ":")
    }
    return string ?? ""
  }
  
  public var path: String {
    return stringForComponent(.path) ?? ""
  }
  
  public var query: String {
    let string = stringForComponent(.query)
    guard string != "?" else { return "" }
    return string ?? ""
  }
  
  public var fragment: String {
    let string = stringForComponent(.fragment)
    guard string != "#" else { return "" }
    return string ?? ""
  }
  
  public var cannotBeABaseURL: Bool {
    return storage.header.cannotBeABaseURL
  }
  
  public var href: String {
    return storage.asUTF8String()
  }
}

extension NewURL: CustomStringConvertible {
  
  public var description: String {
    return
      """
      URL Constructor output:
      
      Href: \(href)
      
      Scheme: \(scheme) (\(schemeKind))
      Username: \(username)
      Password: \(password)
      Hostname: \(hostname)
      Port: \(port)
      Path: \(path)
      Query: \(query)
      Fragment: \(fragment)
      CannotBeABaseURL: \(cannotBeABaseURL)
      """
  }
}

/// A header for storing a generic absolute URL.
///
/// The stored URL must be of the format:
///  [scheme + ":"] + ["//"]? + [username]? + [":" + password] + ["@"]? + [hostname]? + [":" + port]? + ["/" + path]? + ["?" + query]? + ["#" + fragment]?
///
struct URLHeader<SizeType: BinaryInteger>: InlineArrayHeader {
  var _count: SizeType = 0
  
  var components: ComponentsToCopy = [] // TODO: Rename type.
  var schemeKind: NewURLParser.Scheme = .other
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




enum ParsableComponent {
   case scheme
   case authority
   case host
   case port
   case pathStart // better name?
   case path
   case query
   case fragment
}



// --------------------------------
// Compressed optionals
// --------------------------------
// Unused right now, but the idea is that instead of having ScannedURL<Input.Index>, we'd
// have some overridden entrypoints which can, for example, compress an Optional<Int> (9 bytes on x86_64)
// in to something like an Optional<UInt15>, where the high bit is reserved to indicate nil, and we have 5 bits of
// magnitude (allowing indexing up to 32,768 bytes - which ought to be enough for most URLs).
//
// This means significant stack savings, better cache usage, and hopefully faster runtime overall.
//

protocol CompressedOptional {
  associatedtype Wrapped
  
  static var none: Self { get }
  func get() -> Wrapped?
  mutating func set(to newValue: Wrapped?)
}

extension Optional: CompressedOptional {
  #if swift(<5.3)
  static var none: Self {
    return nil
  }
  #endif
  func get() -> Wrapped? {
    return self
  }
  mutating func set(to newValue: Wrapped?) {
    self = newValue
  }
}

struct CompressedOptionalUnsignedInteger<Base: SignedInteger & FixedWidthInteger>: CompressedOptional {
  typealias Wrapped = Base.Magnitude

  private var base: Base
  
  init() {
    self.base = -1
  }
  
  static var none: Self {
    return Self()
  }
  func get() -> Wrapped? {
    return base >= 0 ? base.magnitude : nil
  }
  mutating func set(to newValue: Wrapped?) {
    guard let newValue = newValue else {
      self.base = -1
      return
    }
    precondition(newValue <= Base.Magnitude.max)
    self.base = Base(newValue)
  }
}

/// A set of components to be copied from a URL.
///
/// - seealso: `ScannedURL.componentsToCopyFromBase`
///
struct ComponentsToCopy: OptionSet {
  typealias RawValue = UInt8
  
  var rawValue: RawValue
  init(rawValue: RawValue) {
    self.rawValue = rawValue
  }
  
  static var scheme: Self    { Self(rawValue: 1 << 0) }
  static var authority: Self { Self(rawValue: 1 << 1) }
  static var path: Self      { Self(rawValue: 1 << 2) }
  static var query: Self     { Self(rawValue: 1 << 3) }
  static var fragment: Self  { Self(rawValue: 1 << 4) }
}

/// A summary of information obtained by scanning a string as a URL.
///
/// This summary contains information such as which components are present and where they are located, as well as any components
/// which must be copied from a base URL. Typically, these are mutually-exclusive: a component comes _either_ from the input string _or_ the base URL.
/// However, there is one important exception: constructing a final path can sometimes require _both_ the input string _and_ the base URL.
/// This is the only case when a component is marked as present from both data sources.
///
struct ScannedURL<IndexStorage: CompressedOptional> {
  typealias Index = IndexStorage.Wrapped

  // - Flags and data.
  
  var cannotBeABaseURL = false
  var componentsToCopyFromBase: ComponentsToCopy = []
  var schemeKind: NewURLParser.Scheme? = nil
  
  // - Indexes.
  
  // This is the index of the scheme terminator (":"), if one exists.
  var schemeTerminatorIndex = IndexStorage.none
  
  // This is the index of the first character of the authority segment, if one exists.
  // The scheme and authority may be separated by an arbitrary amount of trivia.
  // The authority ends at the "*EndIndex" of the last of its components.
  var authorityStartIndex = IndexStorage.none
  
    // This is the endIndex of the authority's username component, if one exists.
    // The username starts at the authorityStartIndex.
    var usernameEndIndex = IndexStorage.none
  
    // This is the endIndex of the password, if one exists.
    // If a password exists, a username must also exist, and usernameEndIndex must be the ":" character.
    // The password starts at the index after usernameEndIndex.
    var passwordEndIndex = IndexStorage.none
  
    // This is the endIndex of the hostname, if one exists.
    // The hostname starts at (username/password)EndIndex, or from authorityStartIndex if there are no credentials.
    // If a hostname exists, authorityStartIndex must be set.
    var hostnameEndIndex = IndexStorage.none
  
    // This is the endIndex of the port-string, if one exists. If a port exists, a hostname must also exist.
    // If it exists, the port-string starts at hostnameEndIndex and includes a leading ':' character.
    var portEndIndex = IndexStorage.none
  
  // This is the endIndex of the path, if one exists.
  // If an authority segment exists, the path starts at the end of the authority and includes a leading slash.
  // Otherwise, it starts at the index after 'schemeTerminatorIndex' (if it exists) and may/may not include leading slashes.
  // If there is also no scheme, the path starts at the start of the string and may/may not include leading slashes.
  var pathEndIndex = IndexStorage.none
  
  // This is the endIndex of the query-string, if one exists.
  // If it exists, the query starts at the end of the last component and includes a leading '?' character.
  var queryEndIndex = IndexStorage.none
  
  // This is the endIndex of the fragment-string, if one exists.
  // If it exists, the fragment starts at the end of the last component and includes a leading '#' character.
  var fragmentEndIndex = IndexStorage.none
}

extension ScannedURL {
  
  /// Performs some basic invariant checks on the scanned URL data.
  ///
  func checkStructuralInvariants() -> Bool {
    
    // We must have a scheme from somewhere.
    if schemeTerminatorIndex.get() == nil {
      guard componentsToCopyFromBase.contains(.scheme) else { return false }
    }
    // Authority components imply the presence of an authorityStartIndex and hostname.
    if usernameEndIndex.get() != nil || passwordEndIndex.get() != nil || hostnameEndIndex.get() != nil || portEndIndex.get() != nil {
      guard hostnameEndIndex.get() != nil else { return false }
      guard authorityStartIndex.get() != nil else { return false }
    }
    // A password implies the presence of a username.
    if passwordEndIndex.get() != nil {
      guard usernameEndIndex.get() != nil else { return false }
    }
    
    // Ensure components from input string do not overlap with 'componentsToCopyFromBase' (except path).
    if schemeTerminatorIndex.get() != nil {
      // FIXME: Scheme can overlap in relative URLs, but we already test the string and base schemes for equality.
      // guard componentsToCopyFromBase.contains(.scheme) == false else { return false }
    }
    if authorityStartIndex.get() != nil {
      guard componentsToCopyFromBase.contains(.authority) == false else { return false }
    }
    if queryEndIndex.get() != nil {
      guard componentsToCopyFromBase.contains(.query) == false else { return false }
    }
    if fragmentEndIndex.get() != nil {
      guard componentsToCopyFromBase.contains(.fragment) == false else { return false }
    }
    return true
  }
}

protocol URLWriter {
  
  init(schemeKind: NewURLParser.Scheme, cannotBeABaseURL: Bool)
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

struct GenericURLStorageWriter: URLWriter {
  var storage: NewURL.Storage
  
  init(schemeKind: NewURLParser.Scheme, cannotBeABaseURL: Bool) {
    storage = .init(capacity: 10, initialHeader: .init())
    storage.header.schemeKind = schemeKind
    storage.header.cannotBeABaseURL = cannotBeABaseURL
  }
  
  mutating func buildURL() -> NewURL {
    return NewURL(storage: storage)
  }
  
  mutating func writeSchemeContents<T>(_ schemeBytes: T, countIfKnown: Int?) where T : Collection, T.Element == UInt8 {
    storage.append(contentsOf: schemeBytes)
    storage.append(ASCII.colon.codePoint)
    storage.header.schemeLength = countIfKnown.map { $0 + 1 } ?? storage.header.count
    storage.header.components = [.scheme]
  }
  
  mutating func writeAuthorityHeader() {
    storage.append(repeated: ASCII.forwardSlash.codePoint, count: 2)
    storage.header.components.insert(.authority)
  }
  
  mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    usernameWriter { piece in
      storage.append(contentsOf: piece)
      storage.header.usernameLength += piece.count
    }
  }
  
  mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    storage.append(ASCII.colon.codePoint)
    storage.header.passwordLength = 1
    passwordWriter { piece in
      storage.append(contentsOf: piece)
      storage.header.passwordLength += piece.count
    }
  }
  
  mutating func writeCredentialsTerminator() {
    storage.append(ASCII.commercialAt.codePoint)
  }
  
  mutating func writeHostname<T>(_ hostname: T) where T : RandomAccessCollection, T.Element == UInt8 {
    storage.append(contentsOf: hostname)
    storage.header.hostnameLength = hostname.count
  }
  
  mutating func writePort(_ port: UInt16) {
    storage.append(ASCII.colon.codePoint)
    var portString = String(port)
    portString.withUTF8 {
      storage.append(contentsOf: $0)
      storage.header.portLength = 1 + $0.count
    }
  }
  
  mutating func writeKnownAuthorityString(_ authority: UnsafeBufferPointer<UInt8>, usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int) {
    storage.append(contentsOf: authority)
    storage.header.usernameLength = usernameLength
    storage.header.passwordLength = passwordLength
    storage.header.hostnameLength = hostnameLength
    storage.header.portLength = portLength
  }
  
  mutating func writePathSimple<T>(_ pathWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    storage.header.components.insert(.path)
    pathWriter {
      storage.append(contentsOf: $0)
      storage.header.pathLength += $0.count
    }
  }
  
  mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int) {
    storage.header.components.insert(.path)
    storage.append(uninitializedCapacity: length) { buffer in
      return writer(buffer)
    }
    storage.header.pathLength = length
  }
  
  mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    storage.header.components.insert(.query)
    storage.append(ASCII.questionMark.codePoint)
    storage.header.queryLength = 1
    queryWriter {
      storage.append(contentsOf: $0)
      storage.header.queryLength += $0.count
    }
  }
  
  mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void) where T : RandomAccessCollection, T.Element == UInt8 {
    storage.header.components.insert(.fragment)
    storage.append(ASCII.numberSign.codePoint)
    storage.header.fragmentLength = 1
    fragmentWriter {
      storage.append(contentsOf: $0)
      storage.header.fragmentLength += $0.count
    }
  }
}

struct NewURLParser {
  
  init() {}
  
  /// Constructs a new URL from the given input string, interpreted relative to the given (optional) base URL.
  ///
	func constructURL<Input>(
    input: Input,
    baseURL: NewURL?
  ) -> NewURL? where Input: BidirectionalCollection, Input.Element == UInt8 {
    
    // There are 2 phases to constructing a new URL: scanning and construction.
    //
    // - Scanning:     Determine if the input is at all parseable, and which parts of `input`
    //                 contribute to which components.
    // - Construction: Use the information from the scanning step, together with the base URL,
    //                 to transform and copy the pieces of each component in to a final result.
    
    let filteredInput = FilteredURLInput(input, isSetterMode: false)
    
//    var callback = CollectValidationErrors()
    var callback = IgnoreValidationErrors()
  
    guard let scanResults = scanURL(filteredInput, baseURL: baseURL,
                                    mappingType: ScannedURL<Optional<Input.Index>>.self, stateOverride: nil,
                                    callback: &callback) else {
      return nil
    }
    
    assert(scanResults.checkStructuralInvariants())
    
//    print("")
//    print("Scanning Errors:")
//    print("-----------------------------------------")
//    callback.errors.forEach { print($0.description); print("---") }
//    print("-----------------------------------------")
//    print("")
//    callback.errors.removeAll(keepingCapacity: true)
    let result = construct(url: scanResults, input: filteredInput, baseURL: baseURL, callback: &callback)
    
//    print("")
//    print("Construction Errors:")
//    print("-----------------------------------------")
//    callback.errors.forEach { print($0.description); print("---") }
//    print("-----------------------------------------")
//    print("")
    
    return result
  }
  
  func construct<Input, T, Callback>(
    url: ScannedURL<T>,
    input: FilteredURLInput<Input>,
    baseURL: NewURL?,
    callback: inout Callback
  ) -> NewURL? where ScannedURL<T>.Index == Input.Index, Callback: URLParserCallback {
    
    var url = url

    let schemeKind: NewURLParser.Scheme
    if let scannedSchemeKind = url.schemeKind {
      schemeKind = scannedSchemeKind
    } else if url.componentsToCopyFromBase.contains(.scheme), let baseURL = baseURL {
      schemeKind = baseURL.schemeKind
    } else {
      preconditionFailure("We must have a scheme")
    }

    // The mapping does not contain full ranges. They must be inferred using our knowledge of URL structure.
    // Some components require additional validation (e.g. the port), and others require adjustments based on
    // full knowledge of the URL string (e.g. if a file URL whose path starts with a Windows drive, clear the host).
    
    let schemeRange = url.schemeTerminatorIndex.get().map { input.startIndex..<$0 }
    var usernameRange: Range<Input.Index>?
    var passwordRange: Range<Input.Index>?
    var hostnameRange: Range<Input.Index>?
    var portRange: Range<Input.Index>?
    let pathRange: Range<Input.Index>?
    let queryRange: Range<Input.Index>?
    let fragmentRange: Range<Input.Index>?

    // Step 1: Extract full ranges.
    
    var cursor: Input.Index
    
    if let authorityStart = url.authorityStartIndex.get() {
      cursor = authorityStart
      if let usernameEnd = url.usernameEndIndex.get() {
        usernameRange = cursor..<usernameEnd
        cursor = usernameEnd
        if let passwordEnd = url.passwordEndIndex.get() {
          assert(input[cursor] == ASCII.colon.codePoint)
          cursor = input.index(after: cursor)
          passwordRange = cursor..<passwordEnd
          cursor = passwordEnd
        }
        assert(input[cursor] == ASCII.commercialAt.codePoint)
        cursor = input.index(after: cursor)
      }
      if let hostnameEnd = url.hostnameEndIndex.get() {
        hostnameRange = cursor..<hostnameEnd
        cursor = hostnameEnd
      }
      if let portEndIndex = url.portEndIndex.get() {
        assert(input[cursor] == ASCII.colon.codePoint)
        cursor = input.index(after: cursor)
        portRange = cursor..<portEndIndex
        cursor = portEndIndex
      }
    } else if let schemeRange = schemeRange {
      cursor = input.index(after: schemeRange.upperBound) // ":" scheme separator.
    } else {
      cursor = input.startIndex
    }
    if let pathEnd = url.pathEndIndex.get() {
      pathRange = cursor..<pathEnd
      cursor = pathEnd
    } else {
      pathRange = nil
    }
    if let queryEnd = url.queryEndIndex.get() {
      assert(input[cursor] == ASCII.questionMark.codePoint)
      cursor = input.index(after: cursor) // "?" query separator not included in range.
      queryRange = cursor..<queryEnd
      cursor = queryEnd
    } else {
      queryRange = nil
    }
    if let fragmentEnd = url.fragmentEndIndex.get() {
      assert(input[cursor] == ASCII.numberSign.codePoint)
      cursor = input.index(after: cursor) // "#" fragment separator not included in range.
      fragmentRange = cursor..<fragmentEnd
      cursor = fragmentEnd
    }  else {
      fragmentRange = nil
    }
    
    // Step 2: Process the input string, now that we have full knowledge of its contents.
    
    // 2.1: Parse port string.
    var port: UInt16?
    if let portRange = portRange, portRange.isEmpty == false {
      guard let parsedInteger = UInt16(String(decoding: input[portRange], as: UTF8.self)) else {
        callback.validationError(.portOutOfRange)
        return nil
      }
      port = parsedInteger
    }
    // 2.2 Process hostname.
    // Even though it may be discarded later by certain file URLs, we still need to do this now to reject invalid hostnames.
    // FIXME: Improve this in the following ways:
    // - Remove the copying to Array
    // - For non-special schemes: calculate the final length and lazily percent-encode in to the new storage.
    // - For ascii hostnames: communicate known final length and lazily lowercase characters
    var hostnameString: String?
    if let hostname = hostnameRange.map({ input[$0] }) {
      hostnameString = Array(hostname).withUnsafeBufferPointer { bytes -> String? in
        return WebURLParser.Host.parse(bytes, isNotSpecial: schemeKind.isSpecial == false, callback: &callback)?.serialized
      }
      guard hostnameString != nil else { return nil }
    }
    // 2.3: For file URLs whose paths begin with a Windows drive letter, discard the host.
    if schemeKind == .file, var pathContents = pathRange.map({ input[$0] }) {
      // The path may or may not be prefixed with a leading slash.
      // Strip it so we can detect the Windows drive letter.
      if let firstChar = pathContents.first, (ASCII(firstChar) == .forwardSlash || ASCII(firstChar) == .backslash) {
        pathContents = pathContents.dropFirst()
      }
      if URLStringUtils.hasWindowsDriveLetterPrefix(pathContents) {
        if !(hostnameString == nil || hostnameString?.isEmpty == true) {
          callback.validationError(.unexpectedHostFileScheme)
        }
        hostnameString = nil // file URLs turn 'nil' in to an implicit, empty host.
        url.componentsToCopyFromBase.remove(.authority)
      }
    }
    // 2.4: For file URLs, replace 'localhost' with an empty/nil host.
    if schemeKind == .file && hostnameString == "localhost" {
      hostnameString = nil // file URLs turn 'nil' in to an implicit, empty host.
    }
    
    // Step 3: Construct an absolute URL string from the ranges, as well as the baseURL and components to copy.
    
    func writeURL<WriterType: URLWriter>(using writerType: WriterType.Type) -> NewURL {
    
      var writer = WriterType(schemeKind: schemeKind, cannotBeABaseURL: url.cannotBeABaseURL)
    
      // 3.1: Write scheme
      // We *must* have a scheme.
      if let inputScheme = schemeRange {
        assert(schemeKind == url.schemeKind)
        // Scheme must be lowercased.
        writer.writeSchemeContents(input[inputScheme].lazy.map {
          ASCII($0)?.lowercased.codePoint ?? $0
        }, countIfKnown: nil)
        
      } else {
        guard let baseURL = baseURL, url.componentsToCopyFromBase.contains(.scheme) else {
          preconditionFailure("Cannot construct a URL without a scheme")
        }
        assert(schemeKind == baseURL.schemeKind)
        baseURL.withComponentBytes(.scheme) {
          let bytes = $0!.dropLast() // drop terminator.
          writer.writeSchemeContents(bytes, countIfKnown: bytes.count)
        }
      }
          
      if var hostnameString = hostnameString {
        writer.writeAuthorityHeader()
        
        var hasCredentials = false
        if let username = usernameRange, username.isEmpty == false {
          writer.writeUsernameContents { writePiece in
            PercentEscaping.encodeIterativelyAsBuffer(
              bytes: input[username],
              escapeSet: .url_userInfo,
              processChunk: { piece in writePiece(piece) }
            )
          }
          hasCredentials = true
        }
        if let password = passwordRange, password.isEmpty == false {
          writer.writePasswordContents { writePiece in
            PercentEscaping.encodeIterativelyAsBuffer(
              bytes: input[password],
              escapeSet: .url_userInfo,
              processChunk: { piece in writePiece(piece) }
            )
          }
          hasCredentials = true
        }
        if hasCredentials {
          writer.writeCredentialsTerminator()
        }
        hostnameString.withUTF8 {
          writer.writeHostname($0)
        }
        if let port = port, port != schemeKind.defaultPort {
          writer.writePort(port)
        }

      } else if url.componentsToCopyFromBase.contains(.authority) {
        guard let baseURL = baseURL else {
          preconditionFailure("")
        }
        baseURL.withComponentBytes(.authority) {
          if let baseAuth = $0 {
            writer.writeAuthorityHeader()
            writer.writeKnownAuthorityString(
              baseAuth,
              usernameLength: baseURL.storage.header.usernameLength,
              passwordLength: baseURL.storage.header.passwordLength,
              hostnameLength: baseURL.storage.header.hostnameLength,
              portLength: baseURL.storage.header.portLength
            )
          }
        }
      } else if schemeKind == .file {
        // 'file:' URLs get an implicit authority.
        writer.writeAuthorityHeader()
      }
          
      // Write path.
      if let path = pathRange {
        switch url.cannotBeABaseURL {
        case true:
          writer.writePathSimple { writePiece in
            PercentEscaping.encodeIterativelyAsBuffer(
              bytes: input[path],
              escapeSet: .url_c0,
              processChunk: { piece in writePiece(piece) }
            )
          }
        case false:
          let pathLength = PathBufferLengthCalculator.requiredBufferLength(
            pathString: input[path],
            schemeKind: schemeKind,
            baseURL: url.componentsToCopyFromBase.contains(.path) ? baseURL! : nil
          )
          assert(pathLength > 0)
          
          writer.writeUnsafePathInPreallocatedBuffer(length: pathLength) { mutBuffer in
            PathPreallocatedBufferWriter.writePath(
              to: mutBuffer,
              pathString: input[path],
              schemeKind: schemeKind,
              baseURL: url.componentsToCopyFromBase.contains(.path) ? baseURL! : nil
            )
            return pathLength
          }
        }
      } else if url.componentsToCopyFromBase.contains(.path) {
        guard let baseURL = baseURL else { preconditionFailure("") }
        baseURL.withComponentBytes(.path) {
          if let basePath = $0 {
            writer.writePathSimple { writePiece in
              writePiece(basePath)
            }
          }
        }
      } else if schemeKind.isSpecial {
        // Special URLs always have a '/' following the authority, even if they have no path.
        writer.writePathSimple { writePiece in
          writePiece(CollectionOfOne(ASCII.forwardSlash.codePoint))
        }
      }
          
      // Write query.
      if let query = queryRange {
        let urlIsSpecial = schemeKind.isSpecial
        let escapeSet = PercentEscaping.EscapeSet(shouldEscape: { asciiChar in
          switch asciiChar {
          case .doubleQuotationMark, .numberSign, .lessThanSign, .greaterThanSign,
            _ where asciiChar.codePoint < ASCII.exclamationMark.codePoint,
            _ where asciiChar.codePoint > ASCII.tilde.codePoint, .apostrophe where urlIsSpecial:
            return true
          default: return false
          }
        })
        writer.writeQueryContents { writePiece in
          PercentEscaping.encodeIterativelyAsBuffer(
            bytes: input[query],
            escapeSet: escapeSet,
            processChunk: { piece in writePiece(piece) }
          )
        }
              
      } else if url.componentsToCopyFromBase.contains(.query) {
        guard let baseURL = baseURL else { preconditionFailure("") }
        baseURL.withComponentBytes(.query) {
          if let baseQuery = $0?.dropFirst() { // '?' separator.
            writer.writeQueryContents { writePiece in writePiece(baseQuery) }
          }
        }
      }
      
      // Write fragment.
      if let fragment = fragmentRange {
        writer.writeFragmentContents { writePiece in
          PercentEscaping.encodeIterativelyAsBuffer(
            bytes: input[fragment],
            escapeSet: .url_fragment,
            processChunk: { piece in writePiece(piece) }
          )
        }
      } else if url.componentsToCopyFromBase.contains(.fragment) {
        guard let baseURL = baseURL else { preconditionFailure("") }
        baseURL.withComponentBytes(.fragment) {
          if let baseFragment = $0?.dropFirst() { // '#' separator.
            writer.writeFragmentContents { writePiece in writePiece(baseFragment) }
          }
        }
      }
      
      return writer.buildURL()
    }
    
    return writeURL(using: GenericURLStorageWriter.self)
  }
}

// --------------------------------------
// FilteredURLInput
// --------------------------------------
//
// A byte sequence with leading/trailing spaces trimmed,
// and which lazily skips ASCII newlines and tabs.
//
// We need this hoisted out so that the scanning and construction phases
// both see the same bytes. The mapping produced by the scanning phase is only meaningful
// with respect to this collection.
//
// Some future optimisation ideas:
//
// 1. Scan the byte sequence to check if it even needs to skip characters.
//    Store it as an `Either<LazyFilterSequence<...>, Base>`.
//
// 2. When constructing, look for regions where we can access regions of `Base` contiguously (region-based filtering).
//


struct FilteredURLInput<Base> where Base: BidirectionalCollection, Base.Element == UInt8 {
  let base: Base.SubSequence
  
  init(_ rawInput: Base, isSetterMode: Bool) {
    // Trim leading/trailing C0 control characters and spaces.
    var trimmedSlice = rawInput[...]
    if isSetterMode == false {
      let trimmedInput = trimmedSlice.trim {
        switch ASCII($0) {
        case ASCII.ranges.controlCharacters?, .space?: return true
        default: return false
        }
      }
      if trimmedInput.startIndex != trimmedSlice.startIndex || trimmedInput.endIndex != trimmedSlice.endIndex {
//        callback.validationError(.unexpectedC0ControlOrSpace)
      }
      trimmedSlice = trimmedInput
    }
    // Trim initial filtered bytes so we can provide startIndex in O(1).
    trimmedSlice = trimmedSlice.drop(while: Self.filterShouldDrop)
    
    self.base = trimmedSlice
  }
  
  static func filterShouldDrop(_ byte: UInt8) -> Bool {
    return ASCII(byte) == .horizontalTab
    || ASCII(byte) == .carriageReturn
    || ASCII(byte) == .lineFeed
  }
}

extension FilteredURLInput: BidirectionalCollection {
  typealias Index = Base.Index
  typealias Element = Base.Element
  
  var startIndex: Index {
    return base.startIndex
  }
  var endIndex: Index {
    return base.endIndex
  }
  subscript(position: Base.Index) -> UInt8 {
    return base[position]
  }
  
  private var filtered: LazyFilterSequence<Base.SubSequence> {
    return base.lazy.filter { Self.filterShouldDrop($0) == false }
  }
  var count: Int {
    return filtered.count
  }
  func index(after i: Base.Index) -> Base.Index {
    return filtered.index(after: i)
  }
  func index(before i: Base.Index) -> Base.Index {
    return filtered.index(before: i)
  }
  func distance(from start: Base.Index, to end: Base.Index) -> Int {
    return filtered.distance(from: start, to: end)
  }
}

// --------------------------------------
// URL Scanning
// --------------------------------------
//
// `scanURL` is the entrypoint, and calls in to scanning methods written
// as static functions on the generic `URLScanner` type. This is to avoid constraint duplication,
// as all the scanning methods basically share the same constraints (except the entrypoint itself, which is slightly different).
//

/// The first stage is scanning, where we want to build up a map of the resulting URL's components.
/// This will tell us whether the URL is structurally invalid, although it may still fail to normalize if the domain name is nonsense.
///
func scanURL<Input, T, Callback>(
  _ input: FilteredURLInput<Input>,
  baseURL: NewURL?,
  mappingType: ScannedURL<T>.Type,
  stateOverride: WebURLParser.ParserState? = nil,
  callback: inout Callback
) -> ScannedURL<T>? where ScannedURL<T>.Index == Input.Index, Callback: URLParserCallback {
  
  var scanResults = ScannedURL<T>()
  let success: Bool
  
  if let schemeEndIndex = findScheme(input) {
    
    let schemeNameBytes = input[..<schemeEndIndex].dropLast() // dropLast() to remove the ":" terminator.
    let scheme = NewURLParser.Scheme.parse(asciiBytes: schemeNameBytes)
    
    scanResults.schemeKind = scheme
    scanResults.schemeTerminatorIndex.set(to: input.index(before: schemeEndIndex))
    success = URLScanner.scanURLWithScheme(input[schemeEndIndex...], scheme: scheme, baseURL: baseURL, &scanResults, callback: &callback)
    
  } else {
		// If we don't have a scheme, we'll need to copy from the baseURL.
    guard let base = baseURL else {
      callback.validationError(.missingSchemeNonRelativeURL)
      return nil
    }
    // If base `cannotBeABaseURL`, the only thing we can do is set the fragment.
    guard base.cannotBeABaseURL == false else {
      guard ASCII(flatMap: input.first) == .numberSign else {
        callback.validationError(.missingSchemeNonRelativeURL)
        return nil
      }
      scanResults.componentsToCopyFromBase = [.scheme, .path, .query]
      scanResults.cannotBeABaseURL = true
      if case .failed = URLScanner.scanFragment(input.dropFirst(), &scanResults, callback: &callback) {
        success = false
      } else {
        success = true
      }
      return success ? scanResults : nil
    }
    // (No scheme + valid base URL) = some kind of relative-ish URL.
    if base.schemeKind == .file {
      scanResults.componentsToCopyFromBase = [.scheme]
      success = URLScanner.scanAllFileURLComponents(input[...], baseURL: baseURL, &scanResults, callback: &callback)
    } else {
      success = URLScanner.scanAllRelativeURLComponents(input[...], baseScheme: base.schemeKind, &scanResults, callback: &callback)
    }
  }
  
  // End parse function.
  return success ? scanResults : nil
}

/// Returns the endIndex of the scheme (i.e. index of the scheme terminator ":") if one can be parsed from `input`.
/// Otherwise returns `nil`.
///
private func findScheme<Input>(_ input: FilteredURLInput<Input>) -> Input.Index? {
  
  guard input.isEmpty == false else { return nil }
  var cursor = input.startIndex
  
  // schemeStart: must begin with an ASCII alpha.
  guard ASCII(input[cursor])?.isAlpha == true else { return nil }
  
  // scheme: allow all ASCII { alphaNumeric, +, -, . } characters.
  cursor = input.index(after: cursor)
  let _schemeEnd = input[cursor...].firstIndex(where: { byte in
    let c = ASCII(byte)
    switch c {
    case _ where c?.isAlphaNumeric == true, .plus?, .minus?, .period?:
      return false
    default:
      // TODO: assert(c != ASCII.horizontalTab && c != ASCII.lineFeed)
      return true
    }
  })
  // schemes end with an ASCII colon.
  guard let schemeEnd = _schemeEnd, input[schemeEnd] == ASCII.colon.codePoint else {
    return nil
  }
  cursor = input.index(after: schemeEnd)
  return cursor
}

// MARK: - Path Iteration

/// An object which receives iterated path components. The components are visited in reverse order.
///
protocol PathComponentVisitor {
  
  /// Called when the iterator yields a path component that originates from the input string.
  /// These components may not be contiguously stored and require percent-encoding when written.
  ///
  /// - parameters:
  ///   - pathComponent:                The path component yielded by the iterator.
  ///   - isLeadingWindowsDriveLetter:  If `true`, the component is a Windows drive letter in a `file:` URL.
  ///                                   It should be normalized when written (by writing the first byte followed by the ASCII character `:`).
  ///
  mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
    where InputString: BidirectionalCollection, InputString.Element == UInt8
  
  /// Called when the iterator yields an empty path component. Note that this does not imply that other methods are always called with non-empty path components.
  /// This method exists solely as an optimisation, since empty components have no content to percent-encode/transform.
  ///
  mutating func visitEmptyPathComponent()
  
  /// Called when the iterator yields a path component that originates from the base URL's path.
  /// These components are known to be contiguously stored, properly percent-encoded, and any Windows drive letters will already have been normalized.
  /// They need no further processing, and may be written to the result as-is.
  ///
  /// - parameters:
  ///   - pathComponent: The path component yielded by the iterator.
  ///
  mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>)
}

/// A `PathComponentVisitor` which calculates the size of the buffer required to write a path.
///
struct PathBufferLengthCalculator: PathComponentVisitor {
  private var length: Int = 0
  
  static func requiredBufferLength<InputString>(
    pathString input: InputString,
    schemeKind: NewURLParser.Scheme,
    baseURL: NewURL?
  ) -> Int where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    var visitor = PathBufferLengthCalculator()
    visitor.walkPathComponents(
      pathString: input,
      schemeKind: schemeKind,
      baseURL: baseURL
    )
    return visitor.length
  }
  
  mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    length += 1
    PercentEscaping.encodeReverseIterativelyAsBuffer(
      bytes: pathComponent,
      escapeSet: .url_path,
      processChunk: { piece in length += piece.count }
    )
  }
  
  mutating func visitEmptyPathComponent() {
    length += 1
  }
  
  mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    length += 1 + pathComponent.count
  }
}

/// A `PathComponentVisitor` which writes a properly percent-encoded, normalised URL path string
/// in to a preallocated buffer. Use the `PathBufferLengthCalculator` to calculate the buffer's required size.
///
struct PathPreallocatedBufferWriter: PathComponentVisitor {
  private let buffer: UnsafeMutableBufferPointer<UInt8>
  private var front: Int
  
  static func writePath<InputString>(
    to buffer: UnsafeMutableBufferPointer<UInt8>,
    pathString input: InputString,
    schemeKind: NewURLParser.Scheme,
    baseURL: NewURL?
  ) -> Void where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    // Checking this now allows the implementation to use `.baseAddress.unsafelyUnwrapped`.
    precondition(buffer.baseAddress != nil)
    var visitor = PathPreallocatedBufferWriter(buffer: buffer, front: buffer.endIndex)
    visitor.walkPathComponents(
      pathString: input,
      schemeKind: schemeKind,
      baseURL: baseURL
    )
    precondition(visitor.front == buffer.startIndex, "Failed to initialise entire buffer")
  }
  
  private mutating func prependSlash() {
    front = buffer.index(before: front)
    buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
      .initialize(to: ASCII.forwardSlash.codePoint)
  }

  mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    guard pathComponent.isEmpty == false else {
      prependSlash()
      return
    }
    guard isLeadingWindowsDriveLetter == false else {
      assert(pathComponent.count == 2)
      front = buffer.index(front, offsetBy: -2)
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
        .initialize(to: pathComponent[pathComponent.startIndex])
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front &+ 1)
        .initialize(to: ASCII.colon.codePoint)
      prependSlash()
      return
    }
    PercentEscaping.encodeReverseIterativelyAsBuffer(
      bytes: pathComponent,
      escapeSet: .url_path,
      processChunk: { piece in
        let newFront = buffer.index(front, offsetBy: -1 * piece.count)
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront)
          .initialize(from: piece.baseAddress!, count: piece.count)
        front = newFront
    })
    prependSlash()
  }
  
  mutating func visitEmptyPathComponent() {
    prependSlash()
  }
  
  mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    front = buffer.index(front, offsetBy: -1 * pathComponent.count)
    buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
      .initialize(from: pathComponent.baseAddress!, count: pathComponent.count)
    prependSlash()
  }
}

/// A `PathComponentVisitor` which emits URL validation errors for non-URL code points, invalid percent encoding,
/// and use of backslashes as path separators.
///
struct PathInputStringValidator<Input, Callback>: PathComponentVisitor
where Input: BidirectionalCollection, Input.Element == UInt8, Input == Input.SubSequence, Callback: URLParserCallback {
  private var callback: Callback
  private let path: Input.SubSequence
  
  static func validatePathComponents(
    pathString input: Input,
    schemeKind: NewURLParser.Scheme,
    callback: inout Callback
  ) -> Void {
    var visitor = PathInputStringValidator(callback: callback, path: input)
    visitor.walkPathComponents(
      pathString: input,
      schemeKind: schemeKind,
      baseURL: nil
    )
  }
  
  mutating func visitInputPathComponent<InputString>(_ pathComponent: InputString, isLeadingWindowsDriveLetter: Bool)
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    
    guard let pathComponent = pathComponent as? Input.SubSequence else {
      preconditionFailure("Unexpected slice type")
    }
    if pathComponent.endIndex != path.endIndex, ASCII(path[pathComponent.endIndex]) == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    URLScanner<Input, Input.Index?, Callback>.validateURLCodePointsAndPercentEncoding(pathComponent, callback: &callback)
  }
  mutating func visitEmptyPathComponent() {
    // Nothing to do.
  }
  mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    assertionFailure("Should never be invoked without a base URL")
  }
}

extension PathComponentVisitor {
  
  /// Iterates the simplified components of a given path string, optionally applied relative to a base URL's path.
  /// The components are iterated in reverse order, and yielded via 3 callbacks.
  ///
  /// A path string, such as `"a/b/c/.././d/e/../f/"`, describes a traversal through a tree of nodes.
  /// In order to resolve which nodes are present in the final path without allocating dynamic storage to represent the stack of visited nodes,
  /// the components must be iterated in reverse.
  ///
  /// To construct a simplified path string, repeatedly prepend `"/"` (forward slash) followed by the component, to a resulting string.
  /// For example, the input `"a/b/"` yields the components `["", "b", "a"]`, and the construction proceeds as follows:
  /// `"/" -> "/b/" -> "/a/b/"`. The components are yielded by 3 callbacks, all of which build a single result:
  ///
  ///  - `visitInputPathComponent` yields a component from the input string.
  ///     These components may be expensive to iterate and must be percent-encoded when written.
  ///     In some circumstances, Windows drive letter components require normalisation. If the boolean flag is `true`, handlers should
  ///     check if the component is a Windows drive letter and normalize it if it is.
  ///  - `visitEmptyPathComponent` yields an empty component. Not all empty components are guaranteed to be called via this method,
  ///     but it can be more efficient when we know the component is empty and doesn't need escaping or other checks.
  ///  - `visitBasePathComponent` yields a component from the base URL's path.
  ///     These components are known to be contiguously stored, properly percent-encoded, and any Windows drive letters will already have been normalized.
  ///     They can essentially need no further processing, and may be written to the result as-is.
  ///
  /// If the input string is empty, no callbacks will be called unless the scheme is special, in which case there is always an implicit empty path.
  /// If the input string is not empty, this function will always yield something.
  ///
  mutating func walkPathComponents<InputString>(
    pathString input: InputString,
    schemeKind: NewURLParser.Scheme,
    baseURL: NewURL?
  ) where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    
    let schemeIsSpecial = schemeKind.isSpecial
    let isFileScheme = (schemeKind == .file)
    
    // Special URLs have an implicit, empty path.
    guard input.isEmpty == false else {
      if schemeIsSpecial {
        visitEmptyPathComponent()
      }
      return
    }
    
    let isPathComponentTerminator: (_ byte: UInt8) -> Bool
    if schemeIsSpecial {
      isPathComponentTerminator = { byte in ASCII(byte) == .forwardSlash || ASCII(byte) == .backslash }
    } else {
      isPathComponentTerminator = { byte in ASCII(byte) == .forwardSlash }
    }
    
    var contentStartIdx = input.startIndex
    
    // Trim leading slash if present.
    if isPathComponentTerminator(input[contentStartIdx]) {
      contentStartIdx = input.index(after: contentStartIdx)
    }
    // File paths trim _all_ leading slashes, single- and double-dot path components.
    if isFileScheme {
      while contentStartIdx != input.endIndex, isPathComponentTerminator(input[contentStartIdx]) {
        // callback.validationError(.unexpectedEmptyPath)
        contentStartIdx = input.index(after: contentStartIdx)
      }
      while let terminator = input[contentStartIdx...].firstIndex(where: isPathComponentTerminator) {
        let component = input[contentStartIdx..<terminator]
        guard URLStringUtils.isSingleDotPathSegment(component) || URLStringUtils.isDoubleDotPathSegment(component) || component.isEmpty else {
          break
        }
        contentStartIdx = input.index(after: terminator)
      }
    }
    
    // If the input is now empty after trimming, it is either a lone slash (non-file) or string of slashes and dots (file).
    // All of these possible inputs get shortened down to "/", and are not relative to the base path.
    // With one exception: if this is a file URL and the base path starts with a Windows drive letter (X), the result is just "X:/"
    guard contentStartIdx != input.endIndex else {
      var didYield = false
      if isFileScheme {
        baseURL?.withComponentBytes(.path) {
          guard let basePath = $0?.dropFirst() else { return } // dropFirst() due to the leading slash.
          if URLStringUtils.hasWindowsDriveLetterPrefix(basePath) {
            visitEmptyPathComponent()
            visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath.prefix(2)))
            didYield = true
          }
        }
      }
      if !didYield {
        visitEmptyPathComponent()
      }
      return
    }
    
    // Path component special cases:
    //
    // - Single dot ('.') components get skipped.
    //   - If at the end of the path, they force a trailing slash/empty component.
    // - Double dot ('..') components pop previous components from the path.
    //   - For file URLs, they do not pop the last component if it is a Windows drive letter.
    //   - If at the end of the path, they force a trailing slash/empty component.
    //     (even if they have popped all other components, the result is an empty path, not a nil path)
    // - Consecutive empty components at the start of a file URL get collapsed.
    
    // Iterate the path components in reverse, so we can skip components which later get popped.
    var path = input[contentStartIdx...]
    var popcount = 0
    var trailingEmptyCount = 0
    var didYieldComponent = false
    
    func flushTrailingEmpties() {
      if trailingEmptyCount != 0 {
        for _ in 0 ..< trailingEmptyCount {
          visitEmptyPathComponent()
        }
        didYieldComponent = true
        trailingEmptyCount = 0
      }
    }
    
    // Consume components separated by terminators.
    // Since we stripped the initial slash, this loop never sees the initial path component
    // unless it is empty and the scheme is not file.
    while let componentTerminatorIndex = path.lastIndex(where: isPathComponentTerminator) {
      
      let pathComponent = input[path.index(after: componentTerminatorIndex)..<path.endIndex]
      defer { path = path.prefix(upTo: componentTerminatorIndex) }
      
      if ASCII(input[componentTerminatorIndex]) == .backslash {
        //callback.validationError(.unexpectedReverseSolidus)
      }
      
      // '..' -> skip it and increase the popcount.
      // If at the end of the path, mark it as a trailing empty.
      guard URLStringUtils.isDoubleDotPathSegment(pathComponent) == false else {
        popcount += 1
        if pathComponent.endIndex == input.endIndex {
          trailingEmptyCount += 1
        }
        continue
      }
      // Every other component (incl. '.', empty components) can be popped.
      guard popcount == 0 else {
        popcount -= 1
        continue
      }
      // '.' -> skip it.
      // If at the end of the path, mark it as a trailing empty.
      if URLStringUtils.isSingleDotPathSegment(pathComponent) {
        if pathComponent.endIndex == input.endIndex {
          trailingEmptyCount += 1
        }
        continue
      }
      // '' (empty) -> defer processing.
      if pathComponent.isEmpty {
        trailingEmptyCount += 1
        continue
      }
      flushTrailingEmpties()
      visitInputPathComponent(pathComponent, isLeadingWindowsDriveLetter: false)
      didYieldComponent = true
    }
    
    // If the remainder (first component) is empty, if means the path begins with a '//'.
    // This can't be a file URL, because we would have stripped that.
    assert(path.isEmpty ? isFileScheme == false : true)
    
    switch path {
    case _ where URLStringUtils.isDoubleDotPathSegment(path):
      popcount += 1
      fallthrough
    case _ where URLStringUtils.isSingleDotPathSegment(path):
      // Ensure we have a trailing slash.
      if !didYieldComponent {
        trailingEmptyCount = max(trailingEmptyCount, 1)
      }
      
    case _ where URLStringUtils.isWindowsDriveLetter(path) && isFileScheme:
      flushTrailingEmpties()
      visitInputPathComponent(path, isLeadingWindowsDriveLetter: true)
      return // Never appended to base URL.
    
    case _ where popcount == 0:
      flushTrailingEmpties()
      visitInputPathComponent(path, isLeadingWindowsDriveLetter: false)
      didYieldComponent = true
      
    default:
      popcount -= 1
      break // Popped out.
    }
    
    // The leading component has now been processed.
    // If there is no base URL to carry state forward to, we need to flush anything that was deferred.
    path = path.prefix(0)
    guard let baseURL = baseURL else {
      if didYieldComponent == false {
        // If we haven't yielded anything yet, it's because the leading component was popped-out or skipped.
        // Make sure we have at least (or for files, exactly) 1 trailing empty to yield when we flush.
        trailingEmptyCount = isFileScheme ? 1 : max(trailingEmptyCount, 1)
      }
      flushTrailingEmpties()
      return
    }
    
    baseURL.withComponentBytes(.path) {
      guard var basePath = $0?[...] else {
        // No base path. Flush state from input string, as above.
        assert(baseURL.schemeKind.isSpecial == false, "Special URLs always have a path")
        if didYieldComponent == false {
          trailingEmptyCount = isFileScheme ? 1 : max(trailingEmptyCount, 1)
        }
        flushTrailingEmpties()
        return
      }
      // Trim the leading slash.
      if basePath.first == ASCII.forwardSlash.codePoint {
        basePath = basePath.dropFirst()
      }
      // Drop the last path component.
      if basePath.last == ASCII.forwardSlash.codePoint {
        basePath = basePath.dropLast()
      } else if isFileScheme {
        // file URLs don't drop leading Windows drive letters.
        let lastPathComponent: Slice<UnsafeBufferPointer<UInt8>>
        let trimmedBasePath: Slice<UnsafeBufferPointer<UInt8>>
        if let terminatorBeforeLastPathComponent = basePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
          trimmedBasePath   = basePath[..<terminatorBeforeLastPathComponent]
          lastPathComponent = basePath[terminatorBeforeLastPathComponent...].dropFirst()
        } else {
          trimmedBasePath   = basePath.prefix(0)
          lastPathComponent = basePath
        }
        if !(lastPathComponent.startIndex == basePath.startIndex && URLStringUtils.isWindowsDriveLetter(lastPathComponent)) {
          basePath = trimmedBasePath
        }
      } else {
        basePath = basePath[..<(basePath.lastIndex(of: ASCII.forwardSlash.codePoint) ?? basePath.startIndex)]
      }
      
      // Consume remaining components. Continue to observe popcount and trailing empties.
      while let componentTerminatorIndex = basePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
        let pathComponent = basePath[basePath.index(after: componentTerminatorIndex)..<basePath.endIndex]
        defer { basePath = basePath.prefix(upTo: componentTerminatorIndex) }
        
        assert(URLStringUtils.isDoubleDotPathSegment(pathComponent) == false)
        assert(URLStringUtils.isSingleDotPathSegment(pathComponent) == false)
        guard popcount == 0 else {
          popcount -= 1
          continue
        }
        if pathComponent.isEmpty {
          trailingEmptyCount += 1
          continue
        }
        flushTrailingEmpties()
        visitBasePathComponent(UnsafeBufferPointer(rebasing: pathComponent))
        didYieldComponent = true
      }
      // We're left with the leading path component from the base URL (i.e. the very start of the resulting path).
      
      guard popcount == 0 else {
        // Leading Windows drive letters cannot be popped-out.
        if isFileScheme, URLStringUtils.isWindowsDriveLetter(basePath) {
          trailingEmptyCount = max(1, trailingEmptyCount)
          flushTrailingEmpties()
          visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath))
          return
        }
        if !isFileScheme {
          flushTrailingEmpties()
        }
        if didYieldComponent == false {
          visitEmptyPathComponent()
        }
        return
      }
      
      assert(URLStringUtils.isDoubleDotPathSegment(basePath) == false)
      assert(URLStringUtils.isSingleDotPathSegment(basePath) == false)
      
      if basePath.isEmpty {
        // We are at the very start of the path. File URLs discard empties.
        if !isFileScheme {
          flushTrailingEmpties()
        }
        if didYieldComponent == false {
          // If we still didn't yield anything and basePath is empty, any components have been popped to a net zero result.
          // Yield an empty path.
          visitEmptyPathComponent()
        }
        return
      }
      flushTrailingEmpties()
      visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath))
    }
  }
}

struct URLScanner<Input, T, Callback> where Input: BidirectionalCollection, Input.Element == UInt8, Input.SubSequence == Input,
ScannedURL<T>.Index == Input.Index, Callback: URLParserCallback {
  
  enum ComponentParseResult {
    case failed
    case success(continueFrom: (ParsableComponent, Input.Index)?)
  }
  
  typealias Scheme = NewURLParser.Scheme
}

// URLs with schemes.
// ------------------
// Broadly, the pattern is to look for an authority (host, etc), then path, query and fragment.

extension URLScanner {
  
  /// Scans all components of the input string `input`, and builds up a map based on the URL's `scheme`.
  ///
  static func scanURLWithScheme(_ input: Input, scheme: NewURLParser.Scheme, baseURL: NewURL?, _ mapping: inout ScannedURL<T>,
                                callback: inout Callback) -> Bool {

    switch scheme {
    case .file:
      if !URLStringUtils.hasDoubleSolidusPrefix(input) {
      	callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return scanAllFileURLComponents(input, baseURL: baseURL, &mapping, callback: &callback)
      
    case .other: // non-special.
      let firstIndex = input.startIndex
      guard firstIndex != input.endIndex, ASCII(input[firstIndex]) == .forwardSlash else {
        mapping.cannotBeABaseURL = true
        return scanAllCannotBeABaseURLComponents(input, scheme: scheme, &mapping, callback: &callback)
      }
      // state: "path or authority"
      let secondIndex = input.index(after: firstIndex)
      if secondIndex != input.endIndex, ASCII(input[secondIndex]) == .forwardSlash {
        let authorityStart = input.index(after: secondIndex)
        return scanAllComponents(from: .authority, input[authorityStart...], scheme: scheme, &mapping, callback: &callback)
      } else {
        return scanAllComponents(from: .path, input[firstIndex...], scheme: scheme, &mapping, callback: &callback)
      }
        
    // !!!! FIXME: We actually need to check that the *content* of `scheme` is the same as `baseURLScheme` !!!!
      
    default: // special schemes other than 'file'.
      if scheme == baseURL?.schemeKind, URLStringUtils.hasDoubleSolidusPrefix(input) == false {
        // state: "special relative or authority"
        callback.validationError(.relativeURLMissingBeginningSolidus)
        return scanAllRelativeURLComponents(input, baseScheme: scheme, &mapping, callback: &callback)
      }
      // state: "special authority slashes"
      var authorityStart = input.startIndex
      if URLStringUtils.hasDoubleSolidusPrefix(input) {
        authorityStart = input.index(authorityStart, offsetBy: 2)
      } else {
        callback.validationError(.missingSolidusBeforeAuthority)
      }
      // state: "special authority ignore slashes"
      authorityStart = input[authorityStart...].drop { ASCII($0) == .forwardSlash || ASCII($0) == .backslash }.startIndex
      return scanAllComponents(from: .authority, input[authorityStart...], scheme: scheme, &mapping, callback: &callback)
    }
  }
  
  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllComponents(from: ParsableComponent, _ input: Input, scheme: NewURLParser.Scheme, _ mapping: inout ScannedURL<T>,
                                callback: inout Callback) -> Bool {
    var component = from
    var remaining = input[...]
    while true {
      let componentResult: ComponentParseResult
      switch component {
      case .authority:
        componentResult = scanAuthority(remaining, scheme: scheme, &mapping, callback: &callback)
      case .pathStart:
        componentResult = scanPathStart(remaining, scheme: scheme, &mapping, callback: &callback)
      case .path:
        componentResult = scanPath(remaining, scheme: scheme, &mapping, callback: &callback)
      case .query:
        componentResult = scanQuery(remaining, scheme: scheme, &mapping, callback: &callback)
      case .fragment:
        componentResult = scanFragment(remaining, &mapping, callback: &callback)
      case .scheme:
          fatalError()
      case .host:
        fatalError()
      case .port:
        fatalError()
      }
      guard case .success(let _nextComponent) = componentResult else {
        return false
      }
      guard let nextComponent = _nextComponent else {
        break
      }
      component = nextComponent.0
      remaining = remaining[nextComponent.1...]
    }
    return true
  }
  
  /// Scans the "authority" component of a URL, containing:
  ///  - Username
  ///  - Password
  ///  - Host
  ///  - Port
  ///
  ///  If parsing doesn't fail, the next component is always `pathStart`.
  ///
  static func scanAuthority(_ input: Input, scheme: NewURLParser.Scheme,_ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
     
    // 1. Validate the mapping.
    assert(mapping.usernameEndIndex.get() == nil)
    assert(mapping.passwordEndIndex.get() == nil)
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the authority (i.e. the terminator between host and path/query/fragment).
    let authority = input.prefix {
      switch ASCII($0) {
      case ASCII.forwardSlash?, ASCII.questionMark?, ASCII.numberSign?:
        return false
      case ASCII.backslash? where scheme.isSpecial:
        return false
      default:
        return true
     }
    }
    mapping.authorityStartIndex.set(to: authority.startIndex)

    var hostStartIndex = authority.startIndex
    
    // 3. Find the extent of the credentials, if there are any.
    if let credentialsEndIndex = authority.lastIndex(where: { ASCII($0) == .commercialAt }) {
      hostStartIndex = input.index(after: credentialsEndIndex)
      callback.validationError(.unexpectedCommercialAt)
      guard hostStartIndex != authority.endIndex else {
        callback.validationError(.unexpectedCredentialsWithoutHost)
        return .failed
      }

      let credentials = authority[..<credentialsEndIndex]
      let username = credentials.prefix { ASCII($0) != .colon }
      mapping.usernameEndIndex.set(to: username.endIndex)
      if username.endIndex != credentials.endIndex {
        mapping.passwordEndIndex.set(to: credentials.endIndex)
      }
    }
    
    // 3. Scan the host/port and propagate the continutation advice.
    let hostname = authority[hostStartIndex...]
    guard hostname.isEmpty == false else {
      if scheme.isSpecial {
        callback.validationError(.emptyHostSpecialScheme)
        return .failed
      }
      mapping.hostnameEndIndex.set(to: hostStartIndex)
      return .success(continueFrom: (.pathStart, hostStartIndex))
    }
    
    guard case .success(let postHost) = scanHostname(hostname, scheme: scheme, &mapping, callback: &callback) else {
      return .failed
    }
    // Scan the port, if the host requested it.
    guard let portComponent = postHost, case .port = portComponent.0 else {
      return .success(continueFrom: postHost)
    }
    guard case .success(let postPort) = scanPort(authority[portComponent.1...], scheme: scheme, &mapping, callback: &callback) else {
      return .failed
    }
    return .success(continueFrom: postPort)
  }
  
  static func scanHostname(_ input: Input, scheme: Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the hostname.
    var hostnameEndIndex: Input.Index?
    do {
      // Note: This doesn't use 'input.indices' as that is surprisingly expensive.
      var idx = input.startIndex
      var inBracket = false
      colonSearch: while idx != input.endIndex {
        switch ASCII(input[idx]) {
        case .leftSquareBracket?:
          inBracket = true
        case .rightSquareBracket?:
          inBracket = false
        case .colon? where inBracket == false:
          hostnameEndIndex = idx
          break colonSearch
        default:
          break
        }
        idx = input.index(after: idx)
      }
    }
    let hostname = input[..<(hostnameEndIndex ?? input.endIndex)]
    
    // 3. Validate the structure.
    if let portStartIndex = hostnameEndIndex, portStartIndex == input.startIndex {
      callback.validationError(.unexpectedPortWithoutHost)
      return .failed
    }
    
    // 4. Return the next component.
    mapping.hostnameEndIndex.set(to: hostname.endIndex)
    if let hostnameEnd = hostnameEndIndex {
      return .success(continueFrom: (.port, input.index(after: hostnameEnd)))
    } else {
      return .success(continueFrom: (.pathStart, input.endIndex))
    }
  }
  
  static func scanPort(_ input: Input, scheme: Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the port string.
    let portString = input.prefix { ASCII($0).map { ASCII.ranges.digits.contains($0) } ?? false }
    
    // 3. Validate the port string.
    // The only thing allowed after the numbers is an authority terminator character.
    if portString.endIndex != input.endIndex {
      switch ASCII(input[portString.endIndex]) {
      case .forwardSlash?, .questionMark?, .numberSign?:
        break
      case .backslash? where scheme.isSpecial:
        break
      default:
        callback.validationError(.portInvalid)
        return .failed
      }
    }
 
    // 4. Return the next component.
    mapping.portEndIndex.set(to: portString.endIndex)
    return .success(continueFrom: (.pathStart, portString.endIndex))
  }

  /// Scans the URL string from the character immediately following the authority, and advises
  /// whether the remainder is a path, query or fragment.
  ///
  static func scanPathStart(_ input: Input, scheme: Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
      
    // 1. Validate the mapping.
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Return the component to parse based on input.
    guard input.isEmpty == false else {
      return .success(continueFrom: (.path, input.startIndex))
    }
    
    let c: ASCII? = ASCII(input[input.startIndex])
    switch c {
    case .questionMark?:
      return .success(continueFrom: (.query, input.index(after: input.startIndex)))
      
    case .numberSign?:
      return .success(continueFrom: (.fragment, input.index(after: input.startIndex)))
      
    default:
      return .success(continueFrom: (.path, input.startIndex))
    }
  }
  
  // Note: This considers the percent sign ("%") a valid URL code-point.
  //
  static func validateURLCodePointsAndPercentEncoding(_ input: Input, callback: inout Callback) {
    
    if URLStringUtils.hasNonURLCodePoints(input, allowPercentSign: true) {
      callback.validationError(.invalidURLCodePoint)
    }
    
    var percentSignSearchIdx = input.startIndex
    while let percentSignIdx = input[percentSignSearchIdx...].firstIndex(where: { ASCII($0) == .percentSign }) {
      percentSignSearchIdx = input.index(after: percentSignIdx)
      let nextTwo = input[percentSignIdx...].prefix(2)
      if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
        callback.validationError(.unescapedPercentSign)
      }
    }
  }

  /// Scans a URL path string from the given input, and advises whether there are any components following it.
  ///
  static func scanPath(_ input: Input, scheme: Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the path.
    let nextComponentStartIndex = input.firstIndex { ASCII($0) == .questionMark || ASCII($0) == .numberSign }
    let path = input[..<(nextComponentStartIndex ?? input.endIndex)]

    // 3. Validate the path's contents.
    if Callback.self != IgnoreValidationErrors.self {
      PathInputStringValidator.validatePathComponents(pathString: path, schemeKind: scheme, callback: &callback)
    }
      
    // 4. Return the next component.
    if path.isEmpty && scheme.isSpecial == false {
       mapping.pathEndIndex.set(to: nil)
    } else {
      mapping.pathEndIndex.set(to: path.endIndex)
    }
    if let pathEnd = nextComponentStartIndex {
      return .success(continueFrom: (ASCII(input[pathEnd]) == .questionMark ? .query : .fragment,
                                     input.index(after: pathEnd)))
    } else {
      return .success(continueFrom: nil)
    }
  }
  
  /// Scans a URL query string from the given input, and advises whether there are any components following it.
  ///
  static func scanQuery(_ input: Input, scheme: Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the query
    let queryEndIndex = input.firstIndex { ASCII($0) == .numberSign }
      
    // 3. Validate the query-string.
    validateURLCodePointsAndPercentEncoding(input.prefix(upTo: queryEndIndex ?? input.endIndex), callback: &callback)
      
    // 3. Return the next component.
    mapping.queryEndIndex.set(to: queryEndIndex ?? input.endIndex)
    if let queryEnd = queryEndIndex {
      return .success(continueFrom: ASCII(input[queryEnd]) == .numberSign ? (.fragment, input.index(after: queryEnd)) : nil)
    } else {
      return .success(continueFrom: nil)
    }
  }
  
  /// Scans a URL fragment string from the given input. There are never any components following it.
  ///
  static func scanFragment(_ input: Input, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Validate the fragment string.
    validateURLCodePointsAndPercentEncoding(input, callback: &callback)
    
    mapping.fragmentEndIndex.set(to: input.endIndex)
    return .success(continueFrom: nil)
  }
}

// File URLs.
// ---------

extension URLScanner {
  
  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllFileURLComponents(_ input: Input, baseURL: NewURL?, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> Bool {
    var remaining = input[...]
    
    guard case .success(let _component) = parseFileURLStart(remaining, baseURL: baseURL, &mapping, callback: &callback) else {
      return false
    }
    guard var component = _component else {
      return true
    }
    remaining = input.suffix(from: component.1)
    while true {
      let componentResult: ComponentParseResult
      switch component.0 {
      case .authority:
        componentResult = scanAuthority(remaining, scheme: .file, &mapping, callback: &callback)
      case .pathStart:
        componentResult = scanPathStart(remaining, scheme: .file, &mapping, callback: &callback)
      case .path:
        componentResult = scanPath(remaining, scheme: .file, &mapping, callback: &callback)
      case .query:
        componentResult = scanQuery(remaining, scheme: .file, &mapping, callback: &callback)
      case .fragment:
        componentResult = scanFragment(remaining, &mapping, callback: &callback)
      case .scheme:
          fatalError()
      case .host:
        fatalError()
      case .port:
        fatalError()
      }
      guard case .success(let _nextComponent) = componentResult else {
        return false
      }
      guard let nextComponent = _nextComponent else {
        break
      }
      component = nextComponent
      remaining = remaining.suffix(from: component.1)
    }
    return true
  }
  
  static func parseFileURLStart(_ input: Input, baseURL: NewURL?, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // Note that file URLs may also be relative URLs. It all depends on what comes after "file:".
    // - 0 slashes:  copy base host, parse as path relative to base path.
    // - 1 slash:    copy base host, parse as absolute path.
    // - 2 slashes:  parse own host, parse absolute path.
    // - 3 slahses:  empty host, parse as absolute path.
    // - 4+ slashes: invalid.
    
    let baseScheme = baseURL?.schemeKind
    
    var cursor = input.startIndex
    guard cursor != input.endIndex, let c0 = ASCII(input[cursor]), (c0 == .forwardSlash || c0 == .backslash) else {
      // No slashes. May be a relative path ("file:usr/lib/Swift") or no path ("file:?someQuery").
      guard baseScheme == .file else {
        return .success(continueFrom: (.path, cursor))
      }
      assert(mapping.componentsToCopyFromBase.isEmpty || mapping.componentsToCopyFromBase == [.scheme])
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])

      guard cursor != input.endIndex else {
        mapping.componentsToCopyFromBase.insert(.query)
        return .success(continueFrom: nil)
      }
      switch ASCII(input[cursor]) {
      case .questionMark?:
        return .success(continueFrom: (.query, input.index(after: cursor)))
      case .numberSign?:
        mapping.componentsToCopyFromBase.insert(.query)
        return .success(continueFrom: (.fragment, input.index(after: cursor)))
      default:
        if URLStringUtils.hasWindowsDriveLetterPrefix(input[cursor...]) {
          callback.validationError(.unexpectedWindowsDriveLetter)
        }
        return .success(continueFrom: (.path, cursor))
      }
    }
    cursor = input.index(after: cursor)
    if c0 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    
    guard cursor != input.endIndex, let c1 = ASCII(input[cursor]), (c1 == .forwardSlash || c1 == .backslash) else {
      // 1 slash. e.g. "file:/usr/lib/Swift". Absolute path.
      
      if baseScheme == .file, URLStringUtils.hasWindowsDriveLetterPrefix(input[cursor...]) == false {
        // This string does not begin with a Windows drive letter.
        // If baseURL's path *does*, we are relative to it, rather than being absolute.
        // The appended-path-iteration function handles this case for us, which we opt-in to
        // by having a non-empty path in a special-scheme URL (meaning a guaranteed non-nil path) and
        // including 'path' in 'componentsToCopyFromBase'.
        let basePathStartsWithWindowsDriveLetter: Bool = baseURL.map {
          $0.withComponentBytes(.path) {
            guard let basePath = $0 else { return false }
            return URLStringUtils.hasWindowsDriveLetterPrefix(basePath.dropFirst())
          }
        } ?? false
        if basePathStartsWithWindowsDriveLetter {
          mapping.componentsToCopyFromBase.formUnion([.path])
        } else {
          // No Windows drive letters anywhere. Copy the host and parse our path normally.
          mapping.componentsToCopyFromBase.formUnion([.authority])
        }
      }
      return scanPath(input, scheme: .file, &mapping, callback: &callback)
    }
    
    cursor = input.index(after: cursor)
    if c1 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    
    // 2+ slashes. e.g. "file://localhost/usr/lib/Swift" or "file:///usr/lib/Swift".
    return scanFileHost(input[cursor...], &mapping, callback: &callback)
  }
  
  
  static func scanFileHost(_ input: Input, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
   
    // 1. Validate the mapping.
    assert(mapping.authorityStartIndex.get() == nil)
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the hostname.
    let hostnameEndIndex = input.firstIndex { byte in
      switch ASCII(byte) {
      case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
      default: return false
      }
    } ?? input.endIndex
    
    let hostname = input[..<hostnameEndIndex]
    
    // 3. Brief validation of the hostname. Will be fully validated at construction time.
    if URLStringUtils.isWindowsDriveLetter(hostname) {
      // TODO: Only if not in setter-mode.
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return .success(continueFrom: (.path, input.startIndex))
    }
    if hostname.isEmpty {
      return .success(continueFrom: (.pathStart, input.startIndex))
    }
    
    // 4. Return the next component.
    mapping.authorityStartIndex.set(to: input.startIndex)
    mapping.hostnameEndIndex.set(to: hostnameEndIndex)
    return .success(continueFrom: (.pathStart, hostnameEndIndex))
  }
}

// "cannot-base-a-base" URLs.
// --------------------------

extension URLScanner {
  
  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
    ///
    static func scanAllCannotBeABaseURLComponents(_ input: Input, scheme: NewURLParser.Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> Bool {
      var remaining = input[...]
      
      guard case .success(let _component) = scanCannotBeABaseURLPath(remaining, &mapping, callback: &callback) else {
        return false
      }
      guard var component = _component else {
        return true
      }
      remaining = input.suffix(from: component.1)
      while true {
        let componentResult: ComponentParseResult
        switch component.0 {
        case .query:
          componentResult = scanQuery(remaining, scheme: scheme, &mapping, callback: &callback)
        case .fragment:
          componentResult = scanFragment(remaining, &mapping, callback: &callback)
        case .path:
          fatalError()
        case .pathStart:
          fatalError()
        case .authority:
          fatalError()
        case .scheme:
          fatalError()
        case .host:
          fatalError()
        case .port:
          fatalError()
        }
        guard case .success(let _nextComponent) = componentResult else {
          return false
        }
        guard let nextComponent = _nextComponent else {
          break
        }
        component = nextComponent
        remaining = remaining.suffix(from: component.1)
      }
      return true
    }

  static func scanCannotBeABaseURLPath(_ input: Input, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.authorityStartIndex.get() == nil)
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.pathEndIndex.get() == nil)
    assert(mapping.queryEndIndex.get() == nil)
    assert(mapping.fragmentEndIndex.get() == nil)
    
    // 2. Find the extent of the path.
    let pathEndIndex = input.firstIndex { byte in
      switch ASCII(byte) {
      case .questionMark?, .numberSign?: return true
      default: return false
      }
    }
    let path = input[..<(pathEndIndex ?? input.endIndex)]
    
    // 3. Validate the path.
    validateURLCodePointsAndPercentEncoding(path, callback: &callback)
        
    // 4. Return the next component.
    if let pathEnd = pathEndIndex {
      mapping.pathEndIndex.set(to: pathEnd)
      return .success(continueFrom: (ASCII(input[pathEnd]) == .questionMark ? .query : .fragment,
                                     input.index(after: pathEnd)))
    } else {
      mapping.pathEndIndex.set(to: path.isEmpty ? nil : input.endIndex)
      return .success(continueFrom: nil)
    }
  }
}

// Relative URLs.
// --------------

extension URLScanner {
  
  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllRelativeURLComponents(_ input: Input, baseScheme: NewURLParser.Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> Bool {
    var remaining = input[...]
    
    guard case .success(let _component) = parseRelativeURLStart(remaining, baseScheme: baseScheme, &mapping, callback: &callback) else {
      return false
    }
    guard var component = _component else {
      return true
    }
    remaining = input.suffix(from: component.1)
    while true {
      let componentResult: ComponentParseResult
      switch component.0 {
      case .path:
        componentResult = scanPath(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .query:
        componentResult = scanQuery(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .fragment:
        componentResult = scanFragment(remaining, &mapping, callback: &callback)
      case .pathStart:
        componentResult = scanPathStart(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .authority:
        componentResult = scanAuthority(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .scheme:
        fatalError()
      case .host:
        fatalError()
      case .port:
        fatalError()
      }
      guard case .success(let _nextComponent) = componentResult else {
        return false
      }
      guard let nextComponent = _nextComponent else {
        break
      }
      component = nextComponent
      remaining = remaining.suffix(from: component.1)
    }
    return true
  }
  
  static func parseRelativeURLStart(_ input: Input, baseScheme: NewURLParser.Scheme, _ mapping: inout ScannedURL<T>, callback: inout Callback) -> ComponentParseResult {
    
    mapping.componentsToCopyFromBase = [.scheme]
    
    guard input.isEmpty == false else {
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return .success(continueFrom: nil)
    }
    
    switch ASCII(input[input.startIndex]) {
    // Initial slash. Inspect the rest and parse as either a path or authority.
    case .backslash? where baseScheme.isSpecial:
      callback.validationError(.unexpectedReverseSolidus)
      fallthrough
    case .forwardSlash?:
      var cursor = input.index(after: input.startIndex)
      guard cursor != input.endIndex else {
        mapping.componentsToCopyFromBase.formUnion([.authority])
        return .success(continueFrom: (.path, input.startIndex))
      }
      switch ASCII(input[cursor]) {
      // Second character is also a slash. Parse as an authority.
      case .backslash? where baseScheme.isSpecial:
        callback.validationError(.unexpectedReverseSolidus)
        fallthrough
      case .forwardSlash?:
        if baseScheme.isSpecial {
          cursor = input[cursor...].dropFirst().drop { ASCII($0) == .forwardSlash || ASCII($0) == .backslash }.startIndex
        } else {
          cursor = input.index(after: cursor)
        }
        return .success(continueFrom: (.authority, cursor))
      // Otherwise, copy the base authority. Parse as a (absolute) path.
      default:
        mapping.componentsToCopyFromBase.formUnion([.authority])
        return .success(continueFrom: (.path, input.startIndex))
      }
    
    // Initial query/fragment markers.
    case .questionMark?:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      return .success(continueFrom: (.query, input.index(after: input.startIndex)))
    case .numberSign?:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return .success(continueFrom: (.fragment, input.index(after: input.startIndex)))
      
    // Some other character. Parse as a relative path.
    default:
      // Since we have a non-empty input string with characters before any query/fragment terminators,
      // path-scanning will always produce a mapping with a non-nil pathLength.
      // Construction knows that if a path is found in the input string *and* we ask to copy from the base,
      // that the paths should be combined by stripping the base's last path component.
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      return .success(continueFrom: (.path, input.startIndex))
    }
  }
}














