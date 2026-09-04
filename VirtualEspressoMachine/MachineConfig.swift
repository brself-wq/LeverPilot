//
//  MachineConfig.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/4/26.
//

import Foundation

// MARK: - Comparison Operator

public enum TriggerComparison: String, Sendable, Codable, Equatable {
    case greaterThanOrEqual = ">="
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case lessThan = "<"
    
    public func evaluate(_ actual: Double, against target: Double) -> Bool {
        switch self {
        case .greaterThanOrEqual: return actual >= target
        case .lessThanOrEqual:    return actual <= target
        case .greaterThan:         return actual > target
        case .lessThan:            return actual < target
        }
    }
}

// MARK: - Generic Sensor Trigger Rule

/// An abstract condition evaluated against any sensor channel on the machine.
public nonisolated struct TriggerRule: Sendable, Codable, Equatable {
    public var sensor: SensorKey
    public var comparison: TriggerComparison
    public var threshold: Double
    
    public init(sensor: SensorKey, comparison: TriggerComparison = .greaterThanOrEqual, threshold: Double) {
        self.sensor = sensor
        self.comparison = comparison
        self.threshold = threshold
    }
    
    /// Evaluates this rule against a live machine frame
    public func isSatisfied(by frame: MachineFrame) -> Bool {
        guard let actual = frame[sensor] else { return false }
        return comparison.evaluate(actual, against: threshold)
    }
}

// MARK: - Auto-Stop Configuration (Beanconqueror Lifecycle)

public nonisolated struct AutoStopConfig: Sendable, Codable, Equatable {
    /// Preconditions that must ALL be met before dead-flow checks activate (e.g. time >= 5s, weight >= 5g)
    public var preconditions: [TriggerRule]
    
    /// The rule defining "dead flow" (e.g. flow <= 0.15 mL/s)
    public var cutoffRule: TriggerRule
    
    /// Seconds the dead-flow rule must be continuously sustained before ending the shot
    public var sustainDuration: TimeInterval
    
    /// Seconds trimmed from the final shot record to account for the sustain lag
    public var trimTailDuration: TimeInterval
    
    public init(
        preconditions: [TriggerRule] = [
            TriggerRule(sensor: .time, comparison: .greaterThanOrEqual, threshold: 5.0),
            TriggerRule(sensor: .weight, comparison: .greaterThanOrEqual, threshold: 5.0)
        ],
        cutoffRule: TriggerRule = TriggerRule(sensor: .flow, comparison: .lessThanOrEqual, threshold: 0.15),
        sustainDuration: TimeInterval = 2.0,
        trimTailDuration: TimeInterval = 2.0
    ) {
        self.preconditions = preconditions
        self.cutoffRule = cutoffRule
        self.sustainDuration = sustainDuration
        self.trimTailDuration = trimTailDuration
    }
}

// MARK: - HUD & Guidance Tolerances (Deadbands)

public nonisolated struct GuidanceTolerances: Sendable, Codable, Equatable {
    /// Deadband zone around target pressure considered "ON TARGET" (in bar)
    public var pressureDeadband: Double
    
    /// Deadband zone around target flow considered "ON TARGET" (in mL/s)
    public var flowDeadband: Double
    
    /// Deadband zone around motor power considered "ON TARGET" (in %)
    public var powerDeadband: Double
    
    public init(pressureDeadband: Double = 0.4, flowDeadband: Double = 0.3, powerDeadband: Double = 5.0) {
        self.pressureDeadband = pressureDeadband
        self.flowDeadband = flowDeadband
        self.powerDeadband = powerDeadband
    }
    
    public func deadband(for metric: SensorKey) -> Double {
        switch metric {
        case .pressure: return pressureDeadband
        case .flow:     return flowDeadband
        case .power:    return powerDeadband
        default:        return 0.1
        }
    }
}

// MARK: - Master Machine Configuration Aggregate

/// The unified, extensible configuration container for the Virtual Espresso Machine.
public nonisolated struct MachineConfig: Sendable, Codable, Equatable {
    
    /// The rule that trips auto-start (e.g. pressure >= 0.8 bar or weight >= 0.2g)
    public var autoStartRule: TriggerRule
    
    /// The composite rules governing automated shot cutoff
    public var autoStop: AutoStopConfig
    
    /// Non-touchy deadbands for the Barista HUD
    public var tolerances: GuidanceTolerances
    
    /// Extensible key-value bag for future or experimental machine settings
    public var customSettings: [String: Double]
    
    public init(
        autoStartRule: TriggerRule = TriggerRule(sensor: .pressure, comparison: .greaterThanOrEqual, threshold: 0.8),
        autoStop: AutoStopConfig = AutoStopConfig(),
        tolerances: GuidanceTolerances = GuidanceTolerances(),
        customSettings: [String: Double] = [:]
    ) {
        self.autoStartRule = autoStartRule
        self.autoStop = autoStop
        self.tolerances = tolerances
        self.customSettings = customSettings
    }
    
    // MARK: - Presets
    
    /// Default preset tuned for Flair 58 manual lever with pressure gauge and Bluetooth scale
    public static let flair58Default = MachineConfig()
    
    /// Preset for users with only a smart scale (Auto-starts on first drip > 0.2g!)
    public static let scaleOnlyPreset = MachineConfig(
        autoStartRule: TriggerRule(sensor: .weight, comparison: .greaterThanOrEqual, threshold: 0.2)
    )
}
