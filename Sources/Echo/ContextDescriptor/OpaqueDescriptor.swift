//
//  OpaqueDescriptor.swift
//  Echo
//
//  Created by Alejandro Alonso
//  Copyright © 2020 - 2021 Alejandro Alonso. All rights reserved.
//

/// Represents a descriptor for an opaque type.
///
/// ABI Stability: Stable since the following
///
///     |    macOS    |  iOS/tvOS  |  watchOS  | Linux | Windows |
///     |-------------|------------|-----------|-------|---------|
///     | 10.15 <= .3 | 13.0 <= .3 | 6.0 <= .1 | NA    | NA      |
///
public struct OpaqueDescriptor: ContextDescriptor, LayoutWrapper {
  typealias Layout = _OpaqueDescriptor
  
  /// Backing OpaqueDescriptor pointer.
  public let ptr: UnsafeRawPointer
  
  /// The number of underlying types for this opaque type.
  public var numUnderlyingTypes: Int {
    Int(layout._base._flags.kindSpecificFlags)
  }
  
  /// An array of mangled type names of the underlying types composing this
  /// opaque type.
  public var underlyingTypeMangledNames: [UnsafeRawPointer] {
    Array(unsafeUninitializedCapacity: numUnderlyingTypes) {
      var start = trailing
      
      if flags.isGeneric {
        start += genericContext!.size
      }
      
      for i in 0 ..< numUnderlyingTypes {
        let address = start.offset(of: i, as: RelativeDirectPointer<CChar>.self)
        $0[i] = address.relativeDirectAddress(as: CChar.self)
      }
      
      $1 = numUnderlyingTypes
    }
  }

  /// Realizes the concrete underlying type for the underlying-type entry at
  /// `index`, resolving its mangled name in this opaque descriptor's context.
  ///
  /// An opaque type (`some P`) stores its underlying type only as a mangled
  /// name; this turns it into a live metatype. `genericArguments` supplies the
  /// type arguments when the opaque type is nested in a generic context — pass
  /// `nil` (the default) for a self-contained underlying type, e.g. a
  /// non-generic `func f() -> some P` returning a concrete type.
  /// - Parameters:
  ///   - index: Which underlying type (`0 ..< numUnderlyingTypes`).
  ///   - genericArguments: Pointer to the generic arguments, if any.
  /// - Returns: The underlying type's metatype, or `nil` if out of range or
  ///            unresolvable.
  public func underlyingType(
    at index: Int,
    genericArguments: UnsafeRawPointer? = nil
  ) -> Any.Type? {
    let names = underlyingTypeMangledNames
    guard names.indices.contains(index) else {
      return nil
    }

    let mangledName = names[index]
    let length = getSymbolicMangledNameLength(mangledName)
    let name = mangledName.assumingMemoryBound(to: UInt8.self)
    return _getTypeByMangledNameInContext(
      name,
      UInt(length),
      genericContext: flags.isGeneric ? genericContext!.ptr : nil,
      genericArguments: genericArguments
    )
  }
}

extension OpaqueDescriptor: Equatable {}

struct _OpaqueDescriptor {
  let _base: _ContextDescriptor
}
