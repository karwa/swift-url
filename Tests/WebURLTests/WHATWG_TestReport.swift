import XCTest

// A helper for generating better test reports for the WHATWG tests.
// XCTest just doesn't handle it well:
// - No support for "sub-tests".
//   I'd rather see that 15 sub-tests failed than that 126 individual assertions across all sub-tests failed.
// - The reports are only decent in Xcode.
// - No ability to XFAIL tests and check that they really *do* fail.
// - etc...
struct WHATWG_TestReport {
  var expectedFailures: Set<Int> = []

  private var testFailures = [Int: [(String, Any)]]()
  private var sections = [(Int, String)]()
  private var num_xPass_pass = 0
  private var num_xPass_fail = 0
  private var num_xFail_pass = 0
  private var num_xFail_fail = 0
  // Current test.
  private var currentTestIdx = 0
  private var currentTestDidFail = false
  private var currentTestCapturedData = [(String, Any)]()
  private var currentTestFailedKeys = [String]()

  mutating func recordSection(_ name: String) {
    sections.append((currentTestIdx, name))
    currentTestIdx += 1
  }

  mutating func recordTest(_ test: (inout WHATWG_TestReport) throws -> Void) rethrows {
    currentTestDidFail = false
    currentTestCapturedData.removeAll(keepingCapacity: true)
    currentTestFailedKeys.removeAll(keepingCapacity: true)
    defer {
      if expectedFailures.contains(currentTestIdx) {
        if !currentTestDidFail {
          num_xFail_pass += 1
          XCTFail("Unexpected pass for test \(currentTestIdx). Data: \(currentTestCapturedData)")
          currentTestCapturedData.insert(("TESTREPORT_REASON", "✅❌❔ UNEXPECTED PASS"), at: 0)
          testFailures[currentTestIdx] = currentTestCapturedData
        } else {
          num_xFail_fail += 1
        }
      } else {
        if currentTestDidFail {
          num_xPass_fail += 1
          XCTFail("Unexpected fail for test \(currentTestIdx). Data: \(currentTestCapturedData)")
          currentTestCapturedData.insert(("FAILURE KEYS", currentTestFailedKeys), at: 0)
          testFailures[currentTestIdx] = currentTestCapturedData
        } else {
          num_xPass_pass += 1
        }
      }
      currentTestDidFail = false
      currentTestCapturedData.removeAll(keepingCapacity: true)
      currentTestFailedKeys.removeAll(keepingCapacity: true)
      currentTestIdx += 1
    }

    do {
      try test(&self)
    } catch {
      currentTestDidFail = true
      throw error
    }
  }

  mutating func capture(key: String, _ object: Any) {
    currentTestCapturedData.append((key, object))
  }
  
  mutating func advanceTestIndex() {
    currentTestIdx += 1
  }

  mutating func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ key: String? = nil) {
    if lhs != rhs {
      currentTestDidFail = true
      key.map { currentTestFailedKeys.append($0) }
    }
  }

  mutating func expectTrue(_ lhs: Bool, _ key: String? = nil) {
    if lhs == false {
      currentTestDidFail = true
      key.map { currentTestFailedKeys.append($0) }
    }
  }

  mutating func expectFalse(_ lhs: Bool, _ key: String? = nil) {
    if lhs == true {
      currentTestDidFail = true
      key.map { currentTestFailedKeys.append($0) }
    }
  }

  func generateReport() -> String {
    var output = ""
    print(
      """
      ------------------------------
      ------------------------------
            \(testFailures.count) Tests Failed
      ------------------------------
      Pass: \(num_xPass_pass + num_xFail_pass) (\(num_xPass_pass) expected)
      Fail: \(num_xPass_fail + num_xFail_fail) (\(num_xFail_fail) expected)
      Total: \(num_xPass_pass + num_xPass_fail + num_xFail_pass + num_xFail_fail) tests run
      ------------------------------
      """, to: &output)
    var sectionIterator = sections.makeIterator()
    var nextSection = sectionIterator.next()
    for index in testFailures.keys.sorted() {

      func printDivider() {
        if let section = nextSection {
          if index > section.0 {
            nextSection = sectionIterator.next()
            if index > nextSection?.0 ?? -1 {
              printDivider()
              return
            }

            print("", to: &output)
            print("============== \(section.1) ===========", to: &output)
            print("", to: &output)
            return
          }
        }
        print("------------------------------", to: &output)
        print("", to: &output)
      }
      printDivider()

      guard let capturedData = testFailures[index] else { fatalError("Something went wrong...") }
      print("[\(index)]:", to: &output)
      print("", to: &output)
      for (key, value) in capturedData {
        print(
          """
          \t\(key):
          \t--------------
          \t\(value)
          """, to: &output)
        print("", to: &output)
      }

    }
    return output
  }
}
