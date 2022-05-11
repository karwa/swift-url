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

/// An entry in the IDNA mapping table.
///
public struct MappingTableEntry {

  @usableFromInline
  internal var _storage: UInt64

  @inlinable
  public init(_storage: UInt64) {
    self._storage = _storage
  }

  public enum Status {
    case valid
    case ignored
    case disallowed
    case disallowed_STD3_valid
    case deviation(Mapping?)
    case mapped(Mapping)
    case disallowed_STD3_mapped(Mapping)
  }

  public enum Mapping {
    case single(UInt32)
    case rebased(origin: UInt32)
    case table(ReplacementsTable.Index)
  }
}

// Compact representation.

extension MappingTableEntry {

  @inlinable
  public var codePoints: ClosedRange<UInt32> {
    // bits 63 - 42 (21 bits)
    let lowerBound = _storage &>> 42
    // bits 42 - 26 (16 bits)
    let delta = (_storage &>> 26) & 0xFFFF
    return ClosedRange(
      uncheckedBounds: (UInt32(truncatingIfNeeded: lowerBound), UInt32(truncatingIfNeeded: lowerBound &+ delta))
    )
  }

  @inlinable
  public var status: Status {
    // bits 26 - 23 (3 bits)
    switch (_storage &>> 23) & 0b111 {
    case 1: return .valid
    case 2: return .ignored
    case 3: return .disallowed
    case 4: return .disallowed_STD3_valid
    case 5: return .deviation(Self._parseMapping(_storage))
    case 6: return .mapped(Self._parseMapping(_storage)!)
    case 7: return .disallowed_STD3_mapped(Self._parseMapping(_storage)!)
    default: fatalError("Corrupt data")
    }
  }

  @inlinable
  internal static func _parseMapping(_ value: UInt64) -> Mapping? {
    // bits 23 - 21 (2 bits)
    switch (value &>> 21) & 0b11 {
    case 0:
      return nil
    case 1:
      // bits 0 - 21: replacement.
      let replacement = UInt32(truncatingIfNeeded: value & 0x1FFFF)
      return .single(replacement)
    case 2:
      // bits 0 - 21: origin.
      let origin = UInt32(truncatingIfNeeded: value & 0x1FFFF)
      return .rebased(origin: origin)
    case 3:
      // bits 0 - 21: index.
      // offset: bits 21 - 8 (13 bits)
      let offset = (value >> 8) & 0x1FFF
      // length: bits 8 - 0 (8 bits)
      let length = value & 0xFF
      return .table(
        ReplacementsTable.Index(offset: UInt16(truncatingIfNeeded: offset), length: UInt8(truncatingIfNeeded: length))
      )
    default:
      fatalError("Unreachable")
    }
  }

  // Script only:

  internal init(codePoints: ClosedRange<UInt32>, status: Status) {
    self.init(_storage: Self.toInt(codePoints: codePoints, status: status))
  }

  private static func toInt(codePoints: ClosedRange<UInt32>, status: Status) -> UInt64 {
    var value = UInt64.zero
    // bits 63 - 42 (21 bits)
    value = UInt64(codePoints.lowerBound) &<< 42
    // bits 42 - 26 (16 bits)
    let delta = codePoints.upperBound - codePoints.lowerBound
    precondition(
      delta <= UInt16.max,
      """
      ⚠️ Failed to Print Entry in Mapping Data - Delta too large! ⚠️
      codePoints: \(codePoints.lowerBound) ... \(codePoints.upperBound)
      delta: \(delta)
      """
    )
    value = value | UInt64(delta) &<< 26
    // bits 26 - 23 (3 bits)
    let mapping: Optional<Mapping>
    switch status {
    case .valid:
      value |= (1 << 23)
      mapping = .none
    case .ignored:
      value |= (2 << 23)
      mapping = .none
    case .disallowed:
      value |= (3 << 23)
      mapping = .none
    case .disallowed_STD3_valid:
      value |= (4 << 23)
      mapping = .none
    case .deviation(let _mapping):
      value |= (5 << 23)
      mapping = _mapping
    case .mapped(let _mapping):
      value |= (6 << 23)
      mapping = _mapping
    case .disallowed_STD3_mapped(let _mapping):
      value |= (7 << 23)
      mapping = _mapping
    }
    // bits 23 - 21 (2 bits)
    switch mapping {
    case .none:
      value = value & ~(0x1FFFF)
    case .single(let replacement):
      // bits 0 - 21: replacement.
      value = value | (1 << 21)
      value = value | UInt64(replacement & 0x1FFFF)
    case .rebased(let origin):
      // bits 0 - 21: origin.
      value = value | (2 << 21)
      value = value | UInt64(origin & 0x1FFFF)
    case .table(let index):
      // bits 0 - 21: index.
      value = value | (3 << 21)
      // offset: bits 21 - 8 (13 bits)
      precondition(index.offset < 0x1FFF)
      value = value | UInt64(index.offset) &<< 8
      // length: bits 8 - 0 (8 bits)
      // precondition(index.length < 0x80)
      value = value | UInt64(index.length)
    }
    return value
  }
}


public struct ReplacementsTable {

  public struct Index {

    @usableFromInline
    internal var offset: UInt16

    @usableFromInline
    internal var length: UInt8

    @inlinable
    public init(offset: UInt16, length: UInt8) {
      self.offset = offset
      self.length = length
    }

    @inlinable
    public func get(table: [Unicode.Scalar]) -> ArraySlice<Unicode.Scalar> {
      let start = Int(offset)
      let end = start &+ Int(length)
      return table[Range(uncheckedBounds: (start, end))]
    }
  }

  // Script only:

  internal struct Builder {
    private var data = [[UInt32]: Index]()
    private var length = 0

    internal mutating func insert(mapping: [UInt32]) -> Index {
      // If there is an existing mapping, return it.
      if let existingIndex = data[mapping] { return existingIndex }
      // The 'Index' defines where this appears in the output data;
      // construct one for the region of data that we need.
      let newIndex = Index(offset: UInt16(length), length: UInt8(mapping.count))
      self.length += mapping.count
      // Assign the region to the mapping.
      data[mapping] = newIndex
      return newIndex
    }

    internal func buildReplacementsTable() -> [UInt32] {
      let allItems =
        data
        // Sort by the value's region info. It's a bit confusing because the name is 'Index', but really
        // it describes where the mapping is supposed to be written.
        .sorted(by: { left, right in left.value.offset < right.value.offset })
        // Gather up the mapping tables for each region.
        .flatMap({ $0.key })
      precondition(allItems.count == length)
      return allItems
    }
  }
}
