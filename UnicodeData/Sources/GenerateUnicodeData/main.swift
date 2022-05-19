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
// MARK: - Build database
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

// - A database of the IDNA status and mapping data associated with Unicode code-points.

var idnaDBBuilder = CodePointDatabase<IDNAData>.Builder()

struct IDNAData: CodePointDatabaseBuildSchema {

  // Our ASCII entries contain a simplified valid/mapped/STD3 flag and optional
  // replacement code-point, packed in a UInt16.

  typealias ASCIIData = ASCIIMappingEntry

  static var asciiEntryElementType: String { "UInt16" }

  static func formatASCIIEntry(_ entry: ASCIIData) -> String {
    entry._storage.hexString(format: .fullWidth)
  }

  // Our Unicode entries contain more elaborate status and mapping info:
  // either a 21-bit scalar, as a replacement or new origin to "rebase" against, or
  // an compacted region of a static data table (the "replacements table").
  // We need a UInt32 for these. They contain full Unicode scalars.

  typealias UnicodeData = UnicodeMappingEntry

  static var unicodeEntryElementType: String { "UInt32" }

  static func formatUnicodeEntry(_ entry: UnicodeData) -> String {
    entry._storage.hexString(format: .fullWidth)
  }

  static func entry(_ entry: UnicodeData, copyForStartingAt newStartPoint: UInt32) -> UnicodeData {
    // Rebase mappings can be split, but in practice they never are so this isn't tested at all.
    // Forbid them just to be sure they don't slip by unnoticed.
    if case .some(.rebased) = entry.mapping {
      preconditionFailure("Rebased mappings are intentionally forbidden from being split")
    }
    // All other entries don't care which exact code-point they are linked against in the index.
    // They are "position-independent".
    return entry
  }
}

// -

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

for rawEntry in rawEntries {

  var rawEntry = rawEntry

  // - Consume the ASCII portion of the entry and use it to populate 'asciiData'.
  //   Insert an entry for each individual ASCII codepoint, flattening out rebase mappings.

  if rawEntry.codePoints.lowerBound < 0x80 {

    for asciiCodePoint in rawEntry.codePoints.lowerBound...min(rawEntry.codePoints.upperBound, 0x7F) {
      let entry: ASCIIMappingEntry
      switch rawEntry.status {
      case .valid:
        entry = .valid
      case .disallowed_STD3_valid:
        entry = .disallowed_STD3_valid
      case .mapped:
        let mapping = rawEntry.mapping!
        precondition(mapping.count == 1, "ASCII codepoints should only map to a single other codepoint")
        entry = .mapped(to: UInt8(mapping.first!))
      case .mapped_rebased:
        let offset = asciiCodePoint - rawEntry.codePoints.lowerBound
        let newOrigin = rawEntry.mapping!.first!
        entry = .mapped(to: UInt8(newOrigin + offset))
      case .ignored, .disallowed, .disallowed_STD3_mapped, .deviation:
        fatalError("Mapping types unused for ASCII codepoints")
      }
      idnaDBBuilder.appendAscii(entry, for: asciiCodePoint)
    }

    // Slice off the ASCII portion of the rawEntry; it has been handled.
    guard rawEntry.codePoints.upperBound >= 0x80 else { continue }
    rawEntry.codePoints = 0x80...rawEntry.codePoints.upperBound
  }

  precondition(!rawEntry.codePoints.isEmpty, "Cannot process an empty mapping entry!")

  // - Transform the raw, parsed status in to our compacted status.
  //   Insert mappings in to the replacements table if needed.

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
  idnaDBBuilder.appendUnicode(entry, for: rawEntry.codePoints)
}

let db = idnaDBBuilder.finalize()


// --------------------------------------------
// MARK: - Validate
// --------------------------------------------


for codePoint in 0...0x10FFFF {
  guard let scalar = Unicode.Scalar(codePoint) else {
    continue
  }

  switch db[scalar] {
  case .ascii(let entry):
    precondition(codePoint < 0x80)
    // Certain statuses must have a replacement, others must not have a replacement.
    switch entry.status {
    case .valid, .disallowed_STD3_valid:
      precondition(entry.replacement.value == 0, "Valid/STD3 codepoint should not have a replacement")
    case .mapped:
      precondition(entry.replacement.value != 0, "No ASCII codepoints are ever mapped to NULL")
    }
  // TODO: Validate ASCII entries.

  case .nonAscii(let entry, startCodePoint: let entryStartCodePoint):
    precondition(codePoint >= 0x80)

    // Certain statuses must have a mapping, others must not have a mapping.
    switch entry.status {
    case .valid, .disallowed_STD3_valid, .ignored, .disallowed:
      precondition(
        entry.mapping == nil,
        "Valid/Ignored/Disallowed codepoints should not have a mapping"
      )
    case .mapped, .disallowed_STD3_mapped:
      precondition(
        entry.mapping != nil,
        "Mapped codepoints must have a mapping"
      )
    case .deviation:
      break  // Both nil and non-nil mappings are allowed.
    }

    // Check the mapping results are sensible, all table references are in-bounds,
    // and any numerical scalar values are valid Unicode scalars (e.g. not surrogates).
    switch entry.mapping {
    case .none:
      break
    case .single(let replacement):
      precondition(Unicode.Scalar(replacement) != nil, "\(codePoint) maps invalid scalar value \(replacement)")
    case .rebased(let newOrigin):
      let distance = scalar.value - entryStartCodePoint
      let replacement = newOrigin + distance
      precondition(Unicode.Scalar(replacement) != nil, "\(codePoint) rebased to invalid scalar value \(replacement)")
    case .table(let index):
      precondition(replacements.isInBounds(index), "Replacement table index is out of bounds!")
    }

  // TODO: Check the status data against the raw mapping entries from the parser.
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

output += db.printAsSwiftSourceCode(name: "_idna")

// Print to stdout.

precondition(output.last == "\n")
output.removeLast()

print(output)
