//
//  ShotCoordinatorTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
import MeticulousProfile
import EspressoBLE
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
        
        let lowPressureFrame = MachineFrame(
            timestamp: 0.0,
            state: .armed,
            readings: [.pressure: 0.3, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(lowPressureFrame)
        XCTAssertEqual(coordinator.state, .armed)
        
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
        
        let earlyDeadFlow = MachineFrame(
            timestamp: 2.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 0.0, .weight: 6.0]
        )
        coordinator.processTelemetryFrame(earlyDeadFlow)
        
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
        
        let stallFrame1 = MachineFrame(
            timestamp: 8.0,
            state: .extracting,
            readings: [.pressure: 2.5, .flow: 0.0, .weight: 0.4]
        )
        coordinator.processTelemetryFrame(stallFrame1)
        
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
        
        let deadStart = MachineFrame(
            timestamp: 6.0,
            state: .extracting,
            readings: [.pressure: 1.0, .flow: 0.05, .weight: 7.0]
        )
        coordinator.processTelemetryFrame(deadStart)
        XCTAssertEqual(coordinator.state, .extracting)
        
        let deadMid = MachineFrame(
            timestamp: 7.0,
            state: .extracting,
            readings: [.pressure: 0.5, .flow: 0.05, .weight: 7.0]
        )
        coordinator.processTelemetryFrame(deadMid)
        XCTAssertEqual(coordinator.state, .extracting)
        
        let deadConfirmed = MachineFrame(
            timestamp: 8.0,
            state: .extracting,
            readings: [.pressure: 0.0, .flow: 0.0, .weight: 7.0]
        )
        coordinator.processTelemetryFrame(deadConfirmed)
        XCTAssertEqual(coordinator.state, .shotEnded, "Auto-stop must end shot after sustained dead flow once preconditions are met")
    }
    
    // MARK: - ADR-009 Dead-Flow Staleness Suspension Tests
    
    func test_autoStop_isSuspended_whenScaleIsStale() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        let activeFrame = MachineFrame(
            timestamp: 6.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 8.0],
            isScaleStale: false
        )
        coordinator.processTelemetryFrame(activeFrame)
        XCTAssertEqual(coordinator.state, .extracting)
        
        // Scale stalls or drops packets for 3.0 seconds (t = 6.1s to 9.1s)
        for t in stride(from: 6.1, through: 9.1, by: 0.5) {
            let staleFrame = MachineFrame(
                timestamp: t,
                state: .extracting,
                readings: [.pressure: 9.0, .flow: 0.0, .weight: 8.0],
                isScaleStale: true
            )
            coordinator.processTelemetryFrame(staleFrame)
            XCTAssertEqual(
                coordinator.state,
                .extracting,
                "Dead-flow watchdog must be suspended during scale silence (ADR-009)"
            )
        }
    }
    
    func test_autoStop_resumesAndTrips_afterScaleRecoversFromStaleness() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        // 1. Stale scale silence at t = 6.0s - 8.0s
        let staleFrame = MachineFrame(
            timestamp: 7.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 0.0, .weight: 8.0],
            isScaleStale: true
        )
        coordinator.processTelemetryFrame(staleFrame)
        XCTAssertEqual(coordinator.state, .extracting)
        
        // 2. Scale recovers at t = 8.1s reporting genuine zero flow (connected and not stale)
        let recoveryStart = MachineFrame(
            timestamp: 8.1,
            state: .extracting,
            readings: [.pressure: 1.0, .flow: 0.05, .weight: 8.2],
            isScaleStale: false
        )
        coordinator.processTelemetryFrame(recoveryStart)
        XCTAssertEqual(coordinator.state, .extracting)
        
        // 3. Genuine zero flow sustained for 2.0s (t = 10.1s >= 8.1 + 2.0s)
        let recoverySustained = MachineFrame(
            timestamp: 10.2,
            state: .extracting,
            readings: [.pressure: 0.0, .flow: 0.0, .weight: 8.2],
            isScaleStale: false
        )
        coordinator.processTelemetryFrame(recoverySustained)
        XCTAssertEqual(
            coordinator.state,
            .shotEnded,
            "Auto-stop watchdog must resume evaluation and end shot once scale is verified not stale"
        )
    }
    
    // MARK: - Multi-Stage Progression & Extraction Conclusion
    
    func test_multiStageExtraction_advancesStagesAndHoldsSetpointOnCompletion() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        let stage0Frame = MachineFrame(
            timestamp: 1.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 1.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(stage0Frame)
        XCTAssertEqual(coordinator.activeStageIndex, 0)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Pre-infusion")
        
        let advanceFrame = MachineFrame(
            timestamp: 2.0,
            state: .extracting,
            readings: [.pressure: 3.0, .flow: 1.0, .weight: 1.0]
        )
        coordinator.processTelemetryFrame(advanceFrame)
        
        XCTAssertEqual(coordinator.activeStageIndex, 1)
        XCTAssertEqual(coordinator.guidanceFrame.stageName, "Extraction")
        XCTAssertEqual(coordinator.currentStageBaseline.startTime, 2.0, accuracy: 0.001)
        XCTAssertEqual(coordinator.currentStageBaseline.startWeight, 1.0, accuracy: 0.001)
        XCTAssertEqual(coordinator.stagePills[0].state, .completed)
        XCTAssertEqual(coordinator.stagePills[1].state, .active)
        
        let stage1Frame = MachineFrame(
            timestamp: 4.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 5.0]
        )
        coordinator.processTelemetryFrame(stage1Frame)
        XCTAssertEqual(coordinator.activeStageIndex, 1)
        XCTAssertEqual(coordinator.state, .extracting)
        XCTAssertFalse(coordinator.isProfileComplete)
        
        let finalProfileFrame = MachineFrame(
            timestamp: 7.0,
            state: .extracting,
            readings: [.pressure: 9.0, .flow: 2.0, .weight: 10.0]
        )
        coordinator.processTelemetryFrame(finalProfileFrame)
        
        XCTAssertEqual(coordinator.state, .extracting, "Shot must not terminate immediately while flow is active")
        XCTAssertTrue(coordinator.isProfileComplete)
        XCTAssertEqual(coordinator.exitTriggerItems.first?.label, "Profile Complete")
        
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
        
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 6.0, state: .extracting, readings: [.pressure: 9.0, .flow: 1.5, .weight: 8.0])
        )
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 6.1, state: .extracting, readings: [.pressure: 2.0, .flow: 0.05, .weight: 8.2])
        )
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 7.1, state: .extracting, readings: [.pressure: 0.0, .flow: 0.0, .weight: 8.2])
        )
        coordinator.processTelemetryFrame(
            MachineFrame(timestamp: 8.1, state: .extracting, readings: [.pressure: 0.0, .flow: 0.0, .weight: 8.2])
        )
        
        XCTAssertEqual(coordinator.state, .shotEnded)
        
        let record = coordinator.completedShotRecord
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.duration ?? 0.0, 6.1, accuracy: 0.05)
        XCTAssertEqual(record?.finalWeight ?? 0.0, 8.2, accuracy: 0.05)
        XCTAssertEqual(record?.samples.last?.timestamp ?? 0.0, 6.1, accuracy: 0.05)
    }
    
    // MARK: - Guardrail Alarms
    
    func test_guardrailBreach_activatesAlarm() {
        coordinator.selectProfile(twoStageProfile)
        coordinator.startExtraction()
        
        let breachFrame = MachineFrame(
            timestamp: 0.5,
            state: .extracting,
            readings: [.pressure: 4.5, .flow: 0.0, .weight: 0.0]
        )
        coordinator.processTelemetryFrame(breachFrame)
        
        XCTAssertTrue(coordinator.isAlarmActive)
        XCTAssertEqual(coordinator.guidanceFrame.guardrail?.isBreached, true)
    }
    
    // MARK: - OLS Regression Re-Anchoring Unit Test (ADR-009)
    
    func test_olsRegressionFlow_purgesAndAvoidsSpikesOnGap() {
        let bleManager = EspressoBLEManager()
        let provider = BLETelemetryProvider(bleManager: bleManager)
        
        // Feed 3 contiguous frames @ 10 Hz (t = 1.0, 1.1, 1.2) with steady 2.0 g/s flow (+0.2g / 0.1s)
        _ = provider.calculateRegressionFlow(currentTime: 1.0, currentWeight: 2.0, isStale: false)
        _ = provider.calculateRegressionFlow(currentTime: 1.1, currentWeight: 2.2, isStale: false)
        let flowNormal = provider.calculateRegressionFlow(currentTime: 1.2, currentWeight: 2.4, isStale: false)
        XCTAssertEqual(flowNormal, 2.0, accuracy: 0.2)
        
        // Simulate a 1.5s radio dropout (jump from t = 1.2s to t = 2.7s with +3.0g weight jump)
        // First packet after gap must re-anchor and output 0.0 mL/s rather than spiking
        let flowAfterGapPacket1 = provider.calculateRegressionFlow(currentTime: 2.7, currentWeight: 5.4, isStale: false)
        XCTAssertEqual(flowAfterGapPacket1, 0.0, "First sample after gap must re-anchor without producing a flow spike")
        
        // Second packet contiguous: still < 3 samples, must output 0.0
        let flowAfterGapPacket2 = provider.calculateRegressionFlow(currentTime: 2.8, currentWeight: 5.6, isStale: false)
        XCTAssertEqual(flowAfterGapPacket2, 0.0)
        
        // Third contiguous packet: resumes normal linear regression calculation
        let flowResumed = provider.calculateRegressionFlow(currentTime: 2.9, currentWeight: 5.8, isStale: false)
        XCTAssertEqual(flowResumed, 2.0, accuracy: 0.2)
    }
}
