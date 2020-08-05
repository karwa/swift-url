
import Foundation
import XCTest
@testable import WebURL

class URL2Tests: XCTestCase {
  
  func testStorage() {
    var a = NewURLParser()
//    var str = """
//
//    ht
//    tp+unix++++99898saasa://www.google.com
//    """
    var str = "https://www.google.com"
    let storage = str.withUTF8 { a.constructURL(input: $0, baseURL: nil) }
    
    print(storage?.storage.count)
//    print(storage.withElements(range: 0..<storage.count) { Array($0) })
//    print(storage.withElements(range: 0..<storage.count) { String(decoding: $0, as: UTF8.self) })
  }
}
