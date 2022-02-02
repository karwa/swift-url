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
// MARK: - Contiguous UTF-8
// --------------------------------------------
// Copied from WebURL/Util/StringAdditions.swift


extension StringProtocol {

  /// Calls `body` with this string's contents in a contiguous UTF-8 buffer.
  ///
  /// - If this is already a native String/Substring, its contiguous storage will be used directly.
  /// - Otherwise, it will be copied to contiguous storage.
  ///
  @inlinable @inline(__always)
  internal func _withContiguousUTF8<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
    if let resultWithExistingStorage = try utf8.withContiguousStorageIfAvailable(body) {
      return resultWithExistingStorage
    }
    var copy = String(self)
    return try copy.withUTF8(body)
  }
}

extension Optional where Wrapped: StringProtocol {

  /// Calls `body` with this string's contents in a contiguous UTF-8 buffer.
  ///
  /// - If this value is `nil`, `body` is invoked with `nil`.
  /// - If this is already a native String/Substring, its contiguous storage will be used directly.
  /// - Otherwise, it will be copied to contiguous storage.
  ///
  @inlinable @inline(__always)
  internal func _withContiguousUTF8<Result>(_ body: (UnsafeBufferPointer<UInt8>?) throws -> Result) rethrows -> Result {
    switch self {
    case .some(let string): return try string._withContiguousUTF8(body)
    case .none: return try body(nil)
    }
  }
}
