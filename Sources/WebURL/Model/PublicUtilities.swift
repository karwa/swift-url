
extension StringProtocol {
  
  /// Returns a copy of this string with all special URL characters percent-encoded. Equivalent to JavaScript's `encodeURIComponent()` function.
  ///
  /// The % character itself is included in the encode-set, so that any percent-encoded characters in the original string are preserved and decoding this
  /// string returns the original content without loss.
  ///
  public var urlEncoded: String {
    let encodedBytes = self.utf8.lazy.percentEncoded(using: URLEncodeSet.Component.self).joined()
    return String(_unsafeUninitializedCapacity: encodedBytes.count) { buffer  in
      return buffer.initialize(from: encodedBytes).1
    }
  }
}
