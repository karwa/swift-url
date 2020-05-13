import Dispatch

// TODO:
// - Concurrent sort (+ filter?)
// - Collection sampling (pick n random elements without replacement)
// - 

extension RandomAccessCollection {

    /// Returns a view of this collection with concurrent implementations of certain algorithms.
    ///
    public var concurrent: ConcurrentCollectionOps<Self> {
        return ConcurrentCollectionOps(wrapping: self)
    }
}

public struct ConcurrentCollectionOps<Base> where Base: RandomAccessCollection {
    var base: Base

    init(wrapping base: Base) {
        self.base = base
    }
}

extension ConcurrentCollectionOps {

    fileprivate func _forEachOffset(_ invoke: (Int)->Void) {
        DispatchQueue.concurrentPerform(iterations: base.count) { i in invoke(i) }
    }

    fileprivate func _forEachIndex(_ invoke: (Base.Index)->Void) {
        _forEachOffset { i in
            invoke(base.index(base.startIndex, offsetBy: i))
        }
    }
}

// foreach, map.

extension ConcurrentCollectionOps {

    public func forEach(_ invoke: (Base.Element)->Void) {
        _forEachIndex { invoke(base[$0]) }
    }

    public func map<T>(_ transform: (Base.Element)->T) -> [T] {
        let count = base.count
        return Array(unsafeUninitializedCapacity: count) { buffer, actualCount in
            _forEachOffset { i in
                let idx = base.index(base.startIndex, offsetBy: i)
                let val = transform(base[idx])
                (buffer.baseAddress.unsafelyUnwrapped + i).initialize(to: val)
            }
            actualCount = count
        }
    }
}