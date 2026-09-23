//
//  BQDataModels.swift
//  LeverPilot
//

import Foundation

// MARK: - Configuration Identifier
public nonisolated struct BQConfig: Codable, Hashable, Sendable {
    public let uuid: String
    
    public init(uuid: String) {
        self.uuid = uuid
    }
}

// MARK: - Root Export Envelope (Beans Only)
public nonisolated struct BQExport: Codable, Sendable {
    public let beans: [BQBean]

    enum CodingKeys: String, CodingKey {
        case beans = "BEANS"
    }
    
    public init(beans: [BQBean]) {
        self.beans = beans
    }
}

// MARK: - Bean Model
public nonisolated struct BQBean: Codable, Identifiable, Hashable, Sendable {
    public var id: String { config.uuid }
    public let name: String
    public let roaster: String?
    public let roastingDate: String?
    public let finished: Bool?
    public let internalShareCode: String?
    public let config: BQConfig

    public var isActive: Bool {
        !(finished ?? false)
    }

    public var hasShareCode: Bool {
        guard let code = internalShareCode else { return false }
        return !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case name
        case roaster
        case roastingDate
        case finished
        case internalShareCode = "internal_share_code"
        case config
    }
    
    public init(
        name: String,
        roaster: String? = nil,
        roastingDate: String? = nil,
        finished: Bool? = nil,
        internalShareCode: String? = nil,
        config: BQConfig
    ) {
        self.name = name
        self.roaster = roaster
        self.roastingDate = roastingDate
        self.finished = finished
        self.internalShareCode = internalShareCode
        self.config = config
    }
}
