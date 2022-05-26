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

@usableFromInline
internal struct IDNAValidationData: CodePointDatabase_Schema {
  @usableFromInline typealias ASCIIData = ValidationFlags
  @usableFromInline typealias UnicodeData = ValidationFlags
}

extension IDNAValidationData {

  @usableFromInline
  internal struct ValidationFlags: HasRawStorage, Equatable {

    @usableFromInline
    internal typealias RawStorage = UInt8

    @usableFromInline
    internal var storage: UInt8

    @inlinable
    internal init(storage: UInt8) {
      self.storage = storage
    }
  }
}


// swift-format-ignore
@usableFromInline
internal struct BidiInfo: Equatable {

  @inlinable internal static var L: Self                  { Self(value: 0) }
  @inlinable internal static var RorAL: Self              { Self(value: 1) }
  @inlinable internal static var AN: Self                 { Self(value: 2) }
  @inlinable internal static var EN: Self                 { Self(value: 3) }
  @inlinable internal static var ESorCSorETorONorBN: Self { Self(value: 4) }
  @inlinable internal static var NSM: Self                { Self(value: 5) }
  @inlinable internal static var other: Self              { Self(value: 6) }

  @usableFromInline
  internal var value: UInt8

  @inlinable
  init(value: UInt8) {
    self.value = value
  }
}
