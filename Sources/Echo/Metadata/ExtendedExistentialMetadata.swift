//
//  ExtendedExistentialMetadata.swift
//  Echo
//
//  Metadata for a generalized / constrained existential — e.g. a
//  parameterized-protocol existential like `any Collection<Int>`. These carry
//  a *shape* describing the existential's requirement and generalization
//  signatures, distinct from the classic protocol-composition layout modeled by
//  `ExistentialMetadata`. Reflecting one previously crashed Echo with an
//  "unknown kind 775".
//

/// The metadata structure that represents a generalized existential type, such
/// as `any Collection<Int>` or other constrained / parameterized-protocol
/// existentials.
///
/// ABI Stability: Unstable across all platforms
public struct ExtendedExistentialMetadata: Metadata, LayoutWrapper {
  typealias Layout = _ExtendedExistentialMetadata

  /// Backing extended existential metadata pointer.
  public let ptr: UnsafeRawPointer

  /// The existential shape describing this existential's constraints and
  /// generalization signature.
  public var shape: ExtendedExistentialTypeShape {
    ExtendedExistentialTypeShape(ptr: layout._shape.signed)
  }
}

extension ExtendedExistentialMetadata: Equatable {}

struct _ExtendedExistentialMetadata {
  let _kind: Int
  let _shape: SignedPointer<_ExtendedExistentialTypeShape>
}

/// Describes the shape of a generalized existential: how its value is
/// represented and what optional records (generalization signature, type
/// expression, suggested value witnesses) it carries.
///
/// ABI Stability: Unstable across all platforms
public struct ExtendedExistentialTypeShape: LayoutWrapper {
  typealias Layout = _ExtendedExistentialTypeShape

  /// Backing shape pointer.
  let ptr: UnsafeRawPointer

  /// Flags describing this existential shape.
  public var flags: Flags {
    layout._flags
  }
}

extension ExtendedExistentialTypeShape {
  /// Flags for an extended existential type shape.
  public struct Flags {
    /// Flags as represented in bits.
    public let bits: UInt32

    /// How the existential value is represented.
    public var specialKind: SpecialKind {
      SpecialKind(rawValue: UInt8(bits & 0xFF)) ?? .none
    }

    /// Whether the shape has a generalization signature — the substituted
    /// generic arguments of the existential (e.g. the `Int` in
    /// `any Collection<Int>`).
    public var hasGeneralizationSignature: Bool {
      bits & 0x100 != 0
    }

    /// Whether the shape carries a mangled type expression.
    public var hasTypeExpression: Bool {
      bits & 0x200 != 0
    }

    /// Whether the shape carries suggested value witnesses.
    public var hasSuggestedValueWitnesses: Bool {
      bits & 0x400 != 0
    }
  }

  /// How a generalized existential's value is represented.
  public enum SpecialKind: UInt8 {
    /// An opaque value existential (the general case).
    case none = 0

    /// A class existential — a single retainable pointer.
    case `class` = 1

    /// A metatype existential.
    case metatype = 2

    /// An existential with an explicitly-described layout.
    case explicitLayout = 3
  }
}

extension ExtendedExistentialTypeShape: Equatable {}

struct _ExtendedExistentialTypeShape {
  let _flags: ExtendedExistentialTypeShape.Flags
}
