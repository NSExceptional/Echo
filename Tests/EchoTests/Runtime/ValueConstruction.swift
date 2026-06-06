import XCTest
import Echo

struct VCPoint: Equatable {
  var x: Int
  var y: Int
}

// Large enough — and containing a reference — to be stored out-of-line, so the
// boxed construction path and value-witness retain/release are exercised.
struct VCPerson {
  var name: String
  var nickname: String
  var age: Int
  var id: Int
}

enum ValueConstructionTests {
  static func testStructCreateInline() throws {
    let metadata = reflectStruct(VCPoint.self)!
    let value = metadata.createInstance(fields: ["x": 3, "y": 4])
    XCTAssertEqual(value as! VCPoint, VCPoint(x: 3, y: 4))
  }

  static func testStructCreateOutOfLine() throws {
    let metadata = reflectStruct(VCPerson.self)!
    // Sanity check that this type genuinely exercises the boxed path.
    XCTAssertFalse(metadata.vwt.flags.isValueInline)

    let value = metadata.createInstance(fields: [
      "name": "Ada Lovelace",
      "nickname": "the first programmer",
      "age": 36,
      "id": 1815,
    ])

    let person = value as! VCPerson
    XCTAssertEqual(person.name, "Ada Lovelace")
    XCTAssertEqual(person.nickname, "the first programmer")
    XCTAssertEqual(person.age, 36)
    XCTAssertEqual(person.id, 1815)
  }

  static func testFieldMetadataByKey() throws {
    let metadata = reflectStruct(VCPoint.self)!

    XCTAssertEqual(metadata.fieldOffset(forKey: "x"), 0)
    XCTAssertEqual(metadata.fieldOffset(forKey: "y"), MemoryLayout<Int>.size)
    XCTAssertNil(metadata.fieldOffset(forKey: "nonexistent"))

    let xType = try XCTUnwrap(metadata.fieldType(forKey: "x"))
    XCTAssert(xType.type == Int.self)
    XCTAssertNil(metadata.fieldType(forKey: "nonexistent"))

    XCTAssertEqual(metadata.fieldRecords.map(\.name), ["x", "y"])
  }
}

extension EchoTests {
  func testValueConstruction() throws {
    try ValueConstructionTests.testStructCreateInline()
    try ValueConstructionTests.testStructCreateOutOfLine()
    try ValueConstructionTests.testFieldMetadataByKey()
  }
}
