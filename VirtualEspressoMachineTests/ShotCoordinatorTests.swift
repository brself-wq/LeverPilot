//
//  ShotCoordinatorTests.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/10/26.
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
        
        // Stage 0: Pre-infusion (Exits after 2.0 seconds)
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
                ExitTrigger(type: .time, value: 2.0, comparison: .greaterThanOrEqual)
            ],
            limits: [
                Limit(type: .pressure, value: 4.0)
            ]
        )
        
        // Stage 1: Extraction (Exits when weight >= 10.0g)
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
                ExitTrigger(type: .weight, value: 10.0, comparison: .greaterThanOrEqual)
            ]
        )
        
        twoStageProfile = Profile(
            name: "Test Recipe",
            id: "test-recipe-1",
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
    
    func test_initialState_isReady() {
        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertNil(coordinator.activeProfile)
        XCTAssertFalse(coordinator.isAlarmActive)
    }
    
    func test_selectProfile_configuresInitialStateAndPills() {
        coordinator.selectProfile(twoStageProfile)
        
        XCTAssertEqual(coordinator.state, .profileSelected)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertEqual(coordinator.stagePills.count, 2)
        XCTAssertEqual(coordinator.stagePills[0].state, .active)
        XCTAssertEqual(coordinator.stagePills[1].state, .upcoming)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Pre-infusion")
    }
    
    // MARK: - Auto-Start Transition
    
    func test_autoStart_transitionsFromShotReadyToExtractingOnPressure() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.setToShotReady()
        XCTAssertEqual(coordinator.state, .shotReady)
        
        // Sub-threshold pressure (< 0.5 bar) -> stays in shotReady
        let lowPressureFrame = MachineFrame(
            timestamp: 0.0,
            state: .shotReady,
            readings: [.pressure: 0.3, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(lowPressureFrame)
        XCTAssertEqual(coordinator.state, .shotReady)
        
        // Threshold crossed (>= 0.5 bar) -> transitions to extracting
        let pullFrame = MachineFrame(
            timestamp: 0.1,
            state: .shotReady,
            readings: [.pressure: 0.8, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(pullFrame)
        XCTAssertEqual(coordinator.state, .extracting)
    }
    
    // MARK: - Multi-Stage Progression & End of Shot
    
    func test_multiStageExtraction_advancesStagesAndEndsShot() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.setToShotReady()
        coordinator.startExtraction()
        
        // 1. Tick during Pre-infusion (t = 1.0s, trigger is 2.0s)
        let stage0Frame = MachineFrame(
            timestamp: 1.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 1.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(stage0Frame)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Pre-infusion")
        
        // 2. Tick crossing Pre-infusion trigger (t = 2.0s >= 2.0s)
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
        
        // 3. Tick during Extraction (weight = 5.0g, trigger is 10.0g)
        let stage1Frame = MachineFrame(
            timestamp: 4.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 5.0]
        )
        coordinator.processTelemetryFrame(stage1Frame)
        XCTAssertEqual(coordinator.activeStageIndex, 1)
        XCTAssertEqual(coordinator.state, .extracting)
        
        // 4. Tick crossing Extraction trigger (weight = 10.0g >= 10.0g)
        let finalFrame = MachineFrame(
            timestamp: 7.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 10.0]
        )
        coordinator.processTelemetryFrame(finalFrame)
        
        // Must transition to .shotEnded
        XCTAssertEqual(coordinator.state, .shotEnded)
    }
    
    // MARK: - Guardrail Alarms
    
    func test_guardrailBreach_activatesAlarm() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.setToShotReady()
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
