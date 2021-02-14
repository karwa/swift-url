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

// - General (non URL-related) String utilities.

// -- String Creation.

extension String {

  init(
    _unsafeUninitializedCapacity capacity: Int,
    initializingUTF8With initializer: (_ buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int
  ) rethrows {
    // FIXME: We actually want an SDK version check.
    // See: https://forums.swift.org/t/do-we-need-something-like-if-available/40349/16
    //    #if swift(>=5.3)
    //    if #available(macOS 10.16, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
    //      self = try String(unsafeUninitializedCapacity: capacity, initializingUTF8With: initializer)
    //      return
    //    }
    //    #endif
    if capacity <= 32 {
      let newStr = try with32ByteStackBuffer { buffer -> String in
        let count = try initializer(buffer)
        return String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
      }
      self = newStr
      return
    } else {
      let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
      defer { buffer.deallocate() }
      let count = try initializer(buffer)
      self = String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
    }
  }
}

/// Performs the given closure with a (hopefully) stack-allocated buffer whose UTF8 code-unit capacity matches
/// the smol-string capacity on the current platform. The goal is that creating a `String` from this buffer
/// will create a smol-string (no heap allocation), so it's good to use in a loop where you're making lots
/// of temporary `String`s (maybe because you need to `.append` them to a pre-existing `String`,
/// but `String` doesn't let you just append UTF8 code-units directly).
///
func withSmallStringSizedStackBuffer<T>(_ perform: (UnsafeMutableBufferPointer<UInt8>) throws -> T) rethrows -> T {
  #if arch(i386) || arch(arm) || arch(wasm32)
    var buffer: (Int64, Int16) = (0, 0)
    let capacity = 10
  #else
    var buffer: (Int64, Int64) = (0, 0)
    let capacity = 15
  #endif
  return try withUnsafeMutablePointer(to: &buffer) { ptr in
    return try ptr.withMemoryRebound(to: UInt8.self, capacity: capacity) { basePtr in
      let bufPtr = UnsafeMutableBufferPointer(start: basePtr, count: capacity)
      return try perform(bufPtr)
    }
  }
}

private func with32ByteStackBuffer<T>(_ perform: (UnsafeMutableBufferPointer<UInt8>) throws -> T) rethrows -> T {
  var buffer: (Int64, Int64, Int64, Int64) = (0, 0, 0, 0)
  let capacity = 32
  return try withUnsafeMutablePointer(to: &buffer) { ptr in
    return try ptr.withMemoryRebound(to: UInt8.self, capacity: capacity) { basePtr in
      let bufPtr = UnsafeMutableBufferPointer(start: basePtr, count: capacity)
      return try perform(bufPtr)
    }
  }
}

extension StringProtocol {

  @inlinable @inline(__always)
  func _withUTF8<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
    if var string = self as? String {
      return try string.withUTF8(body)
    } else {
      var substring = self as! Substring
      return try substring.withUTF8(body)
    }
  }
}
