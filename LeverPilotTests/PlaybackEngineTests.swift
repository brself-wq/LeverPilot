//
//  PlaybackEngineTests.swift
//  LeverPilotTests
//
//  Step 4: Headless Playback State Machine Suite
//

import XCTest
@testable import LeverPilot

@MainActor
final class PlaybackEngineTests: XCTestCase {
    
    private var engine: PlaybackEngine!
    private var mockScenario: ShotRecord!
    
    override func setUp() {
        super.setUp()
        
        // Construct 5 discrete samples (0.0s, 0.1s, 0.2s, 0.3s, 0.4s)
        let samples = (0..<5).map { idx in
            ShotSample(
                timestamp: Double(idx) * 0.1,
                pressure: Double(idx) * 1.5,
                flow: 2.0,
                weight: Double(idx) * 3.0,
                stageIndex: 0
            )
        }
        
        mockScenario = ShotRecord(
            id: "test-scenario",
            profileId: "profile-1",
            duration: 0.4,
            finalWeight: 12.0,
            targetWeight: 12.0,
            samples: samples
        )
        
        engine = PlaybackEngine()
        engine.load(scenario: mockScenario)
    }
    
    override func tearDown() {
        engine.stop()
        engine = nil
        mockScenario = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func test_initialLoadedState() {
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.currentSampleIndex, 0)
        XCTAssertEqual(engine.totalSamplesCount, 5)
        XCTAssertEqual(engine.currentTimestamp, 0.0)
        XCTAssertTrue(engine.canStepForward)
        XCTAssertFalse(engine.canStepBackward)
        XCTAssertEqual(engine.playbackSpeedMultiplier, 1.0)
        XCTAssertEqual(engine.speedLabel, "100%")
    }
    
    // MARK: - Step Forward & Step Backward Boundaries
    
    func test_stepForward_incrementsSampleIndexAndTriggersTick() {
        var callbackReceived = false
        engine.onTick = { sample, scenario in
            callbackReceived = true
            XCTAssertEqual(sample.timestamp, 0.1)
        }
        
        engine.stepForward()
        
        XCTAssertEqual(engine.currentSampleIndex, 1)
        XCTAssertEqual(engine.currentTimestamp, 0.1)
        XCTAssertTrue(engine.canStepForward)
        XCTAssertTrue(engine.canStepBackward)
        XCTAssertTrue(callbackReceived)
    }
    
    func test_stepForward_clampsAtLastSample() {
        // Step forward to the end
        engine.stepForward() // 1
        engine.stepForward() // 2
        engine.stepForward() // 3
        engine.stepForward() // 4 (last index)
        
        XCTAssertEqual(engine.currentSampleIndex, 4)
        XCTAssertFalse(engine.canStepForward, "Cannot step forward past the last sample")
        XCTAssertTrue(engine.canStepBackward)
        
        // Attempting another step forward should no-op
        engine.stepForward()
        XCTAssertEqual(engine.currentSampleIndex, 4)
    }
    
    func test_stepBackward_decrementsSampleIndexAndTriggersHook() {
        // Move to index 2
        engine.stepForward()
        engine.stepForward()
        XCTAssertEqual(engine.currentSampleIndex, 2)
        
        var backwardTimestamps: [Double] = []
        engine.onStepBackward = { sample, _ in
            backwardTimestamps.append(sample.timestamp)
        }
        
        // 1. Step backward from index 2 -> 1
        engine.stepBackward()
        XCTAssertEqual(engine.currentSampleIndex, 1)
        XCTAssertEqual(engine.currentTimestamp, 0.1)
        XCTAssertEqual(backwardTimestamps, [0.1])
        
        // 2. Step backward from index 1 -> 0
        engine.stepBackward()
        XCTAssertEqual(engine.currentSampleIndex, 0)
        XCTAssertEqual(engine.currentTimestamp, 0.0)
        XCTAssertEqual(backwardTimestamps, [0.1, 0.0])
        XCTAssertFalse(engine.canStepBackward, "Cannot step backward past index 0")
    }
    
    // MARK: - Reset & Speed Cycling
    
    func test_reset_returnsToBeginningAndTriggersOnReset() {
        engine.stepForward()
        engine.stepForward()
        XCTAssertEqual(engine.currentSampleIndex, 2)
        
        var resetCalled = false
        engine.onReset = {
            resetCalled = true
        }
        
        engine.reset()
        
        XCTAssertEqual(engine.currentSampleIndex, 0)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertTrue(resetCalled)
    }
    
    func test_cycleSpeed_cyclesThroughAvailableSpeeds() {
        // Default: 1.0 (100%)
        XCTAssertEqual(engine.playbackSpeedMultiplier, 1.0)
        
        // Available: [0.25, 0.5, 1.0, 2.0]
        // From 1.0 -> 2.0
        engine.cycleSpeed()
        XCTAssertEqual(engine.playbackSpeedMultiplier, 2.0)
        XCTAssertEqual(engine.speedLabel, "200%")
        
        // From 2.0 -> 0.25
        engine.cycleSpeed()
        XCTAssertEqual(engine.playbackSpeedMultiplier, 0.25)
        XCTAssertEqual(engine.speedLabel, "25%")
        
        // From 0.25 -> 0.5
        engine.cycleSpeed()
        XCTAssertEqual(engine.playbackSpeedMultiplier, 0.5)
        XCTAssertEqual(engine.speedLabel, "50%")
        
        // From 0.5 -> 1.0
        engine.cycleSpeed()
        XCTAssertEqual(engine.playbackSpeedMultiplier, 1.0)
        XCTAssertEqual(engine.speedLabel, "100%")
    }
    
    func test_tickStatusString_formatsProperly() {
        XCTAssertEqual(engine.tickStatusString, "TICK: 0/5 (0.0s)")
        engine.stepForward()
        XCTAssertEqual(engine.tickStatusString, "TICK: 1/5 (0.1s)")
    }
}
