//
//  ValueConstruction.swift
//  Echo
//
//  Safe, high-level construction and access of values whose type is only known
//  at runtime. These build on the value-witness table to allocate, populate,
//  copy, and read back values without the caller having to touch raw
//  `unsafeBitCast`s.
//

//===----------------------------------------------------------------------===//
// Pointer access to an Any's value (lifetime-safe)
//===----------------------------------------------------------------------===//

/// Invokes `body` with a pointer to the in-memory value of `value`.
///
/// This is the safe way to obtain a pointer to an `Any`'s underlying value: for
/// values stored out-of-line (larger than three words) the value lives in a
/// heap box owned by `value`, so the pointer is only valid while `value` is
/// alive. This keeps `value` alive for the duration of `body` and does not
/// escape the pointer.
/// - Parameters:
///   - value: The value whose storage should be accessed.
///   - body: A closure receiving a pointer to `value`'s storage. Do not let the
///           pointer escape the closure.
/// - Returns: Whatever `body` returns.
public func withValuePointer<Result>(
  of value: Any,
  _ body: (UnsafeRawPointer) throws -> Result
) rethrows -> Result {
  var container = container(for: value)
  // `container` shares `value`'s heap box (if any); keep `value` alive so the
  // box outlives the projected pointer.
  return try withExtendedLifetime(value) {
    try body(container.projectValue())
  }
}

//===----------------------------------------------------------------------===//
// Raw value buffers
//===----------------------------------------------------------------------===//

extension Metadata {
  /// Allocates a raw, uninitialized buffer sized and aligned to hold exactly
  /// one value of this type.
  ///
  /// The caller owns the returned buffer. Once a value has been initialized
  /// into it (e.g. via the value witnesses), destroy that value with
  /// `vwt.destroy(_:)` before freeing the buffer with `deallocate()`.
  /// - Returns: A pointer to the freshly allocated, uninitialized storage.
  public func allocateValueBuffer() -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer.allocate(
      byteCount: vwt.size,
      alignment: vwt.flags.alignment
    )
  }

  /// Reads the value at `buffer` — which must be a valid, initialized instance
  /// of this type — back into an `Any`, copying it. The buffer is left intact
  /// (its value is not consumed).
  /// - Parameter buffer: A pointer to a valid instance of this type.
  /// - Returns: The value boxed as `Any`.
  public func value(at buffer: UnsafeRawPointer) -> Any {
    AnyExistentialContainer(metadata: self, copying: buffer).toAny
  }
}

//===----------------------------------------------------------------------===//
// AnyExistentialContainer ergonomics
//===----------------------------------------------------------------------===//

extension AnyExistentialContainer {
  /// Reinterprets this container as the `Any` value it represents.
  ///
  /// The container must already hold a valid value (stored inline, or in a heap
  /// box referenced by `data`). This is the inverse of `container(for:)`.
  public var toAny: Any {
    unsafeBitCast(self, to: Any.self)
  }

  /// Returns a pointer to this container's value storage, allocating a heap box
  /// first if the type is stored out-of-line and no box exists yet.
  ///
  /// Prefer this over `projectValue()` when *populating* a freshly created
  /// container: `projectValue()` assumes a box already exists for out-of-line
  /// types, whereas this allocates one on demand. The returned pointer is the
  /// box's value slot, so values written through it are read back correctly by
  /// a later cast of `toAny`.
  /// - Returns: A pointer to writable storage for this container's value.
  public mutating func mutableValueBuffer() -> UnsafeMutableRawPointer {
    // An out-of-line value that already has a box: reuse it.
    if !metadata.vwt.flags.isValueInline, data.0 != 0 {
      return projectValue().mutable
    }

    // Inline values return a pointer to `data`; out-of-line values get a new
    // heap box (which also records the box pointer in `data`).
    return metadata.allocateBoxForExistential(in: &self).mutable
  }

  /// Creates a container of `metadata`'s type holding a copy of the value at
  /// `source`, which must be a valid instance of that type. The value is copied
  /// (via `initializeWithCopy`); `source` is left intact.
  public init(metadata: Metadata, copying source: UnsafeRawPointer) {
    // Build into stable storage first: allocating a box records its pointer via
    // `&self`, which only persists reliably once `self` is settled.
    var container = AnyExistentialContainer(metadata: metadata)
    let destination = container.mutableValueBuffer()
    metadata.vwt.initializeWithCopy(destination, source.mutable)
    self = container
  }
}

//===----------------------------------------------------------------------===//
// Stored-property access by name
//===----------------------------------------------------------------------===//

extension TypeMetadata {
  /// The stored-property field records declared directly by this type, in
  /// declaration order. Does not include inherited fields for classes.
  public var fieldRecords: [FieldRecord] {
    contextDescriptor?.fields.records ?? []
  }

  /// The byte offset, within an instance, of the stored property named `key`.
  /// - Parameter key: The stored property's declared name.
  /// - Returns: The offset, or `nil` if there is no such stored property.
  public func fieldOffset(forKey key: String) -> Int? {
    guard let index = fieldRecords.firstIndex(where: { $0.name == key }) else {
      return nil
    }

    return fieldOffsets[index]
  }

  /// The metadata for the type of the stored property named `key`.
  /// - Parameter key: The stored property's declared name.
  /// - Returns: The field's type metadata, or `nil` if there is no such stored
  ///            property or its type could not be resolved.
  public func fieldType(forKey key: String) -> Metadata? {
    guard let record = fieldRecords.first(where: { $0.name == key }),
          record.hasMangledTypeName,
          // Qualify with `self.` so this resolves to Echo's mangled-name
          // resolver and not Swift's built-in `type(of:)`.
          let type = self.type(of: record.mangledTypeName) else {
      return nil
    }

    return reflect(type)
  }

  /// Reads the stored property named `key` from the instance at `instance`.
  /// - Parameters:
  ///   - key: The stored property's declared name.
  ///   - instance: A pointer to a valid instance of this type.
  /// - Returns: The property's value as `Any`, or `nil` if there is no such
  ///            stored property.
  public func value(forKey key: String, from instance: UnsafeRawPointer) -> Any? {
    guard let offset = fieldOffset(forKey: key),
          let type = fieldType(forKey: key) else {
      return nil
    }

    return type.value(at: instance + offset)
  }

  /// Reads the stored property named `key` from `instance`.
  ///
  /// A lifetime-safe convenience over `value(forKey:from:)` that keeps
  /// `instance` alive while its storage is read.
  /// - Parameters:
  ///   - key: The stored property's declared name.
  ///   - instance: A value of this type.
  /// - Returns: The property's value as `Any`, or `nil` if there is no such
  ///            stored property.
  public func value(forKey key: String, of instance: Any) -> Any? {
    withValuePointer(of: instance) { value(forKey: key, from: $0) }
  }
}

//===----------------------------------------------------------------------===//
// Struct construction
//===----------------------------------------------------------------------===//

extension StructMetadata {
  /// Creates an instance of this struct, initializing each stored property from
  /// `fields` (keyed by the property's declared name).
  ///
  /// Each provided value must already be of the corresponding property's type —
  /// no conversion is performed — and is copied into the new instance via the
  /// property type's value witnesses. Stored properties with no entry in
  /// `fields` are left untouched, so callers that need a fully-formed value
  /// should supply every property. This is a building block intended for
  /// higher-level mappers that validate and coerce their inputs first.
  /// - Parameter fields: The value for each stored property, keyed by name.
  /// - Returns: The newly constructed struct, boxed as `Any`.
  public func createInstance(fields: [String: Any]) -> Any {
    var existential = AnyExistentialContainer(metadata: self)
    let base = existential.mutableValueBuffer()

    for record in fieldRecords {
      guard let value = fields[record.name],
            let offset = fieldOffset(forKey: record.name),
            let fieldType = fieldType(forKey: record.name) else {
        continue
      }

      // `value` is kept alive by `fields` for the duration of this loop, so its
      // storage pointer is valid here.
      withValuePointer(of: value) { valuePointer in
        // The destination field is freshly allocated (uninitialized), so an
        // initialize — not assign — is the correct value-witness operation.
        fieldType.vwt.initializeWithCopy(base + offset, valuePointer.mutable)
      }
    }

    return existential.toAny
  }
}

//===----------------------------------------------------------------------===//
// Tuple construction
//===----------------------------------------------------------------------===//

extension TupleMetadata {
  /// Creates a tuple of this type, initializing each element from `elements`
  /// (in positional order). Each value must already be of the corresponding
  /// element's type. Excess values, or values beyond the tuple's arity, are
  /// ignored.
  /// - Parameter elements: The value for each tuple element, in order.
  /// - Returns: The newly constructed tuple, boxed as `Any`.
  public func createInstance(elements values: [Any]) -> Any {
    var existential = AnyExistentialContainer(metadata: self)
    let base = existential.mutableValueBuffer()

    for (element, value) in zip(elements, values) {
      withValuePointer(of: value) { valuePointer in
        element.metadata.vwt.initializeWithCopy(
          base + element.offset,
          valuePointer.mutable
        )
      }
    }

    return existential.toAny
  }
}

//===----------------------------------------------------------------------===//
// Class construction
//===----------------------------------------------------------------------===//

extension ClassMetadata {
  /// The byte offset and type metadata of the stored property named `key`,
  /// searching this class and its Swift superclasses.
  func storedProperty(forKey key: String) -> (offset: Int, type: Metadata)? {
    if let offset = fieldOffset(forKey: key), let type = fieldType(forKey: key) {
      return (offset, type)
    }

    if let superclass = superclassMetadata, superclass.isSwiftClass {
      return superclass.storedProperty(forKey: key)
    }

    return nil
  }

  /// Allocates and initializes an instance of this class, setting each stored
  /// property from `fields` (keyed by the property's declared name, including
  /// inherited Swift stored properties).
  ///
  /// As with the struct variant, values must already be of the property's type
  /// and are copied in via the value witnesses. Properties absent from `fields`
  /// remain zero-initialized. This is a low-level building block: it does not
  /// run the class's designated initializer, so types relying on `init` side
  /// effects should not be created this way.
  /// - Parameter fields: The value for each stored property, keyed by name.
  /// - Returns: The newly allocated instance.
  public func createInstance(fields: [String: Any]) -> AnyObject {
    let object = swift_allocObject(
      for: self,
      size: instanceSize,
      alignment: instanceAlignmentMask
    ).mutable

    for (key, value) in fields {
      guard let (offset, type) = storedProperty(forKey: key) else {
        continue
      }

      withValuePointer(of: value) { valuePointer in
        // swift_allocObject zero-fills the instance, so the field is
        // uninitialized storage — initialize rather than assign.
        type.vwt.initializeWithCopy(object + offset, valuePointer.mutable)
      }
    }

    return Unmanaged<AnyObject>.fromOpaque(object).takeRetainedValue()
  }
}

//===----------------------------------------------------------------------===//
// In-place mutation by name
//===----------------------------------------------------------------------===//

extension TypeMetadata {
  /// Overwrites the stored property named `key` in the instance at `instance`
  /// with `value`.
  ///
  /// Unlike construction, this *assigns* over an already-initialized field —
  /// the previous value is destroyed (e.g. released) before the new one is
  /// copied in. `value` must be of the property's type. No-op if there is no
  /// such stored property.
  /// - Parameters:
  ///   - value: The new value, of the property's type.
  ///   - key: The stored property's declared name.
  ///   - instance: A pointer to a valid instance of this type.
  public func set(
    _ value: Any,
    forKey key: String,
    in instance: UnsafeMutableRawPointer
  ) {
    guard let offset = fieldOffset(forKey: key),
          let type = fieldType(forKey: key) else {
      return
    }

    withValuePointer(of: value) { valuePointer in
      type.vwt.assignWithCopy(instance + offset, valuePointer.mutable)
    }
  }
}

extension ClassMetadata {
  /// Overwrites the stored property named `key` (searching this class and its
  /// Swift superclasses) in the instance at `instance` with `value`.
  /// - Parameters:
  ///   - value: The new value, of the property's type.
  ///   - key: The stored property's declared name.
  ///   - instance: A pointer to a valid instance of this class.
  public func set(
    _ value: Any,
    forKey key: String,
    in instance: UnsafeMutableRawPointer
  ) {
    guard let (offset, type) = storedProperty(forKey: key) else {
      return
    }

    withValuePointer(of: value) { valuePointer in
      type.vwt.assignWithCopy(instance + offset, valuePointer.mutable)
    }
  }
}
