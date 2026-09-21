//
//  MachineState.swift
//  VirtualEspressoMachine
//

import Foundation

/// Formal finite state machine (FSM) representing the operational lifecycle
/// of the espresso machine and digital twin copilot.
public enum MachineState: String, Sendable, Codable, CaseIterable {
    /// Machine idle; at rest, no profile armed
    case idle
    
    /// Profile loaded; telemetry observer armed and waiting for physical lever pull
    case armed
    
    /// Active extraction underway; real-time OEPF curve steering is driving the HUD
    case extracting
    
    /// Extraction completed (lever at rest, cutoff reached, or yield target met)
    case shotEnded
    
    /// Chamber purging / wastewater expulsion routine
    case purging
    
    /// Safety cutoff, stall, sensor disconnection, or fatal profile failure
    case error
    
    /// Quick convenience check
    public var isExtracting: Bool { self == .extracting }
}
