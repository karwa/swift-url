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

@testable import UnicodeDataStructures

final class IndexedTableTests: XCTestCase {}

// TODO: Very small datasets might fatalError when building the index.
//       Not a problem for the Unicode tables, but should probably be addressed at some point just because.

extension IndexedTableTests {

  func testTunableIndexSize() {

    // Take some location/data arrays and index them with a variety of precision values (4/5/6/8 bits).
    // Perform some lookups and check that it identifies the correct range of the table.

    // Limitations on the input data:
    //
    // - count must be lower than UInt8.max
    // - must not have duplicate locations, locations array must be sorted
    // - otherwise, locations and data can be anything.
    //
    // We use UInt16 locations because they are small enough that we can actually see some variation
    // in the bits we index; you need really big, far apart numbers to see variation in the top 4 bits
    // of a 64-bit integer.

    let columnVals: [UInt16] = [
      0, 1, 2, 5, 10, 54, 55, 101, 102, 103, 200, 400, 600, 800, 1000, 2000, 4000,
      5001, 5002, 5003, 6000, 7000, 8000, 9000, 10000, 11000, 12000, 13000, 14000, 15000,
      16000, 17000, 18000, 18500, 19000, 20000, 21000, 21500, 22000, 23000, 24000, 25000,
      32000, 34000, 36000, 36500, 38000, 40000, 42000, 42500, 44000, 46000, 48000, 50000,
      52000, 54000, 56000, 56500, 58000, 60000, 62000, 62500, 64000,
    ]
    let dataVals = columnVals.map { _ in "\(Bool.random())" }

    // 4 bits.
    do {
      struct Schema: IndexedTableSchema {
        typealias Column = UInt16
        typealias IndexStorage = UInt8
        static var ColumnBitsToIndex: Int { 4 }
      }

      let index = IndexedTable<Schema, String>.buildIndex(columnVals)
      XCTAssertEqual(index, [0, 16, 22, 26, 30, 35, 40, 41, 42, 45, 47, 50, 52, 54, 57, 59, 62])

      let table = IndexedTable<Schema, String>(uncheckedIndex: index, columnValues: columnVals, dataValues: dataVals)
      table.validate()

      // Lookup a location with an exact match in the location table.
      table.lookupRows(containing: 42000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [40000, 42000, 42500, 44000])
        XCTAssertEqual(ArraySlice(loc), columnVals[47...50])
        XCTAssertEqual(ArraySlice(dat), dataVals[47...50])
      }
      // Lookup locations between values in the table.
      table.lookupRows(containing: 42) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [0, 1, 2, 5, 10, 54, 55, 101, 102, 103, 200, 400, 600, 800, 1000, 2000, 4000])
        XCTAssertEqual(ArraySlice(loc), columnVals[0...16])
        XCTAssertEqual(ArraySlice(dat), dataVals[0...16])
      }
      table.lookupRows(containing: 37373) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [36500, 38000, 40000])
        XCTAssertEqual(ArraySlice(loc), columnVals[45...47])
        XCTAssertEqual(ArraySlice(dat), dataVals[45...47])
      }
      // Lookup around an index boundary (20480, or 0x5000).
      table.lookupRows(containing: 0x4FFF) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [16000, 17000, 18000, 18500, 19000, 20000])
        XCTAssertEqual(ArraySlice(loc), columnVals[30...35])
        XCTAssertEqual(ArraySlice(dat), dataVals[30...35])
      }
      table.lookupRows(containing: 0x5000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000, 21000, 21500, 22000, 23000, 24000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...40])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...40])
      }
      table.lookupRows(containing: 0x5001) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000, 21000, 21500, 22000, 23000, 24000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...40])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...40])
      }
    }

    // 5 bits.
    do {
      struct Schema: IndexedTableSchema {
        typealias Column = UInt16
        typealias IndexStorage = UInt8
        static var ColumnBitsToIndex: Int { 5 }
      }

      let index = IndexedTable<Schema, String>.buildIndex(columnVals)
      // swift-format-ignore
      XCTAssertEqual(index, [
        00, 15, 16, 20, 22, 24, 26, 28, 30, 32, 35, 38, 40, 41, 41, 41,
        42, 43, 45, 46, 47, 49, 50, 51, 52, 53, 54, 55, 57, 58, 59, 61, 62,
      ])

      let table = IndexedTable<Schema, String>(uncheckedIndex: index, columnValues: columnVals, dataValues: dataVals)
      table.validate()

      table.lookupRows(containing: 42000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [40000, 42000, 42500])
        XCTAssertEqual(ArraySlice(loc), columnVals[47...49])
        XCTAssertEqual(ArraySlice(dat), dataVals[47...49])
      }
      table.lookupRows(containing: 42) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [0, 1, 2, 5, 10, 54, 55, 101, 102, 103, 200, 400, 600, 800, 1000, 2000])
        XCTAssertEqual(ArraySlice(loc), columnVals[0...15])
        XCTAssertEqual(ArraySlice(dat), dataVals[0...15])
      }
      table.lookupRows(containing: 37373) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [36500, 38000])
        XCTAssertEqual(ArraySlice(loc), columnVals[45...46])
        XCTAssertEqual(ArraySlice(dat), dataVals[45...46])
      }
      table.lookupRows(containing: 0x4FFF) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [18000, 18500, 19000, 20000])
        XCTAssertEqual(ArraySlice(loc), columnVals[32...35])
        XCTAssertEqual(ArraySlice(dat), dataVals[32...35])
      }
      table.lookupRows(containing: 0x5000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000, 21000, 21500, 22000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...38])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...38])
      }
      table.lookupRows(containing: 0x5001) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000, 21000, 21500, 22000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...38])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...38])
      }
    }

    // 6 bits.
    do {
      struct Schema: IndexedTableSchema {
        typealias Column = UInt16
        typealias IndexStorage = UInt8
        static var ColumnBitsToIndex: Int { 6 }
      }

      let index = IndexedTable<Schema, String>.buildIndex(columnVals)
      // swift-format-ignore
      XCTAssertEqual(index, [
        00, 14, 15, 15, 16, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 34, 35, 37, 38, 39, 40, 41, 41, 41, 41, 41, 41, 41,
        42, 42, 43, 43, 45, 45, 46, 46, 47, 47, 49, 50, 50, 51, 51, 52,
        52, 53, 53, 54, 54, 55, 55, 56, 57, 58, 58, 59, 59, 60, 61, 62, 62,
      ])

      let table = IndexedTable<Schema, String>(uncheckedIndex: index, columnValues: columnVals, dataValues: dataVals)
      table.validate()

      table.lookupRows(containing: 42000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [40000, 42000, 42500])
        XCTAssertEqual(ArraySlice(loc), columnVals[47...49])
        XCTAssertEqual(ArraySlice(dat), dataVals[47...49])
      }
      table.lookupRows(containing: 42) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [0, 1, 2, 5, 10, 54, 55, 101, 102, 103, 200, 400, 600, 800, 1000])
        XCTAssertEqual(ArraySlice(loc), columnVals[0...14])
        XCTAssertEqual(ArraySlice(dat), dataVals[0...14])
      }
      table.lookupRows(containing: 37373) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [36500])
        XCTAssertEqual(ArraySlice(loc), columnVals[45...45])
        XCTAssertEqual(ArraySlice(dat), dataVals[45...45])
      }
      table.lookupRows(containing: 0x4FFF) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [19000, 20000])
        XCTAssertEqual(ArraySlice(loc), columnVals[34...35])
        XCTAssertEqual(ArraySlice(dat), dataVals[34...35])
      }
      table.lookupRows(containing: 0x5000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000, 21000, 21500])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...37])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...37])
      }
      table.lookupRows(containing: 0x5001) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000, 21000, 21500])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...37])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...37])
      }
    }

    // 8 bits.
    do {
      struct Schema: IndexedTableSchema {
        typealias Column = UInt16
        typealias IndexStorage = UInt8
        static var ColumnBitsToIndex: Int { 8 }
      }

      let index = IndexedTable<Schema, String>.buildIndex(columnVals)
      // swift-format-ignore
      XCTAssertEqual(index, [
        00, 10, 11, 12, 14, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 15,
        16, 16, 16, 16, 19, 19, 19, 19, 20, 20, 20, 20, 21, 21, 21, 21,
        22, 22, 22, 22, 23, 23, 23, 23, 24, 24, 24, 25, 25, 25, 25, 26,
        26, 26, 26, 27, 27, 27, 27, 28, 28, 28, 28, 29, 29, 29, 29, 30,
        30, 30, 30, 31, 31, 31, 31, 32, 32, 33, 33, 34, 34, 34, 34, 35,
        35, 35, 35, 36, 37, 37, 38, 38, 38, 38, 39, 39, 39, 39, 40, 40,
        40, 40, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41,
        41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 42, 42, 42,
        42, 42, 42, 42, 42, 43, 43, 43, 43, 43, 43, 43, 43, 44, 44, 45,
        45, 45, 45, 45, 45, 46, 46, 46, 46, 46, 46, 46, 46, 47, 47, 47,
        47, 47, 47, 47, 47, 48, 48, 49, 49, 49, 49, 49, 50, 50, 50, 50,
        50, 50, 50, 50, 51, 51, 51, 51, 51, 51, 51, 51, 52, 52, 52, 52,
        52, 52, 52, 52, 53, 53, 53, 53, 53, 53, 53, 53, 54, 54, 54, 54,
        54, 54, 54, 55, 55, 55, 55, 55, 55, 55, 55, 56, 56, 57, 57, 57,
        57, 57, 57, 58, 58, 58, 58, 58, 58, 58, 58, 59, 59, 59, 59, 59,
        59, 59, 59, 60, 60, 61, 61, 61, 61, 61, 62, 62, 62, 62, 62, 62, 62,
      ])

      let table = IndexedTable<Schema, String>(uncheckedIndex: index, columnValues: columnVals, dataValues: dataVals)
      table.validate()

      table.lookupRows(containing: 42000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [40000, 42000])
        XCTAssertEqual(ArraySlice(loc), columnVals[47...48])
        XCTAssertEqual(ArraySlice(dat), dataVals[47...48])
      }
      table.lookupRows(containing: 42) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [0, 1, 2, 5, 10, 54, 55, 101, 102, 103, 200])
        XCTAssertEqual(ArraySlice(loc), columnVals[0...10])
        XCTAssertEqual(ArraySlice(dat), dataVals[0...10])
      }
      table.lookupRows(containing: 37373) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [36500])
        XCTAssertEqual(ArraySlice(loc), columnVals[45...45])
        XCTAssertEqual(ArraySlice(dat), dataVals[45...45])
      }
      table.lookupRows(containing: 0x4FFF) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...35])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...35])
      }
      table.lookupRows(containing: 0x5000) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...35])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...35])
      }
      table.lookupRows(containing: 0x5001) { loc, dat in
        XCTAssertEqual(ArraySlice(loc), [20000])
        XCTAssertEqual(ArraySlice(loc), columnVals[35...35])
        XCTAssertEqual(ArraySlice(dat), dataVals[35...35])
      }
    }
  }
}
