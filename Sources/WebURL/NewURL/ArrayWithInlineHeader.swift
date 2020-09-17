protocol InlineArrayHeader {
  var count: Int { get set }
}

struct ArrayWithInlineHeader<Header: InlineArrayHeader, Element> {
  fileprivate var buffer: ManagedBuffer<Header, Element>
  
  init(capacity: Int, initialHeader: Header) {
    buffer = .create(minimumCapacity: capacity, makingHeaderWith: { _ in return initialHeader })
  }
  
  var header: Header {
    get {
      return buffer.header
    }
    _modify {
      ensureUniquelyReferenced()
      yield &buffer.header
    }
  }
  
  var count: Int {
    return buffer.header.count
  }
  
  /// Copies the entirety of `buffer` in to new storage with the given minimum capacity.
  ///
  private func copyToNewBuffer(capacity: Int) -> ManagedBuffer<Header, Element> {
    let currentCount = self.count
    precondition(capacity >= currentCount, "Copying to buffer with insufficient space")
    let newBuffer = ManagedBuffer<Header, Element>.create(
      minimumCapacity: capacity,
      makingHeaderWith: { _ in return buffer.header }
    )
    buffer.withUnsafeMutablePointerToElements { oldElements in
      newBuffer.withUnsafeMutablePointerToElements { newElements in
        newElements.initialize(from: oldElements, count: currentCount)
      }
    }
    return newBuffer
  }
  
  /// Ensures that we hold a unique reference to the buffer, otherwise replaces `buffer` with a new, unique copy.
  ///
  /// - parameters:
  ///   - desiredCapacity:  If `buffer` is copied, the copy will be created with the given minimum capacity.
  ///                       If unspecified or less than `count`, the copy will be created with at least enough capacity
  ///                       to store `count` elements.
  ///
  fileprivate mutating func ensureUniquelyReferenced(desiredCapacity: Int? = nil) {
    if !isKnownUniquelyReferenced(&buffer) {
      let currentCount = self.count
      buffer = copyToNewBuffer(capacity: max(desiredCapacity ?? currentCount, currentCount))
      assert(self.count == currentCount)
    }
  }
  
  /// Ensures that `buffer`, which is known to be unique, has at least enough capacity for the specified number of elements.
  /// If `buffer` is too small, its contents will be copied in to new storage with the given minimum capacity.
  ///
  fileprivate mutating func knownUnique_ensureCapacity(_ desiredCapacity: Int) {
    if desiredCapacity > buffer.capacity {
      let currentCount = self.count
      buffer = copyToNewBuffer(capacity: desiredCapacity)
      assert(self.count == currentCount)
    }
  }
  
  fileprivate func knownUnique_setCount(_ newCount: Int) {
    buffer.header.count = newCount
  }
}

// We have a basic Collection-like interface. Not an actual conformance for now.

extension ArrayWithInlineHeader {
  
  typealias Index = Int
  
  var startIndex: Index {
    return 0
  }
  
  var endIndex: Index {
    return count
  }
  
  subscript(index: Index) -> Element {
    get {
      precondition(index >= startIndex && index < endIndex, "Invalid index")
      return buffer.withUnsafeMutablePointerToElements { ($0 + index).pointee }
    }
    _modify {
      precondition(index >= startIndex && index < endIndex, "Invalid index")
      ensureUniquelyReferenced()
      var tmp = buffer.withUnsafeMutablePointerToElements { ($0 + index).move() }
      defer { buffer.withUnsafeMutablePointerToElements { ($0 + index).initialize(to: tmp) } }
      yield &tmp
    }
  }
}


extension ArrayWithInlineHeader {
  
  mutating func append(uninitializedCapacity: Int, initializingWith initializer: (UnsafeMutableBufferPointer<Element>)->Int) {
    let newMinimumCapacity = buffer.header.count + uninitializedCapacity
    ensureUniquelyReferenced(desiredCapacity: newMinimumCapacity)
    knownUnique_ensureCapacity(newMinimumCapacity)
    
    let preAppendCount = self.count
    let numAdded = buffer.withUnsafeMutablePointerToElements { elements -> Int in
      let uninitializedBuffer = UnsafeMutableBufferPointer(start: elements + preAppendCount, count: newMinimumCapacity - preAppendCount)
      return initializer(uninitializedBuffer)
    }
    assert(numAdded == uninitializedCapacity)
    knownUnique_setCount(preAppendCount + numAdded)
  }
  
  mutating func append<C>(contentsOf other: C) where C: Collection, C.Element == Element {
    append(uninitializedCapacity: other.count) {
      $0.initialize(from: other).1
    }
  }
  
  mutating func append(_ element: Element) {
    append(contentsOf: CollectionOfOne(element))
  }
  
  mutating func append(repeated element: Element, count: Int) {
    append(contentsOf: repeatElement(element, count: count))
  }
  
  func withElements<T>(range: Range<Index>, _ block: (UnsafeBufferPointer<Element>) throws -> T) rethrows -> T {
    precondition(range.startIndex >= startIndex, "Invalid startIndex")
    precondition(range.endIndex <= endIndex, "Invalid endIndex")
    return try buffer.withUnsafeMutablePointerToElements { elements in
      let slice = UnsafeBufferPointer(start: elements + range.startIndex, count: range.count)
      return try block(slice)
    }
  }
}

extension ArrayWithInlineHeader where Element == UInt8 {
  
  func asUTF8String() -> String {
    return withElements(range: startIndex..<endIndex) {
      return String(decoding: $0, as: UTF8.self)
    }
  }
}
