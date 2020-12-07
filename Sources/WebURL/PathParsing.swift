/// An object which parses a path string.
///
/// This protocol is an implementation detail. It defines a group of callbacks which are invoked by the `walkPathComponents` method.
/// Conforming types should implement these callbacks, as well as another method/initializer which invokes the `walkPathComponents` method to
/// compute the result. Since the group of callbacks are defined as a type, the entire parsing/processing operation may be specialized.
///
/// Conforming types should be aware that components are visited in reverse order. Given a path "a/b/c", the components visited would be "c", "b", and finally "a".
/// All of the visited path components are present in the simplified path string, with all pushing/popping handled internally by the `walkPathComponents` method.
///
/// Path components originate from 2 sources:
///
/// - They may be slices of some unvalidated, non-normalised string given as an input. In order to be written as a normalized path string, they must
///   be percent-encoded and adjustments must be made to Windows drive letters.
/// - They may be slices of an existing path string, coming from a URL object given as the "base URL". In this case, things are a bit easier -
///   the component will already be properly encoded and normalised, and we know that it exists in contiguous storage.
///
private protocol PathParser {
  associatedtype InputString: BidirectionalCollection where InputString.Element == UInt8

  /// A callback which is invoked when the parser yields a path component originating from the input string.
  /// These components may not be contiguously stored and require percent-encoding before writing.
  ///
  /// - parameters:
  ///   - pathComponent:                The path component yielded by the parser.
  ///   - isLeadingWindowsDriveLetter:  If `true`, the component is a Windows drive letter in a `file:` URL.
  ///                                   It should be normalized when written (by writing the first byte followed by the ASCII character `:`).
  ///
  mutating func visitInputPathComponent(_ pathComponent: InputString.SubSequence, isLeadingWindowsDriveLetter: Bool)

  /// A callback which is invoked when the parser yields a path component originating from the base URL's path.
  /// These components are known to be contiguously stored, properly percent-encoded, and any Windows drive letters will already have been normalized.
  /// They need no further processing, and may be written to the result as-is.
  ///
  /// - parameters:
  ///   - pathComponent: The path component yielded by the parser.
  ///
  mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>)
  
  /// A callback which is invoked when the parser yields a number of consecutive empty path components.
  /// Note that this does not imply that path components yielded via other callbacks are non-empty.
  ///
  /// This method exists as an optimisation, since empty components have no content to percent-encode/transform.
  ///
  mutating func visitEmptyPathComponents(_ n: Int)
  
  /// A callback which is invoked when the parser yields a path sigil ("/.") in order to disambiguate a path with leading slashes from an authority.
  /// Conformers should ensure that a "/." is prepended to the path string if it is written to a URL without an authority sigil.
  ///
  /// If a sigil is yielded, it is always the very start of the path and the parser will not yield any components after this.
  ///
  mutating func visitPathSigil()
}

extension PathParser {

  /// A callback which is invoked when the parser yields an empty path component.
  /// Note that this does not imply that path components yielded via other callbacks are non-empty.
  ///
  /// This method exists as an optimisation, since empty components have no content to percent-encode/transform.
  ///
  mutating func visitEmptyPathComponent() {
    visitEmptyPathComponents(1)
  }
}

extension PathParser {

  // FIXME: [swift]
  // This should be a local function inside 'walkPathComponents', but writing it
  // that way introduces a heap allocation which dominates the performance of the entire function.
  private mutating func __flushTrailingEmpties(_ trailingEmptyCount: inout Int, _ didYieldComponent: inout Bool) {
    if trailingEmptyCount != 0 {
      visitEmptyPathComponents(trailingEmptyCount)
      didYieldComponent = true
      trailingEmptyCount = 0
    }
  }

  /// Parses the simplified list of path components from a given path string, optionally applied relative to the path of a base URL object.
  /// These components are iterated in reverse order, and processed via the callback methods in `PathParser`.
  ///
  /// A path string, such as `"a/b/c/.././d/e/../f/"`, describes a path through a tree of abstract nodes.
  /// In order to resolve which nodes are present in the final path without allocating dynamic storage to represent the stack of visited nodes,
  /// the components must be iterated in reverse.
  ///
  /// To construct a simplified path string, start with an empty string. For each path component yielded by the parser,
  /// prepend `"/"` (ASCII forward slash) followed by the path component's contents, to that string.
  /// An empty component is used to force a trailing slash (for directory paths), and to force a leading slash (as is required for normalized path strings).
  /// Note that path components from the input string require additional normalization such as percent-encoding or Windows drive letter adjustments as
  /// described in the documentation for `visitInputPathComponent`.
  ///
  /// For example, consider the input `"a/b/../c/"`, which normalizes to the path string `"/a/c/"`.
  /// This method yields the components `["", "c", "a"]`, and path construction by prepending proceeds as follows: `"/" -> "/c/" -> "/a/c/"`.
  ///
  /// - Note:
  /// If the input string is empty, and the scheme **is not** special, no callbacks will be called (the path is `nil`).
  /// If the input string is empty, and the scheme **is** special, the result is an implicit root path (`/`).
  /// If the input string is not empty, this function will always yield something.
  ///
  fileprivate mutating func walkPathComponents(
    pathString input: InputString,
    schemeKind: WebURL.SchemeKind,
    baseURL: WebURL?
  ) {

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
        guard
          URLStringUtils.isSingleDotPathSegment(component) || URLStringUtils.isDoubleDotPathSegment(component)
            || component.isEmpty
        else {
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
        baseURL?.storage.withComponentBytes(.path) {
          guard let basePath = $0?.dropFirst() else { return }  // dropFirst() due to the leading slash.
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
    // - If the URL we are writing to does not have an authority sigil, we are not allowed to emit 2 leading slashes
    //   and must prefix them with a "/." sigil. This sigil is not technically part of the path, but must be in the URL.
    //   (This only applies to non-special URLs, as special URLs always have an authority.)

    // Iterate the path components in reverse, so we can skip components which later get popped.
    var path = input[contentStartIdx...]
    var popcount = 0
    var trailingEmptyCount = 0
    var didYieldComponent = false

    // Consume components separated by terminators.
    // Since we trimmed the initial slash, this will *not* consume the first path component from the input string,
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
      __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
      visitInputPathComponent(pathComponent, isLeadingWindowsDriveLetter: false)
      didYieldComponent = true
    }
    // path now contains the first path component from the input string.

    if path.isEmpty {
      assert(isFileScheme == false) // file URLs strip leading slashes, so we can't be one of those.
      assert(input.prefix(2).allSatisfy(isPathComponentTerminator))
    }
    switch path {
    // input string starts with "../" or "./":
    // If we have a base URL, it could affect the popcount, otherwise just make sure we don't have a null path.
    case _ where URLStringUtils.isDoubleDotPathSegment(path):
      popcount += 1
      fallthrough
    case _ where URLStringUtils.isSingleDotPathSegment(path):
      if !didYieldComponent {
        trailingEmptyCount = max(trailingEmptyCount, 1)
      }

    case _ where URLStringUtils.isWindowsDriveLetter(path) && isFileScheme:
      __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
      visitInputPathComponent(path, isLeadingWindowsDriveLetter: true)
      return  // Never appended to base URL.

    case _ where popcount != 0:
      popcount -= 1
    case _ where path.isEmpty:
      trailingEmptyCount += 1
      
    default:
      __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
      visitInputPathComponent(path, isLeadingWindowsDriveLetter: false)
      didYieldComponent = true
    }
    
    // The input string has now been entirely consumed, but we have some state remaining (trailing empties, popcount)
    // that we carry to the base path.
    path = path.prefix(0)
    
    accessOptionalResource(from: baseURL, using: { $0.storage.withComponentBytes(.path, $1) }) {
      guard var basePath = $0?[...] else {
        // Either baseURL is nil, or baseURL.path is nil. Flush all state from the input string.
        // This is the start of the resulting path-string.
        assert(baseURL?._schemeKind.isSpecial != true, "Special URLs always have a path")

        if didYieldComponent == false {
          // If we haven't yielded anything yet, the first component was popped-out, skipped ("."), or deferred (empty).
          // Make sure we at least write an empty path.
          if isFileScheme {
            trailingEmptyCount = 1 // File URLs collapse leading empties.
          } else if trailingEmptyCount == 0 {
            trailingEmptyCount = 1
          }
        }
        // Determine if the path needs to be prefixed with a sigil, then flush remaining state.
        let needsPathSigil = (didYieldComponent ? trailingEmptyCount != 0 : trailingEmptyCount > 1)
        __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
        if needsPathSigil {
          visitPathSigil()
        }
        return
      }
      
      precondition(basePath.first == ASCII.forwardSlash.codePoint, "Normalized base paths must start with a /")
      
      // Drop the last path component.
      guard !(isFileScheme && URLStringUtils.isWindowsDriveLetter(basePath.dropFirst())) else {
        // Do not drop Windows drive letters. This handles the very specific case of a base path
        // which is only a Windows drive letter with no trailing slash ("file:///C:").
        __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
        visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath.dropFirst()))
        return
      }
      basePath = basePath[..<(basePath.lastIndex(of: ASCII.forwardSlash.codePoint) ?? basePath.startIndex)]

      // Consume remaining components.
      while let componentTerminatorIndex = basePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
        let pathComponent = basePath[basePath.index(after: componentTerminatorIndex)..<basePath.endIndex]
        defer { basePath = basePath.prefix(upTo: componentTerminatorIndex) }

        assert(URLStringUtils.isDoubleDotPathSegment(pathComponent) == false)
        assert(URLStringUtils.isSingleDotPathSegment(pathComponent) == false)
        
        // Windows drive letters (which must be the first path component and hence the end of our walk)
        // cannot be popped out.
        if isFileScheme, componentTerminatorIndex == basePath.startIndex,
           URLStringUtils.isWindowsDriveLetter(pathComponent) {
          if didYieldComponent == false {
            trailingEmptyCount = max(1, trailingEmptyCount)
          }
          __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
          visitBasePathComponent(UnsafeBufferPointer(rebasing: pathComponent))
          return
        }
        guard popcount == 0 else {
          popcount -= 1
          continue
        }
        if pathComponent.isEmpty {
          trailingEmptyCount += 1
          continue
        }
        __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
        visitBasePathComponent(UnsafeBufferPointer(rebasing: pathComponent))
        didYieldComponent = true
      }
      precondition(basePath.isEmpty, "Normalized base paths must start with a /")
      
      if didYieldComponent == false {
        // If we still haven't yielded anything, the entire path has been popped-out or deferred (empty).
        // Make sure we at least write an empty path.
        if isFileScheme {
          trailingEmptyCount = 1 // File URLs collapse leading empties.
        } else if trailingEmptyCount == 0 {
          trailingEmptyCount = 1
        }
      }
      
      // Determine if the path needs to be prefixed with a sigil, then flush remaining state.
      let needsPathSigil = (didYieldComponent ? trailingEmptyCount != 0 : trailingEmptyCount > 1)
      __flushTrailingEmpties(&trailingEmptyCount, &didYieldComponent)
      if needsPathSigil {
        visitPathSigil()
      }
      return
    }
  }
}


// MARK: - PathMetrics.

struct PathMetrics {
  
  /// The precise length of the simplified, escaped path string, in bytes.
  private(set) var requiredCapacity: Int
  
  /// The number of components in the simplified path.
  private(set) var numberOfComponents: Int
  
  /// Whether or not the simplified path must be prefixed with a path sigil if it is written to a URL without an authority sigil.
  private(set) var requiresSigil: Bool
  
  /// Whether any components in the simplified path need percent-encoding.
  private(set) var needsEscaping: Bool
}

extension PathMetrics {

  /// Creates a `PathMetrics` object containing information about the shape of the given path-string if it were written in its simplified, normalized form.
  ///
  /// The metrics may also contain information about simplification/normalization steps which can be skipped when writing the path-string.
  ///
  init<InputString>(
    parsing input: InputString,
    schemeKind: WebURL.SchemeKind,
    baseURL: WebURL?
  ) where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    var parser = Parser<InputString>()
    parser.walkPathComponents(pathString: input, schemeKind: schemeKind, baseURL: baseURL)
    self = parser.metrics
  }

  private init() {
    self.requiredCapacity = 0
    self.numberOfComponents = 0
    self.needsEscaping = false
    self.requiresSigil = false
  }

  private struct Parser<InputString>: PathParser
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    var metrics = PathMetrics()

    mutating func visitInputPathComponent(
      _ pathComponent: InputString.SubSequence, isLeadingWindowsDriveLetter: Bool
    ) {
      metrics.numberOfComponents += 1
      metrics.requiredCapacity += 1  // "/"
      let thisComponentNeedsEscaping = pathComponent.lazy
        .percentEncoded(using: URLEncodeSet.Path.self)
        .writeBufferedFromBack { piece in metrics.requiredCapacity += piece.count }
      if thisComponentNeedsEscaping {
        metrics.needsEscaping = true
      }
    }

    mutating func visitEmptyPathComponents(_ n: Int) {
      metrics.numberOfComponents += n
      metrics.requiredCapacity += n
    }
    
    mutating func visitPathSigil() {
      metrics.requiresSigil = true
    }

    mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
      metrics.numberOfComponents += 1
      metrics.requiredCapacity += 1 /* "/" */ + pathComponent.count
    }
  }
}


// MARK: - Path writing.


extension UnsafeMutableBufferPointer where Element == UInt8 {

  /// Initializes this buffer to the simplified, normalized path parsed from `input`.
  ///
  /// Returns the number of bytes written. Use `PathMetrics` to calculate the required size.
  /// Currently, this method fails at runtime if the buffer is not precisely sized to fit the resulting path-string, so the returned value is always equal to `self.count`.
  ///
  func writeNormalizedPath<InputString>(
    parsing input: InputString,
    schemeKind: WebURL.SchemeKind,
    baseURL: WebURL?,
    needsEscaping: Bool = true
  ) -> Int where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    return PathWriter.writePath(
      to: self, pathString: input, schemeKind: schemeKind, baseURL: baseURL, needsEscaping: needsEscaping
    )
  }

  /// A `PathParser` which writes a properly percent-encoded, normalised URL path string
  /// in to a correctly-sized, uninitialized buffer. Use `PathMetrics` to calculate the buffer's required size.
  ///
  private struct PathWriter<InputString>: PathParser
  where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    private let buffer: UnsafeMutableBufferPointer<UInt8>
    private var front: Int
    private let needsEscaping: Bool

    static func writePath(
      to buffer: UnsafeMutableBufferPointer<UInt8>,
      pathString input: InputString,
      schemeKind: WebURL.SchemeKind,
      baseURL: WebURL?,
      needsEscaping: Bool = true
    ) -> Int {
      // Checking this now allows the implementation to use `.baseAddress.unsafelyUnwrapped`.
      precondition(buffer.baseAddress != nil)
      var visitor = PathWriter(buffer: buffer, front: buffer.endIndex, needsEscaping: needsEscaping)
      visitor.walkPathComponents(
        pathString: input,
        schemeKind: schemeKind,
        baseURL: baseURL
      )
      // Checking this now allows the implementation to be safe when omitting bounds checks.
      precondition(visitor.front == 0, "Buffer was incorrectly sized")
      return buffer.count - visitor.front
    }

    private mutating func prependSlash(_ n: Int = 1) {
      front = buffer.index(front, offsetBy: -1 * n)
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
        .initialize(repeating: ASCII.forwardSlash.codePoint, count: n)
    }

    fileprivate mutating func visitInputPathComponent(
      _ pathComponent: InputString.SubSequence, isLeadingWindowsDriveLetter: Bool
    ) {
      guard pathComponent.isEmpty == false else {
        prependSlash()
        return
      }
      guard isLeadingWindowsDriveLetter == false else {
        assert(pathComponent.count == 2)
        front = buffer.index(front, offsetBy: -2)
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: front).initialize(to: pathComponent[pathComponent.startIndex])
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: front &+ 1).initialize(to: ASCII.colon.codePoint)
        prependSlash()
        return
      }
      if needsEscaping {
        pathComponent.lazy.percentEncoded(using: URLEncodeSet.Path.self).writeBufferedFromBack { piece in
          let newFront = buffer.index(front, offsetBy: -1 * piece.count)
          buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront)
            .initialize(from: piece.baseAddress!, count: piece.count)
          front = newFront
        }
      } else {
        let count = pathComponent.count
        let newFront = buffer.index(front, offsetBy: -1 * count)
        _ = UnsafeMutableBufferPointer(
          start: buffer.baseAddress.unsafelyUnwrapped.advanced(by: newFront),
          count: count
        ).initialize(from: pathComponent)
        front = newFront
      }
      prependSlash()
    }

    fileprivate mutating func visitEmptyPathComponents(_ n: Int) {
      prependSlash(n)
    }
    
    fileprivate func visitPathSigil() {
      // URLWriter is reponsible for writing its own path sigil.
    }

    fileprivate mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
      front = buffer.index(front, offsetBy: -1 * pathComponent.count)
      buffer.baseAddress.unsafelyUnwrapped.advanced(by: front)
        .initialize(from: pathComponent.baseAddress!, count: pathComponent.count)
      prependSlash()
    }
  }
}


// MARK: - Others parsers.


/// An objects which checks for URL validation errors in a path string.
///
/// Validation errors are communicated to the given `URLParserCallback` if the path-string contains:
/// - Non-URL code points
/// - Invalid percent encoding (e.g. "%ZZ"), or
/// - Backslashes as path separators
///
/// This type cannot be initialized directly. To validate a path string, use the static `.validate` method.
///
struct PathStringValidator<InputString, Callback>: PathParser
where InputString: BidirectionalCollection, InputString.Element == UInt8, Callback: URLParserCallback {
  private var callback: Callback
  private let path: InputString

  static func validate(
    pathString input: InputString,
    schemeKind: WebURL.SchemeKind,
    callback: inout Callback
  ) {
    guard Callback.self != IgnoreValidationErrors.self else {
      // The compiler has a tough time optimising this function away when we ignore validation errors.
      return
    }
    var visitor = PathStringValidator(callback: callback, path: input)
    // hasAuthority does not matter for input string validation.
    visitor.walkPathComponents(pathString: input, schemeKind: schemeKind, baseURL: nil)
  }

  fileprivate mutating func visitInputPathComponent(
    _ pathComponent: InputString.SubSequence, isLeadingWindowsDriveLetter: Bool
  ) {
    if pathComponent.endIndex != path.endIndex, ASCII(path[pathComponent.endIndex]) == .backslash {
      callback.validationError(.unexpectedReverseSolidus)
    }
    validateURLCodePointsAndPercentEncoding(pathComponent, callback: &callback)
  }

  fileprivate mutating func visitEmptyPathComponents(_ n: Int) {
    // Nothing to do.
  }
  
  fileprivate func visitPathSigil() {
    // Nothing to do.
  }

  fileprivate mutating func visitBasePathComponent(_ pathComponent: UnsafeBufferPointer<UInt8>) {
    assertionFailure("Should never be invoked without a base URL")
  }
}


// MARK: - Path Utilities


extension URLStringUtils where T: Sequence, T.Element == UInt8 {
  
  static func doesNormalizedPathRequirePathSigil(_ path: T) -> Bool {
    var iter = path.makeIterator()
    guard iter.next() == ASCII.forwardSlash.codePoint, iter.next() == ASCII.forwardSlash.codePoint else {
      return false
    }
    return true
  }
}
