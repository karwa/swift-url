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

/// This is what the generation script uses to interface with the (internal) types used by this module.
///
/// There are 2 operations: parsing a database from the contents of a file, and printing the database
/// as Swift source code. That's it.
///
public struct IDNAMappingDatabase {

  internal var codePointDatabase: CodePointDatabase<IDNAMappingData>
  internal var replacementsTable: ReplacementsTable.Builder
  // TODO: Include IDNA table version.
}


// --------------------------------------------
// MARK: - Creation
// --------------------------------------------


extension IDNAMappingDatabase {

  /// Constructs a databse from the Unicode `IdnaMappingTable.txt` file.
  ///
  /// The latest version is available at: https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt
  ///
  public init(parsing idnaMappingTableTxt: String) {

    // - Parse Data File in to enties.

    var parsedEntries = [ParsedIDNAMappingDataEntry]()
    do {
      for line in idnaMappingTableTxt.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
        let rawDataString = line.prefix { $0 != "#" }
        let comment = line[rawDataString.endIndex...].dropFirst()
        guard let entry = ParsedIDNAMappingDataEntry(parsing: rawDataString) else {
          fatalError(
            """
            ⚠️ Failed to Parse Entry in Mapping Data! ⚠️
            line: \(line)
            rawDataString: \(rawDataString)
            comment: \(comment)
            """
          )
        }
        // TODO: Replace this merge step with RangeTable
        // We do a bit of optimization here already, by merging contiguous entries as they are appended to the table
        // and collapsing contiguous mappings. This can remove 1/3 of entries (from ~9000 to 6000).
        if let last = parsedEntries.last, let merged = last.tryMerge(with: entry) {
          parsedEntries[parsedEntries.index(before: parsedEntries.endIndex)] = merged
        } else {
          parsedEntries.append(entry)
        }
      }
    }

    // - Build database

    // Split the raw mapping data in to separate tables:
    //
    // * A database of the IDNA status and mapping data associated with Unicode code-points.
    //   For example, this tells us if a scalar is valid, or if it should be mapped or rejected.
    //
    // * A flattened array containing all the replacements.
    //   One scalar might be replaced with many other scalars (X -> [A, B, C, D]). The longest is one
    //   scalar which maps to a string of 18 replacement scalars. Some entries in the database store
    //   their replacement info here.
    //
    var dbBuilder = CodePointDatabase<IDNAMappingData>.Builder()
    var replacements = ReplacementsTable.Builder()

    for parsedEntry in parsedEntries {
      var parsedEntry = parsedEntry

      // ASCII.
      if parsedEntry.codePoints.lowerBound < 0x80 {
        for asciiCodePoint in parsedEntry.codePoints.lowerBound...min(parsedEntry.codePoints.upperBound, 0x7F) {
          let entry: IDNAMappingData.ASCIIData
          switch parsedEntry.status {
          case .valid:
            entry = .valid
          case .disallowed_STD3_valid:
            entry = .disallowed_STD3_valid
          case .mapped:
            let mapping = parsedEntry.mapping!
            precondition(mapping.count == 1, "ASCII codepoints should only map to a single other codepoint")
            entry = .mapped(to: UInt8(mapping.first!))
          case .mapped_rebased:
            let offset = asciiCodePoint - parsedEntry.codePoints.lowerBound
            let newOrigin = parsedEntry.mapping!.first!
            entry = .mapped(to: UInt8(newOrigin + offset))
          case .ignored, .disallowed, .disallowed_STD3_mapped, .deviation:
            fatalError("Mapping types unused for ASCII codepoints")
          }
          dbBuilder.appendAscii(entry, for: asciiCodePoint)
        }
        // Slice off the ASCII portion of the rawEntry; it has been handled.
        guard parsedEntry.codePoints.upperBound >= 0x80 else { continue }
        parsedEntry.codePoints = 0x80...parsedEntry.codePoints.upperBound
      }

      precondition(!parsedEntry.codePoints.isEmpty, "Cannot process an empty mapping entry!")

      // Non-ASCII.
      let entry: IDNAMappingData.UnicodeData
      switch parsedEntry.status {
      case .valid:
        entry = .init(.valid, .none)
      case .ignored:
        entry = .init(.ignored, .none)
      case .disallowed:
        entry = .init(.disallowed, .none)
      case .disallowed_STD3_valid:
        entry = .init(.disallowed_STD3_valid, .none)
      case .deviation:
        entry = .init(.deviation, parsedEntry.mapping.map { .insertIfNeeded($0, into: &replacements) })
      case .disallowed_STD3_mapped:
        entry = .init(.disallowed_STD3_mapped, .insertIfNeeded(parsedEntry.mapping!, into: &replacements))
      case .mapped:
        entry = .init(.mapped, .insertIfNeeded(parsedEntry.mapping!, into: &replacements))
      case .mapped_rebased:
        entry = .init(.mapped, .rebased(origin: parsedEntry.mapping!.first!))
      }
      dbBuilder.appendUnicode(entry, for: parsedEntry.codePoints)
    }

    let db = dbBuilder.finalize()

    // - Validate

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
        // and any scalar values are valid Unicode scalars (e.g. not surrogates).
        switch entry.mapping {
        case .none:
          break
        case .single(let replacement):
          precondition(Unicode.Scalar(replacement) != nil, "\(codePoint) maps invalid scalar \(replacement)")
        case .rebased(let newOrigin):
          let distance = scalar.value - entryStartCodePoint
          let replacement = newOrigin + distance
          precondition(Unicode.Scalar(replacement) != nil, "\(codePoint) rebased to invalid scalar \(replacement)")
        case .table(let index):
          precondition(replacements.isInBounds(index), "Replacement table index is out of bounds!")
        }

      // TODO: Check the status data against the raw mapping entries from the parser.
      }
    }

    // - Done!

    self.codePointDatabase = db
    self.replacementsTable = replacements
  }
}

extension IDNAMappingData.UnicodeData.Mapping {

  /// Processes a single, raw replacement mapping.
  ///
  /// If the replacement is another single scalar, it is stored in-line.
  /// Otherwise, it is inserted in to the given replacements table and stored as an index in to that table.
  ///
  fileprivate static func insertIfNeeded(
    _ rawMapping: [UInt32], into replacements: inout ReplacementsTable.Builder
  ) -> IDNAMappingData.UnicodeData.Mapping {

    if rawMapping.count == 1 {
      return .single(rawMapping.first!)
    } else {
      precondition(rawMapping.count > 1, "Raw mappings must not be empty")
      return .table(replacements.insert(mapping: rawMapping))
    }
  }
}


// --------------------------------------------
// MARK: - Printing
// --------------------------------------------


extension IDNAMappingDatabase {

  public func printAsSwiftSourceCode(name: String) -> String {
    var output = ""
    // We can print the replacements table as Unicode scalar literals and the compiler still constant-folds them \o/.
    printArrayLiteral(
      name: "\(name)_replacements_table",
      elementType: "Unicode.Scalar",
      data: replacementsTable.buildReplacementsTable(),
      columns: 8,
      formatter: { #""\u{\#($0.unprefixedHexString(format: .padded(toLength: 6)))}""# },
      to: &output
    )
    output += "\n"
    output += codePointDatabase.printAsSwiftSourceCode(name: name, using: DefaultFormatter<IDNAMappingData>.self)

    // Fix up trailing newlines.
    precondition(output.last == "\n")
    output.removeLast()
    precondition(output.last != "\n")
    return output
  }
}
