//
//  ExitTriggersPanelView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

public struct ExitTriggersPanelView: View {
    let exitTriggerItems: [ExitTriggerProgressItem]
    let activeMetric: SensorKey
    
    public init(
        exitTriggerItems: [ExitTriggerProgressItem],
        activeMetric: SensorKey
    ) {
        self.exitTriggerItems = exitTriggerItems
        self.activeMetric = activeMetric
    }
    
    private var themeColor: Color {
        activeMetric.themeColor
    }
    
    private func itemColor(for item: ExitTriggerProgressItem) -> Color {
        // Both weight overruns and the completed target state glow in Blonding Amber
        if item.label == "Profile Complete" || (item.sensorKey == .weight && item.progress >= 1.0) {
            return Color.blondingAmber
        }
        return item.sensorKey.themeColor
    }
    
    private func strokeColor(for item: ExitTriggerProgressItem) -> Color {
        guard item.isLeading else { return Color.clear }
        if item.label == "Profile Complete" || (item.sensorKey == .weight && item.progress >= 1.0) {
            return Color.blondingAmber.opacity(0.4)
        }
        return themeColor.opacity(0.4)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exitTriggerItems.first?.label == "Final Weight Cutoff" ? "FINAL WEIGHT CUTOFF" : "EXIT TRIGGERS")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let leading = exitTriggerItems.first(where: { $0.isLeading }) {
                    let leadingColor = itemColor(for: leading)
                    
                    Text("\(leading.label.uppercased()) LEADING (\(Int(leading.progress * 100))%)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(leadingColor)
                }
            }
            
            if exitTriggerItems.isEmpty {
                HStack {
                    Text("No exit triggers active")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(8)
            } else {
                HStack(spacing: 12) {
                    ForEach(exitTriggerItems) { item in
                        let isBlonding = item.label == "Profile Complete" || (item.sensorKey == .weight && item.progress >= 1.0)
                        let color = itemColor(for: item)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(item.isLeading ? color : .secondary)
                                Text(item.label)
                                    .font(.system(size: 11, weight: item.isLeading ? .bold : .medium))
                                    .foregroundStyle(item.isLeading ? .primary : .secondary)
                                Spacer()
                                Text("\(item.currentString) / \(item.targetString)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(isBlonding ? Color.blondingAmber : .secondary)
                            }
                            
                            GeometryReader { geo in
                                let clampedRatio = CGFloat(min(1.0, max(0.0, item.progress)))
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.isLeading ? color : Color.white.opacity(0.3))
                                        .frame(width: geo.size.width * clampedRatio)
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(8)
                        .background(Color.white.opacity(item.isLeading ? 0.05 : 0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(strokeColor(for: item), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}
