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
//-------------------------------------------------------------------------
//
// This file contains the URL parser.
//
// Parsing happens in 3 steps, starting at the 'urlFromBytes' function:
//
// - Prep:
//    'urlFromBytes' trims C0 control characters and spaces from the input as the WHATWG parser does.
//    We then need to remove all ASCII tabs and newlines: first, we try to get away with just trimming
//    (keeping the contiguity of the content) but if that isn't possible, we remove the characters lazily
//    using the `NewlineAndTabFiltered` wrapper.
//
// - Parsing:
//    A 'ParsedURLString' is initialized for either the filtered/trimmed input string.
//    This initializer makes use of the `URLScanner' type to interpret the byte string - looking for URL components
//    and marking where they start/end. The scanner performs only minimal content validation necessary to scan later
//    components.
//
//    A 'ParsedURLString.ProcessedMapping' is then constructed using the scanned ranges and flags, which checks
//    the few components that can actually be rejected on content (e.g. hostname must be valid, port must be a number).
//    At this point, we are finished parsing, and the 'ParsedURLString' object is successfully constructed.
//
// - Construction:
//    'urlFromBytes' calls 'constructURLObject' on the 'ParsedURLString', which allocates storage and writes the URL
//    components to it, in a normalized format. Since the input was successfully parsed, this step only fails if the
//    resulting normalized URL string would exceed the maximum capacity of the URLStorage type
//    (see: URLStorage.SizeType).
//
//-------------------------------------------------------------------------

@inlinable @inline(__always)
func urlFromBytes<Bytes>(_ inputString: Bytes, baseURL: WebURL?) -> WebURL?
where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  var callback = IgnoreValidationErrors()
  return inputString.withContiguousStorageIfAvailable {
    _urlFromBytes_impl($0.boundsChecked, baseURL: baseURL, callback: &callback)
  } ?? _urlFromBytes_impl(inputString, baseURL: baseURL, callback: &callback)
}

@inlinable @inline(never)
func _urlFromBytes_impl<Bytes, Callback>(
  _ inputString: Bytes, baseURL: WebURL?, callback: inout Callback
) -> WebURL? where Bytes: BidirectionalCollection, Bytes.Element == UInt8, Callback: URLParserCallback {

  // Trim leading/trailing C0 control characters and spaces.
  let trimmedInput = inputString.trim {
    switch ASCII($0) {
    case ASCII.ranges.c0Control?, .space?: return true
    default: return false
    }
  }
  if trimmedInput.startIndex != inputString.startIndex || trimmedInput.endIndex != inputString.endIndex {
    callback.validationError(.unexpectedC0ControlOrSpace)
  }
  return ASCII.filterNewlinesAndTabs(from: trimmedInput).map(
    left: { filtered in
      ParsedURLString(parsing: filtered, baseURL: baseURL, callback: &callback)?.constructURLObject()
    },
    right: { trimmed in
      ParsedURLString(parsing: trimmed, baseURL: baseURL, callback: &callback)?.constructURLObject()
    }
  ).get()
}


// --------------------------------------------
// MARK: - ParsedURLString
// --------------------------------------------


/// A collection of UTF8 bytes which have been successfully parsed as a URL string.
///
/// A `ParsedURLString` contains both the input string and base URL, together with information about the parsed
/// URL components. Parsed components may be fully-independent values (such as a parsed IP address or port number),
/// but are generally slices of the input string or a marker that the component should be copied from the base URL.
///
/// Parsing a string in to a `ParsedURLString` object does not allocate any dynamic memory (such as Arrays or Strings).
/// Once a string has been parsed, it can be written to any `URLWriter`, which is a visitor that is informed of the
/// normalized URL's structure and contents.
///
/// This design allows the parser to be used for a wide range of applications. For example, it is posible to
/// efficiently determine whether a string is a URL or not without allocating. Since a `URLWriter` visits the
/// normalized URL contents, it can collect metrics about the URL (such as its length, scheme, hostname,
/// or even the simplified list of path components), also without allocating.
/// Alternatively, a `URLWriter` might stream the normalized URL to a file or write it to a pre-allocated buffer.
///
@usableFromInline
internal struct ParsedURLString<InputString> where InputString: BidirectionalCollection, InputString.Element == UInt8 {

  @usableFromInline
  internal let inputString: InputString

  @usableFromInline
  internal let baseURL: Optional<WebURL>

  @usableFromInline
  internal private(set) var mapping: ProcessedMapping

  /// Parses the given collection of UTF8 bytes as a URL string, relative to the given base URL.
  ///
  /// - parameters:
  ///   - inputString:  The input string, as a collection of UTF8 bytes.
  ///   - baseURL:      The base URL against which `inputString` should be interpreted.
  ///   - callback:     A callback to receive validation errors.
  ///                   If these are unimportant, pass an instance of `IngoreValidationErrors`.
  ///
  @inlinable
  internal init?<Callback: URLParserCallback>(
    parsing inputString: InputString, baseURL: WebURL?, callback: inout Callback
  ) {
    self.inputString = inputString
    self.baseURL = baseURL
    self.mapping = ProcessedMapping()
    guard mapping.parse(inputString: inputString, baseURL: baseURL, callback: &callback) else {
      return nil
    }
  }

  /// Writes the URL to the given `URLWriter`.
  ///
  @inlinable
  internal func write<Writer: URLWriter>(to writer: inout Writer) {
    mapping.write(inputString: inputString, baseURL: baseURL, to: &writer)
  }

  /// Writes the URL to new `URLStorage`, and returns it as a `WebURL` object.
  ///
  /// Construction will only fail if the normalized URL string exceeds the maximum capacity supported by `URLStorage`.
  ///
  @inlinable
  internal func constructURLObject() -> WebURL? {
    var info = StructureAndMetricsCollector()
    write(to: &info)
    guard let storageCapacity = URLStorage.SizeType(exactly: info.requiredCapacity) else {
      return nil
    }
    let storage = URLStorage(count: storageCapacity, structure: URLStructure(copying: info.structure)) { buffer in
      var writer = UnsafePresizedBufferWriter(buffer: buffer, hints: info.hints)
      write(to: &writer)
      return writer.bytesWritten
    }
    return WebURL(storage: storage)
  }
}

extension ParsedURLString {

  /// The validated URL information contained within a string.
  ///
  /// A `ProcessedMapping` consists of ranges and flags scanned from the input string, and some parsed components
  /// (such as the host and port number). The ranges indicate that the input was successfully scanned
  /// (and hence has a valid structure), whilst the parsed components indicate that sections with additional meaning
  /// have been successfully interpreted (and hence have valid contents).
  ///
  /// Since this is a large value, the most efficient way to obtain a mapping is to instantiate an empty instance
  /// using `init()` and populate its values in-place by calling `parse(inputString:baseURL:callback:)`.
  ///
  @usableFromInline
  internal struct ProcessedMapping {

    @usableFromInline
    internal fileprivate(set) var info: ScannedRangesAndFlags<InputString>

    @usableFromInline
    internal private(set) var __parsedHost: Optional<ParsedHost>

    @usableFromInline
    internal private(set) var __port: Optional<UInt16>

    // --------------------------------------------
    // Work around to avoid expensive 'outlined init with take' calls
    // https://bugs.swift.org/browse/SR-15215
    // https://forums.swift.org/t/expensive-calls-to-outlined-init-with-take/52187
    // --------------------------------------------

    @inlinable @inline(__always)
    internal var parsedHost: Optional<ParsedHost> {
      get {
        // This field should be loadable from an offset, but perhaps the compiler will decide to pack it
        // and use the spare bits.
        guard let offset = MemoryLayout.offset(of: \Self.__parsedHost) else { return __parsedHost }
        return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<ParsedHost>.self) }
      }
      set {
        // We're not seeing the same expensive runtime calls for the setter, so there's nothing to work around here.
        __parsedHost = newValue
      }
    }

    @inlinable @inline(__always)
    internal var port: Optional<UInt16> {
      get {
        // This field should be loadable from an offset, but perhaps the compiler will decide to pack it
        // and use the spare bits.
        guard let offset = MemoryLayout.offset(of: \Self.__port) else { return __port }
        return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<UInt16>.self) }
      }
      set {
        // We're not seeing the same expensive runtime calls for the setter, so there's nothing to work around here.
        __port = newValue
      }
    }

    // --------------------------------------------
    // End Workaround
    // --------------------------------------------

    /// Constructs an empty ProcessedMapping.
    ///
    /// To populate the mapping, call `parse(inputString:baseURL:callback:)`.
    ///
    @inlinable
    internal init() {
      self.info = ScannedRangesAndFlags()
      self.__parsedHost = nil
      self.__port = nil
    }

    /// Populates a ProcessedMapping in-place. The mapping must be empty.
    ///
    /// This function scans the input string and parses any components which require content validation,
    /// and returns whether or not parsing was succesful.
    ///
    @inlinable
    internal mutating func parse<Callback: URLParserCallback>(
      inputString: InputString,
      baseURL: WebURL?,
      callback: inout Callback
    ) -> Bool {
      info.scanURLString(inputString, baseURL: baseURL, callback: &callback)
        && parseScannedComponents(inputString: inputString, baseURL: baseURL, callback: &callback)
    }
  }
}

extension ParsedURLString.ProcessedMapping {

  /// Parses scanned components and returns whether or not they are valid.
  ///
  @inlinable
  internal mutating func parseScannedComponents<Callback>(
    inputString: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> Bool where Callback: URLParserCallback {

    info.checkInvariants(inputString, baseURL: baseURL)

    // Ensure info.schemeKind is not nil.
    let schemeKind: WebURL.SchemeKind
    if let scannedSchemeKind = info.schemeKind {
      schemeKind = scannedSchemeKind
    } else {
      guard let baseURL = baseURL, info.componentsToCopyFromBase.contains(.scheme) else {
        preconditionFailure("We must have a scheme")
      }
      schemeKind = baseURL.schemeKind
    }

    // Port.
    var port: UInt16?
    if let portRange = info.portRange, portRange.isEmpty == false {
      guard let parsedInteger = ASCII.parseDecimalU16(from: inputString[portRange]) else {
        callback.validationError(.portOutOfRange)  // Or invalid (e.g. contains non-digits).
        return false
      }
      if parsedInteger != schemeKind.defaultPort {
        port = parsedInteger
      }
    }

    // Host.
    var parsedHost: ParsedHost?
    if let hostnameRange = info.hostnameRange {
      parsedHost = ParsedHost(inputString[hostnameRange], schemeKind: schemeKind, callback: &callback)
      guard parsedHost != nil else { return false }
    }

    self.info.schemeKind = schemeKind
    self.parsedHost = parsedHost
    self.port = port
    return true
  }

  @inlinable
  internal func write<WriterType: URLWriter>(
    inputString: InputString,
    baseURL: WebURL?,
    to writer: inout WriterType
  ) {

    let schemeKind = info.schemeKind!

    if info.componentsToCopyFromBase.isEmpty == false {
      precondition(baseURL != nil)  // Important: allows us to use 'unsafelyUnwrapped' when copying from a base URL.
    }

    // 1: Flags
    writer.writeFlags(schemeKind: schemeKind, hasOpaquePath: info.hasOpaquePath)

    // 2: Scheme.
    if let inputScheme = info.schemeRange {
      writer.writeSchemeContents(ASCII.Lowercased(inputString[inputScheme]))
    } else {
      precondition(info.componentsToCopyFromBase.contains(.scheme), "Cannot construct a URL without a scheme")
      assert(schemeKind == baseURL!.schemeKind)
      writer.writeSchemeContents(baseURL.unsafelyUnwrapped.utf8.scheme)
    }

    // 3: Authority.
    var hasAuthority = false
    if let hostname = info.hostnameRange {
      hasAuthority = true
      writer.writeAuthoritySigil()

      var hasCredentials = false
      if let username = info.usernameRange, username.isEmpty == false {
        hasCredentials = true
        if writer.getHint(maySkipPercentEncoding: .username) {
          writer.writeUsernameContents { writer in writer(inputString[username]) }
        } else {
          var wasEncoded = false
          writer.writeUsernameContents { writer in
            wasEncoded = inputString[username].lazy.percentEncoded(using: .userInfoSet).write(to: writer)
          }
          writer.writeHint(.username, maySkipPercentEncoding: !wasEncoded)
        }
      }
      if let password = info.passwordRange, password.isEmpty == false {
        hasCredentials = true
        if writer.getHint(maySkipPercentEncoding: .password) {
          writer.writePasswordContents { writer in writer(inputString[password]) }
        } else {
          var wasEncoded = false
          writer.writePasswordContents { writer in
            wasEncoded = inputString[password].lazy.percentEncoded(using: .userInfoSet).write(to: writer)
          }
          writer.writeHint(.password, maySkipPercentEncoding: !wasEncoded)
        }
      }
      if hasCredentials {
        writer.writeCredentialsTerminator()
      }
      parsedHost!.write(bytes: inputString[hostname], using: &writer)
      if let port = port {
        writer.writePort(port)
      }

    } else if info.componentsToCopyFromBase.contains(.authority) {
      baseURL.unsafelyUnwrapped.storage.withUTF8OfAllAuthorityComponents {
        guard let baseAuthority = $0 else { return }
        hasAuthority = true
        writer.writeAuthoritySigil()
        writer.writeKnownAuthorityString(
          baseAuthority, kind: $1, usernameLength: $2, passwordLength: $3, hostnameLength: $4, portLength: $5
        )
      }

    } else if schemeKind == .file {
      // 'file:' URLs have an implicit authority. [URL Standard: "file host" state]
      writer.writeAuthoritySigil()
      writer.writeHostname(lengthIfKnown: 0, kind: .empty) { $0(EmptyCollection()) }
      hasAuthority = true
    }

    // 4: Path.
    switch info.pathRange {
    case .some(let path) where info.hasOpaquePath:
      if writer.getHint(maySkipPercentEncoding: .path) {
        writer.writePath(firstComponentLength: 0) { writer in writer(inputString[path]) }
      } else {
        var wasEncoded = false
        writer.writePath(firstComponentLength: 0) { writer in
          wasEncoded = inputString[path].lazy.percentEncoded(using: .c0ControlSet).write(to: writer)
        }
        writer.writeHint(.path, maySkipPercentEncoding: !wasEncoded)
      }

    case .some(let path):
      let pathMetrics =
        writer.getPathMetricsHint()
        ?? PathMetrics(
          parsing: inputString[path],
          schemeKind: schemeKind,
          hasAuthority: hasAuthority,
          baseURL: info.componentsToCopyFromBase.contains(.path) ? baseURL : nil,
          absolutePathsCopyWindowsDriveFromBase: info.absolutePathsCopyWindowsDriveFromBase
        )
      assert(pathMetrics.requiredCapacity > 0)
      writer.writePathMetricsHint(pathMetrics)
      writer.writeHint(.path, maySkipPercentEncoding: !pathMetrics.needsPercentEncoding)

      if pathMetrics.requiresPathSigil {
        assert(!hasAuthority, "Must not write path sigil if the URL has an authority sigil already")
        writer.writePathSigil()
      }
      writer.writePresizedPathUnsafely(
        length: Int(bitPattern: pathMetrics.requiredCapacity),
        firstComponentLength: Int(bitPattern: pathMetrics.firstComponentLength)
      ) { buffer in
        return buffer.writeNormalizedPath(
          parsing: inputString[path],
          schemeKind: schemeKind,
          hasAuthority: hasAuthority,
          baseURL: info.componentsToCopyFromBase.contains(.path) ? baseURL : nil,
          absolutePathsCopyWindowsDriveFromBase: info.absolutePathsCopyWindowsDriveFromBase,
          needsPercentEncoding: pathMetrics.needsPercentEncoding
        )
      }

    case .none where info.componentsToCopyFromBase.contains(.path):
      let baseURL = baseURL.unsafelyUnwrapped
      if baseURL.storage.structure.pathRequiresSigil, hasAuthority == false {
        writer.writePathSigil()
      }
      writer.writePath(firstComponentLength: Int(baseURL.storage.structure.firstPathComponentLength)) { writer in
        writer(baseURL.utf8.path)
      }

    case .none where schemeKind.isSpecial:
      // Special URLs always have a path.
      writer.writePath(firstComponentLength: 1) { writer in writer(CollectionOfOne(ASCII.forwardSlash.codePoint)) }

    default:
      assert(info.hasOpaquePath || hasAuthority, "If URL doesn't have a path, it must have an authority or be opaque")
    }

    // 5: Query.
    if let query = info.queryRange {
      if writer.getHint(maySkipPercentEncoding: .query) {
        writer.writeQueryContents { writer in writer(inputString[query]) }
      } else {
        var wasEncoded = false
        writer.writeQueryContents { (writer: (UnsafeBufferPointer<UInt8>) -> Void) in
          if schemeKind.isSpecial {
            wasEncoded = inputString[query].lazy.percentEncoded(using: .specialQuerySet).write(to: writer)
          } else {
            wasEncoded = inputString[query].lazy.percentEncoded(using: .querySet).write(to: writer)
          }
        }
        writer.writeHint(.query, maySkipPercentEncoding: !wasEncoded)
      }

    } else if info.componentsToCopyFromBase.contains(.query) {
      let baseURL = baseURL.unsafelyUnwrapped
      if let baseQuery = baseURL.utf8.query {
        let isFormEncoded = baseURL.storage.structure.queryIsKnownFormEncoded
        writer.writeQueryContents(isKnownFormEncoded: isFormEncoded) { writer in writer(baseQuery) }
      }
    }

    // 6: Fragment.
    if let fragment = info.fragmentRange {
      if writer.getHint(maySkipPercentEncoding: .fragment) {
        writer.writeFragmentContents { writer in writer(inputString[fragment]) }
      } else {
        var wasEncoded = false
        writer.writeFragmentContents { writer in
          wasEncoded = inputString[fragment].lazy.percentEncoded(using: .fragmentSet).write(to: writer)
        }
        writer.writeHint(.fragment, maySkipPercentEncoding: !wasEncoded)
      }
    }  // Fragment is never copied from base URL.


    // 7: Finalize.
    writer.finalize()
    return
  }
}


// --------------------------------------------
// MARK: - URL Scanner
// --------------------------------------------


/// The positions of URL components found within a string, and the flags to interpret them.
///
/// After scanning a URL string, certain components require additional _content validation_
/// which can be performed by `ProcessedMapping.parseScannedComponents`.
///
@usableFromInline
internal struct ScannedRangesAndFlags<InputString>
where InputString: BidirectionalCollection, InputString.Element == UInt8 {

  /// The position of the scheme, if present, without its trailing delimiter.
  @usableFromInline
  internal var schemeRange: Optional<Range<InputString.Index>>

  /// The position of the authority section, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var authorityRange: Optional<Range<InputString.Index>>

  /// The position of the username, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var usernameRange: Optional<Range<InputString.Index>>

  /// The position of the password, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var passwordRange: Optional<Range<InputString.Index>>

  /// The position of the hostname, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var hostnameRange: Optional<Range<InputString.Index>>

  /// The position of the port, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var portRange: Optional<Range<InputString.Index>>

  /// The position of the path, if present, without any leading or trailing delimiters.
  /// Note that the path's initial "/", if present, is considered part of the path and not a delimiter.
  @usableFromInline
  internal var pathRange: Optional<Range<InputString.Index>>

  /// The position of the query, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var queryRange: Optional<Range<InputString.Index>>

  /// The position of the fragment, if present, without any leading or trailing delimiters.
  @usableFromInline
  internal var fragmentRange: Optional<Range<InputString.Index>>

  // Flags.

  /// The kind of scheme contained in `schemeRange`, if it is not `nil`.
  @usableFromInline
  internal var __schemeKind: Optional<WebURL.SchemeKind>

  /// Whether this has an opaque path.
  @usableFromInline
  internal var hasOpaquePath: Bool

  /// A flag which causes absolute paths in file URLs to copy the Windows drive from their base URL.
  @usableFromInline
  internal var absolutePathsCopyWindowsDriveFromBase: Bool

  /// The components to copy from the base URL. If non-empty, there must be a base URL.
  ///
  /// Generally, a particular component is either present in the input string or copied from the base URL, but not both.
  /// There are two exceptions:
  ///
  /// - The scheme
  ///
  ///   This arises from a quirk in the scanner's control-flow which isn't worth adjusting.
  ///   When `schemeRange != nil` and `componentsToCopyFromBase.contains(.scheme)` are both true, the base URL's
  ///   scheme and input string's scheme will already have been checked for equivalence.
  ///
  /// - The path
  ///
  ///   When `pathRange != nil` and `componentsToCopyFromBase.contains(.path)` are both true, it is a signal
  ///   that the path from the input string and path from the base URL should be merged - i.e. that the input string's
  ///   path is relative to the base URL's path.
  ///
  @usableFromInline
  internal var componentsToCopyFromBase: _CopyableURLComponentSet

  // --------------------------------------------
  // Work around to avoid expensive 'outlined init with take' calls.
  // https://bugs.swift.org/browse/SR-15215
  // https://forums.swift.org/t/expensive-calls-to-outlined-init-with-take/52187
  // --------------------------------------------

  /// The kind of scheme contained in `schemeRange`, if it is not `nil`.
  @inlinable @inline(__always)
  internal var schemeKind: Optional<WebURL.SchemeKind> {
    get {
      // This field should be loadable from an offset, but perhaps the compiler will decide to pack it
      // and use the spare bits.
      guard let offset = MemoryLayout.offset(of: \Self.__schemeKind) else { return __schemeKind }
      return withUnsafeBytes(of: self) { $0.load(fromByteOffset: offset, as: Optional<WebURL.SchemeKind>.self) }
    }
    set {
      // We're not seeing the same expensive runtime calls for the setter, so there's nothing to work around here.
      __schemeKind = newValue
    }
  }

  // --------------------------------------------
  // End workaround
  // --------------------------------------------

  /// Constructs an empty mapping.
  ///
  @inlinable
  internal init() {
    self.schemeRange = nil
    self.authorityRange = nil
    self.usernameRange = nil
    self.passwordRange = nil
    self.hostnameRange = nil
    self.portRange = nil
    self.pathRange = nil
    self.queryRange = nil
    self.fragmentRange = nil
    self.__schemeKind = nil
    self.hasOpaquePath = false
    self.absolutePathsCopyWindowsDriveFromBase = false
    self.componentsToCopyFromBase = []
  }
}

//swift-format-ignore
/// A set of components to be copied from a URL.
///
/// - seealso: `ScannedRangesAndFlags.componentsToCopyFromBase`
///
@usableFromInline
internal struct _CopyableURLComponentSet: OptionSet {

  @usableFromInline
  internal var rawValue: UInt8

  @inlinable @inline(__always)
  internal init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  @inlinable @inline(__always) internal static var scheme: Self    { Self(rawValue: 1 << 0) }
  @inlinable @inline(__always) internal static var authority: Self { Self(rawValue: 1 << 1) }
  @inlinable @inline(__always) internal static var path: Self      { Self(rawValue: 1 << 2) }
  @inlinable @inline(__always) internal static var query: Self     { Self(rawValue: 1 << 3) }
}

extension ScannedRangesAndFlags {

  @usableFromInline
  internal typealias InputSlice = InputString.SubSequence

  /// Populates this mapping (which must be empty) by scanning a URL string.
  ///
  /// - parameters:
  ///   - string:   The input string, as a collection of UTF8 bytes.
  ///   - baseURL:  The base URL to interpret `string` against.
  ///   - callback: An object to notify about any validation errors which are encountered.
  ///
  /// - returns: Whether or not scanning was successful.
  ///
  @inlinable
  internal mutating func scanURLString<Callback: URLParserCallback>(
    _ string: InputString, baseURL: WebURL?, callback: inout Callback
  ) -> Bool {

    if let (schemeEndIndex, schemeKind) = parseScheme(string), schemeEndIndex < string.endIndex {
      self.schemeKind = schemeKind
      self.schemeRange = Range(uncheckedBounds: (string.startIndex, schemeEndIndex))
      let remaining = string[Range(uncheckedBounds: (string.index(after: schemeEndIndex), string.endIndex))]
      return scanFromSchemeEnd(remaining, scheme: schemeKind, baseURLScheme: baseURL?.schemeKind, callback: &callback)
    }

    // [URL Standard]: "no scheme" state

    guard let base = baseURL else {
      callback.validationError(.missingSchemeNonRelativeURL)
      return false
    }
    var stringSlice = string[Range(uncheckedBounds: (string.startIndex, string.endIndex))]

    if base.hasOpaquePath {
      guard stringSlice.fastPopFirst() == ASCII.numberSign.codePoint else {
        callback.validationError(.missingSchemeNonRelativeURL)
        return false
      }
      self.componentsToCopyFromBase = [.scheme, .path, .query]
      self.hasOpaquePath = true
      return scanFromFragment(stringSlice)
    }
    if case .file = base.schemeKind {
      self.componentsToCopyFromBase = [.scheme]
      return scanFileURLFromSchemeEnd(stringSlice, baseURLScheme: .file, callback: &callback)
    }
    return scanRelativeURLString(stringSlice, baseScheme: base.schemeKind, callback: &callback)
  }

  /// Scans all components following the URL's scheme.
  ///
  /// `stringSlice` should begin immediately after the scheme delimiter.
  ///
  @inlinable
  internal mutating func scanFromSchemeEnd<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, scheme: WebURL.SchemeKind, baseURLScheme: WebURL.SchemeKind?, callback: inout Callback
  ) -> Bool {

    // [URL Standard]: "scheme" state.
    switch scheme {
    case .http, .https, .ws, .wss, .ftp:
      // [URL Standard]:
      //   - "special relative or authority",
      //   - "special authority slashes",
      //   - "special authority ignore slashes"
      var trimmedStringSlice = stringSlice
      if let afterPrefix = indexAfterDoubleSolidusPrefix(utf8: trimmedStringSlice) {
        trimmedStringSlice = trimmedStringSlice[Range(uncheckedBounds: (afterPrefix, trimmedStringSlice.endIndex))]
      } else if scheme == baseURLScheme {
        callback.validationError(.relativeURLMissingBeginningSolidus)
        return scanRelativeURLString(trimmedStringSlice, baseScheme: scheme, callback: &callback)
      } else {
        callback.validationError(.missingSolidusBeforeAuthority)
      }
      trimmedStringSlice = trimmedStringSlice.fastDrop { isForwardSlashOrBackSlash($0) }
      return scanFromAuthorityStart(trimmedStringSlice, scheme: scheme, callback: &callback)

    case .file:
      if indexAfterDoubleSolidusPrefix(utf8: stringSlice) == nil {
        callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return scanFileURLFromSchemeEnd(stringSlice, baseURLScheme: baseURLScheme, callback: &callback)

    case .other:
      var trimmedStringSlice = stringSlice
      guard trimmedStringSlice.fastPopFirst() == ASCII.forwardSlash.codePoint else {
        return scanFromOpaquePath(stringSlice)
      }
      // [URL Standard]: "path or authority" state.
      guard trimmedStringSlice.fastPopFirst() == ASCII.forwardSlash.codePoint else {
        return scanFromListStylePath(stringSlice)
      }
      return scanFromAuthorityStart(trimmedStringSlice, scheme: scheme, callback: &callback)
    }
  }
}


// --------------------------------------------
// MARK: - Authority components
// --------------------------------------------


extension ScannedRangesAndFlags {

  /// Scans all components from the authority section onwards.
  ///
  /// `stringSlice` should begin at the first character of the authority, without any leading slashes.
  ///
  @inlinable
  internal mutating func scanFromAuthorityStart<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, scheme: WebURL.SchemeKind, callback: inout Callback
  ) -> Bool {

    // 1. Validate the mapping.
    assert(self.usernameRange == nil)
    assert(self.passwordRange == nil)
    assert(self.hostnameRange == nil)
    assert(self.portRange == nil)
    assert(self.authorityRange == nil)
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    // 2. Find the extent of the authority (i.e. the delimiter for the first non-authority component).
    let authority = stringSlice.fastPrefix {
      switch $0 {
      case ASCII.forwardSlash.codePoint, ASCII.questionMark.codePoint, ASCII.numberSign.codePoint:
        return false
      case ASCII.backslash.codePoint where scheme.isSpecial:
        return false
      default:
        return true
      }
    }
    self.authorityRange = Range(uncheckedBounds: (authority.startIndex, authority.endIndex))

    // 3. Split the authority in to [credentials]@[host-and-port]
    var hostnameStart = authority.startIndex
    if let credentialsEndIndex = authority.fastLastIndex(of: ASCII.commercialAt.codePoint) {
      // Scan credentials.
      let credentials = authority[Range(uncheckedBounds: (authority.startIndex, credentialsEndIndex))]
      scanCredentials(credentials, callback: &callback)
      hostnameStart = stringSlice.index(after: credentialsEndIndex)
      guard hostnameStart < authority.endIndex else {
        callback.validationError(.unexpectedCredentialsWithoutHost)
        return false
      }
    }

    // 4. Validate the structure.
    if !(hostnameStart < authority.endIndex), scheme.isSpecial {
      callback.validationError(.emptyHostSpecialScheme)
      return false
    }

    // 5. Scan the host and port from the authority, then continue to other components.
    let remaining = stringSlice[Range(uncheckedBounds: (hostnameStart, stringSlice.endIndex))]
    return scanFromHostname(remaining, authorityEnd: authority.endIndex, callback: &callback)
  }

  /// Splits the given user-info string in to username and password and stores their positions in the mapping.
  ///
  /// `stringSlice` should begin at the first character of the user-info section, and its endIndex
  /// should be the location of the `'@'` sign which delimits the start of the hostname.
  ///
  /// This function does not continue scanning any components after the user-info section.
  ///
  @inlinable @inline(never)
  internal mutating func scanCredentials<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, callback: inout Callback
  ) {

    // 1. Validate the mapping.
    assert(self.usernameRange == nil)
    assert(self.passwordRange == nil)
    assert(self.hostnameRange == nil)
    assert(self.portRange == nil)
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    callback.validationError(.unexpectedCommercialAt)

    // 2. Split the credentials string in to [username]:[password].
    let delimiter = stringSlice.fastFirstIndex(of: ASCII.colon.codePoint)

    // 3. Mark the components.
    if let delimiter = delimiter {
      self.usernameRange = Range(uncheckedBounds: (stringSlice.startIndex, delimiter))
      self.passwordRange = Range(uncheckedBounds: (stringSlice.index(after: delimiter), stringSlice.endIndex))
    } else {
      self.usernameRange = Range(uncheckedBounds: (stringSlice.startIndex, stringSlice.endIndex))
    }
  }

  /// Scans all components from the hostname onwards.
  ///
  /// `stringSlice` should begin at the first character of the hostname, without any leading delimiters.
  /// `authorityEnd` should be the index which marks the end of the authority section.
  ///
  @inlinable
  internal mutating func scanFromHostname<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, authorityEnd: InputString.Index, callback: inout Callback
  ) -> Bool {

    // 1. Validate the mapping.
    assert(self.hostnameRange == nil)
    assert(self.portRange == nil)
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    // 2. Split the remaining authority section in to [hostname]:[port].
    let hostAndPort = stringSlice[Range(uncheckedBounds: (stringSlice.startIndex, authorityEnd))]
    var portDelimiter: InputSlice.Index?
    do {
      // We could just split the hostname at the first colon after a closing bracket,
      // but changes to the standard might prohibit that. For now, split exactly where the standard does.
      // https://github.com/whatwg/url/pull/673
      var cursor = hostAndPort.startIndex
      var inBracket = false
      portSearch: while cursor < hostAndPort.endIndex {
        switch stringSlice[cursor] {
        case ASCII.leftSquareBracket.codePoint:
          inBracket = true
        case ASCII.rightSquareBracket.codePoint:
          inBracket = false
        case ASCII.colon.codePoint where !inBracket:
          portDelimiter = cursor
          break portSearch
        default:
          break
        }
        hostAndPort.formIndex(after: &cursor)
      }
    }
    self.hostnameRange = Range(uncheckedBounds: (hostAndPort.startIndex, portDelimiter ?? hostAndPort.endIndex))

    // 3. Scan the port.
    if var portStart = portDelimiter {
      guard portStart != hostAndPort.startIndex else {
        callback.validationError(.unexpectedPortWithoutHost)
        return false
      }
      hostAndPort.formIndex(after: &portStart)
      let portString = hostAndPort[Range(uncheckedBounds: (portStart, hostAndPort.endIndex))]
      scanPort(portString, callback: &callback)
    }

    // 4. Scan remaining components.
    return scanFromAuthorityEnd(stringSlice[Range(uncheckedBounds: (authorityEnd, stringSlice.endIndex))])
  }

  /// Scans an authority section's port string.
  ///
  /// `stringSlice` should be a slice of the authority section (not the entire string), and should not include
  /// any leading or trailing delimiters.
  ///
  /// This function does not continue scanning any components after the port.
  ///
  @inlinable
  internal mutating func scanPort<Callback: URLParserCallback>(_ stringSlice: InputSlice, callback: inout Callback) {

    // 1. Validate the mapping.
    assert(self.portRange == nil)
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    // The port string is not validated, because ProcessedMapping will parse it later as a 16-bit integer.
    // Invalid ports will fail at that point.

    // 2. Mark the component range.
    self.portRange = Range(uncheckedBounds: (stringSlice.startIndex, stringSlice.endIndex))
  }

  /// Scans all components following the authority section.
  ///
  /// The end of the authority is marked by either the end of the string, or some delimiter -
  /// either a slash, `'?'`, or `'#'`. This delimiter signifies which component comes after the authority.
  ///
  /// `stringSlice` should begin at that delimiter and continue to the end of the string.
  ///
  @inlinable
  internal mutating func scanFromAuthorityEnd(_ stringSlice: InputSlice) -> Bool {

    // 1. Validate the mapping.
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    // 2. Scan remaining components.
    guard stringSlice.startIndex < stringSlice.endIndex else {
      // No components after the authority.
      return true
    }

    // [URL Standard]: "path start" state.
    let delimiter = stringSlice[stringSlice.startIndex]
    let postDelim = stringSlice.index(after: stringSlice.startIndex)
    let remaining = stringSlice[Range(uncheckedBounds: (postDelim, stringSlice.endIndex))]
    switch delimiter {
    case ASCII.questionMark.codePoint:
      return scanFromQuery(remaining)
    case ASCII.numberSign.codePoint:
      return scanFromFragment(remaining)
    default:
      assert(delimiter == ASCII.forwardSlash.codePoint || delimiter == ASCII.backslash.codePoint)
      return scanFromListStylePath(stringSlice)
    }
  }
}


// --------------------------------------------
// MARK: - Non-Authority components
// --------------------------------------------


extension ScannedRangesAndFlags {

  /// Scans all components from the path onwards.
  ///
  /// `stringSlice` should begin at the path's leading slash delimiter, if it has one, or the first character of
  /// the path if it does not. This function is for list-style paths only (not opaque paths).
  ///
  @inlinable
  internal mutating func scanFromListStylePath(_ stringSlice: InputSlice) -> Bool {

    // 1. Validate the mapping.
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    // 2. Find the extent of the path.
    // Note: Marking whether the next component is a query/fragment here helps avoid a bounds-check later,
    //       which prompts the compiler to inline subsequent scanning methods and merge their loops.
    var isQueryDelimiter = false
    let queryOrFragDelimiter = stringSlice.fastFirstIndex {
      if $0 == ASCII.questionMark.codePoint {
        isQueryDelimiter = true
        return true
      } else if $0 == ASCII.numberSign.codePoint {
        return true
      }
      return false
    }
    self.pathRange = Range(uncheckedBounds: (stringSlice.startIndex, queryOrFragDelimiter ?? stringSlice.endIndex))

    // 3. Scan remaining components.
    if var queryOrFragmentStart = queryOrFragDelimiter {
      stringSlice.formIndex(after: &queryOrFragmentStart)
      let remaining = stringSlice[Range(uncheckedBounds: (queryOrFragmentStart, stringSlice.endIndex))]
      return isQueryDelimiter ? scanFromQuery(remaining) : scanFromFragment(remaining)
    }
    return true
  }

  /// Scans all components from the path onwards.
  ///
  /// URLs with opaque paths do not have an authority section, and their paths do not have leading slash delimiters.
  /// Therefore, `stringSlice` should begin immediately after the scheme delimiter.
  ///
  @inlinable
  internal mutating func scanFromOpaquePath(_ stringSlice: InputSlice) -> Bool {

    // Note: This is identical to "scanFromListStylePath", other than setting the "hasOpaquePath" flag.
    //       For now, we're keeping them separate for easier maintenance as the URL Standard evolves.
    //       The compiler seems to recognise that they are identical, so this doesn't cost any code-size.

    // 1. Validate the mapping.
    assert(self.authorityRange == nil)
    assert(self.hostnameRange == nil)
    assert(self.portRange == nil)
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    self.hasOpaquePath = true

    // 2. Find the extent of the path.
    // Note: Marking whether the next component is a query/fragment here helps avoid a bounds-check later,
    //       which prompts the compiler to inline subsequent scanning methods and merge their loops.
    var isQueryDelimiter = false
    let queryOrFragDelimiter = stringSlice.fastFirstIndex {
      if $0 == ASCII.questionMark.codePoint {
        isQueryDelimiter = true
        return true
      } else if $0 == ASCII.numberSign.codePoint {
        return true
      }
      return false
    }
    self.pathRange = Range(uncheckedBounds: (stringSlice.startIndex, queryOrFragDelimiter ?? stringSlice.endIndex))

    // 3. Scan remaining components.
    if var queryOrFragmentStart = queryOrFragDelimiter {
      stringSlice.formIndex(after: &queryOrFragmentStart)
      let remaining = stringSlice[Range(uncheckedBounds: (queryOrFragmentStart, stringSlice.endIndex))]
      return isQueryDelimiter ? scanFromQuery(remaining) : scanFromFragment(remaining)
    }
    return true
  }

  /// Scans all components from the query onwards.
  ///
  /// `stringSlice` should begin at the first character of the query, not including any leading delimiters.
  ///
  @inlinable
  internal mutating func scanFromQuery(_ stringSlice: InputSlice) -> Bool {

    // 1. Validate the mapping.
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)

    // 2. Find the extent of the query
    let fragmentDelimiter = stringSlice.fastFirstIndex(of: ASCII.numberSign.codePoint)
    self.queryRange = Range(uncheckedBounds: (stringSlice.startIndex, fragmentDelimiter ?? stringSlice.endIndex))

    // 3. Scan remaining components.
    if var fragmentStart = fragmentDelimiter {
      stringSlice.formIndex(after: &fragmentStart)
      let remaining = stringSlice[Range(uncheckedBounds: (fragmentStart, stringSlice.endIndex))]
      return scanFromFragment(remaining)
    }
    return true
  }

  /// Scans all components from the fragment onwards.
  ///
  /// `stringSlice` should begin at the first character of the fragment, not including any leading delimiters.
  ///
  @inlinable
  internal mutating func scanFromFragment(_ stringSlice: InputSlice) -> Bool {

    // 1. Validate the mapping.
    assert(self.fragmentRange == nil)

    // 2. Mark the component range.
    self.fragmentRange = Range(uncheckedBounds: (stringSlice.startIndex, stringSlice.endIndex))
    return true
  }
}


// --------------------------------------------
// MARK: - File URLs
// --------------------------------------------


extension ScannedRangesAndFlags {

  /// Scans all components from a file URL string.
  ///
  /// `stringSlice` should start immediately after the scheme delimiter (if present).
  /// This function handles both absolute and relative file URL strings.
  ///
  @inlinable
  internal mutating func scanFileURLFromSchemeEnd<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, baseURLScheme: WebURL.SchemeKind?, callback: inout Callback
  ) -> Bool {

    // file URLs may also be relative. It all depends on what comes after the scheme delimiter:
    //
    // | Slashes | Example               | What it means                                      |
    // | ------- | --------------------- | -------------------------------------------------- |
    // |    0    | file:usr/bin/swift    | copy base authority, parse as relative components. |
    // |    1    | file:/usr/bin/swift   | copy base authority, parse as absolute path.       |
    // |    2+   | file:///usr/bin/swift | parse own authority, parse absolute path.          |
    //
    // Note that for the 0-slash (relative) case, the components may start at the query or fragment rather than path.
    // Example: "file:?someQuery", "file:#someFragment".
    //
    // In this case, we copy the earlier components from the base URL, as is typical for relative URLs.
    // (so "file:#someFragment" copies the base URL's path and query).

    assert(self.componentsToCopyFromBase.isEmpty || self.componentsToCopyFromBase == [.scheme])

    var cursor = stringSlice.startIndex
    guard cursor < stringSlice.endIndex, isForwardSlashOrBackSlash(stringSlice[cursor]) else {
      // [URL Standard]: "file" state.
      // 0 slashes. Some kind of relative string.
      guard case .file = baseURLScheme else {
        return scanFromListStylePath(stringSlice)
      }
      self.componentsToCopyFromBase.formUnion([.authority, .path, .query])

      guard cursor < stringSlice.endIndex else {
        return true
      }
      let delimiter = stringSlice[cursor]
      let remaining = stringSlice[Range(uncheckedBounds: (stringSlice.index(after: cursor), stringSlice.endIndex))]
      switch delimiter {
      case ASCII.numberSign.codePoint:
        return scanFromFragment(remaining)
      case ASCII.questionMark.codePoint:
        self.componentsToCopyFromBase.remove(.query)
        return scanFromQuery(remaining)
      default:
        self.componentsToCopyFromBase.remove(.query)
        // If a relative path starts with a Windows drive letter, it is not resolved like a relative path.
        // `_PathParser` knows how to handle this without any special flags in the mapping.
        if PathComponentParser.hasWindowsDriveLetterPrefix(stringSlice) {
          callback.validationError(.unexpectedWindowsDriveLetter)
        }
        return scanFromListStylePath(stringSlice)
      }
    }
    if stringSlice[cursor] == ASCII.backslash.codePoint {
      callback.validationError(.unexpectedReverseSolidus)
    }
    stringSlice.formIndex(after: &cursor)

    guard cursor < stringSlice.endIndex, isForwardSlashOrBackSlash(stringSlice[cursor]) else {
      // [URL Standard]: "file slash" state.
      // 1 slash. Absolute path in path-only URL.
      guard case .file = baseURLScheme else {
        return scanFromListStylePath(stringSlice)
      }
      self.componentsToCopyFromBase.formUnion([.authority])

      // Absolute paths in path-only URLs are still relative to the base URL's Windows drive letter (if it has one).
      // This only occurs if the string goes through the "file slash" state - not if it contains a hostname
      // and goes through the "file host" state. `_PathParser` requires a flag to opt-in to that behavior.
      self.absolutePathsCopyWindowsDriveFromBase = true
      self.componentsToCopyFromBase.formUnion([.path])
      return scanFromListStylePath(stringSlice)
    }
    if stringSlice[cursor] == ASCII.backslash.codePoint {
      callback.validationError(.unexpectedReverseSolidus)
    }
    let pathStartIfDriveLetter = cursor
    stringSlice.formIndex(after: &cursor)

    // [URL Standard]: "file host" state.
    // 2+ slashes. Absolute URL.
    return scanFromFileHost(stringSlice, startIfHost: cursor, startIfPath: pathStartIfDriveLetter, callback: &callback)
  }

  /// Scans all components from a file URL's hostname onwards.
  ///
  /// This function incorporates a number of quirks for file URLs that do not apply to generic hostnames.
  ///
  /// - It consumes the entire authority, but doesn't parse credentials or port strings.
  ///
  ///   File URLs don't support them, and the "@" and ":" delimiters will be rejected by the host parser anyway.
  ///
  /// - As a consequence of the above, it never fails.
  ///
  ///   Even a structurally-invalid authority section, such as one including credentials or a ports with no hostname,
  ///   will scan successfully. Again, we rely on the host parser to ultimately reject these inputs anyway.
  ///
  /// - It can backtrack.
  ///
  ///   If the hostname is a Windows drive letter, the entire authority section is instead considered
  ///   the start of an absolute path. For example, in the URL `"file://C:/Windows/"`, the entire part `"/C:/Windows/"`
  ///   is interpreted as the path.
  ///
  ///   Since Swift's Collection model does not allow slices to expand their bounds,
  ///   the indexes of both the last authority delimiter and start of the hostname must be provided,
  ///   and `stringSlice` must include both indexes within its bounds.
  ///
  ///   ```
  ///   "file://C:/Windows/"
  ///          ^^
  ///          ||
  ///          |+- startIfHost ("C:/...")
  ///          +- startIfPath  ("/C:/...")
  ///   ```
  ///
  @inlinable
  internal mutating func scanFromFileHost<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, startIfHost: InputString.Index, startIfPath: InputString.Index, callback: inout Callback
  ) -> Bool {

    // 1. Validate the mapping.
    assert(self.authorityRange == nil)
    assert(self.hostnameRange == nil)
    assert(self.portRange == nil)
    assert(self.pathRange == nil)
    assert(self.queryRange == nil)
    assert(self.fragmentRange == nil)
    assert(!self.hasOpaquePath)

    // 2. Find the extent of the hostname.
    var hostname = stringSlice[Range(uncheckedBounds: (startIfHost, stringSlice.endIndex))]
    // swift-format-ignore
    let hostnameEnd = hostname.fastFirstIndex { byte in
      switch byte {
      case ASCII.forwardSlash.codePoint, ASCII.backslash.codePoint,
           ASCII.questionMark.codePoint, ASCII.numberSign.codePoint:
        return true
      default:
        return false
      }
    } ?? stringSlice.endIndex
    hostname = stringSlice[Range(uncheckedBounds: (startIfHost, hostnameEnd))]

    // 3. Scan remaining components.
    if PathComponentParser.isWindowsDriveLetter(hostname) {
      // If the hostname is a Windows drive letter, input looks like: "file://C:/...".
      // Backtrack and parse the "/C:/..." part as an absolute path.
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return scanFromListStylePath(stringSlice[Range(uncheckedBounds: (startIfPath, stringSlice.endIndex))])
    }
    self.authorityRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    self.hostnameRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    let remaining = stringSlice[Range(uncheckedBounds: (hostname.endIndex, stringSlice.endIndex))]
    return scanFromAuthorityEnd(remaining)
  }
}


// --------------------------------------------
// MARK: - Relative URLs
// --------------------------------------------


extension ScannedRangesAndFlags {

  /// Scans all components from a relative URL string.
  ///
  /// `stringSlice` should start immediately after the scheme delimiter (if present).
  /// File URLs should use `scanFileURLFromSchemeEnd` instead.
  ///
  @inlinable
  internal mutating func scanRelativeURLString<Callback: URLParserCallback>(
    _ stringSlice: InputSlice, baseScheme: WebURL.SchemeKind, callback: inout Callback
  ) -> Bool {

    self.componentsToCopyFromBase = [.scheme]

    // [URL Standard]: "relative" state.
    guard stringSlice.startIndex < stringSlice.endIndex else {
      self.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return true
    }

    // The number of slashes determines which components the string is relative to:
    //
    // | Slashes | Example     | What it means      | What to do                                                 |
    // | ------- | ----------- | ------------------ | ---------------------------------------------------------- |
    // |    2+   | //hst/p1?q  | Protocol relative  | Copy scheme, parse own authority, path, etc.               |
    // |    1    | /p1/p2?q    | Authority relative | Copy scheme, authority, parse own absolute path, etc.      |
    // |    0    | p1/p2?q     | Path relative      | Copy scheme, authority, merge relative path with base path |
    // |    0    | ?q=foo#bar  | Other relative     | Copy scheme, authority, path, replace given components     |

    switch stringSlice[stringSlice.startIndex] {
    // [URL Standard]: "relative slash" state.
    case ASCII.backslash.codePoint where baseScheme.isSpecial:
      callback.validationError(.unexpectedReverseSolidus)
      fallthrough
    case ASCII.forwardSlash.codePoint:
      var cursor = stringSlice.index(after: stringSlice.startIndex)
      guard cursor < stringSlice.endIndex else {
        self.componentsToCopyFromBase.formUnion([.authority])
        return scanFromListStylePath(stringSlice)
      }
      switch stringSlice[cursor] {
      case ASCII.backslash.codePoint where baseScheme.isSpecial:
        callback.validationError(.unexpectedReverseSolidus)
        fallthrough
      case ASCII.forwardSlash.codePoint:
        stringSlice.formIndex(after: &cursor)
        if baseScheme.isSpecial {
          // [URL Standard]: "special authority ignore slashes" state.
          // swift-format-ignore
          cursor = stringSlice[Range(uncheckedBounds: (cursor, stringSlice.endIndex))].fastFirstIndex {
            !isForwardSlashOrBackSlash($0)
          } ?? stringSlice.endIndex
        }
        let remaining = stringSlice[Range(uncheckedBounds: (cursor, stringSlice.endIndex))]
        return scanFromAuthorityStart(remaining, scheme: baseScheme, callback: &callback)

      default:
        self.componentsToCopyFromBase.formUnion([.authority])
        return scanFromListStylePath(stringSlice)
      }

    // [URL Standard]: "relative" state (again).
    case ASCII.questionMark.codePoint:
      self.componentsToCopyFromBase.formUnion([.authority, .path])
      let postDelim = stringSlice.index(after: stringSlice.startIndex)
      let remaining = stringSlice[Range(uncheckedBounds: (postDelim, stringSlice.endIndex))]
      return scanFromQuery(remaining)
    case ASCII.numberSign.codePoint:
      self.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      let postDelim = stringSlice.index(after: stringSlice.startIndex)
      let remaining = stringSlice[Range(uncheckedBounds: (postDelim, stringSlice.endIndex))]
      return scanFromFragment(remaining)
    default:
      // `scanFromListStylePath` will always set a non-nil pathRange.
      // `ParsedURLString.write` knows that if the mapping contains a non-nil pathRange,
      // and 'componentsToCopyFromBase' also contains '.path', that it should provide both the input and base paths
      // to '_PathParser', which will merge them.
      self.componentsToCopyFromBase.formUnion([.authority, .path])
      return scanFromListStylePath(stringSlice)
    }
  }
}


// --------------------------------------------
// MARK: - Post-scan validation
// --------------------------------------------


extension ScannedRangesAndFlags {

  /// Performs some basic invariant checks on the scanned URL data. For debug builds.
  ///
  #if DEBUG
    @usableFromInline
    internal func checkInvariants(_ inputString: InputString, baseURL: WebURL?) {

      // - Structural invariants.
      // Ensure that the combination of scanned ranges and flags makes sense.

      if schemeRange == nil {
        assert(componentsToCopyFromBase.contains(.scheme), "We must have a scheme from somewhere")
      }
      if usernameRange != nil || passwordRange != nil || hostnameRange != nil || portRange != nil {
        assert(hostnameRange != nil, "A scanned authority component implies a scanned hostname")
        assert(authorityRange != nil, "A scanned authority component implies a scanned authority")
        assert(!hasOpaquePath, "A URL with an authority cannot have an opaque path")
        if passwordRange != nil {
          assert(usernameRange != nil, "Can't have a password without a username (even if empty)")
        }
        if portRange != nil {
          assert(hostnameRange != nil, "Can't have a port without a hostname")
        }
      }
      if hasOpaquePath {
        assert(hostnameRange == nil, "A URL with opaque path cannot have a hostname")
        assert(authorityRange == nil, "A URL with opaque path cannot have an authority")
      }
      // Ensure components from input string do not overlap with 'componentsToCopyFromBase' (except path).
      if schemeRange != nil {
        // Scheme can only overlap in relative URLs of special schemes.
        if componentsToCopyFromBase.contains(.scheme) {
          assert(
            schemeKind!.isSpecial && schemeKind == baseURL!.schemeKind, "Copying a different scheme from baseURL?!")
        }
      }
      if authorityRange != nil {
        assert(
          !componentsToCopyFromBase.contains(.authority), "Authority was scanned; shouldn't be copied from baseURL")
      }
      if queryRange != nil {
        assert(!componentsToCopyFromBase.contains(.query), "Query was scanned; shouldn't be copied from baseURL")
      }

      // - Content invariants.
      // Make sure that things such as separators are where we expect and not inside the scanned ranges.

      if let schemeRange = schemeRange {
        assert(!schemeRange.isEmpty)
        assert(inputString[schemeRange].last != ASCII.colon.codePoint)
      }
      if authorityRange != nil {
        if let username = usernameRange {
          if let password = passwordRange {
            assert(inputString[inputString.index(before: password.lowerBound)] == ASCII.colon.codePoint)
          }
          assert(inputString[passwordRange?.upperBound ?? username.upperBound] == ASCII.commercialAt.codePoint)
        }
        assert(hostnameRange != nil)
        if let port = portRange {
          assert(inputString[inputString.index(before: port.lowerBound)] == ASCII.colon.codePoint)
        }
      }
      if let query = queryRange {
        assert(inputString[inputString.index(before: query.lowerBound)] == ASCII.questionMark.codePoint)
      }
      if let fragment = fragmentRange {
        assert(inputString[inputString.index(before: fragment.lowerBound)] == ASCII.numberSign.codePoint)
      }
    }
  #else
    @inlinable @inline(__always)
    internal func checkInvariants(_ inputString: InputString, baseURL: WebURL?) {}
  #endif
}

extension ParsedURLString.ProcessedMapping {

  /// Validates that the components of the parsed URL only contain valid URL code points,
  /// and that the "%" sign is only used for percent-encoding.
  ///
  /// The parser described in the URL Standard contains frequent sections like the following:
  ///
  /// > 1. If c is not a URL code point and not U+0025 (%), validation error.
  /// > 2. If c is U+0025 (%) and remaining does not start with two ASCII hex digits, validation error.
  /// > 3. UTF-8 percent-encode c using the path percent-encode set and append the result to buffer.
  ///
  /// The validation errors in steps (1) and (2) do not actually affect the result of parsing in any way,
  /// so it is a good idea to save this validation for later (if it is performed at all).
  /// Here's what the URL Standard says about validation errors:
  ///
  /// > A validation error does not mean that the parser terminates.
  /// > Termination of a parser is always stated explicitly, e.g., through a return statement.
  /// >
  /// > It is useful to signal validation errors as error-handling can be non-intuitive,
  /// > legacy user agents might not implement correct error-handling, and the intent of what is written
  /// > might be unclear to other developers.
  ///
  internal func validateURLCodePointsAndPercentEncoding<Callback>(
    _ string: InputString, callback: inout Callback
  ) where Callback: URLParserCallback {

    // Scheme:
    // No validation required here. Must be ASCII with no percent-encoding.

    // Username & Password:
    // Even the URL Standard doesn't care about validating them. They're sort of implicitly invalid.

    // Hostname:
    // - Domains have IDNA for validation and do not contain percent-encoding
    // - IP addresses only allow ASCII and do not contain percent-encoding
    if case .opaque = parsedHost {
      let hostRange = info.hostnameRange!
      _validateURLCodePointsAndPercentEncoding(utf8: string[hostRange], callback: &callback)
    }

    // Port:
    // No validation required here. Must be ASCII digits with no percent-encoding.

    // Path:
    if let pathRange = info.pathRange {
      if info.hasOpaquePath {
        _validateURLCodePointsAndPercentEncoding(utf8: string[pathRange], callback: &callback)
      } else {
        PathStringValidator.validate(
          pathString: string[pathRange], schemeKind: info.schemeKind!,
          hasAuthority: info.authorityRange != nil || info.componentsToCopyFromBase.contains(.authority),
          callback: &callback
        )
      }
    }

    // Query:
    if let queryRange = info.queryRange {
      _validateURLCodePointsAndPercentEncoding(utf8: string[queryRange], callback: &callback)
    }

    // Fragment:
    if let fragmentRange = info.fragmentRange {
      _validateURLCodePointsAndPercentEncoding(utf8: string[fragmentRange], callback: &callback)
    }
  }
}


// --------------------------------------------
// MARK: - Parsing Utilities
// --------------------------------------------


/// Parses a scheme from the start of the given UTF-8 code-units.
///
/// If the string contains a scheme terminator ("`:`"), the returned tuple's `terminator` element
/// will be equal to its index. Otherwise, the entire string will be considered the scheme name,
/// and `terminator` will be equal to the input string's `endIndex`.
///
/// If the string does not contain a valid scheme, this function returns `nil`.
///
@inlinable
internal func parseScheme<UTF8Bytes>(
  _ string: UTF8Bytes
) -> (terminator: UTF8Bytes.Index, kind: WebURL.SchemeKind)? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

  let terminatorIdx = string.fastFirstIndex(of: ASCII.colon.codePoint) ?? string.endIndex
  var schemeName = string[Range(uncheckedBounds: (string.startIndex, terminatorIdx))]

  let kind = WebURL.SchemeKind(parsing: schemeName)
  guard case .other = kind else {
    return (schemeName.endIndex, kind)
  }
  // This also ensures that empty schemes are rejected.
  guard schemeName.fastPopFirst().flatMap({ ASCII($0)?.isAlpha }) == true else { return nil }
  return schemeName.fastAllSatisfy { byte in
    // https://bugs.swift.org/browse/SR-14438
    // swift-format-ignore
    switch ASCII(byte) {
    case .some(let char) where char.isAlphaNumeric: fallthrough
    case .plus?, .minus?, .period?: return true
    default: return false
    }
  } ? (schemeName.endIndex, kind) : nil
}

/// Given a string, like "example.com:99/some/path?hello=world", returns the endIndex of the hostname component.
/// This is used by the Javascript model's ``WebURL/WebURL/JSModel/hostname`` setter, which accepts
/// a rather wide variety of inputs.
///
/// This is a "scan-level" operation: the discovered hostname might not be valid, and needs additional processing
/// before being written to a URL string.
///
/// The only situation in which this function returns `nil` is if the scheme is not `.file`,
/// and the given string starts with a `:` (i.e. a port with no hostname).
///
internal func findEndOfHostnamePrefix<UTF8Bytes, Callback>(
  _ string: UTF8Bytes, scheme: WebURL.SchemeKind, callback cb: inout Callback
) -> UTF8Bytes.Index?
where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

  // See `scanFromAuthorityStart`.
  let hostname = string.fastPrefix {
    switch $0 {
    case ASCII.forwardSlash.codePoint, ASCII.questionMark.codePoint, ASCII.numberSign.codePoint:
      return false
    case ASCII.backslash.codePoint where scheme.isSpecial:
      return false
    default:
      return true
    }
  }
  if case .file = scheme {
    // [URL Standard]: "file host" state.
    // Hostnames which are Windows drive letters are not interpreted as paths in setter mode,
    // so the entire authority is just interpreted as a hostname.
    return hostname.endIndex
  } else {
    // Run the scanner to split the host/port.
    var mapping = ScannedRangesAndFlags<UTF8Bytes>()
    guard mapping.scanFromHostname(hostname, authorityEnd: hostname.endIndex, callback: &cb) else {
      // Only fails if there is a port and the hostname is empty.
      assert(hostname.first == ASCII.colon.codePoint)
      return nil
    }
    return mapping.hostnameRange?.upperBound ?? hostname.endIndex
  }
}
