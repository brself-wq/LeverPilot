//
//  ProfileVariableOverridesView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

public struct ProfileVariableOverridesView: View {
    let originalProfile: Profile
    let defaultDose: Double
    let onApply: (Profile, Double) -> Void
    let onCancel: () -> Void
    
    // Ephemeral Targets
    @State private var targetYield: Double
    @State private var targetTemperature: Double
    @State private var doseWeight: Double
    
    // Ephemeral Profile Variables mapped by variable key
    @State private var variableValues: [String: Double]
    
    private var hasChanges: Bool {
        if abs(targetYield - originalProfile.finalWeight) > 0.05 { return true }
        if abs(targetTemperature - originalProfile.temperature) > 0.05 { return true }
        if abs(doseWeight - defaultDose) > 0.05 { return true }
        for v in originalProfile.variables {
            if let current = variableValues[v.key], abs(current - v.value) > 0.05 {
                return true
            }
        }
        return false
    }
    
    public init(
        profile: Profile,
        initialDose: Double = 18.0,
        onApply: @escaping (Profile, Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalProfile = profile
        self.defaultDose = initialDose
        self.onApply = onApply
        self.onCancel = onCancel
        
        _targetYield = State(initialValue: profile.finalWeight)
        _targetTemperature = State(initialValue: profile.temperature)
        _doseWeight = State(initialValue: initialDose)
        
        var initialDict: [String: Double] = [:]
        for v in profile.variables {
            initialDict[v.key] = v.value
        }
        _variableValues = State(initialValue: initialDict)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.appOverlay)
            
            Divider().background(Theme.Border.subtle)
            
            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    // Session Notice Banner
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Overrides apply only to this brewing session. Profile on disk remains untouched.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
                    
                    // Section 1: Targets (Dose -> Target Weight -> Temperature)
                    targetsSection
                    
                    // Section 2: Variables (If present)
                    if !originalProfile.variables.isEmpty {
                        variablesSection
                    }
                }
                .padding(24)
            }
            
            Divider().background(Theme.Border.subtle)
            
            // Footer Action Bar
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.appFooter)
        }
        .frame(minWidth: 540, minHeight: 480)
        .background(Color.appCanvas)
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            Text(originalProfile.name)
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
            
            Spacer()
            
            if hasChanges {
                Button(action: resetToDefaults) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Defaults")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.Surface.control)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
            }
        }
    }
    
    // MARK: - Targets Section
    
    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TARGETS")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                // 1. Dose
                TargetRowStepper(
                    icon: "cup.and.saucer.fill",
                    label: "Dose",
                    unit: "g",
                    value: $doseWeight,
                    step: 0.5,
                    range: 7.0...30.0,
                    subtitle: "Weight of ground coffee in portafilter"
                )
                
                // 2. Target Weight
                TargetRowStepper(
                    icon: "scalemass.fill",
                    label: "Target Weight",
                    unit: "g",
                    value: $targetYield,
                    step: 0.5,
                    range: 10.0...120.0,
                    subtitle: String(format: "Ratio 1:%.1f (based on %.1fg dose)", targetYield / max(1.0, doseWeight), doseWeight)
                )
                
                // 3. Temperature
                TargetRowStepper(
                    icon: "thermometer.medium",
                    label: "Temperature",
                    unit: "°C",
                    value: $targetTemperature,
                    step: 1.0,
                    range: 75.0...100.0,
                    subtitle: "Water temperature"
                )
            }
        }
    }
    
    // MARK: - Variables Section
    
    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VARIABLES")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(originalProfile.variables.count) VARIABLES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                ForEach(originalProfile.variables, id: \.key) { variable in
                    if let binding = binding(for: variable.key) {
                        VariableRowControl(
                            variable: variable,
                            value: binding
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Footer Actions
    
    private var footerBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.secondary)
            
            Spacer()
            
            // High-Contrast Primary Apply Button
            Button(action: applyAndConfirm) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                    Text("Apply")
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(minWidth: 140)
                .padding(.vertical, 8)
                .foregroundStyle(.black)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Actions
    
    private func binding(for key: String) -> Binding<Double>? {
        guard variableValues[key] != nil else { return nil }
        return Binding<Double>(
            get: { variableValues[key] ?? 0.0 },
            set: { variableValues[key] = $0 }
        )
    }
    
    private func resetToDefaults() {
        targetYield = originalProfile.finalWeight
        targetTemperature = originalProfile.temperature
        doseWeight = defaultDose
        for v in originalProfile.variables {
            variableValues[v.key] = v.value
        }
    }
    
    private func applyAndConfirm() {
        var modified = originalProfile
        modified.finalWeight = targetYield
        modified.temperature = targetTemperature
        
        var updatedVariables: [Variable] = []
        for v in originalProfile.variables {
            var copiedVar = v
            if let overriddenVal = variableValues[v.key] {
                copiedVar.value = overriddenVal
            }
            updatedVariables.append(copiedVar)
        }
        modified.variables = updatedVariables
        
        onApply(modified, doseWeight)
    }
}

// MARK: - Target Stepper + Slider Row

private struct TargetRowStepper: View {
    let icon: String
    let label: String
    let unit: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let subtitle: String
    
    private var formattedValue: String {
        step < 1.0 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Stepper Controls with Large Touch Targets
                HStack(spacing: 6) {
                    Button(action: decrement) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Theme.Surface.control)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 2) {
                        Text(formattedValue)
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(unit)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 58, alignment: .center)
                    
                    Button(action: increment) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Theme.Surface.control)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Continuous Scrubbing Slider
            Slider(value: $value, in: range, step: step)
                .tint(.white.opacity(0.8))
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.wellRadius))
    }
    
    private func decrement() {
        let next = max(range.lowerBound, value - step)
        applyRounded(next)
    }
    
    private func increment() {
        let next = min(range.upperBound, value + step)
        applyRounded(next)
    }
    
    private func applyRounded(_ raw: Double) {
        if step < 1.0 {
            value = (raw * 10.0).rounded() / 10.0
        } else {
            value = raw.rounded()
        }
    }
}

// MARK: - Variable Stepper + Slider Row

private struct VariableRowControl: View {
    let variable: Variable
    @Binding var value: Double
    
    private var config: (step: Double, range: ClosedRange<Double>, unit: String) {
        switch variable.type {
        case .pressure:       return (0.1, 0.0...12.0, "bar")
        case .flow:           return (0.1, 0.0...10.0, "mL/s")
        case .time:           return (0.5, 0.0...120.0, "s")
        case .weight:         return (0.5, 0.0...150.0, "g")
        case .power:          return (1.0, 0.0...100.0, "%")
        case .pistonPosition: return (1.0, 0.0...100.0, "%")
        }
    }
    
    private var formattedValue: String {
        config.step < 1.0 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variable.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Key: $\(variable.key) • \(variable.type.rawValue.uppercased())")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Stepper Controls
                HStack(spacing: 6) {
                    Button(action: decrement) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Theme.Surface.control)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 2) {
                        Text(formattedValue)
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(config.unit)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 58, alignment: .center)
                    
                    Button(action: increment) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Theme.Surface.control)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Continuous Scrubbing Slider
            Slider(value: $value, in: config.range, step: config.step)
                .tint(.white.opacity(0.8))
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.wellRadius))
    }
    
    private func decrement() {
        let next = max(config.range.lowerBound, value - config.step)
        applyRounded(next)
    }
    
    private func increment() {
        let next = min(config.range.upperBound, value + config.step)
        applyRounded(next)
    }
    
    private func applyRounded(_ raw: Double) {
        if config.step < 1.0 {
            value = (raw * 10.0).rounded() / 10.0
        } else {
            value = raw.rounded()
        }
    }
}
