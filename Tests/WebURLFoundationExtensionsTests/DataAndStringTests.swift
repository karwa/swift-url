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

import Foundation
import WebURL
import XCTest

@testable import WebURLFoundationExtras

#if canImport(Swifter)
  import Swifter
#endif

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class DataAndStringTests: XCTestCase {}


// --------------------------------
// MARK: - Data
// --------------------------------


extension DataAndStringTests {

  func testData_contentsOfFileURL() throws {
    var rng = SystemRandomNumberGenerator()
    let bytes = (0..<10).map { _ in rng.next() as UInt8 }

    var nsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    try FileManager.default.createDirectory(at: nsURL, withIntermediateDirectories: true, attributes: nil)

    // Write via Foundation.URL.
    nsURL.appendPathComponent("weburl-\(#function)-tmp")
    try Data(bytes).write(to: nsURL)

    // Read back via WebURL.
    var webURL = try WebURL(filePath: NSTemporaryDirectory())
    webURL.pathComponents.append("weburl-\(#function)-tmp")
    XCTAssertEqual(try Data(contentsOf: webURL).elementsEqual(bytes), true)
  }

  #if canImport(Swifter)

    func testData_contentsOfHttpURL() throws {

      #if swift(<5.5) && !canImport(Darwin)
        // swift-corelibs-foundation loads the correct number of bytes, but they are all zero!
        // This happens on 5.3 and 5.4, but the same code works correctly on 5.5 and Darwin Foundation.
        throw XCTSkip("Data(contentsOf: URL) is broken")
      #endif

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      var rng = SystemRandomNumberGenerator()
      let bytes = (0..<10).map { _ in rng.next() as UInt8 }

      localServer["/files/test"] = { _ in .ok(.data(Data(bytes))) }

      let webURL = WebURL("http://localhost:\(port)/files/test")!
      let loadedBytes = try Data(contentsOf: webURL)
      XCTAssertEqual(loadedBytes.elementsEqual(bytes), true, "\(loadedBytes.count) -- \(Array(loadedBytes))")
    }

  #endif

  func testData_contentsOfConversionFailure() {

    let url = WebURL("http://loc{al}host/foo/bar")!
    XCTAssertEqual(url.serialized(), "http://loc{al}host/foo/bar")
    do {
      let _ = try Data(contentsOf: url)
      XCTFail("Expected an error to be thrown")
    } catch let error as WebURLToFoundationConversionError {
      XCTAssertEqual(error.url, url)
      XCTAssertEqual(error.message, nil)
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  func testData_writeToURL() throws {

    var rng = SystemRandomNumberGenerator()
    let bytes = (0..<10).map { _ in rng.next() as UInt8 }

    var nsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    try FileManager.default.createDirectory(at: nsURL, withIntermediateDirectories: true, attributes: nil)

    // Write via WebURL
    var webURL = try WebURL(filePath: NSTemporaryDirectory())
    webURL.pathComponents.append("weburl-\(#function)-tmp")
    try Data(bytes).write(to: webURL)

    // Read back via Foundation.URL.
    nsURL.appendPathComponent("weburl-\(#function)-tmp")
    XCTAssertEqual(try Data(contentsOf: nsURL).elementsEqual(bytes), true)
  }

  func testData_writeToURL_conversionFailure() throws {

    var rng = SystemRandomNumberGenerator()
    let bytes = (0..<10).map { _ in rng.next() as UInt8 }

    let url = WebURL("http://loc{al}host/foo/bar")!
    XCTAssertEqual(url.serialized(), "http://loc{al}host/foo/bar")
    do {
      try Data(bytes).write(to: url)
      XCTFail("Expected an error to be thrown")
    } catch let error as WebURLToFoundationConversionError {
      XCTAssertEqual(error.url, url)
      XCTAssertEqual(error.message, nil)
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }
}


// --------------------------------
// MARK: - String
// --------------------------------


extension DataAndStringTests {

  func testString_contentsOfFileURL() throws {
    let string = "hello, 🌍!"

    var nsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    try FileManager.default.createDirectory(at: nsURL, withIntermediateDirectories: true, attributes: nil)

    // Write via Foundation.URL.
    nsURL.appendPathComponent("weburl-\(#function)-tmp")
    try string.write(to: nsURL, atomically: false, encoding: .utf8)

    // Read back via WebURL.
    var webURL = try WebURL(filePath: NSTemporaryDirectory())
    webURL.pathComponents.append("weburl-\(#function)-tmp")
    XCTAssertEqual(try String(contentsOf: webURL), string)
  }

  func testString_contentsOfFileURLWithEncoding() throws {

    let bytes = Data([
      /* h */ 0x68, 0x00, 0x00, 0x00, /* e */ 0x65, 0x00, 0x00, 0x00, /* l */ 0x6C, 0x00, 0x00, 0x00,
      /* l */ 0x6C, 0x00, 0x00, 0x00, /* o */ 0x6F, 0x00, 0x00, 0x00, /* , */ 0x2C, 0x00, 0x00, 0x00,
      /*   */ 0x20, 0x00, 0x00, 0x00, /* 🌍 */ 0x0D, 0xF3, 0x01, 0x00, /* ! */ 0x21, 0x00, 0x00, 0x00,
    ])
    var nsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    try FileManager.default.createDirectory(at: nsURL, withIntermediateDirectories: true, attributes: nil)

    // Write via Foundation.URL.
    nsURL.appendPathComponent("weburl-\(#function)-tmp")
    try bytes.write(to: nsURL)

    // Read back via WebURL.
    var webURL = try WebURL(filePath: NSTemporaryDirectory())
    webURL.pathComponents.append("weburl-\(#function)-tmp")
    XCTAssertEqual(try String(contentsOf: webURL, encoding: .utf32LittleEndian), "hello, 🌍!")
  }

  // This doesn't work in swift-corelibs-foundation: https://github.com/apple/swift-corelibs-foundation/pull/3158
  #if canImport(Darwin)

    func testString_contentsOfFileURL_usedEncoding() throws {
      let string = "hello, 🌍!"

      var nsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      try FileManager.default.createDirectory(at: nsURL, withIntermediateDirectories: true, attributes: nil)

      // Write via Foundation.URL.
      nsURL.appendPathComponent("weburl-\(#function)-tmp")
      try string.write(to: nsURL, atomically: false, encoding: .utf32)

      // Read back via WebURL.
      var webURL = try WebURL(filePath: NSTemporaryDirectory())
      webURL.pathComponents.append("weburl-\(#function)-tmp")
      var encoding = String.Encoding.shiftJIS
      XCTAssertEqual(try String(contentsOf: webURL, usedEncoding: &encoding), string)
      #if canImport(Darwin)
        XCTAssertEqual(encoding, .utf32)
      #elseif _endian(little)
        XCTAssertEqual(encoding, .utf32LittleEndian)
      #else
        XCTAssertEqual(encoding, .utf32BigEndian)
      #endif
    }

  #endif

  #if canImport(Swifter)

    func testString_contentsOfHttpURL() throws {

      #if swift(<5.5) && !canImport(Darwin)
        // swift-corelibs-foundation loads an empty string on 5.3 and 5.4, but the same code
        // works correctly on 5.5 and Darwin Foundation.
        throw XCTSkip("String(contentsOf: URL) is broken")
      #endif

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      localServer["/files/test"] = { _ in .ok(.text("🦆 = 👑")) }

      let webURL = WebURL("http://localhost:\(port)/files/test")!
      XCTAssertEqual(try String(contentsOf: webURL), "🦆 = 👑")
    }

    func testString_contentsOfHttpURLWithEncoding() throws {

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      let bytes = Data([
        /* h */ 0x68, 0x00, 0x00, 0x00, /* e */ 0x65, 0x00, 0x00, 0x00, /* l */ 0x6C, 0x00, 0x00, 0x00,
        /* l */ 0x6C, 0x00, 0x00, 0x00, /* o */ 0x6F, 0x00, 0x00, 0x00, /* , */ 0x2C, 0x00, 0x00, 0x00,
        /*   */ 0x20, 0x00, 0x00, 0x00, /* 🌍 */ 0x0D, 0xF3, 0x01, 0x00, /* ! */ 0x21, 0x00, 0x00, 0x00,
      ])

      localServer["/files/test"] = { _ in .ok(.data(bytes)) }

      let webURL = WebURL("http://localhost:\(port)/files/test")!
      XCTAssertEqual(try String(contentsOf: webURL, encoding: .utf32LittleEndian), "hello, 🌍!")
    }

    func testString_contentsOfHttpURL_usedEncoding() throws {

      #if swift(<5.5) && !canImport(Darwin)
        // swift-corelibs-foundation loads an empty string on 5.3 and 5.4, but the same code
        // works correctly on 5.5 and Darwin Foundation.
        throw XCTSkip("String(contentsOf: URL, usedEncoding: inout Encoding) is broken")
      #endif

      let localServer = HttpServer()
      try localServer.start(0)
      defer { localServer.stop() }
      let port = try localServer.port()
      print("ℹ️ Server started on port: \(port)")

      localServer["/files/test"] = { _ in .ok(.text("🦆 = 👑")) }

      let webURL = WebURL("http://localhost:\(port)/files/test")!
      var encoding = String.Encoding.shiftJIS
      XCTAssertEqual(try String(contentsOf: webURL, usedEncoding: &encoding), "🦆 = 👑")
      XCTAssertEqual(encoding, .utf8)
    }

  #endif

  func testString_contentsOfConversionFailure() {

    let url = WebURL("http://loc{al}host/foo/bar")!
    XCTAssertEqual(url.serialized(), "http://loc{al}host/foo/bar")

    // String(contentsOf:)
    do {
      let _ = try String(contentsOf: url)
      XCTFail("Expected an error to be thrown")
    } catch let error as WebURLToFoundationConversionError {
      XCTAssertEqual(error.url, url)
      XCTAssertEqual(error.message, nil)
    } catch {
      XCTFail("Unexpected error \(error)")
    }

    // String(contentsOf:encoding:)
    do {
      let _ = try String(contentsOf: url, encoding: .utf8)
      XCTFail("Expected an error to be thrown")
    } catch let error as WebURLToFoundationConversionError {
      XCTAssertEqual(error.url, url)
      XCTAssertEqual(error.message, nil)
    } catch {
      XCTFail("Unexpected error \(error)")
    }

    // String(contentsOf:usedEncoding:)
    do {
      var encoding = String.Encoding.utf8
      let _ = try String(contentsOf: url, usedEncoding: &encoding)
      XCTFail("Expected an error to be thrown")
    } catch let error as WebURLToFoundationConversionError {
      XCTAssertEqual(error.url, url)
      XCTAssertEqual(error.message, nil)
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  func testString_writeToURL() throws {
    let string = "hello, 🌍!"

    var nsURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    try FileManager.default.createDirectory(at: nsURL, withIntermediateDirectories: true, attributes: nil)

    // Write via WebURL.
    var webURL = try WebURL(filePath: NSTemporaryDirectory())
    webURL.pathComponents.append("weburl-\(#function)-tmp")
    try string.write(to: webURL, atomically: false, encoding: .utf8)

    // Read back via Foundation.URL.
    nsURL.appendPathComponent("weburl-\(#function)-tmp")
    XCTAssertEqual(try String(contentsOf: nsURL), string)
  }

  func testString_writeToURL_conversionFailure() {

    let url = WebURL("http://loc{al}host/foo/bar")!
    XCTAssertEqual(url.serialized(), "http://loc{al}host/foo/bar")

    do {
      let _ = try "hello, 🌍!".write(to: url, atomically: false, encoding: .utf8)
      XCTFail("Expected an error to be thrown")
    } catch let error as WebURLToFoundationConversionError {
      XCTAssertEqual(error.url, url)
      XCTAssertEqual(error.message, nil)
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }
}
