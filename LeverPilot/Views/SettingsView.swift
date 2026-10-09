//
//  SettingsView.swift
//  LeverPilot
//

import SwiftUI

public struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @ObservedObject private var transponder = MeticulousTransponder.shared
    
    @State private var showResetConfirmation: Bool = false
    
    public init(settings: SettingsStore) {
        self.settings = settings
    }
    
    public var body: some View {
        ZStack {
            Color.appCanvas
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                Divider().background(Theme.Border.subtle)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Brew Defaults
                        brewDefaultsSection
                        
                        // 2. Extraction & Watchdogs
                        extractionWatchdogsSection
                        
                        // 3. Meticulous Machine Emulation Server
                        networkSection
                        
                        // 4. Cockpit & Display
                        displaySection
                    }
                    .padding(24)
                    .padding(.bottom, 60)
                }
            }
        }
        .confirmationDialog(
            "Reset all settings to factory defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                settings.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Text("Workflow defaults, sensor watchdogs, and machine interfaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Defaults")
                }
                .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }
    
    // MARK: - Section 1: Brew Defaults
    
    private var brewDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "BREW DEFAULTS", subtitle: "Default dose used across brew profiles")
            
            stepperRow(
                icon: "cup.and.saucer.fill",
                title: "Default Dose",
                subtitle: "Weight of ground coffee in portafilter",
                valueString: String(format: "%.1fg", settings.defaultDose),
                onDecrement: { settings.defaultDose = max(7.0, (settings.defaultDose - 0.5 * 10).rounded() / 10) },
                onIncrement: { settings.defaultDose = min(30.0, (settings.defaultDose + 0.5 * 10).rounded() / 10) }
            )
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    // MARK: - Section 2: Scale & Pressure Device
    
    private var extractionWatchdogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "START & STOP", subtitle: "Rules governing automated start and stop of timer")
            
            VStack(spacing: 8) {
                stepperRow(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    title: "Auto-Start Pressure",
                    subtitle: "Pressure threshold required to start the timer",
                    valueString: String(format: "%.1f bar", settings.autoStartPressure),
                    onDecrement: { settings.autoStartPressure = max(0.2, (settings.autoStartPressure - 0.1 * 10).rounded() / 10) },
                    onIncrement: { settings.autoStartPressure = min(3.0, (settings.autoStartPressure + 0.1 * 10).rounded() / 10) }
                )
                
                stepperRow(
                    icon: "water.waves",
                    title: "Auto-Stop Flow Rate",
                    subtitle: "Flow rate threshold used to trigger the stop sequence",
                    valueString: String(format: "%.2f mL/s", settings.deadFlowThreshold),
                    onDecrement: { settings.deadFlowThreshold = max(0.05, (settings.deadFlowThreshold - 0.05 * 100).rounded() / 100) },
                    onIncrement: { settings.deadFlowThreshold = min(1.0, (settings.deadFlowThreshold + 0.05 * 100).rounded() / 100) }
                )
                
                stepperRow(
                    icon: "clock.arrow.circlepath",
                    title: "Auto-Stop Sustain Duration",
                    subtitle: "Time the low flow rate must persist before stopping",
                    valueString: String(format: "%.1fs", settings.deadFlowSustainDuration),
                    onDecrement: { settings.deadFlowSustainDuration = max(1.0, settings.deadFlowSustainDuration - 0.5) },
                    onIncrement: { settings.deadFlowSustainDuration = min(10.0, settings.deadFlowSustainDuration + 0.5) }
                )
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    // MARK: - Section 3: Meticulous Machine Emulation Server
    
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(
                    title: "METICULOUS EMULATION SERVER",
                    subtitle: "Local loopback interface emulating the Meticulous machine API"
                )
                Spacer()
                
                // Live Status Indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
            }
            
            VStack(spacing: 8) {
                // Master Enable Switch
                toggleRow(
                    icon: "power",
                    title: "Enable Server",
                    subtitle: "Listens on 127.0.0.1 for external history and profile queries",
                    isOn: $settings.enableMeticulousServer
                )
                
                // Configurable Port (Dimmed if server disabled)
                stepperRow(
                    icon: "network",
                    title: "Loopback Port",
                    subtitle: "TCP port serving REST endpoints and Socket.IO presence",
                    valueString: "\(settings.meticulousPort)",
                    onDecrement: { settings.meticulousPort = max(1024, settings.meticulousPort - 1) },
                    onIncrement: { settings.meticulousPort = min(65535, settings.meticulousPort + 1) }
                )
                .opacity(settings.enableMeticulousServer ? 1.0 : 0.45)
                .disabled(!settings.enableMeticulousServer)
                
                // Trace Logging Toggle (Dimmed if server disabled)
                toggleRow(
                    icon: "terminal.fill",
                    title: "Trace Logging",
                    subtitle: "Writes incoming client requests and heartbeat events to Documents/MeticulousTrace.log",
                    isOn: $settings.traceLogging
                )
                .opacity(settings.enableMeticulousServer ? 1.0 : 0.45)
                .disabled(!settings.enableMeticulousServer)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    private var statusText: String {
        guard settings.enableMeticulousServer else { return "OFF" }
        switch transponder.state {
        case .disabled: return "OFF"
        case .standby:  return "READY (PORT \(settings.meticulousPort))"
        case .active:   return "CLIENT ACTIVE"
        }
    }
    
    private var statusColor: Color {
        guard settings.enableMeticulousServer else { return .secondary }
        switch transponder.state {
        case .disabled: return .secondary
        case .standby:  return .green
        case .active:   return Color(red: 1.0, green: 0.12, blue: 0.0)
        }
    }
    
    // MARK: - Section 4: Cockpit & Display
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "COCKPIT & DISPLAY", subtitle: "Screen power and display sleep management")
            
            toggleRow(
                icon: "sun.max.fill",
                title: "Keep Display Awake While Brewing",
                subtitle: "Prevents screen from dimming or locking while armed or extracting",
                isOn: $settings.keepDisplayAwake
            )
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    // MARK: - Reusable Row Builders
    
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
    
    private func stepperRow(
        icon: String,
        title: String,
        subtitle: String,
        valueString: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Theme.Surface.control)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                }
                .buttonStyle(.plain)
                
                Text(valueString)
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 70, alignment: .center)
                
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Theme.Surface.control)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }
    
    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.telemetryFlow)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }
}
