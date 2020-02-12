import XCTest

public struct XCTAssertionContext {
    public var file: StaticString
    public var line: UInt
    
    public init(file: StaticString = #file, line: UInt = #line) {
        self.file = file
        self.line = line
    }
}

extension XCTAssertionContext {

    public func assert(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "") {
        XCTAssert(try expression(), message(), file: file, line: line)
    }
    
    public func assertEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") where T : Equatable {
        XCTAssertEqual(try expression1(), try expression2(), message(), file: file, line: line)
    }
    
    public func assertEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, accuracy: T, _ message: @autoclosure () -> String = "") where T : FloatingPoint {
        XCTAssertEqual(try expression1(), try expression2(), accuracy: accuracy, message(), file: file, line: line)
    }

    public func assertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "") {
        XCTAssertFalse(try expression(), message(), file: file, line: line)
    }
    
    public func assertGreaterThan<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") where T : Comparable {
        XCTAssertGreaterThan(try expression1(), try expression2(), message(), file: file, line: line)
    }
    
    public func assertGreaterThanOrEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") where T : Comparable {
        XCTAssertGreaterThanOrEqual(try expression1(), try expression2(), message(), file: file, line: line)
    }
    
    public func assertLessThan<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") where T : Comparable {
        XCTAssertLessThan(try expression1(), try expression2(), message(), file: file, line: line)
    }
    
    public func assertLessThanOrEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") where T : Comparable {
        XCTAssertLessThanOrEqual(try expression1(), try expression2(), message(), file: file, line: line)
    }
    
    public func assertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "") {
        XCTAssertNil(try expression(), message(), file: file, line: line)
    }
    
    public func assertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") {
        XCTAssertNoThrow(try expression(), message(), file: file, line: line)
    }
    
    public func assertNotEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "") where T : Equatable {
         XCTAssertNotEqual(try expression1(), try expression2(), message(), file: file, line: line)
     }
     
     public func assertNotEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, accuracy: T, _ message: @autoclosure () -> String = "") where T : FloatingPoint {
         XCTAssertNotEqual(try expression1(), try expression2(), accuracy: accuracy, message(), file: file, line: line)
     }
    
    public func assertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "") {
         XCTAssertNotNil(try expression(), message(), file: file, line: line)
     }
    
    public func assertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", _ errorHandler: (Error) -> Void = { _ in }) {
        XCTAssertThrowsError(try expression(), message(), file: file, line: line, errorHandler)
    }
    
    public func assertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "") {
        XCTAssertTrue(try expression(), message(), file: file, line: line)
    }
    
    public func fail(_ message: String = "") {
        XCTFail(message, file: file, line: line)
    }
}
