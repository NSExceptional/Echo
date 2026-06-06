import XCTest
import Echo

struct ReflStruct {
  var a: Int
  var b: String
}

class ReflBase {
  var base = 0
}

class ReflDerived: ReflBase {
  var derived = "d"
}

enum ReflEnum {
  case empty
  case payload(Int)
}

enum ReflectionTests {
  static func testStructChildren() throws {
    let kids = children(of: ReflStruct(a: 7, b: "x"))
    XCTAssertEqual(kids.count, 2)
    XCTAssertEqual(kids[0].label, "a")
    XCTAssertEqual(kids[0].value as? Int, 7)
    XCTAssertEqual(kids[1].label, "b")
    XCTAssertEqual(kids[1].value as? String, "x")
    XCTAssertEqual(displayStyle(of: ReflStruct(a: 0, b: "")), .struct)
  }

  static func testClassChildrenAreDirect() throws {
    // Matches Mirror: only directly-declared properties, not inherited ones.
    let kids = children(of: ReflDerived())
    XCTAssertEqual(kids.map(\.label), ["derived"])
    XCTAssertEqual(kids.first?.value as? String, "d")
    XCTAssertEqual(displayStyle(of: ReflDerived()), .class)
  }

  static func testEnumPayloadProjection() throws {
    let payload = children(of: ReflEnum.payload(42))
    XCTAssertEqual(payload.count, 1)
    XCTAssertEqual(payload[0].label, "payload")
    XCTAssertEqual(payload[0].value as? Int, 42)
    XCTAssertEqual(displayStyle(of: ReflEnum.payload(1)), .enum)

    // A case with no payload has no children.
    XCTAssertEqual(children(of: ReflEnum.empty).count, 0)
  }

  static func testTupleChildren() throws {
    let kids = children(of: (1, "two"))
    XCTAssertEqual(kids.count, 2)
    XCTAssertEqual(kids[0].value as? Int, 1)
    XCTAssertEqual(kids[1].value as? String, "two")
    XCTAssertEqual(displayStyle(of: (1, 2)), .tuple)
  }

  static func testOpaqueValueHasNoChildren() throws {
    // A function value has no reflectable structure.
    let function: () -> Void = {}
    XCTAssertEqual(children(of: function).count, 0)
    XCTAssertEqual(displayStyle(of: function), .none)
  }
}

extension EchoTests {
  func testReflectionMirror() throws {
    try ReflectionTests.testStructChildren()
    try ReflectionTests.testClassChildrenAreDirect()
    try ReflectionTests.testEnumPayloadProjection()
    try ReflectionTests.testTupleChildren()
    try ReflectionTests.testOpaqueValueHasNoChildren()
  }
}
