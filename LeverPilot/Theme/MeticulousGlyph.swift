//
//  MeticulousGlyph.swift
//  LeverPilot
//

import SwiftUI

/// Vector Shape for the official Meticulous geometric 'M.' emblem.
public struct MeticulousGlyph: Shape {
    public var includePeriod: Bool

    public init(includePeriod: Bool = true) {
        self.includePeriod = includePeriod
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // 1. The Origami-style geometric 'M'
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.28))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.76, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.76, y: rect.minY + h * 0.28))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: rect.minY + h * 0.62))
        path.closeSubpath()

        // 2. The signature offset period '.' (conditionally drawn)
        if includePeriod {
            let dotDiameter = w * 0.16
            let dotRect = CGRect(
                x: rect.minX + w * 0.84,
                y: rect.maxY - dotDiameter,
                width: dotDiameter,
                height: dotDiameter
            )
            path.addEllipse(in: dotRect)
        }

        return path
    }
}
