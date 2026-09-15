//
//  ScenarioTelemetryProviderTests.swift
//  VirtualEspressoMachineTests
//

import XCTest
@testable import VirtualEspressoMachine

@MainActor
final class ScenarioTelemetryProviderTests: XCTestCase {
    
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
    }
    
    override func tearDown() {
        mockScenario = nil
        super.tearDown()
    }
    
    // MARK: - Initial State
    
    func test_initialLoadedState() {
        let provider = ScenarioTelemetryProvider(scenario: mockScenario)
        XCTAssertFalse(provider.isStreaming)
        XCTAssertEqual(provider.playbackSpeedMultiplier, 1.0)
        XCTAssertEqual(provider.scenario.id, "test-scenario")
    }
    
    // MARK: - Streaming & Speed Multiplier
    
    func test_start_streamsConsecutiveFramesAtPacedSpeed() async throws {
        // High speed multiplier for near-instant execution
        let provider = ScenarioTelemetryProvider(
            scenario: mockScenario,
            playbackSpeedMultiplier: 100.0,
            syntheticTailDuration: 0.5
        )
        
        var iterator = provider.frames.makeAsyncIterator()
        provider.start()
        XCTAssertTrue(provider.isStreaming)
        
        var receivedTimestamps: [Double] = []
        for _ in 0..<5 {
            if let frame = await iterator.next() {
                receivedTimestamps.append(frame.timestamp)
                XCTAssertEqual(frame[.power], 100.0)
            }
        }
        
        XCTAssertEqual(receivedTimestamps.count, 5)
        XCTAssertEqual(receivedTimestamps[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(receivedTimestamps[1], 0.1, accuracy: 0.001)
        XCTAssertEqual(receivedTimestamps[2], 0.2, accuracy: 0.001)
        XCTAssertEqual(receivedTimestamps[3], 0.3, accuracy: 0.001)
        XCTAssertEqual(receivedTimestamps[4], 0.4, accuracy: 0.001)
        
        provider.stop()
        XCTAssertFalse(provider.isStreaming)
    }
    
    // MARK: - Natural EOF Tail Synthesis
    
    func test_naturalEOFTailSynthesis_emitsZeroFlowRestingFrames() async throws {
        // 5 scenario frames (0.0 ... 0.4s) + 0.3s synthetic tail @ 0.1s step = 3 resting frames
        let provider = ScenarioTelemetryProvider(
            scenario: mockScenario,
            playbackSpeedMultiplier: 100.0,
            syntheticTailDuration: 0.3,
            syntheticFrameInterval: 0.10
        )
        
        var frames: [MachineFrame] = []
        provider.start()
        
        for await frame in provider.frames {
            frames.append(frame)
        }
        
        // 5 scenario samples + 3 resting samples = 8 total frames
        XCTAssertEqual(frames.count, 8)
        
        // Last 3 frames must be zero-flow rest frames holding the final weight (12.0g)
        let tailFrames = frames.suffix(3)
        for tailFrame in tailFrames {
            XCTAssertEqual(try XCTUnwrap(tailFrame[.pressure]), 0.0, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(tailFrame[.flow]), 0.0, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(tailFrame[.weight]), 12.0, accuracy: 0.001)
            XCTAssertGreaterThan(tailFrame.timestamp, 0.4)
        }
        
        XCTAssertFalse(provider.isStreaming)
    }
}
