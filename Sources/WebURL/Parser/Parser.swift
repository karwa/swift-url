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
    _urlFromBytes_impl($0, baseURL: baseURL, callback: &callback)
  } ?? _urlFromBytes_impl(inputString, baseURL: baseURL, callback: &callback)
}

@usableFromInline
@_specialize(kind:partial,where Callback == IgnoreValidationErrors)
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
  return ASCII.NewlineAndTabFiltered.filterIfNeeded(trimmedInput).map(
    left: { filtered in
      ParsedURLString(parsing: filtered, baseURL: baseURL, callback: &callback)?.constructURLObject()
    },
    right: { trimmed in
      ParsedURLString(parsing: trimmed, baseURL: baseURL, callback: &callback)?.constructURLObject()
    }
  ).get()
}


// MARK: - ParsedURLString


/// A collection of UTF8 bytes which have been successfully parsed as a URL string.
///
/// `ParsedURLString` holds the input string and base URL, together with information from the parser which describes where each component can
/// be found (either within the input string, or copied from the base URL). The `ParsedURLString` can write the contents to any `URLWriter`, which
/// it does in a normalized format which includes any transformations needed by specific components (e.g. lowercasing, percent-encoding/decoding).
///
struct ParsedURLString<InputString> where InputString: BidirectionalCollection, InputString.Element == UInt8 {
  let inputString: InputString
  let baseURL: WebURL?
  let mapping: ProcessedMapping

  /// Parses the given collection of UTF8 bytes as a URL string, relative to the given base URL.
  ///
  /// - parameters:
  ///   - inputString:  The input string, as a collection of UTF8 bytes.
  ///   - baseURL:      The base URL against which `inputString` should be interpreted.
  ///   - callback:     A callback to receive validation errors. If these are unimportant, pass an instance of `IngoreValidationErrors`.
  ///
  init?<Callback: URLParserCallback>(parsing inputString: InputString, baseURL: WebURL?, callback: inout Callback) {
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
  /// - Note: Providing a `URLMetrics` object for this `ParsedURLString` can significantly speed the process.
  ///         Obtain metrics by writing the string to a `StructureAndMetricsCollector`.
  ///
  func write<WriterType: URLWriter>(to writer: inout WriterType, metrics: URLMetrics? = nil) {
    mapping.write(inputString: inputString, baseURL: baseURL, to: &writer, metrics: metrics)
  }

  /// Writes the URL to new `URLStorage`, appropriate for its size and structure, and returns it as a `WebURL` object.
  ///
  func constructURLObject() -> WebURL {
    let (count, structure, metrics) = StructureAndMetricsCollector.collect { collector in write(to: &collector) }
    let newStorage = AnyURLStorage(optimalStorageForCapacity: count, structure: structure) { codeUnits in
      var writer = UnsafePresizedBufferWriter(buffer: codeUnits)
      write(to: &writer, metrics: metrics)
      return writer.bytesWritten
    }
    return WebURL(storage: newStorage)
  }
}

extension ParsedURLString {

  /// The validated URL information contained within a string.
  ///
  struct ProcessedMapping {
    let info: ScannedRangesAndFlags<InputString>
    let parsedHost: ParsedHost?
    let port: UInt16?
  }
}

/// The positions of URL components found within a string, and the flags to interpret them.
///
/// After coming from the scanner, certain components require additional _content validation_, which can be performed by constructing a `ProcessedMapping`.
///
struct ScannedRangesAndFlags<InputString> where InputString: Collection {

  /// The position of the scheme's content, if present, without trailing separators.
  var schemeRange: Range<InputString.Index>?

  /// The position of the authority section, if present, without leading or trailing separators.
  var authorityRange: Range<InputString.Index>?

  /// The position of the username content, if present, without leading or trailing separators.
  var usernameRange: Range<InputString.Index>?

  /// The position of the password content, if present, without leading or trailing separators.
  var passwordRange: Range<InputString.Index>?

  /// The position of the hostname content, if present, without leading or trailing separators.
  var hostnameRange: Range<InputString.Index>?

  /// The position of the port content, if present, without leading or trailing separators.
  var portRange: Range<InputString.Index>?

  /// The position of the path content, if present, without leading or trailing separators.
  /// Note that the path's initial "/", if present, is not considered a separator.
  var pathRange: Range<InputString.Index>?

  /// The position of the query content, if present, without leading or trailing separators.
  var queryRange: Range<InputString.Index>?

  /// The position of the fragment content, if present, without leading or trailing separators.
  var fragmentRange: Range<InputString.Index>?

  // Flags.

  /// The kind of scheme contained in `schemeRange`, if it is not `nil`.
  var schemeKind: WebURL.SchemeKind? = nil

  /// Whether this URL 'cannot be a base'.
  var cannotBeABaseURL = false

  /// A flag for a quirk in the standard, which means that absolute paths in particular URL strings should copy the Windows drive from their base URL.
  var absolutePathsCopyWindowsDriveFromBase = false

  /// The components to copy from the base URL. If non-empty, there must be a base URL.
  /// Only the scheme and path may overlap with components detected in the input string - for the former, it is a meaningless quirk of the control flow,
  /// and the two schemes must be equal; for the latter, it means the two paths should be merged (i.e. that the input string's path is relative to the base URL's path).
  fileprivate var componentsToCopyFromBase: CopyableURLComponentSet = []
}

//swift-format-ignore
/// A set of components to be copied from a URL.
///
/// - seealso: `ScannedRangesAndFlags.componentsToCopyFromBase`
///
private struct CopyableURLComponentSet: OptionSet {
  var rawValue: UInt8
  init(rawValue: UInt8) {
    self.rawValue = rawValue
  }
  static var scheme: Self    { Self(rawValue: 1 << 0) }
  static var authority: Self { Self(rawValue: 1 << 1) }
  static var path: Self      { Self(rawValue: 1 << 2) }
  static var query: Self     { Self(rawValue: 1 << 3) }
  static var fragment: Self  { Self(rawValue: 1 << 4) }
}

extension ParsedURLString.ProcessedMapping {

  /// Parses failable components discovered by the scanner.
  /// This is the last stage at which parsing may fail, and successful construction of this mapping signifies that the input string can definitely be written as a URL.
  ///
  init?<Callback>(
    _ scannedInfo: ScannedRangesAndFlags<InputString>,
    inputString: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) where Callback: URLParserCallback {

    var scannedInfo = scannedInfo
    assert(scannedInfo.checkInvariants(inputString, baseURL: baseURL))

    if scannedInfo.schemeKind == nil {
      guard let baseURL = baseURL, scannedInfo.componentsToCopyFromBase.contains(.scheme) else {
        preconditionFailure("We must have a scheme")
      }
      scannedInfo.schemeKind = baseURL._schemeKind
    }

    // Parse port string.
    var port: UInt16?
    if let portRange = scannedInfo.portRange, portRange.isEmpty == false {
      guard let parsedInteger = UInt16(String(decoding: inputString[portRange], as: UTF8.self)) else {
        callback.validationError(.portOutOfRange)
        return nil
      }
      port = parsedInteger
    }
    // Process hostname.
    var parsedHost: ParsedHost?
    if let hostname = scannedInfo.hostnameRange.map({ inputString[$0] }) {
      parsedHost = ParsedHost(hostname, schemeKind: scannedInfo.schemeKind!, callback: &callback)
      guard parsedHost != nil else { return nil }
    }
    // Adjust path for Windows drive letters in authority position.
    // FIXME: It would be better if URLScanner handled this. This is too fragile.
    if scannedInfo.schemeKind == .file {
      // If the scanned path is "//C:/..." and we didn't find a host (even an empty one), it means
      // the 'file host' parser bailed but couldn't drop its extra slash. Drop the double slash now.
      if var pathContents = scannedInfo.pathRange.map({ inputString[$0] }), scannedInfo.hostnameRange == nil {
        let isPathSeparator: (UInt8?) -> Bool = {
          $0 == ASCII.forwardSlash.codePoint || $0 == ASCII.backslash.codePoint
        }
        if isPathSeparator(pathContents.popFirst()),
          isPathSeparator(pathContents.first),
          PathComponentParser.hasWindowsDriveLetterPrefix(pathContents.dropFirst())
        {
          scannedInfo.pathRange = pathContents.startIndex..<pathContents.endIndex
        }
      }
    }

    self.info = scannedInfo
    self.parsedHost = parsedHost
    self.port = port
  }

  func write<WriterType: URLWriter>(
    inputString: InputString,
    baseURL: WebURL?,
    to writer: inout WriterType,
    metrics: URLMetrics? = nil
  ) {

    let schemeKind = info.schemeKind!

    // 1: Write flags
    writer.writeFlags(schemeKind: schemeKind, cannotBeABaseURL: info.cannotBeABaseURL)

    // 2: Write scheme.
    if let inputScheme = info.schemeRange {
      // Scheme must be lowercased.
      writer.writeSchemeContents(ASCII.Lowercased(inputString[inputScheme]))
    } else {
      guard let baseURL = baseURL, info.componentsToCopyFromBase.contains(.scheme) else {
        preconditionFailure("Cannot construct a URL without a scheme")
      }
      assert(schemeKind == baseURL._schemeKind)
      baseURL.storage.withComponentBytes(.scheme) {
        let bytes = $0!.dropLast()  // drop terminator.
        writer.writeSchemeContents(bytes)
      }
    }

    // 3: Write authority.
    var hasAuthority = false
    if let hostname = info.hostnameRange {
      writer.writeAuthoritySigil()
      hasAuthority = true

      var hasCredentials = false
      if let username = info.usernameRange, username.isEmpty == false {
        var didEscape = false
        if metrics?.componentsWhichMaySkipEscaping.contains(.username) == true {
          writer.writeUsernameContents { writePiece in
            writePiece(inputString[username])
          }
        } else {
          writer.writeUsernameContents { writer in
            didEscape = inputString[username].lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).write(to: writer)
          }
        }
        writer.writeHint(.username, needsEscaping: didEscape)
        hasCredentials = true
      }
      if let password = info.passwordRange, password.isEmpty == false {
        var didEscape = false
        if metrics?.componentsWhichMaySkipEscaping.contains(.password) == true {
          writer.writePasswordContents { writePiece in
            writePiece(inputString[password])
          }
        } else {
          writer.writePasswordContents { writer in
            didEscape = inputString[password].lazy.percentEncoded(using: URLEncodeSet.UserInfo.self).write(to: writer)
          }
        }
        writer.writeHint(.password, needsEscaping: didEscape)
        hasCredentials = true
      }
      if hasCredentials {
        writer.writeCredentialsTerminator()
      }

      writer.withHostnameWriter { hostWriter in
        parsedHost!.write(bytes: inputString[hostname], using: &hostWriter)
      }

      if let port = port, port != schemeKind.defaultPort {
        writer.writePort(port)
      }

    } else if info.componentsToCopyFromBase.contains(.authority) {
      guard let baseURL = baseURL else {
        preconditionFailure("A baseURL is required")
      }
      baseURL.storage.withAllAuthorityComponentBytes {
        if let baseAuth = $0 {
          writer.writeAuthoritySigil()
          writer.writeKnownAuthorityString(
            baseAuth,
            usernameLength: $1,
            passwordLength: $2,
            hostnameLength: $3,
            portLength: $4
          )
          hasAuthority = true
        }
      }
    } else if schemeKind == .file {
      // 'file:' URLs get an implicit authority.
      writer.writeAuthoritySigil()
      hasAuthority = true
    }

    // 4: Write path.
    switch info.pathRange {
    case .some(let path) where info.cannotBeABaseURL:
      var didEscape = false
      if metrics?.componentsWhichMaySkipEscaping.contains(.path) == true {
        writer.writePath(firstComponentLength: 0) { $0(inputString[path]) }
      } else {
        writer.writePath(firstComponentLength: 0) { writer in
          didEscape = inputString[path].lazy.percentEncoded(using: URLEncodeSet.C0.self).write(to: writer)
        }
      }
      writer.writeHint(.path, needsEscaping: didEscape)

    case .some(let path):
      let pathMetrics =
        metrics?.pathMetrics
        ?? PathMetrics(
          parsing: inputString[path],
          schemeKind: schemeKind,
          baseURL: info.componentsToCopyFromBase.contains(.path) ? baseURL! : nil,
          absolutePathsCopyWindowsDriveFromBase: info.absolutePathsCopyWindowsDriveFromBase
        )
      assert(pathMetrics.requiredCapacity > 0)
      writer.writePathMetricsHint(pathMetrics)
      writer.writeHint(.path, needsEscaping: pathMetrics.needsEscaping)

      if pathMetrics.requiresSigil && (hasAuthority == false) {
        writer.writePathSigil()
      }
      writer.writeUnsafePath(
        length: pathMetrics.requiredCapacity,
        firstComponentLength: pathMetrics.firstComponentLength
      ) { buffer in
        return buffer.writeNormalizedPath(
          parsing: inputString[path],
          schemeKind: schemeKind,
          baseURL: info.componentsToCopyFromBase.contains(.path) ? baseURL! : nil,
          absolutePathsCopyWindowsDriveFromBase: info.absolutePathsCopyWindowsDriveFromBase,
          needsEscaping: pathMetrics.needsEscaping
        )
      }

    case .none where info.componentsToCopyFromBase.contains(.path):
      guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
      baseURL.storage.withComponentBytes(.path) {
        if let basePath = $0 {
          precondition(
            (hasAuthority == false) || info.componentsToCopyFromBase.contains(.authority),
            "An input string which copies the base URL's path must either have its own authority"
              + "(thus does not need a path sigil) or match the authority/path sigil from the base URL")
          if case .path = baseURL.storage.structure.sigil, hasAuthority == false {
            writer.writePathSigil()
          }
          writer.writePath(firstComponentLength: baseURL.storage.structure.firstPathComponentLength) { writePiece in
            writePiece(basePath)
          }
        }
      }

    case .none where schemeKind.isSpecial:
      // Special URLs always have a path.
      writer.writePath(firstComponentLength: 1) { writePiece in
        writePiece(CollectionOfOne(ASCII.forwardSlash.codePoint))
      }

    default:
      break
    }

    // 5: Write query.
    if let query = info.queryRange {
      var didEscape = false
      if metrics?.componentsWhichMaySkipEscaping.contains(.query) == true {
        writer.writeQueryContents { writerPiece in
          writerPiece(inputString[query])
        }
      } else {
        writer.writeQueryContents { (writer: (PercentEncodedByte) -> Void) in
          if schemeKind.isSpecial {
            didEscape = inputString[query].lazy.percentEncoded(using: URLEncodeSet.Query_Special.self)
              .write(to: writer)
          } else {
            didEscape = inputString[query].lazy.percentEncoded(using: URLEncodeSet.Query_NotSpecial.self)
              .write(to: writer)
          }
        }
      }
      writer.writeHint(.query, needsEscaping: didEscape)
    } else if info.componentsToCopyFromBase.contains(.query) {
      guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
      baseURL.storage.withComponentBytes(.query) {
        if let baseQuery = $0?.dropFirst() {  // '?' separator.
          writer.writeQueryContents { writePiece in writePiece(baseQuery) }
        }
      }
    }

    // 6: Write fragment.
    if let fragment = info.fragmentRange {
      var didEscape = false
      if metrics?.componentsWhichMaySkipEscaping.contains(.fragment) == true {
        writer.writeFragmentContents { writePiece in
          writePiece(inputString[fragment])
        }
      } else {
        writer.writeFragmentContents { writer in
          didEscape = inputString[fragment].lazy.percentEncoded(using: URLEncodeSet.Fragment.self).write(to: writer)
        }
      }
      writer.writeHint(.fragment, needsEscaping: didEscape)
    } else if info.componentsToCopyFromBase.contains(.fragment) {
      guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
      baseURL.storage.withComponentBytes(.fragment) {
        if let baseFragment = $0?.dropFirst() {  // '#' separator.
          writer.writeFragmentContents { writePiece in writePiece(baseFragment) }
        }
      }
    }

    // 7: Finalize.
    writer.finalize()

    return  // End of writing.
  }
}


// MARK: - URL Scanner.


/// A namespace for URL scanning methods.
///
private enum URLScanner<InputString, Callback>
where InputString: BidirectionalCollection, InputString.Element == UInt8, Callback: URLParserCallback {

  /// The result of an operation which scans a non-failable component:
  /// either to continue scanning from the given next component, or that scanning completed succesfully.
  ///
  enum ScanComponentResult {
    case scan(_ component: ComponentToScan, _ startIndex: InputString.Index)
    case scanningComplete
  }

  /// The result of an operation which scans a failable component:
  /// either instructions about which component to scan next, or a signal to abort scanning.
  ///
  enum ScanFailableComponentResult {
    case success(continueFrom: ScanComponentResult)
    case failed
  }

  typealias SchemeKind = WebURL.SchemeKind
  typealias InputSlice = InputString.SubSequence
}

private enum ComponentToScan {
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

    // state: "no scheme"

    guard let base = baseURL else {
      callback.validationError(.missingSchemeNonRelativeURL)
      return nil
    }

    if base._cannotBeABaseURL {
      guard ASCII(flatMap: input.first) == .numberSign else {
        callback.validationError(.missingSchemeNonRelativeURL)
        return nil
      }
      scanResults.componentsToCopyFromBase = [.scheme, .path, .query]
      scanResults.cannotBeABaseURL = true
      _ = scanFragment(input.dropFirst(), &scanResults, callback: &callback)
      return scanResults
    }

    if case .file = base._schemeKind {
      scanResults.componentsToCopyFromBase = [.scheme]
      return scanAllFileURLComponents(
        input[...],
        baseURL: baseURL,
        &scanResults,
        callback: &callback
      ) ? scanResults : nil
    }

    return scanAllRelativeURLComponents(
      input[...],
      baseScheme: base._schemeKind,
      &scanResults,
      callback: &callback
    ) ? scanResults : nil
  }

  /// Scans all components of the input string `input`, and builds up a map based on the URL's `scheme`.
  ///
  internal static func scanURLWithScheme(
    _ input: InputSlice, scheme: SchemeKind, baseURL: WebURL?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    // state: "scheme", after a valid scheme has been parsed.
    switch scheme {
    case .file:
      if !hasDoubleSolidusPrefix(input) {
        callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return scanAllFileURLComponents(input, baseURL: baseURL, &mapping, callback: &callback)

    case .other:
      var authority = input
      guard ASCII(flatMap: authority.popFirst()) == .forwardSlash else {
        mapping.cannotBeABaseURL = true
        return scanAllCannotBeABaseURLComponents(input, scheme: scheme, &mapping, callback: &callback)
      }
      // state: "path or authority"
      guard ASCII(flatMap: authority.popFirst()) == .forwardSlash else {
        return scanAllComponents(from: .path, input, scheme: scheme, &mapping, callback: &callback)
      }
      return scanAllComponents(from: .authority, authority, scheme: scheme, &mapping, callback: &callback)

    default:
      // state: "special relative or authority"
      var authority = input
      if hasDoubleSolidusPrefix(input) {
        // state: "special authority slashes"
        authority = authority.dropFirst(2)
      } else {
        // Since `scheme` is special, comparing the kind is sufficient.
        if scheme == baseURL?._schemeKind {
          callback.validationError(.relativeURLMissingBeginningSolidus)
          return scanAllRelativeURLComponents(input, baseScheme: scheme, &mapping, callback: &callback)
        }
        callback.validationError(.missingSolidusBeforeAuthority)
      }
      // state: "special authority ignore slashes"
      authority = authority.drop { ASCII($0) == .forwardSlash || ASCII($0) == .backslash }
      return scanAllComponents(from: .authority, authority, scheme: scheme, &mapping, callback: &callback)
    }
  }
}

// MARK: - Generic URLs and components.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllComponents(
    from initialComponent: ComponentToScan, _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var remaining = input[...]
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
      remaining = remaining[thisStartIndex...]
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
  static func scanAuthority(
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
      mapping.usernameRange = Range(uncheckedBounds: (username.startIndex, username.endIndex))
      if username.endIndex != credentials.endIndex {
        mapping.passwordRange = Range(
          uncheckedBounds: (credentials.index(after: username.endIndex), credentials.endIndex)
        )
      }
    }

    // 3. Scan the host/port and propagate the continutation advice.
    let hostname = authority[hostStartIndex...]
    guard hostname.isEmpty == false else {
      if scheme.isSpecial {
        callback.validationError(.emptyHostSpecialScheme)
        return .failed
      }
      mapping.hostnameRange = Range(uncheckedBounds: (hostStartIndex, hostStartIndex))
      return .success(continueFrom: .scan(.pathStart, hostStartIndex))
    }

    guard case .success(let postHost) = scanHostname(hostname, scheme: scheme, &mapping, callback: &callback) else {
      return .failed
    }
    // Scan the port, if the host requested it.
    guard case .scan(.port, let portStartIndex) = postHost else {
      return .success(continueFrom: postHost)
    }
    return scanPort(authority[portStartIndex...], scheme: scheme, &mapping, callback: &callback)
  }

  static func scanHostname(
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
    var hostnameEndIndex: InputSlice.Index?
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
    mapping.hostnameRange = Range(uncheckedBounds: (hostname.startIndex, hostname.endIndex))
    if let hostnameEnd = hostnameEndIndex {
      return .success(continueFrom: .scan(.port, input.index(after: hostnameEnd)))
    } else {
      return .success(continueFrom: .scan(.pathStart, input.endIndex))
    }
  }

  static func scanPort(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanFailableComponentResult {

    // 1. Validate the mapping.
    assert(mapping.portRange == nil)
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

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
    mapping.portRange = Range(uncheckedBounds: (portString.startIndex, portString.endIndex))
    return .success(continueFrom: .scan(.pathStart, portString.endIndex))
  }

  /// Scans the URL string from the character immediately following the authority, and advises
  /// whether the remainder is a path, query or fragment.
  ///
  static func scanPathStart(
    _ input: InputSlice, scheme: SchemeKind, _ mapping: inout ScannedRangesAndFlags<InputString>,
    callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Return the component to parse based on input.
    guard input.isEmpty == false else {
      return .scan(.path, input.startIndex)
    }

    let c: ASCII? = ASCII(input[input.startIndex])
    switch c {
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
  static func scanPath(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the path.
    let nextComponentStartIndex = input.firstIndex { ASCII($0) == .questionMark || ASCII($0) == .numberSign }
    let path = input[..<(nextComponentStartIndex ?? input.endIndex)]

    // 3. Validate the path's contents.
    PathStringValidator.validate(pathString: path, schemeKind: scheme, callback: &callback)

    // 4. Return the next component.
    if path.isEmpty && scheme.isSpecial == false {
      mapping.pathRange = nil
    } else {
      mapping.pathRange = Range(uncheckedBounds: (path.startIndex, path.endIndex))
    }
    if let pathEnd = nextComponentStartIndex {
      return .scan(ASCII(input[pathEnd]) == .questionMark ? .query : .fragment, input.index(after: pathEnd))
    } else {
      return .scanningComplete
    }
  }

  /// Scans a URL query string from the given input, and advises whether there are any components following it.
  ///
  static func scanQuery(
    _ input: InputSlice, scheme: SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

    // 2. Find the extent of the query
    let queryEndIndex = input.firstIndex { ASCII($0) == .numberSign }

    // 3. Validate the query-string.
    validateURLCodePointsAndPercentEncoding(input.prefix(upTo: queryEndIndex ?? input.endIndex), callback: &callback)

    // 3. Return the next component.
    mapping.queryRange = Range(uncheckedBounds: (input.startIndex, queryEndIndex ?? input.endIndex))
    if let queryEnd = queryEndIndex {
      return .scan(.fragment, input.index(after: queryEnd))
    } else {
      return .scanningComplete
    }
  }

  /// Scans a URL fragment string from the given input. There are never any components following it.
  ///
  static func scanFragment(
    _ input: InputSlice,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // 1. Validate the mapping.
    assert(mapping.fragmentRange == nil)

    // 2. Validate the fragment string.
    validateURLCodePointsAndPercentEncoding(input, callback: &callback)

    mapping.fragmentRange = Range(uncheckedBounds: (input.startIndex, input.endIndex))
    return .scanningComplete
  }
}

// MARK: - File URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllFileURLComponents(
    _ input: InputSlice, baseURL: WebURL?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var nextLocation = parseFileURLStart(input, baseURL: baseURL, &mapping, callback: &callback)
    guard case .scan(_, let firstComponentStartIndex) = nextLocation else {
      return true
    }
    var remaining = input.suffix(from: firstComponentStartIndex)

    if case .scan(.authority, _) = nextLocation {
      switch scanAuthority(remaining, scheme: .file, &mapping, callback: &callback) {
      case .success(continueFrom: let afterAuthority):
        nextLocation = afterAuthority
      case .failed:
        return false
      }
    }
    while case .scan(let thisComponent, let thisStartIndex) = nextLocation {
      remaining = remaining[thisStartIndex...]
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

  static func parseFileURLStart(
    _ input: InputSlice, baseURL: WebURL?,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    // Note that file URLs may also be relative URLs. It all depends on what comes after "file:".
    // - 0 slashes:  copy base host, parse as path relative to base path.
    // - 1 slash:    copy base host, parse as absolute path.
    // - 2 slashes:  parse own host, parse absolute path.
    // - 3 slahses:  empty host, parse as absolute path.
    // - 4+ slashes: invalid.

    let baseScheme = baseURL?._schemeKind

    var cursor = input.startIndex
    guard cursor != input.endIndex, let c0 = ASCII(input[cursor]), c0 == .forwardSlash || c0 == .backslash else {
      // No slashes. May be a relative path ("file:usr/lib/Swift") or no path ("file:?someQuery").
      guard baseScheme == .file else {
        return .scan(.path, cursor)
      }
      assert(mapping.componentsToCopyFromBase.isEmpty || mapping.componentsToCopyFromBase == [.scheme])
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])

      guard cursor != input.endIndex else {
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

    guard cursor != input.endIndex, let c1 = ASCII(input[cursor]), c1 == .forwardSlash || c1 == .backslash else {
      // 1 slash. e.g. "file:/usr/lib/Swift". Absolute path.
      guard baseScheme == .file else {
        return .scan(.path, input.startIndex)
      }
      mapping.componentsToCopyFromBase.formUnion([.authority])

      // Absolute paths in path-only URLs are still relative to the base URL's Windows drive letter (if it has one).
      // The path parser knows how to handle this.
      mapping.absolutePathsCopyWindowsDriveFromBase = true
      mapping.componentsToCopyFromBase.formUnion([.path])

      return .scan(.path, input.startIndex)
    }

    cursor = input.index(after: cursor)
    if c1 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }

    // 2+ slashes. e.g. "file://localhost/usr/lib/Swift" or "file:///usr/lib/Swift".
    return scanFileHost(input[cursor...], &mapping, callback: &callback)
  }

  // Never fails - even if there is a port and the hostname is empty.
  // In that case, the hostname will contain the port and ultimately get rejected for containing forbidden
  // code-points. File URLs are forbidden from containing ports.
  static func scanFileHost(
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

    // 2. Find the extent of the hostname.
    let hostnameEndIndex =
      input.firstIndex { byte in
        switch ASCII(byte) {
        case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
        default: return false
        }
      } ?? input.endIndex

    let hostname = input[..<hostnameEndIndex]

    // 3. Brief validation of the hostname. Will be fully validated at construction time.
    if PathComponentParser.isWindowsDriveLetter(hostname) {
      // TODO: Only if not in setter-mode.
      // FIXME: 'input' is in the authority position of its containing string.
      //        This requires logic in ProcessedMapping to adjust the path range.
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return .scan(.path, input.startIndex)
    }

    // 4. Return the next component.
    mapping.authorityRange = Range(uncheckedBounds: (input.startIndex, hostnameEndIndex))
    mapping.hostnameRange = Range(uncheckedBounds: (input.startIndex, hostnameEndIndex))
    return .scan(.pathStart, hostnameEndIndex)
  }
}

// MARK: - "cannot-base-a-base" URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllCannotBeABaseURLComponents(
    _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> Bool {

    var nextLocation = scanCannotBeABaseURLPath(input, &mapping, callback: &callback)
    guard case .scan(_, let firstComponentStartIndex) = nextLocation else {
      return true
    }
    var remaining = input.suffix(from: firstComponentStartIndex)

    while case .scan(let thisComponent, let thisStartIndex) = nextLocation {
      remaining = remaining[thisStartIndex...]
      switch thisComponent {
      case .query:
        nextLocation = scanQuery(remaining, scheme: scheme, &mapping, callback: &callback)
      case .fragment:
        nextLocation = scanFragment(remaining, &mapping, callback: &callback)
      case .pathStart, .path, .host, .port, .authority:
        fatalError("Tried to scan invalid component for cannot-be-a-base URL")
      }
    }
    return true
  }

  static func scanCannotBeABaseURLPath(
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
      mapping.pathRange = Range(uncheckedBounds: (path.startIndex, pathEnd))
      return .scan(ASCII(input[pathEnd]) == .questionMark ? .query : .fragment, input.index(after: pathEnd))
    } else {
      mapping.pathRange = path.isEmpty ? nil : Range(uncheckedBounds: (input.startIndex, input.endIndex))
      return .scanningComplete
    }
  }
}

// MARK: - Relative URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllRelativeURLComponents(
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
      remaining = remaining[thisStartIndex...]
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

  static func parseRelativeURLStart(
    _ input: InputSlice, baseScheme: WebURL.SchemeKind,
    _ mapping: inout ScannedRangesAndFlags<InputString>, callback: inout Callback
  ) -> ScanComponentResult {

    mapping.componentsToCopyFromBase = [.scheme]

    guard input.isEmpty == false else {
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return .scanningComplete
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
        return .scan(.path, input.startIndex)
      }
      switch ASCII(input[cursor]) {
      // Second character is also a slash. Parse as an authority.
      case .backslash? where baseScheme.isSpecial:
        callback.validationError(.unexpectedReverseSolidus)
        fallthrough
      case .forwardSlash?:
        if baseScheme.isSpecial {
          cursor =
            input[cursor...].dropFirst()
            .firstIndex { ASCII($0) != .forwardSlash && ASCII($0) != .backslash } ?? input.endIndex
        } else {
          cursor = input.index(after: cursor)
        }
        return .scan(.authority, cursor)
      // Otherwise, copy the base authority. Parse as a (absolute) path.
      default:
        mapping.componentsToCopyFromBase.formUnion([.authority])
        return .scan(.path, input.startIndex)
      }

    // Initial query/fragment markers.
    case .questionMark?:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      return .scan(.query, input.index(after: input.startIndex))
    case .numberSign?:
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])
      return .scan(.fragment, input.index(after: input.startIndex))

    // Some other character. Parse as a relative path.
    default:
      // Since we have a non-empty input string with characters before any query/fragment terminators,
      // path-scanning will always produce a mapping with a non-nil pathLength.
      // Construction knows that if a path is found in the input string *and* we ask to copy from the base,
      // that the paths should be combined by stripping the base's last path component.
      mapping.componentsToCopyFromBase.formUnion([.authority, .path])
      return .scan(.path, input.startIndex)
    }
  }
}


// MARK: - Post-scan validation.


extension ScannedRangesAndFlags where InputString: BidirectionalCollection, InputString.Element == UInt8 {

  /// Performs some basic invariant checks on the scanned URL data. For debug builds.
  ///
  func checkInvariants(_ inputString: InputString, baseURL: WebURL?) -> Bool {

    // - Structural invariants.
    // Ensure that the combination of scanned ranges and flags makes sense.

    // We must have a scheme from somewhere.
    if schemeRange == nil {
      guard componentsToCopyFromBase.contains(.scheme) else { return false }
    }
    // Authority components imply the presence of an authorityRange and hostname.
    if usernameRange != nil || passwordRange != nil || hostnameRange != nil || portRange != nil {
      guard hostnameRange != nil else { return false }
      guard authorityRange != nil else { return false }
      guard cannotBeABaseURL == false else { return false }
    }
    // A password implies the presence of a username.
    if passwordRange != nil {
      guard usernameRange != nil else { return false }
    }

    // Ensure components from input string do not overlap with 'componentsToCopyFromBase' (except path).
    if schemeRange != nil {
      // Scheme can only overlap in relative URLs of special schemes.
      if componentsToCopyFromBase.contains(.scheme) {
        guard schemeKind!.isSpecial, schemeKind == baseURL!._schemeKind else { return false }
      }
    }
    if authorityRange != nil {
      guard componentsToCopyFromBase.contains(.authority) == false else { return false }
    }
    if queryRange != nil {
      guard componentsToCopyFromBase.contains(.query) == false else { return false }
    }
    if fragmentRange != nil {
      guard componentsToCopyFromBase.contains(.fragment) == false else { return false }
    }

    // - Content invariants.
    // Make sure that things such as separators are where we expect and not inside the scanned ranges.

    if schemeRange != nil {
      guard inputString[schemeRange!].last != ASCII.colon.codePoint else { return false }
    }
    if authorityRange != nil {
      if let username = usernameRange {
        if let password = passwordRange {
          guard inputString[inputString.index(before: password.lowerBound)] == ASCII.colon.codePoint else {
            return false
          }
        }
        guard inputString[passwordRange?.upperBound ?? username.upperBound] == ASCII.commercialAt.codePoint else {
          return false
        }
      }
      guard hostnameRange != nil else { return false }
      if let port = portRange {
        guard inputString[inputString.index(before: port.lowerBound)] == ASCII.colon.codePoint else {
          return false
        }
      }
    }
    if let query = queryRange {
      guard inputString[inputString.index(before: query.lowerBound)] == ASCII.questionMark.codePoint else {
        return false
      }
    }
    if let fragment = fragmentRange {
      guard inputString[inputString.index(before: fragment.lowerBound)] == ASCII.numberSign.codePoint else {
        return false
      }
    }
    return true
  }
}


// MARK: - Helper functions.


/// Parses a scheme from the given string of UTF8 bytes.
///
/// If the string contains a scheme terminator ("`:`"), the returned tuple's `terminator` element will be equal to its index.
/// Otherwise, the entire string will be considered the scheme name, and `terminator` will be equal to the input string's `endIndex`.
///
@inlinable
func parseScheme<UTF8Bytes>(
  _ input: UTF8Bytes
) -> (terminator: UTF8Bytes.Index, kind: WebURL.SchemeKind)? where UTF8Bytes: Collection, UTF8Bytes.Element == UInt8 {

  let terminatorIdx = input.firstIndex { $0 == ASCII.colon.codePoint } ?? input.endIndex
  let schemeName = input[Range(uncheckedBounds: (input.startIndex, terminatorIdx))]
  let kind = WebURL.SchemeKind(parsing: schemeName)

  switch kind {
  case .other:
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
  default:
    _onFastPath()
    return (terminatorIdx, kind)
  }
}

/// Given a string, like "example.com:99/some/path?hello=world", returns the endIndex of the hostname component.
/// This is used by the Javascript model's URL setter, which accepts a rather wide variety of inputs.
///
/// This is a "scan-level" operation: the discovered hostname may need additional processing before being written to a URL string.
/// The only situation in which this function returns `nil` is if the scheme is not `file`, and the given string starts with a `:`
/// (i.e. contains a port but no hostname).
///
func findEndOfHostnamePrefix<Input, Callback>(
  _ input: Input, scheme: WebURL.SchemeKind, callback cb: inout Callback
) -> Input.Index? where Input: BidirectionalCollection, Input.Element == UInt8, Callback: URLParserCallback {

  var mapping = ScannedRangesAndFlags<Input>()

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
    _ = URLScanner.scanFileHost(hostname, &mapping, callback: &cb)
  } else {
    guard case .success(_) = URLScanner.scanHostname(hostname, scheme: scheme, &mapping, callback: &cb) else {
      // Only fails if there is a port and the hostname is empty.
      assert(hostname.first == ASCII.colon.codePoint)
      return nil
    }
  }
  return mapping.hostnameRange?.upperBound ?? hostname.endIndex
}

/// Checks if `input`, which is a collection of UTF8-encoded bytes, contains any non-URL code-points or invalid percent encoding (e.g. "%XY").
/// If it does, `callback` is informed with an appropriate `ValidationError`.
///
/// - Note: This method considers the percent sign ("%") to be a valid URL code-point.
/// - Note: This method is a no-op if `callback` is an instance of `IgnoreValidationErrors`.
///
internal func validateURLCodePointsAndPercentEncoding<Input, Callback>(_ input: Input, callback: inout Callback)
where Input: Collection, Input.Element == UInt8, Callback: URLParserCallback {

  guard Callback.self != IgnoreValidationErrors.self else {
    // The compiler has a tough time optimising this function away when we ignore validation errors.
    return
  }

  if hasNonURLCodePoints(input, allowPercentSign: true) {
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
