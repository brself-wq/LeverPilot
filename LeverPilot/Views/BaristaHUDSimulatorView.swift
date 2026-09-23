//
//  BaristaHUDSimulatorView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

struct BaristaHUDSimulatorView: View {
    // Data Stores
    @State private var profileStore = ProfileStore()
    @State private var scenarioStore = ScenarioStore()
    
    // Domain Coordinator & Transport
    @State private var coordinator = ShotCoordinator()
    @State private var playbackEngine = PlaybackEngine()
    
    // Active Scenario Selection
    @State private var selectedScenarioID: String = ""
    @State private var simulateAlarm: Bool = false
    
    private var currentScenario: ShotRecord? {
        guard !selectedScenarioID.isEmpty else { return nil }
        return scenarioStore.scenarios.first(where: { $0.id == selectedScenarioID })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Production Barista HUD Presentation View
            BaristaHUDView(
                frame: coordinator.guidanceFrame,
                planCurve: coordinator.planCurve,
                actualHistory: coordinator.actualHistory,
                exitTriggerItems: coordinator.exitTriggerItems,
                stagePills: coordinator.stagePills,
                domainLabel: coordinator.currentStage?.dynamics.over.rawValue.capitalized ?? "Time",
                finalWeightTarget: coordinator.resolvedTargetWeight,
                nominalDuration: currentScenario?.duration ?? 32.0,
                isAlarmActive: simulateAlarm || coordinator.isAlarmActive,
                elapsedTime: coordinator.elapsedTime,
                stageTime: coordinator.stageTime,
                actualWeight: coordinator.actualWeight
            )
            
            // Extracted Simulator Control Dock
            SimulatorControlDockView(
                profiles: profileStore.profiles,
                scenarios: scenarioStore.scenarios,
                selectedProfile: coordinator.activeProfile,
                selectedScenario: currentScenario,
                playbackEngine: playbackEngine,
                simulateAlarm: $simulateAlarm,
                onSelectProfile: selectProfile,
                onSelectScenario: selectScenario
            )
        }
        .onAppear {
            setupPlaybackHooks()
        }
    }
    
    // MARK: - Playback Engine Wiring
    
    private func setupPlaybackHooks() {
        playbackEngine.onTick = { sample, _ in
            let frame = makeMachineFrame(from: sample)
            coordinator.processTelemetryFrame(frame, allowAdvance: true)
            
            if coordinator.state == .shotEnded && playbackEngine.isPlaying {
                playbackEngine.stop()
            }
        }
        
        playbackEngine.onStepBackward = { sample, _ in
            let frame = makeMachineFrame(from: sample)
            coordinator.stepBackward(to: frame)
        }
        
        playbackEngine.onReset = {
            coordinator.resetExecutionState()
        }
    }
    
    private func selectProfile(_ profile: Profile) {
        playbackEngine.stop()
        coordinator.selectProfile(profile)
    }
    
    private func selectScenario(_ scenario: ShotRecord) {
        selectedScenarioID = scenario.id
        playbackEngine.load(scenario: scenario)
        coordinator.resetExecutionState()
    }
    
    private func makeMachineFrame(from sample: ShotSample) -> MachineFrame {
        MachineFrame(
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
    }
}

#Preview(traits: .landscapeLeft) {
    BaristaHUDSimulatorView()
}
