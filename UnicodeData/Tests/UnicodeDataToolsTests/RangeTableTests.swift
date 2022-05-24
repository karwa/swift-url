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

// FIXME: This file is not formatted because swift-format does something really nasty to the array literals.

import XCTest
import UnicodeDataTools

fileprivate func XCTAssertExpectedSpans<Bound, Element>(
  _ table: RangeTable<Bound, Element>,
  _ expected: [(Range<Bound>, Element)]
) where Bound: Comparable, Element: Equatable {

  var expectedIter = expected.makeIterator()
  for (actualRange, actualValue) in table.spans {
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

  XCTAssertEqual(expected.count, table.spans.count)
  XCTAssertEqual(expected.isEmpty, table.spans.isEmpty)
}


// --------------------------------------------
// MARK: - RangeTableTests
// --------------------------------------------


class RangeTableTests: XCTestCase {}

extension RangeTableTests {

  func testDocumentationExamples() {

    do {
      var table = RangeTable<Int, String?>(bounds: 0..<100, initialValue: nil)

      table.set(0..<20, to: "small")
      table.set(0..<1, to: "tiny")
      table.set(10..<60, to: "big")

      XCTAssertEqual(
        table.description,
        #"| [0..<1]: Optional("tiny") | [1..<10]: Optional("small") | [10..<60]: Optional("big") | [60..<100]: nil |"#
      )
    }

    do {
      enum DetectedFeature {
        case personsName
      }

      let string = "Bob is feeling great"
      var table = RangeTable(
        bounds: string.startIndex..<string.endIndex,
        initialValue: DetectedFeature?.none
      )

      // Perhaps we detect a person's name in the string.
      let detectedName: Substring = string.prefix(3)
      table.set(
        detectedName.startIndex..<detectedName.endIndex,
        to: .personsName
      )

      let toSubstring = table.spans.map { range, feature in (string[range], feature) }
      let expected: [(String, DetectedFeature?)] = [
        ("Bob", DetectedFeature.personsName),
        (" is feeling great", nil),
      ]
      XCTAssertTrue(toSubstring.elementsEqual(expected, by: { $0.0 == $1.0 && $0.1 == $1.1 }))
    }
  }

  func testInitWithBoundsAndValue() {

    // Simple state with non-empty range.
    do {
      let table = RangeTable<Int, Int>(bounds: 0..<100, initialValue: 42)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<100, 42)
      ])
    }

    // The bounds are allowed to be empty.
    // There will still be a span, with a value (but empty range).
    do {
      let table = RangeTable<Int, Int>(bounds: 100..<100, initialValue: 42)
      XCTAssertEqual(table.bounds, 100..<100)
      XCTAssertExpectedSpans(table, [
        (100..<100, 42)
      ])
    }
  }
}


// --------------------------------------------
// MARK: - set(_:to:)
// --------------------------------------------


extension RangeTableTests {

  func testSet_simple() {

    // Setting the entire bounds.
    do {
      var table = RangeTable<Int, Int>(bounds: 0..<100, initialValue: 42)

      table.set(table.bounds, to: 99)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<100, 99)
      ])
    }

    // Setting the entire bounds (Empty bounds).
    do {
      // FIXME: This traps, because technically nothing is "in-bounds" when the bounds are empty. Worth changing?
      // var table = RangeTable<Int, Int>(bounds: 100..<100, initialValue: 42)
      // table.set(table.bounds, to: 99)
      //
      // XCTAssertEqual(table.bounds, 100..<100)
      // XCTAssertExpectedSpans(table, [
      //   (100..<100, 99)
      // ])
    }

    // Setting a region from lowerBound.
    do {
      var table = RangeTable<Int, Int>(bounds: 0..<100, initialValue: 42)

      table.set(0..<64, to: -99)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<64, -99),
        (64..<100, 42),
      ])

      table.set(0..<32, to: -64)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<32, -64),
        (32..<64, -99),
        (64..<100, 42),
      ])

      table.set(0..<16, to: -48)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<16, -48),
        (16..<32, -64),
        (32..<64, -99),
        (64..<100, 42),
      ])
    }

    // Setting a region from upperBound.
    do {
      var table = RangeTable<Int, Int>(bounds: 0..<100, initialValue: 42)

      table.set(32..<100, to: -99)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<32, 42),
        (32..<100, -99),
      ])

      table.set(50..<100, to: -64)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<32, 42),
        (32..<50, -99),
        (50..<100, -64),
      ])

      table.set(75..<100, to: -48)
      XCTAssertEqual(table.bounds, 0..<100)
      XCTAssertExpectedSpans(table, [
        (0..<32, 42),
        (32..<50, -99),
        (50..<75, -64),
        (75..<100, -48),
      ])
    }

    // Setting a region in the middle of the bounds.
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "*")

      table.set(20..<80, to: "XX")
      XCTAssertExpectedSpans(table, [
        (00..<20, "*"),
        (20..<80, "XX"),
        (80..<100, "*")
      ])

      table.set(40..<60, to: "+++")
      XCTAssertExpectedSpans(table, [
        (00..<20, "*"),
        (20..<40, "XX"),
        (40..<60, "+++"),
        (60..<80, "XX"),
        (80..<100, "*")
      ])

      table.set(45..<55, to: "<><>")
      XCTAssertExpectedSpans(table, [
        (00..<20, "*"),
        (20..<40, "XX"),
        (40..<45, "+++"),
        (45..<55, "<><>"),
        (55..<60, "+++"),
        (60..<80, "XX"),
        (80..<100, "*")
      ])
    }

    // Setting multiple regions in-order without overlap
    do {
      var table = RangeTable<UInt32, String>(bounds: 0..<0x11_0000, initialValue: "<Unicode>")
      table.set(0x00_0000..<0x00_0080, to: "ASCII")
      table.set(0x00_0080..<0x01_0000, to: "BMP")
      table.set(0x01_0000..<0x02_0000, to: "SMP")

      XCTAssertEqual(table.bounds, 0..<0x11_0000)
      XCTAssertExpectedSpans(table, [
        (0..<128, "ASCII"),
        (128..<65536, "BMP"),
        (65536..<131072, "SMP"),
        (131072..<1114112, "<Unicode>"),
      ])
    }
  }

  func testSet_acrossSpans() {

    // Setting across existing spans.
    // - Not anchored to start/end of table.
    // - Neither endpoint matches an existing span boundary.
    //
    //      V-----V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "C")
      table.set(0..<30, to: "A")
      table.set(30..<60, to: "B")
      XCTAssertExpectedSpans(table, [
        (0..<30, "A"),
        (30..<60, "B"),
        (60..<100, "C"),
      ])

      table.set(20..<40, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "X"),
        (40..<60, "B"),
        (60..<100, "C"),
      ])

      // Split the A-X and X-B boundaries.
      table.set(10..<30, to: "+")
      XCTAssertExpectedSpans(table, [
        (0..<10, "A"),
        (10..<30, "+"),
        (30..<40, "X"),
        (40..<60, "B"),
        (60..<100, "C"),
      ])

      table.set(35..<50, to: "-")
      XCTAssertExpectedSpans(table, [
        (0..<10, "A"),
        (10..<30, "+"),
        (30..<35, "X"),
        (35..<50, "-"),
        (50..<60, "B"),
        (60..<100, "C"),
      ])

      // Set over lots of boundaries.
      table.set(20..<90, to: ":)")
      XCTAssertExpectedSpans(table, [
        (0..<10, "A"),
        (10..<20, "+"),
        (20..<90, ":)"),
        (90..<100, "C"),
      ])
    }
    do {
      var table = RangeTable<Int, String>(bounds: 0..<160, initialValue: "-")
      table.set(0..<20, to: "A")
      table.set(20..<40, to: "B")
      table.set(40..<60, to: "C")
      table.set(60..<80, to: "D")
      table.set(80..<100, to: "E")
      table.set(100..<120, to: "F")
      table.set(120..<140, to: "G")
      table.set(140..<160, to: "H")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<60, "C"),
        (60..<80, "D"),
        (80..<100, "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      table.set(25..<125, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<25, "B"),
        (25..<125, "X"),
        (125..<140, "G"),
        (140..<160, "H"),
      ])

      // Empty range.
      table.set(22..<22, to: "?")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<25, "B"),
        (25..<125, "X"),
        (125..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Setting across existing spans.
    // - May be anchored to start/end of table.
    // - Both endpoints match existing span boundaries.
    //
    //         V-------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "C")
      table.set(0..<30, to: "A")
      table.set(30..<60, to: "B")
      XCTAssertExpectedSpans(table, [
        (0..<30, "A"),
        (30..<60, "B"),
        (60..<100, "C"),
      ])

      table.set(30..<60, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<30, "A"),
        (30..<60, "X"),
        (60..<100, "C"),
      ])
      table.set(0..<30, to: "+")
      XCTAssertExpectedSpans(table, [
        (0..<30, "+"),
        (30..<60, "X"),
        (60..<100, "C"),
      ])
      table.set(60..<100, to: "-")
      XCTAssertExpectedSpans(table, [
        (0..<30, "+"),
        (30..<60, "X"),
        (60..<100, "-"),
      ])

      // Combine multiple spans.
      table.set(0..<60, to: ":)")
      XCTAssertExpectedSpans(table, [
        (0..<60, ":)"),
        (60..<100, "-"),
      ])
      table.set(0..<100, to: "!")
      XCTAssertExpectedSpans(table, [
        (0..<100, "!"),
      ])
    }
    do {
      var table = RangeTable<Int, String>(bounds: 0..<160, initialValue: "-")
      table.set(0..<20, to: "A")
      table.set(20..<40, to: "B")
      table.set(40..<60, to: "C")
      table.set(60..<80, to: "D")
      table.set(80..<100, to: "E")
      table.set(100..<120, to: "F")
      table.set(120..<140, to: "G")
      table.set(140..<160, to: "H")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<60, "C"),
        (60..<80, "D"),
        (80..<100, "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])
      table.set(40..<120, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<120, "X"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      // Empty range.
      table.set(40..<40, to: "?")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<120, "X"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Setting across existing spans.
    // - Lowerbound is anchored to start of table.
    // - Upperbound is not an existing span boundary.
    //
    // V-----------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "C")
      table.set(0..<30, to: "A")
      table.set(30..<60, to: "B")
      XCTAssertExpectedSpans(table, [
        (0..<30, "A"),
        (30..<60, "B"),
        (60..<100, "C"),
      ])

      table.set(0..<40, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<40, "X"),
        (40..<60, "B"),
        (60..<100, "C"),
      ])
    }
    do {
      var table = RangeTable<Int, String>(bounds: 0..<160, initialValue: "-")
      table.set(0..<20, to: "A")
      table.set(20..<40, to: "B")
      table.set(40..<60, to: "C")
      table.set(60..<80, to: "D")
      table.set(80..<100, to: "E")
      table.set(100..<120, to: "F")
      table.set(120..<140, to: "G")
      table.set(140..<160, to: "H")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<60, "C"),
        (60..<80, "D"),
        (80..<100, "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      table.set(0..<125, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<125, "X"),
        (125..<140, "G"),
        (140..<160, "H"),
      ])
    }

    // Setting across existing spans.
    // - Lowerbound is not an existing span boundary.
    // - Upperbound is anchored to end of table.
    //
    //             V-----------V
    // |AAAAAAA|BBBBBBB|CCCCCCC|
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "C")
      table.set(0..<30, to: "A")
      table.set(30..<60, to: "B")
      XCTAssertExpectedSpans(table, [
        (0..<30, "A"),
        (30..<60, "B"),
        (60..<100, "C"),
      ])

      table.set(50..<100, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<30, "A"),
        (30..<50, "B"),
        (50..<100, "X"),
      ])
    }
    do {
      var table = RangeTable<Int, String>(bounds: 0..<160, initialValue: "-")
      table.set(0..<20, to: "A")
      table.set(20..<40, to: "B")
      table.set(40..<60, to: "C")
      table.set(60..<80, to: "D")
      table.set(80..<100, to: "E")
      table.set(100..<120, to: "F")
      table.set(120..<140, to: "G")
      table.set(140..<160, to: "H")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<60, "C"),
        (60..<80, "D"),
        (80..<100, "E"),
        (100..<120, "F"),
        (120..<140, "G"),
        (140..<160, "H"),
      ])

      table.set(50..<160, to: "X")
      XCTAssertExpectedSpans(table, [
        (0..<20, "A"),
        (20..<40, "B"),
        (40..<50, "C"),
        (50..<160, "X"),
      ])
    }
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension RangeTableTests {

  func testEquatable() {

    let _tableOne: RangeTable<UInt32, String>
    let _tableTwo: RangeTable<UInt32, String>

    // Simple construction - assigning ranges with no overlaps.
    do {
      var table = RangeTable<UInt32, String>(bounds: 0..<0x11_0000, initialValue: "<Unicode>")
      table.set(0..<0x80, to: "ASCII")
      table.set(0x00_0080..<0x01_0000, to: "BMP")
      table.set(0x01_0000..<0x02_0000, to: "SMP")

      XCTAssertExpectedSpans(table, [
        (0..<0x80, "ASCII"),
        (0x80..<0x01_0000, "BMP"),
        (0x01_0000..<0x02_0000, "SMP"),
        (0x02_0000..<0x11_0000, "<Unicode>"),
      ])

      _tableOne = table
    }

    // More elaborate construction.
    do {
      var table = RangeTable<UInt32, String>(bounds: 0..<0x11_0000, initialValue: "<Unicode>")

      table.set(0..<10, to: "<10")
      table.set(5..<10, to: ">5")
      XCTAssertExpectedSpans(table, [
        (0..<5, "<10"),
        (5..<10, ">5"),
        (10..<0x11_0000, "<Unicode>"),
      ])

      table.set(0x00_0000..<0x01_0000, to: "BMP")
      XCTAssertExpectedSpans(table, [
        (0..<0x01_0000, "BMP"),
        (0x01_0000..<0x11_0000, "<Unicode>"),
      ])

      table.set(0x01_0000..<0x02_0000, to: "SMP")
      table.set(0..<0x80, to: "ASCII")
      XCTAssertExpectedSpans(table, [
        (0..<0x80, "ASCII"),
        (0x80..<0x01_0000, "BMP"),
        (0x01_0000..<0x02_0000, "SMP"),
        (0x02_0000..<0x11_0000, "<Unicode>"),
      ])

      _tableTwo = table
    }

    // Even though we built these tables up in very different ways,
    // they both have the exact same set of regions and data.

    XCTAssertExpectedSpans(_tableOne, [
      (0..<0x80, "ASCII"),
      (0x80..<0x01_0000, "BMP"),
      (0x01_0000..<0x02_0000, "SMP"),
      (0x02_0000..<0x11_0000, "<Unicode>"),
    ])
    XCTAssertExpectedSpans(_tableTwo, [
      (0..<0x80, "ASCII"),
      (0x80..<0x01_0000, "BMP"),
      (0x01_0000..<0x02_0000, "SMP"),
      (0x02_0000..<0x11_0000, "<Unicode>"),
    ])
    XCTAssert(_tableOne == _tableTwo)
  }

  func testCustomStringConvertible() {
    do {
      let table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "<default>")
      let description = table.description
      XCTAssertEqual(description, #"| [0..<100]: <default> |"#)
    }
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "<low>")
      table.set(50..<100, to: "hi 👋")
      let description = table.description
      XCTAssertEqual(description, #"| [0..<50]: <low> | [50..<100]: hi 👋 |"#)
    }
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "<default>")
      table.set(20..<40, to: "hello")
      let description = table.description
      XCTAssertEqual(description, #"| [0..<20]: <default> | [20..<40]: hello | [40..<100]: <default> |"#)
    }
  }
}


// --------------------------------------------
// MARK: - Table Optimization
// --------------------------------------------


extension RangeTableTests {

  func testMapElements() {
    var table = RangeTable<UInt32, String>(bounds: 0..<0x11_0000, initialValue: "<Unicode>")
    table.set(0..<0x80, to: "ASCII")
    table.set(0x00_0080..<0x01_0000, to: "BMP")
    table.set(0x01_0000..<0x02_0000, to: "SMP")

    XCTAssertExpectedSpans(table, [
      (0..<0x80, "ASCII"),
      (0x80..<0x01_0000, "BMP"),
      (0x01_0000..<0x02_0000, "SMP"),
      (0x02_0000..<0x11_0000, "<Unicode>"),
    ])

    let mappedTable: RangeTable<UInt32, String> = table.mapElements { name in "*-*\(name.lowercased())*-*" }
    XCTAssertEqual(table.bounds, mappedTable.bounds)
    XCTAssertExpectedSpans(mappedTable, [
      (0..<0x80, "*-*ascii*-*"),
      (0x80..<0x01_0000, "*-*bmp*-*"),
      (0x01_0000..<0x02_0000, "*-*smp*-*"),
      (0x02_0000..<0x11_0000, "*-*<unicode>*-*"),
    ])
    // The original table should be left unchanged.
    XCTAssertExpectedSpans(table, [
      (0..<0x80, "ASCII"),
      (0x80..<0x01_0000, "BMP"),
      (0x01_0000..<0x02_0000, "SMP"),
      (0x02_0000..<0x11_0000, "<Unicode>"),
    ])

    // No span optimizations are performed.
    let everythingMapsToUnity: RangeTable<UInt32, UInt8> = table.mapElements { _ in 1 }
    XCTAssertExpectedSpans(everythingMapsToUnity, [
      (0..<0x80, 1),
      (0x80..<0x01_0000, 1),
      (0x01_0000..<0x02_0000, 1),
      (0x02_0000..<0x11_0000, 1),
    ])
  }

  func testMergeElements() {
    // RangeTable does not require that its element is Equatable, and offers no automatic merging if it is.
    // As a result, we can have lots of spans that are all tagged with the same value.
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "zero")

      table.set(20..<80, to: "zero")
      table.set(40..<60, to: "zero")
      table.set(45..<55, to: "zero")
      XCTAssertExpectedSpans(table, [
        (0..<20, "zero"),
        (20..<40, "zero"),
        (40..<45, "zero"),
        (45..<55, "zero"),
        (55..<60, "zero"),
        (60..<80, "zero"),
        (80..<100, "zero")
      ])

      table.mergeElements()
      XCTAssertExpectedSpans(table, [
        (0..<100, "zero"),
      ])
    }
    // Empty table.
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "zero")
      XCTAssertExpectedSpans(table, [
        (0..<100, "zero")
      ])

      table.mergeElements()
      XCTAssertExpectedSpans(table, [
        (0..<100, "zero")
      ])
    }
    // Merging is driven by the predicate.
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "zero")

      table.set(20..<80, to: "zero")
      table.set(40..<60, to: "zero")
      table.set(45..<55, to: "zero")
      XCTAssertExpectedSpans(table, [
        (0..<20, "zero"),
        (20..<40, "zero"),
        (40..<45, "zero"),
        (45..<55, "zero"),
        (55..<60, "zero"),
        (60..<80, "zero"),
        (80..<100, "zero")
      ])

      table.mergeElements(where: { _, _ in false })
      XCTAssertExpectedSpans(table, [
        (0..<20, "zero"),
        (20..<40, "zero"),
        (40..<45, "zero"),
        (45..<55, "zero"),
        (55..<60, "zero"),
        (60..<80, "zero"),
        (80..<100, "zero")
      ])

      table.set(40..<60, to: "one")
      XCTAssertExpectedSpans(table, [
        (0..<20, "zero"),
        (20..<40, "zero"),
        (40..<60, "one"),
        (60..<80, "zero"),
        (80..<100, "zero")
      ])

      table.mergeElements(where: { _, _ in true })
      XCTAssertExpectedSpans(table, [
        (0..<100, "zero")
      ])
    }
    // Duplicates at the start/end of the table.
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "zero")

      table.set(20..<80, to: "zero")
      table.set(40..<60, to: "one")
      XCTAssertExpectedSpans(table, [
        (0..<20, "zero"),
        (20..<40, "zero"),
        (40..<60, "one"),
        (60..<80, "zero"),
        (80..<100, "zero")
      ])

      table.mergeElements()
      XCTAssertExpectedSpans(table, [
        (0..<40, "zero"),
        (40..<60, "one"),
        (60..<100, "zero")
      ])
    }
    // Another, slightly more complex pattern.
    do {
      var table = RangeTable<Int, String>(bounds: 0..<100, initialValue: "zero")

      table.set(10..<90, to: "zero")
      table.set(20..<80, to: "zero")
      table.set(30..<70, to: "zero")
      table.set(40..<60, to: "zero")
      XCTAssertExpectedSpans(table, [
        (0..<10, "zero"),
        (10..<20, "zero"),
        (20..<30, "zero"),
        (30..<40, "zero"),
        (40..<60, "zero"),
        (60..<70, "zero"),
        (70..<80, "zero"),
        (80..<90, "zero"),
        (90..<100, "zero")
      ])

      table.set(20..<30, to: "one")
      table.set(70..<80, to: "one")
      table.set(90..<100, to: "one")
      XCTAssertExpectedSpans(table, [
        (0..<10, "zero"),
        (10..<20, "zero"),
        (20..<30, "one"),
        (30..<40, "zero"),
        (40..<60, "zero"),
        (60..<70, "zero"),
        (70..<80, "one"),
        (80..<90, "zero"),
        (90..<100, "one")
      ])

      table.mergeElements()
      XCTAssertExpectedSpans(table, [
        (0..<20, "zero"),
        (20..<30, "one"),
        (30..<70, "zero"),
        (70..<80, "one"),
        (80..<90, "zero"),
        (90..<100, "one")
      ])
    }
  }
}


// --------------------------------------------
// MARK: - Collection Tagging
// --------------------------------------------


extension RangeTableTests {

  func testCollectionTagging() {

    /// A DIY AttributedString from a `{ Collection, RangeTable<Collection.Index, Tag?> }` pair.
    ///
    struct MyAttributedString<Tag> {

      var str: String {
        // Reset all tags any time the string changes (because our indexes become invalid).
        // Obviously not ideal and in a real AttributedString we wouldn't provide direct, mutable access to this.
        didSet { tags = .init(bounds: str.startIndex..<str.endIndex, initialValue: nil) }
      }

      var tags: RangeTable<String.Index, Tag?>

      init() {
        str = ""
        tags = .init(bounds: str.startIndex..<str.endIndex, initialValue: nil)
      }

      var regions: [(Substring, Tag?)] {
        tags.spans.map { range, value in (str[range], value) }
      }
    }

    var s = MyAttributedString<Int>()
    s.str = "hello, world!"
    s.tags.set(s.str.startIndex..<s.str.dropFirst(5).startIndex, to: 42)
    s.tags.set(s.str.dropLast(5).endIndex..<s.str.endIndex, to: -1)

    let expected: [(Substring, Int?)] = [
      ("hello", 42),
      (", w", nil),
      ("orld!", -1),
    ]
    XCTAssertTrue(s.regions.elementsEqual(expected, by: { $0.0 == $1.0 && $0.1 == $1.1 }))
  }
}
