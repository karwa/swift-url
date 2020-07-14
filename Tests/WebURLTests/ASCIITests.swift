import XCTest

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
