//
//  MachineProtocol.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/2/26.
//

import Foundation
import MeticulousProfile

/// The master coordinator representing the digital twin of the espresso machine.
@MainActor
public protocol MachineProtocol: AnyObject {
    var state: MachineState { get }
    var currentFrame: MachineFrame { get }
    var sensors: any SensorArrayProtocol { get }
    
    // MARK: - Recipe & Configuration Subsystems
    var profileStore: ProfileStore { get }
    var activeProfile: Profile? { get }
    var config: MachineConfig { get } // 👈 Unified, extensible configuration
    
    // Macro Workflow Transitions
    func setToMachineReady()
    func selectProfile(_ profile: Profile)
    func setToShotReady()
    func startExtraction()
    func endExtraction()
    func setToCleanupComplete()
    func abort()
}
