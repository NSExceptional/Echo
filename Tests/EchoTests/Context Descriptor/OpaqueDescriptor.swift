import XCTest
import Echo

// Opaque-returning functions emit opaque type descriptors into the image.
// `@inline(never)` keeps them from being optimized away.
@inline(never)
func opaqueReturningInt() -> some Equatable { 42 }

@inline(never)
func opaqueReturningString() -> some Equatable { "an opaque string" }

enum OpaqueDescriptorTests {
  static func testUnderlyingTypeRealization() throws {
    // Reference the functions so their opaque descriptors are emitted.
    _ = opaqueReturningInt()
    _ = opaqueReturningString()

    var underlyingTypeNames = Set<String>()
    for type in Echo.types {
      guard let opaque = type as? OpaqueDescriptor else { continue }
      if let underlying = opaque.underlyingType(at: 0) {
        underlyingTypeNames.insert(String(describing: underlying))
      }
      // Out-of-range indices resolve to nil rather than crashing.
      XCTAssertNil(opaque.underlyingType(at: opaque.numUnderlyingTypes))
    }

    // The two functions above contribute `Int` and `String` underlying types.
    XCTAssertTrue(underlyingTypeNames.contains("Int"))
    XCTAssertTrue(underlyingTypeNames.contains("String"))
  }
}

extension EchoTests {
  func testOpaqueDescriptor() throws {
    try OpaqueDescriptorTests.testUnderlyingTypeRealization()
  }
}
