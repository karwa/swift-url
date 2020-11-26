import XCTest

/// Asserts that two sequences contain the same elements in the same order.
///
func XCTAssertEqualElements<Left: Sequence, Right: Sequence>(
  _ left: Left, _ right: Right, file: StaticString = #file, line: UInt = #line
) where Left.Element == Right.Element, Left.Element: Equatable {
  XCTAssertTrue(left.elementsEqual(right), file: file, line: line)
}

