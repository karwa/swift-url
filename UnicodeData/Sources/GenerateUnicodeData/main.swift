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

import Foundation

// --------------------------------------------
// MARK: - Parse Data File
// --------------------------------------------


// - Load the mapping table.

let mappingTableURL = Bundle.module.url(forResource: "TableDefinitions/IdnaMappingTable", withExtension: "txt")!
let entireMappingTable = try String(contentsOf: mappingTableURL)

// - Parse the entries.
//   We do a bit of optimization here already, by merging contiguous entries as they are appended to the table
//   and collapsing contiguous mappings. This can reduce 1/3 of entries (from ~9000 to 6000).

var rawEntries = [RawMappingTableEntry]()
for line in entireMappingTable.split(separator: "\n").filter({ !$0.starts(with: "#") }) {

  let data = line.prefix { $0 != "#" }
  let comment = line[data.endIndex...].dropFirst()

  guard let entry = RawMappingTableEntry(parsing: data) else {
    fatalError(
      """
      ⚠️ Failed to Parse Entry in Mapping Data! ⚠️
      line: \(line)
      data: \(data)
      comment: \(comment)
      """
    )
  }

  if let last = rawEntries.last, let merged = last.tryMerge(with: entry) {
    rawEntries[rawEntries.index(before: rawEntries.endIndex)] = merged
  } else {
    rawEntries.append(entry)
  }
}


// --------------------------------------------
// MARK: - Process, Optimize
// --------------------------------------------


// - Split the raw mapping data in to separate tables:

// The replacements table.
//
// Contains all of the mappings. For example, 1 scalar can sometimes map to as many as 18 replacement scalars.
// The replacements get de-duped and collected in a flat array, and mapping entries can refer to their data
// using the (offset, length) in this table. The (offset, length) info is otherwise known as a ReplacementsTable.Index.

var replacements = ReplacementsTable.Builder()

extension MappingTableEntry.Mapping {

  static func singleOrTable(_ raw: [UInt32], replacements: inout ReplacementsTable.Builder) -> Self {
    if raw.count == 1 {
      return .single(raw.first!)
    } else {
      precondition(raw.count > 1, "Raw mapping should not be empty")
      return .table(replacements.insert(mapping: raw))
    }
  }
}

// Mapping entries.
//
// For every scalar, contains the status and ReplacementsTable.Index, if there is a corresponding mapping.
// There are ~6000 entries. With a binary search, that means 13 steps to find any element.
// It can help a little bit to break the tables up in to some manually-unrolled, easily predictable branches:
//
// bmpXEntries        | Plane 0      | The Basic Multilingual Plane (BMP)
// ideographicEntries | Plane 1 - 3  | Historic Scripts, Emoji, and CJK Unified Ideograph Extensions
// otherEntries       | Plane 4 - 16 | Other (Unassigned, Private Use, etc)
//
// The BMP itself is also broken up in to 3 sections:
//
// 0 | 0x0000 ... 0x0FFF | 35 blocks, including Basic Latin, Latin-1, Greek, Cyrillic, Hebrew, Arabic, Devangali, etc.
// 1 | 0x1000 ... 0x2E7F | 69 blocks, including Cherokee, Runic, Phillipine scripts, extensions, symbols - currency, etc.
// 2 | 0x2E80 ... 0xFFFF | CJK scripts, including Hiragana, Katakana, CJK Unified Ideographs, Hangul Syllables, etc.
//
// These each have ~1000, 1000, and 2500 entries respectively.
//
// These unrolled branches, which map a scalar to one of these smaller tables, are part of the function
// `_idna_mapping_data_for_scalar`, which is emitted alongside the data.

var bmp0Entries = [MappingTableEntry]()
var bmp1Entries = [MappingTableEntry]()
var bmp2Entries = [MappingTableEntry]()
var ideographicEntries = [MappingTableEntry]()
var otherEntries = [MappingTableEntry]()

for rawEntry in rawEntries {

  // Insert mappings in to the replacements table to get the final status for this range of codepoints.

  let status: MappingTableEntry.Status
  switch rawEntry.status {
  case .valid:
    status = .valid
  case .ignored:
    status = .ignored
  case .disallowed:
    status = .disallowed
  case .disallowed_STD3_valid:
    status = .disallowed_STD3_valid
  case .deviation:
    status = .deviation(rawEntry.mapping.map { .singleOrTable($0, replacements: &replacements) })
  case .disallowed_STD3_mapped:
    status = .disallowed_STD3_mapped(.singleOrTable(rawEntry.mapping!, replacements: &replacements))
  case .mapped:
    status = .mapped(.singleOrTable(rawEntry.mapping!, replacements: &replacements))
  case .mapped_rebased:
    status = .mapped(.rebased(origin: rawEntry.mapping!.first!))
  }

  // Insert the status at the appropriate positions across our multiple tables.
  // Essentially this means: at the place where the entry starts, and if it crosses in to any other tables,
  // it should also insert an entry at the table start point.

  func insertInSplitTable(range: ClosedRange<UInt32>, table: inout [MappingTableEntry]) {
    let codePoints = rawEntry.codePoints
    if codePoints.contains(range.lowerBound) {
      assert(table.isEmpty)
      table.append(MappingTableEntry(lowerBound: range.lowerBound, status: status))
    } else if range.contains(codePoints.lowerBound) {
      assert(!table.isEmpty)
      table.append(MappingTableEntry(lowerBound: codePoints.lowerBound, status: status))
    }
  }

  insertInSplitTable(range: 0x000000...0x000FFF, table: &bmp0Entries)
  insertInSplitTable(range: 0x001000...0x002E7F, table: &bmp1Entries)
  insertInSplitTable(range: 0x002E80...0x00FFFF, table: &bmp2Entries)
  insertInSplitTable(range: 0x010000...0x03FFFF, table: &ideographicEntries)
  insertInSplitTable(range: 0x040000...0x10FFFF, table: &otherEntries)
}


// --------------------------------------------
// MARK: - Write
// --------------------------------------------


// TODO: Include IDNA table version in output file

var output =
  #"""
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

  // ---------------------------------------------
  //                 DO NOT MODIFY
  // ---------------------------------------------
  // Generated by GenerateUnicodeData

  """# + "\n"

// Print the replacements table.

printArrayLiteral(
  name: "_idna_replacements_table",
  elementType: "Unicode.Scalar",
  data: replacements.buildReplacementsTable(),
  columns: 8,
  formatter: { #""\u{\#($0.unprefixedHexString(format: .padded(toLength: 6)))}""# },
  to: &output
)
output += "\n"

output +=
  """
  @usableFromInline
  internal typealias MappingTableEntry_Storage = UInt64\n
  """
output += "\n"

output +=
  #"""
  // swift-format-ignore
  @inlinable
  internal func _idna_mapping_data_for_scalar(_ scalar: Unicode.Scalar) -> [MappingTableEntry_Storage] {
    let value = scalar.value
    if value <= 0xFFFF {
      // BMP.
      if value <= 0x0FFF {
        return _idna_mapping_data_bmp0
      } else if value <= 0x2E7F {
        return _idna_mapping_data_bmp1
      } else {
        return _idna_mapping_data_bmp2
      }
    } else if value <= 0x3FFFF {
      // SMP, SIP, TIP.
      return _idna_mapping_data_ideographic
    } else {
      // SSP, SPUA-A/B.
      return _idna_mapping_data_other
    }
  }
  """# + "\n"
output += "\n"

for (table, name) in [
  (bmp0Entries, "_idna_mapping_data_bmp0"),
  (bmp1Entries, "_idna_mapping_data_bmp1"),
  (bmp2Entries, "_idna_mapping_data_bmp2"),
  (ideographicEntries, "_idna_mapping_data_ideographic"),
  (otherEntries, "_idna_mapping_data_other"),
] {
  printArrayLiteral(
    name: name,
    elementType: "MappingTableEntry_Storage",
    data: table, columns: 5,
    formatter: { $0._storage.hexString(format: .fullWidth) },
    to: &output
  )
  output += "\n"
}

// Print to stdout.

precondition(output.last == "\n")
output.removeLast()

print(output)
