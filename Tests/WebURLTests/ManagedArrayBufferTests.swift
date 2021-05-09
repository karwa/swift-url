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

import Checkit
import XCTest

@testable import WebURL

final class ManagedArrayBufferTests: XCTestCase {}

extension ManagedArrayBufferTests {

  struct BasicHeader: ManagedBufferHeader {
    var count: Int
    let capacity: Int
    func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> BasicHeader? {
      return BasicHeader(count: count, capacity: minimumCapacity)
    }
  }

  struct DataHolderHeader<T>: ManagedBufferHeader {
    var data: T
    var count: Int
    let capacity: Int

    func withCapacity(minimumCapacity: Int, maximumCapacity: Int) -> DataHolderHeader? {
      return DataHolderHeader(data: data, count: count, capacity: minimumCapacity)
    }
  }

  func testEmpty() {
    let emptyBuffer = ManagedArrayBuffer<BasicHeader, Void>(
      minimumCapacity: 10, initialHeader: BasicHeader(count: -1, capacity: -1)
    )
    // Collection properties confirm that the buffer is empty.
    XCTAssertEqual(emptyBuffer.startIndex, 0)
    XCTAssertEqual(emptyBuffer.endIndex, 0)
    XCTAssertEqual(emptyBuffer.count, 0)
    XCTAssertTrue(emptyBuffer.isEmpty)
    // Header properties are set appropriately.
    XCTAssertEqual(emptyBuffer.header.count, 0)
    XCTAssertGreaterThanOrEqual(emptyBuffer.header.capacity, 10)
  }

  func testHeaderCOW() {
    var original = ManagedArrayBuffer<DataHolderHeader<Int>, Void>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    let originalAddress = original.withUnsafeBufferPointer { $0.baseAddress }
    XCTAssertEqual(original.header.data, 42)

    // Mutate the header. Ensure it doesn't copy as the buffer is unique.
    original.header.data = 24
    XCTAssertEqual(original.header.data, 24)
    XCTAssertEqual(original.header.count, 0)
    XCTAssertGreaterThanOrEqual(original.header.capacity, 10)
    XCTAssertEqual(originalAddress, original.withUnsafeBufferPointer { $0.baseAddress })

    // Copy the reference and mutate via the copy. Ensure the mutation copies to new storage.
    var copy = original
    copy.header.data = -88
    XCTAssertEqual(original.header.data, 24)
    XCTAssertEqual(original.header.count, 0)
    XCTAssertGreaterThanOrEqual(original.header.capacity, 10)
    XCTAssertNotEqual(originalAddress, copy.withUnsafeBufferPointer { $0.baseAddress })
    XCTAssertEqual(copy.header.data, -88)
    XCTAssertEqual(copy.header.count, 0)
    // We can't say what the copy's capacity is.
  }

  func testAppend() {
    var buffer = ManagedArrayBuffer<DataHolderHeader<Int>, Int>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    // Appending works to fill the buffer.
    // The returned range tells you where the elements were inserted,
    // and the header's extra data is unmodified by the append.
    let range0 = buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    XCTAssertEqualElements(range0, 0..<100)
    XCTAssertEqualElements(buffer[range0], 100..<200)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 100)
    XCTAssertEqual(buffer.header.count, 100)

    let range1 = buffer.append(contentsOf: 0..<10)
    XCTAssertEqualElements(buffer, [100..<200, 0..<10].joined())
    XCTAssertEqualElements(range1, 100..<110)
    XCTAssertEqualElements(buffer[range1], 0..<10)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 110)
    XCTAssertEqual(buffer.header.count, 110)

    let copy = buffer

    // Appending works when the buffer is not uniquely references.
    // Appending a single element returns the index of that element,
    // and the header's data is unmodified by the append.
    let idx2 = buffer.append(500)
    XCTAssertEqualElements(buffer, [100..<200, 0..<10, 500..<501].joined())
    XCTAssertEqual(idx2, 110)
    XCTAssertEqual(buffer[idx2], 500)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 111)
    XCTAssertEqual(buffer.header.count, 111)
    // Since the buffer was not uniquely referenced, it copied. Other references don't see the append.
    XCTAssertEqualElements(copy, [100..<200, 0..<10].joined())
    XCTAssertEqual(copy.header.data, 42)
    XCTAssertEqual(copy.count, 110)
    XCTAssertEqual(copy.header.count, 110)
  }

  func testCollectionConformance() {
    var buffer = ManagedArrayBuffer<DataHolderHeader<Int>, Int>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    // Check conformance when buffer is empty.
    CollectionChecker.check(buffer)
    // Check conformance when non-empty.
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    CollectionChecker.check(buffer)
  }

  func testMutableCollection() {
    var buffer = ManagedArrayBuffer<DataHolderHeader<Int>, Int>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)

    // Mutate in-place. The test for MutableCollection is that doing so does not invalidate any indexes.
    XCTAssertEqual(buffer[20], 120)
    XCTAssertEqual(buffer.header.data, 42)
    let beforeIndices = buffer.indices
    buffer[20] = -99
    XCTAssertEqual(buffer[20], -99)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.indices, beforeIndices)
    // Check COW.
    let copy = buffer
    buffer[95] = Int.max
    XCTAssertEqual(buffer[95], Int.max)
    XCTAssertEqual(copy[95], 195)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(copy.header.data, 42)
  }

  func testReserveCapacity() {
    var buffer = ManagedArrayBuffer<DataHolderHeader<Int>, Int>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    buffer.append(contentsOf: 20..<25)
    let originalAddress = buffer.withUnsafeBufferPointer { $0.baseAddress }

    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.header.count, 5)
    XCTAssertEqual(buffer.header.capacity, 10)
    XCTAssertEqual(originalAddress, buffer.withUnsafeBufferPointer { $0.baseAddress })
    XCTAssertEqualElements(buffer, 20..<25)

    // Reserve less than count. Should be a no-op.
    buffer.reserveCapacity(2)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.header.count, 5)
    XCTAssertEqual(buffer.header.capacity, 10)
    XCTAssertEqual(originalAddress, buffer.withUnsafeBufferPointer { $0.baseAddress })
    XCTAssertEqualElements(buffer, 20..<25)

    // Reserve more than count. Should reserve.
    buffer.reserveCapacity(500)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.header.count, 5)
    XCTAssertEqual(buffer.header.capacity, 500)
    XCTAssertNotEqual(originalAddress, buffer.withUnsafeBufferPointer { $0.baseAddress })
    XCTAssertEqualElements(buffer, 20..<25)

    // Make non-unique and reserve again. Should allocate new storage with the requested capacity.
    let copy = buffer

    buffer.reserveCapacity(100)
    buffer.append(25)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.header.count, 6)
    XCTAssertEqual(buffer.header.capacity, 100)
    XCTAssertEqualElements(buffer, 20..<26)

    // The old reference has the old capacity and contents.
    XCTAssertEqual(copy.header.data, 42)
    XCTAssertEqual(copy.header.count, 5)
    XCTAssertEqual(copy.header.capacity, 500)
    XCTAssertEqualElements(copy, 20..<25)
  }

  func doTestReplaceSubrange(_ didFinishTestStep: (inout ManagedArrayBuffer<DataHolderHeader<Int>, Int>) -> Void) {
    // Test replacement:
    // - At the start
    // - In the middle
    // - At the end
    // and with the given range:
    // - Shrinking (removing some elements, inserting fewer elements)
    // - Growing   (removing some elements, inserting more elements)
    // - Removing  (removing some elements, inserting no elements)
    // - Inserting (removing no elements)
    var buffer = ManagedArrayBuffer<DataHolderHeader<Int>, Int>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    buffer.reserveCapacity(500)  // Make sure we never reallocate due to capacity, only due to COW.
    didFinishTestStep(&buffer)

    // Shrink at the start.
    let range0 = buffer.replaceSubrange(0..<10, with: 10..<15)
    XCTAssertEqualElements(buffer, [10..<15, 110..<200].joined())
    XCTAssertEqualElements(buffer[range0], 10..<15)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 95)
    XCTAssertEqual(buffer.header.count, 95)
    didFinishTestStep(&buffer)

    // Shrink in the middle.
    let range1 = buffer.replaceSubrange(40..<60, with: 0..<5)
    XCTAssertEqualElements(buffer, [10..<15, 110..<145, 0..<5, 165..<200].joined())
    XCTAssertEqualElements(buffer[range1], 0..<5)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 80)
    XCTAssertEqual(buffer.header.count, 80)
    didFinishTestStep(&buffer)

    // Shrink at the end.
    let range2 = buffer.replaceSubrange(74..<80, with: CollectionOfOne(99))
    XCTAssertEqualElements(buffer, [10..<15, 110..<145, 0..<5, 165..<194, 99..<100].joined())
    XCTAssertEqualElements(buffer[range2], CollectionOfOne(99))
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 75)
    XCTAssertEqual(buffer.header.count, 75)
    didFinishTestStep(&buffer)

    // Remove everything.
    let range3 = buffer.replaceSubrange(0..<75, with: EmptyCollection())
    XCTAssertEqualElements(buffer, [])
    XCTAssertTrue(buffer.isEmpty)
    XCTAssertEqual(range3, 0..<0)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 0)
    XCTAssertEqual(buffer.header.count, 0)
    didFinishTestStep(&buffer)
    // Start afresh with new contents.
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    didFinishTestStep(&buffer)

    // Grow at the start.
    let range4 = buffer.replaceSubrange(0..<5, with: 500..<520)
    XCTAssertEqualElements(buffer, [500..<520, 105..<200].joined())
    XCTAssertEqualElements(buffer[range4], 500..<520)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 115)
    XCTAssertEqual(buffer.header.count, 115)
    didFinishTestStep(&buffer)

    // Grow in the middle.
    let range5 = buffer.replaceSubrange(50..<55, with: 500..<520)
    XCTAssertEqualElements(buffer, [500..<520, 105..<135, 500..<520, 140..<200].joined())
    XCTAssertEqualElements(buffer[range5], 500..<520)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 130)
    XCTAssertEqual(buffer.header.count, 130)
    didFinishTestStep(&buffer)

    // Grow at the end.
    let range6 = buffer.replaceSubrange(125..<130, with: 500..<520)
    XCTAssertEqualElements(buffer, [500..<520, 105..<135, 500..<520, 140..<195, 500..<520].joined())
    XCTAssertEqualElements(buffer[range6], 500..<520)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 145)
    XCTAssertEqual(buffer.header.count, 145)
    didFinishTestStep(&buffer)

    // Start afresh.
    buffer.replaceSubrange(0..<145, with: EmptyCollection())
    XCTAssertEqualElements(buffer, [])
    XCTAssertTrue(buffer.isEmpty)
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    didFinishTestStep(&buffer)

    // Remove from the start.
    let range7 = buffer.replaceSubrange(0..<10, with: EmptyCollection())
    XCTAssertEqualElements(buffer, [110..<200].joined())
    XCTAssertEqual(range7, 0..<0)
    XCTAssertEqualElements(buffer[range7], EmptyCollection())
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 90)
    XCTAssertEqual(buffer.header.count, 90)
    didFinishTestStep(&buffer)

    // Remove from the middle.
    let range8 = buffer.replaceSubrange(40..<50, with: EmptyCollection())
    XCTAssertEqualElements(buffer, [110..<150, 160..<200].joined())
    XCTAssertEqual(range8, 40..<40)
    XCTAssertEqualElements(buffer[range8], EmptyCollection())
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 80)
    XCTAssertEqual(buffer.header.count, 80)
    didFinishTestStep(&buffer)

    // Remove from the end.
    let range9 = buffer.replaceSubrange(70..<80, with: EmptyCollection())
    XCTAssertEqualElements(buffer, [110..<150, 160..<190].joined())
    XCTAssertEqual(range9, 70..<70)
    XCTAssertEqualElements(buffer[range9], EmptyCollection())
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 70)
    XCTAssertEqual(buffer.header.count, 70)
    didFinishTestStep(&buffer)

    // Start afresh.
    buffer.replaceSubrange(0..<70, with: EmptyCollection())
    XCTAssertEqualElements(buffer, [])
    XCTAssertTrue(buffer.isEmpty)
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    didFinishTestStep(&buffer)

    // Insert elements at the start.
    let range10 = buffer.replaceSubrange(0..<0, with: 5..<10)
    XCTAssertEqualElements(buffer, [5..<10, 100..<200].joined())
    XCTAssertEqualElements(buffer[range10], 5..<10)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 105)
    XCTAssertEqual(buffer.header.count, 105)
    didFinishTestStep(&buffer)

    // Insert in the middle.
    let range11 = buffer.replaceSubrange(50..<50, with: 5..<10)
    XCTAssertEqualElements(buffer, [5..<10, 100..<145, 5..<10, 145..<200].joined())
    XCTAssertEqualElements(buffer[range11], 5..<10)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 110)
    XCTAssertEqual(buffer.header.count, 110)
    didFinishTestStep(&buffer)

    // Insert at the end.
    let range12 = buffer.replaceSubrange(110..<110, with: 5..<10)
    XCTAssertEqualElements(buffer, [5..<10, 100..<145, 5..<10, 145..<200, 5..<10].joined())
    XCTAssertEqualElements(buffer[range12], 5..<10)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 115)
    XCTAssertEqual(buffer.header.count, 115)
    didFinishTestStep(&buffer)
  }

  func testReplaceSubrange_inplace() {
    var lastAddress: UnsafePointer<Int>?
    doTestReplaceSubrange { buffer in
      let thisAddress = buffer.withUnsafeBufferPointer { $0.baseAddress }
      if lastAddress != nil {
        XCTAssertEqual(lastAddress, thisAddress)
      }
      lastAddress = thisAddress
    }
  }

  func testReplaceSubrange_outOfPlace() {
    var lastAddress: UnsafePointer<Int>?
    var lastBuffer: ManagedArrayBuffer<DataHolderHeader<Int>, Int>?
    doTestReplaceSubrange { buffer in
      let thisAddress = buffer.withUnsafeBufferPointer { $0.baseAddress }
      if lastAddress != nil {
        XCTAssertNotEqual(lastAddress, thisAddress)
      }
      lastAddress = thisAddress
      lastBuffer = buffer  // Escape the buffer.
    }
    XCTAssertNotNil(lastBuffer)  // Needs to be read to silence warning.
  }
}

extension ManagedArrayBufferTests {

  func doTestRemoveSubrange(_ didFinishTestStep: (inout ManagedArrayBuffer<DataHolderHeader<Int>, Int>) -> Void) {

    var buffer = ManagedArrayBuffer<DataHolderHeader<Int>, Int>(
      minimumCapacity: 10, initialHeader: DataHolderHeader(data: 42, count: -1, capacity: -1)
    )
    buffer.reserveCapacity(500)  // Make sure we never reallocate due to capacity, only due to COW.
    didFinishTestStep(&buffer)

    XCTAssertEqualElements(buffer, [])
    XCTAssertTrue(buffer.isEmpty)
    buffer.append(contentsOf: 100..<200)
    XCTAssertEqualElements(buffer, 100..<200)
    didFinishTestStep(&buffer)

    // Remove from the start.
    let index0 = buffer.removeSubrange(0..<10)
    XCTAssertEqualElements(buffer, [110..<200].joined())
    XCTAssertEqual(index0, 0)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 90)
    XCTAssertEqual(buffer.header.count, 90)
    didFinishTestStep(&buffer)

    // Remove from the middle.
    let index1 = buffer.removeSubrange(40..<50)
    XCTAssertEqualElements(buffer, [110..<150, 160..<200].joined())
    XCTAssertEqual(index1, 40)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 80)
    XCTAssertEqual(buffer.header.count, 80)
    didFinishTestStep(&buffer)

    // Remove from the end.
    let index2 = buffer.removeSubrange(70..<80)
    XCTAssertEqualElements(buffer, [110..<150, 160..<190].joined())
    XCTAssertEqual(index2, 70)
    XCTAssertEqual(buffer.header.data, 42)
    XCTAssertEqual(buffer.count, 70)
    XCTAssertEqual(buffer.header.count, 70)
    didFinishTestStep(&buffer)
  }

  func testRemoveSubrange_inplace() {
    var lastAddress: UnsafePointer<Int>?
    doTestRemoveSubrange { buffer in
      let thisAddress = buffer.withUnsafeBufferPointer { $0.baseAddress }
      if lastAddress != nil {
        XCTAssertEqual(lastAddress, thisAddress)
      }
      lastAddress = thisAddress
    }
  }

  func testRemoveSubrange_outOfPlace() {
    var lastAddress: UnsafePointer<Int>?
    var lastBuffer: ManagedArrayBuffer<DataHolderHeader<Int>, Int>?
    doTestRemoveSubrange { buffer in
      let thisAddress = buffer.withUnsafeBufferPointer { $0.baseAddress }
      if lastAddress != nil {
        XCTAssertNotEqual(lastAddress, thisAddress)
      }
      lastAddress = thisAddress
      lastBuffer = buffer  // Escape the buffer.
    }
    XCTAssertNotNil(lastBuffer)  // Needs to be read to silence warning.
  }
}
