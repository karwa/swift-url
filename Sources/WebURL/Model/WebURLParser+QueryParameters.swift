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

extension WebURL {

  public struct QueryParameters {
    public var items: [(name: String, value: String)] = []
    public init() {}
  }
}

extension WebURL.QueryParameters {

  /// Parses a `QueryParameters` object from an `application/x-www-form-urlencoded`-formatted String.
  ///
  /// Conforms to https://url.spec.whatwg.org/#urlencoded-parsing as of 27.06.2020
  ///
  init<C>(parsingUTF8 bytes: C) where C: Collection, C.Element == UInt8 {
    self.init()

    func processByteSequence(_ byteSequence: C.SubSequence) {
      let name: String
      let value: String
      if let separatorIdx = byteSequence.firstIndex(of: ASCII.equalSign.codePoint) {
        name = String(
          decoding: byteSequence[Range(uncheckedBounds: (byteSequence.startIndex, separatorIdx))]
            .lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self),
          as: UTF8.self
        )
        let valueStartIdx = byteSequence.index(after: separatorIdx)
        value = String(
          decoding: byteSequence[Range(uncheckedBounds: (valueStartIdx, byteSequence.endIndex))]
            .lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self),
          as: UTF8.self
        )
      } else {
        name = String(
          decoding: byteSequence.lazy.percentDecoded(using: URLEncodeSet.FormEncoded.self),
          as: UTF8.self
        )
        value = ""
      }
      items.append((name, value))
    }

    var remainingBytes = bytes[...]
    while remainingBytes.isEmpty == false {
      if let byteSequenceEnd = remainingBytes.firstIndex(of: ASCII.ampersand.codePoint) {
        processByteSequence(remainingBytes.prefix(upTo: byteSequenceEnd))
        remainingBytes = remainingBytes.suffix(from: byteSequenceEnd).dropFirst()
      } else {
        processByteSequence(remainingBytes)
        break
      }
    }
  }

  /// Serializes a seqeuence of (name, value) pairs as a `application/x-www-form-urlencoded`-formatted String.
  ///
  /// Conforms to https://url.spec.whatwg.org/#urlencoded-serializing as of 27.06.2020
  ///
  static func serialiseQueryString<S>(_ queryComponents: S) -> String where S: Sequence, S.Element == (String, String) {
    var output = ""
    for (name, value) in queryComponents {
      output.append(name.urlFormEncoded)
      output.append("=")
      output.append(value.urlFormEncoded)
      output.append("&")
    }
    if !output.isEmpty { output.removeLast() }
    return output
  }

  /// Serializes a `QueryParameters` object to a `application/x-www-form-urlencoded`-formatted String.
  ///
  /// Conforms to https://url.spec.whatwg.org/#urlencoded-serializing as of 27.06.2020
  ///
  var serialized: String {
    return WebURL.QueryParameters.serialiseQueryString(items)
  }
}
