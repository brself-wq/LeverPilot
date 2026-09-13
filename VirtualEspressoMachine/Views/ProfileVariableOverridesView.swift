//
//  ProfileVariableOverridesView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile

public struct ProfileVariableOverridesView: View {
    let originalProfile: Profile
    let onApply: (Profile, Double) -> Void
    let onCancel: () -> Void
    
    // Ephemeral Targets
    @State private var targetYield: Double
    @State private var targetTemperature: Double
    @State private var doseWeight: Double
    
    // Ephemeral Profile Variables mapped by variable key
    @State private var variableValues: [String: Double]
    
    private var accentColor: Color {
        Color(hex: originalProfile.display?.accentColor)
    }
    
    private var hasChanges: Bool {
        if abs(targetYield - originalProfile.finalWeight) > 0.05 { return true }
        if abs(targetTemperature - originalProfile.temperature) > 0.05 { return true }
        if abs(doseWeight - 18.0) > 0.05 { return true }
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
                .background(Color(red: 0.07, green: 0.07, blue: 0.09))
            
            Divider().background(Color.white.opacity(0.08))
            
            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    // Session Notice Banner
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accentColor)
                        Text("Overrides apply only to this shot session. Recipe on disk remains untouched.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    
                    // Section 1: Targets (Dose -> Target Weight -> Temperature)
                    targetsSection
                    
                    // Section 2: Parameters (If present)
                    if !originalProfile.variables.isEmpty {
                        parametersSection
                    }
                }
                .padding(24)
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            // Footer Action Bar
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        }
        .frame(minWidth: 540, minHeight: 480)
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
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
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Targets Section
    
    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TARGETS")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 10) {
                // 1. Dose
                TargetRowStepper(
                    icon: "cup.and.saucer.fill",
                    label: "Dose",
                    unit: "g",
                    value: $doseWeight,
                    step: 0.5,
                    range: 7.0...30.0,
                    accentColor: accentColor,
                    subtitle: "Reference ground coffee dose in portafilter"
                )
                
                // 2. Target Weight
                TargetRowStepper(
                    icon: "scalemass.fill",
                    label: "Target Weight",
                    unit: "g",
                    value: $targetYield,
                    step: 0.5,
                    range: 10.0...120.0,
                    accentColor: accentColor,
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
                    accentColor: accentColor,
                    subtitle: "Machine kettle / chamber water temperature"
                )
            }
        }
    }
    
    // MARK: - Parameters Section
    
    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PARAMETERS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(originalProfile.variables.count) VARIABLES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
            }
            
            VStack(spacing: 10) {
                ForEach(originalProfile.variables, id: \.key) { variable in
                    if let binding = binding(for: variable.key) {
                        VariableRowControl(
                            variable: variable,
                            value: binding,
                            accentColor: accentColor
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
            
            Button(action: applyAndConfirm) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                    Text("Apply")
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(accentColor)
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
        doseWeight = 18.0
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

// MARK: - Target Stepper Row

private struct TargetRowStepper: View {
    let icon: String
    let label: String
    let unit: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    let subtitle: String
    
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(accentColor)
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
            
            HStack(spacing: 6) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                EditableNumericField(
                    value: $value,
                    step: step,
                    range: range,
                    accentColor: .white
                )
                
                Text(unit)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)
                
                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
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

// MARK: - Variable Row Control

private struct VariableRowControl: View {
    let variable: Variable
    @Binding var value: Double
    let accentColor: Color
    
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
                
                HStack(spacing: 6) {
                    Button(action: decrement) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    EditableNumericField(
                        value: $value,
                        step: config.step,
                        range: config.range,
                        accentColor: accentColor
                    )
                    
                    Text(config.unit)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .leading)
                    
                    Button(action: increment) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Slider(value: $value, in: config.range, step: config.step)
                .tint(accentColor)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
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

// MARK: - Keyboard-Editable Numeric Field

private struct EditableNumericField: View {
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    
    @State private var textInput: String = ""
    @FocusState private var isFocused: Bool
    
    private var borderStrokeColor: Color {
        isFocused ? accentColor.opacity(0.8) : Color.white.opacity(0.1)
    }
    
    private var borderStrokeWidth: CGFloat {
        isFocused ? 1.5 : 1.0
    }
    
    private var backgroundFillColor: Color {
        isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.05)
    }
    
    var body: some View {
        let field = TextField("", text: $textInput)
            .multilineTextAlignment(TextAlignment.center)
            .font(Font.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(accentColor)
            .frame(minWidth: 46, maxWidth: 58)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderStrokeColor, lineWidth: borderStrokeWidth)
            )
            .focused($isFocused)
            .onAppear {
                syncTextFromValue()
                DispatchQueue.main.async {
                    isFocused = false
                }
            }
            .onChange(of: value) { _, _ in
                if !isFocused {
                    syncTextFromValue()
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitText()
                }
            }
            .onSubmit {
                commitText()
                isFocused = false
            }
        
        #if os(iOS)
        field.keyboardType(.decimalPad)
        #else
        field
        #endif
    }
    
    private func syncTextFromValue() {
        let fmt = step < 1.0 ? "%.1f" : "%.0f"
        textInput = String(format: fmt, value)
    }
    
    private func commitText() {
        let cleaned = textInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        
        guard let parsed = Double(cleaned) else {
            syncTextFromValue()
            return
        }
        
        let minVal = range.lowerBound
        let maxVal = range.upperBound
        let clamped = min(max(parsed, minVal), maxVal)
        
        if step < 1.0 {
            value = (clamped * 10.0).rounded() / 10.0
        } else {
            value = clamped.rounded()
        }
        
        syncTextFromValue()
    }
}
