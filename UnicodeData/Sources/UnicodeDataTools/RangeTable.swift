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

/// A `RangeTable` is a space in values of the `Bound` type, where contiguous regions
/// may be 'painted' with a value.
///
/// It is like a number line, but within some fixed bounds (that do not have to be numbers).
/// For example, we can tag ranges of integers with strings:
///
/// ```swift
/// var table = RangeTable<Int, String?>(bounds: 0..<100, initialValue: nil)
///
/// table.set(0..<20, to: "small")
/// table.set(0..<1, to: "tiny")
/// table.set(10..<60, to: "big")
/// print(table)
/// // | [0..<1]: "tiny" | [1..<10]: "small" | [10..<60]: "big" | [60..<100]: nil |
/// ```
///
/// Or we could tag ranges of arbitrary Collections. The following example demonstrates tagging regions
/// of a `String`, but the same could be used for `[Int]` or any other collection, for tagging arbitrary data:
///
/// ```swift
/// let string = "Bob is feeling great"
/// var table = RangeTable(
///   bounds: string.startIndex..<string.endIndex,
///   initialValue: DetectedFeature?.none
/// )
///
/// // Perhaps we detect a person's name in the string.
/// let detectedName: Substring = ...
/// table.set(
///   detectedName.startIndex..<detectedName.endIndex,
///   to: .personsName
/// )
///
/// for (range, feature) in table.spans {
///   print(#""\#(string[range])""#, "-", feature)
/// }
/// // "Bob" - DetectedFeature.personsName
/// // " is feeling great" - nil
/// ```
///
public struct RangeTable<Bound, Element> where Bound: Comparable {

  /// The overall bounds of the table.
  ///
  /// All positions within these bounds have a corresponding value in this table.
  ///
  public private(set) var bounds: Range<Bound>

  @usableFromInline
  internal var _initialValue: Element

  // TODO: Split _data array for better binary search performance.

  @usableFromInline
  internal var _data: [(breakPoint: Bound, value: Element)]

  /// Creates a new table with the given bounds and initial value.
  ///
  /// All positions within the bounds will be assigned the initial value.
  ///
  /// ```swift
  /// let table = RangeTable<Int, String>(
  ///   bounds: 0..<100, initialValue: "default"
  /// )
  ///
  /// print(table)  // | [0..<100]: default |
  /// ```
  ///
  public init(bounds: Range<Bound>, initialValue: Element) {
    self.bounds = bounds
    self._initialValue = initialValue
    self._data = []
  }
}


// --------------------------------------------
// MARK: - Spans
// --------------------------------------------


extension RangeTable {

  /// Spans divide the table's `bounds` in to regions with the same value.
  ///
  /// There are no gaps between spans - each span starts immediately where its predecessor ends,
  /// for the entire bounds of the table. Consecutive spans may have the same value, although
  /// `RangeTable` offers operations to merge spans.
  ///
  @inlinable
  public var spans: Spans {
    Spans(_table: self)
  }

  public struct Spans {

    @usableFromInline
    internal var _table: RangeTable

    @inlinable
    internal init(_table: RangeTable) {
      self._table = _table
    }
  }
}

extension RangeTable.Spans: RandomAccessCollection {

  public struct Index: Comparable {

    // There is an implicit span from 'bounds.lowerBound' with value 'initialValue'.
    // After that, all spans are defined by a breakpoint in the 'data' array.
    // This value is the index _after_ that breakpoint, so:
    // - 0    = The implicit span
    // - 1... = Value defined by break-point at 'data[index.endEntry - 1]'

    @usableFromInline
    internal var endEntry: Int

    @inlinable
    internal init(endEntry: Int) {
      self.endEntry = endEntry
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.endEntry < rhs.endEntry
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.endEntry == rhs.endEntry
    }
  }

  @inlinable
  public var startIndex: Index {
    Index(endEntry: 0)
  }

  @inlinable
  public var endIndex: Index {
    Index(endEntry: _table._data.endIndex + 1)
  }

  @inlinable
  public var count: Int {
    _table._data.count + 1
  }

  @inlinable
  public var isEmpty: Bool {
    false
  }

  @inlinable
  public func index(after i: Index) -> Index {
    Index(endEntry: i.endEntry + 1)
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    i.endEntry += 1
  }

  @inlinable
  public func index(before i: Index) -> Index {
    Index(endEntry: i.endEntry - 1)
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    i.endEntry -= 1
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    Index(endEntry: i.endEntry + distance)
  }

  @inlinable
  public func distance(from i: Index, to j: Index) -> Int {
    j.endEntry - i.endEntry
  }

  @inlinable
  public subscript(i: Index) -> (range: Range<Bound>, data: Element) {
    precondition(i.endEntry >= 0 && i.endEntry <= _table._data.endIndex, "Index out of bounds")
    // Implicit span.
    if i.endEntry == 0 {
      let endOfImplicitSpan = _table._data.first?.breakPoint ?? _table.bounds.upperBound
      return (_table.bounds.lowerBound..<endOfImplicitSpan, _table._initialValue)
    }
    // Break-point-delimited spans.
    let spanStart = _table._data[i.endEntry - 1]
    let spanEnd = (i.endEntry == _table._data.endIndex) ? _table.bounds.upperBound : _table._data[i.endEntry].breakPoint
    precondition(spanStart.breakPoint != spanEnd, "There should not be any empty spans")
    return (spanStart.breakPoint..<spanEnd, spanStart.value)
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension RangeTable: CustomStringConvertible {

  @inlinable
  public var description: String {
    spans.reduce(into: "") { partial, block in
      partial += "| [\(block.range)]: \(block.data) "
    } + "|"
  }
}

extension RangeTable: Equatable where Element: Equatable {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.bounds == rhs.bounds && lhs._initialValue == rhs._initialValue
      && lhs._data.elementsEqual(rhs._data, by: { $0.breakPoint == $1.breakPoint && $0.value == $1.value })
  }
}


// --------------------------------------------
// MARK: - Get, Set, Modify
// --------------------------------------------


extension RangeTable {

  @inlinable
  internal func _boundsCheck(range: Range<Bound>) {
    precondition(
      self.bounds.contains(range.lowerBound),
      "\(range) is out of bounds. Valid bounds are \(self.bounds)"
    )
    precondition(
      self.bounds.contains(range.upperBound) || self.bounds.upperBound == range.upperBound,
      "\(range) is out of bounds. Valid bounds are \(self.bounds)"
    )
  }

  /// Sets a value over a given region.
  ///
  /// This function overwrites all previously-inserted values contained within the given region.
  ///
  /// ```swift
  /// var table = RangeTable<Int, String?>(bounds: 0..<100, initialValue: nil)
  ///
  /// table.set(0..<20, to: "small")
  /// table.set(0..<1, to: "tiny")
  /// table.set(10..<60, to: "big")
  /// print(table)
  /// // | [0..<1]: "tiny" | [1..<10]: "small" | [10..<60]: "big" | [60..<100]: nil |
  /// ```
  ///
  /// This function does not merge adjacent regions.
  ///
  public mutating func set(_ boundsToReplace: Range<Bound>, to newValue: Element) {

    _boundsCheck(range: boundsToReplace)
    guard !boundsToReplace.isEmpty else { return }

    // Ensure there is a break to preserve values >= 'upperBound'.

    var endOfOldData: Array<(Bound, Element)>.Index

    if boundsToReplace.upperBound == bounds.upperBound {
      endOfOldData = _data.endIndex
    } else {
      if _data.isEmpty {
        _data.append((breakPoint: boundsToReplace.upperBound, value: _initialValue))
        endOfOldData = _data.startIndex
      } else {
        let idx = _data._codepointdatabase_partitionedIndex { $0.breakPoint < boundsToReplace.upperBound }
        if idx == _data.endIndex || _data[idx].breakPoint != boundsToReplace.upperBound {
          let valueAtUpperBound = (idx == _data.startIndex) ? _initialValue : _data[idx - 1].value
          _data.insert((breakPoint: boundsToReplace.upperBound, value: valueAtUpperBound), at: idx)
        }
        endOfOldData = idx
      }
    }

    // Ensure there is a break to apply the new value for >= 'lowerBound'.

    let startOfOldData: Array<(Bound, Element)>.Index

    if boundsToReplace.lowerBound == bounds.lowerBound {
      _initialValue = newValue
      startOfOldData = _data.startIndex
    } else {
      let idx = _data[..<endOfOldData]._codepointdatabase_partitionedIndex {
        $0.breakPoint < boundsToReplace.lowerBound
      }
      precondition(boundsToReplace.upperBound == bounds.upperBound || idx != _data.endIndex)
      _data.insert((breakPoint: boundsToReplace.lowerBound, value: newValue), at: idx)
      endOfOldData += 1
      startOfOldData = idx + 1
    }

    _data.removeSubrange(startOfOldData..<endOfOldData)
  }

  // FIXME: Add get, modify
}


// --------------------------------------------
// MARK: - Table Optimizations
// --------------------------------------------


extension RangeTable {

  /// Returns a new `RangeTable`, created by transforming all of this table's values using the given closure.
  ///
  /// The result will have the same number of spans as this table, at the same locations.
  ///
  /// An effective technique when simplifying complex tables is to first map the table's elements to a
  /// simplified, normalized form (for example, to an `enum` with fewer cases). This leads to lots of consecutive
  /// spans with the same value, which can be efficiently compacted by calling ``mergeElements(where:)``.
  ///
  /// ```swift
  /// enum ComplexData {
  ///   case categoryA, categoryB, categoryC // ... lots of cases ...
  /// }
  /// let table: RangeTable<Int, ComplexData> = // ...
  /// print(table)
  /// // | [0..<2]: categoryA | [2..<4]: categoryB | [4..<12]: categoryC | ...
  ///
  /// enum SimplifiedData {
  ///   case yes, no, invalid
  /// }
  /// var simplifiedTable = table.mapElements { complexData in
  ///   SimplifiedData(converting: complexData)
  /// }
  /// print(simplifiedTable)
  /// // | [0..<2]: yes | [2..<4]: yes | [4..<12]: yes | ...
  /// // Lots of duplicates because we mapped them all to the same value!
  ///
  /// simpliedTable.mergeElements()
  /// print(simplifiedTable)
  /// // | [0..<2000]: yes | [2000..<2024]: invalid | [2024..<2056]: yes | ...
  /// // Much better :)
  /// ```
  ///
  @inlinable
  public func mapElements<T>(_ transform: (Element) throws -> T) rethrows -> RangeTable<Bound, T> {
    var new = RangeTable<Bound, T>(bounds: self.bounds, initialValue: try transform(self._initialValue))
    new._data = try self._data.map { ($0.0, try transform($0.1)) }
    return new
  }

  /// Merges spans for as long as the given predicate returns `true`.
  ///
  /// The first argument to the predicate (`running`) is the value in to which spans are being merged.
  /// The second argument (`next`) is the value of the next span which you can decide to merge or not.
  ///
  /// An effective technique when simplifying complex tables is to first map the table's elements to a
  /// simplified, normalized form (for example, to an `enum` with fewer cases) uing ``mapElements(_:)``.
  /// This leads to lots of consecutive spans with the same value, which can be efficiently compacted
  /// by calling this function.
  ///
  /// ```swift
  /// enum ComplexData {
  ///   case categoryA, categoryB, categoryC // ... lots of cases ...
  /// }
  /// let table: RangeTable<Int, ComplexData> = // ...
  /// print(table)
  /// // | [0..<2]: categoryA | [2..<4]: categoryB | [4..<12]: categoryC | ...
  ///
  /// enum SimplifiedData {
  ///   case yes, no, invalid
  /// }
  /// var simplifiedTable = table.mapElements { complexData in
  ///   SimplifiedData(converting: complexData)
  /// }
  /// print(simplifiedTable)
  /// // | [0..<2]: yes | [2..<4]: yes | [4..<12]: yes | ...
  /// // Lots of duplicates because we mapped them all to the same value!
  ///
  /// simpliedTable.mergeElements()
  /// print(simplifiedTable)
  /// // | [0..<2000]: yes | [2000..<2024]: invalid | [2024..<2056]: yes | ...
  /// // Much better :)
  /// ```
  ///
  @inlinable
  public mutating func mergeElements(where shouldMerge: (_ running: Element, _ next: Element) -> Bool) {
    var reduced: [(Bound, Element)] = []
    var lastValue = _initialValue
    for breakpoint in _data {
      if !shouldMerge(lastValue, breakpoint.value) {
        reduced.append(breakpoint)
        lastValue = breakpoint.value
      }
    }
    self._data = reduced
  }
}

extension RangeTable where Element: Equatable {

  /// Merges spans of consecutive equal elements.
  ///
  /// An effective technique when simplifying complex tables is to first map the table's elements to a
  /// simplified, normalized form (for example, to an `enum` with fewer cases) uing ``mapElements(_:)``.
  /// This leads to lots of consecutive spans with the same value, which can be efficiently compacted
  /// by calling this function.
  ///
  /// ```swift
  /// enum ComplexData {
  ///   case categoryA, categoryB, categoryC // ... lots of cases ...
  /// }
  /// let table: RangeTable<Int, ComplexData> = // ...
  /// print(table)
  /// // | [0..<2]: categoryA | [2..<4]: categoryB | [4..<12]: categoryC | ...
  ///
  /// enum SimplifiedData {
  ///   case yes, no, invalid
  /// }
  /// var simplifiedTable = table.mapElements { complexData in
  ///   SimplifiedData(converting: complexData)
  /// }
  /// print(simplifiedTable)
  /// // | [0..<2]: yes | [2..<4]: yes | [4..<12]: yes | ...
  /// // Lots of duplicates because we mapped them all to the same value!
  ///
  /// simpliedTable.mergeElements()
  /// print(simplifiedTable)
  /// // | [0..<2000]: yes | [2000..<2024]: invalid | [2024..<2056]: yes | ...
  /// // Much better :)
  /// ```
  ///
  @inlinable
  public mutating func mergeElements() {
    mergeElements(where: { $0 == $1 })
  }
}
