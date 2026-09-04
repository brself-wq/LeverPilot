//
//  BaristaHUDSimulatorView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/4/26.
//

import SwiftUI
import MeticulousProfile

struct BaristaHUDSimulatorView: View {
    @State private var profileStore = ProfileStore()
    
    @State private var selectedProfileID: String = ""
    @State private var activeStageIndex: Int = 0
    
    // Extracted Display Data
    @State private var frame: GuidanceFrame = Self.emptyFrame
    @State private var planCurve: [PlanPoint] = []
    @State private var actualHistory: [ActualPoint] = []
    @State private var exitTriggerItems: [ExitTriggerProgressItem] = []
    @State private var stagePills: [StagePillItem] = []
    
    @State private var simulateAlarm: Bool = false
    
    private var currentProfile: Profile? {
        profileStore.profiles.first(where: { $0.id == selectedProfileID }) ?? profileStore.profiles.first
    }
    
    private var currentStage: Stage? {
        guard let p = currentProfile, p.stages.indices.contains(activeStageIndex) else { return nil }
        return p.stages[activeStageIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Releasable Barista HUD
            BaristaHUDView(
                frame: frame,
                planCurve: planCurve,
                actualHistory: actualHistory,
                exitTriggerItems: exitTriggerItems,
                stagePills: stagePills,
                domainLabel: currentStage?.dynamics.over.rawValue.capitalized ?? "Time",
                finalWeightTarget: currentProfile?.finalWeight ?? 40.0,
                nominalDuration: 32.0,
                isAlarmActive: simulateAlarm || (frame.guardrail?.isBreached ?? false),
                onSelectStage: { index in
                    activeStageIndex = index
                    rebuildStageData()
                }
            )
            
            // Dev Sandbox Toolbar (Isolated to this wrapper!)
            HStack(spacing: 12) {
                // Profile Switcher
                Menu {
                    ForEach(profileStore.profiles, id: \.id) { profile in
                        Button(profile.name) {
                            selectedProfileID = profile.id
                            activeStageIndex = 0
                            rebuildStageData()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text(currentProfile?.name ?? "Profile")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                
                Divider().frame(height: 14)
                
                Text("DEV STAGES:")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.tertiary)
                
                if let profile = currentProfile {
                    ForEach(Array(profile.stages.enumerated()), id: \.offset) { index, stage in
                        Button("Stage \(index + 1)") {
                            activeStageIndex = index
                            rebuildStageData()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(activeStageIndex == index ? .green : .gray)
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
            .padding(.vertical, 6)
            .background(Color(red: 0.04, green: 0.04, blue: 0.05))
        }
        .onAppear {
            if let first = profileStore.profiles.first {
                selectedProfileID = first.id
                rebuildStageData()
            }
        }
    }
    
    private func rebuildStageData() {
        guard let profile = currentProfile, let stage = currentStage else { return }
        
        let activeMetric: SensorKey
        switch stage.type {
        case .pressure: activeMetric = .pressure
        case .flow:     activeMetric = .flow
        case .power:    activeMetric = .power
        }
        
        // 1. Parse Real Dynamics Points
        let rawKnots: [(x: Double, y: Double)] = stage.dynamics.points.compactMap { pt in
            guard let x = pt.x.numericValue, let y = pt.y.numericValue else { return nil }
            return (x: x, y: y)
        }
        
        let maxKnotX = rawKnots.map(\.x).max() ?? 0.0
        let timeTriggerVal = stage.exitTriggers?.first(where: { $0.type == .time })?.value.numericValue ?? 0.0
        let stageHorizon = max(maxKnotX, timeTriggerVal, 10.0)
        
        var points: [PlanPoint] = []
        if rawKnots.isEmpty {
            points = [PlanPoint(x: 0, y: 0), PlanPoint(x: stageHorizon, y: 0)]
        } else if rawKnots.count == 1 {
            let singleY = rawKnots[0].y
            points = [PlanPoint(x: 0, y: singleY), PlanPoint(x: stageHorizon, y: singleY)]
        } else {
            for knot in rawKnots {
                points.append(PlanPoint(x: knot.x, y: knot.y))
            }
            if let lastKnot = rawKnots.last, lastKnot.x < stageHorizon {
                points.append(PlanPoint(x: stageHorizon, y: lastKnot.y))
            }
        }
        self.planCurve = points
        
        // 2. Extract Real Limits
        var activeLimitStatus: GuardrailStatus? = nil
        if let limit = stage.limits?.first, let limitVal = limit.value.numericValue {
            let limitMetric: SensorKey = (limit.type == .pressure) ? .pressure : .flow
            let simActual = (limitMetric == .flow) ? 1.2 : 3.5
            activeLimitStatus = GuardrailStatus(
                metric: limitMetric,
                limitValue: limitVal,
                actualValue: simActual,
                isBreached: simActual > limitVal
            )
        }
        
        // 3. Extract Real Exit Triggers
        var triggers: [ExitTriggerProgressItem] = []
        if let exitTriggers = stage.exitTriggers, !exitTriggers.isEmpty {
            for (idx, trigger) in exitTriggers.enumerated() {
                let targetNum = trigger.value.numericValue ?? 5.0
                let icon: String
                let unit: String
                let simActual: Double
                let sensorKey: SensorKey
                
                switch trigger.type {
                case .time:
                    sensorKey = .time
                    icon = "clock.fill"
                    unit = "s"
                    simActual = targetNum * 0.65
                case .weight:
                    sensorKey = .weight
                    icon = "scalemass.fill"
                    unit = "g"
                    simActual = targetNum * 0.25
                case .pressure:
                    sensorKey = .pressure
                    icon = "gauge.with.dots.needle.bottom.50percent"
                    unit = "bar"
                    simActual = targetNum * 0.85
                case .flow:
                    sensorKey = .flow
                    icon = "water.waves"
                    unit = "mL/s"
                    simActual = targetNum * 0.5
                default:
                    sensorKey = .power
                    icon = "bolt.fill"
                    unit = "%"
                    simActual = targetNum * 0.5
                }
                
                let progress = targetNum > 0 ? min(1.0, simActual / targetNum) : 0.0
                triggers.append(ExitTriggerProgressItem(
                    sensorKey: sensorKey,
                    icon: icon,
                    label: trigger.type.displayName,
                    currentString: String(format: "%.1f%@", simActual, unit),
                    targetString: String(format: "%.1f%@", targetNum, unit),
                    progress: progress,
                    isLeading: idx == 0
                ))
            }
        } else {
            triggers.append(ExitTriggerProgressItem(
                sensorKey: .weight,
                icon: "scalemass.fill",
                label: "Final Weight Cutoff",
                currentString: String(format: "%.1fg", profile.finalWeight * 0.70),
                targetString: String(format: "%.1fg", profile.finalWeight),
                progress: 0.70,
                isLeading: true
            ))
        }
        self.exitTriggerItems = triggers
        
        // 4. Build Carousel Items
        self.stagePills = profile.stages.enumerated().map { index, s in
            let icon: String
            switch s.type {
            case .pressure: icon = "gauge.with.dots.needle.bottom.50percent"
            case .flow:     icon = "water.waves"
            case .power:    icon = "bolt.fill"
            }
            let state: StagePillState = index < activeStageIndex ? .completed : (index == activeStageIndex ? .active : .upcoming)
            return StagePillItem(stageNumber: index + 1, title: s.name, icon: icon, state: state)
        }
        
        // 5. Build Simulated Actual Telemetry Trail
        let simElapsed = min(stageHorizon * 0.55, 12.0)
        let targetAtNow = evaluateTarget(at: simElapsed, knots: rawKnots, horizon: stageHorizon)
        let actualAtNow = max(0.0, targetAtNow - 0.25)
        
        self.actualHistory = [
            ActualPoint(x: 0.0, y: max(0.0, (rawKnots.first?.y ?? 2.0) * 0.3)),
            ActualPoint(x: simElapsed * 0.5, y: targetAtNow * 0.75),
            ActualPoint(x: simElapsed, y: actualAtNow)
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
    
    private func evaluateTarget(at time: Double, knots: [(x: Double, y: Double)], horizon: Double) -> Double {
        guard let first = knots.first else { return 0.0 }
        if knots.count == 1 || time <= first.x { return first.y }
        if let last = knots.last, time >= last.x { return last.y }
        
        for i in 0..<(knots.count - 1) {
            let p0 = knots[i]
            let p1 = knots[i + 1]
            if time >= p0.x && time <= p1.x {
                let ratio = (time - p0.x) / (p1.x - p0.x)
                return p0.y + ratio * (p1.y - p0.x)
            }
        }
        return first.y
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

#Preview {
    BaristaHUDSimulatorView()
        .previewInterfaceOrientation(.landscapeLeft)
}
