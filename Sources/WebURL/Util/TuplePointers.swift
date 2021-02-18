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

extension UnsafeRawBufferPointer {

  /// Returns a typed pointer to the memory referenced by this buffer, assuming that the memory is already bound to the specified type.
  ///
  /// This is equivalent to calling `UnsafeRawPointer.assumingMemoryBound` on this buffer's base address, and dividing this buffer's
  /// `count` by the `stride` of the given type. Be sure to do lots of research on the above method before even thinking about using this.
  ///
  fileprivate func assumingMemoryBound<T>(to: T.Type) -> UnsafeBufferPointer<T> {
    guard let base = baseAddress else {
      return .init(start: nil, count: 0)
    }
    // Question: If we 'assumingMemoryBound' the base address, can we just make a buffer with the correct 'count'
    //           and treat all of it as typed/bound?
    //
    // Answer:   Yes. Unlike 'bindMemory', which calls a Builtin function [1] with the pointer address and number of
    //           elements and communicates to the compiler the entire _region_ of memory being bound,
    //           'assumingMemoryBound' does nothing [2] - it doesn't call any Builtins, and simply constructs
    //           a typed pointer from an untyped one.
    //
    //           That's what makes it so dangerous: as it doesn't actually communicate anything to the compiler
    //           about how the memory is being accessed, incorrect use can cause type-based anti-aliasing to miscompile.
    //           As the name suggests, we assume the compiler already knows - i.e. that the entire region has already
    //           been bound.
    //
    // [1]: https://github.com/apple/swift/blob/a0098c0174199b76473636af50699e21b688110c/stdlib/public/core/UnsafeRawBufferPointer.swift.gyb#L692
    // [2]: https://github.com/apple/swift/blob/a0098c0174199b76473636af50699e21b688110c/stdlib/public/core/UnsafeRawPointer.swift#L335
    return .init(start: base.assumingMemoryBound(to: to), count: count / MemoryLayout<T>.stride)
  }
}

extension UnsafeMutableRawBufferPointer {

  /// Returns a typed pointer to the memory referenced by this buffer, assuming that the memory is already bound to the specified type.
  ///
  /// This is equivalent to calling `UnsafeMutableRawPointer.assumingMemoryBound` on this buffer's base address, and dividing this buffer's
  /// `count` by the `stride` of the given type. Be sure to do lots of research on the above method before even thinking about using this.
  ///
  fileprivate func assumingMemoryBound<T>(to: T.Type) -> UnsafeMutableBufferPointer<T> {
    guard let base = baseAddress else {
      return .init(start: nil, count: 0)
    }
    return .init(start: base.assumingMemoryBound(to: to), count: count / MemoryLayout<T>.stride)
  }
}

// Arity 4:

func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T, T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = $0.assumingMemoryBound(to: T.self)
    return body(&ptr)
  }
}

// Arity 8:

func withUnsafeBufferPointerToElements<T, Result>(
  tuple: (T, T, T, T, T, T, T, T), _ body: (UnsafeBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeBytes(of: tuple) {
    return body($0.assumingMemoryBound(to: T.self))
  }
}

func withUnsafeMutableBufferPointerToElements<T, Result>(
  tuple: inout (T, T, T, T, T, T, T, T), _ body: (inout UnsafeMutableBufferPointer<T>) -> Result
) -> Result {
  return withUnsafeMutableBytes(of: &tuple) {
    var ptr = $0.assumingMemoryBound(to: T.self)
    return body(&ptr)
  }
}
