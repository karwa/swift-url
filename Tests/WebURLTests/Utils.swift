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

/// Asserts that two sequences contain the same elements in the same order.
///
func XCTAssertEqualElements<Left: Sequence, Right: Sequence>(
  _ left: Left, _ right: Right, file: StaticString = #file, line: UInt = #line
) where Left.Element == Right.Element, Left.Element: Equatable {
  XCTAssertTrue(left.elementsEqual(right), file: file, line: line)
}

/// Aseerts that a closure throws a particular error.
///
func XCTAssertThrowsSpecific<E>(
  _ expectedError: E, file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void
) where E: Error, E: Equatable {
  do {
    try body()
    XCTFail("Expected an error to be thrown")
  } catch let error as E {
    XCTAssertEqual(error, expectedError)
  } catch {
    XCTFail("Unexpected error")
  }
}

/// A String containing all 128 ASCII characters (`0..<128`), in order.
///
let stringWithEveryASCIICharacter: String = {
  let asciiChars: Range<UInt8> = 0..<128
  let str = String(asciiChars.lazy.map { Character(UnicodeScalar($0)) })
  precondition(str.utf8.elementsEqual(asciiChars))
  return str
}()


// --------------------------------------------
// MARK: - WebURL test utilities
// --------------------------------------------


@inline(__always)
func checkDoesNotCopy(_ url: inout WebURL, _ body: (inout WebURL) -> Void) {
  let addressBefore = url.storage.withEntireString { $0.baseAddress }
  body(&url)
  XCTAssertEqual(addressBefore, url.storage.withEntireString { $0.baseAddress })
}

/// Checks that the given URL returns precisely the same value when its serialized representation is re-parsed.
///
func XCTAssertURLIsIdempotent(_ url: WebURL) {
  var serialized = url.serialized
  serialized.makeContiguousUTF8()
  guard let reparsed = WebURL(serialized) else {
    XCTFail("Failed to reparse URL string: \(serialized)")
    return
  }
  // Check that the URLStructure (i.e. code-unit offsets, flags, etc) are the same.
  XCTAssertEqual(url.storage.structure, reparsed.storage.structure)
  // Check that the code-units are the same.
  url.storage.withEntireString { original in
    reparsed.storage.withEntireString { reparsed in
      XCTAssertEqualElements(original, reparsed)
    }
  }
  // Triple check: check that the serialized representations are the same.
  XCTAssertEqual(serialized, reparsed.serialized)
}
