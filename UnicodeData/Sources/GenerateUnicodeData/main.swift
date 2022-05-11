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

private var rawEntries = [RawMappingTableEntry]()
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

fileprivate struct RawMappingTableEntry {

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


// --------------------------------------------
// MARK: - Process, Optimize
// --------------------------------------------


// - Split the mappings off in to a separate table ("replacements table"),
//   so that every entry is a fixed-size scalar.

// TODO: Split the entries in to more tables - e.g. a table of just the starting code-point for lookup.
// TODO: Split the main code-point table in to several tables (in a more sophisticated way than the 'writing' step does).
//       - Probably some kind of trie? Aligned on Unicode planes so users don't cross sub-tables too often?

var processed = [MappingTableEntry]()
var replacements = ReplacementsTable.Builder()

for entry in rawEntries {

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

  processed.append(MappingTableEntry(codePoints: entry.codePoints, status: processedStatus))
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
  formatter: { #""\u{\#(String($0, radix: 16, uppercase: true))}""# },
  to: &output
)
output += "\n"

// Swift's support for static data tables is pretty poor.
// We need to split this in to smaller tables to avoid exponential memory growth
// and promote putting it in the static data section of the binary.

output +=
  """
  @usableFromInline
  internal typealias IDNAMappingTableSubArrayElt = UInt64\n
  """
output += "\n"

var splitArrayInfo = [(Int, ClosedRange<UInt32>)]()

var splitArrayNum = 0
var splitElements = [MappingTableEntry]()

for element in processed {
  splitElements.append(element)
  if splitElements.count == 250 {
    splitArrayInfo.append(
      (splitArrayNum, splitElements.first!.codePoints.lowerBound...splitElements.last!.codePoints.upperBound)
    )
    printArrayLiteral(
      name: "_idna_mapping_data_sub_\(splitArrayNum)",
      elementType: "IDNAMappingTableSubArrayElt",
      data: splitElements, columns: 5,
      formatter: { $0._storage.paddedHexString },
      to: &output
    )
    output += "\n"
    splitArrayNum += 1
    splitElements.removeAll(keepingCapacity: true)
  }
}
if !splitElements.isEmpty {
  splitArrayInfo.append(
    (splitArrayNum, splitElements.first!.codePoints.lowerBound...splitElements.last!.codePoints.upperBound)
  )
  printArrayLiteral(
    name: "_idna_mapping_data_sub_\(splitArrayNum)",
    elementType: "IDNAMappingTableSubArrayElt",
    data: splitElements, columns: 5,
    formatter: { $0._storage.paddedHexString },
    to: &output
  )
  output += "\n"
  splitElements.removeAll(keepingCapacity: true)
}

// Write the 2D array.

printArrayLiteral(
  name: "_idna_mapping_data_subs",
  elementType: "(ClosedRange<UInt32>, [IDNAMappingTableSubArrayElt])",
  data: splitArrayInfo, columns: 1,
  formatter: { "(\($1), _idna_mapping_data_sub_\($0))" },
  to: &output
)

// Print to stdout.

precondition(output.last == "\n")
output.removeLast()

print(output)
