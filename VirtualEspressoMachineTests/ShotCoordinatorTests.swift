//
//  ShotCoordinatorTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
import MeticulousProfile
@testable import VirtualEspressoMachine

@MainActor
final class ShotCoordinatorTests: XCTestCase {
    
    private var coordinator: ShotCoordinator!
    private var twoStageProfile: Profile!
    
    override func setUp() {
        super.setUp()
        coordinator = ShotCoordinator()
        
        // Stage 0: Pre-infusion (Exits after 2.0 seconds stage duration)
        let preinfusion = Stage(
            name: "Pre-infusion",
            key: "preinfusion",
            type: .pressure,
            dynamics: Dynamics(
                points: [Point(0.0, 3.0), Point(5.0, 3.0)],
                over: .time,
                interpolation: .linear
            ),
            exitTriggers: [
                ExitTrigger(type: .time, value: 2.0, relative: true, comparison: .greaterThanOrEqual)
            ],
            limits: [
                Limit(type: .pressure, value: 4.0)
            ]
        )
        
        // Stage 1: Extraction (Exits when total cup weight >= 10.0g)
        let extraction = Stage(
            name: "Extraction",
            key: "extraction",
            type: .pressure,
            dynamics: Dynamics(
                points: [Point(0.0, 9.0), Point(20.0, 9.0)],
                over: .time,
                interpolation: .linear
            ),
            exitTriggers: [
                ExitTrigger(type: .weight, value: 10.0, relative: false, comparison: .greaterThanOrEqual)
            ]
        )
        
        twoStageProfile = Profile(
            name: "Test Profile",
            id: "test-profile-1",
            author: "Tester",
            authorId: "tester-1",
            temperature: 93.0,
            finalWeight: 10.0,
            stages: [preinfusion, extraction]
        )
    }
    
    override func tearDown() {
        coordinator = nil
        twoStageProfile = nil
        super.tearDown()
    }
    
    // MARK: - Initial & Profile Selection
    
    func test_initialState_isIdle() {
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertNil(coordinator.activeProfile)
        XCTAssertFalse(coordinator.isAlarmActive)
        XCTAssertFalse(coordinator.isProfileComplete)
    }
    
    func test_selectProfile_configuresInitialStateAndPills() {
        coordinator.selectProfile(twoStageProfile)
        
        XCTAssertEqual(coordinator.state, .armed)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertEqual(coordinator.stagePills.count, 2)
        XCTAssertEqual(coordinator.stagePills[0].state, .active)
        XCTAssertEqual(coordinator.stagePills[1].state, .upcoming)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Pre-infusion")
        XCTAssertFalse(coordinator.isProfileComplete)
    }
    
    // MARK: - Auto-Start Transition (Pressure Exclusivity)
    
    func test_autoStart_transitionsFromArmedToExtractingOnPressure() {
        coordinator.selectProfile(twoStageProfile)
        XCTAssertEqual(coordinator.state, .armed)
        
        // Sub-threshold pressure (< 0.5 bar) -> stays armed
        let lowPressureFrame = MachineFrame(
            timestamp: 0.0,
            state: .armed,
            readings: [.pressure: 0.3, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(lowPressureFrame)
        XCTAssertEqual(coordinator.state, .armed)
        
        // Threshold crossed (>= 0.5 bar) -> transitions to extracting
        let pullFrame = MachineFrame(
            timestamp: 0.1,
            state: .armed,
            readings: [.pressure: 0.8, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(pullFrame)
        XCTAssertEqual(coordinator.state, .extracting)
    }
    
    func test_autoStart_doesNotTransitionOnWeightAlone() {
        coordinator.selectProfile(twoStageProfile)
        XCTAssertEqual(coordinator.state, .armed)
        
        // Rest cup on scale (150.0g) with zero pressure (0.0 bar) -> MUST remain armed
        let cupOnScaleFrame = MachineFrame(
            timestamp: 0.0,
            state: .armed,
            readings: [.pressure: 0.0, .flow: 0.0, .weight: 150.0]
        )
        coordinator.processTelemetryFrame(cupOnScaleFrame)
        XCTAssertEqual(coordinator.state, .armed, "Resting a cup or scale weight must never trip extraction start")
    }
    
    // MARK: - Auto-Stop Watchdog Precondition Tests (5s / 5g / 1:1)
    
    func test_autoStop_doesNotTripBeforeFiveSeconds_evenIfFlowIsZero() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // Weight is 6.0g (meets weight gate), flow is 0.0 mL/s, but timestamp is only 2.0s (< 5.0s)
        let earlyDeadFlow = MachineFrame(
            timestamp: 2.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 0.0, .weight: 6.0]
        )
        coordinator.processTelemetryFrame(earlyDeadFlow)
        
        // Timestamp 4.0s (sustain 2.0s expired, but still under 5.0s elapsed shot time)
        let frameAt4 = MachineFrame(
            timestamp: 4.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 0.0, .weight: 6.0]
        )
        coordinator.processTelemetryFrame(frameAt4)
        
        XCTAssertEqual(coordinator.state, .extracting, "Auto-stop must not trip before 5.0s elapsed shot time")
    }
    
    func test_autoStop_doesNotTripWhenWeightUnderFiveGrams_evenAfterFiveSeconds() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // Stalled pre-infusion: 8.0s elapsed, flow 0.0 mL/s, but only 0.4g in cup (< 5.0g)
        let stallFrame1 = MachineFrame(
            timestamp: 8.0,
            state: .extracting,
            readings: [.pressure: 2.5, .flow: 0.0, .weight: 0.4]
        )
        coordinator.processTelemetryFrame(stallFrame1)
        
        // Still stalled at 10.5s
        let stallFrame2 = MachineFrame(
            timestamp: 10.5,
            state: .extracting,
            readings: [.pressure: 2.5, .flow: 0.0, .weight: 0.4]
        )
        coordinator.processTelemetryFrame(stallFrame2)
        
        XCTAssertEqual(coordinator.state, .extracting, "Auto-stop must not kill stalled pre-infusions under 5.0g yield")
    }
    
    func test_autoStop_tripsWhenPreconditionsMetAndFlowDeadForSustainDuration() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // Preconditions met at t=6.0s: time >= 5.0s, weight = 7.0g >= 5.0g, flow = 0.05 <= 0.15 cutoff
        let deadStart = MachineFrame(
            timestamp: 6.0,
            state: .extracting,
            readings: [.pressure: 1.0, .flow: 0.05, .weight: 7.0]
        )
        coordinator.processTelemetryFrame(deadStart)
        XCTAssertEqual(coordinator.state, .extracting)
        
        // 1.0s later (t=7.0s): still within sustain duration (2.0s)
        let deadMid = MachineFrame(
            timestamp: 7.0,
            state: .extracting,
            readings: [.pressure: 0.5, .flow: 0.05, .weight: 7.0]
        )
        coordinator.processTelemetryFrame(deadMid)
        XCTAssertEqual(coordinator.state, .extracting)
        
        // 2.0s later (t=8.0s >= 6.0 + 2.0s sustain): auto-stop trips!
        let deadConfirmed = MachineFrame(
            timestamp: 8.0,
            state: .extracting,
            readings: [.pressure: 0.0, .flow: 0.0, .weight: 7.0]
        )
        coordinator.processTelemetryFrame(deadConfirmed)
        XCTAssertEqual(coordinator.state, .shotEnded, "Auto-stop must end shot after sustained dead flow once preconditions are met")
    }
    
    // MARK: - Multi-Stage Progression, Profile Complete & Extraction Conclusion
    
    func test_multiStageExtraction_advancesStagesAndHoldsSetpointOnCompletion() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // 1. Tick during Pre-infusion (t = 1.0s, trigger is 2.0s local)
        let stage0Frame = MachineFrame(
            timestamp: 1.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 1.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(stage0Frame)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Pre-infusion")
        
        // 2. Tick crossing Pre-infusion trigger (t = 2.0s >= 2.0s local)
        let advanceFrame = MachineFrame(
            timestamp: 2.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 1.0, .weight: 1.0]
        )
        coordinator.processTelemetryFrame(advanceFrame)
        
        // Must advance to Stage 1 (Extraction)
        XCTAssertEqual(coordinator.activeStageIndex, 1)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Extraction")
        XCTAssertEqual(coordinator.currentStageBaseline.startTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(coordinator.currentStageBaseline.startWeight, 1.0, accuracy: 0.001)
        XCTAssertEqual(coordinator.stagePills[0].state, .completed)
        XCTAssertEqual(coordinator.stagePills[1].state, .active)
        
        // 3. Tick during Extraction (weight = 5.0g, trigger is 10.0g absolute)
        let stage1Frame = MachineFrame(
            timestamp: 4.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 5.0]
        )
        coordinator.processTelemetryFrame(stage1Frame)
        XCTAssertEqual(coordinator.activeStageIndex, 1)
        XCTAssertEqual(coordinator.state, .extracting)
        XCTAssertFalse(coordinator.isProfileComplete)
        
        // 4. Tick crossing Extraction trigger (weight = 10.0g >= 10.0g absolute) with active flow (2.0 mL/s)
        let finalProfileFrame = MachineFrame(
            timestamp: 7.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 10.0]
        )
        coordinator.processTelemetryFrame(finalProfileFrame)
        
        // Guidance reaches completion, but shot remains extracting while liquid flows!
        XCTAssertEqual(coordinator.state, .extracting, "Shot must not terminate immediately while flow is active")
        XCTAssertTrue(coordinator.isProfileComplete)
        XCTAssertEqual(coordinator.exitTriggerItems.first?.label, "Profile Complete")
        
        // 5. Liquid flow ceases -> Dead-flow watchdog triggers final conclusion
        let flowStop1 = MachineFrame(
            timestamp: 7.5,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 0.05, .weight: 10.2]
        )
        let flowStop2 = MachineFrame(
            timestamp: 9.5,
            state: .extracting,
            readings: [.pressure: 0.0, .flow: 0.0, .weight: 10.2]
        )
        coordinator.processTelemetryFrame(flowStop1)
        coordinator.processTelemetryFrame(flowStop2)
        
        XCTAssertEqual(coordinator.state, .shotEnded)
    }
    
    // MARK: - Retroactive Tail Trimming Test
    
    func test_retroactiveTailTrimming_anchorsDurationAndWeightToTrueFlowStop() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // Active flow up to t = 6.0s (weight = 8.0g, flow = 1.5)
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 6.0, state: .extracting, readings: [.pressure: 9.0, .flow: 1.5, .weight: 8.0])
        )
        
        // Flow drops below cutoff at t = 6.1s (weight = 8.2g, flow = 0.05)
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 6.1, state: .extracting, readings: [.pressure: 2.0, .flow: 0.05, .weight: 8.2])
        )
        
        // 2-second sustain period where flow remains dead
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 7.1, state: .extracting, readings: [.pressure: 0.0, .flow: 0.0, .weight: 8.2])
        )
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 8.1, state: .extracting, readings: [.pressure: 0.0, .flow: 0.0, .weight: 8.2])
        )
        
        XCTAssertEqual(coordinator.state, .shotEnded)
        
        let record = coordinator.completedShotRecord
        XCTAssertNotNil(record)
        // Must be trimmed back to t = 6.1s (where flow first dropped below cutoff), NOT 8.1s!
        XCTAssertEqual(record?.duration ?? 0.0, 6.1, accuracy: 0.05)
        XCTAssertEqual(record?.finalWeight ?? 0.0, 8.2, accuracy: 0.05)
        XCTAssertEqual(record?.samples.last?.timestamp ?? 0.0, 6.1, accuracy: 0.05)
    }
    
    // MARK: - Guardrail Alarms
    
    func test_guardrailBreach_activatesAlarm() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // Limit on Stage 0 is 4.0 bar. Frame has 4.5 bar -> breach!
        let breachFrame = MachineFrame(
            timestamp: 0.5,
            state: .extracting,
            readings: [.pressure: 4.5, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(breachFrame)
        
        XCTAssertTrue(coordinator.isAlarmActive)
        XCTAssertEqual(coordinator.guidanceFrame.guardrail?.isBreached, true)
    }
}
