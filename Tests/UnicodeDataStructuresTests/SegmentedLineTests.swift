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

import UnicodeDataStructures
import XCTest

fileprivate func XCTAssertSegments<Bound, Value>(
  _ line: SegmentedLine<Bound, Value>,
  _ expected: [(Range<Bound>, Value)]
) where Bound: Comparable, Value: Equatable {

  var expectedIter = expected.makeIterator()
  for (actualRange, actualValue) in line.segments {
    guard let nextExpected = expectedIter.next() else {
      XCTFail("Unexpected entry: \(actualRange) = \(actualValue)")
      return
    }
    XCTAssertEqual(nextExpected.0, actualRange)
    XCTAssertEqual(nextExpected.1, actualValue)
  }
  if let straggler = expectedIter.next() {
    XCTFail("Failed to find entry: \(straggler.0) = \(straggler.1)")
  }

  XCTAssertEqual(expected.count, line.segments.count)
  XCTAssertEqual(expected.isEmpty, line.segments.isEmpty)
}


// --------------------------------------------
// MARK: - SegmentedLineTests
// --------------------------------------------


final class SegmentedLineTests: XCTestCase {}

extension SegmentedLineTests {

  func testDocumentationExamples() {

    // SegmentedLine, .set, .segments
    do {
      var line = SegmentedLine<Int, String?>(bounds: 0..<100, value: nil)

      // After setting values <5 to "small" and values >10 to "large",
      // the gap is left with its previous value, "medium".

      line.set(0..<20, to: "medium")
      line.set(0..<5, to: "small")
      line.set(10..<60, to: "large")

      XCTAssertEqual(
        line.description,
        #"| [0..<5]: Optional("small") | [5..<10]: Optional("medium") | [10..<60]: Optional("large") | [60..<100]: nil |"#
      )
    }

    // modify.
    do {
      enum Font: Equatable {
        case custom(String)
      }

      enum Color {
        case orange
        case green
        case pink
        case yellow

        static var _fakeRandomColors = [Color.orange, .green, .pink, .yellow].makeIterator()
        static func random() -> Color { _fakeRandomColors.next()! }
      }

      let string = "Bob is feeling great"
      var tags = SegmentedLine(
        bounds: string.startIndex..<string.endIndex,
        value: [] as [Any]
      )

      // Set a font attribute over the entire string.

      tags.modify(tags.bounds) { attributes in
        attributes.append(Font.custom("Comic Sans"))
      }

      // Set each word to a different color.

      for word: Substring in string.split(separator: " ") {
        tags.modify(word.startIndex..<word.endIndex) { attributes in
          attributes.append(Color.random())
        }
      }

      // Check the result.

      // for (range, attributes) in tags.segments {
      //   print(#""\#(string[range])""#, "-", attributes)
      // }

      // swift-format-ignore
      var expected: Array<(Substring, [Any])>.Iterator = [
        ("Bob",     [Font.custom("Comic Sans"), Color.orange]),
        (" ",       [Font.custom("Comic Sans")]),
        ("is",      [Font.custom("Comic Sans"), Color.green]),
        (" ",       [Font.custom("Comic Sans")]),
        ("feeling", [Font.custom("Comic Sans"), Color.pink]),
        (" ",       [Font.custom("Comic Sans")]),
        ("great",   [Font.custom("Comic Sans"), Color.yellow]),
      ].makeIterator()

      for (range, attributes) in tags.segments {
        let expectedSegment = expected.next()!
        XCTAssertEqual(string[range], expectedSegment.0)

        var expectedAttributes = expectedSegment.1.makeIterator()
        for actualAttribute in attributes {
          switch actualAttribute {
          case let font as Font: XCTAssertEqual(expectedAttributes.next() as? Font, font)
          case let color as Color: XCTAssertEqual(expectedAttributes.next() as? Color, color)
          default: XCTFail("Unexpected attribute: \(actualAttribute)")
          }
        }
        XCTAssertNil(expectedAttributes.next())
      }
    }
  }

  func testInitWithBoundsAndValue() {

    do {
      let line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, 42)
      ])
    }

    // The bounds are allowed to be empty.
    // This should trap, but we can't test it :(
    // do {
    //   let line = SegmentedLine<Int, Int>(bounds: 100..<100, value: 42)
    //   XCTFail("Should have trapped")
    // }
  }
}


// --------------------------------------------
// MARK: - Set
// --------------------------------------------


extension SegmentedLineTests {

  func testSet_simple() {

    // Setting the entire bounds.
    do {
      var line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)
      line.set(line.bounds, to: 99)

      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, 99)
      ])
    }

    // Setting a region from lowerBound.
    do {
      var line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)

      line.set(0..<64, to: -99)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<64,  -99),
        (64..<100, 42),
      ])

      line.set(0..<32, to: -64)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,  -64),
        (32..<64, -99),
        (64..<100, 42),
      ])

      line.set(0..<16, to: -48)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<16,  -48),
        (16..<32, -64),
        (32..<64, -99),
        (64..<100, 42),
      ])
    }

    // Setting a region from upperBound.
    do {
      var line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)

      line.set(32..<100, to: -99)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,    42),
        (32..<100, -99),
      ])

      line.set(50..<100, to: -64)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,    42),
        (32..<50,  -99),
        (50..<100, -64),
      ])

      line.set(75..<100, to: -48)
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,    42),
        (32..<50,  -99),
        (50..<75,  -64),
        (75..<100, -48),
      ])
    }

    // Setting a region in the middle of the bounds.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "*")

      line.set(20..<80, to: "XX")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "*"),
        (20..<80,  "XX"),
        (80..<100, "*")
      ])

      line.set(40..<60, to: "+++")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "*"),
        (20..<40,  "XX"),
        (40..<60,  "+++"),
        (60..<80,  "XX"),
        (80..<100, "*")
      ])

      line.set(45..<55, to: "<><>")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,  "*"),
        (20..<40, "XX"),
        (40..<45, "+++"),
        (45..<55, "<><>"),
        (55..<60, "+++"),
        (60..<80, "XX"),
        (80..<100, "*")
      ])
    }

    // Setting an empty region.
    // All of these should be no-ops.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region @ lowerBound
      line.set(0..<0, to: "---")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region inside the first segment.
      line.set(10..<10, to: "---")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region on a segment boundary.
      line.set(30..<30, to: "---")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region on another segment boundary.
      line.set(60..<60, to: "---")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region for the last valid location.
      line.set(99..<99, to: "---")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])
    }

    // Setting multiple regions without overlap (in order)
    do {
      var line = SegmentedLine<UInt32, String>(bounds: 0..<0x11_0000, value: "<Unicode>")
      line.set(0x00_0000..<0x00_0080, to: "ASCII")
      line.set(0x00_0080..<0x01_0000, to: "BMP")
      line.set(0x01_0000..<0x02_0000, to: "SMP")

      XCTAssertEqual(line.bounds, 0..<0x11_0000)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<128,          "ASCII"),
        (128..<65536,      "BMP"),
        (65536..<131072,   "SMP"),
        (131072..<1114112, "<Unicode>"),
      ])
    }
  }

  func testSet_acrossSegments() {

    // Setting across existing segments.
    // - Not anchored to start/end of line.
    // - Neither endpoint is on an existing boundary.
    //
    //      V-----V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.set(20..<40, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "A"),
        (20..<40,  "X"),
        (40..<60,  "B"),
        (60..<100, "C"),
      ])

      // Split the A-X and X-B boundaries.
      line.set(10..<30, to: "+")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "A"),
        (10..<30,  "+"),
        (30..<40,  "X"),
        (40..<60,  "B"),
        (60..<100, "C"),
      ])
      line.set(35..<50, to: "-")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "A"),
        (10..<30,  "+"),
        (30..<35,  "X"),
        (35..<50,  "-"),
        (50..<60,  "B"),
        (60..<100, "C"),
      ])

      // Set over lots of boundaries.
      line.set(20..<90, to: ":)")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "A"),
        (10..<20,  "+"),
        (20..<90,  ":)"),
        (90..<100, "C"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.set(25..<125, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<25,   "B"),
        (25..<125,  "X"),
        (125..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Setting across existing segments.
    // - May be anchored to start/end of the line.
    // - Both endpoints are on existing boundaries.
    //
    //         V-------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.set(30..<60, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "X"),
        (60..<100, "C"),
      ])
      line.set(0..<30, to: "+")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "+"),
        (30..<60,  "X"),
        (60..<100, "C"),
      ])
      line.set(60..<100, to: "-")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "+"),
        (30..<60,  "X"),
        (60..<100, "-"),
      ])

      // Combine multiple segments.
      line.set(0..<60, to: ":)")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<60,   ":)"),
        (60..<100, "-"),
      ])
      line.set(0..<100, to: "!")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, "!"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.set(40..<120, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<120,  "X"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Setting across existing segments.
    // - Lowerbound is anchored to start of the line.
    // - Upperbound is not an existing boundary.
    //
    // V-----------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.set(0..<40, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "X"),
        (40..<60,  "B"),
        (60..<100, "C"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.set(0..<125, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<125,   "X"),
        (125..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Setting across existing segments.
    // - Lowerbound is not an existing boundary.
    // - Upperbound is anchored to end of the line.
    //
    //             V-----------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.set(50..<100, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<50,  "B"),
        (50..<100, "X"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.set(50..<160, to: "X")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "A"),
        (20..<40,  "B"),
        (40..<50,  "C"),
        (50..<160, "X"),
      ])
    }
  }
}


// --------------------------------------------
// MARK: - Modify
// --------------------------------------------


extension SegmentedLineTests {

  func testModify_simple() {

    // Modify the entire bounds.
    do {
      var line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)

      line.modify(line.bounds) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, 84)
      ])
    }

    // Modify a region from lowerBound.
    do {
      var line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)

      line.modify(0..<64) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<64,   84),
        (64..<100, 42),
      ])

      line.modify(0..<32) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,   168),
        (32..<64,  84),
        (64..<100, 42),
      ])

      line.modify(0..<16) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<16,   336),
        (16..<32,  168),
        (32..<64,  84),
        (64..<100, 42),
      ])
    }

    // Modify a region from upperBound.
    do {
      var line = SegmentedLine<Int, Int>(bounds: 0..<100, value: 42)

      line.modify(32..<100) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,   42),
        (32..<100, 84),
      ])

      line.modify(50..<100) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,   42),
        (32..<50,  84),
        (50..<100, 168),
      ])

      line.modify(75..<100) { $0 *= 2 }
      XCTAssertEqual(line.bounds, 0..<100)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<32,   42),
        (32..<50,  84),
        (50..<75,  168),
        (75..<100, 336),
      ])
    }

    // Modifying a region in the middle of the bounds.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "*")

      line.modify(20..<80) { $0 += "-" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (00..<20,  "*"),
        (20..<80,  "*-"),
        (80..<100, "*")
      ])

      line.modify(40..<60) { $0 += "x" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (00..<20,  "*"),
        (20..<40,  "*-"),
        (40..<60,  "*-x"),
        (60..<80,  "*-"),
        (80..<100, "*")
      ])

      line.modify(45..<55) { $0 += "<>" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (00..<20,  "*"),
        (20..<40,  "*-"),
        (40..<45,  "*-x"),
        (45..<55,  "*-x<>"),
        (55..<60,  "*-x"),
        (60..<80,  "*-"),
        (80..<100, "*")
      ])
    }

    // Modifying an empty region.
    // All of these should be no-ops.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region @ lowerBound
      line.modify(0..<0) {
        XCTFail("Should not be called")
        $0 += "FAIL"
      }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region inside the first segment.
      line.modify(10..<10) {
        XCTFail("Should not be called")
        $0 += "FAIL"
      }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region on a segment boundary.
      line.modify(30..<30) {
        XCTFail("Should not be called")
        $0 += "FAIL"
      }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region on another segment boundary.
      line.modify(60..<60) {
        XCTFail("Should not be called")
        $0 += "FAIL"
      }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      // Empty region for the last valid location.
      line.modify(99..<99) {
        XCTFail("Should not be called")
        $0 += "FAIL"
      }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])
    }

    // Modifying multiple regions in-order without overlap
    do {
      var line = SegmentedLine<UInt32, String>(bounds: 0..<0x11_0000, value: "<Unicode>")
      line.modify(0x00_0000..<0x00_0080) {
        XCTAssertEqual($0, "<Unicode>")
        $0 = "ASCII"
      }
      line.modify(0x00_0080..<0x01_0000) {
        XCTAssertEqual($0, "<Unicode>")
        $0 = "BMP"
      }
      line.modify(0x01_0000..<0x02_0000) {
        XCTAssertEqual($0, "<Unicode>")
        $0 = "SMP"
      }

      XCTAssertEqual(line.bounds, 0..<0x11_0000)
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<128,          "ASCII"),
        (128..<65536,      "BMP"),
        (65536..<131072,   "SMP"),
        (131072..<1114112, "<Unicode>"),
      ])
    }
  }

  func testModify_acrossSegments() {

    // Modifying across existing segments.
    // - Not anchored to start/end of the line.
    // - Neither endpoint matches an existing boundary.
    //
    //      V-----V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(20..<40) { $0 += "[1]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "A"),
        (20..<30,  "A[1]"),
        (30..<40,  "B[1]"),
        (40..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(10..<50) { $0 += "[2]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "A"),
        (10..<20,  "A[2]"),
        (20..<30,  "A[1][2]"),
        (30..<40,  "B[1][2]"),
        (40..<50,  "B[2]"),
        (50..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(35..<36) { $0 += "[3]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "A"),
        (10..<20,  "A[2]"),
        (20..<30,  "A[1][2]"),
        (30..<35,  "B[1][2]"),
        (35..<36,  "B[1][2][3]"),
        (36..<40,  "B[1][2]"),
        (40..<50,  "B[2]"),
        (50..<60,  "B"),
        (60..<100, "C"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.modify(0..<20) { $0 = "A" }
      line.modify(20..<40) { $0 = "B" }
      line.modify(40..<60) { $0 = "C" }
      line.modify(60..<80) { $0 = "D" }
      line.modify(80..<100) { $0 = "E" }
      line.modify(100..<120) { $0 = "F" }
      line.modify(120..<140) { $0 = "G" }
      line.modify(140..<160) { $0 = "H" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.modify(25..<125) { $0 += "X" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<25,   "B"),
        (25..<40,   "BX"),
        (40..<60,   "CX"),
        (60..<80,   "DX"),
        (80..<100,  "EX"),
        (100..<120, "FX"),
        (120..<125, "GX"),
        (125..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Modifying across existing segments.
    // - May be anchored to start/end of line.
    // - Both endpoints match existing boundaries.
    //
    //         V-------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(30..<60) { $0 += "[1]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B[1]"),
        (60..<100, "C"),
      ])
      line.modify(0..<30) { $0 += "[2]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A[2]"),
        (30..<60,  "B[1]"),
        (60..<100, "C"),
      ])
      line.modify(60..<100) { $0 += "[3]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A[2]"),
        (30..<60,  "B[1]"),
        (60..<100, "C[3]"),
      ])

      // Modify multiple segments.
      line.modify(0..<60) { $0 += "[4]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A[2][4]"),
        (30..<60,  "B[1][4]"),
        (60..<100, "C[3]"),
      ])
      line.modify(0..<100) { $0 += "[5]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A[2][4][5]"),
        (30..<60,  "B[1][4][5]"),
        (60..<100, "C[3][5]"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.modify(40..<120) { $0 += "***" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C***"),
        (60..<80,   "D***"),
        (80..<100,  "E***"),
        (100..<120, "F***"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Modifying across existing segments.
    // - Lowerbound is anchored to start of line.
    // - Upperbound is not an existing boundary.
    //
    // V-----------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(0..<40) { $0 += "[X]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A[X]"),
        (30..<40,  "B[X]"),
        (40..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(0..<70) { $0 += "***" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A[X]***"),
        (30..<40,  "B[X]***"),
        (40..<60,  "B***"),
        (60..<70,  "C***"),
        (70..<100, "C"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.modify(0..<50) { $0 = "LessThanFifty" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "LessThanFifty"),
        (20..<40,   "LessThanFifty"),
        (40..<50,   "LessThanFifty"),
        (50..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Modifying across existing segments.
    // - Lowerbound is not an existing boundary.
    // - Upperbound is anchored to end of line.
    //
    //             V-----------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "C")
      line.set(0..<30, to: "A")
      line.set(30..<60, to: "B")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<60,  "B"),
        (60..<100, "C"),
      ])

      line.modify(50..<100) { $0 += "[X]" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<30,   "A"),
        (30..<50,  "B"),
        (50..<60,  "B[X]"),
        (60..<100, "C[X]"),
      ])

      line.modify(20..<100) { $0 += "***" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "A"),
        (20..<30,  "A***"),
        (30..<50,  "B***"),
        (50..<60,  "B[X]***"),
        (60..<100, "C[X]***"),
      ])
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<160, value: "-")
      line.set(0..<20, to: "A")
      line.set(20..<40, to: "B")
      line.set(40..<60, to: "C")
      line.set(60..<80, to: "D")
      line.set(80..<100, to: "E")
      line.set(100..<120, to: "F")
      line.set(120..<140, to: "G")
      line.set(140..<160, to: "H")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<80,   "D"),
        (80..<100,  "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      line.modify(70..<160) { $0 = "MoreThanSeventy" }
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,    "A"),
        (20..<40,   "B"),
        (40..<60,   "C"),
        (60..<70,   "D"),
        (70..<80,   "MoreThanSeventy"),
        (80..<100,  "MoreThanSeventy"),
        (100..<120, "MoreThanSeventy"),
        (120..<140, "MoreThanSeventy"),
        (140..<160, "MoreThanSeventy"),
      ])
    }
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension SegmentedLineTests {

  func testEquatable() {

    let _lineOne: SegmentedLine<UInt32, String>
    let _lineTwo: SegmentedLine<UInt32, String>

    // Simple construction - assigning ranges with no overlaps.
    do {
      var line = SegmentedLine<UInt32, String>(bounds: 0..<0x11_0000, value: "<Unicode>")
      line.set(0..<0x80, to: "ASCII")
      line.set(0x00_0080..<0x01_0000, to: "BMP")
      line.set(0x01_0000..<0x02_0000, to: "SMP")

      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<0x80,              "ASCII"),
        (0x80..<0x01_0000,      "BMP"),
        (0x01_0000..<0x02_0000, "SMP"),
        (0x02_0000..<0x11_0000, "<Unicode>"),
      ])
      _lineOne = line
    }

    // More elaborate construction - setting things, overwriting things, etc.
    do {
      var line = SegmentedLine<UInt32, String>(bounds: 0..<0x11_0000, value: "<Unicode>")

      line.set(0..<10, to: "<10")
      line.set(5..<10, to: ">5")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<5,          "<10"),
        (5..<10,         ">5"),
        (10..<0x11_0000, "<Unicode>"),
      ])

      line.set(0x00_0000..<0x01_0000, to: "BMP")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<0x01_0000,         "BMP"),
        (0x01_0000..<0x11_0000, "<Unicode>"),
      ])

      line.set(0x01_0000..<0x02_0000, to: "SMP")
      line.set(0..<0x80, to: "ASCII")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<0x80,              "ASCII"),
        (0x80..<0x01_0000,      "BMP"),
        (0x01_0000..<0x02_0000, "SMP"),
        (0x02_0000..<0x11_0000, "<Unicode>"),
      ])

      _lineTwo = line
    }

    // Each line should be considered == to itself.
    XCTAssertTrue(_lineOne == _lineOne)
    XCTAssertTrue(_lineTwo == _lineTwo)

    // Even though we built these lines up in different ways,
    // they have the exact same set of segments, and hence should be ==.
    XCTAssertTrue(_lineOne == _lineTwo)

    // If we change a segment's data, it will no longer be considered == to lineOne/Two.
    do {
      var line = _lineTwo
      line.set(0x80..<0x01_0000, to: "PMB")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<0x80,              "ASCII"),
        (0x80..<0x01_0000,      "PMB"),
        (0x01_0000..<0x02_0000, "SMP"),
        (0x02_0000..<0x11_0000, "<Unicode>"),
      ])

      XCTAssertTrue(line == line)
      XCTAssertFalse(line == _lineOne)
      XCTAssertFalse(line == _lineTwo)
    }

    // If we change a segment's length, it will no longer be considered == to lineOne/Two.
    do {
      var line = _lineTwo
      line.set(0x80..<0x01_00FF, to: "BMP")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<0x80,              "ASCII"),
        (0x80..<0x01_00FF,      "BMP"),
        (0x01_00FF..<0x02_0000, "SMP"),
        (0x02_0000..<0x11_0000, "<Unicode>"),
      ])

      XCTAssertTrue(line == line)
      XCTAssertFalse(line == _lineOne)
      XCTAssertFalse(line == _lineTwo)
    }

    // We store every break-point location in an Array (except upperBound).
    // Ensure that even if 2 lines have the same break-points, different upperBounds make them different lines.
    do {
      var line = SegmentedLine<UInt32, String>(bounds: 0..<0x12_0000, value: "<Unicode>")
      line.set(0..<0x80, to: "ASCII")
      line.set(0x00_0080..<0x01_0000, to: "BMP")
      line.set(0x01_0000..<0x02_0000, to: "SMP")

      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<0x80,              "ASCII"),
        (0x80..<0x01_0000,      "BMP"),
        (0x01_0000..<0x02_0000, "SMP"),
        (0x02_0000..<0x12_0000, "<Unicode>"),
      ])

      XCTAssertTrue(line == line)
      XCTAssertFalse(line == _lineOne)
      XCTAssertFalse(line == _lineTwo)
    }
  }

  func testCustomStringConvertible() {
    do {
      let line = SegmentedLine<Int, String>(bounds: 0..<100, value: "<default>")
      let description = line.description
      XCTAssertEqual(description, #"| [0..<100]: <default> |"#)
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "<low>")
      line.set(50..<100, to: "hi 👋")
      let description = line.description
      XCTAssertEqual(description, #"| [0..<50]: <low> | [50..<100]: hi 👋 |"#)
    }
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "<default>")
      line.set(20..<40, to: "hello")
      let description = line.description
      XCTAssertEqual(description, #"| [0..<20]: <default> | [20..<40]: hello | [40..<100]: <default> |"#)
    }
  }
}


// --------------------------------------------
// MARK: - Table Optimization
// --------------------------------------------


extension SegmentedLineTests {

  func testMapValues() {
    var line = SegmentedLine<UInt32, String>(bounds: 0..<0x11_0000, value: "<Unicode>")
    line.set(0..<0x80, to: "ASCII")
    line.set(0x00_0080..<0x01_0000, to: "BMP")
    line.set(0x01_0000..<0x02_0000, to: "SMP")

    // swift-format-ignore
    XCTAssertSegments(line, [
      (0..<0x80,              "ASCII"),
      (0x80..<0x01_0000,      "BMP"),
      (0x01_0000..<0x02_0000, "SMP"),
      (0x02_0000..<0x11_0000, "<Unicode>"),
    ])

    let mappedLine: SegmentedLine<UInt32, String> = line.mapValues { name in "*-*\(name.lowercased())*-*" }
    XCTAssertEqual(line.bounds, mappedLine.bounds)
    // swift-format-ignore
    XCTAssertSegments(mappedLine, [
      (0..<0x80,              "*-*ascii*-*"),
      (0x80..<0x01_0000,      "*-*bmp*-*"),
      (0x01_0000..<0x02_0000, "*-*smp*-*"),
      (0x02_0000..<0x11_0000, "*-*<unicode>*-*"),
    ])

    // The original table should be left unchanged.
    // swift-format-ignore
    XCTAssertSegments(line, [
      (0..<0x80,              "ASCII"),
      (0x80..<0x01_0000,      "BMP"),
      (0x01_0000..<0x02_0000, "SMP"),
      (0x02_0000..<0x11_0000, "<Unicode>"),
    ])

    // No segment merging is performed.
    let weAreOne: SegmentedLine<UInt32, UInt8> = line.mapValues { _ in 1 }
    // swift-format-ignore
    XCTAssertSegments(weAreOne, [
      (0..<0x80,              1),
      (0x80..<0x01_0000,      1),
      (0x01_0000..<0x02_0000, 1),
      (0x02_0000..<0x11_0000, 1),
    ])
  }

  func testCombineSegmentsWhile() {

    // SegmentedLine does not automatically merge segments (Value does not need to be Equatable).
    // It is possible to have lots of segments all tagged with the same value.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(20..<80, to: "zero")
      line.set(40..<60, to: "zero")
      line.set(45..<55, to: "zero")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero"),
        (20..<40,  "zero"),
        (40..<45,  "zero"),
        (45..<55,  "zero"),
        (55..<60,  "zero"),
        (60..<80,  "zero"),
        (80..<100, "zero"),
      ])

      // We can explicitly fold segments via combineSegments.
      line.combineSegments(while: { $0.value == $1.value })
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, "zero"),
      ])
    }

    // 'combineSegments' should visit every segment.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(20..<80, to: "zero")
      line.set(40..<60, to: "zero")
      line.set(45..<55, to: "zero")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero"),
        (20..<40,  "zero"),
        (40..<45,  "zero"),
        (45..<55,  "zero"),
        (55..<60,  "zero"),
        (60..<80,  "zero"),
        (80..<100, "zero"),
      ])

      let expectedSegments = Array(line.segments)
      var visitedSegments = [(range: Range<Int>, value: String)]()
      line.combineSegments(while: { accumulator, next in
        if visitedSegments.count > 2 {
          // Since we're not merging, 'accumulator' should be equal to 'next' from the previous call.
          XCTAssertEqual(accumulator.range, visitedSegments.last?.range)
          XCTAssertEqual(accumulator.value, visitedSegments.last?.value)
        }
        if visitedSegments.count == 0 { visitedSegments.append(accumulator) }
        visitedSegments.append(next)
        return false
      })

      let areEqual = expectedSegments.elementsEqual(visitedSegments) { $0.range == $1.range && $0.value == $1.value }
      XCTAssertTrue(areEqual)
    }

    // Folding merges segments while the closure returns 'true',
    // but keeps the segment break and starts a new accumulator if the closure returns 'false'.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(20..<80, to: "zero")
      line.set(40..<60, to: "zero")
      line.set(45..<55, to: "zero")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero"),
        (20..<40,  "zero"),
        (40..<45,  "zero"),
        (45..<55,  "zero"),
        (55..<60,  "zero"),
        (60..<80,  "zero"),
        (80..<100, "zero"),
      ])

      // No merge.
      line.combineSegments(while: { acc, _ in false })
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero"),
        (20..<40,  "zero"),
        (40..<45,  "zero"),
        (45..<55,  "zero"),
        (55..<60,  "zero"),
        (60..<80,  "zero"),
        (80..<100, "zero"),
      ])

      // Merge in groups of 2
      var count = 0
      var lineCopy = line
      lineCopy.combineSegments(while: { acc, _ in
        count += 1
        if count < 2 {
          acc.value += "*"
          return true
        } else {
          count = 0
          return false
        }
      })
      // swift-format-ignore
      XCTAssertSegments(lineCopy, [
        (0..<40,   "zero*"),
        (40..<55,  "zero*"),
        (55..<80,  "zero*"),
        (80..<100, "zero"),
      ])

      // Merge in groups of 3
      count = 0
      lineCopy = line
      lineCopy.combineSegments(while: { acc, _ in
        count += 1
        if count < 3 {
          acc.value += "*"
          return true
        } else {
          count = 0
          return false
        }
      })
      // swift-format-ignore
      XCTAssertSegments(lineCopy, [
        (0..<45,   "zero**"),
        (45..<80,  "zero**"),
        (80..<100, "zero"),
      ])

      // Merge in groups of 4
      count = 0
      lineCopy = line
      lineCopy.combineSegments(while: { acc, _ in
        count += 1
        if count < 4 {
          acc.value += "*"
          return true
        } else {
          count = 0
          return false
        }
      })
      // swift-format-ignore
      XCTAssertSegments(lineCopy, [
        (0..<55,   "zero***"),
        (55..<100, "zero**"),
      ])
    }

    // The closure is able to set the segment's value based on its bounds.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(10..<90, to: "zero")
      line.set(20..<80, to: "zero")
      line.set(30..<70, to: "zero")
      line.set(40..<60, to: "zero")
      line.set(20..<30, to: "one")
      line.set(70..<80, to: "one")
      line.set(90..<100, to: "one")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "zero"),
        (10..<20,  "zero"),
        (20..<30,  "one"),
        (30..<40,  "zero"),
        (40..<60,  "zero"),
        (60..<70,  "zero"),
        (70..<80,  "one"),
        (80..<90,  "zero"),
        (90..<100, "one")
      ])

      line.combineSegments(while: { accumulator, next in
        if accumulator.value.starts(with: next.value) {
          // Mark when we fold a segment.
          accumulator.value += "+"
          return true
        }
        // Mark when we know the final range.
        accumulator.value += " over \(accumulator.range)"
        return false
      })
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero+ over 0..<20"),
        (20..<30,  "one over 20..<30"),
        (30..<70,  "zero++ over 30..<70"),
        (70..<80,  "one over 70..<80"),
        (80..<90,  "zero over 80..<90"),
        (90..<100, "one"),
      ])
    }

    // The accumulator's range cannot be altered by the caller.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(20..<80, to: "zero")
      line.set(40..<60, to: "one")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero"),
        (20..<40,  "zero"),
        (40..<60,  "one"),
        (60..<80,  "zero"),
        (80..<100, "zero"),
      ])

      var expectedRange = 0..<20
      line.combineSegments(while: { accumulator, next in
        XCTAssertEqual(accumulator.range, expectedRange)
        // Calculate the expected range for next time and set the range to a bogus value.
        if accumulator.value == next.value {
          expectedRange = accumulator.range.lowerBound..<next.range.upperBound
          accumulator.range = 5..<10
          return true
        } else {
          expectedRange = next.range
          accumulator.range = 14..<16
          return false
        }
      })

      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "zero"),
        (40..<60,  "one"),
        (60..<100, "zero"),
      ])
    }
  }

  func testCombineSegmentsEquatable() {

    // Bonus test. Some mixed-length ranges.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(10..<90, to: "zero")
      line.set(20..<80, to: "zero")
      line.set(30..<70, to: "zero")
      line.set(40..<60, to: "zero")
      line.set(20..<30, to: "one")
      line.set(70..<80, to: "one")
      line.set(90..<100, to: "one")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<10,   "zero"),
        (10..<20,  "zero"),
        (20..<30,  "one"),
        (30..<40,  "zero"),
        (40..<60,  "zero"),
        (60..<70,  "zero"),
        (70..<80,  "one"),
        (80..<90,  "zero"),
        (90..<100, "one")
      ])

      line.combineSegments()
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20, "zero"),
        (20..<30, "one"),
        (30..<70, "zero"),
        (70..<80, "one"),
        (80..<90, "zero"),
        (90..<100, "one")
      ])
    }

    // Duplicates at the start and end of the line.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      line.set(20..<80, to: "zero")
      line.set(40..<60, to: "one")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<20,   "zero"),
        (20..<40,  "zero"),
        (40..<60,  "one"),
        (60..<80,  "zero"),
        (80..<100, "zero"),
      ])

      line.combineSegments()
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "zero"),
        (40..<60,  "one"),
        (60..<100, "zero")
      ])
    }

    // Line is already compact. Should be a no-op.
    do {
      var line = SegmentedLine<Int, String>(bounds: 0..<100, value: "zero")

      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, "zero")
      ])
      line.combineSegments()
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<100, "zero")
      ])

      line.set(40..<60, to: "one")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "zero"),
        (40..<60,  "one"),
        (60..<100, "zero"),
      ])
      line.combineSegments()
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "zero"),
        (40..<60,  "one"),
        (60..<100, "zero"),
      ])

      line.set(45..<55, to: "two")
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "zero"),
        (40..<45,  "one"),
        (45..<55,  "two"),
        (55..<60,  "one"),
        (60..<100, "zero"),
      ])
      line.combineSegments()
      // swift-format-ignore
      XCTAssertSegments(line, [
        (0..<40,   "zero"),
        (40..<45,  "one"),
        (45..<55,  "two"),
        (55..<60,  "one"),
        (60..<100, "zero"),
      ])
    }
  }
}
