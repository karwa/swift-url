
// - General (non URL-related) String utilities.

extension String {
    init(
        _unsafeUninitializedCapacity capacity: Int,
        initializingUTF8With initializer: (_ buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int) rethrows {
        #if swift(>=5.3)
        if #available(macOS 11.0, iOS 14.0, *) {
            self = try String(unsafeUninitializedCapacity: capacity, initializingUTF8With: initializer)
        } else {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }
            let count = try initializer(buffer)
            self = String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
        }
        #else
        if capacity <= 32 {
            let newStr = try with32ByteStackBuffer { buffer -> String in
                let count = try initializer(buffer)
                return String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
            }
            self = newStr
            return
        } else {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }
            let count = try initializer(buffer)
            self = String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
        }
        #endif
    }
}

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

extension Collection where Element == UInt8 {
    
    /// If the byte at `index` is a UTF8-encoded codepoint's header byte, returns
    /// the `SubSequence` of the entire codepoint. Returns `nil` otherwise
    /// (i.e. the byte at `index` is a continuation byte or not a valid UTF8 header byte).
    ///
    internal func utf8EncodedCodePoint(startingAt index: Index) -> SubSequence? {
        let byte = self[index]
        // ASCII.
        if _fastPath(byte & 0b1000_0000 == 0b0000_0000) { return self[index..<self.index(after: index)] }
        // Valid UTF8 sequences.
        if byte & 0b1110_0000 == 0b1100_0000 { return self[index..<self.index(index, offsetBy: 2)] }
        if byte & 0b1111_0000 == 0b1110_0000 { return self[index..<self.index(index, offsetBy: 3)] }
        if byte & 0b1111_1000 == 0b1111_0000 { return self[index..<self.index(index, offsetBy: 4)] }
        // Continuation bytes or invalid UTF8.
        return nil
    }
}

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

func with32ByteStackBuffer<T>(_ perform: (UnsafeMutableBufferPointer<UInt8>) throws -> T) rethrows -> T {
    var buffer: (Int64, Int64, Int64, Int64) = (0, 0, 0, 0)
    let capacity = 32
    return try withUnsafeMutablePointer(to: &buffer) { ptr in
        return try ptr.withMemoryRebound(to: UInt8.self, capacity: capacity) { basePtr in
            let bufPtr = UnsafeMutableBufferPointer(start: basePtr, count: capacity)
            return try perform(bufPtr)
        }
    }
}
