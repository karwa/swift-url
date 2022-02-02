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

import WebURLTestSupport
import XCTest

@testable import WebURL

final class FilePathTests: ReportGeneratingTestCase {}

extension FilePathTests {

  func testFilePathToURL() throws {
    let testFile = try loadTestFile(.FilePathTests, as: FilePathTestFile.self)
    var harness = FilePathToURLTests.WebURLReportHarness()
    harness.runTests(testFile.file_path_to_url)
    XCTAssert(harness.entriesSeen > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "file_path_to_url.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }

  func testURLToFilePath() throws {
    let testFile = try loadTestFile(.FilePathTests, as: FilePathTestFile.self)
    var harness = URLToFilePathTests.WebURLReportHarness()
    harness.runTests(testFile.url_to_file_path)
    XCTAssert(harness.entriesSeen > 0, "Failed to execute any tests")
    XCTAssertFalse(harness.report.hasUnexpectedResults, "Test failed")

    let reportURL = fileURLForReport(named: "url_to_file_path.txt")
    try harness.report.generateReport().write(to: reportURL, atomically: false, encoding: .utf8)
    print("ℹ️ Report written to \(reportURL)")
  }
}

extension FilePathTests {

  func testEmptyFileURLIsValidURL() {
    XCTAssertEqual(_emptyFileURL.serialized(), "file:///")
    XCTAssertURLIsIdempotent(_emptyFileURL)
  }

  func testFileURLsMayNotHavePortNumbers() {
    // This test keeps track of whether the URL standard allows port numbers in file URL hosts.
    // If it ever changes, we'll need to update our url-to-file-path function to add them to UNC paths.

    // Cannot parse a file URL with a port.
    XCTAssertNil(WebURL("file://example:99/foo/bar"))

    // Cannot set a port on a file URL.
    guard var fileURL = WebURL("file://example/foo/bar") else {
      XCTFail()
      return
    }
    XCTAssertEqual(fileURL.serialized(), "file://example/foo/bar")
    XCTAssertURLIsIdempotent(fileURL)
    XCTAssertThrowsSpecific(URLSetterError.cannotHaveCredentialsOrPort) {
      try fileURL.setPort(99)
    }
  }

  func testByteStringPath_posix() throws {

    // The only parts of a POSIX path we should be interpreting are the byte values: 0x00, 0x2F, and 0x2E.
    //
    // Those are included in the JSON tests, but we can't easily include byte sequences
    // from other encodings that are not valid UTF-8 in those tests. So they are tested here.

    // NULL bytes are part of the JSON tests, and `String(decoding: ..., as: UTF8.self)` does appear to allow
    // and preserve NULL bytes, but I'm not totally sure if I trust it. So some Array tests are included here, too.

    // Null-terminated.
    do {
      let nullTerminated: [UInt8] = [
        0x2F /* / */, 0x68 /* h */, 0x69 /* i */,
        0x00,
      ]
      XCTAssertEqual(String(cString: nullTerminated.map { CChar(bitPattern: $0) }), "/hi")

      XCTAssertThrowsSpecific(URLFromFilePathError.nullBytes) {
        let _ = try WebURL.fromBinaryFilePath(nullTerminated, format: .posix)
      }
    }

    // Nulls elsewhere.
    do {
      let includesNulls: [UInt8] = [
        0x2F /* / */, 0x68 /* h */, 0x69 /* i */,
        0x00,
        0x68 /* h */, 0x69 /* i */,
      ]
      XCTAssertEqual(String(cString: includesNulls.map { CChar(bitPattern: $0) }), "/hi")

      XCTAssertThrowsSpecific(URLFromFilePathError.nullBytes) {
        let _ = try WebURL.fromBinaryFilePath(includesNulls, format: .posix)
      }
    }

    // Unpaired surrogate.
    do {
      let unpairedSurrogate: [UInt8] = [
        0x2F /* / */, 0x66 /* f */, 0x6F /* o */, 0xED, 0xA0, 0x80, 0x6F /* o */,
        0x2F /* / */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
      ]
      XCTAssertEqual(String(decoding: unpairedSurrogate, as: UTF8.self), #"/fo���o/bar"#)

      let fileURL = try WebURL.fromBinaryFilePath(unpairedSurrogate, format: .posix)

      XCTAssertEqual(fileURL.serialized(), #"file:///fo%ED%A0%80o/bar"#)
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .posix, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, unpairedSurrogate)
    }

    // ISO/IEC 8859-1 (Latin-1).
    do {
      let latin1: [UInt8] = [
        0x2F /* / */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
      ]
      XCTAssertEqual(String(decoding: latin1, as: UTF8.self), "/caf��")

      let fileURL = try WebURL.fromBinaryFilePath(latin1, format: .posix)

      XCTAssertEqual(fileURL.serialized(), "file:///caf%E9%DD")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.count, 1)

      XCTAssertEqual(fileURL.pathComponents[raw: fileURL.pathComponents.startIndex], "caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.first, "caf��")

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .posix, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, latin1)
    }

    // ISO/IEC 8859-7 (Latin/Greek).
    do {
      let greek: [UInt8] = [
        0x2F /* / */, 0x68 /* h */, 0x69 /* i */, 0xE1 /* α */, 0xE2 /* β */, 0xE3 /* γ */,
      ]
      XCTAssertEqual(String(decoding: greek, as: UTF8.self), "/hi���")

      let fileURL = try WebURL.fromBinaryFilePath(greek, format: .posix)

      XCTAssertEqual(fileURL.serialized(), "file:///hi%E1%E2%E3")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.count, 1)

      XCTAssertEqual(fileURL.pathComponents[raw: fileURL.pathComponents.startIndex], "hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.first, "hi���")

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .posix, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, greek)
    }

    // All 8-bit values.
    do {
      var allBytes = Array(#"/foo/bar"#.utf8)
      allBytes.insert(contentsOf: 1...UInt8.max, at: 3)  // NULL bytes not allowed.
      XCTAssert(String(decoding: allBytes, as: UTF8.self).contains("�"))

      let fileURL = try WebURL.fromBinaryFilePath(allBytes, format: .posix)

      XCTAssertEqual(
        fileURL.serialized(),
        #"file:///fo%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"#
          + #"%20!%22%23$%25&'()*+,-./0123456789%3A;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[%5C]^_%60abcdefghijklm"#
          + #"nopqrstuvwxyz%7B%7C%7D~%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97"#
          + #"%98%99%9A%9B%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8"#
          + #"%B9%BA%BB%BC%BD%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9"#
          + #"%DA%DB%DC%DD%DE%DF%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA"#
          + #"%FB%FC%FD%FE%FFo/bar"#
      )
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(
        fileURL,
        scheme: "file",
        hostname: "",
        path: #"/fo%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"#
          + #"%20!%22%23$%25&'()*+,-./0123456789%3A;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[%5C]^_%60abcdefghijklm"#
          + #"nopqrstuvwxyz%7B%7C%7D~%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97"#
          + #"%98%99%9A%9B%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8"#
          + #"%B9%BA%BB%BC%BD%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9"#
          + #"%DA%DB%DC%DD%DE%DF%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA"#
          + #"%FB%FC%FD%FE%FFo/bar"#
      )
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .posix, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, allBytes)
    }
  }

  func testByteStringPath_windows() throws {

    // Since Windows paths are natively Unicode, we interpret a few more byte values than is perhaps strictly
    // necessary (in particular, 0x20 as a space), but all within the ASCII range.
    //
    // ASCII values are included in the JSON tests, but we can't easily include byte sequences
    // from other encodings that are not valid UTF-8 in those tests. So they are tested here.

    // NULL bytes are part of the JSON tests, and `String(decoding: ..., as: UTF8.self)` does appear to allow
    // and preserve NULL bytes, but I'm not totally sure if I trust it. So some Array tests are included here, too.

    // Null-terminated.
    do {
      let nullTerminated: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x00,
      ]
      XCTAssertEqual(String(cString: nullTerminated.map { CChar(bitPattern: $0) }), #"C:\hi"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.nullBytes) {
        let _ = try WebURL.fromBinaryFilePath(nullTerminated, format: .windows)
      }
    }

    // Nulls elsewhere.
    do {
      let includesNulls: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x00,
        0x68 /* h */, 0x69 /* i */,
      ]
      XCTAssertEqual(String(cString: includesNulls.map { CChar(bitPattern: $0) }), #"C:\hi"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.nullBytes) {
        let _ = try WebURL.fromBinaryFilePath(includesNulls, format: .windows)
      }
    }

    // Unpaired surrogate.
    do {
      let unpairedSurrogate: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x66 /* f */, 0x6F /* o */, 0xED, 0xA0, 0x80, 0x6F /* o */,
        0x5C /* \ */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
      ]
      XCTAssertEqual(String(decoding: unpairedSurrogate, as: UTF8.self), #"C:\fo���o\bar"#)

      let fileURL = try WebURL.fromBinaryFilePath(unpairedSurrogate, format: .windows)

      XCTAssertEqual(fileURL.serialized(), #"file:///C:/fo%ED%A0%80o/bar"#)
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, unpairedSurrogate)
    }

    // ISO/IEC 8859-1 (Latin-1).
    do {
      let latin1: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
      ]
      XCTAssertEqual(String(decoding: latin1, as: UTF8.self), #"C:\caf��"#)

      let fileURL = try WebURL.fromBinaryFilePath(latin1, format: .windows)

      XCTAssertEqual(fileURL.serialized(), "file:///C:/caf%E9%DD")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      XCTAssertEqual(fileURL.pathComponents[raw: fileURL.pathComponents.indices.last!], "caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.last, "caf��")

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, latin1)
    }

    // ISO/IEC 8859-7 (Latin/Greek).
    do {
      let greek: [UInt8] = [
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */, 0xE1 /* α */, 0xE2 /* β */, 0xE3 /* γ */,
      ]
      XCTAssertEqual(String(decoding: greek, as: UTF8.self), #"C:\hi���"#)

      let fileURL = try WebURL.fromBinaryFilePath(greek, format: .windows)

      XCTAssertEqual(fileURL.serialized(), "file:///C:/hi%E1%E2%E3")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      XCTAssertEqual(fileURL.pathComponents[raw: fileURL.pathComponents.indices.last!], "hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.last, "hi���")

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, greek)
    }

    // All 8-bit values.
    do {
      var allBytes = Array(#"C:\foo\bar"#.utf8)
      allBytes.insert(contentsOf: 1...UInt8.max, at: 5)  // NULL bytes not allowed.
      XCTAssert(String(decoding: allBytes, as: UTF8.self).contains("�"))

      let fileURL = try WebURL.fromBinaryFilePath(allBytes, format: .windows)

      XCTAssertEqual(
        fileURL.serialized(),
        #"file:///C:/fo%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"#
          //      Dot at end of component is trimmed                Backslash turned to forward slash in URL
          //                        V                                                    V
          + #"%20!%22%23$%25&'()*+,-/0123456789%3A;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[/]^_%60abcdefghijklmnopqrstu"#
          + #"vwxyz%7B%7C%7D~%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B"#
          + #"%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD"#
          + #"%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF"#
          + #"%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FFo/bar"#
      )
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(
        fileURL,
        scheme: "file",
        hostname: "",
        path: #"/C:/fo%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"#
          + #"%20!%22%23$%25&'()*+,-/0123456789%3A;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[/]^_%60abcdefghijklmnopqrstu"#
          + #"vwxyz%7B%7C%7D~%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B"#
          + #"%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD"#
          + #"%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF"#
          + #"%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FFo/bar"#
      )
      XCTAssertEqual(fileURL.pathComponents.count, 5)

      // Unfortunately, this does not precisely round-trip due to trimming and Windows having 2 path separators,
      // but if we reverse those transformations, the round-trip result should then be the same as the original.

      var roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      roundtripPath.insert(0x2E, at: 5 + 0x2E - 1)  // re-insert the trimmed '.'
      roundtripPath[5 + 0x2F - 1] = 0x2F  // URL paths have forward slashes, are turned to backslashes in path.
      XCTAssertEqualElements(roundtripPath, allBytes)
    }

    // Latin-1 in UNC server name.
    do {
      let latin1: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x5C /* \ */, 0x62 /* b */, 0x79 /* y */, 0x65 /* e */,
        0x5C /* \ */,
      ]
      XCTAssertEqual(String(decoding: latin1, as: UTF8.self), #"\\caf��\hi\bye\"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.invalidHostname) {
        let _ = try WebURL.fromBinaryFilePath(latin1, format: .windows)
      }
    }

    // Unpaired surrogate in server name.
    do {
      let unpairedSurrogate: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0xED, 0xA0, 0x80,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x5C /* \ */, 0x62 /* b */, 0x79 /* y */, 0x65 /* e */,
        0x5C /* \ */,
      ]
      XCTAssertEqual(String(decoding: unpairedSurrogate, as: UTF8.self), #"\\ca���\hi\bye\"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.invalidHostname) {
        let _ = try WebURL.fromBinaryFilePath(unpairedSurrogate, format: .windows)
      }
    }

    // Currently, all Unicode (including valid Unicode) is banned from UNC server names because we don't have IDNA.
    do {
      let unicode = #"\\🦆\share\bread\"#
      XCTAssertThrowsSpecific(URLFromFilePathError.invalidHostname) {
        let _ = try WebURL.fromBinaryFilePath(unicode.utf8, format: .windows)
      }
    }
  }

  func testByteStringPath_windows_win32Namespaced() throws {

    // As above, but using the "\\?\" long-path syntax.

    // Null-terminated.
    do {
      let nullTerminated: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */, 0x5C /* \ */,
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x00,
      ]
      XCTAssertEqual(String(cString: nullTerminated.map { CChar(bitPattern: $0) }), #"\\?\C:\hi"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.nullBytes) {
        let _ = try WebURL.fromBinaryFilePath(nullTerminated, format: .windows)
      }
    }

    // Nulls elsewhere.
    do {
      let includesNulls: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */, 0x5C /* \ */,
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x00,
        0x68 /* h */, 0x69 /* i */,
      ]
      XCTAssertEqual(String(cString: includesNulls.map { CChar(bitPattern: $0) }), #"\\?\C:\hi"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.nullBytes) {
        let _ = try WebURL.fromBinaryFilePath(includesNulls, format: .windows)
      }
    }

    // Unpaired surrogate.
    do {
      let unpairedSurrogate: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */, 0x5C /* \ */,
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x66 /* f */, 0x6F /* o */, 0xED, 0xA0, 0x80, 0x6F /* o */,
        0x5C /* \ */, 0x62 /* b */, 0x61 /* a */, 0x72 /* r */,
      ]
      XCTAssertEqual(String(decoding: unpairedSurrogate, as: UTF8.self), #"\\?\C:\fo���o\bar"#)

      let fileURL = try WebURL.fromBinaryFilePath(unpairedSurrogate, format: .windows)

      XCTAssertEqual(fileURL.serialized(), #"file:///C:/fo%ED%A0%80o/bar"#)
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/fo%ED%A0%80o/bar")
      XCTAssertEqual(fileURL.pathComponents.count, 3)

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, unpairedSurrogate.dropFirst(4) /* \\?\ prefix */)
    }

    // ISO/IEC 8859-1 (Latin-1).
    do {
      let latin1: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */, 0x5C /* \ */,
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
      ]
      XCTAssertEqual(String(decoding: latin1, as: UTF8.self), #"\\?\C:\caf��"#)

      let fileURL = try WebURL.fromBinaryFilePath(latin1, format: .windows)

      XCTAssertEqual(fileURL.serialized(), "file:///C:/caf%E9%DD")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      XCTAssertEqual(fileURL.pathComponents[raw: fileURL.pathComponents.indices.last!], "caf%E9%DD")
      XCTAssertEqual(fileURL.pathComponents.last, "caf��")

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, latin1.dropFirst(4) /* \\?\ prefix */)
    }

    // ISO/IEC 8859-7 (Latin/Greek).
    do {
      let greek: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */, 0x5C /* \ */,
        0x43 /* C */, 0x3A /* : */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */, 0xE1 /* α */, 0xE2 /* β */, 0xE3 /* γ */,
      ]
      XCTAssertEqual(String(decoding: greek, as: UTF8.self), #"\\?\C:\hi���"#)

      let fileURL = try WebURL.fromBinaryFilePath(greek, format: .windows)

      XCTAssertEqual(fileURL.serialized(), "file:///C:/hi%E1%E2%E3")
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(fileURL, scheme: "file", hostname: "", path: "/C:/hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.count, 2)

      XCTAssertEqual(fileURL.pathComponents[raw: fileURL.pathComponents.indices.last!], "hi%E1%E2%E3")
      XCTAssertEqual(fileURL.pathComponents.last, "hi���")

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, greek.dropFirst(4) /* \\?\ prefix */)
    }

    // All 8-bit values.
    do {
      var allBytes = Array(#"\\?\C:\foo\bar"#.utf8)
      allBytes.insert(contentsOf: [1...0x2E, 0x30...UInt8.max].joined(), at: 9)  // NULL and 0x2F not allowed.
      XCTAssert(String(decoding: allBytes, as: UTF8.self).contains("�"))

      let fileURL = try WebURL.fromBinaryFilePath(allBytes, format: .windows)

      XCTAssertEqual(
        fileURL.serialized(),
        #"file:///C:/fo%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"#
          //                                                        Backslash turned to forward slash in URL
          //                                                                             V
          + #"%20!%22%23$%25&'()*+,-.0123456789%3A;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[/]^_%60abcdefghijklmnopqrstu"#
          + #"vwxyz%7B%7C%7D~%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B"#
          + #"%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD"#
          + #"%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF"#
          + #"%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FFo/bar"#
      )
      XCTAssertURLIsIdempotent(fileURL)
      XCTAssertURLComponents(
        fileURL,
        scheme: "file",
        hostname: "",
        path: #"/C:/fo%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13%14%15%16%17%18%19%1A%1B%1C%1D%1E%1F"#
          + #"%20!%22%23$%25&'()*+,-.0123456789%3A;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[/]^_%60abcdefghijklmnopqrstu"#
          + #"vwxyz%7B%7C%7D~%7F%80%81%82%83%84%85%86%87%88%89%8A%8B%8C%8D%8E%8F%90%91%92%93%94%95%96%97%98%99%9A%9B"#
          + #"%9C%9D%9E%9F%A0%A1%A2%A3%A4%A5%A6%A7%A8%A9%AA%AB%AC%AD%AE%AF%B0%B1%B2%B3%B4%B5%B6%B7%B8%B9%BA%BB%BC%BD"#
          + #"%BE%BF%C0%C1%C2%C3%C4%C5%C6%C7%C8%C9%CA%CB%CC%CD%CE%CF%D0%D1%D2%D3%D4%D5%D6%D7%D8%D9%DA%DB%DC%DD%DE%DF"#
          + #"%E0%E1%E2%E3%E4%E5%E6%E7%E8%E9%EA%EB%EC%ED%EE%EF%F0%F1%F2%F3%F4%F5%F6%F7%F8%F9%FA%FB%FC%FD%FE%FFo/bar"#
      )
      XCTAssertEqual(fileURL.pathComponents.count, 4)

      // Unlike the non-Win32 namespaced variant, no trimming is performed and forward-slashes aren't allowed.
      // That means the path does actually round-trip! (I mean, besides the \\?\ prefix, which we can't preserve).

      let roundtripPath = try WebURL.binaryFilePath(from: fileURL, format: .windows, nullTerminated: false)
      XCTAssertEqualElements(roundtripPath, allBytes.dropFirst(4) /* \\?\ prefix */)
    }

    // Latin-1 in UNC server name.
    do {
      let latin1: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */,
        0x5C /* \ */, 0x55 /* U */, 0x4E /* N */, 0x43 /* C */,
        0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0x66 /* f */, 0xE9 /* é */, 0xDD /* Ý */,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x5C /* \ */, 0x62 /* b */, 0x79 /* y */, 0x65 /* e */,
        0x5C /* \ */,
      ]
      XCTAssertEqual(String(decoding: latin1, as: UTF8.self), #"\\?\UNC\caf��\hi\bye\"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.invalidHostname) {
        let _ = try WebURL.fromBinaryFilePath(latin1, format: .windows)
      }
    }

    // Unpaired surrogate in server name.
    do {
      let unpairedSurrogate: [UInt8] = [
        0x5C /* \ */, 0x5C /* \ */, 0x3F /* ? */,
        0x5C /* \ */, 0x55 /* U */, 0x4E /* N */, 0x43 /* C */,
        0x5C /* \ */, 0x63 /* c */, 0x61 /* a */, 0xED, 0xA0, 0x80,
        0x5C /* \ */, 0x68 /* h */, 0x69 /* i */,
        0x5C /* \ */, 0x62 /* b */, 0x79 /* y */, 0x65 /* e */,
        0x5C /* \ */,
      ]
      XCTAssertEqual(String(decoding: unpairedSurrogate, as: UTF8.self), #"\\?\UNC\ca���\hi\bye\"#)

      XCTAssertThrowsSpecific(URLFromFilePathError.invalidHostname) {
        let _ = try WebURL.fromBinaryFilePath(unpairedSurrogate, format: .windows)
      }
    }

    // Currently, all Unicode (including valid Unicode) is banned from UNC server names because we don't have IDNA.
    do {
      let unicode = #"\\?\UNC\🦆\share\bread\"#
      XCTAssertThrowsSpecific(URLFromFilePathError.invalidHostname) {
        let _ = try WebURL.fromBinaryFilePath(unicode.utf8, format: .windows)
      }
    }
  }
}
