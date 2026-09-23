//
//  ScenarioTelemetryProvider.swift
//  LeverPilot
//

import Foundation
import MeticulousProfile

/// Feeds recorded scenario samples as a standardized TelemetryProvider stream.
/// Automatically synthesizes a resting dead-flow tail upon EOF so the coordinator's
/// physical watchdog cleanly triggers extraction termination and retroactive trimming.
public final class ScenarioTelemetryProvider: TelemetryProvider, @unchecked Sendable {
    
    // MARK: - Stream Infrastructure
    private var continuation: AsyncStream<MachineFrame>.Continuation?
    public let frames: AsyncStream<MachineFrame>
    
    // MARK: - Scenario & Streaming State
    public let scenario: ShotRecord
    public private(set) var isStreaming: Bool = false
    public var playbackSpeedMultiplier: Double = 1.0
    
    // Watchdog trigger configuration
    public let syntheticTailDuration: TimeInterval
    public let syntheticFrameInterval: TimeInterval
    
    private var streamingTask: Task<Void, Never>?
    
    public init(
        scenario: ShotRecord,
        playbackSpeedMultiplier: Double = 1.0,
        syntheticTailDuration: TimeInterval = 2.5,
        syntheticFrameInterval: TimeInterval = 0.10 // 10 Hz
    ) {
        self.scenario = scenario
        self.playbackSpeedMultiplier = playbackSpeedMultiplier
        self.syntheticTailDuration = syntheticTailDuration
        self.syntheticFrameInterval = syntheticFrameInterval
        
        var capturedContinuation: AsyncStream<MachineFrame>.Continuation?
        self.frames = AsyncStream { cont in
            capturedContinuation = cont
        }
        self.continuation = capturedContinuation
    }
    
    deinit {
        stop()
        continuation?.finish()
    }
    
    // MARK: - TelemetryProvider Protocol Conformance
    
    public func start() {
        guard !isStreaming, !scenario.samples.isEmpty else { return }
        isStreaming = true
        
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            guard let self else { return }
            
            var lastSample: ShotSample?
            
            // 1. Stream actual scenario samples
            for sample in self.scenario.samples {
                guard !Task.isCancelled, self.isStreaming else { break }
                
                self.emitFrame(for: sample)
                lastSample = sample
                
                let delayMs = UInt64((self.syntheticFrameInterval / self.playbackSpeedMultiplier) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayMs)
            }
            
            // 2. Natural EOF Tail Synthesis
            // If scenario finishes while in-flight, synthesize resting frames (0.0 bar, 0.0 mL/s, lastWeight)
            // so the ShotCoordinator's 2.0s sustained dead-flow watchdog trips naturally.
            if !Task.isCancelled, self.isStreaming, let tailBase = lastSample {
                let tailFramesCount = max(1, Int((self.syntheticTailDuration / self.syntheticFrameInterval).rounded()))
                
                for step in 1...tailFramesCount {
                    guard !Task.isCancelled, self.isStreaming else { break }
                    
                    let currentTimestamp = tailBase.timestamp + (Double(step) * self.syntheticFrameInterval)
                    
                    let syntheticFrame = MachineFrame(
                        timestamp: currentTimestamp,
                        absoluteTime: Date(),
                        state: .extracting,
                        readings: [
                            .pressure: 0.0,
                            .flow: 0.0,
                            .weight: tailBase.weight,
                            .time: currentTimestamp,
                            .power: 100.0
                        ]
                    )
                    self.continuation?.yield(syntheticFrame)
                    
                    let delayMs = UInt64((self.syntheticFrameInterval / self.playbackSpeedMultiplier) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delayMs)
                }
            }
            
            self.stop()
        }
    }
    
    public func stop() {
        isStreaming = false
        streamingTask?.cancel()
        streamingTask = nil
        continuation?.finish()
    }
    
    // MARK: - Frame Translation
    
    private func emitFrame(for sample: ShotSample) {
        let frame = MachineFrame(
            timestamp: sample.timestamp,
            absoluteTime: Date(),
            state: .extracting,
            readings: [
                .pressure: sample.pressure,
                .flow: sample.flow,
                .weight: sample.weight,
                .time: sample.timestamp,
                .power: 100.0
            ]
        )
        continuation?.yield(frame)
    }
}
