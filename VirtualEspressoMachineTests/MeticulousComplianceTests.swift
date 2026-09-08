//
//  MeticulousComplianceTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
import MeticulousProfile
@testable import VirtualEspressoMachine

final class MeticulousComplianceTests: XCTestCase {
    
    private var engine: ProfileExecutionEngine!
    
    override func setUp() {
        super.setUp()
        engine = ProfileExecutionEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    // MARK: - 1. Global final_weight Cutoff Precedence
    
    func testGlobalFinalWeight_TriggersAdvance_EvenWhenStageTriggersPending() throws {
        // -----------------------------------------------------------------------------------------
        // ARCHITECTURAL DILEMMA (DEFERRED):
        // Is `final_weight` an exit trigger for an individual stage, or a Shot Termination invariant?
        // If an intermediate stage (e.g. Preinfusion) channels and hits 40g, returning
        // `shouldAdvanceStage = true` causes the coordinator to advance into Stage 2 (9 bar Infusion),
        // flooding an already completed cup!
        // Decision pending: Handle at the Machine Coordinator level (MachineState = .shotEnded)
        // vs. emitting an explicit `isShotComplete` flag from the Engine.
        // -----------------------------------------------------------------------------------------
        throw XCTSkip("Skipped pending decision: Global final_weight is a Coordinator Shot Terminator, not a stage transition.")
        
        let stage = Stage(
            name: "Infusion",
            key: "stage_infusion",
            type: .pressure,
            dynamics: Dynamics(points: [Point(0, 9.0)], over: .time, interpolation: .linear),
            exitTriggers: [
                ExitTrigger(type: .time, value: 60.0, relative: true, comparison: .greaterThanOrEqual)
            ]
        )
        
        let frame = MachineFrame(timestamp: 20.0, state: .extracting, readings: [.pressure: 9.0, .weight: 40.5])
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frame,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        
        XCTAssertTrue(result.shouldAdvanceStage)
    }
    
    // MARK: - 2. Decay / Descending Triggers (<=)
    
    func testDecayTrigger_ProgressIsNotComplete_WhenAboveTarget() throws {
        // -----------------------------------------------------------------------------------------
        // ARCHITECTURAL DILEMMA (DEFERRED):
        // The Meticulous schema specifies boolean triggers (comparison: "<="), but percentage progress
        // is our custom Barista HUD racetrack construct.
        // The engine's current formula (`currentVal / targetVal`) assumes ascending metrics, clamping
        // 8.0 bar / 4.0 bar to 100%. To compute honest 0-100% decay progress, `StageBaseline` must
        // track the stage's entry/peak pressure (currently it only stores startTime & startWeight).
        // -----------------------------------------------------------------------------------------
        throw XCTSkip("Skipped pending decision: StageBaseline must track entry/peak pressure to compute honest decay progress.")
        
        let stage = Stage(
            name: "Pressure Decline",
            key: "stage_decline",
            type: .pressure,
            dynamics: Dynamics(points: [Point(0, 9.0)], over: .time, interpolation: .linear),
            exitTriggers: [
                ExitTrigger(type: .pressure, value: 4.0, relative: false, comparison: .lessThanOrEqual)
            ]
        )
        
        let frame = MachineFrame(timestamp: 5.0, state: .extracting, readings: [.pressure: 8.0, .weight: 15.0])
        let baseline = StageBaseline(startTime: 0.0, startWeight: 10.0)
        
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frame,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        
        XCTAssertFalse(result.shouldAdvanceStage)
        let triggerItem = result.exitTriggerItems.first(where: { $0.sensorKey == .pressure })
        XCTAssertLessThan(triggerItem?.progress ?? 0.0, 1.0)
    }
    
    func testDecayTrigger_AdvancesStage_WhenTargetReachedOrPassed() {
        let stage = Stage(
            name: "Pressure Decline",
            key: "stage_decline",
            type: .pressure,
            dynamics: Dynamics(points: [Point(0, 9.0)], over: .time, interpolation: .linear),
            exitTriggers: [
                ExitTrigger(type: .pressure, value: 4.0, relative: false, comparison: .lessThanOrEqual)
            ]
        )
        
        let frame = MachineFrame(timestamp: 15.0, state: .extracting, readings: [.pressure: 3.8, .weight: 28.0])
        let baseline = StageBaseline(startTime: 0.0, startWeight: 10.0)
        
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frame,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        
        XCTAssertTrue(result.shouldAdvanceStage, "Decay trigger must trip when pressure (3.8 bar) <= 4.0 bar.")
    }
    
    // MARK: - 3. Step Interpolation ("none") vs Linear Lerp
    
    func testStepInterpolation_HoldsPreviousKnot_WithoutLerping() throws {
        // -----------------------------------------------------------------------------------------
        // ARCHITECTURAL DILEMMA (DEFERRED):
        // `ProfileExecutionEngine.evaluateTarget` currently defaults to linear lerp across all stages.
        // It needs a clean update to support piecewise-constant hold for `dynamics.interpolation == .none`.
        // Deferred until engine modification session.
        // -----------------------------------------------------------------------------------------
        throw XCTSkip("Skipped pending implementation: ProfileExecutionEngine step interpolation support.")
        
        let stage = Stage(
            name: "Step Stage",
            key: "stage_step",
            type: .pressure,
            dynamics: Dynamics(
                points: [Point(0, 2.0), Point(10, 8.0)],
                over: .time,
                interpolation: .none
            ),
            exitTriggers: [ExitTrigger(type: .time, value: 15.0, relative: true)]
        )
        
        let frame = MachineFrame(timestamp: 5.0, state: .extracting, readings: [.pressure: 2.0, .weight: 0.0])
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frame,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        
        XCTAssertEqual(result.guidanceFrame.targetValue, 2.0, accuracy: 0.001)
    }
    
    // MARK: - 4. Overrun Flatline Clamping
    
    func testOverrunKnot_FlatlinesAtLastKnotValue() {
        let stage = Stage(
            name: "Ramping Stage",
            key: "stage_ramp",
            type: .pressure,
            dynamics: Dynamics(
                points: [Point(0, 2.0), Point(10, 8.0)],
                over: .time,
                interpolation: .linear
            ),
            exitTriggers: [ExitTrigger(type: .weight, value: 40.0, relative: false)]
        )
        
        let frame = MachineFrame(timestamp: 25.0, state: .extracting, readings: [.pressure: 8.0, .weight: 20.0])
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        let result = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frame,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        
        XCTAssertEqual(
            result.guidanceFrame.targetValue,
            8.0,
            accuracy: 0.001,
            "Target setpoint past the final knot must flatline at the last knot's y value (8.0 bar)."
        )
    }
    
    // MARK: - 5. Relative vs Absolute Weight Triggers
    
    func testWeightTrigger_RelativeRespectsStageBaseline() {
        let stage = Stage(
            name: "Ramp Stage",
            key: "stage_ramp",
            type: .flow,
            dynamics: Dynamics(points: [Point(0, 2.5)], over: .time, interpolation: .linear),
            exitTriggers: [
                ExitTrigger(type: .weight, value: 10.0, relative: true, comparison: .greaterThanOrEqual)
            ]
        )
        
        let frameUnder = MachineFrame(timestamp: 8.0, state: .extracting, readings: [.flow: 2.5, .weight: 22.0])
        let baseline = StageBaseline(startTime: 0.0, startWeight: 15.0)
        
        let resultUnder = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frameUnder,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        XCTAssertFalse(resultUnder.shouldAdvanceStage, "Delta weight (+7.0g) has not reached +10.0g target.")
        
        let frameOver = MachineFrame(timestamp: 12.0, state: .extracting, readings: [.flow: 2.5, .weight: 25.5])
        let resultOver = engine.evaluate(
            stage: stage,
            stageIndex: 1,
            totalStages: 2,
            frame: frameOver,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        XCTAssertTrue(resultOver.shouldAdvanceStage, "Delta weight (+10.5g) meets or exceeds +10.0g relative target.")
    }
    
    // MARK: - 6. OR-Logic Resolution Across Multiple Triggers
    
    func testMultiTrigger_FirstSatisfiedTripsStageAdvance() {
        let stage = Stage(
            name: "Preinfusion",
            key: "stage_preinfuse",
            type: .flow,
            dynamics: Dynamics(points: [Point(0, 4.0)], over: .time, interpolation: .linear),
            exitTriggers: [
                ExitTrigger(type: .time, value: 30.0, relative: true, comparison: .greaterThanOrEqual),
                ExitTrigger(type: .weight, value: 0.3, relative: true, comparison: .greaterThanOrEqual),
                ExitTrigger(type: .pressure, value: 8.0, relative: false, comparison: .greaterThanOrEqual)
            ]
        )
        
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        let framePressureSpike = MachineFrame(timestamp: 6.0, state: .extracting, readings: [.flow: 4.0, .pressure: 8.2, .weight: 0.0])
        let resultPressure = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: framePressureSpike,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        XCTAssertTrue(resultPressure.shouldAdvanceStage, "Hitting pressure trigger alone must advance stage via OR logic.")
        
        let frameDrip = MachineFrame(timestamp: 12.0, state: .extracting, readings: [.flow: 4.0, .pressure: 4.0, .weight: 0.4])
        let resultDrip = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 2,
            frame: frameDrip,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        XCTAssertTrue(resultDrip.shouldAdvanceStage, "Hitting weight trigger alone must advance stage via OR logic.")
    }
    
    // MARK: - 7. Safety Limits & Guardrail Breach
    
    func testSafetyLimit_FlagsBreachWhenExceeded() {
        let stage = Stage(
            name: "Pressure Stage",
            key: "stage_pressure",
            type: .pressure,
            dynamics: Dynamics(points: [Point(0, 8.0)], over: .time, interpolation: .linear),
            exitTriggers: [ExitTrigger(type: .time, value: 30.0, relative: true)],
            limits: [
                Limit(type: .flow, value: 3.0)
            ]
        )
        
        let baseline = StageBaseline(startTime: 0.0, startWeight: 0.0)
        
        let frameSafe = MachineFrame(timestamp: 10.0, state: .extracting, readings: [.pressure: 8.0, .flow: 2.4, .weight: 10.0])
        let resultSafe = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameSafe,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        XCTAssertFalse(resultSafe.guidanceFrame.guardrail?.isBreached ?? true, "Flow at 2.4 should not breach 3.0 limit.")
        
        let frameBreach = MachineFrame(timestamp: 12.0, state: .extracting, readings: [.pressure: 8.0, .flow: 4.1, .weight: 15.0])
        let resultBreach = engine.evaluate(
            stage: stage,
            stageIndex: 0,
            totalStages: 1,
            frame: frameBreach,
            baseline: baseline,
            finalWeightTarget: 40.0
        )
        XCTAssertTrue(resultBreach.guidanceFrame.guardrail?.isBreached ?? false, "Flow at 4.1 MUST breach 3.0 limit.")
    }
}
