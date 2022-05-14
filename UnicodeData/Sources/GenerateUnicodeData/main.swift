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

for entry in rawEntries {

  // Insert mappings in to the replacements table.

  let processedStatus: MappingTableEntry.Status
  switch entry.status {
  case .valid:
    processedStatus = .valid
  case .ignored:
    processedStatus = .ignored
  case .disallowed:
    processedStatus = .disallowed
  case .disallowed_STD3_valid:
    processedStatus = .disallowed_STD3_valid
  case .deviation:
    guard let mapping = entry.mapping else {
      processedStatus = .deviation(nil)
      break
    }
    if mapping.count == 1 {
      processedStatus = .deviation(.single(mapping.first!))
    } else {
      processedStatus = .deviation(.table(replacements.insert(mapping: mapping)))
    }
  case .disallowed_STD3_mapped:
    guard let mapping = entry.mapping else { fatalError("Expected mapping") }
    if mapping.count == 1 {
      processedStatus = .disallowed_STD3_mapped(.single(mapping.first!))
    } else {
      processedStatus = .disallowed_STD3_mapped(.table(replacements.insert(mapping: mapping)))
    }
  case .mapped:
    guard let mapping = entry.mapping else { fatalError("Expected mapping") }
    if mapping.count == 1 {
      processedStatus = .mapped(.single(mapping.first!))
    } else {
      processedStatus = .mapped(.table(replacements.insert(mapping: mapping)))
    }
  case .mapped_rebased:
    guard let mapping = entry.mapping else { fatalError("Expected mapping") }
    processedStatus = .mapped(.rebased(origin: mapping.first!))
    break
  }

  // Insert the data from the entry in as many sub-tables as appropriate,
  // splitting entries on table boundaries if necessary.

  let lowerBoundPlane = entry.codePoints.lowerBound >> 16
  let unalignedEntry = MappingTableEntry(codePoints: entry.codePoints, status: processedStatus)

  switch lowerBoundPlane {
  case 0:
    // First, split BMP/ideographic codepoints.
    let (bmp, ideographic) = unalignedEntry.split(at: 0x10000)
    if let ideographic = ideographic {
      precondition(ideographic.codePoints.upperBound < 0x40000, "Single range covers entire ideographic space?!")
      ideographicEntries.append(ideographic)
    }
    // Then split the BMP entry in to BMP0/1/2.
    let (bmp0, rest) = bmp!.split(at: 0x1000)
    if let bmp0 = bmp0 { bmp0Entries.append(bmp0) }
    if let rest = rest {
      let (bmp1, bmp2) = rest.split(at: 0x2E80)
      if let bmp1 = bmp1 { bmp1Entries.append(bmp1) }
      if let bmp2 = bmp2 { bmp2Entries.append(bmp2) }
    }
  case 1, 2, 3:
    let (ideographic, other) = unalignedEntry.split(at: 0x40000)
    ideographicEntries.append(ideographic!)
    if let other = other { otherEntries.append(other) }
  default:
    otherEntries.append(unalignedEntry)
  }
}

extension MappingTableEntry {

  /// Splits this mapping table entry at the given code-point value.
  ///
  /// The result is a tuple of 2 optional mapping entries:
  ///
  /// - `lessThan` will contain codepoints in the range `lowerBound ... (firstNotIncluded - 1)`, if there are any.
  /// - `greaterThanOrEqual` will contain codepoints in the range `firstNotIncluded ... upperBound`, if there are any.
  ///
  /// Both of these mapping entries inherit their mapping information from this (the original) entry.
  /// It just expresses the same status for the same codepoints in 2 entries rather than 1.
  ///
  func split(
    at firstNotIncluded: UInt32
  ) -> (lessThan: MappingTableEntry?, greaterThanOrEqual: MappingTableEntry?) {

    let lowerIsWithin = self.codePoints.lowerBound < firstNotIncluded
    let upperIsWithin = self.codePoints.upperBound < firstNotIncluded
    switch (lowerIsWithin, upperIsWithin) {
    case (true, true):
      return (lessThan: self, greaterThanOrEqual: nil)
    case (false, false):
      return (lessThan: nil, greaterThanOrEqual: self)
    case (true, false):
      let status = self.status
      let lowerCodepoints = self.codePoints.lowerBound...(firstNotIncluded - 1)
      let upperCodepoints = firstNotIncluded...self.codePoints.upperBound
      return (
        lessThan: MappingTableEntry(codePoints: lowerCodepoints, status: status),
        greaterThanOrEqual: MappingTableEntry(codePoints: upperCodepoints, status: status)
      )
    case (false, true):
      fatalError("upperBound > lowerBound")
    }
  }
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
