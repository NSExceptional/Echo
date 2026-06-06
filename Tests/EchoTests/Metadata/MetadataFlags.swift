import XCTest
import Echo

actor FlagActor {
  var counter = 0
}

class FlagPlainClass {
  var x = 0
}

enum FlagThrownError: Error {
  case boom
}

enum MetadataFlagsTests {
  static func testValueWitnessCopyability() throws {
    // Ordinary copyable types report copyable / bitwise-borrowable.
    let intFlags = reflect(Int.self).vwt.flags
    XCTAssertTrue(intFlags.isCopyable)
    XCTAssertTrue(intFlags.isBitwiseBorrowable)

    let stringFlags = reflect(String.self).vwt.flags
    XCTAssertTrue(stringFlags.isCopyable)
  }

  static func testFunctionFlags() throws {
    let plain = reflect((() -> Void).self) as! FunctionMetadata
    XCTAssertFalse(plain.flags.isAsync)
    XCTAssertFalse(plain.flags.throws)
    XCTAssertFalse(plain.flags.isSendable)
    XCTAssertFalse(plain.flags.hasGlobalActor)

    let asyncFn = reflect((() async -> Void).self) as! FunctionMetadata
    XCTAssertTrue(asyncFn.flags.isAsync)

    let throwingFn = reflect((() throws -> Void).self) as! FunctionMetadata
    XCTAssertTrue(throwingFn.flags.throws)

    let sendableFn = reflect((@Sendable () -> Void).self) as! FunctionMetadata
    XCTAssertTrue(sendableFn.flags.isSendable)

    let asyncThrows = reflect((() async throws -> Void).self) as! FunctionMetadata
    XCTAssertTrue(asyncThrows.flags.isAsync)
    XCTAssertTrue(asyncThrows.flags.throws)

    let globalActorFn = reflect((@MainActor () -> Void).self) as! FunctionMetadata
    XCTAssertTrue(globalActorFn.flags.hasGlobalActor)
  }

  static func testFunctionTrailingTypes() throws {
    // Plain function: none of the conditional trailing fields.
    let plain = reflect((() -> Void).self) as! FunctionMetadata
    XCTAssertNil(plain.globalActorType)
    XCTAssertNil(plain.extendedFlags)
    XCTAssertNil(plain.thrownErrorType)

    // Global actor isolation carries the actor type in the trailing objects.
    let mainActorFn = reflect((@MainActor () -> Void).self) as! FunctionMetadata
    XCTAssertTrue(mainActorFn.flags.hasGlobalActor)
    XCTAssert(mainActorFn.globalActorType == MainActor.self)

    // Typed throws carries extended flags + the thrown error type. The runtime
    // support for typed-throws function metadata requires macOS 15 / iOS 18.
    if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, *) {
      let typedThrows = reflect((() throws(FlagThrownError) -> Void).self) as! FunctionMetadata
      XCTAssertTrue(typedThrows.flags.hasExtendedFlags)
      XCTAssertEqual(typedThrows.extendedFlags?.isTypedThrows, true)
      XCTAssert(typedThrows.thrownErrorType == FlagThrownError.self)
    }
  }

  static func testActorFlags() throws {
    let actorMetadata = reflectClass(FlagActor.self)!
    XCTAssertTrue(actorMetadata.isActor)
    XCTAssertTrue(actorMetadata.isDefaultActor)

    let plainMetadata = reflectClass(FlagPlainClass.self)!
    XCTAssertFalse(plainMetadata.isActor)
    XCTAssertFalse(plainMetadata.isDefaultActor)

    #if canImport(ObjectiveC)
    // Non-Swift classes never trap and report not-an-actor.
    let nsObject = reflectClass(NSObject.self)!
    XCTAssertFalse(nsObject.isActor)
    #endif
  }
}

extension EchoTests {
  func testMetadataFlags() throws {
    try MetadataFlagsTests.testValueWitnessCopyability()
    try MetadataFlagsTests.testFunctionFlags()
    try MetadataFlagsTests.testFunctionTrailingTypes()
    try MetadataFlagsTests.testActorFlags()
  }
}
