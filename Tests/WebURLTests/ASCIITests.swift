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

  func testASCIIHexParseTable() {
    XCTAssertEqual(_parseHex_table.count, 128)
  }

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

    var buf: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]

    // UInt8.
    buf.withUnsafeMutableBytes { buffer in
      for num in (UInt8.min)...(UInt8.max) {
        let bufferContentsCount = ASCII.writeDecimalString(for: num, to: buffer.baseAddress!)
        XCTAssertEqualElements(buffer[..<Int(bufferContentsCount)], String(num, radix: 10).utf8)
      }
    }

    // UInt16.
    buf.withUnsafeMutableBytes { buffer in
      for num in (UInt16.min)...(UInt16.max) {
        let bufferContentsCount = ASCII.writeDecimalString(for: num, to: buffer.baseAddress!)
        XCTAssertEqualElements(buffer[..<Int(bufferContentsCount)], String(num, radix: 10).utf8)
        XCTAssertEqual(bufferContentsCount, ASCII.lengthOfDecimalString(for: num))
      }
    }
  }

  func testDecimalParsing() {

    // All valid numbers can be parsed.
    for num in (UInt16.min)...(UInt16.max) {
      let stringRepresentation = String(num)
      XCTAssertEqual(ASCII.parseDecimalU16(from: stringRepresentation.utf8), UInt16(stringRepresentation))
    }

    // Invalid numbers are rejected.
    XCTAssertNil(ASCII.parseDecimalU16(from: "65536".utf8))
    XCTAssertNil(ASCII.parseDecimalU16(from: "-1".utf8))
    XCTAssertNil(ASCII.parseDecimalU16(from: "-100".utf8))
    XCTAssertNil(ASCII.parseDecimalU16(from: "-0".utf8))
    XCTAssertNil(ASCII.parseDecimalU16(from: "1234boo".utf8))

    // Leading zeroes are fine.
    XCTAssertEqual(ASCII.parseDecimalU16(from: "00000000080".utf8), 80)
  }

  func testASCIIHexPrinting() {

    var buf: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]

    // UInt8.
    buf.withUnsafeMutableBytes { buffer in
      for num in (UInt8.min)...(UInt8.max) {
        let bufferContentsCount = ASCII.writeHexString(for: num, to: buffer.baseAddress!)
        XCTAssertEqualElements(buffer[..<Int(bufferContentsCount)], String(num, radix: 16).utf8)
      }
    }

    // UInt16.
    buf.withUnsafeMutableBytes { buffer in
      for num in (UInt16.min)...(UInt16.max) {
        let bufferContentsCount = ASCII.writeHexString(for: num, to: buffer.baseAddress!)
        XCTAssertEqualElements(buffer[..<Int(bufferContentsCount)], String(num, radix: 16).utf8)
      }
    }

    // Random sample of UInt32s.
    buf.withUnsafeMutableBytes { buffer in
      for _ in 0..<10_000 {
        let num = UInt32.random(in: 0...UInt32.max)
        let bufferContentsCount = ASCII.writeHexString(for: num, to: buffer.baseAddress!)
        XCTAssertEqualElements(buffer[..<Int(bufferContentsCount)], String(num, radix: 16).utf8)
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

  func testLazyNewlineAndTabFilter_contiguous() {
    let testData: [(String, String, isEmpty: Bool)] = [
      ("\thello\n\rworld\n", "helloworld", false),
      ("\n\nnewlines \n\nonly\n", "newlines only", false),
      ("\t\ttabs \t\tonly\t", "tabs only", false),
      ("\r\rcarriage returns \r\ronly\r", "carriage returns only", false),
      ("\t\ttrim only, please\n\r\t", "trim only, please", false),
      ("\t\n\n\r\t", "", true),
      ("no change 0123456789", "no change 0123456789", false),
    ]
    for (testString, expected, isEmpty) in testData {
      if testData.withContiguousStorageIfAvailable({ _ in true }) == nil {
        XCTFail("Expected contiguous input")
      }

      // Check results after performing an initial scan and trimming.
      let initialScanResult = ASCII.filterNewlinesAndTabs(from: testString.utf8)
      switch initialScanResult {
      case .left(let lazyFiltered):
        XCTAssertEqualElements(lazyFiltered, expected.utf8)
        XCTAssertFalse(lazyFiltered.isEmpty)
        XCTAssertFalse(isEmpty)
        CollectionChecker.check(lazyFiltered)
      case .right(let trimmed):
        XCTAssertEqualElements(trimmed, expected.utf8)
        XCTAssertEqual(trimmed.isEmpty, isEmpty)
        CollectionChecker.check(trimmed)
      }

      // Check without performing an initial scan.
      XCTAssertEqualElements(ASCII.NewlineAndTabFiltered(testString.utf8), expected.utf8)
      CollectionChecker.check(ASCII.NewlineAndTabFiltered(testString.utf8))
    }
  }

  func testLazyNewlineAndTabFilter_noncontiguous() {
    let testData: [(String, String, isEmpty: Bool)] = [
      ("\thello\n\rworld\n", "helloworld", false),
      ("\n\nnewlines \n\nonly\n", "newlines only", false),
      ("\t\ttabs \t\tonly\t", "tabs only", false),
      ("\r\rcarriage returns \r\ronly\r", "carriage returns only", false),
      ("\t\ttrim only, please\n\r\t", "trim only, please", false),
      ("\t\n\n\r\t", "", true),
      ("no change 0123456789", "no change 0123456789", false),
    ]
    for (testString, expected, isEmpty) in testData {
      let nonContiguousUTF8 = testString.utf8.lazy.map { $0 }
      if nonContiguousUTF8.withContiguousStorageIfAvailable({ _ in true }) != nil {
        XCTFail("Expected non-contiguous input")
      }

      // Check results after performing an initial scan and trimming.
      let initialScanResult = ASCII.filterNewlinesAndTabs(from: nonContiguousUTF8)
      switch initialScanResult {
      case .left(let lazyFiltered):
        XCTAssertEqualElements(lazyFiltered, expected.utf8)
        XCTAssertFalse(lazyFiltered.isEmpty)
        XCTAssertFalse(isEmpty)
        CollectionChecker.check(lazyFiltered)
      case .right(let trimmed):
        XCTAssertEqualElements(trimmed, expected.utf8)
        XCTAssertEqual(trimmed.isEmpty, isEmpty)
        CollectionChecker.check(trimmed)
      }

      // Check without performing an initial scan.
      XCTAssertEqualElements(ASCII.NewlineAndTabFiltered(nonContiguousUTF8), expected.utf8)
      CollectionChecker.check(ASCII.NewlineAndTabFiltered(nonContiguousUTF8))
    }
  }
}
