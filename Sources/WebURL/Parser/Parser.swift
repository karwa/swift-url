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
  @usableFromInline
  internal struct ProcessedMapping {

    @usableFromInline
    internal fileprivate(set) var info: ScannedRangesAndFlags<InputString>

    @usableFromInline
    internal private(set) var __parsedHost: Optional<ParsedHost>

    @usableFromInline
    internal private(set) var __port: Optional<UInt16>

    /// Constructs an empty ProcessedMapping.
    ///
    /// To populate the mapping, call the `parse` function.
    ///
    @inlinable
    internal init() {
      self.info = ScannedRangesAndFlags()
      self.__parsedHost = nil
      self.__port = nil
    }

    // Work around avoid expensive 'outlined init with take' calls.
    // https://bugs.swift.org/browse/SR-15215
    // https://forums.swift.org/t/expensive-calls-to-outlined-init-with-take/52187

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
  }
}

/// The positions of URL components found within a string, and the flags to interpret them.
///
/// After coming from the scanner, certain components require additional _content validation_, which can be performed by constructing a `ProcessedMapping`.
///
@usableFromInline
internal struct ScannedRangesAndFlags<InputString> where InputString: Collection {

  /// The position of the scheme's content, if present, without trailing separators.
  @usableFromInline
  internal var schemeRange: Optional<Range<InputString.Index>>

  /// The position of the authority section, if present, without leading or trailing separators.
  @usableFromInline
  internal var authorityRange: Optional<Range<InputString.Index>>

  /// The position of the username content, if present, without leading or trailing separators.
  @usableFromInline
  internal var usernameRange: Optional<Range<InputString.Index>>

  /// The position of the password content, if present, without leading or trailing separators.
  @usableFromInline
  internal var passwordRange: Optional<Range<InputString.Index>>

  /// The position of the hostname content, if present, without leading or trailing separators.
  @usableFromInline
  internal var hostnameRange: Optional<Range<InputString.Index>>

  /// The position of the port content, if present, without leading or trailing separators.
  @usableFromInline
  internal var portRange: Optional<Range<InputString.Index>>

  /// The position of the path content, if present, without leading or trailing separators.
  /// Note that the path's initial "/", if present, is not considered a separator.
  @usableFromInline
  internal var pathRange: Optional<Range<InputString.Index>>

  /// The position of the query content, if present, without leading or trailing separators.
  @usableFromInline
  internal var queryRange: Optional<Range<InputString.Index>>

  /// The position of the fragment content, if present, without leading or trailing separators.
  @usableFromInline
  internal var fragmentRange: Optional<Range<InputString.Index>>

  // Flags.

  /// The kind of scheme contained in `schemeRange`, if it is not `nil`.
  @usableFromInline
  internal var __schemeKind: Optional<WebURL.SchemeKind>

  /// Whether this URL's path is opaque.
  @usableFromInline
  internal var hasOpaquePath: Bool

  /// A flag for a quirk in the standard, which means that absolute paths in particular URL strings should copy the Windows drive from their base URL.
  @usableFromInline
  internal var absolutePathsCopyWindowsDriveFromBase: Bool

  /// The components to copy from the base URL. If non-empty, there must be a base URL.
  /// Only the scheme and path may overlap with components detected in the input string - for the former, it is a meaningless quirk of the control flow,
  /// and the two schemes must be equal; for the latter, it means the two paths should be merged (i.e. that the input string's path is relative to the base URL's path).
  @usableFromInline
  internal var componentsToCopyFromBase: _CopyableURLComponentSet

  @inlinable
  internal init(
    schemeRange: Range<InputString.Index>?,
    authorityRange: Range<InputString.Index>?,
    usernameRange: Range<InputString.Index>?,
    passwordRange: Range<InputString.Index>?,
    hostnameRange: Range<InputString.Index>?,
    portRange: Range<InputString.Index>?,
    pathRange: Range<InputString.Index>?,
    queryRange: Range<InputString.Index>?,
    fragmentRange: Range<InputString.Index>?,
    schemeKind: WebURL.SchemeKind?,
    hasOpaquePath: Bool,
    absolutePathsCopyWindowsDriveFromBase: Bool,
    componentsToCopyFromBase: _CopyableURLComponentSet
  ) {
    self.schemeRange = schemeRange
    self.authorityRange = authorityRange
    self.usernameRange = usernameRange
    self.passwordRange = passwordRange
    self.hostnameRange = hostnameRange
    self.portRange = portRange
    self.pathRange = pathRange
    self.queryRange = queryRange
    self.fragmentRange = fragmentRange
    self.__schemeKind = schemeKind
    self.hasOpaquePath = hasOpaquePath
    self.absolutePathsCopyWindowsDriveFromBase = absolutePathsCopyWindowsDriveFromBase
    self.componentsToCopyFromBase = componentsToCopyFromBase
  }

  @inlinable
  internal init() {
    self.init(
      schemeRange: nil, authorityRange: nil, usernameRange: nil, passwordRange: nil,
      hostnameRange: nil, portRange: nil, pathRange: nil, queryRange: nil, fragmentRange: nil,
      schemeKind: nil, hasOpaquePath: false, absolutePathsCopyWindowsDriveFromBase: false,
      componentsToCopyFromBase: []
    )
  }

  // This is a workaround to avoid expensive 'outlined init with take' calls.
  // https://bugs.swift.org/browse/SR-15215
  // https://forums.swift.org/t/expensive-calls-to-outlined-init-with-take/52187

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

  @inlinable
  internal init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  @inlinable internal static var scheme: Self    { Self(rawValue: 1 << 0) }
  @inlinable internal static var authority: Self { Self(rawValue: 1 << 1) }
  @inlinable internal static var path: Self      { Self(rawValue: 1 << 2) }
  @inlinable internal static var query: Self     { Self(rawValue: 1 << 3) }
}

extension ParsedURLString.ProcessedMapping {

  @inlinable
  internal mutating func parse<Callback: URLParserCallback>(
    inputString: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> Bool {

    URLScanner.scanURLString(&info, string: inputString, baseURL: baseURL, callback: &callback)
      && process(inputString: inputString, baseURL: baseURL, callback: &callback)
  }

  /// Parses failable components discovered by the scanner.
  ///
  /// Successful construction of this mapping affirms that the URL components discovered by the scanner do not contain invalid content,
  /// and may definitely be written to a `URLWriter` as a standard-compliant, normalized URL string.
  ///
  @inlinable
  internal mutating func process<Callback>(
    inputString: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> Bool where Callback: URLParserCallback {

    info.checkInvariants(inputString, baseURL: baseURL)

    if info.schemeKind == nil {
      guard let baseURL = baseURL, info.componentsToCopyFromBase.contains(.scheme) else {
        preconditionFailure("We must have a scheme")
      }
      info.schemeKind = baseURL.schemeKind
    }

    // Port.
    var port: UInt16?
    if let portRange = info.portRange, portRange.isEmpty == false {
      guard let parsedInteger = ASCII.parseDecimalU16(from: inputString[portRange]) else {
        callback.validationError(.portOutOfRange)
        return false
      }
      if parsedInteger != info.schemeKind!.defaultPort {
        port = parsedInteger
      }
    }

    // Host.
    var parsedHost: ParsedHost?
    if let hostnameRange = info.hostnameRange {
      parsedHost = ParsedHost(inputString[hostnameRange], schemeKind: info.schemeKind!, callback: &callback)
      guard parsedHost != nil else { return false }
    }

    self.__parsedHost = parsedHost
    self.__port = port
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
          baseURL: info.componentsToCopyFromBase.contains(.path) ? baseURL.unsafelyUnwrapped : nil,
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
          baseURL: info.componentsToCopyFromBase.contains(.path) ? baseURL.unsafelyUnwrapped : nil,
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


/// A namespace for URL scanning methods.
///
@usableFromInline
internal enum URLScanner<InputString>
where InputString: BidirectionalCollection, InputString.Element == UInt8 {

  @usableFromInline
  internal typealias SchemeKind = WebURL.SchemeKind
  @usableFromInline
  internal typealias InputSlice = InputString.SubSequence
}

extension URLScanner {

  /// Populates the given empty mapping by scanning a URL string.
  ///
  /// - parameters:
  ///   - scanResults: An empty mapping which will be populated with the scan results.
  ///   - input:       The input string, as a collection of UTF8 bytes.
  ///   - baseURL:     The base URL to interpret `input` against.
  ///   - callback:    An object to notify about any validation errors which are encountered.
  ///
  /// - returns: Whether or not scanning was successful.
  ///
  @inlinable
  internal static func scanURLString<Callback: URLParserCallback>(
    _ scanResults: inout ScannedRangesAndFlags<InputString>,
    string: InputString, baseURL: WebURL?, callback: inout Callback
  ) -> Bool {

    if let (schemeEndIndex, schemeKind) = parseScheme(string), schemeEndIndex < string.endIndex {
      scanResults.schemeKind = schemeKind
      scanResults.schemeRange = Range(uncheckedBounds: (string.startIndex, schemeEndIndex))
      return scanURLWithScheme(
        &scanResults,
        string[Range(uncheckedBounds: (string.index(after: schemeEndIndex), string.endIndex))],
        scheme: schemeKind,
        baseURLScheme: baseURL?.schemeKind,
        callback: &callback
      )
    }

    // [URL Standard]: "no scheme" state

    guard let base = baseURL else {
      callback.validationError(.missingSchemeNonRelativeURL)
      return false
    }
    var inputSlice = string[Range(uncheckedBounds: (string.startIndex, string.endIndex))]

    if base.hasOpaquePath {
      guard inputSlice.fastPopFirst() == ASCII.numberSign.codePoint else {
        callback.validationError(.missingSchemeNonRelativeURL)
        return false
      }
      scanResults.componentsToCopyFromBase = [.scheme, .path, .query]
      scanResults.hasOpaquePath = true
      scanFromFragment(&scanResults, inputSlice)
      return true
    }
    if case .file = base.schemeKind {
      scanResults.componentsToCopyFromBase = [.scheme]
      scanFileURL(&scanResults, inputSlice, baseURLScheme: .file, callback: &callback)
      return true
    }
    return scanRelativeURLString(&scanResults, inputSlice, baseScheme: base.schemeKind, callback: &callback)
  }

  /// Populates the given mapping by scanning all components following the URL's scheme.
  ///
  /// The given slice of the input string should begin immediately after the scheme delimiter.
  ///
  @inlinable
  internal static func scanURLWithScheme<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, scheme: SchemeKind, baseURLScheme: WebURL.SchemeKind?, callback: inout Callback
  ) -> Bool {

    // [URL Standard]: "scheme" state.
    switch scheme {
    case .http, .https, .ws, .wss, .ftp:
      // [URL Standard]:
      //   - "special relative or authority",
      //   - "special authority slashes",
      //   - "special authority ignore slashes"
      var trimmedInput = input
      if let afterPrefix = indexAfterDoubleSolidusPrefix(utf8: trimmedInput) {
        trimmedInput = trimmedInput[Range(uncheckedBounds: (afterPrefix, trimmedInput.endIndex))]
      } else if scheme == baseURLScheme {
        callback.validationError(.relativeURLMissingBeginningSolidus)
        return scanRelativeURLString(&mapping, trimmedInput, baseScheme: scheme, callback: &callback)
      } else {
        callback.validationError(.missingSolidusBeforeAuthority)
      }
      trimmedInput = trimmedInput.fastDrop { isForwardSlashOrBackSlash($0) }
      return scanURLWithAuthority(&mapping, trimmedInput, scheme: scheme, callback: &callback)

    case .file:
      if indexAfterDoubleSolidusPrefix(utf8: input) == nil {
        callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      scanFileURL(&mapping, input, baseURLScheme: baseURLScheme, callback: &callback)
      return true

    case .other:
      var trimmedInput = input
      guard trimmedInput.fastPopFirst() == ASCII.forwardSlash.codePoint else {
        return scanURLWithOpaquePath(&mapping, input)
      }
      // [URL Standard]: "path or authority" state.
      guard trimmedInput.fastPopFirst() == ASCII.forwardSlash.codePoint else {
        return scanURLWithPathNoAuthority(&mapping, input)
      }
      return scanURLWithAuthority(&mapping, trimmedInput, scheme: scheme, callback: &callback)
    }
  }

  /// Scans all components from `input`, starting with an authority
  /// and proceeding to the path, query, and fragment.
  ///
  /// Leading slashes should **not** be included in the given slice of the input string.
  ///
  @inlinable
  internal static func scanURLWithAuthority<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, scheme: WebURL.SchemeKind, callback: inout Callback
  ) -> Bool {

    switch scanAuthority(&mapping, input, scheme: scheme, callback: &callback) {
    case .success(scanPathStartFrom: let afterAuthority):
      let remaining = input[Range(uncheckedBounds: (afterAuthority, input.endIndex))]
      scanFromPathStart(&mapping, remaining)
      return true
    case .failed:
      return false
    }
  }

  /// Scans all components from `input`, starting with a path
  /// and proceeding to the query and fragment.
  ///
  @inlinable
  internal static func scanURLWithPathNoAuthority(
    _ mapping: inout ScannedRangesAndFlags<InputString>, _ input: InputSlice
  ) -> Bool {
    scanFromPath(&mapping, input)
    return true
  }
}


// --------------------------------------------
// MARK: - Authority components
// --------------------------------------------


extension URLScanner {

  @usableFromInline
  internal enum AuthorityScanResult {
    case success(scanPathStartFrom: InputString.Index)
    case failed
  }

  /// Populates the given mapping by scanning the authority components from the given URL string.
  ///
  /// The given slice of the input string should begin immediately after the authority sigil (leading `'//'`).
  ///
  /// This method returns `.failure` if the structure is not valid (e.g. a port without a hostname).
  /// Otherwise, scanning should continue from the returned location at the `pathStart` state.
  ///
  @inlinable
  internal static func scanAuthority<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, scheme: WebURL.SchemeKind, callback: inout Callback
  ) -> AuthorityScanResult {

    // 1. Validate the mapping.
    assert(mapping.usernameRange == nil)
    assert(mapping.passwordRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.authorityRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    // TODO: Can extents be split as a separate function? Perhaps it can be merged with the later pathStart scan.
    // 2. Find the extent of the authority (i.e. the delimiter for the path/query/fragment).
    let authority = input.fastPrefix {
      switch $0 {
      case ASCII.forwardSlash.codePoint, ASCII.questionMark.codePoint, ASCII.numberSign.codePoint:
        return false
      case ASCII.backslash.codePoint where scheme.isSpecial:
        return false
      default:
        return true
      }
    }
    mapping.authorityRange = Range(uncheckedBounds: (authority.startIndex, authority.endIndex))

    // 3. Split the authority in to [credentials]@[host-and-port]
    let hostAndPort: InputSlice
    if let credentialsEndIndex = authority.fastLastIndex(of: ASCII.commercialAt.codePoint) {
      let credentials = authority[Range(uncheckedBounds: (authority.startIndex, credentialsEndIndex))]
      scanCredentials(&mapping, credentials, callback: &callback)
      let hostnameStart = input.index(after: credentialsEndIndex)
      guard hostnameStart < authority.endIndex else {
        callback.validationError(.unexpectedCredentialsWithoutHost)
        return .failed
      }
      hostAndPort = authority[Range(uncheckedBounds: (hostnameStart, authority.endIndex))]
    } else {
      _onFastPath()
      hostAndPort = authority
    }

    // 4. Validate the structure.
    if hostAndPort.isEmpty, scheme.isSpecial {
      callback.validationError(.emptyHostSpecialScheme)
      return .failed
    }

    // 5. Scan the host and port.
    _onFastPath()
    return scanAuthorityFromHostname(&mapping, hostAndPort, callback: &callback)
  }

  /// Populates the given mapping by scanning the credentials/user-info components from the given string.
  ///
  /// The given slice of the input string should begin immediately after the authority sigil (leading `'//'`),
  /// and its endIndex should be the location of the `'@'` sign which delimits the user-info section.
  ///
  @inlinable @inline(never)
  internal static func scanCredentials<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, callback: inout Callback
  ) {

    // 1. Validate the mapping.
    assert(mapping.usernameRange == nil)
    assert(mapping.passwordRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    callback.validationError(.unexpectedCommercialAt)

    // 2. Split the credentials string in to [username]:[password].
    let delimiter = input.fastFirstIndex(of: ASCII.colon.codePoint)

    // 3. Mark the components.
    if let delimiter = delimiter {
      mapping.usernameRange = Range(uncheckedBounds: (input.startIndex, delimiter))
      mapping.passwordRange = Range(uncheckedBounds: (input.index(after: delimiter), input.endIndex))
    } else {
      mapping.usernameRange = Range(uncheckedBounds: (input.startIndex, input.endIndex))
    }
  }

  /// Populates the given mapping by scanning the hostname and port from the given authority string.
  ///
  /// The given slice of the input string should begin immediately after the authority sigil (leading `'//'`),
  /// or after the user-info delimiter (`'@'`) if there is one, and should end where the authority section ends.
  ///
  @inlinable
  internal static func scanAuthorityFromHostname<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, callback: inout Callback
  ) -> AuthorityScanResult {

    // 1. Validate the mapping.
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    // 2. Find the extent of the hostname.
    var portDelimiter: InputSlice.Index?
    do {
      // We could just split the hostname at the first colon after a closing bracket,
      // but changes to the standard might prohibit that. For now, split exactly where the standard does.
      // https://github.com/whatwg/url/pull/673
      var cursor = input.startIndex
      var inBracket = false
      portSearch: while cursor < input.endIndex {
        switch input[cursor] {
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
        input.formIndex(after: &cursor)
      }
    }
    let hostname = input[Range(uncheckedBounds: (input.startIndex, portDelimiter ?? input.endIndex))]

    // 3. Validate the structure.
    if let portDelimiter = portDelimiter, portDelimiter == input.startIndex {
      callback.validationError(.unexpectedPortWithoutHost)
      return .failed
    }
    _onFastPath()

    // 4. Return the next component.
    mapping.hostnameRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    if let portDelimiter = portDelimiter {
      let remaining = input[Range(uncheckedBounds: (input.index(after: portDelimiter), input.endIndex))]
      return scanPort(&mapping, remaining, callback: &callback)
    } else {
      return .success(scanPathStartFrom: input.endIndex)
    }
  }

  /// Scans an authority section's port.
  ///
  /// The port's leading `':'` delimiter should **not** be included in the given slice of the authority string.
  ///
  @inlinable
  internal static func scanPort<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, callback: inout Callback
  ) -> AuthorityScanResult {

    // 1. Validate the mapping.
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    // The port string is not validated, because ProcessedMapping will parse it later as a 16-bit integer.
    // Invalid ports will fail at that point.

    // 2. Mark the component range.
    mapping.portRange = Range(uncheckedBounds: (input.startIndex, input.endIndex))
    return .success(scanPathStartFrom: input.endIndex)
  }
}


// --------------------------------------------
// MARK: - Generic components
// --------------------------------------------


extension URLScanner {

  /// Scans all URL components from the character immediately following the authority.
  ///
  /// The end of the authority is marked by some delimiter - either a slash, `'?'`, or `'#'`.
  /// This delimiter signifies which component comes after the authority and **should** be included in the given
  /// slice of the input string.
  ///
  @inlinable
  internal static func scanFromPathStart(
    _ mapping: inout ScannedRangesAndFlags<InputString>, _ input: InputSlice
  ) {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    // 2. Scan the next component.
    guard input.startIndex < input.endIndex else {
      // No components after the authority.
      return
    }

    let delimiter = input[input.startIndex]
    let remaining = input[Range(uncheckedBounds: (input.index(after: input.startIndex), input.endIndex))]
    switch delimiter {
    case ASCII.questionMark.codePoint:
      return scanFromQuery(&mapping, remaining)
    case ASCII.numberSign.codePoint:
      return scanFromFragment(&mapping, remaining)
    default:
      assert(delimiter == ASCII.forwardSlash.codePoint || delimiter == ASCII.backslash.codePoint)
      return scanFromPath(&mapping, input)
    }
  }

  /// Scans all URL components from the path onwards.
  ///
  /// If the path includes a leading slash delimiter, it **should** be included in the given slice of the input string.
  /// This function is for list-style paths only (not opaque paths).
  ///
  @inlinable
  internal static func scanFromPath(
    _ mapping: inout ScannedRangesAndFlags<InputString>, _ input: InputSlice
  ) {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    // 2. Find the extent of the path.
    var nextComponentIsQuery = false
    let nextComponentDelimiter = input.fastFirstIndex {
      if $0 == ASCII.questionMark.codePoint {
        nextComponentIsQuery = true
        return true
      } else if $0 == ASCII.numberSign.codePoint {
        return true
      }
      return false
    }
    let pathEnd = nextComponentDelimiter ?? input.endIndex

    // 3. Scan the next component.
    if input.startIndex < pathEnd {
      mapping.pathRange = Range(uncheckedBounds: (input.startIndex, pathEnd))
    }
    if var nextComponentStart = nextComponentDelimiter {
      input.formIndex(after: &nextComponentStart)
      let remaining = input[Range(uncheckedBounds: (nextComponentStart, input.endIndex))]
      return nextComponentIsQuery ? scanFromQuery(&mapping, remaining) : scanFromFragment(&mapping, remaining)
    }
  }

  /// Scans all URL components from the query onwards.
  ///
  /// The query's leading `'?'` delimiter should **not** be included in the given slice of the input string.
  ///
  @inlinable
  internal static func scanFromQuery(
    _ mapping: inout ScannedRangesAndFlags<InputString>, _ input: InputSlice
  ) {

    // 1. Validate the mapping.
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the query
    let fragmentDelimiter = input.fastFirstIndex(of: ASCII.numberSign.codePoint)

    // 3. Scan the next component.
    mapping.queryRange = Range(uncheckedBounds: (input.startIndex, fragmentDelimiter ?? input.endIndex))
    if var fragmentStart = fragmentDelimiter {
      input.formIndex(after: &fragmentStart)
      return scanFromFragment(&mapping, input[Range(uncheckedBounds: (fragmentStart, input.endIndex))])
    }
  }

  /// Scans a URL string's fragment.
  ///
  /// The fragment's leading `'#'` delimiter should **not** be included in the given slice of the input string.
  ///
  @inlinable
  internal static func scanFromFragment(
    _ mapping: inout ScannedRangesAndFlags<InputString>, _ input: InputSlice
  ) {

    // 1. Validate the mapping.
    assert(mapping.fragmentRange == nil)

    // 2. Mark the component range.
    mapping.fragmentRange = Range(uncheckedBounds: (input.startIndex, input.endIndex))
  }
}


// --------------------------------------------
// MARK: - File URLs
// --------------------------------------------


extension URLScanner {

  /// Scans all components from `input`, which is known to belong to a file URL.
  ///
  /// The given slice of the input string should start immediately after the input's scheme delimiter (if it has one).
  /// This function handles both relative and absolute URL strings, and starts by determining which components
  /// should be copied from the base URL and which should be scanned.
  ///
  @inlinable
  internal static func scanFileURL<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, baseURLScheme: WebURL.SchemeKind?, callback: inout Callback
  ) {

    // file URLs may also be relative. It all depends on what comes after "file:".
    // - 0 slashes:  copy base host, parse as relative path.
    // - 1 slash:    copy base host, parse as absolute path.
    // - 2+ slashes: parse own host, parse absolute path.

    assert(mapping.componentsToCopyFromBase.isEmpty || mapping.componentsToCopyFromBase == [.scheme])

    var cursor = input.startIndex
    guard cursor < input.endIndex, isForwardSlashOrBackSlash(input[cursor]) else {
      // [URL Standard: "file" state].
      // No slashes. Some kind of relative string (e.g. "file:usr/lib/Swift", "file:?someQuery").
      guard case .file = baseURLScheme else {
        return scanFromPath(&mapping, input)
      }
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])

      guard cursor < input.endIndex else {
        return
      }
      let delimiter = input[cursor]
      let remaining = input[Range(uncheckedBounds: (input.index(after: cursor), input.endIndex))]
      switch delimiter {
      case ASCII.numberSign.codePoint:
        return scanFromFragment(&mapping, remaining)
      case ASCII.questionMark.codePoint:
        mapping.componentsToCopyFromBase.remove(.query)
        return scanFromQuery(&mapping, remaining)
      default:
        mapping.componentsToCopyFromBase.remove(.query)
        // If a relative path starts with a Windows drive letter, it is not resolved like a relative path.
        // `_PathParser` knows how to handle this without any special flags in the mapping.
        if PathComponentParser.hasWindowsDriveLetterPrefix(input) {
          callback.validationError(.unexpectedWindowsDriveLetter)
        }
        return scanFromPath(&mapping, input)
      }
    }
    if input[cursor] == ASCII.backslash.codePoint {
      callback.validationError(.unexpectedReverseSolidus)
    }
    input.formIndex(after: &cursor)

    guard cursor < input.endIndex, isForwardSlashOrBackSlash(input[cursor]) else {
      // [URL Standard: "file slash" state].
      // 1 slash. Absolute path ("file:/usr/lib/Swift").
      guard case .file = baseURLScheme else {
        return scanFromPath(&mapping, input)
      }
      mapping.componentsToCopyFromBase.formUnion([.authority])

      // Absolute paths in path-only URLs are still relative to the base URL's Windows drive letter (if it has one).
      // This only occurs if the string goes through the "file slash" state - not if it contains a hostname
      // and goes through the "file host" state. The path parser requires a flag to opt-in to that behaviour.
      mapping.absolutePathsCopyWindowsDriveFromBase = true
      mapping.componentsToCopyFromBase.formUnion([.path])

      return scanFromPath(&mapping, input)
    }
    if input[cursor] == ASCII.backslash.codePoint {
      callback.validationError(.unexpectedReverseSolidus)
    }
    let pathStartIfDriveLetter = cursor
    input.formIndex(after: &cursor)

    // [URL Standard: "file host" state].
    // 2+ slashes. e.g. "file://localhost/usr/lib/Swift" or "file:///usr/lib/Swift".
    return scanFromFileHostOrPath(
      &mapping,
      input,
      startIfHost: cursor,
      startIfPath: pathStartIfDriveLetter,
      callback: &callback
    )
  }

  /// Scans all URL components from the hostname onwards, for file URLs.
  ///
  /// Note that, unlike the generic "host" scanner, this never fails - even if there is a port and no hostname.
  /// In that case, the scanned hostname will contain the port and ultimately get rejected for containing
  /// a forbidden host code-point.
  ///
  /// If the hostname is a Windows drive letter, the entire authority section is instead considered an absolute path.
  /// For example, in the URL `"file://C:/Windows/"`, the entire part `"/C:/Windows/"` is interpreted as the path.
  /// Since Swift's Collection model does not allow slices to expand their bounds, the indexes of both the last
  /// authority delimiter and start of the hostname must be provided.
  ///
  /// ```
  /// "file://C:/Windows/"
  ///        ^^
  ///        ||
  ///        |+- startIfHost ("C:/...")
  ///        +- startIfPath  ("/C:/...")
  /// ```
  ///
  @inlinable
  internal static func scanFromFileHostOrPath<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, startIfHost: InputString.Index, startIfPath: InputString.Index, callback: inout Callback
  ) {

    // 1. Validate the mapping.
    assert(mapping.authorityRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    // 2. Find the extent of the hostname.
    var hostname = input[Range(uncheckedBounds: (startIfHost, input.endIndex))]
    // swift-format-ignore
    let hostnameEnd = hostname.fastFirstIndex { byte in
      switch byte {
      case ASCII.forwardSlash.codePoint, ASCII.backslash.codePoint,
           ASCII.questionMark.codePoint, ASCII.numberSign.codePoint:
        return true
      default:
        return false
      }
    } ?? input.endIndex
    hostname = input[Range(uncheckedBounds: (hostname.startIndex, hostnameEnd))]

    // 3. Scan the next component.
    if PathComponentParser.isWindowsDriveLetter(hostname) {
      // If the hostname is a Windows drive letter, input looks like: "file://C:/...".
      // We consider that a mistake, so the "/C:/..." part gets interpreted as an absolute path.
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return scanFromPath(&mapping, input[Range(uncheckedBounds: (startIfPath, input.endIndex))])
    }
    mapping.authorityRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    mapping.hostnameRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    let remaining = input[Range(uncheckedBounds: (hostnameEnd, input.endIndex))]
    return scanFromPathStart(&mapping, remaining)
  }
}


// --------------------------------------------
// MARK: - URLs with opaque paths
// --------------------------------------------


extension URLScanner {

  /// Scans all URL components from the path onwards, for URLs with opaque paths.
  ///
  @inlinable
  internal static func scanURLWithOpaquePath(
    _ mapping: inout ScannedRangesAndFlags<InputString>, _ input: InputSlice
  ) -> Bool {

    // 1. Validate the mapping.
    assert(mapping.authorityRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)
    assert(!mapping.hasOpaquePath)

    mapping.hasOpaquePath = true

    // 2. Find the extent of the path.
    var nextComponentIsQuery = false
    let nextComponentDelimiter = input.fastFirstIndex {
      if $0 == ASCII.questionMark.codePoint {
        nextComponentIsQuery = true
        return true
      } else if $0 == ASCII.numberSign.codePoint {
        return true
      }
      return false
    }
    let pathEnd = nextComponentDelimiter ?? input.endIndex

    // 3. Scan the next component.
    if input.startIndex < pathEnd {
      mapping.pathRange = Range(uncheckedBounds: (input.startIndex, pathEnd))
    }
    if var nextComponentStart = nextComponentDelimiter {
      input.formIndex(after: &nextComponentStart)
      let remaining = input[Range(uncheckedBounds: (nextComponentStart, input.endIndex))]
      nextComponentIsQuery ? scanFromQuery(&mapping, remaining) : scanFromFragment(&mapping, remaining)
    }
    return true
  }
}


// --------------------------------------------
// MARK: - Relative URLs
// --------------------------------------------


extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  @inlinable
  internal static func scanRelativeURLString<Callback: URLParserCallback>(
    _ mapping: inout ScannedRangesAndFlags<InputString>,
    _ input: InputSlice, baseScheme: WebURL.SchemeKind, callback: inout Callback
  ) -> Bool {

    mapping.componentsToCopyFromBase = [.scheme]

    // [URL Standard: "relative" state].
    guard input.startIndex < input.endIndex else {
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return true
    }

    switch input[input.startIndex] {
    // [URL Standard: "relative slash" state].
    case ASCII.backslash.codePoint where baseScheme.isSpecial:
      callback.validationError(.unexpectedReverseSolidus)
      fallthrough
    case ASCII.forwardSlash.codePoint:
      var cursor = input.index(after: input.startIndex)
      guard cursor < input.endIndex else {
        mapping.componentsToCopyFromBase.formUnion([.authority])
        scanFromPath(&mapping, input)
        return true
      }
      switch input[cursor] {
      case ASCII.backslash.codePoint where baseScheme.isSpecial:
        callback.validationError(.unexpectedReverseSolidus)
        fallthrough
      case ASCII.forwardSlash.codePoint:
        input.formIndex(after: &cursor)
        if baseScheme.isSpecial {
          // [URL Standard: "special authority ignore slashes" state].
          // swift-format-ignore
          cursor = input[Range(uncheckedBounds: (cursor, input.endIndex))].fastFirstIndex {
            !isForwardSlashOrBackSlash($0)
          } ?? input.endIndex
        }
        let remaining = input[Range(uncheckedBounds: (cursor, input.endIndex))]
        return scanURLWithAuthority(&mapping, remaining, scheme: baseScheme, callback: &callback)

      default:
        mapping.componentsToCopyFromBase.formUnion([.authority])
        scanFromPath(&mapping, input)
      }

    // Back to [URL Standard: "relative" state].
    case ASCII.questionMark.codePoint:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      let remaining = input[Range(uncheckedBounds: (input.index(after: input.startIndex), input.endIndex))]
      scanFromQuery(&mapping, remaining)
    case ASCII.numberSign.codePoint:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      let remaining = input[Range(uncheckedBounds: (input.index(after: input.startIndex), input.endIndex))]
      scanFromFragment(&mapping, remaining)
    default:
      // Since we have a non-empty slice which doesn't begin with a query/fragment sigil ("?"/"#"),
      // `scanFromPath` will always set a non-nil pathRange.
      // `ParsedURLString.write` knows that if the mapping contains a non-nil pathRange,
      // and 'componentsToCopyFromBase' also contains '.path', that it should provide both the input and base paths
      // to '_PathParser', which will merge them.
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      scanFromPath(&mapping, input)
    }
    return true
  }
}


// --------------------------------------------
// MARK: - Post-scan validation
// --------------------------------------------


extension ScannedRangesAndFlags where InputString: BidirectionalCollection, InputString.Element == UInt8 {

  internal func validate<Callback>(_ inputString: InputString, callback: inout Callback)
  where Callback: URLParserCallback {

    guard let scheme = schemeKind else {
      fatalError()
    }

    if let pathRange = pathRange {
      if hasOpaquePath {
        validateURLCodePointsAndPercentEncoding(utf8: inputString[pathRange], callback: &callback)
      } else {
        PathStringValidator.validate(
          pathString: inputString[pathRange], schemeKind: scheme,
          hasAuthority: authorityRange != nil || componentsToCopyFromBase.contains(.authority),
          callback: &callback
        )
      }
    }
    if let queryRange = queryRange {
      validateURLCodePointsAndPercentEncoding(utf8: inputString[queryRange], callback: &callback)
    }
    if let fragmentRange = fragmentRange {
      validateURLCodePointsAndPercentEncoding(utf8: inputString[fragmentRange], callback: &callback)
    }
  }

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


// --------------------------------------------
// MARK: - Parsing Utilities
// --------------------------------------------


/// Parses a scheme from the start of the given UTF-8 code-units.
///
/// If the string contains a scheme terminator ("`:`"), the returned tuple's `terminator` element will be equal to its index.
/// Otherwise, the entire string will be considered the scheme name, and `terminator` will be equal to the input string's `endIndex`.
/// If the string does not contain a valid scheme, this function returns `nil`.
///
@inlinable
func parseScheme<UTF8Bytes>(
  _ input: UTF8Bytes
) -> (terminator: UTF8Bytes.Index, kind: WebURL.SchemeKind)? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

  let terminatorIdx = input.fastFirstIndex { $0 == ASCII.colon.codePoint } ?? input.endIndex
  let schemeName = input[Range(uncheckedBounds: (input.startIndex, terminatorIdx))]
  let kind = WebURL.SchemeKind(parsing: schemeName)

  guard case .other = kind else {
    return (terminatorIdx, kind)
  }
  // Note: this ensures empty strings are rejected.
  guard ASCII(flatMap: schemeName.first)?.isAlpha == true else { return nil }
  let isValidSchemeName = schemeName.allSatisfy { byte in
    // https://bugs.swift.org/browse/SR-14438
    // swift-format-ignore
    switch ASCII(byte) {
    case .some(let char) where char.isAlphaNumeric: fallthrough
    case .plus?, .minus?, .period?: return true
    default: return false
    }
  }
  return isValidSchemeName ? (terminatorIdx, kind) : nil
}

/// Given a string, like "example.com:99/some/path?hello=world", returns the endIndex of the hostname component.
/// This is used by the Javascript model's `hostname` setter, which accepts a rather wide variety of inputs.
///
/// This is a "scan-level" operation: the discovered hostname may need additional processing before being written to a URL string.
/// The only situation in which this function returns `nil` is if the scheme is not `file`, and the given string starts with a `:`
/// (i.e. contains a port but no hostname).
///
internal func findEndOfHostnamePrefix<UTF8Bytes, Callback>(
  _ input: UTF8Bytes, scheme: WebURL.SchemeKind, callback cb: inout Callback
) -> UTF8Bytes.Index?
where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8, Callback: URLParserCallback {

  var mapping = ScannedRangesAndFlags<UTF8Bytes>()

  // See `URLScanner.scanAuthority`.
  let hostname = input.fastPrefix {
    switch $0 {
    case ASCII.forwardSlash.codePoint, ASCII.questionMark.codePoint, ASCII.numberSign.codePoint:
      return false
    case ASCII.backslash.codePoint where scheme.isSpecial:
      return false
    default:
      return true
    }
  }
  if scheme == .file {
    // [URL Standard: "file host" state].
    // Hostnames which are Windows drive letters are not interpreted as paths in setter mode, so pSIDL = nil.
    //    _ = URLScanner.scanFileHostOrPath(
    //      hostname,
    //      startIfHostname: hostname.startIndex,
    //      startIfPath: nil,
    //      &mapping, callback: &cb
    //    )
    mapping.hostnameRange = hostname.startIndex..<hostname.endIndex
  } else {
    guard case .success(_) = URLScanner.scanAuthorityFromHostname(&mapping, hostname, callback: &cb) else {
      // Only fails if there is a port and the hostname is empty.
      assert(hostname.first == ASCII.colon.codePoint)
      return nil
    }
  }
  return mapping.hostnameRange?.upperBound ?? hostname.endIndex
}
