//
//  BaristaHUDView.swift
//  VirtualEspressoMachine
//

import Charts
import MeticulousProfile
import SwiftUI

// MARK: - Discrete Chart Coordinate Models

struct PlanPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

struct ActualPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

// MARK: - Exit Trigger Progress Model

struct ExitTriggerProgressItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let currentString: String
    let targetString: String
    let progress: Double
    let isLeading: Bool
}

typealias LimitStatus = GuardrailStatus
extension GuidanceFrame {
    var activeLimit: GuardrailStatus? { guardrail }
}

// MARK: - Main Barista HUD View

struct BaristaHUDView: View {
    @State private var profileStore = ProfileStore()

    // Active Profile & Stage Selection
    @State private var selectedProfileID: String = ""
    @State private var activeStageIndex: Int = 0

    // Derived UI State
    @State private var frame: GuidanceFrame = Self.emptyFrame
    @State private var planCurve: [PlanPoint] = []
    @State private var actualHistory: [ActualPoint] = []
    @State private var exitTriggerItems: [ExitTriggerProgressItem] = []

    // Dev Sandbox Controls
    @State private var simulateAlarm: Bool = false
    @State private var alarmFlashPhase: Bool = false

    private var currentProfile: Profile? {
        profileStore.profiles.first(where: { $0.id == selectedProfileID })
            ?? profileStore.profiles.first
    }

    private var currentStage: Stage? {
        guard let p = currentProfile,
            p.stages.indices.contains(activeStageIndex)
        else { return nil }
        return p.stages[activeStageIndex]
    }

    // Beanconqueror Canonical Metric Colors
    private func color(for metric: SensorKey) -> Color {
        switch metric {
        case .pressure: return Color(red: 0.15, green: 0.68, blue: 0.38)  // Forest Green
        case .flow: return Color(red: 0.0, green: 0.68, blue: 0.94)  // Cyan / Blue
        default: return Color.secondary
        }
    }

    private var themeColor: Color {
        color(for: frame.activeMetric)
    }

    private var themeIcon: String {
        frame.activeMetric == .pressure
            ? "gauge.with.dots.needle.bottom.50percent" : "water.waves"
    }

    private var isAlarmBreached: Bool {
        simulateAlarm || (frame.activeLimit?.isBreached ?? false)
    }

    var body: some View {
        ZStack {
            // Deep background
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

                Spacer(minLength: 0)

                sandboxToolbarView
            }
            .padding(.top, 4)
        }
        // Ambient Warning Glow
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    isAlarmBreached && alarmFlashPhase
                        ? Color.red.opacity(0.85) : Color.clear,
                    lineWidth: 6
                )
                .ignoresSafeArea()
        )
        .onAppear {
            if let first = profileStore.profiles.first {
                selectedProfileID = first.id
                rebuildStageData()
            }
        }
        .task(id: isAlarmBreached) {
            if isAlarmBreached {
                while !Task.isCancelled && isAlarmBreached {
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

    // MARK: - 1. Top Rail: Profile Selector & Stage Carousel

    @ViewBuilder
    private var topRailView: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(profileStore.profiles, id: \.id) { profile in
                    Button(profile.name) {
                        selectedProfileID = profile.id
                        activeStageIndex = 0
                        rebuildStageData()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.caption)
                    Text(currentProfile?.name ?? "Select Profile")
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
                .foregroundStyle(.primary)
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            if let profile = currentProfile {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(
                            Array(profile.stages.enumerated()),
                            id: \.offset
                        ) { index, stage in
                            Button(action: {
                                activeStageIndex = index
                                rebuildStageData()
                            }) {
                                StagePill(
                                    stageNumber: index + 1,
                                    title: stage.name,
                                    icon: stage.type == .pressure
                                        ? "gauge.with.dots.needle.bottom.50percent"
                                        : "water.waves",
                                    state: stageState(for: index)
                                )
                            }
                            .buttonStyle(.plain)

                            if index < profile.stages.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - 2. Left Cockpit: The Complete Instrument Cluster

    @ViewBuilder
    private var leftCockpitView: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Macro Shot Context: Time + Final Yield
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%04.1fs", frame.yieldProgress * 32.0))
                        .font(
                            .system(
                                size: 11,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                    Text("(~32s)")
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
                    Text(
                        String(
                            format: "%.1f / %.1fg",
                            frame.yieldProgress
                                * (currentProfile?.finalWeight ?? 40.0),
                            currentProfile?.finalWeight ?? 40.0
                        )
                    )
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }

            Divider().background(Color.white.opacity(0.06))

            // Active Stage Maneuver: Title + Mode
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
                    .font(
                        .system(size: 58, weight: .black, design: .monospaced)
                    )
                    .foregroundStyle(themeColor)
                Text(frame.activeMetric == .pressure ? "bar" : "mL/s")
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
                        .font(
                            .system(.body, design: .monospaced, weight: .bold)
                        )
                        .foregroundStyle(.primary)
                }

                Spacer()

                DeltaBadge(
                    delta: frame.delta,
                    metric: frame.activeMetric,
                    unit: frame.activeMetric == .pressure ? "bar" : "mL/s"
                )
            }

            Divider().background(Color.white.opacity(0.08))

            // STAGE LIMIT: Cleanly colored to its OWN physical metric!
            if let limit = frame.activeLimit {
                let limitColor = color(for: limit.metric)
                let limitIcon =
                    limit.metric == .pressure
                    ? "gauge.with.dots.needle.bottom.50percent" : "water.waves"

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(
                            systemName: isAlarmBreached
                                ? "exclamationmark.triangle.fill" : limitIcon
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(
                            isAlarmBreached ? Color.red : limitColor
                        )

                        Text(
                            isAlarmBreached ? "LIMIT BREACHED!" : "STAGE LIMIT"
                        )
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(
                            isAlarmBreached ? Color.red : .secondary
                        )

                        Spacer()

                        Text(
                            "\(limit.metric.description.capitalized) <= \(String(format: "%.1f", limit.limitValue))"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            isAlarmBreached ? Color.red : limitColor
                        )
                    }

                    // Proximity Bar wears the Limit's color (e.g. Cyan for Flow, Green for Pressure)
                    GeometryReader { geo in
                        let ratio = CGFloat(
                            min(1.0, limit.actualValue / limit.limitValue)
                        )
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    isAlarmBreached
                                        ? Color.red
                                        : (ratio > 0.8
                                            ? Color.orange
                                            : limitColor.opacity(0.85))
                                )
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

    // MARK: - 3. Stage Chart (Cleaned Header, Zero Jargon)

    @ViewBuilder
    private var stageDynamicsChartView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Clean domain indicator (no "STAGE DYNAMICS" clutter)
                Text(
                    "OVER: \(currentStage?.dynamics.over.rawValue.uppercased() ?? "TIME")"
                )
                .font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(themeColor.opacity(0.15))
                .foregroundStyle(themeColor)
                .clipShape(Capsule())

                Spacer()

                // Legend
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
                    AxisGridLine(
                        stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
                    )
                    .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine(
                        stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
                    )
                    .foregroundStyle(Color.white.opacity(0.1))
                    if let sec = value.as(Double.self) {
                        let unit =
                            currentStage?.dynamics.over == .weight ? "g" : "s"
                        AxisValueLabel("\(Int(sec))\(unit)")
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
                Text(
                    exitTriggerItems.first?.label == "Final Weight Cutoff"
                        ? "FINAL WEIGHT CUTOFF" : "EXIT TRIGGERS"
                )
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
                Spacer()
                if let leading = exitTriggerItems.first(where: { $0.isLeading })
                {
                    Text(
                        "\(leading.label.uppercased()) LEADING (\(Int(leading.progress * 100))%)"
                    )
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(themeColor)
                }
            }

            HStack(spacing: 12) {
                ForEach(exitTriggerItems) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: item.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    item.isLeading ? themeColor : .secondary
                                )
                            Text(item.label)
                                .font(
                                    .system(
                                        size: 10,
                                        weight: item.isLeading ? .bold : .medium
                                    )
                                )
                                .foregroundStyle(
                                    item.isLeading ? .primary : .secondary
                                )
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
                                    .fill(
                                        item.isLeading
                                            ? themeColor
                                            : Color.white.opacity(0.3)
                                    )
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(8)
                    .background(
                        Color.white.opacity(item.isLeading ? 0.05 : 0.02)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                item.isLeading
                                    ? themeColor.opacity(0.4) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .cornerRadius(6)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: - 5. Sandbox Stepper Dock

    @ViewBuilder
    private var sandboxToolbarView: some View {
        HStack(spacing: 10) {
            Text("PREVIEW STAGE:")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.tertiary)

            if let profile = currentProfile {
                ForEach(Array(profile.stages.enumerated()), id: \.offset) {
                    index,
                    stage in
                    Button("Stage \(index + 1)") {
                        activeStageIndex = index
                        rebuildStageData()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(activeStageIndex == index ? themeColor : .gray)
                }
            }

            Spacer()

            Toggle("Simulate Alarm", isOn: $simulateAlarm)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption2)
                .tint(.red)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Accurate Trajectory Math & State Builder

    private func rebuildStageData() {
        guard let profile = currentProfile, let stage = currentStage else {
            return
        }

        let activeMetric: SensorKey =
            (stage.type == .pressure) ? .pressure : .flow

        // Parse Raw Knots
        let rawKnots: [(x: Double, y: Double)] = stage.dynamics.points
            .compactMap { pt in
                guard let x = pt.x.numericValue, let y = pt.y.numericValue
                else { return nil }
                return (x: x, y: y)
            }

        // Find Stage Horizon
        let maxKnotX = rawKnots.map(\.x).max() ?? 0.0
        let timeTriggerVal =
            stage.exitTriggers?.first(where: { $0.type == .time })?.value
            .numericValue ?? 0.0
        let stageHorizon = max(maxKnotX, timeTriggerVal, 10.0)

        // Plan Curve with Infinite Right Flatline Rule
        var points: [PlanPoint] = []
        if rawKnots.isEmpty {
            points = [PlanPoint(x: 0, y: 0), PlanPoint(x: stageHorizon, y: 0)]
        } else if rawKnots.count == 1 {
            let singleY = rawKnots[0].y
            points = [
                PlanPoint(x: 0, y: singleY),
                PlanPoint(x: stageHorizon, y: singleY),
            ]
        } else {
            for knot in rawKnots {
                points.append(PlanPoint(x: knot.x, y: knot.y))
            }
            if let lastKnot = rawKnots.last, lastKnot.x < stageHorizon {
                points.append(PlanPoint(x: stageHorizon, y: lastKnot.y))
            }
        }
        self.planCurve = points

        // Extract Real Stage Limit
        var activeLimitStatus: GuardrailStatus? = nil
        if let limit = stage.limits?.first,
            let limitVal = limit.value.numericValue
        {
            let limitMetric: SensorKey =
                (limit.type == .pressure) ? .pressure : .flow
            let simActual = (limitMetric == .flow) ? 1.2 : 3.5
            activeLimitStatus = GuardrailStatus(
                metric: limitMetric,
                limitValue: limitVal,
                actualValue: simActual,
                isBreached: simActual > limitVal
            )
        }

        // Extract Real Exit Triggers
        var triggers: [ExitTriggerProgressItem] = []
        if let exitTriggers = stage.exitTriggers, !exitTriggers.isEmpty {
            for (idx, trigger) in exitTriggers.enumerated() {
                let targetNum = trigger.value.numericValue ?? 5.0
                let icon: String
                let unit: String
                let simActual: Double

                switch trigger.type {
                case .time:
                    icon = "clock.fill"
                    unit = "s"
                    simActual = targetNum * 0.65
                case .weight:
                    icon = "scalemass.fill"
                    unit = "g"
                    simActual = targetNum * 0.25
                case .pressure:
                    icon = "gauge.with.dots.needle.bottom.50percent"
                    unit = "bar"
                    simActual = targetNum * 0.85
                default:
                    icon = "water.waves"
                    unit = "mL/s"
                    simActual = targetNum * 0.5
                }

                let progress =
                    targetNum > 0 ? min(1.0, simActual / targetNum) : 0.0
                triggers.append(
                    ExitTriggerProgressItem(
                        icon: icon,
                        label: trigger.type.displayName,
                        currentString: String(
                            format: "%.1f%@",
                            simActual,
                            unit
                        ),
                        targetString: String(format: "%.1f%@", targetNum, unit),
                        progress: progress,
                        isLeading: idx == 0
                    )
                )
            }
        } else {
            let targetWeight = profile.finalWeight
            let simWeight = targetWeight * 0.70
            triggers.append(
                ExitTriggerProgressItem(
                    icon: "scalemass.fill",
                    label: "Final Weight Cutoff",
                    currentString: String(format: "%.1fg", simWeight),
                    targetString: String(format: "%.1fg", targetWeight),
                    progress: 0.70,
                    isLeading: true
                )
            )
        }
        self.exitTriggerItems = triggers

        // Simulated Actual Telemetry Trail
        let simElapsed = min(stageHorizon * 0.55, 12.0)
        let targetAtNow = evaluateTarget(
            at: simElapsed,
            knots: rawKnots,
            horizon: stageHorizon
        )
        let actualAtNow = max(0.0, targetAtNow - 0.25)

        self.actualHistory = [
            ActualPoint(x: 0.0, y: max(0.0, (rawKnots.first?.y ?? 2.0) * 0.3)),
            ActualPoint(x: simElapsed * 0.5, y: targetAtNow * 0.75),
            ActualPoint(x: simElapsed, y: actualAtNow),
        ]

        self.frame = GuidanceFrame(
            stageIndex: activeStageIndex,
            totalStages: profile.stages.count,
            stageName: stage.name,
            activeMetric: activeMetric,
            targetValue: targetAtNow,
            actualValue: actualAtNow,
            delta: actualAtNow - targetAtNow,
            stageProgress: triggers.first?.progress ?? 0.65,
            yieldProgress: 0.30,
            guardrail: activeLimitStatus
        )
    }

    private func evaluateTarget(
        at time: Double,
        knots: [(x: Double, y: Double)],
        horizon: Double
    ) -> Double {
        guard let first = knots.first else { return 0.0 }
        if knots.count == 1 || time <= first.x { return first.y }
        if let last = knots.last, time >= last.x { return last.y }

        for i in 0..<(knots.count - 1) {
            let p0 = knots[i]
            let p1 = knots[i + 1]
            if time >= p0.x && time <= p1.x {
                let ratio = (time - p0.x) / (p1.x - p0.x)
                return p0.y + ratio * (p1.y - p0.y)
            }
        }
        return first.y
    }

    private func stageState(for index: Int) -> StagePillState {
        if index < activeStageIndex { return .completed }
        if index == activeStageIndex { return .active }
        return .upcoming
    }

    private static var emptyFrame: GuidanceFrame {
        GuidanceFrame(
            stageIndex: 0,
            totalStages: 1,
            stageName: "Standby",
            activeMetric: .pressure,
            targetValue: 0.0,
            actualValue: 0.0,
            delta: 0.0,
            stageProgress: 0.0,
            yieldProgress: 0.0,
            guardrail: nil
        )
    }
}

// MARK: - Subviews: DeltaBadge & StagePill

private struct DeltaBadge: View {
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
                    .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.25))  // Coral
                Text(String(format: "+%.1f", delta))
                    .font(
                        .system(
                            .subheadline,
                            design: .monospaced,
                            weight: .bold
                        )
                    )
                Text("EASE OFF")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(red: 0.95, green: 0.40, blue: 0.25))
            } else if isUnder {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(red: 0.98, green: 0.68, blue: 0.15))  // Amber/Gold
                Text(String(format: "%.1f", delta))
                    .font(
                        .system(
                            .subheadline,
                            design: .monospaced,
                            weight: .bold
                        )
                    )
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

private enum StagePillState {
    case completed
    case active
    case upcoming
}

private struct StagePill: View {
    let stageNumber: Int
    let title: String
    let icon: String
    let state: StagePillState

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        state == .active
                            ? Color.white.opacity(0.15)
                            : Color.white.opacity(0.05)
                    )
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
                    .font(
                        .system(
                            size: 10,
                            weight: state == .active ? .bold : .medium
                        )
                    )
                    .foregroundStyle(state == .active ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            state == .active
                ? Color.white.opacity(0.08) : Color.white.opacity(0.02)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    state == .active ? Color.white.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .cornerRadius(6)
    }
}

#Preview {
    BaristaHUDView()
        .previewInterfaceOrientation(.landscapeLeft)
}
