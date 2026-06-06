//
//  DynamicCast.swift
//  Echo
//
//  Runtime dynamic casting: cast a value to a type that is only known at
//  runtime (as `Metadata`), which the static `as?` operator cannot express.
//

import CEcho

/// Attempts to dynamically cast `value` to the type described by `targetType`,
/// returning the cast value on success or `nil` on failure.
///
/// This is the runtime equivalent of `value as? T`, but with the target type
/// supplied as `Metadata` rather than a static type — useful when the type to
/// cast to is itself discovered through reflection. It performs the same checks
/// the compiler emits for `as?`: class-hierarchy walks, protocol-conformance
/// lookups, bridging, and existential unwrapping.
/// - Parameters:
///   - value: The value to cast. It is not modified.
///   - targetType: Metadata for the type to cast to.
/// - Returns: The cast value boxed as `Any`, or `nil` if the cast fails.
public func dynamicCast(_ value: Any, to targetType: Metadata) -> Any? {
  var container = container(for: value)
  let sourceType = container.metadata

  let sourceBuffer = sourceType.allocateValueBuffer()
  let destinationBuffer = targetType.allocateValueBuffer()
  defer {
    sourceBuffer.deallocate()
    destinationBuffer.deallocate()
  }

  // Copy the source into an owned buffer so the cast may consume it without
  // disturbing the caller's value.
  withValuePointer(of: value) { source in
    sourceType.vwt.initializeWithCopy(sourceBuffer, source.mutable)
  }

  // DynamicCastFlags.takeOnSuccess (0x2) | .destroyOnFailure (0x4): a
  // conditional cast that consumes `sourceBuffer`'s value on both the success
  // and failure paths, so we only free its raw storage. (Bit 0x1 is
  // Unconditional, which would trap on failure instead of returning false.)
  let flags = 0x2 | 0x4
  let didCast = swift_dynamicCast(
    destinationBuffer,
    sourceBuffer,
    sourceType.ptr,
    targetType.ptr,
    flags
  )

  guard didCast else {
    return nil
  }

  // On success `destinationBuffer` holds an initialized value of `targetType`.
  defer { targetType.vwt.destroy(destinationBuffer) }
  return targetType.value(at: destinationBuffer)
}

/// Attempts to dynamically cast `value` to `type`.
///
/// A convenience over ``dynamicCast(_:to:)-(Any,Metadata)`` that takes a
/// metatype instead of `Metadata`.
/// - Parameters:
///   - value: The value to cast. It is not modified.
///   - type: The type to cast to.
/// - Returns: The cast value boxed as `Any`, or `nil` if the cast fails.
public func dynamicCast(_ value: Any, to type: Any.Type) -> Any? {
  dynamicCast(value, to: reflect(type))
}
