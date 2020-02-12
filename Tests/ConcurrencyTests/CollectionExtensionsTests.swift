import XCTest
import Concurrency

class MyObj: CustomStringConvertible {
    var value: Int
    var square: Int
    init(_ v: Int) {
        value = v; square = v * v
    }
    var description: String {
        return "\(value) -> \(square)"
    }
}

class CollectionExtensionsTestCase: XCTestCase {
    
    func testMap() {
        
        let a = 1...20
        let b = a.concurrent.map { MyObj($0) }
        
//        print(b)
        b.concurrent.forEach { print($0) }
    }
}
