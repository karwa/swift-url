
struct NewURL {
  var storage: Storage = .init(capacity: 0, initialHeader: .init())
}

extension NewURL {
  
  struct Header: InlineArrayHeader {
    var count: UInt16 = 0
    var schemeLength: UInt16 = 0
    
    @_implements(InlineArrayHeader, count)
    var _count: Int {
      get { return Int(count as UInt16) }
      set { count = UInt16(newValue) }
    }
  }
  
  typealias Storage = ArrayWithInlineHeader<Header, UInt8>
  
  func withSchemeBytes<T>(_ perform: (UnsafeBufferPointer<UInt8>)->T) -> T {
    let schemeLength = Int(storage.header.schemeLength)
    return storage.withElements(range: 0..<schemeLength) { perform($0) }
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

/*
 
 Notes about parser implementation
 =================================
 
 - The WHATWG parser has 4 main inputs:
   - The input string
   - A base URL object
   - An existing URL object
   - An optional setter we wish to call (stateOverride).
 
 - What we *would like* to do, is to move the last 2 of these to the construction step.
   
   - Parsing the structure of the input string and only depends on the scheme. We do not need to read/write the entire object.
   - *EXCEPT* Paths. 
 
 - Original idea: split parsing up in to scan & construction steps.
 
    1. Scan. Discover the portions of the input string/base URL/existing URL required to build each piece of the result.
       For example:
       {
         scheme   = baseURL { 0..<5 }
         hostname = baseURL { 5..<20 }
         path     = input   { 0..<20 }
       }
       or (for a '.query' setter):
       {
         scheme   = existing URL { 0..<5 }
         hostname = existing URL { 5..<20 }
         query    = input   { 0..<20 }
       }
 
    2. Construction. Use the information from the scan phase to build the resulting URL. There are two cases to consider:
       
       - In-place mutation. When the
 
 */

struct CompressedOptionalUnsignedInteger<Base: SignedInteger & FixedWidthInteger> {
  private var base: Base
  init() {
    self.base = -1
  }
  var value: Base.Magnitude? {
    get {
      return base < 0 ? nil : base.magnitude
    }
    set {
      guard let newValue = newValue else {
        self.base = -1
        return
      }
      precondition(newValue.magnitude <= Base.Magnitude(1 << (Base.Magnitude.bitWidth - 1)))
      self.base = Base(newValue)
    }
  }
}

struct NewURLParser {
  
  init() {}
  
  struct Mapping<OffsetType: SignedInteger & FixedWidthInteger> {
    var scheme   = CompressedOptionalUnsignedInteger<OffsetType>()
    var username = CompressedOptionalUnsignedInteger<OffsetType>()
    var password = CompressedOptionalUnsignedInteger<OffsetType>()
    var hostname = CompressedOptionalUnsignedInteger<OffsetType>()
    var port = CompressedOptionalUnsignedInteger<OffsetType>()
    var path = CompressedOptionalUnsignedInteger<OffsetType>()
    var query = CompressedOptionalUnsignedInteger<OffsetType>()
    var fragment = CompressedOptionalUnsignedInteger<OffsetType>()
    var cannotBeABaseURL = false
  }
  
  /// Constructs a new URL from the given input string, interpreted relative to the given (optional) base URL.
  ///
	func constructURL<Input>(
    input: Input,
    baseURL: NewURL?
  ) -> NewURL? where Input: BidirectionalCollection, Input.Element == UInt8, Input.Index: FixedWidthInteger {
    
    // There are 2 phases to constructing a new URL: scanning and construction.
    //
    // - Scanning:     Determine if the input is at all parseable, and which parts of `input`
    //                 contribute to which components.
    // - Construction: Use the information from the scanning step, together with the base URL,
    //                 to transform and copy the pieces of each component in to a final result.
  
    guard let scanResults = URLScanner.scan(rawInput: input[...], baseURL: baseURL, offsetType: Int16.self, stateOverride: nil) else {
      return nil
    }
    return construct(url: scanResults, input: input, baseURL: baseURL)
  }
  
  func construct<Input, OffsetType>(
    url: Mapping<OffsetType>,
    input: Input,
    baseURL: NewURL?
  ) -> NewURL? {
    
    return nil
  }
}


struct URLScanner<Input, Offset> where Input: BidirectionalCollection, Input.SubSequence == Input, Input.Element == UInt8,
  Input.Index: FixedWidthInteger, Offset: FixedWidthInteger & SignedInteger {
  
  enum ComponentParseResult {
    case failed
    case success(continueFrom: (ParsableComponent, Input.Index)?)
  }
  
  typealias Scheme = NewURLParser.Scheme
  typealias Mapping = NewURLParser.Mapping<Offset>
}

extension URLScanner {
  
  /// The first stage is scanning, where we want to build up a map of the resulting URL's components.
  /// This will tell us whether the URL is structurally invalid, although it may still fail to normalize if the domain name is nonsense.
  ///
  static func scan(
    rawInput: Input,
    baseURL: NewURL?,
    offsetType: Offset.Type,
    stateOverride: WebURLParser.ParserState? = nil
  ) -> Mapping? {
    
    // Create the result object.
    var scanResults = Mapping()
    
    // 1. Trim leading/trailing C0 control characters and spaces.
    var trimmedSlice = rawInput[...]
    if stateOverride == nil {
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
    
    // 2. Filter all ASCII newlines and tabs.
    let input = trimmedSlice.lazy.filter { ASCII($0) != .horizontalTab && ASCII($0) != .lineFeed }

    // TODO: 3. Skip to unicode code-point boundaries.
        
    let success: Bool
    // 4. Try to parse a scheme.
    if let schemeEndIndex = tryParseScheme(input: input) {
      scanResults.scheme.value = numericCast(schemeEndIndex)
      let schemeNameBytes = input[..<schemeEndIndex].dropLast() // dropLast() to remove the ":" terminator.
      let scheme = NewURLParser.Scheme.parse(asciiBytes: schemeNameBytes)
      print("Found scheme!", scheme)
      
      success = URLScanner<LazyFilterSequence<Input>, Offset>.scanURLWithScheme(input[schemeEndIndex...], scheme: scheme, baseURLScheme: baseURL?.scheme, &scanResults)
      
    } else { // no scheme.

      guard let base = baseURL else {
//        callback.validationError(.missingSchemeNonRelativeURL)
        return nil
      }
      guard base.cannotBeABaseURL == false else {
        guard ASCII(flatMap: input.first) == .numberSign else {
//          callback.validationError(.missingSchemeNonRelativeURL)
          return nil
        }
        // FIXME: We need to communicate this to the 'construction' stage.
//        url.scheme = base.scheme
//        url.path = base.path
//        url.query = base.query
//        url.fragment = ""
//        url.cannotBeABaseURL = true
        if case .failed = URLScanner<LazyFilterSequence<Input>, Offset>.scanFragment(input.dropFirst(), &scanResults) {
          success = false
        } else {
          success = true
        }
        return success ? scanResults : nil
      }
      if base.scheme == .file {
        success = parseFileURL(input)
      } else {
        success = parseRelativeURL(input)
      }
    }
    
    // End parse function.
    return success ? scanResults : nil
  }
}

/// Returns the endIndex of the scheme (i.e. index of the scheme terminator ":") if one can be parsed from `input`.
/// Otherwise returns `nil`.
///
private func tryParseScheme<Input>(
  input: Input
) -> Input.Index? where Input: Collection, Input.Element == UInt8 {
  
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

// URLs with schemes.
// ------------------
// Broadly, the pattern is to look for an authority (host, etc), then path, query and fragment.

extension URLScanner {
  
  /// Scans all components of the input string `input`, and builds up a map based on the URL's `scheme`.
  ///
  static func scanURLWithScheme(_ input: Input, scheme: NewURLParser.Scheme, baseURLScheme: NewURLParser.Scheme?, _ mapping: inout Mapping) -> Bool {

    switch scheme {
    case .file:
      if !URLStringUtils.hasDoubleSolidusPrefix(input) {
//          callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return parseFileURL(input)
      
    case .other: // non-special.
      var componentStartIdx = input.startIndex
      guard componentStartIdx != input.endIndex, ASCII(input[componentStartIdx]) == .forwardSlash else {
        mapping.cannotBeABaseURL = true
        return parseCannotBeABaseURLPath(input)
      }
      // state: "path or authority"
      componentStartIdx = input.index(after: componentStartIdx)
      if componentStartIdx != input.endIndex, ASCII(input[componentStartIdx]) == .forwardSlash {
        let authorityStart = input.index(after: componentStartIdx)
        return scanComponents(from: .authority, input[authorityStart...], scheme: scheme, &mapping)
      } else {
        return scanComponents(from: .path, input[componentStartIdx...], scheme: scheme, &mapping)
      }
        
    default: // special schemes other than 'file'.
      if scheme == baseURLScheme, URLStringUtils.hasDoubleSolidusPrefix(input) == false {
        // state: "special relative or authority"
        // callback.validationError(.relativeURLMissingBeginningSolidus)
        return parseRelativeURL(input)
      }
      // state: "special authority slashes"
      var authorityStart = input.startIndex
      if URLStringUtils.hasDoubleSolidusPrefix(input) {
        authorityStart = input.index(authorityStart, offsetBy: 2)
      } else {
        // callback.validationError(.missingSolidusBeforeAuthority)
      }
      // state: "special authority ignore slashes"
      authorityStart = input[authorityStart...].drop { ASCII($0) == .forwardSlash || ASCII($0) == .backslash }.startIndex
      return scanComponents(from: .authority, input[authorityStart...], scheme: scheme, &mapping)
    }
  }
  
  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanComponents(from: ParsableComponent, _ input: Input, scheme: NewURLParser.Scheme, _ mapping: inout Mapping) -> Bool {
    var component = from
    var remaining = input[...]
    while true {
      print("** Parsing component: \(component)")
      print("** Data: \(String(decoding: remaining, as: UTF8.self))")
      let componentResult: ComponentParseResult
      switch component {
      case .authority:
        componentResult = scanAuthority(remaining, scheme: scheme, &mapping)
      case .pathStart:
        componentResult = scanPathStart(remaining, scheme: scheme, &mapping)
      case .path:
        componentResult = scanPath(remaining, scheme: scheme, &mapping)
      case .query:
        componentResult = scanQuery(remaining, scheme: scheme, &mapping)
      case .fragment:
        componentResult = scanFragment(remaining, &mapping)
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
  static func scanAuthority(_ input: Input, scheme: NewURLParser.Scheme,_ mapping: inout Mapping) -> ComponentParseResult {
     
      // 1. Find the extent of the authority (i.e. the terminator between host and path/query/fragment).
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

      var hostStartIndex = authority.startIndex
      
      // 2. Look for credentials.
      if let credentialsEndIndex = authority.lastIndex(where: { ASCII($0) == .commercialAt }) {
        hostStartIndex = input.index(after: credentialsEndIndex)
        // callback.validationError(.unexpectedCommercialAt)
        guard credentialsEndIndex != authority.startIndex else {
          // callback.validationError(.missingCredentials)
          return .failed
        }

        let credentials = authority[..<credentialsEndIndex]
        let username = credentials.prefix { ASCII($0) != .colon }
        let password = credentials.suffix(from: credentials.index(after: username.endIndex))
        
        print("username: ", String(decoding: username, as: UTF8.self))
        print("password: ", String(decoding: password, as: UTF8.self))
      }
      
      // 3. Parse the host.
      if hostStartIndex == authority.endIndex {
        // Host is empty.
        if scheme.isSpecial {
          // callback.validationError(.emptyHostSpecialScheme)
          return .failed
        }
        mapping.hostname.value = 0
      } else {
        // TODO: Handle port here perhaps?
        guard case .success = scanHost(authority[hostStartIndex...], scheme: scheme, &mapping) else {
          return .failed
        }
      }
      
      // 4. Return the next component.
      return .success(continueFrom: (.pathStart, authority.endIndex))
  }
  
  static func scanHost(_ input: Input, scheme: Scheme, _ mapping: inout Mapping) -> ComponentParseResult {
      // TODO: parse port.
      
      // swift-format-ignore
      guard let parsedHost = Array(input).withUnsafeBufferPointer({ buffer -> WebURLParser.Host? in
        var fakecallback = IgnoreValidationErrors()
        return WebURLParser.Host.parse(buffer, isNotSpecial: scheme.isSpecial == false, callback: &fakecallback)
      }) else {
        return .failed
      }
      
      print("host: \(parsedHost)")
      return .success(continueFrom: nil) // ?
  }

  /// Scans the URL string from the character immediately following the authority, and advises
  /// whether the remainder is a path, query or fragment.
  ///
  static func scanPathStart(_ input: Input, scheme: Scheme, _ mapping: inout Mapping) -> ComponentParseResult {
      
      guard input.isEmpty == false else {
        return .success(continueFrom: scheme.isSpecial ? (.path, input.startIndex) : nil)
      }
      
      let c: ASCII? = ASCII(input[input.startIndex])
      switch c {
      case .questionMark?:
        return .success(continueFrom: (.query, input.index(after: input.startIndex)))
        
      case .numberSign?:
        return .success(continueFrom: (.fragment, input.index(after: input.startIndex)))
        
      default:
        if c == .forwardSlash || (scheme.isSpecial && c == .backslash) {
          if c == .backslash {
            // callback.validationError(.unexpectedReverseSolidus)
          }
          return .success(continueFrom: (.path, input.index(after: input.startIndex)))
        } else {
          return .success(continueFrom: (.path, input.startIndex))
        }
      }
  }

  /// Scans a URL path string from the given input, and advises whether there are any components following it.
  ///
  static func scanPath(_ input: Input, scheme: Scheme, _ mapping: inout Mapping) -> ComponentParseResult {
      
      // 1. Find the extent of the path.
      let pathEndIndex = input.firstIndex { ASCII($0) == .questionMark || ASCII($0) == .numberSign }
      
      // 2. Validate the path's contents.
      let path = input[..<(pathEndIndex ?? input.endIndex)]
      
      func isPathComponentTerminator(_ byte: UInt8) -> Bool {
        return ASCII(byte) == .forwardSlash || (scheme.isSpecial && ASCII(byte) == .backslash)
      }
      func validatePathComponent(_ pathComponent: Input.SubSequence) {
        if URLStringUtils.hasNonURLCodePoints(pathComponent, allowPercentSign: true) {
          // callback.validationError(.invalidURLCodePoint)
        }
        // Validate percent escaping.
        var percentSignSearchIdx = pathComponent.startIndex
        while let percentSignIdx = pathComponent[percentSignSearchIdx...].firstIndex(where: { ASCII($0) == .percentSign }) {
          percentSignSearchIdx = pathComponent.index(after: percentSignIdx)
          let nextTwo = pathComponent[percentSignIdx...].prefix(2)
          if nextTwo.count != 2 || !nextTwo.allSatisfy({ ASCII($0)?.isHexDigit ?? false }) {
            // callback.validationError(.unescapedPercentSign)
          }
        }
        print("path component: \(String(decoding: pathComponent, as: UTF8.self))")
      }
      
      var componentStartIdx = path.startIndex
      while let componentEndIndex = path[componentStartIdx...].firstIndex(where: isPathComponentTerminator) {
        if ASCII(path[componentEndIndex]) == .backslash {
          //  callback.validationError(.unexpectedReverseSolidus)
        }
        validatePathComponent(path[componentStartIdx..<componentEndIndex])
        componentStartIdx = path.index(after: componentEndIndex)
      }
      validatePathComponent(path[componentStartIdx..<path.endIndex])
        
      // 3. Return the next component.
      if let pathEnd = pathEndIndex {
        return .success(continueFrom: (ASCII(input[pathEnd]) == .questionMark ? .query : .fragment,
                                       input.index(after: pathEnd)))
      } else {
        return .success(continueFrom: nil)
      }
  }
  
  /// Scans a URL query string from the given input, and advises whether there are any components following it.
  ///
  static func scanQuery(_ input: Input, scheme: Scheme, _ mapping: inout Mapping) -> ComponentParseResult {
      
    // 1. Find the extent of the query
    let queryEndIndex = input.firstIndex { ASCII($0) == .numberSign }
      
    // 2. Validate the query components.
      
    // 3. Return the next component.
    if let queryEnd = queryEndIndex {
      return .success(continueFrom: ASCII(input[queryEnd]) == .numberSign ? (.fragment, input.index(after: queryEnd)) : nil)
    } else {
      return .success(continueFrom: nil)
    }
  }
  
  /// Scans a URL fragment string from the given input. There are never any components following it.
  ///
  static func scanFragment(_ input: Input, _ mapping: inout Mapping) -> ComponentParseResult {
        
    return .success(continueFrom: nil)
  }
}

// File URLs.
// ---------

extension URLScanner {
  
  static func parseFileURL<T>(_: T) -> Bool {
    print("Reached file URL")
    return true
  }
}

// Relative and "cannot-base-a-base" URLs.
// --------------------------------------

extension URLScanner {

  static func parseCannotBeABaseURLPath<T>(_: T) -> Bool {
    print("Reached cannot-be-a-base-url-path")
    return true
  }
  
  static func parseRelativeURL<T>(_: T) -> Bool {
    print("Reached relative URL")
    return true
  }
}

// Component parsing.














extension NewURL {
  
  var scheme: NewURLParser.Scheme {
    return .other
  }
  
  var cannotBeABaseURL: Bool {
    return false
  }
}
