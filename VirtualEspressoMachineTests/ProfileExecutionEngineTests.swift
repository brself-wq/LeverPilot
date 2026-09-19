//
//  ProfileExecutionEngineTests.swift
//  VirtualEspressoMachineTests
//
//  Step 4: Headless Engine Verification Suite
//

import XCTest
@testable import VirtualEspressoMachine
import MeticulousProfile

final class ProfileExecutionEngineTests: XCTestCase {
    
    private var engine: ProfileExecutionEngine!
    
    override func setUp() {
        super.setUp()
        engine = ProfileExecutionEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    // MARK: - Test Helpers & Factories
    
    private func makeFrame(
        timestamp: Double = 0.0,
        pressure: Double = 0.0,
        flow: Double = 0.0,
        weight: Double = 0.0,
        power: Double = 100.0
    ) -> MachineFrame {
        MachineFrame(
            timestamp: timestamp,
            state: .extracting,
            readings: [
                .pressure: pressure,
                .flow: flow,
                .weight: weight,
                .time: timestamp,
                .power: power
            ]
        )
    }
    
    private func makeStage(
        name: String = "Test Stage",
        type: StageType = .pressure,
        points: [(Double, Double)] = [(0.0, 6.0), (10.0, 6.0)],
        over: DynamicsInterpolationOverType = .time,
        triggers: [ExitTrigger]? = nil,
        limits: [Limit]? = nil
    ) -> Stage {
        Stage(
            name: name,
            key: "stage_test",
            type: type,
            dynamics: Dynamics(
                points: points.map { Point(.value($0.0), .value($0.1)) },
                over: over,
                interpolation: .linear
            ),
            exitTriggers: triggers,
            limits: limits
        )
    }
    
    // MARK: - Baseline Parity & Relative vs Absolute Time
    
    /// Verifies local time stage duration (frame.timestamp - baseline.startTime) when relative == true.
    func test_bloomStage_doesNotPrematurelyCutoffAtAbsoluteShotTime_whenRelativeTrue() {
        let bloomStage = makeStage(
            name: "Bloom",
            type: .flow,
            triggers: [ExitTrigger(type: .time, value: .value(5.0), relative: true)]
        )
        // Stage began at 10.0s
        let baseline = StageBaseline(startTime: 10.0, startWeight: 2.0)
        
        // At 14.0s total time, local time is 4.0s (less than 5.0s threshold)
        let frameAt14 = makeFrame(timestamp: 14.0)
        let result14 = engine.evaluate(
            stage: bloomStage,
            stageIndex: 1,
            totalStages: 3,
            frame: frameAt14,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(result14.shouldAdvanceStage, "Bloom should not cut off before 5.0s local duration has elapsed")
        
        // At 15.0s total time, local time is 5.0s (threshold satisfied)
        let frameAt15 = makeFrame(timestamp: 15.0)
        let result15 = engine.evaluate(
            stage: bloomStage,
            stageIndex: 1,
            totalStages: 3,
            frame: frameAt15,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(result15.shouldAdvanceStage, "Bloom should advance once local time reaches 5.0s")
    }
    
    /// Verifies time trigger with relative == true measures local stage time.
    func test_timeTrigger_whenRelativeTrue_measuresFromStageEntryBaseline() {
        let stage = makeStage(
            type: .flow,
            triggers: [ExitTrigger(type: .time, value: .value(5.0), relative: true)]
        )
        // Stage entered at shot timestamp 12.0s
        let baseline = StageBaseline(startTime: 12.0, startWeight: 4.0)
        
        // Shot elapsed is 15.0s -> stage local time is 3.0s (3.0 / 5.0 = 60%)
        let frame = makeFrame(timestamp: 15.0)
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 3,
            frame: frame,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(result.shouldAdvanceStage)
        XCTAssertEqual(result.exitTriggerItems.first!.progress, 0.6, accuracy: 0.001)
        XCTAssertEqual(result.exitTriggerItems.first?.currentString, "3.0s")
        
        // Shot elapsed is 17.0s -> stage local time is 5.0s -> Hit!
        let frameHit = makeFrame(timestamp: 17.0)
        let resultHit = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 3,
            frame: frameHit,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultHit.shouldAdvanceStage)
        XCTAssertEqual(resultHit.exitTriggerItems.first!.progress, 1.0)
    }
    
    /// Verifies that when relative == false, time triggers evaluate against total elapsed shot timestamp.
    func test_timeTrigger_whenRelativeFalse_measuresFromTotalShotTimestamp() {
        let stage = makeStage(
            type: .flow,
            triggers: [ExitTrigger(type: .time, value: .value(20.0), relative: false)]
        )
        // Stage entered at shot timestamp 12.0s; target is 20.0s total shot time
        let baseline = StageBaseline(startTime: 12.0, startWeight: 4.0)
        
        // At 16.0s total shot time (local 4.0s), progress is (16 - 12) / (20 - 12) = 4 / 8 = 50%
        let frameMid = makeFrame(timestamp: 16.0)
        let resultMid = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 3,
            frame: frameMid,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultMid.shouldAdvanceStage)
        XCTAssertEqual(resultMid.exitTriggerItems.first!.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(resultMid.exitTriggerItems.first?.currentString, "16.0s")
        XCTAssertEqual(resultMid.exitTriggerItems.first?.targetString, "20.0s")
        
        // At 20.0s total shot time -> Hit!
        let frameHit = makeFrame(timestamp: 20.0)
        let resultHit = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 3,
            frame: frameHit,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultHit.shouldAdvanceStage)
        XCTAssertEqual(resultHit.exitTriggerItems.first!.progress, 1.0)
    }
    
    /// Verifies that an omitted relative flag normalizes to false (absolute shot time) per OEPF spec.
    func test_timeTrigger_omittedRelativeDefaultsToFalse() {
        let stage = makeStage(
            type: .pressure,
            triggers: [ExitTrigger(type: .time, value: .value(25.0))] // relative omitted -> false
        )
        let baseline = StageBaseline(startTime: 15.0, startWeight: 10.0)
        
        // At t = 20.0s, total shot time is 20.0s < 25.0s -> pending
        let frameMid = makeFrame(timestamp: 20.0)
        let resultMid = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frameMid,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultMid.shouldAdvanceStage)
        XCTAssertEqual(resultMid.exitTriggerItems.first!.currentString, "20.0s")
        
        // At t = 25.0s, total shot time hits 25.0s -> advances
        let frameHit = makeFrame(timestamp: 25.0)
        let resultHit = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frameHit,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultHit.shouldAdvanceStage)
    }
    
    /// Verifies weight cutoff triggers against target cup yield.
    func test_weightTrigger_respectsCupTarget() {
        let stage = makeStage(
            type: .pressure,
            triggers: [ExitTrigger(type: .weight, value: .value(36.0), relative: false)]
        )
        let baseline = StageBaseline(startTime: 10.0, startWeight: 15.0)
        
        let frameBelow = makeFrame(timestamp: 20.0, weight: 35.8)
        let resultBelow = engine.evaluate(
            stage: stage,
            stageIndex: 2,
            totalStages: 3,
            frame: frameBelow,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultBelow.shouldAdvanceStage)
        
        let frameMet = makeFrame(timestamp: 21.0, weight: 36.0)
        let resultMet = engine.evaluate(
            stage: stage,
            stageIndex: 2,
            totalStages: 3,
            frame: frameMet,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultMet.shouldAdvanceStage)
    }
    
    // MARK: - 1. Trigger Verification
    
    /// Verifies that a pressure exit trigger does not fire below threshold, but fires when reached/exceeded.
    func test_pressureExitTrigger_advancesWhenThresholdReached() {
        let stage = makeStage(
            type: .pressure,
            triggers: [ExitTrigger(type: .pressure, value: .value(4.0))]
        )
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        // 1. Below threshold (3.8 bar)
        let frameBelow = makeFrame(timestamp: 2.0, pressure: 3.8)
        let resultBelow = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 3,
            frame: frameBelow,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultBelow.shouldAdvanceStage, "Should not advance when pressure is below threshold")
        XCTAssertEqual(resultBelow.exitTriggerItems.first!.progress, 3.8 / 4.0, accuracy: 0.001)
        
        // 2. At threshold (4.0 bar)
        let frameAt = makeFrame(timestamp: 3.0, pressure: 4.0)
        let resultAt = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 3,
            frame: frameAt,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultAt.shouldAdvanceStage, "Should advance stage when pressure reaches 4.0 bar")
        XCTAssertEqual(resultAt.exitTriggerItems.first!.progress, 1.0)
    }
    
    /// Verifies that a flow exit trigger fires when flow threshold is satisfied.
    func test_flowExitTrigger_evaluatesCorrectly() {
        let stage = makeStage(
            type: .flow,
            triggers: [ExitTrigger(type: .flow, value: .value(2.0))]
        )
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        // Flow at 1.8 mL/s
        let frameBelow = makeFrame(timestamp: 1.0, flow: 1.8)
        let resultBelow = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: frameBelow,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultBelow.shouldAdvanceStage)
        
        // Flow reaches 2.1 mL/s
        let frameAbove = makeFrame(timestamp: 2.0, flow: 2.1)
        let resultAbove = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: frameAbove,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultAbove.shouldAdvanceStage)
    }
    
    /// Verifies that relative vs. absolute weight triggers evaluate against the correct scale baseline.
    func test_weightTrigger_respectsRelativeAndAbsoluteMode() {
        // Stage with RELATIVE weight trigger: +10g in this stage
        let relativeStage = makeStage(
            type: .pressure,
            triggers: [ExitTrigger(type: .weight, value: .value(10.0), relative: true)]
        )
        // Stage entry occurred at weight = 12.0g
        let baseline = StageBaseline(startTime: 5.0, startWeight: 12.0)
        
        // Current total weight = 20.0g (local added weight = 8.0g / 10.0g)
        let frame1 = makeFrame(timestamp: 8.0, weight: 20.0)
        let result1 = engine.evaluate(
            stage: relativeStage,
            stageIndex: 1,
            totalStages: 3,
            frame: frame1,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(result1.shouldAdvanceStage)
        XCTAssertEqual(result1.exitTriggerItems.first?.currentString, "8.0g")
        XCTAssertEqual(result1.exitTriggerItems.first!.progress, 0.8, accuracy: 0.001)
        
        // Current total weight = 22.0g (local added weight = 10.0g) -> Hit!
        let frame2 = makeFrame(timestamp: 10.0, weight: 22.0)
        let result2 = engine.evaluate(
            stage: relativeStage,
            stageIndex: 1,
            totalStages: 3,
            frame: frame2,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(result2.shouldAdvanceStage)
        XCTAssertEqual(result2.exitTriggerItems.first!.progress, 1.0)
    }
    
    /// Verifies the multi-trigger race condition: whichever trigger has the highest progress is flagged `isLeading`.
    func test_multiTriggerRace_leadingTriggerFlagsIsLeading() {
        let stage = makeStage(
            type: .pressure,
            triggers: [
                ExitTrigger(type: .time, value: .value(10.0), relative: true),
                ExitTrigger(type: .weight, value: .value(20.0), relative: true)
            ]
        )
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        // Condition A: Time is at 6.0s (60%), Weight is at 4.0g (20%) -> Time leads
        let frameA = makeFrame(timestamp: 6.0, weight: 4.0)
        let resultA = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: frameA,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultA.shouldAdvanceStage)
        let timeItemA = resultA.exitTriggerItems.first(where: { $0.sensorKey == .time })!
        let weightItemA = resultA.exitTriggerItems.first(where: { $0.sensorKey == .weight })!
        XCTAssertTrue(timeItemA.isLeading, "Time at 60% should be leading over weight at 20%")
        XCTAssertFalse(weightItemA.isLeading)
        
        // Condition B: Time is at 7.0s (70%), Weight accelerates to 18.0g (90%) -> Weight takes lead!
        let frameB = makeFrame(timestamp: 7.0, weight: 18.0)
        let resultB = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: frameB,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultB.shouldAdvanceStage)
        let timeItemB = resultB.exitTriggerItems.first(where: { $0.sensorKey == .time })!
        let weightItemB = resultB.exitTriggerItems.first(where: { $0.sensorKey == .weight })!
        XCTAssertFalse(timeItemB.isLeading)
        XCTAssertTrue(weightItemB.isLeading, "Weight at 90% should be leading over time at 70%")
        
        // Condition C: Weight hits 20.0g first -> shouldAdvanceStage fires
        let frameC = makeFrame(timestamp: 8.0, weight: 20.0)
        let resultC = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: frameC,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultC.shouldAdvanceStage)
    }
    
    /// When a stage defines no explicit exit triggers, it must fall back to the profile final weight cutoff.
    func test_stageWithoutExitTriggers_fallsBackToFinalWeightCutoff() {
        let stageNoTriggers = makeStage(
            type: .pressure,
            triggers: []
        )
        let baseline = StageBaseline(startTime: 10.0, startWeight: 15.0)
        
        let frameBelow = makeFrame(timestamp: 15.0, weight: 35.5)
        let resultBelow = engine.evaluate(
            stage: stageNoTriggers,
            stageIndex: 2,
            totalStages: 3,
            frame: frameBelow,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultBelow.shouldAdvanceStage)
        XCTAssertEqual(resultBelow.exitTriggerItems.count, 1)
        XCTAssertEqual(resultBelow.exitTriggerItems.first?.label, "Final Weight Cutoff")
        XCTAssertEqual(resultBelow.exitTriggerItems.first!.progress, 35.5 / 36.0, accuracy: 0.001)
        
        let frameMet = makeFrame(timestamp: 16.0, weight: 36.0)
        let resultMet = engine.evaluate(
            stage: stageNoTriggers,
            stageIndex: 2,
            totalStages: 3,
            frame: frameMet,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultMet.shouldAdvanceStage)
        XCTAssertEqual(resultMet.exitTriggerItems.first!.progress, 1.0)
    }
    
    // MARK: - 2. Limit / Guardrail Breaches
    
    /// Verifies safety limit evaluation and breach flags for pressure.
    func test_pressureLimit_evaluatesBreachAccurately() {
        let stage = makeStage(
            type: .flow,
            limits: [Limit(type: .pressure, value: .value(9.0))]
        )
        let baseline = StageBaseline()
        
        // 1. Operating in-bounds (8.5 bar)
        let frameNormal = makeFrame(pressure: 8.5)
        let resultNormal = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameNormal,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertNotNil(resultNormal.guidanceFrame.guardrail)
        XCTAssertFalse(resultNormal.guidanceFrame.guardrail!.isBreached)
        XCTAssertFalse(resultNormal.guidanceFrame.isAlarmActive)
        
        // 2. Over limit (9.4 bar) -> Alarm breach!
        let frameBreached = makeFrame(pressure: 9.4)
        let resultBreached = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameBreached,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultBreached.guidanceFrame.guardrail!.isBreached)
        XCTAssertTrue(resultBreached.guidanceFrame.isAlarmActive)
        XCTAssertEqual(resultBreached.guidanceFrame.guardrail!.actualValue, 9.4)
        XCTAssertEqual(resultBreached.guidanceFrame.guardrail!.limitValue, 9.0)
    }
    
    /// Verifies flow limit evaluation and breach flags.
    func test_flowLimit_evaluatesBreachAccurately() {
        let stage = makeStage(
            type: .pressure,
            limits: [Limit(type: .flow, value: .value(4.0))]
        )
        let baseline = StageBaseline()
        
        let frameNormal = makeFrame(flow: 3.5)
        let resultNormal = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameNormal,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertFalse(resultNormal.guidanceFrame.guardrail!.isBreached)
        
        let frameBreached = makeFrame(flow: 4.2)
        let resultBreached = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameBreached,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertTrue(resultBreached.guidanceFrame.guardrail!.isBreached)
        XCTAssertEqual(resultBreached.guidanceFrame.guardrail!.metric, .flow)
    }
    
    /// A stage with no limits should yield `guardrail == nil` and `isAlarmActive == false`.
    func test_stageWithoutLimits_guardrailIsNil() {
        let stage = makeStage(type: .pressure, limits: nil)
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: makeFrame(),
            baseline: StageBaseline(),
            finalWeightTarget: 36.0
        )
        XCTAssertNil(result.guidanceFrame.guardrail)
        XCTAssertFalse(result.guidanceFrame.isAlarmActive)
    }
    
    // MARK: - 3. Math & Guidance Trajectories
    
    /// Verifies multi-knot linear interpolation and target setpoint evaluation.
    func test_trajectoryInterpolation_computesExactIntermediateSetpoint() {
        // Ramp: 2.0 bar at 0s up to 6.0 bar at 4s
        let stage = makeStage(
            type: .pressure,
            points: [(0.0, 2.0), (4.0, 6.0)],
            over: .time
        )
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        // At t = 2.0s (midpoint), expected target is exactly 4.0 bar
        let frameMid = makeFrame(timestamp: 2.0, pressure: 4.5)
        let resultMid = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameMid,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertEqual(resultMid.guidanceFrame.targetValue, 4.0, accuracy: 0.001)
        XCTAssertEqual(resultMid.guidanceFrame.actualValue, 4.5, accuracy: 0.001)
        XCTAssertEqual(resultMid.guidanceFrame.delta, 0.5, accuracy: 0.001)
    }
    
    /// Verifies dynamics over weight: target interpolates along accumulated grams rather than seconds.
    func test_trajectoryInterpolation_evaluatesOverWeightDomain() {
        // Decline: 9.0 bar at 0g down to 5.0 bar at 20g
        let stage = makeStage(
            type: .pressure,
            points: [(0.0, 9.0), (20.0, 5.0)],
            over: .weight
        )
        let baseline = StageBaseline(startTime: 5.0, startWeight: 10.0)
        
        // Current weight = 20.0g -> local weight = 10.0g (midpoint: (9.0 + 5.0) / 2 = 7.0 bar)
        let frameMid = makeFrame(timestamp: 12.0, pressure: 7.2, weight: 20.0)
        let resultMid = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frameMid,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertEqual(resultMid.guidanceFrame.targetValue, 7.0, accuracy: 0.001)
        XCTAssertEqual(resultMid.guidanceFrame.delta, 0.2, accuracy: 0.001)
    }
    
    /// Verifies the Meticulous infinite flatline rule: past the final defined knot, target holds steady.
    func test_trajectory_infiniteFlatlineHoldPastLastKnot() {
        let stage = makeStage(
            type: .pressure,
            points: [(0.0, 2.0), (3.0, 8.0)], // Last knot defined at 3.0s
            over: .time
        )
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        // At t = 10.0s (well beyond 3.0s), target must hold at 8.0 bar
        let frameLate = makeFrame(timestamp: 10.0, pressure: 7.8)
        let resultLate = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameLate,
            baseline: baseline,
            finalWeightTarget: 36.0
        )
        XCTAssertEqual(resultLate.guidanceFrame.targetValue, 8.0, accuracy: 0.001)
        XCTAssertEqual(resultLate.guidanceFrame.delta, -0.2, accuracy: 0.001)
        
        let lastPlanPoint = resultLate.planCurve.last
        XCTAssertNotNil(lastPlanPoint)
        XCTAssertGreaterThanOrEqual(lastPlanPoint!.x, 10.0)
        XCTAssertEqual(lastPlanPoint!.y, 8.0, accuracy: 0.001)
    }
    
    /// Verifies that stage progress and yield progress are cleanly normalized between 0.0 and 1.0.
    func test_progressNormalization_clampsBetweenZeroAndOne() {
        let stage = makeStage(
            type: .flow,
            triggers: [ExitTrigger(type: .weight, value: .value(20.0), relative: true)]
        )
        let baseline = StageBaseline(startTime: 0.0, startWeight: 10.0)
        
        // Weight exceeds trigger (10g start + 25g actual = +25g on 20g target)
        let frameOver = makeFrame(weight: 35.0)
        let resultOver = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameOver,
            baseline: baseline,
            finalWeightTarget: 30.0
        )
        XCTAssertEqual(resultOver.guidanceFrame.stageProgress, 1.0)
        XCTAssertEqual(resultOver.guidanceFrame.yieldProgress, 1.0)
    }
}
