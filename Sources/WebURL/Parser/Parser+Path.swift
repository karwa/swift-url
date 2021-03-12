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
  ///   - pathComponent:         The path component yielded by the parser.
  ///   - isWindowsDriveLetter:  If `true`, the component is a Windows drive letter in a `file:` URL.
  ///                            It should be normalized when written (by writing the first byte followed by the ASCII character `:`).
  ///
  mutating func visitInputPathComponent(_ pathComponent: InputString.SubSequence, isWindowsDriveLetter: Bool)

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

  mutating func visitValidationError(_ error: ValidationError)
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

  mutating func visitValidationError(_ error: ValidationError) {
    // No required action.
  }
}

private enum DeferredPathComponent<Source: Collection> {
  case potentialWindowsDrive(Source, Int)
  case empties(Int)

  var isPotentialWindowsDrive: Bool {
    if case .potentialWindowsDrive = self { return true }
    return false
  }

  func needsPathSigilWhenFlushing(_ state: PathState) -> Bool {
    if state.didYieldComponent {
      if case .empties(let count) = self {
        return count != 0
      }
    } else {
      if case .empties(let count) = self {
        return count > 1
      }
    }
    return false
  }
}

private struct PathState {
  var popcount = 0
  var didYieldComponent = false
}

extension WebURL {

  fileprivate func withNormalizedWindowsDriveLetter<T>(_ block: (Slice<UnsafeBufferPointer<UInt8>>?) -> T) -> T {
    return self.storage.withComponentBytes(.path) {
      // dropFirst() due to the leading slash.
      if let path = $0?.dropFirst(), PathComponentParser.isNormalizedWindowsDriveLetter(path.prefix(2)) {
        return block(path.prefix(2))
      } else {
        return block(nil)
      }
    }
  }

  fileprivate var hasNormalizedWindowsDriveLetter: Bool {
    return withNormalizedWindowsDriveLetter { $0 != nil }
  }
}

extension PathParser {

  // FIXME: [swift]
  // Some/all of these should be local functions inside 'walkPathComponents', but writing it
  // that way introduces heap allocations which dominate the performance of the entire function.

  /// Clears the given deferred component(s) and updates the path parser's state.
  ///
  /// - For potential Windows drives, this means we yield the component unless the popcount from the RHS would have popped it,
  ///   then merge the resulting RHS popcount in to the LHS popcount in the given path parser state.
  ///-   For empty components, we just check and yield them.
  ///
  private mutating func __flushDeferredComponent(
    _ deferredComponent: inout DeferredPathComponent<InputString.SubSequence>?,
    _ state: inout PathState
  ) {
    switch deferredComponent {
    case .none:
      break
    case .potentialWindowsDrive(let componentContent, var storedPopcount):
      // We've concluded that this is *not* a Windows drive letter, so yield it unless it would have been popped.
      if storedPopcount == 0 {
        visitInputPathComponent(componentContent, isWindowsDriveLetter: false)
        state.didYieldComponent = true
      } else {
        storedPopcount -= 1
      }
      // Merge the popcount from the RHS of the Windows drive.
      state.popcount += storedPopcount
    case .empties(let count):
      assert(count != 0, "0 is not a valid value for deferred empties")
      visitEmptyPathComponents(count)
      state.didYieldComponent = true
    }
    deferredComponent = .none
  }

  /// Defers an empty path component. If there are already empty components deferred, it will be added to them.
  /// Asserts that no other deferred components are inadvertedly overwritten.
  ///
  private mutating func __deferTrailingEmptyAssert(
    _ deferredComponent: inout DeferredPathComponent<InputString.SubSequence>?, _ state: inout PathState
  ) {
    assert(state.popcount == 0, "cannot defer empty component - has been popped!")
    guard case .empties(let count) = deferredComponent else {
      assert(deferredComponent == nil, "cannot defer empty component - Windows drive already deferred!")
      deferredComponent = .empties(1)
      return
    }
    deferredComponent = .empties(count + 1)
  }

  /// Flushes deferred empty components.
  /// Asserts that no other deferred components are inadvertedly flushed.
  ///
  private mutating func __flushDeferredEmptiesAssert(
    _ deferredComponent: inout DeferredPathComponent<InputString.SubSequence>?, _ state: inout PathState
  ) {
    switch deferredComponent {
    case .none: break
    case .empties(_): __flushDeferredComponent(&deferredComponent, &state)
    default: assertionFailure("Deferred non-empties")
    }
  }

  private mutating func __flushDeferredComponentForFinalization(
    _ deferredComponent: inout DeferredPathComponent<InputString.SubSequence>?, _ state: inout PathState
  ) {
    switch deferredComponent {
    case .potentialWindowsDrive(let firstComponent, _):
      visitInputPathComponent(firstComponent, isWindowsDriveLetter: true)
    case .empties(_), .none:
      // If we haven't yielded anything yet, make sure we at least write an empty path.
      if state.didYieldComponent == false {
        __deferTrailingEmptyIfNone(&deferredComponent, &state)
      }
      // Determine if the path needs to be prefixed with a sigil, then flush remaining state.
      let needsPathSigil = deferredComponent?.needsPathSigilWhenFlushing(state) ?? false
      __flushDeferredEmptiesAssert(&deferredComponent, &state)
      if needsPathSigil {
        visitPathSigil()
      }
    }
  }

  private mutating func __deferTrailingEmptyIfNone(
    _ deferredComponent: inout DeferredPathComponent<InputString.SubSequence>?, _ state: inout PathState
  ) {
    guard case .empties(let count) = deferredComponent else {
      assert(deferredComponent == nil, "cannot defer empty component - Windows drive already deferred!")
      deferredComponent = .empties(1)
      return
    }
    assert(count != 0)
  }

  /// Parses the given path string, optionally applied relative to the path of a base URL object, and yields the simplified list of path components.
  /// These components are iterated in *reverse order*, and processed via the callback methods in `PathParser`.
  ///
  /// To construct the simplified path string, start with an empty string. For each path component yielded by the parser,
  /// prepend `"/"` (ASCII forward slash) followed by the path component's contents, to that string. Note that path components from the input string may require
  /// additional adjustments such as percent-encoding or drive letter normalization as described in the documentation for `visitInputPathComponent`.
  ///
  /// For example, consider the input `"a/b/../c/"`, which normalizes to the path string `"/a/c/"`.
  /// This method yields the components `["", "c", "a"]`, and path construction by prepending proceeds as follows: `"/" -> "/c/" -> "/a/c/"`.
  ///
  /// - Note:
  /// If the input string is empty, and the scheme **is not** special, no callbacks will be called (the path is `nil`).
  /// If the input string is empty, and the scheme **is** special, the result is an implicit root path (`/`).
  /// If the input string is not empty, this function will always yield something.
  ///
  /// - parameters:
  ///  - inputString:  The path string to parse, as a collection of UTF8-encoded bytes.
  ///  - schemeKind:   The scheme of the URL which the path will be part of.
  ///  - baseURL:      The URL whose path serves as the "base" for the input string, if it is a relative path.
  ///                  Note that there are some edge-cases related to Windows drive letters which require the URL parser to provide the base URL
  ///                  (if present), even for absolute paths.
  ///  - absolutePathsCopyWindowsDriveFromBase: A flag set by the URL parser to enable special behaviours for absolute paths in path-only file
  ///                                           URLs, making them copy the base URL's Windows drive letter in some cirumstances.
  ///                                           For example, the path-only URL "file:/hello" parsed against the base URL
  ///                                           "file:///C:/Windows" results in "file:///C:/hello", but the non-path-only
  ///                                           URL "file:///hello" results in "file:///hello" when parsed against the same base URL.
  ///                                           In both cases the path parser only sees the string "/hello" as its input.
  ///
  fileprivate mutating func walkPathComponents(
    pathString input: InputString,
    schemeKind: WebURL.SchemeKind,
    baseURL: WebURL?,
    absolutePathsCopyWindowsDriveFromBase: Bool
  ) {

    // Set some definitions based on the scheme.
    let isFileScheme = (schemeKind == .file)
    let isPathSeparator: (_ byte: UInt8) -> Bool
    if schemeKind.isSpecial {
      isPathSeparator = { byte in ASCII(byte) == .forwardSlash || ASCII(byte) == .backslash }
    } else {
      isPathSeparator = { byte in ASCII(byte) == .forwardSlash }
    }

    var input = input[...]

    guard input.isEmpty == false else {
      // Empty string. Special URLs have an implicit path, non-special URLs may have an empty path.
      if schemeKind.isSpecial {
        visitEmptyPathComponent()
      }
      return
    }

    // If the input string starts with a path separator, remove it.
    // Leading path separators (e.g. "usr/lib" vs. "/usr/lib") denote absolute vs. relative paths.
    //
    // Removing the leading separator means that, when we consume components, the first component from
    // input will be left as a remainder.
    let isInputAbsolute = isPathSeparator(input[input.startIndex])
    if isInputAbsolute {
      input = input.dropFirst()
    }

    guard input.isEmpty == false else {
      // The input string is just a single separator ("/" or "\"), i.e. a root/empty, absolute path.
      // We can fast-path this: it results in a single "/", or the drive root if baseURL has a Windows drive letter.
      assert(isInputAbsolute)
      visitEmptyPathComponent()
      if isFileScheme {
        baseURL?.withNormalizedWindowsDriveLetter {
          if let driveLetter = $0 {
            visitBasePathComponent(UnsafeBufferPointer(rebasing: driveLetter))
          }
        }
      }
      return
    }

    // Consume path components from the end.
    //
    // Consuming in reverse means that we can avoid tracking the shortened path in an dynamically-sized Array.
    // Instead, we maintain an integer `popcount`, which tells us how many components towards the front ultimately get
    // popped and removed from the traversal. For instance, consider the path "/p1/p2/../p3/p4/p5/../../p6":
    // - When we see p6, the popcount is 0. p6 is yielded.
    // - When we see p5 and p4, the popcount is 2 and 1 respectively. They are not yielded.
    // - When we see p3, the popcount is 0 again, and it is yielded. p2 is not yielded, p1 is.
    // Hence the final path is p1/p3/p6 - only, we discovered that information in reverse order (["p6", "p3", "p1"]).
    //
    // The downside is that it's harder for us to tell when something is at the start of the final path
    // or whether other components may appear before it. For this reason, some components which have different
    // behaviour get deferred until we can make that determination.
    //
    // Deferred Components
    // ===================
    //
    // - Potential Windows drive letters. For file URLs, a component such as "C:" may not be popped when it is at the
    //   start of the path. If it is not at the start of the path, it's just a regular component.
    //   The way we handle this is by noting that while popped components are allowed ("abc/../C:" contains a drive),
    //   any other non-popped component invalidates it. So we split the popcount on the LHS and RHS of the potential
    //   drive, and if we see a component about to be yielded on the LHS, it means the candidate is not really a drive
    //   so we can flush it and merge the popcounts.
    //
    // - Empty components. These were originally deferred due to special behaviour with empty components at the start
    //   of file paths (which was removed in https://github.com/whatwg/url/pull/544). However, non-special URLs may
    //   also require a "path sigil" if the path starts with an empty component ("//p2"), because otherwise that string
    //   would look like an authority (see https://github.com/whatwg/url/pull/505), meaning we still have a
    //   reason to track whether the last component we yielded was empty. Deferring the empty helps us do that,
    //   even though we could also track it in other ways.
    //
    // Other special components
    // ========================
    //
    // - Single dot ('.') components get skipped.
    //   - If at the end of the path, they force a trailing slash/empty component.
    //   - They cannot be independently popped; e.g. "/a/b/./../" -> "/a/", not "/a/b/".
    //
    // - Double dot ('..') components pop previous components from the path.
    //   - For file URLs, they do not pop beyond a Windows drive letter.
    //   - If at the end of the path, they force a trailing slash/empty component.
    //     (even if they have popped all other components, the result is an empty path, not a nil path)

    var remainingInput = input
    var state = PathState()
    var deferredComponent: DeferredPathComponent<InputString.SubSequence>? = .none

    // Since we trimmed the initial slash, this will *not* consume the first path component from the input string.
    while var componentTerminatorIndex = remainingInput.lastIndex(where: isPathSeparator) {

      let pathComponent = input[remainingInput.index(after: componentTerminatorIndex)..<remainingInput.endIndex]
      defer { remainingInput = remainingInput.prefix(upTo: componentTerminatorIndex) }

      if ASCII(input[componentTerminatorIndex]) == .backslash {
        visitValidationError(.unexpectedReverseSolidus)
      }

      switch pathComponent {
      case _ where PathComponentParser.isDoubleDotPathSegment(pathComponent):
        state.popcount += 1
        fallthrough

      case _ where PathComponentParser.isSingleDotPathSegment(pathComponent):
        if pathComponent.endIndex == input.endIndex {
          // Don't defer this as it will be nulled by the popcount increment. Only matches "p1/p2/.." or "p1/p2/.".
          visitEmptyPathComponent()
          state.didYieldComponent = true
        }

      case _ where isFileScheme && PathComponentParser.isWindowsDriveLetter(pathComponent):
        __flushDeferredComponent(&deferredComponent, &state)
        // Move the popcount in to deferredComponent and start a new count for the LHS of the Windows drive candidate.
        deferredComponent = .potentialWindowsDrive(pathComponent, state.popcount)
        state.popcount = 0

      case _ where state.popcount != 0:
        state.popcount -= 1

      case _ where deferredComponent?.isPotentialWindowsDrive == true:
        // Invalidate our candidate Windows drive letter: flush its component and merge the popcounts.
        // Reset the cursor to re-check this component.
        __flushDeferredComponent(&deferredComponent, &state)
        componentTerminatorIndex = pathComponent.endIndex

      default:
        if pathComponent.isEmpty {
          __deferTrailingEmptyAssert(&deferredComponent, &state)
        } else {
          __flushDeferredEmptiesAssert(&deferredComponent, &state)
          visitInputPathComponent(pathComponent, isWindowsDriveLetter: false)
          state.didYieldComponent = true
        }
      }
    }
    // 'remainingInput' now contains the first path component from the input string.

    repeatFirstComponent: while true {
      // TODO: This is exactly the same as above, except for using a `while` loop to repeat the component.
      //       Good candidate for some refactoring.
      switch remainingInput {
      case _ where PathComponentParser.isDoubleDotPathSegment(remainingInput):
        state.popcount += 1
        fallthrough

      case _ where PathComponentParser.isSingleDotPathSegment(remainingInput):
        if remainingInput.endIndex == input.endIndex {
          assert(state.didYieldComponent == false && deferredComponent == nil)
          visitEmptyPathComponent()
          state.didYieldComponent = true
        }

      case _ where isFileScheme && PathComponentParser.isWindowsDriveLetter(remainingInput):
        __flushDeferredComponent(&deferredComponent, &state)
        deferredComponent = .potentialWindowsDrive(remainingInput, state.popcount)
        state.popcount = 0

      case _ where state.popcount != 0:
        state.popcount -= 1

      case _ where deferredComponent?.isPotentialWindowsDrive == true:
        __flushDeferredComponent(&deferredComponent, &state)
        continue repeatFirstComponent  // Repeat the first component after restoring the popcount.

      default:
        if remainingInput.isEmpty {
          __deferTrailingEmptyAssert(&deferredComponent, &state)
        } else {
          __flushDeferredEmptiesAssert(&deferredComponent, &state)
          visitInputPathComponent(remainingInput, isWindowsDriveLetter: false)
          state.didYieldComponent = true
        }
      }
      break repeatFirstComponent
    }

    // We have now processed all of the input string, but we're not done yet.
    remainingInput = remainingInput.prefix(0)
    // This means we have already accounted for any trailing slashes (i.e. empty components) at the end of the path.
    assert(
      deferredComponent != nil || state.didYieldComponent,
      "Since the input path was not empty, we must have either deferred or yielded something from it.")

    accessOptionalResource(from: baseURL, using: { $0.storage.withComponentBytes(.path, $1) }) {

      let baseHasWindowsDrive = (baseURL?.hasNormalizedWindowsDriveLetter ?? false)

      if case .potentialWindowsDrive(let firstComponent, _) = deferredComponent,
        firstComponent.startIndex == input.startIndex
      {
        // A Windows drive literally as the first component of the input string is never relative to the base path.
        visitInputPathComponent(firstComponent, isWindowsDriveLetter: true)
        return
      }
      if isFileScheme, isInputAbsolute, baseHasWindowsDrive, absolutePathsCopyWindowsDriveFromBase {
        // Certain absolute paths whose drive letters (if they have one) are not literally the first component
        // will insist that we discard any candidate drive letters and always use the drive letter from the base path.
        // This depends on the surrounding URL structure, so there is no way to divine it from the path parser.
        __flushDeferredComponent(&deferredComponent, &state)
        baseURL!.withNormalizedWindowsDriveLetter { visitBasePathComponent(UnsafeBufferPointer(rebasing: $0!)) }
        return
      }
      // Flush state for absolute paths, and relative paths with no base path.
      guard isInputAbsolute == false, var basePath = $0?[...] else {
        __flushDeferredComponentForFinalization(&deferredComponent, &state)
        return
      }

      precondition(basePath.first == ASCII.forwardSlash.codePoint, "Normalized base paths must start with a /")
      // Drop the last path component (unless it is a Windows drive, of course).
      guard !(isFileScheme && PathComponentParser.isNormalizedWindowsDriveLetter(basePath.dropFirst())) else {
        __flushDeferredComponent(&deferredComponent, &state)
        visitBasePathComponent(UnsafeBufferPointer(rebasing: basePath.dropFirst()))
        return
      }
      basePath = basePath[..<(basePath.lastIndex(of: ASCII.forwardSlash.codePoint) ?? basePath.startIndex)]

      while var componentTerminatorIndex = basePath.lastIndex(of: ASCII.forwardSlash.codePoint) {
        let pathComponent = basePath[basePath.index(after: componentTerminatorIndex)..<basePath.endIndex]
        defer { basePath = basePath.prefix(upTo: componentTerminatorIndex) }

        assert(PathComponentParser.isDoubleDotPathSegment(pathComponent) == false)
        assert(PathComponentParser.isSingleDotPathSegment(pathComponent) == false)

        switch pathComponent {
        // If the base path has a Windows drive letter, we can flush everything and end.
        case _
        where componentTerminatorIndex == basePath.startIndex && isFileScheme
          && PathComponentParser.isNormalizedWindowsDriveLetter(pathComponent):
          __flushDeferredComponent(&deferredComponent, &state)
          visitBasePathComponent(UnsafeBufferPointer(rebasing: pathComponent))
          return
        case _ where state.popcount != 0:
          state.popcount -= 1
        case _ where deferredComponent?.isPotentialWindowsDrive == true:
          __flushDeferredComponent(&deferredComponent, &state)
          componentTerminatorIndex = pathComponent.endIndex
          continue
        default:
          if pathComponent.isEmpty {
            __deferTrailingEmptyAssert(&deferredComponent, &state)
          } else {
            __flushDeferredEmptiesAssert(&deferredComponent, &state)
            visitBasePathComponent(UnsafeBufferPointer(rebasing: pathComponent))
            state.didYieldComponent = true
          }
        }
      }
      assert(basePath.isEmpty, "Normalized base paths must start with a /")
      __flushDeferredComponentForFinalization(&deferredComponent, &state)
      return  // Finally done!
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
    baseURL: WebURL?,
    absolutePathsCopyWindowsDriveFromBase: Bool
  ) where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    var parser = Parser<InputString>()
    parser.walkPathComponents(
      pathString: input, schemeKind: schemeKind, baseURL: baseURL,
      absolutePathsCopyWindowsDriveFromBase: absolutePathsCopyWindowsDriveFromBase)
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
      _ pathComponent: InputString.SubSequence, isWindowsDriveLetter: Bool
    ) {
      metrics.numberOfComponents += 1
      metrics.requiredCapacity += 1  // "/"
      for byteGroup in pathComponent.lazy.percentEncoded(using: URLEncodeSet.Path.self) {
        if case .percentEncodedByte = byteGroup {
          metrics.needsEscaping = true
        }
        metrics.requiredCapacity += byteGroup.count
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
    absolutePathsCopyWindowsDriveFromBase: Bool,
    needsEscaping: Bool = true
  ) -> Int where InputString: BidirectionalCollection, InputString.Element == UInt8 {
    return PathWriter.writePath(
      to: self, pathString: input, schemeKind: schemeKind, baseURL: baseURL,
      ignoreWindowsDriveLetterFromInputString: absolutePathsCopyWindowsDriveFromBase,
      needsEscaping: needsEscaping
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
      ignoreWindowsDriveLetterFromInputString: Bool,
      needsEscaping: Bool = true
    ) -> Int {
      // Checking this now allows the implementation to use `.baseAddress.unsafelyUnwrapped`.
      precondition(buffer.baseAddress != nil)
      var visitor = PathWriter(buffer: buffer, front: buffer.endIndex, needsEscaping: needsEscaping)
      visitor.walkPathComponents(
        pathString: input,
        schemeKind: schemeKind,
        baseURL: baseURL,
        absolutePathsCopyWindowsDriveFromBase: ignoreWindowsDriveLetterFromInputString
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
      _ pathComponent: InputString.SubSequence, isWindowsDriveLetter: Bool
    ) {
      guard pathComponent.isEmpty == false else {
        prependSlash()
        return
      }
      guard isWindowsDriveLetter == false else {
        assert(pathComponent.count == 2)
        front = buffer.index(front, offsetBy: -2)
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: front).initialize(to: pathComponent[pathComponent.startIndex])
        buffer.baseAddress.unsafelyUnwrapped.advanced(by: front &+ 1).initialize(to: ASCII.colon.codePoint)
        prependSlash()
        return
      }
      if needsEscaping {
        for byteGroup in pathComponent.reversed().lazy.percentEncoded(using: URLEncodeSet.Path.self) {
          switch byteGroup {
          case .percentEncodedByte:
            (buffer.baseAddress.unsafelyUnwrapped + front - 3).initialize(to: byteGroup[0])
            (buffer.baseAddress.unsafelyUnwrapped + front - 2).initialize(to: byteGroup[1])
            (buffer.baseAddress.unsafelyUnwrapped + front - 1).initialize(to: byteGroup[2])
            front &-= 3
          case .sourceByte(let byte), .substitutedByte(let byte):
            (buffer.baseAddress.unsafelyUnwrapped + front - 1).initialize(to: byte)
            front &-= 1
          }
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
    visitor.walkPathComponents(
      pathString: input, schemeKind: schemeKind, baseURL: nil,
      absolutePathsCopyWindowsDriveFromBase: false)
  }

  fileprivate mutating func visitInputPathComponent(
    _ pathComponent: InputString.SubSequence, isWindowsDriveLetter: Bool
  ) {
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

  fileprivate mutating func visitValidationError(_ error: ValidationError) {
    callback.validationError(error)
  }
}


// MARK: - Path Utilities


/// A namespace for functions relating to parsing of path components.
///
enum PathComponentParser<T> where T: Collection, T.Element == UInt8 {

  /// A Windows drive letter is two code points, of which the first is an ASCII alpha and the second is either U+003A (:) or U+007C (|).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  static func isWindowsDriveLetter(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard let byte1 = it.next(), ASCII(byte1)?.isAlpha == true else { return false }
    guard let byte2 = it.next(), ASCII(byte2) == .colon || ASCII(byte2) == .verticalBar else { return false }
    guard it.next() == nil else { return false }
    return true
  }

  /// A normalized Windows drive letter is a Windows drive letter of which the second code point is U+003A (:).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  static func isNormalizedWindowsDriveLetter(_ bytes: T) -> Bool {
    isWindowsDriveLetter(bytes) && (bytes.dropFirst().first.map { ASCII($0) == .colon } ?? false)
  }

  /// A string starts with a Windows drive letter if all of the following are true:
  ///
  /// - its length is greater than or equal to 2
  /// - its first two code points are a Windows drive letter
  /// - its length is 2 or its third code point is U+002F (/), U+005C (\), U+003F (?), or U+0023 (#).
  ///
  /// https://url.spec.whatwg.org/#url-miscellaneous
  ///
  static func hasWindowsDriveLetterPrefix(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard let byte1 = it.next(), ASCII(byte1)?.isAlpha == true else { return false }
    guard let byte2 = it.next(), ASCII(byte2) == .colon || ASCII(byte2) == .verticalBar else { return false }
    guard let byte3 = it.next() else { return true }
    switch ASCII(byte3) {
    case .forwardSlash?, .backslash?, .questionMark?, .numberSign?: return true
    default: return false
    }
  }

  /// Returns `true` if the next contents of `iterator` are either the ASCII byte U+002E (.), the string "%2e", or "%2E".
  /// Otherwise, `false`.
  ///
  private static func checkForDotOrCaseInsensitivePercentEncodedDot(in iterator: inout T.Iterator) -> Bool {
    guard let byte1 = iterator.next(), let ascii1 = ASCII(byte1) else { return false }
    if ascii1 == .period { return true }
    guard ascii1 == .percentSign,
      let byte2 = iterator.next(), ASCII(byte2) == .n2,
      let byte3 = iterator.next(), ASCII(byte3) == .E || ASCII(byte3) == .e
    else {
      return false
    }
    return true
  }

  /// Returns `true` if `bytes` contains a single U+002E (.), the ASCII string "%2e" or "%2E" only.
  /// Otherwise, `false`.
  ///
  static func isSingleDotPathSegment(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
    guard it.next() == nil else { return false }
    return true
  }

  /// Returns `true` if `bytes` contains two of either U+002E (.), the ASCII string "%2e" or "%2E" only.
  /// Otherwise, `false`.
  ///
  static func isDoubleDotPathSegment(_ bytes: T) -> Bool {
    var it = bytes.makeIterator()
    guard checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
    guard checkForDotOrCaseInsensitivePercentEncodedDot(in: &it) else { return false }
    guard it.next() == nil else { return false }
    return true
  }

  /// Returns `true` if the given normalized path requires a path sigil when written to a URL that does not have an authority sigil.
  ///
  static func doesNormalizedPathRequirePathSigil(_ path: T) -> Bool {
    var iter = path.makeIterator()
    guard iter.next() == ASCII.forwardSlash.codePoint, iter.next() == ASCII.forwardSlash.codePoint else {
      return false
    }
    return true
  }
}
