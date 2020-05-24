/// Performs the given closure with a stack-buffer whose UTF8 code-unit capacity matches
/// the small-string capacity on the current platform. The goal is that creating a String
/// from this buffer won't cause a heap allocation.
///
func withSmallStringSizedStackBuffer<T>(_ perform: (UnsafeMutableBufferPointer<UInt8>) throws -> T) rethrows -> T {
    #if arch(i386) || arch(arm) || arch(wasm32)
    var buffer: (Int64, Int16) = (0,0)
    let capacity = 10
    #else
    var buffer: (Int64, Int64) = (0,0)
    let capacity = 15
    #endif
    return try withUnsafeMutablePointer(to: &buffer) { ptr in
        return try ptr.withMemoryRebound(to: UInt8.self, capacity: capacity) { basePtr in
            let bufPtr = UnsafeMutableBufferPointer(start: basePtr, count: capacity)
            return try perform(bufPtr)
        }
    }
}

func url_escape_c0(byte: UInt8) -> Bool {
    byte > 0x7E || ASCII.ranges.controlCharacters.contains(byte)
}
func url_escape_fragment(byte: UInt8) -> Bool {
    guard !url_escape_c0(byte: byte) else { return true }
    switch byte {
    case ASCII.space, ASCII.doubleQuotationMark, ASCII.lessThanSign, ASCII.greaterThanSign, ASCII.backtick:
        return true
    default:
        return false 
    }
}
func url_escape_path(byte: UInt8) -> Bool {
    guard !url_escape_fragment(byte: byte) else { return true }
    switch byte {
    case ASCII.numberSign, ASCII.questionMark, ASCII.leftCurlyBracket, ASCII.rightCurlyBracket:
        return true
    default:
        return false 
    }
}
func url_escape_userInfo(byte: UInt8) -> Bool {
    guard !url_escape_path(byte: byte) else { return true }
    switch byte {
    case ASCII.forwardSlash, ASCII.colon, ASCII.semicolon, ASCII.equalSign, ASCII.commercialAt, ASCII.leftSquareBracket, ASCII.rightSquareBracket, ASCII.backslash, ASCII.circumflexAccent, ASCII.verticalBar:
        return true
    default:
        return false 
    }
}

enum PercentEscaping {

    static func escape<S>(utf8 string: S, where shouldEscapeByte: (UInt8)->Bool) -> String where S: StringProtocol {
        var output = ""
        withSmallStringSizedStackBuffer { buffer in
            var i = 0
            for byte in string.utf8 {
                if shouldEscapeByte(byte) { 
                    _escape(byte: byte, into: UnsafeMutableBufferPointer(rebasing: buffer[i...]))
                    i &+= 3
                } else {
                    buffer[i] = byte
                    i &+= 1
                }
                if buffer.count &- i < 3 {
                    output.append(String(decoding: UnsafeBufferPointer(rebasing: buffer[..<i]), as: UTF8.self))
                    i = 0
                }
            }
            output.append(String(decoding: UnsafeBufferPointer(rebasing: buffer[..<i]), as: UTF8.self))
        }
        return output
    }

    static func escape(utf8 character: Character, where shouldEscapeByte: (UInt8)->Bool) -> String {
        escape(utf8: String(character), where: shouldEscapeByte)
    }

    /// Note: Requires that output.count >= 3.
    private static func _escape(byte: UInt8, into output: UnsafeMutableBufferPointer<UInt8>) {
        output[0] = ASCII.percentSign.codePoint
        output[1] = ASCII.getHexDigit_upper(byte >> 4).codePoint
        output[2] = ASCII.getHexDigit_upper(byte).codePoint
    }

    // static func unescape(utf8 escapedString: String) -> String? {
    //     String(utf8Capacity: escapedString.utf8.count) { cnt in

    //     }
    // }


}