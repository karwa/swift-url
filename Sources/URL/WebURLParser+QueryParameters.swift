
extension WebURLParser {
    
    public struct QueryParameters {
        public var items: [(name: String, value: String)] = []
        public init() {}
    }
}

extension WebURLParser.QueryParameters {
    
    /// Parses a `QueryParameters` object from an `application/x-www-form-urlencoded`-formatted String.
    ///
    /// Conforms to https://url.spec.whatwg.org/#urlencoded-parsing as of 27.06.2020
    ///
    init<C>(parsingUTF8 bytes: C) where C: Collection, C.Element == UInt8 {
        self.init()
        
        func processByteSequence(_ byteSequence: C.SubSequence) {
            let name: String
            let value: String
            if let separatorIdx  = byteSequence.firstIndex(of: ASCII.equalSign.codePoint),
               let valueStartIdx = byteSequence.index(separatorIdx, offsetBy: 1, limitedBy: byteSequence.endIndex) {
                name  = PercentEscaping.decodeFormEncodedString(utf8: byteSequence[Range(uncheckedBounds: (byteSequence.startIndex, separatorIdx))])
                value = PercentEscaping.decodeFormEncodedString(utf8: byteSequence[Range(uncheckedBounds: (valueStartIdx, byteSequence.endIndex))])
            } else {
                name  = PercentEscaping.decodeFormEncodedString(utf8: byteSequence)
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
            PercentEscaping.encodeIterativelyAsStringForForm(bytes: name.utf8) { output.append($0) }
            output.append("=")
            PercentEscaping.encodeIterativelyAsStringForForm(bytes: value.utf8) { output.append($0) }
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
        return WebURLParser.QueryParameters.serialiseQueryString(items)
    }
}
