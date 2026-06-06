//
//  Demangle.swift
//  Echo
//
//  Demangling and context-free type-by-name resolution. The context-aware
//  resolver already lives on `TypeMetadata.type(of:)`; these round out the
//  surface with human-readable demangling and a standalone name lookup.
//

import Foundation

@_silgen_name("swift_demangle")
private func _stdlib_swift_demangle(
  _ mangledName: UnsafePointer<CChar>?,
  _ mangledNameLength: UInt,
  _ outputBuffer: UnsafeMutablePointer<CChar>?,
  _ outputBufferSize: UnsafeMutablePointer<UInt>?,
  _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?

/// Demangles a Swift mangled symbol name into a human-readable description.
///
/// For example, the mangled type symbol `"$sSiD"` demangles to `"Swift.Int"`.
/// The input must be a complete Swift symbol (typically prefixed with `$s`).
/// - Parameter mangledName: A Swift mangled symbol.
/// - Returns: The human-readable demangling, or `nil` if `mangledName` is not a
///            recognized Swift symbol.
public func demangle(_ mangledName: String) -> String? {
  mangledName.utf8CString.withUnsafeBufferPointer { buffer -> String? in
    guard let base = buffer.baseAddress else { return nil }

    // `utf8CString` includes the trailing null, which is not part of the length.
    guard let demangled = _stdlib_swift_demangle(
      base, UInt(buffer.count - 1), nil, nil, 0
    ) else {
      return nil
    }

    defer { free(demangled) }
    return String(cString: demangled)
  }
}

/// Resolves a mangled type name to its metatype, with no enclosing generic
/// context.
///
/// Use this for self-contained names (e.g. `"Si"` → `Int`). For names that
/// reference the generic parameters of an enclosing type — such as a generic
/// type's field types — use `TypeMetadata.type(of:)`, which threads the
/// correct context and generic arguments.
/// - Parameter mangledName: A mangled Swift type name.
/// - Returns: The resolved metatype, or `nil` if it could not be resolved.
public func type(named mangledName: String) -> Any.Type? {
  _typeByName(mangledName)
}
