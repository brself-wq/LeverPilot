//
//  SensorKey.swift
//  VirtualEspressoMachine
//

import Foundation

/// Canonical, strongly-typed sensor channels recognized by the Virtual Espresso Machine.
public nonisolated enum SensorKey: String, Codable, Sendable, CaseIterable, CustomStringConvertible {
    // Standard Meticulous Channels
    case weight
    case pressure
    case flow
    case time
    case power
    case pistonPosition = "piston_position"
    case userInteraction = "user_interaction"
    
    // Extended / Decent Channels
    case volume
    case temperature
    
    // Fallback for unrecognized external schema keys
    case unknown
    
    public var description: String { rawValue }
    
    /// Boundary parser: safely maps incoming strings from external profiles (e.g. Meticulous JSON) to domain cases
    public init(fromExternalKey key: String) {
        self = SensorKey(rawValue: key.lowercased()) ?? .unknown
    }
}
