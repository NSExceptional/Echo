//
//  ValueConstruction.swift
//  Echo
//
//  Safe, high-level construction of values whose type is only known at runtime.
//  These build on the value-witness table to allocate and populate instances
//  without the caller having to touch raw `unsafeBitCast`s.
//
//  NOTE: The read-back / arbitrary-buffer round-trip APIs (reading a non-inline
//  boxed value back into `Any`) are intentionally not exposed yet — they depend
//  on `AnyExistentialContainer.projectValue()`, which currently mislocates the
//  value for out-of-line (boxed) types. See GAPS.md "Known fragilities".
//

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
  /// box's value slot as reported by the runtime, so values written through it
  /// are read back correctly by a later cast of `toAny`.
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
}

//===----------------------------------------------------------------------===//
// Stored-property metadata by name
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

      var valueBox = container(for: value)
      // The destination field is freshly allocated (uninitialized), so an
      // initialize — not assign — is the correct value-witness operation.
      fieldType.vwt.initializeWithCopy(
        base + offset,
        valueBox.projectValue().mutable
      )
    }

    return existential.toAny
  }
}
