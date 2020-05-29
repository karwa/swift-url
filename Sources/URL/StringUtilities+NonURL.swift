
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