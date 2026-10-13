//
//  ProfileOverride.swift
//  LeverPilot
//

import Foundation
import MeticulousProfile

/// A sparse delta record capturing user dial-in tweaks for a specific profile ID.
/// Stored independently in UserDefaults to preserve factory profile immutability.
public struct ProfileOverride: Codable, Equatable, Sendable {
    
    /// Overridden dry coffee mass in basket (grams). `nil` if matching default.
    public var dose: Double?
    
    /// Overridden liquid target yield / auto-stop trigger (grams). `nil` if matching profile default.
    public var targetWeight: Double?
    
    /// Overridden target water temperature (°C). `nil` if matching profile default.
    public var temperature: Double?
    
    /// Sparse map of variable keys to overridden values. Only includes explicitly modified variables.
    public var variables: [String: Double]
    
    /// Recency timestamp for forensics and UI indicators.
    public var updatedAt: Date
    
    public init(
        dose: Double? = nil,
        targetWeight: Double? = nil,
        temperature: Double? = nil,
        variables: [String: Double] = [:],
        updatedAt: Date = Date()
    ) {
        self.dose = dose
        self.targetWeight = targetWeight
        self.temperature = temperature
        self.variables = variables
        self.updatedAt = updatedAt
    }
    
    /// Evaluates whether all fields match baseline (no active overrides).
    public var isEmpty: Bool {
        dose == nil &&
        targetWeight == nil &&
        temperature == nil &&
        variables.isEmpty
    }
    
    // MARK: - Sparse Delta Construction
    
    /// Constructs a sparse delta by comparing the modified working copy against the baseline author specification.
    /// Returns `nil` if no values were changed beyond floating-point epsilon (0.01).
    public static func createSparse(
        baseProfile: Profile,
        baseDose: Double,
        workingDose: Double,
        workingTargetWeight: Double,
        workingTemperature: Double,
        workingVariables: [String: Double]
    ) -> ProfileOverride? {
        let epsilon = 0.01
        
        let doseDelta: Double? = abs(workingDose - baseDose) > epsilon ? workingDose : nil
        let weightDelta: Double? = abs(workingTargetWeight - baseProfile.finalWeight) > epsilon ? workingTargetWeight : nil
        let tempDelta: Double? = abs(workingTemperature - baseProfile.temperature) > epsilon ? workingTemperature : nil
        
        var variableDeltas: [String: Double] = [:]
        for baseVar in baseProfile.variables {
            if let modifiedVal = workingVariables[baseVar.key],
               abs(modifiedVal - baseVar.value) > epsilon {
                variableDeltas[baseVar.key] = modifiedVal
            }
        }
        
        let override = ProfileOverride(
            dose: doseDelta,
            targetWeight: weightDelta,
            temperature: tempDelta,
            variables: variableDeltas
        )
        
        return override.isEmpty ? nil : override
    }
    
    // MARK: - Pure Application & Guarded Injection
    
    /// Applies this sparse override onto a base profile, returning an effective execution profile and dose.
    /// Strictly whitelists variable keys and clamps values to safe physical bounds based on `VariableType`.
    public func applying(to base: Profile, fallbackDose: Double) -> (profile: Profile, dose: Double) {
        var modified = base
        
        // 1. Resolve Dose
        let resolvedDose = self.dose ?? fallbackDose
        
        // 2. Resolve Macro Targets
        if let targetWeight {
            modified.finalWeight = targetWeight
        }
        if let temperature {
            modified.temperature = temperature
        }
        
        // 3. Whitelist-only Variable Injection with Safe Range Clamping
        if !variables.isEmpty {
            var updatedVariables: [Variable] = []
            for baseVar in base.variables {
                var copied = baseVar
                if let rawOverriddenVal = variables[baseVar.key] {
                    copied.value = Self.clamp(rawOverriddenVal, for: baseVar.type)
                }
                updatedVariables.append(copied)
            }
            modified.variables = updatedVariables
        }
        
        return (modified, resolvedDose)
    }
    
    // MARK: - Physical Range Guarding
    
    /// Protects against schema drift or corrupted setpoints by clamping values to physical domain bounds.
    private static func clamp(_ value: Double, for type: VariableType) -> Double {
        switch type {
        case .pressure:       return min(max(value, 0.0), 12.0)
        case .flow:           return min(max(value, 0.0), 10.0)
        case .time:           return min(max(value, 0.0), 180.0)
        case .weight:         return min(max(value, 0.0), 150.0)
        case .power:          return min(max(value, 0.0), 100.0)
        case .pistonPosition: return min(max(value, 0.0), 100.0)
        }
    }
}
