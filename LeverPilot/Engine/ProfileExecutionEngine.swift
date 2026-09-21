//
//  ProfileExecutionEngine.swift
//  VirtualEspressoMachine
//

import Foundation
import MeticulousProfile

// MARK: - Stage Baseline (Tracking relative offsets & entry sensor readings)

/// Captures the machine state at the exact moment a stage begins.
/// Used to calculate relative time, relative weight offsets, and decay trigger progress baselines.
public nonisolated struct StageBaseline: Sendable, Equatable {
    public let startTime: TimeInterval
    public let startWeight: Double
    public let entryPressure: Double
    public let entryFlow: Double
    
    public init(
        startTime: TimeInterval = 0.0,
        startWeight: Double = 0.0,
        entryPressure: Double = 0.0,
        entryFlow: Double = 0.0
    ) {
        self.startTime = startTime
        self.startWeight = startWeight
        self.entryPressure = entryPressure
        self.entryFlow = entryFlow
    }
}

// MARK: - Evaluation Result

/// The combined output of a single engine tick evaluation.
public nonisolated struct StageEvaluationResult: Sendable {
    /// The surface snapshot ready for the Barista HUD
    public let guidanceFrame: GuidanceFrame
    
    /// The generated plan curve coordinates for the chart
    public let planCurve: [PlanPoint]
    
    /// The detailed exit trigger items for the race track
    public let exitTriggerItems: [ExitTriggerProgressItem]
    
    /// True if ANY active exit trigger has satisfied its transition condition
    public let shouldAdvanceStage: Bool
}

// MARK: - Pure Stateless Execution Engine

/// Pure, headless domain service responsible for trajectory math, limit monitoring, and trigger evaluation.
public nonisolated struct ProfileExecutionEngine: Sendable {
    
    public init() {}
    
    /// Evaluates a stage against the current machine frame and returns guidance, chart points, and transition flags.
    public func evaluate(
        stage: Stage,
        stageIndex: Int,
        totalStages: Int,
        frame: MachineFrame,
        baseline: StageBaseline,
        finalWeightTarget: Double
    ) -> StageEvaluationResult {
        
        // 1. Resolve Active Metric Channel
        let activeMetric: SensorKey
        switch stage.type {
        case .pressure: activeMetric = .pressure
        case .flow:     activeMetric = .flow
        case .power:    activeMetric = .power
        }
        
        // 2. Parse Raw Trajectory Knots
        let rawKnots: [(x: Double, y: Double)] = stage.dynamics.points.compactMap { pt in
            guard let x = pt.x.numericValue, let y = pt.y.numericValue else { return nil }
            return (x: x, y: y)
        }
        
        // 3. Compute Local Domain Progress ($x$)
        let localTime = max(0.0, frame.timestamp - baseline.startTime)
        let currentWeight = frame[.weight] ?? 0.0
        let localWeight = max(0.0, currentWeight - baseline.startWeight)
        
        let domainValue: Double
        switch stage.dynamics.over {
        case .time:           domainValue = localTime
        case .weight:         domainValue = localWeight
        case .pistonPosition: domainValue = frame[.pistonPosition] ?? 0.0
        }
        
        // 4. Calculate Stage Horizon & Plan Curve (Accounting for Relative vs Absolute Time Triggers)
        let maxKnotX = rawKnots.map(\.x).max() ?? 0.0
        let timeTrigger = stage.exitTriggers?.first(where: { $0.type == .time })
        let timeTriggerVal: Double
        if let timeTrigger, let rawVal = timeTrigger.value.numericValue {
            if timeTrigger.relative ?? false {
                timeTriggerVal = rawVal
            } else {
                // Absolute shot time: remaining stage horizon is bounded by (target - baseline.startTime)
                timeTriggerVal = max(0.0, rawVal - baseline.startTime)
            }
        } else {
            timeTriggerVal = 0.0
        }
        
        let stageHorizon = max(maxKnotX, timeTriggerVal, 10.0, domainValue)
        let planCurve = generatePlanCurve(
            knots: rawKnots,
            horizon: stageHorizon,
            interpolation: stage.dynamics.interpolation
        )
        
        // 5. Interpolate Commanded Target Setpoint (Step vs. Lerp)
        let targetValue = evaluateTarget(
            at: domainValue,
            knots: rawKnots,
            interpolation: stage.dynamics.interpolation
        )
        let actualValue = frame[activeMetric] ?? 0.0
        let delta = actualValue - targetValue
        
        // 6. Evaluate Safety Limits
        let limitStatus = evaluateLimit(stage: stage, frame: frame)
        
        // 7. Evaluate Exit Triggers & Check if Stage Should Advance
        let (triggerItems, shouldAdvance) = evaluateExitTriggers(
            stage: stage,
            frame: frame,
            baseline: baseline,
            localTime: localTime,
            localWeight: localWeight,
            finalWeightTarget: finalWeightTarget
        )
        
        // 8. Construct Final GuidanceFrame
        let yieldRatio = finalWeightTarget > 0 ? min(1.0, currentWeight / finalWeightTarget) : 0.0
        let stageProgressRatio = triggerItems.map(\.progress).max() ?? yieldRatio
        
        let guidanceFrame = GuidanceFrame(
            stageIndex: stageIndex,
            totalStages: totalStages,
            stageName: stage.name,
            activeMetric: activeMetric,
            targetValue: targetValue,
            actualValue: actualValue,
            delta: delta,
            stageProgress: stageProgressRatio,
            yieldProgress: yieldRatio,
            guardrail: limitStatus
        )
        
        return StageEvaluationResult(
            guidanceFrame: guidanceFrame,
            planCurve: planCurve,
            exitTriggerItems: triggerItems,
            shouldAdvanceStage: shouldAdvance
        )
    }
    
    // MARK: - Trajectory & Interpolation Math
    
    private func generatePlanCurve(
        knots: [(x: Double, y: Double)],
        horizon: Double,
        interpolation: DynamicsInterpolationType = .linear
    ) -> [PlanPoint] {
        if knots.isEmpty {
            return [PlanPoint(x: 0, y: 0), PlanPoint(x: horizon, y: 0)]
        } else if knots.count == 1 {
            let y = knots[0].y
            return [PlanPoint(x: 0, y: y), PlanPoint(x: horizon, y: y)]
        } else if interpolation == DynamicsInterpolationType.none {
            // Piecewise-constant step curve rendering for HUD chart
            var points: [PlanPoint] = []
            for i in 0..<(knots.count - 1) {
                let p0 = knots[i]
                let p1 = knots[i + 1]
                points.append(PlanPoint(x: p0.x, y: p0.y))
                points.append(PlanPoint(x: p1.x, y: p0.y))
            }
            if let last = knots.last {
                points.append(PlanPoint(x: last.x, y: last.y))
                if last.x < horizon {
                    points.append(PlanPoint(x: horizon, y: last.y))
                }
            }
            return points
        } else {
            var points = knots.map { PlanPoint(x: $0.x, y: $0.y) }
            // Infinite flatline hold past last defined knot
            if let last = knots.last, last.x < horizon {
                points.append(PlanPoint(x: horizon, y: last.y))
            }
            return points
        }
    }
    
    private func evaluateTarget(
        at x: Double,
        knots: [(x: Double, y: Double)],
        interpolation: DynamicsInterpolationType = .linear
    ) -> Double {
        guard let first = knots.first else { return 0.0 }
        if knots.count == 1 || x <= first.x { return first.y }
        if let last = knots.last, x >= last.x { return last.y } // Flatline hold!
        
        for i in 0..<(knots.count - 1) {
            let p0 = knots[i]
            let p1 = knots[i + 1]
            if x >= p0.x && x <= p1.x {
                if interpolation == DynamicsInterpolationType.none {
                    // Zero-order hold: maintain setpoint of interval start without lerping
                    return p0.y
                } else {
                    guard p1.x > p0.x else { return p0.y }
                    let ratio = (x - p0.x) / (p1.x - p0.x)
                    return p0.y + ratio * (p1.y - p0.y)
                }
            }
        }
        return knots.last?.y ?? first.y
    }
    
    // MARK: - Limits & Exit Trigger Evaluation
    
    private func evaluateLimit(stage: Stage, frame: MachineFrame) -> GuardrailStatus? {
        guard let limit = stage.limits?.first, let limitVal = limit.value.numericValue else { return nil }
        let limitMetric: SensorKey = (limit.type == .pressure) ? .pressure : .flow
        let actual = frame[limitMetric] ?? 0.0
        
        return GuardrailStatus(
            metric: limitMetric,
            limitValue: limitVal,
            actualValue: actual,
            isBreached: actual > limitVal
        )
    }
    
    private func evaluateExitTriggers(
        stage: Stage,
        frame: MachineFrame,
        baseline: StageBaseline,
        localTime: Double,
        localWeight: Double,
        finalWeightTarget: Double
    ) -> (items: [ExitTriggerProgressItem], shouldAdvance: Bool) {
        
        var items: [ExitTriggerProgressItem] = []
        var shouldAdvance = false
        
        if let triggers = stage.exitTriggers, !triggers.isEmpty {
            for trigger in triggers {
                let targetVal = trigger.value.numericValue ?? 0.0
                let currentVal: Double
                let startVal: Double
                let sensorKey: SensorKey
                let icon: String
                let unit: String
                
                let isRelative = trigger.relative ?? false
                
                switch trigger.type {
                case .time:
                    sensorKey = .time
                    icon = "clock.fill"
                    unit = "s"
                    if isRelative {
                        currentVal = localTime
                        startVal = 0.0
                    } else {
                        currentVal = frame.timestamp
                        startVal = baseline.startTime
                    }
                    
                case .weight:
                    sensorKey = .weight
                    icon = "scalemass.fill"
                    unit = "g"
                    if isRelative {
                        currentVal = localWeight
                        startVal = 0.0
                    } else {
                        currentVal = frame[.weight] ?? 0.0
                        startVal = baseline.startWeight
                    }
                    
                case .pressure:
                    sensorKey = .pressure
                    icon = "gauge.with.dots.needle.bottom.50percent"
                    unit = "bar"
                    currentVal = frame[.pressure] ?? 0.0
                    if isRelative {
                        startVal = 0.0
                    } else if trigger.resolvedComparison == .lessThanOrEqual {
                        // Decay trigger: baseline is stage entry pressure, fallback to initial knot setpoint
                        startVal = baseline.entryPressure > 0
                            ? baseline.entryPressure
                            : (stage.dynamics.points.first?.y.numericValue ?? currentVal)
                    } else {
                        startVal = baseline.entryPressure
                    }
                    
                case .flow:
                    sensorKey = .flow
                    icon = "water.waves"
                    unit = "mL/s"
                    currentVal = frame[.flow] ?? 0.0
                    if isRelative {
                        startVal = 0.0
                    } else if trigger.resolvedComparison == .lessThanOrEqual {
                        startVal = baseline.entryFlow > 0
                            ? baseline.entryFlow
                            : (stage.dynamics.points.first?.y.numericValue ?? currentVal)
                    } else {
                        startVal = baseline.entryFlow
                    }
                    
                default:
                    sensorKey = .power
                    icon = "bolt.fill"
                    unit = "%"
                    currentVal = frame[.power] ?? 100.0
                    startVal = 0.0
                }
                
                // Check satisfaction (>= or <=)
                let isSatisfied = trigger.resolvedComparison == .greaterThanOrEqual
                    ? currentVal >= targetVal
                    : currentVal <= targetVal
                
                if isSatisfied {
                    shouldAdvance = true
                }
                
                // Continuous progress calculation for HUD racetrack (unified ramp & decay math)
                let progress: Double
                if isSatisfied {
                    progress = 1.0
                } else {
                    let denominator = targetVal - startVal
                    if abs(denominator) < 0.0001 {
                        progress = 0.0
                    } else {
                        let ratio = (currentVal - startVal) / denominator
                        progress = min(1.0, max(0.0, ratio))
                    }
                }
                
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
            
            // Mark the leading trigger in the race
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
            // Universal Final Weight Cutoff (When stage has no explicit triggers)
            let currentWeight = frame[.weight] ?? 0.0
            let progress = finalWeightTarget > 0 ? min(1.0, currentWeight / finalWeightTarget) : 0.0
            let isSatisfied = currentWeight >= finalWeightTarget
            
            if isSatisfied {
                shouldAdvance = true
            }
            
            items.append(ExitTriggerProgressItem(
                sensorKey: .weight,
                icon: "scalemass.fill",
                label: "Final Weight Cutoff",
                currentString: String(format: "%.1fg", currentWeight),
                targetString: String(format: "%.1fg", finalWeightTarget),
                progress: progress,
                isLeading: true
            ))
        }
        
        return (items, shouldAdvance)
    }
}
