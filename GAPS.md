# Echo Reflection Coverage and Gaps

> Generated against the current public API surface of Echo and a catalog of
> Swift language/runtime features backed by runtime metadata. ABI citations
> reference `swift/ABI/Metadata.h`, `swift/ABI/MetadataValues.h`,
> `swift/ABI/GenericContext.h`, `swift/ABI/ValueWitnessTable.h`,
> `swift/ABI/InvertibleProtocols.h`, `swift/Runtime/Metadata.h`, and
> `swift/Runtime/Casting.h` from the Swift toolchain source tree.

## Summary

Echo provides broad, low-level coverage of Swift's *static* type-metadata and
context-descriptor ABI: it models all 14 metadata kinds, value-witness tables,
context descriptors for every nominal kind, generic contexts, field/protocol
descriptors, conformance descriptors, witness tables, and existential
containers. It exposes the runtime entry points `swift_conformsToProtocol`,
`swift_getTypeName`, `swift_allocBox`, and `swift_allocObject`, plus generic
metadata instantiation via `MetadataAccessFunction`. The headline gaps are all
on the *dynamic/runtime-service* side: Echo has no high-level value reflection
(the stdlib `ReflectionMirror` field/child enumeration), no dynamic-cast API, no
*safe* value-witness operations on arbitrary values, and no resolution of
associated types/conformances despite cataloging the requirement records.

> **Correction (post-review):** an earlier draft listed "type-by-mangled-name"
> as a gap. It is not — Echo already ships
> `TypeMetadata.type(of mangledName:) -> Any.Type?`
> ([`TypeMetadata.swift:141`](Sources/Echo/Metadata/TypeMetadata.swift#L141)),
> a cached, context-aware wrapper over `swift_getTypeByMangledNameInContext`.
> What remains under "Gap #1" is narrower: a *general* demangler (human-readable
> output, arbitrary symbols) and a cleaner public entry point. See Gap #1.

> **Consumer context — Jsum.** The driving consumer of Echo here is Jsum, a
> Mantle-style object mapper that does runtime **creation, mutation, and
> enumeration** of values. That reframes priorities: the *write-side* surface
> (Gap #5 — safe value-witness ops, instance allocation, set-by-offset) is the
> load-bearing capability, not the read-only `ReflectionMirror` wrap (Gap #4).
> Jsum currently hand-rolls the write-side in unsafe pointer code that should
> become first-class Echo API. The "Value" column below is annotated **(Jsum)**
> where a gap is specifically load-bearing for that use case.

It also predates several recent language features — variadic generics
(pack shapes), generic value parameters, typed throws, async/`@Sendable`/global-actor
function flags, `~Copyable`/`~Escapable` (invertible protocols), actors and
distributed actors, accessible-function records, dynamic replacement, and
layout strings — none of which are surfaced even though their backing records
exist in the ABI.

A systemic, easily-overlooked problem cuts across the otherwise well-covered
static surface: the `Flags` structs are consistently *incomplete*. The same
pattern repeats in `ClassMetadata.Flags` (only 3 of the bits and none of the
`TypeContextDescriptorFlags` type-specific bits: actor, default-actor,
vtable, override-table, resilient-superclass-reference-kind),
`ValueWitnessTable.Flags` (missing `IsNonCopyable`/`IsNonBitwiseBorrowable`),
and `FunctionMetadata.Flags` (missing `isAsync`/`isSendable`/`hasGlobalActor`
and the entire `ExtendedFunctionTypeFlags` path). Because these bits gate
modern class/function/value introspection, the coverage gap is wider than a
metadata-kind census suggests.

Finally, several exposed areas are fragile: `isSwiftClass` is marked FIXME, the
`resilientSuperclassRefKind` shift is decoded incorrectly (load-bearing for
resilient-class introspection), `MetadataAccessFunction` has a confirmed
buffer-population bug, and key paths are almost entirely commented out.

## Covered today

- **Metadata kinds (all 14):** class, struct, enum/optional, tuple, function,
  existential, metatype, existential-metatype, ObjC-class-wrapper,
  foreign-class, opaque, heap-local-variable, heap-generic-local-variable,
  error-object — via `reflect`, `reflectClass/Struct/Enum`, and the
  `Metadata`/`TypeMetadata` protocols.
- **Value-witness tables:** layout (`size`, `stride`, `flags`,
  `extraInhabitantCount`) and all 8 copy/destroy/take operations plus
  single-payload and full enum witnesses (`getEnumTag`,
  `destructiveProjectEnumData`, `destructiveInjectEnumTag`). VWT *function calls*
  are reachable through `CEcho` arm64e ptrauth stubs. Note: `Flags` decodes only
  `isPOD`/`isBitwiseTakable`/`hasSpareBits`/`hasEnumWitnesses`/`isValueInline`/`isIncomplete`
  — the newer `IsNonCopyable`/`IsNonBitwiseBorrowable` bits are absent (Gap #6).
- **Context descriptors:** `ContextDescriptor`/`TypeContextDescriptor` plus
  class/struct/enum/protocol/module/extension/anonymous/opaque descriptors,
  including class vtable headers, method descriptors, and override tables. Note:
  the type-specific `TypeContextDescriptorFlags` bits (actor, default-actor,
  vtable, override-table, resilient-superclass-reference-kind, layout-string)
  are not surfaced (Gaps #6, #7).
- **Generic context (static decoding):** parameters, requirements,
  key/extra-argument counts, the type metadata pattern, and the common
  `GenericRequirementKind`s (protocol, sameType, baseClass, layout). The
  `sameConformance` kind and the `TypePack`/`Value` parameter kinds are *not*
  decoded (Gap #10).
- **Fields & instance layout:** `FieldDescriptor`/`FieldRecord` (names, mangled
  type names, reference-storage kind), field-offset vectors, class instance
  size/address-point/alignment.
- **Protocols & conformances:** `ProtocolDescriptor` (requirements, requirement
  signature, associated-type names), `ConformanceDescriptor` + flags,
  `WitnessTable`, and the live conformance check `swift_conformsToProtocol`
  (returns the witness table).
- **Existentials:** `AnyExistentialContainer`/`ExistentialContainer`/`DualExistentialContainer`
  with inline/indirect value projection (classic protocol-composition layout only).
- **Generic metadata instantiation:** `MetadataAccessFunction` callable for 0–N
  generic arguments + witness tables; `MetadataRequest`/`MetadataResponse`/`MetadataState`.
- **Image inspection:** Mach-O and ELF section iteration; enumeration of all
  loaded `protocols` and `types`; builtin metadata via `KnownMetadata.Builtin`.
- **Runtime services:** `swift_getTypeName` (qualified/unqualified),
  `swift_allocBox`, `swift_allocObject`.

## Gaps

Ordered by Value (descending), then Effort (ascending). **(Jsum)** marks gaps
load-bearing for the object-mapping consumer. Rows ~~struck through~~ are already
landed.

| # | Gap | Value | Effort | ABI location |
|---|-----|:-----:|:------:|--------------|
| 5 | **Safe value-witness ops + instance allocation / set-by-offset (promote Jsum's helpers)** | **High (Jsum)** | M | `ValueWitnessTable.h:132-310`; `swift_allocObject`/`swift_allocBox`/`swift_projectBox` |
| 2 | Dynamic cast (`swift_dynamicCast` family) | High (Jsum) | S | `Runtime/Casting.h:40-202` |
| 3 | Associated types & associated conformances | High | M | `Runtime/Metadata.h:387-424` |
| 6 | Class metadata flags: actor / default-actor / vtable / override-table / resilient-superclass-ref-kind | High | S | `MetadataValues.h:1968-2007` |
| 1 | General demangler + public type-by-name ergonomics (*core resolver already exists*) | Med | S | `SwiftDemangle.h` / `Demangling/Demangle.h` (resolver: `TypeMetadata.swift:141`) |
| 4 | ReflectionMirror field/child enumeration (**read-only**; wrap-primary) | Med | M | `Runtime/Reflection.h`, `swift_reflectAny` |
| 7 | Async/throws/Sendable/typed-throws/global-actor function metadata | High | M | `MetadataValues.h:1166-1170, 1289-1348`; `Metadata.h:1529-1708` |
| 8 | Noncopyable (`~Copyable`)/`~Escapable` & invertible protocols | High | M | `ABI/InvertibleProtocols.h`, `MetadataValues.h:177-178` |
| 9 | Generic metadata instantiation ergonomics — *arg-corruption crash **fixed** (`09de17d`); buffer-ownership / witness-count hardening remains* | Med | M | `Runtime/Metadata.h:276-341` |
| 10 | Full generic requirement decoding (sameConformance / layout / pack-shape / value params) | Med | M | `GenericContext.h:120-336`, `MetadataValues.h:2220-2231` |
| 11 | Variadic generics: pack-shape & same-shape classes | Med | M | `GenericContext.h:264-304` |
| 12 | Opaque type resolution (underlying-type realization) | Med | M | `Metadata.h:3396-3475` |
| 13 | Layout-string decoding from type context descriptors | Med | M | `MetadataValues.h:1961-1962, 2053-2055` |
| 14 | Distributed actors & accessible-function records | Med | L | `Metadata.h:5332-5358`, `Runtime/AccessibleFunction.h` |
| 15 | Dynamic replacement records | Low | M | `Metadata.h:5231-5330`, `Runtime/FunctionReplacement.h` |
| 16 | Extended existential type shapes | Low | L | `Metadata.h:2104-2350`, `2449-2493` |

### 1. General demangler + public type-by-name ergonomics — Value: Med, Effort: S

**Already present (correction).** The core capability — resolving a mangled type
name to a live `Any.Type` in the right generic context — *already exists* as
`public func TypeMetadata.type(of mangledName:) -> Any.Type?`
([`TypeMetadata.swift:141`](Sources/Echo/Metadata/TypeMetadata.swift#L141)). It
wraps `swift_getTypeByMangledNameInContext`, threads the descriptor's generic
context + generic arguments, and caches results. Jsum already depends on it for
field-type resolution. So the earlier "can't resolve names" framing was wrong.

**What remains.** Two narrower things: (a) a *general* demangler for
human-readable output and for arbitrary symbols not tied to a `TypeMetadata`'s
context (`swift_demangle` / the `Demangler`); and (b) cleaner public ergonomics
— `type(of:)` takes a raw `UnsafeRawPointer`, so a `String`/`FieldRecord`-based
overload and a context-free resolver would round out the surface.

**ABI location.** Resolver already wired at `TypeMetadata.swift:141`. For
human-readable output, the `swift_demangle_get*` family in
`SwiftDemangle/SwiftDemangle.h` and the `Demangler` in `Demangling/Demangle.h`.

**Effort.** S — thin wrappers plus ergonomic overloads; the hard part (context
substitution callbacks) is already solved.

### 2. Dynamic cast (`swift_dynamicCast` family) — Value: High, Effort: S

**What.** "Is value of type `X` actually a `Y`?" and "open this existential to
its concrete type." Includes `swift_dynamicCast` (general),
`swift_dynamicCastClass[Unconditional]`, and
`swift_dynamicCastMetatype[Unconditional]`.

**Why metadata.** Casting requires walking class hierarchies, checking
conformances, and consulting value-witness tables for opaque values — all
metadata-driven. The Echo survey notes `swift_dynamicCast` exists at the
`CEcho` layer (`Functions.h`) but is deliberately not surfaced in Swift.

**ABI location.** `Runtime/Casting.h:40-45` (general), `54-137` (class),
`174-202` (metatype). Existential opening uses
`ExistentialTypeMetadata::getDynamicType()`/`projectValue()`
(`Metadata.h:1931-2046`).

**Effort.** S — the C entry points already exist; wrap them with safe Swift
signatures that take `Metadata` and return typed results/optionals.

### 3. Associated types & associated conformances — Value: High, Effort: M

**What.** Given a conforming type's witness table and a protocol requirement,
fetch the bound associated type's metadata (`Self.Element`) and the witness
table for an associated conformance (`Self.Element: Comparable`).

**Why metadata.** Associated-type bindings are not stored statically; they are
recovered at runtime by calling accessor witnesses inside the witness table.
Echo already exposes `ProtocolRequirement.Kind.associatedTypeAccessFunction`
and `.associatedConformanceAccessFunction` and reads `associatedTypeNames`, but
provides no call path to actually resolve them.

**ABI location.** `swift_getAssociatedTypeWitness` /
`swift_getAssociatedTypeWitnessRelative` (`Runtime/Metadata.h:387-399`) and
`swift_getAssociatedConformanceWitness` /
`...Relative` (`Runtime/Metadata.h:411-424`). Requires the protocol's
requirement signature (`ProtocolDescriptor.requirementSignature`, already
exposed) to identify the right requirement descriptor.

**Effort.** M — needs correct selection of the requirement descriptor from the
signature and the relative-vs-absolute witness variants.

### 4. ReflectionMirror field/child enumeration of arbitrary values — Value: Med, Effort: M

> **Read-only — lower priority for the Jsum use case.** `swift_reflectionMirror_*`
> returns *copies* of children (`-> Any`); it has no setter and no instance
> allocation, so it cannot serve an object mapper's decode (create + mutate)
> path — the same wall that makes `Swift.Mirror` useless to Jsum. It's a nice
> general read API for Echo's other consumers, but it's largely orthogonal to
> Jsum and ranks below the write-side gaps. **Recommended approach: wrap-primary**
> (re-declare the ~6 `@_silgen_name` SPI functions; the non-generic
> `recursiveChildOffset`/`recursiveChildMetadata` trio needs only `Any.Type` and
> avoids the generic-`<T>` calling-convention subtlety), with a from-scratch
> projector as an optional no-SPI mode later. The one spot the wrap genuinely
> helps even Jsum is **enum payload projection**, where from-scratch is hardest.

**What.** The high-level "give me the named children and their values" surface
the stdlib `Mirror` is built on: count children, get the i-th child's name,
type, and a copy of its value, for any `Any` — including resilient and ObjC
types.

**Why metadata.** This is the single most-requested reflection capability.
While Echo *can* assemble it from field descriptors + field-offset vectors +
value-witness `initializeWithCopy`, the stdlib provides a battle-tested runtime
(`swift_reflectAny` and the `swift_reflectionMirror_*` family) that handles
enums (current case + payload projection), classes with superclass chains, and
edge cases Echo's manual path would miss.

**ABI location.** `Runtime/Reflection.h` (`MirrorWitnessTable`, `Mirror`
struct), `swift_reflectAny`; the `swift_reflectionMirror_count` /
`_subscript` / `_recursiveCount` runtime functions. Echo today exposes the raw
ingredients (`FieldRecord`, `fieldOffsets`, VWT) but no child-projection API.

**Effort.** M — either thin wrappers over the (SPI) reflection-mirror runtime,
or a from-scratch projector using already-exposed field offsets plus mangled-name
resolution from gap #1 (the two pair naturally).

### 5. Safe value-witness ops + instance allocation / set-by-offset — Value: High (Jsum), Effort: M

> **Highest-value gap for the Jsum consumer, and the next thing to build.** This
> is the *write-side* surface an object mapper needs: allocate an instance of a
> runtime-only-known type, set a stored property by offset, and copy/destroy
> values — none of which the read-only `ReflectionMirror` (Gap #4) can do.

**What.** Safe, high-level allocate / copy / move / destroy of a value of a
runtime-only-known type; enum tag get/set; **and instance construction +
set-by-key/offset** for structs, classes, and tuples — exposed as ergonomic
Swift APIs operating on `Metadata` + a buffer, not raw `unsafeBitCast`.

**Promote Jsum's helpers into Echo.** Jsum already implements this whole layer in
unsafe pointer code that belongs in Echo:
`RawPointer.allocateBuffer(for:)` / `storeBytes(of:type:offset:)` /
`copyMemory(from:type:)`
([`PointerExtensions.swift`](file:///Users/tanner/Repos/Jsum/Sources/PointerExtensions.swift)),
`StructMetadata.createInstance(props:)`, `ClassMetadata.createInstance(props:)`
(`swift_allocObject`), `TupleMetadata.createInstance(elements:)`,
`set(value:forKey:pointer:)`, and the `AnyExistentialContainer` box helpers
(`getValueBuffer`, `store(value:)`)
([`EchoExtensions.swift`](file:///Users/tanner/Repos/Jsum/Sources/EchoExtensions.swift)).
Lifting these into Echo as first-class, documented API (e.g.
`TypeMetadata.createInstance(fields:)`, `Metadata.set(_:forKey:in:)`,
`ValueBuffer`/box wrappers) lets Jsum delete its unsafe plumbing and gives every
Echo consumer a supported write surface.

**Why metadata.** The value-witness table is the only way to manipulate a value
whose type isn't known statically. Echo exposes the VWT *structure* and the
function pointers, but direct calls are routed only through `CEcho` arm64e stubs
and require unsafe access; there is no safe, documented Swift surface for "copy
this `Any` into that buffer" or "allocate one of these and populate it."

**ABI location.** `ValueWitnessTable.h:132-229` (copy/destroy),
`234-264` (enum), `279-310` (layout); witness signatures in `ValueWitness.def`.
`swift_allocObject` is already exposed; box helpers
`swift_projectBox`/`swift_deallocBox` are declared in `CEcho`'s `Functions.h`
but commented out in `Functions.swift`.

**Effort.** M — much of the logic is proven in Jsum already; the work is API
design (safe ownership, value-inline vs boxed, retain semantics for class
fields) and re-enabling the box project/dealloc path.

### 6. Class metadata flags: actor / default-actor / vtable / override-table / resilient-superclass-ref-kind — Value: High, Effort: S

**What.** Surface the type-specific `TypeContextDescriptorFlags` bits that
describe a class beyond the three `ClassMetadata.Flags` bits Echo decodes today
(`isSwiftPreStableABI`, `usesSwiftRefCounting`, `hasCustomObjCName`). The
missing bits identify actors (`Class_IsActor`), default actors
(`Class_IsDefaultActor`), whether the descriptor carries a vtable
(`Class_HasVTable`) or override table
(`Class_HasOverrideTable`/`Class_HasDefaultOverrideTable`), and how a resilient
superclass is referenced (`Class_ResilientSuperclassReferenceKind`, a 3-bit
`TypeReferenceKind`).

**Why metadata.** Actor and default-actor introspection — the foundation of any
concurrency-aware reflection — is impossible without bits 7 and 8. The
vtable/override-table bits gate whether the class descriptor even *has* the
trailing method records Echo already models, so reading them blindly is unsafe
on classes that lack them. The resilient-superclass-reference-kind drives how
to safely dereference the superclass relative pointer (direct vs. indirect vs.
symbolic), and Echo currently decodes its shift incorrectly (see Known
fragilities).

**ABI location.** `TypeContextDescriptorFlags`:
`HasLayoutString=4`, `Class_HasDefaultOverrideTable=6`, `Class_IsActor=7`,
`Class_IsDefaultActor=8`, `Class_ResilientSuperclassReferenceKind=9`
(`_width=3`), `Class_AreImmediateMembersNegative=12`,
`Class_HasResilientSuperclass=13`, `Class_HasOverrideTable=14`,
`Class_HasVTable=15` — all at `MetadataValues.h:1968-2007`. The 3-bit
reference-kind value is a `TypeReferenceKind`.

**Effort.** S — these are pure flag accessors over a 16-bit field Echo already
loads; the only nuance is masking the 3-bit reference-kind correctly and mapping
it to `TypeReferenceKind`.

### 7. Async/throws/Sendable/typed-throws/global-actor function metadata — Value: High, Effort: M

**What.** Full modern function-signature reflection: `isAsync`, `isSendable`,
`hasGlobalActor` (and the global-actor type), differentiability, isolation kind,
sending result, and the typed-throws *thrown error type*.

**Why metadata.** `FunctionMetadata` uses a trailing-objects layout whose tail
(parameter flags, differentiability kind, global-actor metadata, *extended*
flags, thrown-error type) is gated by bits in the flags word. Echo's
`FunctionMetadata.Flags` currently decodes only `numParams`, `convention`,
`throws`, `hasParamFlags`, `isEscaping` — it omits `isAsync` (`AsyncMask`),
`isSendable` (`SendableMask`), `hasGlobalActor` (`GlobalActorMask`),
differentiability (`DifferentiableMask`), and the entire
`ExtendedFunctionTypeFlags` path (typed throws, isolation, sending result).

**ABI location.** `FunctionTypeFlags` masks `GlobalActorMask=0x10000000`,
`AsyncMask=0x20000000`, `SendableMask=0x40000000`, `ExtendedFlagsMask=0x80000000`
at `MetadataValues.h:1166-1170`; `ExtendedFunctionTypeFlags`
(`TypedThrowsMask=0x01`, isolation bits, `HasSendingResult`, and an inverted-
protocol set in the high bits) at `MetadataValues.h:1289-1348`;
`TargetFunctionTypeMetadata` trailing layout at `Metadata.h:1529-1708`; builder
`swift_getExtendedFunctionTypeMetadata`.

**Effort.** M — extend flags decoding and correctly walk the conditional
trailing fields (the global-actor and thrown-error pointers move depending on
which flags are set).

### 8. Noncopyable (`~Copyable`)/`~Escapable` & invertible protocols — Value: High, Effort: M

**What.** Report whether a type is non-copyable / non-bitwise-borrowable, and
decode the `InvertibleProtocolSet` constraints on generic parameters and
extended function types.

**Why metadata.** Copyability and escapability are encoded as *inverse*
capabilities: value-witness flag bits on the type, and bitset records in
generic/extended-function contexts. A reflection user inspecting modern Swift
types needs these to avoid illegal copies and to render signatures correctly.
Echo's `ValueWitnessTable.Flags` currently exposes only
`isPOD`/`isBitwiseTakable`/etc. and is missing the newer bits.

**ABI location.** `TargetValueWitnessFlags` `IsNonCopyable=0x00800000`,
`IsNonBitwiseBorrowable=0x01000000` at `MetadataValues.h:177-178` (accessors
`isCopyable()`/`isBitwiseBorrowable()` at `MetadataValues.h:251-271`);
`InvertibleProtocolSet` (Copyable=bit0, Escapable=bit1) in
`ABI/InvertibleProtocols.h`; the inverted-protocol bitset packed into the high
bits of `ExtendedFunctionTypeFlags` (`InvertedProtocolMask`, `MetadataValues.h:1301-1303`)
and the conditional inverted protocols in generic contexts.

**Effort.** M — add the flag accessors (trivial) plus decode the invertible-set
trailing records in generic/extended-function/opaque contexts (the harder part).

### 9. Generic metadata instantiation correctness — Value: High, Effort: M

**What.** Make `MetadataAccessFunction`'s general N-argument path correct and
generally usable for instantiating generic metadata at runtime.

**Why metadata.** Instantiating `Foo<Int, String>` from its descriptor requires
building the key-argument buffer (generic args + witness tables) and calling
the access function — the only runtime path to specialized metadata. Echo has
this, but the general buffer path has a confirmed bug.

**ABI location.** `swift_getGenericMetadata` /
`swift_allocateGenericClass|ValueMetadata` (`Runtime/Metadata.h:276-341`);
generic-argument layout per `getGenericArgumentOffset()`.

**Confirmed bug.** In `Sources/Echo/Metadata/MetadataAccessFunction.swift`,
`createMetadataAccessBuffer` stores `args[0].0` for every key argument instead
of `args[i].0`:

```swift
for i in 0 ..< args.count {
  buffer.storeBytes(of: args[0].0, toByteOffset: ptrSize * i, as: Any.Type.self)
}
```

so any instantiation with 4+ generic arguments writes the first argument N
times. The caller-deallocates contract is also undocumented at the public API.

**Effort.** M — the one-line fix is trivial; making the whole path safe
(ownership of the buffer, witness-table count derivation) is the real work.

### 10. Full generic requirement decoding — Value: Med, Effort: M

**What.** Decode *all* requirement kinds and parameter kinds, not just the
common three. Missing: the `sameConformance` conformance record (kind `0x3`),
`sameShape` (pack-shape) requirements, layout kinds beyond `class`, and generic
*value* parameters.

**Why metadata.** `GenericRequirementDescriptor` stores a union discriminated
by a flags kind; Echo decodes only `sameType`, `protocol`, `baseClass`, and
`layout`, leaving the `sameConformance` union arm opaque. Likewise
`GenericParamKind` exposes only `Type` (0x0), missing `TypePack` (0x1) and
`Value` (0x2).

**ABI location.** `GenericRequirementDescriptor` / `GenericRequirementFlags`
(`GenericContext.h:120-260`); `GenericParamKind` (`Type=0`, `TypePack=1`,
`Value=2`, `MetadataValues.h:2220-2231`); `GenericParamDescriptor`
(`MetadataValues.h:2233-2284`); generic value params at `GenericContext.h:326-336`.

**Effort.** M — add the missing union arms and the value/pack parameter kinds;
mostly mechanical once the flag definitions are mirrored.

### 11. Variadic generics: pack-shape & same-shape classes — Value: Med, Effort: M

**What.** Surface parameter packs (`each T`), their pack-shape descriptors, and
the same-shape equivalence classes that relate two packs of equal length.

**Why metadata.** Pack shapes are stored as a `GenericPackShapeHeader` +
`GenericPackShapeDescriptor` array trailing the generic context; each descriptor
carries a `Kind` (Metadata/WitnessTable), a pack index into the generic-args
array, and a `ShapeClass` equivalence ID. Without decoding these, a reflector
cannot tell which generic arguments are packs or how long they are.

**ABI location.** `GenericPackShapeHeader` / `GenericPackShapeDescriptor`
(`GenericContext.h:264-304`); pack flags via
`GenericParamKind::TypePack` (`MetadataValues.h:2225`) and
`GenericRequirementFlags.isPackRequirement`.

**Effort.** M — depends on gap #10's flag work; adds trailing-record walking for
the pack-shape array.

### 12. Opaque type resolution — Value: Med, Effort: M

**What.** Turn an opaque result type (`some P`) into the concrete underlying
type at runtime.

**Why metadata.** `OpaqueDescriptor` stores the underlying types only as
mangled names plus a generic signature; Echo already reads
`underlyingTypeMangledNames` but cannot realize them into metadata.

**ABI location.** `TargetOpaqueTypeDescriptor` (`Metadata.h:3396-3475`);
realization needs the type-by-mangled-name machinery from gap #1 fed with the
opaque descriptor's generic context.

**Effort.** M — primarily a consumer of gap #1; the descriptor side is already
exposed.

### 13. Layout-string decoding from type context descriptors — Value: Med, Effort: M

**What.** Read and decode the layout string a type context descriptor may point
to when the `HasLayoutString` flag is set — the compact byte-coded description
of a type's in-memory layout used by the runtime for value operations on
resilient/generic types.

**Why metadata.** `TypeContextDescriptorFlags.HasLayoutString` (bit 4) signals
that the descriptor carries a trailing pointer to layout metadata. Echo decodes
none of this today: it neither reports the flag nor exposes any mechanism to
locate or interpret the layout string. Surfacing it gives consumers an
alternative, runtime-blessed view of field layout that complements the
field-offset-vector path, and is required to fully reason about types built
with layout-string codegen.

**ABI location.** `HasLayoutString=4` in `TypeContextDescriptorFlags`
(`MetadataValues.h:1961-1962`); the layout-string presence/handling at
`MetadataValues.h:2053-2055`. Decoding the byte format itself follows the
runtime's layout-string interpreter.

**Effort.** M — the flag accessor is trivial (and pairs with Gap #6), but
locating the trailing pointer and decoding the layout-string byte format is
nontrivial and ABI-version-sensitive.

### 14. Distributed actors & accessible-function records — Value: Med, Effort: L

**What.** Enumerate runtime-discoverable (distributed/remote-invocable)
functions and resolve them by name, plus recognize distributed-actor metadata
(building on the actor flags from Gap #6).

**Why metadata.** `AccessibleFunctionRecord` lives in its own metadata section
and carries the function name, generic environment, mangled function type, and
the implementation pointer, with an `isDistributed()` flag. This is how remote
invocation reconstructs a callee from a string key. Distributed actors are first
recognized via the `Class_IsActor`/`Class_IsDefaultActor` descriptor flags (Gap
#6), then by their accessible-function records. Echo has section-iteration
infrastructure but no record type or registration for accessible functions.

**ABI location.** `TargetAccessibleFunctionRecord` (`Metadata.h:5332-5358`);
`Runtime/AccessibleFunction.h` (`swift_findAccessibleFunction`,
`AccessibleFunctionFlags`).

**Effort.** L — new record type, a new section registration path
(analogous to `registerProtocols`), and generic-environment decoding.

### 15. Dynamic replacement records — Value: Low, Effort: M

**What.** Decode the `@_dynamicReplacement` chains: replacement keys,
descriptors, and the enable/disable scope.

**Why metadata.** Replacement is implemented as a linked list of
`DynamicReplacementChainEntry` keyed by `DynamicReplacementKey`; testing/mocking
frameworks introspect and toggle these. Echo exposes none of it.

**ABI location.** `Metadata.h:5231-5330`; `Runtime/FunctionReplacement.h`.

**Effort.** M — new descriptor types and the chain-walking logic; lower demand
than the type-reflection gaps.

### 16. Extended existential type shapes — Value: Low, Effort: L

**What.** Generalized existentials (`any P<Int>`, constrained protocol
compositions) with explicit shape descriptors and generalization arguments.

**Why metadata.** These use a separate `TargetExtendedExistentialTypeShape`
with its own generalization/requirement signatures and suggested value
witnesses; Echo's `ExistentialMetadata` only models the classic
protocol-composition layout.

**ABI location.** `TargetExtendedExistentialTypeShape` (`Metadata.h:2104-2350`)
and `TargetExtendedExistentialTypeMetadata` (`Metadata.h:2449-2493`).

**Effort.** L — a structurally new metadata kind with nontrivial trailing
layout; comparatively rare in practice.

## Known fragilities

These are bugs or stability hazards in code Echo already ships.

- **`ClassMetadata.isSwiftClass` is FIXME and heuristic.**
  `Sources/Echo/Metadata/ClassMetadata.swift:71-90` masks the rodata pointer
  with `0x1` (non-Darwin / older) or `0x2` (Darwin ≥ 10.14.4). The in-source
  comment states it "doesn't take into account what's on disk and what's
  currently being run," so the result can be wrong across mixed runtime
  scenarios.
- **✅ FIXED — `resilientSuperclassRefKind` mis-shift (was HIGH severity).**
  Masked with `0xE00` but never shifted `>> 9`, so any non-direct reference kind
  trapped the force-unwrap — a hard crash on any class with an indirectly-
  referenced (cross-module) resilient superclass. Fixed in commit `eee06b8` with
  a regression test reflecting `Boat3<String>: JSONEncoder`.
- **✅ FIXED — `MetadataAccessFunction` buffer bug.**
  `createMetadataAccessBuffer` wrote `args[0].0` for every key argument instead
  of `args[i].0`, corrupting any buffer-path generic instantiation (silent: the
  first type argument was written into every position). Fixed in commit
  `09de17d` with a regression test instantiating `FooBaz2<Int, Double>`. The
  buffer is still caller-deallocated; documenting/owning that contract remains
  (Gap #9).
- **Systemic `Flags`-struct incompleteness.** The same omission recurs across
  three flag structs and is wider than any single metadata kind: `ClassMetadata.Flags`
  exposes 3 bits and none of the type-specific `TypeContextDescriptorFlags`
  (actor/default-actor/vtable/override-table/resilient-ref-kind/layout-string —
  Gaps #6, #13); `ValueWitnessTable.Flags` omits
  `IsNonCopyable`/`IsNonBitwiseBorrowable` (Gap #8); `FunctionMetadata.Flags`
  omits `isAsync`/`isSendable`/`hasGlobalActor`/differentiability and all of
  `ExtendedFunctionTypeFlags` (Gap #7). Because these bits gate modern
  introspection and, in the class/function cases, the *presence* of trailing
  records, the practical coverage gap is larger than a metadata-kind census
  suggests.
- **ABI-version-pinned / "Unstable" structures.** The survey marks
  `TupleMetadata`, `FunctionMetadata`, `ExistentialMetadata`, `MetatypeMetadata`,
  `ExistentialMetatypeMetadata`, `HeapLocalVariableMetadata`, and
  `HeapGenericLocalVariableMetadata` as relying on layouts the Swift team
  considers unstable; they may shift between toolchains.
- **Platform-dependent tuple element offset.**
  `TupleMetadata.swift:96-104` reads the element offset as `Int` on Darwin but
  `UInt32` (with padding) on Linux — a hard-coded layout difference.
- **`ConformanceDescriptor.objcClass` weak-linking.** Only available under
  `canImport(ObjectiveC)`; weak-linked classes return `nil`
  (`Runtime/ConformanceDescriptor.swift:71-72`).
- **Null-safety on optional descriptors.** Recent commits
  (`b0155b5`, `f3f815d`, `b204531`) show `ClassMetadata.descriptor` was being
  force-unwrapped and is being hardened; similar nullable relative pointers
  (resilient superclass, foreign/singleton init) deserve an audit.
- **`ValueWitnessTable.Flags.isIncomplete` exposed.** Surfacing incomplete
  metadata invites use of metadata that isn't safe to read; callers should gate
  on `MetadataState` first.
- **Key paths almost entirely commented out.** `Runtime/KeyPaths.swift:9-278`
  is mostly disabled; only `KeyPathObject`/`KeyPathBufferHeader`/`KeyPathComponent`
  shells remain. Key-path reflection is effectively non-functional.
- **VWT calls require unsafe access.** Direct value-witness invocation is only
  reachable via `CEcho` arm64e ptrauth stubs; there is no safe Swift surface
  (see Gap #5).
- **🔴 `AnyExistentialContainer.projectValue()` mislocates out-of-line values
  (NEW, HIGH severity).** For values stored *inline* it is correct, but for
  out-of-line (boxed) values — types larger than the 3-word inline buffer — it
  returns a pointer that is not the value: reading back a boxed value through
  `container(for:).projectValue()` yields garbage
  (`Sources/Echo/Runtime/ExistentialContainer.swift:50-69`). Discovered while
  building the Gap #5 write surface: `StructMetadata.createInstance(fields:)`
  works (it writes into a `swift_allocBox` buffer and is read back via the
  runtime's own projection), but a value-read round-trip of a boxed value does
  not. This is foundational — `container(for:)` and `projectValue()` underpin
  most value access (including Jsum's), so it blocks the read half of Gap #5 and
  affects construction whenever a *field value* is itself out-of-line. Likely a
  box header-size / value-offset miscalculation versus the current Swift runtime
  box layout. Root-cause and fix before exposing `value(at:)`/`value(forKey:)`.

## Suggested roadmap

A phased ordering that front-loads the highest-value, lowest-effort work and
respects dependencies (later phases consume earlier ones). **Re-ordered for the
Jsum consumer:** the write-side (Gap #5) is pulled forward, and Gap #1 is
demoted since its core resolver already exists.

0. **✅ Phase 0 — fix what's already shipped (DONE).**
   Landed the `MetadataAccessFunction` `args[i].0` fix (`09de17d`) and the
   `resilientSuperclassRefKind` shift fix (`eee06b8`), each with a regression
   test proven to fail on the old code. (Earlier in this effort: a
   `__swift5_types` decode crash and the `ConformanceDescriptor` null-safety fix
   also landed.) Remaining tail: document `MetadataAccessFunction`'s buffer-
   ownership contract (Gap #9) and re-audit other nullable relative pointers.

1. **▶ Phase 1 — write-side surface / promote Jsum's helpers (Gap #5). ← NEXT.**
   The load-bearing capability for Jsum and the marquee gap: safe value-witness
   ops (copy/destroy/enum tag), instance allocation, and set-by-key/offset for
   structs/classes/tuples. Lift Jsum's proven-but-unsafe `PointerExtensions` /
   `EchoExtensions` write helpers into first-class Echo API. Lets Jsum delete its
   plumbing and gives every consumer a supported write surface.

2. **Phase 2 — dynamic cast (Gap #2).**
   The C entry points already exist at the `CEcho` layer; wrapping them is small
   and unlocks "does X conform / is X a Y / open this existential," which pairs
   naturally with the already-exposed `swift_conformsToProtocol`. Also useful to
   Jsum (it currently hand-rolls casts via `_openExistential`).

3. **Phase 3 — flag-struct completeness (Gaps #6, #8; flag halves of #7, #13).**
   Decode the missing bits across `ClassMetadata.Flags` (actor/default-actor/
   vtable/override-table/resilient-ref-kind, plus the `HasLayoutString` flag),
   `ValueWitnessTable.Flags` (`~Copyable`/`~Escapable`), and the
   `FunctionMetadata.Flags`/`ExtendedFunctionTypeFlags` bits. Pure accessors over
   fields Echo already loads — small effort, high value; closes the systemic
   `Flags`-incompleteness pattern in one sweep.

4. **Phase 4 — demangling & public type-by-name ergonomics (Gap #1).**
   The core resolver already exists (`TypeMetadata.type(of:)`); this phase adds a
   general `swift_demangle` wrapper and `String`/context-free overloads. Small.

5. **Phase 5 — ReflectionMirror read surface (Gap #4).**
   Wrap-primary; a nice general read API but read-only, so it ranks below the
   write-side. Optionally adopt its enum projection inside Jsum's encode path.

6. **Phase 6 — associated types & conformances (Gap #3).**
   With witness-table access and requirement signatures already exposed, add the
   `swift_getAssociatedType/ConformanceWitness` calls. Completes
   protocol-level reflection.

7. **Phase 7 — modern function & type semantics, trailing layout (Gaps #7, #8 tails).**
   Having decoded the gating flags in Phase 3, walk the conditional trailing
   fields: global-actor metadata and the typed-throws thrown-error type in
   `FunctionMetadata`, and the invertible-protocol trailing records in
   generic/extended-function/opaque contexts. No new runtime calls — high value
   for current-era Swift.

8. **Phase 8 — generics completeness (Gaps #10, #11, #12).**
   Finish requirement-union decoding (`sameConformance`), value/pack parameters,
   pack-shape/same-shape classes, and opaque-type realization (the latter reuses
   Phase 4). These compound: do #10 first, then #11, then #12.

9. **Phase 9 — layout strings (Gap #13).**
   With the `HasLayoutString` flag already surfaced in Phase 3, locate the
   trailing layout-string pointer and decode the byte format. Schedule after the
   generics work since it shares trailing-object decoding infrastructure and is
   ABI-version-sensitive.

10. **Phase 10 — dynamic/distributed surface (Gaps #14, #15, #16).**
    Accessible-function records and distributed-actor discovery (building on the
    actor flags from Phase 3), dynamic-replacement chains, and extended
    existential shapes. Lower demand and higher effort; schedule last, once the
    section-registration and trailing-object infrastructure from earlier phases
    is mature.
