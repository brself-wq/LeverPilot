//
//  Color+Hex.swift
//  LeverPilot
//

import SwiftUI

extension Color {
    init(hex: String?, fallback: Color = Color(red: 0.90, green: 0.68, blue: 0.28)) {
        guard let hex = hex else {
            self = fallback
            return
        }
        
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        
        let r, g, b, a: Double
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = (
                Double((int >> 8) * 17) / 255,
                Double((int >> 4 & 0xF) * 17) / 255,
                Double((int & 0xF) * 17) / 255,
                1.0
            )
        case 6: // RGB (24-bit)
            (r, g, b, a) = (
                Double((int >> 16) & 0xFF) / 255,
                Double((int >> 8) & 0xFF) / 255,
                Double(int & 0xFF) / 255,
                1.0
            )
        case 8: // RGBA (32-bit)
            (r, g, b, a) = (
                Double((int >> 24) & 0xFF) / 255,
                Double((int >> 16) & 0xFF) / 255,
                Double((int >> 8) & 0xFF) / 255,
                Double(int & 0xFF) / 255
            )
        default:
            self = fallback
            return
        }
        
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
