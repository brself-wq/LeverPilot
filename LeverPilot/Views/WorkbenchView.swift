//
//  WorkbenchView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

public struct WorkbenchView: View {
    @State private var scenarioStore = ScenarioStore()
    @State private var playbackEngine = ShotPlaybackController()
    @State private var selectedScenarioID: String = ""
    @State private var simulateAlarm: Bool = false
    
    private var currentScenario: ShotRecord? {
        scenarioStore.scenarios.first(where: { $0.id == selectedScenarioID })
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Production Barista HUD Presentation View
            BaristaHUDView(
                frame: playbackEngine.guidanceFrame,
                planCurve: playbackEngine.planCurve,
                actualHistory: playbackEngine.actualHistory,
                exitTriggerItems: playbackEngine.exitTriggerItems,
                stagePills: playbackEngine.stagePills,
                domainLabel: playbackEngine.domainLabel,
                finalWeightTarget: playbackEngine.resolvedTargetWeight,
                nominalDuration: playbackEngine.nominalDuration,
                isAlarmActive: simulateAlarm || playbackEngine.guidanceFrame.isAlarmActive,
                elapsedTime: playbackEngine.currentTimestamp,
                stageTime: max(0.0, playbackEngine.currentTimestamp - playbackEngine.stageBaseline.startTime),
                actualWeight: playbackEngine.currentSample?.weight ?? 0.0,
                approachProgress: playbackEngine.approachProgress
            )
            
            // Debrief Control Dock
            ShotPlaybackView(
                scenarios: scenarioStore.scenarios,
                selectedScenario: currentScenario,
                playbackEngine: playbackEngine,
                simulateAlarm: $simulateAlarm,
                onSelectScenario: selectScenario
            )
        }
        .onAppear {
            if selectedScenarioID.isEmpty, let first = scenarioStore.scenarios.first {
                selectScenario(first)
            }
        }
    }
    
    private func selectScenario(_ scenario: ShotRecord) {
        selectedScenarioID = scenario.id
        playbackEngine.load(scenario: scenario)
    }
}

#Preview(traits: .landscapeLeft) {
    WorkbenchView()
}
