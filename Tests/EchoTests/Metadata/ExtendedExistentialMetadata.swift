import XCTest
import Echo

enum ExtendedExistentialMetadataTests {
  static func testParameterizedExistential() throws {
    // `any Collection<Int>` is a parameterized-protocol existential, which uses
    // the extended-existential metadata (kind 775). Reflecting it used to crash
    // Echo with "unknown kind 775".
    let metadata = reflect((any Collection<Int>).self)
    XCTAssertEqual(metadata.kind, .extendedExistential)

    let extended = try XCTUnwrap(metadata as? ExtendedExistentialMetadata)
    // Collection<Int> carries Int as a generalization argument.
    XCTAssertTrue(extended.shape.flags.hasGeneralizationSignature)
    // It is an opaque value existential, not a class/metatype one.
    XCTAssertEqual(extended.shape.flags.specialKind, .none)

    // The metadata round-trips back to the same type.
    XCTAssert(metadata.type == (any Collection<Int>).self)
  }

  static func testPlainExistentialIsClassic() throws {
    // A non-parameterized existential keeps the classic protocol-composition
    // metadata, not the extended one.
    let metadata = reflect((any Equatable).self)
    XCTAssertEqual(metadata.kind, .existential)
    XCTAssertTrue(metadata is ExistentialMetadata)
  }
}

extension EchoTests {
  func testExtendedExistentialMetadata() throws {
    try ExtendedExistentialMetadataTests.testParameterizedExistential()
    try ExtendedExistentialMetadataTests.testPlainExistentialIsClassic()
  }
}
