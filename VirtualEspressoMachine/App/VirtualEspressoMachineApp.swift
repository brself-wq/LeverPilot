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
    @State private var bleManager = EspressoBLEManager(savedDevices: loadSavedBLEDevices())
    @State private var coordinator = ShotCoordinator()
    @State private var activeTelemetryProvider: (any TelemetryProvider)?
    @State private var showAbortConfirmation: Bool = false
    
    // MARK: - Navigation State
    @State private var activeExtractionProfile: Profile? = nil
    @State private var completedRecordForDebrief: ShotRecord? = nil
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // 1. BASE LAYER: Profile Console
                ProfileConsoleView(
                    profiles: profileStore.profiles,
                    bleManager: bleManager,
                    scenarioStore: scenarioStore,
                    onArm: { sessionProfile, primedScenario in
                        launchShot(with: sessionProfile, primedScenario: primedScenario)
                    }
                )
                
                // 2. EXTRACTION LAYER: Cross-Platform HUD (Visible only in flight)
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
                        isAlarmActive: coordinator.isAlarmActive,
                        elapsedTime: coordinator.elapsedTime,
                        stageTime: coordinator.stageTime,
                        actualWeight: coordinator.actualWeight
                    )
                    .onChange(of: coordinator.state) { _, newState in
                        if newState == .extracting {
                            bleManager.startScaleTimer()
                        } else if newState == .shotEnded {
                            concludeShot()
                        }
                    }
                    // HUD Flight Controls: Clean Abort Trigger
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
                
                // 3. POST-SHOT LAYER: Full-Screen Shot Record / History
                if let shotRecord = completedRecordForDebrief {
                    ShotRecordView(
                        record: shotRecord,
                        onSave: { updatedRecord in
                            try? scenarioStore.recordCompletedShot(updatedRecord)
                        },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                completedRecordForDebrief = nil
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    // MARK: - Machine Lifecycle Handlers
    
    private func launchShot(with profile: Profile, primedScenario: ShotRecord? = nil) {
        coordinator.arm(with: profile, store: profileStore)
        
        let provider: any TelemetryProvider
        if let primedScenario {
            let replay = ReplayTelemetryProvider(scenario: primedScenario)
            provider = replay
            self.activeTelemetryProvider = provider
            coordinator.attach(telemetryProvider: provider)
            replay.play()
        } else {
            // Zero physical scale and reset scale timer upon arming
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
        
        let finishedRecord = coordinator.completedShotRecord
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
            completedRecordForDebrief = finishedRecord
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
