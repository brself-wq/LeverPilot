//
//  ShotRecord+Meticulous.swift
//  VirtualEspressoMachine
//

import Foundation

extension ShotRecord {
    /// Maps an immutable VEM `ShotRecord` and its 10 Hz `ShotSample` series
    /// into the canonical payload structure expected by Meticulous REST endpoints.
    public nonisolated func toMeticulousHistoryEntry() -> MeticulousHistoryEntry {
        let telemetryPoints: [MeticulousDataPoint] = samples.map { sample in
            let elapsedMs = Int((sample.timestamp * 1000.0).rounded())
            
            // brewTemperature and gravimetricFlow are not useful without sensors.
            // Supress them in the JSON output as null values or remove the keys entirely.
            
            let telemetry = MeticulousShotTelemetry(
                pressure: (sample.pressure * 10.0).rounded() / 10.0,
                flow: (sample.flow * 10.0).rounded() / 10.0,
                weight: (sample.weight * 10.0).rounded() / 10.0,
                temperature: nil,
                gravimetricFlow: nil
            )
            
            return MeticulousDataPoint(
                time: elapsedMs,
                status: "extracting",
                shot: telemetry
            )
        }
        
        let profile = MeticulousProfile(
            name: profileName,
            temperature: brewTemperature,
            dbKey: 1
        )
        
        return MeticulousHistoryEntry(
            id: id,
            dbKey: 1,
            time: Int64(timestamp.timeIntervalSince1970),
            name: profileName,
            profile: profile,
            data: telemetryPoints
        )
    }
}
