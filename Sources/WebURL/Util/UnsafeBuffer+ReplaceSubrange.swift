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
// This file contains a generic implementation of 'replaceSubrange' for contiguous buffers,
// including those only accessible indirectly such as `ManagedBuffer` subclasses.
//
// It includes optimizations for in-place replacement as well as consuming the original storage when additional
// capacity is required. The implementation is adapted from the standard library's source code, where it forms
// the basis of Array's implementation of replaceSubrange.
//
// I've tried to split the functionality in to small, well-defined functions. Unfortunately, the main entrypoint
// is still a big function with lots of parameters which I've found difficult to clean up by defining appropriate
// abstractions. It looks uglier than it is.
// --------------------------------------------


/// An object which contains a unique, mutable buffer.
/// This protocol is a required level of indirection so that `replaceElements` can allocate, fill, and return objects which provide their buffers indirectly.
///
@usableFromInline
internal protocol BufferContainer {
  associatedtype Element
  mutating func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R
}

/// Given a `buffer`, representing an entire allocation in which `0..<initializedCount` are initialized elements
/// and `initializedCount..<buffer.count` is uninitialized capacity, replaces the elements in `subrange` with
/// those given by `newElements`.
///
/// If `isUnique` is true and the buffer's capacity is sufficient, elements will be efficiently rearranged in-place.
/// Otherwise, `storageConstructor` will be invoked and passed the required capacity as a parameter. The closure must return an object with access
/// to at least that many mutable bytes. If `isUnique` is true, the old buffer will be consumed and its elements efficiently moved in to the new storage, otherwise
/// they will be copied.
///
///  Typical usage looks as follows (where `storage` is an instance variable which is some subclass of `ManagedBuffer`):
///
///  ```swift
///  let isUnique = isKnownUniquelyReferenced(&storage)
///  let result = storage.withUnsafeMutablePointerToElements { elems in
///   return replaceElements(
///    in: UnsafeMutableBufferPointer(start: elems, count: storage.capacity),
///    initializedCount: storage.header.count,
///    subrange: subrange,
///    with: newElements,
///    isUnique: isUnique,
///    storageConstructor: { MyManagedBufferSubclass(minimumCapacity: $0, initialHeader: storage.header) }
///   )
///  }
///  // Update the count of the existing storage. Its contents may have been moved out.
///  storage.header.count = result.bufferCount
///  // Adopt any new storage that was allocated.
///  if var newStorage = result.newStorage {
///   newStorage.header.count = result.newStorageCount
///   self.storage = newStorage
///  }
///  ```
///
/// - parameters:
///   - buffer:              A buffer-pointer which represents the entire available capacity, including any uninitialized storage.
///   - initializedCount:    The number of contiguous elements (from 0) that are initialized in `buffer`.
///   - subrange:            The range of elements in `buffer` to replace. `buffer.endIndex..<buffer.endIndex` performs an append.
///   - newElements:         The new elements to insert in `subrange`.
///   - isUnique:            If `true`, `buffer` is assumed to be a unique reference which may be consumed or mutated in-place.
///   - storageConstructor:  A closure which can construct a new buffer with a given capacity.
///
/// - returns: A tuple containing the following fields:
///   - bufferCount:           The number of contiguous elements which remain initialized in the original `buffer`. If `isUnique` is `false`, this will always
///                   be the same as `initializedCount`.
///   - insertedCount:       The number of elements which were inserted.
///                   The elements will be found at `subrange.lowerBound ..< subrange.lowerBound + insertedCount`,
///                   in either `buffer` or `newStorage`.
///   - newStorage:           The new storage object, if one had to be allocated.
///   - newStorageCount: The number of contiguous elements which are initialized in `newStorage`.
///
@inlinable
internal func replaceElements<C, T: BufferContainer>(
  in buffer: UnsafeMutableBufferPointer<C.Element>,
  initializedCount: Int,
  subrange: Range<Int>,
  with newElements: C,
  isUnique: Bool,
  storageConstructor: (_ minimumCapacity: Int) -> T
) -> (bufferCount: Int, insertedCount: Int, newStorage: T?, newStorageCount: Int)
where C: Collection, T.Element == C.Element {
  replaceElements(
    in: buffer,
    initializedCount: initializedCount,
    isUnique: isUnique,
    subrange: subrange,
    withElements: newElements.count,
    initializedWith: { return $0.fastInitialize(from: newElements) },
    storageConstructor: storageConstructor
  )
}

@inlinable
internal func replaceElements<T: BufferContainer>(
  in buffer: UnsafeMutableBufferPointer<T.Element>,
  initializedCount: Int,
  isUnique: Bool,
  subrange: Range<Int>,
  withElements newElementsCount: Int,
  initializedWith initializer: (inout UnsafeMutableBufferPointer<T.Element>) -> Int,
  storageConstructor: (_ minimumCapacity: Int) -> T
) -> (bufferCount: Int, insertedCount: Int, newStorage: T?, newStorageCount: Int) {

  precondition(subrange.lowerBound >= 0, "subrange start is negative")
  precondition(subrange.upperBound <= initializedCount, "subrange extends past the end")

  let insertCount = newElementsCount
  let finalCount = initializedCount - subrange.count + insertCount

  if isUnique && finalCount <= buffer.count {
    let newCount = replaceSubrange_inplace(
      buffer: buffer, initializedCount: initializedCount,
      subrange: subrange, newElementCount: insertCount
    ) { ptr, expectedCount in
      var rangePtr = UnsafeMutableBufferPointer(start: ptr, count: expectedCount)
      let n = initializer(&rangePtr)
      precondition(n == expectedCount, "initializer failed to initialize entire capacity")
    }
    return (bufferCount: newCount, insertedCount: insertCount, newStorage: nil, newStorageCount: 0)
  }
  var newStorage = storageConstructor(finalCount)
  let srcBuffer = UnsafeMutableBufferPointer(rebasing: buffer.prefix(initializedCount))
  let newCount = newStorage.withUnsafeMutablePointerToElements { newBufferPtr -> Int in
    let newBuffer = UnsafeMutableBufferPointer(start: newBufferPtr, count: finalCount)
    if isUnique {
      return newBuffer.moveInitialize(from: srcBuffer, replacingSubrange: subrange, withElements: insertCount) {
        ptr, expectedCount in
        var rangePtr = UnsafeMutableBufferPointer(start: ptr, count: expectedCount)
        let n = initializer(&rangePtr)
        precondition(n == expectedCount, "initializer failed to initialize entire capacity")
      }
    }
    return newBuffer.initialize(
      from: UnsafeBufferPointer(srcBuffer), replacingSubrange: subrange, withElements: insertCount
    ) { ptr, expectedCount in
      var rangePtr = UnsafeMutableBufferPointer(start: ptr, count: expectedCount)
      let n = initializer(&rangePtr)
      precondition(n == expectedCount, "initializer failed to initialize entire capacity")
    }
  }
  assert(newCount == finalCount)
  return (
    bufferCount: isUnique ? 0 : initializedCount, insertedCount: insertCount, newStorage: newStorage,
    newStorageCount: finalCount
  )
}

/// Given a buffer, whose elements from `0..<initializedCount` are initialized, replaces the given subrange with the elements in `newValues`.
/// The buffer must have sufficient capacity to store the elements.
///
/// - returns: The buffer's new `count`.
///
@inlinable
internal func replaceSubrange_inplace<Element>(
  buffer: UnsafeMutableBufferPointer<Element>,
  initializedCount: Int,
  subrange: Range<Int>,
  newElementCount: Int,
  _ initializeNewElements:
    ((UnsafeMutablePointer<Element>, _ count: Int) -> Void) = { ptr, count in
      precondition(count == 0)
    }
) -> Int {

  let oldCount = initializedCount
  let growth = newElementCount - subrange.count
  let finalCount = oldCount + growth
  precondition(finalCount <= buffer.count, "Insufficient capacity for replaceSubrange_inplace")

  guard let elements = buffer.baseAddress else { return 0 }
  switch growth {
  case _ where growth > 0:
    (elements + subrange.lowerBound + newElementCount)
      .moveInitialize(from: elements + subrange.upperBound, count: oldCount - subrange.upperBound)
    (elements + subrange.lowerBound).deinitialize(count: subrange.count)
    initializeNewElements(elements + subrange.lowerBound, newElementCount)

  case _ where growth == 0:
    (elements + subrange.lowerBound).deinitialize(count: subrange.count)
    initializeNewElements(elements + subrange.lowerBound, newElementCount)

  case _ where growth < 0: fallthrough
  default:
    (elements + subrange.lowerBound).deinitialize(count: subrange.count)
    initializeNewElements(elements + subrange.lowerBound, newElementCount)
    (elements + subrange.lowerBound + newElementCount)
      .moveInitialize(from: elements + subrange.upperBound, count: oldCount - subrange.upperBound)
  }
  return finalCount
}


// --------------------------------------------
// MARK: - Out-of-place replacements
// --------------------------------------------


extension UnsafeMutableBufferPointer {

  /// Initializes the contents of this buffer by moving the contents of `oldContents`, with the exception of `subrange`, whose
  /// old contents are deinitialized and replaced by a region of size `newCount`, initialized by the given closure.
  ///
  /// - parameters:
  ///   - oldContents:            The buffer whose contents should be moved in to this buffer.
  ///   - subrange:               The region of `buffer` which should be replaced.
  ///   - newCount:               The number of elements to replace `subrange` with.
  ///   - initializeNewElements:  A closure, which **must** initialize `newCount` elements starting at the given pointer.
  ///
  /// - returns: The total number of elements that were initialized.
  ///
  @inlinable
  internal func moveInitialize(
    from oldContents: UnsafeMutableBufferPointer<Element>,
    replacingSubrange subrange: Range<Int>,
    withElements newCount: Int,  // Number of new elements to insert
    _ initializeNewElements:
      ((UnsafeMutablePointer<Element>, _ count: Int) -> Void) = { ptr, count in
        precondition(count == 0)
      }
  ) -> Int {
    guard let sourceStart = oldContents.baseAddress else { return 0 }

    precondition(subrange.lowerBound >= 0 && subrange.upperBound <= oldContents.count, "Invalid subrange")
    let finalCount = oldContents.count - subrange.count + newCount
    precondition(finalCount <= self.count, "Insufficient capacity")

    var head = self.baseAddress!
    // Move the head items
    head.moveInitialize(from: sourceStart, count: subrange.lowerBound)
    head += subrange.lowerBound
    // Destroy unused source items
    (sourceStart + subrange.lowerBound).deinitialize(count: subrange.count)
    // Initialize the gap.
    initializeNewElements(head, newCount)
    head += newCount
    // Move the tail items
    head.moveInitialize(from: sourceStart + subrange.upperBound, count: oldContents.count - subrange.upperBound)
    return finalCount
  }

  /// Initializes the contents of this buffer by copying the contents of `oldContents`, with the exception of `subrange`, which is
  /// replaced by a region of size `newCount`, initialized by the given closure.
  ///
  /// - parameters:
  ///   - oldContents:            The buffer whose contents should be copied in to this buffer.
  ///   - subrange:               The region of `buffer` which should be replaced.
  ///   - newCount:               The number of elements to replace `subrange` with.
  ///   - initializeNewElements:  A closure, which **must** initialize `newCount` elements starting at the given pointer.
  ///
  /// - returns: The total number of elements that were initialized.
  ///
  @inlinable
  internal func initialize(
    from oldContents: UnsafeBufferPointer<Element>,
    replacingSubrange subrange: Range<Int>,
    withElements newCount: Int,  // Number of new elements to insert
    _ initializeNewElements:
      ((UnsafeMutablePointer<Element>, _ count: Int) -> Void) = { ptr, count in
        precondition(count == 0)
      }
  ) -> Int {
    guard let sourceStart = oldContents.baseAddress else { return 0 }

    precondition(subrange.lowerBound >= 0 && subrange.upperBound <= oldContents.count, "Invalid subrange")
    let finalCount = oldContents.count - subrange.count + newCount
    precondition(finalCount <= self.count, "Insufficient capacity")

    var head = self.baseAddress!
    // Copy the head items.
    head.initialize(from: sourceStart, count: subrange.lowerBound)
    head += subrange.lowerBound
    // Initialize the gap.
    initializeNewElements(head, newCount)
    head += newCount
    // Copy the tail items.
    head.initialize(from: sourceStart + subrange.upperBound, count: oldContents.count - subrange.upperBound)
    return finalCount
  }
}
