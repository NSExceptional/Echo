//
//  FunctionMetadata.swift
//  Echo
//
//  Created by Alejandro Alonso
//  Copyright © 2019 - 2021 Alejandro Alonso. All rights reserved.
//

/// The metadata structure that represents a function type in Swift.
///
/// ABI Stability: Unstable across all platforms
///
///     | macOS | iOS/tvOS | watchOS | Linux | Windows |
///     |-------|----------|---------|-------|---------|
///     | NA    | NA       | NA      | NA    | NA      |
///
public struct FunctionMetadata: Metadata, LayoutWrapper {
  typealias Layout = _FunctionMetadata
  
  /// Backing function metadata pointer.
  public let ptr: UnsafeRawPointer
  
  /// The flags specific to function metadata.
  public var flags: Flags {
    layout._flags
  }
  
  /// The result type for this function.
  public var resultType: Any.Type {
    layout._result
  }
  
  /// The result type metadata for this function.
  public var resultMetadata: Metadata {
    reflect(resultType)
  }
  
  /// An array of parameter types for this function.
  public var paramTypes: [Any.Type] {
    Array(unsafeUninitializedCapacity: flags.numParams) {
      for i in 0 ..< flags.numParams {
        let type = trailing.load(
          fromByteOffset: i * MemoryLayout<Any.Type>.size,
          as: Any.Type.self
        )
        
        $0[i] = type
      }
      
      $1 = flags.numParams
    }
  }
  
  /// An array of parameter type metadata for this function.
  public var paramMetadata: [Metadata] {
    paramTypes.map { reflect($0) }
  }
  
  /// An array of parameter flags that describe each parameter for this
  /// function, if any.
  public var paramFlags: [ParamFlags] {
    guard flags.hasParamFlags else { return [] }
    
    return Array(unsafeUninitializedCapacity: flags.numParams) {
      let start = trailing.offset(of: flags.numParams)
      
      for i in 0 ..< flags.numParams {
        let paramFlag = start.load(
          fromByteOffset: i * MemoryLayout<ParamFlags>.stride,
          as: ParamFlags.self
        )
        
        $0[i] = paramFlag
      }
      
      $1 = flags.numParams
    }
  }
}

extension FunctionMetadata {
  // The conditional trailing fields after the parameter array, in ABI order:
  // parameters, parameter flags, differentiability, global actor, extended
  // flags, thrown error. Each is laid out at its natural alignment.
  private func trailingFieldOffsets() -> (
    globalActor: Int?, extendedFlags: Int?, thrownError: Int?
  ) {
    let pointerSize = MemoryLayout<UnsafeRawPointer>.size
    let uint32Size = MemoryLayout<UInt32>.size

    func aligned(_ offset: Int, to alignment: Int) -> Int {
      (offset + alignment - 1) & ~(alignment - 1)
    }

    // After the parameter type array.
    var offset = flags.numParams * pointerSize

    if flags.hasParamFlags {
      offset += flags.numParams * uint32Size
    }

    if flags.isDifferentiable {
      offset = aligned(offset, to: pointerSize)
      offset += pointerSize
    }

    var globalActor: Int?
    if flags.hasGlobalActor {
      offset = aligned(offset, to: pointerSize)
      globalActor = offset
      offset += pointerSize
    }

    var extendedFlags: Int?
    if flags.hasExtendedFlags {
      offset = aligned(offset, to: uint32Size)
      extendedFlags = offset
      offset += uint32Size
    }

    var thrownError: Int?
    if let extendedFlags,
       trailing.load(fromByteOffset: extendedFlags, as: ExtendedFunctionTypeFlags.self)
         .isTypedThrows {
      offset = aligned(offset, to: pointerSize)
      thrownError = offset
      offset += pointerSize
    }

    return (globalActor, extendedFlags, thrownError)
  }

  /// The global actor this function type is isolated to (e.g. `MainActor`), if
  /// it has one (`flags.hasGlobalActor`).
  public var globalActorType: Any.Type? {
    guard let offset = trailingFieldOffsets().globalActor else {
      return nil
    }

    return trailing.load(fromByteOffset: offset, as: Any.Type.self)
  }

  /// The extended function-type flags (typed throws, isolation kind, sending
  /// result), if present (`flags.hasExtendedFlags`).
  public var extendedFlags: ExtendedFunctionTypeFlags? {
    guard let offset = trailingFieldOffsets().extendedFlags else {
      return nil
    }

    return trailing.load(fromByteOffset: offset, as: ExtendedFunctionTypeFlags.self)
  }

  /// The error type of a typed-throws function (e.g. `MyError` for
  /// `throws(MyError)`), if it has one.
  public var thrownErrorType: Any.Type? {
    guard let offset = trailingFieldOffsets().thrownError else {
      return nil
    }

    return trailing.load(fromByteOffset: offset, as: Any.Type.self)
  }
}

/// The extended flags carried by some function types, beyond the 32-bit
/// `FunctionMetadata.Flags`. Present only when `flags.hasExtendedFlags`.
public struct ExtendedFunctionTypeFlags {
  /// Flags as represented in bits.
  public let bits: UInt32

  /// Whether this function uses typed throws (`throws(E)`); if so, the thrown
  /// error type is available via `FunctionMetadata.thrownErrorType`.
  public var isTypedThrows: Bool {
    bits & 0x1 != 0
  }

  /// Whether this function has `@isolated(any)` isolation.
  public var isIsolatedAny: Bool {
    bits & 0xE == 0x2
  }

  /// Whether this function is `nonisolated(nonsending)`.
  public var isNonIsolatedNonsending: Bool {
    bits & 0xE == 0x4
  }

  /// Whether this function has a `sending` result.
  public var hasSendingResult: Bool {
    bits & 0x10 != 0
  }
}

extension FunctionMetadata: Equatable {}

struct _FunctionMetadata {
  let _kind: Int
  let _flags: FunctionMetadata.Flags
  let _result: Any.Type
}
