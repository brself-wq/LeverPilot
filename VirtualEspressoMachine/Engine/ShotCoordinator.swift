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
    
    // MARK: - Machine Operational State
    public private(set) var state: MachineState = .idle
    public private(set) var currentFrame: MachineFrame = MachineFrame(state: .idle)
    
    // MARK: - Profile Management (In-Memory Session vs Previous)
    /// The active in-memory profile driving the HUD & Engine (may contain session variable overrides)
    public private(set) var activeProfile: Profile? = nil
    public private(set) var previousProfile: Profile? = nil
    public private(set) var activeDose: Double = 18.0
    
    // MARK: - Shot Telemetry Accumulation & Output
    public private(set) var completedShotRecord: ShotRecord? = nil
    private var capturedSamples: [ShotSample] = []
    
    // MARK: - Active Stage Execution
    public private(set) var activeStageIndex: Int = 0
    public private(set) var currentStageBaseline: StageBaseline = StageBaseline()
    public private(set) var stageBaselines: [Int: StageBaseline] = [0: StageBaseline()]
    
    // MARK: - Surface Guidance Buffers (Feeds BaristaHUDView)
    public private(set) var guidanceFrame: GuidanceFrame = ShotCoordinator.emptyGuidanceFrame
    public private(set) var planCurve: [PlanPoint] = []
    public private(set) var actualHistory: [ActualPoint] = []
    public private(set) var exitTriggerItems: [ExitTriggerProgressItem] = []
    public private(set) var stagePills: [StagePillItem] = []
    
    // MARK: - Clocks & Real-time Telemetry
    public private(set) var elapsedTime: Double = 0.0
    public private(set) var stageTime: Double = 0.0
    public private(set) var actualWeight: Double = 0.0
    public var isAlarmActive: Bool = false
    
    // MARK: - Configuration & Watchdogs
    public var machineConfig: MachineConfig = .flair58Default
    private var deadFlowStartTime: TimeInterval? = nil
    
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
    
    // MARK: - Profile Arming & Lifecycle
    
    /// Arms a profile for execution.
    /// Can accept a canonical template from ProfileStore or a session copy modified by ProfileVariableOverridesView.
    public func arm(with profile: Profile, dose: Double = 18.0, store: ProfileStore? = nil) {
        if let current = activeProfile, current.id != profile.id {
            self.previousProfile = current
        }
        
        // Resolve dynamic $variables if store is provided
        let executableProfile: Profile
        if let store {
            executableProfile = (try? store.resolveForExecution(profile)) ?? profile
        } else {
            executableProfile = profile
        }
        
        self.activeProfile = executableProfile
        self.activeDose = dose
        self.state = .armed
        resetExecutionState()
    }
    
    /// Backwards compatibility for existing views
    public func selectProfile(_ profile: Profile) {
        arm(with: profile)
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
        self.completedShotRecord = nil
        self.capturedSamples.removeAll()
        self.deadFlowStartTime = nil
        
        setupInitialStage(stageIndex: 0)
    }
    
    // MARK: - Machine State Transitions
    
    public func startExtraction() {
        guard state == .armed || state == .idle else { return }
        state = .extracting
    }
    
    public func endExtraction() {
        guard state == .extracting else { return }
        state = .shotEnded
        
        // Freeze in-flight telemetry and the exact in-memory profile into a permanent record
        if let profile = activeProfile {
            self.completedShotRecord = ShotRecord(
                profileId: profile.id,
                profileName: profile.name,
                profileSnapshot: profile.sanitizedForHistory(),
                timestamp: Date(),
                duration: elapsedTime,
                finalWeight: actualWeight,
                doseWeight: activeDose,
                targetWeight: resolvedTargetWeight,
                brewTemperature: profile.temperature,
                samples: capturedSamples
            )
        }
    }
    
    public func abort() {
        state = .idle
        resetExecutionState()
    }
    
    // MARK: - Telemetry Binding
    
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
    
    // MARK: - Frame Processing & Watchdogs
    
    public func processTelemetryFrame(_ frame: MachineFrame, allowAdvance: Bool = true) {
        self.currentFrame = frame
        let currentPressure = frame[.pressure] ?? 0.0
        let currentFlow = frame[.flow] ?? 0.0
        let currentWeight = frame[.weight] ?? 0.0
        
        // 1. Auto-Start: Triggered strictly by >= 0.5 bar lever pull or external extraction state
        if state == .armed && (currentPressure >= 0.5 || frame.state == .extracting) {
            state = .extracting
        }
        
        guard state == .extracting, let profile = activeProfile, let stage = currentStage else {
            return
        }
        
        // 2. Continuous Full-Shot Telemetry Accumulation
        let sample = ShotSample(
            timestamp: frame.timestamp,
            pressure: currentPressure,
            flow: currentFlow,
            weight: currentWeight,
            targetPressure: stage.type == .pressure ? guidanceFrame.targetValue : nil,
            targetFlow: stage.type == .flow ? guidanceFrame.targetValue : nil,
            stageIndex: activeStageIndex
        )
        capturedSamples.append(sample)
        
        // 3. Auto-Stop Dead-Flow Watchdog
        // Beanconqueror Heuristic: Requires elapsed time >= 5.0s AND (weight >= 5.0g OR weight >= dose)
        let isPreconditionMet = frame.timestamp >= 5.0 && (currentWeight >= 5.0 || currentWeight >= activeDose)
        
        if isPreconditionMet && currentFlow <= machineConfig.autoStop.cutoffRule.threshold {
            if let start = deadFlowStartTime {
                if (frame.timestamp - start) >= machineConfig.autoStop.sustainDuration {
                    print("🛑 SHOT ENDED: BLE Dead-Flow Watchdog (Sustained dead flow for \(machineConfig.autoStop.sustainDuration)s at t=\(String(format: "%.1f", frame.timestamp))s, weight=\(String(format: "%.1f", currentWeight))g)")
                    endExtraction()
                    return
                }
            } else {
                deadFlowStartTime = frame.timestamp
            }
        } else {
            deadFlowStartTime = nil
        }
        
        // 4. Evaluate Stage Dynamics with Execution Engine
        var result = executionEngine.evaluate(
            stage: stage,
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            frame: frame,
            baseline: currentStageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
        
        // 5. Evaluate Stage Progression
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
                actualHistory.removeAll() // Cleared for active stage chart display
                
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
                print("🏁 SHOT ENDED: Profile Reached Final Stage Exit Trigger (Stage \(activeStageIndex + 1)/\(profile.stages.count))")
                endExtraction()
                return
            }
        }
        
        // 6. Update Guidance Surface Buffers
        self.guidanceFrame = result.guidanceFrame
        self.planCurve = result.planCurve
        self.exitTriggerItems = result.exitTriggerItems
        self.elapsedTime = frame.timestamp
        self.stageTime = max(0.0, frame.timestamp - currentStageBaseline.startTime)
        self.actualWeight = currentWeight
        self.isAlarmActive = result.guidanceFrame.guardrail?.isBreached ?? false
        
        // 7. Append Historical Point for Active Stage Chart
        let activeStage = currentStage ?? stage
        let metricVal: Double
        switch activeStage.type {
        case .pressure: metricVal = currentPressure
        case .flow:     metricVal = currentFlow
        case .power:    metricVal = frame[.power] ?? 100.0
        }
        let pointX = max(0.0, frame.timestamp - currentStageBaseline.startTime)
        self.actualHistory.append(ActualPoint(x: pointX, y: metricVal))
        
        // 8. Update Stage Navigation Pills
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
        
        // Trim accumulated samples to current scrubber timestamp
        capturedSamples.removeAll { $0.timestamp > frame.timestamp }
        
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
