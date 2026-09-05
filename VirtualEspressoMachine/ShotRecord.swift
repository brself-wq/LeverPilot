//
//  ShotRecord.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/5/26.
//

import Foundation
import MeticulousProfile

// MARK: - Profile Sanitization Extension

extension Profile {
    /// Produces a lightweight copy of the profile suitable for archiving inside historical shot logs
    public func sanitizedForHistory() -> Profile {
        var copy = self
        if copy.display != nil {
            // Strip heavy image payloads; keep text descriptions and accent colors
            copy.display?.image = nil
        }
        return copy
    }
}

// MARK: - 10 Hz Discrete Telemetry Sample

/// A single 10 Hz sample slice captured during an extraction.
public nonisolated struct ShotSample: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: TimeInterval    // Elapsed shot seconds (0.0, 0.1, 0.2...)
    public let pressure: Double           // Bar (from Bookoo or transducer)
    public let flow: Double               // mL/s or g/s (derived dw/dt or flow sensor)
    public let weight: Double             // Grams in cup (from Bookoo scale)
    
    // Target guidance setpoints active at this exact millisecond
    public let targetPressure: Double?    // Planned pressure setpoint (if in pressure stage)
    public let targetFlow: Double?        // Planned flow setpoint (if in flow stage)
    public let stageIndex: Int            // Active recipe stage index (0, 1, 2...)
    
    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        pressure: Double,
        flow: Double,
        weight: Double,
        targetPressure: Double? = nil,
        targetFlow: Double? = nil,
        stageIndex: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.pressure = pressure
        self.flow = flow
        self.weight = weight
        self.targetPressure = targetPressure
        self.targetFlow = targetFlow
        self.stageIndex = stageIndex
    }
}

// MARK: - The Universal Shot Record

/// The universal, persistent representation of an espresso shot.
/// Functions as:
/// 1. A completed extraction log saved in your local database.
/// 2. A mock testing fixture (when placed in MockScenarios/).
/// 3. The export source for Visualizer.coffee and Beanconqueror.
public nonisolated struct ShotRecord: Sendable, Codable, Identifiable, Equatable {
    // MARK: - Identity & Recipe Link
    public let id: String                 // Unique shot UUID
    public let profileId: String          // Explicit link to MeticulousProfile.Profile.id
    public let profileName: String        // "Chocolate Nutcracker"
    public let timestamp: Date            // Wall-clock time when shot was pulled
    
    // MARK: - Immutable Recipe Snapshot
    public let profileSnapshot: Profile?  // Frozen copy of the exact recipe used (minus heavy artwork)
    
    // MARK: - Core Execution Metrics
    public let duration: TimeInterval     // Total shot time (e.g. 32.4s)
    public let finalWeight: Double        // Total liquid yield in cup (e.g. 40.2g)
    public let doseWeight: Double?        // Dry grounds dose in basket (e.g. 18.0g)
    public let targetWeight: Double       // Recipe goal (e.g. 40.0g)
    public let brewTemperature: Double    // Water temperature (°C)
    
    // MARK: - Barista Notes & Metadata
    public var grinderModel: String?      // e.g. "DF64 Gen 2"
    public var grindSetting: String?      // e.g. "14.5"
    public var beanRoaster: String?       // e.g. "DAK Coffee Roasters"
    public var beanName: String?          // e.g. "Milky Donks"
    public var tastingNotes: String?      // Barista feedback
    public var isAborted: Bool            // True if manually cancelled early
    
    // MARK: - Sub-Second Telemetry Series (10 Hz)
    public let samples: [ShotSample]
    
    public init(
        id: String = UUID().uuidString,
        profileId: String,
        profileName: String,
        profileSnapshot: Profile? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval,
        finalWeight: Double,
        doseWeight: Double? = nil,
        targetWeight: Double,
        brewTemperature: Double = 93.0,
        grinderModel: String? = nil,
        grindSetting: String? = nil,
        beanRoaster: String? = nil,
        beanName: String? = nil,
        tastingNotes: String? = nil,
        isAborted: Bool = false,
        samples: [ShotSample]
    ) {
        self.id = id
        self.profileId = profileId
        self.profileName = profileName
        self.profileSnapshot = profileSnapshot?.sanitizedForHistory()
        self.timestamp = timestamp
        self.duration = duration
        self.finalWeight = finalWeight
        self.doseWeight = doseWeight
        self.targetWeight = targetWeight
        self.brewTemperature = brewTemperature
        self.grinderModel = grinderModel
        self.grindSetting = grindSetting
        self.beanRoaster = beanRoaster
        self.beanName = beanName
        self.tastingNotes = tastingNotes
        self.isAborted = isAborted
        self.samples = samples
    }
}

// MARK: - External Platform Serializers (Visualizer & Beanconqueror)

extension ShotRecord {
    /// Generates the columnar JSON payload format expected by Visualizer.coffee API
    public func toVisualizerPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "clock": samples.map { $0.timestamp },
            "espresso_pressure": samples.map { $0.pressure },
            "espresso_flow": samples.map { $0.flow },
            "espresso_flow_weight": samples.map { $0.flow },
            "espresso_weight": samples.map { $0.weight },
            "profile_title": profileName,
            "target_weight": targetWeight,
            "duration": duration,
            "drink_weight": finalWeight,
            "grinder_model": grinderModel ?? "",
            "grinder_setting": grindSetting ?? "",
            "bean_weight": doseWeight ?? 0.0,
            "espresso_notes": tastingNotes ?? ""
        ]
        
        // Attach target curves if available in the samples
        let targetPressures = samples.compactMap { $0.targetPressure }
        if targetPressures.count == samples.count {
            payload["espresso_pressure_goal"] = targetPressures
        }
        
        let targetFlows = samples.compactMap { $0.targetFlow }
        if targetFlows.count == samples.count {
            payload["espresso_flow_goal"] = targetFlows
        }
        
        return payload
    }
}
