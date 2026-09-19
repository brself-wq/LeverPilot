//
//  SettingsView.swift
//  VirtualEspressoMachine
//

import SwiftUI

public struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @ObservedObject private var bqStorage = BQStorageManager.shared
    
    @State private var isShowingFolderPicker: Bool = false
    @State private var showResetConfirmation: Bool = false
    
    public init(settings: SettingsStore) {
        self.settings = settings
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                Divider().background(Color.white.opacity(0.08))
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Brew Defaults
                        brewDefaultsSection
                        
                        // 2. Extraction & Watchdogs
                        extractionWatchdogsSection
                        
                        // 3. Meticulous Server & Logging
                        networkSection
                        
                        // 4. HUD Viewport Dynamics
                        hudSection
                        
                        // 5. Beanconqueror Integration
                        beanconquerorSection
                    }
                    .padding(24)
                    // Bottom clearance for the universal hamburger menu
                    .padding(.bottom, 60)
                }
            }
        }
        .sheet(isPresented: $isShowingFolderPicker) {
            DocumentPickerView { url in
                bqStorage.saveFolderBookmark(url: url)
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
                Text("Machine thresholds, workflow defaults, and server integrations")
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
            sectionHeader(title: "BREW DEFAULTS", subtitle: "Default dose used across console recipes")
            
            stepperRow(
                icon: "cup.and.saucer.fill",
                title: "Default Ground Dose",
                subtitle: "Initial reference ground coffee dose in portafilter",
                valueString: String(format: "%.1fg", settings.defaultDose),
                onDecrement: { settings.defaultDose = max(7.0, (settings.defaultDose - 0.5 * 10).rounded() / 10) },
                onIncrement: { settings.defaultDose = min(30.0, (settings.defaultDose + 0.5 * 10).rounded() / 10) }
            )
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Section 2: Extraction & Watchdogs
    
    private var extractionWatchdogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "EXTRACTION & WATCHDOGS", subtitle: "Rules governing automated start and dead-flow cutoff")
            
            VStack(spacing: 8) {
                stepperRow(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    title: "Auto-Start Pressure",
                    subtitle: "Pressure threshold required to trip transition from Armed to Extracting",
                    valueString: String(format: "%.1f bar", settings.autoStartPressure),
                    onDecrement: { settings.autoStartPressure = max(0.2, (settings.autoStartPressure - 0.1 * 10).rounded() / 10) },
                    onIncrement: { settings.autoStartPressure = min(3.0, (settings.autoStartPressure + 0.1 * 10).rounded() / 10) }
                )
                
                stepperRow(
                    icon: "water.waves",
                    title: "Dead-Flow Cutoff Threshold",
                    subtitle: "Flow rate below which extraction flow is considered dead",
                    valueString: String(format: "%.2f mL/s", settings.deadFlowThreshold),
                    onDecrement: { settings.deadFlowThreshold = max(0.05, (settings.deadFlowThreshold - 0.05 * 100).rounded() / 100) },
                    onIncrement: { settings.deadFlowThreshold = min(1.0, (settings.deadFlowThreshold + 0.05 * 100).rounded() / 100) }
                )
                
                stepperRow(
                    icon: "clock.arrow.circlepath",
                    title: "Dead-Flow Sustain Duration",
                    subtitle: "Seconds flow must stay dead before ending the shot",
                    valueString: String(format: "%.1fs", settings.deadFlowSustainDuration),
                    onDecrement: { settings.deadFlowSustainDuration = max(1.0, settings.deadFlowSustainDuration - 0.5) },
                    onIncrement: { settings.deadFlowSustainDuration = min(10.0, settings.deadFlowSustainDuration + 0.5) }
                )
            }
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Section 3: Meticulous Server & Logging
    
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "METICULOUS EMULATION SERVER", subtitle: "Local loopback listener configuration for Beanconqueror")
            
            VStack(spacing: 8) {
                stepperRow(
                    icon: "network",
                    title: "Loopback Port",
                    subtitle: "Port on 127.0.0.1 serving telemetry and Socket.IO presence",
                    valueString: "\(settings.meticulousPort)",
                    onDecrement: { settings.meticulousPort = max(1024, settings.meticulousPort - 1) },
                    onIncrement: { settings.meticulousPort = min(65535, settings.meticulousPort + 1) }
                )
                
                toggleRow(
                    icon: "terminal.fill",
                    title: "Verbose Server Traffic Logging",
                    subtitle: "Logs incoming HTTP request lines and Socket.IO heartbeat pings to stdout",
                    isOn: $settings.verboseServerLogging
                )
            }
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Section 4: HUD Dynamics
    
    private var hudSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "HUD & VIEWPORT", subtitle: "Live chart rendering and viewport sliding parameters")
            
            stepperRow(
                icon: "chart.xyaxis.line",
                title: "Chart Sliding Window Span",
                subtitle: "Visible horizon window (seconds/grams) before chart autoscrolls",
                valueString: String(format: "%.0fs", settings.chartWindowSpan),
                onDecrement: { settings.chartWindowSpan = max(10.0, settings.chartWindowSpan - 5.0) },
                onIncrement: { settings.chartWindowSpan = min(60.0, settings.chartWindowSpan + 5.0) }
            )
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Section 5: Beanconqueror Archive Link
    
    private var beanconquerorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "BEANCONQUEROR INTEGRATION", subtitle: "Security-scoped folder bookmark to Beanconqueror.zip")
            
            HStack(spacing: 12) {
                Circle()
                    .fill(bqStorage.isConfigured ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(bqStorage.isConfigured ? "Beanconqueror Folder Linked" : "Folder Not Linked")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(bqStorage.syncStatusMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if bqStorage.isConfigured {
                    Button {
                        bqStorage.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button(bqStorage.isConfigured ? "Change Folder" : "Link Folder") {
                    isShowingFolderPicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(bqStorage.isConfigured ? .secondary : .blue)
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Text(valueString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 70, alignment: .center)
                
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
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
                .tint(.blue)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}
