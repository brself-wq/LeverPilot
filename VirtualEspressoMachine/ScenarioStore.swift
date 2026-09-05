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
        
        // Zero-setup fallback: Inject a built-in Golden Pull scenario for Chocolate Nutcracker
        if scenarios.isEmpty {
            self.scenarios = [createNutcrackerGoldenPull()]
        }
    }
    
    /// Retrieve all scenarios linked to a specific Meticulous profile ID
    public func scenarios(for profileId: String) -> [ShotRecord] {
        scenarios.filter { $0.profileId == profileId }
    }
    
    // MARK: - Bundle Loading
    
    public func loadBundledScenarios(from bundle: Bundle = .main) {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return
        }
        
        var loaded: [ShotRecord] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for url in urls {
            // Only load files containing valid ShotRecord schemas
            if let data = try? Data(contentsOf: url),
               let record = try? decoder.decode(ShotRecord.self, from: data) {
                loaded.append(record)
            }
        }
        
        if !loaded.isEmpty {
            self.scenarios = loaded
        }
    }
    
    // MARK: - Built-in Golden Pull Fixture for Chocolate Nutcracker
    
    /// Generates a realistic 10 Hz "Golden Pull" matching the 3 stages of Chocolate Nutcracker:
    /// - Stage 0 (Pre-soak, 5s): 2.0 bar hold, 0g weight
    /// - Stage 1 (Bloom, 6s): 1.0 -> 1.5 mL/s flow, pressure ~2-3 bar, weight reaches ~4g
    /// - Stage 2 (Extraction): Ramps to 6.1 bar, flow ~2.0 mL/s, runs smoothly until 40.0g cutoff at ~31s!
    public func createNutcrackerGoldenPull() -> ShotRecord {
        var samples: [ShotSample] = []
        
        var currentTime: TimeInterval = 0.0
        var currentWeight: Double = 0.0
        var currentPressure: Double = 0.0
        var currentFlow: Double = 0.0
        
        // 1. Stage 0: Pre-Soak (0.0s to 5.0s) — Hold 2.0 bar, 0g weight
        while currentTime < 5.0 {
            currentPressure = min(2.0, currentTime * 1.5) // ramp to 2 bar
            currentFlow = 0.0
            currentWeight = 0.0
            
            samples.append(ShotSample(
                timestamp: (currentTime * 10).rounded() / 10,
                pressure: currentPressure,
                flow: currentFlow,
                weight: currentWeight,
                targetPressure: 2.0,
                stageIndex: 0
            ))
            currentTime += 0.1
        }
        
        // 2. Stage 1: Bloom (5.0s to 11.0s) — Flow ramp 1.0 -> 1.5, first drips hit cup (~4g)
        while currentTime < 11.0 {
            let stageElapsed = currentTime - 5.0
            currentPressure = 2.0 + (stageElapsed * 0.1) // gentle resistance rise
            currentFlow = 1.0 + (stageElapsed / 6.0) * 0.5 // 1.0 -> 1.5 mL/s
            currentWeight += currentFlow * 0.1 // integrate flow into cup weight
            
            samples.append(ShotSample(
                timestamp: (currentTime * 10).rounded() / 10,
                pressure: currentPressure,
                flow: currentFlow,
                weight: currentWeight,
                targetFlow: currentFlow,
                stageIndex: 1
            ))
            currentTime += 0.1
        }
        
        // 3. Stage 2: Extraction (11.0s until 40.0g) — Ramp to 6.1 bar, steady flow ~2.0 mL/s
        while currentWeight < 40.0 {
            let stageElapsed = currentTime - 11.0
            // Ramp to 6.1 bar over 5s, then hold flat
            if stageElapsed < 5.1 {
                currentPressure = 2.5 + (stageElapsed / 5.1) * 3.6
            } else {
                currentPressure = 6.1
            }
            
            currentFlow = 2.0
            currentWeight += currentFlow * 0.1
            
            samples.append(ShotSample(
                timestamp: (currentTime * 10).rounded() / 10,
                pressure: currentPressure,
                flow: currentFlow,
                weight: min(40.0, currentWeight),
                targetPressure: currentPressure,
                stageIndex: 2
            ))
            currentTime += 0.1
        }
        
        return ShotRecord(
            id: "scenario-nutcracker-golden",
            profileId: "1ec13e5a-e549-4f31-a47a-5acbdce2c4cc", // Matches Chocolate Nutcracker ID
            profileName: "Chocolate Nutcracker",
            timestamp: Date(),
            duration: (currentTime * 10).rounded() / 10,
            finalWeight: (currentWeight * 10).rounded() / 10,
            doseWeight: 18.0,
            targetWeight: 40.0,
            brewTemperature: 93.0,
            grinderModel: "DF64 Gen 2",
            grindSetting: "15.0",
            beanRoaster: "WJB3",
            beanName: "Nutcracker Blend",
            tastingNotes: "Ideal simulated extraction; clean 3-stage progression.",
            isAborted: false,
            samples: samples
        )
    }
}
