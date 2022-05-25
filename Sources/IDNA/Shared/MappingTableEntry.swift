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

// FIXME: We have 2 schemas - One to build the database, and another to read it.
// Building uses nice types, but then it prints its storage as plain integers, so that's what the read schema
// uses. It would be nice to find a protocol hierarchy which let us read data automatically as the nice type.

@usableFromInline
internal struct IDNAMappingData: CodePointDatabase_Schema {}

@usableFromInline
internal struct RawIDNAData: CodePointDatabase_Schema {
  @usableFromInline internal typealias ASCIIData = UInt16
  @usableFromInline internal typealias UnicodeData = UInt32
}


// --------------------------------------------
// MARK: - ASCII
// --------------------------------------------


extension IDNAMappingData {

  /// An IDNA mapping table entry for an ASCII codepoint.
  ///
  /// ASCII code-points have simple entries, stored in a 1:1 lookup table.
  ///
  @usableFromInline
  internal struct ASCIIData: Equatable {

    // 2 bytes: <status> and <replacement>
    @usableFromInline
    internal var _storage: UInt16

    @inlinable
    internal init(_storage: UInt16) {
      self._storage = _storage
    }

    // Getting components.

    /// The status of this ASCII code-point.
    ///
    @inlinable
    internal var status: Status {
      Status(UInt8(truncatingIfNeeded: _storage &>> 8))
    }

    /// The replacement code-point to use instead of this code-point.
    ///
    /// This value is only specified if `isMapped` is `true`.
    ///
    @inlinable
    internal var replacement: Unicode.Scalar {
      Unicode.Scalar(UInt8(truncatingIfNeeded: _storage))
    }

    // Byte values and creation.

    @usableFromInline
    internal enum Status {
      case valid
      case disallowed_STD3_valid
      case mapped

      @inlinable
      internal init(_ integer: UInt8) {
        assert(integer <= 2)
        switch integer {
        case 0: self = .valid
        case 1: self = .disallowed_STD3_valid
        default: self = .mapped
        }
      }
    }

    @inlinable
    internal static var valid: Self {
      ASCIIData(_storage: 0x00_00)
    }

    @inlinable
    internal static var disallowed_STD3_valid: Self {
      ASCIIData(_storage: 0x01_00)
    }

    @inlinable
    internal static func mapped(to replacement: UInt8) -> Self {
      ASCIIData(_storage: 0x02_00 | UInt16(replacement))
    }

    // Other properties.

    /// If `true`, this entry's status is `.mapped`.
    ///
    /// It is a tiny bit faster to query this property than to check the precise value of `.status`.
    ///
    @inlinable
    internal var isMapped: Bool {
      _storage >= 0x02_00
    }

    @inlinable
    internal static func == (lhs: Self, rhs: Self) -> Bool {
      lhs._storage == rhs._storage
    }
  }
}


// --------------------------------------------
// MARK: - Unicode
// --------------------------------------------


extension IDNAMappingData {

  /// An IDNA mapping table entry, describing the status of a range of code-points.
  ///
  @usableFromInline
  internal struct UnicodeData {

    // high byte: 4 bits <status> and 4 bits <mapping-kind>
    // remaining: mapping data (3 bytes).
    @usableFromInline
    internal var _storage: UInt32

    @inlinable
    internal init(_storage: UInt32) {
      self._storage = _storage
    }

    @usableFromInline
    internal enum Status {
      case valid
      case deviation
      case disallowed_STD3_valid
      case mapped
      case disallowed_STD3_mapped
      case ignored
      case disallowed
    }

    @usableFromInline
    internal enum Mapping {
      case single(UInt32)
      case rebased(origin: UInt32)
      case table(ReplacementsTable.Index)
    }

    @inlinable
    internal var status: Status {
      // bits 31..<32 (1 bit)  = <unused>
      // bits 28..<31 (3 bits) = Status
      switch _storage &>> 28 {
      case 0: return .valid
      case 1: return .deviation
      case 2: return .disallowed_STD3_valid
      case 3: return .mapped
      case 4: return .disallowed_STD3_mapped
      case 5: return .ignored
      case 6: return .disallowed
      default:
        assertionFailure("Corrupt data")
        return .disallowed
      }
    }

    @inlinable
    internal var mapping: Mapping? {
      // bits 26..<28 (2 bit)  = <unused>
      // bits 24..<26 (2 bits) = Mapping Kind
      switch (_storage &>> 24) & 0b11 {
      case 0:
        return nil
      case 1:
        // bits 22..<24 (2 bit)   = <unused>
        // bits 00..<22 (21 bits) = Replacement
        return .single(_storage & 0x00FF_FFFF)
      case 2:
        // bits 22..<24 (2 bit)   = <unused>
        // bits 00..<22 (21 bits) = Origin
        return .rebased(origin: _storage & 0x00FF_FFFF)
      default:
        // bits 08..<24 (16 bits) = Offset
        // bits 00..<08 (08 bits) = Length
        let offset = UInt16(truncatingIfNeeded: _storage &>> 8)
        let length = UInt8(truncatingIfNeeded: _storage)
        return .table(ReplacementsTable.Index(offset: offset, length: length))
      }
    }
  }

  // Splitting location-sensitive data.

  @inlinable
  internal static func unicodeData(
    _ data: UnicodeData, at originalStart: UInt32, copyForStartingAt newStartPoint: UInt32
  ) -> UnicodeData {
    // If we split a rebase mapping across tables, the entry in the new table need to start with
    // an offset already applied. As it happens, this never occurs. Even if I implemented it,
    // the code would never get executed, so better to forbid it and get a message to take a look if it
    // ever triggers.
    if case .some(.rebased) = data.mapping {
      preconditionFailure("Rebased mappings are never split. Please file a bug report!")
    }
    // All other entries don't care which exact code-point they are linked against in the table.
    // They are "position-independent".
    return data
  }
}

extension IDNAMappingData.UnicodeData {

  init(_ status: Status, _ mapping: Mapping?) {

    var value: UInt32

    // bits 31..<32 (1 bit)  = <unused>
    // bits 28..<31 (3 bits) = Status
    switch status {
    case .valid:
      value = 0x0000_0000
    case .deviation:
      value = 0x1000_0000
    case .disallowed_STD3_valid:
      value = 0x2000_0000
    case .mapped:
      value = 0x3000_0000
    case .disallowed_STD3_mapped:
      value = 0x4000_0000
    case .ignored:
      value = 0x5000_0000
    case .disallowed:
      value = 0x6000_0000
    }

    // bits 26..<28 (2 bit)  = <unused>
    switch mapping {
    case .none:
      break
    case .single(let replacement):
      // bits 24..<26 (2 bits)  = Mapping Kind
      // bits 22..<24 (2 bit)   = <unused>
      // bits 00..<22 (21 bits) = Replacement
      value = value | (1 << 24) | replacement
    case .rebased(let origin):
      // bits 24..<26 (2 bits)  = Mapping Kind
      // bits 22..<24 (2 bit)   = <unused>
      // bits 00..<22 (21 bits) = Origin
      value = value | (2 << 24) | origin
    case .table(let index):
      // bits 24..<26 (2 bits)  = Mapping Kind
      // bits 08..<24 (16 bits) = Offset
      // bits 00..<08 (08 bits) = Length
      value = value | (3 << 24) | (UInt32(index.offset) &<< 8) | UInt32(index.length)
    }

    self._storage = value
  }
}


// --------------------------------------------
// MARK: - Replacements Table
// --------------------------------------------


@usableFromInline
internal struct ReplacementsTable {

  @usableFromInline
  internal struct Index {

    @usableFromInline
    internal var offset: UInt16

    @usableFromInline
    internal var length: UInt8

    @inlinable
    internal init(offset: UInt16, length: UInt8) {
      self.offset = offset
      self.length = length
    }

    @inlinable
    internal func get(table: [Unicode.Scalar]) -> ArraySlice<Unicode.Scalar> {
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
      precondition(!mapping.isEmpty, "Attempt to insert empty mapping")
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

    internal func isInBounds(_ index: Index) -> Bool {
      Int(index.offset) + Int(index.length) <= self.length
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
