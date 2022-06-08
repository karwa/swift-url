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

  @inlinable
  internal func isNFC<C: Collection>(_ scalars: C) -> Bool where C.Element == Unicode.Scalar {
    var s = ""
    s.unicodeScalars.append(contentsOf: scalars)
    if #available(macOS 9999, *) {
      return s._nfc.elementsEqual(scalars)
    } else {
      fatalError()
    }
  }

  @inlinable
  internal func toNFC(_ string: String) -> [Unicode.Scalar] {
    if #available(macOS 9999, *) {
      return Array(string._nfc)
    } else {
      fatalError()
    }
  }

#else

  import Foundation

  @inlinable
  internal func isNFC<C: Collection>(_ scalars: C) -> Bool where C.Element == Unicode.Scalar {
    var str = ""
    str.unicodeScalars.append(contentsOf: scalars)
    return str.precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual(scalars)
  }

  @inlinable
  internal func toNFC(_ string: String) -> [Unicode.Scalar] {
    Array(string.precomposedStringWithCanonicalMapping.unicodeScalars)
  }

#endif
