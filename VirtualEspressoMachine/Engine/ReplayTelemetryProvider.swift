//
//  ReplayTelemetryProvider.swift
//  VirtualEspressoMachine
//

import Foundation
import MeticulousProfile

/// Feeds recorded scenario samples as a standardized MachineFrame stream.
public final class ReplayTelemetryProvider: TelemetryProvider, @unchecked Sendable {
    
    // MARK: - Stream Infrastructure
    private var continuation: AsyncStream<MachineFrame>.Continuation?
    public let frames: AsyncStream<MachineFrame>
    
    // MARK: - Scenario & Transport State
    public private(set) var scenario: ShotRecord?
    public private(set) var currentSampleIndex: Int = 0
    public private(set) var isPlaying: Bool = false
    public var playbackSpeedMultiplier: Double = 1.0
    
    private var playbackTask: Task<Void, Never>?
    
    public init(scenario: ShotRecord? = nil) {
        self.scenario = scenario
        
        var capturedContinuation: AsyncStream<MachineFrame>.Continuation?
        self.frames = AsyncStream { cont in
            capturedContinuation = cont
        }
        self.continuation = capturedContinuation
    }
    
    deinit {
        playbackTask?.cancel()
        continuation?.finish()
    }
    
    // MARK: - TelemetryProvider Protocol Conformance
    
    public func start() {
        play()
    }
    
    public func stop() {
        pause()
    }
    
    // MARK: - Scenario Loading
    
    public func load(scenario: ShotRecord?) {
        stop()
        self.scenario = scenario
        self.currentSampleIndex = 0
    }
    
    // MARK: - Transport Controls
    
    public func play() {
        guard let scenario, !scenario.samples.isEmpty else { return }
        isPlaying = true
        
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { break }
                guard self.currentSampleIndex < scenario.samples.count else {
                    self.stop()
                    break
                }
                
                let sample = scenario.samples[self.currentSampleIndex]
                self.emitFrame(for: sample)
                
                self.currentSampleIndex += 1
                
                let delayMs = UInt64(100.0 / self.playbackSpeedMultiplier)
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }
    
    public func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }
    
    public func stepForward() {
        guard let scenario, currentSampleIndex < scenario.samples.count - 1 else { return }
        if isPlaying { pause() }
        currentSampleIndex += 1
        emitFrame(for: scenario.samples[currentSampleIndex])
    }
    
    public func stepBackward() {
        guard let scenario, currentSampleIndex > 0 else { return }
        if isPlaying { pause() }
        currentSampleIndex -= 1
        emitFrame(for: scenario.samples[currentSampleIndex])
    }
    
    public func reset() {
        stop()
        currentSampleIndex = 0
        if let first = scenario?.samples.first {
            emitFrame(for: first)
        }
    }
    
    // MARK: - Frame Translation
    
    private func emitFrame(for sample: ShotSample) {
        let frame = MachineFrame(
            timestamp: sample.timestamp,
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
