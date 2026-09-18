//
//  ShotSample.swift
//  VirtualEspressoMachine
//

import Foundation
import MeticulousProfile

// MARK: - Profile Sanitization Extension (Nonisolated)

extension Profile {
    /// Produces a lightweight copy of the profile suitable for archiving inside historical shot logs
    public nonisolated func sanitizedForHistory() -> Profile {
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
    
    // Custom Decodable: Makes `id` completely optional in JSON files!
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp, time
        case pressure
        case flow
        case weight
        case targetPressure = "target_pressure"
        case altTargetPressure = "targetPressure"
        case targetFlow = "target_flow"
        case altTargetFlow = "targetFlow"
        case stageIndex = "stage_index"
        case altStageIndex = "stageIndex"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Auto-generate UUID if omitted from JSON
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        
        // Supports "timestamp" or "time"
        if let t = try? container.decode(Double.self, forKey: .timestamp) {
            self.timestamp = t
        } else {
            self.timestamp = (try? container.decode(Double.self, forKey: .time)) ?? 0.0
        }
        
        self.pressure = (try? container.decode(Double.self, forKey: .pressure)) ?? 0.0
        self.flow = (try? container.decode(Double.self, forKey: .flow)) ?? 0.0
        self.weight = (try? container.decode(Double.self, forKey: .weight)) ?? 0.0
        
        self.targetPressure = (try? container.decode(Double.self, forKey: .targetPressure))
            ?? (try? container.decode(Double.self, forKey: .altTargetPressure))
            
        self.targetFlow = (try? container.decode(Double.self, forKey: .targetFlow))
            ?? (try? container.decode(Double.self, forKey: .altTargetFlow))
            
        self.stageIndex = (try? container.decode(Int.self, forKey: .stageIndex))
            ?? (try? container.decode(Int.self, forKey: .altStageIndex))
            ?? 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(pressure, forKey: .pressure)
        try container.encode(flow, forKey: .flow)
        try container.encode(weight, forKey: .weight)
        try container.encodeIfPresent(targetPressure, forKey: .targetPressure)
        try container.encodeIfPresent(targetFlow, forKey: .targetFlow)
        try container.encode(stageIndex, forKey: .stageIndex)
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
    public let id: String                 // Unique shot or scenario ID
    public let profileId: String          // Explicit link to MeticulousProfile.Profile.id
    public let profileName: String        // Cached recipe name
    public let timestamp: Date            // Wall-clock time when shot was pulled
    
    // MARK: - Immutable Recipe Snapshot
    public let profileSnapshot: Profile?  // Frozen copy of the exact recipe used (minus heavy artwork)
    
    // MARK: - Core Execution Metrics
    public let duration: TimeInterval     // Total shot time (e.g. 32.4s)
    public let finalWeight: Double        // Total liquid yield in cup (e.g. 40.2g)
    public let doseWeight: Double?        // Dry grounds dose in basket (e.g. 18.0g)
    public let targetWeight: Double       // Recipe goal (e.g. 40.0g)
    public let brewTemperature: Double    // Water temperature (°C)
    
    // MARK: - Metadata
    public var isAborted: Bool            // True if manually cancelled early
    
    // MARK: - Sub-Second Telemetry Series (10 Hz)
    public let samples: [ShotSample]
    
    public init(
        id: String = UUID().uuidString,
        profileId: String,
        profileName: String = "",
        profileSnapshot: Profile? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval? = nil,
        finalWeight: Double? = nil,
        doseWeight: Double? = nil,
        targetWeight: Double = 40.0,
        brewTemperature: Double = 93.0,
        isAborted: Bool = false,
        samples: [ShotSample]
    ) {
        self.id = id
        self.profileId = profileId
        self.profileName = profileName
        self.profileSnapshot = profileSnapshot?.sanitizedForHistory()
        self.timestamp = timestamp
        self.samples = samples
        
        // Auto-compute duration and finalWeight from samples if not explicitly passed
        self.duration = duration ?? (samples.last?.timestamp ?? 0.0)
        self.finalWeight = finalWeight ?? (samples.last?.weight ?? targetWeight)
        
        self.doseWeight = doseWeight
        self.targetWeight = targetWeight
        self.brewTemperature = brewTemperature
        self.isAborted = isAborted
    }
    
    // MARK: - Forgiving Decodable for Lean Hand-Authoring
    
    enum CodingKeys: String, CodingKey {
        case id
        case profileId = "profile_id"
        case altProfileId = "profileId"
        case profileName = "profile_name"
        case altProfileName = "profileName"
        case profileSnapshot = "profile_snapshot"
        case altProfileSnapshot = "profileSnapshot"
        case timestamp, date
        case duration
        case finalWeight = "final_weight"
        case altFinalWeight = "finalWeight"
        case doseWeight = "dose_weight"
        case altDoseWeight = "doseWeight"
        case targetWeight = "target_weight"
        case altTargetWeight = "targetWeight"
        case brewTemperature = "brew_temperature"
        case altBrewTemperature = "brewTemperature"
        case grinderModel = "grinder_model"
        case altGrinderModel = "grinderModel"
        case grindSetting = "grind_setting"
        case altGrindSetting = "grindSetting"
        case beanRoaster = "bean_roaster"
        case altBeanRoaster = "beanRoaster"
        case beanName = "bean_name"
        case altBeanName = "beanName"
        case tastingNotes = "tasting_notes"
        case altTastingNotes = "tastingNotes"
        case notes
        case isAborted = "is_aborted"
        case altIsAborted = "isAborted"
        case samples
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        
        // profileId is the single required anchor
        if let pId = try? container.decode(String.self, forKey: .profileId) {
            self.profileId = pId
        } else {
            self.profileId = try container.decode(String.self, forKey: .altProfileId)
        }
        
        self.profileName = (try? container.decode(String.self, forKey: .profileName))
            ?? (try? container.decode(String.self, forKey: .altProfileName))
            ?? ""
            
        self.profileSnapshot = ((try? container.decode(Profile.self, forKey: .profileSnapshot))
            ?? (try? container.decode(Profile.self, forKey: .altProfileSnapshot)))?.sanitizedForHistory()
            
        self.timestamp = (try? container.decode(Date.self, forKey: .timestamp))
            ?? (try? container.decode(Date.self, forKey: .date))
            ?? Date()
            
        let decodedSamples = (try? container.decode([ShotSample].self, forKey: .samples)) ?? []
        self.samples = decodedSamples
        
        // Auto-derive metrics from samples if omitted in hand-authored JSON
        let lastSampleTime = decodedSamples.last?.timestamp ?? 0.0
        let lastSampleWeight = decodedSamples.last?.weight ?? 0.0
        
        self.duration = (try? container.decode(Double.self, forKey: .duration)) ?? lastSampleTime
        
        self.finalWeight = (try? container.decode(Double.self, forKey: .finalWeight))
            ?? (try? container.decode(Double.self, forKey: .altFinalWeight))
            ?? lastSampleWeight
            
        self.doseWeight = (try? container.decode(Double.self, forKey: .doseWeight))
            ?? (try? container.decode(Double.self, forKey: .altDoseWeight))
            
        self.targetWeight = (try? container.decode(Double.self, forKey: .targetWeight))
            ?? (try? container.decode(Double.self, forKey: .altTargetWeight))
            ?? self.finalWeight
            
        self.brewTemperature = (try? container.decode(Double.self, forKey: .brewTemperature))
            ?? (try? container.decode(Double.self, forKey: .altBrewTemperature))
            ?? 93.0
            
        self.isAborted = (try? container.decode(Bool.self, forKey: .isAborted))
            ?? (try? container.decode(Bool.self, forKey: .altIsAborted))
            ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(profileId, forKey: .profileId)
        try container.encode(profileName, forKey: .profileName)
        try container.encodeIfPresent(profileSnapshot, forKey: .profileSnapshot)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(duration, forKey: .duration)
        try container.encode(finalWeight, forKey: .finalWeight)
        try container.encodeIfPresent(doseWeight, forKey: .doseWeight)
        try container.encode(targetWeight, forKey: .targetWeight)
        try container.encode(brewTemperature, forKey: .brewTemperature)
        try container.encode(isAborted, forKey: .isAborted)
        try container.encode(samples, forKey: .samples)
    }
}
