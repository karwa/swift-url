
import Foundation
import XCTest
@testable import WebURL

class URL2Tests: XCTestCase {
  
  func testStorage() {
    
//    var str = """
//
//
//
//    ht
//    Tp+unix+asdawe://www.google.com
//    """
//    var str = #"https://///\\\\/user:name:password@thisIsNotTheHost@www.google.com/p1/p2#fragout!"#
//    var str = #"https:////\\user:name:password@thisIsNotTheHost@www.google.com:8080/path1/path2/../😸\path3/?query!=foo&🙌=55#fraggymentalis"#
//    var str = #"file://usr/lib/Swift?something"#
//    var str = #"javascript:alert("hello, world! 😻");"#
//    var str = #"some/relative/path"#
    
//    let str = #"http://example.com/a1/b2/../b3/../../a0/c2/../c1"#   // "http://example.com/a0/c1"
    let str = #"http://example.com/foo/bar/.."#                      // "http://example.com/foo/"
//    let str = #"http://example.com/foo/../../.."#                    // "http://example.com/"
//    let str = #"http://example.com////../.."#                        // "http://example.com//"
    

    
    let base: String? = nil
//    let base = "file://host.com/some/base/path"

    let url = NewURL(str, base: base)
//
//    let storage = str.withUTF8 { a.constructURL(input: $0, baseURL: base) }
    
    print(url?.storage.count)
    print(url?.storage.asUTF8String())
    
    print(url?.description ?? "<NIL>")
    
//    print(storage.withElements(range: 0..<storage.count) { Array($0) })
//    print(storage.withElements(range: 0..<storage.count) { String(decoding: $0, as: UTF8.self) })
  }
}
