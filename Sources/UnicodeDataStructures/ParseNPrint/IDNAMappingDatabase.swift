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

#if WEBURL_UNICODE_PARSE_N_PRINT

  /// This is what the generation script uses to interface with the (internal) types used by this module.
  ///
  /// There are 2 operations: parsing a database from the contents of a file, and printing the database
  /// as Swift source code. That's it.
  ///
  public struct IDNAMappingDatabase {
    internal var codePointDatabase: CodePointDatabase<IDNAMappingData>
    internal var replacementsTable: ReplacementsTable.Builder
  }


  // --------------------------------------------
  // MARK: - Printing
  // --------------------------------------------


  extension IDNAMappingDatabase {

    public func printAsSwiftSourceCode(name: String) -> String {
      var output = ""
      // We can print the replacements table as Unicode scalar literals
      // and the compiler still constant-folds them \o/.
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

      precondition(output.last == "\n")
      precondition(output.dropLast().last != "\n")
      return output
    }
  }


  // --------------------------------------------
  // MARK: - Creation
  // --------------------------------------------


  extension IDNAMappingDatabase {

    /// Constructs a database from the Unicode `IdnaMappingTable.txt` file.
    ///
    /// The latest version is available at: https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt
    ///
    public init(parsing idnaMappingTableTxt: String) {

      // - Parse Data File.

      var mappingData = SegmentedLine<UInt32, RawIDNAMappingEntry>(
        bounds: Range(0...0x10_FFFF), value: RawIDNAMappingEntry(status: .disallowed, replacements: nil)
      )
      do {
        for line in idnaMappingTableTxt.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
          let rawDataString = line.prefix { $0 != "#" }
          let comment = line[rawDataString.endIndex...].dropFirst()
          guard let (codepoints, entry) = RawIDNAMappingEntry.parse(rawDataString) else {
            fatalError(
              """
              ⚠️ Failed to Parse Entry in Mapping Data! ⚠️
              line: \(line)
              rawDataString: \(rawDataString)
              comment: \(comment)
              """
            )
          }
          mappingData.set(Range(codepoints), to: entry)
        }
        mappingData.combineSegments()
      }

      // - Create rebase mappings.

      // If consecutive single-element segments map to consecutive scalars (e.g. "A" -> "a", "B" -> "b" ... "Z" -> "z"),
      // we can create a single mapping which takes our offset in a segment and applies it to a new base.
      // This reduces the number of entries by ~2000. In particular, it halves the size of the SMP table.
      //
      // However, these values depend on their segment location. That means we cannot alter segments
      // after we create these things. Consider rebasing "A-Z" on to "a":
      //
      // | ["A"..<after("Z")]: rebase("a") |
      //
      // If we then do a SegmentedLine operation which split segments around "K", we would end up with the following:
      //
      // | ["A"..<"K"]: rebase("a") | ["K"..<"L"]: newValue | ["L"..<after("Z")]: rebase("a") |
      //
      // Which is not correct. "L" would be rebased to "a". We can't just trivially split these values
      // and copy the new value to the new segment - we would need to calculate an adjusted value.
      // We also can't combine them - two segments which each rebase to "a" can't just be merged as one big segment
      // which is all rebased to "a"; we'd still need to reset the origin for rebased code-points in the second segment.
      //
      // So it's all very nice, but it means that other table optimizations should happen *BEFORE* creating
      // rebase mappings.

      mappingData.combineSegments { accumulator, next in
        // Don't create rebase mappings for ASCII segments;
        // we're only going to unpack them in the next step when we create the database.
        guard next.range.upperBound > 0x80 else { return false }
        switch (accumulator.value.status, next.value.status) {
        case (.mapped, .mapped):
          let accuMapping = accumulator.value.replacements!
          let nextMapping = next.value.replacements!
          precondition(accuMapping != nextMapping, "Should have been combined previously")
          if accumulator.range.count == 1, next.range.count == 1,
            accuMapping.count == 1, nextMapping.count == 1,
            accuMapping[0] + 1 == nextMapping[0]
          {
            accumulator.value.status = .mapped_rebased
            return true
          }
          return false
        case (.mapped_rebased, .mapped):
          let accuMapping = accumulator.value.replacements!
          let nextMapping = next.value.replacements!
          if next.range.count == 1, nextMapping.count == 1,
            accuMapping[0] + UInt32(accumulator.range.count) == nextMapping[0]
          {
            return true
          }
          return false
        default:
          return false
        }
      }

      // - Build database

      var replacementsTable = ReplacementsTable.Builder()
      let db = mappingData.generateTable(
        IDNAMappingData.self,
        mapAsciiValue: { entry in
          switch entry.status {
          case .valid:
            return .valid
          case .disallowed_STD3_valid:
            return .disallowed_STD3_valid
          case .mapped:
            let mapping = entry.replacements!
            precondition(mapping.count == 1, "ASCII codepoints should only map to a single other codepoint")
            return .mapped(to: UInt8(mapping.first!))
          case .ignored, .disallowed, .disallowed_STD3_mapped, .deviation, .mapped_rebased:
            fatalError("Unexpected mapping type for ASCII codepoint")
          }
        },
        mapUnicodeValue: { entry in
          switch entry.status {
          case .valid:
            return .init(.valid, .none)
          case .ignored:
            return .init(.ignored, .none)
          case .disallowed:
            return .init(.disallowed, .none)
          case .disallowed_STD3_valid:
            return .init(.disallowed_STD3_valid, .none)
          case .deviation:
            return .init(.deviation, entry.getOrInsertReplacementsIndex(in: &replacementsTable))
          case .disallowed_STD3_mapped:
            return .init(.disallowed_STD3_mapped, entry.getOrInsertReplacementsIndex(in: &replacementsTable)!)
          case .mapped:
            return .init(.mapped, entry.getOrInsertReplacementsIndex(in: &replacementsTable)!)
          case .mapped_rebased:
            return .init(.mapped, .rebased(origin: entry.replacements!.first!))
          }
        }
      )

      // - Done!

      self.codePointDatabase = db
      self.replacementsTable = replacementsTable
      self.validate()
    }
  }

  private struct RawIDNAMappingEntry: Equatable {

    var status: Status
    var replacements: [UInt32]?

    enum Status: String {

      /// The code point is valid, and not modified.
      case valid = "valid"

      /// The code point is removed: this is equivalent to mapping the code point to an empty string.
      case ignored = "ignored"

      /// The code point is replaced in the string by the value for the mapping.
      case mapped = "mapped"

      /// The code point is either mapped or valid, depending on whether the processing is transitional or not.
      case deviation = "deviation"

      /// The code point is not allowed.
      case disallowed = "disallowed"

      /// The status is disallowed if `UseSTD3ASCIIRules=true` (the normal case);
      /// implementations that allow `UseSTD3ASCIIRules=false` would treat the code point as **valid**.
      case disallowed_STD3_valid = "disallowed_STD3_valid"

      /// the status is disallowed if `UseSTD3ASCIIRules=true` (the normal case);
      /// implementations that allow `UseSTD3ASCIIRules=false` would treat the code point as **mapped**.
      case disallowed_STD3_mapped = "disallowed_STD3_mapped"

      case mapped_rebased = "___weburl___mapped_rebased___"
    }

    /// Parses the code-points, status and mapping from a given line of the IDNA mapping table.
    /// The given line must be stripped of its trailing comment.
    ///
    /// For example:
    ///
    /// ```
    /// 00B8          ; disallowed_STD3_mapped ; 0020 0327
    /// 00B9          ; mapped                 ; 0031
    /// 00BA          ; mapped                 ; 006F
    /// 00BB          ; valid                  ;      ; NV8
    /// 00BC          ; mapped                 ; 0031 2044 0034
    /// 00BD          ; mapped                 ; 0031 2044 0032
    /// 00E0..00F6    ; valid
    /// ```
    ///
    /// The validation here is minimal. The input data is presumed to be a correctly-formatted Unicode data table.
    ///
    static func parse(_ tableData: Substring) -> (codePoints: ClosedRange<UInt32>, data: RawIDNAMappingEntry)? {

      let components = tableData.split(separator: ";").map { $0.trimmingSpaces }
      guard components.count >= 2 else { return nil }

      let codePoints: ClosedRange<UInt32>
      let status: Status
      let replacements: [UInt32]?

      parseCodePoints: do {
        guard let _codePoints = ParsingHelpers.parseCodePointRange(components[0]) else { return nil }
        codePoints = _codePoints
      }
      parseStatus: do {
        guard let _status = Status(rawValue: String(components[1])) else { return nil }
        status = _status
      }
      if case .mapped_rebased = status {
        fatalError("Rebased status cannot be used when parsing")
      }
      parseReplacements: do {
        let replacementsString: Substring
        switch status {
        case .valid, .ignored, .disallowed, .disallowed_STD3_valid, .mapped_rebased:
          // No replacements.
          replacements = nil
          break parseReplacements
        case .deviation:
          // May specify replacements.
          replacementsString = components[2]
          if replacementsString.isEmpty {
            replacements = nil
            break parseReplacements
          }
        case .mapped, .disallowed_STD3_mapped:
          // Must specify replacements.
          replacementsString = components[2]
          break
        }

        guard !replacementsString.isEmpty else { return nil }
        do {
          struct InvalidNumber: Error {}
          replacements = try replacementsString.split(separator: " ").map {
            try UInt32($0, radix: 16) ?? { throw InvalidNumber() }()
          }
          precondition(replacements?.isEmpty == false)
        } catch {
          return nil
        }
      }

      return (codePoints, RawIDNAMappingEntry(status: status, replacements: replacements))
    }

    fileprivate func getOrInsertReplacementsIndex(
      in replacementsBuilder: inout ReplacementsTable.Builder
    ) -> IDNAMappingData.UnicodeData.Mapping? {

      guard let replacements = replacements, !replacements.isEmpty else {
        return nil
      }
      if replacements.count == 1 {
        return .single(replacements.first!)
      } else {
        return .table(replacementsBuilder.insert(mapping: replacements))
      }
    }
  }


  // --------------------------------------------
  // MARK: - Validation
  // --------------------------------------------
  // TODO: This should become some sort of test, I think?


  extension IDNAMappingDatabase {

    fileprivate func validate() {

      for codePoint in 0...0x10FFFF {

        guard let scalar = Unicode.Scalar(codePoint) else { continue }

        switch codePointDatabase[scalar] {
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
            precondition(replacementsTable.isInBounds(index), "Replacement table index is out of bounds!")
          }

        // TODO: Check the status data against the raw mapping entries from the parser.
        }
      }

      // Check that we don't create rebase mappings for consecutive scalars if one mapping is a many-to-one.
      // This actually happens - we can have one codepoint mapped to "g", then 4 codepoints all mapped to "h".
      // We shouldn't generate a rebase mapping in that case.
      if case .nonAscii(IDNAMappingData.UnicodeData(.mapped, .single(0x67)), 0x210A) = codePointDatabase["\u{210A}"],
        case .nonAscii(IDNAMappingData.UnicodeData(.mapped, .single(0x68)), 0x210B) = codePointDatabase["\u{210B}"],
        case .nonAscii(IDNAMappingData.UnicodeData(.mapped, .single(0x68)), 0x210B) = codePointDatabase["\u{210C}"],
        case .nonAscii(IDNAMappingData.UnicodeData(.mapped, .single(0x68)), 0x210B) = codePointDatabase["\u{210D}"],
        case .nonAscii(IDNAMappingData.UnicodeData(.mapped, .single(0x68)), 0x210B) = codePointDatabase["\u{210E}"]
      {
      } else {
        assertionFailure("Unexpected mapping data")
      }
    }
  }

#endif  // WEBURL_UNICODE_PARSE_N_PRINT
