//
//  TelemetryProvider.swift
//  VirtualEspressoMachine
//

import Foundation
import MeticulousProfile

/// Standard contract for any telemetry source (Scenario Replay or Live CoreBluetooth).
public protocol TelemetryProvider: AnyObject, Sendable {
    /// An asynchronous stream emitting consecutive machine frames.
    var frames: AsyncStream<MachineFrame> { get }
}
