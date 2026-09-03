//
//  MachineState.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/2/26.
//

import Foundation

/// The macro workflow states of the espresso machine and barista session.
public enum MachineState: String, Codable, Sendable, CaseIterable {
    /// Machine preheated and idle; ready for bean prep or profile selection
    case ready
    
    /// Profile chosen and armed in the runner
    case profileSelected
    
    /// Portafilter locked, water chamber filled, cup placed; ready for extraction
    case shotReady
    
    /// Active extraction underway; Profile Runner is actively driving the HUD
    case extracting
    
    /// Extraction completed (lever at rest, cutoff reached, or yield met)
    case shotEnded
    
    /// Purging water, knocking puck, preparing for the next shot
    case cleaning
    
    /// Quick convenience check
    public var isExtracting: Bool { self == .extracting }
}
