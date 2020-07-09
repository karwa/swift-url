import Concurrency
import XCTest

class CollectionExtensionsTestCase: XCTestCase {

  private struct MyObject: Equatable {
    var square: Int
    init(_ v: Int) {
      square = v * v
    }
  }

  func testMap() {
    let values = 0..<50
    let mapped = values.concurrent.map { MyObject($0) }
    XCTAssertEqual(values.count, mapped.count)
    XCTAssertTrue(mapped.elementsEqual(values.lazy.map { MyObject($0) }))
  }
}
