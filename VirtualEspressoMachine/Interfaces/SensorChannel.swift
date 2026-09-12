//
//  SensorChannel.swift
//  VirtualEspressoMachine
//

import Foundation

/// Interface for an individual sensor feed (e.g. physical BLE, derived flow, static stub).
public protocol SensorChannel: AnyObject, Sendable {
    var key: SensorKey { get }
    var unit: String { get }
    var currentValue: Double? { get }
    var isConnected: Bool { get }
}

/// Registry and lookup bus for all machine sensors.
public protocol SensorArrayProtocol: AnyObject, Sendable {
    func channel(for key: SensorKey) -> (any SensorChannel)?
    subscript(key: SensorKey) -> (any SensorChannel)? { get }
    
    /// Captures a synchronized snapshot across all registered channels
    func captureSnapshot(at timestamp: TimeInterval, state: MachineState) -> MachineFrame
}
