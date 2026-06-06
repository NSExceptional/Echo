import XCTest
import Echo

enum DynamicCastTests {
  static func testCastSuccess() throws {
    let value: Any = 42
    XCTAssertEqual(dynamicCast(value, to: Int.self) as? Int, 42)
  }

  static func testCastFailure() throws {
    let value: Any = 42
    XCTAssertNil(dynamicCast(value, to: String.self))
  }

  static func testCastReferenceType() throws {
    // String is out-of-line-ish but value semantics; check a heap value too.
    let value: Any = "hello world, this is a fairly long string"
    XCTAssertEqual(dynamicCast(value, to: String.self) as? String,
                   "hello world, this is a fairly long string")
  }

  static func testClassUpcast() throws {
    let dog: Any = VCDog(name: "Rex", legs: 4, breed: "Lab")

    let asAnimal = dynamicCast(dog, to: VCAnimal.self)
    XCTAssertNotNil(asAnimal)
    XCTAssertTrue(asAnimal is VCAnimal)
    XCTAssertEqual((asAnimal as? VCAnimal)?.name, "Rex")

    // Cross-hierarchy / unrelated casts fail.
    XCTAssertNil(dynamicCast(dog, to: Int.self))
    XCTAssertNil(dynamicCast(dog, to: VCPoint.self))
  }

  static func testCastViaMetadata() throws {
    let value: Any = VCPoint(x: 1, y: 2)
    let target = reflect(VCPoint.self)
    let casted = dynamicCast(value, to: target)
    XCTAssertEqual(casted as? VCPoint, VCPoint(x: 1, y: 2))
  }
}

extension EchoTests {
  func testDynamicCast() throws {
    try DynamicCastTests.testCastSuccess()
    try DynamicCastTests.testCastFailure()
    try DynamicCastTests.testCastReferenceType()
    try DynamicCastTests.testClassUpcast()
    try DynamicCastTests.testCastViaMetadata()
  }
}
