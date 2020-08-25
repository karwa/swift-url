
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

// --------------------------------
// Compressed optionals
// --------------------------------
// Unused right now, but the idea is that instead of having Mapping<Input.Index>, we'd
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
  static var none: Optional<Wrapped> {
    return nil
  }
  func get() -> Wrapped? {
    return self
  }
  mutating func set(to newValue: Wrapped?) {
    self = newValue
  }
}

struct CompressedOptionalUnsignedInteger<Base: SignedInteger & BinaryInteger & FixedWidthInteger>: CompressedOptional {
  private var base: Base
  init() {
    self.base = -1
  }
  
  typealias Wrapped = Base
  static var none: Self {
    return Self()
  }
  func get() -> Wrapped? {
    return base >= 0 ? base : nil
  }
  mutating func set(to newValue: Wrapped?) {
    guard let newValue = newValue else {
      self.base = -1
      return
    }
    precondition(newValue.magnitude <= Base.Magnitude(1 << (Base.Magnitude.bitWidth - 1)))
    self.base = newValue
  }
}

struct Mapping<IndexStorage: CompressedOptional> {
  typealias Index = IndexStorage.Wrapped
  
  var cannotBeABaseURL = false
  
  var scheme: NewURLParser.Scheme? = nil
  // This is the index of the scheme terminator (":"), if one exists.
  var schemeTerminator = IndexStorage.none
  
  // This is the index of the first character of the authority segment, if one exists.
  // The scheme and authority may be separated by an arbitrary amount of trivia.
  // The authority ends at the "*EndIndex" of the last of its components.
  var authorityStartPosition = IndexStorage.none
  
    // This is the endIndex of the authority's username component, if one exists.
    // The username starts at the authorityStartPosition.
    var usernameEndIndex = IndexStorage.none
  
    // This is the endIndex of the password, if one exists.
    // If a password exists, a username must also exist, and usernameEndIndex must be the ":" character.
    // The password starts at the index after usernameEndIndex.
    var passwordEndIndex = IndexStorage.none

// TODO (hostname): What if there is no authorityStartPosition? Is it guaranteed to be set?
  
    // This is the endIndex of the hostname, if one exists.
    // The hostname starts at the index after (username/password)EndIndex,
    // or from authorityStartPosition if there are no credentials.
    var hostnameEndIndex = IndexStorage.none
  
    // This is the endIndex of the port-string, if one exists.
    // If a port-string exists, a hostname must also exist, and hostnameEndIndex must be the ":" character.
    // The port-string starts at the index after hostnameEndIndex.
    var portEndIndex = IndexStorage.none
  
  // This is the endIndex of the path, if one exists.
  // If an authority segment exists, the path starts at the index after the end of the authority.
  // Otherwise, it starts at the index 2 places after 'schemeTerminator' (":" + "/" or "\").
  var path = IndexStorage.none
  
  var query = IndexStorage.none
  var fragment = IndexStorage.none
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
    
    var callback = CollectValidationErrors()
  
    guard let scanResults = scanURL(filteredInput, baseURL: baseURL,
                                    mappingType: Mapping<Optional<Input.Index>>.self, stateOverride: nil,
                                    callback: &callback) else {
      return nil
    }
    
    print("")
    print("Scanning Errors:")
    print("-----------------------------------------")
    callback.errors.forEach { print($0.description); print("---") }
    print("-----------------------------------------")
    print("")
    callback.errors.removeAll(keepingCapacity: true)
    
    let result = construct(url: scanResults, input: filteredInput, baseURL: baseURL, callback: &callback)
    
    print("")
    print("Construction Errors:")
    print("-----------------------------------------")
    callback.errors.forEach { print($0.description); print("---") }
    print("-----------------------------------------")
    print("")
    
    return result
  }
  
  func construct<Input, T, Callback>(
    url: Mapping<T>,
    input: FilteredURLInput<Input>,
    baseURL: NewURL?,
    callback: inout Callback
  ) -> NewURL? where Mapping<T>.Index == Input.Index, Callback: URLParserCallback {
    
    let schemeRange = url.schemeTerminator.get().map { input.startIndex..<$0 }
    var usernameRange: Range<Input.Index>?
    var passwordRange: Range<Input.Index>?
    var hostnameRange: Range<Input.Index>?
    var port: UInt16?

    var cursor = schemeRange?.upperBound ?? input.startIndex
    
    if let authorityStart = url.authorityStartPosition.get() {
      cursor = authorityStart
      if let usernameEnd = url.usernameEndIndex.get() {
        usernameRange = cursor..<usernameEnd
        cursor = input.index(after: usernameEnd)
        
        if let passwordEnd = url.passwordEndIndex.get() {
          assert(input[usernameEnd] == ASCII.colon.codePoint)
          passwordRange = cursor..<passwordEnd
          cursor = input.index(after: passwordEnd)
          assert(input[passwordEnd] == ASCII.commercialAt.codePoint)
        } else {
          assert(input[usernameEnd] == ASCII.commercialAt.codePoint)
        }
      }
      
      hostnameRange = url.hostnameEndIndex.get().map { hostnameEndIndex in
        cursor..<hostnameEndIndex
      }
      cursor = hostnameRange.map { $0.upperBound } ?? cursor
      
      if let portStringEndIndex = url.portEndIndex.get() {
        cursor = input.index(after: cursor) // ":" hostname separator.
        if portStringEndIndex != cursor {
          guard let parsedInteger = UInt16(String(decoding: input[cursor..<portStringEndIndex], as: UTF8.self)) else {
            callback.validationError(.portOutOfRange)
            return nil
          }
          port = parsedInteger
          cursor = portStringEndIndex
        }
      }
    } else {
      print("NO AUTHORITY!!! 🤟")
    }
    
    let pathRange = url.path.get().map { pathEndIndex -> Range<Input.Index> in
      cursor = input.index(after: cursor) // "/" or "\" path separator.
      defer { cursor = pathEndIndex }
      return cursor..<pathEndIndex
    }
    let queryRange = url.query.get().map { queryEndIndex -> Range<Input.Index> in
      cursor = input.index(after: cursor) // "?" query separator.
      defer { cursor = queryEndIndex }
      return cursor..<queryEndIndex
    }
    let fragmentRange = url.fragment.get().map { fragmentEndIndex -> Range<Input.Index> in
      cursor = input.index(after: cursor) // "#" fragment separator.
      defer { cursor = fragmentEndIndex }
      return cursor..<fragmentEndIndex
    }
        
    print("""
      scheme object: \(url.scheme as Any?)
      
      scheme: \( schemeRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      username: \( usernameRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      password: \( passwordRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      hostname: \( hostnameRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      port: \( port.map { String($0) } ?? "<nil>" )
      
      path: \( pathRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      query: \( queryRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      fragment: \( fragmentRange.map { String(decoding: input[$0], as: UTF8.self) } ?? "<nil>" )
      
      remaining: \( String(decoding: input[cursor...], as: UTF8.self) )
    """)
    
    return nil
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
  var base: LazyFilterSequence<Base.SubSequence>
  
  init(_ rawInput: Base, isSetterMode: Bool) {
    // 1. Trim leading/trailing C0 control characters and spaces.
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
    
    // 2. Filter all ASCII newlines and tabs.
    let input = trimmedSlice.lazy.filter { ASCII($0) != .horizontalTab && ASCII($0) != .lineFeed }

    // TODO: 3. Skip to unicode code-point boundaries.
    
    self.base = input
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
  var count: Int {
    return base.count
  }
  func index(after i: Base.Index) -> Base.Index {
    return base.index(after: i)
  }
  func index(before i: Base.Index) -> Base.Index {
    return base.index(before: i)
  }
  func index(_ i: Base.Index, offsetBy distance: Int, limitedBy limit: Base.Index) -> Base.Index? {
    return base.index(i, offsetBy: distance, limitedBy: limit)
  }
  func distance(from start: Base.Index, to end: Base.Index) -> Int {
    return base.distance(from: start, to: end)
  }
  subscript(position: Base.Index) -> UInt8 {
    return base[position]
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
  mappingType: Mapping<T>.Type,
  stateOverride: WebURLParser.ParserState? = nil,
  callback: inout Callback
) -> Mapping<T>? where Mapping<T>.Index == Input.Index, Callback: URLParserCallback {
  
  var scanResults = Mapping<T>()
  let success: Bool
  
  // Try to parse a scheme.
  if let schemeEndIndex = findScheme(input) {
    let schemeNameBytes = input[..<schemeEndIndex].dropLast() // dropLast() to remove the ":" terminator.
    let scheme = NewURLParser.Scheme.parse(asciiBytes: schemeNameBytes)
    
    scanResults.scheme = scheme
    scanResults.schemeTerminator.set(to: input.index(before: schemeEndIndex))
    success = URLScanner.scanURLWithScheme(input[schemeEndIndex...], scheme: scheme, baseURLScheme: baseURL?.scheme, &scanResults, callback: &callback)
    
  } else {

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
      if case .failed = URLScanner.scanFragment(input.dropFirst(), &scanResults, callback: &callback) {
        success = false
      } else {
        success = true
      }
      return success ? scanResults : nil
    }
    if base.scheme == .file {
      success = URLScanner<Slice<FilteredURLInput<Input>>, T, Callback>.scanAllFileURLComponents(input[...], baseScheme: base.scheme, &scanResults, callback: &callback)
    } else {
      success = URLScanner<Slice<FilteredURLInput<Input>>, T, Callback>.parseRelativeURL(input[...])
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

struct URLScanner<Input, T, Callback> where Input: BidirectionalCollection, Input.Element == UInt8, Input.SubSequence == Input,
Mapping<T>.Index == Input.Index, Callback: URLParserCallback {
  
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
  static func scanURLWithScheme(_ input: Input, scheme: NewURLParser.Scheme, baseURLScheme: NewURLParser.Scheme?, _ mapping: inout Mapping<T>,
                                callback: inout Callback) -> Bool {

    switch scheme {
    case .file:
      if !URLStringUtils.hasDoubleSolidusPrefix(input) {
      	callback.validationError(.fileSchemeMissingFollowingSolidus)
      }
      return scanAllFileURLComponents(input, baseScheme: baseURLScheme, &mapping, callback: &callback)
      
    case .other: // non-special.
      var componentStartIdx = input.startIndex
      guard componentStartIdx != input.endIndex, ASCII(input[componentStartIdx]) == .forwardSlash else {
        mapping.cannotBeABaseURL = true
        if case .failed = scanCannotBeABaseURLPath(input, &mapping, callback: &callback) {
          return false
        }
        return true
      }
      // state: "path or authority"
      componentStartIdx = input.index(after: componentStartIdx)
      if componentStartIdx != input.endIndex, ASCII(input[componentStartIdx]) == .forwardSlash {
        let authorityStart = input.index(after: componentStartIdx)
        return scanAllComponents(from: .authority, input[authorityStart...], scheme: scheme, &mapping, callback: &callback)
      } else {
        return scanAllComponents(from: .path, input[componentStartIdx...], scheme: scheme, &mapping, callback: &callback)
      }
        
    default: // special schemes other than 'file'.
      if scheme == baseURLScheme, URLStringUtils.hasDoubleSolidusPrefix(input) == false {
        // state: "special relative or authority"
        callback.validationError(.relativeURLMissingBeginningSolidus)
        return parseRelativeURL(input)
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
  static func scanAllComponents(from: ParsableComponent, _ input: Input, scheme: NewURLParser.Scheme, _ mapping: inout Mapping<T>,
                                callback: inout Callback) -> Bool {
    var component = from
    var remaining = input[...]
    while true {
      print("** Parsing component: \(component)")
      print("** Data: \(String(decoding: remaining, as: UTF8.self))")
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
  static func scanAuthority(_ input: Input, scheme: NewURLParser.Scheme,_ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
     
    // 1. Validate the mapping.
    assert(mapping.usernameEndIndex.get() == nil)
    assert(mapping.passwordEndIndex.get() == nil)
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
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
    mapping.authorityStartPosition.set(to: authority.startIndex)

    var hostStartIndex = authority.startIndex
    
    // 3. Find the extent of the credentials, if there are any.
    if let credentialsEndIndex = authority.lastIndex(where: { ASCII($0) == .commercialAt }) {
      hostStartIndex = input.index(after: credentialsEndIndex)
      callback.validationError(.unexpectedCommercialAt)
      guard credentialsEndIndex != authority.startIndex else {
        callback.validationError(.missingCredentials)
        return .failed
      }

      let credentials = authority[..<credentialsEndIndex]
      let username = credentials.prefix { ASCII($0) != .colon }
      let password = credentials.suffix(from: credentials.index(after: username.endIndex))
  
      mapping.usernameEndIndex.set(to: username.endIndex)
      if password.isEmpty == false {
        mapping.passwordEndIndex.set(to: password.endIndex)
      }
    }
    
    // 3. Scan the host/port and propagate the continutation advice.
    let hostname = authority[hostStartIndex...]
    guard hostname.isEmpty == false else {
      if scheme.isSpecial {
        callback.validationError(.emptyHostSpecialScheme)
        return .failed
      }
      mapping.hostnameEndIndex.set(to: authority.endIndex)
      return .success(continueFrom: (.pathStart, authority.endIndex))
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
  
  static func scanHostname(_ input: Input, scheme: Scheme, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
    // 2. Find the extent of the hostname.
    var hostnameEndIndex: Input.Index?
    var inBracket = false
    colonSearch: for idx in input.indices {
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
    }
    let hostname = input[..<(hostnameEndIndex ?? input.endIndex)]
    
    // 3. Validate the hostname.
    // swift-format-ignore
    guard let _ = Array(hostname).withUnsafeBufferPointer({ buffer -> WebURLParser.Host? in
      return WebURLParser.Host.parse(buffer, isNotSpecial: scheme.isSpecial == false, callback: &callback)
    }) else {
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
  
  static func scanPort(_ input: Input, scheme: Scheme, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
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
  static func scanPathStart(_ input: Input, scheme: Scheme, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
      
    // 1. Validate the mapping.
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
    // 2. Return the component to parse based on input.
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
          callback.validationError(.unexpectedReverseSolidus)
        }
        return .success(continueFrom: (.path, input.index(after: input.startIndex)))
      } else {
        return .success(continueFrom: (.path, input.startIndex))
      }
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
  static func scanPath(_ input: Input, scheme: Scheme, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
    // 2. Find the extent of the path.
    let pathEndIndex = input.firstIndex { ASCII($0) == .questionMark || ASCII($0) == .numberSign }
    let path = input[..<(pathEndIndex ?? input.endIndex)]

    // 3. Validate the path's contents.
    func isPathComponentTerminator(_ byte: UInt8) -> Bool {
      return ASCII(byte) == .forwardSlash || (scheme.isSpecial && ASCII(byte) == .backslash)
    }
    
    var componentStartIdx = path.startIndex
    while let componentTerminatorIndex = path[componentStartIdx...].firstIndex(where: isPathComponentTerminator) {
      if ASCII(path[componentTerminatorIndex]) == .backslash {
        callback.validationError(.unexpectedReverseSolidus)
      }
      let pathComponent = path[componentStartIdx..<componentTerminatorIndex]
      validateURLCodePointsAndPercentEncoding(pathComponent, callback: &callback)
      componentStartIdx = path.index(after: componentTerminatorIndex)
      
      print("path component: \(String(decoding: pathComponent, as: UTF8.self))")
    }
    validateURLCodePointsAndPercentEncoding(path[componentStartIdx...], callback: &callback)
    print("path component: \(String(decoding: path[componentStartIdx...], as: UTF8.self))")
      
    // 4. Return the next component.
    mapping.path.set(to: path.endIndex)
    if let pathEnd = pathEndIndex {
      return .success(continueFrom: (ASCII(input[pathEnd]) == .questionMark ? .query : .fragment,
                                     input.index(after: pathEnd)))
    } else {
      return .success(continueFrom: nil)
    }
  }
  
  /// Scans a URL query string from the given input, and advises whether there are any components following it.
  ///
  static func scanQuery(_ input: Input, scheme: Scheme, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
    // 2. Find the extent of the query
    let queryEndIndex = input.firstIndex { ASCII($0) == .numberSign }
      
    // 3. Validate the query-string.
    validateURLCodePointsAndPercentEncoding(input.prefix(upTo: queryEndIndex ?? input.endIndex), callback: &callback)
      
    // 3. Return the next component.
    mapping.query.set(to: queryEndIndex ?? input.endIndex)
    if let queryEnd = queryEndIndex {
      return .success(continueFrom: ASCII(input[queryEnd]) == .numberSign ? (.fragment, input.index(after: queryEnd)) : nil)
    } else {
      return .success(continueFrom: nil)
    }
  }
  
  /// Scans a URL fragment string from the given input. There are never any components following it.
  ///
  static func scanFragment(_ input: Input, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.fragment.get() == nil)
    
    // 2. Validate the fragment string.
    validateURLCodePointsAndPercentEncoding(input, callback: &callback)
    
    mapping.fragment.set(to: input.endIndex)
    return .success(continueFrom: nil)
  }
}

// File URLs.
// ---------

extension URLScanner {
  
  /// Scans the given component from `input`, and continues scanning additional components until we can't find any more.
  ///
  static func scanAllFileURLComponents(_ input: Input, baseScheme: NewURLParser.Scheme?, _ mapping: inout Mapping<T>, callback: inout Callback) -> Bool {
    var remaining = input[...]
    
    guard case .success(let _component) = parseFileURLStart(remaining, baseScheme: baseScheme, &mapping, callback: &callback) else {
      return false
    }
    guard var component = _component else {
      return true
    }
    remaining = input.suffix(from: component.1)
    while true {
      print("** [FILEURL] Parsing component: \(component)")
      print("** [FILEURL] Data: \(String(decoding: remaining, as: UTF8.self))")
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
  
  static func parseFileURLStart(_ input: Input, baseScheme: NewURLParser.Scheme?, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    print("Reached file URL")
    
//    guard input.isEmpty == false else {
//      return .success(continueFrom: nil)
//    }
    
    // After "file:"
    // - 0 slashes:  copy base host, append path to base path.
    // - 1 slash:    copy base host, parse own path.
    // - 2 slashes:  parse own host, parse own path.
    // - 3 slahses:  empty host, parse own path.
    // - 4+ slashes: invalid.
    
    var cursor = input.startIndex
    guard cursor != input.endIndex, let c0 = ASCII(input[cursor]), (c0 == .forwardSlash || c0 == .backslash) else {
      // No slashes. e.g. "file:usr/lib/Swift" or "file:?someQuery".
      guard baseScheme == .file else {
        return .success(continueFrom: (.path, cursor))
      }
      // TODO: Propagate this to construction phase.
//      url.host = base.host
//      url.path = base.path
//      url.query = base.query
      guard cursor != input.endIndex else {
        return .success(continueFrom: nil)
      }
      switch ASCII(input[cursor]) {
      case .questionMark?:
        return .success(continueFrom: (.query, input.index(after: cursor)))
      case .numberSign?:
        return .success(continueFrom: (.fragment, input.index(after: cursor)))
      default:
        if URLStringUtils.hasWindowsDriveLetterPrefix(input[cursor...]) {
          callback.validationError(.unexpectedWindowsDriveLetter)
        } else {
          // TODO: Propagate this to construction phase.
          // shortenURLPath(&url.path, isFileScheme: true)
        }
        return .success(continueFrom: (.path, cursor))
      }
    }
    cursor = input.index(after: cursor)
    if c0 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    
    guard cursor != input.endIndex, let c1 = ASCII(input[cursor]), (c1 == .forwardSlash || c1 == .backslash) else {
      // 1 slash. e.g. "file:/usr/lib/Swift".
      
      // If the base path starts with a Windows drive letter and we *dont't*, the path is relative
      // to the base URL's Windows drive:
      // ("file:/Users", base: "file:///C/Windows")     -> "file:///Users"
      // ("file:/Users", base: "file:///C:/Windows")    -> "file:///C:/Users"
      // ("file:/D:/Users", base: "file:///C:/Windows") -> "file:///D:/Users"
      if baseScheme == .file, URLStringUtils.hasWindowsDriveLetterPrefix(input[cursor...]) == false {
//        if let basePathStart = base.path.first, URLStringUtils.isNormalisedWindowsDriveLetter(basePathStart.utf8) {
//          url.path.append(basePathStart)
//        } else {
//          url.host = base.host
//        }
      }
      return scanPath(input[cursor...], scheme: .file, &mapping, callback: &callback)
    }
    
    cursor = input.index(after: cursor)
    if c1 == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    
    // 2+ slashes. e.g. "file://localhost/usr/lib/Swift" or "file:///usr/lib/Swift".
    return scanFileHost(input[cursor...], &mapping, callback: &callback)
  }
  
  
  static func scanFileHost(_ input: Input, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
   
    // 1. Validate the mapping.
    assert(mapping.authorityStartPosition.get() == nil)
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
    // 2. Find the extent of the hostname.
    let hostnameEndIndex = input.firstIndex { byte in
      switch ASCII(byte) {
      case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
      default: return false
      }
    } ?? input.endIndex
    
    let hostname = input[..<hostnameEndIndex]
    
    // 3. Validate the hostname.
    if URLStringUtils.isWindowsDriveLetter(hostname) {
      // TODO: Only if not in setter-mode.
      callback.validationError(.unexpectedWindowsDriveLetterHost)
      return .success(continueFrom: (.path, input.startIndex))
    }
    if hostname.isEmpty {
      return .success(continueFrom: (.pathStart, input.startIndex))
    }
    // swift-format-ignore
    guard let parsedHost = Array(hostname).withUnsafeBufferPointer({ buffer -> WebURLParser.Host? in
      return WebURLParser.Host.parse(buffer, isNotSpecial: false, callback: &callback)
    }) else {
      return .failed
    }
    
    // 4. Return the next component.
    mapping.authorityStartPosition.set(to: input.startIndex)
    if parsedHost != .domain("localhost") {
      mapping.hostnameEndIndex.set(to: hostnameEndIndex)
    }
    return .success(continueFrom: (.pathStart, hostnameEndIndex))
  }
}

// "cannot-base-a-base" URLs.
// --------------------------

extension URLScanner {

  static func scanCannotBeABaseURLPath(_ input: Input, _ mapping: inout Mapping<T>, callback: inout Callback) -> ComponentParseResult {
    
    // 1. Validate the mapping.
    assert(mapping.authorityStartPosition.get() == nil)
    assert(mapping.hostnameEndIndex.get() == nil)
    assert(mapping.portEndIndex.get() == nil)
    assert(mapping.path.get() == nil)
    assert(mapping.query.get() == nil)
    assert(mapping.fragment.get() == nil)
    
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
      mapping.path.set(to: pathEnd)
      return .success(continueFrom: (ASCII(input[pathEnd]) == .questionMark ? .query : .fragment,
                                     input.index(after: pathEnd)))
    } else {
      mapping.path.set(to: input.endIndex)
      return .success(continueFrom: nil)
    }
  }
}

// Relative URLs.
// --------------

extension URLScanner {
  
  static func parseRelativeURL<T>(_: T) -> Bool {
    print("Reached relative URL")
    return true
  }
}














extension NewURL {
  
  var scheme: NewURLParser.Scheme {
    return .other
  }
  
  var cannotBeABaseURL: Bool {
    return false
  }
}
