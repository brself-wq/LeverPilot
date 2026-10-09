//
//  SettingsStore.swift
//  LeverPilot
//

import Foundation
import Observation

@Observable
@MainActor
public final class SettingsStore {
    
    // MARK: - Brew Defaults
    public var defaultDose: Double {
        didSet { defaults.set(defaultDose, forKey: "settings.defaultDose") }
    }
    
    // MARK: - Extraction & Watchdog Thresholds
    public var autoStartPressure: Double {
        didSet { defaults.set(autoStartPressure, forKey: "settings.autoStartPressure") }
    }
    
    public var deadFlowThreshold: Double {
        didSet { defaults.set(deadFlowThreshold, forKey: "settings.deadFlowThreshold") }
    }
    
    public var deadFlowSustainDuration: Double {
        didSet { defaults.set(deadFlowSustainDuration, forKey: "settings.deadFlowSustainDuration") }
    }
    
    // MARK: - Meticulous Machine Emulation Server
    public var enableMeticulousServer: Bool {
        didSet { defaults.set(enableMeticulousServer, forKey: "settings.enableMeticulousServer") }
    }
    
    public var meticulousPort: Int {
        didSet { defaults.set(meticulousPort, forKey: "settings.meticulousPort") }
    }
    
    public var traceLogging: Bool {
        didSet { defaults.set(traceLogging, forKey: "settings.traceLogging") }
    }
    
    // MARK: - Cockpit & Display
    public var keepDisplayAwake: Bool {
        didSet { defaults.set(keepDisplayAwake, forKey: "settings.keepDisplayAwake") }
    }
    
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        self.defaultDose = defaults.object(forKey: "settings.defaultDose") as? Double ?? 18.0
        self.autoStartPressure = defaults.object(forKey: "settings.autoStartPressure") as? Double ?? 0.5
        self.deadFlowThreshold = defaults.object(forKey: "settings.deadFlowThreshold") as? Double ?? 0.15
        self.deadFlowSustainDuration = defaults.object(forKey: "settings.deadFlowSustainDuration") as? Double ?? 2.0
        self.enableMeticulousServer = defaults.object(forKey: "settings.enableMeticulousServer") as? Bool ?? true
        self.meticulousPort = defaults.object(forKey: "settings.meticulousPort") as? Int ?? 8080
        self.traceLogging = defaults.bool(forKey: "settings.traceLogging")
        self.keepDisplayAwake = defaults.object(forKey: "settings.keepDisplayAwake") as? Bool ?? true
    }

    public func resetToDefaults() {
        defaultDose = 18.0
        autoStartPressure = 0.5
        deadFlowThreshold = 0.15
        deadFlowSustainDuration = 2.0
        enableMeticulousServer = true
        meticulousPort = 8080
        traceLogging = false
        keepDisplayAwake = true
    }
}
