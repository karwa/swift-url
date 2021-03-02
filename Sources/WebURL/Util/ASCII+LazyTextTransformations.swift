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

import Algorithms

// MARK: - ASCII.NewlineAndTabFiltered


extension ASCII {

  /// A collection of UTF8-encoded bytes with ASCII newline and tab characters lazily removed.
  ///
  struct NewlineAndTabFiltered<Base> where Base: Collection, Base.Element == UInt8 {
    private let base: Base.SubSequence

    /// Creates a `NewlineAndTabFiltered` view over the given collection.
    ///
    init(_ base: Base) {
      // We only need to trim one side. This is a subtle difference from 'filterIfNeeded', but it shouldn't
      // result in any visible behaviour differences:
      // - endIndex is still "past the end". It is no longer "1 past the end", but that isn't important,
      //   since 'index(after:)' snaps to endIndex whenever there are no more valid indexes,
      //   whatever the precise value of 'endIndex' happens to be. It does not require any more steps.
      // - If we trim everything, base.startIndex == base.endIndex, so 'isEmpty' still works.
      self.base = base.drop(while: { Self.isAllowedByte($0) == false })
    }

    /// Creates a `NewlineAndTabFiltered` over a slice whose start has already been trimmed of filtered characters.
    ///
    private init(unchecked_slice base: Base.SubSequence) {
      assert(base.first.map { Self.isAllowedByte($0) } ?? true, "slice has not been trimmed")
      self.base = base
    }

    internal static func isAllowedByte(_ byte: UInt8) -> Bool {
      return byte != ASCII.horizontalTab.codePoint && byte != ASCII.carriageReturn.codePoint
        && byte != ASCII.lineFeed.codePoint
    }
  }
}

extension ASCII.NewlineAndTabFiltered: Collection {
  typealias Index = Base.Index
  typealias Element = Base.Element

  var startIndex: Index {
    return base.startIndex
  }
  var endIndex: Index {
    return base.endIndex
  }
  subscript(position: Index) -> UInt8 {
    return base[position]
  }
  subscript(bounds: Range<Index>) -> Self {
    return Self(unchecked_slice: base[bounds])
  }
  func index(after i: Index) -> Index {
    let next = base.index(after: i)
    return base[Range(uncheckedBounds: (next, endIndex))].firstIndex(where: Self.isAllowedByte) ?? endIndex
  }
  func formIndex(after i: inout Index) {
    base.formIndex(after: &i)
    i = base[Range(uncheckedBounds: (i, endIndex))].firstIndex(where: Self.isAllowedByte) ?? endIndex
  }
}

extension ASCII.NewlineAndTabFiltered: BidirectionalCollection where Base: BidirectionalCollection {

  /// Trims ASCII newline and tab characters from the given collection. If the resulting slice still contains characters that require filtering,
  /// this method returns a `NewlineAndTabFiltered` view over that slice (`.left`).
  /// If the trimmed slice does not contain any more ASCII newlines or tabs, and so does not require further filtering,
  /// this method returns that slice without wrapping (`.right`).
  ///
  static func filterIfNeeded(_ base: Base) -> Either<Self, Base.SubSequence> {
    let trimmedSlice = base.trim(where: { isAllowedByte($0) == false })
    if trimmedSlice.isEmpty == false, trimmedSlice.contains(where: { isAllowedByte($0) == false }) {
      return .left(Self(unchecked_slice: trimmedSlice))
    }
    return .right(trimmedSlice)
  }

  func index(before i: Index) -> Index {
    precondition(i != startIndex)
    return base[Range(uncheckedBounds: (startIndex, i))].lastIndex(where: Self.isAllowedByte) ?? startIndex
  }
  func formIndex(before i: inout Index) {
    precondition(i != startIndex)
    i = base[Range(uncheckedBounds: (startIndex, i))].lastIndex(where: Self.isAllowedByte) ?? startIndex
  }
}


// MARK: - ASCII.Lowercased


extension ASCII {

  /// A collection of UTF8-encoded bytes with ASCII alpha characters (A-Z) lazily replaced with their lowercase counterparts.
  /// Other bytes are left unchanged.
  ///
  struct Lowercased<Base> where Base: Sequence, Base.Element == UInt8 {
    private var base: Base

    init(_ base: Base) {
      self.base = base
    }
  }
}

extension ASCII.Lowercased: Sequence {
  typealias Element = UInt8

  struct Iterator: IteratorProtocol {
    var baseIterator: Base.Iterator

    mutating func next() -> UInt8? {
      let byte = baseIterator.next()
      return ASCII(flatMap: byte)?.lowercased.codePoint ?? byte
    }
  }

  func makeIterator() -> Iterator {
    return Iterator(baseIterator: base.makeIterator())
  }
}

extension ASCII.Lowercased: Collection where Base: Collection {
  typealias Index = Base.Index

  var startIndex: Index {
    return base.startIndex
  }
  var endIndex: Index {
    return base.endIndex
  }
  subscript(position: Index) -> UInt8 {
    let byte = base[position]
    return ASCII(byte)?.lowercased.codePoint ?? byte
  }
  func index(after i: Index) -> Index {
    return base.index(after: i)
  }
  func formIndex(after i: inout Index) {
    base.formIndex(after: &i)
  }
  // Since we don't alter the 'count', these may be cheaper than Collection's default implementations.
  var count: Int {
    return base.count
  }
  var isEmpty: Bool {
    return base.isEmpty
  }
  func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    return base.index(i, offsetBy: distance, limitedBy: limit)
  }
  func distance(from start: Index, to end: Index) -> Int {
    return base.distance(from: start, to: end)
  }
}

extension ASCII.Lowercased: BidirectionalCollection where Base: BidirectionalCollection {

  func index(before i: Index) -> Index {
    return base.index(before: i)
  }
  func formIndex(before i: inout Index) {
    base.formIndex(before: &i)
  }
}

extension ASCII.Lowercased: RandomAccessCollection where Base: RandomAccessCollection {
}
