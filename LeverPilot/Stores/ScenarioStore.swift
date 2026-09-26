//
//  ScenarioStore.swift
//  LeverPilot
//

import Foundation
import Observation

// MARK: - Ergonomic Domain Alias
public typealias ShotRecordStore = ScenarioStore

@Observable
@MainActor
public final class ScenarioStore {
    public enum StorageMode: Sendable {
        case disk(directory: URL? = nil)
        case inMemory
    }
    
    /// Real historical shot logs recorded from completed pulls.
    public var scenarios: [ShotRecord] = []
    
    /// Bundled mock test fixtures reserved exclusively for simulator / desk debugging.
    /// In RELEASE builds, this is guaranteed to remain empty.
    public var mockScenarios: [ShotRecord] = []
    
    private let mode: StorageMode
    private let fileManager = FileManager.default
    private let shotLogsDirectory: URL?
    
    public init(mode: StorageMode = .disk(), bundle: Bundle = .main) {
        self.mode = mode
        
        switch mode {
        case .disk(let customURL):
            if let customURL {
                self.shotLogsDirectory = customURL
            } else {
                guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    fatalError("CRITICAL: Documents directory is unavailable.")
                }
                let targetDir = docs.appendingPathComponent("ShotLogs", isDirectory: true)
                
                // One-time silent migration from Application Support -> Documents/ShotLogs
                if let legacyAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let oldDir = legacyAppSupport.appendingPathComponent("ShotLogs", isDirectory: true)
                    if fileManager.fileExists(atPath: oldDir.path()) && !fileManager.fileExists(atPath: targetDir.path()) {
                        try? fileManager.moveItem(at: oldDir, to: targetDir)
                    }
                }
                
                self.shotLogsDirectory = targetDir
            }
            ensureDirectoryExists()
            loadAllScenarios(bundle: bundle)
            
        case .inMemory:
            self.shotLogsDirectory = nil
            loadBundledOnly(bundle: bundle)
        }
    }
    
    public func recordCompletedShot(_ shot: ShotRecord) throws {
        scenarios.insert(shot, at: 0)
        
        guard case .disk = mode, let dir = shotLogsDirectory else { return }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
        let dateString = formatter.string(from: shot.timestamp).replacingOccurrences(of: ":", with: "-")
        let filename = "shot_\(dateString)_\(shot.id.prefix(8)).json"
        let fileURL = dir.appendingPathComponent(filename)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(shot)
        try data.write(to: fileURL, options: .atomic)
    }
    
    public func clearAllHistory() throws {
        scenarios.removeAll()
        guard case .disk = mode, let dir = shotLogsDirectory else { return }
        if fileManager.fileExists(atPath: dir.path()) {
            try fileManager.removeItem(at: dir)
            ensureDirectoryExists()
        }
    }
    
    public func deleteShot(withID id: String) throws {
        scenarios.removeAll(where: { $0.id == id })
        guard case .disk = mode, let dir = shotLogsDirectory else { return }
        if let fileURLs = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in fileURLs where url.lastPathComponent.contains(id.prefix(8)) {
                try fileManager.removeItem(at: url)
            }
        }
    }
    
    public func loadAllScenarios(bundle: Bundle = .main) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // 1. Bundle Scenarios (Isolated for DEBUG simulation only)
        #if DEBUG
        var bundled: [ShotRecord] = []
        if let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            for url in urls {
                if let data = try? Data(contentsOf: url),
                   let raw = try? decoder.decode(ShotRecord.self, from: data) {
                    let continuous = Self.expandKeyframesTo10Hz(samples: raw.samples)
                    bundled.append(raw.updatingSamples(continuous))
                }
            }
        }
        self.mockScenarios = bundled
        #else
        // Guaranteed zero mock scenarios in production RELEASE builds
        self.mockScenarios = []
        #endif
        
        // 2. Real User Shot Logs from Application Support (Sole source of truth for History)
        var recorded: [ShotRecord] = []
        if case .disk = mode, let dir = shotLogsDirectory,
           let logURLs = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in logURLs where url.pathExtension.lowercased() == "json" {
                if let data = try? Data(contentsOf: url),
                   let raw = try? decoder.decode(ShotRecord.self, from: data) {
                    recorded.append(raw)
                }
            }
        }
        
        self.scenarios = recorded.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func loadBundledOnly(bundle: Bundle) {
        loadAllScenarios(bundle: bundle)
    }
    
    private func ensureDirectoryExists() {
        guard let dir = shotLogsDirectory else { return }
        if !fileManager.fileExists(atPath: dir.path()) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    public static func expandKeyframesTo10Hz(samples: [ShotSample]) -> [ShotSample] {
        guard samples.count > 1 else { return samples }
        var continuous: [ShotSample] = []
        for i in 0..<(samples.count - 1) {
            let s0 = samples[i]
            let s1 = samples[i + 1]
            let dt = s1.timestamp - s0.timestamp
            if dt <= 0.15 {
                continuous.append(s0)
            } else {
                let steps = max(1, Int((dt / 0.1).rounded()))
                for step in 0..<steps {
                    let progress = Double(step) / Double(steps)
                    let rawTime = s0.timestamp + (progress * dt)
                    let t = (rawTime * 10).rounded() / 10
                    let p = s0.pressure + progress * (s1.pressure - s0.pressure)
                    let f = s0.flow + progress * (s1.flow - s0.flow)
                    let w = s0.weight + progress * (s1.weight - s0.weight)
                    continuous.append(ShotSample(timestamp: t, pressure: p, flow: f, weight: w, targetPressure: s0.targetPressure, targetFlow: s0.targetFlow, stageIndex: s0.stageIndex))
                }
            }
        }
        if let last = samples.last { continuous.append(last) }
        return continuous
    }
}

private extension ShotRecord {
    func updatingSamples(_ newSamples: [ShotSample]) -> ShotRecord {
        ShotRecord(id: self.id, profileId: self.profileId, profileName: self.profileName, profileSnapshot: self.profileSnapshot, timestamp: self.timestamp, duration: self.duration, finalWeight: self.finalWeight, doseWeight: self.doseWeight, targetWeight: self.targetWeight, brewTemperature: self.brewTemperature, isAborted: self.isAborted, samples: newSamples)
    }
}
