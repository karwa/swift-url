import AlgorithmsTests
import WebURLTests
import XCTest

var tests = [XCTestCaseEntry]()
tests += AlgorithmsTests.__allTests()
tests += WebURLTests.__allTests()

XCTMain(tests)
