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

extension Collection {

  /// Returns  a collection whose elements are slices of this collection, with up to `maxLength` elements per slice.
  ///
  /// - parameters:
  ///     - maxLength:  The maximum number of elements to appear in each row of the resulting collection.
  ///
  @inlinable
  public func split(maxLength: Int) -> LazySplitCollection<Self> {
    return LazySplitCollection(base: self, rowLength: maxLength)
  }
}

public struct LazySplitCollection<Base: Collection> {
  @usableFromInline let base: Base
  @usableFromInline let rowLength: Int
  public let startIndex: Index

  @inlinable
  init(base: Base, rowLength: Int) {
    precondition(rowLength > 0, "Cannot split a Collection in to rows of 0 or negative length")
    self.base = base
    self.rowLength = rowLength
    self.startIndex = Index(
      start: base.startIndex,
      end: base.index(base.startIndex, offsetBy: rowLength, limitedBy: base.endIndex) ?? base.endIndex
    )
  }
}

extension LazySplitCollection: Collection {
  public typealias Element = Base.SubSequence

  public struct Index: Equatable, Comparable {
    @usableFromInline var lowerBound: Base.Index
    @usableFromInline var upperBound: Base.Index

    @inlinable
    init(start: Base.Index, end: Base.Index) {
      self.lowerBound = start
      self.upperBound = end
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      return lhs.lowerBound == rhs.lowerBound && lhs.upperBound == rhs.upperBound
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      return lhs.lowerBound < rhs.lowerBound
    }
  }

  @inlinable
  public var endIndex: Index {
    return Index(start: base.endIndex, end: base.endIndex)
  }

  @inlinable
  public var isEmpty: Bool {
    return base.isEmpty
  }

  @inlinable
  public var count: Int {
    let x = base.count.quotientAndRemainder(dividingBy: rowLength)
    return x.quotient + x.remainder.signum()
  }

  @inlinable
  public func distance(from start: Index, to end: Index) -> Int {
    let x = base.distance(from: start.lowerBound, to: end.lowerBound).quotientAndRemainder(dividingBy: rowLength)
    return x.quotient + x.remainder.signum()
  }

  @inlinable
  public subscript(position: Index) -> Base.SubSequence {
    // Interestingly, *slicing* from endIndex is allowed (and returns an empty slice),
    // so we need to do our own bounds-checking here.
    precondition(position.lowerBound != base.endIndex, "Cannot subscript endIndex")
    return base[position.lowerBound..<position.upperBound]
  }

  // Index traversal.

  @inlinable
  public func index(after i: Index) -> Index {
    return index(i, offsetBy: 1)
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    formIndex(&i, offsetBy: 1)
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    var i = i
    guard formIndex(&i, offsetBy: distance, limitedBy: distance > 0 ? endIndex : startIndex) else {
      fatalError("Index out of bounds")
    }
    return i
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    var i = i
    guard formIndex(&i, offsetBy: distance, limitedBy: limit) else { return nil }
    return i
  }

  @inlinable
  public func formIndex(_ i: inout Index, offsetBy distance: Int, limitedBy limit: Index) -> Bool {
    guard distance != 0 else { return true }
    if distance > 0 {
      guard limit > i else {
        i = limit
        return false
      }
      // Advance by (distance - 1) complete rows. If even that fails, `distance` is clearly too large.
      guard base.formIndex(&i.lowerBound, offsetBy: rowLength * (distance - 1), limitedBy: limit.lowerBound) else {
        i = limit
        return false
      }
      // Try to advance by another whole row.
      // If it fails, `limit` is less than `rowLength` away (i.e. we have an incomplete row).
      // Given that we have one step to go, the desired index must be `limit`. Success.
      guard base.formIndex(&i.lowerBound, offsetBy: rowLength, limitedBy: limit.lowerBound) else {
        i = limit
        return true
      }
      // `i.lowerBound` is in the correct position. Advance `upperBound` by up to `rowLength`.
      i.upperBound = i.lowerBound
      _ = base.formIndex(&i.upperBound, offsetBy: rowLength, limitedBy: limit.lowerBound)
      return true

    } else {
      assert(distance < 0)
      guard limit <= i else {
        i = limit
        return false
      }
      // Initial decrement.
      if i.lowerBound == base.endIndex {
        var remainder = base.count.quotientAndRemainder(dividingBy: rowLength).remainder
        remainder = (remainder != 0) ? remainder : rowLength
        guard base.formIndex(&i.lowerBound, offsetBy: -remainder, limitedBy: limit.lowerBound) else {
          i = limit
          return false
        }
        assert(i.upperBound == base.endIndex)
      } else {
        i.upperBound = i.lowerBound
        guard base.formIndex(&i.lowerBound, offsetBy: -rowLength, limitedBy: limit.lowerBound) else {
          i = limit
          return false
        }
        assert(i.upperBound != base.endIndex)
      }
      assert(
        base.distance(from: base.startIndex, to: i.lowerBound).isMultiple(of: rowLength),
        "We should be aligned to a row start at this point")
      // Now that we are aligned to a row boundary, offset by multiples of rowLength.
      guard distance != -1 else { return true }
      i.upperBound = i.lowerBound
      guard base.formIndex(&i.upperBound, offsetBy: rowLength * (distance + 2), limitedBy: limit.lowerBound) else {
        i = limit
        return false
      }
      i.lowerBound = i.upperBound
      return base.formIndex(&i.lowerBound, offsetBy: -rowLength, limitedBy: limit.lowerBound)
    }
  }
}

extension LazySplitCollection: BidirectionalCollection, RandomAccessCollection where Base: RandomAccessCollection {

  @inlinable
  public func index(before i: Index) -> Index {
    return self.index(i, offsetBy: -1)
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    self.formIndex(&i, offsetBy: -1)
  }
}
