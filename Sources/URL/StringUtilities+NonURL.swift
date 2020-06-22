
// - General (non URL-related) String utilities.

#if swift(<5.3)
extension String {
    init(
        unsafeUninitializedCapacity capacity: Int,
        initializingUTF8With initializer: (_ buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int) rethrows {
            let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }
            let count = try initializer(buffer) 
            self = String(decoding: UnsafeBufferPointer(rebasing: buffer.prefix(count)), as: UTF8.self)
    }
}
#endif

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
        let length = (~self[index]).leadingZeroBitCount
        switch length {
        case 0:  return index != endIndex ? self[index..<self.index(after: index)] : nil // ASCII.
        case 2:  fallthrough
        case 3:  fallthrough
        case 4:  return self.index(index, offsetBy: length, limitedBy: self.endIndex).map { self[index..<$0] }
        default: return nil // Continuation byte or invald UTF8.
        }
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
