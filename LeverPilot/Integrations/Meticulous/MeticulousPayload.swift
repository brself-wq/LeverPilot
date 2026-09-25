//
//  MeticulousPayload.swift
//  LeverPilot
//

import Foundation

// MARK: - History Response Envelope
public nonisolated struct MeticulousHistoryResponse: Codable, Sendable {
    public let history: [MeticulousHistoryEntry]

    public init(history: [MeticulousHistoryEntry]) {
        self.history = history
    }
}

// MARK: - History Entry
public nonisolated struct MeticulousHistoryEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let dbKey: Int?
    public let time: Int64
    public let file: String?
    public let name: String
    public let profile: MeticulousProfile
    public let data: [MeticulousDataPoint]?

    public init(
        id: String,
        dbKey: Int? = 1,
        time: Int64,
        name: String,
        profile: MeticulousProfile,
        data: [MeticulousDataPoint]? = nil
    ) {
        self.id = id
        self.dbKey = dbKey
        self.time = time
        self.file = nil
        self.name = name
        self.profile = profile
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case id
        case dbKey = "db_key"
        case time
        case file
        case name
        case profile
        case data
    }

    /// Returns a lightweight copy for listing queries (dump_data: false)
    public func withoutData() -> MeticulousHistoryEntry {
        MeticulousHistoryEntry(
            id: self.id,
            dbKey: self.dbKey,
            time: self.time,
            name: self.name,
            profile: self.profile,
            data: nil
        )
    }
}

// MARK: - Profile Definition
public nonisolated struct MeticulousProfile: Codable, Sendable {
    public let name: String
    public let temperature: Double?
    public let dbKey: Int?

    public init(name: String, temperature: Double? = 93.0, dbKey: Int? = 1) {
        self.name = name
        self.temperature = temperature
        self.dbKey = dbKey
    }

    enum CodingKeys: String, CodingKey {
        case name
        case temperature
        case dbKey = "db_key"
    }
}

// MARK: - Extraction Data Point
public nonisolated struct MeticulousDataPoint: Codable, Sendable {
    public let time: Int
    public let status: String
    public let shot: MeticulousShotTelemetry

    public init(time: Int, status: String = "extracting", shot: MeticulousShotTelemetry) {
        self.time = time
        self.status = status
        self.shot = shot
    }
}

// MARK: - Shot Telemetry Values
public nonisolated struct MeticulousShotTelemetry: Codable, Sendable {
    public let pressure: Double
    public let flow: Double
    public let weight: Double
    public let temperature: Double
    public let gravimetricFlow: Double

    public init(
        pressure: Double,
        flow: Double,
        weight: Double,
        temperature: Double,
        gravimetricFlow: Double
    ) {
        self.pressure = pressure
        self.flow = flow
        self.weight = weight
        self.temperature = temperature
        self.gravimetricFlow = gravimetricFlow
    }

    enum CodingKeys: String, CodingKey {
        case pressure
        case flow
        case weight
        case temperature
        case gravimetricFlow = "gravimetric_flow"
    }
}
