//
//  BQDataModels.swift
//  VirtualEspressoMachine
//

import Foundation

// MARK: - Configuration Identifier
public struct BQConfig: Codable, Hashable, Sendable {
    public let uuid: String
}

// MARK: - Root Export Envelope (Beans Only)
public struct BQExport: Codable, Sendable {
    public let beans: [BQBean]

    enum CodingKeys: String, CodingKey {
        case beans = "BEANS"
    }
}

// MARK: - Bean Model
public struct BQBean: Codable, Identifiable, Hashable, Sendable {
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
}
