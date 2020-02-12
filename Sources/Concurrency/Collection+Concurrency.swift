import Dispatch

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
    
    fileprivate func _forEachIndex(_ invoke: (Base.Index)->Void) {
        DispatchQueue.concurrentPerform(iterations: base.count) { i in
            let idx = base.index(base.startIndex, offsetBy: i)
            invoke(idx)
        }
    }
}

extension ConcurrentCollectionOps {
    
    public func map<T>(_ transform: (Base.Element)->T) -> [T] {
        return Array(unsafeUninitializedCapacity: base.count) { buffer, actualCount in
            DispatchQueue.concurrentPerform(iterations: base.count) { i in
                let idx = base.index(base.startIndex, offsetBy: i)
                let val = transform(base[idx])
                (buffer.baseAddress.unsafelyUnwrapped + i).initialize(to: val)
            }
            actualCount = base.count
        }
    }
    
    public func forEach(_ invoke: (Base.Element)->Void) {
        _forEachIndex { invoke(base[$0]) }
    }
}
