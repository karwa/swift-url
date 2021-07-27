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

/// A description of a file path's structure.
///
public struct FilePathFormat: Equatable, Hashable, CustomStringConvertible {

  @usableFromInline
  internal enum _Format {
    case posix
    case windows
  }

  @usableFromInline
  internal var _fmt: _Format

  @inlinable
  internal init(_ _fmt: _Format) {
    self._fmt = _fmt
  }

  /// A path which is compatible with the POSIX standard.
  ///
  @inlinable
  public static var posix: FilePathFormat {
    FilePathFormat(.posix)
  }

  /// A path which is compatible with those used by Microsoft Windows.
  ///
  @inlinable
  public static var windows: FilePathFormat {
    FilePathFormat(.windows)
  }

  /// The native path style used by the current operating system.
  ///
  @inlinable
  public static var native: FilePathFormat {
    #if os(Windows)
      return .windows
    #else
      return .posix
    #endif
  }

  public var description: String {
    switch _fmt {
    case .posix: return "posix"
    case .windows: return "windows"
    }
  }
}


// --------------------------------------------
// MARK: - File path to URL
// --------------------------------------------


extension WebURL {

  /// Creates a `file:` URL representing the given file path, and from which the file path may be reconstructed.
  ///
  /// This is a low-level function, which accepts a file path as a `Collection` of 8-bit code-units. Correct usage requires detailed knowledge
  /// of character sets and text encodings, and how various operating systems and file systems actually handle file paths internally.
  /// Most users should prefer higher-level APIs, providing a file path as a `String` or `FilePath`, as many of these details will be
  /// handled for you.
  ///
  /// ## Supported paths
  ///
  /// This function only supports non-relative paths (i.e. absolute POSIX paths, fully-qualified Windows paths), which do not contain any `..` components
  /// or ASCII `NULL` bytes. Null-terminated strings also fall in to this category, so callers must first measure such strings using `strlen` and provide the
  /// path as a slice which does not include the null terminator. Attempting to create a URL from an unsupported path throws a `FilePathToURLError`.
  ///
  /// These restrictions are considered a feature. URLs have no way of expressing relative paths, so such paths would first have to be resolved against
  /// a base path or working directory, which can lead to unexpected results. Likewise, `..` components and unexpected NULL bytes
  /// are a common source of [security vulnerabilities][OWASP-PathTraversal]. Rather than risk drastically altering the file you intended to point to,
  /// within an opaque (and already rather complex) path-to-URL conversion, it is considered better practice to just not support those paths.
  ///
  /// If you don't expect those kinds of paths to show up, you get the most direct, most secure behaviour by default; and if you do expect and wish to support them,
  /// you can use specialized path APIs (provided by the platform or a library such as `swift-system`) to resolve them and validate that they don't
  /// point to somewhere unexpected, as is appropriate for your application. The point is that path resolution really should be an explicit, separate step, and
  /// each application should decide the extent to which it wants to support relative paths/upwards traversal.
  ///
  /// Additionally, paths to Win32 file namespaces are not supported (paths which begin with `\\?\`). These paths are intended not to be normalized
  /// or canonicalized (for example, they do not interpret `/` as a path separator, and allow referring to files and folders named `.` or `..`).
  /// They are intended for direct consumption by the Windows API (and even then, not all APIs support them), and the files and folders created with them
  /// may not be accessible to Windows shell applications. Unfortunately, it is not currently possible to represent these paths using URLs.
  /// It may not even be wise to try - URL paths have their own semantics, and these kinds of paths explicitly opt-out of many behaviours you might expect.
  ///
  /// ## Encodings
  ///
  /// While we may usually think of file and directory names strings of text, many operating systems do not treat them that way.
  /// In fact, many operating systems treat these names as opaque, numeric code-units, where the size of those code-units can differ between systems.
  /// This means we need to be careful to ensure that the original sequence of code-units used for file and directory names can be precisely reconstructed
  /// from the file URL we create.
  ///
  /// In order to process paths in a portable way, we need to at least be able to understand their structure. This is the same basic level of understanding
  /// that every file/operating-system needs - and so, while file and directory names may be opaque code-units, it turns out that the code-units of the
  /// _path_ itself are never entirely opaque. The system reserves some values for use as path separators, string terminators, and other
  /// special path components (such as `..`). There are a couple of things to pay attention to here:
  ///
  ///  - Reserved code-units are numeric values, not textual code-points or characters.
  ///
  ///    Consider the case of SHIFT-JIS - a pre-Unicode encoding popular in Japan which replaced the ASCII backslash, `0x5C`, with the ¥ symbol.
  ///    On Windows, the kernel would still interpret the code-unit with numeric value `0x5C` to be a path separator, but fonts rendered it as the ¥ symbol,
  ///    meaning that file names could not contain the ¥ symbol and their paths would display as `C:¥Windows¥`.
  ///    For decades, Japanese users became accustomed to delimiting paths using Yen symbols (and some Japanese fonts still do present them that way,
  ///    even though Unicode means they no longer have to occupy the code-unit value, just because of how familiar it became).
  ///
  ///    So was the Windows path separator `\`, `¥`, or both? The lesson of the story is that it was neither - it was the code-unit with numeric value `0x5C`.
  ///    We tend to write reserved code-units as ASCII characters (e.g. `/`, `..`), but what is meant are the numeric values (e.g. `0x2F`, `[0x2E, 0x2E]`) -
  ///    regardless of how the file/directory names are encoded, `0x2F` will be a path separator on a POSIX platform, as `0x5C` is on Windows.
  ///
  /// - 16-bit code-units may be assumed to be Unicode code-points, encoded as UTF-16.
  ///
  ///    Most [major file systems][Wiki-FileSystems] use 8-bit code-units. However, file systems as NTFS, HFS+, and exFAT, natively store
  ///    file and directory names using 16-bit code-units, and on Windows, the `-W` family of APIs allows developers to work with paths as strings of
  ///    16-bit `wchar_t`s. All of these systems define those code-units to represent Unicode code-points encoded using UTF-16.
  ///
  ///    This has the benefit that the 16-bit code-unit with value `0x005C` is unambiguously mapped to the Unicode code-point U+005C REVERSE SOLIDUS.
  ///    More importantly, it means these paths can be transcoded to UTF-8, with the exact same numeric values for reserved code-units, and transcoded
  ///    back to the same sequence of UTF-16 code-units. Unfortunately, not all systems validate the well-formedness of Unicode text used in paths,
  ///    so this transcoding will fail for some rare filenames, but it will reliably fail rather than producing a corrupted/misinterpreted file path.
  ///
  /// This function accepts a file path as a `Collection` of 8-bit code-units. This is the natural format for a file path within a URL, as percent-encoding is only
  /// able to escape 8-bit elements. The set of reserved code-unit values depend on the conventions established by the given `FilePathFormat`
  /// (e.g. `0x5C` is considered a path separator for the `.windows` format, but not the `.posix` format). Non-reserved code-unit values are,
  /// for the most part, considered opaque, and may be percent-encoded to preserve their values. An important exception is that for UNC paths
  /// in the `.windows` format, the code-units of the server name portion _must_ be valid UTF-8. This is because they are domains, and hence may
  /// be subject to IDNA normalization.
  ///
  /// Paths represented using 16-bit code-units must be transcoded to a filesystem-safe 8-bit encoding for the given `FilePathFormat`
  /// (i.e. an encoding which will not remove/insert any additional reserved code-units). Since these paths may be assumed to represent Unicode code-points,
  /// transcoding to UTF-8 is highly recommended. This is especially true if the file path will be reconstructed from the URL by an application not under your control
  /// (e.g. a web browser).
  ///
  /// ## Normalization
  ///
  /// Some basic lexical normalization is applied to the path, according to its format.
  ///
  /// For example, both POSIX- and Windows-style paths define that certain sequences of repeat path separators can be collapsed to a single separator
  /// (e.g. `/usr///bin/swift` is the same as `/usr/bin/swift`), but there are also other kinds of normalization which are specific to Windows paths.
  ///
  /// [OWASP-PathTraversal]: https://owasp.org/www-community/attacks/Path_Traversal
  /// [Wiki-FileSystems]: https://en.wikipedia.org/wiki/Comparison_of_file_systems#Limits
  ///
  /// - parameters:
  ///   - path:   The file path, as a `Collection` of 8-bit code-units.
  ///   - format: The way in which `path` should be interpreted; either `.posix`, `.windows`, or `.native`.
  ///
  /// - returns: A URL with the `file` scheme which can be used to reconstruct the given path.
  /// - throws: `FilePathToURLError`
  ///
  @inlinable
  public static func fromFilePathBytes<Bytes>(
    _ path: Bytes, format: FilePathFormat = .native
  ) throws -> WebURL where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {
    switch format._fmt {
    case .posix: return try _filePathToURL_posix(path).get()
    case .windows: return try _filePathToURL_windows(path).get()
    }
  }
}

/// The reason why a file URL could not be created from a given file path.
///
public struct FilePathToURLError: Error, Equatable, Hashable, CustomStringConvertible {

  @usableFromInline
  internal enum _Err {
    case emptyInput
    case nullBytes
    case relativePath
    case upwardsTraversal
    case unsupportedHostname
    case transcodingFailure
  }

  @usableFromInline
  internal var _err: _Err

  @inlinable init(_ _err: _Err) {
    self._err = _err
  }

  /// The given path is empty.
  ///
  @inlinable
  public static var emptyInput: FilePathToURLError {
    FilePathToURLError(.emptyInput)
  }

  /// The given path contains ASCII `NULL` bytes.
  ///
  /// `NULL` bytes are forbidden, to protect against injected truncation.
  ///
  @inlinable
  public static var nullBytes: FilePathToURLError {
    FilePathToURLError(.nullBytes)
  }

  /// The given path is not absolute/fully-qualified.
  ///
  /// Each path style has different kinds of relative paths. Use APIs provided by the platform, or the `swift-system` library, to resolve the input
  /// as an absolute path. Be advised that some kinds of relative path resolution may not be thread-safe; consult your chosen resolution API for details.
  ///
  @inlinable
  public static var relativePath: FilePathToURLError {
    FilePathToURLError(.relativePath)
  }

  /// The given path contains one or more `..` components.
  ///
  /// These components are forbidden, to protect against directory traversal attacks. Use APIs provided by the platform, or the `swift-system` library,
  /// to resolve the path. Users are advised to check that the path has not escaped the expected area of the filesystem after it has been resolved.
  ///
  @inlinable
  public static var upwardsTraversal: FilePathToURLError {
    FilePathToURLError(.upwardsTraversal)
  }

  /// The given path is a Windows UNC path, but the hostname was not valid or cannot be supported by the URL Standard.
  ///
  /// Note that currently, only ASCII domains, IPv4, and IPv6 addresses are supported. Domains may not include [forbidden host code-points][URL-FHCP].
  /// Additionally, Win32 file namespace paths (UNC paths whose hostname is `?`) are not supported.
  ///
  /// [URL-FHCP]: https://url.spec.whatwg.org/#forbidden-host-code-point
  ///
  @inlinable
  public static var unsupportedHostname: FilePathToURLError {
    FilePathToURLError(.unsupportedHostname)
  }

  // '.transcodingFailure' is thrown by higher-level functions (e.g. System.FilePath -> URL),
  // but defined as part of FilePathToURLError.

  /// Transcoding the given path for inclusion in a URL failed.
  ///
  /// File URLs can preserve the precise bytes of their path components by means of percent-encoding.
  /// However, when the platform's native path representation uses non-8-bit code-units, those elements must be transcoded
  /// to an 8-bit encoding suitable for percent-encoding.
  ///
  @inlinable
  public static var transcodingFailure: FilePathToURLError {
    FilePathToURLError(.transcodingFailure)
  }

  public var description: String {
    switch _err {
    case .emptyInput: return "Path is empty"
    case .nullBytes: return "Path contains NULL bytes"
    case .relativePath: return "Path is relative"
    case .upwardsTraversal: return "Path contains upwards traversal"
    case .unsupportedHostname: return "UNC path contains an unsupported hostname"
    case .transcodingFailure: return "Transcoding failure"
    }
  }
}

/// Creates a `file:` URL from a POSIX-style path.
///
/// The bytes must be in a 'filesystem-safe' encoding, but are otherwise just opaque bytes.
///
@inlinable @inline(never)
internal func _filePathToURL_posix<Bytes>(
  _ path: Bytes
) -> Result<WebURL, FilePathToURLError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  guard !path.isEmpty else {
    return .failure(.emptyInput)
  }
  guard !path.contains(ASCII.null.codePoint) else {
    return .failure(.nullBytes)
  }
  guard !path.containsLiteralDotDotComponent(isSeparator: { $0 == ASCII.forwardSlash.codePoint }) else {
    return .failure(.upwardsTraversal)
  }
  guard path.first == ASCII.forwardSlash.codePoint else {
    return .failure(.relativePath)
  }

  var escapedPath = ContiguousArray(path.lazy.percentEncoded(as: \.posixPath))

  // Collapse multiple path slashes into a single slash, except if a leading double slash ("//usr/bin").
  // POSIX says that leading double slashes are implementation-defined.
  // https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_13

  precondition(escapedPath[0] == ASCII.forwardSlash.codePoint)

  if escapedPath.count > 2 {
    if escapedPath[1] == ASCII.forwardSlash.codePoint, escapedPath[2] != ASCII.forwardSlash.codePoint {
      escapedPath.collapseForwardSlashes(from: 2)
    } else {
      escapedPath.collapseForwardSlashes(from: 0)
    }
  }

  // We've already encoded or rejected most things the URL path parser will interpret
  // (backslashes, Windows drive delimiters, etc), with the notable exception of single-dot components.
  // The path setter will additionally encode whitespace, control chars, '#', '?', and anything else that
  // URL semantics would interpret.

  var fileURL = _emptyFileURL
  try! fileURL.utf8.setPath(escapedPath)
  return .success(fileURL)
}

/// Creates a `file:` URL from a Windows-style path.
///
/// The bytes must be in a 'filesystem-safe' encoding for Windows. If a UNC server name is included, it must be UTF-8.
///
@inlinable @inline(never)
internal func _filePathToURL_windows<Bytes>(
  _ path: Bytes
) -> Result<WebURL, FilePathToURLError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  guard !path.isEmpty else {
    return .failure(.emptyInput)
  }
  guard !path.contains(ASCII.null.codePoint) else {
    return .failure(.nullBytes)
  }

  if !isWindowsFilePathSeparator(path.first!) {

    // DOS path.
    // Must have the form: <alpha><colon><separator><...>, e.g. "C:\Windows\", "D:/foo".

    guard !path.containsLiteralDotDotComponent(isSeparator: isWindowsFilePathSeparator) else {
      return .failure(.upwardsTraversal)
    }
    let driveLetter = path.prefix(2)
    guard PathComponentParser.isNormalizedWindowsDriveLetter(driveLetter) else {
      return .failure(.relativePath)
    }
    guard driveLetter.endIndex < path.endIndex, isWindowsFilePathSeparator(path[driveLetter.endIndex]) else {
      return .failure(.relativePath)
    }

    var escapedPath = ContiguousArray(driveLetter)
    escapedPath.append(contentsOf: path[driveLetter.endIndex...].lazy.percentEncoded(as: \.windowsPath))

    escapedPath.collapseWindowsPathSeparators(from: 2)
    escapedPath.trimPathSegmentsForWindows(from: 2, isUNC: false)

    var fileURL = _emptyFileURL
    try! fileURL.utf8.setPath(escapedPath)
    return .success(fileURL)

  } else {

    // UNC.
    // Must have the form: <2+ separators><hostname><separator?>.
    // Content after the hostname's separator is parsed as: <share><separator><path>.

    var numberOfLeadingSlashes = -1
    let pathWithoutLeadingSlashes = path.drop { byte in
      numberOfLeadingSlashes += 1
      return isWindowsFilePathSeparator(byte)
    }
    guard numberOfLeadingSlashes > 1 else {
      return .failure(.relativePath)
    }

    var fileURL = _emptyFileURL

    // UNC hostname.
    // This part must be valid UTF-8. For now, since we don't support unicode domains (due to IDNA),
    // check that the hostname is ASCII and doesn't include percent-encoding.

    let rawHost = pathWithoutLeadingSlashes.prefix { !isWindowsFilePathSeparator($0) }
    guard rawHost.allSatisfy({ ASCII($0) != nil }), !rawHost.contains(ASCII.percentSign.codePoint) else {
      return .failure(.unsupportedHostname)
    }
    guard !rawHost.elementsEqual(CollectionOfOne(ASCII.questionMark.codePoint)) else {
      // Explicitly reject Win32 file namespace paths. Not only can we not support this hostname, but the entire
      // semantics of these paths are different and impossible to capture in a file URL.
      return .failure(.unsupportedHostname)
    }

    // The URL standard does not preserve "localhost" as a hostname in file URLs, but removing it would turn a UNC path
    // in to a local path. As a workaround, replace it with "127.0.0.1". https://github.com/whatwg/url/issues/618

    if ASCII.Lowercased(rawHost).elementsEqual("localhost".utf8) {
      // FIXME: Add an API to set the hostname to an IP-address object, to avoid host-parsing.
      var ipv4String = IPv4Address(octets: (127, 0, 0, 1)).serializedDirect
      withUnsafeBytes(of: &ipv4String.buffer) { try! fileURL.utf8.setHostname($0.prefix(Int(ipv4String.count))) }
    } else {
      guard let _ = try? fileURL.utf8.setHostname(rawHost) else {
        return .failure(.unsupportedHostname)
      }
    }

    // UNC share & path.

    let rawShareAndPath = path.suffix(from: rawHost.endIndex)
    guard !rawShareAndPath.containsLiteralDotDotComponent(isSeparator: isWindowsFilePathSeparator) else {
      return .failure(.upwardsTraversal)
    }

    var escapedShareAndPath = ContiguousArray(rawShareAndPath.lazy.percentEncoded(as: \.windowsPath))
    escapedShareAndPath.collapseWindowsPathSeparators(from: escapedShareAndPath.startIndex)
    escapedShareAndPath.trimPathSegmentsForWindows(from: escapedShareAndPath.startIndex, isUNC: true)

    try! fileURL.utf8.setPath(escapedShareAndPath)
    return .success(fileURL)
  }
}


// --------------------------------------------
// MARK: - File URL to path
// --------------------------------------------


extension WebURL {

  /// Reconstructs a file path from a `file:` URL.
  ///
  /// This is a low-level function, which returns a file path as a `Collection` of 8-bit code-units. Correct usage requires detailed knowledge
  /// of character sets and text encodings, and how various operating systems and file systems actually handle file paths internally.
  /// Most users should prefer higher-level APIs, which return a file path as a `String` or `FilePath`, as many of these details will be
  /// handled for you.
  ///
  /// ## Accepted URLs
  ///
  /// This function only accepts URLs with a `file` scheme, whose paths do not contain percent-encoded path separators or `NULL` bytes.
  /// Additionally, as there is no obvious interpretation of a POSIX path to a remote host, POSIX paths may only be constructed from URLs with empty hostnames.
  /// Windows paths must be fully-qualified: either they have a hostname and are UNC paths, or they have an empty hostname and begin with a drive letter
  /// component.
  ///
  /// Attempting to create a file path from an unsupported URL will throw a `URLToFilePathError`.
  ///
  /// ## Encoding
  ///
  /// This function returns an array of 8-bit code-units, formed by percent-decoding the URL's contents and applying format-specific path normalization.
  /// Note that the encoding of these code-units is, in general, not known.
  ///
  /// - To use the returned path on a POSIX system, request a null-terminated file path, and map/reinterpret the array's contents as the platform's `CChar` type.
  ///   POSIX requires that the C `char` type be 8 bits, so this is always safe. As POSIX systems generally do not assume any particular encoding for
  ///   file or directory names, it is reasonable to use the path as-is.
  ///
  /// - To use the returned path on a Windows system, some transcoding may be necessary as the system natively uses 16-bit code-units.
  ///   It is generally a good idea to assume that the path decoded from the URL is UTF-8, transcode it to UTF-16, add a null-terminator, and use it
  ///   with the `-W` family of APIs. The exception is when you happen to know that the 8-bit code-units used to create the URL were not UTF-8.
  ///
  /// ## Normalization
  ///
  /// Some basic normalization is applied to the path, according to the specific rules which govern how each path style is interpreted.
  ///
  /// For example, both POSIX- and Windows-style paths define that certain sequences of repeat path separators can be collapsed to a single separator
  /// (e.g. `/usr//bin/swift` is the same as `/usr/bin/swift`), but there are also other kinds of normalization which are specific to Windows paths.
  ///
  /// - parameters:
  ///   - url:    The file URL.
  ///   - format: The path format which should be constructed; either `.posix`, `.windows`, or `.native`.
  ///   - nullTerminated: Whether the returned file path should include a null-terminator. The default is `false`.
  ///
  /// - returns: A reconstruction of the file path encoded in the given URL, as an array of bytes.
  /// - throws: `URLToFilePathError`
  ///
  @inlinable
  public static func filePathBytes(
    from url: WebURL, format: FilePathFormat = .native, nullTerminated: Bool = false
  ) throws -> ContiguousArray<UInt8> {
    switch format._fmt {
    case .posix: return try _urlToFilePath_posix(url, nullTerminated: nullTerminated).get()
    case .windows: return try _urlToFilePath_windows(url, nullTerminated: nullTerminated).get()
    }
  }
}

/// The reason why a file path could not be created from a given URL.
///
public struct URLToFilePathError: Error, Equatable, Hashable, CustomStringConvertible {

  @usableFromInline
  internal enum _Err {
    case notAFileURL
    case encodedPathSeparator
    case encodedNullBytes
    case posixPathsCannotContainHosts
    case windowsPathIsNotFullyQualified
    case transcodingFailure
  }

  @usableFromInline
  internal var _err: _Err

  @inlinable
  internal init(_ _err: _Err) {
    self._err = _err
  }

  /// The given URL is not a `file:` URL.
  ///
  @inlinable
  public static var notAFileURL: URLToFilePathError {
    URLToFilePathError(.notAFileURL)
  }

  /// The given URL contains a percent-encoded path separator.
  ///
  /// Typically, percent-encoded bytes in a URL are decoded when generating a file path, as percent-encoding is a URL feature that has no meaning to
  /// a filesystem. However, if the decoded byte would be interpreted by the system as a path separator, decoding it would pose a security risk as it could
  /// be used by an attacker to smuggle extra path components, including ".." components.
  ///
  @inlinable
  public static var encodedPathSeparator: URLToFilePathError {
    URLToFilePathError(.encodedPathSeparator)
  }

  /// The given URL contains a percent-encoded `NULL` byte.
  ///
  /// Typically, percent-encoded bytes in a URL are decoded when generating a file path, as percent-encoding is a URL feature that has no meaning to
  /// a filesystem. However, if the decoded byte is a `NULL` byte, many systems would interpret that as the end of the path, which poses a security risk
  /// as an attacker could unexpectedly discard parts of the path.
  ///
  @inlinable
  public static var encodedNullBytes: URLToFilePathError {
    URLToFilePathError(.encodedNullBytes)
  }

  /// The given URL refers to a file on a remote host, which cannot be represented by a POSIX path.
  ///
  /// On POSIX systems, remote filesystems tend to be mounted at locations in the local filesystem.
  /// There is no obvious interpretation of a URL with a remote host on a POSIX system.
  ///
  @inlinable
  public static var posixPathsCannotContainHosts: URLToFilePathError {
    URLToFilePathError(.posixPathsCannotContainHosts)
  }

  /// The given URL does not resolve to a fully-qualified Windows path.
  ///
  /// file URLs cannot contain relative paths; they always represent absolute locations on the filesystem.
  /// For Windows platforms, this means it would be incorrect for a file URL to result in anything other than a fully-qualified path.
  /// Windows paths are fully-qualified if they are UNC paths (i.e. have hostnames), or if their first component is a drive letter with a trailing separator.
  ///
  @inlinable
  public static var windowsPathIsNotFullyQualified: URLToFilePathError {
    URLToFilePathError(.windowsPathIsNotFullyQualified)
  }

  // '.transcodingFailure' is thrown by higher-level functions (e.g. URL -> System.FilePath),
  // but defined as part of URLToFilePathError.

  /// The path created from the URL could not be transcoded to the system's encoding.
  ///
  /// File URLs can preserve the precise bytes of their path components by means of percent-encoding.
  /// However, when the platform's native path representation uses non-8-bit code-units, those elements must be transcoded
  /// from the percent-encoded 8-bit values to the system's native encoding.
  ///
  @inlinable
  public static var transcodingFailure: URLToFilePathError {
    URLToFilePathError(.transcodingFailure)
  }

  public var description: String {
    switch _err {
    case .notAFileURL: return "Not a file URL"
    case .encodedPathSeparator: return "Percent-encoded path separator"
    case .encodedNullBytes: return "Percent-encoded NULL bytes"
    case .posixPathsCannotContainHosts: return "Hostnames are unsupported by POSIX paths"
    case .windowsPathIsNotFullyQualified: return "Not a fully-qualified Windows path"
    case .transcodingFailure: return "Transcoding failure"
    }
  }
}

/// Creates a POSIX path from a `file:` URL.
///
/// The result is a string of opaque bytes, reflecting the bytes encoded in the URL. The returned bytes are not null-terminated.
///
@usableFromInline
internal func _urlToFilePath_posix(
  _ url: WebURL, nullTerminated: Bool
) -> Result<ContiguousArray<UInt8>, URLToFilePathError> {

  guard case .file = url.schemeKind else {
    return .failure(.notAFileURL)
  }
  guard url.utf8.hostname!.isEmpty else {
    return .failure(.posixPathsCannotContainHosts)
  }

  var filePath = ContiguousArray<UInt8>()
  filePath.reserveCapacity(url.utf8.path.count)

  // Percent-decode the path, including control characters and invalid UTF-8 byte sequences.
  // Do not decode characters which are interpreted by the filesystem and would meaningfully alter the path.
  // For POSIX, that means 0x00 and 0x2F. Pct-encoded periods are already interpreted by the URL parser.

  for i in url.utf8.path.lazy.percentDecodedUTF8.indices {
    if i.isDecoded {
      if i.decodedValue == ASCII.null.codePoint {
        return .failure(.encodedNullBytes)
      }
      if i.decodedValue == ASCII.forwardSlash.codePoint {
        return .failure(.encodedPathSeparator)
      }
    } else {
      assert(i.decodedValue != ASCII.null.codePoint, "Non-percent-encoded NULL byte in URL path")
    }
    filePath.append(i.decodedValue)
  }

  // Normalization.
  // Collapse multiple path slashes into a single slash, except if a leading double slash ("//usr/bin").
  // POSIX says that leading double slashes are implementation-defined.

  precondition(filePath[0] == ASCII.forwardSlash.codePoint, "URL has invalid path")

  if filePath.count > 2 {
    if filePath[1] == ASCII.forwardSlash.codePoint, filePath[2] != ASCII.forwardSlash.codePoint {
      filePath.collapseForwardSlashes(from: 2)
    } else {
      filePath.collapseForwardSlashes(from: 0)
    }
  }

  // Null-termination (if requested).

  if nullTerminated {
    filePath.append(0)
  }

  assert(!filePath.isEmpty)
  return .success(filePath)
}

/// Creates a Windows path from a `file:` URL.
///
/// The result is a string of kind-of-opaque bytes, reflecting the bytes encoded in the URL.
/// It is more reasonable to assume that Windows paths will be UTF-8 encoded, although that may not always be the case.
/// The returned bytes are not null-terminated.
///
@usableFromInline
internal func _urlToFilePath_windows(
  _ url: WebURL, nullTerminated: Bool
) -> Result<ContiguousArray<UInt8>, URLToFilePathError> {

  guard case .file = url.schemeKind else {
    return .failure(.notAFileURL)
  }

  let isUNC = (url.utf8.hostname!.isEmpty == false)
  var urlPath = url.utf8.path
  precondition(urlPath.first == ASCII.forwardSlash.codePoint, "URL has invalid path")

  if !isUNC {
    // For DOS-style paths, the first component must be a drive letter and be followed by another component.
    // (e.g. "/C:/" is okay, "/C:" is not). Furthermore, we require the drive letter not be percent-encoded.

    // This may be too strict - people sometimes over-escape characters in URLs, and generally standards favour
    // treating percent-encoded characters as equivalent to their decoded versions.
    let drive = url.utf8.pathComponent(url.pathComponents.startIndex)
    guard PathComponentParser.isNormalizedWindowsDriveLetter(drive), drive.endIndex < urlPath.endIndex else {
      return .failure(.windowsPathIsNotFullyQualified)
    }
    // Drop the leading slash from the path.
    urlPath.removeFirst()
    assert(urlPath.startIndex == drive.startIndex)
  }

  // Percent-decode the path, including control characters and invalid UTF-8 byte sequences.
  // Do not decode characters which are interpreted by the filesystem and would meaningfully alter the path.
  // For Windows, that means 0x00, 0x2F, and 0x5C. Pct-encoded periods are already interpreted by the URL parser.

  var filePath = ContiguousArray<UInt8>()
  filePath.reserveCapacity(url.utf8.path.count)

  for i in urlPath.lazy.percentDecodedUTF8.indices {
    if i.isDecoded {
      if i.decodedValue == ASCII.null.codePoint {
        return .failure(.encodedNullBytes)
      }
      if isWindowsFilePathSeparator(i.decodedValue) {
        return .failure(.encodedPathSeparator)
      }
    }
    filePath.append(i.decodedValue)
  }

  assert(!filePath.isEmpty)
  assert((filePath.first == ASCII.forwardSlash.codePoint) == isUNC)

  // Normalization.
  // At this point, we should only be using forward slashes since the path came from the URL,
  // so collapse them and replace with back slashes.

  assert(!filePath.contains(ASCII.backslash.codePoint))

  filePath.collapseForwardSlashes(from: 0)
  filePath.trimPathSegmentsForWindows(from: 0, isUNC: isUNC)
  for i in 0..<filePath.count {
    if filePath[i] == ASCII.forwardSlash.codePoint {
      filePath[i] = ASCII.backslash.codePoint
    }
  }

  assert(!filePath.isEmpty)
  assert((filePath.first == ASCII.backslash.codePoint) == isUNC)

  // Prepend the UNC server name.

  if isUNC {
    let hostname = url.utf8.hostname!
    assert(!hostname.contains(ASCII.percentSign.codePoint), "file URL hostnames cannot contain percent-encoding")

    if hostname.first == ASCII.leftSquareBracket.codePoint {
      // IPv6 hostnames must be transcribed for UNC:
      // https://en.wikipedia.org/wiki/IPv6_address#Literal_IPv6_addresses_in_UNC_path_names
      assert(hostname.last == ASCII.rightSquareBracket.codePoint, "Invalid hostname")
      assert(IPv6Address(utf8: hostname.dropFirst().dropLast()) != nil, "Invalid IPv6 hostname")

      var transcribedHostAndPrefix = ContiguousArray(#"\\"#.utf8)
      transcribedHostAndPrefix += hostname.dropFirst().dropLast().lazy.map { codePoint in
        codePoint == ASCII.colon.codePoint ? ASCII.minus.codePoint : codePoint
      }
      transcribedHostAndPrefix += ".ipv6-literal.net".utf8
      filePath.insert(contentsOf: transcribedHostAndPrefix, at: 0)
    } else {
      filePath.insert(contentsOf: hostname, at: 0)
      filePath.insert(contentsOf: #"\\"#.utf8, at: 0)
    }
  }

  // Null-termination (if requested).

  if nullTerminated {
    filePath.append(0)
  }

  return .success(filePath)
}


// --------------------------------------------
// MARK: - Utilities
// --------------------------------------------


/// The URL `file:///` - the simplest valid file URL, consisting of an empty hostname and a root path.
///
@inlinable
internal var _emptyFileURL: WebURL {
  WebURL(
    storage: AnyURLStorage(
      URLStorage<BasicURLHeader<UInt8>>(
        count: 8,
        structure: URLStructure(
          schemeLength: 5, usernameLength: 0, passwordLength: 0, hostnameLength: 0,
          portLength: 0, pathLength: 1, queryLength: 0, fragmentLength: 0, firstPathComponentLength: 1,
          sigil: .authority, schemeKind: .file, cannotBeABaseURL: false, queryIsKnownFormEncoded: true),
        initializingCodeUnitsWith: { buffer in
          ("file:///" as StaticString).withUTF8Buffer { buffer.fastInitialize(from: $0) }
        }
      )
    ))
}

extension PercentEncodeSet {

  /// A percent-encode set for Windows DOS-style path components, as well as UNC share names and UNC path components.
  ///
  /// This set encodes ASCII codepoints which may occur in the Windows path components, but have special meaning in a URL string.
  /// The set does not include the 'path' encode-set, as some codepoints must stay in their original form for trimming (e.g. spaces, periods).
  ///
  /// Note that the colon character (`:`) is also included, so this encode-set is not appropriate for Windows drive letter components.
  /// Drive letters should not be percent-encoded.
  ///
  @usableFromInline
  internal struct WindowsPathPercentEncoder: PercentEncodeSetProtocol {
    // swift-format-ignore
    @inlinable
    internal static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      // Encode:
      // - The `%` sign itself. Filesystem paths do not contain percent-encoding, and any character seqeuences which
      //   look like percent-encoding are just coincidences.
      codePoint == ASCII.percentSign.codePoint
      // - Colons (`:`). These are interpreted as Windows drive letter delimiters; but *actual* drive letters
      //   are detected by the file-path-to-URL function and not encoded. Any other components that look
      //   like drive letters are coincidences.
      || codePoint == ASCII.colon.codePoint
      // - Vertical bars (`|`). These are sometimes interpreted as Windows drive delimiters in URL paths
      //   and relative references, but not by Windows in filesystem paths.
      || codePoint == ASCII.verticalBar.codePoint
    }
  }

  /// A percent-encode set for POSIX-style path components.
  ///
  /// This set encodes ASCII codepoints which may occur in the path components of a POSIX-style path, but have special meaning in a URL string.
  /// The set includes the codepoints of the 'path' encode-set, as the components of POSIX paths are not trimmed.
  ///
  @usableFromInline
  internal struct POSIXPathPercentEncoder: PercentEncodeSetProtocol {
    // swift-format-ignore
    @inlinable
    internal static func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
      // Encode:
      // - The '%' sign itself. Filesystem paths do not contain percent-encoding, and any character seqeuences which
      //   look like percent-encoding are just coincidences.
      codePoint == ASCII.percentSign.codePoint
      // - Backslashes (`\`). They are allowed in POSIX paths and are not separators.
      || codePoint == ASCII.backslash.codePoint
      // - Colons (`:`) and vertical bars (`|`). These are sometimes interpreted as Windows drive letter delimiters,
      //   which POSIX paths obviously do not have.
      || codePoint == ASCII.colon.codePoint || codePoint == ASCII.verticalBar.codePoint
      // - The entire 'path' percent-encode set. The path setter will check this and do it as well, but we can
      //   make things more efficient by correctly encoding the path in the first place.
      //   Since POSIX path components are not trimmed, we don't need to avoid encoding things like spaces or periods.
      || PercentEncodeSet.Path.shouldPercentEncode(ascii: codePoint)
    }
  }

  @usableFromInline
  internal var windowsPath: WindowsPathPercentEncoder.Type { WindowsPathPercentEncoder.self }

  @usableFromInline
  internal var posixPath: POSIXPathPercentEncoder.Type { POSIXPathPercentEncoder.self }
}

/// Whether the given code-unit, which is assumed to be in a Windows 'filesystem-safe' encoding, is considered a path separator on Windows.
///
@inlinable
internal func isWindowsFilePathSeparator(_ codeUnit: UInt8) -> Bool {
  ASCII(codeUnit) == .forwardSlash || ASCII(codeUnit) == .backslash
}

extension Collection where Element == UInt8 {

  /// Whether this collection, when split by elements matching the given `isSeparator` closure, contains any segments
  /// that consist of the ASCII string ".." only ([0x2E, 0x2E]).
  ///
  @inlinable
  internal func containsLiteralDotDotComponent(isSeparator: (UInt8) -> Bool) -> Bool {
    (".." as StaticString).withUTF8Buffer { dotdot in
      var componentStart = startIndex
      while let separatorIndex = self[componentStart...].firstIndex(where: isSeparator) {
        guard !self[componentStart..<separatorIndex].elementsEqual(dotdot) else {
          return true
        }
        componentStart = index(after: separatorIndex)
      }
      guard !self[componentStart...].elementsEqual(dotdot) else {
        return true
      }
      return false
    }
  }
}

extension BidirectionalCollection where Self: MutableCollection, Self: RangeReplaceableCollection, Element == UInt8 {

  /// Replaces runs of 2 or more ASCII forward slashes (0x2F) with a single forward slash, starting at the given index.
  ///
  @inlinable
  internal mutating func collapseForwardSlashes(from start: Index) {
    let end = collapseConsecutiveElements(from: start) { $0 == ASCII.forwardSlash.codePoint }
    removeSubrange(end...)
  }

  /// Replaces runs of 2 or more Windows path separators with a single separator, starting at the given index.
  /// For each run of separators, the first separator is kept.
  ///
  @inlinable
  internal mutating func collapseWindowsPathSeparators(from start: Index) {
    let end = collapseConsecutiveElements(from: start) { isWindowsFilePathSeparator($0) }
    removeSubrange(end...)
  }

  /// Splits the collection's contents in to segments at Windows path separators, from the given index,
  /// and trims each segment according to Windows' documented path normalization rules.
  ///
  /// If the path is a UNC path (`isUNC` is `true`), the first component is interpreted as a UNC share name and is not trimmed.
  ///
  @inlinable
  internal mutating func trimPathSegmentsForWindows(from start: Index, isUNC: Bool) {
    let end = trimSegments(from: start, separatedBy: isWindowsFilePathSeparator) { component, isFirst, isLast in
      guard !(isUNC && isFirst) else {
        // The first component is the share name. IE and Windows Explorer appear to have a bug and trim these,
        // but GetFullPathName, Edge, and Chrome do not.
        // https://github.com/dotnet/docs/issues/24563
        return component
      }

      // Windows path component trimming:
      //
      // - If a segment ends in a single period, that period is removed.
      //   (A segment of a single or double period is normalized in the previous step.
      //    A segment of three or more periods is not normalized and is actually a valid file/directory name.)
      // - If the path doesn't end in a separator, all trailing periods and spaces (U+0020) are removed.
      //   If the last segment is simply a single or double period, it falls under the relative components rule above.
      //   This rule means that you can create a directory name with a trailing space by adding
      //   a trailing separator after the space.
      //
      //   Source: https://docs.microsoft.com/en-us/dotnet/standard/io/file-path-formats#trim-characters

      // Single-dot-components will be normalized by the URL path parser.
      if component.elementsEqual(CollectionOfOne(ASCII.period.codePoint)) {
        return component
      }
      // Double-dot-components should have been rejected already.
      assert(!component.elementsEqual(repeatElement(ASCII.period.codePoint, count: 2)))

      if isLast {
        // Trim all dots and spaces, even if it leaves the component empty.
        let charactersToTrim = component.suffix { $0 == ASCII.period.codePoint || $0 == ASCII.space.codePoint }
        return component[component.startIndex..<charactersToTrim.startIndex]
      } else {
        // If the component ends with <non-dot><dot>, trim the trailing dot.
        if component.last == ASCII.period.codePoint {
          let trimmedComponent = component.dropLast()
          assert(!trimmedComponent.isEmpty)
          if trimmedComponent.last != ASCII.period.codePoint {
            return trimmedComponent
          }
        }
        // Otherwise, nothing to trim; we're done.
        return component
      }
    }
    removeSubrange(end...)
  }
}
