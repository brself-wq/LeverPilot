//
//  PreFlightValidator.swift
//  VirtualEspressoMachine
//

import Foundation
import MeticulousProfile
import EspressoBLE

public struct PreFlightValidator: Sendable {
    
    /// Evaluates whether all conditions are satisfied to transition from `.idle` to `.armed`.
    /// - Parameters:
    ///   - profile: The in-memory candidate profile.
    ///   - bleManager: The live Bluetooth peripheral manager.
    ///   - primedScenario: An optional mock scenario chosen for desk testing.
    /// - Returns: An array of issues found. If empty, the machine is ready to arm.
    public static func evaluate(
        profile: Profile?,
        bleManager: EspressoBLEManager,
        primedScenario: ShotRecord? = nil
    ) -> [PreFlightIssue] {
        var issues: [PreFlightIssue] = []
        
        // 1. Profile Integrity Checks
        guard let profile else {
            issues.append(.noProfileSelected)
            return issues
        }
        
        if profile.stages.isEmpty {
            issues.append(.profileHasNoStages)
        }
        
        // 2. Telemetry & Bluetooth Interlocks
        // If an explicit debug mock scenario is primed, it synthesizes the telemetry stream
        // and satisfies the hardware requirement without physical BLE peripherals.
        if primedScenario == nil {
            switch bleManager.centralState {
            case .unauthorized:
                issues.append(.bluetoothUnauthorized)
            case .poweredOff:
                issues.append(.bluetoothPoweredOff)
            case .unsupported:
                issues.append(.bluetoothUnsupported)
            case .unknown, .resetting:
                if !bleManager.isBluetoothReady {
                    issues.append(.bluetoothPoweredOff)
                }
            case .poweredOn:
                break
            }
            
            if bleManager.slots[.scale]?.isConnected != true {
                issues.append(.scaleDisconnected)
            }
            if bleManager.slots[.pressure]?.isConnected != true {
                issues.append(.pressureDisconnected)
            }
        }
        
        return issues
    }
}