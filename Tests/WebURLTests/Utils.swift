import XCTest

/// Asserts that two sequences contain the same elements in the same order.
///
func XCTAssertEqualElements<Left: Sequence, Right: Sequence>(
  _ left: Left, _ right: Right, file: StaticString = #file, line: UInt = #line
) where Left.Element == Right.Element, Left.Element: Equatable {
  XCTAssertTrue(left.elementsEqual(right), file: file, line: line)
}

/// A String containing all 128 ASCII characters (`0..<128`), in order.
///
let stringWithEveryASCIICharacter: String = {
  let asciiChars: Range<UInt8> = 0..<128
  let str = String(asciiChars.lazy.map { Character(UnicodeScalar($0)) })
  precondition(str.utf8.elementsEqual(asciiChars))
  return str
}()

