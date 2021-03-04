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
//    looking for components and marking where they start/end. The results are normalized, validated, and stored as
//    a 'ParsedURLString.ProcessedMapping' value. At this point, we are finished parsing, and the 'ParsedURLString'
//    object is returned to 'urlFromBytes'.
//
// - Construction:
//    'urlFromBytes' calls 'constructURLObject' on the result of the previous step, which unconditionally writes
//    the content to freshly-allocated storage. The actual construction process involves performing a dry-run
//    to calculate the optimal result type and produce an allocation which is correctly sized to hold the result.

func urlFromBytes<Bytes>(_ inputString: Bytes, baseURL: WebURL?) -> WebURL?
where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  var callback = IgnoreValidationErrors()
  return inputString.withContiguousStorageIfAvailable {
    _urlFromBytes_impl($0, baseURL: baseURL, callback: &callback)
  } ?? _urlFromBytes_impl(inputString, baseURL: baseURL, callback: &callback)
}

private func _urlFromBytes_impl<Bytes, Callback>(
  _ inputString: Bytes, baseURL: WebURL?, callback: inout Callback
) -> WebURL? where Bytes: BidirectionalCollection, Bytes.Element == UInt8, Callback: URLParserCallback {

  // Trim leading/trailing C0 control characters and spaces.
  let trimmedInput = inputString.trim {
    switch ASCII($0) {
    case ASCII.ranges.controlCharacters?, .space?: return true
    default: return false
    }
  }
  if trimmedInput.startIndex != inputString.startIndex || trimmedInput.endIndex != inputString.endIndex {
    callback.validationError(.unexpectedC0ControlOrSpace)
  }
  return ASCII.NewlineAndTabFiltered.filterIfNeeded(trimmedInput).map(
    left: { filtered in
      ParsedURLString(inputString: filtered, baseURL: baseURL, callback: &callback)?.constructURLObject()
    },
    right: { trimmed in
      ParsedURLString(inputString: trimmed, baseURL: baseURL, callback: &callback)?.constructURLObject()
    }
  ).get()
}


// MARK: - ParsedURLString


/// A collection of UTF8 bytes which have been successfully parsed as a URL string.
///
/// `ParsedURLString` holds the input string and base URL, together with information from the parser which describes where each component can
/// be found (either within the input string, or copied from the base URL). That is to say, it holds equivalent knowledge to the full URL object,
/// but without allocating storage.
///
/// Create a `ParsedURLString` using the static `.scan` function. You may then attempt to construct a URL object from its contents.
///
struct ParsedURLString<InputString> where InputString: BidirectionalCollection, InputString.Element == UInt8 {
  let inputString: InputString
  let baseURL: WebURL?
  let mapping: ProcessedMapping

  /// Parses the given collection of UTF8 bytes as a URL string, relative to some base URL.
  ///
  /// - parameters:
  ///   - inputString:  The input string, as a collection of UTF8 bytes.
  ///   - baseURL:      The base URL against which `inputString` should be interpreted.
  ///   - callback:     A callback to receive validation errors. If these are unimportant, pass an instance of `IngoreValidationErrors`.
  ///
  init?<Callback: URLParserCallback>(inputString: InputString, baseURL: WebURL?, callback: inout Callback) {
    guard let mapping = URLScanner.scanURLString(inputString, baseURL: baseURL, callback: &callback) else {
      return nil
    }
    self.inputString = inputString
    self.baseURL = baseURL
    self.mapping = mapping
  }

  /// Allocates a new storage buffer and writes the URL to it.
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

  /// Writes the URL to the given consumer.
  ///
  /// As part of this process, the total length of the path needs to be calculated before it is written.
  /// If this `ParsedURLString` is being written for a second time and this length is already known, it may be provided via `knownPathLength`
  /// to skip the length calculation phase of path-writing.
  ///
  func write<WriterType: URLWriter>(to writer: inout WriterType, metrics: URLMetrics? = nil) {
    mapping.write(inputString: inputString, baseURL: baseURL, to: &writer, metrics: metrics)
  }
}

extension ParsedURLString {

  // TODO: document the components of `ProcessedMapping`, including whether components include leading/trailing
  // trivia. Possibly merge it with `URLScanner.UnprocessedMapping` since the details are so closely related.

  /// Information about the URL components inside a string. These values should not be constructed directly - they are produced by the URL parser.
  ///
  struct ProcessedMapping {
    let schemeRange: Range<InputString.Index>?
    let usernameRange: Range<InputString.Index>?
    let passwordRange: Range<InputString.Index>?
    let hostnameRange: Range<InputString.Index>?
    let pathRange: Range<InputString.Index>?
    let queryRange: Range<InputString.Index>?
    let fragmentRange: Range<InputString.Index>?

    let hostKind: ParsedHost?
    let port: UInt16?

    let cannotBeABaseURL: Bool
    fileprivate let componentsToCopyFromBase: ComponentsToCopy
    let schemeKind: WebURL.SchemeKind

    let absolutePathsCopyWindowsDriveFromBase: Bool

    /// - seealso: `ParsedURLString.write(to:knownPathLength:)`.
    func write<WriterType: URLWriter>(
      inputString: InputString,
      baseURL: WebURL?,
      to writer: inout WriterType,
      metrics: URLMetrics? = nil
    ) {

      // 1: Write flags
      writer.writeFlags(schemeKind: schemeKind, cannotBeABaseURL: cannotBeABaseURL)

      // 2: Write scheme.
      if let inputScheme = schemeRange {
        // Scheme must be lowercased.
        writer.writeSchemeContents(ASCII.Lowercased(inputString[inputScheme]))
      } else {
        guard let baseURL = baseURL, componentsToCopyFromBase.contains(.scheme) else {
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
      if let hostname = hostnameRange {
        writer.writeAuthoritySigil()
        hasAuthority = true

        var hasCredentials = false
        if let username = usernameRange, username.isEmpty == false {
          var didEscape = false
          if metrics?.componentsWhichMaySkipEscaping.contains(.username) == true {
            writer.writeUsernameContents { writePiece in
              writePiece(inputString[username])
            }
          } else {
            writer.writeUsernameContents { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
              didEscape = inputString[username]
                .lazy.percentEncoded(using: URLEncodeSet.UserInfo.self)
                .writeBuffered { piece in writePiece(piece) }
            }
          }
          writer.writeHint(.username, needsEscaping: didEscape)
          hasCredentials = true
        }
        if let password = passwordRange, password.isEmpty == false {
          var didEscape = false
          if metrics?.componentsWhichMaySkipEscaping.contains(.password) == true {
            writer.writePasswordContents { writePiece in
              writePiece(inputString[password])
            }
          } else {
            writer.writePasswordContents { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
              didEscape = inputString[password]
                .lazy.percentEncoded(using: URLEncodeSet.UserInfo.self)
                .writeBuffered { piece in writePiece(piece) }
            }
          }
          writer.writeHint(.password, needsEscaping: didEscape)
          hasCredentials = true
        }
        if hasCredentials {
          writer.writeCredentialsTerminator()
        }

        writer.withHostnameWriter { hostWriter in
          hostKind!.write(bytes: inputString[hostname], using: &hostWriter)
        }

        if let port = port, port != schemeKind.defaultPort {
          writer.writePort(port)
        }

      } else if componentsToCopyFromBase.contains(.authority) {
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
      switch pathRange {
      case .some(let path) where cannotBeABaseURL:
        var didEscape = false
        if metrics?.componentsWhichMaySkipEscaping.contains(.path) == true {
          writer.writePath { $0(inputString[path]) }
        } else {
          writer.writePath { writePiece in
            didEscape = inputString[path].lazy.percentEncoded(using: URLEncodeSet.C0.self).writeBuffered(writePiece)
          }
        }
        writer.writeHint(.path, needsEscaping: didEscape)

      case .some(let path):
        let pathMetrics =
          metrics?.pathMetrics
          ?? PathMetrics(
            parsing: inputString[path],
            schemeKind: schemeKind,
            baseURL: componentsToCopyFromBase.contains(.path) ? baseURL! : nil,
            absolutePathsCopyWindowsDriveFromBase: absolutePathsCopyWindowsDriveFromBase
          )
        assert(pathMetrics.requiredCapacity > 0)
        writer.writePathMetricsHint(pathMetrics)
        writer.writeHint(.path, needsEscaping: pathMetrics.needsEscaping)

        if pathMetrics.requiresSigil && (hasAuthority == false) {
          writer.writePathSigil()
        }
        writer.writeUnsafePath(length: pathMetrics.requiredCapacity) { buffer in
          return buffer.writeNormalizedPath(
            parsing: inputString[path],
            schemeKind: schemeKind,
            baseURL: componentsToCopyFromBase.contains(.path) ? baseURL! : nil,
            absolutePathsCopyWindowsDriveFromBase: absolutePathsCopyWindowsDriveFromBase,
            needsEscaping: pathMetrics.needsEscaping
          )
        }

      case .none where componentsToCopyFromBase.contains(.path):
        guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
        baseURL.storage.withComponentBytes(.path) {
          if let basePath = $0 {
            precondition(
              (hasAuthority == false) || componentsToCopyFromBase.contains(.authority),
              "An input string which copies the base URL's path must either have its own authority"
                + "(thus does not need a path sigil) or match the authority/path sigil from the base URL")
            if case .path = baseURL.storage.structure.sigil, hasAuthority == false {
              writer.writePathSigil()
            }
            writer.writePath { writePiece in writePiece(basePath) }
          }
        }

      case .none where schemeKind.isSpecial:
        // Special URLs always have a path.
        writer.writePath { writePiece in
          writePiece(CollectionOfOne(ASCII.forwardSlash.codePoint))
        }

      default:
        break
      }

      // 5: Write query.
      if let query = queryRange {
        var didEscape = false
        if metrics?.componentsWhichMaySkipEscaping.contains(.query) == true {
          writer.writeQueryContents { writerPiece in
            writerPiece(inputString[query])
          }
        } else {
          writer.writeQueryContents { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
            didEscape = writeBufferedPercentEncodedQuery(
              inputString[query],
              isSpecial: schemeKind.isSpecial
            ) { piece in writePiece(piece) }
          }
        }
        writer.writeHint(.query, needsEscaping: didEscape)
      } else if componentsToCopyFromBase.contains(.query) {
        guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
        baseURL.storage.withComponentBytes(.query) {
          if let baseQuery = $0?.dropFirst() {  // '?' separator.
            writer.writeQueryContents { writePiece in writePiece(baseQuery) }
          }
        }
      }

      // 6: Write fragment.
      if let fragment = fragmentRange {
        var didEscape = false
        if metrics?.componentsWhichMaySkipEscaping.contains(.fragment) == true {
          writer.writeFragmentContents { writePiece in
            writePiece(inputString[fragment])
          }
        } else {
          writer.writeFragmentContents { (writePiece: (UnsafeBufferPointer<UInt8>) -> Void) in
            didEscape = inputString[fragment]
              .lazy.percentEncoded(using: URLEncodeSet.Fragment.self)
              .writeBuffered { piece in writePiece(piece) }
          }
        }
        writer.writeHint(.fragment, needsEscaping: didEscape)
      } else if componentsToCopyFromBase.contains(.fragment) {
        guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
        baseURL.storage.withComponentBytes(.fragment) {
          if let baseFragment = $0?.dropFirst() {  // '#' separator.
            writer.writeFragmentContents { writePiece in writePiece(baseFragment) }
          }
        }
      }

      return  // End of writing.
    }
  }
}


// MARK: - URL Scanner.


/// A set of components to be copied from a URL.
///
/// - seealso: `URLScanner.UnprocessedMapping.componentsToCopyFromBase`
///
fileprivate struct ComponentsToCopy: OptionSet {
  var rawValue: UInt8
  init(rawValue: UInt8) {
    self.rawValue = rawValue
  }
  static var scheme: Self { Self(rawValue: 1 << 0) }
  static var authority: Self { Self(rawValue: 1 << 1) }
  static var path: Self { Self(rawValue: 1 << 2) }
  static var query: Self { Self(rawValue: 1 << 3) }
  static var fragment: Self { Self(rawValue: 1 << 4) }
}

fileprivate enum ParsableComponent {
  case authority
  case host
  case port
  case pathStart  // better name?
  case path
  case query
  case fragment
}

/// A namespace for URL scanning methods.
///
fileprivate enum URLScanner<InputString, Callback>
where InputString: BidirectionalCollection, InputString.Element == UInt8, Callback: URLParserCallback {

  enum ComponentParseResult {
    case failed
    case success(continueFrom: (ParsableComponent, InputString.Index)?)
  }

  typealias Scheme = WebURL.SchemeKind
  typealias InputSlice = InputString.SubSequence
}

extension URLScanner {

  /// A summary of information obtained by scanning a string as a URL.
  ///
  /// This summary contains information such as which components are present and where they are located, as well as any components
  /// which must be copied from a base URL. Typically, these are mutually-exclusive: a component comes _either_ from the input string _or_ the base URL.
  /// However, there is one important exception: constructing a final path can sometimes require _both_ the input string _and_ the base URL.
  /// This is the only case when a component is marked as present from both data sources.
  ///
  struct UnprocessedMapping {

    // This is the index of the scheme terminator (":"), if one exists.
    var schemeRange: Range<InputString.Index>?

    // This is the index of the first character of the authority segment, if one exists.
    // The scheme and authority may be separated by an arbitrary amount of trivia.
    // The authority ends at the "*EndIndex" of the last of its components.
    var authorityRange: Range<InputString.Index>?

    // This is the endIndex of the authority's username component, if one exists.
    // The username starts at the authorityStartIndex.
    var usernameRange: Range<InputString.Index>?

    // This is the endIndex of the password, if one exists.
    // If a password exists, a username must also exist, and usernameEndIndex must be the ":" character.
    // The password starts at the index after usernameEndIndex.
    var passwordRange: Range<InputString.Index>?

    // This is the endIndex of the hostname, if one exists.
    // The hostname starts at (username/password)EndIndex, or from authorityStartIndex if there are no credentials.
    // If a hostname exists, authorityStartIndex must be set.
    var hostnameRange: Range<InputString.Index>?

    // This is the endIndex of the port-string, if one exists. If a port exists, a hostname must also exist.
    // If it exists, the port-string starts at hostnameEndIndex and includes a leading ':' character.
    var portRange: Range<InputString.Index>?

    // This is the endIndex of the path, if one exists.
    // If an authority segment exists, the path starts at the end of the authority and includes a leading slash.
    // Otherwise, it starts at the index after 'schemeTerminatorIndex' (if it exists) and may/may not include leading slashes.
    // If there is also no scheme, the path starts at the start of the string and may/may not include leading slashes.
    var pathRange: Range<InputString.Index>?

    // This is the endIndex of the query-string, if one exists.
    // If it exists, the query starts at the end of the last component and includes a leading '?' character.
    var queryRange: Range<InputString.Index>?

    // This is the endIndex of the fragment-string, if one exists.
    // If it exists, the fragment starts at the end of the last component and includes a leading '#' character.
    var fragmentRange: Range<InputString.Index>?

    // - Flags and data.

    var cannotBeABaseURL = false
    var componentsToCopyFromBase: ComponentsToCopy = []
    var schemeKind: WebURL.SchemeKind? = nil

    var absolutePathsCopyWindowsDriveFromBase = false
  }
}

// MARK: - URL Scanner Entry point.

// `scanURLString` calls in to `scanURLString_noprocess`.
//
// `scanURLString_noprocess` looks for a scheme, and calls `scanURLWithScheme` if it finds one.
// Both paths analyze the start of the input and dispatch to either:
// - `scanAllComponents`
// - `scanAllFileURLComponents`
// - `scanAllRelativeURLComponents`, or
// - `scanAllCannotBeABaseURLComponents`
//
// This produces an 'UnprocessedMapping', which is then processed to create a 'ProcessedMapping'.

extension URLScanner {

  /// Scans the given URL string and returns a mapping of components that were discovered.
  ///
  /// - parameters:
  ///   - input:    The input string, as a collection of UTF8 bytes.
  ///   - baseURL:  The base URL to interpret `input` against.
  ///   - callback: An object to notify about any validation errors which are encountered.
  /// - returns:    A mapping of detected URL components, or `nil` if the string could not be parsed.
  ///
  static func scanURLString(
    _ input: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> ParsedURLString<InputString>.ProcessedMapping? {
    return scanURLStringWithoutProcessing(input, baseURL: baseURL, callback: &callback)?
      .process(inputString: input, baseURL: baseURL, callback: &callback)
  }

  static func scanURLStringWithoutProcessing(
    _ input: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> UnprocessedMapping? {

    var scanResults = UnprocessedMapping()

    if let schemeEndIndex = findScheme(input),
      schemeEndIndex != input.endIndex,
      input[schemeEndIndex] == ASCII.colon.codePoint
    {
      let schemeName = input.prefix(upTo: schemeEndIndex)
      let schemeKind = WebURL.SchemeKind(parsing: schemeName)
      scanResults.schemeKind = schemeKind
      scanResults.schemeRange = Range(uncheckedBounds: (input.startIndex, schemeName.endIndex))

      let tail = input.suffix(from: input.index(after: schemeEndIndex))
      return scanURLWithScheme(
        tail, scheme: schemeKind, baseURL: baseURL,
        &scanResults, callback: &callback
      ) ? scanResults : nil
    }

    // If we don't have a scheme, we'll need to copy from the baseURL.
    guard let base = baseURL else {
      callback.validationError(.missingSchemeNonRelativeURL)
      return nil
    }
    // If base `cannotBeABaseURL`, the only thing we can do is set the fragment.
    guard base._cannotBeABaseURL == false else {
      guard ASCII(flatMap: input.first) == .numberSign else {
        callback.validationError(.missingSchemeNonRelativeURL)
        return nil
      }
      scanResults.componentsToCopyFromBase = [.scheme, .path, .query]
      scanResults.cannotBeABaseURL = true
      guard case .success = scanFragment(input.dropFirst(), &scanResults, callback: &callback) else {
        return nil
      }
      return scanResults
    }
    // (No scheme + valid base URL) = relative URL.
    if base._schemeKind == .file {
      scanResults.componentsToCopyFromBase = [.scheme]
      return scanAllFileURLComponents(
        input[...], baseURL: baseURL, &scanResults, callback: &callback
      ) ? scanResults : nil
    }
    return scanAllRelativeURLComponents(
      input[...], baseScheme: base._schemeKind, &scanResults, callback: &callback
    ) ? scanResults : nil
  }

  /// Scans all components of the input string `input`, and builds up a map based on the URL's `scheme`.
  ///
  static func scanURLWithScheme(
    _ input: InputSlice, scheme: Scheme, baseURL: WebURL?,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> Bool {

    switch scheme {
    case .file:
      if !URLStringUtils.hasDoubleSolidusPrefix(input) {
        callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return scanAllFileURLComponents(input, baseURL: baseURL, &mapping, callback: &callback)

    case .other:
      var authority = input[...]
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
      var authority = input[...]
      if URLStringUtils.hasDoubleSolidusPrefix(input) {
        // state: "special authority slashes"
        authority = authority.dropFirst(2)
      } else {
        // Note: since `scheme` is special, comparing the kind is sufficient.
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
    from: ParsableComponent, _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> Bool {

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
      case .host, .port:
        fatalError("Host and port should have been handled by scanAuthority")
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
  /// If parsing doesn't fail, the next component is always `pathStart`.
  ///
  static func scanAuthority(
    _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
      return .success(continueFrom: (.pathStart, hostStartIndex))
    }

    guard case .success(let postHost) = scanHostname(hostname, scheme: scheme, &mapping, callback: &callback) else {
      return .failed
    }
    // Scan the port, if the host requested it.
    guard let portComponent = postHost, case .port = portComponent.0 else {
      return .success(continueFrom: postHost)
    }
    return scanPort(authority[portComponent.1...], scheme: scheme, &mapping, callback: &callback)
  }

  static func scanHostname(
    _ input: InputSlice, scheme: Scheme,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
      return .success(continueFrom: (.port, input.index(after: hostnameEnd)))
    } else {
      return .success(continueFrom: (.pathStart, input.endIndex))
    }
  }

  static func scanPort(
    _ input: InputSlice, scheme: Scheme,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
    return .success(continueFrom: (.pathStart, portString.endIndex))
  }

  /// Scans the URL string from the character immediately following the authority, and advises
  /// whether the remainder is a path, query or fragment.
  ///
  static func scanPathStart(
    _ input: InputSlice, scheme: Scheme, _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

    // 1. Validate the mapping.
    assert(mapping.pathRange == nil)
    assert(mapping.queryRange == nil)
    assert(mapping.fragmentRange == nil)

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

  /// Scans a URL path string from the given input, and advises whether there are any components following it.
  ///
  static func scanPath(
    _ input: InputSlice, scheme: Scheme,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
      return .success(
        continueFrom: (
          ASCII(input[pathEnd]) == .questionMark ? .query : .fragment, input.index(after: pathEnd)
        ))
    } else {
      return .success(continueFrom: nil)
    }
  }

  /// Scans a URL query string from the given input, and advises whether there are any components following it.
  ///
  static func scanQuery(
    _ input: InputSlice, scheme: Scheme,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
      return .success(
        continueFrom: ASCII(input[queryEnd]) == .numberSign ? (.fragment, input.index(after: queryEnd)) : nil
      )
    } else {
      return .success(continueFrom: nil)
    }
  }

  /// Scans a URL fragment string from the given input. There are never any components following it.
  ///
  static func scanFragment(
    _ input: InputSlice,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

    // 1. Validate the mapping.
    assert(mapping.fragmentRange == nil)

    // 2. Validate the fragment string.
    validateURLCodePointsAndPercentEncoding(input, callback: &callback)

    mapping.fragmentRange = Range(uncheckedBounds: (input.startIndex, input.endIndex))
    return .success(continueFrom: nil)
  }
}

// MARK: - File URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllFileURLComponents(
    _ input: InputSlice, baseURL: WebURL?,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> Bool {

    var remaining: InputSlice.SubSequence
    var component: (ParsableComponent, InputString.Index)
    switch parseFileURLStart(input, baseURL: baseURL, &mapping, callback: &callback) {
    case .failed:
      return false
    case .success(continueFrom: .none):
      return true
    case .success(continueFrom: .some(let _component)):
      component = _component
      remaining = input.suffix(from: component.1)
    }
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
      case .host, .port:
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

  static func parseFileURLStart(
    _ input: InputSlice, baseURL: WebURL?,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
        return .success(continueFrom: (.path, cursor))
      }
      assert(mapping.componentsToCopyFromBase.isEmpty || mapping.componentsToCopyFromBase == [.scheme])
      mapping.componentsToCopyFromBase.formUnion([.authority, .path, .query])

      guard cursor != input.endIndex else {
        return .success(continueFrom: nil)
      }
      switch ASCII(input[cursor]) {
      case .questionMark?:
        mapping.componentsToCopyFromBase.remove(.query)
        return .success(continueFrom: (.query, input.index(after: cursor)))
      case .numberSign?:
        return .success(continueFrom: (.fragment, input.index(after: cursor)))
      default:
        mapping.componentsToCopyFromBase.remove(.query)
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

    guard cursor != input.endIndex, let c1 = ASCII(input[cursor]), c1 == .forwardSlash || c1 == .backslash else {
      // 1 slash. e.g. "file:/usr/lib/Swift". Absolute path.
      guard baseScheme == .file else {
        return .success(continueFrom: (.path, input.startIndex))
      }
      mapping.componentsToCopyFromBase.formUnion([.authority])

      // Absolute paths in path-only URLs are still relative to the base URL's Windows drive letter (if it has one).
      // The path parser knows how to handle this.
      mapping.absolutePathsCopyWindowsDriveFromBase = true
      mapping.componentsToCopyFromBase.formUnion([.path])

      return .success(continueFrom: (.path, input.startIndex))
    }

    cursor = input.index(after: cursor)
    if c1 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }

    // 2+ slashes. e.g. "file://localhost/usr/lib/Swift" or "file:///usr/lib/Swift".
    return scanFileHost(input[cursor...], &mapping, callback: &callback)
  }


  static func scanFileHost(
    _ input: InputSlice,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
    if URLStringUtils.isWindowsDriveLetter(hostname) {
      // TODO: Only if not in setter-mode.
      // FIXME: 'input' is in the authority position of its containing string.
      //        This requires logic in ProcessedMapping to adjust the path range.
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return .success(continueFrom: (.path, input.startIndex))
    }

    // 4. Return the next component.
    mapping.authorityRange = Range(uncheckedBounds: (input.startIndex, hostnameEndIndex))
    mapping.hostnameRange = Range(uncheckedBounds: (input.startIndex, hostnameEndIndex))
    return .success(continueFrom: (.pathStart, hostnameEndIndex))
  }
}

// MARK: - "cannot-base-a-base" URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllCannotBeABaseURLComponents(
    _ input: InputSlice, scheme: WebURL.SchemeKind,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> Bool {

    var remaining: InputSlice.SubSequence
    var component: (ParsableComponent, InputString.Index)
    switch scanCannotBeABaseURLPath(input, &mapping, callback: &callback) {
    case .failed:
      return false
    case .success(continueFrom: .none):
      return true
    case .success(continueFrom: .some(let _component)):
      component = _component
      remaining = input.suffix(from: component.1)
    }
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

  static func scanCannotBeABaseURLPath(
    _ input: InputSlice,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
      return .success(
        continueFrom: (
          ASCII(input[pathEnd]) == .questionMark ? .query : .fragment, input.index(after: pathEnd)
        ))
    } else {
      mapping.pathRange = path.isEmpty ? nil : Range(uncheckedBounds: (input.startIndex, input.endIndex))
      return .success(continueFrom: nil)
    }
  }
}

// MARK: - Relative URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllRelativeURLComponents(
    _ input: InputSlice, baseScheme: WebURL.SchemeKind,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> Bool {

    var remaining: InputSlice.SubSequence
    var component: (ParsableComponent, InputString.Index)
    switch parseRelativeURLStart(input, baseScheme: baseScheme, &mapping, callback: &callback) {
    case .failed:
      return false
    case .success(continueFrom: .none):
      return true
    case .success(continueFrom: .some(let _component)):
      component = _component
      remaining = input.suffix(from: component.1)
    }
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

  static func parseRelativeURLStart(
    _ input: InputSlice, baseScheme: WebURL.SchemeKind,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

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
          cursor =
            input[cursor...].dropFirst()
            .firstIndex { ASCII($0) != .forwardSlash && ASCII($0) != .backslash } ?? input.endIndex
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

// MARK: - Post-scan processing.

extension URLScanner.UnprocessedMapping {

  /// Creates a processed mapping from the raw, unprocessed data returned by the scanner.
  ///
  func process(
    inputString: InputString,
    baseURL: WebURL?,
    callback: inout Callback
  ) -> ParsedURLString<InputString>.ProcessedMapping? {

    assert(checkStructuralInvariants())
    let u_mapping = self  // TODO: This is being kept around temporarily in case I decide to move the function.

    let schemeKind: WebURL.SchemeKind
    if let scannedSchemeKind = u_mapping.schemeKind {
      schemeKind = scannedSchemeKind
    } else if componentsToCopyFromBase.contains(.scheme), let baseURL = baseURL {
      schemeKind = baseURL._schemeKind
    } else {
      preconditionFailure("We must have a scheme")
    }

    // Step 1: Extract full ranges.

    if u_mapping.authorityRange != nil {
      if let username = u_mapping.usernameRange {
        if let password = u_mapping.passwordRange {
          assert(inputString[inputString.index(before: password.lowerBound)] == ASCII.colon.codePoint)
        }
        assert(inputString[u_mapping.passwordRange?.upperBound ?? username.upperBound] == ASCII.commercialAt.codePoint)
      }
      assert(u_mapping.hostnameRange != nil)
      if let port = u_mapping.portRange {
        assert(inputString[inputString.index(before: port.lowerBound)] == ASCII.colon.codePoint)
      }
    }
    if let query = u_mapping.queryRange {
      assert(inputString[inputString.index(before: query.lowerBound)] == ASCII.questionMark.codePoint)
    }
    if let fragment = u_mapping.fragmentRange {
      assert(inputString[inputString.index(before: fragment.lowerBound)] == ASCII.numberSign.codePoint)
    }

    // Step 2: Process the input string, now that we have full knowledge of its contents.

    // 2.1: Parse port string.
    var port: UInt16?
    if let portRange = portRange, portRange.isEmpty == false {
      guard let parsedInteger = UInt16(String(decoding: inputString[portRange], as: UTF8.self)) else {
        callback.validationError(.portOutOfRange)
        return nil
      }
      port = parsedInteger
    }
    // 2.2 Process hostname.
    // Even though it may be discarded later by certain file URLs, we still need to do this now
    // to reject invalid hostnames.
    var hostKind: ParsedHost?
    if let hostname = hostnameRange.map({ inputString[$0] }) {
      hostKind = ParsedHost(hostname, schemeKind: schemeKind, callback: &callback)
      guard hostKind != nil else { return nil }
    }

    // FIXME: This is too fragile.
    var adjustedPathRange = u_mapping.pathRange
    if schemeKind == .file {
      // We may have a Windows drive letter in the authority position ("file://C:/foo").
      // If so, drop the leading slash so it is treated as an absolute path with Windows drive.
      if var pathContents = adjustedPathRange.map({ inputString[$0] }), hostnameRange == nil {
        let isPathSeparator: (UInt8?) -> Bool = {
          $0 == ASCII.forwardSlash.codePoint || $0 == ASCII.backslash.codePoint
        }
        if isPathSeparator(pathContents.popFirst()),
          isPathSeparator(pathContents.first),
          URLStringUtils.hasWindowsDriveLetterPrefix(pathContents.dropFirst())
        {
          adjustedPathRange = pathContents.startIndex..<pathContents.endIndex
        }
      }
    }

    // Step 3: Construct a `ProcessedMapping` from that information.
    return ParsedURLString<InputString>.ProcessedMapping(
      schemeRange: u_mapping.schemeRange,
      usernameRange: u_mapping.usernameRange,
      passwordRange: u_mapping.passwordRange,
      hostnameRange: u_mapping.hostnameRange,
      pathRange: adjustedPathRange,
      queryRange: u_mapping.queryRange,
      fragmentRange: u_mapping.fragmentRange,
      hostKind: hostKind,
      port: port,
      cannotBeABaseURL: u_mapping.cannotBeABaseURL,
      componentsToCopyFromBase: u_mapping.componentsToCopyFromBase,
      schemeKind: schemeKind,
      absolutePathsCopyWindowsDriveFromBase: u_mapping.absolutePathsCopyWindowsDriveFromBase
    )
  }

  /// Performs some basic invariant checks on the scanned URL data.
  ///
  func checkStructuralInvariants() -> Bool {

    // We must have a scheme from somewhere.
    if schemeRange == nil {
      guard componentsToCopyFromBase.contains(.scheme) else { return false }
    }
    // Authority components imply the presence of an authorityStartIndex and hostname.
    if usernameRange != nil || passwordRange != nil || hostnameRange != nil || portRange != nil {
      guard hostnameRange != nil else { return false }
      guard authorityRange != nil else { return false }
    }
    // A password implies the presence of a username.
    if passwordRange != nil {
      guard usernameRange != nil else { return false }
    }

    // Ensure components from input string do not overlap with 'componentsToCopyFromBase' (except path).
    if schemeRange != nil {
      // FIXME: Scheme can overlap in relative URLs, but we already test the string and base schemes for equality.
      // guard componentsToCopyFromBase.contains(.scheme) == false else { return false }
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
    return true
  }
}

// MARK: - Helper functions.

/// Returns the endIndex of the scheme name if one can be parsed from `input`.
///
func findScheme<Input>(_ input: Input) -> Input.Index? where Input: Collection, Input.Element == UInt8 {

  guard input.isEmpty == false else { return nil }
  var slice = input[...]

  // schemeStart: must begin with an ASCII alpha.
  guard ASCII(flatMap: slice.popFirst())?.isAlpha == true else { return nil }

  // scheme: allow all ASCII { alphaNumeric, +, -, . } characters.
  let _schemeEnd = slice.firstIndex { byte in
    let c = ASCII(byte)
    switch c {
    case _ where c?.isAlphaNumeric == true, .plus?, .minus?, .period?:
      return false
    default:
      assert(c != .horizontalTab && c != .lineFeed)
      return true
    }
  }
  if let schemeEnd = _schemeEnd {
    return input[schemeEnd] == ASCII.colon.codePoint ? schemeEnd : nil
  }
  return input.endIndex
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

  var mapping = URLScanner<Input, Callback>.UnprocessedMapping()

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
    guard case .success(_) = URLScanner.scanFileHost(hostname, &mapping, callback: &cb) else {
      // Never fails - even if there is a port and the hostname is empty.
      // In that case, the hostname will contain the port and ultimately get rejected for containing forbidden
      // code-points. File URLs are forbidden from containing ports.
      assertionFailure("Unexpected failure to scan file host")
      return nil
    }
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
