import Algorithms // for Collection.longestSubrange.

// TODO:
// - Parser:
//   - Check use of masking shifts
//   - Clean up validation messages
//   - More tests
//   - Test on s390x (big-endian system)

public enum IPAddress {}

// MARK: - IPv6

extension IPAddress {

    /// A 128-bit numerical identifier assigned to a device on an 
    /// [Internet Protocol, version 6](https://tools.ietf.org/html/rfc2460) network.
    ///
    public struct V6 {
        public typealias AddressType = (UInt16,UInt16,UInt16,UInt16,UInt16,UInt16,UInt16,UInt16) 
        
        // Host byte order.

        /// The raw address (i.e. in host byte order).
        ///
        public var rawAddress: AddressType

        /// Creates a value with the given raw address.
        ///
        /// - parameters:
        ///     - rawAddress:   The address value in host byte order.
        ///
        @inlinable
        public init(rawAddress: AddressType = (0, 0, 0, 0, 0, 0, 0, 0)) {
            self.rawAddress = rawAddress
        }

        // Network byte order.

        /// The network address (i.e. in network byte order).
        /// 
        public var networkAddress: AddressType {
            return (
                rawAddress.0.bigEndian, rawAddress.1.bigEndian,
                rawAddress.2.bigEndian, rawAddress.3.bigEndian,
                rawAddress.4.bigEndian, rawAddress.5.bigEndian,
                rawAddress.6.bigEndian, rawAddress.7.bigEndian
            )
        }

        /// Creates a value with the given network address.
        ///
        /// - parameters:
        ///     - networkAddress:   The address value in network byte order.
        ///
        @inlinable
        public init(networkAddress: AddressType) {
            self.init(rawAddress: (
                networkAddress.0.bigEndian, networkAddress.1.bigEndian,
                networkAddress.2.bigEndian, networkAddress.3.bigEndian,
                networkAddress.4.bigEndian, networkAddress.5.bigEndian,
                networkAddress.6.bigEndian, networkAddress.7.bigEndian
            ))
        }

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

    public enum ParseResult {
        case success(IPAddress.V6)
        case validationFailure(ParseResult.Error)
    
        public struct Error: Equatable, CustomStringConvertible {
            private let errorCode: UInt8
            private let context: Int
            private init(errorCode: UInt8, context: Int = -1) {
                self.errorCode = errorCode; self.context = context
            }

            // Note: These are deliberately not public, because we don't want to make the set of possible errors API.
            //       They are 'internal' for testing purposes only.  
            internal static var emptyInput: Self { Self(errorCode: 1) }
            // -
            internal static var unexpectedLeadingColon:  Self { Self(errorCode: 2) }
            internal static var unexpectedTrailingColon: Self { Self(errorCode: 3) }
            internal static var unexpectedPeriod:        Self { Self(errorCode: 4) }
            internal static var unexpectedCharacter:     Self { Self(errorCode: 5) }
            // -
            internal static var tooManyPieces:            Self { Self(errorCode: 6) }
            internal static var notEnoughPieces:          Self { Self(errorCode: 7) }
            internal static var multipleCompressedPieces: Self { Self(errorCode: 8) }
            // -
            internal static var invalidPositionForIPv4Address: Self { Self(errorCode: 9) }
            internal static func invalidIPv4Address(_ err: IPAddress.V4.ParseResult.Error) -> Self {
                Self(errorCode: 10, context: err.packedAsInt)
            }

            public var description: String {
                switch self {
                case .emptyInput:
                    return "Empty input"
                case .unexpectedLeadingColon:
                    return "Unexpected lone ':' at start of address"
                case .unexpectedTrailingColon:
                    return "Unexpected lone ':' at end of address"
                case .unexpectedPeriod:
                    return "Unexpected '.' in address segment"
                case .unexpectedCharacter:
                    return "Unexpected character after address segment"
                case .tooManyPieces:
                    return "Too many pieces in address"
                case .notEnoughPieces:
                    return "Not enough segments in address"
                case .multipleCompressedPieces:
                    return "Multiple compressed pieces in address"
                case .invalidPositionForIPv4Address:
                    return "Invalid position for IPv4 address segment"
                case _ where self.errorCode == Self.invalidIPv4Address(.emptyInput).errorCode:
                    let wrappedError = IPAddress.V4.ParseResult.Error(unpacking: context)
                    return "Invalid IPv4 address: \(wrappedError)"
                default:
                    fatalError("Unrecognised error code")
                }
            }
        }
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
        guard input.isEmpty == false else { return .validationFailure(.emptyInput) }

        var result: IPAddress.V6.AddressType = (0, 0, 0, 0, 0, 0, 0, 0)
        return withUnsafeMutableBytes(of: &result) { tuplePointer -> ParseResult in
            let addressBuffer = tuplePointer.bindMemory(to: UInt16.self)
            var pieceIndex    = 0
            var compress      = -1 // We treat -1 as "null".
            var idx           = input.startIndex

            // Handle leading compressed pieces ('::').
            if input[idx] == ASCII.colon {
                idx = input.index(after: idx)
                guard idx != input.endIndex, input[idx] == ASCII.colon else {
                    return .validationFailure(.unexpectedLeadingColon)
                }
                idx          = input.index(after: idx)
                pieceIndex &+= 1
                compress     = pieceIndex
            } 

            parseloop: 
            while idx != input.endIndex {
                guard pieceIndex != 8 else {
                    return .validationFailure(.tooManyPieces)
                }
                // If the piece starts with a ':', it must be a compressed group of pieces.
                guard input[idx] != ASCII.colon else {
                    guard compress == -1 else {
                        return .validationFailure(.multipleCompressedPieces)
                    }
                    idx          = input.index(after: idx)
                    pieceIndex &+= 1
                    compress     = pieceIndex
                    continue parseloop
                }
                // Parse the piece's numeric value.
                let pieceStartIndex = idx
                var value: UInt16   = 0
                var length: UInt8   = 0            
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
                // Parse characters after the numeric value.
                // - ':' signifies the end of the piece.
                // - '.' signifies that we should re-parse the piece as an IPv4 address.
                guard _slowPath(input[idx] != ASCII.colon) else {
                    addressBuffer[pieceIndex] = value
                    pieceIndex &+= 1
                    idx = input.index(after: idx)
                    guard idx != input.endIndex else {
                        return .validationFailure(.unexpectedTrailingColon)
                    }
                    continue parseloop
                }
                guard _slowPath(input[idx] != ASCII.period) else {
                    guard length != 0 else {
                        return .validationFailure(.unexpectedPeriod)
                    }
                    guard !(pieceIndex > 6) else {
                        return .validationFailure(.invalidPositionForIPv4Address)
                    }

                    switch IPAddress.V4.parse_simple(UnsafeBufferPointer(rebasing: input[pieceStartIndex...])) {
                    case .success(let value):
                        addressBuffer[pieceIndex]      = UInt16(truncatingIfNeeded: value.rawAddress >> 16)
                        addressBuffer[pieceIndex &+ 1] = UInt16(truncatingIfNeeded: value.rawAddress)
                    case .validationFailure(let err):
                        return .validationFailure(.invalidIPv4Address(err))
                    }
                    pieceIndex &+= 2

                    break parseloop
                }
                return .validationFailure(.unexpectedCharacter)
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
                    return .validationFailure(.notEnoughPieces)
                }
            }

            // Parsing successful.
            return .success(IPAddress.V6(rawAddress: 
                UnsafeRawPointer(addressBuffer.baseAddress.unsafelyUnwrapped)
                  .load(fromByteOffset: 0, as: IPAddress.V6.AddressType.self)
            ))
        }
    }
}

extension IPAddress.V6 {
    
    @inlinable public static func parse<S>(_ input: S) -> ParseResult where S: StringProtocol {
        return input._withUTF8 { parse($0) }
    }

    @inlinable public init?<S>(_ input: S) where S: StringProtocol {
        guard case .success(let parsed) = Self.parse(input) else { return nil }
        self = parsed 
    }
}

extension IPAddress.V6: CustomStringConvertible {

    public var description: String {
        // Maximum normalised length of an IPv6 address = 39 bytes
        // 32 (128 bits/4 bits per hex character) + 7 (separators)
        return String(unsafeUninitializedCapacity: 39) { stringBuffer in
            return withUnsafeBytes(of: rawAddress) { __rawRawAddressBuffer in
                let rawAddressBuffer = __rawRawAddressBuffer.bindMemory(to: UInt16.self)
                // Look for ranges of consecutive zeroes.
                let compressedPieces: Range<Int>
                let compressedRangeResult = rawAddressBuffer.longestSubrange(equalTo: 0)
                if compressedRangeResult.length > 1 {
                    compressedPieces = compressedRangeResult.subrange
                } else {
                    compressedPieces = -1 ..< -1
                }

                var stringBufferIdx = stringBuffer.startIndex                
                var pieceIndex = 0
                while pieceIndex < 8 {
                    // Skip compressed pieces.
                    if pieceIndex == compressedPieces.lowerBound {
                        stringBuffer[stringBufferIdx] = ASCII.colon.codePoint
                        stringBufferIdx &+= 1
                        if pieceIndex == 0 {
                            stringBuffer[stringBufferIdx] = ASCII.colon.codePoint
                            stringBufferIdx &+= 1
                        }
                        pieceIndex = compressedPieces.upperBound
                        continue
                    }
                    // Print the piece and, if not the last piece, the separator.
                    stringBufferIdx &+= ASCII.insertHexString(
                        for: rawAddressBuffer[pieceIndex],
                        into: UnsafeMutableBufferPointer(rebasing: stringBuffer[stringBufferIdx...])
                    )
                    if pieceIndex != 7 {
                        stringBuffer[stringBufferIdx] = ASCII.colon.codePoint
                        stringBufferIdx &+= 1
                    }
                    pieceIndex &+= 1
                }
                return stringBufferIdx
            }
        }
    }
}

// MARK: - IPv4

extension IPAddress {

    /// A 32-bit numerical identifier assigned to a device on an 
    /// [Internet Protocol, version 4](https://tools.ietf.org/html/rfc791) network.
    ///
    public struct V4 {

        // Host byte order.

        /// The raw address (i.e. in host byte order).
        ///
        public var rawAddress: UInt32

        /// Creates a value with the given raw address.
        ///
        /// - parameters:
        ///     - rawAddress:   The address value in host byte order.
        ///
        @inlinable
        public init(rawAddress: UInt32) {
            self.rawAddress = rawAddress
        }

        // Network byte order.

        /// The network address (i.e. in network byte order).
        /// 
        public var networkAddress: UInt32 {
            return rawAddress.bigEndian
        }

        /// Creates a value with the given network address.
        ///
        /// - parameters:
        ///     - networkAddress:   The address value in network byte order.
        ///
        @inlinable
        public init(networkAddress: UInt32) {
            self.init(rawAddress: networkAddress.bigEndian)
        }
    }
}

extension IPAddress.V4: Equatable, Hashable {
    // Synthesised.
}

extension IPAddress.V4 {

    public enum ParseResult {
        case success(IPAddress.V4)
        case validationFailure(ParseResult.Error)
    
        public struct Error: Equatable, CustomStringConvertible {
            private let errorCode: UInt8
            private init(errorCode: UInt8) {
                self.errorCode = errorCode
            }
            // Packing and unpacking for embedding in `IPv6.ParseResult.Error`.
            fileprivate var packedAsInt: Int {
                return Int(errorCode)
            }
            fileprivate init(unpacking packedValue: Int) {
                self = Self(errorCode: UInt8(packedValue))
            }

            // Note: These are deliberately not public, because we don't want to make the set of possible errors API.
            //       They are 'internal' for testing purposes only.  
            internal static var emptyInput: Self { Self(errorCode: 1) }
            // -
            internal static var pieceBeginsWithInvalidCharacter:       Self { Self(errorCode: 3) } // full only.
            internal static var pieceContainsInvalidCharacterForRadix: Self { Self(errorCode: 4) } // full only.
            internal static var unsupportedRadix:                      Self { Self(errorCode: 9) } // simple only.
            internal static var unexpectedTrailingCharacter:           Self { Self(errorCode: 5) }
            internal static var invalidCharacter:                      Self { Self(errorCode: 2) }
            // -
            internal static var pieceOverflows:   Self { Self(errorCode: 6) }
            internal static var addressOverflows: Self { Self(errorCode: 7) }
            // -
            internal static var tooManyPieces:   Self { Self(errorCode: 8) }
            internal static var notEnoughPieces: Self { Self(errorCode: 10) }
            
            public var description: String {
                switch self {
                case .emptyInput:
                    return "Empty input"
                case .invalidCharacter:
                    return "Invalid IPv4 address segment. Unexpected character"
                case .pieceBeginsWithInvalidCharacter:
                    return "Piece begins with invalid character"
                case .pieceContainsInvalidCharacterForRadix:
                    return "Piece contains invalid character for radix"
                case .pieceOverflows:
                    return "Piece overflows"
                case .addressOverflows:
                    return "Address overflows"
                case .tooManyPieces:
                    return "Too many pieces in address"
                case .unexpectedTrailingCharacter:
                    return "Unexpected character at end of address"
                case .unsupportedRadix:
                    return "Unexpected leading '0' in peice. Octal and hexadecimal pieces are not supported by the simple parser"
                case .notEnoughPieces:
                    return "Incorrect number of pieces in address"
                default:
                    fatalError("Unrecognised error code")
                }
            }
        }
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
        guard input.isEmpty == false else { return .validationFailure(.emptyInput) }

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
                    return .validationFailure(.pieceBeginsWithInvalidCharacter)
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
                        return .validationFailure(.pieceContainsInvalidCharacterForRadix)
                    }
                    // TODO: Is there a cheaper way to predict overflow?
                    var (overflowM, overflowA) = (false, false)
                    (value, overflowM) = value.multipliedReportingOverflow(by: radix)
                    (value, overflowA) = value.addingReportingOverflow(UInt32(numericValue))
                    guard !overflowM, !overflowA else {
                        return .validationFailure(.pieceOverflows)
                    }
                    idx = input.index(after: idx)
                }
                // Set value for piece.
                guard pieceIndex < 3 else {
                    return .validationFailure(.tooManyPieces) 
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
                return .validationFailure(.unexpectedTrailingCharacter)
            }

            var rawAddress: UInt32 = 0
            switch pieceIndex {
            case 0: // 'a'       - 32-bits.
                rawAddress = pieces[0]
            case 1: // 'a.b'     - 8-bits/24-bits.
                var invalidBits = pieces[0] & ~0x000000FF
                invalidBits    |= pieces[1] & ~0x00FFFFFF
                guard invalidBits == 0 else { return .validationFailure(.addressOverflows) }
                rawAddress = (pieces[0] << 24) | pieces[1]
            case 2: // 'a.b.c'   - 8-bits/8-bits/16-bits.
                var invalidBits = pieces[0] & ~0x000000FF
                invalidBits    |= pieces[1] & ~0x000000FF
                invalidBits    |= pieces[2] & ~0x0000FFFF
                guard invalidBits == 0 else { return .validationFailure(.addressOverflows) }
                rawAddress = (pieces[0] << 24) | (pieces[1] << 16) | pieces[2]
            case 3: // 'a.b.c.d' - 8-bits/8-bits/8-bits/8-bits.
                var invalidBits = pieces[0] & ~0x000000FF
                invalidBits    |= pieces[1] & ~0x000000FF
                invalidBits    |= pieces[2] & ~0x000000FF
                invalidBits    |= pieces[3] & ~0x000000FF
                guard invalidBits == 0 else { return .validationFailure(.addressOverflows) }
                rawAddress = (pieces[0] << 24) | (pieces[1] << 16) | (pieces[2] << 8) | pieces[3]
            default:
                fatalError("Internal error. pieceIndex has unexpected value.")
            }
            // Parsing successful.
            return .success(IPAddress.V4(rawAddress: rawAddress))
        }
    }

    /// Parses an IPv4 address from a UTF-8 string.
    /// 
    /// This simplified parser accepts only the 4-piece decimal notation ("a.b.c.d").
    /// Trailing '.'s are not permitted.
    ///
    /// - parameters:
    ///     - input: A buffer of ASCII/UTF-8 codepoints. The buffer does not have to be null-terminated.
    /// - returns:
    ///     A result object containing either the successfully-parsed address, or a failure message.
    ///
    public static func parse_simple(_ input: UnsafeBufferPointer<UInt8>) -> IPAddress.V4.ParseResult {

        var result      = UInt32(0)
        var idx         = input.startIndex
        var numbersSeen = 0
        while idx != input.endIndex {
            // Consume '.' separator from end of previous piece.
            if numbersSeen > 0 {
                guard input[idx] == ASCII.period else {
                    return .validationFailure(.invalidCharacter)
                }
                guard numbersSeen < 4 else {
                    return .validationFailure(.tooManyPieces)
                }
                idx = input.index(after: idx)
            }
            // Consume decimal digits from the piece.
            var ipv4Piece = -1 // We treat -1 as "null".
            while idx != input.endIndex, let asciiChar = ASCII(input[idx]), ASCII.ranges.digits.contains(asciiChar) {
                let digit = ASCII.parseDecimalDigit(ascii: asciiChar)
                assert(digit != 99) // We already checked it was a digit.
                switch ipv4Piece {
                case -1: 
                    ipv4Piece = Int(digit)
                case 0:
                    return .validationFailure(.unsupportedRadix)
                default: 
                    ipv4Piece *= 10
                    ipv4Piece += Int(digit)
                }
                guard ipv4Piece < 256 else {
                    return .validationFailure(.pieceOverflows)
                }
                idx = input.index(after: idx)
            }
            guard ipv4Piece != -1 else {
                return .validationFailure(.pieceBeginsWithInvalidCharacter)
            }
            // Accumulate in to result.
            result &<<= 8
            result &+= UInt32(ipv4Piece)
            numbersSeen &+= 1
        }
        guard numbersSeen == 4 else {
            return .validationFailure(.notEnoughPieces)
        }
        return .success(IPAddress.V4(rawAddress: result))
    }
}


extension IPAddress.V4 {

    @inlinable public static func parse<S>(_ input: S) -> ParseResult where S: StringProtocol {
        return input._withUTF8 { parse($0) }
    }

    @inlinable public init?<S>(_ input: S) where S: StringProtocol {
        guard case .success(let parsed) = Self.parse(input) else { return nil }
        self = parsed 
    }
}

extension IPAddress.V4: CustomStringConvertible {

    public var description: String {
        // 15 bytes is the maximum length of an IPv4 address in decimal notation ("XXX.XXX.XXX.XXX"),
        // but is also happily the small-string size on 64-bit platforms.
        return String(unsafeUninitializedCapacity: 15) { stringBuffer in
            return withUnsafeBytes(of: rawAddress.byteSwapped) { __rawAddressBytes -> Int in
                let addressBytes    = __rawAddressBytes.bindMemory(to: UInt8.self)
                var stringBufferIdx = stringBuffer.startIndex
                for i in 0..<4 {
                    stringBufferIdx &+= ASCII.insertDecimalString(
                        for: addressBytes[i],
                        into: UnsafeMutableBufferPointer(
                            rebasing: stringBuffer[Range(uncheckedBounds: (stringBufferIdx, stringBuffer.endIndex))]
                        )
                    )
                    if i != 3 {
                        stringBuffer[stringBufferIdx] = ASCII.period.codePoint
                        stringBufferIdx &+= 1
                    }
                }
                return stringBufferIdx
            }
        }
    }
}

// MARK: - String utilities.

extension StringProtocol {

    @inlinable 
    func _withUTF8<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        if var string = self as? String {
            return try string.withUTF8(body)
        } else {
            var substring = self as! Substring
            return try substring.withUTF8(body)
        }
    }
}

#if swift(<5.3)
extension String {
    public init(
        unsafeUninitializedCapacity capacity: Int,
        initializingUTF8With initializer: (_ buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int) rethrows {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
            let count  = try initializer(buffer) 
            self = String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
    }
}
#endif