//
//  Theme.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

public enum Theme {
    // MARK: - Surfaces & Backgrounds
    public enum Surface {
        public static let canvas = Color(red: 0.05, green: 0.05, blue: 0.06)
        public static let card = Color(red: 0.08, green: 0.08, blue: 0.10)
        public static let overlay = Color(red: 0.07, green: 0.07, blue: 0.09)
        public static let footer = Color(red: 0.06, green: 0.06, blue: 0.08)
        public static let well = Color.white.opacity(0.04)
        public static let wellSubtle = Color.white.opacity(0.03)
        public static let control = Color.white.opacity(0.06)
        public static let selected = Color.white.opacity(0.10)
    }
    
    // MARK: - Borders & Dividers
    public enum Border {
        public static let subtle = Color.white.opacity(0.08)
        public static let hair = Color.white.opacity(0.06)
        public static let active = Color.white.opacity(0.25)
        public static var glassGradient: LinearGradient {
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Telemetry Palette
    public enum Telemetry {
        public static let pressure = Color(red: 0.13, green: 0.77, blue: 0.51) // Emerald Green (#22C55E)
        public static let flow     = Color(red: 0.06, green: 0.65, blue: 0.91) // Hydro Cyan (#0EA5E9)
        public static let power    = Color(red: 0.98, green: 0.45, blue: 0.09) // Tungsten Amber (#F97316)
        public static let weight   = Color(red: 0.96, green: 0.62, blue: 0.04) // Crema Gold (#F59E0B)
        public static let pullHarder = Color(red: 0.98, green: 0.68, blue: 0.15)
        public static let easeOff    = Color(red: 0.95, green: 0.40, blue: 0.25)
        public static let warning    = Color(red: 0.98, green: 0.72, blue: 0.20)
        public static let alert      = Color(red: 1.0, green: 0.42, blue: 0.42)
        public static let inactive   = Color(red: 0.65, green: 0.72, blue: 0.85)
    }
    
    // MARK: - Geometry
    public enum Layout {
        public static let pillRadius: CGFloat = 4
        public static let controlRadius: CGFloat = 6
        public static let cardRadius: CGFloat = 8
        public static let wellRadius: CGFloat = 10
        public static let podRadius: CGFloat = 12
        public static let heroRadius: CGFloat = 18
    }
}

// MARK: - Global Ergonomic Extensions
extension Color {
    public static let appCanvas = Theme.Surface.canvas
    public static let appCard = Theme.Surface.card
    public static let appOverlay = Theme.Surface.overlay
    public static let appFooter = Theme.Surface.footer
    public static let appBorderSubtle = Theme.Border.subtle
    
    public static let telemetryPressure = Theme.Telemetry.pressure
    public static let telemetryFlow = Theme.Telemetry.flow
    public static let telemetryWeight = Theme.Telemetry.weight
    public static let telemetryPower = Theme.Telemetry.power
    public static let telemetryWarning = Theme.Telemetry.warning
    public static let telemetryAlert = Theme.Telemetry.alert
}

// MARK: - Domain SensorKey Binding
extension SensorKey {
    public var themeColor: Color {
        switch self {
        case .pressure: return Theme.Telemetry.pressure
        case .flow:     return Theme.Telemetry.flow
        case .power:    return Theme.Telemetry.power
        case .weight:   return Theme.Telemetry.weight
        case .time:     return Theme.Telemetry.inactive
        default:        return .secondary
        }
    }
}
