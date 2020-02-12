import XCTest

/// A wrapper around XCTest's assertion functions which forwards the given file and line information.
///
public struct XCTAssertionContext {
    /// A transform which is applied to logged messages.
    /// - parameters:
    ///        - file:        The actual file from which the assertion was triggered (_not_ the wrapped file)
    ///        - line:        The actual line from which the assertion was triggered (_not_ the wrapped line)
    ///        - message:    The message content.
    ///    - returns:    A transformed message to log as output.
    ///
    public typealias MessageFormatter = (StaticString, UInt, String) -> String
    
    public var file: StaticString
    public var line: UInt
    public var messageFormatter: MessageFormatter
    
    public init(file: StaticString = #file, line: UInt = #line, messageFormatter: @escaping MessageFormatter = { $2 }) {
        self.file = file
        self.line = line
        self.messageFormatter = messageFormatter
    }
}

extension XCTAssertionContext {

    public func assert(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssert(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : Equatable {
        XCTAssertEqual(try expression1(), try expression2(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : FloatingPoint {
        XCTAssertEqual(try expression1(), try expression2(), accuracy: accuracy, self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }

    public func assertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertGreaterThan<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : Comparable {
        XCTAssertGreaterThan(try expression1(), try expression2(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertGreaterThanOrEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : Comparable {
        XCTAssertGreaterThanOrEqual(try expression1(), try expression2(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertLessThan<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : Comparable {
        XCTAssertLessThan(try expression1(), try expression2(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertLessThanOrEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : Comparable {
        XCTAssertLessThanOrEqual(try expression1(), try expression2(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertNoThrow(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func assertNotEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : Equatable {
         XCTAssertNotEqual(try expression1(), try expression2(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
     }
     
     public func assertNotEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) where T : FloatingPoint {
         XCTAssertNotEqual(try expression1(), try expression2(), accuracy: accuracy, self.messageFormatter(file, line, message()), file: self.file, line: self.line)
     }
    
    public func assertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
         XCTAssertNotNil(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
     }
    
    public func assertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line, _ errorHandler: (Error) -> Void = { _ in }) {
        XCTAssertThrowsError(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line, errorHandler)
    }
    
    public func assertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(try expression(), self.messageFormatter(file, line, message()), file: self.file, line: self.line)
    }
    
    public func fail(_ message: String = "", file: StaticString = #file, line: UInt = #line) {
        XCTFail(message, file: self.file, line: self.line)
    }
}
