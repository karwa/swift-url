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

/// A fixed-capacity stack view over unowned memory.
///
/// This type allows for a variable `count` Collection view over a region of memory.
/// Append items using the `push` method, and remove them using `pop`. Appending more elements
/// than the stack has capacity for, or popping elements when the stack is empty, will trigger a runtime error.
///
/// This type is unsafe, as it does not own the memory used to store elements, and it is your responsibility
/// to ensure that its lifetime does not exceed that of the memory it points to.
///
@usableFromInline
internal struct UnsafeSmallStack<Element> {

  @usableFromInline
  internal var _storage: UnsafeMutablePointer<Element?>

  @usableFromInline
  internal var _capacity: UInt8

  @usableFromInline
  internal var _count: UInt8

  /// Creates an `UnsafeSmallStack` over the given region of memory, containing instances of `Optional<Element>`.
  /// The entire capacity must be initialized - e.g. to `Optional<Element>.none`/`nil`.
  ///
  @inlinable
  internal init(ptr: UnsafeMutablePointer<Element?>, capacity: UInt8) {
    self._storage = ptr
    self._capacity = capacity
    self._count = 0
  }
}

extension UnsafeSmallStack: RandomAccessCollection {

  @usableFromInline
  internal typealias Index = UInt8

  @inlinable
  internal var startIndex: UInt8 { 0 }

  @inlinable
  internal var endIndex: UInt8 { _count }

  @inlinable
  internal var count: Int { Int(_count) }

  @inlinable
  internal func index(after i: UInt8) -> UInt8 { i &+ 1 }

  @inlinable
  internal func index(before i: UInt8) -> UInt8 { i &- 1 }

  @inlinable
  internal subscript(position: UInt8) -> Element {
    precondition(position < _count)
    return (_storage + Int(position)).pointee.unsafelyUnwrapped
  }
}

extension UnsafeSmallStack {

  /// Appends an item to the end of the stack.
  /// If the stack has no more capacity, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func push(_ newElement: Element) {
    precondition(_count < _capacity)
    (_storage + Int(_count)).pointee = newElement
    _count &+= 1
  }

  /// Removes the last item from the stack.
  /// If the stack is empty, a runtime error is triggered.
  ///
  @inlinable
  internal mutating func pop(_ newElement: Element) {
    precondition(_count > 0)
    (_storage + Int(_count)).pointee = nil
    _count &-= 1
  }

  @inlinable
  internal static func += (_ stack: inout Self, _ newElement: Element) {
    stack.push(newElement)
  }
}

/// Executes `body`, passing in an `UnsafeSmallStack` with capacity for 2 elements of the given type.
///
/// - important: The lifetime of the `UnsafeSmallStack` must not escape the duration of `body`.
///
@inlinable @inline(__always)
func withUnsafeSmallStack_2<Element, Result>(
  of: Element.Type, _ body: (inout UnsafeSmallStack<Element>) -> Result
) -> Result {
  var storage: (Element?, Element?) = (nil, nil)
  return withUnsafeMutableBufferPointerToElements(tuple: &storage) {
    var arrayView = UnsafeSmallStack(ptr: $0.baseAddress.unsafelyUnwrapped, capacity: 2)
    return body(&arrayView)
  }
}
