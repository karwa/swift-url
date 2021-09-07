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

/// An interface through which `ParsedURLString` writes a normalized URL string.
///
/// `ParsedURLString` will call the `write...` functions implemented by conformers to this protocol, writing the UTF-8 code-units of each component,
///  in the order in which they appear in the final string. Conformers are required to ensure that all code-units are written without loss.
///
@usableFromInline
internal protocol URLWriter: HostnameWriter {

  /// Notes the given information about the URL. This is always the first function to be called.
  ///
  mutating func writeFlags(schemeKind: WebURL.SchemeKind, isHierarchical: Bool)

  /// A function which writes a piece of a component.
  ///
  /// Functions using this pattern typically look like the following:
  /// ```swift
  /// func writeUsername<T>(_ usernameWriter: (PieceWriter<T>)->Void)
  /// ```
  ///
  /// Callers invoke this function with a closure, which is passed a `PieceWriter` through which it can write its contents iteratively, incorporating its own
  /// control-flow and using whichever `Collection` type is convenient.
  /// ```swift
  /// writeUsername { writePiece in
  ///   for piece in ... {
  ///     writePiece(piece)
  ///   }
  /// }
  /// ```
  ///
  typealias PieceWriter<T> = (T) -> Void

  /// Appends the given UTF-8 code-units to the URL string, followed by the scheme separator character (`:`).
  /// This is always the first call to the writer after `writeFlags`.
  ///
  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8

  /// Appends the authority header (`//`) to the URL string.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  ///
  mutating func writeAuthoritySigil()

  /// Appends the path sigil (`/.`) to the URL string.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  ///
  mutating func writePathSigil()

  /// Appends the UTF-8 code-units provided by `usernameWriter` to the URL string.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeAuthoritySigil`.
  ///
  /// Note that `usernameWriter` is not guaranteed to be invoked.
  ///
  mutating func writeUsernameContents<T>(
    _ usernameWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8

  /// Appends the password separator character (`:`), followed by the UTF-8 code-units provided by `passwordWriter`, to the URL string.
  /// The content must already be percent-encoded and not include any separators.
  ///
  /// Note that `passwordWriter` is not guaranteed to be invoked.
  ///
  mutating func writePasswordContents<T>(
    _ passwordWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8

  /// Appends the credential terminator byte (`@`) to the URL string.
  /// If called, this must always be the immediate successor to either `writeUsernameContents` or `writePasswordContents`.
  ///
  mutating func writeCredentialsTerminator()

  /// Appends the UTF-8 code-units given by `hostnameWriter` to the URL string.
  /// The content must already be percent-encoded/IDNA-transformed and not include any separators.
  /// If called, this must always have been preceded by a call to `writeAuthoritySigil`.
  ///
  /// Note that `hostnameWriter` is not guaranteed to be invoked.
  ///
  mutating func writeHostname<T>(
    lengthIfKnown: Int?, _ hostnameWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8

  /// Appends the port separator character (`:`), followed by the textual representation of the given port number, to the URL string.
  /// If called, this must always be the immediate successor to `writeHostname`.
  ///
  mutating func writePort(_ port: UInt16)

  /// Appends an entire authority string (username + password + hostname + port) to the URL string.
  /// The content must already be percent-encoded/IDNA-transformed.
  /// If called, this must always be the immediate successor to `writeAuthoritySigil`.
  ///
  /// - important: `passwordLength` and `portLength` include their required leading separators (so a port component of `:8080` has a length of 5).
  ///
  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  )

  /// Appends the UTF-8 code-units given by `writer` to the URL string.
  /// The content must already be percent-encoded. No separators are added before or after the content.
  ///
  /// Note that `writer` is not guaranteed to be invoked.
  ///
  mutating func writePath<T>(
    firstComponentLength: Int, _ writer: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8

  /// Appends a path of size `length`, which may be initialized by `writer`, to the URL string.
  /// The `writer` closure must initialize all bytes from `0..<length`, and should return an independently-calculated measure of the number of bytes it wrote.
  /// The content must already be percent-encoded. No separators are added before or after the content.
  ///
  /// Note that `writer` is not guaranteed to be invoked.
  ///
  mutating func writePresizedPathUnsafely(
    length: Int, firstComponentLength: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  )

  /// Appends the query separator character (`?`), followed by the UTF-8 code-units provided by `queryWriter`, to the URL string.
  /// The content must already be percent-encoded.
  ///
  /// Note that `queryWriter` is not guaranteed to be invoked.
  ///
  mutating func writeQueryContents<T>(
    isKnownFormEncoded: Bool, _ queryWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8

  /// Appends the fragment separator character (`#`), followed by the UTF-8 code-units provided by `fragmentWriter`, to the URL string.
  /// The content must already be percent-encoded.
  ///
  /// Note that `fragmentWriter` is not guaranteed to be invoked.
  ///
  mutating func writeFragmentContents<T>(
    _ fragmentWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8

  // Optional callbacks.

  /// Optional function which informs the writer that the URL has completed writing. No more content or hints will be written after this function is called.
  /// The default implementation does nothing.
  ///
  mutating func finalize()

  // Optional hints.

  /// Optional function which asks the writer whether it happens to know that the given component may skip percent-encoding.
  ///
  /// The default implementation returns `false`.
  ///
  func getHint(maySkipPercentEncoding component: WebURL.Component) -> Bool

  /// Optional function which notes that the given component did not require percent-encoding when writing from the input-string.
  /// This doesn't mean that the component does not _contain_ any percent-encoded contents, only that we don't need to perform an
  /// additional level of encoding when writing.
  ///
  /// Conformers may wish to store and share this information, in case they wish to write the same contents using another `URLWriter`.
  /// The default implementation does nothing.
  ///
  mutating func writeHint(_ component: WebURL.Component, maySkipPercentEncoding: Bool)

  /// Optional function which asks the writer whether it happens to have `PathMetrics` for the URL which is being written.
  ///
  /// The default implementation returns `nil`.
  ///
  func getPathMetricsHint() -> PathMetrics?

  /// Optional function which takes note of metrics collected while writing the URL's path component.
  ///
  /// Conformers may wish to store and share this information, in case they wish to write the same contents using another `URLWriter`.
  /// The default implementation does nothing.
  ///
  mutating func writePathMetricsHint(_ pathMetrics: PathMetrics)
}

extension URLWriter {

  @inlinable
  internal mutating func writeQueryContents<T>(
    _ queryWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    writeQueryContents(isKnownFormEncoded: false, queryWriter)
  }

  @inlinable
  internal mutating func finalize() {
    // Not required.
  }

  @inlinable
  internal func getHint(maySkipPercentEncoding component: WebURL.Component) -> Bool {
    false
  }

  @inlinable
  internal mutating func writeHint(_ component: WebURL.Component, maySkipPercentEncoding: Bool) {
    // Not required.
  }

  @inlinable
  internal func getPathMetricsHint() -> PathMetrics? {
    nil
  }

  @inlinable
  internal mutating func writePathMetricsHint(_ pathMetrics: PathMetrics) {
    // Not required.
  }
}

/// Stored hints about how to write a particular URL string.
///
@usableFromInline
internal struct URLWriterHints {

  /// If set, contains information about the number of code-units in the path, number of path components, etc.
  /// If not set, users may make no assumptions about the path.
  ///
  @usableFromInline
  internal var pathMetrics: PathMetrics?

  /// Components which are known to not require percent-encoding.
  /// If a component is not in this set, users must assume that it requires percent-encoding.
  ///
  @usableFromInline
  internal var componentsWhichMaySkipPercentEncoding: WebURL.ComponentSet

  @inlinable
  internal init() {
    self.pathMetrics = nil
    self.componentsWhichMaySkipPercentEncoding = []
  }
}


// --------------------------------------------
// MARK: - Writers
// --------------------------------------------


/// A `URLWriter` which does not actually write to any storage, only gathering information about what the URL string looks like.
///
/// This type cannot be instantiated directly. Use the `StructureAndMetricsCollector.collect { ... }` function
/// to obtain an instance, write to it, and collect its results.
///
@usableFromInline
internal struct StructureAndMetricsCollector: URLWriter {

  // Note: requiredCapacity must always use arithmetic which traps on overflow,
  //       as 'UnsafePresizedBufferWriter' relies on this fact being verified for memory safety.
  @usableFromInline
  internal private(set) var requiredCapacity: Int

  @usableFromInline
  internal private(set) var structure: URLStructure<Int>

  @usableFromInline
  internal private(set) var hints: URLWriterHints

  /// Creates a new structure and metrics collector, initially representing an invalid, empty URL string.
  ///
  /// - important: Do not use the returned instance's data until an URL string has been written to it.
  ///
  @inlinable
  internal init() {
    self.requiredCapacity = 0
    self.structure = .invalidEmptyStructure()
    self.hints = URLWriterHints()
  }

  @inlinable
  internal mutating func writeFlags(schemeKind: WebURL.SchemeKind, isHierarchical: Bool) {
    structure.schemeKind = schemeKind
    structure.isHierarchical = isHierarchical
  }

  @inlinable
  internal mutating func writeSchemeContents<T>(
    _ schemeBytes: T
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.schemeLength == 0)
    structure.schemeLength = schemeBytes.count + 1 /* ":" */
    requiredCapacity = structure.schemeLength
  }

  @inlinable
  internal mutating func writeAuthoritySigil() {
    assert(structure.sigil == .none)
    structure.sigil = .authority
    requiredCapacity += Int(Sigil.authority.length)
  }

  @inlinable
  internal mutating func writePathSigil() {
    assert(structure.sigil == .none)
    structure.sigil = .path
    requiredCapacity += Int(Sigil.path.length)
  }

  @inlinable
  internal mutating func writeUsernameContents<T>(
    _ usernameWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.usernameLength == 0)
    usernameWriter { structure.usernameLength += $0.count }
    requiredCapacity += structure.usernameLength
  }

  @inlinable
  internal mutating func writePasswordContents<T>(
    _ passwordWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.passwordLength == 0)
    structure.passwordLength = 1
    passwordWriter { structure.passwordLength += $0.count }
    requiredCapacity += structure.passwordLength
  }

  @inlinable
  internal mutating func writeCredentialsTerminator() {
    requiredCapacity += 1
  }

  @inlinable
  internal mutating func writeHostname<T>(
    lengthIfKnown: Int?, _ hostnameWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.hostnameLength == 0)
    if let knownLength = lengthIfKnown {
      structure.hostnameLength = knownLength
      requiredCapacity += structure.hostnameLength
    } else {
      hostnameWriter { structure.hostnameLength += $0.count }
      requiredCapacity += structure.hostnameLength
    }
  }

  @inlinable
  internal mutating func writePort(_ port: UInt16) {

    assert(structure.portLength == 0)
    structure.portLength = 1 /* ":" */
    switch port {
    case 10000...UInt16.max: structure.portLength += 5
    case 1000..<10000: structure.portLength += 4
    case 100..<1000: structure.portLength += 3
    case 10..<100: structure.portLength += 2
    default /* 0..<10 */: structure.portLength += 1
    }
    requiredCapacity += structure.portLength
  }

  @inlinable
  internal mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  ) {

    assert(structure.usernameLength == 0 && structure.passwordLength == 0)
    assert(structure.hostnameLength == 0 && structure.portLength == 0)
    structure.usernameLength = usernameLength
    structure.passwordLength = passwordLength
    structure.hostnameLength = hostnameLength
    structure.portLength = portLength
    requiredCapacity += authority.count
  }

  @inlinable
  internal mutating func writePath<T>(
    firstComponentLength: Int, _ writer: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.firstPathComponentLength == 0)
    assert(structure.pathLength == 0)
    structure.firstPathComponentLength = firstComponentLength
    writer { structure.pathLength += $0.count }
    requiredCapacity += structure.pathLength
  }

  @inlinable
  internal mutating func writePresizedPathUnsafely(
    length: Int, firstComponentLength: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {

    assert(structure.firstPathComponentLength == 0)
    assert(structure.pathLength == 0)
    structure.firstPathComponentLength = firstComponentLength
    structure.pathLength = length
    requiredCapacity += length
  }

  @inlinable
  internal mutating func writeQueryContents<T>(
    isKnownFormEncoded: Bool, _ queryWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.queryLength == 0)
    structure.queryLength = 1 /* "?" */
    queryWriter { structure.queryLength += $0.count }
    structure.queryIsKnownFormEncoded = isKnownFormEncoded
    requiredCapacity += structure.queryLength
  }

  @inlinable
  internal mutating func writeFragmentContents<T>(
    _ fragmentWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {

    assert(structure.fragmentLength == 0)
    structure.fragmentLength = 1
    fragmentWriter { structure.fragmentLength += $0.count }
    requiredCapacity += structure.fragmentLength
  }

  @inlinable
  internal mutating func finalize() {
    precondition(requiredCapacity >= 0)
    if structure.queryIsKnownFormEncoded == false {
      // Empty and nil queries are considered form-encoded (i.e. they do not need to be re-encoded).
      structure.queryIsKnownFormEncoded = (structure.queryLength == 0 || structure.queryLength == 1)
    }
    structure.checkInvariants()
  }

  // Hints.

  @inlinable
  internal mutating func writeHint(_ component: WebURL.Component, maySkipPercentEncoding: Bool) {
    hints.componentsWhichMaySkipPercentEncoding[component] = maySkipPercentEncoding
  }

  @inlinable
  internal mutating func writePathMetricsHint(_ pathMetrics: PathMetrics) {
    hints.pathMetrics = pathMetrics
  }
}

/// A `URLWriter` which writes a URL string to a pre-sized mutable buffer.
///
/// The buffer must have precisely the correct capacity to store the URL string, or a runtime error will be triggered.  This implies that its address may not be `nil`.
/// The fact that the exact capacity is known (and `URLWriterHints` available) is taken as proof that the number of bytes written will not overflow an `Int`.
///
@usableFromInline
internal struct UnsafePresizedBufferWriter: URLWriter {

  @usableFromInline
  internal let buffer: UnsafeMutableBufferPointer<UInt8>

  @usableFromInline
  internal private(set) var bytesWritten: Int

  @usableFromInline
  internal let knownHints: URLWriterHints

  @inlinable
  internal init(buffer: UnsafeMutableBufferPointer<UInt8>, hints: URLWriterHints) {
    self.buffer = buffer
    self.bytesWritten = 0
    self.knownHints = hints
    precondition(buffer.baseAddress != nil, "Invalid buffer")
  }

  @inlinable
  internal mutating func _writeByte(_ byte: UInt8) {
    assert(bytesWritten < buffer.count)
    (buffer.baseAddress.unsafelyUnwrapped + bytesWritten).initialize(to: byte)
    bytesWritten &+= 1
  }

  @inlinable
  internal mutating func _writeByte(_ byte: UInt8, count: Int) {
    assert(bytesWritten < buffer.count || count == 0)
    (buffer.baseAddress.unsafelyUnwrapped + bytesWritten).initialize(repeating: byte, count: count)
    bytesWritten &+= count
  }

  @inlinable
  internal mutating func _writeBytes<T>(_ bytes: T) where T: Collection, T.Element == UInt8 {
    assert(bytesWritten < buffer.count || bytes.isEmpty)
    let count = UnsafeMutableBufferPointer(
      start: buffer.baseAddress.unsafelyUnwrapped + bytesWritten,
      count: buffer.count &- bytesWritten
    ).fastInitialize(from: bytes)
    bytesWritten &+= count
  }

  // URLWriter.

  @inlinable
  internal mutating func writeFlags(schemeKind: WebURL.SchemeKind, isHierarchical: Bool) {
    // This writer does not calculate a URLStructure.
  }

  @inlinable
  internal mutating func writeSchemeContents<T>(
    _ schemeBytes: T
  ) where T: Collection, T.Element == UInt8 {
    _writeBytes(schemeBytes)
    _writeByte(ASCII.colon.codePoint)
  }

  @inlinable
  internal mutating func writeAuthoritySigil() {
    _writeByte(ASCII.forwardSlash.codePoint, count: 2)
  }

  @inlinable
  internal mutating func writePathSigil() {
    _writeByte(ASCII.forwardSlash.codePoint)
    _writeByte(ASCII.period.codePoint)
  }

  @inlinable
  internal mutating func writeUsernameContents<T>(
    _ usernameWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    usernameWriter { _writeBytes($0) }
  }

  @inlinable
  internal mutating func writePasswordContents<T>(
    _ passwordWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    _writeByte(ASCII.colon.codePoint)
    passwordWriter { _writeBytes($0) }
  }

  @inlinable
  internal mutating func writeCredentialsTerminator() {
    _writeByte(ASCII.commercialAt.codePoint)
  }

  @inlinable
  internal mutating func writeHostname<T>(
    lengthIfKnown: Int?, _ hostnameWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    hostnameWriter { _writeBytes($0) }
  }

  @inlinable
  internal mutating func writePort(_ port: UInt16) {
    _writeByte(ASCII.colon.codePoint)
    let rawPointer = UnsafeMutableRawPointer(buffer.baseAddress.unsafelyUnwrapped + bytesWritten)
    bytesWritten &+= Int(ASCII.writeDecimalString(for: port, to: rawPointer))
  }

  @inlinable
  internal mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  ) {
    _writeBytes(authority)
  }

  @inlinable
  internal mutating func writePath<T>(
    firstComponentLength: Int, _ writer: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    writer { _writeBytes($0) }
  }

  @inlinable
  internal mutating func writePresizedPathUnsafely(
    length: Int, firstComponentLength: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    let space = UnsafeMutableBufferPointer(start: buffer.baseAddress.unsafelyUnwrapped + bytesWritten, count: length)
    let pathBytesWritten = writer(space)
    assert(pathBytesWritten == length)
    bytesWritten &+= pathBytesWritten
  }

  @inlinable
  internal mutating func writeQueryContents<T>(
    isKnownFormEncoded: Bool, _ queryWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    _writeByte(ASCII.questionMark.codePoint)
    queryWriter { _writeBytes($0) }
  }

  @inlinable
  internal mutating func writeFragmentContents<T>(
    _ fragmentWriter: (PieceWriter<T>) -> Void
  ) where T: Collection, T.Element == UInt8 {
    _writeByte(ASCII.numberSign.codePoint)
    fragmentWriter { _writeBytes($0) }
  }

  @inlinable
  internal func finalize() {
    precondition(bytesWritten == buffer.count)
  }

  // Hints.

  @inlinable
  internal func getHint(maySkipPercentEncoding component: WebURL.Component) -> Bool {
    knownHints.componentsWhichMaySkipPercentEncoding[component]
  }

  @inlinable
  internal func getPathMetricsHint() -> PathMetrics? {
    knownHints.pathMetrics
  }
}


// --------------------------------------------
// MARK: - HostnameWriter
// --------------------------------------------


/// An interface through which a `ParsedHost` writes its contents.
///
@usableFromInline
internal protocol HostnameWriter {

  /// Writes the bytes given by `hostnameWriter`.
  /// The content must already be percent-encoded/IDNA-transformed and not include any separators.
  ///
  mutating func writeHostname<T>(
    lengthIfKnown: Int?, _ hostnameWriter: ((T) -> Void) -> Void
  ) where T: Collection, T.Element == UInt8
}

/// A `HostnameWriter` which computes the length of the hostname, were it to be written.
///
@usableFromInline
internal struct HostnameLengthCounter: HostnameWriter {

  @usableFromInline
  internal private(set) var length: Int

  @inlinable
  internal init() {
    self.length = 0
  }

  @inlinable
  internal mutating func writeHostname<T>(
    lengthIfKnown: Int?, _ writerFunc: ((T) -> Void) -> Void
  ) where T: Collection, T.Element == UInt8 {
    if let knownLength = lengthIfKnown {
      length = knownLength
      return
    }
    writerFunc { piece in
      length += piece.count
    }
  }
}

/// A `HostnameWriter` which writes a hostname to a given buffer.
/// After writing, the buffer points to the space after written hostname.
///
@usableFromInline
internal struct UnsafeBufferHostnameWriter: HostnameWriter {

  @usableFromInline
  internal private(set) var buffer: UnsafeMutableBufferPointer<UInt8>

  @inlinable
  internal init(buffer: UnsafeMutableBufferPointer<UInt8>) {
    self.buffer = buffer
  }

  @inlinable
  internal mutating func writeHostname<T>(
    lengthIfKnown: Int?, _ writerFunc: ((T) -> Void) -> Void
  ) where T: Collection, T.Element == UInt8 {
    writerFunc { piece in
      let n = buffer.fastInitialize(from: piece)
      buffer = UnsafeMutableBufferPointer(rebasing: buffer.suffix(from: n))
    }
  }
}
