//
//  MockVirtualEspressoMachine.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/2/26.
//

import Foundation
import Observation
import MeticulousProfile

@Observable
@MainActor
public final class MockVirtualEspressoMachine: MachineProtocol {
    
    public var state: MachineState = .ready
    public var currentFrame: MachineFrame = MachineFrame(state: .ready)
    public var sessionFrames: [MachineFrame] = []
    
    // Subsystems & Config owned by this machine
    public let profileStore: ProfileStore
    public var activeProfile: Profile? = nil
    public var config: MachineConfig = .flair58Default
    
    public let mockSensors = MockSensorArray()
    public var sensors: any SensorArrayProtocol { mockSensors }
    
    private var extractionTask: Task<Void, Never>?
    private var elapsed: TimeInterval = 0.0
    
    // MARK: - Initializers
    
    public init() {
        self.profileStore = ProfileStore()
        if let initial = profileStore.profiles.first {
            selectProfile(initial)
        }
    }
    
    public init(profileStore: ProfileStore, config: MachineConfig = .flair58Default) {
        self.profileStore = profileStore
        self.config = config
        if let initial = profileStore.profiles.first {
            selectProfile(initial)
        }
    }
    
    // MARK: - MachineProtocol Transitions
    
    public func setToMachineReady() {
        state = .ready
        elapsed = 0.0
        sessionFrames.removeAll()
        currentFrame = MachineFrame(state: .ready)
    }
    
    public func selectProfile(_ profile: Profile) {
        do {
            let resolved = try profileStore.resolveForExecution(profile)
            self.activeProfile = resolved
            self.state = .profileSelected
        } catch {
            print("[VEM] Error selecting profile: \(error)")
        }
    }
    
    public func setToShotReady() {
        state = .shotReady
    }
    
    public func startExtraction() {
        guard state == .shotReady else { return }
        state = .extracting
        elapsed = 0.0
        sessionFrames.removeAll()
        
        extractionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    break
                }
                
                guard let self = self, !Task.isCancelled else { break }
                
                self.elapsed += 0.1
                
                // Simulated ramp & flow curve
                let simPressure = min(8.5, self.elapsed * 1.8)
                let simFlow = self.elapsed > 4.0 ? 2.0 : 0.0
                let simWeight = max(0.0, (self.elapsed - 4.0) * 2.0)
                
                self.mockSensors.setReading(simPressure, for: .pressure)
                self.mockSensors.setReading(simWeight, for: .weight)
                self.mockSensors.setReading(simFlow, for: .flow)
                
                let frame = self.mockSensors.captureSnapshot(at: self.elapsed, state: .extracting)
                self.currentFrame = frame
                self.sessionFrames.append(frame)
                
                // Check cutoff against profile final weight
                let targetWeight = self.activeProfile?.finalWeight ?? 45.0
                if simWeight >= targetWeight {
                    self.endExtraction()
                    break
                }
            }
        }
    }
    
    public func endExtraction() {
        extractionTask?.cancel()
        extractionTask = nil
        state = .shotEnded
        currentFrame = mockSensors.captureSnapshot(at: elapsed, state: .shotEnded)
    }
    
    public func setToCleanupComplete() {
        setToMachineReady()
    }
    
    public func abort() {
        endExtraction()
        setToMachineReady()
    }
}
