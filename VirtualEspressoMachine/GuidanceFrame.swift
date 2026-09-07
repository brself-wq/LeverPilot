//
//  GuidanceFrame.swift
//  VirtualEspressoMachine
//

import Foundation

/// A self-contained evaluation of an active safety limit/guardrail.
public nonisolated struct GuardrailStatus: Sendable, Equatable {
    public let metric: SensorKey        // e.g. .flow or .pressure
    public let limitValue: Double       // e.g. 2.0 ml/s or 8.5 bar
    public let actualValue: Double      // current live reading
    public let isBreached: Bool         // true -> trigger audio/visual alarm!
    
    public init(metric: SensorKey, limitValue: Double, actualValue: Double, isBreached: Bool) {
        self.metric = metric
        self.limitValue = limitValue
        self.actualValue = actualValue
        self.isBreached = isBreached
    }
}

/// An immutable, universal evaluation snapshot at a discrete tick along the shot timeline.
public nonisolated struct GuidanceFrame: Sendable {
    // 1. Stage Info (for the Carousel)
    public let stageIndex: Int               // e.g. 0, 1, 2
    public let totalStages: Int             // e.g. 3
    public let stageName: String            // "pre soak", "bloom", "extraction"
    
    // 2. Flight Director (The Active Variable)
    public let activeMetric: SensorKey      // .pressure (Green) or .flow (Blue)
    public let targetValue: Double          // e.g. 2.0 bar or 1.5 ml/s
    public let actualValue: Double          // e.g. 1.8 bar
    public let delta: Double                // actual - target (-0.2 bar -> "PULL HARDER")
    
    // 3. Time & Weight Telemetry (Absolute and Relative)
    public let elapsedTime: TimeInterval    // Total shot time from start of extraction (seconds)
    public let stageTime: TimeInterval      // Local elapsed time in current stage (seconds)
    public let actualWeight: Double         // Current liquid yield in cup (grams)
    
    // 4. Progress Ratios
    public let stageProgress: Double        // 0.0 ... 1.0 (closest exit trigger)
    public let yieldProgress: Double        // currentWeight / finalWeight (e.g. 12g / 40g = 30%)
    
    // 5. Guardrail / Safety Limit
    public let guardrail: GuardrailStatus?  // nil if this stage has no limits defined
    
    public var isAlarmActive: Bool {
        guardrail?.isBreached ?? false
    }
    
    public init(
        stageIndex: Int,
        totalStages: Int,
        stageName: String,
        activeMetric: SensorKey,
        targetValue: Double,
        actualValue: Double,
        delta: Double,
        elapsedTime: TimeInterval = 0.0,
        stageTime: TimeInterval = 0.0,
        actualWeight: Double = 0.0,
        stageProgress: Double,
        yieldProgress: Double,
        guardrail: GuardrailStatus? = nil
    ) {
        self.stageIndex = stageIndex
        self.totalStages = totalStages
        self.stageName = stageName
        self.activeMetric = activeMetric
        self.targetValue = targetValue
        self.actualValue = actualValue
        self.delta = delta
        self.elapsedTime = elapsedTime
        self.stageTime = stageTime
        self.actualWeight = actualWeight
        self.stageProgress = stageProgress
        self.yieldProgress = yieldProgress
        self.guardrail = guardrail
    }
}
