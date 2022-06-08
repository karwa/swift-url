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

/// A `SegmentedLine` is a one-dimensional space, where every location is assigned a value.
///
/// `SegmentedLine` is effective when entire regions are assigned the same value.
/// For example, we can build a simple number line to tag ranges of integers; in this case,
/// we're tagging each range with an optional string.
///
/// ```swift
/// var line = SegmentedLine<Int, String?>(bounds: 0..<100, value: nil)
///
/// // After setting values <5 to "small" and values >10 to "large",
/// // the gap is left with its previous value, "medium".
///
/// line.set(0..<20,  to: "medium")
/// line.set(0..<5,   to: "small")
/// line.set(10..<60, to: "large")
/// print(line)
/// // | [0..<5]: "small" | [5..<10]: "medium" | [10..<60]: "large" | [60..<100]: nil |
/// ```
///
/// The locations on a `SegmentedLine` do not have to be integers - they can be any `Comparable` type,
/// including dates, strings, Unicode scalars (for building character sets), or `Collection` indexes.
///
/// In the latter case, we can model a Collection's elements as a line from its `startIndex` to its `endIndex`,
/// allowing us to annotate regions of any Collection. In a way, it can be used as a generalized `AttributedString`.
///
/// ```swift
/// let string = "Bob is feeling great"
///
/// // Create a SegmentedLine for the collection's contents.
/// // Start by setting a font attribute over the entire string.
///
/// var tags = SegmentedLine(
///   bounds: string.startIndex..<string.endIndex,
///   value: [Font.custom("Comic Sans")] as [Any]
/// )
///
/// // Set each word to a different color.
/// // Use 'modify' to append the attribute, but only for the region
/// // we're modifying.
///
/// for word: Substring in string.split(separator: " ") {
///   tags.modify(word.startIndex..<word.endIndex) { attributes in
///     attributes.append(Color.random())
///   }
/// }
///
/// // Check the result.
/// // - ✅ Every segment still contains the font attribute.
/// // - ✅ Each word also contains its individual color attribute.
///
/// for (range, attributes) in tags.segments {
///   print(#""\#(string[range])""#, "-", attributes)
/// }
///
/// // "Bob"     [Font.custom("Comic Sans"), Color.orange]
/// // " "       [Font.custom("Comic Sans")]
/// // "is"      [Font.custom("Comic Sans"), Color.green]
/// // " "       [Font.custom("Comic Sans")]
/// // "feeling" [Font.custom("Comic Sans"), Color.pink]
/// // " "       [Font.custom("Comic Sans")]
/// // "great"   [Font.custom("Comic Sans"), Color.yellow]
/// ```
///
public struct SegmentedLine<Bound, Value> where Bound: Comparable {

  @usableFromInline internal typealias BreakPoint = (location: Bound, value: Value)

  // This array must never be empty.
  // There must always be an initial breakPoint which defines our lowerBound and starting value.
  @usableFromInline internal var _data: [BreakPoint]

  // The value of `Bound` at which the final breakPoint ends.
  // This is necessary to ensure that all regions of the table cover an expressible range of positions,
  // without requiring a concept like Swift's `PartialRangeFrom` for the final region.
  @usableFromInline internal var _upperBound: Bound

  /// Creates a new space with the given bounds and value.
  ///
  /// All locations within the bounds will be assigned the initial value.
  ///
  /// ```swift
  /// let line = SegmentedLine<Int, String>(bounds: 0..<100, value: "default")
  /// print(line)  // | [0..<100]: default |
  /// ```
  ///
  /// `bounds` must not be empty.
  ///
  @inlinable
  public init(bounds: Range<Bound>, value: Value) {
    precondition(bounds.lowerBound < bounds.upperBound, "Invalid range for SegmentedLine bounds")
    self._data = [(location: bounds.lowerBound, value: value)]
    self._upperBound = bounds.upperBound
  }

  /// Memberwise initializer. Would be fileprivate, but must be internal so it can also be @inlinable.
  ///
  @inlinable
  internal init(_upperBound: Bound, _data: [BreakPoint]) {
    precondition(!_data.isEmpty && _upperBound > _data[0].0, "SegmentedLine is invalid")
    self._upperBound = _upperBound
    self._data = _data
  }

  @inlinable
  internal var _lowerBound: Bound {
    _data[0].location
  }
}

extension SegmentedLine {

  /// The bounds of this space.
  ///
  /// All locations within these bounds have an assigned value.
  ///
  @inlinable
  public var bounds: Range<Bound> {
    Range(uncheckedBounds: (_lowerBound, _upperBound))
  }
}


// --------------------------------------------
// MARK: - Segments
// --------------------------------------------


extension SegmentedLine {

  /// The assigned regions of the space.
  ///
  /// A `SegmentedLine` divides its bounds in to segments. Values are assigned to entire segments,
  /// and apply to all locations within the segment.
  ///
  /// ```swift
  /// var line = SegmentedLine<Int, String?>(bounds: 0..<100, value: nil)
  ///
  /// line.set(0..<20,  to: "medium")
  /// line.set(0..<5,   to: "small")
  /// line.set(10..<60, to: "large")
  ///
  /// for (range, value) in line.segments {
  ///   print(range, value)
  ///   // Prints:
  ///   // 0..<5    small
  ///   // 5..<10   medium
  ///   // 10..<60  large
  ///   // 60..<100 nil
  /// }
  /// ```
  ///
  /// There are no gaps between segments - each segment starts where its predecessor ends.
  /// Every `SegmentedLine` begins with at least one segment, assigning a value to its entire ``bounds``.
  ///
  /// Segments are created as needed when values are assigned or modified. Consecutive segments with the same value
  /// are _not_ automatically merged (there is not even any requirement that values are `Equatable`),
  /// but they can be merged explicitly using the ``combineSegments(while:)`` function.
  ///
  @inlinable
  public var segments: Segments {
    Segments(_line: self)
  }

  public struct Segments {

    @usableFromInline
    internal var _line: SegmentedLine

    @inlinable
    internal init(_line: SegmentedLine) {
      self._line = _line
    }
  }
}

extension SegmentedLine.Segments: RandomAccessCollection {

  public struct Index: Comparable {

    /// An index in to the line's `_data` Array.
    @usableFromInline
    internal var _breakPointIndex: Int

    @inlinable
    internal init(_breakPointIndex: Int) {
      self._breakPointIndex = _breakPointIndex
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs._breakPointIndex < rhs._breakPointIndex
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs._breakPointIndex == rhs._breakPointIndex
    }
  }

  @inlinable
  public var startIndex: Index {
    Index(_breakPointIndex: _line._data.startIndex)
  }

  @inlinable
  public var endIndex: Index {
    Index(_breakPointIndex: _line._data.endIndex)
  }

  @inlinable
  public var count: Int {
    _line._data.count
  }

  @inlinable
  public var isEmpty: Bool {
    false
  }

  @inlinable
  public func index(after i: Index) -> Index {
    let (result, overflow) = i._breakPointIndex.addingReportingOverflow(1)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
    return Index(_breakPointIndex: result)
  }

  @inlinable
  public func index(before i: Index) -> Index {
    let (result, overflow) = i._breakPointIndex.subtractingReportingOverflow(1)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
    return Index(_breakPointIndex: result)
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    let (result, overflow) = i._breakPointIndex.addingReportingOverflow(distance)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
    return Index(_breakPointIndex: result)
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    let overflow: Bool
    (i._breakPointIndex, overflow) = i._breakPointIndex.addingReportingOverflow(1)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    let overflow: Bool
    (i._breakPointIndex, overflow) = i._breakPointIndex.subtractingReportingOverflow(1)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
  }

  @inlinable
  public func formIndex(_ i: inout Index, offsetBy distance: Int) {
    let overflow: Bool
    (i._breakPointIndex, overflow) = i._breakPointIndex.subtractingReportingOverflow(distance)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
  }

  @inlinable
  public func distance(from i: Index, to j: Index) -> Int {
    let (result, overflow) = j._breakPointIndex.subtractingReportingOverflow(i._breakPointIndex)
    assert(!overflow, "Invalid index - encountered overflow in indexing operation")
    return result
  }

  @inlinable
  public subscript(i: Index) -> (range: Range<Bound>, value: Value) {
    let (start, value) = _line._data[i._breakPointIndex]
    let valueEndIndex = index(after: i)._breakPointIndex
    let end = (valueEndIndex < _line._data.endIndex) ? _line._data[valueEndIndex].location : _line._upperBound
    assert(start < end, "We should never have empty segments")
    return (range: Range(uncheckedBounds: (start, end)), value: value)
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension SegmentedLine: CustomStringConvertible {

  @inlinable
  public var description: String {
    segments.reduce(into: "") { partial, segment in
      partial += "| [\(segment.range)]: \(segment.value) "
    } + "|"
  }
}

extension SegmentedLine: Equatable where Value: Equatable {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs._upperBound == rhs._upperBound else { return false }
    // Unfortunately, tuples are not Equatable so we need to write our own Array.==
    return lhs._data.withUnsafeBufferPointer { lhsBuffer in
      rhs._data.withUnsafeBufferPointer { rhsBuffer in
        guard lhsBuffer.count == rhsBuffer.count else { return false }
        if lhsBuffer.baseAddress == rhsBuffer.baseAddress { return true }
        return lhsBuffer.elementsEqual(rhsBuffer, by: { $0.location == $1.location && $0.value == $1.value })
      }
    }
  }
}

// TODO: Hashable, Codable, etc

//#if swift(>=5.5) && canImport(_Concurrency)
//  extension SegmentedLine: Sendable where Bound: Sendable, Value: Sendable {}
//#endif


// --------------------------------------------
// MARK: - Get, GetAll (TODO)
// --------------------------------------------


// TODO: Add 'get' (single location and range variants) -- and/or add APIs to .segments?


// --------------------------------------------
// MARK: - Set, Modify
// --------------------------------------------


extension SegmentedLine {

  @inlinable
  internal func _boundsCheck(_ range: Range<Bound>) {
    precondition(self._lowerBound <= range.lowerBound, "\(range) is out of bounds. Valid bounds are \(self.bounds)")
    precondition(self._upperBound >= range.upperBound, "\(range) is out of bounds. Valid bounds are \(self.bounds)")
  }

  /// Ensures that the line's `_data` array contains a breakPoint at the given location.
  ///
  /// - returns: The index of the breakPoint for the given location, and a flag marking
  ///            whether was inserted or existed before this function was called.
  ///
  @inlinable
  internal mutating func _ensureSegmentBreak(at location: Bound) -> (Array<BreakPoint>.Index, inserted: Bool) {

    assert(location < self._upperBound, "location is not in bounds")
    if location == self.bounds.lowerBound {
      return (_data.startIndex, inserted: false)
    }

    // TODO: Limit search.
    let idx = _data._codepointdatabase_partitionedIndex { $0.location < location }
    if idx == _data.endIndex || _data[idx].location != location {
      let valueAtLocation = _data[idx - 1].value
      _data.insert((location: location, value: valueAtLocation), at: idx)
      return (idx, inserted: true)
    }
    return (idx, inserted: false)
  }

  /// Ensures that the line's `_data` array contains breakPoints for the given range's `upperBound` and `lowerBound`.
  ///
  /// - returns: A range of breakPoint indices. The lowerBound of this range is the index of a breakPoint
  ///            whose location is the lowerBound of the given range. Similarly, the upperBound of the range
  ///            refers to a breakPoint for the given range's upperBound.
  ///            If the given range was empty, the result is `nil`.
  ///
  @inlinable
  internal mutating func _ensureSegmentBreaks(for boundsToSplit: Range<Bound>) -> Range<Array<BreakPoint>.Index>? {

    _boundsCheck(boundsToSplit)
    guard !boundsToSplit.isEmpty else { return nil }

    // Ensure there is a break to preserve values >= 'upperBound'.

    var dataIndexForUpperBound: Array<BreakPoint>.Index

    if boundsToSplit.upperBound == bounds.upperBound {
      dataIndexForUpperBound = _data.endIndex
    } else {
      let (idx, _) = _ensureSegmentBreak(at: boundsToSplit.upperBound)
      assert(idx > _data.startIndex, "A non-empty in-bounds range cannot end at startIndex")
      dataIndexForUpperBound = idx
    }

    // Ensure there is a break to apply the new value at locations >= 'lowerBound'.
    // If we insert anything, we must increment 'endOfOldData' to keep it pointing to the correct element.

    let dataIndexForLowerBound: Array<BreakPoint>.Index

    let startDataWasInserted: Bool
    (dataIndexForLowerBound, startDataWasInserted) = _ensureSegmentBreak(at: boundsToSplit.lowerBound)
    if startDataWasInserted { dataIndexForUpperBound += 1 }

    assert(dataIndexForLowerBound < dataIndexForUpperBound)  // Ensure not empty.
    return dataIndexForLowerBound..<dataIndexForUpperBound
  }

  /// Assigns a single value to all locations in the given region.
  ///
  /// Any segments which intersect the region will be split, preserving the values of locations
  /// outside the region. Locations inside the region will be covered by a single segment,
  /// containing the given value.
  ///
  /// ```swift
  /// var line = SegmentedLine<Int, String?>(bounds: 0..<100, value: nil)
  ///
  /// // After setting values <5 to "small" and values >10 to "large",
  /// // the gap is left with its previous value, "medium".
  ///
  /// line.set(0..<20,  to: "medium")
  /// line.set(0..<5,   to: "small")
  /// line.set(10..<60, to: "large")
  /// print(line)
  /// // | [0..<5]: "small" | [5..<10]: "medium" | [10..<60]: "large" | [60..<100]: nil |
  ///
  /// // After setting, there will be a single span covering the given region.
  ///
  /// line.set(5..<100, to: "not small")
  /// print(line)
  /// // | [0..<5]: "small" | [5..<100]: "not small" |
  /// ```
  ///
  /// `boundsToReplace` must be entirely within the ``bounds`` of this space.
  /// Assigning a value to an empty range will not modify any segments.
  ///
  /// Every location within the bounds of this space is assigned a value.
  /// Every `SegmentedLine` begins with at least one segment, assigning a value to its entire bounds
  /// (in the above example, the value's type is an `Optional` and the initial value is `nil`).
  ///
  /// - parameters:
  ///   - boundsToReplace: The locations which should be assigned the new value.
  ///                      Must be entirely within this space's ``bounds``.
  ///   - newValue:        The value to assign.
  ///
  @inlinable
  public mutating func set(_ boundsToReplace: Range<Bound>, to newValue: Value) {

    guard let breakPointIndices = _ensureSegmentBreaks(for: boundsToReplace) else {
      return  // Range is empty.
    }

    assert(_data[breakPointIndices.lowerBound].location == boundsToReplace.lowerBound)

    // To apply: assign the new value at the first breakPoint (lowerBound),
    // then remove all other breakPoints in the range.

    _data[breakPointIndices.lowerBound].value = newValue
    _data.removeSubrange(breakPointIndices.lowerBound + 1..<breakPointIndices.upperBound)
  }

  /// Modifies the values assigned to the given region.
  ///
  /// Any segments which intersect the region will be split, preserving the values of locations
  /// outside the region. Locations inside the region will be visited by the given closure, which may
  /// assign a new value derived from the existing value.
  ///
  /// ```swift
  /// let string = "Bob is feeling great"
  ///
  /// // Create a SegmentedLine for the collection's contents.
  /// // Start by setting a font attribute over the entire string.
  ///
  /// var tags = SegmentedLine(
  ///   bounds: string.startIndex..<string.endIndex,
  ///   value: [Font.custom("Comic Sans")] as [Any]
  /// )
  ///
  /// // Set each word to a different color.
  /// // Use 'modify' to append the attribute, but only for the region
  /// // we're modifying.
  ///
  /// for word: Substring in string.split(separator: " ") {
  ///   tags.modify(word.startIndex..<word.endIndex) { attributes in
  ///     attributes.append(Color.random())
  ///   }
  /// }
  ///
  /// // Check the result.
  /// // - ✅ Every segment still contains the font attribute.
  /// // - ✅ Each word also contains its individual color attribute.
  ///
  /// for (range, attributes) in tags.segments {
  ///   print(#""\#(string[range])""#, "-", attributes)
  /// }
  ///
  /// // "Bob"     [Font.custom("Comic Sans"), Color.orange]
  /// // " "       [Font.custom("Comic Sans")]
  /// // "is"      [Font.custom("Comic Sans"), Color.green]
  /// // " "       [Font.custom("Comic Sans")]
  /// // "feeling" [Font.custom("Comic Sans"), Color.pink]
  /// // " "       [Font.custom("Comic Sans")]
  /// // "great"   [Font.custom("Comic Sans"), Color.yellow]
  /// ```
  ///
  /// `boundsToModify` must be entirely within the ``bounds`` of this space.
  /// Modifying an empty range will not modify any segments, and may not invoke the closure at all.
  ///
  /// - parameters:
  ///   - boundsToModify: The locations whose values should be modified.
  ///                     Must be within this space's ``bounds``.
  ///   - body:           A closure which modifies values associated with the given locations.
  ///
  @inlinable
  public mutating func modify(_ boundsToModify: Range<Bound>, _ body: (inout Value) -> Void) {

    guard let breakPointIndices = _ensureSegmentBreaks(for: boundsToModify) else {
      return  // Range is empty.
    }

    assert(_data[breakPointIndices.lowerBound].location == boundsToModify.lowerBound)

    // To apply: visit the values of all segments in the range.

    for i in breakPointIndices {
      body(&_data[i].value)
    }
  }
}


// --------------------------------------------
// MARK: - Table Optimizations
// --------------------------------------------


extension SegmentedLine {

  /// Returns a new `SegmentedLine`, created by transforming this line's values using the given closure.
  ///
  /// The result will have the same bounds and number of segments as this line, at the same locations.
  ///
  /// This function can be particularly effective at simplifying lines with lots of segments, as by mapping
  /// complex values to simplified ones (for example, mapping to an `enum` with fewer cases), we can discard
  /// information that isn't needed. This can lead to adjacent segments containing the same value more often,
  /// to be combined by ``combineSegments()``.
  ///
  /// ```swift
  /// // ℹ️ Imagine we have a complex SegmentedLine with lots of small segments
  /// //    capturing granular details, and we'd like to simplify it.
  ///
  /// enum ComplexData {
  ///   case categoryA, categoryB, categoryC // ...
  /// }
  /// let complexLine: SegmentedLine<Int, ComplexData> = // ...
  /// print(complexLine)
  /// // | [0..<2]: categoryA | [2..<4]: categoryB | [4..<12]: categoryC | ...
  ///
  /// // 1️⃣ Perhaps we can map these to a smaller number of states.
  ///
  /// enum SimplifiedData {
  ///   case valid, invalid
  /// }
  /// var simplifiedLine = complexLine.mapValues { complex in
  ///   SimplifiedData(validating: complex)
  /// }
  /// print(simplifiedLine)
  /// // | [0..<2]: valid | [2..<4]: valid | [4..<12]: valid | ...
  ///
  /// // 2️⃣ Notice that we have lots of segments for boundaries which
  /// //    which are no longer important. 'combineSegments' can clean them up.
  ///
  /// simplifiedLine.combineSegments()
  /// print(simplifiedLine)
  /// // | [0..<2000]: valid | [2000..<2024]: invalid | [2024..<2056]: valid | ...
  /// ```
  ///
  @inlinable
  public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> SegmentedLine<Bound, T> {
    SegmentedLine<Bound, T>(
      _upperBound: _upperBound,
      _data: try _data.map { ($0.0, try transform($0.1)) }
    )
  }

  /// Merges segments according to the given closure.
  ///
  /// This function implements a left-fold, similar to Collection's `reduce`, except that the folding closure
  /// can decide to preserve a segment break and reset the fold operation.
  ///
  /// The closure is invoked with two segments as arguments - an `accumulator`, which has a mutable value,
  /// and `next`, which is its successor on this line. Given these segments, the closure may decide:
  ///
  /// - To combine `next` and `accumulator`.
  ///
  ///   To fold segments, the closure performs any required adjustments to merge `next.value`
  ///   in to `accumulator.value`, and returns `true`. The segment `next` will be discarded,
  ///   and the accumulator's range will expand up to `next.range.upperBound`.
  ///
  ///   Folding continues with the same accumulator for as long as the closure returns `true`;
  ///   this process is similar to Collection's `reduce(into:)` function.
  ///
  /// - To maintain the segment break.
  ///
  ///   If it is not desirable to combine the segments, the closure may return `false`.
  ///   This finalizes the current accumulator, and restarts folding with `next` as the new accumulator.
  ///
  @inlinable
  public mutating func combineSegments(
    while shouldMerge: (_ accumulator: inout Segments.Element, _ next: Segments.Element) -> Bool
  ) {
    var reduced: [BreakPoint] = []
    var accumulator = segments[segments.startIndex]
    for next in segments.dropFirst() {
      let accumulatorStart = accumulator.range.lowerBound
      if shouldMerge(&accumulator, next) {
        accumulator.range = Range(uncheckedBounds: (accumulatorStart, next.range.upperBound))
      } else {
        reduced.append((accumulatorStart, accumulator.value))
        accumulator = next
      }
    }
    reduced.append((accumulator.range.lowerBound, accumulator.value))
    self._data = reduced
  }
}

extension SegmentedLine where Value: Equatable {

  /// Merges segments of consecutive equal elements.
  ///
  /// This function can be particularly effective at simplifying lines with lots of segments, as by mapping
  /// complex values to simplified ones (for example, mapping to an `enum` with fewer cases) using ``mapValues(_:)``,
  /// we can discard information that isn't needed. This can lead to adjacent segments containing the same value
  /// more often - segments which can then be combined by this function.
  ///
  /// ```swift
  /// // ℹ️ Imagine we have a complex SegmentedLine with lots of small segments
  /// //    capturing granular details, and we'd like to simplify it.
  ///
  /// enum ComplexData {
  ///   case categoryA, categoryB, categoryC // ...
  /// }
  /// let complexLine: SegmentedLine<Int, ComplexData> = // ...
  /// print(complexLine)
  /// // | [0..<2]: categoryA | [2..<4]: categoryB | [4..<12]: categoryC | ...
  ///
  /// // 1️⃣ Perhaps we can map these to a smaller number of states.
  ///
  /// enum SimplifiedData {
  ///   case valid, invalid
  /// }
  /// var simplifiedLine = complexLine.mapValues { complex in
  ///   SimplifiedData(validating: complex)
  /// }
  /// print(simplifiedLine)
  /// // | [0..<2]: valid | [2..<4]: valid | [4..<12]: valid | ...
  ///
  /// // 2️⃣ Notice that we have lots of segments for boundaries which
  /// //    which are no longer important. 'combineSegments' can clean them up.
  ///
  /// simplifiedLine.combineSegments()
  /// print(simplifiedLine)
  /// // | [0..<2000]: valid | [2000..<2024]: invalid | [2024..<2056]: valid | ...
  /// ```
  ///
  @inlinable
  public mutating func combineSegments() {
    combineSegments(while: { $0.value == $1.value })
  }
}
