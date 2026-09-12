//
//  PlaybackEngine.swift
//  VirtualEspressoMachine
//

import Foundation
import Observation
import MeticulousProfile

@Observable
@MainActor
public final class PlaybackEngine {
    // MARK: - Playback State
    public private(set) var isPlaying: Bool = false
    public private(set) var currentSampleIndex: Int = 0
    public private(set) var playbackSpeedMultiplier: Double = 1.0
    
    public private(set) var scenario: ShotRecord? = nil
    
    // MARK: - Configuration
    public let availableSpeeds: [Double] = [0.25, 0.5, 1.0, 2.0]
    
    // MARK: - Event Hooks
    public var onTick: ((_ sample: ShotSample, _ scenario: ShotRecord) -> Void)?
    public var onStepBackward: ((_ sample: ShotSample, _ scenario: ShotRecord) -> Void)?
    public var onReset: (() -> Void)?
    
    // MARK: - Internal Loop
    private var playbackTask: Task<Void, Never>? = nil
    
    public init(scenario: ShotRecord? = nil) {
        self.scenario = scenario
    }
    
    // MARK: - Scenario Management
    
    public func load(scenario: ShotRecord?) {
        stop()
        self.scenario = scenario
        self.currentSampleIndex = 0
        self.onReset?()
    }
    
    // MARK: - Computed Status
    
    public var currentSample: ShotSample? {
        guard let samples = scenario?.samples, samples.indices.contains(currentSampleIndex) else { return nil }
        return samples[currentSampleIndex]
    }
    
    public var totalSamplesCount: Int {
        scenario?.samples.count ?? 0
    }
    
    public var currentTimestamp: Double {
        currentSample?.timestamp ?? (Double(currentSampleIndex) * 0.1)
    }
    
    public var speedLabel: String {
        "\(Int(playbackSpeedMultiplier * 100))%"
    }
    
    public var canStepForward: Bool {
        guard let scenario, !scenario.samples.isEmpty else { return false }
        return !isPlaying && currentSampleIndex < scenario.samples.count - 1
    }
    
    public var canStepBackward: Bool {
        guard let scenario, !scenario.samples.isEmpty else { return false }
        return !isPlaying && currentSampleIndex > 0
    }
    
    public var tickStatusString: String {
        if let scenario {
            return "TICK: \(currentSampleIndex)/\(scenario.samples.count) (\(String(format: "%.1fs", currentTimestamp)))"
        } else {
            return "TICK: --/-- (0.0s)"
        }
    }
    
    // MARK: - Playback Controls
    
    public func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func play() {
        guard let scenario, !scenario.samples.isEmpty else { return }
        isPlaying = true
        
        playbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { break }
                guard self.currentSampleIndex < scenario.samples.count else {
                    self.stop()
                    break
                }
                
                let sample = scenario.samples[self.currentSampleIndex]
                self.onTick?(sample, scenario)
                
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
    
    public func stop() {
        pause()
    }
    
    public func stepForward() {
        guard let scenario, currentSampleIndex < scenario.samples.count - 1 else { return }
        if isPlaying { pause() }
        currentSampleIndex += 1
        let sample = scenario.samples[currentSampleIndex]
        onTick?(sample, scenario)
    }
    
    public func stepBackward() {
        guard let scenario, currentSampleIndex > 0 else { return }
        if isPlaying { pause() }
        currentSampleIndex -= 1
        let sample = scenario.samples[currentSampleIndex]
        onStepBackward?(sample, scenario)
    }
    
    public func reset() {
        stop()
        currentSampleIndex = 0
        onReset?()
    }
    
    public func cycleSpeed() {
        if let idx = availableSpeeds.firstIndex(of: playbackSpeedMultiplier) {
            let next = (idx + 1) % availableSpeeds.count
            playbackSpeedMultiplier = availableSpeeds[next]
        } else {
            playbackSpeedMultiplier = 1.0
        }
    }
}
