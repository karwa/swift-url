// This file contains the URL parser.
//
// Parsing happens in 3 steps, starting at the 'urlFromBytes' function:
//
// 1. 'urlFromBytes' checks to see if the bytes contain ASCII tab/newline characters.
//    If they do, the collection is wrapped in a 'FilteredURLInput' to lazily remove them.
//    A 'ParsedURLString' is created, which calls in to `URLScanner.scanURLString'.
//
// 2. The URLScanner scans the byte string - looking for components and marking where they start/end.
//    The result is then processed in to a 'ParsedURLString.ProcessedMapping' and the completed 'ParsedURLString'
//    object is returned.
//
// 3. 'urlFromBytes' calls 'constructURLObject' on the result of the previous step, which unconditionally writes
//    the content to freshly-allocated storage. The actual construction process involves performing a dry-run
//    to calculate the optimal result type and produce an allocation which is correctly sized to hold the result.

func urlFromBytes<Bytes>(_ inputString: Bytes, baseURL: NewURL?) -> NewURL?
where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  var callback = IgnoreValidationErrors()
  let (trimmedInput, needsFiltering) = FilteredURLInput.trim(inputString, callback: &callback)
  if needsFiltering {
    let filteredInput = FilteredURLInput<Bytes>(trimmedInput)
    return ParsedURLString(inputString: filteredInput, baseURL: baseURL, callback: &callback)?.constructURLObject()
  }
  if let bufferSlice = trimmedInput as? Slice<UnsafeBufferPointer<UInt8>> {
    return ParsedURLString(
      inputString: UnsafeBufferPointer(rebasing: bufferSlice),
      baseURL: baseURL,
      callback: &callback
    )?.constructURLObject()
  }
  return ParsedURLString(inputString: trimmedInput, baseURL: baseURL, callback: &callback)?.constructURLObject()
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
  let baseURL: NewURL?
  let mapping: ProcessedMapping

  /// Parses the given collection of UTF8 bytes as a URL string, relative to some base URL.
  ///
  /// - parameters:
  ///   - inputString:  The input string, as a collection of UTF8 bytes.
  ///   - baseURL:      The base URL against which `inputString` should be interpreted.
  ///   - callback:     A callback to receive validation errors. If these are unimportant, pass an instance of `IngoreValidationErrors`.
  ///
  init?<Callback: URLParserCallback>(inputString: InputString, baseURL: NewURL?, callback: inout Callback) {
    guard let mapping = URLScanner.scanURLString(inputString, baseURL: baseURL, callback: &callback) else {
      return nil
    }
    self.inputString = inputString
    self.baseURL = baseURL
    self.mapping = mapping
  }

  /// Allocates a new storage buffer and writes the URL to it.
  ///
  func constructURLObject() -> NewURL {

    // Do a dry-run to calculate metrics about the final contents.
    var metrics = URLMetricsCollector()
    write(to: &metrics)
    // Write to the optimal storage variant.
    if metrics.requiredCapacity < UInt8.max {
      return GenericURLHeader<UInt8>.writeURLToNewStorage(capacity: metrics.requiredCapacity) { smallWriter in
        write(to: &smallWriter, knownPathLength: metrics.pathLength)
      }
    } else {
      return GenericURLHeader<Int>.writeURLToNewStorage(capacity: metrics.requiredCapacity) { genericWriter in
        write(to: &genericWriter, knownPathLength: metrics.pathLength)
      }
    }
  }

  /// Writes the URL to the given consumer.
  ///
  /// As part of this process, the total length of the path needs to be calculated before it is written.
  /// If this `ParsedURLString` is being written for a second time and this length is already known, it may be provided via `knownPathLength`
  /// to skip the length calculation phase of path-writing.
  ///
  func write<WriterType: URLWriter>(to writer: inout WriterType, knownPathLength: Int? = nil) {
    mapping.write(inputString: inputString, baseURL: baseURL, to: &writer, knownPathLength: knownPathLength)
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

    let pathRange: Range<InputString.Index>?
    let queryRange: Range<InputString.Index>?
    let fragmentRange: Range<InputString.Index>?

    let hostnameString: String?
    let port: UInt16?

    let cannotBeABaseURL: Bool
    let componentsToCopyFromBase: ComponentsToCopy
    let schemeKind: NewURL.Scheme

    /// - seealso: `ParsedURLString.write(to:knownPathLength:)`.
    func write<WriterType: URLWriter>(
      inputString: InputString,
      baseURL: NewURL?,
      to writer: inout WriterType,
      knownPathLength: Int? = nil
    ) {

      // 1: Write flags
      writer.writeFlags(schemeKind: schemeKind, cannotBeABaseURL: cannotBeABaseURL)

      // 2: Write scheme.
      if let inputScheme = schemeRange {
        // Scheme must be lowercased.
        writer.writeSchemeContents(LowercaseASCIITransformer(base: inputString[inputScheme]), countIfKnown: nil)
      } else {
        guard let baseURL = baseURL, componentsToCopyFromBase.contains(.scheme) else {
          preconditionFailure("Cannot construct a URL without a scheme")
        }
        assert(schemeKind == baseURL.schemeKind)
        baseURL.variant.withComponentBytes(.scheme) {
          let bytes = $0!.dropLast()  // drop terminator.
          writer.writeSchemeContents(bytes, countIfKnown: bytes.count)
        }
      }

      // 3: Write authority.
      if var hostnameString = hostnameString {
        writer.writeAuthorityHeader()

        var hasCredentials = false
        if let username = usernameRange, username.isEmpty == false {
          writer.writeUsernameContents { writePiece in
            PercentEscaping.encodeIterativelyAsBuffer(
              bytes: inputString[username],
              escapeSet: .url_userInfo,
              processChunk: { piece in writePiece(piece) }
            )
          }
          hasCredentials = true
        }
        if let password = passwordRange, password.isEmpty == false {
          writer.writePasswordContents { writePiece in
            PercentEscaping.encodeIterativelyAsBuffer(
              bytes: inputString[password],
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

      } else if componentsToCopyFromBase.contains(.authority) {
        guard let baseURL = baseURL else {
          preconditionFailure("A baseURL is required")
        }
        baseURL.variant.withAllAuthorityComponentBytes {
          if let baseAuth = $0 {
            writer.writeAuthorityHeader()
            writer.writeKnownAuthorityString(
              baseAuth,
              usernameLength: $1,
              passwordLength: $2,
              hostnameLength: $3,
              portLength: $4
            )
          }
        }
      } else if schemeKind == .file {
        // 'file:' URLs get an implicit authority.
        writer.writeAuthorityHeader()
      }

      // 4: Write path.
      if let path = pathRange {
        switch cannotBeABaseURL {
        case true:
          writer.writePathSimple { writePiece in
            PercentEscaping.encodeIterativelyAsBuffer(
              bytes: inputString[path],
              escapeSet: .url_c0,
              processChunk: { piece in writePiece(piece) }
            )
          }
        case false:
          let pathLength: Int
          if let knownLength = knownPathLength {
            pathLength = knownLength
          } else {
            pathLength = PathBufferLengthCalculator.requiredBufferLength(
              pathString: inputString[path],
              schemeKind: schemeKind,
              baseURL: componentsToCopyFromBase.contains(.path) ? baseURL! : nil
            )
          }
          assert(pathLength > 0)

          writer.writeUnsafePathInPreallocatedBuffer(length: pathLength) { mutBuffer in
            PathPreallocatedBufferWriter.writePath(
              to: mutBuffer,
              pathString: inputString[path],
              schemeKind: schemeKind,
              baseURL: componentsToCopyFromBase.contains(.path) ? baseURL! : nil
            )
            return pathLength
          }
        }
      } else if componentsToCopyFromBase.contains(.path) {
        guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
        baseURL.variant.withComponentBytes(.path) {
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

      // 5: Write query.
      if let query = queryRange {
        writer.writeQueryContents { writePiece in
          PercentEscaping.encodeIterativelyAsBuffer(
            bytes: inputString[query],
            escapeSet: schemeKind.isSpecial ? .url_query_special : .url_query_nonSpecial,
            processChunk: { piece in writePiece(piece) }
          )
        }
      } else if componentsToCopyFromBase.contains(.query) {
        guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
        baseURL.variant.withComponentBytes(.query) {
          if let baseQuery = $0?.dropFirst() {  // '?' separator.
            writer.writeQueryContents { writePiece in writePiece(baseQuery) }
          }
        }
      }

      // 6: Write fragment.
      if let fragment = fragmentRange {
        writer.writeFragmentContents { writePiece in
          PercentEscaping.encodeIterativelyAsBuffer(
            bytes: inputString[fragment],
            escapeSet: .url_fragment,
            processChunk: { piece in writePiece(piece) }
          )
        }
      } else if componentsToCopyFromBase.contains(.fragment) {
        guard let baseURL = baseURL else { preconditionFailure("A baseURL is required") }
        baseURL.variant.withComponentBytes(.fragment) {
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
struct ComponentsToCopy: OptionSet {
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

enum ParsableComponent {
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
enum URLScanner<InputString, Callback>
where InputString: BidirectionalCollection, InputString.Element == UInt8, Callback: URLParserCallback {

  enum ComponentParseResult {
    case failed
    case success(continueFrom: (ParsableComponent, InputString.Index)?)
  }

  typealias Scheme = NewURL.Scheme
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

    // - Indexes.

    // This is the index of the scheme terminator (":"), if one exists.
    var schemeTerminatorIndex = InputString.Index?.none

    // This is the index of the first character of the authority segment, if one exists.
    // The scheme and authority may be separated by an arbitrary amount of trivia.
    // The authority ends at the "*EndIndex" of the last of its components.
    var authorityStartIndex = InputString.Index?.none

    // This is the endIndex of the authority's username component, if one exists.
    // The username starts at the authorityStartIndex.
    var usernameEndIndex = InputString.Index?.none

    // This is the endIndex of the password, if one exists.
    // If a password exists, a username must also exist, and usernameEndIndex must be the ":" character.
    // The password starts at the index after usernameEndIndex.
    var passwordEndIndex = InputString.Index?.none

    // This is the endIndex of the hostname, if one exists.
    // The hostname starts at (username/password)EndIndex, or from authorityStartIndex if there are no credentials.
    // If a hostname exists, authorityStartIndex must be set.
    var hostnameEndIndex = InputString.Index?.none

    // This is the endIndex of the port-string, if one exists. If a port exists, a hostname must also exist.
    // If it exists, the port-string starts at hostnameEndIndex and includes a leading ':' character.
    var portEndIndex = InputString.Index?.none

    // This is the endIndex of the path, if one exists.
    // If an authority segment exists, the path starts at the end of the authority and includes a leading slash.
    // Otherwise, it starts at the index after 'schemeTerminatorIndex' (if it exists) and may/may not include leading slashes.
    // If there is also no scheme, the path starts at the start of the string and may/may not include leading slashes.
    var pathEndIndex = InputString.Index?.none

    // This is the endIndex of the query-string, if one exists.
    // If it exists, the query starts at the end of the last component and includes a leading '?' character.
    var queryEndIndex = InputString.Index?.none

    // This is the endIndex of the fragment-string, if one exists.
    // If it exists, the fragment starts at the end of the last component and includes a leading '#' character.
    var fragmentEndIndex = InputString.Index?.none

    // - Flags and data.

    var cannotBeABaseURL = false
    var componentsToCopyFromBase: ComponentsToCopy = []
    var schemeKind: NewURL.Scheme? = nil
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
    baseURL: NewURL?,
    callback: inout Callback
  ) -> ParsedURLString<InputString>.ProcessedMapping? {
    return scanURLStringWithoutProcessing(input, baseURL: baseURL, callback: &callback)?
      .process(inputString: input, baseURL: baseURL, callback: &callback)
  }

  static func scanURLStringWithoutProcessing(
    _ input: InputString,
    baseURL: NewURL?,
    callback: inout Callback
  ) -> UnprocessedMapping? {

    var scanResults = UnprocessedMapping()

    if let schemeEndIndex = findScheme(input) {
      let schemeName = input.prefix(upTo: schemeEndIndex).dropLast()  // dropLast() to remove the ":" terminator.
      let schemeKind = NewURL.Scheme.parse(asciiBytes: schemeName)

      scanResults.schemeKind = schemeKind
      scanResults.schemeTerminatorIndex = schemeName.endIndex
      return scanURLWithScheme(
        input.suffix(from: schemeEndIndex), scheme: schemeKind, baseURL: baseURL,
        &scanResults, callback: &callback
      ) ? scanResults : nil
    }

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
      guard case .success = scanFragment(input.dropFirst(), &scanResults, callback: &callback) else {
        return nil
      }
      return scanResults
    }
    // (No scheme + valid base URL) = relative URL.
    if base.schemeKind == .file {
      scanResults.componentsToCopyFromBase = [.scheme]
      return scanAllFileURLComponents(
        input[...], baseURL: baseURL, &scanResults, callback: &callback
      ) ? scanResults : nil
    }
    return scanAllRelativeURLComponents(
      input[...], baseScheme: base.schemeKind, &scanResults, callback: &callback
    ) ? scanResults : nil
  }

  /// Scans all components of the input string `input`, and builds up a map based on the URL's `scheme`.
  ///
  static func scanURLWithScheme(
    _ input: InputSlice, scheme: Scheme, baseURL: NewURL?,
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
        if scheme == baseURL?.schemeKind {
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
    from: ParsableComponent, _ input: InputSlice, scheme: NewURL.Scheme,
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
    _ input: InputSlice, scheme: NewURL.Scheme,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

    // 1. Validate the mapping.
    assert(mapping.usernameEndIndex == nil)
    assert(mapping.passwordEndIndex == nil)
    assert(mapping.hostnameEndIndex == nil)
    assert(mapping.portEndIndex == nil)
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

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
    mapping.authorityStartIndex = authority.startIndex

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
      mapping.usernameEndIndex = username.endIndex
      if username.endIndex != credentials.endIndex {
        mapping.passwordEndIndex = credentials.endIndex
      }
    }

    // 3. Scan the host/port and propagate the continutation advice.
    let hostname = authority[hostStartIndex...]
    guard hostname.isEmpty == false else {
      if scheme.isSpecial {
        callback.validationError(.emptyHostSpecialScheme)
        return .failed
      }
      mapping.hostnameEndIndex = hostStartIndex
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
    assert(mapping.hostnameEndIndex == nil)
    assert(mapping.portEndIndex == nil)
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

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
    mapping.hostnameEndIndex = hostname.endIndex
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
    assert(mapping.portEndIndex == nil)
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

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
    mapping.portEndIndex = portString.endIndex
    return .success(continueFrom: (.pathStart, portString.endIndex))
  }

  /// Scans the URL string from the character immediately following the authority, and advises
  /// whether the remainder is a path, query or fragment.
  ///
  static func scanPathStart(
    _ input: InputSlice, scheme: Scheme, _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

    // 1. Validate the mapping.
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

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
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

    // 2. Find the extent of the path.
    let nextComponentStartIndex = input.firstIndex { ASCII($0) == .questionMark || ASCII($0) == .numberSign }
    let path = input[..<(nextComponentStartIndex ?? input.endIndex)]

    // 3. Validate the path's contents.
    if Callback.self != IgnoreValidationErrors.self {
      PathInputStringValidator.validatePathComponents(pathString: path, schemeKind: scheme, callback: &callback)
    }

    // 4. Return the next component.
    if path.isEmpty && scheme.isSpecial == false {
      mapping.pathEndIndex = nil
    } else {
      mapping.pathEndIndex = path.endIndex
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
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

    // 2. Find the extent of the query
    let queryEndIndex = input.firstIndex { ASCII($0) == .numberSign }

    // 3. Validate the query-string.
    if Callback.self != IgnoreValidationErrors.self {
      validateURLCodePointsAndPercentEncoding(input.prefix(upTo: queryEndIndex ?? input.endIndex), callback: &callback)
    }

    // 3. Return the next component.
    mapping.queryEndIndex = queryEndIndex ?? input.endIndex
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
    assert(mapping.fragmentEndIndex == nil)

    // 2. Validate the fragment string.
    if Callback.self != IgnoreValidationErrors.self {
      validateURLCodePointsAndPercentEncoding(input, callback: &callback)
    }

    mapping.fragmentEndIndex = input.endIndex
    return .success(continueFrom: nil)
  }
}

// MARK: - File URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllFileURLComponents(
    _ input: InputSlice, baseURL: NewURL?,
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
    _ input: InputSlice, baseURL: NewURL?,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

    // Note that file URLs may also be relative URLs. It all depends on what comes after "file:".
    // - 0 slashes:  copy base host, parse as path relative to base path.
    // - 1 slash:    copy base host, parse as absolute path.
    // - 2 slashes:  parse own host, parse absolute path.
    // - 3 slahses:  empty host, parse as absolute path.
    // - 4+ slashes: invalid.

    let baseScheme = baseURL?.schemeKind

    var cursor = input.startIndex
    guard cursor != input.endIndex, let c0 = ASCII(input[cursor]), c0 == .forwardSlash || c0 == .backslash else {
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

    guard cursor != input.endIndex, let c1 = ASCII(input[cursor]), c1 == .forwardSlash || c1 == .backslash else {
      // 1 slash. e.g. "file:/usr/lib/Swift". Absolute path.

      if baseScheme == .file, URLStringUtils.hasWindowsDriveLetterPrefix(input[cursor...]) == false {
        // This string does not begin with a Windows drive letter.
        // If baseURL's path *does*, we are relative to it, rather than being absolute.
        // The appended-path-iteration function handles this case for us, which we opt-in to
        // by having a non-empty path in a special-scheme URL (meaning a guaranteed non-nil path) and
        // including 'path' in 'componentsToCopyFromBase'.
        let basePathStartsWithWindowsDriveLetter: Bool =
          baseURL.map {
            $0.variant.withComponentBytes(.path) {
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


  static func scanFileHost(
    _ input: InputSlice,
    _ mapping: inout UnprocessedMapping, callback: inout Callback
  ) -> ComponentParseResult {

    // 1. Validate the mapping.
    assert(mapping.authorityStartIndex == nil)
    assert(mapping.hostnameEndIndex == nil)
    assert(mapping.portEndIndex == nil)
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

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
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return .success(continueFrom: (.path, input.startIndex))
    }
    if hostname.isEmpty {
      return .success(continueFrom: (.pathStart, input.startIndex))
    }

    // 4. Return the next component.
    mapping.authorityStartIndex = input.startIndex
    mapping.hostnameEndIndex = hostnameEndIndex
    return .success(continueFrom: (.pathStart, hostnameEndIndex))
  }
}

// MARK: - "cannot-base-a-base" URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllCannotBeABaseURLComponents(
    _ input: InputSlice, scheme: NewURL.Scheme,
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
    assert(mapping.authorityStartIndex == nil)
    assert(mapping.hostnameEndIndex == nil)
    assert(mapping.portEndIndex == nil)
    assert(mapping.pathEndIndex == nil)
    assert(mapping.queryEndIndex == nil)
    assert(mapping.fragmentEndIndex == nil)

    // 2. Find the extent of the path.
    let pathEndIndex = input.firstIndex { byte in
      switch ASCII(byte) {
      case .questionMark?, .numberSign?: return true
      default: return false
      }
    }
    let path = input[..<(pathEndIndex ?? input.endIndex)]

    // 3. Validate the path.
    if Callback.self != IgnoreValidationErrors.self {
      validateURLCodePointsAndPercentEncoding(path, callback: &callback)
    }

    // 4. Return the next component.
    if let pathEnd = pathEndIndex {
      mapping.pathEndIndex = pathEnd
      return .success(
        continueFrom: (
          ASCII(input[pathEnd]) == .questionMark ? .query : .fragment, input.index(after: pathEnd)
        ))
    } else {
      mapping.pathEndIndex = path.isEmpty ? nil : input.endIndex
      return .success(continueFrom: nil)
    }
  }
}

// MARK: - Relative URLs.

extension URLScanner {

  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllRelativeURLComponents(
    _ input: InputSlice, baseScheme: NewURL.Scheme,
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
    _ input: InputSlice, baseScheme: NewURL.Scheme,
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
    baseURL: NewURL?,
    callback: inout Callback
  ) -> ParsedURLString<InputString>.ProcessedMapping? {

    assert(checkStructuralInvariants())
    let u_mapping = self  // TODO: This is being kept around temporarily in case I decide to move the function.

    var componentsToCopyFromBase = u_mapping.componentsToCopyFromBase

    let schemeKind: NewURL.Scheme
    if let scannedSchemeKind = u_mapping.schemeKind {
      schemeKind = scannedSchemeKind
    } else if componentsToCopyFromBase.contains(.scheme), let baseURL = baseURL {
      schemeKind = baseURL.schemeKind
    } else {
      preconditionFailure("We must have a scheme")
    }

    // The mapping does not contain full ranges. They must be inferred using our knowledge of URL structure.
    // Some components require additional validation (e.g. the port), and others require adjustments based on
    // full knowledge of the URL string (e.g. if a file URL whose path starts with a Windows drive, clear the host).

    let schemeRange = u_mapping.schemeTerminatorIndex.map { inputString.startIndex..<$0 }
    var usernameRange: Range<InputString.Index>?
    var passwordRange: Range<InputString.Index>?
    var hostnameRange: Range<InputString.Index>?
    var portRange: Range<InputString.Index>?
    let pathRange: Range<InputString.Index>?
    let queryRange: Range<InputString.Index>?
    let fragmentRange: Range<InputString.Index>?

    // Step 1: Extract full ranges.

    var cursor: InputString.Index

    if let authorityStart = u_mapping.authorityStartIndex {
      cursor = authorityStart
      if let usernameEnd = u_mapping.usernameEndIndex {
        usernameRange = cursor..<usernameEnd
        cursor = usernameEnd
        if let passwordEnd = u_mapping.passwordEndIndex {
          assert(inputString[cursor] == ASCII.colon.codePoint)
          cursor = inputString.index(after: cursor)
          passwordRange = cursor..<passwordEnd
          cursor = passwordEnd
        }
        assert(inputString[cursor] == ASCII.commercialAt.codePoint)
        cursor = inputString.index(after: cursor)
      }
      if let hostnameEnd = u_mapping.hostnameEndIndex {
        hostnameRange = cursor..<hostnameEnd
        cursor = hostnameEnd
      }
      if let portEndIndex = u_mapping.portEndIndex {
        assert(inputString[cursor] == ASCII.colon.codePoint)
        cursor = inputString.index(after: cursor)
        portRange = cursor..<portEndIndex
        cursor = portEndIndex
      }
    } else if let schemeRange = schemeRange {
      cursor = inputString.index(after: schemeRange.upperBound)  // ":" scheme separator.
    } else {
      cursor = inputString.startIndex
    }
    if let pathEnd = u_mapping.pathEndIndex {
      pathRange = cursor..<pathEnd
      cursor = pathEnd
    } else {
      pathRange = nil
    }
    if let queryEnd = u_mapping.queryEndIndex {
      assert(inputString[cursor] == ASCII.questionMark.codePoint)
      cursor = inputString.index(after: cursor)  // "?" query separator not included in range.
      queryRange = cursor..<queryEnd
      cursor = queryEnd
    } else {
      queryRange = nil
    }
    if let fragmentEnd = u_mapping.fragmentEndIndex {
      assert(inputString[cursor] == ASCII.numberSign.codePoint)
      cursor = inputString.index(after: cursor)  // "#" fragment separator not included in range.
      fragmentRange = cursor..<fragmentEnd
      cursor = fragmentEnd
    } else {
      fragmentRange = nil
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
    // Even though it may be discarded later by certain file URLs, we still need to do this now to reject invalid hostnames.
    // FIXME: Improve this in the following ways:
    // - Remove the copying to Array
    // - For non-special schemes: calculate the final length and lazily percent-encode in to the new storage.
    // - For ascii hostnames: communicate known final length and lazily lowercase characters
    var hostnameString: String?
    if let hostname = hostnameRange.map({ inputString[$0] }) {
      hostnameString = Array(hostname).withUnsafeBufferPointer { bytes -> String? in
        return WebURL.Host
          .parse(bytes, isNotSpecial: schemeKind.isSpecial == false, callback: &callback)?
          .serialized
      }
      guard hostnameString != nil else { return nil }
    }
    // 2.3: For file URLs whose paths begin with a Windows drive letter, discard the host.
    if schemeKind == .file, var pathContents = pathRange.map({ inputString[$0] }) {
      // The path may or may not be prefixed with a leading slash.
      // Strip it so we can detect the Windows drive letter.
      if let firstChar = pathContents.first, ASCII(firstChar) == .forwardSlash || ASCII(firstChar) == .backslash {
        pathContents = pathContents.dropFirst()
      }
      if URLStringUtils.hasWindowsDriveLetterPrefix(pathContents) {
        if !(hostnameString == nil || hostnameString?.isEmpty == true) {
          callback.validationError(.unexpectedHostFileScheme)
        }
        hostnameString = nil  // file URLs turn 'nil' in to an implicit, empty host.
        componentsToCopyFromBase.remove(.authority)
      }
    }
    // 2.4: For file URLs, replace 'localhost' with an empty/nil host.
    if schemeKind == .file && hostnameString == "localhost" {
      hostnameString = nil  // file URLs turn 'nil' in to an implicit, empty host.
    }

    // Step 3: Construct an absolute URL string from the ranges, as well as the baseURL and components to copy.

    return ParsedURLString<InputString>.ProcessedMapping(
      schemeRange: schemeRange,
      usernameRange: usernameRange,
      passwordRange: passwordRange,
      pathRange: pathRange,
      queryRange: queryRange,
      fragmentRange: fragmentRange,
      hostnameString: hostnameString,
      port: port,
      cannotBeABaseURL: u_mapping.cannotBeABaseURL,
      componentsToCopyFromBase: componentsToCopyFromBase,
      schemeKind: schemeKind
    )
  }

  /// Performs some basic invariant checks on the scanned URL data.
  ///
  func checkStructuralInvariants() -> Bool {

    // We must have a scheme from somewhere.
    if schemeTerminatorIndex == nil {
      guard componentsToCopyFromBase.contains(.scheme) else { return false }
    }
    // Authority components imply the presence of an authorityStartIndex and hostname.
    if usernameEndIndex != nil || passwordEndIndex != nil || hostnameEndIndex != nil || portEndIndex != nil {
      guard hostnameEndIndex != nil else { return false }
      guard authorityStartIndex != nil else { return false }
    }
    // A password implies the presence of a username.
    if passwordEndIndex != nil {
      guard usernameEndIndex != nil else { return false }
    }

    // Ensure components from input string do not overlap with 'componentsToCopyFromBase' (except path).
    if schemeTerminatorIndex != nil {
      // FIXME: Scheme can overlap in relative URLs, but we already test the string and base schemes for equality.
      // guard componentsToCopyFromBase.contains(.scheme) == false else { return false }
    }
    if authorityStartIndex != nil {
      guard componentsToCopyFromBase.contains(.authority) == false else { return false }
    }
    if queryEndIndex != nil {
      guard componentsToCopyFromBase.contains(.query) == false else { return false }
    }
    if fragmentEndIndex != nil {
      guard componentsToCopyFromBase.contains(.fragment) == false else { return false }
    }
    return true
  }
}

// MARK: - Helper functions.

/// Returns the endIndex of the scheme (i.e. index of the scheme terminator ":") if one can be parsed from `input`.
/// Otherwise returns `nil`.
///
private func findScheme<Input>(_ input: Input) -> Input.Index? where Input: Collection, Input.Element == UInt8 {

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

// Note: This considers the percent sign ("%") a valid URL code-point.
//
internal func validateURLCodePointsAndPercentEncoding<Input, Callback>(_ input: Input, callback: inout Callback)
where Input: Collection, Input.Element == UInt8, Callback: URLParserCallback {

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

/// A byte sequence with leading/trailing spaces trimmed, and which lazily skips ASCII newlines and tabs if they are present.
///
struct FilteredURLInput<Base> where Base: BidirectionalCollection, Base.Element == UInt8 {
  let base: Base.SubSequence

  init(_ base: Base.SubSequence) {
    self.base = base
  }
  
  static func trim<Callback: URLParserCallback>(_ rawInput: Base, callback: inout Callback) -> (Base.SubSequence, needsFiltering: Bool) {
    // Trim leading/trailing C0 control characters and spaces.
    var trimmedSlice = rawInput[...]
    let trimmedInput = trimmedSlice.trim {
      switch ASCII($0) {
      case ASCII.ranges.controlCharacters?, .space?: return true
      default: return false
      }
    }
    if trimmedInput.startIndex != trimmedSlice.startIndex || trimmedInput.endIndex != trimmedSlice.endIndex {
      callback.validationError(.unexpectedC0ControlOrSpace)
    }
    trimmedSlice = trimmedInput
    // Trim initial filtered bytes.
    trimmedSlice = trimmedSlice.drop(while: filterShouldDrop)
    return (trimmedSlice, trimmedSlice.contains(where: filterShouldDrop))
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
  subscript(bounds: Range<Base.Index>) -> FilteredURLInput<Base> {
    return FilteredURLInput(base[bounds])
  }

  private var filtered: LazyFilterSequence<Base.SubSequence> {
    return base.lazy.filter { Self.filterShouldDrop($0) == false }
  }
  var count: Int {
    return filtered.count
  }
  var isEmpty: Bool {
    return filtered.isEmpty
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
  func formIndex(after i: inout Base.Index) {
    filtered.formIndex(after: &i)
  }
  func formIndex(before i: inout Base.Index) {
    filtered.formIndex(before: &i)
  }

  // TODO: Investigate adding a custom Iterator once we have a more comprehensive benchmark suite.
}

/// A type which lazily transforms ASCII alpha characters to their lowercase variants.
/// Non-ASCII/non-alpha characters remain unchanged.
///
struct LowercaseASCIITransformer<Base> where Base: Sequence, Base.Element == UInt8 {
  var base: Base
}

extension LowercaseASCIITransformer: Sequence {
  typealias Element = UInt8

  struct Iterator: IteratorProtocol {
    var baseIterator: Base.Iterator
    mutating func next() -> UInt8? {
      let byte = baseIterator.next()
      return ASCII(flatMap: byte)?.lowercased.codePoint ?? byte
    }
  }

  func makeIterator() -> Iterator {
    return Iterator(baseIterator: base.makeIterator())
  }
}

extension LowercaseASCIITransformer: Collection where Base: Collection, Base.Element == UInt8 {

  var startIndex: Base.Index {
    return base.startIndex
  }
  var endIndex: Base.Index {
    return base.endIndex
  }
  var count: Int {
    return base.count
  }
  func index(after i: Base.Index) -> Base.Index {
    return base.index(after: i)
  }
  func distance(from start: Base.Index, to end: Base.Index) -> Int {
    return base.distance(from: start, to: end)
  }
  subscript(position: Base.Index) -> UInt8 {
    let byte = base[position]
    return ASCII(base[position])?.lowercased.codePoint ?? byte
  }
}
