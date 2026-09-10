//
//  ShotCoordinator.swift
//  VirtualEspressoMachine
//

import Foundation
import Observation
import MeticulousProfile

@Observable
@MainActor
public final class ShotCoordinator {
    
    // MARK: - Machine Lifecycle State
    public private(set) var state: MachineState = .idle
    public private(set) var currentFrame: MachineFrame = MachineFrame(state: .idle)
    
    // MARK: - Active Profile & Recipe Execution
    public private(set) var activeProfile: Profile? = nil
    public private(set) var activeStageIndex: Int = 0
    public private(set) var currentStageBaseline: StageBaseline = StageBaseline()
    public private(set) var stageBaselines: [Int: StageBaseline] = [0: StageBaseline()]
    
    // MARK: - Surface Guidance Buffers (Feeds BaristaHUDView)
    public private(set) var guidanceFrame: GuidanceFrame = ShotCoordinator.emptyGuidanceFrame
    public private(set) var planCurve: [PlanPoint] = []
    public private(set) var actualHistory: [ActualPoint] = []
    public private(set) var exitTriggerItems: [ExitTriggerProgressItem] = []
    public private(set) var stagePills: [StagePillItem] = []
    
    // MARK: - Live Telemetry Clocks
    public private(set) var elapsedTime: Double = 0.0
    public private(set) var stageTime: Double = 0.0
    public private(set) var actualWeight: Double = 0.0
    public var isAlarmActive: Bool = false
    
    // MARK: - Internal Dependencies
    private let executionEngine = ProfileExecutionEngine()
    @ObservationIgnored private var telemetryTask: Task<Void, Never>?
    public private(set) weak var telemetryProvider: (any TelemetryProvider)?
    
    public init() {}
    
    // MARK: - Computed Properties
    
    public var currentStage: Stage? {
        guard let p = activeProfile, p.stages.indices.contains(activeStageIndex) else { return nil }
        return p.stages[activeStageIndex]
    }
    
    public var resolvedTargetWeight: Double {
        if let fw = activeProfile?.finalWeight, fw > 0 {
            return fw
        }
        if let profile = activeProfile {
            for stage in profile.stages.reversed() {
                if let triggers = stage.exitTriggers,
                   let trigger = triggers.first(where: { $0.type == .weight }),
                   let target = trigger.value.numericValue, target > 0 {
                    return target
                }
            }
        }
        return activeProfile != nil ? 36.0 : 0.0
    }
    
    // MARK: - Profile Selection & Setup
    
    public func selectProfile(_ profile: Profile) {
        self.activeProfile = profile
        self.state = .armed // Immediately arm the digital twin observer
        resetExecutionState()
    }
    
    public func resetExecutionState() {
        self.activeStageIndex = 0
        self.currentStageBaseline = StageBaseline()
        self.stageBaselines = [0: self.currentStageBaseline]
        self.elapsedTime = 0.0
        self.stageTime = 0.0
        self.actualWeight = 0.0
        self.actualHistory = []
        self.isAlarmActive = false
        
        setupInitialStage(stageIndex: 0)
    }
    
    // MARK: - Machine State Transitions
    
    public func arm() {
        guard state == .idle || state == .shotEnded || state == .purging else { return }
        state = .armed
    }
    
    public func startExtraction() {
        guard state == .armed || state == .idle else { return }
        state = .extracting
    }
    
    public func endExtraction() {
        state = .shotEnded
    }
    
    public func purge() {
        state = .purging
    }
    
    public func triggerError() {
        state = .error
    }
    
    public func abort() {
        state = .idle
        resetExecutionState()
    }
    
    // MARK: - Telemetry Binding & Loop
    
    public func attach(telemetryProvider: any TelemetryProvider) {
        self.telemetryProvider = telemetryProvider
        telemetryTask?.cancel()
        
        telemetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await frame in telemetryProvider.frames {
                guard !Task.isCancelled else { break }
                self.processTelemetryFrame(frame)
            }
        }
    }
    
    public func detachTelemetry() {
        telemetryTask?.cancel()
        telemetryTask = nil
        self.telemetryProvider = nil
    }
    
    // MARK: - Frame Processing & Progression
    
    public func processTelemetryFrame(_ frame: MachineFrame, allowAdvance: Bool = true) {
        self.currentFrame = frame
        let currentPressure = frame[.pressure] ?? 0.0
        let currentFlow = frame[.flow] ?? 0.0
        let currentWeight = frame[.weight] ?? 0.0
        
        // Auto-Start: Lever pull (pressure >= 0.5 bar), scale drip (weight >= 0.5g), or incoming extraction frames
        if state == .armed && (currentPressure >= 0.5 || currentWeight >= 0.5 || frame.state == .extracting) {
            state = .extracting
        }
        
        guard state == .extracting, let profile = activeProfile, let stage = currentStage else {
            return
        }
        
        // 1. Evaluate against stateless execution engine
        var result = executionEngine.evaluate(
            stage: stage,
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            frame: frame,
            baseline: currentStageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
        
        // 2. Evaluate stage progression
        if allowAdvance && result.shouldAdvanceStage {
            if activeStageIndex + 1 < profile.stages.count {
                activeStageIndex += 1
                currentStageBaseline = StageBaseline(
                    startTime: frame.timestamp,
                    startWeight: currentWeight,
                    entryPressure: currentPressure,
                    entryFlow: currentFlow
                )
                stageBaselines[activeStageIndex] = currentStageBaseline
                actualHistory.removeAll()
                
                if let nextStage = currentStage {
                    result = executionEngine.evaluate(
                        stage: nextStage,
                        stageIndex: activeStageIndex,
                        totalStages: profile.stages.count,
                        frame: frame,
                        baseline: currentStageBaseline,
                        finalWeightTarget: resolvedTargetWeight
                    )
                }
            } else {
                // Reached end of final stage
                endExtraction()
            }
        }
        
        // 3. Update Surface Presentation State
        self.guidanceFrame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        self.elapsedTime = frame.timestamp
        self.stageTime = max(0.0, frame.timestamp - currentStageBaseline.startTime)
        self.actualWeight = currentWeight
        self.isAlarmActive = result.guidanceFrame.guardrail?.isBreached ?? false
        
        // 4. Append historical telemetry point for active stage
        let activeStage = currentStage ?? stage
        let metricVal: Double
        switch activeStage.type {
        case .pressure: metricVal = currentPressure
        case .flow:     metricVal = currentFlow
        case .power:    metricVal = frame[.power] ?? 100.0
        }
        let pointX = max(0.0, frame.timestamp - currentStageBaseline.startTime)
        self.actualHistory.append(ActualPoint(x: pointX, y: metricVal))
        
        // 5. Update Stage Pills
        updateStagePills(for: profile, activeIndex: activeStageIndex)
    }
    
    // MARK: - Rehearsal / Stepping Backward
    
    public func stepBackward(to frame: MachineFrame) {
        if activeStageIndex > 0 && frame.timestamp < currentStageBaseline.startTime {
            activeStageIndex -= 1
            currentStageBaseline = stageBaselines[activeStageIndex] ?? StageBaseline()
        }
        
        let stageStart = currentStageBaseline.startTime
        let currentX = max(0.0, frame.timestamp - stageStart)
        actualHistory.removeAll { $0.x > currentX }
        
        processTelemetryFrame(frame, allowAdvance: false)
    }
    
    // MARK: - Helpers
    
    private func setupInitialStage(stageIndex: Int) {
        guard let profile = activeProfile, profile.stages.indices.contains(stageIndex) else {
            self.actualHistory = []
            self.guidanceFrame = ShotCoordinator.emptyGuidanceFrame
            self.planCurve = []
            self.exitTriggerItems = []
            self.stagePills = []
            return
        }
        
        let stage = profile.stages[stageIndex]
        let initialFrame = MachineFrame(timestamp: 0.0, state: .armed, readings: [:])
        
        let result = executionEngine.evaluate(
            stage: stage,
            stageIndex: stageIndex,
            totalStages: profile.stages.count,
            frame: initialFrame,
            baseline: currentStageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
        
        self.guidanceFrame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        updateStagePills(for: profile, activeIndex: stageIndex)
    }
    
    private func updateStagePills(for profile: Profile, activeIndex: Int) {
        self.stagePills = profile.stages.enumerated().map { index, s in
            let icon: String
            switch s.type {
            case .pressure: icon = "gauge.with.dots.needle.bottom.50percent"
            case .flow:     icon = "water.waves"
            case .power:    icon = "bolt.fill"
            }
            let state: StagePillState = index < activeIndex ? .completed : (index == activeIndex ? .active : .upcoming)
            return StagePillItem(stageNumber: index + 1, title: s.name, icon: icon, state: state)
        }
    }
    
    private static var emptyGuidanceFrame: GuidanceFrame {
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
