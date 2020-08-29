
import Foundation
import XCTest
@testable import WebURL

class URL2Tests: XCTestCase {
  
  func testStorage() {
    var a = NewURLParser()
//    var str = """
//
//
//
//    ht
//    Tp+unix+asdawe://www.google.com
//    """
//    var str = #"https://///\\\\/user:name:password@thisIsNotTheHost@www.google.com/p1/p2#fragout!"#
//    var str = #"https:////\\user:name:password@thisIsNotTheHost@www.google.com:8080/path1/path2/../😸\path3/?query!=foo&🙌=55#fraggymentalis"#
    var str = #"https://user:name:password@thisIsNotTheHost@www.google.com?hello"#
    
//    var str = #"file://usr/lib/Swift?something"#
    
//    var str = #"javascript:alert("hello, world! 😻");"#
//
    let storage = str.withUTF8 { a.constructURL(input: $0, baseURL: nil) }
    
//    var str = #"some/relative/path"#
//    var base = NewURL()
//
//    let storage = str.withUTF8 { a.constructURL(input: $0, baseURL: base) }
    
    print(storage?.storage.count)
    print(storage?.storage.asUTF8String())
    
    let newurl = storage!
    
    print(newurl.description)
    
//    print(storage.withElements(range: 0..<storage.count) { Array($0) })
//    print(storage.withElements(range: 0..<storage.count) { String(decoding: $0, as: UTF8.self) })
  }
}
