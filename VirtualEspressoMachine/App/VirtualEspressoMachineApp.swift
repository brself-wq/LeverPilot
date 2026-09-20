//
//  VirtualEspressoMachineApp.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile
import EspressoBLE

@main
struct VirtualEspressoMachineApp: App {
    
    // MARK: - App-Level Shared Singletons
    @State private var profileStore = ProfileStore()
    @State private var scenarioStore = ScenarioStore()
    @State private var settingsStore = SettingsStore()
    @State private var bleManager = EspressoBLEManager(savedDevices: loadSavedBLEDevices())
    @State private var coordinator = ShotCoordinator()
    @State private var activeTelemetryProvider: (any TelemetryProvider)?
    @State private var showAbortConfirmation: Bool = false
    
    // MARK: - Root Navigation Destination
    @State private var currentDestination: AppDestination = .brew
    
    // MARK: - Active Extraction / Shot Modal Overlays
    @State private var activeExtractionProfile: Profile? = nil
    @State private var completedRecordForReview: ShotRecord? = nil
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // 1. BASE LAYER: Active Workspace
                Group {
                    switch currentDestination {
                    case .brew:
                        ProfileConsoleView(
                            profiles: profileStore.profiles,
                            bleManager: bleManager,
                            scenarioStore: scenarioStore,
                            settings: settingsStore,
                            onArm: { sessionProfile, dose, primedScenario in
                                launchShot(with: sessionProfile, dose: dose, primedScenario: primedScenario)
                            }
                        )
                    case .history:
                        ShotHistoryBrowserView(scenarioStore: scenarioStore)
                    case .settings:
                        SettingsView(settings: settingsStore)
                    case .workbench:
                        EmptyView()
                    }
                }
                .transition(.opacity)
                
                // 2. UNIVERSAL BOTTOM-LEFT HAMBURGER MENU
                VStack {
                    Spacer()
                    HStack {
                        universalHamburgerMenu
                            .padding(.leading, 28)
                            .padding(.bottom, 22)
                        Spacer()
                    }
                }
                
                // 3. EXTRACTION LAYER: Cross-Platform HUD (Visible only in flight)
                if activeExtractionProfile != nil {
                    BaristaHUDView(
                        frame: coordinator.guidanceFrame,
                        planCurve: coordinator.planCurve,
                        actualHistory: coordinator.actualHistory,
                        exitTriggerItems: coordinator.exitTriggerItems,
                        stagePills: coordinator.stagePills,
                        domainLabel: coordinator.currentStage?.dynamics.over.rawValue.capitalized ?? "Time",
                        finalWeightTarget: coordinator.resolvedTargetWeight,
                        nominalDuration: 32.0,
                        windowSpan: settingsStore.chartWindowSpan,
                        isAlarmActive: coordinator.isAlarmActive,
                        elapsedTime: coordinator.elapsedTime,
                        stageTime: coordinator.stageTime,
                        actualWeight: coordinator.actualWeight,
                        isScaleStale: coordinator.currentFrame.isScaleStale,
                        isPressureStale: coordinator.currentFrame.isPressureStale
                    )
                    .onChange(of: coordinator.state) { _, newState in
                        if newState == .extracting {
                            bleManager.startScaleTimer()
                        } else if newState == .shotEnded {
                            concludeShot()
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: { showAbortConfirmation = true }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.08), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(14)
                        .confirmationDialog(
                            "Abort Extraction?",
                            isPresented: $showAbortConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Abort Shot", role: .destructive) {
                                abortShot()
                            }
                            Button("Resume Extraction", role: .cancel) {}
                        } message: {
                            Text("Active extraction will be stopped and in-flight telemetry discarded.")
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
                
                // 4. POST-SHOT LAYER: Full-Screen Shot Record / Shot History
                if let shotRecord = completedRecordForReview {
                    ShotRecordView(
                        record: shotRecord,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                completedRecordForReview = nil
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                Task {
                    await MeticulousServer.shared.configure(
                        port: settingsStore.meticulousPort,
                        verbose: settingsStore.verboseServerLogging
                    )
                }
            }
            .onChange(of: settingsStore.meticulousPort) { _, newPort in
                Task {
                    await MeticulousServer.shared.configure(
                        port: newPort,
                        verbose: settingsStore.verboseServerLogging
                    )
                }
            }
            .onChange(of: settingsStore.verboseServerLogging) { _, newVerbose in
                Task {
                    await MeticulousServer.shared.setVerboseLogging(newVerbose)
                }
            }
        }
    }
    
    // MARK: - Universal Hamburger Menu
    
    private var universalHamburgerMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .settings }
            } label: {
                Label(AppDestination.settings.rawValue, systemImage: AppDestination.settings.systemImage)
            }
            
            Divider()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .brew }
            } label: {
                Label(AppDestination.brew.rawValue, systemImage: AppDestination.brew.systemImage)
            }
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .history }
            } label: {
                Label(AppDestination.history.rawValue, systemImage: AppDestination.history.systemImage)
            }
            
            Button {} label: {
                Label(AppDestination.workbench.rawValue, systemImage: AppDestination.workbench.systemImage)
            }
            .disabled(true)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .menuOrder(.fixed)
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    // MARK: - Machine Lifecycle Handlers
    
    private func launchShot(with profile: Profile, dose: Double? = nil, primedScenario: ShotRecord? = nil) {
        coordinator.configure(from: settingsStore)
        let resolvedDose = dose ?? settingsStore.defaultDose
        coordinator.arm(with: profile, dose: resolvedDose, store: profileStore)
        
        let provider: any TelemetryProvider
        if let primedScenario {
            let scenarioProvider = ScenarioTelemetryProvider(scenario: primedScenario)
            provider = scenarioProvider
            self.activeTelemetryProvider = provider
            coordinator.attach(telemetryProvider: provider)
            scenarioProvider.start()
        } else {
            bleManager.tareScale()
            bleManager.resetScaleTimer()
            
            let ble = BLETelemetryProvider(bleManager: bleManager)
            provider = ble
            self.activeTelemetryProvider = provider
            coordinator.attach(telemetryProvider: provider)
            ble.start()
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeExtractionProfile = profile
        }
    }
    
    private func concludeShot() {
        bleManager.stopScaleTimer()
        activeTelemetryProvider?.stop()
        activeTelemetryProvider = nil
        coordinator.detachTelemetry()
        
        if let finishedRecord = coordinator.completedShotRecord {
            try? scenarioStore.recordCompletedShot(finishedRecord)
            
            withAnimation(.easeInOut(duration: 0.25)) {
                activeExtractionProfile = nil
                completedRecordForReview = finishedRecord
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                activeExtractionProfile = nil
            }
        }
    }
    
    private func abortShot() {
        bleManager.stopScaleTimer()
        activeTelemetryProvider?.stop()
        activeTelemetryProvider = nil
        coordinator.detachTelemetry()
        coordinator.abort()
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
        }
    }
    
    private static func loadSavedBLEDevices() -> [BLEDeviceRole: UUID] {
        var saved: [BLEDeviceRole: UUID] = [:]
        for role in BLEDeviceRole.allCases {
            if let raw = UserDefaults.standard.string(forKey: "ble.device.\(role.rawValue)"),
               let uuid = UUID(uuidString: raw) {
                saved[role] = uuid
            }
        }
        return saved
    }
}
