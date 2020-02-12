import XCTest
import TestUtilities

class CollectionSemanticsTests: XCTestCase {}

extension CollectionSemanticsTests {
    
    func testStdlib_empty() {
        CollectionSemanticsTester.test([Int]())
        CollectionSemanticsTester.test(EmptyCollection<String>())
        CollectionSemanticsTester.test(0 ..< 0)
        CollectionSemanticsTester.test(Int.max ..< Int.max)
        CollectionSemanticsTester.test(Int.min ..< Int.min)
    }
    
    func testStdlib_single() {
        CollectionSemanticsTester.test([42])
        CollectionSemanticsTester.test(CollectionOfOne(3.141))
        CollectionSemanticsTester.test(0 ..< 1)
        CollectionSemanticsTester.test(-1 ..< 0)
        CollectionSemanticsTester.test(Int.max - 1 ..< Int.max)
        CollectionSemanticsTester.test(Int.min ..< Int.min + 1)
    }

    func testStdlib() {
        CollectionSemanticsTester.test([1, 3])
        CollectionSemanticsTester.test("Hello everybody! 👋👨‍⚕️")
        CollectionSemanticsTester.test(0..<13)
        let dictionary = ["Hi,": 3, "Dr.": 42, "Nick": -99, "!": Int.max]
        CollectionSemanticsTester.test(dictionary)
        CollectionSemanticsTester.test(dictionary.keys)
        CollectionSemanticsTester.test(dictionary.keys.joined() as FlattenSequence)
        CollectionSemanticsTester.test(dictionary.values)
        CollectionSemanticsTester.test(Set(dictionary.keys.joined()))
    }
}
