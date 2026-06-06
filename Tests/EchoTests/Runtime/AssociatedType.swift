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

protocol HasComparableItem {
  associatedtype Item: Comparable
}

struct IntItemHolder: HasComparableItem {
  typealias Item = Int
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

  static func testResolveAssociatedConformance() throws {
    let metadata = reflectStruct(IntItemHolder.self)!
    let proto = try XCTUnwrap(
      metadata.conformances.first { $0.protocol.name == "HasComparableItem" }?.protocol
    )

    // Comparable's protocol descriptor ("SL" is the stdlib mangling).
    let comparableMetadata = reflect(_typeByName("SL")!) as! ExistentialMetadata
    let comparable = comparableMetadata.protocols[0]

    let witness = try XCTUnwrap(
      metadata.associatedConformance(
        ofAssociatedType: "Item",
        to: comparable,
        conformingTo: proto
      )
    )

    // The associated conformance for Item == Int must be Int's own Comparable
    // witness table.
    let intComparable = try XCTUnwrap(
      swift_conformsToProtocol(type: Int.self, protocol: comparable)
    )
    XCTAssertEqual(witness, intComparable)
  }
}

extension EchoTests {
  func testAssociatedType() throws {
    try AssociatedTypeTests.testResolveAssociatedType()
    try AssociatedTypeTests.testUnknownAssociatedTypeIsNil()
    try AssociatedTypeTests.testResolveAssociatedConformance()
  }
}
