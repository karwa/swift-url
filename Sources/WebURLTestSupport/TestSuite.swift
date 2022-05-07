// Copyright The swift-url Contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// A description of a test suite.
///
/// This groups a series of related types, which can be used to simplify some boilerplate code.
///
public protocol TestSuite {

  /// A testcase. A set of input data and expected results.
  ///
  associatedtype TestCase: Hashable

  /// The set of possible failures that may occur when testing a particular `TestCase`.
  ///
  associatedtype TestFailure: Hashable

  /// Additional information captured while testing a particular `TestCase`.
  ///
  associatedtype CapturedData: Hashable = Never

  // Note:
  // Ideally, we'd have the harness here as an "associated protocol", and then we could build
  // some more functionality, such as adding a `runTest<H: Harness>(TestCase, using: H)` requirement.
  //
  // I've tried a bunch of stuff, like open classes, but anything I add in protocol extensions on 'TestSuite'
  // won't get dynamic dispatch. We're really quite limited in what we can express, so this can't be much more
  // than a bag-o-types.
}

/// The result of testing a particular `TestCase` from the given `Suite`.
///
/// This includes the case that was tested, any failures that occurred, and any additional captured data.
///
public struct TestResult<Suite: TestSuite> {

  /// The number of cases that have been tested prior to this one.
  ///
  public var testNumber: Int

  /// The `TestCase` that was tested.
  ///
  public var testCase: Suite.TestCase

  /// The failures that were encountered while testing `testCase`. If empty, the test did not encounter any unexpected results.
  ///
  public var failures: Set<Suite.TestFailure>

  /// Any additional captured data gathered while running the test.
  ///
  public var captures: Suite.CapturedData?

  public init(testNumber: Int, testCase: Suite.TestCase) {
    self.testNumber = testNumber
    self.testCase = testCase
    self.captures = nil
    self.failures = []
  }
}

extension TestResult: Equatable, Hashable {}

/// An object which is able to run test-cases from a `TestSuite` and collect the results.
///
/// Each `TestSuite` adds its own protocol which refines this one, adding requirements for the functionality it needs,
/// and implements the `_runTestCase` method using those requirements. Conformers should implement those additional requirements,
/// as well as `reportTestResult` and (optionally) `markSection`, but **not** `_runTestCase`.
///
public protocol TestHarnessProtocol {

  associatedtype Suite: TestSuite

  /// Private method which is implemented by protocols which refine `TestHarnessProtocol`.
  /// Unless you are defining a new `TestSuite`, **DO NOT IMPLEMENT THIS**.
  ///
  func _runTestCase(_ testcase: Suite.TestCase, _ result: inout TestResult<Suite>)

  /// Report the result of running a test from the suite.
  ///
  mutating func reportTestResult(_ result: TestResult<Suite>)

  /// Optional method which marks the start of a new section of tests.
  /// All results reported after this method is called are considered as belonging to tests in this section.
  ///
  mutating func markSection(_ name: String)
}

extension TestHarnessProtocol {

  public mutating func markSection(_ name: String) {
    // Optional.
  }

  public mutating func runTests(_ tests: [Suite.TestCase]) {
    var index = 0
    for testcase in tests {
      var result = TestResult<Suite>(testNumber: index, testCase: testcase)
      _runTestCase(testcase, &result)
      reportTestResult(result)
      index += 1
    }
  }

  public mutating func runTests(_ tests: FlatSectionedArray<Suite.TestCase>) {
    var index = 0
    for sectionOrTestcase in tests {
      switch sectionOrTestcase {
      case .sectionHeader(let name):
        markSection(name)
      case .element(let testcase):
        var result = TestResult<Suite>(testNumber: index, testCase: testcase)
        _runTestCase(testcase, &result)
        reportTestResult(result)
        index += 1
      }
    }
  }
}
