
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





enum Component {
   case scheme
   case host
   case port
   case path
   case query
   case fragment
 }

protocol NewURLWalker {
  associatedtype Input: Collection where Input.Element == UInt8
  
  mutating func markPossibleComponent(_ component: Component, startingAt index: Input.Index)
  mutating func rejectPossibleComponent(_ component: Component) -> Input.Index
  mutating func confirmPossibleComponent(_ component: Component, endingAt index: Input.Index)
}

extension NewURLWalker {
  
  mutating func confirmComponent(_ component: Component, range: Range<Input.Index>) {
    markPossibleComponent(component, startingAt: range.lowerBound)
    confirmPossibleComponent(component, endingAt: range.upperBound)
  }
}

class StorageCopier<Input>: NewURLWalker where Input: Collection, Input.Element == UInt8 {
  var input: Input
  var storage: NewURL.Storage
  

  private var component: Component? = nil
  private var componentStartIdx: Input.Index? = nil
  
  init(storage: NewURL.Storage, input: Input) {
    self.storage = storage; self.input = input
  }
  
  func markPossibleComponent(_ component: Component, startingAt index: Input.Index) {
    assert(self.component == nil, "Already started a component")
    self.component = component
    
    assert(componentStartIdx == nil, "componentStartIdx should be nil")
    assert(input.indices.contains(index), "Invalid index")
    componentStartIdx = index
  }
  
  func rejectPossibleComponent(_ component: Component) -> Input.Index {
    assert(self.component == component, "Incorrect component")
    guard let rewindIndex = componentStartIdx else {
      fatalError("No component started")
    }
    self.component = nil
    self.componentStartIdx = nil
    return rewindIndex
  }
  
  func confirmPossibleComponent(_ component: Component, endingAt endIndex: Input.Index) {
    assert(self.component == component, "Incorrect component")
    assert(input.indices.contains(endIndex) || input.endIndex == endIndex, "Invalid index")
    guard let startIndex = componentStartIdx else {
      fatalError("No component started")
    }
    let inputRange = startIndex ..< endIndex
    print("""
    !!! COMPONENT CONFIRMED !!!
    - Component: \(component)
    - Data: |\(String(decoding: input[inputRange], as: UTF8.self))|
    """)
    switch component {
    case .scheme:
      confirmScheme(range: inputRange)
    default:
      fatalError("Unhandled component: \(component)")
    }
  }
  
  func confirmScheme(range: Range<Input.Index>) {
  	// What we do here may be complex.
    // - If the URL already has a scheme and is unique, we can modify in-place.
    // - Otherwise, we need to create a new buffer containing these
    storage.append(contentsOf: input[range])
  }
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
  
    guard let scanResults = scan(rawInput: input, baseURL: baseURL, offsetType: Int16.self, stateOverride: nil) else {
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
    
  /// The first stage is scanning, where we want to build up a map of the resulting URL's components.
  /// This will tell us whether the URL is structurally invalid, although it may still fail to normalize if the domain name is nonsense.
  ///
  func scan<Input, OffsetType>(
    rawInput: Input,
    baseURL: NewURL?,
    offsetType: OffsetType.Type,
    stateOverride: WebURLParser.ParserState? = nil
  ) -> Mapping<OffsetType>? where Input: BidirectionalCollection, Input.Element == UInt8, Input.Index: FixedWidthInteger {
    
    // Create the result object.
    var scanResults = Mapping<OffsetType>()
    
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
        
    // 4. Try to parse a scheme.
    if let schemeEndIndex = tryParseScheme(input: input) {
      scanResults.scheme.value = numericCast(schemeEndIndex)
      let schemeNameBytes = input[..<schemeEndIndex].dropLast() // dropLast() to remove the ":" terminator.
      let scheme = NewURLParser.Scheme.parse(asciiBytes: schemeNameBytes)
      print("Found scheme!", scheme)
      
      let remaining = input[schemeEndIndex...]
      switch scheme {
      case .file:
        if !URLStringUtils.hasDoubleSolidusPrefix(remaining) {
//          callback.validationError(.fileSchemeMissingFollowingSolidus)
        }
        parseFileURL(remaining)
      case .other:
        if ASCII(flatMap: remaining.first) == .forwardSlash {
          // state: "path or authority"
          if ASCII(flatMap: remaining.dropFirst().first) == .forwardSlash {
            parseAuthority(remaining.dropFirst(2), &scanResults)
          } else {
            parsePath(remaining.dropFirst(), &scanResults)
          }
          
        } else {
          scanResults.cannotBeABaseURL = true
//          url.path.append("")
          parseCannotBeABaseURLPath(remaining)
        }
      default:
        if baseURL?.scheme == scheme {
          // state: "special relative or authority"
          if URLStringUtils.hasDoubleSolidusPrefix(remaining) {
            parseSpecialAuthorityIgnoreSlashes(remaining.dropFirst(2), &scanResults)
          } else {
//            callback.validationError(.relativeURLMissingBeginningSolidus)
            parseRelativeURL(remaining)
          }
        } else {
          // state: "special authority slashes"
          if URLStringUtils.hasDoubleSolidusPrefix(remaining) {
            parseSpecialAuthorityIgnoreSlashes(remaining.dropFirst(2), &scanResults)
          } else {
//            callback.validationError(.missingSolidusBeforeAuthority)
            parseSpecialAuthorityIgnoreSlashes(remaining, &scanResults)
          }
        }
      }
      
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
        parseFragment(input.dropFirst())
        return scanResults // ?
      }
      if base.scheme == .file {
        parseFileURL(input)
      } else {
        parseRelativeURL(input)
      }
    }
    
    // End parse function.
    return scanResults
  }
  
  
  func parseSpecialAuthorityIgnoreSlashes<Input, Offset>(_ input: Input, _ mapping: inout Mapping<Offset>)
    where Input: BidirectionalCollection, Input.Element == UInt8, Input.Index: FixedWidthInteger {
      
      let authorityStart = input.prefix {
        return ASCII($0) == .forwardSlash || ASCII($0) == .backslash
      }.endIndex
      if authorityStart == input.startIndex {
//        callback.validationError(.missingSolidusBeforeAuthority)
      }
      return parseAuthority(input[authorityStart...], &mapping)
  }
  

   
  func parseAuthority<Input, Offset>(_ input: Input, _ mapping: inout Mapping<Offset>)
    where Input: BidirectionalCollection, Input.Element == UInt8, Input.Index: FixedWidthInteger {
     
      print("Reached authority")
      print(String(decoding: input, as: UTF8.self))
   }

  func parsePath<Input, Offset>(_ input: Input, _ mapping: inout Mapping<Offset>)
    where Input: BidirectionalCollection, Input.Element == UInt8, Input.Index: FixedWidthInteger {
  }
  
  func parseFragment<T>(_: T) {
    
  }
  
  func parseFileURL<T>(_: T) {
    
  }

  func parseCannotBeABaseURLPath<T>(_: T) {
    
  }
  
  func parseRelativeURL<T>(_: T) {
    
  }
}

// Component parsing.

extension NewURLParser {
  
 	/// Attempts to parse a scheme from the UTF8-encoded bytes in `input`.
  /// If a scheme can be parsed, the given `walker` object will be notified of its location. `input` must not contain any ASCII tabs or newlines.
  ///
  func tryParseScheme<Input>(
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
}













extension NewURL {
  
  var scheme: NewURLParser.Scheme {
    return .other
  }
  
  var cannotBeABaseURL: Bool {
    return false
  }
}
