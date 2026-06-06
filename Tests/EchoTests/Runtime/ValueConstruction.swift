import XCTest
import Echo

struct VCPoint: Equatable {
  var x: Int
  var y: Int
}

class VCAnimal {
  var name: String
  var legs: Int
  init(name: String, legs: Int) {
    self.name = name
    self.legs = legs
  }
}

class VCDog: VCAnimal {
  var breed: String
  init(name: String, legs: Int, breed: String) {
    self.breed = breed
    super.init(name: name, legs: legs)
  }
}

// Large enough — and containing a reference — to be stored out-of-line, so the
// boxed construction path and value-witness retain/release are exercised.
struct VCPerson: Equatable {
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

  static func testValueBufferRoundTrip() throws {
    let metadata = reflect(VCPerson.self)
    let original: Any = VCPerson(
      name: "Grace Hopper",
      nickname: "Amazing Grace",
      age: 85,
      id: 1906
    )

    let buffer = metadata.allocateValueBuffer()
    defer {
      metadata.vwt.destroy(buffer)
      buffer.deallocate()
    }

    // Copy the value into the caller-owned buffer; after this the buffer holds
    // an independent copy, so it outlives `original`.
    withValuePointer(of: original) { source in
      metadata.vwt.initializeWithCopy(buffer, UnsafeMutableRawPointer(mutating: source))
    }

    let roundTripped = metadata.value(at: buffer) as! VCPerson
    XCTAssertEqual(roundTripped, original as! VCPerson)
  }

  static func testValueByKey() throws {
    let metadata = reflectStruct(VCPerson.self)!
    let person = VCPerson(name: "Katherine", nickname: "Johnson", age: 101, id: 1918)

    XCTAssertEqual(metadata.value(forKey: "name", of: person) as? String, "Katherine")
    XCTAssertEqual(metadata.value(forKey: "age", of: person) as? Int, 101)
    XCTAssertEqual(metadata.value(forKey: "id", of: person) as? Int, 1918)
    XCTAssertNil(metadata.value(forKey: "nonexistent", of: person))
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

  static func testClassCreateWithInheritance() throws {
    let metadata = reflectClass(VCDog.self)!
    let dog = metadata.createInstance(fields: [
      "name": "Rex",   // inherited from VCAnimal
      "legs": 4,       // inherited from VCAnimal
      "breed": "Lab",  // declared on VCDog
    ]) as! VCDog

    XCTAssertEqual(dog.name, "Rex")
    XCTAssertEqual(dog.legs, 4)
    XCTAssertEqual(dog.breed, "Lab")
  }

  static func testTupleCreate() throws {
    let metadata = reflect((Int, String).self) as! TupleMetadata
    let tuple = metadata.createInstance(elements: [42, "hello"]) as! (Int, String)
    XCTAssertEqual(tuple.0, 42)
    XCTAssertEqual(tuple.1, "hello")
  }

  static func testSetByKeyStruct() throws {
    let metadata = reflectStruct(VCPerson.self)!
    var person = VCPerson(name: "old", nickname: "n", age: 1, id: 2)

    withUnsafeMutablePointer(to: &person) { pointer in
      let raw = UnsafeMutableRawPointer(pointer)
      // Reassign an Int (POD) and a String (releases the old, retains the new).
      metadata.set(99, forKey: "age", in: raw)
      metadata.set("brand new name", forKey: "name", in: raw)
    }

    XCTAssertEqual(person.age, 99)
    XCTAssertEqual(person.name, "brand new name")
    XCTAssertEqual(person.id, 2)
  }

  static func testSetByKeyClass() throws {
    let metadata = reflectClass(VCDog.self)!
    let dog = VCDog(name: "Rex", legs: 4, breed: "Lab")
    let object = unsafeBitCast(dog, to: UnsafeMutableRawPointer.self)

    metadata.set("Max", forKey: "name", in: object)    // inherited field
    metadata.set("Husky", forKey: "breed", in: object) // own field

    XCTAssertEqual(dog.name, "Max")
    XCTAssertEqual(dog.breed, "Husky")
    XCTAssertEqual(dog.legs, 4)
  }
}

extension EchoTests {
  func testValueConstruction() throws {
    try ValueConstructionTests.testStructCreateInline()
    try ValueConstructionTests.testStructCreateOutOfLine()
    try ValueConstructionTests.testValueBufferRoundTrip()
    try ValueConstructionTests.testValueByKey()
    try ValueConstructionTests.testFieldMetadataByKey()
    try ValueConstructionTests.testClassCreateWithInheritance()
    try ValueConstructionTests.testTupleCreate()
    try ValueConstructionTests.testSetByKeyStruct()
    try ValueConstructionTests.testSetByKeyClass()
  }
}
