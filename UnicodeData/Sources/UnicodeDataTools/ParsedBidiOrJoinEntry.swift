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

internal struct ParsedBidiClassEntry {

  var codePoints: ClosedRange<UInt32>
  var value: BidiClass

  enum BidiClass: String {
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
  }

  /// Parses the code-points and Bidi\_Class from a given line of the Unicode data table.
  /// The given line must be stripped of its trailing comment.
  ///
  /// For example:
  ///
  /// ```
  /// 1F20..1F45    ; L
  /// 1F48..1F4D    ; L
  /// 1F50..1F57    ; L
  /// 1F59          ; L
  /// 1F5B          ; L
  /// 1F5D          ; L
  /// 0660..0669    ; AN
  /// 066B..066C    ; AN
  /// 06DD          ; AN
  /// 0890..0891    ; AN
  /// ```
  ///
  /// The validation here is minimal. The input data is presumed to be a correctly-formatted Unicode data table.
  ///
  init?(parsing tableData: Substring) {

    let components = tableData.split(separator: ";").map { $0.trimmingSpaces }
    guard components.count == 2 else { return nil }

    codePoints: do {
      let stringValue = components[0]
      if let singleValue = UInt32(stringValue, radix: 16) {
        self.codePoints = singleValue...singleValue
      } else {
        guard
          stringValue.contains("."),
          let rangeStart = UInt32(stringValue.prefix(while: { $0 != "." }), radix: 16),
          let rangeEnd = UInt32(stringValue.suffix(while: { $0 != "." }), radix: 16)
        else {
          return nil
        }
        self.codePoints = rangeStart...rangeEnd
      }
    }
    value: do {
      let stringValue = components[1]
      guard let bidiClass = BidiClass(rawValue: String(stringValue)) else {
        return nil
      }
      self.value = bidiClass
    }
    // Done.
  }
}


// --------------------------------------------
// MARK: - JoiningType
// --------------------------------------------


internal struct ParsedJoiningTypeEntry {

  var codePoints: ClosedRange<UInt32>
  var value: JoiningType

  enum JoiningType: String {
    case C = "C"
    case D = "D"
    case R = "R"
    case L = "L"
    case T = "T"
  }

  /// Parses the code-points and Joining\_Type from a given line of the Unicode data table.
  /// The given line must be stripped of its trailing comment.
  ///
  /// For example:
  ///
  /// ```
  /// 0640          ; C
  /// 07FA          ; C
  /// 0883..0885    ; C
  /// 0626          ; D
  /// 0628          ; D
  /// 062A..062E    ; D
  /// 0633..063F    ; D
  /// ```
  ///
  /// The validation here is minimal. The input data is presumed to be a correctly-formatted Unicode data table.
  ///
  init?(parsing tableData: Substring) {

    let components = tableData.split(separator: ";").map { $0.trimmingSpaces }
    guard components.count == 2 else { return nil }

    codePoints: do {
      let stringValue = components[0]
      if let singleValue = UInt32(stringValue, radix: 16) {
        self.codePoints = singleValue...singleValue
      } else {
        guard
          stringValue.contains("."),
          let rangeStart = UInt32(stringValue.prefix(while: { $0 != "." }), radix: 16),
          let rangeEnd = UInt32(stringValue.suffix(while: { $0 != "." }), radix: 16)
        else {
          return nil
        }
        self.codePoints = rangeStart...rangeEnd
      }
    }
    value: do {
      let stringValue = components[1]
      guard let joiningType = JoiningType(rawValue: String(stringValue)) else {
        return nil
      }
      self.value = joiningType
    }
    // Done.
  }
}
