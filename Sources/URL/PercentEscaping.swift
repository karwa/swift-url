// TODO: Think about exposing this as a public API.
// The issue with round-tripping Strings like "%100" (as required by the URL standard) makes it a bit awkward.

enum PercentEscaping {
    struct EscapeSet {
        var shouldEscape: (ASCII)->Bool
    }
}

// Encoding.
// The encoding interface contains 2 sets of entry-points:
//
// 1. Iteratively encoding an arbitrary-length sequence of bytes, into a small buffer or "smol" String,
//    with callbacks to process each chunk.
// 2. Encoding a single UTF8-encoded code-point, again in to a small buffer or "smol" String.
//    There is a callback (due to the buffer hopefully being stack-allocated), but it is only called once.
//
// Each of these entry-points has a buffer and String version, in case it makes sense to defer the String
// validation overhead.

extension PercentEscaping {

    /// Iteratively encodes the given byte sequence as a buffer of ASCII bytes, by means of the "percent-escaping" transformation.
    /// A callback is invoked periodically to process the results.
    ///
    /// - Bytes which are not valid ASCII characters are always transformed as the sequence "%ZZ",
    ///   where ZZ is the byte's numerical value as a hexadecimal string.
    /// - Bytes which are valid ASCII characters are also transformed if the predicate returns `true`.
    ///
    /// -  important: 	This algorithm does not round-trip for arbitrary byte sequences unless `escapeSet` includes
    /// 				the `ASCII.percentSign` character itself. If not, sequences which happen to contain a valid escape string already
    ///                 will be not be escaped, and the reciever, expecting an additional level of escaping, will over-unescape the resulting String.
    ///
    /// - parameters:
    ///     - bytes:        The sequence of bytes to encode.
    ///     - escapeSet:    The predicate which decides if a particular ASCII character should be escaped or not.
    ///     - processChunk: A callback which processes a chunk of escaped data. Each chunk is guaranteed to be a valid ASCII String, containing
    ///                     only the % character, upper-case ASCII hex digits, and characters allowed by the escape set.
    ///
    static func encodeIterativelyAsBuffer<S>(
        bytes: S, escapeSet: EscapeSet,
        processChunk: (UnsafeBufferPointer<UInt8>)->Void
    ) where S: Sequence, S.Element == UInt8 {
        withSmallStringSizedStackBuffer { buffer in
            var i = 0
            for byte in bytes {
                // If the buffer can't hold an escaped byte, flush it.
                if i &+ 3 > buffer.count {
                    processChunk(UnsafeBufferPointer(rebasing: buffer[..<i]))
                    i = 0
                }
                if let asciiChar = ASCII(byte), escapeSet.shouldEscape(asciiChar) == false {
                    buffer[i] = byte
                    i &+= 1
                } else {
                    _escape(byte: byte, into: UnsafeMutableBufferPointer(rebasing: buffer[i...]))
                    i &+= 3
                }
            }
            // Flush the buffer.
            processChunk(UnsafeBufferPointer(rebasing: buffer[..<i]))
        }
    }
    
    /// See `encodeIterativelyAsBuffer<C>(bytes: escapeSet: processChunk:)`
    ///
    static func encodeIterativelyAsString<S>(
        bytes: S, escapeSet: EscapeSet,
        processChunk: (String)->Void
    ) where S: Sequence, S.Element == UInt8 {
        encodeIterativelyAsBuffer(bytes: bytes, escapeSet: escapeSet, processChunk: { buffer in
            processChunk(String(decoding: buffer, as: UTF8.self))
        })
    }
    
    /// Encodes a single UTF8-encode codepoint as a buffer of ASCII bytes, by means of the "percent-escaping" transformation.
    /// A callback is invoked once to process the result.
    ///
    /// - Code-points which are not ASCII characters are always transformed as the sequence "%ZZ%ZZ%ZZ...",
    ///   where ZZ are the UTF8 bytes' numerical values as a hexadecimal string.
    /// - Bytes which are valid ASCII characters are also transformed if the predicate returns `true`.
    ///
    /// -  important:    This algorithm does not encode the `ASCII.percentSign` character itself,
    ///                  unless it is explicitly told to do so by the escape set.
    /// - precondition: `singleUTF8CodePoint` may not be empty, nor may it contain more than 4 bytes.
    ///
    /// - parameters:
    ///     - singleUTF8CodePoint:  The single UTF8-encoded codepoint to transform. May not be larger than 4 bytes.
    ///     - escapeSet:            The predicate which decides if a particular ASCII character should be escaped or not.
    ///     - processResult:        A callback which processes the escaped data. It will only be invoked once.
    ///                             The buffer is guaranteed to be a valid ASCII String, containing only the % character,
    ///                             upper-case ASCII hex digits, and characters allowed by the escape set.
    ///
    static func encodeAsBuffer<C>(
        singleUTF8CodePoint: C, escapeSet: EscapeSet,
        processResult: (UnsafeBufferPointer<UInt8>)->Void
    ) where C: Collection, C.Element == UInt8 {
        precondition((1...4) ~= singleUTF8CodePoint.count, "Cannot encode more or less than a single codepoint")
        var result: (UInt16, UInt64) = (0, 0) // 4 UTF8 bytes * 3 ASCII chars/byte = 12 bytes.
        withUnsafeMutableBytes(of: &result) { rawbuffer in
            let buffer = rawbuffer.bindMemory(to: UInt8.self)
            var i = 0
            for byte in singleUTF8CodePoint {
                if let asciiChar = ASCII(byte), escapeSet.shouldEscape(asciiChar) == false {
                    buffer[0] = byte
                    processResult(UnsafeBufferPointer(rebasing: buffer[0..<1]))
                    return // An ASCII byte means the code-point is over.
                }
                _escape(byte: byte, into: UnsafeMutableBufferPointer(rebasing: buffer[i...]))
                i &+= 3
            }
            processResult(UnsafeBufferPointer(rebasing: buffer[..<i]))
        }
    }
    
    /// See `encodeAsBuffer<C>(singleUTF8CodePoint: escapeSet: processChunk:)`
    ///
    static func encodeAsString<C>(
        singleUTF8CodePoint: C, escapeSet: EscapeSet,
        processResult: (String)->Void
    ) where C: Collection, C.Element == UInt8 {
        encodeAsBuffer(singleUTF8CodePoint: singleUTF8CodePoint, escapeSet: escapeSet, processResult: { buffer in
            processResult(String(decoding: buffer, as: UTF8.self))
        })
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
            return String(_unsafeUninitializedCapacity: decodedByteCount) { buffer in
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
                return String(_unsafeUninitializedCapacity: decodedByteCount) { buffer in
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
//    @_specialize(where Self == String)
//    @_specialize(where Self == Substring)
//    func percentEscaped(where shouldEscapeASCII: (ASCII)->Bool) -> String {
//        return self._withUTF8 { PercentEscaping.encode(bytes: $0, where: shouldEscapeASCII) }
//    }

    /// Decodes the given percent-escaped `String` and interprets the result as a UTF8 `String`.    
    ///
    /// The decoder replaces patterns of the form "%ZZ" with the byte 0xZZ, where Z is an ASCII hexadecimal digit.
    /// If the decoded byte sequence represents an invalid UTF8 `String`, it will be repaired by replacing
    /// the appropriate parts with the unicode replacement character (U+FFFD).
    ///
    /// - returns:  A `String` containing the unescaped contents of the given `String`, interpreted as UTF8. 
    ///
//    @_specialize(where Self == String)
//    @_specialize(where Self == Substring)
//    func removingPercentEscaping() -> String {
//        return PercentEscaping.decodeString(self)
//    }
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
//    func percentEscaped(where shouldEscapeASCII: (ASCII)->Bool) -> String {
//        return PercentEscaping.encode(bytes: self.utf8, where: shouldEscapeASCII)
//    }
}

// - URL Percent-escaping predicates.

extension PercentEscaping.EscapeSet {
    
    static var url_c0: Self {
        return Self { ascii in
            ascii.codePoint > 0x7E || ASCII.ranges.controlCharacters.contains(ascii)
        }
    }
    
    static var url_fragment: Self {
        return Self { ascii in
            guard !url_c0.shouldEscape(ascii) else { return true }
            switch ascii {
            case .space, .doubleQuotationMark, .lessThanSign, .greaterThanSign, .backtick:
                return true
            default:
                return false
            }
        }
    }
    
    static var url_path: Self {
        return Self { ascii in
            guard !url_fragment.shouldEscape(ascii) else { return true }
            switch ascii {
            case .numberSign, .questionMark, .leftCurlyBracket, .rightCurlyBracket:
                return true
            default:
                return false
            }
        }
    }
    
    static var url_userInfo: Self {
        return Self { ascii in
            guard !url_path.shouldEscape(ascii) else { return true }
            switch ascii {
            case .forwardSlash, .colon, .semicolon, .equalSign, .commercialAt,
                 .leftSquareBracket, .rightSquareBracket, .backslash, .circumflexAccent,
                 .verticalBar:
                return true
            default:
                return false
            }
        }
    }
}
