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
  mutating func writeFlags(schemeKind: WebURL.Scheme, cannotBeABaseURL: Bool)

  /// A function which appends the given bytes to storage.
  ///
  /// Functions using this pattern typically look like the following:
  /// ```swift
  /// func writeUsername<T>(_ usernameWriter: (WriterFunc<T>)->Void)
  /// ```
  ///
  /// Callers typically use this as shown:
  /// ```swift
  /// writeUsername { writePiece in
  ///   PercentEncoding.encodeIteratively(..., handlePiece: { writePiece($0) })
  /// }
  /// ```
  /// in this example, `writePiece` is a `WriterFunc`, and its type is inferred by the call to `PercentEncoding.encodeIteratively(...)`.
  ///
  typealias WriterFunc<T> = (T) -> Void

  /// Appends the given bytes to storage, followed by the scheme separator character (`:`).
  /// This is always the first call to the writer after `writeFlags`.
  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8

  /// Appends the authority header (`//`) to storage.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  mutating func writeAuthorityHeader()

  /// Appends the bytes provided by `usernameWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeAuthorityHeader`.
  mutating func writeUsernameContents<T>(_ usernameWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends the password separator character (`:`), followed by the bytes provided by `passwordWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeUsernameContents`.
  mutating func writePasswordContents<T>(_ passwordWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends the credential terminator byte (`@`).
  /// If called, this must always be the immediate successor to either `writeUsernameContents` or `writePasswordContents`.
  mutating func writeCredentialsTerminator()

  /// Appends the bytes given by `hostnameWriter`.
  /// The content must already be percent-encoded/IDNA-transformed and not include any separators.
  /// If called, this must always have been preceded by a call to `writeAuthorityHeader`.
  mutating func writeHostname<T>(_ hostnameWriter: (WriterFunc<T>) -> Void) where T: Collection, T.Element == UInt8

  /// Appends the port separator character (`:`), followed by the textual representation of the given port number to storage.
  /// If called, this must always be the immediate successor to `writeHostname`.
  mutating func writePort(_ port: UInt16)

  /// Appends an entire authority string (username + password + hostname + port) to storage.
  /// The content must already be percent-encoded/IDNA-transformed.
  /// If called, this must always be the immediate successor to `writeAuthorityHeader`.
  /// - important: `passwordLength` and `portLength` include their required leading separators (so a port component of `:8080` has a length of 5).
  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  )

  /// Appends the bytes given by `pathWriter`.
  /// The content must already be percent-encoded. No separators are added before or after the content.
  mutating func writePathSimple<T>(_ pathWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends an uninitialized space of size `length` and calls the given closure to allow for the path content to be written out of order.
  /// The `writer` closure must return the number of bytes written (`bytesWritten`), and all bytes from `0..<bytesWritten` must be initialized.
  /// Content written in to the buffer must already be percent-encoded. No separators are added before or after the content.
  mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int)

  /// Appends the query separator character (`?`), followed by the bytes provided by `queryWriter`.
  /// The content must already be percent-encoded.
  mutating func writeQueryContents<T>(_ queryWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends the fragment separator character (`#`), followed by the bytes provided by `fragmentWriter`
  /// The content must already be percent-encoded.
  mutating func writeFragmentContents<T>(_ fragmentWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  mutating func writeHint(_ component: ComponentsToCopy, needsEscaping: Bool)
  mutating func writePathMetricsHint(_ pathMetrics: PathMetricsCollector)
}

extension URLWriter {
  mutating func writeHint(_ component: ComponentsToCopy, needsEscaping: Bool) {
    // Not required.
  }
  mutating func writePathMetricsHint(_ pathMetrics: PathMetricsCollector) {
    // Not required.
  }
}

// MARK: - Metrics collector.

/// A `URLWriter` which collects various metrics so that storage can be optimally allocated and written.
///
/// Currently, it collects the total required capacity of the string (post any percent-encoding) and the length of the path component.
/// It may collect other data in the future. In particular, it might be interesting to know if we can skip percent-encoding any components, or how many path
/// components are in the final string (perhaps we'll have a URL storage type with random access to path components).
///
struct URLMetricsCollector: URLWriter {
  var requiredCapacity: Int = 0
  var pathMetrics: PathMetricsCollector? = nil
  private var componentsWhichMaySkipEscaping: ComponentsToCopy = []

  init() {
  }

  func componentMaySkipEscaping(_ component: ComponentsToCopy) -> Bool {
    return componentsWhichMaySkipEscaping.contains(component)
  }

  mutating func writeHint(_ component: ComponentsToCopy, needsEscaping: Bool) {
    if needsEscaping == false {
      componentsWhichMaySkipEscaping.insert(component)
    }
  }
  mutating func writePathMetricsHint(_ pathMetrics: PathMetricsCollector) {
    self.pathMetrics = pathMetrics
  }

  mutating func writeFlags(schemeKind: WebURL.Scheme, cannotBeABaseURL: Bool) {
    // Nothing to do.
  }

  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8 {
    requiredCapacity = schemeBytes.count + 1
  }

  mutating func writeAuthorityHeader() {
    requiredCapacity += 2
  }

  mutating func writeUsernameContents<T>(_ usernameWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    usernameWriter {
      requiredCapacity += $0.count
    }
  }

  mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    requiredCapacity += 1
    passwordWriter {
      requiredCapacity += $0.count
    }
  }

  mutating func writeCredentialsTerminator() {
    requiredCapacity += 1
  }

  mutating func writeHostname<T>(_ hostnameWriter: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
    hostnameWriter {
      requiredCapacity += $0.count
    }
  }

  mutating func writePort(_ port: UInt16) {
    requiredCapacity += 1
    requiredCapacity += String(port).utf8.count
  }

  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  ) {
    requiredCapacity += authority.count
  }

  mutating func writePathSimple<T>(_ pathWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    pathWriter {
      requiredCapacity += $0.count
    }
  }

  mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int) {
    self.requiredCapacity += length
  }

  mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    requiredCapacity += 1
    queryWriter {
      requiredCapacity += $0.count
    }
  }

  mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void)
  where T: Collection, T.Element == UInt8 {
    requiredCapacity += 1
    fragmentWriter {
      requiredCapacity += $0.count
    }
  }
}
