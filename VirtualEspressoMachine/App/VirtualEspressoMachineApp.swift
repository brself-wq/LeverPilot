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
    @State private var bleManager = EspressoBLEManager()
    @State private var coordinator = ShotCoordinator()
    @State private var bleProvider: BLETelemetryProvider?
    @State private var showAbortConfirmation: Bool = false
    
    // MARK: - View-Driven Navigation State
    @State private var activeExtractionProfile: Profile? = nil
    @State private var completedRecordForDebrief: ShotRecord? = nil

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 1. BASE LAYER: Profile Console & Hardware Dock
                ProfileConsoleView(
                    profiles: profileStore.profiles,
                    bleManager: bleManager,
                    onSelectProfile: { profile in
                        launchShot(with: profile)
                    },
                    onCustomizeProfile: nil
                )
                
                // 2. EXTRACTION LAYER: Cross-Platform HUD (iPad + macOS)
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
                        if newState == .shotEnded {
                            concludeShot()
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: { showAbortConfirmation = true }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.06), in: Circle())
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
            }
            // 3. SHOT RECORD / SCORECARD LAYER (Supported natively on both iOS and macOS)
            .sheet(item: $completedRecordForDebrief) { shotRecord in
                ShotRecordView(
                    record: shotRecord,
                    onSave: { updatedRecord in
                        try? scenarioStore.recordCompletedShot(updatedRecord)
                    },
                    onDismiss: {
                        completedRecordForDebrief = nil
                    }
                )
            }
            .preferredColorScheme(.dark)
        }
    }
    
    // MARK: - Machine Lifecycle Handlers
    
    private func launchShot(with profile: Profile) {
        // Arm coordinator with session profile
        coordinator.arm(with: profile, store: profileStore)
        
        // Start 10 Hz metronome
        let provider = BLETelemetryProvider(bleManager: bleManager)
        self.bleProvider = provider
        coordinator.attach(telemetryProvider: provider)
        provider.start()
        
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeExtractionProfile = profile
        }
    }
    
    private func concludeShot() {
        bleProvider?.stop()
        coordinator.detachTelemetry()
        
        let finishedRecord = coordinator.completedShotRecord
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
            completedRecordForDebrief = finishedRecord
        }
    }
    
    private func abortShot() {
        bleProvider?.stop()
        coordinator.detachTelemetry()
        coordinator.abort()
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
        }
    }
}
