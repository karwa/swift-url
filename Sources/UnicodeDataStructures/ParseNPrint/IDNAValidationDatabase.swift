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
  /// There are 2 operations: parsing a database from the contents of some files, and printing the database
  /// as Swift source code. That's it.
  ///
  public struct IDNAValidationDatabase {
    internal var codePointDatabase: CodePointDatabase<IDNAValidationData>
  }


  // --------------------------------------------
  // MARK: - Printing
  // --------------------------------------------


  extension IDNAValidationDatabase {

    public func printAsSwiftSourceCode(name: String) -> String {
      let output = codePointDatabase.printAsSwiftSourceCode(
        name: name,
        using: DefaultFormatter<IDNAValidationData>.self
      )
      precondition(output.last == "\n")
      precondition(output.dropLast().last != "\n")
      return output
    }
  }


  // --------------------------------------------
  // MARK: - Creation
  // --------------------------------------------


  extension IDNAValidationDatabase {

    public init(
      mappingDB: IDNAMappingDatabase,
      derivedBidiClassTxt: String,
      derivedJoiningTypeTxt: String
    ) {

      // - Parse Data Files

      var bidiData = SegmentedLine<UInt32, RawBidiClass>(
        bounds: Range(0...0x10_FFFF), value: .L
      )
      var joiningData = SegmentedLine<UInt32, RawJoiningType>(
        bounds: Range(0...0x10_FFFF), value: .U
      )

      do {
        for line in derivedBidiClassTxt.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
          let rawDataString = line.prefix { $0 != "#" }
          let comment = line[rawDataString.endIndex...].dropFirst()
          guard let entry = ParsingHelpers.CodePointsToProperty<RawBidiClass>(parsing: rawDataString) else {
            fatalError(
              """
              ⚠️ Failed to Parse Entry in Bidi_Class Data! ⚠️
              line: \(line)
              rawDataString: \(rawDataString)
              comment: \(comment)
              """
            )
          }
          bidiData.set(Range(entry.codePoints), to: entry.value)
        }
        bidiData.combineSegments()
      }
      do {
        for line in derivedJoiningTypeTxt.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
          let rawDataString = line.prefix { $0 != "#" }
          let comment = line[rawDataString.endIndex...].dropFirst()
          guard let entry = ParsingHelpers.CodePointsToProperty<RawJoiningType>(parsing: rawDataString) else {
            fatalError(
              """
              ⚠️ Failed to Parse Entry in Joining_Type Data! ⚠️
              line: \(line)
              rawDataString: \(rawDataString)
              comment: \(comment)
              """
            )
          }
          joiningData.set(Range(entry.codePoints), to: entry.value)
        }
        joiningData.combineSegments()
      }

      // - Create a merged data-set.

      // a. Start with the Bidi_Class data.
      var validationData: SegmentedLine<UInt32, IDNAValidationData.ValidationFlags> = bidiData.mapValues { parsedInfo in
        IDNAValidationData.ValidationFlags(
          bidiInfo: parsedInfo.simplified(),
          joiningType: .other, isVirama: false, isMark: false  // defaults.
        )
      }

      // b. Insert Joining_Type data.
      for (range, parsedJoinType) in joiningData.segments {
        let simplified = parsedJoinType.simplified()
        validationData.modify(range) { $0.joiningType = simplified }
      }

      // c. Mark virama and marks.
      for codePoint in 0...(0x10_FFFF as UInt32) {
        guard let scalar = Unicode.Scalar(codePoint) else { continue }

        // TODO: We should get this data from a stable source.
        let isVirama = (scalar.properties.canonicalCombiningClass == .virama)
        let isMark = [.spacingMark, .nonspacingMark, .enclosingMark].contains(scalar.properties.generalCategory)

        if isVirama || isMark {
          validationData.modify(codePoint..<(codePoint + 1)) {
            $0.isVirama = isVirama
            $0.isMark = isMark
          }
        }
      }

      // - Create a DB out of the combined data.

      validationData.combineSegments()

      self.codePointDatabase = validationData.generateTable(
        IDNAValidationData.self,
        mapAsciiValue: { $0 },
        mapUnicodeValue: { $0 }
      )
    }
  }

  private enum RawBidiClass: String {
    case L = "L"
    case R = "R"
    case EN = "EN"
    case ES = "ES"
    case ET = "ET"
    case AN = "AN"
    case CS = "CS"
    case B = "B"
    case S = "S"
    case WS = "WS"
    case ON = "ON"
    case BN = "BN"
    case NSM = "NSM"
    case AL = "AL"
    case LRO = "LRO"
    case RLO = "RLO"
    case LRE = "LRE"
    case RLE = "RLE"
    case PDF = "PDF"
    case LRI = "LRI"
    case RLI = "RLI"
    case FSI = "FSI"
    case PDI = "PDI"

    func simplified() -> IDNAValidationData.ValidationFlags.BidiInfo {

      // Here's the Bidi rule (it's actually 6 rules).
      // We don't actually need all the Bidi_Class data for it:
      //
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

      // swift-format-ignore
      switch self {
      case .L:      return .L      // For 1, 5, 6
      case .R, .AL: return .RorAL  // For 1, 2, 3
      case .AN:     return .AN     // For 2, 4
      case .EN:     return .EN     // For 2, 4, 5
      case .ES, .CS, .ET, .ON, .BN: return .ESorCSorETorONorBN  // For 2, 5
      case .NSM:    return .NSM    // For 2, 3, 5, 6
      default:      return .disallowed  // Everything else
      }
    }
  }

  private enum RawJoiningType: String {
    case C = "C"
    case D = "D"
    case R = "R"
    case L = "L"
    case T = "T"
    case U = "U"

    func simplified() -> IDNAValidationData.ValidationFlags.JoiningType {
      switch self {
      case .L: return .L
      case .R: return .R
      case .D: return .D
      case .T: return .T
      default: return .other
      }
    }
  }

#endif  // WEBURL_UNICODE_PARSE_N_PRINT
