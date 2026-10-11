//
//  ShotPlaybackController.swift
//  LeverPilot
//

import Foundation
import Observation
import MeticulousProfile

@Observable
@MainActor
public final class ShotPlaybackController {
    
    // MARK: - Playback State
    public private(set) var isPlaying: Bool = false
    public private(set) var currentSampleIndex: Int = 0
    public private(set) var playbackSpeedMultiplier: Double = 1.0
    public private(set) var scenario: ShotRecord? = nil
    
    // MARK: - Configuration
    public let availableSpeeds: [Double] = [0.25, 0.5, 1.0, 2.0]
    
    // MARK: - Legacy Event Hooks (Preserved for PlaybackEngineTests)
    public var onTick: ((_ sample: ShotSample, _ scenario: ShotRecord) -> Void)?
    public var onStepBackward: ((_ sample: ShotSample, _ scenario: ShotRecord) -> Void)?
    public var onReset: (() -> Void)?
    
    // MARK: - Internal Engine Dependencies
    @ObservationIgnored private var playbackTask: Task<Void, Never>? = nil
    @ObservationIgnored private let executionEngine = ProfileExecutionEngine()
    
    public init(scenario: ShotRecord? = nil) {
        self.scenario = scenario
    }
    
    // MARK: - Scenario Management
    
    public func load(scenario: ShotRecord?) {
        stop()
        self.scenario = scenario
        self.currentSampleIndex = 0
        self.onReset?()
    }
    
    // MARK: - Cursor & Telemetry Status
    
    public var currentSample: ShotSample? {
        guard let samples = scenario?.samples, samples.indices.contains(currentSampleIndex) else { return nil }
        return samples[currentSampleIndex]
    }
    
    public var totalSamplesCount: Int {
        scenario?.samples.count ?? 0
    }
    
    public var currentTimestamp: Double {
        currentSample?.timestamp ?? (Double(currentSampleIndex) * 0.1)
    }
    
    public var speedLabel: String {
        "\(Int(playbackSpeedMultiplier * 100))%"
    }
    
    public var canStepForward: Bool {
        guard let scenario, !scenario.samples.isEmpty else { return false }
        return !isPlaying && currentSampleIndex < scenario.samples.count - 1
    }
    
    public var canStepBackward: Bool {
        guard let scenario, !scenario.samples.isEmpty else { return false }
        return !isPlaying && currentSampleIndex > 0
    }
    
    public var tickStatusString: String {
        if let scenario {
            return "TICK: \(currentSampleIndex)/\(scenario.samples.count) (\(String(format: "%.1fs", currentTimestamp)))"
        } else {
            return "TICK: --/-- (0.0s)"
        }
    }
    
    // MARK: - Playback Controls
    
    public func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func play() {
        guard let scenario, !scenario.samples.isEmpty else { return }
        isPlaying = true
        
        playbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { break }
                guard self.currentSampleIndex < scenario.samples.count - 1 else {
                    self.stop()
                    break
                }
                
                self.currentSampleIndex += 1
                let sample = scenario.samples[self.currentSampleIndex]
                self.onTick?(sample, scenario)
                
                let delayMs = UInt64(100.0 / self.playbackSpeedMultiplier)
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }
    
    public func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }
    
    public func stop() {
        pause()
    }
    
    public func stepForward() {
        guard let scenario, currentSampleIndex < scenario.samples.count - 1 else { return }
        if isPlaying { pause() }
        currentSampleIndex += 1
        let sample = scenario.samples[currentSampleIndex]
        onTick?(sample, scenario)
    }
    
    public func stepBackward() {
        guard let scenario, currentSampleIndex > 0 else { return }
        if isPlaying { pause() }
        currentSampleIndex -= 1
        let sample = scenario.samples[currentSampleIndex]
        onStepBackward?(sample, scenario)
    }
    
    public func seek(to index: Int) {
        guard let scenario, !scenario.samples.isEmpty else { return }
        if isPlaying { pause() }
        currentSampleIndex = max(0, min(index, scenario.samples.count - 1))
        if let sample = currentSample {
            onTick?(sample, scenario)
        }
    }
    
    public func reset() {
        stop()
        currentSampleIndex = 0
        onReset?()
    }
    
    public func cycleSpeed() {
        if let idx = availableSpeeds.firstIndex(of: playbackSpeedMultiplier) {
            let next = (idx + 1) % availableSpeeds.count
            playbackSpeedMultiplier = availableSpeeds[next]
        } else {
            playbackSpeedMultiplier = 1.0
        }
    }
    
    // MARK: - BaristaHUDView Presentation Projections
    
    public var activeStageIndex: Int {
        currentSample?.stageIndex ?? 0
    }
    
    public var activeProfile: Profile? {
        scenario?.profileSnapshot
    }
    
    public var currentStage: Stage? {
        guard let profile = activeProfile, profile.stages.indices.contains(activeStageIndex) else { return nil }
        return profile.stages[activeStageIndex]
    }
    
    public var resolvedTargetWeight: Double {
        scenario?.targetWeight ?? activeProfile?.finalWeight ?? 36.0
    }
    
    public var nominalDuration: Double {
        scenario?.duration ?? 32.0
    }
    
    public var domainLabel: String {
        currentStage?.dynamics.over.rawValue.capitalized ?? "Time"
    }
    
    /// Deterministic Stage Baseline derived purely from the first sample recorded in that stage.
    public func baseline(for stageIndex: Int) -> StageBaseline {
        guard let first = scenario?.samples.first(where: { $0.stageIndex == stageIndex }) else {
            return StageBaseline()
        }
        return StageBaseline(
            startTime: first.timestamp,
            startWeight: first.weight,
            entryPressure: first.pressure,
            entryFlow: first.flow
        )
    }
    
    public var stageBaseline: StageBaseline {
        baseline(for: activeStageIndex)
    }
    
    /// Evaluates the recipe stage dynamics for the current sample frame.
    private var executionResult: StageEvaluationResult? {
        guard let stage = currentStage, let profile = activeProfile, let sample = currentSample else { return nil }
        
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
        
        return executionEngine.evaluate(
            stage: stage,
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            frame: frame,
            baseline: stageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
    }
    
    public var guidanceFrame: GuidanceFrame {
        if let result = executionResult {
            return result.guidanceFrame
        }
        
        // Fallback static projection from ShotSample
        let sample = currentSample
        let target = sample?.targetPressure ?? sample?.targetFlow ?? 0.0
        let actual = sample?.pressure ?? 0.0
        return GuidanceFrame(
            stageIndex: activeStageIndex,
            totalStages: activeProfile?.stages.count ?? 1,
            stageName: currentStage?.name ?? "Replay",
            activeMetric: currentStage?.type == .flow ? .flow : .pressure,
            targetValue: target,
            actualValue: actual,
            delta: actual - target,
            elapsedTime: currentTimestamp,
            stageTime: max(0.0, currentTimestamp - stageBaseline.startTime),
            actualWeight: sample?.weight ?? 0.0,
            stageProgress: 0.0,
            yieldProgress: resolvedTargetWeight > 0 ? (sample?.weight ?? 0.0) / resolvedTargetWeight : 0.0,
            guardrail: nil
        )
    }
    
    public var planCurve: [PlanPoint] {
        executionResult?.planCurve ?? []
    }
    
    public var exitTriggerItems: [ExitTriggerProgressItem] {
        executionResult?.exitTriggerItems ?? []
    }
    
    /// Actual telemetry points for the current stage up to the current sample cursor.
    public var actualHistory: [ActualPoint] {
        guard let samples = scenario?.samples, !samples.isEmpty else { return [] }
        let stageStart = stageBaseline.startTime
        let activeStageType = currentStage?.type ?? .pressure
        
        let stageSamples = samples.prefix(through: currentSampleIndex)
            .filter { $0.stageIndex == activeStageIndex }
        
        return stageSamples.map { sample in
            let pointX = max(0.0, sample.timestamp - stageStart)
            let pointY: Double
            switch activeStageType {
            case .pressure: pointY = sample.pressure
            case .flow:     pointY = sample.flow
            case .power:    pointY = 100.0
            }
            return ActualPoint(x: pointX, y: pointY)
        }
    }
    
    public var stagePills: [StagePillItem] {
        guard let profile = activeProfile else { return [] }
        return profile.stages.enumerated().map { index, stage in
            let icon: String
            switch stage.type {
            case .pressure: icon = "gauge.with.dots.needle.bottom.50percent"
            case .flow:     icon = "water.waves"
            case .power:    icon = "bolt.fill"
            }
            let pillState: StagePillState = index < activeStageIndex ? .completed : (index == activeStageIndex ? .active : .upcoming)
            return StagePillItem(stageNumber: index + 1, title: stage.name, icon: icon, state: pillState)
        }
    }
    
    /// Closing reticle progress: 0.0 -> 1.0 (touchdown) -> >1.125 (overrun).
    public var approachProgress: Double? {
        guard let sample = currentSample, resolvedTargetWeight > 0 else { return nil }
        let acquisitionStart = resolvedTargetWeight - ShotCoordinator.acquisitionWindowGrams
        if sample.weight >= acquisitionStart {
            let progress = (sample.weight - acquisitionStart) / ShotCoordinator.acquisitionWindowGrams
            return max(0.0, progress)
        }
        return nil
    }
}
