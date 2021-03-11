import XCTest

import AlgorithmsTests
import WebURLTests

var tests = [XCTestCaseEntry]()
tests += AlgorithmsTests.__allTests()
tests += WebURLTests.__allTests()

XCTMain(tests)
