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

import SystemPackage
import WebURL
import XCTest

@testable import WebURLSystemExtras

final class SystemFilePathTests: XCTestCase {}

#if os(Windows)

  extension SystemFilePathTests {

    func testASCII() throws {

      // Start with an ASCII file path.
      let filePath: FilePath = #"C:\foo\bar.txt"#
      filePath.withPlatformString {
        XCTAssertEqualElements(
          UnsafeBufferPointer(start: $0, count: filePath.length),
          [
            0x0043 /* C */, 0x003A /* : */,
            0x005C /* \ */, 0x0066 /* f */, 0x006F /* o */, 0x006F /* o */,
            0x005C /* \ */, 0x0062 /* b */, 0x0061 /* a */, 0x0072 /* r */,
            0x002E /* . */, 0x0074 /* t */, 0x0078 /* x */, 0x0074 /* t */,
          ]
        )
      }
      XCTAssertEqual(String(decoding: filePath), #"C:\foo\bar.txt"#)

      // Use WebURL.init(FilePath) to create a file URL.
      let fileURL = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL.serialized, "file:///C:/foo/bar.txt")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/foo/bar.txt")
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly.
      let filePath2 = try FilePath(url: fileURL)
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }

      // Use WebURL.init(FilePath) to create another file URL which should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath2)
      XCTAssertEqual(fileURL2.serialized, "file:///C:/foo/bar.txt")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/C:/foo/bar.txt")
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testUnicode() throws {

      // Start with a Unicode file path.
      let filePath: FilePath = #"C:\f🦆o\b🏆🏎r.💩"#
      filePath.withPlatformString {
        XCTAssertEqualElements(
          UnsafeBufferPointer(start: $0, count: filePath.length),
          [
            0x0043 /* C */, 0x003A /* : */,
            0x005C /* \ */, 0x0066 /* f */, 0xD83E, 0xDD86 /* 🦆 */, 0x006F /* o */,
            0x005C /* \ */, 0x0062 /* b */, 0xD83C, 0xDFC6 /* 🏆 */, 0xD83C, 0xDFCE /* 🏎 */, 0x0072 /* r */,
            0x002E /* . */, 0xD83D, 0xDCA9 /* 💩 */,
          ]
        )
      }
      XCTAssertEqual(String(decoding: filePath), #"C:\f🦆o\b🏆🏎r.💩"#)

      // Use WebURL.init(FilePath) to create a file URL. Should be transcoded to UTF-8.
      let fileURL = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL.serialized, "file:///C:/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(
        fileURL, scheme: "file", hostname: "", path: "/C:/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9"
      )
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly. Should be transcoded back to UTF-16.
      let filePath2 = try FilePath(url: fileURL)
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }

      // Use WebURL.init(FilePath) to create another file URL which should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath2)
      XCTAssertEqual(fileURL2.serialized, "file:///C:/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(
        fileURL2, scheme: "file", hostname: "", path: "/C:/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9"
      )
      XCTAssertEqual(fileURL2.pathComponents.count, 3)
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testUnpairedSurrogateInURL() throws {

      let unpairedSurrogate: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x66 /* f */, 0x6F /* o */, 0xED, 0xA0, 0x80, 0x6F /* o */,
        0x5C /* \ */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
      ]

      // Create a file URL from the raw bytes.
      let fileURL = try WebURL.fromFilePathBytes(unpairedSurrogate, format: .windows)
      XCTAssertEqual(fileURL.serialized, "file:///C:/fo%ED%A0%80o/bar")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      // TODO: It is questionable what we should do here. There are 3 possibile courses of action:
      //
      // 1. As usual, interpret the bytes as non-UTF-8 and fall back to the system's code-page.
      // 2. Recognize lone surrogates as being botched UTF-8, don't fall back to system code-page.
      //   2a. We could be strict and fail to transcode to UTF-16, or
      //   2b. We could be lenient and decode them anyway.

      // If the system's active code-page is UTF-8, we should fail in any case.
      XCTAssertThrowsSpecific(URLToFilePathError.transcodingFailure) {
        let _ = try PlatformStringConversions.simulatingActiveCodePage(65001) { try FilePath(url: fileURL) }
      }

      // Code page 437 = IBM extended ASCII. Every code-unit is defined.
      XCTAssertNoThrow {
        let _ = try PlatformStringConversions.simulatingActiveCodePage(437) { try FilePath(url: fileURL) }
      }
    }

    func testUnpairedSurrogateInFilePath() throws {

      let unpairedSurrogate: [UInt16] = [
        0x0043 /* C */, 0x003A /* : */,
        0x005C /* \ */, 0x0066 /* f */, 0x006F /* o */, 0x0D800, 0x006F /* o */,
        0x005C /* \ */, 0x0062 /* b */, 0x0061 /* a */, 0x0072 /* r */,
        0x0000,
      ]
      let filePath = FilePath(platformString: unpairedSurrogate)
      XCTAssertThrowsSpecific(FilePathToURLError.transcodingFailure) { let _ = try WebURL(filePath: filePath) }
    }

    func testFallbackCodePage_latin1() throws {

      let latin1: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
      ]

      // Create a file URL from the raw bytes.
      let fileURL = try WebURL.fromFilePathBytes(latin1, format: .windows)
      XCTAssertEqual(fileURL.serialized, "file:///C:/caf%E9%DD")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      // Use FilePath.init(WebURL) to reconstruct the file path.
      // Since the path is not valid UTF-8, it will be transcoded using the system's code-page.
      let filePath = try PlatformStringConversions.simulatingActiveCodePage(1252) { try FilePath(url: fileURL) }
      filePath.withPlatformString {
        XCTAssertEqualElements(
          UnsafeBufferPointer(start: $0, count: filePath.length),
          [0x0043, 0x003A, 0x005C, 0x0063, 0x0061, 0x0066, 0x00E9, 0x00DD]
        )
      }
      XCTAssertEqual(String(decoding: filePath), #"C:\caféÝ"#)

      // Transcoding failures will be caught.
      // 1255 = Hebrew, where the byte 0xDD is undefined.
      XCTAssertThrowsSpecific(URLToFilePathError.transcodingFailure) {
        let _ = try PlatformStringConversions.simulatingActiveCodePage(1255) { try FilePath(url: fileURL) }
      }

      // Use WebURL.init(FilePath) to create a file URL.
      // Since the FilePath contents are UTF-16 (rather than the ANSI bytes we started with),
      // the contents should be transcoded to UTF-8.
      let fileURL2 = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL2.serialized, "file:///C:/caf%C3%A9%C3%9D")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/C:/caf%C3%A9%C3%9D")
      XCTAssertEqual(fileURL2.pathComponents.count, 2)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly.
      // Since the URL contents are now valid UTF-8, the system code-page shouldn't matter.
      let filePath2 = try PlatformStringConversions.simulatingActiveCodePage(1255) { try FilePath(url: fileURL2) }
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }
    }

    func testFallbackCodePage_greek() throws {

      let greek: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */, 0xE1 /* α */, 0xE2 /* β */, 0xE3 /* γ */,
      ]

      // Create a file URL from the raw bytes.
      let fileURL = try WebURL.fromFilePathBytes(greek, format: .windows)
      XCTAssertEqual(fileURL.serialized, "file:///C:/hi%E1%E2%E3")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      // Use FilePath.init(WebURL) to reconstruct the file path.
      // Since the path is not valid UTF-8, it will be transcoded using the system's code-page.
      let filePath = try PlatformStringConversions.simulatingActiveCodePage(1253) { try FilePath(url: fileURL) }
      filePath.withPlatformString {
        XCTAssertEqualElements(
          UnsafeBufferPointer(start: $0, count: filePath.length),
          [0x0043, 0x003A, 0x005C, 0x0068, 0x0069, 0x03B1, 0x03B2, 0x03B3]
        )
      }
      XCTAssertEqual(String(decoding: filePath), #"C:\hiαβγ"#)

      // Transcoding failures will be caught.
      // 932 = Windows-31J, where the bytes 0xE? denote the start of a multi-byte sequence,
      // meaning the sequence [0xE1, 0xE2] is nonsense.
      XCTAssertThrowsSpecific(URLToFilePathError.transcodingFailure) {
        let _ = try PlatformStringConversions.simulatingActiveCodePage(932) { try FilePath(url: fileURL) }
      }

      // Use WebURL.init(FilePath) to create a file URL.
      // Since the FilePath contents are UTF-16 (rather than the ANSI bytes we started with),
      // the contents should be transcoded to UTF-8.
      let fileURL2 = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL2.serialized, "file:///C:/hi%CE%B1%CE%B2%CE%B3")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/C:/hi%CE%B1%CE%B2%CE%B3")
      XCTAssertEqual(fileURL2.pathComponents.count, 2)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly.
      // Since the URL contents are now valid UTF-8, the system code-page shouldn't matter.
      let filePath2 = try PlatformStringConversions.simulatingActiveCodePage(932) { try FilePath(url: fileURL2) }
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }
    }

    /// Make sure we agree with FilePath about which paths are absolute vs. relative.
    func testRelativePaths() {

      let relativePaths: [FilePath] = [
        #"C:"#,
        #"C:foo"#,
        #"foo"#,
        #"\foo"#,
        #"/foo"#,
      ]
      for path in relativePaths {
        XCTAssertTrue(path.isRelative)
        XCTAssertFalse(path.isAbsolute)
        XCTAssertThrowsSpecific(FilePathToURLError.relativePath) {
          let _ = try WebURL(filePath: path)
        }
      }

      let absolutePaths: [FilePath] = [
        #"C:\"#,
        #"C:/"#,
        #"C:\foo"#,
        #"C:/foo"#,
        #"\\server\"#,
        #"//server"#,
        #"\\server\share"#,
        #"//server/share/foo"#,
        #"\\?\C:\foo"#,
        #"\\?\UNC\server\share\foo"#,
      ]
      for path in absolutePaths {
        XCTAssertFalse(path.isRelative)
        XCTAssertTrue(path.isAbsolute)
        XCTAssertNoThrow { let _ = try WebURL(filePath: path) }
      }
    }
  }

#else

  extension SystemFilePathTests {

    func testASCII() throws {

      // Start with an ASCII file path.
      let filePath: FilePath = "/tmp/foo/bar.txt"
      filePath.withPlatformString {
        XCTAssertEqualElements(
          UnsafeBufferPointer(start: $0, count: filePath.length),
          [
            0x2F /* / */, 0x74 /* t */, 0x6D /* m */, 0x70 /* p */,
            0x2F /* / */, 0x66 /* f */, 0x6F /* o */, 0x6F /* o */,
            0x2F /* / */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
            0x2E /* . */, 0x74 /* t */, 0x78 /* x */, 0x74 /* t */,
          ]
        )
      }
      XCTAssertEqual(String(decoding: filePath), "/tmp/foo/bar.txt")

      // Use WebURL.init(FilePath) to create a file URL.
      let fileURL = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL.serialized, "file:///tmp/foo/bar.txt")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/tmp/foo/bar.txt")
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly.
      let filePath2 = try FilePath(url: fileURL)
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }

      // Use WebURL.init(FilePath) to create another file URL which should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath2)
      XCTAssertEqual(fileURL2.serialized, "file:///tmp/foo/bar.txt")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/tmp/foo/bar.txt")
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testUnicode() throws {

      // Start with a Unicode file path.
      let filePath: FilePath = "/tmp/f🦆o/b🏆🏎r.💩"
      filePath.withPlatformString {
        // swift-format-ignore
        XCTAssertEqualElements(
          UnsafeBufferPointer(start: $0, count: filePath.length),
          [
            0x2F /* / */, 0x74 /* t */, 0x6D /* m */, 0x70 /* p */,
            0x2F /* / */, 0x66 /* f */, 0xF0, 0x9F, 0xA6, 0x86 /* 🦆 */, 0x6F /* o */,
            0x2F /* / */, 0x62 /* b */, 0xF0, 0x9F, 0x8F, 0x86 /* 🏆 */, 0xF0, 0x9F, 0x8F, 0x8E /* 🏎 */, 0x72 /* r */,
            0x2E /* . */, 0xF0, 0x9F, 0x92, 0xA9 /* 💩 */,
          ].map { CChar(bitPattern: $0) }
        )
      }
      XCTAssertEqual(String(decoding: filePath), "/tmp/f🦆o/b🏆🏎r.💩")

      // Use WebURL.init(FilePath) to create a file URL.
      let fileURL = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL.serialized, "file:///tmp/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(
        fileURL, scheme: "file", hostname: "", path: "/tmp/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9"
      )
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly.
      let filePath2 = try FilePath(url: fileURL)
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }

      // Use WebURL.init(FilePath) to create another file URL which should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath2)
      XCTAssertEqual(fileURL2.serialized, "file:///tmp/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(
        fileURL2, scheme: "file", hostname: "", path: "/tmp/f%F0%9F%A6%86o/b%F0%9F%8F%86%F0%9F%8F%8Er.%F0%9F%92%A9"
      )
      XCTAssertEqual(fileURL2.pathComponents.count, 3)
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testUnpairedSurrogateInURL() throws {

      let unpairedSurrogate: [UInt8] = [
        0x2F /* / */, 0x66 /* f */, 0x6F /* o */, 0xED, 0xA0, 0x80, 0x6F /* o */,
        0x2F /* / */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
      ]

      // Create a file URL from the raw bytes. No UTF-8 validation is performed.
      let fileURL = try WebURL.fromFilePathBytes(unpairedSurrogate, format: .posix)
      XCTAssertEqual(fileURL.serialized, "file:///fo%ED%A0%80o/bar")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      // Create a file path from the URL. Should preserve the bytes exactly.
      let filePath = try FilePath(url: fileURL)
      filePath.withPlatformString {
        UnsafeBufferPointer(start: $0, count: filePath.length).withMemoryRebound(to: UInt8.self) { filePathChars in
          XCTAssertEqualElements(filePathChars, unpairedSurrogate)
        }
      }

      // Create another file URL from the path. Should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL2.serialized, "file:///fo%ED%A0%80o/bar")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testUnpairedSurrogateInFilePath() throws {

      let unpairedSurrogate: [CChar] = [
        0x2F /* / */, 0x66 /* f */, 0x6F /* o */, 0xED, 0xA0, 0x80, 0x6F /* o */,
        0x2F /* / */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
        0x00 as UInt8,
      ].map { CChar(bitPattern: $0) }

      // Start with a file path containing a UTF-8-encoded unpaired surrogate.
      let filePath = FilePath(platformString: unpairedSurrogate)

      // Use WebURL.init(FilePath) to create a file URL.
      let fileURL = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL.serialized, "file:///fo%ED%A0%80o/bar")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      // Use FilePath.init(WebURL) to reconstruct the file path exactly.
      let filePath2 = try FilePath(url: fileURL)
      filePath.withPlatformString {
        let filePath1Chars = UnsafeBufferPointer(start: $0, count: filePath.length)
        filePath2.withPlatformString {
          let filePath2Chars = UnsafeBufferPointer(start: $0, count: filePath2.length)
          XCTAssertEqualElements(filePath1Chars, filePath2Chars)
        }
      }

      // Create another file URL from the path. Should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL2.serialized, "file:///fo%ED%A0%80o/bar")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testLatin1() throws {

      let latin1: [UInt8] = [
        0x2F /* / */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
      ]
      XCTAssertEqual(String(decoding: latin1, as: UTF8.self), "/caf��")

      // Create a file URL from the raw bytes. No UTF-8 validation is performed.
      let fileURL = try WebURL.fromFilePathBytes(latin1, format: .posix)
      XCTAssertEqual(fileURL.serialized, "file:///caf%E9%DD")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.count, 1)

      // Create a file path from the URL. Should preserve the bytes exactly.
      let filePath = try FilePath(url: fileURL)
      filePath.withPlatformString {
        UnsafeBufferPointer(start: $0, count: filePath.length).withMemoryRebound(to: UInt8.self) { filePathChars in
          XCTAssertEqualElements(filePathChars, latin1)
        }
      }

      // Create another file URL from the path. Should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL2.serialized, "file:///caf%E9%DD")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/caf%E9%DD")
      XCTAssertEqual(fileURL, fileURL2)
    }

    func testGreek() throws {

      let greek: [UInt8] = [
        0x2F /* / */, 0x68 /* h */, 0x69 /* i */, 0xE1 /* α */, 0xE2 /* β */, 0xE3 /* γ */,
      ]
      XCTAssertEqual(String(decoding: greek, as: UTF8.self), "/hi���")

      // Create a file URL from the raw bytes. No UTF-8 validation is performed.
      let fileURL = try WebURL.fromFilePathBytes(greek, format: .posix)
      XCTAssertEqual(fileURL.serialized, "file:///hi%E1%E2%E3")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.count, 1)

      // Create a file path from the URL. Should preserve the bytes exactly.
      let filePath = try FilePath(url: fileURL)
      filePath.withPlatformString {
        UnsafeBufferPointer(start: $0, count: filePath.length).withMemoryRebound(to: UInt8.self) { filePathChars in
          XCTAssertEqualElements(filePathChars, greek)
        }
      }

      // Create another file URL from the path. Should exactly match the first one.
      let fileURL2 = try WebURL(filePath: filePath)
      XCTAssertEqual(fileURL2.serialized, "file:///hi%E1%E2%E3")
      XCTAssertURLIsIdempotent(fileURL2)
      XCTAssertURLComponents(fileURL2, scheme: "file", hostname: "", path: "/hi%E1%E2%E3")
      XCTAssertEqual(fileURL, fileURL2)
    }

    /// Make sure we agree with FilePath about which paths are absolute vs. relative.
    func testRelativePaths() {

      do {
        let path: FilePath = "foo"
        XCTAssertTrue(path.isRelative)
        XCTAssertFalse(path.isAbsolute)
        XCTAssertThrowsSpecific(FilePathToURLError.relativePath) {
          let _ = try WebURL(filePath: path)
        }
      }
      do {
        let path: FilePath = "/foo"
        XCTAssertFalse(path.isRelative)
        XCTAssertTrue(path.isAbsolute)
        XCTAssertNoThrow {
          let _ = try WebURL(filePath: path)
        }
      }
    }
  }

#endif
