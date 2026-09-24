//
//  LeftCockpitView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

extension Color {
    /// Warm crema-blonde tone signaling target yield reached/overrun without error alarm
    public static let blondingAmber = Color(red: 0.90, green: 0.66, blue: 0.34)
}

public struct LeftCockpitView: View {
    let frame: GuidanceFrame
    let displayElapsedTime: Double
    let displayStageTime: Double
    let displayActualWeight: Double
    let finalWeightTarget: Double
    let isAlarmActive: Bool
    
    public init(
        frame: GuidanceFrame,
        displayElapsedTime: Double,
        displayStageTime: Double,
        displayActualWeight: Double,
        finalWeightTarget: Double,
        isAlarmActive: Bool
    ) {
        self.frame = frame
        self.displayElapsedTime = displayElapsedTime
        self.displayStageTime = displayStageTime
        self.displayActualWeight = displayActualWeight
        self.finalWeightTarget = finalWeightTarget
        self.isAlarmActive = isAlarmActive
    }
    
    private var isOverrun: Bool {
        finalWeightTarget > 0 && displayActualWeight >= finalWeightTarget
    }
    
    private var cardStrokeStyle: AnyShapeStyle {
        if isOverrun {
            return AnyShapeStyle(Color.blondingAmber.opacity(0.35))
        } else {
            return AnyShapeStyle(Theme.Border.glassGradient)
        }
    }
    
    private var themeColor: Color {
        frame.activeMetric.themeColor
    }
    
    private var themeIcon: String {
        switch frame.activeMetric {
        case .pressure: return "gauge.with.dots.needle.bottom.50percent"
        case .flow:     return "water.waves"
        case .power:    return "bolt.fill"
        default:        return "chart.xyaxis.line"
        }
    }
    
    private var unitString: String {
        switch frame.activeMetric {
        case .pressure: return "bar"
        case .flow:     return "mL/s"
        case .power:    return "%"
        default:        return ""
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // Macro Shot Status: Clocks & Weight Yield
            HStack(spacing: 8) {
                // Time Card
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%04.1fs", displayElapsedTime))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    Text("Stage: \(String(format: "%.1fs", displayStageTime))")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Weight Card (Blonding Transition on Target Overrun)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(isOverrun ? Color.blondingAmber : .secondary)
                        Text(String(format: "%.1fg", displayActualWeight))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isOverrun ? Color.blondingAmber : Color.telemetryWeight)
                    }
                    Text(finalWeightTarget > 0 ? "Target: \(String(format: "%.1fg", finalWeightTarget))" : "Target: --")
                        .font(.system(size: 10, weight: isOverrun ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isOverrun ? Color.blondingAmber.opacity(0.85) : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .strokeBorder(cardStrokeStyle, lineWidth: 1)
            )
            
            Divider().background(Theme.Border.hair)
            
            // Active Stage Maneuver: Title + Mode Badge
            HStack {
                Text(frame.stageName.uppercased())
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: themeIcon)
                    Text(frame.activeMetric.description.capitalized)
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(themeColor.opacity(0.18))
                .foregroundStyle(themeColor)
                .clipShape(Capsule())
            }
            
            // Big Actual Reading
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", frame.actualValue))
                    .font(.system(size: 58, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(themeColor)
                Text(unitString)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, -4)
            
            // Target Setpoint & Delta Cue
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Text("Target")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f", frame.targetValue))
                        .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                DeltaBadge(delta: frame.delta, metric: frame.activeMetric, unit: unitString)
            }
            
            Divider().background(Theme.Border.subtle)
            
            // LIMIT / Guardrail
            if let limit = frame.activeLimit {
                let limitColor = limit.metric.themeColor
                let limitIcon = limit.metric == .pressure ? "gauge.with.dots.needle.bottom.50percent" : "water.waves"
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: isAlarmActive ? "exclamationmark.triangle.fill" : limitIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(isAlarmActive ? Color.red : limitColor)
                        
                        Text(isAlarmActive ? "LIMIT BREACHED!" : "LIMIT")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(isAlarmActive ? Color.red : .secondary)
                        
                        Spacer()
                        
                        Text("\(limit.metric.description.capitalized) <= \(String(format: "%.1f", limit.limitValue))")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isAlarmActive ? Color.red : limitColor)
                    }
                    
                    GeometryReader { geo in
                        let ratio = CGFloat(min(1.0, limit.actualValue / limit.limitValue))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isAlarmActive ? Color.red : (ratio > 0.8 ? Color.orange : limitColor.opacity(0.85)))
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.top, 2)
            } else {
                Text("No limit active")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
}

// MARK: - DeltaBadge (Channel-Aware Flight Director)

struct DeltaBadge: View {
    let delta: Double
    let metric: SensorKey
    let unit: String
    
    private var deadband: Double {
        metric == .pressure ? 0.4 : 0.3
    }
    
    private var isOver: Bool { delta > deadband }
    private var isUnder: Bool { delta < -deadband }
    
    private var channelColor: Color {
        metric.themeColor
    }
    
    var body: some View {
        HStack(spacing: 5) {
            if isOver {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .black))
                Text(String(format: "+%.1f", delta))
                    .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                Text("EASE OFF")
                    .font(.system(size: 9, weight: .heavy))
            } else if isUnder {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .black))
                Text(String(format: "%.1f", delta))
                    .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                Text("PULL HARDER")
                    .font(.system(size: 9, weight: .heavy))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                Text("ON TARGET")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .foregroundStyle(isOver || isUnder ? channelColor : .white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isOver || isUnder ? channelColor.opacity(0.14) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.controlRadius)
                .strokeBorder(isOver || isUnder ? channelColor.opacity(0.40) : Color.clear, lineWidth: 1)
        )
    }
}
