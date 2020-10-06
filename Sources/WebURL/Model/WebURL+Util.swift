extension WebURL {
  
  /// A component in a URL.
  ///
  struct Component: Equatable {
    var rawValue: UInt8
    init(rawValue: UInt8) {
      self.rawValue = rawValue
    }
    static var scheme: Self { Self(rawValue: 1 << 0) }
    static var username: Self { Self(rawValue: 1 << 1) }
    static var password: Self { Self(rawValue: 1 << 2) }
    static var hostname: Self { Self(rawValue: 1 << 3) }
    static var port: Self { Self(rawValue: 1 << 4) }
    static var path: Self { Self(rawValue: 1 << 5) }
    static var query: Self { Self(rawValue: 1 << 6) }
    static var fragment: Self { Self(rawValue: 1 << 7) }
  }
}

extension WebURL {
  
  struct ComponentSet: Equatable, ExpressibleByArrayLiteral {
    private var rawValue: UInt8
    
    init(arrayLiteral elements: Component...) {
      self.rawValue = elements.reduce(into: 0) { $0 |= $1.rawValue }
    }
    mutating func insert(_ newMember: Component) {
      self.rawValue |= newMember.rawValue
    }
    func contains(_ member: Component) -> Bool {
      return (self.rawValue & member.rawValue) != 0
    }
  }
}
