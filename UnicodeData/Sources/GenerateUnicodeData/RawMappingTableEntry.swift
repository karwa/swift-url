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

internal struct RawMappingTableEntry {

  var codePoints: ClosedRange<UInt32>
  var status: Status
  var mapping: [UInt32]?

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
  init?(parsing tableData: Substring) {

    let components = tableData.split(separator: ";").map { $0.trimmingSpaces }
    guard components.count >= 2 else { return nil }

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
    status: do {
      let stringValue = components[1]
      guard let status = Status(rawValue: String(stringValue)) else {
        return nil
      }
      self.status = status
    }
    if case .mapped_rebased = self.status {
      fatalError("Rebased status cannot be used when parsing")
    }
    mapping: do {
      switch self.status {
      case .mapped, .deviation, .disallowed_STD3_mapped:
        // Code-points are mapped; we must have a corresponding mapping entry.
        break
      default:
        // Code-points are unmapped or ignored (mapped to the empty string).
        self.mapping = nil
        break mapping
      }
      // If we're expecting mapping data, it must not be empty unless this is a deviation.
      let stringValue = components[2]
      if stringValue.isEmpty {
        guard case .deviation = self.status else { return nil }
        self.mapping = nil
        break mapping
      }
      var replacements = [UInt32]()
      for replacementScalar in stringValue.split(separator: " ") {
        guard let scalar = UInt32(replacementScalar, radix: 16) else {
          return nil
        }
        replacements.append(scalar)
      }
      precondition(!replacements.isEmpty)
      self.mapping = replacements
    }
    // Done.
  }
}

extension RawMappingTableEntry {

  func tryMerge(with next: RawMappingTableEntry) -> RawMappingTableEntry? {

    // Ranges must be contiguous.
    guard self.codePoints.upperBound + 1 == next.codePoints.lowerBound else {
      return nil
    }
    // FIXME: Don't merge entries if the merged result would contain > 0xFFFF code-points,
    //        because the length wouldn't fit in a 16-bit integer later. In future, we should
    //        go through a splitting phase to get the biggest blocks we can, aligned to script boundaries, etc.
    if self.codePoints.count + next.codePoints.count > UInt16.max {
      return nil
    }

    switch (self.status, next.status) {
    // No mapping data; the existing entry can simply be extended.
    case (.valid, .valid),
      (.ignored, .ignored),
      (.disallowed, .disallowed),
      (.disallowed_STD3_valid, .disallowed_STD3_valid):
      var copy = self
      copy.codePoints = self.codePoints.lowerBound...next.codePoints.upperBound
      return copy

    // Merge mapping data.
    case (.mapped, .mapped):
      let selfMapping = self.mapping!
      let otherMapping = next.mapping!
      // If the mapping data is identical, the existing entry can simply be extended.
      if selfMapping == otherMapping {
        var copy = self
        copy.codePoints = self.codePoints.lowerBound...next.codePoints.upperBound
        return copy
      }
      // If the mapping data is not identical, but are both mappings to single, sequential scalars,
      // we can merge both entries in to a mapped_rebased.
      if selfMapping.count == 1, otherMapping.count == 1, selfMapping[0] + 1 == otherMapping[0] {
        var copy = self
        copy.status = .mapped_rebased
        copy.codePoints = self.codePoints.lowerBound...next.codePoints.upperBound
        return copy
      }
    case (.mapped_rebased, .mapped):
      let selfMapping = self.mapping!
      let otherMapping = next.mapping!
      if otherMapping.count == 1, selfMapping[0] + UInt32(self.codePoints.count) == otherMapping[0] {
        var copy = self
        copy.codePoints = self.codePoints.lowerBound...next.codePoints.upperBound
        return copy
      }
    default:
      break
    }
    return nil
  }
}
