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


// --------------------------------------------
// MARK: - Newline and tab filtering
// --------------------------------------------


extension ASCII {

  /// Returns a collection with the same contents as the given collection,
  /// but without any newline characters or horizontal tabs.
  ///
  /// If the only newline or tab characters are at the ends of the source collection, this method returns
  /// a trimmed `SubSequence` of the original data. If the collection contains any additional newlines or tabs,
  /// it instead returns a wrapper which filters bytes on-demand.
  ///
  @inlinable
  internal static func filterNewlinesAndTabs<UTF8Bytes>(
    from utf8: UTF8Bytes
  ) -> Either<ASCII.NewlineAndTabFiltered<UTF8Bytes>, UTF8Bytes.SubSequence>
  where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    let trimmedSlice = utf8.trim { isNewlineOrTab($0) }
    if !trimmedSlice.isEmpty {
      let hasInternalNewlinesOrTabs =
        trimmedSlice.withContiguousStorageIfAvailable {
          $0.boundsChecked.uncheckedFastContainsTabOrCROrLF()
        } ?? trimmedSlice.contains(where: { isNewlineOrTab($0) })
      if hasInternalNewlinesOrTabs {
        return .left(ASCII.NewlineAndTabFiltered(unchecked: trimmedSlice))
      }
    }
    return .right(trimmedSlice)
  }

  /// Whether the given character is a newline or tab
  /// (`0x09` horizontal tab, `0x0A` line feed, or `0x0D` carriage return).
  ///
  @inlinable
  internal static func isNewlineOrTab(_ codeUnit: UInt8) -> Bool {
    (codeUnit & 0b1111_1011 == 0b0000_1001)  // horizontal tab (0x09) and carriage return (0x0D)
      || codeUnit == ASCII.lineFeed.codePoint
  }

  /// A collection of UTF8-encoded bytes with ASCII newline and tab characters lazily removed.
  ///
  @usableFromInline
  internal struct NewlineAndTabFiltered<Base> where Base: Collection, Base.Element == UInt8 {

    @usableFromInline
    internal let base: Base.SubSequence

    /// Creates a view over a slice whose start has already been trimmed of tabs and newlines.
    ///
    @inlinable
    internal init(unchecked base: Base.SubSequence) {
      assert(base.first.map { !ASCII.isNewlineOrTab($0) } ?? true, "slice has not been trimmed")
      self.base = base
    }

    /// Creates a view over a collection which may start with a tab or newline.
    ///
    @inlinable
    internal init(_ base: Base) {
      self.init(unchecked: base.drop(while: ASCII.isNewlineOrTab))
    }
  }
}

extension ASCII.NewlineAndTabFiltered: Collection {

  @usableFromInline typealias Index = Base.Index
  @usableFromInline typealias Element = Base.Element

  @inlinable
  internal var startIndex: Index {
    base.startIndex
  }

  @inlinable
  internal var endIndex: Index {
    base.endIndex
  }

  @inlinable
  internal subscript(position: Index) -> UInt8 {
    base[position]
  }

  @inlinable
  internal subscript(bounds: Range<Index>) -> Self {
    Self(unchecked: base[bounds])
  }

  @inlinable
  internal func index(after i: Index) -> Index {
    let next = base.index(after: i)
    return base[Range(uncheckedBounds: (next, endIndex))].fastFirstIndex { !ASCII.isNewlineOrTab($0) } ?? endIndex
  }

  @inlinable
  internal func formIndex(after i: inout Index) {
    base.formIndex(after: &i)
    i = base[Range(uncheckedBounds: (i, endIndex))].fastFirstIndex { !ASCII.isNewlineOrTab($0) } ?? endIndex
  }
}

extension ASCII.NewlineAndTabFiltered: BidirectionalCollection where Base: BidirectionalCollection {

  @inlinable
  internal func index(before i: Index) -> Index {
    // Note that decrementing startIndex does not trap (BidirectionalCollection does not require it);
    // it just keeps returning startIndex.
    return base[Range(uncheckedBounds: (startIndex, i))].fastLastIndex { !ASCII.isNewlineOrTab($0) } ?? startIndex
  }

  @inlinable
  internal func formIndex(before i: inout Index) {
    // Note that decrementing startIndex does not trap (BidirectionalCollection does not require it);
    // it just keeps returning startIndex.
    i = base[Range(uncheckedBounds: (startIndex, i))].fastLastIndex { !ASCII.isNewlineOrTab($0) } ?? startIndex
  }
}


// --------------------------------------------
// MARK: - Lowercasing
// --------------------------------------------


extension ASCII {

  /// A collection of UTF8-encoded bytes with ASCII uppercase alpha characters (A-Z) lazily replaced with their lowercase counterparts.
  /// Other characters are left unchanged.
  ///
  @usableFromInline
  internal struct Lowercased<Base> where Base: Sequence, Base.Element == UInt8 {

    @usableFromInline
    internal var base: Base

    @inlinable
    internal init(_ base: Base) {
      self.base = base
    }
  }
}

extension ASCII.Lowercased: Sequence {

  @usableFromInline typealias Element = UInt8

  @usableFromInline
  internal struct Iterator: IteratorProtocol {

    @usableFromInline
    internal var baseIterator: Base.Iterator

    @inlinable
    internal init(baseIterator: Base.Iterator) {
      self.baseIterator = baseIterator
    }

    @inlinable
    internal mutating func next() -> UInt8? {
      baseIterator.next().flatMap { ASCII($0)?.lowercased.codePoint ?? $0 }
    }
  }

  @inlinable
  internal func makeIterator() -> Iterator {
    Iterator(baseIterator: base.makeIterator())
  }
}

extension ASCII.Lowercased: Collection where Base: Collection {

  @usableFromInline typealias Index = Base.Index

  @inlinable
  internal var startIndex: Index {
    base.startIndex
  }

  @inlinable
  internal var endIndex: Index {
    base.endIndex
  }

  @inlinable
  internal subscript(position: Index) -> UInt8 {
    let byte = base[position]
    return ASCII(byte)?.lowercased.codePoint ?? byte
  }

  @inlinable
  internal func index(after i: Index) -> Index {
    base.index(after: i)
  }

  @inlinable
  internal func formIndex(after i: inout Index) {
    base.formIndex(after: &i)
  }

  @inlinable
  internal func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    base.index(i, offsetBy: distance, limitedBy: limit)
  }

  @inlinable
  internal func formIndex(_ i: inout Index, offsetBy distance: Int, limitedBy limit: Index) -> Bool {
    base.formIndex(&i, offsetBy: distance, limitedBy: limit)
  }

  @inlinable
  internal var count: Int {
    base.count
  }

  @inlinable
  internal var isEmpty: Bool {
    base.isEmpty
  }

  @inlinable
  internal func distance(from start: Index, to end: Index) -> Int {
    base.distance(from: start, to: end)
  }
}

extension ASCII.Lowercased: BidirectionalCollection where Base: BidirectionalCollection {

  @inlinable
  internal func index(before i: Index) -> Index {
    base.index(before: i)
  }

  @inlinable
  internal func formIndex(before i: inout Index) {
    base.formIndex(before: &i)
  }
}

extension ASCII.Lowercased: RandomAccessCollection where Base: RandomAccessCollection {
}
