
// TODO:
// - Parser:
//   - Clean up IPv6 parser
//   - Clean up tests
//   - Clean up validation messages

public enum IPAddress {}

// MARK: - IPv6

extension IPAddress {

    /// A 128-bit numerical identifier assigned to a device on an 
    /// [Internet Protocol, version 6](https://tools.ietf.org/html/rfc2460) network.
    ///
    public struct V6 {
        public typealias RawAddress = (UInt16,UInt16,UInt16,UInt16,UInt16,UInt16,UInt16,UInt16) 
        
        public var rawAddress: RawAddress

        @inlinable
        public init(rawAddress: RawAddress = (0, 0, 0, 0, 0, 0, 0, 0)) {
            self.rawAddress = rawAddress
        }
    }
}

extension IPAddress.V6 {

    @inlinable
    public init(
        _ a0: UInt16, _ a1: UInt16, _ a2: UInt16, _ a3: UInt16, 
        _ a4: UInt16, _ a5: UInt16, _ a6: UInt16, _ a7: UInt16) {
            self.init(rawAddress: (a0, a1, a2, a3, a4, a5, a6, a7))
    }
}

extension IPAddress.V6: Equatable, Hashable {
    @inlinable
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.rawAddress.0 == rhs.rawAddress.0 &&
        lhs.rawAddress.1 == rhs.rawAddress.1 &&
        lhs.rawAddress.2 == rhs.rawAddress.2 &&
        lhs.rawAddress.3 == rhs.rawAddress.3 &&
        lhs.rawAddress.4 == rhs.rawAddress.4 &&
        lhs.rawAddress.5 == rhs.rawAddress.5 &&
        lhs.rawAddress.6 == rhs.rawAddress.6 &&
        lhs.rawAddress.7 == rhs.rawAddress.7
    }

    @inlinable
    public func hash(into hasher: inout Hasher) {
        withUnsafeBytes(of: rawAddress) { hasher.combine(bytes: $0) }
    }
}

extension IPAddress.V6 {

    @frozen public enum ParseResult {
        case success(IPAddress.V6)
        case validationFailure(StaticString)
    }

    /// Parses an IPv6 address from a UTF-8 string.
    /// 
    /// TODO: Add description of accepted formats.
    ///
    /// - parameters:
    ///     - input: A buffer of ASCII/UTF-8 codepoints. The buffer does not have to be null-terminated.
    /// - returns:
    ///     A result object containing either the successfully-parsed address, or a failure message.
    ///
    public static func parse(_ input: UnsafeBufferPointer<UInt8>) -> ParseResult {
        guard input.isEmpty == false else { return .validationFailure("Empty input") }

        var result: IPAddress.V6.RawAddress = (0, 0, 0, 0, 0, 0, 0, 0)
        return withUnsafeMutableBytes(of: &result) { tuplePointer -> ParseResult in
            let addressBuffer = tuplePointer.bindMemory(to: UInt16.self)
            var pieceIndex    = 0
            var compress      = -1 // We treat -1 as "null".
            var idx           = input.startIndex

            if input[idx] == ASCII.colon {
                idx = input.index(after: idx)
                guard idx != input.endIndex, input[idx] == ASCII.colon else {
                    return .validationFailure("Unexpected lone ':' at start of address")
                }
                idx          = input.index(after: idx)
                pieceIndex &+= 1
                compress     = pieceIndex
            } 

            parseloop: while idx != input.endIndex {
                guard pieceIndex != 8 else {
                    return .validationFailure("Too many segments in address")
                }
                guard input[idx] != ASCII.colon else {
                    if compress != -1 {
                        return .validationFailure("Empty segment or more than one compressed segment")
                    } else {
                        idx          = input.index(after: idx)
                        pieceIndex &+= 1
                        compress     = pieceIndex
                        continue parseloop
                    }
                }
                let segmentStartIndex = idx //< For faster rewinding in case of an IPv4 address, since `String.Index` is slow.
                var value: UInt16 = 0
                var length: UInt8 = 0

                while length < 4, idx != input.endIndex, let asciiChar = ASCII(input[idx]) {
                    let numberValue = ASCII.parseHexDigit(ascii: asciiChar)
                    guard numberValue != ASCII.parse_NotFound else { break }
                    value  &<<= 4
                    value  &+= UInt16(numberValue)
                    length &+= 1
                    idx = input.index(after: idx)
                }
                guard idx != input.endIndex else {
                    addressBuffer[pieceIndex] = value
                    pieceIndex &+= 1
                    break parseloop
                }

                switch input[idx] {
                case ASCII.colon:
                    idx = input.index(after: idx)
                    guard idx != input.endIndex else {
                        return .validationFailure("Unexpected lone ':' at end of address")
                    }
                case ASCII.period:
                    guard length != 0 else {
                        return .validationFailure("Unexpected '.' in address segment")
                    }
                    idx = segmentStartIndex
                    guard !(pieceIndex > 6) else {
                        return .validationFailure("Invalid position for IPv4 address segment")
                    }
                    var numbersSeen = 0
                    while idx != input.endIndex {
                        var ipv4Piece = -1 // We treat -1 as "null".
                        if numbersSeen > 0 {
                            guard input[idx] == ASCII.period, numbersSeen < 4 else {
                                return .validationFailure("Invalid IPv4 address segment. Unexpected character")
                            }
                            idx = input.index(after: idx)
                        }
                        guard idx != input.endIndex, let asciiChar = ASCII(input[idx]), ASCII.ranges.digits.contains(asciiChar) else {
                            return .validationFailure("Invalid IPv4 address segment. Unexpected character")
                        }
                        while idx != input.endIndex, let asciiChar = ASCII(input[idx]), ASCII.ranges.digits.contains(asciiChar) {
                            let digit = ASCII.parseDecimalDigit(ascii: asciiChar)
                            assert(digit != 99) // We already checked it was a digit.
                            switch ipv4Piece {
                            case -1: 
                                ipv4Piece = Int(digit)
                            case 0:
                                return .validationFailure("Invalid IPv4 address segment. Unexpected leading '0' in IPv4 address")
                            default: 
                                ipv4Piece *= 10
                                ipv4Piece += Int(digit)
                            }
                            guard ipv4Piece < 256 else {
                                return .validationFailure("Invalid IPv4 address segment. Sub-segment is greater than 255")
                            }
                            idx = input.index(after: idx)
                        }
                        addressBuffer[pieceIndex] &<<= 8
                        addressBuffer[pieceIndex] &+= UInt16(ipv4Piece)
                        numbersSeen &+= 1
                        if numbersSeen == 2 || numbersSeen == 4 {
                            pieceIndex &+= 1
                        } 
                    }
                    guard numbersSeen == 4 else {
                        return .validationFailure("Invalid IPv4 address segment.")
                    }
                    break parseloop
                default:
                    return .validationFailure("Unexpected character after address segment")
                }
                addressBuffer[pieceIndex] = value
                pieceIndex &+= 1
            }

            if compress != -1 {
                var swaps = pieceIndex - compress
                pieceIndex = 7
                while pieceIndex != 0, swaps > 0 {
                    let destinationPiece = compress + swaps - 1
                    // Check that locations are not the same, otherwise we'll have an exclusivity violation.
                    if pieceIndex != destinationPiece {
                        swap(&addressBuffer[pieceIndex], &addressBuffer[destinationPiece])
                    }
                    pieceIndex &-= 1
                    swaps      &-= 1
                }
            } else {
                guard pieceIndex == 8 else {
                    return .validationFailure("Not enough segments in address")
                }
            }
            // Parsing successful.
            return .success(IPAddress.V6(rawAddress: 
                UnsafeRawPointer(addressBuffer.baseAddress!).load(fromByteOffset: 0, as: IPAddress.V6.RawAddress.self)
            ))
        }
    }
}

extension IPAddress.V6 {
    
    @inlinable public static func parse(_ input: Substring) -> ParseResult {
        var copy = input
        return copy.withUTF8 { parse($0) }
    }

    @inlinable public init?(_ input: Substring) {
        guard case .success(let parsed) = Self.parse(input) else { return nil }
        self = parsed 
    }

    @inlinable public static func parse(_ input: String) -> ParseResult { return parse(input[...]) }
    @inlinable public init?(_ input: String) { self.init(input[...]) }
}

// MARK: - IPv4

extension IPAddress {

    /// A 32-bit numerical identifier assigned to a device on an 
    /// [Internet Protocol, version 4](https://tools.ietf.org/html/rfc791) network.
    ///
    public struct V4 {
        public typealias RawAddress = UInt32 
        
        public var rawAddress: RawAddress

        @inlinable
        public init(rawAddress: RawAddress = 0) {
            self.rawAddress = rawAddress
        }
    }
}

extension IPAddress.V4: Equatable, Hashable {
    // Synthesised.
}

extension IPAddress.V4 {

    @frozen public enum ParseResult {
        case success(IPAddress.V4)
        case validationFailure(StaticString)
    }

    /// Parses an IPv4 address from a UTF-8 string.
    /// 
    /// The given string may have 1, 2, 3 or 4 pieces, separated by a '.',
    /// and each piece may be specified in octal, decimal, or hexadecimal notation.
    /// A single trailing '.' is permitted.
    ///
    /// - parameters:
    ///     - input: A buffer of ASCII/UTF-8 codepoints. The buffer does not have to be null-terminated.
    /// - returns:
    ///     A result object containing either the successfully-parsed address, or a failure message.
    ///
    public static func parse(_ input: UnsafeBufferPointer<UInt8>) -> ParseResult {
        guard input.isEmpty == false else { return .validationFailure("Empty input") }

        // This algorithm isn't from the WHATWG spec, but supports all the required shorthands.
        // Translated and adapted to Swift (with some modifications) from:
        // https://android.googlesource.com/platform/bionic/+/froyo/libc/inet/inet_aton.c
        
        var __pieces: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
        return withUnsafeMutableBytes(of: &__pieces) { rawPtr -> ParseResult in
            let pieces     = rawPtr.bindMemory(to: UInt32.self)
            var pieceIndex = -1
            var idx        = input.startIndex

            while idx != input.endIndex {
                var value: UInt32 = 0
                var radix: UInt32 = 10

                guard ASCII.ranges.digits.contains(input[idx]) else { 
                    return .validationFailure("Piece begins with invalid character")
                }
                // Leading '0' or '0x' sets the radix.
                if input[idx] == ASCII.n0 {
                    idx = input.index(after: idx)
                    if idx != input.endIndex {
                        switch input[idx] {
                        case ASCII.x, ASCII.X:
                            radix = 16
                            idx   = input.index(after: idx)
                        default:
                            radix = 8
                        }
                    }
                }
                // Parse remaining digits in piece.
                while idx != input.endIndex {
                    guard let numericValue = ASCII(input[idx]).map({ ASCII.parseHexDigit(ascii: $0) }),
                        numericValue != ASCII.parse_NotFound else { break }
                    guard numericValue < radix else {
                        return .validationFailure("Piece contains invalid character for radix")
                    }
                    // TODO: Is there a cheaper way to predict overflow?
                    var (overflowM, overflowA) = (false, false)
                    (value, overflowM) = value.multipliedReportingOverflow(by: radix)
                    (value, overflowA) = value.addingReportingOverflow(UInt32(numericValue))
                    guard !overflowM, !overflowA else {
                        return .validationFailure("Address overflows")
                    }
                    idx = input.index(after: idx)
                }
                // Set value for piece.
                guard pieceIndex < 3 else {
                    return .validationFailure("Too many pieces in address") 
                }
                pieceIndex &+= 1
                pieces[pieceIndex] = value
                // Allow one trailing '.' after the piece, even if it's the last piece.
                guard idx != input.endIndex, input[idx] == ASCII.period else { 
                    break
                }
                idx = input.index(after: idx)
            }

            guard idx == input.endIndex else {
                return .validationFailure("Unexpected character at end of address")
            }

            var rawAddress: UInt32 = 0
            switch pieceIndex {
            case 0: // 'a'       - 32-bits.
                rawAddress = pieces[0]
            case 1: // 'a.b'     - 8-bits/24-bits.
                var invalidBits = pieces[0] & ~0x000000FF
                invalidBits    |= pieces[1] & ~0x00FFFFFF
                guard invalidBits == 0 else { return .validationFailure("Address overflows") }
                rawAddress = (pieces[0] << 24) | pieces[1]
            case 2: // 'a.b.c'   - 8-bits/8-bits/16-bits.
                var invalidBits = pieces[0] & ~0x000000FF
                invalidBits    |= pieces[1] & ~0x000000FF
                invalidBits    |= pieces[2] & ~0x0000FFFF
                guard invalidBits == 0 else { return .validationFailure("Address overflows") }
                rawAddress = (pieces[0] << 24) | (pieces[1] << 16) | pieces[2]
            case 3: // 'a.b.c.d' - 8-bits/8-bits/8-bits/8-bits.
                var invalidBits = pieces[0] & ~0x000000FF
                invalidBits    |= pieces[1] & ~0x000000FF
                invalidBits    |= pieces[2] & ~0x000000FF
                invalidBits    |= pieces[3] & ~0x000000FF
                guard invalidBits == 0 else { return .validationFailure("Address overflows") }
                rawAddress = (pieces[0] << 24) | (pieces[1] << 16) | (pieces[2] << 8) | pieces[3]
            default:
                fatalError("Internal error. pieceIndex has unexpected value.")
            }
            // Parsing successful.
            rawAddress = rawAddress.bigEndian
            return .success(IPAddress.V4(rawAddress: rawAddress))
        }
    }
}

extension IPAddress.V4 {

    @inlinable public static func parse(_ input: Substring) -> ParseResult {
        var copy = input
        return copy.withUTF8 { parse($0) }
    }

    @inlinable public init?(_ input: Substring) {
        guard case .success(let parsed) = Self.parse(input) else { return nil }
        self = parsed 
    }

    @inlinable public static func parse(_ input: String) -> ParseResult { return parse(input[...]) }
    @inlinable public init?(_ input: String) { self.init(input[...]) }
}