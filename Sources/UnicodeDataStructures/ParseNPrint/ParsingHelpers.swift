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

  /// Helper utilities for parsing Unicode data files.
  ///
  internal enum ParsingHelpers {}

  extension ParsingHelpers {

    /// A mapping of code-points to a single property value.
    ///
    /// This value can be parsed from a line of various Unicode data tables.
    ///
    internal struct CodePointsToProperty<Property> where Property: RawRepresentable, Property.RawValue == String {

      internal var codePoints: ClosedRange<UInt32>
      internal var value: Property

      /// Parses a value from a line of a Unicode data table.
      ///
      /// The range of code-points should be specified as a hexadecimal integer or range of integers,
      /// separated from the property value by a semicolon. Spaces will be trimmed from both values.
      ///
      /// If the line contains a comment (as many Unicode data tables do), it must be stripped before parsing.
      /// For example, valid inputs for parsing the value `Bidi_Class`, which has values `"L"` and `"AN"`, would be:
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
      internal init?(parsing tableData: Substring) {
        let components = tableData.split(separator: ";").map { $0.trimmingSpaces }
        guard components.count == 2 else { return nil }
        codePoints: do {
          let stringValue = components[0]
          guard let codePoints = parseCodePointRange(stringValue) else { return nil }
          self.codePoints = codePoints
        }
        value: do {
          let stringValue = components[1]
          guard let value = Property(rawValue: String(stringValue)) else { return nil }
          self.value = value
        }
        // Done.
      }
    }
  }

  extension ParsingHelpers {

    /// Parses a codepoint range, as typically expressed in Unicode data tables.
    ///
    /// Accepted formats are:
    ///
    /// - Single 32-bit integer in hex notation (case insensitive)
    /// - Two 32-bit integers in hex notation (case insensitive), separated by two dots ("..").
    ///
    /// For example: `"004AE"`, or `"0061..0071"`.
    ///
    /// The codepoints are validated as being \<= `0x10\_FFFF`, but may not be valid scalar values.
    ///
    internal static func parseCodePointRange(_ stringValue: Substring) -> ClosedRange<UInt32>? {

      if let singleValue = UInt32(stringValue, radix: 16) {
        return singleValue <= 0x10_FFFF ? singleValue...singleValue : nil
      } else {
        guard
          stringValue.contains("."),
          let rangeStart = UInt32(stringValue.prefix(while: { $0 != "." }), radix: 16), rangeStart <= 0x10_FFFF,
          let rangeEnd = UInt32(stringValue.suffix(while: { $0 != "." }), radix: 16), rangeEnd <= 0x10_FFFF
        else {
          return nil
        }
        return rangeStart...rangeEnd
      }
    }
  }

#endif  // WEBURL_UNICODE_PARSE_N_PRINT
