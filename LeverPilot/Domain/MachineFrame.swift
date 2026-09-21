//
//  MachineFrame.swift
//  VirtualEspressoMachine
//

import Foundation

/// An immutable, time-indexed snapshot of the entire virtual machine state.
public nonisolated struct MachineFrame: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: TimeInterval     // Elapsed extraction time in seconds (0.0 if not extracting)
    public let absoluteTime: Date          // System wall-clock time
    public let state: MachineState
    
    /// Raw sensor readings keyed by SensorKey
    public let readings: [SensorKey: Double]
    
    /// Telemetry channel health flags (ADR-009)
    public let isScaleStale: Bool
    public let isPressureStale: Bool
    
    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval = 0.0,
        absoluteTime: Date = Date(),
        state: MachineState,
        readings: [SensorKey: Double] = [:],
        isScaleStale: Bool = false,
        isPressureStale: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.absoluteTime = absoluteTime
        self.state = state
        self.readings = readings
        self.isScaleStale = isScaleStale
        self.isPressureStale = isPressureStale
    }
    
    /// Typed lookup: `frame[.pressure]`
    public subscript(key: SensorKey) -> Double? {
        readings[key]
    }
    
    /// Dynamic string lookup matching Meticulous triggers: `frame[trigger.type]`
    public subscript(dynamicKey: String) -> Double? {
        readings[SensorKey(fromExternalKey: dynamicKey)]
    }
}
