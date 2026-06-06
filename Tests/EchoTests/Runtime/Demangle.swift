import XCTest
import Echo

enum DemangleTests {
  static func testTypeByName() throws {
    XCTAssert(type(named: "Si")! == Int.self)
    XCTAssert(type(named: "SS")! == String.self)
    XCTAssert(type(named: "Sb")! == Bool.self)
    XCTAssertNil(type(named: "this is definitely not a mangled name"))
  }

  static func testDemangle() throws {
    let demangled = demangle("$sSiD")
    XCTAssertNotNil(demangled)
    XCTAssertTrue(demangled?.contains("Int") ?? false)

    XCTAssertNil(demangle("not a swift symbol at all"))
  }
}

extension EchoTests {
  func testDemangle() throws {
    try DemangleTests.testTypeByName()
    try DemangleTests.testDemangle()
  }
}
