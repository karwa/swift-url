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

import Checkit
import XCTest

@testable import WebURL

final class ASCIITests: XCTestCase {

  func testASCIIHexValue() {
    // Test that hex digits have the appropriate character classes,
    // that we can get the numeric value of a character and the character of a numeric value.

    // uppercase.
    do {
      for (numericValue, character) in "0123456789ABCDEF".enumerated() {
        guard let asciiChar = ASCII(flatMap: character.asciiValue) else {
          XCTFail("\(character) not recognized as ASCII")
          continue
        }

        XCTAssertTrue(asciiChar.isHexDigit)
        XCTAssertTrue(asciiChar.isAlphaNumeric)
        if numericValue < 10 {
          XCTAssertTrue(asciiChar.isDigit)
        } else {
          XCTAssertTrue(asciiChar.isAlpha)
        }

        XCTAssertEqual(asciiChar.hexNumberValue.map { Int($0) }, numericValue)
        XCTAssertEqual(asciiChar, ASCII.uppercaseHexDigit(of: UInt8(numericValue)))
      }
      for invalidChar in [ASCII.G, .O, .X] {
        XCTAssertFalse(invalidChar.isHexDigit)
        XCTAssertNil(invalidChar.hexNumberValue)

        XCTAssertTrue(invalidChar.isAlpha)
        XCTAssertTrue(invalidChar.isAlphaNumeric)
      }
      for cycledNumber in 16...UInt8.max {
        XCTAssertEqual(ASCII.uppercaseHexDigit(of: cycledNumber).hexNumberValue, cycledNumber % 16)
      }
    }

    // lowercase.
    do {
      for (numericValue, character) in "0123456789abcdef".enumerated() {
        guard let asciiChar = ASCII(flatMap: character.asciiValue) else {
          XCTFail("\(character) not recognized as ASCII")
          continue
        }

        XCTAssertTrue(asciiChar.isHexDigit)
        XCTAssertTrue(asciiChar.isAlphaNumeric)
        if numericValue < 10 {
          XCTAssertTrue(asciiChar.isDigit)
        } else {
          XCTAssertTrue(asciiChar.isAlpha)
        }

        XCTAssertEqual(asciiChar.hexNumberValue.map { Int($0) }, numericValue)
        XCTAssertEqual(asciiChar, ASCII.lowercaseHexDigit(of: UInt8(numericValue)))
      }
      for invalidChar in [ASCII.g, .o, .x] {
        XCTAssertFalse(invalidChar.isHexDigit)
        XCTAssertNil(invalidChar.hexNumberValue)

        XCTAssertTrue(invalidChar.isAlpha)
        XCTAssertTrue(invalidChar.isAlphaNumeric)
      }
      for cycledNumber in 16...UInt8.max {
        XCTAssertEqual(ASCII.lowercaseHexDigit(of: cycledNumber).hexNumberValue, cycledNumber % 16)
      }
    }
  }

  func testASCIIDecimalValue() {
    // Test that decimal digits have the appropriate character classes,
    // that we can get the numeric value of a character and the character of a numeric value.

    for (numericValue, character) in "0123456789".enumerated() {
      guard let asciiChar = ASCII(flatMap: character.asciiValue) else {
        XCTFail("\(character) not recognized as ASCII")
        continue
      }

      XCTAssertTrue(asciiChar.isDigit)
      XCTAssertTrue(asciiChar.isHexDigit)
      XCTAssertFalse(asciiChar.isAlpha)
      XCTAssertTrue(asciiChar.isAlphaNumeric)

      XCTAssertEqual(asciiChar.decimalNumberValue.map { Int($0) }, numericValue)
      XCTAssertEqual(asciiChar, ASCII.decimalDigit(of: UInt8(numericValue)))
    }
    for invalidChar in [ASCII.A, .B, .C, .D, .E, .F, .G, .O, .X, .a, .b, .c, .d, .e, .f, .g, .o, .x] {
      XCTAssertFalse(invalidChar.isDigit)
      XCTAssertTrue(invalidChar.isAlpha)
      XCTAssertTrue(invalidChar.isAlphaNumeric)
      XCTAssertNil(invalidChar.decimalNumberValue)
    }
    for invalidNumber in 10...UInt8.max {
      XCTAssertNil(ASCII.decimalDigit(of: invalidNumber))
    }
  }

  func testASCIIDecimalPrinting() {
    var buf: [UInt8] = [0, 0, 0, 0]
    buf.withUnsafeMutableBytes { buffer in
      for num in (UInt8.min)...(UInt8.max) {
        let bufferContentsEnd = ASCII.insertDecimalString(for: num, into: buffer)
        let asciiContents = Array(buffer[..<bufferContentsEnd])
        let stdlibString = Array(String(num, radix: 10).utf8)
        XCTAssertEqual(stdlibString, asciiContents)
      }
    }
  }
}


// MARK: - Lazy views.


extension ASCIITests {

  func testLazyLowercase() {
    let testData: [(String, String, isEmpty: Bool)] = [
      ("hElLo, wOrLd! ✌️ PEAcE :)", "hello, world! ✌️ peace :)", false),
      ("no change 0123456789", "no change 0123456789", false),
      ("№ 🅰️$©ℹ️ℹ️", "№ 🅰️$©ℹ️ℹ️", false),
      ("", "", true),
    ]
    for (testString, expected, isEmpty) in testData {
      // Check that it works.
      XCTAssertEqualElements(ASCII.Lowercased(testString.utf8), expected.utf8)
      XCTAssertEqual(ASCII.Lowercased(testString.utf8).isEmpty, isEmpty)
      // Check Collection conformances.
      CollectionChecker.check(ASCII.NewlineAndTabFiltered(testString.utf8))
    }
  }

  func testLazyNewlineAndTabFilter() {
    let testData: [(String, String, isEmpty: Bool)] = [
      ("\thello\nworld\n", "helloworld", false),
      ("\t\n\n\t", "", true),
      ("no change 0123456789", "no change 0123456789", false),
    ]
    for (testString, expected, isEmpty) in testData {
      // Check that it works.
      XCTAssertEqualElements(ASCII.NewlineAndTabFiltered(testString.utf8), expected.utf8)
      XCTAssertEqual(ASCII.NewlineAndTabFiltered(testString.utf8).isEmpty, isEmpty)
      // Check Collection conformances.
      CollectionChecker.check(ASCII.NewlineAndTabFiltered(testString.utf8))
    }
  }
}
