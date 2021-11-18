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

/// Asserts that a closure throws a particular error.
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
    XCTFail("Unexpected error \(error)")
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
// MARK: - Tuples
// --------------------------------------------


typealias Tuple4<T> = (T, T, T, T)
typealias Tuple8<T> = (T, T, T, T, T, T, T, T)
typealias Tuple16<T> = (T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T)

extension Array {

  init(elements tuple: Tuple4<Element>) {
    self = [tuple.0, tuple.1, tuple.2, tuple.3]
  }

  init(elements tuple: Tuple8<Element>) {
    self = [tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7]
  }

  init(elements tuple: Tuple16<Element>) {
    self = [
      tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7,
      tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15,
    ]
  }
}

// One day, when tuples are Equatable, we won't need these.
// https://github.com/apple/swift-evolution/blob/main/proposals/0283-tuples-are-equatable-comparable-hashable.md
func XCTAssertEqual<T>(
  _ expression1: @autoclosure () throws -> Tuple4<T>?,
  _ expression2: @autoclosure () throws -> Tuple4<T>?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) rethrows where T: Equatable {
  let left = try expression1()
  let right = try expression2()
  switch (left, right) {
  case (.none, .none):
    return
  case (.some, .none), (.none, .some):
    XCTFail(
      "XCTAssertEqual failed. \(String(describing: left)) is not equal to \(String(describing: right)). \(message())",
      file: file, line: line
    )
  case (.some(let left), .some(let right)):
    XCTAssertEqual(Array(elements: left), Array(elements: right), message(), file: file, line: line)
  }
}

func XCTAssertEqual<T>(
  _ expression1: @autoclosure () throws -> Tuple8<T>?,
  _ expression2: @autoclosure () throws -> Tuple8<T>?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) rethrows where T: Equatable {
  let left = try expression1()
  let right = try expression2()
  switch (left, right) {
  case (.none, .none):
    return
  case (.some, .none), (.none, .some):
    XCTFail(
      "XCTAssertEqual failed. \(String(describing: left)) is not equal to \(String(describing: right)). \(message())",
      file: file, line: line
    )
  case (.some(let left), .some(let right)):
    XCTAssertEqual(Array(elements: left), Array(elements: right), message(), file: file, line: line)
  }
}

func XCTAssertEqual<T>(
  _ expression1: @autoclosure () throws -> Tuple16<T>?,
  _ expression2: @autoclosure () throws -> Tuple16<T>?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) rethrows where T: Equatable {
  let left = try expression1()
  let right = try expression2()
  switch (left, right) {
  case (.none, .none):
    return
  case (.some, .none), (.none, .some):
    XCTFail(
      "XCTAssertEqual failed. \(String(describing: left)) is not equal to \(String(describing: right)). \(message())",
      file: file, line: line
    )
  case (.some(let left), .some(let right)):
    XCTAssertEqual(Array(elements: left), Array(elements: right), message(), file: file, line: line)
  }
}


// --------------------------------------------
// MARK: - WebURL test utilities
// --------------------------------------------


@inline(__always)
func checkDoesNotCopy(_ url: inout WebURL, _ body: (inout WebURL) -> Void) {
  let addressBefore = url.utf8.withUnsafeBufferPointer { $0.baseAddress }
  body(&url)
  XCTAssertEqual(addressBefore, url.utf8.withUnsafeBufferPointer { $0.baseAddress })
}

/// Checks that the given URL returns precisely the same value when its serialized representation is re-parsed.
///
func XCTAssertURLIsIdempotent(_ url: WebURL) {
  var serialized = url.serialized()
  serialized.makeContiguousUTF8()
  guard let reparsed = WebURL(serialized) else {
    XCTFail("Failed to reparse URL string: \(serialized)")
    return
  }
  // Check that the URLStructure (i.e. code-unit offsets, flags, etc) are the same.
  XCTAssertTrue(url.storage.structure.describesSameStructure(as: reparsed.storage.structure))
  // Check that the code-units are the same.
  XCTAssertEqualElements(url.utf8, reparsed.utf8)
  // Triple check: check that the serialized representations are the same.
  XCTAssertEqual(serialized, reparsed.serialized())
}

/// Checks the component values of the given URL. Any components not specified are checked to have a `nil` value.
///
func XCTAssertURLComponents(
  _ url: WebURL, scheme: String, username: String? = nil, password: String? = nil, hostname: String? = nil,
  port: Int? = nil, path: String, query: String? = nil, fragment: String? = nil
) {
  XCTAssertEqual(url.scheme, scheme)
  XCTAssertEqual(url.username, username)
  XCTAssertEqual(url.password, password)
  XCTAssertEqual(url.hostname, hostname)
  XCTAssertEqual(url.port, port)
  XCTAssertEqual(url.path, path)
  XCTAssertEqual(url.query, query)
  XCTAssertEqual(url.fragment, fragment)
}
