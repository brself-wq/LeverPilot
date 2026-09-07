//
//  BaristaHUDSimulatorView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/6/26.
//

import SwiftUI
import MeticulousProfile

struct BaristaHUDSimulatorView: View {
    @State private var profileStore = ProfileStore()
    @State private var scenarioStore = ScenarioStore()
    
    // Delegated Domain Engine
    private let engine = ProfileExecutionEngine()
    
    // Active Profile & Scenario Selection
    @State private var selectedProfileID: String = ""
    @State private var selectedScenarioID: String = ""
    @State private var activeStageIndex: Int = 0
    @State private var currentStageBaseline = StageBaseline()
    
    // Playback Engine State
    @State private var isPlaying: Bool = false
    @State private var playbackSpeedMultiplier: Double = 1.0 // 0.25x, 0.5x, 1x, 2x
    @State private var currentSampleIndex: Int = 0
    @State private var playbackTask: Task<Void, Never>? = nil
    
    private let availableSpeeds: [Double] = [0.25, 0.5, 1.0, 2.0]
    
    // Live Display Buffers Feeding BaristaHUDView
    @State private var frame: GuidanceFrame = Self.emptyFrame
    @State private var planCurve: [PlanPoint] = []
    @State private var actualHistory: [ActualPoint] = []
    @State private var exitTriggerItems: [ExitTriggerProgressItem] = []
    @State private var stagePills: [StagePillItem] = []
    
    @State private var simulateAlarm: Bool = false
    
    private var currentProfile: Profile? {
        profileStore.profiles.first(where: { $0.id == selectedProfileID }) ?? profileStore.profiles.first
    }
    
    private var availableScenariosForProfile: [ShotRecord] {
        guard let p = currentProfile else { return scenarioStore.scenarios }
        let matched = scenarioStore.scenarios(for: p.id)
        return matched.isEmpty ? scenarioStore.scenarios : matched
    }
    
    private var currentScenario: ShotRecord? {
        availableScenariosForProfile.first(where: { $0.id == selectedScenarioID }) ?? availableScenariosForProfile.first
    }
    
    private var currentStage: Stage? {
        guard let p = currentProfile, p.stages.indices.contains(activeStageIndex) else { return nil }
        return p.stages[activeStageIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Releasable Barista HUD Presentation View
            BaristaHUDView(
                frame: frame,
                planCurve: planCurve,
                actualHistory: actualHistory,
                exitTriggerItems: exitTriggerItems,
                stagePills: stagePills,
                domainLabel: currentStage?.dynamics.over.rawValue.capitalized ?? "Time",
                finalWeightTarget: currentProfile?.finalWeight ?? 40.0,
                nominalDuration: currentScenario?.duration ?? 32.0,
                isAlarmActive: simulateAlarm || (frame.guardrail?.isBreached ?? false)
            )
            
            // Simulation & Playback Control Dock
            HStack(spacing: 10) {
                // 1. Profile Selector Menu
                Menu {
                    ForEach(profileStore.profiles, id: \.id) { profile in
                        Button(profile.name) {
                            selectProfileAndScenario(profile)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text(currentProfile?.name ?? "Profile")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                
                // 2. Scenario Fixture Selector Menu
                Menu {
                    ForEach(availableScenariosForProfile, id: \.id) { scenario in
                        Button(scenario.tastingNotes ?? scenario.id) {
                            stopPlayback()
                            selectedScenarioID = scenario.id
                            resetPlayback()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                        Text(currentScenario?.id ?? "Scenario")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                
                Divider().frame(height: 16)
                
                // 3. Playback Controls (Play / Step Back / Step Forward / Reset / Speed)
                HStack(spacing: 6) {
                    // Play / Pause
                    Button(action: togglePlayback) {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(minWidth: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(isPlaying ? .orange : .blue)
                    
                    // Step Backward (-0.1s)
                    Button(action: stepBackward) {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPlaying || currentSampleIndex == 0)
                    
                    // Step Forward (+0.1s)
                    Button(action: stepForward) {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPlaying || currentSampleIndex >= (currentScenario?.samples.count ?? 0) - 1)
                    
                    // Reset to Beginning
                    Button(action: resetPlayback) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    // Speed Multiplier Cycle (25% -> 50% -> 100% -> 200%)
                    Button(action: cycleSpeed) {
                        Text(speedLabel)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .frame(minWidth: 42)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(playbackSpeedMultiplier != 1.0 ? .cyan : .gray)
                }
                
                // 4. Tick Counter
                if let scenario = currentScenario {
                    Text("TICK: \(currentSampleIndex)/\(scenario.samples.count) (\(String(format: "%.1fs", Double(currentSampleIndex) * 0.1)))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Alarm Toggle
                Toggle("Alarm", isOn: $simulateAlarm)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2)
                    .tint(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.04, green: 0.04, blue: 0.05))
        }
        .onAppear {
            if selectedProfileID.isEmpty {
                if let first = profileStore.profiles.first {
                    selectedProfileID = first.id
                    autoSelectMatchingScenario()
                    setupStage(stageIndex: 0)
                }
            }
        }
    }
    
    // MARK: - Speed Formatting
    
    private var speedLabel: String {
        "\(Int(playbackSpeedMultiplier * 100))%"
    }
    
    private func cycleSpeed() {
        if let idx = availableSpeeds.firstIndex(of: playbackSpeedMultiplier) {
            let next = (idx + 1) % availableSpeeds.count
            playbackSpeedMultiplier = availableSpeeds[next]
        } else {
            playbackSpeedMultiplier = 1.0
        }
    }
    
    // MARK: - Playback Engine Controls
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let scenario = currentScenario, !scenario.samples.isEmpty else { return }
        isPlaying = true
        
        playbackTask = Task { @MainActor in
            while !Task.isCancelled && isPlaying {
                guard currentSampleIndex < scenario.samples.count else {
                    stopPlayback()
                    break
                }
                
                let sample = scenario.samples[currentSampleIndex]
                renderSampleAtCurrentIndex(sample: sample, in: scenario)
                
                currentSampleIndex += 1
                
                let delayMs = UInt64(100.0 / playbackSpeedMultiplier)
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }
    
    private func stepForward() {
        guard let scenario = currentScenario, currentSampleIndex < scenario.samples.count - 1 else { return }
        if isPlaying { stopPlayback() }
        currentSampleIndex += 1
        let sample = scenario.samples[currentSampleIndex]
        renderSampleAtCurrentIndex(sample: sample, in: scenario)
    }
    
    private func stepBackward() {
        guard let scenario = currentScenario, currentSampleIndex > 0 else { return }
        if isPlaying { stopPlayback() }
        currentSampleIndex -= 1
        let sample = scenario.samples[currentSampleIndex]
        renderSampleAtCurrentIndex(sample: sample, in: scenario)
    }
    
    private func stopPlayback() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }
    
    private func resetPlayback() {
        stopPlayback()
        currentSampleIndex = 0
        activeStageIndex = 0
        setupStage(stageIndex: 0)
    }
    
    private func selectProfileAndScenario(_ profile: Profile) {
        stopPlayback()
        selectedProfileID = profile.id
        activeStageIndex = 0
        currentSampleIndex = 0
        if currentScenario?.profileId != profile.id {
            selectedScenarioID = scenarioStore.scenarios(for: profile.id).first?.id ?? ""
        }
        setupStage(stageIndex: 0)
    }
    
    private func jumpToStage(_ index: Int) {
        guard let scenario = currentScenario else { return }
        if let targetSampleIndex = scenario.samples.firstIndex(where: { $0.stageIndex == index }) {
            currentSampleIndex = targetSampleIndex
            let sample = scenario.samples[currentSampleIndex]
            renderSampleAtCurrentIndex(sample: sample, in: scenario)
        } else {
            setupStage(stageIndex: index)
        }
    }
    
    private func autoSelectMatchingScenario() {
        if let matched = availableScenariosForProfile.first {
            selectedScenarioID = matched.id
        }
    }
    
    // MARK: - Simulation Tick Execution (Delegated to ProfileExecutionEngine!)
    
    private func renderSampleAtCurrentIndex(sample: ShotSample, in scenario: ShotRecord) {
        guard let profile = currentProfile else { return }
        
        // 1. Stage Handoff & Baseline Synchronization
        if sample.stageIndex != activeStageIndex && profile.stages.indices.contains(sample.stageIndex) {
            activeStageIndex = sample.stageIndex
            let stageStartSample = scenario.samples.first(where: { $0.stageIndex == activeStageIndex })
            currentStageBaseline = StageBaseline(
                startTime: stageStartSample?.timestamp ?? sample.timestamp,
                startWeight: stageStartSample?.weight ?? sample.weight
            )
        }
        
        guard let stage = currentStage else { return }
        
        // 2. Synthesize MachineFrame from live sample
        let machineFrame = MachineFrame(
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
        
        // 3. Delegate ALL math, limits, and triggers to ProfileExecutionEngine!
        let result = engine.evaluate(
            stage: stage,
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            frame: machineFrame,
            baseline: currentStageBaseline,
            finalWeightTarget: profile.finalWeight
        )
        
        // 4. Update UI Display State
        self.frame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        
        // 5. Rebuild Stage Telemetry Trail (Deterministic history slicing for rewind support)
        let stageStartTime = currentStageBaseline.startTime
        let stageSamples = scenario.samples.enumerated().filter { idx, s in
            s.stageIndex == activeStageIndex && idx <= currentSampleIndex
        }
        
        self.actualHistory = stageSamples.map { _, s in
            let metricVal: Double
            switch stage.type {
            case .pressure: metricVal = s.pressure
            case .flow:     metricVal = s.flow
            case .power:    metricVal = 100.0
            }
            return ActualPoint(x: max(0.0, s.timestamp - stageStartTime), y: metricVal)
        }
        
        // 6. Update Carousel Pills
        self.stagePills = profile.stages.enumerated().map { index, s in
            let icon: String
            switch s.type {
            case .pressure: icon = "gauge.with.dots.needle.bottom.50percent"
            case .flow:     icon = "water.waves"
            case .power:    icon = "bolt.fill"
            }
            let state: StagePillState = index < activeStageIndex ? .completed : (index == activeStageIndex ? .active : .upcoming)
            return StagePillItem(stageNumber: index + 1, title: s.name, icon: icon, state: state)
        }
    }
    
    // MARK: - Initial Stage Setup
    
    private func setupStage(stageIndex: Int) {
        guard let profile = currentProfile, profile.stages.indices.contains(stageIndex) else { return }
        let stage = profile.stages[stageIndex]
        
        currentStageBaseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        let initialFrame = MachineFrame(timestamp: 0.0, state: .shotReady, readings: [:])
        
        // Delegate initial plan & triggers to ProfileExecutionEngine
        let result = engine.evaluate(
            stage: stage,
            stageIndex: stageIndex,
            totalStages: profile.stages.count,
            frame: initialFrame,
            baseline: currentStageBaseline,
            finalWeightTarget: profile.finalWeight
        )
        
        self.actualHistory = []
        self.frame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        
        self.stagePills = profile.stages.enumerated().map { index, s in
            let icon: String
            switch s.type {
            case .pressure: icon = "gauge.with.dots.needle.bottom.50percent"
            case .flow:     icon = "water.waves"
            case .power:    icon = "bolt.fill"
            }
            let state: StagePillState = index < stageIndex ? .completed : (index == stageIndex ? .active : .upcoming)
            return StagePillItem(stageNumber: index + 1, title: s.name, icon: icon, state: state)
        }
    }
    
    private static var emptyFrame: GuidanceFrame {
        GuidanceFrame(
            stageIndex: 0,
            totalStages: 1,
            stageName: "Standby",
            activeMetric: .pressure,
            targetValue: 0.0,
            actualValue: 0.0,
            delta: 0.0,
            elapsedTime: 0.0,
            stageTime: 0.0,
            actualWeight: 0.0,
            stageProgress: 0.0,
            yieldProgress: 0.0,
            guardrail: nil
        )
    }
}

#Preview(traits: .landscapeLeft) {
    BaristaHUDSimulatorView()
}
