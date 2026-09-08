//
//  BaristaHUDSimulatorView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/6/26.
//

import SwiftUI
import MeticulousProfile

struct BaristaHUDSimulatorView: View {
    // Data Stores
    @State private var profileStore = ProfileStore()
    @State private var scenarioStore = ScenarioStore()
    
    // Domain Engines
    private let executionEngine = ProfileExecutionEngine()
    @State private var playbackEngine = PlaybackEngine()
    
    // Active Selections (Unselected at launch)
    @State private var selectedProfileID: String = ""
    @State private var selectedScenarioID: String = ""
    
    // Execution Baseline Tracking
    @State private var activeStageIndex: Int = 0
    @State private var currentStageBaseline = StageBaseline()
    @State private var stageBaselines: [Int: StageBaseline] = [0: StageBaseline(startTime: 0.0, startWeight: 0.0)]
    
    // Buffers feeding BaristaHUDView
    @State private var frame: GuidanceFrame = Self.emptyFrame
    @State private var planCurve: [PlanPoint] = []
    @State private var actualHistory: [ActualPoint] = []
    @State private var exitTriggerItems: [ExitTriggerProgressItem] = []
    @State private var stagePills: [StagePillItem] = []
    
    // Live Clocks & Yield
    @State private var currentElapsedTime: Double = 0.0
    @State private var currentStageTime: Double = 0.0
    @State private var currentActualWeight: Double = 0.0
    
    @State private var simulateAlarm: Bool = false
    
    private var currentProfile: Profile? {
        guard !selectedProfileID.isEmpty else { return nil }
        return profileStore.profiles.first(where: { $0.id == selectedProfileID })
    }
    
    private var currentScenario: ShotRecord? {
        guard !selectedScenarioID.isEmpty else { return nil }
        return scenarioStore.scenarios.first(where: { $0.id == selectedScenarioID })
    }
    
    private var currentStage: Stage? {
        guard let p = currentProfile, p.stages.indices.contains(activeStageIndex) else { return nil }
        return p.stages[activeStageIndex]
    }
    
    // Dynamically resolves target yield from finalWeight, exit triggers, or profile stages
    private var resolvedTargetWeight: Double {
        if let fw = currentProfile?.finalWeight, fw > 0 {
            return fw
        }
        if let weightItem = exitTriggerItems.first(where: { $0.sensorKey == .weight }) {
            let numStr = weightItem.targetString.replacingOccurrences(of: "g", with: "").trimmingCharacters(in: .whitespaces)
            if let val = Double(numStr), val > 0 {
                return val
            }
        }
        if let profile = currentProfile {
            for stage in profile.stages.reversed() {
                if let triggers = stage.exitTriggers,
                   let trigger = triggers.first(where: { $0.type == .weight }),
                   let target = trigger.value.numericValue, target > 0 {
                    return target
                }
            }
        }
        return currentProfile != nil ? 36.0 : 0.0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Production Barista HUD Presentation View
            BaristaHUDView(
                frame: frame,
                planCurve: planCurve,
                actualHistory: actualHistory,
                exitTriggerItems: exitTriggerItems,
                stagePills: stagePills,
                domainLabel: currentStage?.dynamics.over.rawValue.capitalized ?? "Time",
                finalWeightTarget: resolvedTargetWeight,
                nominalDuration: currentScenario?.duration ?? 32.0,
                isAlarmActive: simulateAlarm || (frame.guardrail?.isBreached ?? false),
                elapsedTime: currentElapsedTime,
                stageTime: currentStageTime,
                actualWeight: currentActualWeight
            )
            
            // Extracted Simulator Control Dock
            SimulatorControlDockView(
                profiles: profileStore.profiles,
                scenarios: scenarioStore.scenarios,
                selectedProfile: currentProfile,
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
        playbackEngine.onTick = { [self] sample, scenario in
            self.renderSample(sample: sample, in: scenario, allowAdvance: true)
        }
        
        playbackEngine.onStepBackward = { [self] sample, scenario in
            if self.activeStageIndex > 0 && sample.timestamp < self.currentStageBaseline.startTime {
                self.activeStageIndex -= 1
                self.currentStageBaseline = self.stageBaselines[self.activeStageIndex] ?? StageBaseline(startTime: 0.0, startWeight: 0.0)
            }
            self.renderSample(sample: sample, in: scenario, allowAdvance: false)
        }
        
        playbackEngine.onReset = { [self] in
            self.activeStageIndex = 0
            self.currentStageBaseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
            self.stageBaselines = [0: self.currentStageBaseline]
            self.currentElapsedTime = 0.0
            self.currentStageTime = 0.0
            self.currentActualWeight = 0.0
            self.setupInitialStage(stageIndex: 0)
        }
    }
    
    private func selectProfile(_ profile: Profile) {
        playbackEngine.stop()
        selectedProfileID = profile.id
        activeStageIndex = 0
        currentStageBaseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        stageBaselines = [0: currentStageBaseline]
        currentElapsedTime = 0.0
        currentStageTime = 0.0
        currentActualWeight = 0.0
        setupInitialStage(stageIndex: 0)
    }
    
    private func selectScenario(_ scenario: ShotRecord) {
        selectedScenarioID = scenario.id
        playbackEngine.load(scenario: scenario)
        if currentProfile != nil {
            setupInitialStage(stageIndex: 0)
        }
    }
    
    // MARK: - Telemetry Tick Evaluation
    
    private func renderSample(sample: ShotSample, in scenario: ShotRecord, allowAdvance: Bool) {
        guard let profile = currentProfile, let stage = currentStage else { return }
        
        // 1. Synthesize MachineFrame from mock sample
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
        
        // 2. Evaluate against domain engine
        var result = executionEngine.evaluate(
            stage: stage,
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            frame: machineFrame,
            baseline: currentStageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
        
        // 3. Engine-driven stage progression
        if allowAdvance && result.shouldAdvanceStage {
            if activeStageIndex + 1 < profile.stages.count {
                activeStageIndex += 1
                currentStageBaseline = StageBaseline(
                    startTime: sample.timestamp,
                    startWeight: sample.weight
                )
                stageBaselines[activeStageIndex] = currentStageBaseline
                
                if let nextStage = currentStage {
                    result = executionEngine.evaluate(
                        stage: nextStage,
                        stageIndex: activeStageIndex,
                        totalStages: profile.stages.count,
                        frame: machineFrame,
                        baseline: currentStageBaseline,
                        finalWeightTarget: resolvedTargetWeight
                    )
                }
            } else if playbackEngine.isPlaying {
                playbackEngine.stop()
            }
        }
        
        // 4. Update HUD presentation state
        self.frame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        self.currentElapsedTime = sample.timestamp
        self.currentStageTime = max(0.0, sample.timestamp - currentStageBaseline.startTime)
        self.currentActualWeight = sample.weight
        
        // 5. Slice telemetry trail for current stage
        let stageStartTime = currentStageBaseline.startTime
        let stageSamples = scenario.samples.enumerated().filter { idx, s in
            s.timestamp >= (stageStartTime - 0.001) && idx <= playbackEngine.currentSampleIndex
        }
        
        let activeStage = currentStage ?? stage
        self.actualHistory = stageSamples.map { _, s in
            let metricVal: Double
            switch activeStage.type {
            case .pressure: metricVal = s.pressure
            case .flow:     metricVal = s.flow
            case .power:    metricVal = 100.0
            }
            return ActualPoint(x: max(0.0, s.timestamp - stageStartTime), y: metricVal)
        }
        
        // 6. Update stage pills
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
    
    private func setupInitialStage(stageIndex: Int) {
        guard let profile = currentProfile, profile.stages.indices.contains(stageIndex) else {
            self.actualHistory = []
            self.frame = Self.emptyFrame
            self.planCurve = []
            self.exitTriggerItems = []
            self.stagePills = []
            return
        }
        
        let stage = profile.stages[stageIndex]
        currentStageBaseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        let initialFrame = MachineFrame(timestamp: 0.0, state: .shotReady, readings: [:])
        
        let result = executionEngine.evaluate(
            stage: stage,
            stageIndex: stageIndex,
            totalStages: profile.stages.count,
            frame: initialFrame,
            baseline: currentStageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
        
        self.actualHistory = []
        self.frame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        self.currentElapsedTime = 0.0
        self.currentStageTime = 0.0
        self.currentActualWeight = 0.0
        
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
            stageProgress: 0.0,
            yieldProgress: 0.0,
            guardrail: nil
        )
    }
}

#Preview(traits: .landscapeLeft) {
    BaristaHUDSimulatorView()
}
