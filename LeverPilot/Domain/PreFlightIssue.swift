//
//  PreFlightIssue.swift
//  LeverPilot
//

import Foundation

public enum PreFlightIssue: Sendable, Equatable, CustomStringConvertible {
    case noProfileSelected
    case profileHasNoStages
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case scaleDisconnected
    case pressureDisconnected
    
    public var description: String {
        switch self {
        case .noProfileSelected:
            return "No profile selected."
        case .profileHasNoStages:
            return "Selected profile contains no stages."
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off. Enable Bluetooth in Control Center or Settings."
        case .bluetoothUnauthorized:
            return "Bluetooth permission is denied. Allow Bluetooth access in Settings."
        case .bluetoothUnsupported:
            return "Bluetooth Low Energy is unsupported on this device."
        case .scaleDisconnected:
            return "Scale is not connected."
        case .pressureDisconnected:
            return "Pressure device is not connected."
        }
    }
}

