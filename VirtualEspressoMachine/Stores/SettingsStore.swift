//
//  SettingsStore.swift
//  VirtualEspressoMachine
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
    
    // MARK: - Network & Emulation Server
    public var meticulousPort: Int {
        didSet { defaults.set(meticulousPort, forKey: "settings.meticulousPort") }
    }
    
    public var verboseServerLogging: Bool {
        didSet { defaults.set(verboseServerLogging, forKey: "settings.verboseServerLogging") }
    }
    
    // MARK: - HUD Dynamics
    public var chartWindowSpan: Double {
        didSet { defaults.set(chartWindowSpan, forKey: "settings.chartWindowSpan") }
    }
    
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        self.defaultDose = defaults.object(forKey: "settings.defaultDose") as? Double ?? 18.0
        self.autoStartPressure = defaults.object(forKey: "settings.autoStartPressure") as? Double ?? 0.5
        self.deadFlowThreshold = defaults.object(forKey: "settings.deadFlowThreshold") as? Double ?? 0.15
        self.deadFlowSustainDuration = defaults.object(forKey: "settings.deadFlowSustainDuration") as? Double ?? 2.0
        self.meticulousPort = defaults.object(forKey: "settings.meticulousPort") as? Int ?? 8080
        self.verboseServerLogging = defaults.bool(forKey: "settings.verboseServerLogging")
        self.chartWindowSpan = defaults.object(forKey: "settings.chartWindowSpan") as? Double ?? 25.0
    }

    public func resetToDefaults() {
        defaultDose = 18.0
        autoStartPressure = 0.5
        deadFlowThreshold = 0.15
        deadFlowSustainDuration = 2.0
        meticulousPort = 8080
        verboseServerLogging = false
        chartWindowSpan = 25.0
    }
}
