//
//  ShotCoordinator.swift
//  LeverPilot
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
    
    // MARK: - Terminal Approach Guidance (The Closing Reticle & Radar)
    /// Nil during cruising. Smooth 0.0 -> 1.0 progress across the final 12g acquisition runway.
    public private(set) var approachProgress: Double? = nil
    public private(set) var gramsToGo: Double = 0.0
    
    // Approach Calibration Thresholds
    public static let acquisitionWindowGrams: Double = 12.0 // Reticle appears wide (~10s lead)
    public static let sonarPacerWindowGrams: Double = 4.0   // Radar audio kicks in
    public static let flareMarginGrams: Double = 1.5        // Decision height / rapid pings
    
    // MARK: - Clocks & Real-time Telemetry
    public private(set) var elapsedTime: Double = 0.0
    public private(set) var stageTime: Double = 0.0
    public private(set) var actualWeight: Double = 0.0
    public var isAlarmActive: Bool = false
    
    /// True when all profile stages and triggers have concluded, but physical flow is still active.
    public private(set) var isProfileComplete: Bool = false
    
    // MARK: - Configuration & Watchdogs
    public var machineConfig: MachineConfig = .flair58Default
    private var deadFlowStartTime: TimeInterval? = nil
    
    // MARK: - Audio & Sensory Engine
    @ObservationIgnored private let soundEngine = AvionicsSoundEngine()
    @ObservationIgnored private var lastSonarTickTime: TimeInterval = 0.0
    @ObservationIgnored private var hasFiredTouchdownChime: Bool = false
    
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
    
    public func arm(with profile: Profile, dose: Double = 18.0, store: ProfileStore? = nil) {
        if let current = activeProfile, current.id != profile.id {
            self.previousProfile = current
        }
        
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
        self.isProfileComplete = false
        self.completedShotRecord = nil
        self.capturedSamples.removeAll()
        self.deadFlowStartTime = nil
        
        // Reset Terminal Guidance & Audio State
        self.approachProgress = nil
        self.gramsToGo = resolvedTargetWeight
        self.lastSonarTickTime = 0.0
        self.hasFiredTouchdownChime = false
        self.soundEngine.stop()
        
        setupInitialStage(stageIndex: 0)
    }
    
    // MARK: - Settings Synchronization
    
    public func configure(from settings: SettingsStore) {
        self.machineConfig.autoStartRule.threshold = settings.autoStartPressure
        self.machineConfig.autoStop.cutoffRule.threshold = settings.deadFlowThreshold
        self.machineConfig.autoStop.sustainDuration = settings.deadFlowSustainDuration
    }
    
    // MARK: - Machine State Transitions
    
    public func startExtraction() {
        guard state == .armed || state == .idle else { return }
        state = .extracting
    }
    
    public func endExtraction() {
        guard state == .extracting else { return }
        state = .shotEnded
        soundEngine.stop()
        
        let threshold = machineConfig.autoStop.cutoffRule.threshold
        var trimmedDuration = elapsedTime
        var trimmedFinalWeight = actualWeight
        var trimmedSamples = capturedSamples
        
        if let lastSignificantIndex = capturedSamples.lastIndex(where: { $0.flow > threshold }) {
            let cutoffIndex = min(lastSignificantIndex + 1, capturedSamples.count - 1)
            let cutoffSample = capturedSamples[cutoffIndex]
            trimmedDuration = cutoffSample.timestamp
            trimmedFinalWeight = cutoffSample.weight
            trimmedSamples = Array(capturedSamples.prefix(through: cutoffIndex))
        }
        
        if let profile = activeProfile {
            self.completedShotRecord = ShotRecord(
                profileId: profile.id,
                profileName: profile.name,
                profileSnapshot: profile.sanitizedForHistory(),
                timestamp: Date(),
                duration: trimmedDuration,
                finalWeight: trimmedFinalWeight,
                doseWeight: activeDose,
                targetWeight: resolvedTargetWeight,
                brewTemperature: profile.temperature,
                samples: trimmedSamples
            )
        }
    }
    
    public func abort() {
        state = .idle
        soundEngine.stop()
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
        soundEngine.stop()
    }
    
    // MARK: - Frame Processing & Watchdogs
    
    public func processTelemetryFrame(_ frame: MachineFrame, allowAdvance: Bool = true) {
        self.currentFrame = frame
        let currentPressure = frame[.pressure] ?? 0.0
        let currentFlow = frame[.flow] ?? 0.0
        let currentWeight = frame[.weight] ?? 0.0
        
        // 1. Auto-Start: Trip on pressure threshold (ignoring weight artifacts)
        if state == .armed && (machineConfig.autoStartRule.isSatisfied(by: frame) || frame.state == .extracting) {
            print("[AutoStart] 🚀 Extraction started (P = \(String(format: "%.2f", currentPressure)) bar >= \(machineConfig.autoStartRule.threshold) bar)")
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
        
        // 3. Auto-Stop Dead-Flow Watchdog (ADR-005, ADR-009)
        let isPreconditionMet = frame.timestamp >= 5.0 && (currentWeight >= 5.0 || currentWeight >= activeDose)
        
        if frame.isScaleStale {
            if deadFlowStartTime != nil {
                print("[AutoStop] ⏸ Countdown SUSPENDED: Scale packet stream became stale at t=\(String(format: "%.1f", frame.timestamp))s.")
                deadFlowStartTime = nil
            }
        } else if isPreconditionMet && currentFlow <= machineConfig.autoStop.cutoffRule.threshold {
            if let start = deadFlowStartTime {
                let elapsedDead = frame.timestamp - start
                if elapsedDead >= machineConfig.autoStop.sustainDuration {
                    print("🛑 SHOT ENDED: BLE Dead-Flow Watchdog (Sustained dead flow for \(String(format: "%.1f", elapsedDead))s at t=\(String(format: "%.1f", frame.timestamp))s, weight=\(String(format: "%.1f", currentWeight))g)")
                    endExtraction()
                    return
                }
            } else {
                deadFlowStartTime = frame.timestamp
                print("[AutoStop] ⏳ Low flow detected (\(String(format: "%.2f", currentFlow)) mL/s <= \(machineConfig.autoStop.cutoffRule.threshold) mL/s at t=\(String(format: "%.1f", frame.timestamp))s, weight=\(String(format: "%.1f", currentWeight))g). Starting \(String(format: "%.1f", machineConfig.autoStop.sustainDuration))s sustain timer...")
            }
        } else {
            if deadFlowStartTime != nil {
                deadFlowStartTime = nil
            }
        }
        
        // 4. Terminal Approach Guidance & Sonar Radar Pacer
        evaluateTerminalGuidance(currentWeight: currentWeight, frameTimestamp: frame.timestamp)
        
        // 5. Evaluate Stage Dynamics with Execution Engine
        var result = executionEngine.evaluate(
            stage: stage,
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            frame: frame,
            baseline: currentStageBaseline,
            finalWeightTarget: resolvedTargetWeight
        )
        
        // 6. Evaluate Stage Progression
        if allowAdvance && result.shouldAdvanceStage {
            if activeStageIndex + 1 < profile.stages.count {
                let oldIndex = activeStageIndex
                activeStageIndex += 1
                currentStageBaseline = StageBaseline(
                    startTime: frame.timestamp,
                    startWeight: currentWeight,
                    entryPressure: currentPressure,
                    entryFlow: currentFlow
                )
                stageBaselines[activeStageIndex] = currentStageBaseline
                actualHistory.removeAll()
                
                // Waypoint Advance Earcon: Subtle E5 chime
                soundEngine.playBeep(frequency: 659.25, duration: 0.12, volume: 0.18)
                
                if let nextStage = currentStage {
                    print("[Coordinator] ⏭ Stage advanced: [\(oldIndex + 1)] \(stage.name) -> [\(activeStageIndex + 1)] \(nextStage.name)")
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
                if !isProfileComplete {
                    print("🎯 PROFILE COMPLETE: Holding final setpoint until flow cutoff.")
                    isProfileComplete = true
                }
            }
        }
        
        // 7. Update Guidance Surface Buffers
        self.guidanceFrame = result.guidanceFrame
        self.planCurve = result.planCurve
        
        if isProfileComplete {
            self.exitTriggerItems = [
                ExitTriggerProgressItem(
                    sensorKey: .flow,
                    icon: "cup.and.saucer.fill",
                    label: "Profile Complete",
                    currentString: String(format: "%.1f mL/s", currentFlow),
                    targetString: "Flow Stop",
                    progress: 1.0,
                    isLeading: true
                )
            ]
        } else {
            self.exitTriggerItems = result.exitTriggerItems
        }
        
        self.elapsedTime = frame.timestamp
        self.stageTime = max(0.0, frame.timestamp - currentStageBaseline.startTime)
        self.actualWeight = currentWeight
        self.isAlarmActive = result.guidanceFrame.guardrail?.isBreached ?? false
        
        // 8. Append Historical Point for Active Stage Chart
        let activeStage = currentStage ?? stage
        let metricVal: Double
        switch activeStage.type {
        case .pressure: metricVal = currentPressure
        case .flow:     metricVal = currentFlow
        case .power:    metricVal = frame[.power] ?? 100.0
        }
        let pointX = max(0.0, frame.timestamp - currentStageBaseline.startTime)
        self.actualHistory.append(ActualPoint(x: pointX, y: metricVal))
        
        // 9. Update Stage Navigation Pills
        updateStagePills(for: profile, activeIndex: activeStageIndex)
    }
    
    // MARK: - Terminal Guidance & Sonar Radar Pacer Logic
    
    private func evaluateTerminalGuidance(currentWeight: Double, frameTimestamp: Double) {
        let target = resolvedTargetWeight
        guard target > 0 else {
            self.approachProgress = nil
            self.gramsToGo = 0.0
            return
        }
        
        self.gramsToGo = max(0.0, target - currentWeight)
        let acquisitionStart = target - Self.acquisitionWindowGrams
        
        // 1. Acquisition Check: Is the reticle active?
        if currentWeight >= acquisitionStart {
            let progress = (currentWeight - acquisitionStart) / Self.acquisitionWindowGrams
            self.approachProgress = min(1.0, max(0.0, progress))
        } else {
            self.approachProgress = nil
            soundEngine.stop()
            return
        }
        
        // 2. Touchdown Check: Exact Target Cutoff
        if currentWeight >= target {
            if !hasFiredTouchdownChime {
                hasFiredTouchdownChime = true
                soundEngine.playBeep(frequency: 1046.5, duration: 0.35, volume: 0.30) // High C6 Chime
            }
            return
        }
        
        hasFiredTouchdownChime = false
        
        // 3. Sonar Radar Pacer: Active in final 4.0g window
        let sonarStart = target - Self.sonarPacerWindowGrams
        if currentWeight >= sonarStart {
            let sonarProgress = min(1.0, max(0.0, (currentWeight - sonarStart) / Self.sonarPacerWindowGrams))
            
            // Cadence scales from 0.8s down to 0.15s between ticks
            let cadenceInterval = max(0.14, 0.80 - (sonarProgress * 0.65))
            
            if (frameTimestamp - lastSonarTickTime) >= cadenceInterval {
                lastSonarTickTime = frameTimestamp
                // Pitch glides from 440 Hz up to 880 Hz
                let pingFrequency = Float(440.0 + (sonarProgress * 440.0))
                soundEngine.playBeep(frequency: pingFrequency, duration: 0.06, volume: 0.20)
            }
        }
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
