//
//  AssociatedType.swift
//  Echo
//
//  Resolving associated-type witnesses. A conformance's associated types (e.g.
//  `Self.Element` for a `Sequence` conformance) are not stored statically —
//  they are recovered at runtime by invoking accessor witnesses in the witness
//  table. Echo already surfaces the requirement descriptors and associated-type
//  names; this provides the call path to actually resolve them.
//

// swift_getAssociatedTypeWitness is SWIFT_CC(swift); @_silgen_name calls it with
// Swift's native calling convention, which matches. MetadataResponse's layout
// ({ metadata pointer, state }) mirrors the runtime's return struct.
@_silgen_name("swift_getAssociatedTypeWitness")
internal func _swift_getAssociatedTypeWitness(
  _ request: Int,
  _ witnessTable: UnsafeRawPointer,
  _ conformingType: UnsafeRawPointer,
  _ requirementBase: UnsafeRawPointer,
  _ associatedTypeRequirement: UnsafeRawPointer
) -> MetadataResponse

@_silgen_name("swift_getAssociatedConformanceWitness")
internal func _swift_getAssociatedConformanceWitness(
  _ witnessTable: UnsafeRawPointer,
  _ conformingType: UnsafeRawPointer,
  _ associatedType: UnsafeRawPointer,
  _ requirementBase: UnsafeRawPointer,
  _ associatedConformance: UnsafeRawPointer
) -> UnsafeRawPointer?

extension ProtocolDescriptor {
  /// The names of this protocol's associated types, in declaration order.
  public var associatedTypeNameList: [String] {
    associatedTypeNames
      .split(separator: " ")
      .map(String.init)
  }

  /// Resolves the metadata bound to the associated type named `name` for the
  /// conformance of `conformingType` described by `witnessTable`.
  ///
  /// For example, for a `Sequence` conformance this can recover `Element`.
  /// - Parameters:
  ///   - name: The associated type's name (e.g. `"Element"`).
  ///   - conformingType: Metadata for the conforming type.
  ///   - witnessTable: The witness table for `conformingType`'s conformance to
  ///                   this protocol.
  /// - Returns: The associated type's metadata, or `nil` if this protocol has no
  ///            such associated type.
  public func associatedTypeWitness(
    named name: String,
    conformingType: Metadata,
    witnessTable: WitnessTable
  ) -> Metadata? {
    let names = associatedTypeNameList
    guard let nameIndex = names.firstIndex(of: name) else {
      return nil
    }

    let requirements = self.requirements
    guard let firstRequirement = requirements.first else {
      return nil
    }

    // reqBase = &requirements[0] - WitnessTableFirstRequirementOffset (= 1).
    let requirementSize = MemoryLayout<_ProtocolRequirement>.size
    let requirementBase = firstRequirement.ptr - requirementSize

    // The associated-type access-function requirements appear in the same order
    // as the associated-type names, so pick the nameIndex-th one.
    var seen = 0
    var associatedTypeRequirement: UnsafeRawPointer?
    for requirement in requirements
    where requirement.flags.kind == .associatedTypeAccessFunction {
      if seen == nameIndex {
        associatedTypeRequirement = requirement.ptr
        break
      }
      seen += 1
    }

    guard let assocReq = associatedTypeRequirement else {
      return nil
    }

    let response = _swift_getAssociatedTypeWitness(
      MetadataRequest.complete.bits,
      witnessTable.ptr,
      conformingType.ptr,
      requirementBase,
      assocReq
    )

    return response.metadata
  }

  /// Resolves the witness table proving that the associated type named
  /// `associatedTypeName` conforms to `targetProtocol`, for the conformance of
  /// `conformingType` described by `witnessTable`.
  ///
  /// For example, given `protocol P { associatedtype A: Comparable }` and a
  /// type `T: P` whose `A` is `Int`, this returns `Int`'s `Comparable` witness
  /// table.
  ///
  /// - Note: This relies on the associated-conformance access-function
  ///   requirements corresponding one-to-one, in order, with the
  ///   protocol-conformance requirements in the requirement signature. That
  ///   holds for protocols without inherited protocols; when the counts differ
  ///   (e.g. a refining protocol), this conservatively returns `nil` rather
  ///   than risk a wrong witness.
  /// - Parameters:
  ///   - associatedTypeName: The associated type's name (e.g. `"A"`).
  ///   - targetProtocol: The protocol the associated type is constrained to.
  ///   - conformingType: Metadata for the conforming type.
  ///   - witnessTable: The witness table for `conformingType`'s conformance to
  ///                   this protocol.
  /// - Returns: The associated conformance's witness table, or `nil`.
  public func associatedConformanceWitness(
    ofAssociatedType associatedTypeName: String,
    to targetProtocol: ProtocolDescriptor,
    conformingType: Metadata,
    witnessTable: WitnessTable
  ) -> WitnessTable? {
    guard let associatedType = associatedTypeWitness(
      named: associatedTypeName,
      conformingType: conformingType,
      witnessTable: witnessTable
    ) else {
      return nil
    }

    let requirements = self.requirements
    guard let firstRequirement = requirements.first else {
      return nil
    }
    let requirementSize = MemoryLayout<_ProtocolRequirement>.size
    let requirementBase = firstRequirement.ptr - requirementSize

    let signatureConformances = requirementSignature.filter {
      $0.flags.kind == .protocol
    }
    let accessRequirements = requirements.filter {
      $0.flags.kind == .associatedConformanceAccessFunction
    }

    guard signatureConformances.count == accessRequirements.count,
          let index = signatureConformances.firstIndex(where: {
            $0.protocol == targetProtocol
          }) else {
      return nil
    }

    guard let witnessPointer = _swift_getAssociatedConformanceWitness(
      witnessTable.ptr,
      conformingType.ptr,
      associatedType.ptr,
      requirementBase,
      accessRequirements[index].ptr
    ) else {
      return nil
    }

    return WitnessTable(ptr: witnessPointer)
  }
}

extension TypeMetadata {
  /// Resolves the associated type named `name` for this type's conformance to
  /// `protocolDescriptor`, looking up the witness table at runtime.
  /// - Parameters:
  ///   - name: The associated type's name (e.g. `"Element"`).
  ///   - protocolDescriptor: The protocol declaring the associated type.
  /// - Returns: The associated type's metadata, or `nil` if this type does not
  ///            conform or the protocol has no such associated type.
  public func associatedType(
    named name: String,
    conformingTo protocolDescriptor: ProtocolDescriptor
  ) -> Metadata? {
    guard let witnessTable = swift_conformsToProtocol(
      metadata: self,
      protocol: protocolDescriptor
    ) else {
      return nil
    }

    return protocolDescriptor.associatedTypeWitness(
      named: name,
      conformingType: self,
      witnessTable: witnessTable
    )
  }

  /// Resolves the witness table proving this type's associated type
  /// `associatedTypeName` (from its conformance to `protocolDescriptor`)
  /// conforms to `targetProtocol`, looking up the witness table at runtime.
  /// - Parameters:
  ///   - associatedTypeName: The associated type's name (e.g. `"Element"`).
  ///   - targetProtocol: The protocol the associated type is constrained to.
  ///   - protocolDescriptor: The protocol declaring the associated type.
  /// - Returns: The associated conformance's witness table, or `nil`.
  public func associatedConformance(
    ofAssociatedType associatedTypeName: String,
    to targetProtocol: ProtocolDescriptor,
    conformingTo protocolDescriptor: ProtocolDescriptor
  ) -> WitnessTable? {
    guard let witnessTable = swift_conformsToProtocol(
      metadata: self,
      protocol: protocolDescriptor
    ) else {
      return nil
    }

    return protocolDescriptor.associatedConformanceWitness(
      ofAssociatedType: associatedTypeName,
      to: targetProtocol,
      conformingType: self,
      witnessTable: witnessTable
    )
  }
}
