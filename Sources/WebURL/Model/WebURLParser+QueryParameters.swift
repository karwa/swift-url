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
      PercentEncoding.encode(bytes: name.utf8, using: URLEncodeSet.FormEncoded.self) {
        output.append(String(decoding: $0, as: UTF8.self))
      }
      output.append("=")
      PercentEncoding.encode(bytes: value.utf8, using: URLEncodeSet.FormEncoded.self) {
        output.append(String(decoding: $0, as: UTF8.self))
      }
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
