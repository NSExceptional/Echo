//
//  ImageInspection.swift
//  Echo
//
//  Created by Alejandro Alonso
//  Copyright © 2021 Alejandro Alonso. All rights reserved.
//

import Foundation

#if canImport(MachO)
import MachO
#elseif canImport(Glibc)
import Glibc
#endif

#if os(Linux)
import CEcho
#endif

//===----------------------------------------------------------------------===//
// __swift5_protos/swift5_protocols
//===----------------------------------------------------------------------===//

/// The list of all protocols this program has loaded.
///
/// NOTE: This list is populated once before the program starts with all of
///       the protocols that are statically know at compile time. If you
///       are attempting to load libraries dynamically at runtime, this list
///       will update automatically, so make sure if you need up to date
///       information on these protocols, fetch this often. Example:
///
///       var protocols = Echo.protocols
///       loadPlugin(...)
///       // protocols is now outdated! Refresh it by calling this again.
///       protocols = Echo.protocols
public var protocols: [ProtocolDescriptor] {
  #if os(Linux)
  iterateSharedObjects()
  #endif
  
  let protos = protocolLock.withLock {
    _protocols
  }
  
  return Array(unsafeUninitializedCapacity: protos.count) {
    for (i, proto) in protos.enumerated() {
      $0[i] = ProtocolDescriptor(ptr: proto)
    }
    
    $1 = protos.count
  }
}

let protocolLock = NSLock()
var _protocols = Set<UnsafeRawPointer>()

@_cdecl("registerProtocols")
public func registerProtocols(section: UnsafeRawPointer, size: Int) {
  for i in 0 ..< size / 4 {
    let start = section.offset(of: i, as: Int32.self)
    let ptr = start.relativeDirectAddress(as: _ProtocolDescriptor.self)
    
    _ = protocolLock.withLock {
      _protocols.insert(ptr)
    }
  }
}

//===----------------------------------------------------------------------===//
// __swift5_proto/swift5_protocol_conformances
//===----------------------------------------------------------------------===//

let conformanceLock = NSLock()
var conformances = [UnsafeRawPointer: [ConformanceDescriptor]]()

@_cdecl("registerProtocolConformances")
public func registerProtocolConformances(section: UnsafeRawPointer, size: Int) {
  for i in 0 ..< size / 4 {
    let start = section.offset(of: i, as: Int32.self)
    let ptr = start.relativeDirectAddress(as: _ConformanceDescriptor.self)
    let conformance = ConformanceDescriptor(ptr: ptr)
    
    #if canImport(ObjectiveC)
    if let objcClass = conformance.objcClass {
      conformanceLock.withLock {
        conformances[objcClass.ptr, default: []].append(conformance)
      }
      continue
    }
    #endif
    
    if let descriptor = conformance.contextDescriptor {
      conformanceLock.withLock {
        conformances[descriptor.ptr, default: []].append(conformance)
      }
    }
  }
}

//===----------------------------------------------------------------------===//
// __swift5_types/swift5_type_metadata
//===----------------------------------------------------------------------===//

/// The list of all protocols this program has loaded.
///
/// NOTE: This list is populated once before the program starts with all of
///       the protocols that are statically know at compile time. If you
///       are attempting to load libraries dynamically at runtime, this list
///       will update automatically, so make sure if you need up to date
///       information on these protocols, fetch this often. Example:
///
///       var protocols = Echo.protocols
///       loadPlugin(...)
///       // protocols is now outdated! Refresh it by calling this again.
///       protocols = Echo.protocols
public var types: [ContextDescriptor] {
  #if os(Linux)
  iterateSharedObjects()
  #endif
  
  let types = typeLock.withLock {
    _types
  }
  
  var result = [ContextDescriptor]()
  result.reserveCapacity(types.count)
  
  for type in types {
    result.append(getContextDescriptor(at: type))
  }
  
  return result
}

let typeLock = NSLock()
var _types = Set<UnsafeRawPointer>()

@_cdecl("registerTypeMetadata")
public func registerTypeMetadata(section: UnsafeRawPointer, size: Int) {
  for i in 0 ..< size / 4 {
    let start = section.offset(of: i, as: Int32.self)

    // Each record is a RelativeDirectPointerIntPair<ContextDescriptor,
    // TypeReferenceKind>: the low 2 bits of the relative offset encode the
    // reference kind and must be masked off before resolving the pointer.
    // Records whose kind is an indirect reference point at a GOT slot that
    // holds the real descriptor, and ObjC class references never appear here.
    let raw = Int(start.load(as: Int32.self))
    let pointerOffset = raw & ~0x3

    // A zero offset is a null/padding record; skip it.
    guard pointerOffset != 0 else {
      continue
    }

    let addr = start + pointerOffset
    let ptr: UnsafeRawPointer

    switch TypeReferenceKind(rawValue: UInt16(raw & 0x3)) {
    case .directTypeDescriptor:
      ptr = addr
    case .indirectTypeDescriptor:
      ptr = addr.load(as: UnsafeRawPointer.self)
    default:
      // .directObjCClass / .indirectObjCClass are never emitted into this list.
      continue
    }

    _ = typeLock.withLock {
      _types.insert(ptr)
    }
  }
}

//===----------------------------------------------------------------------===//
// Mach-O Image Inspection
//===----------------------------------------------------------------------===//

#if canImport(MachO)

#if arch(x86_64) || arch(arm64)
typealias mach_header_platform = mach_header_64
#else
typealias mach_header_platform = mach_header
#endif

@_cdecl("lookupSection")
public func lookupSection(
  _ header: UnsafePointer<mach_header>?,
  segment: UnsafePointer<CChar>?,
  section: UnsafePointer<CChar>?,
  do handler: @convention(c) (UnsafeRawPointer, Int) -> ()
) {
  guard let header = header else {
    return
  }
  
  var size: UInt = 0
  
  let section = header.withMemoryRebound(
    to: mach_header_platform.self,
    capacity: 1
  ) {
    getsectiondata($0, segment, section, &size)
  }
  
  guard section != nil else {
    return
  }
  
  handler(section!, Int(size))
}

#endif

//===----------------------------------------------------------------------===//
// ELF Image Inspection
//===----------------------------------------------------------------------===//

#if os(Linux)

let sharedObjectLock = NSLock()
var sharedObjects = Set<String>()

@_cdecl("cacheSharedObject")
func cacheSharedObject(cString: UnsafePointer<CChar>) -> Bool {
  let str = String(cString: cString)
  
  let entry = sharedObjectLock.withLock {
    sharedObjects.insert(str)
  }
  
  return entry.inserted
}

#endif
