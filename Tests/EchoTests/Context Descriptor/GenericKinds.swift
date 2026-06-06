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
}

extension EchoTests {
  func testGenericKinds() throws {
    try GenericKindsTests.testOrdinaryParameterKinds()
    try GenericKindsTests.testParameterPackKind()
  }
}
