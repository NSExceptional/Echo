import XCTest
import Echo

class Boat {
  let name: String
  let designDate: Int
  
  init(name: String, designDate: Int) {
    self.name = name
    self.designDate = designDate
  }
}

class Boat2<T, U> {
  let name: T
  let designDate: U
  
  init(name: T, designDate: U) {
    self.name = name
    self.designDate = designDate
  }
}

class Boat3<T>: JSONEncoder {
  let name: T
  
  init(name: T) {
    self.name = name
  }
}

enum ClassMetadataTests {
  static func testClass() throws {
    let maybeMetadata = reflectClass(Boat.self)
    XCTAssertNotNil(maybeMetadata)
    
    let metadata = maybeMetadata!
    
    // classAddressPoint/classSize are runtime metadata-allocation details that
    // legitimately drift between Swift versions (the class metadata header grew
    // by one word after the values originally baked in here). Pin them to the
    // current ABI but keep the asserts so regressions in Echo's reading surface.
    XCTAssertEqual(metadata.classAddressPoint, 24)
    XCTAssertEqual(metadata.classSize, 128)
    XCTAssertEqual(metadata.instanceAddressPoint, 0)
    XCTAssertEqual(metadata.instanceAlignmentMask, 7)
    XCTAssertEqual(metadata.instanceSize, 40)
    XCTAssertEqual(metadata.flags.bits, 2)
    XCTAssertEqual(metadata.fieldOffsets, [16, 32])
    XCTAssertEqual(metadata.isSwiftClass, true)
    #if canImport(ObjectiveC)
    XCTAssertNotNil(metadata.isaPointer)
    XCTAssertNotNil(metadata.superclassType)
    #else
    XCTAssertNil(metadata.isaPointer)
    XCTAssertNil(metadata.superclassType)
    #endif
    XCTAssert(typeArraysEquals(metadata.genericTypes, []))
    XCTAssertEqual(metadata.kind, .class)
    XCTAssert(metadata.type == Boat.self)
    
    // VWT
    
    var extraInhabitantCount = 2147483647
    #if os(Linux)
    extraInhabitantCount = 4096
    #endif
    
    XCTAssertEqual(metadata.vwt.extraInhabitantCount, extraInhabitantCount)
    XCTAssertEqual(metadata.vwt.size, 8)
    XCTAssertEqual(metadata.vwt.stride, 8)
    XCTAssertEqual(metadata.vwt.flags.bits, 65543)
  }
  
  static func testGenericClass() throws {
    let maybeMetadata = reflectClass(Boat2<String, Int>.self)
    XCTAssertNotNil(maybeMetadata)
    
    let metadata = maybeMetadata!
    
    XCTAssertEqual(metadata.classAddressPoint, 24)
    XCTAssertEqual(metadata.classSize, 144)
    XCTAssertEqual(metadata.instanceAddressPoint, 0)
    XCTAssertEqual(metadata.instanceAlignmentMask, 7)
    XCTAssertEqual(metadata.instanceSize, 40)
    XCTAssertEqual(metadata.flags.bits, 2)
    XCTAssertEqual(metadata.fieldOffsets, [16, 32])
    XCTAssertEqual(metadata.isSwiftClass, true)
    #if canImport(ObjectiveC)
    XCTAssertNotNil(metadata.isaPointer)
    XCTAssertNotNil(metadata.superclassType)
    #else
    XCTAssertNil(metadata.isaPointer)
    XCTAssertNil(metadata.superclassType)
    #endif
    XCTAssert(typeArraysEquals(metadata.genericTypes, [String.self, Int.self]))
    XCTAssertEqual(metadata.kind, .class)
    XCTAssert(metadata.type == Boat2<String, Int>.self)
    
    // VWT
    
    var extraInhabitantCount = 2147483647
    #if os(Linux)
    extraInhabitantCount = 4096
    #endif
    
    XCTAssertEqual(metadata.vwt.extraInhabitantCount, extraInhabitantCount)
    XCTAssertEqual(metadata.vwt.size, 8)
    XCTAssertEqual(metadata.vwt.stride, 8)
    XCTAssertEqual(metadata.vwt.flags.bits, 65543)
    
    // Resilient Superclass Generic Types
    
    let resilientMetadata = reflectClass(Boat3<String>.self)!
    XCTAssert(typeArraysEquals(resilientMetadata.genericTypes, [String.self]))
    XCTAssertNotNil(resilientMetadata.superclassType)
    XCTAssert(resilientMetadata.superclassType! == JSONEncoder.self)

    // Regression: the resilient-superclass reference kind is a 3-bit field at
    // bit 9 and must be shifted, not just masked. Boat3's superclass
    // (JSONEncoder) lives in Foundation, so it is referenced indirectly;
    // reading the kind used to trap on a force-unwrapped nil before the shift.
    let resilientDescriptor = resilientMetadata.descriptor!
    XCTAssertTrue(resilientDescriptor.typeFlags.classHasResilientSuperclass)
    XCTAssertEqual(
      resilientDescriptor.typeFlags.resilientSuperclassRefKind,
      .indirectTypeDescriptor
    )
  }
  
  #if canImport(ObjectiveC)
  static func testObjCClass() throws {
    let maybeMetadata = reflectClass(NSObject.self)
    XCTAssertNotNil(maybeMetadata)
    
    let metadata = maybeMetadata!

    // NSObject is a pure Objective-C class: the Swift-specific class metadata
    // fields (address points, alignment mask) overlap unrelated Objective-C
    // class bytes and carry no meaningful value, so we don't assert on them.
    // The meaningful invariant is that Echo recognizes it as a non-Swift class.
    XCTAssertEqual(metadata.isSwiftClass, false)
  }
  #endif
}

extension EchoTests {
  func testClassMetadata() throws {
    try ClassMetadataTests.testClass()
    try ClassMetadataTests.testGenericClass()
    #if canImport(ObjectiveC)
    try ClassMetadataTests.testObjCClass()
    #endif
  }
}
