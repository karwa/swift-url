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

struct MappingTableEntry {

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
        self.codePoints = singleValue ... singleValue
      } else {
        guard
          stringValue.contains("."),
          let rangeStart = UInt32(stringValue.prefix(while: { $0 != "." }), radix: 16),
          let rangeEnd   = UInt32(stringValue.suffix(while: { $0 != "." }), radix: 16)
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


// Utilities.


extension Substring {

  var trimmingSpaces: Substring {
    let firstNonSpace = firstIndex(where: { $0 != " " }) ?? endIndex
    let lastNonSpace  = lastIndex(where: { $0 != " " }).map { index(after: $0) } ?? endIndex
    return self[firstNonSpace..<lastNonSpace]
  }
}

extension BidirectionalCollection {

  /// Returns the slice of this collection's trailing elements which match the given predicate.
  ///
  /// If no elements match the predicate, the returned slice is empty, from `endIndex..<endIndex`.
  ///
  @usableFromInline
  internal func suffix(while predicate: (Element) -> Bool) -> SubSequence {
    var i = endIndex
    while i > startIndex {
      let beforeI = index(before: i)
      guard predicate(self[beforeI]) else { return self[i..<endIndex] }
      i = beforeI
    }
    return self[startIndex..<endIndex]
  }
}

extension UInt32 {
  var hexString: String {
    "0x" + String(self, radix: 16, uppercase: true)
  }
}


// Script


import Foundation

// 1. Load the mapping table.
let mappingTableURL = URL(fileURLWithPath: #filePath, isDirectory: false)
  .deletingLastPathComponent()
  .appendingPathComponent("IdnaMappingTable.txt")
let entireMappingTable = try String(contentsOf: mappingTableURL)

// 2. Parse the entries.
var entries = [MappingTableEntry]()
for line in entireMappingTable.split(separator: "\n").filter({ !$0.starts(with: "#") }) {
  let data = line.prefix { $0 != "#" }
  let comment = line[data.endIndex...].dropFirst()
  guard let entry = MappingTableEntry(parsing: data) else {
    fatalError("FAILED TO PARSE: \(data) -- \(comment)")
  }
  entries.append(entry)
}

// TODO: 3. Transform the raw, parsed entries in to some kind of optimized/compact form.

// 4. Write the data out as a Swift file which can be imported by the IDNA module.

// TODO: Include IDNA table version in output file

var output = #"""
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

  internal enum IDNAMappingStatus {

    /// The code point is valid, and not modified.
    case valid

    /// The code point is removed: this is equivalent to mapping the code point to an empty string.
    case ignored

    /// The code point is replaced in the string by the value for the mapping.
    case mapped

    /// The code point is either mapped or valid, depending on whether the processing is transitional or not.
    case deviation

    /// The code point is not allowed.
    case disallowed

    /// The status is disallowed if `UseSTD3ASCIIRules=true` (the normal case);
    /// implementations that allow `UseSTD3ASCIIRules=false` would treat the code point as **valid**.
    case disallowed_STD3_valid

    /// the status is disallowed if `UseSTD3ASCIIRules=true` (the normal case);
    /// implementations that allow `UseSTD3ASCIIRules=false` would treat the code point as **mapped**.
    case disallowed_STD3_mapped
  }

  internal typealias IDNAMappingTableSubArrayElt = (
    codepoints: ClosedRange<UInt32>, status: IDNAMappingStatus, mapping: [UInt32]?
  )

  """# + "\n"

// Swift's support for static data tables is pretty poor.
// We need to split this in to smaller tables to avoid exponential memory growth
// and promote putting it in the static data section of the binary.

struct SubArray {
  var string: String
  var number: Int
  var count: Int

  init(number: Int) {
    self.number = number
    self.count = 0
    self.string = #"""
    // swift-format-ignore
    internal let _idna_mapping_data_sub_\#(number): [IDNAMappingTableSubArrayElt] = [
    """# + "\n"
  }

  mutating func append(_ entry: MappingTableEntry) {
    count += 1

    string += "  ("
    string += "codepoints: ClosedRange<UInt32>(uncheckedBounds: (\(entry.codePoints.lowerBound.hexString), \(entry.codePoints.upperBound.hexString))), "
    string += "status: IDNAMappingStatus.\(entry.status), "

    if let mapping = entry.mapping {
      precondition(!mapping.isEmpty)
      string += "mapping: [\(mapping.map { $0.hexString }.joined(separator: ", "))]"
    } else {
      string += "nil"
    }
    string += "),\n"
  }

  func finalizedIfFull() -> (serialization: String, next: SubArray)? {
    guard count == 100 else {
      precondition(count < 100)
      return nil
    }
    return (serialization: self.finalized(), next: SubArray(number: self.number + 1))
  }

  func finalized() -> String {
    self.string + "]\n"
  }
}

// Write the sub-arrays.

var sub = SubArray(number: 0)
for entry in entries {
  sub.append(entry)
  if let (serialization, nextSub) = sub.finalizedIfFull() {
    output += serialization
    output += "\n"
    sub = nextSub
  }
}
output += sub.finalized()
output += "\n"

// Write the 2D array.

output += #"""
// swift-format-ignore
internal let _idna_mapping_data_subs: [[IDNAMappingTableSubArrayElt]] = [
"""# + "\n"
for subArrayIndex in 0...sub.number {
  output += "  _idna_mapping_data_sub_\(subArrayIndex),\n"
}
output += "]"

// Print to stdout.

print(output)
