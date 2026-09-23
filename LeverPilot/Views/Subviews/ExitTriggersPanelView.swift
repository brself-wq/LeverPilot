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
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exitTriggerItems.first?.label == "Final Weight Cutoff" ? "FINAL WEIGHT CUTOFF" : "EXIT TRIGGERS")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Spacer()
                if let leading = exitTriggerItems.first(where: { $0.isLeading }) {
                    let leadingColor = leading.sensorKey.themeColor
                    Text("\(leading.label.uppercased()) LEADING (\(Int(leading.progress * 100))%)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(leadingColor)
                }
            }
            
            if exitTriggerItems.isEmpty {
                HStack {
                    Text("No exit triggers active")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(8)
            } else {
                HStack(spacing: 12) {
                    ForEach(exitTriggerItems) { item in
                        let itemColor = item.sensorKey.themeColor
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(item.isLeading ? itemColor : .secondary)
                                Text(item.label)
                                    .font(.system(size: 10, weight: item.isLeading ? .bold : .medium))
                                    .foregroundStyle(item.isLeading ? .primary : .secondary)
                                Spacer()
                                Text("\(item.currentString) / \(item.targetString)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            GeometryReader { geo in
                                let ratio = CGFloat(item.progress)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.isLeading ? itemColor : Color.white.opacity(0.3))
                                        .frame(width: geo.size.width * ratio)
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(8)
                        .background(Color.white.opacity(item.isLeading ? 0.05 : 0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(item.isLeading ? themeColor.opacity(0.4) : Color.clear, lineWidth: 1)
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
