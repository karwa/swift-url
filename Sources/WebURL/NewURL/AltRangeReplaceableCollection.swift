// This file contains 'AltRangeReplaceableCollection' - an alternative to the standard library's
// `RangeReplaceableCollection`, with 2 differences:
//
// - There is no `init()` requirement. This allows more subclasses of `ManagedBuffer` to conform.
// - `replaceSubrange` and other methods return the range of the inserted elements. This is required for many algorithms.
//

protocol AltRangeReplaceableCollection : Collection where Self.SubSequence : AltRangeReplaceableCollection {

    /// Replaces the specified subrange of elements with the given collection.
    ///
    /// This method has the effect of removing the specified range of elements
    /// from the collection and inserting the new elements at the same location.
    /// The number of new elements need not match the number of elements being
    /// removed.
    ///
    /// In this example, three elements in the middle of an array of integers are
    /// replaced by the five elements of a `Repeated<Int>` instance.
    ///
    ///      var nums = [10, 20, 30, 40, 50]
    ///      nums.replaceSubrange(1...3, with: repeatElement(1, count: 5))
    ///      print(nums)
    ///      // Prints "[10, 1, 1, 1, 1, 1, 50]"
    ///
    /// If you pass a zero-length range as the `subrange` parameter, this method
    /// inserts the elements of `newElements` at `subrange.startIndex`. Calling
    /// the `insert(contentsOf:at:)` method instead is preferred.
    ///
    /// Likewise, if you pass a zero-length collection as the `newElements`
    /// parameter, this method removes the elements in the given subrange
    /// without replacement. Calling the `removeSubrange(_:)` method instead is
    /// preferred.
    ///
    /// Calling this method may invalidate any existing indices for use with this
    /// collection.
    ///
    /// - Parameters:
    ///   - subrange: The subrange of the collection to replace. The bounds of
    ///     the range must be valid indices of the collection.
    ///   - newElements: The new elements to add to the collection.
    ///
    /// - Complexity: O(*n* + *m*), where *n* is length of this collection and
    ///   *m* is the length of `newElements`. If the call to this method simply
    ///   appends the contents of `newElements` to the collection, this method is
    ///   equivalent to `append(contentsOf:)`.
    @discardableResult
    mutating func replaceSubrange<C>(_ subrange: Range<Self.Index>, with newElements: C) -> Range<Self.Index>
      where C : Collection, Self.Element == C.Element

    /// Prepares the collection to store the specified number of elements, when
    /// doing so is appropriate for the underlying type.
    ///
    /// If you are adding a known number of elements to a collection, use this
    /// method to avoid multiple reallocations. A type that conforms to
    /// `RangeReplaceableCollection` can choose how to respond when this method
    /// is called. Depending on the type, it may make sense to allocate more or
    /// less storage than requested, or to take no action at all.
    ///
    /// - Parameter n: The requested number of elements to store.
    mutating func reserveCapacity(_ n: Int)

    /// Adds an element to the end of the collection.
    ///
    /// If the collection does not have sufficient capacity for another element,
    /// additional storage is allocated before appending `newElement`. The
    /// following example adds a new number to an array of integers:
    ///
    ///     var numbers = [1, 2, 3, 4, 5]
    ///     numbers.append(100)
    ///
    ///     print(numbers)
    ///     // Prints "[1, 2, 3, 4, 5, 100]"
    ///
    /// - Parameter newElement: The element to append to the collection.
    ///
    /// - Complexity: O(1) on average, over many calls to `append(_:)` on the
    ///   same collection.
  	@discardableResult
    mutating func append(_ newElement: Self.Element) -> Self.Index

    /// Adds the elements of a sequence or collection to the end of this
    /// collection.
    ///
    /// The collection being appended to allocates any additional necessary
    /// storage to hold the new elements.
    ///
    /// The following example appends the elements of a `Range<Int>` instance to
    /// an array of integers:
    ///
    ///     var numbers = [1, 2, 3, 4, 5]
    ///     numbers.append(contentsOf: 10...15)
    ///     print(numbers)
    ///     // Prints "[1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15]"
    ///
    /// - Parameter newElements: The elements to append to the collection.
    ///
    /// - Complexity: O(*m*), where *m* is the length of `newElements`.
    @discardableResult
    mutating func append<S>(contentsOf newElements: S) -> Range<Self.Index> where S : Sequence, Self.Element == S.Element

    /// Inserts a new element into the collection at the specified position.
    ///
    /// The new element is inserted before the element currently at the
    /// specified index. If you pass the collection's `endIndex` property as
    /// the `index` parameter, the new element is appended to the
    /// collection.
    ///
    ///     var numbers = [1, 2, 3, 4, 5]
    ///     numbers.insert(100, at: 3)
    ///     numbers.insert(200, at: numbers.endIndex)
    ///
    ///     print(numbers)
    ///     // Prints "[1, 2, 3, 100, 4, 5, 200]"
    ///
    /// Calling this method may invalidate any existing indices for use with this
    /// collection.
    ///
    /// - Parameter newElement: The new element to insert into the collection.
    /// - Parameter i: The position at which to insert the new element.
    ///   `index` must be a valid index into the collection.
    ///
    /// - Complexity: O(*n*), where *n* is the length of the collection. If
    ///   `i == endIndex`, this method is equivalent to `append(_:)`.
    @discardableResult
    mutating func insert(_ newElement: Self.Element, at i: Self.Index) -> Self.Index

//    /// Inserts the elements of a sequence into the collection at the specified
//    /// position.
//    ///
//    /// The new elements are inserted before the element currently at the
//    /// specified index. If you pass the collection's `endIndex` property as the
//    /// `index` parameter, the new elements are appended to the collection.
//    ///
//    /// Here's an example of inserting a range of integers into an array of the
//    /// same type:
//    ///
//    ///     var numbers = [1, 2, 3, 4, 5]
//    ///     numbers.insert(contentsOf: 100...103, at: 3)
//    ///     print(numbers)
//    ///     // Prints "[1, 2, 3, 100, 101, 102, 103, 4, 5]"
//    ///
//    /// Calling this method may invalidate any existing indices for use with this
//    /// collection.
//    ///
//    /// - Parameter newElements: The new elements to insert into the collection.
//    /// - Parameter i: The position at which to insert the new elements. `index`
//    ///   must be a valid index of the collection.
//    ///
//    /// - Complexity: O(*n* + *m*), where *n* is length of this collection and
//    ///   *m* is the length of `newElements`. If `i == endIndex`, this method
//    ///   is equivalent to `append(contentsOf:)`.
//    mutating func insert<S>(contentsOf newElements: S, at i: Self.Index) where S : Collection, Self.Element == S.Element
//
//    /// Removes and returns the element at the specified position.
//    ///
//    /// All the elements following the specified position are moved to close the
//    /// gap. This example removes the middle element from an array of
//    /// measurements.
//    ///
//    ///     var measurements = [1.2, 1.5, 2.9, 1.2, 1.6]
//    ///     let removed = measurements.remove(at: 2)
//    ///     print(measurements)
//    ///     // Prints "[1.2, 1.5, 1.2, 1.6]"
//    ///
//    /// Calling this method may invalidate any existing indices for use with this
//    /// collection.
//    ///
//    /// - Parameter i: The position of the element to remove. `index` must be
//    ///   a valid index of the collection that is not equal to the collection's
//    ///   end index.
//    /// - Returns: The removed element.
//    ///
//    /// - Complexity: O(*n*), where *n* is the length of the collection.
//    mutating func remove(at i: Self.Index) -> Self.Element
//
//    /// Removes the specified subrange of elements from the collection.
//    ///
//    ///     var bugs = ["Aphid", "Bumblebee", "Cicada", "Damselfly", "Earwig"]
//    ///     bugs.removeSubrange(1...3)
//    ///     print(bugs)
//    ///     // Prints "["Aphid", "Earwig"]"
//    ///
//    /// Calling this method may invalidate any existing indices for use with this
//    /// collection.
//    ///
//    /// - Parameter bounds: The subrange of the collection to remove. The bounds
//    ///   of the range must be valid indices of the collection.
//    ///
//    /// - Complexity: O(*n*), where *n* is the length of the collection.
//    mutating func removeSubrange(_ bounds: Range<Self.Index>)
//
//    /// Removes and returns the first element of the collection.
//    ///
//    /// The collection must not be empty.
//    ///
//    ///     var bugs = ["Aphid", "Bumblebee", "Cicada", "Damselfly", "Earwig"]
//    ///     bugs.removeFirst()
//    ///     print(bugs)
//    ///     // Prints "["Bumblebee", "Cicada", "Damselfly", "Earwig"]"
//    ///
//    /// Calling this method may invalidate any existing indices for use with this
//    /// collection.
//    ///
//    /// - Returns: The removed element.
//    ///
//    /// - Complexity: O(*n*), where *n* is the length of the collection.
//    mutating func removeFirst() -> Self.Element
//
//    /// Removes the specified number of elements from the beginning of the
//    /// collection.
//    ///
//    ///     var bugs = ["Aphid", "Bumblebee", "Cicada", "Damselfly", "Earwig"]
//    ///     bugs.removeFirst(3)
//    ///     print(bugs)
//    ///     // Prints "["Damselfly", "Earwig"]"
//    ///
//    /// Calling this method may invalidate any existing indices for use with this
//    /// collection.
//    ///
//    /// - Parameter k: The number of elements to remove from the collection.
//    ///   `k` must be greater than or equal to zero and must not exceed the
//    ///   number of elements in the collection.
//    ///
//    /// - Complexity: O(*n*), where *n* is the length of the collection.
//    mutating func removeFirst(_ k: Int)
//
//    /// Removes all elements from the collection.
//    ///
//    /// Calling this method may invalidate any existing indices for use with this
//    /// collection.
//    ///
//    /// - Parameter keepCapacity: Pass `true` to request that the collection
//    ///   avoid releasing its storage. Retaining the collection's storage can
//    ///   be a useful optimization when you're planning to grow the collection
//    ///   again. The default value is `false`.
//    ///
//    /// - Complexity: O(*n*), where *n* is the length of the collection.
//    mutating func removeAll(keepingCapacity keepCapacity: Bool)
//
//    /// Removes all the elements that satisfy the given predicate.
//    ///
//    /// Use this method to remove every element in a collection that meets
//    /// particular criteria. The order of the remaining elements is preserved.
//    /// This example removes all the odd values from an
//    /// array of numbers:
//    ///
//    ///     var numbers = [5, 6, 7, 8, 9, 10, 11]
//    ///     numbers.removeAll(where: { $0 % 2 != 0 })
//    ///     // numbers == [6, 8, 10]
//    ///
//    /// - Parameter shouldBeRemoved: A closure that takes an element of the
//    ///   sequence as its argument and returns a Boolean value indicating
//    ///   whether the element should be removed from the collection.
//    ///
//    /// - Complexity: O(*n*), where *n* is the length of the collection.
//    mutating func removeAll(where shouldBeRemoved: (Self.Element) throws -> Bool) rethrows
}

extension AltRangeReplaceableCollection {
  
  mutating func reserveCapacity(_ n: Int) {
    // No-op.
  }
  
  @discardableResult
  mutating func append(_ newElement: Self.Element) -> Self.Index {
    return replaceSubrange(endIndex..<endIndex, with: CollectionOfOne(newElement)).lowerBound
  }
  
  @discardableResult
  mutating func append<S>(contentsOf newElements: S) -> Range<Self.Index> where S : Sequence, Self.Element == S.Element {
    reserveCapacity(newElements.underestimatedCount)
    let preAppendEnd = endIndex
    for element in newElements {
      append(element)
    }
    return preAppendEnd..<endIndex
  }

  @discardableResult
  mutating func insert(_ newElement: Self.Element, at i: Self.Index) -> Self.Index {
    return replaceSubrange(i..<i, with: CollectionOfOne(newElement)).lowerBound
  }
  
//  mutating func removeSubrange(_ bounds: Range<Self.Index>) {
//    replaceSubrange(bounds, with: EmptyCollection())
//  }
//
//  mutating func remove(at i: Self.Index) -> Self.Element {
//    precondition(i != endIndex)
//    removeSubrange(i..<i)
//  }
}

extension AltRangeReplaceableCollection {
  
  mutating func append(repeated element: Element, count: Int) {
   append(contentsOf: repeatElement(element, count: count))
  }
}

extension Slice: AltRangeReplaceableCollection where Base: AltRangeReplaceableCollection {
  
  mutating func reserveCapacity(_ n: Int) {
    var x = base
    x.reserveCapacity(n)
    self = Slice(base: x, bounds: Range(uncheckedBounds: (startIndex, endIndex)))
  }
  
  @discardableResult
  mutating func replaceSubrange<C>(_ subrange: Range<Base.Index>, with newElements: C) -> Range<Base.Index>
    where C : Collection, Self.Element == C.Element {
    
    let sliceOffset = base.distance(from: base.startIndex, to: startIndex)
    let newSliceCount = base.distance(from: startIndex, to: subrange.lowerBound)
      + base.distance(from: subrange.upperBound, to: endIndex)
      + newElements.count
    var x = base
    let insertedRange = x.replaceSubrange(subrange, with: newElements)
    let newStartIndex = x.index(x.startIndex, offsetBy: sliceOffset)
    let newEndIndex = x.index(newStartIndex, offsetBy: newSliceCount)
		
    self = Slice(base: x, bounds: newStartIndex..<newEndIndex)
    return insertedRange
  }
}
