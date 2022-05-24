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

public func generateIDNAValidationData() throws -> String {

  let mappingTableURL = Bundle.module.url(forResource: "TableDefinitions/DerivedBidiClass", withExtension: "txt")!
  let mappingTable = try String(contentsOf: mappingTableURL)
  let db = createIDNAValidationDatabase(dataFileContents: mappingTable)
  return db.printAsSwiftSourceCode(name: "_bidi")
}


// --------------------------------------------
// MARK: - Database Creation
// --------------------------------------------


func createIDNAValidationDatabase(
  dataFileContents: String
) -> CodePointDatabase<IDNAValidationDataSchema> {

  var fullBidiTable = RangeTable<UInt32, ParsedBidiClassEntry.BidiClass>(
    bounds: Range(0...0x10_FFFF), initialValue: .L
  )

  // FIXME: Is it even worth setting unassigned code-points at all?
  // FIXME: Is it even worth setting code-points other than those with 'valid' status in IDNA?

  // - First, set some defaults for unassigned code points.

  // # Unlike other properties, unassigned code points in blocks
  // # reserved for right-to-left scripts are given either types R or AL.
  // #
  // # The unassigned code points that default to AL are in the ranges:
  // #     [\u0600-\u07BF \u0860-\u08FF \uFB50-\uFDCF \uFDF0-\uFDFF \uFE70-\uFEFF
  // #      \U00010D00-\U00010D3F \U00010F30-\U00010F6F
  // #      \U0001EC70-\U0001ECBF \U0001ED00-\U0001ED4F \U0001EE00-\U0001EEFF]
  // #
  // #     This includes code points in the Arabic, Syriac, and Thaana blocks, among others.
  for range: ClosedRange<UInt32> in [
    0x0600...0x07BF,
    0x0860...0x08FF,
    0xFB50...0xFDCF,
    0xFDF0...0xFDFF,
    0xFE70...0xFEFF,
    0x0001_0D00...0x0001_0D3F,
    0x0001_0F30...0x0001_0F6F,
    0x0001_EC70...0x0001_ECBF,
    0x0001_ED00...0x0001_ED4F,
    0x0001_EE00...0x0001_EEFF,
  ] {
    fullBidiTable.set(Range(range), to: .AL)
  }
  // # The unassigned code points that default to R are in the ranges:
  // #     [\u0590-\u05FF \u07C0-\u085F \uFB1D-\uFB4F
  // #      \U00010800-\U00010CFF \U00010D40-\U00010F2F \U00010F70-\U00010FFF
  // #      \U0001E800-\U0001EC6F \U0001ECC0-\U0001ECFF \U0001ED50-\U0001EDFF \U0001EF00-\U0001EFFF]
  // #
  // #     This includes code points in the Hebrew, NKo, and Phoenician blocks, among others.
  for range: ClosedRange<UInt32> in [
    0x0590...0x05FF,
    0x07C0...0x085F,
    0xFB1D...0xFB4F,
    0x0001_0800...0x0001_0CFF,
    0x0001_0D40...0x0001_0F2F,
    0x0001_0F70...0x0001_0FFF,
    0x0001_E800...0x0001_EC6F,
    0x0001_ECC0...0x0001_ECFF,
    0x0001_ED50...0x0001_EDFF,
    0x0001_EF00...0x0001_EFFF,
  ] {
    fullBidiTable.set(Range(range), to: .R)
  }
  // # The unassigned code points that default to ET are in the range:
  // #     [\u20A0-\u20CF]
  // #
  // #     This consists of code points in the Currency Symbols block.
  for range: ClosedRange<UInt32> in [
    0x20A0...0x20CF
  ] {
    fullBidiTable.set(Range(range), to: .ET)
  }
  // # The unassigned code points that default to BN have one of the following properties:
  // #     Default_Ignorable_Code_Point
  // #     Noncharacter_Code_Point
  for codePoint in fullBidiTable.bounds {
    guard let scalar = Unicode.Scalar(codePoint) else { continue }
    if scalar.properties.generalCategory == .unassigned,
      scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isNoncharacterCodePoint
    {
      fullBidiTable.set(scalar.value..<scalar.value + 1, to: .BN)
    }
  }
  // # For all other cases:
  // #  All code points not explicitly listed for Bidi_Class
  // #  have the value Left_To_Right (L).

  // - Parse Data Files

  do {
    for line in dataFileContents.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
      let rawDataString = line.prefix { $0 != "#" }
      let comment = line[rawDataString.endIndex...].dropFirst()
      guard let entry = ParsedBidiClassEntry(parsing: rawDataString) else {
        fatalError(
          """
          ⚠️ Failed to Parse Entry in Mapping Data! ⚠️
          line: \(line)
          rawDataString: \(rawDataString)
          comment: \(comment)
          """
        )
      }
      fullBidiTable.set(Range(entry.codePoints), to: entry.value)
    }
  }
  // TODO: Also parse joiner data
  // TODO: Also get IDNA mapping database?

  // - Remove unnecessary data

  var reducedBidiTable = fullBidiTable.mapElements { $0.toInt() }
  reducedBidiTable.mergeElements()

  return reducedBidiTable.generateTable(
    IDNAValidationDataSchema.self,
    mapAsciiValue: { $0 },
    mapUnicodeValue: { $0 }
  )
}

// TODO: Figure something out for all of this.

struct IDNAValidationDataSchema: CodePointDatabaseBuildSchema {
  typealias ASCIIData = UInt8
  static var asciiEntryElementType: String { "UInt8" }
  static func formatASCIIEntry(_ entry: ASCIIData) -> String { entry.hexString(format: .fullWidth) }

  typealias UnicodeData = UInt8
  static var unicodeEntryElementType: String { "UInt8" }
  static func formatUnicodeEntry(_ entry: UnicodeData) -> String { entry.hexString(format: .fullWidth) }
}

extension ParsedBidiClassEntry.BidiClass {
  func toInt() -> UInt8 {

    // 1.  The first character must be a character with Bidi property L, R,
    //     or AL.  If it has the R or AL property, it is an RTL label; if it
    //     has the L property, it is an LTR label.
    //
    // 2.  In an RTL label, only characters with the Bidi properties R, AL,
    //     AN, EN, ES, CS, ET, ON, BN, or NSM are allowed.
    //
    // 3.  In an RTL label, the end of the label must be a character with
    //     Bidi property R, AL, EN, or AN, followed by zero or more
    //     characters with Bidi property NSM.
    //
    // 4.  In an RTL label, if an EN is present, no AN may be present, and
    //     vice versa.
    //
    // 5.  In an LTR label, only characters with the Bidi properties L, EN,
    //     ES, CS, ET, ON, BN, or NSM are allowed.
    //
    // 6.  In an LTR label, the end of the label must be a character with
    //     Bidi property L or EN, followed by zero or more characters with
    //     Bidi property NSM.
    switch self {
    case .L: return 0  // For 1, 5, 6
    case .R, .AL: return 1  // For 1, 2, 3
    case .AN: return 2  // For 2, 4
    case .EN: return 3  // For 2, 4, 5
    case .ES, .CS, .ET, .ON, .BN: return 4  // For 2, 5
    case .NSM: return 5  // For 2, 3, 5, 6
    default: return 6
    }
  }
}
