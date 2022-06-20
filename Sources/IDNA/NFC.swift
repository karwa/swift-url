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

#if WEBURL_IDNA_USE_STDLIB_NFC

  @_spi(_Unicode) import Swift

  @usableFromInline
  internal typealias NFCIterator = AnyIterator<Unicode.Scalar>

  @inlinable
  internal func isNFC<C: Collection>(_ scalars: C) -> Bool where C.Element == Unicode.Scalar {
    toNFC(String(scalars)).elementsEqual(scalars)
  }

  @usableFromInline
  internal func toNFC(_ string: String) -> NFCIterator {
    if #available(macOS 9999, *) {
      return AnyIterator(string._nfc.makeIterator())
    } else {
      fatalError()
    }
  }

#else

  import Foundation

  @usableFromInline
  internal typealias NFCIterator = String.UnicodeScalarView.Iterator

  @inlinable
  internal func isNFC<C: Collection>(_ scalars: C) -> Bool where C.Element == Unicode.Scalar {
    IteratorSequence(toNFC(String(scalars))).elementsEqual(scalars)
  }

  @inlinable
  internal func toNFC(_ string: String) -> NFCIterator {
    string.precomposedStringWithCanonicalMapping.unicodeScalars.makeIterator()
  }

#endif

// Why is this not in the standard library?
extension String {

  @inlinable
  internal init<C>(_ scalars: C) where C: Collection, C.Element == Unicode.Scalar {
    // Unicode.Scalar is a UInt32:
    // https://github.com/apple/swift/blob/0c67ce64874d83b2d4f8d73b899ee58f2a75527f/stdlib/public/core/UnicodeScalar.swift#L38
    // Again, would be cool if the standard library would offer this interface,
    // so we wouldn't need to do... what I'm about to do.
    let _contiguousResult = scalars.withContiguousStorageIfAvailable { ptr in
      ptr.withMemoryRebound(to: UInt32.self) { utf32 in
        String(decoding: utf32, as: UTF32.self)
      }
    }
    if let contiguousResult = _contiguousResult {
      self = contiguousResult
      return
    }
    self = ""
    self.unicodeScalars.replaceSubrange(Range(uncheckedBounds: (endIndex, endIndex)), with: scalars)
  }
}
