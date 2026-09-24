//
//  CoffeeBeanGlyph.swift
//  LeverPilot
//

import SwiftUI

public struct CoffeeBeanGlyph: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Center rotation transform (-22° tilt matching BQ orientation)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: -22.0 * .pi / 180.0)
            .translatedBy(x: -center.x, y: -center.y)

        var beanPath = Path()
        
        // Left Lobe
        beanPath.move(to: CGPoint(x: rect.minX + w * 0.46, y: rect.minY + h * 0.08))
        beanPath.addCurve(
            to: CGPoint(x: rect.minX + w * 0.46, y: rect.minY + h * 0.92),
            control1: CGPoint(x: rect.minX + w * 0.02, y: rect.minY + h * 0.22),
            control2: CGPoint(x: rect.minX + w * 0.02, y: rect.minY + h * 0.78)
        )
        beanPath.addCurve(
            to: CGPoint(x: rect.minX + w * 0.46, y: rect.minY + h * 0.08),
            control1: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.65),
            control2: CGPoint(x: rect.minX + w * 0.58, y: rect.minY + h * 0.35)
        )
        beanPath.closeSubpath()

        // Right Lobe
        beanPath.move(to: CGPoint(x: rect.minX + w * 0.54, y: rect.minY + h * 0.08))
        beanPath.addCurve(
            to: CGPoint(x: rect.minX + w * 0.54, y: rect.minY + h * 0.92),
            control1: CGPoint(x: rect.minX + w * 0.66, y: rect.minY + h * 0.35),
            control2: CGPoint(x: rect.minX + w * 0.40, y: rect.minY + h * 0.65)
        )
        beanPath.addCurve(
            to: CGPoint(x: rect.minX + w * 0.54, y: rect.minY + h * 0.08),
            control1: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.78),
            control2: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.22)
        )
        beanPath.closeSubpath()

        path.addPath(beanPath, transform: transform)
        return path
    }
}

// Convenient Color Extension for BQ Warm Caramel
extension Color {
    public static let bqCaramel = Color(red: 0.86, green: 0.64, blue: 0.42)
}
