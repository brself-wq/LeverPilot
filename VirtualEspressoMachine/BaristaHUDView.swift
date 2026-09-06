//
//  BaristaHUDView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/3/26.
//

import SwiftUI
import Charts
import MeticulousProfile

// MARK: - Discrete Coordinate & Progress Models (Nonisolated Value Types)

public nonisolated struct PlanPoint: Identifiable, Sendable {
    public let id: UUID
    public let x: Double
    public let y: Double
    
    public init(id: UUID = UUID(), x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public nonisolated struct ActualPoint: Identifiable, Sendable {
    public let id: UUID
    public let x: Double
    public let y: Double
    
    public init(id: UUID = UUID(), x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public nonisolated struct ExitTriggerProgressItem: Identifiable, Sendable {
    public let id: UUID
    public let sensorKey: SensorKey
    public let icon: String
    public let label: String
    public let currentString: String
    public let targetString: String
    public let progress: Double
    public let isLeading: Bool
    
    public init(id: UUID = UUID(), sensorKey: SensorKey, icon: String, label: String, currentString: String, targetString: String, progress: Double, isLeading: Bool) {
        self.id = id
        self.sensorKey = sensorKey
        self.icon = icon
        self.label = label
        self.currentString = currentString
        self.targetString = targetString
        self.progress = progress
        self.isLeading = isLeading
    }
}

public nonisolated enum StagePillState: Sendable {
    case completed
    case active
    case upcoming
}

public nonisolated struct StagePillItem: Identifiable, Sendable {
    public let id: UUID
    public let stageNumber: Int
    public let title: String
    public let icon: String
    public let state: StagePillState
    
    public init(id: UUID = UUID(), stageNumber: Int, title: String, icon: String, state: StagePillState) {
        self.id = id
        self.stageNumber = stageNumber
        self.title = title
        self.icon = icon
        self.state = state
    }
}

typealias LimitStatus = GuardrailStatus
extension GuidanceFrame {
    var activeLimit: GuardrailStatus? { guardrail }
}

// MARK: - Releasable Barista HUD Presentation View

public struct BaristaHUDView: View {
    let frame: GuidanceFrame
    let planCurve: [PlanPoint]
    let actualHistory: [ActualPoint]
    let exitTriggerItems: [ExitTriggerProgressItem]
    let stagePills: [StagePillItem]
    let domainLabel: String
    let finalWeightTarget: Double
    let nominalDuration: Double
    let isAlarmActive: Bool
    
    var onSelectStage: ((Int) -> Void)? = nil
    
    @State private var alarmFlashPhase: Bool = false
    
    public init(
        frame: GuidanceFrame,
        planCurve: [PlanPoint],
        actualHistory: [ActualPoint],
        exitTriggerItems: [ExitTriggerProgressItem],
        stagePills: [StagePillItem],
        domainLabel: String = "TIME",
        finalWeightTarget: Double = 40.0,
        nominalDuration: Double = 32.0,
        isAlarmActive: Bool = false,
        onSelectStage: ((Int) -> Void)? = nil
    ) {
        self.frame = frame
        self.planCurve = planCurve
        self.actualHistory = actualHistory
        self.exitTriggerItems = exitTriggerItems
        self.stagePills = stagePills
        self.domainLabel = domainLabel
        self.finalWeightTarget = finalWeightTarget
        self.nominalDuration = nominalDuration
        self.isAlarmActive = isAlarmActive
        self.onSelectStage = onSelectStage
    }
    
    // 4-Channel Canonical Color Palette
    private func color(for metric: SensorKey) -> Color {
        switch metric {
        case .pressure: return Color(red: 0.15, green: 0.68, blue: 0.38) // Forest Green
        case .flow:     return Color(red: 0.0, green: 0.68, blue: 0.94)  // Cyan / Blue
        case .power:    return Color(red: 1.0, green: 0.48, blue: 0.0)   // Electric Orange (80's Espresso)
        case .weight:   return Color(red: 0.90, green: 0.68, blue: 0.28) // Crema Caramel
        case .time:     return Color(red: 0.65, green: 0.72, blue: 0.85) // Slate Silver
        default:        return Color.secondary
        }
    }
    
    private var themeColor: Color {
        color(for: frame.activeMetric)
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
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                topRailView
                
                HStack(spacing: 10) {
                    leftCockpitView
                        .frame(width: 280)
                    
                    VStack(spacing: 8) {
                        stageDynamicsChartView
                        exitTriggersView
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isAlarmActive && alarmFlashPhase ? Color.red.opacity(0.85) : Color.clear, lineWidth: 6)
                .ignoresSafeArea()
        )
        .task(id: isAlarmActive) {
            if isAlarmActive {
                while !Task.isCancelled && isAlarmActive {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        alarmFlashPhase.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                }
            } else {
                alarmFlashPhase = false
            }
        }
    }
    
    // MARK: - 1. Top Rail: Recipe Stages & Macro Context
    
    @ViewBuilder
    private var topRailView: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stagePills) { pill in
                        Button(action: {
                            onSelectStage?(pill.stageNumber - 1)
                        }) {
                            StagePill(
                                stageNumber: pill.stageNumber,
                                title: pill.title,
                                icon: pill.icon,
                                state: pill.state
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if pill.stageNumber < stagePills.count {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
    }
    
    // MARK: - 2. Left Cockpit: The Complete Instrument Cluster
    
    @ViewBuilder
    private var leftCockpitView: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // Macro Shot Status: Clock + Final Yield
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%04.1fs", frame.yieldProgress * nominalDuration))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("(\(Int(nominalDuration))s)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f / %.1fg", frame.yieldProgress * finalWeightTarget, finalWeightTarget))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }
            
            Divider().background(Color.white.opacity(0.06))
            
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
                    .font(.system(size: 58, weight: .black, design: .monospaced))
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
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f", frame.targetValue))
                        .font(.system(.body, design: .monospaced, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                DeltaBadge(delta: frame.delta, metric: frame.activeMetric, unit: unitString)
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            // LIMIT: Cleanly labeled and styled
            if let limit = frame.activeLimit {
                let limitColor = color(for: limit.metric)
                let limitIcon = limit.metric == .pressure ? "gauge.with.dots.needle.bottom.50percent" : "water.waves"
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: isAlarmActive ? "exclamationmark.triangle.fill" : limitIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(isAlarmActive ? Color.red : limitColor)
                        
                        Text(isAlarmActive ? "LIMIT BREACHED!" : "LIMIT")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(isAlarmActive ? Color.red : .secondary)
                        
                        Spacer()
                        
                        Text("\(limit.metric.description.capitalized) <= \(String(format: "%.1f", limit.limitValue))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
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
        .cornerRadius(12)
    }
    
    // MARK: - 3. Stage Dynamics Chart
    
    @ViewBuilder
    private var stageDynamicsChartView: some View {
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
                
                if let current = actualHistory.last {
                    PointMark(
                        x: .value("Domain", current.x),
                        y: .value("Value", current.y)
                    )
                    .symbolSize(80)
                    .foregroundStyle(Color.white)
                }
            }
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
        .cornerRadius(12)
    }
    
    // MARK: - 4. Exit Triggers Panel
    
    @ViewBuilder
    private var exitTriggersView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exitTriggerItems.first?.label == "Final Weight Cutoff" ? "FINAL WEIGHT CUTOFF" : "EXIT TRIGGERS")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Spacer()
                if let leading = exitTriggerItems.first(where: { $0.isLeading }) {
                    let leadingColor = color(for: leading.sensorKey)
                    Text("\(leading.label.uppercased()) LEADING (\(Int(leading.progress * 100))%)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(leadingColor)
                }
            }
            
            HStack(spacing: 12) {
                ForEach(exitTriggerItems) { item in
                    let itemColor = color(for: item.sensorKey)
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
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}

// MARK: - Subviews: DeltaBadge & StagePill

struct DeltaBadge: View {
    let delta: Double
    let metric: SensorKey
    let unit: String
    
    private var deadband: Double {
        metric == .pressure ? 0.4 : 0.3
    }
    
    private var isOver: Bool { delta > deadband }
    private var isUnder: Bool { delta < -deadband }
    
    var body: some View {
        HStack(spacing: 5) {
            if isOver {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.25))
                Text(String(format: "+%.1f", delta))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                Text("EASE OFF")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.25))
            } else if isUnder {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(red: 0.98, green: 0.68, blue: 0.15))
                Text(String(format: "%.1f", delta))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                Text("PULL HARDER")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(red: 0.98, green: 0.68, blue: 0.15))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                Text("ON TARGET")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
    }
}

struct StagePill: View {
    let stageNumber: Int
    let title: String
    let icon: String
    let state: StagePillState
    
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state == .active ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                    .frame(width: 20, height: 20)
                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(state == .active ? .white : .secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("STAGE \(stageNumber)")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(state == .active ? .secondary : .tertiary)
                Text(title)
                    .font(.system(size: 10, weight: state == .active ? .bold : .medium))
                    .foregroundStyle(state == .active ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state == .active ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(state == .active ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(6)
    }
}
