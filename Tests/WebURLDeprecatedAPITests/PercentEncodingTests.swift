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

import XCTest

@testable import WebURL

@available(*, deprecated)
final class PercentEncodingTests_Deprecated: XCTestCase {

  func testEncodingWithKeyPath() {

    // From: LazyCollectionProtocol.percentEncoded(using:)
    do {
      // Encode arbitrary data as an ASCII string.
      let image = Data([0xBA, 0x74, 0x5F, 0xE0, 0x11, 0x22, 0xEB, 0x10, 0x2C, 0x7F])
      XCTAssert(
        image.lazy.percentEncoded(as: \.component)
          .elementsEqual("%BAt_%E0%11%22%EB%10%2C%7F".utf8)
      )

      // Encode-sets determine which characters are encoded, and some perform substitutions.
      let bytes = "hello, world!".utf8
      XCTAssert(
        bytes.lazy.percentEncoded(as: \.component)
          .elementsEqual("hello%2C%20world!".utf8)
      )
      XCTAssert(
        bytes.lazy.percentEncoded(as: \.form)
          .elementsEqual("hello%2C+world%21".utf8)
      )
    }

    // From: Collection.percentEncodedString(using:)
    do {
      // Encode arbitrary data as an ASCII string.
      let image = Data([0xBA, 0x74, 0x5F, 0xE0, 0x11, 0x22, 0xEB, 0x10, 0x2C, 0x7F])
      XCTAssertEqual(image.percentEncodedString(as: \.component), "%BAt_%E0%11%22%EB%10%2C%7F")

      // Encode-sets determine which characters are encoded, and some perform substitutions.
      let bytes = "hello, world!".utf8
      XCTAssert(bytes.urlComponentEncodedString == "hello%2C%20world!")
      XCTAssert(bytes.urlFormEncodedString == "hello%2C+world%21")
    }

    // From: StringProtocol.percentEncoded(using:)
    do {
      // Percent-encoding can be used to escapes special characters, e.g. spaces.
      XCTAssertEqual("hello, world!".percentEncoded(as: \.userInfo), "hello,%20world!")

      // Encode-sets determine which characters are encoded, and some perform substitutions.
      XCTAssertEqual("/usr/bin/swift".urlComponentEncoded, "%2Fusr%2Fbin%2Fswift")
      XCTAssertEqual("king of the 🦆s".urlFormEncoded, "king+of+the+%F0%9F%A6%86s")
    }
  }

  func testDecodingWithKeyPath() {

    // From: LazyCollectionProtocol.percentDecoded(substitutions:)
    do {
      // The bytes, containing a string with UTF-8 form-encoding.
      let source: [UInt8] = [
        0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64,
      ]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "h%C2%A3llo+world")

      // Specify the `.formEncoding` substitution set to decode the contents.
      XCTAssert(source.lazy.percentDecodedUTF8(from: \.form).elementsEqual("h£llo world".utf8))
    }

    // From: LazyCollectionProtocol.percentDecoded()
    do {
      // The bytes, containing a string with percent-encoding.
      let source: [UInt8] = [0x25, 0x36, 0x31, 0x25, 0x36, 0x32, 0x25, 0x36, 0x33]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "%61%62%63")

      // In this case, the decoded bytes contain the ASCII string "abc".
      XCTAssert(source.lazy.percentDecodedUTF8.elementsEqual("abc".utf8))
    }

    // From: StringProtocol.percentDecoded(substitutions:)
    do {
      // Decode percent-encoded UTF-8 as a string.
      XCTAssertEqual("hello,%20world!".percentDecoded(from: \.percentEncodedOnly), "hello, world!")
      XCTAssertEqual("%2Fusr%2Fbin%2Fswift".percentDecoded(from: \.percentEncodedOnly), "/usr/bin/swift")

      // Some encodings require a substitution map to accurately decode.
      XCTAssertEqual("king+of+the+%F0%9F%A6%86s".percentDecoded(from: \.form), "king of the 🦆s")
      XCTAssertEqual("king+of+the+%F0%9F%A6%86s".urlFormDecoded, "king of the 🦆s")
    }

    // Note: StringProtocol.percentDecoded() can't be back-ported; changed from a computed property to a function.

    // Collection.percentDecodedString(from:)
    do {
      let source: [UInt8] = [0x25, 0x36, 0x31, 0x25, 0x36, 0x32, 0x25, 0x36, 0x33]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "%61%62%63")
      XCTAssertEqual(source.percentDecodedString(from: \.percentEncodedOnly), "abc")
    }
    // Collection.percentDecodedString
    do {
      let source: [UInt8] = [0x25, 0x36, 0x31, 0x25, 0x36, 0x32, 0x25, 0x36, 0x33]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "%61%62%63")
      XCTAssertEqual(source.percentDecodedString, "abc")
    }
    // Collection.urlFormDecodedString
    do {
      let source: [UInt8] = [
        0x68, 0x25, 0x43, 0x32, 0x25, 0x41, 0x33, 0x6C, 0x6C, 0x6F, 0x2B, 0x77, 0x6F, 0x72, 0x6C, 0x64,
      ]
      XCTAssertEqual(String(decoding: source, as: UTF8.self), "h%C2%A3llo+world")
      XCTAssertEqual(source.lazy.urlFormDecodedString, "h£llo world")
    }
  }
}
