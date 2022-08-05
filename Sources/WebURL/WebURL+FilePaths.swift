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
/// A format describes the structure and normalization rules of a file path, as well as the
/// properties of binary paths supported by WebURL. They are used to interpret or prepare file paths
/// for a particular system.
///
/// ```swift
/// // ℹ️ POSIX paths (for macOS, iOS, Linux, etc) require the .posix format.
/// try WebURL(filePath: "/usr/bin/swift", format: .posix)
///   // ✅ "file:///usr/bin/swift"
/// try WebURL(filePath: "/usr/bin/swift", format: .windows)
///   // ❌ Not a valid Windows path (no drive letter).
///
/// // ℹ️ Windows paths require the .windows format.
/// try WebURL(filePath: #"C:\Windows\"#, format: .windows)
///   // ✅ "file:///C:/Windows/"
/// try WebURL(filePath: #"C:\Windows\"#, format: .posix)
///   // ❌ Interpreted as a relative path by POSIX (no "/").
///
/// // ℹ️ Use .native for the current machine's format (.native is usually the default).
/// try WebURL(filePath: NSTemporaryDirectory(), format: .native)
///   // ✅ A known native path.
/// ```
///
/// Currently, two file path formats are supported: ``posix`` and ``windows``. Their documentation provides
/// detailed information and references about the kinds of paths which are supported, and how to interoperate
/// with the platform's binary path format.
///
/// Most of the time you should specify the ``native`` format, which resolves to the appropriate value
/// for the compile target.
///
/// > Tip:
/// > If you're only working with paths for the local system, we recommend using swift-system's `FilePath` type.
/// > The `WebURLSystemExtras` module contains WebURL <-> FilePath conversions which handle the details of each
/// > system's path format for you, and help you write portable, correct code.
/// >
/// > ```swift
/// > // This works on both POSIX systems and Windows
/// > // (although the file locations need adapting).
/// > import WebURL
/// > import System
/// > import WebURLSystemExtras
/// >
/// > // Start with a file URL.
/// > let url = WebURL("file:///private/tmp/my%20file.dat")!
/// >
/// > // Reconstruct the file path.
/// > let path = try FilePath(url: url)
/// >
/// > // Open the file and write some data.
/// > let descriptor = try FileDescriptor.open(path, .readWrite, options: .create, permissions: [.ownerReadWrite, .otherRead])
/// > try descriptor.writeAll("hello, world!".utf8)
/// > try descriptor.close()
/// > ```
///
/// ## Topics
///
/// ### Supported Formats
///
/// - ``FilePathFormat/posix``
/// - ``FilePathFormat/windows``
/// - ``FilePathFormat/native``
///
/// ### Errors
///
/// - ``FilePathFromURLError``
/// - ``URLFromFilePathError``
///
/// ## See Also
///
/// - ``WebURL/init(filePath:format:)``
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
  /// ## Path Format & Normalization
  ///
  /// The format and interpretation of POSIX-style paths is documented by [IEEE Std 1003.1][POSIX-4-13].
  ///
  /// Consecutive separators can be normalized to a single separator, except that 2 separators at the start
  /// of the path cannot be collapsed. This means that:
  ///
  /// - `/usr/bin`,
  /// - `/usr//bin`, and
  /// - `/usr///bin`
  ///
  /// Are all the same path, but `//usr/bin` is considered a different path.
  ///
  /// As the contents of path components have no defined meaning, they must not be altered by any normalization
  /// procedure.
  ///
  /// ## Binary Path Encoding
  ///
  /// This section describes how binary file paths are obtained from the Operating System and how their bytes
  /// are interpreted by WebURL functions.
  ///
  /// The following byte values have particular meaning in POSIX-style paths.
  ///
  /// | Code Unit       | ASCII Character | Purpose                                       |
  /// | --------------- | :-------------: | --------------------------------------------- |
  /// | `0x00`          |       -         | End of String                                 |
  /// | `0x2E`          |      `.`        | Current directory (1x); Parent directory (2x) |
  /// | `0x2F`          |      `/`        | Path separator                                |
  ///
  /// All other values are not specified and do not necessarily have any meaning beyond opaque bytes.
  /// Some systems enforce these to be Unicode code-points in UTF-8, but that must not be assumed.
  ///
  /// As such, this format defines an 8-bit binary file path to be in an **unspecified, filesystem-safe encoding**,
  /// where "filesystem-safe" means that the above byte values have no purpose other than that described by the table.
  ///
  ///
  /// [POSIX-4-13]: https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_13
  ///
  @inlinable
  public static var posix: FilePathFormat {
    FilePathFormat(.posix)
  }

  /// A path which is compatible with those used by Microsoft Windows.
  ///
  /// ## Path Formats & Normalization
  ///
  /// There are many, many Windows path formats. This format value represents the most common ones:
  /// DOS paths, UNC paths, and Long paths.
  ///
  /// | Kind           | Example                                               |
  /// |----------------|-------------------------------------------------------|
  /// | DOS path       | `C:\Users\Alice\Desktop\family.jpg`                   |
  /// | UNC path       | `\\us-west.example.com\files\meeting-notes-june.docx` |
  /// | Long DOS path  | `\\?\C:\Users\Bob\Documents\...`                      |
  /// | Long UNC path  | `\\?\UNC\europe.example.com\jim\...`                  |
  ///
  /// Each of these has different sets of allowed characters and normalization rules, which are summarized
  /// in subsequent sections. This information has been collected from a variety of sources which may be worth
  /// consulting for further clarification:
  ///
  /// - [Microsoft: File path formats on Windows systems][MS-PathFormat]
  /// - [Microsoft: Naming Files, Paths, and Namespaces][MS-FileNaming]
  /// - [Microsoft: UNC Path specification][MS-UNCSPEC]
  /// - [Project Zero: The Definitive Guide on Win32 to NT Path Conversion][PRZ-NTPaths]
  ///
  /// ### DOS Paths
  ///
  /// DOS paths begin with a drive letter and path separator.
  /// Both forward-slashes and back-slashes are accepted as path separators.
  ///
  /// Windows has a notion of a "current drive", and each drive has its own "current directory".
  /// This means there are lots of kinds of relative paths:
  ///
  /// | Path                         | Description                                              |
  /// | ---------------------------- | -------------------------------------------------------- |
  /// | `C:\Users\Alice\picture.jpg` | A path from the root of the `C:` drive (fully-qualified) |
  /// | `\Users\Alice\picture.jpg`   | A path from the root of the current drive                |
  /// | `D:picture.jpg`              | A path from the current directory of the `D:` drive      |
  /// | `picture.jpg`                | A path from the current directory of the current drive   |
  ///
  /// ### UNC Paths
  ///
  /// UNC paths begin with a two-separator prefix, followed by a server name, share name, and a path within the share.
  /// Both forward-slashes and back-slashes are accepted as path separators.
  ///
  /// **Example**: `\\us-west.example.com\files\meeting-notes-june.docx`
  /// - **Server**: `us-west.example.com`
  /// - **Share**: `files`
  /// - **Path**: `\meeting-notes-june.docx`
  ///
  /// UNC paths are always fully-qualified. It is possible to resolve relative references against them,
  /// but there is no concept of a "relative UNC path".
  ///
  /// For both DOS and UNC paths, consecutive separators can be normalized to a single separator (except for the
  /// double-slash prefix in UNC paths).
  ///
  /// Trailing ASCII periods and spaces may be trimmed from path components, in accordance with
  /// [Microsoft's documentation][MS-PathFormat]. It is not possible to express files named "`foo.`"
  /// with these paths, and even trying can be dangerous.
  ///
  /// ### Long paths
  ///
  /// Regular Windows paths are typically limited to 260 characters; in order to overcome this limit, an alternative
  /// "long path" format can be used. These have the prefix "`\\?\`", and are a kind of low-level path handled by
  /// something called the "object manager". They can point to devices and more abstract things, but also support
  /// locations with drive letters and UNC locations.
  ///
  /// | Path                                              | Description                      |
  /// | ------------------------------------------------- | -------------------------------- |
  /// | `\\?\C:\Users\Alice\...`                          | Long file path with drive letter |
  /// | `\\?\UNC\us-west.example.com\files\...`           | Long UNC path                    |
  /// | `\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1` | Abstract Win32 path              |
  ///
  /// The strict definition of these paths is that the back-slash (`\`, `0x5C`) is the path separator,
  /// and **all other characters** (even `NULL`s) are unreserved and may be used in path components.
  ///
  /// This has some interesting implications, and forces us to accept the following limitations:
  ///
  /// - "`..`" components are forbidden.
  ///
  ///   In this case, they do not mean parent traversal, but actually a file _named_ "`..`". This cannot be expressed
  ///   in a URL (even with percent-encoding). Also, Windows APIs are not consistent, and will sometimes interpret
  ///   these as parent traversal regardless, and this ambiguity could be a potential security risk.
  ///   No commonly-used filesystem or network protocol on Windows supports these file or directory names anyway.
  ///
  /// - Forward slashes are forbidden.
  ///
  ///   They represent files with literal forward slashes in their name. Again, Windows APIs are not consistent,
  ///   and will sometimes interpret these as path separators regardless, which can be a security risk.
  ///   No commonly-used filesystem or network protocol on Windows supports these file or directory names anyway.
  ///
  /// In practice, they should not affect well-formed long paths. Additionally, this `FilePathFormat` limits the allowed
  /// Win32 paths to those which are actually "long file paths":
  ///
  /// - Long file paths with drive letters
  /// - Long UNC paths
  ///
  /// Paths such as `\\?\GLOBALROOT\Device\...` are not supported. Due to this limiting accepted paths to those used
  /// in filesystem contexts, the following normalization procedure is considered safe:
  ///
  /// - Empty and "`.`" components will be removed.
  ///
  ///   Empty components have no meaning on any filesystem, and all commonly-used filesystems on Windows
  ///   (including FAT, exFAT, NTFS, and ReFS) forbid files and directories named "`.`". SMB/CIFS and NFS
  ///   (the most common protocols used with UNC) likewise define that "`.`" components refer to the current directory.
  ///
  /// ## Binary Path Encoding
  ///
  /// This section describes how binary file paths are obtained from the Operating System and how their bytes
  /// are interpreted by WebURL functions.
  ///
  /// Windows file paths are defined as containing Unicode code-points. However, Windows for the most part
  /// does not verify that Unicode text is valid, nor does it employ canonical equivalence for path lookups.
  /// This means that path components may contain invalid text (such as lone surrogates), and their code-points
  /// must be preserved exactly. Reserved code-points are within the ASCII range.
  ///
  /// | Code-Point(s)            | Character(s) | Purpose                                        |
  /// | ------------------------ | ------------ | ---------------------------------------------- |
  /// | REVERSE SOLIDUS, U+005C  |    `\`       | Path separator                                 |
  /// | SOLIDUS, U+002F          |    `/`       | Path separator (DOS and UNC only)              |
  /// | FULL STOP, U+002E        |    `.`       | Current directory (1x); Parent directory (2x)  |
  /// | QUESTION MARK, U+003F    |    `?`       | Element of Long Path prefix ("`\\?\`")         |
  /// | Alphas from Basic Latin  | `a-z,A-Z`    | Drive letters (DOS and Long DOS only)          |
  /// | COLON, U+003A            |    `:`       | Drive-letter delimiter (DOS and Long DOS only) |
  ///
  /// As such, this format defines an 8-bit binary file path to be in an **unspecified, ASCII-compatible encoding**.
  /// Effectively, ASCII bytes will be considered as alphas, colons, slashes, spaces, etc., and all other bytes
  /// within a path component are considered opaque. There is one exception: the hostname of a UNC or Long UNC path
  /// must be valid UTF-8/ASCII, as it is subject to domain normalization (IDNA).
  ///
  /// The Windows API exposes file paths using UTF-16 code-units, which can be transcoded to/from UTF-8 losslessly.
  /// This is the preferred process, as UTF-8 supports all Unicode code-points and is expected by other systems.
  /// Handling invalid Unicode is, unfortunately, left as an exercise for the reader.
  /// There have been some creative solutions to this problem, such as the pseudo-encoding ["WTF-8"][WTF-8]
  /// (the "Wobbly Transformation Format"), which encodes these code-points in UTF-8 style regardless.
  /// It is admittedly a hack, but it can be useful in isolated systems.
  /// If in doubt, throw a ``URLFromFilePathError/transcodingFailure``.
  ///
  /// The definition of "unspecified, ASCII-compatible encoding" also happens to include ANSI encodings,
  /// such as Latin-1 or Windows-31J. It may be necessary to produce such URLs when interoperating
  /// with legacy systems, but their use is discouraged in favor of Unicode.
  ///
  /// [MS-PathFormat]: https://web.archive.org/web/20210714174116/https://docs.microsoft.com/en-us/dotnet/standard/io/file-path-formats
  /// [MS-FileNaming]: https://web.archive.org/web/20210716121600/https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file
  /// [PRZ-NTPaths]: https://web.archive.org/web/20210323091740/https://googleprojectzero.blogspot.com/2016/02/the-definitive-guide-on-win32-to-nt.html
  /// [MS-UNCSPEC]: https://web.archive.org/web/20210708165404/https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-dtyp/62e862f4-2a51-452e-8eeb-dc4ff5ee33cc
  /// [WTF-8]: https://simonsapin.github.io/wtf-8/
  ///
  @inlinable
  public static var windows: FilePathFormat {
    FilePathFormat(.windows)
  }

  /// The native path style used by the compile target.
  ///
  /// If building for a Windows platform, this returns ``windows``. Otherwise, it returns ``posix``.
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
// MARK: - URL From File Path
// --------------------------------------------


extension WebURL {

  /// Create a URL representation of a file path string.
  ///
  /// In order to create a file URL, the file path must satisfy two conditions.
  ///
  /// - It must be a valid, absolute file path. Be aware that this depends on the ``FilePathFormat``.
  ///
  ///   ```swift
  ///   // 🚩 POSIX-style paths (Apple OSes, Linux, etc)
  ///   try WebURL(filePath: "/usr/bin/swift")   // ✅ "file:///usr/bin/swift"
  ///   try WebURL(filePath: "/tmp/my file.dat") // ✅ "file:///tmp/my%20file.dat"
  ///
  ///   try WebURL(filePath: "file.txt") // ❌ Relative path
  ///   ```
  ///
  ///   ```swift
  ///   // 🚩 Windows-style paths
  ///   try WebURL(filePath: #"C:\Users\Alice\Desktop\family.jpg"#) // ✅ "file:///C:/Users/Alice/Desktop/family.jpg"
  ///   try WebURL(filePath: #"\\Janes-PC\Music\awesome song.mp3"#) // ✅ "file://janes-pc/Music/awesome%20song.mp3"
  ///
  ///   try WebURL(filePath: "/usr/bin") // ❌ Relative path on Windows (no drive letter).
  ///   ```
  ///
  /// - It must not contain any "`..`" components.
  ///
  ///   ```swift
  ///   try WebURL(filePath: "/usr/local/../../etc/passwd") // ❌ Parent traversal.
  ///   ```
  ///
  /// Some minimal normalization is applied to the path according to the ``FilePathFormat``
  /// (for example, collapsing duplicate slashes, such as `/usr//bin` -> `/usr/bin`),
  /// and percent-encoding is added where required.
  ///
  /// > Tip:
  /// >
  /// > In general, file paths are binary rather than textual, so it is recommended
  /// > that developers use a dedicated file path type such as swift-system's `FilePath`.
  /// > Some paths will become corrupted if stored as a string, so WebURL only reconstructs
  /// > file paths from URLs as a _binary_ result.
  /// >
  /// > The `WebURLSystemExtras` library includes bidirectional `WebURL` <-> `FilePath` conversions,
  /// > and is the best way to convert between file URLs and file paths.
  /// >
  /// > ```swift
  /// > import WebURL
  /// > import System
  /// > import WebURLSystemExtras
  /// >
  /// > // Start with a file URL.
  /// > let url = WebURL("file:///private/tmp/my%20file.dat")!
  /// >
  /// > // Reconstruct the file path.
  /// > let path = try FilePath(url: url)
  /// >
  /// > // Open the file and write some data.
  /// > let descriptor = try FileDescriptor.open(path, .readWrite, options: .create, permissions: [.ownerReadWrite, .otherRead])
  /// > try descriptor.writeAll("hello, world!".utf8)
  /// > try descriptor.close()
  /// > ```
  ///
  /// - parameters:
  ///   - filePath: The file path from which to create the file URL.
  ///   - format:   The way in which `filePath` should be interpreted.
  ///               The default is ``FilePathFormat/native``, which resolves to the appropriate value for the
  ///               compile target.
  ///
  /// - throws: ``URLFromFilePathError``
  ///
  /// ## See Also
  ///
  /// - ``WebURL/WebURL/binaryFilePath(from:format:nullTerminated:)``
  /// - ``WebURL/FilePathFormat``
  ///
  public init<StringType>(
    filePath: StringType, format: FilePathFormat = .native
  ) throws where StringType: StringProtocol {
    self = try filePath._withContiguousUTF8 { utf8 in try WebURL.fromBinaryFilePath(utf8, format: format) }
  }
}

extension WebURL {

  /// Creates a URL representation of a binary file path.
  ///
  /// In order to create a file URL, the file path must satisfy two conditions:
  ///
  /// - It must be a syntactically valid, non-relative binary path according to the ``FilePathFormat``, and
  /// - It must not contain any components which traverse to their parent directories ("`..`" components).
  ///
  /// Additionally, it must not contain `NULL` bytes, so the terminator of a null-terminated string should
  /// not be included in the binary file path. Otherwise, a ``URLFromFilePathError`` error will be thrown
  /// which can be used to provide diagnostics.
  ///
  /// Some minimal normalization is applied to the path according to the ``FilePathFormat`` (for example,
  /// collapsing duplicate slashes, such as `/usr//bin` -> `/usr/bin`), and percent-encoding is added where required.
  ///
  /// ### Encoding
  ///
  /// The given ``FilePathFormat`` determines how the binary file path is interpreted. Each format contains
  /// documentation and references explaining which bytes are reserved or not, and how to obtain a binary path
  /// from the Operating System.
  ///
  /// The TL;DR is:
  ///
  /// - On POSIX systems (Apple OSes, Linux, Android), file and directory names are considered binary data rather
  ///   than textual. The most direct way to obtain a binary path is to use a C string (minus the null terminator).
  ///   See ``FilePathFormat/posix`` for more.
  ///
  /// - On Windows, the platform APIs work with paths as UTF-16. Use these and transcode to UTF-8 to obtain an
  ///   8-bit binary path. They might contain invalid Unicode, but there's no good answer as to what to do about that.
  ///   Throwing a ``URLFromFilePathError/transcodingFailure`` error is reasonable. See ``FilePathFormat/windows`` .
  ///
  /// ```swift
  /// // This example demonstrates use on POSIX systems;
  /// // Windows developers should use the '-W' family of platform functions and convert to UTF-8.
  /// // Or use swift-system's FilePath.
  /// import Darwin // or Glibc, etc.
  ///
  /// // Start with a C path.
  /// let cwd: UnsafeMutablePointer<CChar> = getcwd(nil, 0)!
  /// defer { free(cwd) }
  ///
  /// // Use 'realpath' to normalize.
  /// let normalCwd: UnsafeMutablePointer<CChar> = realpath(cwd, nil)!
  /// defer { free(normalCwd) }
  ///
  /// // Handle signed CChar by rebinding.
  /// let normalCwdLen = strlen(normalCwd)
  /// let url: WebURL = try normalCwd.withMemoryRebound(to: UInt8.self, capacity: normalCwdLen) {
  ///   // Do not include the null terminator.
  ///   let buffer = UnsafeBufferPointer(start: UnsafePointer($0), count: normalCwdLen)
  ///   return try WebURL.fromBinaryFilePath(buffer)
  ///   // ✅ "file:///private/tmp"
  /// }
  /// ```
  ///
  /// > Tip:
  /// > To work with binary file paths, we recommend developers use a dedicated file path type,
  /// > such as swift-system's `FilePath`. The `WebURL(filePath: FilePath)` initializer from `WebURLSystemExtras` is
  /// > the best way to construct a file URL from a binary file path. It handles the transcoding on Windows mentioned
  /// > above, and provides simple APIs to check that a binary path is absolute and contains no "`..`" components.
  /// >
  /// > ```swift
  /// > import WebURL
  /// > import System
  /// > import WebURLSystemExtras
  /// >
  /// > let cString = getcwd(nil, 0)
  /// > defer { free(cString) }
  /// >
  /// > var path = FilePath(cString: cString)
  /// > path.lexicallyNormalize()
  /// > let url = try WebURL(filePath: path)
  /// > // ✅ "file:///private/tmp"
  /// > ```
  ///
  /// [WTF-8]: https://simonsapin.github.io/wtf-8/
  ///
  /// - parameters:
  ///   - path:   The binary file path, as a collection of 8-bit code-units.
  ///   - format: The way in which `path` should be interpreted.
  ///             The default is ``FilePathFormat/native``, which resolves to the correct format for the
  ///             compile target.
  ///
  /// - throws: ``URLFromFilePathError``
  ///
  @inlinable
  public static func fromBinaryFilePath<Bytes>(
    _ path: Bytes, format: FilePathFormat = .native
  ) throws -> WebURL where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {
    let result =
      path.withContiguousStorageIfAvailable {
        _urlFromBinaryFilePath_impl($0.boundsChecked, format: format)
      } ?? _urlFromBinaryFilePath_impl(path, format: format)
    return try result.get()
  }
}

/// The reason why a file URL could not be created from a file path.
///
/// ## Topics
///
/// ### All Paths
///
/// - ``URLFromFilePathError/emptyInput``
/// - ``URLFromFilePathError/nullBytes``
/// - ``URLFromFilePathError/relativePath``
/// - ``URLFromFilePathError/upwardsTraversal``
///
/// ### Windows Paths
///
/// - ``URLFromFilePathError/invalidHostname``
/// - ``URLFromFilePathError/invalidPath``
/// - ``URLFromFilePathError/unsupportedWin32NamespacedPath``
/// - ``URLFromFilePathError/transcodingFailure``
///
public struct URLFromFilePathError: Error, Equatable, Hashable, CustomStringConvertible {

  @usableFromInline
  internal enum _Err {
    case emptyInput
    case nullBytes
    case relativePath
    case upwardsTraversal
    case invalidHostname
    case invalidPath
    case unsupportedWin32NamespacedPath
    case transcodingFailure
  }

  @usableFromInline
  internal var _err: _Err

  @inlinable init(_ _err: _Err) {
    self._err = _err
  }

  /// The file path is empty.
  ///
  @inlinable
  public static var emptyInput: URLFromFilePathError {
    URLFromFilePathError(.emptyInput)
  }

  /// The file path contains ASCII `NULL` bytes.
  ///
  /// `NULL` bytes are forbidden to protect against injected truncation. If the file path is a null-terminated string,
  /// remove the null terminator prior to calling ``WebURL/fromBinaryFilePath(_:format:)``.
  ///
  /// ```swift
  /// let cString: UnsafePointer<CChar> = ...
  /// let len = strlen(cString)
  ///
  /// // Handle signed CChar by rebinding.
  /// let url = try cString.withMemoryRebound(to: UInt8.self, capacity: len) {
  ///   // Do not include the null terminator.
  ///   let buffer = UnsafeBufferPointer(start: $0, count: len)
  ///   return try WebURL.fromBinaryFilePath(buffer) // ✅
  /// }
  /// ```
  ///
  @inlinable
  public static var nullBytes: URLFromFilePathError {
    URLFromFilePathError(.nullBytes)
  }

  /// The file path is relative.
  ///
  /// Each ``FilePathFormat`` has different kinds of relative paths, and some formats have many kinds.
  /// Consult the format's documentation for more information.
  ///
  /// To resolve a path, use the APIs provided by the platform (such as `realpath` on POSIX, or `GetFullPathNameW`
  /// on Windows), or another library. Swift-system's `FilePath` type contains operations such as `push(FilePath)`,
  /// which allows you to resolve a relative path, and `lexicallyResolving(FilePath)`, which additionally ensures
  /// that the result does not escape the base path.
  ///
  /// ```swift
  /// import System
  ///
  /// let relativePath: FilePath = "file.txt"
  /// try WebURL(filePath: relativePath)
  /// // ❌ Relative path
  ///
  /// // Resolve the relative path against a base path;
  /// // in this case the current working directory.
  /// let baseCString = getcwd(nil, 0)!
  /// defer { free(baseCString) }
  /// guard let resolvedPath = FilePath(cString: baseCString).lexicallyResolving(relativePath) else {
  ///   // Unexpectedly escaped the base path!
  ///   fatalError()
  /// }
  ///
  /// try WebURL(filePath: resolvedPath)
  /// // ✅ "file:///private/tmp/file.txt"
  /// ```
  ///
  @inlinable
  public static var relativePath: URLFromFilePathError {
    URLFromFilePathError(.relativePath)
  }

  /// The file path contains `..` components.
  ///
  /// Consider the following POSIX-style path:
  ///
  /// ```swift
  /// try WebURL(filePath: "/usr/bin/../../etc/passwd")
  /// // ❌ Upwards traversal
  /// ```
  ///
  /// It can be quite easy for ".." components to enter a path string if it consists (even partially) of components
  /// which an attacker can influence. The URL Standard requires paths in URLs to be fully resolved, and automatically
  /// collapsing this path is considered a potential security risk.
  ///
  /// Instead, resolve the path yourself, and check that it points to where you intended it to go. You can use
  /// swift-system's `FilePath` type to resolve a path:
  ///
  /// ```swift
  /// import System
  ///
  /// let templates = FilePath("/opt/my_app/templates/")
  ///
  /// // Resolve a relative path (perhaps containing user input),
  /// // and check it does not escape the base path.
  /// let badPath   = templates.lexicallyResolving("../../../etc/passwd")
  /// // ❌ - escapes the path
  /// let badPath2  = templates.lexicallyResolving("/etc/passwd")
  /// // ❌ - escapes the path (absolute path)
  /// let goodPath  = templates.lexicallyResolving("floral_light")
  /// // ✅ "/opt/my_app/templates/floral_light"
  ///
  /// // Or check that a lexically-normalized path is contained
  /// // within another normalized path (this does not follow symlinks).
  /// let templateName = "../../etc/passwd" // Given by attacker.
  /// let templatePath = "/opt/my_app/templates/" + templateName
  ///
  /// let normalizedPath = FilePath(templatePath).lexicallyNormalized()
  /// guard normalizedPath.starts(with: "/opt/my_app/templates/") else {
  ///   throw BadPathError()
  /// }
  /// // ✅
  /// ```
  ///
  @inlinable
  public static var upwardsTraversal: URLFromFilePathError {
    URLFromFilePathError(.upwardsTraversal)
  }

  /// The file path refers to a remote host, but the hostname is not valid or is unsupported.
  ///
  /// Note that currently, only ASCII domains, IPv4, and IPv6 addresses are supported.
  /// Domains may not include [forbidden host code-points][URL-FHCP].
  ///
  /// [URL-FHCP]: https://url.spec.whatwg.org/#forbidden-host-code-point
  ///
  @inlinable
  public static var invalidHostname: URLFromFilePathError {
    URLFromFilePathError(.invalidHostname)
  }

  /// The file path is ill-formed.
  ///
  /// Win32 file namespace paths (a.k.a. "long" paths) require a device component followed by a backslash.
  /// Examples of invalid Win32 file namespace paths:
  ///
  /// - `\\?\` (no path following prefix)
  /// - `\\?\\` (device name is empty)
  /// - `\\?\C:` (no trailing slash after device name)
  /// - `\\?\UNC` (no trailing slash after device name)
  ///
  @inlinable
  public static var invalidPath: URLFromFilePathError {
    URLFromFilePathError(.invalidPath)
  }

  /// The file path uses an unsupported Win32 file namespace.
  ///
  /// Win32 file namespace paths have a variety of ways to reference files - for instance,
  /// both `\\?\BootPartition\Users\` and `\\?\HarddiskVolume2\Users\` might resolve to `\\?\C:\Users\`.
  /// They might also refer to abstract objects whose paths have little in the way of defined semantics.
  /// These more exotic paths are not supported.
  ///
  /// Long paths must either include a drive letter, or reference a UNC location.
  ///
  /// - `\\?\C:\Users\` ✅
  /// - `\\?\UNC\someserver.com\someshare\files\spreadsheet.xlsx` ✅
  ///
  @inlinable
  public static var unsupportedWin32NamespacedPath: URLFromFilePathError {
    URLFromFilePathError(.unsupportedWin32NamespacedPath)
  }

  // '.transcodingFailure' is thrown by higher-level functions (e.g. System.FilePath -> WebURL),
  // but defined as part of URLFromFilePathError.

  /// The file path could not be transcoded.
  ///
  /// Binary file paths must be in an ASCII-compatible (8-bit) encoding. If the platform's native
  /// path representation uses a different encoding, it needs to be transcoded.
  ///
  /// On Windows, the platform's native path representation uses a 16-bit encoding of Unicode code-points,
  /// and in general this can be transcoded to UTF-8 losslessly. However, in very rare cases the path may contain
  /// invalid Unicode text (such as lone surrogates), which it is not possible to transcode.
  ///
  /// There is, unfortunately, no good answer to this.
  ///
  @inlinable
  public static var transcodingFailure: URLFromFilePathError {
    URLFromFilePathError(.transcodingFailure)
  }

  public var description: String {
    switch _err {
    case .emptyInput: return "Path is empty"
    case .nullBytes: return "Path contains NULL bytes"
    case .relativePath: return "Path is relative"
    case .upwardsTraversal: return "Path contains upwards traversal"
    case .invalidHostname: return "Path references an invalid hostname"
    case .invalidPath: return "Path is ill-formed"
    case .unsupportedWin32NamespacedPath: return "Unsupported Win32 namespaced path"
    case .transcodingFailure: return "Transcoding failure"
    }
  }
}

@inlinable
internal func _urlFromBinaryFilePath_impl<Bytes>(
  _ path: Bytes, format: FilePathFormat
) -> Result<WebURL, URLFromFilePathError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {
  switch format._fmt {
  case .posix: return _urlFromFilePath_posix(path)
  case .windows: return _urlFromFilePath_windows(path)
  }
}

/// Creates a `file:` URL from a POSIX-style path.
///
/// The bytes must be in a 'filesystem-safe' encoding, but are otherwise just opaque bytes.
///
@inlinable @inline(never)
internal func _urlFromFilePath_posix<Bytes>(
  _ path: Bytes
) -> Result<WebURL, URLFromFilePathError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

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

  var escapedPath = ContiguousArray(path.lazy.percentEncoded(using: POSIXPathEncodeSet()))

  // Collapse multiple path slashes into a single slash, except if a leading double slash ("//usr/bin").
  // POSIX says that leading double slashes are implementation-defined.

  precondition(escapedPath[0] == ASCII.forwardSlash.codePoint)

  if escapedPath.count > 2 {
    if escapedPath[1] == ASCII.forwardSlash.codePoint, escapedPath[2] != ASCII.forwardSlash.codePoint {
      escapedPath.collapseForwardSlashes(from: 2)
    } else {
      escapedPath.collapseForwardSlashes(from: 0)
    }
  }

  var fileURL = _emptyFileURL
  try! fileURL.utf8.setPath(escapedPath)
  return .success(fileURL)
}

/// Creates a `file:` URL from a Windows-style path.
///
/// The bytes must be some kind of extended ASCII (either UTF-8 or any ANSI codepage). If a UNC server name is included, it must be UTF-8.
///
@inlinable @inline(never)
internal func _urlFromFilePath_windows<Bytes>(
  _ path: Bytes
) -> Result<WebURL, URLFromFilePathError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  guard !path.isEmpty else {
    return .failure(.emptyInput)
  }
  guard !path.contains(ASCII.null.codePoint) else {
    return .failure(.nullBytes)
  }

  if !isWindowsFilePathSeparator(path.first!) {
    // No prefix; parse as a regular DOS path.
    return _urlFromFilePath_windows_DOS(path, trimComponents: true)
  }

  if path.starts(with: #"\\?\"#.utf8) {
    // Win32 file namespace path.
    let pathWithoutPrefix = path.dropFirst(4)
    guard !pathWithoutPrefix.isEmpty else {
      return .failure(.invalidPath)
    }
    guard !pathWithoutPrefix.contains(ASCII.forwardSlash.codePoint) else {
      return .failure(.unsupportedWin32NamespacedPath)
    }
    let device = pathWithoutPrefix.prefix(while: { $0 != ASCII.backslash.codePoint })
    guard !device.isEmpty, device.endIndex < pathWithoutPrefix.endIndex else {
      return .failure(.invalidPath)
    }
    // Use the device to determine which kind of path this is.
    if ASCII.Lowercased(device).elementsEqual("unc".utf8) {
      let uncPathContents = pathWithoutPrefix[pathWithoutPrefix.index(after: device.endIndex)...]
      guard !uncPathContents.isEmpty else {
        return .failure(.invalidPath)
      }
      return _urlFromFilePath_windows_UNC(uncPathContents, trimComponents: false)
    }
    if PathComponentParser.isNormalizedWindowsDriveLetter(device) {
      return _urlFromFilePath_windows_DOS(pathWithoutPrefix, trimComponents: false)
    }
    return .failure(.unsupportedWin32NamespacedPath)
  }

  let pathWithoutLeadingSeparators = path.drop(while: isWindowsFilePathSeparator)
  guard path.distance(from: path.startIndex, to: pathWithoutLeadingSeparators.startIndex) > 1 else {
    // 1 leading separator: drive-relative path.
    return .failure(.relativePath)
  }
  // 2+ leading separators: UNC.
  return _urlFromFilePath_windows_UNC(pathWithoutLeadingSeparators, trimComponents: true)
}

@inlinable @inline(never)
internal func _urlFromFilePath_windows_DOS<Bytes>(
  _ path: Bytes, trimComponents: Bool
) -> Result<WebURL, URLFromFilePathError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  // DOS-path = <alpha><":"><separator><...> ; e.g. "C:\Windows\", "D:/foo".

  guard !path.containsLiteralDotDotComponent(isSeparator: isWindowsFilePathSeparator) else {
    return .failure(.upwardsTraversal)
  }
  let driveLetter = path.prefix(2)
  guard PathComponentParser.isNormalizedWindowsDriveLetter(driveLetter) else {
    return .failure(.relativePath)
  }
  guard driveLetter.endIndex < path.endIndex else {
    return .failure(.relativePath)
  }
  guard isWindowsFilePathSeparator(path[driveLetter.endIndex]) else {
    return .failure(.relativePath)
  }

  var escapedPath = ContiguousArray(driveLetter)
  escapedPath.append(contentsOf: path[driveLetter.endIndex...].lazy.percentEncoded(using: WindowsPathEncodeSet()))

  escapedPath.collapseWindowsPathSeparators(from: 2)
  if trimComponents {
    escapedPath.trimPathSegmentsForWindows(from: 2, isUNC: false)
  }

  var fileURL = _emptyFileURL
  try! fileURL.utf8.setPath(escapedPath)
  return .success(fileURL)
}

@inlinable @inline(never)
internal func _urlFromFilePath_windows_UNC<Bytes>(
  _ path: Bytes, trimComponents: Bool
) -> Result<WebURL, URLFromFilePathError> where Bytes: BidirectionalCollection, Bytes.Element == UInt8 {

  // UNC-postprefix = <hostname><separator share>?<separator path>?

  var fileURL = _emptyFileURL

  // UNC hostname.
  // This part must be valid UTF-8 due to IDNA.

  let rawHost = path.prefix { !isWindowsFilePathSeparator($0) }
  do {
    guard !rawHost.isEmpty else {
      return .failure(.invalidHostname)
    }
    // For now, since we don't support unicode domains,
    // check that the hostname is ASCII and doesn't include percent-encoding.
    guard rawHost.allSatisfy({ ASCII($0) != nil }), !rawHost.contains(ASCII.percentSign.codePoint) else {
      return .failure(.invalidHostname)
    }
    // Reject "?" and "." as UNC hostnames.
    // Otherwise we might create something which looks like a Win32 file namespace/local device path.
    guard !rawHost.elementsEqual(CollectionOfOne(ASCII.questionMark.codePoint)) else {
      return .failure(.invalidHostname)
    }
    guard !rawHost.elementsEqual(CollectionOfOne(ASCII.period.codePoint)) else {
      return .failure(.invalidHostname)
    }
    // The URL standard does not preserve "localhost" as a hostname in file URLs,
    // but removing it would turn a UNC path in to a local path.
    // As a workaround, replace it with "127.0.0.1". https://github.com/whatwg/url/issues/618
    if isLocalhost(utf8: rawHost) {
      var ipv4String = IPv4Address(octets: (127, 0, 0, 1)).serializedDirect
      withUnsafeBytes(of: &ipv4String.buffer) { try! fileURL.utf8.setHostname($0.prefix(Int(ipv4String.count))) }
    } else {
      guard let _ = try? fileURL.utf8.setHostname(rawHost) else {
        return .failure(.invalidHostname)
      }
    }
  }

  // UNC share & path.

  let rawShareAndPath = path.suffix(from: rawHost.endIndex)
  guard !rawShareAndPath.containsLiteralDotDotComponent(isSeparator: isWindowsFilePathSeparator) else {
    return .failure(.upwardsTraversal)
  }

  var escapedShareAndPath = ContiguousArray(rawShareAndPath.lazy.percentEncoded(using: WindowsPathEncodeSet()))

  escapedShareAndPath.collapseWindowsPathSeparators(from: escapedShareAndPath.startIndex)
  if trimComponents {
    escapedShareAndPath.trimPathSegmentsForWindows(from: escapedShareAndPath.startIndex, isUNC: true)
  }

  try! fileURL.utf8.setPath(escapedShareAndPath)
  return .success(fileURL)
}


// --------------------------------------------
// MARK: - File path from URL
// --------------------------------------------


extension WebURL {

  /// Reconstructs a binary file path from a URL.
  ///
  /// In order to create a file path, the URL must satisfy two conditions:
  ///
  /// - It must be a file URL, containing a semantically valid, non-relative path according to the ``FilePathFormat``.
  /// - It must not contain any percent-encoded directory separators or NULL bytes.
  ///
  /// Otherwise, a ``FilePathFromURLError`` error will be thrown which can be used to provide diagnostics.
  ///
  /// Some minimal normalization is applied to the path according to the ``FilePathFormat`` (for example,
  /// collapsing duplicate slashes, such as `/usr//bin` -> `/usr/bin`), and percent-encoding is removed.
  ///
  /// ### Encoding
  ///
  /// Binary paths consist of bytes decoded from the URL. Depending on the platform's file path encoding,
  /// some interpretation may be necessary.
  ///
  /// - On POSIX (Apple, Linux, etc) systems, the returned path may be used directly (without transcoding).
  ///   Request a null-terminated binary file path, then use the array's pointer as a C string when interacting
  ///   with the operating system.
  ///
  /// - On Windows, we need to turn the bytes in to a set of Unicode code-points, in UTF-16 encoding.
  ///
  ///   To do that, we need to guess how these bytes we received from some URL might be encoded.
  ///   A good strategy is to first try transcoding from UTF-8 since it is self-validating and widely used,
  ///   and if that fails, fall back to trying ANSI code-pages, including the system-specific "active" code-page.
  ///   The platform's `MultiByteToWideChar` function is able to map these encodings to Unicode.
  ///
  /// ```swift
  /// // This example demonstrates use on POSIX systems;
  /// // Windows developers should convert to UTF-16 and use the '-W' family of platform functions.
  /// // Or use swift-system's FilePath.
  /// import Darwin // or Glibc, etc.
  /// let openFn: (UnsafePointer<CChar>, Int32, mode_t) -> Int32 = Darwin.open
  ///
  /// // Start with a file URL.
  /// let url = WebURL("file:///private/tmp/my%20file.dat")!
  ///
  /// // Reconstruct the binary file path.
  /// let binaryPath = try WebURL.binaryFilePath(from: url, nullTerminated: true)
  ///
  /// // Handle signed CChar by rebinding.
  /// binaryPath.withUnsafeBufferPointer {
  ///   $0.withMemoryRebound(to: CChar.self) { cString in
  ///     // Use the C string to interact with the OS.
  ///     let descriptor = openFn(cString.baseAddress!, O_WRONLY | O_CREAT, S_IRUSR | S_IWUSR | S_IROTH)
  ///     // ... write to file
  ///     close(descriptor)
  ///   }
  /// }
  /// ```
  ///
  /// > Tip:
  /// > To work with binary file paths, we recommend developers use a dedicated file path type,
  /// > such as swift-system's `FilePath`. The `FilePath(url: WebURL)` initializer from `WebURLSystemExtras` is
  /// > the best way to construct a file path from a URL. It automatically handles platform-specific details
  /// > such as transcoding on Windows.
  /// >
  /// > ```swift
  /// > import WebURL
  /// > import System
  /// > import WebURLSystemExtras
  /// >
  /// > // Start with a file URL.
  /// > let url = WebURL("file:///private/tmp/my%20file.dat")!
  /// >
  /// > // Reconstruct the file path.
  /// > let path = try FilePath(url: url)
  /// >
  /// > // Open the file and write some data.
  /// > let descriptor = try FileDescriptor.open(path, .readWrite, options: .create, permissions: [.ownerReadWrite, .otherRead])
  /// > try descriptor.writeAll("hello, world!".utf8)
  /// > try descriptor.close()
  /// > ```
  ///
  /// - parameters:
  ///   - url:    The file URL.
  ///   - format: The kind of path to construct.
  ///             The default is ``FilePathFormat/native``, which resolves to the correct format for the
  ///             compile target.
  ///   - nullTerminated: Whether the returned binary file path should include a null-terminator.
  ///
  /// - throws: ``FilePathFromURLError``
  ///
  @inlinable
  public static func binaryFilePath(
    from url: WebURL, format: FilePathFormat = .native, nullTerminated: Bool
  ) throws -> [UInt8] {
    switch format._fmt {
    case .posix: return Array(try _filePathFromURL_posix(url, nullTerminated: nullTerminated).get())
    case .windows: return Array(try _filePathFromURL_windows(url, nullTerminated: nullTerminated).get())
    }
  }
}

/// The reason why a file path could not be created from a URL.
///
/// ## Topics
///
/// ### All URLs and Paths
///
/// - ``FilePathFromURLError/notAFileURL``
/// - ``FilePathFromURLError/encodedPathSeparator``
/// - ``FilePathFromURLError/encodedNullBytes``
///
/// ### POSIX Paths
///
/// - ``FilePathFromURLError/unsupportedNonLocalFile``
///
/// ### Windows Paths
///
/// - ``FilePathFromURLError/unsupportedHostname``
/// - ``FilePathFromURLError/windowsPathIsNotFullyQualified``
/// - ``FilePathFromURLError/transcodingFailure``
///
public struct FilePathFromURLError: Error, Equatable, Hashable, CustomStringConvertible {

  @usableFromInline
  internal enum _Err {
    case notAFileURL
    case encodedPathSeparator
    case encodedNullBytes
    case unsupportedNonLocalFile
    case unsupportedHostname
    case windowsPathIsNotFullyQualified
    case transcodingFailure
  }

  @usableFromInline
  internal var _err: _Err

  @inlinable
  internal init(_ _err: _Err) {
    self._err = _err
  }

  /// The URL is not a `file:` URL.
  ///
  @inlinable
  public static var notAFileURL: FilePathFromURLError {
    FilePathFromURLError(.notAFileURL)
  }

  /// The URL contains a percent-encoded path separator.
  ///
  /// Consider the following example:
  ///
  /// ```swift
  /// let url  = WebURL("file:///tmp/files/filename%2F..%2F..%2F..%2Fetc%2Fpasswd")!
  /// let path = try WebURL.binaryFilePath(from: url, nullTerminated: true)
  /// // ❌ - encoded path separator.
  /// // This would otherwise return "/tmp/files/filename/../../../etc/passwd"
  /// ```
  ///
  /// When a path component contains percent-encoding, it means the encoded byte is contained literally within
  /// the component. However, path separators by definition cannot be contained within a path component, so
  /// the path is invalid and potentially dangerous to decode.
  ///
  /// The path separators are defined by the ``FilePathFormat``. For POSIX paths, "%2F" (forward-slash) is prohibited,
  /// and for Windows, both "%2F" and "%5C" (backwards-slash) are prohibited, as both are accepted as path separators.
  ///
  @inlinable
  public static var encodedPathSeparator: FilePathFromURLError {
    FilePathFromURLError(.encodedPathSeparator)
  }

  /// The URL contains a percent-encoded NULL byte.
  ///
  /// Consider the following example:
  ///
  /// ```swift
  /// let url  = WebURL("file:///tmp/files/filename.doc%00.pdf")!
  /// let path = try WebURL.binaryFilePath(from: url, nullTerminated: true)
  /// // ❌ - encoded null byte.
  /// // This would otherwise return "/tmp/files/filename.doc<null>.pdf"
  /// ```
  ///
  /// When a path component contains percent-encoding, it means the encoded byte is contained literally within
  /// the component. Technically, a path could contain NULL bytes, providing it was only accessed using counted
  /// strings, but the prevalence of C interfaces using NULL-terminated strings makes it impractical and dangerous.
  ///
  /// Given the above string, `"/tmp/files/filename.doc<null>.pdf"`, a Swift application would interpret this
  /// as accessing a PDF file, but if it travels through a C interface, the path may be truncated and
  /// the operating system would read a DOC file. Attackers can use this to bypass validation routines.
  ///
  @inlinable
  public static var encodedNullBytes: FilePathFromURLError {
    FilePathFromURLError(.encodedNullBytes)
  }

  /// The URL contains a hostname, but the path format does not support hostnames.
  ///
  /// Consider the following example:
  ///
  /// ```swift
  /// let url = WebURL("file://janes-pc/docs/spring-summer-21.xlsx")!
  /// url.hostname // "janes-pc"
  /// url.path     // "/docs/spring-summer-21.xlsx"
  ///
  /// let windowsPath = try WebURL.binaryFilePath(from: url, format: .windows, nullTerminated: true)
  /// // ✅ - "\\janes-pc\docs\spring-summer-21.xlsx"
  /// // This is supported by Windows' UNC path syntax.
  ///
  /// let posixPath = try WebURL.binaryFilePath(from: url, format: .posix, nullTerminated: true)
  /// // ❌ - Unsupported non-local file
  /// // POSIX systems tend to work in a different way.
  /// // They mount remote filesystems like local folders.
  /// // e.g. "/Volumes/docs/spring-summer-21.xlsx"
  /// ```
  ///
  /// Hostnames don't have any obvious meaning to the POSIX filesystem, and ignoring them
  /// also isn't great (it would mean `"file://www.apple.com/etc/passwd"` accesses your local files,
  /// just like `"file:///etc/passwd"`), so they are considered an error.
  ///
  /// If you have reason to ignore a file's hostname, set the URL's ``WebURL/hostname`` property to the empty string.
  ///
  @inlinable
  public static var unsupportedNonLocalFile: FilePathFromURLError {
    FilePathFromURLError(.unsupportedNonLocalFile)
  }

  /// The URL's hostname is reserved by the path format.
  ///
  /// For instance, Windows UNC paths with the hostname "`.`" would be interpreted by the system
  /// as referring to a local device (e.g. `\\.\COM1`). These are not files, and creating such paths
  /// is prohibited by the ``FilePathFormat``.
  ///
  @inlinable
  public static var unsupportedHostname: FilePathFromURLError {
    FilePathFromURLError(.unsupportedHostname)
  }

  /// The URL does not contain a fully-qualified Windows path.
  ///
  /// Local paths must have a drive letter, followed by a path separator.
  ///
  /// ```swift
  /// var url  = WebURL("file:///C:/Users/Alice/")
  /// var path = try WebURL.binaryFilePath(from: url, format: .windows, nullTerminated: true)
  /// // ✅ - "C:\Users\Alice\"
  ///
  /// url  = WebURL("file:///Users/Alice/")!
  /// path = try WebURL.binaryFilePath(from: url, format: .windows, nullTerminated: true)
  /// // ❌ - Not fully-qualified. No drive letter.
  ///
  /// url  = WebURL("file:///C:Users/Alice/")!
  /// path = try WebURL.binaryFilePath(from: url, format: .windows, nullTerminated: true)
  /// // ❌ - Not fully-qualified. This is a relative path on Windows.
  ///
  /// url  = WebURL("file:///C:")!
  /// path = try WebURL.binaryFilePath(from: url, format: .windows, nullTerminated: true)
  /// // ❌ - Not fully-qualified. This is a relative path on Windows.
  /// ```
  ///
  /// If you need to repair a URL's path, consider using the ``WebURL/pathComponents-swift.property`` view.
  ///
  /// The ``FilePathFormat/windows`` documentation includes more information and resources
  /// about the various kinds of relative paths on Windows.
  ///
  @inlinable
  public static var windowsPathIsNotFullyQualified: FilePathFromURLError {
    FilePathFromURLError(.windowsPathIsNotFullyQualified)
  }

  // '.transcodingFailure' is thrown by higher-level functions (e.g. URL -> System.FilePath),
  // but defined as part of FilePathFromURLError.

  /// The URL's binary file path could not be transcoded.
  ///
  /// Binary paths consist of bytes decoded from the URL. Depending on the platform's file path encoding,
  /// some interpretation may be necessary.
  ///
  /// On Windows, we need to turn the bytes in to a set of Unicode code-points, in UTF-16 encoding.
  /// To do that, we need to guess how these bytes we received from some URL might be encoded.
  /// A good strategy is to first try transcoding from UTF-8 since it is self-validating and ubiquitous,
  /// and if that fails, fall back to trying other ANSI code-pages, including the system-specific "active" code-page.
  /// The platform's `MultiByteToWideChar` function is able to map these encodings to Unicode.
  ///
  /// This error is thrown by libraries such as `WebURLSystemExtras` when all else fails - the path isn't
  /// UTF-8, isn't in the system's ANSI code-page, nor any other fallback encodings they tried (if any).
  ///
  /// > Tip:
  /// > If you know the encoding used to create the file URL, you can transcode the binary file path to UTF-16 manually.
  /// > Make sure to pay special attention to any code-points which map to path separators or periods
  /// > (for ".." components).
  ///
  @inlinable
  public static var transcodingFailure: FilePathFromURLError {
    FilePathFromURLError(.transcodingFailure)
  }

  public var description: String {
    switch _err {
    case .notAFileURL: return "Not a file URL"
    case .encodedPathSeparator: return "Percent-encoded path separator"
    case .encodedNullBytes: return "Percent-encoded NULL bytes"
    case .unsupportedNonLocalFile: return "Unsupported non-local file"
    case .unsupportedHostname: return "Unsupported hostname"
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
internal func _filePathFromURL_posix(
  _ url: WebURL, nullTerminated: Bool
) -> Result<ContiguousArray<UInt8>, FilePathFromURLError> {

  guard case .file = url.schemeKind else {
    return .failure(.notAFileURL)
  }
  guard url.utf8.hostname!.isEmpty else {
    return .failure(.unsupportedNonLocalFile)
  }

  var filePath = ContiguousArray<UInt8>()
  filePath.reserveCapacity(url.utf8.path.count)

  // Percent-decode the path, including control characters and invalid UTF-8 byte sequences.
  // Do not decode characters which are interpreted by the filesystem and would meaningfully alter the path.
  // For POSIX, that means 0x00 and 0x2F. Pct-encoded periods are already interpreted by the URL parser.

  for i in url.utf8.path.lazy.percentDecoded().indices {
    if i.isDecodedOrUnsubstituted {
      if i.byte == ASCII.null.codePoint {
        return .failure(.encodedNullBytes)
      }
      if i.byte == ASCII.forwardSlash.codePoint {
        return .failure(.encodedPathSeparator)
      }
    } else {
      assert(i.byte != ASCII.null.codePoint, "Non-percent-encoded NULL byte in URL path")
    }
    filePath.append(i.byte)
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

  assert(!filePath.isEmpty)

  if nullTerminated {
    filePath.append(0)
  }
  return .success(filePath)
}

/// Creates a Windows path from a `file:` URL.
///
/// The result is a string of kind-of-opaque bytes, reflecting the bytes encoded in the URL.
/// It is more reasonable to assume that Windows paths will be UTF-8 encoded, although that may not always be the case.
/// The returned bytes are not null-terminated.
///
@usableFromInline
internal func _filePathFromURL_windows(
  _ url: WebURL, nullTerminated: Bool
) -> Result<ContiguousArray<UInt8>, FilePathFromURLError> {

  guard case .file = url.schemeKind else {
    return .failure(.notAFileURL)
  }

  let isUNC = (url.utf8.hostname!.isEmpty == false)
  var urlPath = url.utf8.path
  precondition(urlPath.first == ASCII.forwardSlash.codePoint, "URL has invalid path")

  if !isUNC {
    // For DOS-style paths, the first component must be a drive letter and be followed by another component.
    // (e.g. "/C:/" is okay, "/C:" is not). Furthermore, we allow the drive letter to be percent-encoded.

    let drive = url.utf8.pathComponent(url.pathComponents.startIndex)
    let decodedDrive = drive.lazy.percentDecoded()
    guard PathComponentParser.isNormalizedWindowsDriveLetter(decodedDrive), drive.endIndex < urlPath.endIndex else {
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

  for i in urlPath.lazy.percentDecoded().indices {
    if i.isDecodedOrUnsubstituted {
      if i.byte == ASCII.null.codePoint {
        return .failure(.encodedNullBytes)
      }
      if isWindowsFilePathSeparator(i.byte) {
        return .failure(.encodedPathSeparator)
      }
    }
    filePath.append(i.byte)
  }

  assert(!filePath.isEmpty)
  assert((filePath.first == ASCII.forwardSlash.codePoint) == isUNC)

  // Normalization.
  // At this point, we should only be using forward slashes since the path came from the URL,
  // so collapse them and replace with back slashes.
  // Note: Do not trim path segments because we don't know if this represents a 'verbatim' path.

  assert(!filePath.contains(ASCII.backslash.codePoint))

  filePath.collapseForwardSlashes(from: 0)
  for i in 0..<filePath.count {
    if filePath[i] == ASCII.forwardSlash.codePoint {
      filePath[i] = ASCII.backslash.codePoint
    }
  }

  assert(!filePath.isEmpty)
  assert((filePath.first == ASCII.backslash.codePoint) == isUNC)

  // Prepend the UNC server name.

  prependHostname: if isUNC {
    let hostname = url.utf8.hostname!
    assert(!hostname.contains(ASCII.percentSign.codePoint), "file URL hostnames cannot contain percent-encoding")

    // Do not create local device paths from file URLs.
    if hostname.elementsEqual(CollectionOfOne(ASCII.period.codePoint)) {
      return .failure(.unsupportedHostname)
    }
    // IPv6 hostnames must be transcribed for UNC:
    // https://en.wikipedia.org/wiki/IPv6_address#Literal_IPv6_addresses_in_UNC_path_names
    if hostname.first == ASCII.leftSquareBracket.codePoint {
      assert(hostname.last == ASCII.rightSquareBracket.codePoint, "Invalid hostname")
      assert(IPv6Address(utf8: hostname.dropFirst().dropLast()) != nil, "Invalid IPv6 hostname")

      var transcribedHostAndPrefix = ContiguousArray(#"\\"#.utf8)
      transcribedHostAndPrefix += hostname.dropFirst().dropLast().lazy.map { codePoint in
        codePoint == ASCII.colon.codePoint ? ASCII.minus.codePoint : codePoint
      }
      transcribedHostAndPrefix += ".ipv6-literal.net".utf8
      filePath.insert(contentsOf: transcribedHostAndPrefix, at: 0)
      break prependHostname
    }
    // Hostname is a domain or IPv4 address. Can be added as-is.
    filePath.insert(contentsOf: hostname, at: 0)
    filePath.insert(contentsOf: #"\\"#.utf8, at: 0)
  }

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
    storage: URLStorage(
      count: 8,
      structure: URLStructure(
        schemeLength: 5, usernameLength: 0, passwordLength: 0, hostnameLength: 0,
        portLength: 0, pathLength: 1, queryLength: 0, fragmentLength: 0, firstPathComponentLength: 1,
        sigil: .authority, schemeKind: .file, hostKind: .empty, hasOpaquePath: false, queryIsKnownFormEncoded: true),
      initializingCodeUnitsWith: { buffer in
        ("file:///" as StaticString).withUTF8Buffer { buffer.fastInitialize(from: $0) }
      }
    )
  )
}

/// A percent-encode set for Windows DOS-style path components, as well as UNC share names and UNC path components.
///
/// This set encodes ASCII codepoints which may occur in the Windows path components, but have special meaning in a URL string.
/// The set does not include the 'path' encode-set, as some codepoints must stay in their original form for trimming (e.g. spaces, periods).
///
/// Note that the colon character (`:`) is also included, so this encode-set is not appropriate for Windows drive letter components.
/// Drive letters should not be percent-encoded.
///
@usableFromInline
internal struct WindowsPathEncodeSet: PercentEncodeSet {

  @inlinable
  internal init() {}

  // swift-format-ignore
  @inlinable
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    // Encode:
    // - The `%` sign itself. Filesystem paths do not contain percent-encoding, and any character sequences which
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
internal struct POSIXPathEncodeSet: PercentEncodeSet {

  @inlinable
  internal init() {}

  // swift-format-ignore
  @inlinable
  internal func shouldPercentEncode(ascii codePoint: UInt8) -> Bool {
    // Encode:
    // - The '%' sign itself. Filesystem paths do not contain percent-encoding, and any character sequences which
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
    || URLEncodeSet.Path().shouldPercentEncode(ascii: codePoint)
  }
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
      while let separatorIndex = self[componentStart...].fastFirstIndex(where: isSeparator) {
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
