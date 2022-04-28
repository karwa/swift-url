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

/// Asserts that two sequences contain the same elements in the same order.
///
func XCTAssertEqualElements<Left: Sequence, Right: Sequence>(
  _ left: Left, _ right: Right, file: StaticString = #file, line: UInt = #line
) where Left.Element == Right.Element, Left.Element: Equatable {
  XCTAssertTrue(left.elementsEqual(right), file: file, line: line)
}

/// Asserts that two sequences contain the same elements in the same order.
///
func XCTAssertEqualElements<Left: Sequence, Right: Sequence>(
  _ left: Left?, _ right: Right, file: StaticString = #file, line: UInt = #line
) where Left.Element == Right.Element, Left.Element: Equatable {
  guard let left = left else {
    XCTFail("nil is not equal to \(right)", file: file, line: line)
    return
  }
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
