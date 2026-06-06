import XCTest
import Echo

protocol AssocContainer {
  associatedtype Item
}

struct IntContainer: AssocContainer {
  typealias Item = Int
}

struct StringContainer: AssocContainer {
  typealias Item = String
}

enum AssociatedTypeTests {
  private static func assocContainerProtocol() throws -> ProtocolDescriptor {
    let metadata = reflectStruct(IntContainer.self)!
    let conformance = metadata.conformances.first {
      $0.protocol.name == "AssocContainer"
    }
    return try XCTUnwrap(conformance?.protocol)
  }

  static func testResolveAssociatedType() throws {
    let proto = try assocContainerProtocol()
    XCTAssertEqual(proto.associatedTypeNameList, ["Item"])

    let intItem = reflectStruct(IntContainer.self)!
      .associatedType(named: "Item", conformingTo: proto)
    XCTAssertNotNil(intItem)
    XCTAssert(intItem!.type == Int.self)

    // A different conforming type resolves to its own associated type.
    let stringItem = reflectStruct(StringContainer.self)!
      .associatedType(named: "Item", conformingTo: proto)
    XCTAssertNotNil(stringItem)
    XCTAssert(stringItem!.type == String.self)
  }

  static func testUnknownAssociatedTypeIsNil() throws {
    let proto = try assocContainerProtocol()
    let result = reflectStruct(IntContainer.self)!
      .associatedType(named: "DoesNotExist", conformingTo: proto)
    XCTAssertNil(result)
  }
}

extension EchoTests {
  func testAssociatedType() throws {
    try AssociatedTypeTests.testResolveAssociatedType()
    try AssociatedTypeTests.testUnknownAssociatedTypeIsNil()
  }
}
