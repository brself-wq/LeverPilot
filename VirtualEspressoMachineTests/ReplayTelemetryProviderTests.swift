//
//  ReplayTelemetryProviderTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
@testable import VirtualEspressoMachine

@MainActor
final class ReplayTelemetryProviderTests: XCTestCase {
    
    private var provider: ReplayTelemetryProvider!
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
        
        provider = ReplayTelemetryProvider(scenario: mockScenario)
    }
    
    override func tearDown() {
        provider.stop()
        provider = nil
        mockScenario = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func test_initialLoadedState() {
        XCTAssertFalse(provider.isPlaying)
        XCTAssertEqual(provider.currentSampleIndex, 0)
        XCTAssertEqual(provider.playbackSpeedMultiplier, 1.0)
        XCTAssertNotNil(provider.scenario)
    }
    
    // MARK: - Step Forward & Sensor Mapping
    
    func test_stepForward_emitsMachineFrameWithMappedSensors() async throws {
        var iterator = provider.frames.makeAsyncIterator()
        
        // Step to index 1 (timestamp 0.1s)
        provider.stepForward()
        
        let nextFrame = await iterator.next()
        let frame = try XCTUnwrap(nextFrame, "Expected a frame from stream after stepForward()")
        
        XCTAssertEqual(provider.currentSampleIndex, 1)
        XCTAssertEqual(frame.timestamp, 0.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame[.pressure]), 1.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame[.flow]), 2.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame[.weight]), 3.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame[.power]), 100.0, accuracy: 0.001)
    }
    
    func test_stepForward_clampsAtLastSample() {
        // Step through to the end
        provider.stepForward() // 1
        provider.stepForward() // 2
        provider.stepForward() // 3
        provider.stepForward() // 4 (last)
        
        XCTAssertEqual(provider.currentSampleIndex, 4)
        
        // Further steps must clamp at 4
        provider.stepForward()
        XCTAssertEqual(provider.currentSampleIndex, 4)
    }
    
    // MARK: - Step Backward
    
    func test_stepBackward_decrementsIndexAndEmitsPreviousSample() async throws {
        var iterator = provider.frames.makeAsyncIterator()
        
        provider.stepForward() // to 1
        _ = await iterator.next()
        
        provider.stepForward() // to 2
        _ = await iterator.next()
        XCTAssertEqual(provider.currentSampleIndex, 2)
        
        // Step back to 1
        provider.stepBackward()
        let nextFrame = await iterator.next()
        let frame = try XCTUnwrap(nextFrame, "Expected frame after stepBackward()")
        
        XCTAssertEqual(provider.currentSampleIndex, 1)
        XCTAssertEqual(frame.timestamp, 0.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame[.pressure]), 1.5, accuracy: 0.001)
    }
    
    // MARK: - Reset
    
    func test_reset_rewindsToZeroAndEmitsInitialFrame() async throws {
        var iterator = provider.frames.makeAsyncIterator()
        
        provider.stepForward() // 1
        _ = await iterator.next()
        provider.stepForward() // 2
        _ = await iterator.next()
        XCTAssertEqual(provider.currentSampleIndex, 2)
        
        provider.reset()
        
        let initialFrame = await iterator.next()
        let resetFrame = try XCTUnwrap(initialFrame, "Expected initial frame after reset()")
        
        XCTAssertEqual(provider.currentSampleIndex, 0)
        XCTAssertFalse(provider.isPlaying)
        XCTAssertEqual(resetFrame.timestamp, 0.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(resetFrame[.pressure]), 0.0, accuracy: 0.001)
    }
    
    // MARK: - Async Play Streaming
    
    func test_play_streamsConsecutiveFrames() async throws {
        var iterator = provider.frames.makeAsyncIterator()
        
        // Run at 100x speed so test executes instantly (1ms per tick)
        provider.playbackSpeedMultiplier = 100.0
        provider.play()
        
        XCTAssertTrue(provider.isPlaying)
        
        // Ingest first 3 streamed frames
        var receivedTimestamps: [Double] = []
        for _ in 0..<3 {
            if let frame = await iterator.next() {
                receivedTimestamps.append(frame.timestamp)
            }
        }
        
        provider.stop()
        XCTAssertFalse(provider.isPlaying)
        
        XCTAssertEqual(receivedTimestamps.count, 3)
        XCTAssertEqual(receivedTimestamps[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(receivedTimestamps[1], 0.1, accuracy: 0.001)
        XCTAssertEqual(receivedTimestamps[2], 0.2, accuracy: 0.001)
    }
}
