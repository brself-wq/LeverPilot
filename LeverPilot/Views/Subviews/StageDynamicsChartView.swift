//
//  StageDynamicsChartView.swift
//  LeverPilot
//

import SwiftUI
import Charts
import MeticulousProfile

struct StageDynamicsChartView: View {
    static let slidingWindowSpan: TimeInterval = 25.0

    let planCurve: [PlanPoint]
    let actualHistory: [ActualPoint]
    let domainLabel: String
    let activeMetric: SensorKey
    
    /// Maximum time/domain span (in seconds or grams) visible in the viewport window
    let windowSpan: Double
    
    /// Terminal approach guidance progress (nil = cruising, 0.0 -> 1.0 = closing, >1.125 = overrun)
    let approachProgress: Double?
    
    public init(
        planCurve: [PlanPoint],
        actualHistory: [ActualPoint],
        domainLabel: String,
        activeMetric: SensorKey,
        windowSpan: Double = 25.0,
        approachProgress: Double? = nil
    ) {
        self.planCurve = planCurve
        self.actualHistory = actualHistory
        self.domainLabel = domainLabel
        self.activeMetric = activeMetric
        self.windowSpan = windowSpan
        self.approachProgress = approachProgress
    }
    
    private var themeColor: Color {
        activeMetric.themeColor
    }
    
    private var currentX: Double {
        actualHistory.last?.x ?? 0.0
    }
    
    private var xDomain: ClosedRange<Double> {
        let nominalMax = planCurve.map(\.x).max() ?? windowSpan
        let baselineMax = max(windowSpan, nominalMax)
        
        if currentX <= baselineMax {
            return 0.0...baselineMax
        } else {
            return (currentX - windowSpan)...currentX
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("OVER: \(domainLabel.uppercased())")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeColor.opacity(0.15))
                    .foregroundStyle(themeColor)
                    .clipShape(Capsule())
                
                Spacer()
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("╌╌")
                            .fontWeight(.black)
                            .foregroundStyle(themeColor.opacity(0.6))
                        Text("Plan (Target)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("──")
                            .fontWeight(.black)
                            .foregroundStyle(themeColor)
                        Text("Actual Pull")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Chart {
                ForEach(planCurve) { pt in
                    LineMark(
                        x: .value("Domain", pt.x),
                        y: .value("Value", pt.y),
                        series: .value("Stream", "Plan")
                    )
                    .foregroundStyle(themeColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                }
                
                ForEach(actualHistory) { pt in
                    LineMark(
                        x: .value("Domain", pt.x),
                        y: .value("Value", pt.y),
                        series: .value("Stream", "Actual")
                    )
                    .foregroundStyle(themeColor)
                    .lineStyle(StrokeStyle(lineWidth: 3.5))
                }
                
                // Dynamic Leading Tracer Bead (With Compass Rose Closing Reticle & Overrun Lock)
                if let current = actualHistory.last {
                    PointMark(
                        x: .value("Domain", current.x),
                        y: .value("Value", current.y)
                    )
                    .symbolSize(85)
                    .foregroundStyle(themeColor)
                    
                    PointMark(
                        x: .value("Domain", current.x),
                        y: .value("Value", current.y)
                    )
                    .symbolSize(30)
                    .foregroundStyle(Color.white)
                    .annotation(position: .overlay) {
                        if let progress = approachProgress {
                            CompassReticleOverlay(progress: progress)
                        }
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    if let val = value.as(Double.self) {
                        let unit = domainLabel.lowercased() == "weight" ? "g" : "s"
                        AxisValueLabel("\(Int(val))\(unit)")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
}

// MARK: - Perfectly Concentric Compass Rose Reticle with Symmetrical Overrun Lock

private struct CompassReticleOverlay: View {
    let progress: Double // 0.0 (12g out) -> 1.0 (Target) -> 1.125 (+1.5g Overrun)
    
    // Scale calibrated for the 11" iPad & macOS canvas
    private let baseDiameter: CGFloat = 110.0
    private let lockedDiameter: CGFloat = 20.0
    private let overrunDiameter: CGFloat = 42.0 // Snaps open on overrun
    
    // 1.5g overrun / 12.0g window = 0.125. The Green Pocket spans 1.0 to 1.125
    private var isOverrun: Bool {
        progress > 1.125
    }
    
    private var isTouchdownPocket: Bool {
        progress >= 1.0 && !isOverrun
    }
    
    private var isFlareActive: Bool {
        progress >= 0.875 && progress < 1.0
    }
    
    private var currentDiameter: CGFloat {
        if isOverrun {
            return overrunDiameter
        } else if isTouchdownPocket {
            return lockedDiameter
        } else {
            return baseDiameter - (CGFloat(progress) * (baseDiameter - lockedDiameter))
        }
    }
    
    private var reticleColor: Color {
        if isOverrun {
            return Theme.Telemetry.alert     // Ruby Red on overrun
        } else if isTouchdownPocket {
            return Theme.Telemetry.pressure  // Emerald Green in the pocket
        } else if isFlareActive {
            return Theme.Telemetry.warning   // Tungsten Amber during flare
        } else {
            return Theme.Telemetry.weight    // Crema Gold during closing
        }
    }
    
    private var strokeStyle: StrokeStyle {
        if isOverrun {
            return StrokeStyle(lineWidth: 2.0, dash: [4, 4]) // Dashed Lost-Lock
        } else {
            return StrokeStyle(lineWidth: (isFlareActive || isTouchdownPocket) ? 3.5 : 2.5)
        }
    }
    
    private var strokeOpacity: Double {
        isOverrun ? 0.95 : (0.55 + (min(1.0, progress) * 0.45))
    }
    
    var body: some View {
        ZStack {
            // 1. Contracting Targeting Ring (Pops to dashed red on overrun)
            Circle()
                .stroke(reticleColor.opacity(strokeOpacity), style: strokeStyle)
                .frame(width: currentDiameter, height: currentDiameter)
                .shadow(
                    color: reticleColor.opacity(isOverrun ? 0.7 : (isFlareActive ? 0.6 : 0.3)),
                    radius: isOverrun ? 5 : 3
                )
            
            // 2. Mathematically Concentric Cardinal Compass Ticks
            ForEach([0, 90, 180, 270], id: \.self) { angle in
                Capsule()
                    .fill(reticleColor.opacity(strokeOpacity))
                    .frame(width: isOverrun ? 2.0 : (isFlareActive ? 3.5 : 2.5), height: 8)
                    .offset(y: -(currentDiameter / 2 + 6))
                    .rotationEffect(.degrees(Double(angle)))
            }
        }
        .frame(width: currentDiameter + 30, height: currentDiameter + 30)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: isOverrun)
        .animation(.easeOut(duration: 0.1), value: progress)
    }
}
