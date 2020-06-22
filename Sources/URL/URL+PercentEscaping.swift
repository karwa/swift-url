// TODO: Think about exposing this as a public API.
// The issue with round-tripping Strings like "%100" (as required by the URL standard) makes it a bit awkward.

enum PercentEscaping {}

extension PercentEscaping {

    /// Encodes the given arbitrary byte sequence as an ASCII `String`, by means of the "percent-escaping" transformation.   
    ///
    /// - Bytes which are not valid ASCII characters are always transformed as the sequence "%ZZ",
    ///   where ZZ is the byte's numerical value as a hexadecimal string.
    /// - Bytes which are valid ASCII characters are also transformed if the predicate returns `true`.
    ///
    /// -  important: 	This algorithm does not round-trip for arbitrary byte sequences unless `shouldEscapeASCII` includes
    /// 				the `ASCII.percentSign` character itself. If not, sequences which happen to contain a valid escape string already
    ///                 will be not be escaped, and the reciever, expecting an additional level of escaping, will over-unescape the resulting String.
    ///
    /// - parameters:
    ///     - bytes:                The sequence of bytes to encode.
    ///     - shouldEscapeASCII:    The predicate which decides if a particular ASCII character should be escaped or not.
    ///
    /// - returns:  A percent-escaped ASCII `String` containing only the % character, upper-case hex digits, and
    ///             characters allowed by the predicate.
    ///
    static func encode<S>(bytes: S, where shouldEscapeASCII: (ASCII)->Bool) -> String where S: Sequence, S.Element == UInt8 {
        var output = ""
        output.reserveCapacity(bytes.underestimatedCount)
        withSmallStringSizedStackBuffer { buffer in
            var i = 0
            for byte in bytes {
                // If the buffer can't hold an escaped byte, flush it.
                if i &+ 3 > buffer.count {
                    output.append(String(decoding: UnsafeBufferPointer(rebasing: buffer[..<i]), as: Unicode.ASCII.self))
                    i = 0
                }
                // Non-ASCII bytes are always escaped.
                guard let asciiChar = ASCII(byte) else {
                    _escape(byte: byte, into: UnsafeMutableBufferPointer(rebasing: buffer[i...]))
                    i &+= 3
                    continue
                }
                // ASCII bytes are conditionally escaped, depending on the predicate.
                if shouldEscapeASCII(asciiChar) {
                    _escape(byte: byte, into: UnsafeMutableBufferPointer(rebasing: buffer[i...]))
                    i &+= 3
                } else {
                    buffer[i] = byte
                    i &+= 1
                }
            }
            // Flush the buffer.
            output.append(String(decoding: UnsafeBufferPointer(rebasing: buffer[..<i]), as: Unicode.ASCII.self))
        }
        return output
    }
    
    /// Encodes a single UTF8-encoded codepoint as an ASCII `String`, by means of the "percent-escaping" transformation.
    ///
    /// - Code-points which are not ASCII characters are always transformed as the sequence "%ZZ%ZZ%ZZ...",
    ///   where ZZ are the UTF8 bytes' numerical values as a hexadecimal string.
    /// - Bytes which are valid ASCII characters are also transformed if the predicate returns `true`.
    ///
    /// -  important:	This algorithm does not encode the `ASCII.percentSign` character itself,
    /// 			   	unless it is explicitly told to do so by the predicate.
    /// - precondition:	`singleUTF8CodePoint` may not be larger than 4 bytes.
    ///
    /// - parameters:
    ///     - singleUTF8CodePoint:  The single UTF8-encoded codepoint to transform. May not be larger than 4 bytes.
    ///     - shouldEscapeASCII:    The predicate which decides if a particular ASCII character should be escaped or not.
    ///
    /// - returns:  A percent-escaped ASCII `String` containing only the % character, upper-case hex digits, and
    ///             characters allowed by the predicate.
    ///
    static func encode<C>(singleUTF8CodePoint: C, where shouldEscapeASCII: (ASCII)->Bool) -> String where C: Collection, C.Element == UInt8 {
        precondition(singleUTF8CodePoint.count <= 4, "Cannot encode more than a single codepoint")
        return String(unsafeUninitializedCapacity: 12) { buffer in
            var i = 0
            for byte in singleUTF8CodePoint {
                if let asciiChar = ASCII(byte), shouldEscapeASCII(asciiChar) == false {
                    buffer[0] = byte
                    return 1 // An ASCII byte means the code-point is over.
                }
                _escape(byte: byte, into: UnsafeMutableBufferPointer(rebasing: buffer[i...]))
                i &+= 3
            }
            return i
        }
    }

    /// Note: Assumes that output.count >= 3.
    private static func _escape(byte: UInt8, into output: UnsafeMutableBufferPointer<UInt8>) {
        output[0] = ASCII.percentSign.codePoint
        output[1] = ASCII.getHexDigit_upper(byte >> 4).codePoint
        output[2] = ASCII.getHexDigit_upper(byte).codePoint
    }
}

extension PercentEscaping {

    /// Decodes the given percent-escaped byte sequence, without interpreting the result.   
    ///
    /// The decoder replaces patterns of the form "%ZZ" with the byte 0xZZ, where Z is an ASCII hexadecimal digit.
    /// The decoded sequence is returned as a binary blob, without additional interpretation. If the contents are expected
    /// to be a UTF8-encoded `String`, use the `decodeString` function instead.
    /// 
    /// - parameters:
    ///     - bytes:    The sequence of bytes to decode.
    ///
    /// - returns:  An `Array` of bytes containing the unescaped contents of the given sequence. 
    ///
    static func decode<C>(bytes: C) -> Array<UInt8> where C: Collection, C.Element == UInt8 {
        var decodedByteCount = 0
        switch _decode(bytes: bytes, onDecode: { _ in decodedByteCount &+= 1 }) {
        case .none:
            assert(decodedByteCount == bytes.count)
            return Array(bytes)
        case .some(let firstEscapedByte):
            assert(decodedByteCount < bytes.count)
            return Array(unsafeUninitializedCapacity: decodedByteCount) { buffer, count in
                count = buffer.initialize(from: bytes[..<firstEscapedByte]).1
                _ = _decode(bytes: bytes[firstEscapedByte...], onDecode: { buffer[count] = $0; count &+= 1 })
            }
        }
    }

    /// Decodes the given percent-escaped byte sequence and interprets the result as a UTF8-encoded `String`.   
    ///
    /// The decoder replaces patterns of the form "%ZZ" with the byte 0xZZ, where Z is an ASCII hexadecimal digit.
    /// If the decoded byte sequence represents an invalid UTF8 `String`, it will be repaired by replacing
    /// the appropriate parts with the unicode replacement character (U+FFFD).
    /// 
    /// - parameters:
    ///     - bytes:    The sequence of bytes to decode.
    ///
    /// - returns:  A `String` containing the unescaped contents of the given byte sequence, interpreted as UTF8. 
    ///
    static func decodeString<C>(utf8 bytes: C) -> String where C: Collection, C.Element == UInt8 {

        // We cannot decode in fixed-size chunks, since each chunk might not be a valid UTF8 sequence.
        // So there ends up being 3 potential strategies to decoding:
        //
        // 1. Decode in to a temporary Array, then copy in to a String.
        //    - Possibly causing 2 heap allocations, depending on the eventual length of the decoded bytes.
        //
        // 2. Be conservative and ask String for a capacity of `bytes.count`,
        //    even though we may end up using significantly less than that.
        //    - Given that one byte of the original gets escaped as 3 bytes,
        //      we will almost never decode in to a small-string, even if the decoded string really is small.
        //      e.g. "🐶️%" is 8 bytes decoded (small) but 22 bytes when escaped -- and it's more than just non-ASCII
        //      characters that get escaped (also spaces, slashes, question marks, etc).
        //
        // 3. Scan the String and determine the actual required capacity before decoding. 
        //    - This makes the operation 2*O(n), but is able to avoid heap allocations if the decoded string is small.
        //      We can also perform the second decoding pass from the first escaped byte and avoid copying unescaped strings.
        //
        // Each part of a URL tends to be relatively small once decoded and gets defensively unescaped
        // (it often isn't even escaped at all). So we choose option #3. 

        var decodedByteCount = 0
        switch _decode(bytes: bytes, onDecode: { _ in decodedByteCount &+= 1 }) {
        case .none:
            assert(decodedByteCount == bytes.count)
            return String(decoding: bytes, as: UTF8.self)
        case .some(let firstEscapedByte):
            assert(decodedByteCount < bytes.count)
            return String(unsafeUninitializedCapacity: decodedByteCount) { buffer in
                var i = buffer.initialize(from: bytes[..<firstEscapedByte]).1
                _ = _decode(bytes: bytes[firstEscapedByte...], onDecode: { buffer[i] = $0; i &+= 1 })
                return i
            }
        }
    }

    // Fast path for decoding a String when the source is another String.
    // In that case, non-escaped strings can just be returned without copying
    // (which is a common case; strings are often defensively unescaped).

    /// Decodes the given percent-escaped `String` and interprets the result as a UTF8 `String`.    
    ///
    /// The decoder replaces patterns of the form "%ZZ" with the byte 0xZZ, where Z is an ASCII hexadecimal digit.
    /// If the decoded byte sequence represents an invalid UTF8 `String`, it will be repaired by replacing
    /// the appropriate parts with the unicode replacement character (U+FFFD).
    /// 
    /// - parameters:
    ///     - string:    The string to decode.
    ///
    /// - returns:  A `String` containing the unescaped contents of the given `String`, interpreted as UTF8. 
    ///
    static func decodeString<S>(_ string: S) -> String where S: StringProtocol {
        let original = string
        return string._withUTF8 { bytes in
            var decodedByteCount = 0
            switch _decode(bytes: bytes, onDecode: { _ in decodedByteCount &+= 1 }) {
            case .none:
                assert(decodedByteCount == bytes.count)
                return String(original) // This shouldn't result in a copy.
            case .some(let firstEscapedByte):
                assert(decodedByteCount < bytes.count)
                return String(unsafeUninitializedCapacity: decodedByteCount) { buffer in
                    var i = buffer.initialize(from: bytes[..<firstEscapedByte]).1
                    _ = _decode(bytes: bytes[firstEscapedByte...], onDecode: { buffer[i] = $0; i &+= 1 })
                    return i
                }
            }
        }
    }

    private static func _decode<C>(bytes: C, onDecode: (UInt8)->Void) -> C.Index? where C: Collection, C.Element == UInt8 {
        var firstEscapedByteIndex: C.Index?
        var byte0Index = bytes.startIndex
        while byte0Index != bytes.endIndex {
            let byte0 = bytes[byte0Index]
            if _slowPath(byte0 == ASCII.percentSign) {
                // Try to decode the next two bytes. If either one fails, byte0 isn't the start of a percent-escaped byte;
                // invoke the callback with `byte0` and try again from `byte1`.
                let byte1Index    = bytes.index(after: byte0Index)
                guard byte1Index != bytes.endIndex,
                        let decodedByte1 = ASCII(bytes[byte1Index]).map({ ASCII.parseHexDigit(ascii: $0) }),
                        decodedByte1 != ASCII.parse_NotFound else {
                            onDecode(byte0)
                            byte0Index = byte1Index
                            continue
                }
                let byte2Index    = bytes.index(after: byte1Index)
                guard byte2Index != bytes.endIndex,
                        let decodedByte2 = ASCII(bytes[byte2Index]).map({ ASCII.parseHexDigit(ascii: $0) }),
                        decodedByte2 != ASCII.parse_NotFound else { 
                            onDecode(byte0)
                            byte0Index = byte1Index
                            continue
                }
                let decodedValue = (decodedByte1 &* 16) &+ (decodedByte2)
                onDecode(decodedValue)
                if firstEscapedByteIndex == nil { 
                    firstEscapedByteIndex = byte0Index
                }
                byte0Index = bytes.index(after: byte2Index)
            } else {
                onDecode(byte0)
                byte0Index = bytes.index(after: byte0Index)
            }
        }
        return firstEscapedByteIndex
    }
}

extension StringProtocol {

    /// Encodes the given String's UTF8-encoded bytes as an ASCII String, by means of the "percent-escaping" transformation.   
    ///
    /// - Bytes which are valid ASCII characters are replaced by the sequence "%XX" if the predicate returns `true`,
    ///   where XX is the byte's numerical value in hexadecimal.
    /// - Bytes which are not valid ASCII characters are always escaped.
    ///
    /// - parameters:
    ///     - shouldEscapeASCII:    The predicate which decides if a particular ASCII character should be escaped or not.
    ///
    /// - returns:  A percent-escaped ASCII String from which the original String may be decoded. 
    ///
    @_specialize(where Self == String)
    @_specialize(where Self == Substring)
    func percentEscaped(where shouldEscapeASCII: (ASCII)->Bool) -> String {
        return self._withUTF8 { PercentEscaping.encode(bytes: $0, where: shouldEscapeASCII) }
    }

    /// Decodes the given percent-escaped `String` and interprets the result as a UTF8 `String`.    
    ///
    /// The decoder replaces patterns of the form "%ZZ" with the byte 0xZZ, where Z is an ASCII hexadecimal digit.
    /// If the decoded byte sequence represents an invalid UTF8 `String`, it will be repaired by replacing
    /// the appropriate parts with the unicode replacement character (U+FFFD).
    ///
    /// - returns:  A `String` containing the unescaped contents of the given `String`, interpreted as UTF8. 
    ///
    @_specialize(where Self == String)
    @_specialize(where Self == Substring)
    func removingPercentEscaping() -> String {
        return PercentEscaping.decodeString(self)
    }
}

extension Character {

    /// Encodes the given Character's UTF8-encoded bytes as an ASCII String, by means of the "percent-escaping" transformation.   
    ///
    /// - If the Character is ASCII, it is replaced by the sequence "%XX" if the predicate returns `true`,
    ///   where XX is the ASCII codepoint's numerical value in hexadecimal.
    /// - Characters which are not ASCII are always escaped.
    ///
    /// - parameters:
    ///     - shouldEscapeASCII:    The predicate which decides if a particular ASCII character should be escaped or not.
    ///
    /// - returns:  A percent-escaped ASCII String from which the original Character may be decoded. 
    ///
    func percentEscaped(where shouldEscapeASCII: (ASCII)->Bool) -> String {
        return PercentEscaping.encode(bytes: self.utf8, where: shouldEscapeASCII)
    }
}

// - URL Percent-escaping predicates.

func url_escape_c0(_ byte: ASCII) -> Bool {
    byte.codePoint > 0x7E || ASCII.ranges.controlCharacters.contains(byte)
}
func url_escape_fragment(_ byte: ASCII) -> Bool {
    guard !url_escape_c0(byte) else { return true }
    switch byte {
    case ASCII.space, ASCII.doubleQuotationMark, ASCII.lessThanSign, ASCII.greaterThanSign, ASCII.backtick:
        return true
    default:
        return false 
    }
}
func url_escape_path(_ byte: ASCII) -> Bool {
    guard !url_escape_fragment(byte) else { return true }
    switch byte {
    case ASCII.numberSign, ASCII.questionMark, ASCII.leftCurlyBracket, ASCII.rightCurlyBracket:
        return true
    default:
        return false 
    }
}
func url_escape_userInfo(_ byte: ASCII) -> Bool {
    guard !url_escape_path(byte) else { return true }
    switch byte {
    case ASCII.forwardSlash, ASCII.colon, ASCII.semicolon, ASCII.equalSign, ASCII.commercialAt, ASCII.leftSquareBracket, ASCII.rightSquareBracket, ASCII.backslash, ASCII.circumflexAccent, ASCII.verticalBar:
        return true
    default:
        return false 
    }
}
