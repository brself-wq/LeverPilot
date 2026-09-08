//
//  ScenarioStore.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/5/26.
//

import Foundation
import Observation

/// Manages and loads mock extraction scenarios (ShotRecord fixtures) used for simulation and unit testing.
@Observable
@MainActor
public final class ScenarioStore {
    
    /// All available test scenarios loaded from disk or bundle
    public var scenarios: [ShotRecord] = []
    
    public init(bundle: Bundle = .main) {
        loadBundledScenarios(from: bundle)
    }
    
    /// Retrieve all scenarios linked to a specific Meticulous profile ID
    public func scenarios(for profileId: String) -> [ShotRecord] {
        scenarios.filter { $0.profileId == profileId }
    }
    
    // MARK: - Bundle Loading & Keyframe Expansion
    
    public func loadBundledScenarios(from bundle: Bundle = .main) {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return
        }
        
        var loaded: [ShotRecord] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let rawRecord = try? decoder.decode(ShotRecord.self, from: data) {
                
                // Automatically expand sparse hand-authored keyframes into smooth 10 Hz ticks!
                let continuousSamples = Self.expandKeyframesTo10Hz(samples: rawRecord.samples)
                
                let record = ShotRecord(
                    id: rawRecord.id,
                    profileId: rawRecord.profileId,
                    profileName: rawRecord.profileName,
                    profileSnapshot: rawRecord.profileSnapshot,
                    timestamp: rawRecord.timestamp,
                    duration: rawRecord.duration,
                    finalWeight: rawRecord.finalWeight,
                    doseWeight: rawRecord.doseWeight,
                    targetWeight: rawRecord.targetWeight,
                    brewTemperature: rawRecord.brewTemperature,
                    grinderModel: rawRecord.grinderModel,
                    grindSetting: rawRecord.grindSetting,
                    beanRoaster: rawRecord.beanRoaster,
                    beanName: rawRecord.beanName,
                    tastingNotes: rawRecord.tastingNotes,
                    isAborted: rawRecord.isAborted,
                    samples: continuousSamples
                )
                loaded.append(record)
            }
        }
        
        if !loaded.isEmpty {
            self.scenarios = loaded.sorted { ($0.tastingNotes ?? $0.id) < ($1.tastingNotes ?? $1.id) }
        }
    }
    
    // MARK: - Keyframe Interpolator (Fixed Math)
    
    /// Takes sparse hand-authored samples (e.g. points at 0s, 5s, 11s) and fills in
    /// smooth linear 10 Hz (100ms) ticks so hand-authored JSON files can be ultra-compact.
    public static func expandKeyframesTo10Hz(samples: [ShotSample]) -> [ShotSample] {
        guard samples.count > 1 else { return samples }
        var continuous: [ShotSample] = []
        
        for i in 0..<(samples.count - 1) {
            let s0 = samples[i]
            let s1 = samples[i + 1]
            let dt = s1.timestamp - s0.timestamp
            
            // If already at 10 Hz cadence (dt <= 0.15s), keep as is
            if dt <= 0.15 {
                continuous.append(s0)
            } else {
                // Interpolate 100ms ticks between s0 and s1
                let steps = max(1, Int((dt / 0.1).rounded()))
                for step in 0..<steps {
                    let progress = Double(step) / Double(steps)
                    
                    // Fixed: Clean elapsed calculation with proper rounding
                    let rawTime = s0.timestamp + (progress * dt)
                    let t = (rawTime * 10).rounded() / 10
                    
                    let p = s0.pressure + progress * (s1.pressure - s0.pressure)
                    let f = s0.flow + progress * (s1.flow - s0.flow)
                    let w = s0.weight + progress * (s1.weight - s0.weight)
                    
                    continuous.append(ShotSample(
                        timestamp: t,
                        pressure: p,
                        flow: f,
                        weight: w,
                        targetPressure: s0.targetPressure,
                        targetFlow: s0.targetFlow,
                        stageIndex: s0.stageIndex
                    ))
                }
            }
        }
        
        if let last = samples.last {
            continuous.append(last)
        }
        
        return continuous
    }
}
