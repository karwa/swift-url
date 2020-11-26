import XCTest
import Checkit

@testable import WebURL

// TODO:
// Test plan.
//================
// - UInt8 -> ASCII Hex
// - UInt8 -> ASCII Decimal
// - ASCII Hex -> UInt8
// - ASCII Dec -> UInt8
// - ASCII.insertHexString
// - More? lowercased/isAlpha/ranges/etc?

final class ASCIITests: XCTestCase {

  func testASCIIDecimalPrinting() {
    var buf: [UInt8] = [0, 0, 0, 0]
    buf.withUnsafeMutableBufferPointer { buffer in
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
