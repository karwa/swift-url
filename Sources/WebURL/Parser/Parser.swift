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
//    This initializer calls in to `URLScanner.scanURLString', which begins the process of scanning the byte string -
//    looking for components and marking where they start/end. The scanner concerns itself with locating components,
//    not with checking their content.
//
//    The resulting component ranges and flags are validated and stored as a 'ParsedURLString.ProcessedMapping',
//    which checks the few components that can actually be rejected on content. At this point, we are finished parsing,
//    and the 'ParsedURLString' object is returned to 'urlFromBytes'.
//
// - Construction:
//    'urlFromBytes' calls 'constructURLObject' on the result of the previous step, which unconditionally writes
//    the content to freshly-allocated storage. The actual construction process involves performing a dry-run
//    to calculate the optimal result type and produce an allocation which is correctly sized to hold the result.
//
//-------------------------------------------------------------------------

@inlinable
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
/// A `ParsedURLString` contains both the input string and base URL, together with information from the parser which describes where each component can
/// be found (either within the input string, or copied from the base URL). The `ParsedURLString` can then write the contents to any `URLWriter`, performing
/// any transformations needed by specific components (e.g. lowercasing, percent-encoding/decoding) as it does so.
///
@usableFromInline
internal struct ParsedURLString<InputString> where InputString: BidirectionalCollection, InputString.Element == UInt8 {

  @usableFromInline
  internal let inputString: InputString

  @usableFromInline
  internal let baseURL: WebURL?

  @usableFromInline
  internal let mapping: ProcessedMapping

  /// Parses the given collection of UTF8 bytes as a URL string, relative to the given base URL.
  ///
  /// - parameters:
  ///   - inputString:  The input string, as a collection of UTF8 bytes.
  ///   - baseURL:      The base URL against which `inputString` should be interpreted.
  ///   - callback:     A callback to receive validation errors. If these are unimportant, pass an instance of `IngoreValidationErrors`.
  ///
  @inlinable
  internal init?<Callback: URLParserCallback>(
    parsing inputString: InputString, baseURL: WebURL?, callback: inout Callback
  ) {
    guard let ranges = URLScanner.scanURLString(inputString, baseURL: baseURL, callback: &callback),
      let mapping = ProcessedMapping(ranges, inputString: inputString, baseURL: baseURL, callback: &callback)
    else {
      return nil
    }
    self.inputString = inputString
    self.baseURL = baseURL
    self.mapping = mapping
  }

  /// Writes the URL to the given `URLWriter`.
  ///
  /// - Note: Providing a `URLWriterHints` object for this `ParsedURLString` can significantly speed the process.
  ///         Obtain metrics by writing the string to a `StructureAndMetricsCollector`.
  ///
  @inlinable
  internal func write<WriterType: URLWriter>(to writer: inout WriterType) {
    mapping.write(inputString: inputString, baseURL: baseURL, to: &writer)
  }

  /// Writes the URL to new `URLStorage`, appropriate for its size and structure, and returns it as a `WebURL` object.
  ///
  @inlinable
  internal func constructURLObject() -> WebURL {
    var info = StructureAndMetricsCollector()
    write(to: &info)
    let storage = AnyURLStorage(optimalStorageForCapacity: info.requiredCapacity, structure: info.structure) { buffer in
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
    internal let info: ScannedRangesAndFlags<InputString>

    @usableFromInline
    internal let parsedHost: ParsedHost?

    @usableFromInline
    internal let port: UInt16?
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
  internal var schemeRange: Range<InputString.Index>?

  /// The position of the authority section, if present, without leading or trailing separators.
  @usableFromInline
  internal var authorityRange: Range<InputString.Index>?

  /// The position of the username content, if present, without leading or trailing separators.
  @usableFromInline
  internal var usernameRange: Range<InputString.Index>?

  /// The position of the password content, if present, without leading or trailing separators.
  @usableFromInline
  internal var passwordRange: Range<InputString.Index>?

  /// The position of the hostname content, if present, without leading or trailing separators.
  @usableFromInline
  internal var hostnameRange: Range<InputString.Index>?

  /// The position of the port content, if present, without leading or trailing separators.
  @usableFromInline
  internal var portRange: Range<InputString.Index>?

  /// The position of the path content, if present, without leading or trailing separators.
  /// Note that the path's initial "/", if present, is not considered a separator.
  @usableFromInline
  internal var pathRange: Range<InputString.Index>?

  /// The position of the query content, if present, without leading or trailing separators.
  @usableFromInline
  internal var queryRange: Range<InputString.Index>?

  /// The position of the fragment content, if present, without leading or trailing separators.
  @usableFromInline
  internal var fragmentRange: Range<InputString.Index>?

  // Flags.

  /// The kind of scheme contained in `schemeRange`, if it is not `nil`.
  @usableFromInline
  internal var schemeKind: WebURL.SchemeKind?

  /// Whether this URL is hierarchical ("cannot-be-a-base" is false).
  @usableFromInline
  internal var isHierarchical: Bool

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
    isHierarchical: Bool,
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
    self.schemeKind = schemeKind
    self.isHierarchical = isHierarchical
    self.absolutePathsCopyWindowsDriveFromBase = absolutePathsCopyWindowsDriveFromBase
    self.componentsToCopyFromBase = componentsToCopyFromBase
  }

  @inlinable init() {
    self.init(
      schemeRange: nil, authorityRange: nil, usernameRange: nil, passwordRange: nil,
      hostnameRange: nil, portRange: nil, pathRange: nil, queryRange: nil, fragmentRange: nil,
      schemeKind: nil, isHierarchical: true, absolutePathsCopyWindowsDriveFromBase: false,
      componentsToCopyFromBase: []
    )
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

  /// Parses failable components discovered by the scanner.
  /// This is the last stage at which parsing may fail, and successful construction of this mapping signifies that the input string can definitely be written as a URL.
  ///
  @inlinable
  internal init?<Callback>(
    _ scannedInfo: ScannedRangesAndFlags<InputString>,
    inputString: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) where Callback: URLParserCallback {

    var scannedInfo = scannedInfo
    scannedInfo.checkInvariants(inputString, baseURL: baseURL)

    if scannedInfo.schemeKind == nil {
      guard let baseURL = baseURL, scannedInfo.componentsToCopyFromBase.contains(.scheme) else {
        preconditionFailure("We must have a scheme")
      }
      scannedInfo.schemeKind = baseURL.schemeKind
    }

    // Port.
    var port: UInt16?
    if let portRange = scannedInfo.portRange, portRange.isEmpty == false {
      guard let parsedInteger = ASCII.parseDecimalU16(from: inputString[portRange]) else {
        callback.validationError(.portOutOfRange)
        return nil
      }
      if parsedInteger != scannedInfo.schemeKind!.defaultPort {
        port = parsedInteger
      }
    }

    // Host.
    var parsedHost: ParsedHost?
    if let hostnameRange = scannedInfo.hostnameRange {
      parsedHost = ParsedHost(inputString[hostnameRange], schemeKind: scannedInfo.schemeKind!, callback: &callback)
      guard parsedHost != nil else { return nil }
    }

    self.info = scannedInfo
    self.parsedHost = parsedHost
    self.port = port
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
    writer.writeFlags(schemeKind: schemeKind, isHierarchical: info.isHierarchical)

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
            wasEncoded = inputString[username].lazy.percentEncodedGroups(as: \.userInfo).write(to: writer)
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
            wasEncoded = inputString[password].lazy.percentEncodedGroups(as: \.userInfo).write(to: writer)
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
          baseAuthority, usernameLength: $1, passwordLength: $2, hostnameLength: $3, portLength: $4
        )
      }

    } else if schemeKind == .file {
      // 'file:' URLs have an implicit authority. [URL Standard: "file host" state]
      writer.writeAuthoritySigil()
      hasAuthority = true
    }

    // 4: Path.
    switch info.pathRange {
    case .some(let path) where !info.isHierarchical:
      if writer.getHint(maySkipPercentEncoding: .path) {
        writer.writePath(firstComponentLength: 0) { writer in writer(inputString[path]) }
      } else {
        var wasEncoded = false
        writer.writePath(firstComponentLength: 0) { writer in
          wasEncoded = inputString[path].lazy.percentEncodedGroups(as: \.c0Control).write(to: writer)
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
        length: pathMetrics.requiredCapacity,
        firstComponentLength: pathMetrics.firstComponentLength
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
      writer.writePath(firstComponentLength: baseURL.storage.structure.firstPathComponentLength) { writer in
        writer(baseURL.utf8.path)
      }

    case .none where schemeKind.isSpecial:
      // Special URLs always have a path.
      writer.writePath(firstComponentLength: 1) { writer in writer(CollectionOfOne(ASCII.forwardSlash.codePoint)) }

    default:
      assert(!info.isHierarchical || hasAuthority, "Hierarchical URLs must have an authority or path")
    }

    // 5: Query.
    if let query = info.queryRange {
      if writer.getHint(maySkipPercentEncoding: .query) {
        writer.writeQueryContents { writer in writer(inputString[query]) }
      } else {
        var wasEncoded = false
        writer.writeQueryContents { (writer: (_PercentEncodedByte) -> Void) in
          if schemeKind.isSpecial {
            wasEncoded = inputString[query].lazy.percentEncodedGroups(as: \.query_special).write(to: writer)
          } else {
            wasEncoded = inputString[query].lazy.percentEncodedGroups(as: \.query_notSpecial).write(to: writer)
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
          wasEncoded = inputString[fragment].lazy.percentEncodedGroups(as: \.fragment).write(to: writer)
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
internal enum URLScanner<InputString, Callback>
where InputString: BidirectionalCollection, InputString.Element == UInt8, Callback: URLParserCallback {

  /// The result of an operation which scans a non-failable component:
  /// either to continue scanning from the given next component, or that scanning completed succesfully.
  ///
  @usableFromInline
  internal enum ScanComponentResult {
    case scan(_ component: ComponentToScan, _ startIndex: InputString.Index)
    case scanningComplete
  }

  /// The result of an operation which scans a failable component:
  /// either instructions about which component to scan next, or a signal to abort scanning.
  ///
  @usableFromInline
  internal enum ScanFailableComponentResult {
    case success(continueFrom: ScanComponentResult)
    case failed
  }

  @usableFromInline
  internal typealias SchemeKind = WebURL.SchemeKind
  @usableFromInline
  internal typealias InputSlice = InputString.SubSequence
}

@usableFromInline
internal enum ComponentToScan {
  case authority
  case pathStart
  case path
  case query
  case fragment
  // host and port only used internally within scanAuthority.
  case host
  case port
}

extension URLScanner {

  /// Scans the given URL string and returns a mapping of components that were discovered.
  ///
  /// - parameters:
  ///   - input:    The input string, as a collection of UTF8 bytes.
  ///   - baseURL:  The base URL to interpret `input` against.
  ///   - callback: An object to notify about any validation errors which are encountered.
  /// - returns:    A mapping of detected URL components, or `nil` if the string could not be parsed.
  ///
  @inlinable
  internal static func scanURLString(
    _ input: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> ScannedRangesAndFlags<InputString>? {

    var scanResults = ScannedRangesAndFlags<InputString>()

    if let (schemeEndIndex, schemeKind) = parseScheme(input), schemeEndIndex != input.endIndex {
      scanResults.schemeKind = schemeKind
      scanResults.schemeRange = Range(uncheckedBounds: (input.startIndex, schemeEndIndex))

      return scanURLWithScheme(
        input.suffix(from: input.index(after: schemeEndIndex)),
        scheme: schemeKind,
        baseURL: baseURL,
        &scanResults,
        callback: &callback
      ) ? scanResults : nil
    }

    // [URL Standard: "no scheme" state]

    guard let base = baseURL else {
      callback.validationError(.missingSchemeNonRelativeURL)
      return nil
    }
    var relative = input[...]

    if !base.isHierarchical {
      guard ASCII(flatMap: relative.popFirst()) == .numberSign else {
        callback.validationError(.missingSchemeNonRelativeURL)
        return nil
      }
      scanResults.componentsToCopyFromBase = [.scheme, .path, .query]
      scanResults.isHierarchical = false
      _ = scanFragment(relative, &scanResults, callback: &callback)
      return scanResults
    }

    if case .file = base.schemeKind {
      scanResults.componentsToCopyFromBase = [.scheme]
      return scanAllFileURLComponents(
        relative,
        baseURL: baseURL,
        &scanResults,
        callback: &callback
      ) ? scanResults : nil
    }

    return scanAllRelativeURLComponents(
      relative,
      baseScheme: base.schemeKind,
      &scanResults,
      callback: &callback
    ) ? scanResults : nil
  }

  /// Scans all components of the input string `input`, and builds up a map based on the URL's `scheme`.
  ///
  @inlinable
  internal static func scanURLWithScheme(
    _ input: InputSlice, scheme: SchemeKind, baseURL: WebURL?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    // [URL Standard: "scheme" state].
    switch scheme {
    case .file:
      if indexAfterDoubleSolidusPrefix(utf8: input) == nil {
        callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return scanAllFileURLComponents(input, baseURL: baseURL, &mapping, callback: &callback)

    case .other:
      var authority = input
      guard ASCII(flatMap: authority.popFirst()) == .forwardSlash else {
        mapping.isHierarchical = false
        return scanAllNonHierarchicalURLComponents(input, scheme: scheme, &mapping, callback: &callback)
      }
      // [URL Standard: "path or authority" state].
      guard ASCII(flatMap: authority.popFirst()) == .forwardSlash else {
        return scanAllComponents(from: .path, input, scheme: scheme, &mapping, callback: &callback)
      }
      return scanAllComponents(from: .authority, authority, scheme: scheme, &mapping, callback: &callback)

    default:
      // [URL Standard: "special relative or authority" state].
      var authority = input
      if let afterPrefix = indexAfterDoubleSolidusPrefix(utf8: input) {
        // [URL Standard: "special authority slashes" state].
        authority = authority[afterPrefix...]
      } else {
        // Since `scheme` is special, comparing the kind is sufficient.
        if scheme == baseURL?.schemeKind {
          callback.validationError(.relativeURLMissingBeginningSolidus)
          return scanAllRelativeURLComponents(input, baseScheme: scheme, &mapping, callback: &callback)
        }
        callback.validationError(.missingSolidusBeforeAuthority)
      }
      // [URL Standard: "special authority ignore slashes" state].
      authority = authority.drop { ASCII($0) == .forwardSlash || ASCII($0) == .backslash }
      return scanAllComponents(from: .authority, authority, scheme: scheme, &mapping, callback: &callback)
    }
  }
}


// --------------------------------------------
// MARK: - Non-specific URLs and components
// --------------------------------------------


extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  @inlinable
  internal static func scanAllComponents(
    from initialComponent: ComponentToScan, _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var remaining = input
    var nextLocation: ScanComponentResult = .scan(initialComponent, remaining.startIndex)

    if case .scan(.authority, _) = nextLocation {
      switch scanAuthority(remaining, scheme: scheme, &mapping, callback: &callback) {
      case .success(continueFrom: let afterAuthority):
        nextLocation = afterAuthority
      case .failed:
        return false
      }
    }
    while case .scan(let thisComponent, let thisStartIndex) = nextLocation {
      remaining = remaining[Range(uncheckedBounds: (thisStartIndex, remaining.endIndex))]
      switch thisComponent {
      case .pathStart:
        nextLocation = scanPathStart(remaining, scheme: scheme, &mapping, callback: &callback)
      case .path:
        nextLocation = scanPath(remaining, scheme: scheme, &mapping, callback: &callback)
      case .query:
        nextLocation = scanQuery(remaining, scheme: scheme, &mapping, callback: &callback)
      case .fragment:
        nextLocation = scanFragment(remaining, &mapping, callback: &callback)
      case .host, .port, .authority:
        fatalError("Component tried to return to scanning authority")
      }
    }
    return true
  }

  /// Scans the "authority" component of a URL, containing:
  ///  - Username
  ///  - Password
  ///  - Host
  ///  - Port
  ///
  /// If parsing doesn't fail, the next component is always `pathStart`.
  ///
  @inlinable
  internal static func scanAuthority(
    _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanFailableComponentResult {

    // 1. Validate the mapping.
    assert(mapping.usernameRange == nil)
    assert(mapping.passwordRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

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

    mapping.authorityRange = Range(uncheckedBounds: (authority.startIndex, authority.endIndex))

    // 3. Find the extent of the credentials, if there are any, and where the host starts.
    var hostStartIndex = authority.startIndex
    if let credentialsEndIndex = authority.lastIndex(of: ASCII.commercialAt.codePoint) {
      callback.validationError(.unexpectedCommercialAt)
      hostStartIndex = input.index(after: credentialsEndIndex)
      guard hostStartIndex < authority.endIndex else {
        callback.validationError(.unexpectedCredentialsWithoutHost)
        return .failed
      }

      let credentials = authority[..<credentialsEndIndex]
      let separatorIndex = credentials.firstIndex(of: ASCII.colon.codePoint) ?? credentials.endIndex
      mapping.usernameRange = credentials.startIndex..<separatorIndex
      if separatorIndex < credentials.endIndex {
        mapping.passwordRange = credentials.index(after: separatorIndex)..<credentials.endIndex
      }
    }

    // 4. Scan the host (and port), and propagate the continutation advice.
    let hostname = authority[hostStartIndex...]
    guard !hostname.isEmpty else {
      guard !scheme.isSpecial else {
        callback.validationError(.emptyHostSpecialScheme)
        return .failed
      }
      mapping.hostnameRange = Range(uncheckedBounds: (hostStartIndex, hostStartIndex))
      return .success(continueFrom: .scan(.pathStart, hostStartIndex))
    }

    guard case .success(let postHost) = scanHostname(hostname, scheme: scheme, &mapping, callback: &callback) else {
      return .failed
    }
    // If we need to scan a port, do it now as part of authority scanning rather than as an independent component.
    if case .scan(.port, let portStartIndex) = postHost {
      return scanPort(authority[portStartIndex...], scheme: scheme, &mapping, callback: &callback)
    }
    return .success(continueFrom: postHost)
  }

  @inlinable
  internal static func scanHostname(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanFailableComponentResult {

    // 1. Validate the mapping.
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the hostname.
    var separatorIndex: InputSlice.Index?
    do {
      var cursor = input.startIndex
      var inBracket = false
      portSearch: while cursor < input.endIndex {
        switch ASCII(input[cursor]) {
        case .leftSquareBracket?:
          inBracket = true
        case .rightSquareBracket?:
          inBracket = false
        case .colon? where !inBracket:
          separatorIndex = cursor
          break portSearch
        default:
          break
        }
        cursor = input.index(after: cursor)
      }
    }

    let hostname = input[..<(separatorIndex ?? input.endIndex)]

    // 3. Validate the structure.
    if let portStartIndex = separatorIndex, portStartIndex == input.startIndex {
      callback.validationError(.unexpectedPortWithoutHost)
      return .failed
    }

    // 4. Return the next component.
    mapping.hostnameRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    if let separatorIndex = separatorIndex {
      return .success(continueFrom: .scan(.port, input.index(after: separatorIndex)))
    } else {
      return .success(continueFrom: .scan(.pathStart, input.endIndex))
    }
  }

  @inlinable
  internal static func scanPort(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanFailableComponentResult {

    // 1. Validate the mapping.
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the port string.
    let portString = input

    // 3. Validate the port string.
    if !portString.allSatisfy({ ASCII($0)?.isDigit ?? false }), !portString.isEmpty {
      callback.validationError(.portInvalid)
      return .failed
    }

    // 4. Return the next component.
    mapping.portRange = Range(uncheckedBounds: (portString.startIndex, portString.endIndex))
    return .success(continueFrom: .scan(.pathStart, portString.endIndex))
  }

  /// Scans the URL string from the character immediately following the authority, and advises
  /// whether the remainder is a path, query or fragment.
  ///
  @inlinable
  internal static func scanPathStart(
    _ input: InputSlice, scheme: SchemeKind, _ mapping: inout ScannedRangesAndFlags<InputString>,
    callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Return the component to parse based on input.
    guard input.startIndex < input.endIndex else {
      // Shortcut the 'path' state. This would otherwise ensure that special URLs have a non-nil pathRange,
      // but `ParsedURLString.write` already knows to give special URLs an implicit path.
      return .scanningComplete
    }

    switch ASCII(input[input.startIndex]) {
    case .questionMark?:
      return .scan(.query, input.index(after: input.startIndex))
    case .numberSign?:
      return .scan(.fragment, input.index(after: input.startIndex))
    default:
      return .scan(.path, input.startIndex)
    }
  }

  /// Scans a URL path string from the given input, and advises whether there are any components following it.
  ///
  @inlinable
  internal static func scanPath(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the path.
    let startOfNextComponent = input.firstIndex { ASCII($0) == .questionMark || ASCII($0) == .numberSign }
    let path = input[..<(startOfNextComponent ?? input.endIndex)]

    // 3. Validate the path's contents.
    PathStringValidator.validate(
      pathString: path, schemeKind: scheme,
      hasAuthority: mapping.authorityRange != nil || mapping.componentsToCopyFromBase.contains(.authority),
      callback: &callback
    )

    // 4. Return the next component.
    if !(path.startIndex < path.endIndex), !scheme.isSpecial {
      mapping.pathRange = nil
    } else {
      mapping.pathRange = Range(uncheckedBounds: (path.startIndex, path.endIndex))
    }
    if let nextStart = startOfNextComponent {
      return .scan(ASCII(input[nextStart]) == .questionMark ? .query : .fragment, input.index(after: nextStart))
    } else {
      return .scanningComplete
    }
  }

  /// Scans a URL query string from the given input, and advises whether there are any components following it.
  ///
  @inlinable
  internal static func scanQuery(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the query
    let startOfFrg = input.firstIndex(of: ASCII.numberSign.codePoint)

    // 3. Validate the query-string.
    validateURLCodePointsAndPercentEncoding(utf8: input.prefix(upTo: startOfFrg ?? input.endIndex), callback: &callback)

    // 3. Return the next component.
    mapping.queryRange = Range(uncheckedBounds: (input.startIndex, startOfFrg ?? input.endIndex))
    if let nextStart = startOfFrg {
      return .scan(.fragment, input.index(after: nextStart))
    } else {
      return .scanningComplete
    }
  }

  /// Scans a URL fragment string from the given input. There are never any components following it.
  ///
  @inlinable
  internal static func scanFragment(
    _ input: InputSlice,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.fragmentRange == nil)

    // 2. Validate the fragment string.
    validateURLCodePointsAndPercentEncoding(utf8: input, callback: &callback)

    mapping.fragmentRange = Range(uncheckedBounds: (input.startIndex, input.endIndex))
    return .scanningComplete
  }
}


// --------------------------------------------
// MARK: - File URLs
// --------------------------------------------


extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  @inlinable
  internal static func scanAllFileURLComponents(
    _ input: InputSlice, baseURL: WebURL?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var nextLocation = parseFileURLStart(input, baseURL: baseURL, &mapping, callback: &callback)
    guard case .scan(_, let firstComponentStartIndex) = nextLocation else {
      return true
    }
    var remaining = input.suffix(from: firstComponentStartIndex)

    while case .scan(let thisComponent, let thisStartIndex) = nextLocation {
      remaining = remaining[Range(uncheckedBounds: (thisStartIndex, remaining.endIndex))]
      switch thisComponent {
      case .pathStart:
        nextLocation = scanPathStart(remaining, scheme: .file, &mapping, callback: &callback)
      case .path:
        nextLocation = scanPath(remaining, scheme: .file, &mapping, callback: &callback)
      case .query:
        nextLocation = scanQuery(remaining, scheme: .file, &mapping, callback: &callback)
      case .fragment:
        nextLocation = scanFragment(remaining, &mapping, callback: &callback)
      case .host, .port, .authority:
        fatalError("Component tried to return to scanning authority")
      }
    }
    return true
  }

  @inlinable
  internal static func parseFileURLStart(
    _ input: InputSlice, baseURL: WebURL?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // Note that file URLs may also be relative URLs. It all depends on what comes after "file:".
    // - 0 slashes:  copy base host, parse as path relative to base path.
    // - 1 slash:    copy base host, parse as absolute path.
    // - 2 slashes:  parse own host, parse absolute path.
    // - 3 slahses:  empty host, parse as absolute path.
    // - 4+ slashes: invalid.

    let baseScheme = baseURL?.schemeKind

    var cursor = input.startIndex
    guard cursor < input.endIndex, let c0 = ASCII(input[cursor]), c0 == .forwardSlash || c0 == .backslash else {
      // [URL Standard: "file" state].
      // No slashes. May be a relative path ("file:usr/lib/Swift") or no path ("file:?someQuery").
      guard baseScheme == .file else {
        return .scan(.path, cursor)
      }
      assert(mapping.componentsToCopyFromBase.isEmpty || mapping.componentsToCopyFromBase == [.scheme])
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])

      guard cursor < input.endIndex else {
        return .scanningComplete
      }
      switch ASCII(input[cursor]) {
      case .questionMark?:
        mapping.componentsToCopyFromBase.remove(.query)
        return .scan(.query, input.index(after: cursor))
      case .numberSign?:
        return .scan(.fragment, input.index(after: cursor))
      default:
        mapping.componentsToCopyFromBase.remove(.query)
        // Relative paths which begin with a Windows drive letter are not actually relative to baseURL.
        // This doesn't depend on the surrounding URL structure, so the path parser handles it
        // without needing special instruction/flags.
        if PathComponentParser.hasWindowsDriveLetterPrefix(input[cursor...]) {
          callback.validationError(.unexpectedWindowsDriveLetter)
        }
        return .scan(.path, cursor)
      }
    }
    cursor = input.index(after: cursor)
    if c0 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }

    guard cursor < input.endIndex, let c1 = ASCII(input[cursor]), c1 == .forwardSlash || c1 == .backslash else {
      // [URL Standard: "file slash" state].
      // 1 slash. Absolute path ("file:/usr/lib/Swift").
      guard baseScheme == .file else {
        return .scan(.path, input.startIndex)
      }
      mapping.componentsToCopyFromBase.formUnion([.authority])

      // Absolute paths in path-only URLs are still relative to the base URL's Windows drive letter (if it has one).
      // This only occurs if the string goes through the "file slash" state - not if it contains a hostname
      // and goes through the "file host" state. The path parser requires a flag to opt-in to that behaviour.
      mapping.absolutePathsCopyWindowsDriveFromBase = true
      mapping.componentsToCopyFromBase.formUnion([.path])

      return .scan(.path, input.startIndex)
    }
    let pathStartIfDriveLetter = cursor
    cursor = input.index(after: cursor)
    if c1 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }

    // [URL Standard: "file host" state].
    // 2+ slashes. e.g. "file://localhost/usr/lib/Swift" or "file:///usr/lib/Swift".
    return scanFileHost(input[cursor...], pathStartIfDriveLetter: pathStartIfDriveLetter, &mapping, callback: &callback)
  }

  /// Scans a hostname for a file URL from `input` and advises on how to proceed with scanning.
  ///
  /// Note that, unlike the nonspecific "host" parser, this never fails - even if there is a port and the hostname is empty.
  /// In that case, the scanned hostname will contain the port and ultimately get rejected for containing a forbidden host code-point.
  ///
  /// If `pathStartIfDriveLetter` is given and the hostname is a Windows drive letter, scanning will be advised to scan a path from that position.
  /// This position is typically just before `input.startIndex`, which is unusual for scanning methods as they don't typically advise to go backwards.
  ///
  @inlinable
  internal static func scanFileHost(
    _ input: InputSlice, pathStartIfDriveLetter: InputString.Index?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.authorityRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the hostname.
    //    The hostname is not validated after this, as it will be checked by the host parser.
    let startOfNextComponent =
      input.firstIndex { byte in
        switch ASCII(byte) {
        case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
        default: return false
        }
      } ?? input.endIndex

    let hostname = input[..<startOfNextComponent]

    // 3. Return the next component.
    if let pathStartIfDriveLetter = pathStartIfDriveLetter, PathComponentParser.isWindowsDriveLetter(hostname) {
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return .scan(.path, pathStartIfDriveLetter)
    }
    mapping.authorityRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    mapping.hostnameRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    return .scan(.pathStart, startOfNextComponent)
  }
}


// --------------------------------------------
// MARK: - Non-Hierarchical URLs
// --------------------------------------------


extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  @inlinable
  internal static func scanAllNonHierarchicalURLComponents(
    _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var nextLocation = scanNonHierarchicalPath(input, &mapping, callback: &callback)
    guard case .scan(_, let firstComponentStartIndex) = nextLocation else {
      return true
    }
    var remaining = input.suffix(from: firstComponentStartIndex)

    while case .scan(let thisComponent, let thisStartIndex) = nextLocation {
      remaining = remaining[Range(uncheckedBounds: (thisStartIndex, remaining.endIndex))]
      switch thisComponent {
      case .query:
        nextLocation = scanQuery(remaining, scheme: scheme, &mapping, callback: &callback)
      case .fragment:
        nextLocation = scanFragment(remaining, &mapping, callback: &callback)
      case .pathStart, .path, .host, .port, .authority:
        fatalError("Tried to scan invalid component for non-hierarchical URL")
      }
    }
    return true
  }

  @inlinable
  internal static func scanNonHierarchicalPath(
    _ input: InputSlice,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.authorityRange == nil)
    assert(mapping.hostnameRange == nil)
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the path.
    let startOfNextComponent = input.firstIndex { byte in
      switch ASCII(byte) {
      case .questionMark?, .numberSign?: return true
      default: return false
      }
    }

    let path = input[..<(startOfNextComponent ?? input.endIndex)]

    // 3. Validate the path.
    validateURLCodePointsAndPercentEncoding(utf8: path, callback: &callback)

    // 4. Return the next component.
    if let nextStart = startOfNextComponent {
      mapping.pathRange = Range(uncheckedBounds: (path.startIndex, nextStart))
      return .scan(ASCII(input[nextStart]) == .questionMark ? .query : .fragment, input.index(after: nextStart))
    } else {
      mapping.pathRange = path.isEmpty ? nil : Range(uncheckedBounds: (input.startIndex, input.endIndex))
      return .scanningComplete
    }
  }
}


// --------------------------------------------
// MARK: - Relative URLs
// --------------------------------------------


extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  @inlinable
  internal static func scanAllRelativeURLComponents(
    _ input: InputSlice, baseScheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var nextLocation = parseRelativeURLStart(input, baseScheme: baseScheme, &mapping, callback: &callback)
    guard case .scan(_, let firstComponentStartIndex) = nextLocation else {
      return true
    }
    var remaining = input.suffix(from: firstComponentStartIndex)

    if case .scan(.authority, _) = nextLocation {
      switch scanAuthority(remaining, scheme: baseScheme, &mapping, callback: &callback) {
      case .success(continueFrom: let afterAuthority):
        nextLocation = afterAuthority
      case .failed:
        return false
      }
    }
    while case .scan(let thisComponent, let thisStartIndex) = nextLocation {
      remaining = remaining[Range(uncheckedBounds: (thisStartIndex, remaining.endIndex))]
      switch thisComponent {
      case .path:
        nextLocation = scanPath(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .pathStart:
        nextLocation = scanPathStart(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .query:
        nextLocation = scanQuery(remaining, scheme: baseScheme, &mapping, callback: &callback)
      case .fragment:
        nextLocation = scanFragment(remaining, &mapping, callback: &callback)
      case .host, .port, .authority:
        fatalError("Component tried to return to scanning authority")
      }
    }
    return true
  }

  @inlinable
  internal static func parseRelativeURLStart(
    _ input: InputSlice, baseScheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    mapping.componentsToCopyFromBase = [.scheme]

    // [URL Standard: "relative" state].
    guard input.startIndex < input.endIndex else {
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return .scanningComplete
    }

    switch ASCII(input[input.startIndex]) {
    // [URL Standard: "relative slash" state].
    case .backslash? where baseScheme.isSpecial:
      callback.validationError(.unexpectedReverseSolidus)
      fallthrough
    case .forwardSlash?:
      var cursor = input.index(after: input.startIndex)
      guard cursor < input.endIndex else {
        mapping.componentsToCopyFromBase.formUnion([.authority])
        return .scan(.path, input.startIndex)
      }
      switch ASCII(input[cursor]) {
      case .backslash? where baseScheme.isSpecial:
        callback.validationError(.unexpectedReverseSolidus)
        fallthrough
      case .forwardSlash?:
        cursor = input.index(after: cursor)
        if baseScheme.isSpecial {
          // [URL Standard: "special authority ignore slashes" state].
          cursor =
            input[cursor...].firstIndex {
              ASCII($0) != .forwardSlash && ASCII($0) != .backslash
            } ?? input.endIndex
        }
        return .scan(.authority, cursor)
      default:
        mapping.componentsToCopyFromBase.formUnion([.authority])
        return .scan(.path, input.startIndex)
      }

    // Back to [URL Standard: "relative" state].
    case .questionMark?:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      return .scan(.query, input.index(after: input.startIndex))
    case .numberSign?:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return .scan(.fragment, input.index(after: input.startIndex))
    default:
      // Since we have a non-empty input string which doesn't begin with a query/fragment sigil ("?"/"#"),
      // `scanPath` will always set a non-nil pathRange.
      // `ParsedURLString.write` knows that if it sees a non-nil pathRange, *and* we ask the base's path,
      // that it should provide both to the path parser, which will combine them.
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      return .scan(.path, input.startIndex)
    }
  }
}


// --------------------------------------------
// MARK: - Post-scan validation
// --------------------------------------------


extension ScannedRangesAndFlags where InputString: BidirectionalCollection, InputString.Element == UInt8 {

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
        assert(isHierarchical, "A URL with an authority is hierarchical")
        if passwordRange != nil {
          assert(usernameRange != nil, "Can't have a password without a username (even if empty)")
        }
        if portRange != nil {
          assert(hostnameRange != nil, "Can't have a port without a hostname")
        }
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

  let terminatorIdx = input.firstIndex { $0 == ASCII.colon.codePoint } ?? input.endIndex
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
  let hostname = input.prefix {
    switch ASCII($0) {
    case ASCII.forwardSlash?, ASCII.questionMark?, ASCII.numberSign?:
      return false
    case ASCII.backslash? where scheme.isSpecial:
      return false
    default:
      return true
    }
  }
  if scheme == .file {
    // [URL Standard: "file host" state].
    // Hostnames which are Windows drive letters are not interpreted as paths in setter mode, so pSIDL = nil.
    _ = URLScanner.scanFileHost(hostname, pathStartIfDriveLetter: nil, &mapping, callback: &cb)
  } else {
    guard case .success(_) = URLScanner.scanHostname(hostname, scheme: scheme, &mapping, callback: &cb) else {
      // Only fails if there is a port and the hostname is empty.
      assert(hostname.first == ASCII.colon.codePoint)
      return nil
    }
  }
  return mapping.hostnameRange?.upperBound ?? hostname.endIndex
}
