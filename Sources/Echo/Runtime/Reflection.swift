//
//  Reflection.swift
//  Echo
//
//  A thin wrap over the standard library's reflection-mirror runtime — the same
//  SPI `Swift.Mirror` is built on. This gives child/value enumeration of an
//  arbitrary value (structs, classes incl. superclasses, enums with payload
//  projection, tuples) that is more robust than assembling it by hand from
//  field descriptors, at the cost of depending on `@_silgen_name` SPI.
//

internal typealias _NameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void

@_silgen_name("swift_reflectionMirror_count")
internal func _reflectionMirror_count<T>(_ value: T, type: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_subscript")
internal func _reflectionMirror_subscript<T>(
  _ value: T,
  type: Any.Type,
  index: Int,
  outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
  outFreeFunc: UnsafeMutablePointer<_NameFreeFunc?>
) -> Any

@_silgen_name("swift_reflectionMirror_displayStyle")
internal func _reflectionMirror_displayStyle<T>(_ value: T) -> CChar

/// One child of a reflected value: a stored property, tuple element, or an
/// enum's payload.
public struct ReflectedChild {
  /// The child's label — a property name, tuple element label, or enum case
  /// name. `nil` for unlabeled tuple elements.
  public let label: String?

  /// The child's value.
  public let value: Any
}

/// The high-level "kind" the reflection runtime reports for a value, mirroring
/// `Mirror.DisplayStyle` for the cases the runtime distinguishes.
public enum ReflectionDisplayStyle {
  case `struct`
  case `class`
  case `enum`
  case tuple
  /// No special structure (e.g. a scalar, function, or opaque value).
  case none
}

/// Enumerates the children of `subject` using the standard library's reflection
/// runtime — the same machinery `Swift.Mirror` uses.
///
/// For a struct or class this yields its *directly declared* stored properties
/// (a class's inherited properties are not included, matching `Mirror`); for a
/// tuple, its elements; for an enum, the single child is the current case's
/// payload labeled with the case name. Each child's `value` is an independent
/// copy, so it outlives `subject`. To include inherited class fields, use the
/// `ClassMetadata` field/`storedProperty` APIs, which walk the superclass chain.
/// - Parameter subject: The value to reflect.
/// - Returns: The value's children in order.
public func children(of subject: Any) -> [ReflectedChild] {
  let subjectType = Swift.type(of: subject)
  let count = _reflectionMirror_count(subject, type: subjectType)

  var result = [ReflectedChild]()
  result.reserveCapacity(count)

  for index in 0 ..< count {
    var name: UnsafePointer<CChar>? = nil
    var freeFunc: _NameFreeFunc? = nil

    let value = _reflectionMirror_subscript(
      subject,
      type: subjectType,
      index: index,
      outName: &name,
      outFreeFunc: &freeFunc
    )

    let label = name.map { String(cString: $0) }
    freeFunc?(name)

    result.append(ReflectedChild(label: label, value: value))
  }

  return result
}

/// The structural kind the reflection runtime reports for `subject`.
/// - Parameter subject: The value to inspect.
/// - Returns: The reflected display style.
public func displayStyle(of subject: Any) -> ReflectionDisplayStyle {
  switch UInt8(bitPattern: _reflectionMirror_displayStyle(subject)) {
  case UInt8(ascii: "s"): return .struct
  case UInt8(ascii: "c"): return .class
  case UInt8(ascii: "e"): return .enum
  case UInt8(ascii: "t"): return .tuple
  default: return .none
  }
}
