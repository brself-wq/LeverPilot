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
    @State private var playbackEngine = PlaybackEngine()
    @State private var bleProvider: BLETelemetryProvider?
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
                    onSelectProfile: { profile in
                        launchShot(with: profile)
                    },
                    onSelectScenario: { profile, scenario in
                        launchScenarioPlayback(profile: profile, scenario: scenario)
                    },
                    onCustomizeProfile: nil
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
                        if newState == .shotEnded {
                            concludeShot()
                        }
                    }
                    // HUD-Only Flight Controls: STOP Trigger + Abort Button
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 10) {
                            #if DEBUG
                            Button(action: simulateFlowStop) {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                    Text("CUTOFF (0 flow)")
                                }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red.opacity(0.85))
                            .controlSize(.small)
                            #endif
                            
                            Button(action: { showAbortConfirmation = true }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .background(Color.white.opacity(0.08), in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
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
                        .padding(14)
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            // 3. SHOT RECORD / SCORECARD LAYER
            .sheet(item: $completedRecordForDebrief) { shotRecord in
                ShotRecordView(
                    record: shotRecord,
                    onSave: { updatedRecord in
                        do {
                            let savedURL = try scenarioStore.recordCompletedShot(updatedRecord)
                            print("💾 [PERSISTENCE SUCCESS] Wrote ShotRecord to disk at: \(savedURL)")
                        } catch {
                            print("❌ [PERSISTENCE ERROR] Failed to save ShotRecord: \(error)")
                        }
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
        coordinator.arm(with: profile, store: profileStore)
        
        let provider = BLETelemetryProvider(bleManager: bleManager)
        self.bleProvider = provider
        coordinator.attach(telemetryProvider: provider)
        provider.start()
        
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeExtractionProfile = profile
        }
    }
    
    private func launchScenarioPlayback(profile: Profile, scenario: ShotRecord) {
        coordinator.arm(with: profile, store: profileStore)
        playbackEngine.load(scenario: scenario)
        
        playbackEngine.onTick = { sample, _ in
            let frame = MachineFrame(
                timestamp: sample.timestamp,
                state: .extracting,
                readings: [
                    .pressure: sample.pressure,
                    .flow: sample.flow,
                    .weight: sample.weight,
                    .time: sample.timestamp,
                    .power: 100.0
                ]
            )
            coordinator.processTelemetryFrame(frame, allowAdvance: true)
            
            if coordinator.state == .shotEnded && playbackEngine.isPlaying {
                playbackEngine.stop()
            }
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeExtractionProfile = profile
        }
        
        playbackEngine.play()
    }
    
    private func concludeShot() {
        playbackEngine.stop()
        bleProvider?.stop()
        coordinator.detachTelemetry()
        
        let finishedRecord = coordinator.completedShotRecord
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
            completedRecordForDebrief = finishedRecord
        }
    }
    
    private func abortShot() {
        playbackEngine.stop()
        bleProvider?.stop()
        coordinator.detachTelemetry()
        coordinator.abort()
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
        }
    }
    
    // MARK: - Debug Stimulation Helpers
    #if DEBUG
    private func simulateFlowStop() {
        let frame = MachineFrame(
            timestamp: coordinator.elapsedTime,
            state: .extracting,
            readings: [
                .pressure: 0.0,
                .flow: 0.0,
                .weight: coordinator.actualWeight,
                .time: coordinator.elapsedTime,
                .power: 0.0
            ]
        )
        coordinator.processTelemetryFrame(frame, allowAdvance: true)
    }
    #endif
}
