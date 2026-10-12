//
//  AppDestination.swift
//  LeverPilot
//

import Foundation

/// Primary macro-level workspaces for the Virtual Espresso Machine console.
public enum AppDestination: String, CaseIterable, Identifiable, Sendable {
    case brew = "Brew"
    case history = "History"
    #if ENABLE_WORKBENCH
    case workbench = "Workbench"
    #endif
    case settings = "Settings"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .brew: return "cup.and.saucer.fill"
        case .history: return "chart.xyaxis.line"
        #if ENABLE_WORKBENCH
        case .workbench: return "wrench.and.screwdriver.fill"
        #endif
        case .settings: return "gearshape.fill"
        }
    }
}
