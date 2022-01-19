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
// --------------------------------------------
// FilePath -> WebURL and WebURL -> FilePath conversions, for both SystemPackage and System.framework.
// This file is written in such a way that all implementations of 'swift-system' discoverable via canImport
// will be supported, and at least one must be present.
//
// Technically, this means that software targeting newer Darwin platforms could omit SystemPackage and rely on
// System.framework instead. That is difficult (perhaps impossible) to express with SwiftPM currently,
// and toolchain versions behave differently.
//
// For now, the 'WebURLSystemExtras' module depends on SystemPackage unconditionally.
// If that is a problem, commenting out the dependency in 'Package.swift' should allow you to depend only
// on System.framework, without any other changes to the library source.
// --------------------------------------------

import WebURL

// --------------------------------------------
// MARK: - SystemPackage interface
// --------------------------------------------


#if canImport(SystemPackage)
  import SystemPackage

  extension WebURL {

    /// Creates a `file:` URL representation of the given `FilePath`.
    ///
    /// The given path must be absolute and must not contain any components which traverse to their parent directories
    /// (`".."` components).
    ///
    /// Use the `FilePath.isAbsolute` property to check that the path is absolute, and resolve it against a base path
    /// if it is not. Use the `FilePath.lexicallyNormalize` or `.lexicallyResolving` methods to resolve any `".."`
    /// components.
    ///
    /// - parameters:
    ///   - filePath: The file path from which to create the file URL.
    ///
    /// - throws: `URLFromFilePathError`
    ///
    public init(filePath: SystemPackage.FilePath) throws {
      self = try filePath.withPlatformString { platformStr in
        try PlatformStringConversions.toMultiByte(UnsafeBufferPointer(start: platformStr, count: filePath.length + 1)) {
          guard let mbStr = $0 else { throw URLFromFilePathError.transcodingFailure }
          precondition(mbStr.last == 0, "Expected a null-terminated string")
          return try WebURL.fromBinaryFilePath(UnsafeBufferPointer(rebasing: mbStr.dropLast()), format: .native)
        }
      }
    }
  }

  extension SystemPackage.FilePath {

    /// Reconstructs a `FilePath` from its URL representation.
    ///
    /// The given URL must be a `file:` URL representation of an absolute path according to this system's path format.
    /// The resulting `FilePath` is both absolute and lexically normalized.
    ///
    /// On Windows, the reconstructed path is first interpreted as UTF-8.
    /// Should it not contain valid UTF-8, it will be interpreted using the system's active code-page
    /// and converted to its Unicode representation.
    ///
    /// - parameters:
    ///   - url: The file URL from which to reconstruct the file path.
    ///
    /// - throws: `FilePathFromURLError`
    ///
    public init(url: WebURL) throws {
      self = try WebURL.binaryFilePath(from: url, format: .native, nullTerminated: true).withUnsafeBufferPointer {
        try PlatformStringConversions.fromMultiByte($0) {
          guard let platformString = $0 else { throw FilePathFromURLError.transcodingFailure }
          return FilePath(platformString: platformString.baseAddress!)
        }
      }
    }
  }
#endif


// --------------------------------------------
// MARK: - System.framework interface
// --------------------------------------------


#if !os(iOS)  // FB9832953 - System.framework for iOS is broken in Xcode 13. Last tested: Xcode 13.2.1
  #if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS)) && canImport(System)
    import System

    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, *)
    extension WebURL {

      /// Creates a `file:` URL representation of the given `FilePath`.
      ///
      /// The given path must be absolute and must not contain any components which traverse to their parent directories
      /// (`".."` components).
      ///
      /// Use the `FilePath.isAbsolute` property to check that the path is absolute, and resolve it against a base path
      /// if it is not. Use the `FilePath.lexicallyNormalize` or `.lexicallyResolving` methods to resolve any `".."`
      /// components.
      ///
      /// - parameters:
      ///   - filePath: The file path from which to create the file URL.
      ///
      /// - throws: `URLFromFilePathError`
      ///
      public init(filePath: System.FilePath) throws {
        self = try filePath.withCString { cString in
          try PlatformStringConversions.toMultiByte(UnsafeBufferPointer(start: cString, count: filePath.length + 1)) {
            guard let mbStr = $0 else { throw URLFromFilePathError.transcodingFailure }
            precondition(mbStr.last == 0, "Expected a null-terminated string")
            return try WebURL.fromBinaryFilePath(UnsafeBufferPointer(rebasing: mbStr.dropLast()), format: .native)
          }
        }
      }
    }

    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, *)
    extension System.FilePath {

      /// Reconstructs a `FilePath` from its URL representation.
      ///
      /// The given URL must be a `file:` URL representation of an absolute path according to this system's path format.
      /// The resulting `FilePath` is both absolute and lexically normalized.
      ///
      /// On Windows, the reconstructed path is first interpreted as UTF-8.
      /// Should it not contain valid UTF-8, it will be interpreted using the system's active code-page
      /// and converted to its Unicode representation.
      ///
      /// - parameters:
      ///   - url: The file URL from which to reconstruct the file path.
      ///
      /// - throws: `FilePathFromURLError`
      ///
      public init(url: WebURL) throws {
        self = try WebURL.binaryFilePath(from: url, format: .native, nullTerminated: true).withUnsafeBufferPointer {
          try PlatformStringConversions.fromMultiByte($0) {
            guard let platformString = $0 else { throw FilePathFromURLError.transcodingFailure }
            return FilePath(cString: platformString.baseAddress!)
          }
        }
      }
    }
  #endif
#endif  // !os(iOS)


// --------------------------------------------
// MARK: - Platform string conversions
// --------------------------------------------


#if canImport(SystemPackage)
  import SystemPackage
  private typealias CInterop_PlatformChar = SystemPackage.CInterop.PlatformChar
#elseif os(iOS)  // FB9832953 - System.framework for iOS is broken in Xcode 13. Last tested: Xcode 13.2.1
  private typealias CInterop_PlatformChar = CChar
#elseif (os(macOS) || os(iOS) || os(tvOS) || os(watchOS)) && canImport(System)
  private typealias CInterop_PlatformChar = CChar
#endif

private protocol PlatformStringConversionsProtocol {

  /// Converts a null-terminated buffer of platform characters to a null-terminated buffer of bytes.
  ///
  /// If the platform string is known to contain textual code-points,
  /// the buffer passed to `body` will be encoded with UTF-8.
  ///
  static func toMultiByte<ResultType>(
    _ platformString: UnsafeBufferPointer<CInterop_PlatformChar>,
    _ body: (UnsafeBufferPointer<UInt8>?) throws -> ResultType
  ) rethrows -> ResultType

  /// Converts a null-terminated buffer of bytes to a null-terminated platform string.
  ///
  /// If the platform string requires its contents to be textual code-points,
  /// this function will attempt to infer the encoding of the bytes.
  ///
  static func fromMultiByte<ResultType>(
    _ mbString: UnsafeBufferPointer<UInt8>,
    _ body: (UnsafeBufferPointer<CInterop_PlatformChar>?) throws -> ResultType
  ) rethrows -> ResultType
}

#if os(Windows)

  import WinSDK

  // Windows paths.
  // --------------
  // - Platform string: Unicode codepoints (UTF-16/UCS-2).
  // - Multi-byte string: Depends.
  //                       - For `toMultiByte`, we choose UTF-8.
  //                       - For `fromMultiByte`, we expect UTF-8 but fall back to the system's code-page.
  //
  // This follows the principle of being strict when sending and lenient when receiving,
  // and matches the behavior of Chromium/Edge, so it should match the expectations of Windows users.
  // https://github.com/chromium/chromium/blob/7417fc2bd5c8cf0e6dbf7ca4b599603c67d3edf3/net/base/filename_util.cc#L138
  //
  // The Windows system routines are WideCharToMultiByte and MultiByteToWideChar.
  // The documentation for those functions includes the following note:
  //
  // > Starting with Windows Vista, this function fully conforms with the Unicode 4.1 specification
  // > for UTF-8 and UTF-16. The function used on earlier operating systems encodes or decodes lone surrogate halves
  // > or mismatched surrogate pairs. Code written in earlier versions of Windows that rely on this behavior to
  // > encode random non-text binary data might run into problems.
  //
  // https://web.archive.org/web/20210225215335if_/https://docs.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-multibytetowidechar#remarks
  //
  // Assuming this is accurate, the standard library's built-in routines should do just as good a job.
  // MultiByteToWideChar is still useful as a fallback for transcoding from a Windows code-page to UTF-16, however.
  //
  internal enum PlatformStringConversions: PlatformStringConversionsProtocol {

    fileprivate static func toMultiByte<ResultType>(
      _ plString: UnsafeBufferPointer<UInt16>,
      _ body: (UnsafeBufferPointer<UInt8>?) throws -> ResultType
    ) rethrows -> ResultType {

      precondition(plString.last == 0, "Expected a null-terminated string")

      var transcoded = ContiguousArray<UInt8>()
      transcoded.reserveCapacity(plString.count)
      let invalidUnicode = transcode(plString.makeIterator(), from: UTF16.self, to: UTF8.self, stoppingOnError: true) {
        codeUnit in transcoded.append(codeUnit)
      }
      guard !invalidUnicode else {
        return try body(nil)
      }
      precondition(transcoded.last == 0, "Expected the transcoded result to be null-terminated")
      return try transcoded.withUnsafeBufferPointer(body)
    }

    fileprivate static func fromMultiByte<ResultType>(
      _ mbString: UnsafeBufferPointer<UInt8>,
      _ body: (UnsafeBufferPointer<UInt16>?) throws -> ResultType
    ) rethrows -> ResultType {

      precondition(mbString.last == 0, "Expected a null-terminated string")

      var transcoded = ContiguousArray<UInt16>()
      transcoded.reserveCapacity(mbString.count)
      let invalidUnicode = transcode(mbString.makeIterator(), from: UTF8.self, to: UTF16.self, stoppingOnError: true) {
        codeUnit in transcoded.append(codeUnit)
      }
      if invalidUnicode {
        guard mbString.withMemoryRebound(to: CChar.self, { FallbackCPtoWide($0, &transcoded) }) else {
          return try body(nil)
        }
      }
      precondition(transcoded.last == 0, "Expected the transcoded result to be null-terminated")
      return try transcoded.withUnsafeBufferPointer(body)
    }

    /// Interprets `input` as a string in the fallback code-page and attempts to transcode it to UTF-16,
    /// storing the result in `output`.
    ///
    /// Note that `input` must be null-terminated, and the result will be null-terminated.
    /// `output` will have its contents replaced with the resulting string and will be resized as needed,
    /// reusing any previously-allocated capacity if possible.
    ///
    /// If transcoding fails, the contents of `output` are unspecified.
    ///
    /// - returns: `true` if transcoding was successful, otherwise `false`.
    ///
    private static func FallbackCPtoWide(
      _ input: UnsafeBufferPointer<CChar>,
      _ output: inout ContiguousArray<UInt16>
    ) -> Bool {

      precondition(input.last == 0, "Expected a null-terminated string")

      let codePage = Self.FallbackCodePage
      let requiredCapacity = MultiByteToWideChar(
        codePage, DWORD(bitPattern: MB_ERR_INVALID_CHARS),
        input.baseAddress, Int32(input.count), nil, 0
      )
      guard requiredCapacity > 0 else {
        return false
      }
      output.replaceSubrange(0..<output.count, with: repeatElement(0, count: Int(requiredCapacity)))
      let stringLength = output.withUnsafeMutableBufferPointer { buffer in
        // swift-format-ignore
        Int(MultiByteToWideChar(
          codePage, DWORD(bitPattern: MB_ERR_INVALID_CHARS),
          input.baseAddress, Int32(input.count), buffer.baseAddress, Int32(buffer.count)
        ))
      }
      guard stringLength == output.count else {
        return false
      }
      precondition(output.last == 0, "Expected the transcoded result to be null-terminated")
      return true
    }

    // Code-page testing.

    #if DEBUG
      private static var FallbackCodePage = UINT(bitPattern: CP_ACP)

      /// Makes platform-string conversions fall back to interpreting bytes using the given code-page,
      /// rather than the system's active code-page, for the duration of `body`.
      ///
      internal static func simulatingActiveCodePage<T>(
        _ newCodePage: UINT, _ body: () throws -> T
      ) rethrows -> T {

        let previousCodePage = FallbackCodePage
        FallbackCodePage = newCodePage
        defer {
          FallbackCodePage = previousCodePage
        }
        return try body()
      }
    #else
      private static let FallbackCodePage = UINT(bitPattern: CP_ACP)
    #endif
  }

#else

  // POSIX paths.
  // ------------
  // - Platform string: opaque bytes.
  // - Multi-byte string: opaque bytes.
  //
  // POSIX platform strings are natively multi-byte. We can't assume that they contain Unicode text,
  // so we couldn't transcode them even if we wanted to.
  //
  // Essentially this conversion, then, papers over signed/unsigned char from the platform string
  // and normalizes them as UInt8. Which is what the WebURL functions accept/return, because they treat
  // the string as semi-opaque octets and don't care about the sign of the numeric value.
  //
  private enum PlatformStringConversions: PlatformStringConversionsProtocol {

    fileprivate static func toMultiByte<ResultType>(
      _ platformString: UnsafeBufferPointer<CChar>,
      _ body: (UnsafeBufferPointer<UInt8>?) throws -> ResultType
    ) rethrows -> ResultType {

      precondition(platformString.last == 0, "Expected a null-terminated string")
      return try platformString.withMemoryRebound(to: UInt8.self, body)
    }

    fileprivate static func fromMultiByte<ResultType>(
      _ mbString: UnsafeBufferPointer<UInt8>,
      _ body: (UnsafeBufferPointer<CChar>?) throws -> ResultType
    ) rethrows -> ResultType {

      precondition(mbString.last == 0, "Expected a null-terminated string")
      return try mbString.withMemoryRebound(to: CChar.self, body)
    }
  }

#endif
