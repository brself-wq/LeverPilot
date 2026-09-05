//
//  BaristaHUDSimulatorView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/4/26.
//

import SwiftUI
import MeticulousProfile

struct BaristaHUDSimulatorView: View {
    @State private var profileStore = ProfileStore()
    @State private var scenarioStore = ScenarioStore()
    
    // Active Profile & Scenario
    @State private var selectedProfileID: String = ""
    @State private var activeStageIndex: Int = 0
    
    // Playback Engine State
    @State private var isPlaying: Bool = false
    @State private var playbackSpeedMultiplier: Double = 1.0 // 0.25x, 0.5x, 1x, 2x
    @State private var currentSampleIndex: Int = 0
    @State private var playbackTask: Task<Void, Never>? = nil
    
    private let availableSpeeds: [Double] = [0.25, 0.5, 1.0, 2.0]
    
    // Live Display Buffers
    @State private var frame: GuidanceFrame = Self.emptyFrame
    @State private var planCurve: [PlanPoint] = []
    @State private var actualHistory: [ActualPoint] = []
    @State private var exitTriggerItems: [ExitTriggerProgressItem] = []
    @State private var stagePills: [StagePillItem] = []
    
    @State private var simulateAlarm: Bool = false
    
    private var currentProfile: Profile? {
        profileStore.profiles.first(where: { $0.id == selectedProfileID }) ?? profileStore.profiles.first
    }
    
    private var currentScenario: ShotRecord? {
        guard let p = currentProfile else { return scenarioStore.scenarios.first }
        return scenarioStore.scenarios(for: p.id).first ?? scenarioStore.scenarios.first
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
                isAlarmActive: simulateAlarm || (frame.guardrail?.isBreached ?? false),
                onSelectStage: { index in
                    if !isPlaying {
                        activeStageIndex = index
                        resetPlaybackToStage(index)
                    }
                }
            )
            
            // Simulation & Playback Control Dock
            HStack(spacing: 12) {
                // Profile Selector Menu
                Menu {
                    ForEach(profileStore.profiles, id: \.id) { profile in
                        Button(profile.name) {
                            stopPlayback()
                            selectedProfileID = profile.id
                            activeStageIndex = 0
                            currentSampleIndex = 0
                            setupStage(stageIndex: 0)
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
                
                Divider().frame(height: 16)
                
                // Playback Controls (Play / Step / Reset / Speed)
                HStack(spacing: 6) {
                    // Play / Pause
                    Button(action: togglePlayback) {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(minWidth: 65)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(isPlaying ? .orange : .blue)
                    
                    // Single-Step Forward (+0.1s Tick)
                    Button(action: stepForward) {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPlaying || currentSampleIndex >= (currentScenario?.samples.count ?? 0))
                    
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
                
                // Sample Progress Counter
                if let scenario = currentScenario {
                    Text("TICK: \(currentSampleIndex) / \(scenario.samples.count) (\(String(format: "%.1fs", Double(currentSampleIndex) * 0.1)))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Alarm Simulator Toggle
                Toggle("Alarm", isOn: $simulateAlarm)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2)
                    .tint(.red)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(red: 0.04, green: 0.04, blue: 0.05))
        }
        .onAppear {
            autoSyncProfileAndScenario()
        }
    }
    
    // MARK: - Speed Formatting (Percentages)
        
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
    
    // MARK: - Playback Engine Logic
    
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
                advanceSimulationTick(with: sample, in: scenario)
                
                currentSampleIndex += 1
                
                // Scaled delay (e.g. 100ms / 0.5 = 200ms sleep)
                let delayMs = UInt64(100.0 / playbackSpeedMultiplier)
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }
    
    /// Advance exactly ONE 100ms tick (+0.1s)
    private func stepForward() {
        guard let scenario = currentScenario, currentSampleIndex < scenario.samples.count else { return }
        if isPlaying { stopPlayback() }
        
        let sample = scenario.samples[currentSampleIndex]
        advanceSimulationTick(with: sample, in: scenario)
        currentSampleIndex += 1
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
        actualHistory.removeAll()
        setupStage(stageIndex: 0)
    }
    
    private func resetPlaybackToStage(_ index: Int) {
        guard let scenario = currentScenario else { return }
        if let firstSampleIndex = scenario.samples.firstIndex(where: { $0.stageIndex == index }) {
            currentSampleIndex = firstSampleIndex
        }
        setupStage(stageIndex: index)
    }
    
    private func autoSyncProfileAndScenario() {
        // Look for scenario linked to profile, or link profile to scenario!
        if let scenario = scenarioStore.scenarios.first,
           let matchedProfile = profileStore.profile(withID: scenario.profileId) {
            selectedProfileID = matchedProfile.id
        } else if let firstProfile = profileStore.profiles.first {
            selectedProfileID = firstProfile.id
        }
        setupStage(stageIndex: 0)
    }
    
    // MARK: - 10 Hz Simulation Tick Processor
    
    private func advanceSimulationTick(with sample: ShotSample, in scenario: ShotRecord) {
        guard let profile = currentProfile else { return }
        
        // 1. Detect Stage Handoff
        if sample.stageIndex != activeStageIndex && profile.stages.indices.contains(sample.stageIndex) {
            activeStageIndex = sample.stageIndex
            actualHistory.removeAll()
            setupStagePlanCurve(for: sample.stageIndex)
        }
        
        guard let stage = currentStage else { return }
        
        // 2. Determine Metric Values for this tick
        let activeMetric: SensorKey
        let actualMetricValue: Double
        let targetMetricValue: Double
        
        switch stage.type {
        case .pressure:
            activeMetric = .pressure
            actualMetricValue = sample.pressure
            targetMetricValue = sample.targetPressure ?? evaluateTarget(at: sample.timestamp, stage: stage)
        case .flow:
            activeMetric = .flow
            actualMetricValue = sample.flow
            targetMetricValue = sample.targetFlow ?? evaluateTarget(at: sample.timestamp, stage: stage)
        case .power:
            activeMetric = .power
            actualMetricValue = 100.0
            targetMetricValue = 100.0
        }
        
        // 3. Append to Stage Telemetry Trail
        let stageStartSample = scenario.samples.first(where: { $0.stageIndex == activeStageIndex })
        let stageStartTime = stageStartSample?.timestamp ?? 0.0
        let localStageTime = max(0.0, sample.timestamp - stageStartTime)
        
        actualHistory.append(ActualPoint(x: localStageTime, y: actualMetricValue))
        
        // 4. Update Exit Trigger Progress ("The Race")
        updateExitTriggers(for: stage, sample: sample, localTime: localStageTime, profile: profile)
        
        // 5. Update Limit Status
        let limitStatus = evaluateLimit(stage: stage, sample: sample)
        
        // 6. Project Live GuidanceFrame
        let yieldRatio = min(1.0, sample.weight / (profile.finalWeight))
        let stageProgressRatio = exitTriggerItems.map(\.progress).max() ?? yieldRatio
        
        self.frame = GuidanceFrame(
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            stageName: stage.name,
            activeMetric: activeMetric,
            targetValue: targetMetricValue,
            actualValue: actualMetricValue,
            delta: actualMetricValue - targetMetricValue,
            stageProgress: stageProgressRatio,
            yieldProgress: yieldRatio,
            guardrail: limitStatus
        )
        
        // 7. Update Carousel Pills
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
    
    // MARK: - Stage Setup & Curve Math
    
    private func setupStage(stageIndex: Int) {
        guard let profile = currentProfile, profile.stages.indices.contains(stageIndex) else { return }
        let stage = profile.stages[stageIndex]
        
        setupStagePlanCurve(for: stageIndex)
        
        let activeMetric: SensorKey = stage.type == .pressure ? .pressure : (stage.type == .flow ? .flow : .power)
        let initialTarget = planCurve.first?.y ?? 2.0
        
        self.frame = GuidanceFrame(
            stageIndex: stageIndex,
            totalStages: profile.stages.count,
            stageName: stage.name,
            activeMetric: activeMetric,
            targetValue: initialTarget,
            actualValue: 0.0,
            delta: 0.0,
            stageProgress: 0.0,
            yieldProgress: 0.0,
            guardrail: evaluateLimit(stage: stage, sample: nil)
        )
        
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
    
    private func setupStagePlanCurve(for stageIndex: Int) {
        guard let profile = currentProfile, profile.stages.indices.contains(stageIndex) else { return }
        let stage = profile.stages[stageIndex]
        
        let rawKnots: [(x: Double, y: Double)] = stage.dynamics.points.compactMap { pt in
            guard let x = pt.x.numericValue, let y = pt.y.numericValue else { return nil }
            return (x: x, y: y)
        }
        
        let maxKnotX = rawKnots.map(\.x).max() ?? 0.0
        let timeTriggerVal = stage.exitTriggers?.first(where: { $0.type == .time })?.value.numericValue ?? 0.0
        let stageHorizon = max(maxKnotX, timeTriggerVal, 10.0)
        
        var points: [PlanPoint] = []
        if rawKnots.isEmpty {
            points = [PlanPoint(x: 0, y: 0), PlanPoint(x: stageHorizon, y: 0)]
        } else if rawKnots.count == 1 {
            let singleY = rawKnots[0].y
            points = [PlanPoint(x: 0, y: singleY), PlanPoint(x: stageHorizon, y: singleY)]
        } else {
            for knot in rawKnots {
                points.append(PlanPoint(x: knot.x, y: knot.y))
            }
            if let lastKnot = rawKnots.last, lastKnot.x < stageHorizon {
                points.append(PlanPoint(x: stageHorizon, y: lastKnot.y))
            }
        }
        self.planCurve = points
    }
    
    private func updateExitTriggers(for stage: Stage, sample: ShotSample, localTime: Double, profile: Profile) {
        var items: [ExitTriggerProgressItem] = []
        
        if let triggers = stage.exitTriggers, !triggers.isEmpty {
            for trigger in triggers {
                let targetVal = trigger.value.numericValue ?? 5.0
                let currentVal: Double
                let sensorKey: SensorKey
                let icon: String
                let unit: String
                
                switch trigger.type {
                case .time:
                    sensorKey = .time
                    icon = "clock.fill"
                    unit = "s"
                    currentVal = localTime
                case .weight:
                    sensorKey = .weight
                    icon = "scalemass.fill"
                    unit = "g"
                    currentVal = sample.weight
                case .pressure:
                    sensorKey = .pressure
                    icon = "gauge.with.dots.needle.bottom.50percent"
                    unit = "bar"
                    currentVal = sample.pressure
                case .flow:
                    sensorKey = .flow
                    icon = "water.waves"
                    unit = "mL/s"
                    currentVal = sample.flow
                default:
                    sensorKey = .power
                    icon = "bolt.fill"
                    unit = "%"
                    currentVal = 100.0
                }
                
                let progress = targetVal > 0 ? min(1.0, currentVal / targetVal) : 0.0
                items.append(ExitTriggerProgressItem(
                    sensorKey: sensorKey,
                    icon: icon,
                    label: trigger.type.displayName,
                    currentString: String(format: "%.1f%@", currentVal, unit),
                    targetString: String(format: "%.1f%@", targetVal, unit),
                    progress: progress,
                    isLeading: false
                ))
            }
            
            // Mark the leading trigger (highest progress ratio)
            if let maxProgress = items.map(\.progress).max(), maxProgress > 0 {
                if let leadingIdx = items.firstIndex(where: { $0.progress == maxProgress }) {
                    let old = items[leadingIdx]
                    items[leadingIdx] = ExitTriggerProgressItem(
                        sensorKey: old.sensorKey,
                        icon: old.icon,
                        label: old.label,
                        currentString: old.currentString,
                        targetString: old.targetString,
                        progress: old.progress,
                        isLeading: true
                    )
                }
            }
        } else {
            let targetWeight = profile.finalWeight
            let progress = min(1.0, sample.weight / targetWeight)
            items.append(ExitTriggerProgressItem(
                sensorKey: .weight,
                icon: "scalemass.fill",
                label: "Final Weight Cutoff",
                currentString: String(format: "%.1fg", sample.weight),
                targetString: String(format: "%.1fg", targetWeight),
                progress: progress,
                isLeading: true
            ))
        }
        
        self.exitTriggerItems = items
    }
    
    private func evaluateLimit(stage: Stage, sample: ShotSample?) -> GuardrailStatus? {
        guard let limit = stage.limits?.first, let limitVal = limit.value.numericValue else { return nil }
        let limitMetric: SensorKey = (limit.type == .pressure) ? .pressure : .flow
        
        let actual: Double
        if let s = sample {
            actual = limitMetric == .pressure ? s.pressure : s.flow
        } else {
            actual = 0.0
        }
        
        return GuardrailStatus(
            metric: limitMetric,
            limitValue: limitVal,
            actualValue: actual,
            isBreached: actual > limitVal
        )
    }
    
    private func evaluateTarget(at time: Double, stage: Stage) -> Double {
        let rawKnots: [(x: Double, y: Double)] = stage.dynamics.points.compactMap { pt in
            guard let x = pt.x.numericValue, let y = pt.y.numericValue else { return nil }
            return (x: x, y: y)
        }
        guard let first = rawKnots.first else { return 0.0 }
        if rawKnots.count == 1 || time <= first.x { return first.y }
        if let last = rawKnots.last, time >= last.x { return last.y }
        
        for i in 0..<(rawKnots.count - 1) {
            let p0 = rawKnots[i]
            let p1 = rawKnots[i + 1]
            if time >= p0.x && time <= p1.x {
                let ratio = (time - p0.x) / (p1.x - p0.x)
                return p0.y + ratio * (p1.y - p0.y)
            }
        }
        return first.y
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

#Preview {
    BaristaHUDSimulatorView()
        .previewInterfaceOrientation(.landscapeLeft)
}
