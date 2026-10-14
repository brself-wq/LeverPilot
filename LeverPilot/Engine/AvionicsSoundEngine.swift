//
//  AvionicsSoundEngine.swift
//  LeverPilot
//

import Foundation
import AVFoundation
import Observation
import os

// MARK: - Thread-Safe Audio Buffer Renderer
private final class AudioState: @unchecked Sendable {
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private var _frequency: Float = 440.0
    private var _volume: Float = 0.0
    private var _isPlaying: Bool = false
    private var phase: Float = 0.0

    init() {
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func setTone(frequency: Float, volume: Float) {
        os_unfair_lock_lock(lock)
        self._frequency = frequency
        self._volume = volume
        self._isPlaying = volume > 0.001
        os_unfair_lock_unlock(lock)
    }

    func stop() {
        os_unfair_lock_lock(lock)
        self._volume = 0.0
        self._isPlaying = false
        os_unfair_lock_unlock(lock)
    }

    func render(frameCount: AVAudioFrameCount, ptr: UnsafeMutablePointer<Float>, sampleRate: Double) {
        os_unfair_lock_lock(lock)
        let freq = self._frequency
        let vol = self._volume
        let active = self._isPlaying
        os_unfair_lock_unlock(lock)

        let phaseIncrement = (2.0 * Float.pi * freq) / Float(sampleRate)

        for frame in 0..<Int(frameCount) {
            if active && vol > 0.0 {
                ptr[frame] = sin(self.phase) * vol
                self.phase += phaseIncrement
                if self.phase >= 2.0 * Float.pi {
                    self.phase -= 2.0 * Float.pi
                }
            } else {
                ptr[frame] = 0.0
            }
        }
    }
}

// MARK: - Swift 6 Avionics Sound Service
@Observable
@MainActor
public final class AvionicsSoundEngine {
    @ObservationIgnored private var audioEngine = AVAudioEngine()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private let state = AudioState()
    private let sampleRate: Double = 44100.0
    
    public init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        let audioState = self.state
        let rate = self.sampleRate

        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = ablPointer.first, let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            audioState.render(frameCount: frameCount, ptr: ptr, sampleRate: rate)
            
            // If output is stereo non-interleaved, duplicate channel 0 to channel 1
            if ablPointer.count > 1, let secondBuffer = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) {
                secondBuffer.assign(from: ptr, count: Int(frameCount))
            }
            
            return noErr
        }

        guard let sourceNode = sourceNode else { return }
        
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        audioEngine.attach(sourceNode)
        audioEngine.connect(sourceNode, to: audioEngine.mainMixerNode, format: monoFormat)
        
        ensureRunning()
    }

    /// Guarantees that the underlying audio engine is awake and rendering.
    public func ensureRunning() {
        guard !audioEngine.isRunning else { return }
        do {
            try audioEngine.start()
            print("🔊 [AvionicsSoundEngine] Audio engine started successfully.")
        } catch {
            print("❌ [AvionicsSoundEngine] Failed to start audio engine: \(error)")
        }
    }

    public func setTone(frequency: Float, volume: Float) {
        ensureRunning()
        state.setTone(frequency: frequency, volume: volume)
    }

    public func playBeep(frequency: Float, duration: Double, volume: Float = 0.25) {
        ensureRunning()
        setTone(frequency: frequency, volume: volume)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self.setTone(frequency: frequency, volume: 0.0)
        }
    }

    public func stop() {
        state.stop()
    }
}
