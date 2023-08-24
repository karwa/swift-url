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

/// Executes `body`, passing in an `UnsafeSmallStack` with capacity for 2 elements of the given type.
///
/// - important: The lifetime of the `UnsafeSmallStack` must not escape the duration of `body`.
///
@inlinable @inline(__always)
func withUnsafeSmallStack_2<Element, Result>(
  of: Element.Type, _ body: (inout FixedCapacityStack<Element>) -> Result
) -> Result {

  #if swift(>=5.6)
    withStack(of: Element.self, capacity: 2, body)
  #else
    var storage: (Element?, Element?) = (nil, nil)
    return withUnsafeMutableBufferPointerToElements(tuple: &storage) {
      var stack = FixedCapacityStack(ptr: $0.baseAddress.unsafelyUnwrapped, capacity: 2)
      return body(&stack)
    }
  #endif
}

#if swift(>=5.6)

  @inlinable
  internal func withStack<Element, Result>(
    of: Element.Type, capacity: UInt8, _ body: (inout FixedCapacityStack<Element>) -> Result
  ) -> Result {
    withUnsafeTemporaryAllocation(of: Element.self, capacity: Int(capacity)) { storage in
      var stack = FixedCapacityStack(_doNotUse: storage.baseAddress!, capacity: capacity)
      defer {
        precondition(stack._storage == storage.baseAddress)
        // We'd like to have the stack's deinit deinitialize the elements on Swift 5.9+,
        // but there seems to be a compiler bug.
        // #if swift(<5.9)
          stack.clear()
        // #endif
      }
      return body(&stack)
    }
  }

#endif

#if swift(>=5.9)

  /// A fixed-capacity stack of elements.
  ///
  /// Append elements using the `push` method, and remove them using `pop`.
  /// Appending more elements than the stack has capacity for, or popping elements when the stack is empty,
  /// will trigger a runtime error.
  ///
  /// To create a stack, use the global `withStack(of:capacity:)` function:
  ///
  /// ```swift
  /// withStack(of: Int.self, capacity: 4) { stack in
  ///   stack.push(42)
  ///   stack.push(99)
  ///   ...
  ///   stack.pop() // 99
  /// }
  /// ```
  ///
  @usableFromInline
  internal struct FixedCapacityStack<Element>: ~Copyable {

    @usableFromInline
    internal var _storage: UnsafeMutablePointer<Element>

    @usableFromInline
    internal var _count: UInt8

    @usableFromInline
    internal var _capacity: UInt8

    @inlinable
    internal init(_doNotUse ptr: UnsafeMutablePointer<Element>, capacity: UInt8) {
      self._storage = ptr
      self._count = 0
      self._capacity = capacity
    }

    deinit {
      precondition(_count == 0, "Still \(_count) elements not deinitialized")
      // _storage.deinitialize(count: Int(_count))
    }
  }

#else

  /// A fixed-capacity stack of elements.
  ///
  /// Append elements using the `push` method, and remove them using `pop`.
  /// Appending more elements than the stack has capacity for, or popping elements when the stack is empty,
  /// will trigger a runtime error.
  ///
  /// To create a stack, use the global `withStack(of:capacity:)` function:
  ///
  /// ```swift
  /// withStack(of: Int.self, capacity: 4) { stack in
  ///   stack.push(42)
  ///   stack.push(99)
  ///   ...
  ///   stack.pop() // 99
  /// }
  /// ```
  ///
  @usableFromInline
  internal struct FixedCapacityStack<Element> {

    #if swift(>=5.6)
      @usableFromInline
      internal typealias StorageElement = Element
    #else
      @usableFromInline
      internal typealias StorageElement = Element?
    #endif

    @usableFromInline
    internal var _storage: UnsafeMutablePointer<StorageElement>

    @usableFromInline
    internal var _count: UInt8

    @usableFromInline
    internal var _capacity: UInt8

    @inlinable
    internal init(ptr: UnsafeMutablePointer<StorageElement>, capacity: UInt8) {
      self._storage = ptr
      self._count = 0
      self._capacity = capacity
    }
  }

#endif

extension FixedCapacityStack {

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
}

extension FixedCapacityStack {

  @inlinable
  func forEach(_ body: (Element) -> Void) {
    var i = startIndex
    while i < endIndex {
      body(self[i])
      i = index(after: i)
    }
  }

  @inlinable
  func reversedForEach(_ body: (Element) -> Void) {
    var i = endIndex
    while i > startIndex {
      i = index(before: i)
      body(self[i])
    }
  }
}

#if swift(>=5.6)

  extension FixedCapacityStack {

    @inlinable
    internal subscript(position: UInt8) -> Element {
      precondition(position < _count)
      return (_storage + Int(position)).pointee
    }

    /// Appends an item to the end of the stack.
    /// If the stack has no more capacity, a runtime error is triggered.
    ///
    @inlinable
    internal mutating func push(_ newElement: __owned Element) {
      precondition(_count < _capacity)
      (_storage + Int(_count)).initialize(to: newElement)
      _count &+= 1
    }

    /// Removes the last item from the stack.
    /// If the stack is empty, a runtime error is triggered.
    ///
    @inlinable
    internal mutating func pop() -> Element {
      precondition(_count > 0)
      defer { _count &-= 1 }
      return (_storage + Int(_count)).move()
    }

    @inlinable
    internal mutating func clear() {
      _storage.deinitialize(count: Int(_count))
      _count = 0
    }
  }

#else

  extension FixedCapacityStack {

    @inlinable
    internal subscript(position: UInt8) -> Element {
      precondition(position < _count)
      return (_storage + Int(position)).pointee.unsafelyUnwrapped
    }

    /// Appends an item to the end of the stack.
    /// If the stack has no more capacity, a runtime error is triggered.
    ///
    @inlinable
    internal mutating func push(_ newElement: __owned Element) {
      precondition(_count < _capacity)
      (_storage + Int(_count)).pointee = newElement
      _count &+= 1
    }

    /// Removes the last item from the stack.
    /// If the stack is empty, a runtime error is triggered.
    ///
    @inlinable
    internal mutating func pop() -> Element {
      precondition(_count > 0)
      var lastElement: Element? = nil
      swap(&lastElement, &(_storage + Int(_count)).pointee)
      _count &-= 1
      return lastElement!
    }
  }

#endif

extension FixedCapacityStack {

  @inlinable
  internal static func += (_ stack: inout Self, _ newElement: __owned Element) {
    stack.push(newElement)
  }
}
