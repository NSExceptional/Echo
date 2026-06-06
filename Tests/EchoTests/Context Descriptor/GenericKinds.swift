import XCTest
import Echo

struct PlainGeneric<T, U> {
  var t: T
  var u: U
}

// Variadic generics (Swift 5.9+): a type parameter pack.
struct PackGeneric<each Element> {}

enum GenericKindsTests {
  static func testOrdinaryParameterKinds() throws {
    let metadata = reflectStruct(PlainGeneric<Int, String>.self)!
    let context = try XCTUnwrap(metadata.descriptor.genericContext)
    XCTAssertEqual(context.parameters.count, 2)
    for parameter in context.parameters {
      XCTAssertEqual(parameter.kind, .type)
    }
  }

  static func testParameterPackKind() throws {
    // Reflecting a variadic-generic type must not crash decoding the pack
    // parameter's kind (previously force-unwrapped against a .type-only enum).
    let metadata = reflectStruct(PackGeneric<Int, String, Bool>.self)!
    let context = try XCTUnwrap(metadata.descriptor.genericContext)
    let kinds = context.parameters.map(\.kind)
    XCTAssertTrue(kinds.contains(.typePack))
  }

  static func testPackShapeDescriptors() throws {
    let metadata = reflectStruct(PackGeneric<Int, String, Bool>.self)!
    let context = try XCTUnwrap(metadata.descriptor.genericContext)

    XCTAssertTrue(context.descriptorFlags.hasTypePacks)
    let header = try XCTUnwrap(context.packShapeHeader)
    XCTAssertGreaterThanOrEqual(Int(header.numShapeClasses), 1)
    XCTAssertEqual(context.packShapeDescriptors.count, Int(header.numShapeClasses))
    // The single `each Element` parameter is a metadata pack.
    XCTAssertTrue(context.packShapeDescriptors.contains { $0.kind == .metadata })
  }

  static func testNonPackHasNoShapes() throws {
    let metadata = reflectStruct(PlainGeneric<Int, String>.self)!
    let context = try XCTUnwrap(metadata.descriptor.genericContext)

    XCTAssertFalse(context.descriptorFlags.hasTypePacks)
    XCTAssertNil(context.packShapeHeader)
    XCTAssertTrue(context.packShapeDescriptors.isEmpty)
  }
}

extension EchoTests {
  func testGenericKinds() throws {
    try GenericKindsTests.testOrdinaryParameterKinds()
    try GenericKindsTests.testParameterPackKind()
    try GenericKindsTests.testPackShapeDescriptors()
    try GenericKindsTests.testNonPackHasNoShapes()
  }
}
