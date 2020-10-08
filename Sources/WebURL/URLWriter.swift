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
  ///
  mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8

  /// Appends the authority header (`//`) to storage.
  /// If called, this must always be the immediate successor to `writeSchemeContents`.
  ///
  mutating func writeAuthorityHeader()

  /// Appends the bytes provided by `usernameWriter`.
  /// The content must already be percent-encoded and not include any separators.
  /// If called, this must always be the immediate successor to `writeAuthorityHeader`.
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
  /// If called, this must always have been preceded by a call to `writeAuthorityHeader`.
  ///
  mutating func writeHostname<T>(_ hostnameWriter: (WriterFunc<T>) -> Void) where T: Collection, T.Element == UInt8

  /// Appends the port separator character (`:`), followed by the textual representation of the given port number to storage.
  /// If called, this must always be the immediate successor to `writeHostname`.
  ///
  mutating func writePort(_ port: UInt16)

  /// Appends an entire authority string (username + password + hostname + port) to storage.
  /// The content must already be percent-encoded/IDNA-transformed.
  /// If called, this must always be the immediate successor to `writeAuthorityHeader`.
  ///
  /// - important: `passwordLength` and `portLength` include their required leading separators (so a port component of `:8080` has a length of 5).
  ///
  mutating func writeKnownAuthorityString(
    _ authority: UnsafeBufferPointer<UInt8>,
    usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
  )

  /// Appends the bytes given by `pathWriter`.
  /// The content must already be percent-encoded. No separators are added before or after the content.
  ///
  mutating func writePathSimple<T>(_ pathWriter: (WriterFunc<T>) -> Void)
  where T: Collection, T.Element == UInt8

  /// Appends an uninitialized space of size `length` and calls the given closure to allow for the path content to be written out of order.
  /// The `writer` closure must return the number of bytes written (`bytesWritten`), and all bytes from `0..<bytesWritten` must be initialized.
  /// Content written in to the buffer must already be percent-encoded. No separators are added before or after the content.
  ///
  mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int)

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
  
  /// Optional function which takes note of the metrics collected while writing the URL's path component.
  /// Conformers may wish to note this information, in case they wish to write the same contents using another `URLWriter`.
  /// The default implementation does nothing.
  ///
  mutating func writePathMetricsHint(_ pathMetrics: PathMetricsCollector)
}

extension URLWriter {
  
  mutating func writeHint(_ component: WebURL.Component, needsEscaping: Bool) {
    // Not required.
  }
  mutating func writePathMetricsHint(_ pathMetrics: PathMetricsCollector) {
    // Not required.
  }
}

// MARK: - Metrics.

/// Information which is used to determine how a URL should be stored or written.
///
struct URLMetrics {
  
  /// The capacity required to store the URL's code-units. Must always be present and correct.
  var requiredCapacity: Int
  
  /// If set, contains information about the number of code-units in the path, number of path components, etc.
  /// If not set, users may make no assumptions about the path.
  var pathMetrics: PathMetricsCollector? = nil
  
  /// Components which are known to not require percent-encoding.
  /// If a component is not in this set, users must assume that it requires percent-encoding.
  var componentsWhichMaySkipEscaping: WebURL.ComponentSet = []
}

extension URLMetrics {
  
  static func collect(_ body: (inout Collector) -> Void) -> URLMetrics {
    var collector = Collector()
    body(&collector)
    precondition(collector.metrics.requiredCapacity >= 0)
    return collector.metrics
  }

  struct Collector: URLWriter {
    // TODO: Prohibit users reading this until they finish writing.
    fileprivate var metrics = URLMetrics(requiredCapacity: 0)

    fileprivate init() {
    }

    func componentMaySkipEscaping(_ component: WebURL.Component) -> Bool {
      return metrics.componentsWhichMaySkipEscaping.contains(component)
    }

    mutating func writeFlags(schemeKind: WebURL.Scheme, cannotBeABaseURL: Bool) {
      // Nothing to do.
    }

    mutating func writeSchemeContents<T>(_ schemeBytes: T) where T: Collection, T.Element == UInt8 {
      metrics.requiredCapacity = schemeBytes.count + 1
    }

    mutating func writeAuthorityHeader() {
      metrics.requiredCapacity += 2
    }

    mutating func writeUsernameContents<T>(_ usernameWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      usernameWriter {
        metrics.requiredCapacity += $0.count
      }
    }

    mutating func writePasswordContents<T>(_ passwordWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      metrics.requiredCapacity += 1
      passwordWriter {
        metrics.requiredCapacity += $0.count
      }
    }

    mutating func writeCredentialsTerminator() {
      metrics.requiredCapacity += 1
    }

    mutating func writeHostname<T>(_ hostnameWriter: ((T) -> Void) -> Void) where T: Collection, T.Element == UInt8 {
      hostnameWriter {
        metrics.requiredCapacity += $0.count
      }
    }

    mutating func writePort(_ port: UInt16) {
      metrics.requiredCapacity += 1
      metrics.requiredCapacity += String(port).utf8.count
    }

    mutating func writeKnownAuthorityString(
      _ authority: UnsafeBufferPointer<UInt8>,
      usernameLength: Int, passwordLength: Int, hostnameLength: Int, portLength: Int
    ) {
      metrics.requiredCapacity += authority.count
    }

    mutating func writePathSimple<T>(_ pathWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      pathWriter {
        metrics.requiredCapacity += $0.count
      }
    }

    mutating func writeUnsafePathInPreallocatedBuffer(length: Int, writer: (UnsafeMutableBufferPointer<UInt8>) -> Int) {
      metrics.requiredCapacity += length
    }

    mutating func writeQueryContents<T>(_ queryWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      metrics.requiredCapacity += 1
      queryWriter {
        metrics.requiredCapacity += $0.count
      }
    }

    mutating func writeFragmentContents<T>(_ fragmentWriter: ((T) -> Void) -> Void)
    where T: Collection, T.Element == UInt8 {
      metrics.requiredCapacity += 1
      fragmentWriter {
        metrics.requiredCapacity += $0.count
      }
    }
    
    mutating func writeHint(_ component: WebURL.Component, needsEscaping: Bool) {
      if needsEscaping == false {
        metrics.componentsWhichMaySkipEscaping.insert(component)
      }
    }
    
    mutating func writePathMetricsHint(_ pathMetrics: PathMetricsCollector) {
      metrics.pathMetrics = pathMetrics
    }
  }
}
