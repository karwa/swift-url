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
/// line.set(0..<10,  to: "small")
/// line.set(5..<20,  to: "medium")
/// line.set(10..<60, to: "large")
/// print(line)
/// // ┬
/// // ├ [0..<5]: "small"
/// // ├ [5..<10]: "medium"
/// // ├ [10..<60]: "large"
/// // ├ [60..<100]: nil
/// // ┴
/// ```
///
/// The locations on a `SegmentedLine` do not have to be integers - they can be any `Comparable` values,
/// including dates, strings, and `Collection` indexes.
///
/// For example, a line from a collection's `startIndex` to its `endIndex` can be used to annotate
/// regions of its elements, and can be used in a similar way to `AttributedString`.
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
/// // Use the '.modify' function to append a color attribute
/// // to each word.
///
/// for word in string.split(separator: " ") {
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

  /// The segment information for this line.
  ///
  /// Each entry contains a location, and a value which applies from that location
  /// until the next entry's location.
  ///
  /// The list is sorted by location and is never empty.
  /// The first entry defines the line's lowerBound.
  ///
  @usableFromInline
  internal var _breakpoints: BreakpointStorage

  /// The line's overall upperBound.
  ///
  /// The final entry in `_breakpoints` ends at this location.
  ///
  @usableFromInline
  internal var _upperBound: Bound

  /// Memberwise initializer.
  ///
  /// Would be **fileprivate**, but must be internal so it can be @inlinable.
  ///
  @inlinable
  internal init(_breakpoints: BreakpointStorage, _upperBound: Bound) {
    precondition(_upperBound > _breakpoints.locations[0], "Attempt to create a SegmentedLine with invalid bounds")
    self._breakpoints = _breakpoints
    self._upperBound = _upperBound
  }

  /// Creates a new space with the given bounds and value.
  ///
  /// All locations within the bounds will be assigned the initial value.
  ///
  /// ```swift
  /// let line = SegmentedLine(bounds: 0..<100, value: "default")
  /// print(line)  // [0..<100]: "default"
  /// ```
  ///
  /// `bounds` must not be empty.
  ///
  @inlinable
  public init(bounds: Range<Bound>, value: Value) {
    self.init(
      _breakpoints: BreakpointStorage(locations: [bounds.lowerBound], values: [value]),
      _upperBound: bounds.upperBound
    )
  }
}


// --------------------------------------------
// MARK: - Breakpoint Storage
// --------------------------------------------


extension SegmentedLine {

  /// The storage for a SegmentedLine.
  ///
  /// This type manages two separate physical allocations (`locations` and `values`)
  /// as a single logical list of `(Bound, Value)` pairs. It maintains the following invariants:
  ///
  /// - `locations` and `values` always have the same length.
  /// - `locations` and `values` are never empty.
  ///
  @usableFromInline
  internal struct BreakpointStorage {

    @usableFromInline
    internal private(set) var locations: [Bound]

    @usableFromInline
    internal private(set) var values: [Value]

    @inlinable
    internal init(locations: [Bound], values: [Value]) {
      precondition(!locations.isEmpty && locations.count == values.count)
      self.locations = locations
      self.values = values
    }
  }
}

extension SegmentedLine.BreakpointStorage: RandomAccessCollection {

  @usableFromInline
  internal typealias Index = Int

  @usableFromInline
  internal typealias Element = (location: Bound, value: Value)

  @inlinable
  internal var startIndex: Index { locations.startIndex }

  @inlinable
  internal var endIndex: Index { locations.endIndex }

  @inlinable
  internal var count: Int { locations.count }

  @inlinable
  internal var isEmpty: Bool { false }

  @inlinable
  internal func index(after i: Index) -> Index {
    let (result, overflow) = i.addingReportingOverflow(1)
    assert(!overflow, "Invalid index - operation overflowed")
    return result
  }

  @inlinable
  internal func index(before i: Index) -> Index {
    let (result, overflow) = i.subtractingReportingOverflow(1)
    assert(!overflow, "Invalid index - operation overflowed")
    return result
  }

  @inlinable
  internal func index(_ i: Index, offsetBy distance: Int) -> Index {
    let (result, overflow) = i.addingReportingOverflow(distance)
    assert(!overflow, "Invalid index - operation overflowed")
    return result
  }

  @inlinable
  internal func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    let (l, overflow) = limit.subtractingReportingOverflow(i)
    assert(!overflow, "Invalid index - operation overflowed")
    if distance > 0 ? l >= 0 && l < distance : l <= 0 && distance < l {
      return nil
    }
    return index(i, offsetBy: distance)
  }

  @inlinable
  internal func formIndex(after i: inout Index) {
    let overflow: Bool
    (i, overflow) = i.addingReportingOverflow(1)
    assert(!overflow, "Invalid index - operation overflowed")
  }

  @inlinable
  internal func formIndex(before i: inout Index) {
    let overflow: Bool
    (i, overflow) = i.subtractingReportingOverflow(1)
    assert(!overflow, "Invalid index - operation overflowed")
  }

  @inlinable
  internal func formIndex(_ i: inout Index, offsetBy distance: Int) {
    let overflow: Bool
    (i, overflow) = i.addingReportingOverflow(distance)
    assert(!overflow, "Invalid index - operation overflowed")
  }

  @inlinable
  internal func distance(from i: Index, to j: Index) -> Int {
    let (result, overflow) = j.subtractingReportingOverflow(i)
    assert(!overflow, "Invalid index - operation overflowed")
    return result
  }

  @inlinable
  internal subscript(i: Index) -> Element {
    precondition(i >= startIndex && i < endIndex, "Index out of bounds")
    return locations.withUnsafeBufferPointer { locationsPtr in
      values.withUnsafeBufferPointer { valuesPtr in
        (locationsPtr[i], valuesPtr[i])
      }
    }
  }
}

extension SegmentedLine.BreakpointStorage {

  @inlinable
  internal subscript(valueAt i: Index) -> Value {
    get {
      values[i]
    }
    _modify {
      yield &values[i]
    }
    set {
      values[i] = newValue
    }
  }

  @inlinable
  internal mutating func insert(_ newElement: Element, at index: Index) {
    locations.insert(newElement.location, at: index)
    values.insert(newElement.value, at: index)
  }

  @inlinable
  internal mutating func append(_ newElement: Element) {
    locations.append(newElement.location)
    values.append(newElement.value)
  }

  @inlinable
  internal mutating func removeSubrange(_ bounds: Range<Index>) {
    locations.removeSubrange(bounds)
    values.removeSubrange(bounds)
    precondition(!locations.isEmpty, "Removed all breakpoints")
  }
}


// --------------------------------------------
// MARK: - Segments View
// --------------------------------------------


extension SegmentedLine {

  /// The segments of this line.
  ///
  /// A `SegmentedLine` divides its bounds in to segments. Each segment starts where its predecessor ends,
  /// with no gaps, so that every value within the bounds belongs to a segment.
  /// Each segment has an associated value.
  ///
  /// ```swift
  /// var line = SegmentedLine<Int, String?>(bounds: 0..<100, value: nil)
  ///
  /// for (range, value) in line.segments {
  ///   print(range, value)
  ///   // Prints:
  ///   // 0..<100 nil
  /// }
  ///
  /// line.set(0..<10,  to: "small")
  /// line.set(5..<20,  to: "medium")
  /// line.set(10..<60, to: "large")
  ///
  /// for (range, value) in line.segments {
  ///   print(range, value)
  ///   // Prints:
  ///   // 0..<5    "small"
  ///   // 5..<10   "medium"
  ///   // 10..<60  "large"
  ///   // 60..<100 nil
  /// }
  /// ```
  ///
  /// Segments are created as needed when values are assigned or modified. Consecutive segments with the same value
  /// are _not_ merged automatically, but can be merged manually using the ``combineSegments(while:)`` function.
  ///
  /// The segment containing a location can be found by using the ``Segments-swift.struct/index(of:)`` function.
  ///
  @inlinable
  public var segments: Segments {
    Segments(self)
  }

  public struct Segments {

    @usableFromInline
    internal var _line: SegmentedLine

    @inlinable
    internal init(_ _line: SegmentedLine) {
      self._line = _line
    }
  }
}

extension SegmentedLine.Segments: RandomAccessCollection {

  public struct Index: Comparable {

    @usableFromInline
    internal var _breakpointIndex: SegmentedLine.BreakpointStorage.Index

    @inlinable
    internal init(_ _breakpointsIndex: SegmentedLine.BreakpointStorage.Index) {
      self._breakpointIndex = _breakpointsIndex
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs._breakpointIndex < rhs._breakpointIndex
    }

    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs._breakpointIndex == rhs._breakpointIndex
    }
  }

  @inlinable
  public var startIndex: Index {
    Index(_line._breakpoints.startIndex)
  }

  @inlinable
  public var endIndex: Index {
    Index(_line._breakpoints.endIndex)
  }

  @inlinable
  public var count: Int {
    _line._breakpoints.count
  }

  @inlinable
  public var isEmpty: Bool {
    _line._breakpoints.isEmpty
  }

  @inlinable
  public func index(after i: Index) -> Index {
    Index(_line._breakpoints.index(after: i._breakpointIndex))
  }

  @inlinable
  public func index(before i: Index) -> Index {
    Index(_line._breakpoints.index(before: i._breakpointIndex))
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    Index(_line._breakpoints.index(i._breakpointIndex, offsetBy: distance))
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    _line._breakpoints.index(i._breakpointIndex, offsetBy: distance, limitedBy: limit._breakpointIndex)
      .map { Index($0) }
  }

  @inlinable
  public func formIndex(after i: inout Index) {
    _line._breakpoints.formIndex(after: &i._breakpointIndex)
  }

  @inlinable
  public func formIndex(before i: inout Index) {
    _line._breakpoints.formIndex(before: &i._breakpointIndex)
  }

  @inlinable
  public func formIndex(_ i: inout Index, offsetBy distance: Int) {
    _line._breakpoints.formIndex(&i._breakpointIndex, offsetBy: distance)
  }

  @inlinable
  public func distance(from i: Index, to j: Index) -> Int {
    _line._breakpoints.distance(from: i._breakpointIndex, to: j._breakpointIndex)
  }

  @inlinable
  public subscript(i: Index) -> (range: Range<Bound>, value: Value) {
    let (start, value) = _line._breakpoints[i._breakpointIndex]
    let nextBreakIndex = index(after: i)._breakpointIndex
    let end =
      (nextBreakIndex < _line._breakpoints.endIndex)
      ? _line._breakpoints.locations[nextBreakIndex]
      : _line._upperBound
    assert(start < end, "We should never have empty segments")
    return (range: Range(uncheckedBounds: (start, end)), value: value)
  }
}

extension SegmentedLine.Segments {

  /// The index of the segment containing the given location.
  ///
  /// The location must be within the line's bounds.
  ///
  /// ```swift
  /// var line = SegmentedLine(bounds: 0..<50, value: 42)
  /// line.set(10..<20, to: 99)
  /// line.set(30..<50, to: 1024)
  /// print(line)
  /// // ┬
  /// // ├ [0..<10]: 42
  /// // ├ [10..<20]: 99
  /// // ├ [20..<30]: 42
  /// // ├ [30..<50]: 1024
  /// // ┴
  ///
  /// let i = line.segments.index(of: 35)
  /// print(line.segments[i])  // (range: 30..<50, value: 1024)
  /// ```
  ///
  /// - complexity: O(log *n*)
  ///
  @inlinable
  public func index(of location: Bound) -> Index {
    _line.boundsCheck(location)
    var idx = _line._breakpoints.locations._codepointdatabase_partitionedIndex { $0 < location }
    if idx == _line._breakpoints.endIndex || _line._breakpoints.locations[idx] != location {
      _line._breakpoints.formIndex(before: &idx)
    }
    return Index(idx)
  }
}


// --------------------------------------------
// MARK: - Standard Protocols
// --------------------------------------------


extension SegmentedLine: Equatable where Value: Equatable {

  @inlinable
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs._upperBound == rhs._upperBound
      && lhs._breakpoints.locations == rhs._breakpoints.locations
      && lhs._breakpoints.values == rhs._breakpoints.values
  }
}

extension SegmentedLine: Hashable where Bound: Hashable, Value: Hashable {

  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_upperBound)
    hasher.combine(_breakpoints.locations)
    hasher.combine(_breakpoints.values)
  }
}

extension SegmentedLine: CustomStringConvertible {

  @inlinable
  public var description: String {
    guard segments.count > 1 else {
      let singleSegment = segments.first!
      return "[\(singleSegment.range)]: \(singleSegment.value)"
    }
    return segments.reduce(into: "┬\n") { partial, segment in
      partial += "├ [\(segment.range)]: \(segment.value)\n"
    } + "┴"
  }
}

#if swift(>=5.5) && canImport(_Concurrency)

  extension SegmentedLine: Sendable where Bound: Sendable, Value: Sendable {}
  extension SegmentedLine.BreakpointStorage: Sendable where Bound: Sendable, Value: Sendable {}
  extension SegmentedLine.Segments: Sendable where Bound: Sendable, Value: Sendable {}

#endif


// --------------------------------------------
// MARK: - Bounds
// --------------------------------------------


extension SegmentedLine {

  /// The bounds of this space.
  ///
  /// All locations within these bounds have an assigned value.
  ///
  @inlinable
  public var bounds: Range<Bound> {
    Range(uncheckedBounds: (_breakpoints.locations[0], _upperBound))
  }

  /// Ensures the given location is within this line's ``bounds``.
  ///
  /// If the location is not within the line's bounds, the program terminates.
  /// This function should only be used for diagnostics, not memory safety.
  ///
  @inlinable
  internal func boundsCheck(_ location: Bound) {
    precondition(bounds.lowerBound <= location, "\(location) is out of bounds. Valid bounds are \(bounds)")
    precondition(bounds.upperBound > location, "\(location) is out of bounds. Valid bounds are \(bounds)")
  }

  /// Ensures the given range is within this line's ``bounds``.
  ///
  /// If the range is not within the line's bounds, the program terminates.
  /// This function should only be used for diagnostics, not memory safety.
  ///
  @inlinable
  internal func boundsCheck(_ range: Range<Bound>) {
    precondition(bounds.lowerBound <= range.lowerBound, "\(range) is out of bounds. Valid bounds are \(bounds)")
    precondition(bounds.upperBound >= range.upperBound, "\(range) is out of bounds. Valid bounds are \(bounds)")
  }
}


// --------------------------------------------
// MARK: - Get
// --------------------------------------------


extension SegmentedLine {

  /// The value assigned to a given location.
  ///
  /// The location must be within the line's ``bounds``.
  ///
  /// ```swift
  /// var line = SegmentedLine(bounds: 0..<50, value: 42)
  /// line.set(10..<20, to: 99)
  /// line.set(30..<50, to: 1024)
  /// print(line)
  /// // ┬
  /// // ├ [0..<10]: 42
  /// // ├ [10..<20]: 99
  /// // ├ [20..<30]: 42
  /// // ├ [30..<50]: 1024
  /// // ┴
  ///
  /// line[5]  // 42
  /// line[12] // 99
  /// line[35] // 1024
  /// ```
  ///
  /// - complexity: O(log *n*), where *n* is the number of segments in this line.
  ///
  @inlinable
  public subscript(_ location: Bound) -> Value {
    _breakpoints.values[segments.index(of: location)._breakpointIndex]
  }
}


// --------------------------------------------
// MARK: - Set, Modify
// --------------------------------------------


extension SegmentedLine {

  /// Ensures that the line's `_breakpoints` contains a breakpoint at the given location.
  /// The location is assumed to be within the line's bounds.
  ///
  /// This operation does not change the values assigned to any locations.
  ///
  /// - returns: The index of the breakpoint which begins at the given location.
  ///
  @inlinable
  internal mutating func _ensureSegmentBreak(at location: Bound) -> BreakpointStorage.Index {

    guard location > bounds.lowerBound else { return _breakpoints.startIndex }

    let containingSegment = segments.index(of: location)._breakpointIndex
    guard _breakpoints.locations[containingSegment] != location else { return containingSegment }

    let newBreakpointLocation = _breakpoints.index(after: containingSegment)
    _breakpoints.insert((location, _breakpoints.values[containingSegment]), at: newBreakpointLocation)
    return newBreakpointLocation
  }

  /// Ensures that the line's `_breakpoints` contains breakpoints for the given range's `lowerBound` and `upperBound`.
  /// Both locations are assumed to be within the line's bounds.
  ///
  /// This operation does not change the values assigned to any locations.
  ///
  /// - returns: A range of breakpoint indices.
  ///            The lowerBound is the index of the breakpoint which begins at the lowerBound of the given range.
  ///            The upperBound is either `endIndex` or the index of the breakpoint which begins at the upperBound
  ///            of the given range.
  ///            If the given range was empty, the result is `nil`.
  ///
  @inlinable
  internal mutating func _ensureSegmentBreaks(for boundsToSplit: Range<Bound>) -> Range<BreakpointStorage.Index>? {

    guard !boundsToSplit.isEmpty else { return nil }

    // TODO: Limit search range when finding upperBoundBreakpoint - we know the break will be >lowerBoundBreakpoint.
    let lowerBoundBreakpoint = _ensureSegmentBreak(at: boundsToSplit.lowerBound)
    let upperBoundBreakpoint =
      (boundsToSplit.upperBound < bounds.upperBound)
      ? _ensureSegmentBreak(at: boundsToSplit.upperBound)
      : _breakpoints.endIndex

    assert(lowerBoundBreakpoint < _breakpoints.endIndex, "lowerBound is in-bounds and so must have a segment")
    assert(lowerBoundBreakpoint < upperBoundBreakpoint, "must have at least one segment for a non-empty range")
    return lowerBoundBreakpoint..<upperBoundBreakpoint
  }

  /// Assigns a value to all locations in the given region.
  ///
  /// When this operation completes, there will be a single segment covering the given region.
  /// Segments which previously intersected the given region will be split
  /// in order to preserve values assigned outside the region.
  ///
  /// ```swift
  /// var line = SegmentedLine<Int, String?>(bounds: 0..<100, value: nil)
  ///
  /// line.set(0..<10,  to: "small")
  /// line.set(5..<20,  to: "medium")
  /// line.set(10..<60, to: "large")
  /// print(line)
  /// // ┬
  /// // ├ [0..<5]: "small"
  /// // ├ [5..<10]: "medium"
  /// // ├ [10..<60]: "large"
  /// // ├ [60..<100]: nil
  /// // ┴
  ///
  /// // After setting, there will be a single segment covering the given region.
  ///
  /// line.set(5..<100, to: "not small")
  /// print(line)
  /// // ┬
  /// // ├ [0..<5]: "small"
  /// // ├ [5..<100]: "not small"
  /// // ┴
  /// ```
  ///
  /// `boundsToReplace` must be entirely within the ``bounds`` of this space.
  /// If `boundsToReplace` is empty, this method is a no-op.
  ///
  /// - parameters:
  ///   - boundsToReplace: The locations which should be assigned the new value.
  ///                      Must be entirely within this space's ``bounds``.
  ///   - newValue:        The value to assign.
  ///
  @inlinable
  public mutating func set(_ boundsToReplace: Range<Bound>, to newValue: Value) {

    boundsCheck(boundsToReplace)
    guard let breakPointIndices = _ensureSegmentBreaks(for: boundsToReplace) else { return /* Empty range */ }
    assert(_breakpoints[breakPointIndices.lowerBound].location == boundsToReplace.lowerBound)

    // To apply: ensure a single breakpoint covers this range, then set the value for that breakpoint.

    _breakpoints.removeSubrange(_breakpoints.index(after: breakPointIndices.lowerBound)..<breakPointIndices.upperBound)
    _breakpoints[valueAt: breakPointIndices.lowerBound] = newValue
  }

  /// Modifies the values assigned to locations in the given region.
  ///
  /// Segments which intersect the given region will be split in order to preserve values
  /// outside the region. The given closure will then be invoked for all segments inside the region,
  /// and can modify their values.
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
  /// // Use 'modify' to append the attribute for the region we're modifying.
  ///
  /// for word in string.split(separator: " ") {
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
  /// If `boundsToModify` is empty, this method is a no-op.
  ///
  /// - parameters:
  ///   - boundsToModify: The locations whose values should be modified.
  ///                     Must be within this space's ``bounds``.
  ///   - body:           A closure which modifies values associated with the given locations.
  ///
  @inlinable
  public mutating func modify(_ boundsToModify: Range<Bound>, _ body: (inout Value) -> Void) {

    boundsCheck(boundsToModify)
    guard let breakPointIndices = _ensureSegmentBreaks(for: boundsToModify) else { return /* Empty range */ }
    assert(_breakpoints[breakPointIndices.lowerBound].location == boundsToModify.lowerBound)

    // To apply: visit the values of all segments in the range.

    for i in breakPointIndices { body(&_breakpoints[valueAt: i]) }
  }
}


// --------------------------------------------
// MARK: - Table Optimizations
// --------------------------------------------


extension SegmentedLine {

  /// Returns a new `SegmentedLine` created by transforming this line's values using the given closure.
  ///
  /// The result will have the same bounds as this line, and the same number of segments at the same locations.
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
  /// // ┬
  /// // ├ [0..<2]: categoryA
  /// // ├ [2..<4]: categoryB
  /// // ├ [4..<12]: categoryC
  /// // ├ ...
  /// // ┴
  ///
  /// // 1️⃣ We can map these to a smaller number of states.
  ///
  /// enum SimplifiedData {
  ///   case valid, invalid
  /// }
  /// var simplifiedLine = complexLine.mapValues { complex in
  ///   SimplifiedData(validating: complex)
  /// }
  /// print(simplifiedLine)
  /// // ┬
  /// // ├ [0..<2]: valid
  /// // ├ [2..<4]: valid
  /// // ├ [4..<12]: valid
  /// // ├ ...
  /// // ┴
  ///
  /// // 2️⃣ Notice that we have lots of segments for boundaries which
  /// //    which are no longer important. 'combineSegments' can clean them up.
  ///
  /// simplifiedLine.combineSegments()
  /// print(simplifiedLine)
  /// // ┬
  /// // ├ [0..<2000]: valid
  /// // ├ [2000..<2024]: invalid
  /// // ├ [2024..<2056]: valid
  /// // ├ ...
  /// // ┴
  /// ```
  ///
  @inlinable
  public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> SegmentedLine<Bound, T> {
    SegmentedLine<Bound, T>(
      _breakpoints: .init(locations: _breakpoints.locations, values: try _breakpoints.values.map(transform)),
      _upperBound: _upperBound
    )
  }

  /// Merges strings of adjacent segments.
  ///
  /// This function implements a kind of left-fold, similar to `Collection.reduce`,
  /// with the key difference that the closure can decide _not_ to combine two elements
  /// and instead to restart the fold operation.
  ///
  /// When the closure is invoked, two segments are provided to it as parameters -
  /// an `accumulator` with a mutable value, and `next`, which is its successor on this line.
  /// Given these two segments, the closure decides either:
  ///
  /// - To merge `next` in to `accumulator`.
  ///
  ///   To merge segments, the closure performs any required adjustments to merge `next.value`
  ///   in to `accumulator.value` and returns `true`.
  ///
  ///   The segment `next` will automatically be discarded,
  ///   and the accumulator's range will be expanded to include `next.range`.
  ///   Folding continues with the same accumulator for as long as the closure returns `true`.
  ///
  /// - To maintain `next` and `accumulator` as separate sections.
  ///
  ///   If it is not desirable to merge the segments, the closure may return `false`.
  ///   This finalizes the current accumulator, and restarts folding with `next` as the new accumulator.
  ///
  @inlinable
  public mutating func combineSegments(
    while shouldMerge: (_ accumulator: inout Segments.Element, _ next: Segments.Element) -> Bool
  ) {
    // TODO: It would be nice to perform this in-place.
    // - For locations, we can overwrite values (MutableCollection-style) and chop off the tail at the end.
    // - For values, it's a little more awkward because we'd want to *move* Value elements in to the accumulator.
    //   It's possible, but needs to be done carefully.

    var reducedLocations = [Bound]()
    var reducedValues = [Value]()

    var accumulator = segments[segments.startIndex]
    var i = segments.index(after: segments.startIndex)
    while i < segments.endIndex {
      let next = segments[i]

      // Ignore any modifications the closure makes to the 'range' part of the accumulator.
      let accumulatorStart = accumulator.range.lowerBound
      if shouldMerge(&accumulator, next) {
        accumulator.range = Range(uncheckedBounds: (accumulatorStart, next.range.upperBound))
      } else {
        reducedLocations.append(accumulatorStart)
        reducedValues.append(accumulator.value)
        accumulator = next
      }

      segments.formIndex(after: &i)
    }

    reducedLocations.append(accumulator.range.lowerBound)
    reducedValues.append(accumulator.value)
    self._breakpoints = BreakpointStorage(locations: reducedLocations, values: reducedValues)
  }
}

extension SegmentedLine where Value: Equatable {

  /// Merges strings of adjacent segments with the same value.
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
  /// // ┬
  /// // ├ [0..<2]: categoryA
  /// // ├ [2..<4]: categoryB
  /// // ├ [4..<12]: categoryC
  /// // ├ ...
  /// // ┴
  ///
  /// // 1️⃣ We can map these to a smaller number of states.
  ///
  /// enum SimplifiedData {
  ///   case valid, invalid
  /// }
  /// var simplifiedLine = complexLine.mapValues { complex in
  ///   SimplifiedData(validating: complex)
  /// }
  /// print(simplifiedLine)
  /// // ┬
  /// // ├ [0..<2]: valid
  /// // ├ [2..<4]: valid
  /// // ├ [4..<12]: valid
  /// // ├ ...
  /// // ┴
  ///
  /// // 2️⃣ Notice that we have lots of segments for boundaries which
  /// //    which are no longer important. 'combineSegments' can clean them up.
  ///
  /// simplifiedLine.combineSegments()
  /// print(simplifiedLine)
  /// // ┬
  /// // ├ [0..<2000]: valid
  /// // ├ [2000..<2024]: invalid
  /// // ├ [2024..<2056]: valid
  /// // ├ ...
  /// // ┴
  /// ```
  ///
  @inlinable
  public mutating func combineSegments() {
    combineSegments(while: { $0.value == $1.value })
  }
}
