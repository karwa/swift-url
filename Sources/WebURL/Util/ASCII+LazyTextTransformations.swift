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

  /// Returns a collection which has the same contents as the given collection, but without any newline characters or horizontal tabs.
  ///
  /// If the only newline or tab characters are at the ends of the given collection, this method returns a trimmed `SubSequence` of the original data in order to
  /// maintain the collection's performance characteristics. If the collection contains additional newlines or tabs, a lazily-filtering wrapper is returned instead.
  ///
  @inlinable
  internal static func filterNewlinesAndTabs<UTF8Bytes>(
    from utf8: UTF8Bytes
  ) -> Either<ASCII.NewlineAndTabFiltered<UTF8Bytes>, UTF8Bytes.SubSequence>
  where UTF8Bytes: BidirectionalCollection, UTF8Bytes.Element == UInt8 {

    let trimmedSlice = utf8.trim { isNewlineOrTab($0) }
    if trimmedSlice.isEmpty == false, trimmedSlice.contains(where: { isNewlineOrTab($0) }) {
      return .left(ASCII.NewlineAndTabFiltered(unchecked: trimmedSlice))
    }
    return .right(trimmedSlice)
  }

  /// If `true`, this character is a newline or tab (`0x0A` carriage return, `0x0D` line feed, or `0x09` horizontal tab).
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
    return base[Range(uncheckedBounds: (next, endIndex))].firstIndex { !ASCII.isNewlineOrTab($0) } ?? endIndex
  }

  @inlinable
  internal func formIndex(after i: inout Index) {
    base.formIndex(after: &i)
    i = base[Range(uncheckedBounds: (i, endIndex))].firstIndex { !ASCII.isNewlineOrTab($0) } ?? endIndex
  }
}

extension ASCII.NewlineAndTabFiltered: BidirectionalCollection where Base: BidirectionalCollection {

  @inlinable
  internal func index(before i: Index) -> Index {
    // Note that decrementing startIndex does not trap (BidirectionalCollection does not require it);
    // it just keeps returning startIndex.
    return base[Range(uncheckedBounds: (startIndex, i))].lastIndex { !ASCII.isNewlineOrTab($0) } ?? startIndex
  }

  @inlinable
  internal func formIndex(before i: inout Index) {
    // Note that decrementing startIndex does not trap (BidirectionalCollection does not require it);
    // it just keeps returning startIndex.
    i = base[Range(uncheckedBounds: (startIndex, i))].lastIndex { !ASCII.isNewlineOrTab($0) } ?? startIndex
  }
}


// --------------------------------------------
// MARK: - Lowercasing
// --------------------------------------------


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
