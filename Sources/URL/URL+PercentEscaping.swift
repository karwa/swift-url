
enum PercentEscaping {

    /// Encodes the given byte sequence as an ASCII String, by means of the "percent-escaping" transformation.   
    ///
    /// - Bytes which are valid ASCII characters are replaced by the sequence "%XX" if the predicate returns `true`,
    ///   where XX is the byte's numerical value in hexadecimal.
    /// - Bytes which are not valid ASCII characters are always escaped.
    ///
    /// - parameters:
    ///     - bytes:                The sequence of bytes to encode.
    ///     - shouldEscapeASCII:    The predicate which decides if a particular ASCII character should be escaped or not.
    ///
    /// - returns:  A percent-escaped ASCII String from which the original byte sequence may be decoded. 
    ///
    static func encode<S>(bytes: S, where shouldEscapeASCII: (ASCII)->Bool) -> String where S: Sequence, S.Element == UInt8 {
        var output = ""
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

    /// Note: Assumes that output.count >= 3.
    private static func _escape(byte: UInt8, into output: UnsafeMutableBufferPointer<UInt8>) {
        output[0] = ASCII.percentSign.codePoint
        output[1] = ASCII.getHexDigit_upper(byte >> 4).codePoint
        output[2] = ASCII.getHexDigit_upper(byte).codePoint
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
    func percentEscaped(where shouldEscapeASCII: (ASCII)->Bool) -> String {
        return PercentEscaping.encode(bytes: self.utf8, where: shouldEscapeASCII)
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