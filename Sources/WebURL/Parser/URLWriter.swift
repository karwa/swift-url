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

/// An interface through which `ParsedURLString` constructs a new URL object.
///
/// Conformers accept UTF8 bytes as given by the construction function, write them to storage, and mark
/// relevant information in a header structure.
///
/// Conformers may be specialised to only accepting certain kinds of URLs - and they might, for example, omit or replace certain fields
/// in their header structures for their use-case.
///
protocol URLWriter {

  /// Notes the given information about the URL. This is always the first function to be called.
  ///
  mutating func writeFlags(schemeKind: WebURL.SchemeKind, cannotBeABaseURL: Bool)

  /// A function which appends the given bytes to storage.
  ///
  /// Functions using this pattern typically look like the following:
  /// ```swift
  /// func writeUsername<T>(_ usernameWriter: (WriterFunc<T>)->Void)
  /// ```
  ///
  /// Callers typically use this as shown:
  /// ```swift
  /// writeUsername { writeBytes in
  ///   newValue.lazy.percentEncoded(using: ...).write(to: writeBytes)
  /// }
  /// ```
  /// in this example, `writePiece` is a `WriterFunc`, and its type is inferred as `(UnsafeBufferPointer<UInt8>)->Void`.
  ///
  typealias WriterFunc<T> = (T) -> Void

  /// Appends the given bytes to storage, followed by the scheme separator character (`:`).
  /// This is always the first call to the writer after `writeFlags`.
  ///
  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8

  /// Appends the authority header (`//`) to storage.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  ///
  mutating func writeAuthoritySigil()

  /// Appends the path sigil (`/.`) to storage.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  ///
  mutating func writePathSigil()

  /// Appends the bytes provided by `usernameWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeAuthoritySigil`.
  ///
  mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends the password separator character (`:`), followed by the bytes provided by `passwordWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeUsernameContents`.
  ///
  mutating func writePasswordContents<T>(_ passwordWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends the credential terminator byte (`@`).
  /// If called, this must always be the immediate successor to either `writeUsernameContents` or `writePasswordContents`.
  ///
  mutating func writeCredentialsTerminator()

  /// Appends the bytes given by `hostnameWriter`.
  /// The content must already be percent-encoded/IDNA-transformed and not include any separators.
  /// If called, this must always have been preceded by a call to `writeAuthoritySigil`.
  ///
  mutating func writeHostname<T>(_ hostnameWriter: (WriterFunc<T>) -> Void) where T: Collection, T.Element == UInt8

  /// Appends the port separator character (`:`), followed by the textual representation of the given port number to storage.
  /// If called, this must always be the immediate successor to `writeHostname`.
  ///
  mutating func writePort(_ port: UInt16)

  /// Appends an entire authority string (username + password + hostname + port) to storage.
  /// The content must already be percent-encoded/IDNA-transformed.
  /// If called, this must always be the immediate successor to `writeAuthoritySigil`.
  ///
  /// - important: `passwordLength` and `portLength` include their required leading separators (so a port component of `:8080` has a length of 5).
  ///
  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  )

  /// Appends the bytes given by `writer`.
  /// The content must already be percent-encoded. No separators are added before or after the content.
  ///
  mutating func writePath<T>(firstComponentLength: Int, _ writer: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends an uninitialized space of size `length` and calls the given closure to allow for the path content to be written out of order.
  /// The `writer` closure must return the number of bytes written (`bytesWritten`), and all bytes from `0..<bytesWritten` must be initialized.
  /// Content written in to the buffer must already be percent-encoded. No separators are added before or after the content.
  ///
  mutating func writeUnsafePath(
    length: Int, firstComponentLength: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  )

  /// Appends the query separator character (`?`), followed by the bytes provided by `queryWriter`.
  /// The content must already be percent-encoded.
  ///
  mutating func writeQueryContents<T>(_ queryWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends the fragment separator character (`#`), followed by the bytes provided by `fragmentWriter`
  /// The content must already be percent-encoded.
  ///
  mutating func writeFragmentContents<T>(_ fragmentWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  // Optional hints.

  /// Optional function which notes that the given component did not require percent-encoding when writing from the input-string.
  /// This doesn't mean that the component does not _contain_ any percent-encoded contents, only that we don't need to perform an
  /// additional level of encoding when writing.
  ///
  /// Conformers may wish to note this information, in case they wish to write the same contents using another `URLWriter`.
  /// The default implementation does nothing.
  ///
  mutating func writeHint(_ component: WebURL.Component, needsEscaping: Bool)

  /// Optional function which takes note of metrics collected while writing the URL's path component.
  /// Conformers may wish to note this information, in case they wish to write the same contents using another `URLWriter`.
  /// The default implementation does nothing.
  ///
  mutating func writePathMetricsHint(_ pathMetrics: PathMetrics)

  /// Optional function which informs the writer that the URL has completed writing. No more content or hints will be written after this function is called.
  ///
  mutating func finalize()
}

extension URLWriter {

  mutating func writeHint(_ component: WebURL.Component, needsEscaping: Bool) {
    // Not required.
  }
  mutating func writePathMetricsHint(_ pathMetrics: PathMetrics) {
    // Not required.
  }
  mutating func finalize() {
    // Not required.
  }
}

// MARK: - URLWriters.

/// Information which is used to determine how a URL should be stored or written.
///
struct URLMetrics {

  /// If set, contains information about the number of code-units in the path, number of path components, etc.
  /// If not set, users may make no assumptions about the path.
  var pathMetrics: PathMetrics? = nil

  /// Components which are known to not require percent-encoding.
  /// If a component is not in this set, users must assume that it requires percent-encoding.
  var componentsWhichMaySkipEscaping: WebURL.ComponentSet = []
}

/// A `URLWriter` which does not actually write to any storage, and gathers information about
/// what the result looks like (its `URLStructure` and `URLMetrics`).
///
/// This type cannot be instantiated directly. Use the `StructureAndMetricsCollector.collect { ... }` function
/// to obtain an instance, write to it, and collect its results.
///
struct StructureAndMetricsCollector: URLWriter {
  private var requiredCapacity: Int = 0
  private var metrics = URLMetrics()
  private var structure = URLStructure<Int>.invalidEmptyStructure()

  private init() {}

  static func collect(
    _ body: (inout StructureAndMetricsCollector) -> Void
  ) -> (requiredCapacity: Int, structure: URLStructure<Int>, metrics: URLMetrics) {
    var collector = StructureAndMetricsCollector()
    body(&collector)
    precondition(collector.requiredCapacity >= 0)
    return (collector.requiredCapacity, collector.structure, collector.metrics)
  }

  mutating func writeFlags(schemeKind: WebURL.SchemeKind, cannotBeABaseURL: Bool) {
    structure.schemeKind = schemeKind
    structure.cannotBeABaseURL = cannotBeABaseURL
  }

  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8 {
    structure.schemeLength = schemeBytes.count + 1
    requiredCapacity = structure.schemeLength
  }

  mutating func writeAuthoritySigil() {
    precondition(structure.sigil == .none)
    structure.sigil = .authority
    requiredCapacity += Sigil.authority.length
  }

  mutating func writePathSigil() {
    precondition(structure.sigil == .none)
    structure.sigil = .path
    requiredCapacity += Sigil.path.length
  }

  mutating func writeUsernameContents<T>(_ usernameWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    structure.usernameLength = 0
    usernameWriter {
      structure.usernameLength += $0.count
    }
    requiredCapacity += structure.usernameLength
  }

  mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    structure.passwordLength = 1
    passwordWriter {
      structure.passwordLength += $0.count
    }
    requiredCapacity += structure.passwordLength
  }

  mutating func writeCredentialsTerminator() {
    requiredCapacity += 1
  }

  mutating func writeHostname<T>(_ hostnameWriter: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
    structure.hostnameLength = 0
    hostnameWriter {
      structure.hostnameLength += $0.count
    }
    requiredCapacity += structure.hostnameLength
  }

  mutating func writePort(_ port: UInt16) {
    structure.portLength = 1
    switch port {
    case 10000...UInt16.max: structure.portLength += 5
    case 1000..<10000: structure.portLength += 4
    case 100..<1000: structure.portLength += 3
    case 10..<100: structure.portLength += 2
    case 0..<10: structure.portLength += 1
    default: preconditionFailure()
    }
    requiredCapacity += structure.portLength
  }

  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  ) {
    structure.usernameLength = usernameLength
    structure.passwordLength = passwordLength
    structure.hostnameLength = hostnameLength
    structure.portLength = portLength
    requiredCapacity += authority.count
  }

  mutating func writePath<T>(firstComponentLength: Int, _ writer: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    structure.firstPathComponentLength = firstComponentLength
    structure.pathLength = 0
    writer {
      structure.pathLength += $0.count
    }
    requiredCapacity += structure.pathLength
  }

  mutating func writeUnsafePath(
    length: Int, firstComponentLength: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    structure.firstPathComponentLength = firstComponentLength
    structure.pathLength = length
    requiredCapacity += length
  }

  mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    structure.queryLength = 1
    queryWriter {
      structure.queryLength += $0.count
    }
    requiredCapacity += structure.queryLength
  }

  mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    structure.fragmentLength = 1
    fragmentWriter {
      structure.fragmentLength += $0.count
    }
    requiredCapacity += structure.fragmentLength
  }

  // Hints.

  mutating func writeHint(_ component: WebURL.Component, needsEscaping: Bool) {
    if needsEscaping == false {
      metrics.componentsWhichMaySkipEscaping.insert(component)
    }
  }

  mutating func writePathMetricsHint(_ pathMetrics: PathMetrics) {
    metrics.pathMetrics = pathMetrics
  }

  mutating func finalize() {
    // Empty and nil queries are considered form-encoded (i.e. they do not need to be re-encoded).
    structure.queryIsKnownFormEncoded = (structure.queryLength == 0 || structure.queryLength == 1)
    structure.checkInvariants()
  }
}

/// A `URLWriter` which writes to a pre-sized mutable buffer.
///
/// The buffer **must** have sufficient capacity to store the entire result,
/// as this writer is free to omit bounds checking in release build configurations.
///
struct UnsafePresizedBufferWriter: URLWriter {
  private(set) var bytesWritten: Int
  let buffer: UnsafeMutableBufferPointer<UInt8>

  init(buffer: UnsafeMutableBufferPointer<UInt8>) {
    self.bytesWritten = 0
    self.buffer = buffer
    precondition(buffer.baseAddress != nil, "Invalid buffer")
  }

  // Underlying buffer-writing functions.

  private mutating func writeByte(_ byte: UInt8) {
    assert(bytesWritten < buffer.count)
    (buffer.baseAddress.unsafelyUnwrapped + bytesWritten).pointee = byte
    bytesWritten += 1
  }
  private mutating func writeByte(_ byte: UInt8, count: Int) {
    assert(bytesWritten < buffer.count || count == 0)
    (buffer.baseAddress.unsafelyUnwrapped + bytesWritten).initialize(repeating: byte, count: count)
    bytesWritten += count
  }
  private mutating func writeBytes<T>(_ bytes: T) where T: Collection, T.Element == UInt8 {
    assert(bytesWritten < buffer.count || bytes.isEmpty)
    let count = UnsafeMutableBufferPointer(rebasing: buffer.suffix(from: bytesWritten)).initialize(from: bytes).1
    bytesWritten += count
  }

  // URLWriter.

  mutating func writeFlags(schemeKind: WebURL.SchemeKind, cannotBeABaseURL: Bool) {
  }

  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8 {
    writeBytes(schemeBytes)
    writeByte(ASCII.colon.codePoint)
  }

  mutating func writeAuthoritySigil() {
    writeByte(ASCII.forwardSlash.codePoint, count: 2)
  }

  mutating func writePathSigil() {
    writeByte(ASCII.forwardSlash.codePoint)
    writeByte(ASCII.period.codePoint)
  }

  mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8 {
    usernameWriter { piece in
      writeBytes(piece)
    }
  }

  mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    writeByte(ASCII.colon.codePoint)
    passwordWriter { piece in
      writeBytes(piece)
    }
  }

  mutating func writeCredentialsTerminator() {
    writeByte(ASCII.commercialAt.codePoint)
  }

  mutating func writeHostname<T>(_ hostnameWriter: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
    hostnameWriter { piece in
      writeBytes(piece)
    }
  }

  mutating func writePort(_ port: UInt16) {
    writeByte(ASCII.colon.codePoint)
    var portString = String(port)
    portString.withUTF8 {
      writeBytes($0)
    }
  }

  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  ) {
    writeBytes(authority)
  }

  mutating func writePath<T>(firstComponentLength: Int, _ writer: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    writer { piece in
      writeBytes(piece)
    }
  }

  mutating func writeUnsafePath(
    length: Int, firstComponentLength: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int
  ) {
    let space = UnsafeMutableBufferPointer(start: buffer.baseAddress.unsafelyUnwrapped + bytesWritten, count: length)
    let pathBytesWritten = writer(space)
    assert(pathBytesWritten == length)
    bytesWritten += pathBytesWritten
  }

  mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    writeByte(ASCII.questionMark.codePoint)
    queryWriter {
      writeBytes($0)
    }
  }

  mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    writeByte(ASCII.numberSign.codePoint)
    fragmentWriter {
      writeBytes($0)
    }
  }
}


// MARK: - HostnameWriter.


/// An interface through which `ParsedHost` writes its contents.
///
protocol HostnameWriter {

  /// Writes the bytes provided by `writerFunc`.
  /// The bytes will already be percent-encoded/IDNA-transformed and not include any separators.
  ///
  mutating func writeHostname<T>(_ writerFunc: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8
}

/// An adapter which allows any `URLWriter` to provide a limited-scope conformance to `HostnameWriter`.
///
struct URLHostnameWriterAdapter<Base: URLWriter>: HostnameWriter {
  fileprivate var base: UnsafeMutablePointer<Base>

  mutating func writeHostname<T>(_ writerFunc: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
    base.pointee.writeHostname(writerFunc)
  }
}

extension URLWriter {

  /// Provides a `HostnameWriter` instance with a limited lifetime, which may be used to write the URL's hostname.
  /// If called, this must always have been preceded by a call to `writeAuthoritySigil`.
  ///
  mutating func withHostnameWriter(_ hostnameWriter: (inout URLHostnameWriterAdapter<Self>) -> Void) {
    withUnsafeMutablePointer(to: &self) { ptr in
      var adapter = URLHostnameWriterAdapter(base: ptr)
      hostnameWriter(&adapter)
    }
  }
}

struct HostnameLengthCounter: HostnameWriter {
  var length: Int = 0
  mutating func writeHostname<T>(_ writerFunc: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
    writerFunc { piece in
      length += piece.count
    }
  }
}

struct UnsafeBufferHostnameWriter: HostnameWriter {
  var buffer: UnsafeMutableBufferPointer<UInt8>
  mutating func writeHostname<T>(_ writerFunc: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
    writerFunc { piece in
      let n = buffer.initialize(from: piece).1
      buffer = UnsafeMutableBufferPointer(rebasing: buffer.suffix(from: n))
    }
  }
}
