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

/// Data used to validate domain labels in IDNA.
///
/// Validity criteria are described by [UTS#46](https://unicode.org/reports/tr46/#Validity_Criteria).
///
public struct IDNAValidationData: CodePointDatabase_Schema {
  public typealias ASCIIData = ValidationFlags
  public typealias UnicodeData = ValidationFlags
}

extension IDNAValidationData {

  public struct ValidationFlags: HasRawStorage, Equatable {

    public typealias RawStorage = UInt8

    public var storage: UInt8

    @inlinable
    public init(storage: UInt8) {
      self.storage = storage
    }

    // Reading and writing properties.

    @inlinable
    public var bidiInfo: BidiInfo {
      // Bidi_Class gets the low 3 bits.
      get { BidiInfo(value: storage & 0b0000_0111) }
      set { storage = (storage & ~0b0000_0111) | newValue.value }
    }

    @inlinable
    public var joiningType: JoiningType {
      // Joining_Type gets the next 3 bits.
      get { JoiningType(value: (storage & 0b0011_1000) &>> 3) }
      set { storage = (storage & ~0b0011_1000) | (newValue.value &<< 3) }
    }

    @inlinable
    public var isVirama: Bool {
      // The next bit marks the 61 code-points with CCC=virama.
      // Having this here means we can avoid a lookup in the standard library's data tables.
      get { (storage & 0b0100_0000) != 0 }
      set { storage = newValue ? (storage | 0b0100_0000) : (storage & ~0b0100_0000) }
    }

    @inlinable
    public var isMark: Bool {
      // The final bit is to mark the ~2000 code-points with General_Category=Mark.
      // Having this here means we can avoid a lookup in the standard library's data tables.
      get { (storage & 0b1000_0000) != 0 }
      set { storage = newValue ? (storage | 0b1000_0000) : (storage & ~0b1000_0000) }
    }

    // Creation.

    @inlinable
    internal init(bidiInfo: BidiInfo, joiningType: JoiningType, isVirama: Bool, isMark: Bool) {
      self.storage = 0
      self.bidiInfo = bidiInfo
      self.joiningType = joiningType
      self.isVirama = isVirama
      self.isMark = isMark
    }
  }
}

extension IDNAValidationData.ValidationFlags {

  // swift-format-ignore
  public struct BidiInfo: Equatable {

    @inlinable public static var L: Self                  { Self(value: 0) }
    @inlinable public static var RorAL: Self              { Self(value: 1) }
    @inlinable public static var AN: Self                 { Self(value: 2) }
    @inlinable public static var EN: Self                 { Self(value: 3) }
    @inlinable public static var ESorCSorETorONorBN: Self { Self(value: 4) }
    @inlinable public static var NSM: Self                { Self(value: 5) }
    @inlinable public static var disallowed: Self         { Self(value: 6) }

    @usableFromInline
    internal var value: UInt8

    @inlinable
    init(value: UInt8) {
      self.value = value
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.value == rhs.value
    }
  }

  // swift-format-ignore
  public struct JoiningType: Equatable {

    @inlinable public static var other: Self { Self(value: 0) }
    @inlinable public static var T: Self     { Self(value: 1) }
    @inlinable public static var D: Self     { Self(value: 2) }
    @inlinable public static var L: Self     { Self(value: 3) }
    @inlinable public static var R: Self     { Self(value: 4) }

    @usableFromInline
    internal var value: UInt8

    @inlinable
    init(value: UInt8) {
      self.value = value
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.value == rhs.value
    }
  }
}
