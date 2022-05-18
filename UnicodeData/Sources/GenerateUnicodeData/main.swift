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


var rawEntries = [RawMappingTableEntry]()

do {
  // - Load the mapping table.
  let mappingTableURL = Bundle.module.url(forResource: "TableDefinitions/IdnaMappingTable", withExtension: "txt")!
  let mappingTable = try String(contentsOf: mappingTableURL)

  // - Parse the entries.
  for line in mappingTable.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
    let rawDataString = line.prefix { $0 != "#" }
    let comment = line[rawDataString.endIndex...].dropFirst()
    guard let entry = RawMappingTableEntry(parsing: rawDataString) else {
      fatalError(
        """
        ⚠️ Failed to Parse Entry in Mapping Data! ⚠️
        line: \(line)
        rawDataString: \(rawDataString)
        comment: \(comment)
        """
      )
    }
    // We do a bit of optimization here already, by merging contiguous entries as they are appended to the table
    // and collapsing contiguous mappings. This can remove 1/3 of entries (from ~9000 to 6000).
    if let last = rawEntries.last, let merged = last.tryMerge(with: entry) {
      rawEntries[rawEntries.index(before: rawEntries.endIndex)] = merged
    } else {
      rawEntries.append(entry)
    }
  }
}


// --------------------------------------------
// MARK: - Process, Optimize
// --------------------------------------------


// Split the raw mapping data in to separate tables:
//
// - The replacements table.
//
//   Contains all of the mappings. For example, 1 scalar can sometimes map to as many as 18 replacement scalars.
//   The replacements get de-duped and collected in a flat array, and mapping entries can refer to their data
//   using the (offset, length) in this table. The (offset, length) info is otherwise known
//   as a ReplacementsTable.Index.

// TODO: Compact the replacements table.
var replacements = ReplacementsTable.Builder()

extension UnicodeMappingEntry.Mapping {

  /// Processes a single, raw replacement mapping.
  ///
  /// If the replacement is another single scalar, it is stored in-line.
  /// Otherwise, it is inserted in to the given replacements table and stored as an index in to that table.
  ///
  fileprivate static func insertIfNeeded(
    _ rawMapping: [UInt32], into replacements: inout ReplacementsTable.Builder
  ) -> UnicodeMappingEntry.Mapping {

    if rawMapping.count == 1 {
      return .single(rawMapping.first!)
    } else {
      precondition(rawMapping.count > 1, "Raw mappings must not be empty")
      return .table(replacements.insert(mapping: rawMapping))
    }
  }
}

// - Status entries.
//
//   Every scalar has a status - valid, mapped, disallowed, ignored, etc. But Unicode scalars exist in a space
//   of 17 planes, each consisting of 2^16 (65K) scalars, and it is impractical to store an individual entry
//   for every single scalar. We need to compress it somehow, while keeping lookups reasonably fast.
//
//   There are ^a lot^ of ways we could do this. Each region of scalars is more/less common and has its own
//   size:speed trade-off to consider. We also have the option of looking up scalars directly as UTF-8 bytes,
//   since scalars encoded as UTF-8 sort the same way as their decoded values.
//
//   The approach here is not _too_ fancy. We do lookup at the (decoded) Unicode scalar level. ASCII uses a simple
//   1:1 lookup table (an Array), and everything else goes through binary search, taking a maximum of
//   log2(n) + 1 steps to locate a scalar, where n is the (fixed) size of the table.
//
//   Despite not being too fancy, we do a couple of things to try optimize lookup a bit further. For one thing,
//   we split the scalars in an 'index' table away from the status data for better cache utilization when performing
//   the binary search. Also, since Unicode scalars are 21-bit numbers, typically they are stored as UInt32s
//   which wastes a lot of bits; to improve on this, we give each _plane_ its own mapping table, and store
//   16-bit offsets in the index. This idea was borrowed from ICU: <https://icu.unicode.org/design/struct/utrie>.

var asciiData = [ASCIIMappingEntry]()
var planeData = (0...16).map { _ in PairOfArrays<UInt16, UnicodeMappingEntry>(x: [], y: []) }

/// A pair of arrays that are guaranteed to have the same number of elements.
///
struct PairOfArrays<X, Y> {
  private(set) var x: [X]
  private(set) var y: [Y]

  mutating func append(_ elementX: X, _ elementY: Y) {
    x.append(elementX)
    y.append(elementY)
  }
}

for rawEntry in rawEntries {

  var rawEntry = rawEntry

  // - Consume the ASCII portion of the entry and use it to populate 'asciiData'.

  if rawEntry.codePoints.lowerBound < 0x80 {

    func entry(codePoint: UInt8) -> ASCIIMappingEntry {
      switch rawEntry.status {
      case .valid:
        return .valid
      case .disallowed_STD3_valid:
        return .disallowed_STD3_valid
      case .mapped:
        let mapping = rawEntry.mapping!
        precondition(mapping.count == 1, "ASCII codepoints should only map to a single other codepoint")
        return .mapped(to: UInt8(mapping.first!))
      case .mapped_rebased:
        let origin = UInt8(rawEntry.mapping!.first!)
        let distance = codePoint - UInt8(rawEntry.codePoints.lowerBound)
        return .mapped(to: origin + distance)
      case .ignored, .disallowed, .disallowed_STD3_mapped, .deviation:
        fatalError("Mapping types unused for ASCII codepoints")
      }
    }

    // Insert an entry for each individual ASCII codepoint.
    precondition(asciiData.count == Int(rawEntry.codePoints.lowerBound), "Inserting ASCII entry in wrong location!")
    let asciiUpperbound = min(rawEntry.codePoints.upperBound, 0x7F)
    for codePoint in rawEntry.codePoints.lowerBound...asciiUpperbound {
      asciiData.append(entry(codePoint: UInt8(codePoint)))
    }

    // Slice off the ASCII portion of the rawEntry; it has been handled.
    guard rawEntry.codePoints.upperBound >= 0x80 else { continue }
    rawEntry.codePoints = 0x80...rawEntry.codePoints.upperBound
  }

  precondition(!rawEntry.codePoints.isEmpty, "Cannot process an empty mapping entry!")

  // Transform the raw status in to our compacted status,
  // including inserting it in the replacements table if needed.

  let entry: UnicodeMappingEntry
  switch rawEntry.status {
  case .valid:
    entry = UnicodeMappingEntry(.valid, .none)
  case .ignored:
    entry = UnicodeMappingEntry(.ignored, .none)
  case .disallowed:
    entry = UnicodeMappingEntry(.disallowed, .none)
  case .disallowed_STD3_valid:
    entry = UnicodeMappingEntry(.disallowed_STD3_valid, .none)
  case .deviation:
    entry = UnicodeMappingEntry(.deviation, rawEntry.mapping.map { .insertIfNeeded($0, into: &replacements) })
  case .disallowed_STD3_mapped:
    entry = UnicodeMappingEntry(.disallowed_STD3_mapped, .insertIfNeeded(rawEntry.mapping!, into: &replacements))
  case .mapped:
    entry = UnicodeMappingEntry(.mapped, .insertIfNeeded(rawEntry.mapping!, into: &replacements))
  case .mapped_rebased:
    entry = UnicodeMappingEntry(.mapped, .rebased(origin: rawEntry.mapping!.first!))
  }

  // Insert the status at the appropriate positions in each plane's table.
  // Essentially this means: at the place where the entry starts, and if it crosses in to any other planes,
  // it should also insert an entry at the plane's start point.

  func addToPlaneTable(
    _ table: inout PairOfArrays<UInt16, UnicodeMappingEntry>, planeRange: ClosedRange<UInt32>
  ) -> Bool {
    let codePoints = rawEntry.codePoints
    if codePoints.contains(UInt32(planeRange.lowerBound)) {
      assert(table.x.isEmpty)
      table.append(0, entry)
      return true
    }
    if planeRange.contains(codePoints.lowerBound) {
      assert(table.x.isEmpty == false || codePoints.lowerBound == 0x80)
      table.append(UInt16(codePoints.lowerBound & 0xFFFF), entry)
      return true
    }
    return false
  }

  var insertedInSomePlane = false
  for plane in 0..<17 {
    let planeStart = UInt32(plane) << 16
    let insertedInThisPlane = addToPlaneTable(&planeData[plane], planeRange: planeStart...planeStart + 0xFFFF)

    // We don't support splitting rebase mappings across multiple planes. It never occurs, anyway.
    if insertedInThisPlane && insertedInSomePlane {
      if case .some(.rebased) = entry.mapping {
        preconditionFailure("Rebased mappings may not cross planes")
      }
    }
    insertedInSomePlane = insertedInSomePlane || insertedInThisPlane
  }
  precondition(insertedInSomePlane, "Mapping entry was not inserted in any plane: \(rawEntry)")
}


// --------------------------------------------
// MARK: - Validate
// --------------------------------------------


precondition(!asciiData.isEmpty)
// TODO: Validate ASCII data.

precondition(planeData.count == 17)
for plane in 0..<17 {
  let dataForPlane = planeData[plane]

  // Check the lengths.
  // Note: This means a valid position in the index table is a valid position in the mapping entry table,
  // and we don't need to bounds-check when using a position from one table in the other table.
  precondition(
    dataForPlane.x.count == dataForPlane.y.count,
    "The index and status tables must have the same number of elements"
  )

  // There is always at least one entry, for the start of the plane.
  if plane == 0 {
    precondition(
      dataForPlane.x[0] == 0x80,
      "The BMP data must start with an entry at offset 0x80"
    )
  } else {
    precondition(
      dataForPlane.x[0] == 0x00,
      "Non-BMP plane data must start with an entry for offset 0x00"
    )
  }

  for mappingEntryIdx in dataForPlane.y.indices {
    let mappingEntry = dataForPlane.y[mappingEntryIdx]

    // Certain statuses must have a mapping, others must not have a mapping.
    switch mappingEntry.status {
    case .valid, .disallowed_STD3_valid, .ignored, .disallowed:
      precondition(
        mappingEntry.mapping == nil,
        "Valid/Ignored/Disallowed codepoints should not have a mapping"
      )
    case .mapped, .disallowed_STD3_mapped:
      precondition(
        mappingEntry.mapping != nil,
        "Mapped codepoints must have a mapping"
      )
    case .deviation:
      break  // Both nil and non-nil mappings are allowed.
    }

    // Check the mapping results are sensible, all table references are in-bounds,
    // and any numerical scalar values are valid Unicode scalars (e.g. not surrogates).
    switch mappingEntry.mapping {
    case .none:
      break
    case .single(let value):
      precondition(
        Unicode.Scalar(value) != nil,
        "Invalid scalar value. \(value)"
      )
    case .rebased(let origin):
      // For a rebase mapping, switch to the index table and find which offsets map to this entry.
      let mappingEntryStart = dataForPlane.x[mappingEntryIdx]
      let mappingEntryLength: UInt16
      if mappingEntryIdx < dataForPlane.y.endIndex {
        mappingEntryLength = dataForPlane.x[mappingEntryIdx + 1] - mappingEntryStart
      } else {
        mappingEntryLength = UInt16.max - mappingEntryStart
      }
      precondition(mappingEntryLength > 0)
      // Check every valid offset from this origin.
      for offset in 0..<mappingEntryLength {
        let rebasedPlaneOffset = origin + UInt32(offset)
        let rebasedCodePoint = UInt32(plane << 16) + rebasedPlaneOffset
        precondition(
          Unicode.Scalar(rebasedCodePoint) != nil,
          "Invalid scalar value. [Plane \(plane)] \(origin) + \(offset) = \(String(rebasedCodePoint, radix: 16))"
        )
      }
    case .table(let index):
      precondition(
        replacements.isInBounds(index),
        "Replacement table index is out of bounds!"
      )
    }
  }

  // TODO: Check the status data against the raw mapping entries, before we "optimized" them.
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
// We can print these as Unicode scalar literals and the compiler still constant-folds them \o/.

printArrayLiteral(
  name: "_idna_replacements_table",
  elementType: "Unicode.Scalar",
  data: replacements.buildReplacementsTable(),
  columns: 8,
  formatter: { #""\u{\#($0.unprefixedHexString(format: .padded(toLength: 6)))}""# },
  to: &output
)
output += "\n"

// ASCII

printArrayLiteral(
  name: "_idna_status_ascii",
  elementType: "UInt16",
  data: asciiData, columns: 8,
  formatter: { $0._storage.hexString(format: .fullWidth) },
  to: &output
)
output += "\n"

// Index and Status arrays for each plane.

var indexArrays = [String]()
var statusArrays = [String]()
for (plane, data) in planeData.enumerated() {
  let indexArrayName = "_idna_index_sub_plane_\(plane)"
  let statusArrayName = "_idna_status_sub_plane_\(plane)"

  printArrayLiteral(
    name: indexArrayName,
    elementType: "UInt16",
    data: data.x, columns: 10,
    formatter: { $0.hexString(format: .fullWidth) },
    to: &output
  )
  output += "\n"
  printArrayLiteral(
    name: statusArrayName,
    elementType: "UInt32",
    data: data.y, columns: 8,
    formatter: { $0._storage.hexString(format: .fullWidth) },
    to: &output
  )
  output += "\n"

  indexArrays.append(indexArrayName)
  statusArrays.append(statusArrayName)
}

// Overall Index and Status arrays.

printArrayLiteral(
  name: "_idna_indexes",
  elementType: "[UInt16]",
  data: indexArrays, columns: 1,
  to: &output
)
output += "\n"
printArrayLiteral(
  name: "_idna_statuses",
  elementType: "[UInt32]",
  data: statusArrays, columns: 1,
  to: &output
)
output += "\n"

output +=
  #"""
  // swift-format-ignore
  @inlinable
  internal func _idna_withIndexAndStatusTable<T>(
    containing scalar: Unicode.Scalar,
    body: (
      _ index: UnsafeBufferPointer<UInt16>, _ statusTable: UnsafeBufferPointer<UInt32>,
      _ planeStart: UInt32, _ offset: UInt16
    ) -> T
  ) -> T {
    let plane      = scalar.value &>> 16
    let planeStart = plane &<< 16
    let offset     = UInt16(truncatingIfNeeded: scalar.value)
    return _idna_indexes.withUnsafeBufferPointer { indexes_buffer in
      return indexes_buffer[Int(plane)].withUnsafeBufferPointer { index in
        return _idna_statuses.withUnsafeBufferPointer { statuses_buffer in
          return statuses_buffer[Int(plane)].withUnsafeBufferPointer { statusTable in
            return body(index, statusTable, planeStart, offset)
          }
        }
      }
    }
  }
  """#
output += "\n"

// Print to stdout.

precondition(output.last == "\n")
output.removeLast()

print(output)
