//
//  BaristaHUDView.swift
//  VirtualEspressoMachine
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

// MARK: - Canonical Color Palette Extension

extension SensorKey {
    var themeColor: Color {
        switch self {
        case .pressure: return Color(red: 0.15, green: 0.68, blue: 0.38) // Forest Green
        case .flow:     return Color(red: 0.0, green: 0.68, blue: 0.94)  // Cyan / Blue
        case .power:    return Color(red: 1.0, green: 0.48, blue: 0.0)   // Electric Orange
        case .weight:   return Color(red: 0.90, green: 0.68, blue: 0.28) // Crema Caramel
        case .time:     return Color(red: 0.65, green: 0.72, blue: 0.85) // Slate Silver
        default:        return Color.secondary
        }
    }
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
    let windowSpan: Double
    let isAlarmActive: Bool
    
    // Explicit telemetry overrides with fallback to frame
    let elapsedTime: Double?
    let stageTime: Double?
    let actualWeight: Double?
    
    // Hardware Sensor Health Flags (ADR-009)
    let isScaleStale: Bool
    let isPressureStale: Bool
    
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
        windowSpan: Double = 25.0,
        isAlarmActive: Bool = false,
        elapsedTime: Double? = nil,
        stageTime: Double? = nil,
        actualWeight: Double? = nil,
        isScaleStale: Bool = false,
        isPressureStale: Bool = false
    ) {
        self.frame = frame
        self.planCurve = planCurve
        self.actualHistory = actualHistory
        self.exitTriggerItems = exitTriggerItems
        self.stagePills = stagePills
        self.domainLabel = domainLabel
        self.finalWeightTarget = finalWeightTarget
        self.nominalDuration = nominalDuration
        self.windowSpan = windowSpan
        self.isAlarmActive = isAlarmActive
        self.elapsedTime = elapsedTime
        self.stageTime = stageTime
        self.actualWeight = actualWeight
        self.isScaleStale = isScaleStale
        self.isPressureStale = isPressureStale
    }
    
    // Resolved Telemetry
    private var displayElapsedTime: Double {
        elapsedTime ?? frame.elapsedTime
    }
    
    private var displayStageTime: Double {
        stageTime ?? frame.stageTime
    }
    
    private var displayActualWeight: Double {
        actualWeight ?? frame.actualWeight
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                topRailView
                
                HStack(spacing: 10) {
                    LeftCockpitView(
                        frame: frame,
                        displayElapsedTime: displayElapsedTime,
                        displayStageTime: displayStageTime,
                        displayActualWeight: displayActualWeight,
                        finalWeightTarget: finalWeightTarget,
                        isAlarmActive: isAlarmActive
                    )
                    .frame(width: 280)
                    
                    VStack(spacing: 8) {
                        StageDynamicsChartView(
                            planCurve: planCurve,
                            actualHistory: actualHistory,
                            domainLabel: domainLabel,
                            activeMetric: frame.activeMetric,
                            windowSpan: windowSpan
                        )
                        
                        ExitTriggersPanelView(
                            exitTriggerItems: exitTriggerItems,
                            activeMetric: frame.activeMetric
                        )
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
    
    // MARK: - Top Rail: Profile Stages, Warning Chips & Macro Context
    
    @ViewBuilder
    private var topRailView: some View {
        HStack(spacing: 10) {
            if stagePills.isEmpty {
                Text("STANDBY - NO ACTIVE PROFILE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(stagePills) { pill in
                            StagePill(
                                stageNumber: pill.stageNumber,
                                title: pill.title,
                                icon: pill.icon,
                                state: pill.state
                            )
                            
                            if pill.stageNumber < stagePills.count {
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
            
            // ADR-009 Sensor Staleness Warning Chips (Fixed trailing alignment; no layout shift)
            HStack(spacing: 8) {
                if isScaleStale {
                    amberWarningChip(icon: "scalemass.fill", text: "SCALE SIGNAL LOST")
                }
                if isPressureStale {
                    amberWarningChip(icon: "gauge.with.dots.needle.bottom.50percent", text: "PRESSURE DEVICE OFFLINE")
                }
            }
            .padding(.trailing, 48) // Clearance for top-trailing abort 'xmark' button
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
    
    private func amberWarningChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.20))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(red: 0.98, green: 0.72, blue: 0.20).opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(red: 0.98, green: 0.72, blue: 0.20).opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(6)
        .transition(.opacity)
    }
}

// MARK: - StagePill

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

// MARK: - Standalone Xcode Previews (Pure In-Memory, No Sockets / No Disk I/O)

#Preview("Nominal Pull", traits: .landscapeLeft) {
    BaristaHUDView.previewInstance()
}

#Preview("Scale Signal Lost", traits: .landscapeLeft) {
    BaristaHUDView.previewInstance(isScaleStale: true)
}

#Preview("Pressure Device Offline", traits: .landscapeLeft) {
    BaristaHUDView.previewInstance(isPressureStale: true)
}

#Preview("Dual Sensor Loss", traits: .landscapeLeft) {
    BaristaHUDView.previewInstance(isScaleStale: true, isPressureStale: true)
}

private extension BaristaHUDView {
    static func previewInstance(isScaleStale: Bool = false, isPressureStale: Bool = false) -> BaristaHUDView {
        let frame = GuidanceFrame(
            stageIndex: 1,
            totalStages: 3,
            stageName: "Extraction",
            activeMetric: .pressure,
            targetValue: 9.0,
            actualValue: 8.8,
            delta: -0.2,
            elapsedTime: 14.5,
            stageTime: 6.5,
            actualWeight: 22.4,
            stageProgress: 0.65,
            yieldProgress: 0.56,
            guardrail: nil
        )
        
        let planCurve = [
            PlanPoint(x: 0.0, y: 9.0),
            PlanPoint(x: 8.0, y: 9.0),
            PlanPoint(x: 15.0, y: 7.5),
            PlanPoint(x: 25.0, y: 6.0)
        ]
        
        let actualHistory = [
            ActualPoint(x: 0.0, y: 8.0),
            ActualPoint(x: 2.0, y: 8.5),
            ActualPoint(x: 4.0, y: 9.1),
            ActualPoint(x: 6.5, y: 8.8)
        ]
        
        let exitTriggerItems = [
            ExitTriggerProgressItem(
                sensorKey: .weight,
                icon: "scalemass.fill",
                label: "Target Yield",
                currentString: "22.4g",
                targetString: "40.0g",
                progress: 0.56,
                isLeading: true
            ),
            ExitTriggerProgressItem(
                sensorKey: .time,
                icon: "clock.fill",
                label: "Stage Limit",
                currentString: "6.5s",
                targetString: "20.0s",
                progress: 0.32,
                isLeading: false
            )
        ]
        
        let stagePills = [
            StagePillItem(stageNumber: 1, title: "Pre-infusion", icon: "gauge.with.dots.needle.bottom.50percent", state: .completed),
            StagePillItem(stageNumber: 2, title: "Extraction", icon: "gauge.with.dots.needle.bottom.50percent", state: .active),
            StagePillItem(stageNumber: 3, title: "Decline", icon: "gauge.with.dots.needle.bottom.50percent", state: .upcoming)
        ]
        
        return BaristaHUDView(
            frame: frame,
            planCurve: planCurve,
            actualHistory: actualHistory,
            exitTriggerItems: exitTriggerItems,
            stagePills: stagePills,
            domainLabel: "TIME",
            finalWeightTarget: 40.0,
            nominalDuration: 32.0,
            windowSpan: 25.0,
            isAlarmActive: false,
            elapsedTime: 14.5,
            stageTime: 6.5,
            actualWeight: 22.4,
            isScaleStale: isScaleStale,
            isPressureStale: isPressureStale
        )
    }
}
