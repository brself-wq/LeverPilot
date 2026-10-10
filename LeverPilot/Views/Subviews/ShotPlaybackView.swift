//
//  SimulatorControlDockView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

public struct ShotPlaybackView: View {
    let scenarios: [ShotRecord]
    let selectedScenario: ShotRecord?
    let onSelectScenario: (ShotRecord) -> Void
    
    @Bindable var playbackEngine: ShotPlaybackController
    @Binding var simulateAlarm: Bool
    
    public init(
        scenarios: [ShotRecord],
        selectedScenario: ShotRecord?,
        playbackEngine: ShotPlaybackController,
        simulateAlarm: Binding<Bool>,
        onSelectScenario: @escaping (ShotRecord) -> Void
    ) {
        self.scenarios = scenarios
        self.selectedScenario = selectedScenario
        self.playbackEngine = playbackEngine
        self._simulateAlarm = simulateAlarm
        self.onSelectScenario = onSelectScenario
    }
    
    private var hasScenario: Bool {
        selectedScenario != nil
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            // Scrubber Bar
            if let scenario = selectedScenario, scenario.samples.count > 1 {
                HStack(spacing: 8) {
                    Text(String(format: "%.1fs", playbackEngine.currentTimestamp))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    
                    Slider(
                        value: Binding(
                            get: { Double(playbackEngine.currentSampleIndex) },
                            set: { playbackEngine.seek(to: Int($0)) }
                        ),
                        in: 0...Double(scenario.samples.count - 1),
                        step: 1.0
                    )
                    .tint(.cyan)
                    
                    Text(String(format: "%.1fs", scenario.duration))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 12)
            }
            
            // Transport Dock
            HStack(spacing: 10) {
                // Shot Selector Menu
                Menu {
                    ForEach(scenarios) { scenario in
                        Button(action: { onSelectScenario(scenario) }) {
                            Text("\(scenario.profileName) (\(formattedDate(scenario.timestamp)))")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(selectedScenario?.profileName.isEmpty == false ? selectedScenario!.profileName : "Select Shot Log")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(hasScenario ? 0.12 : 0.06))
                    .foregroundStyle(hasScenario ? .primary : .secondary)
                    .cornerRadius(6)
                }
                .frame(maxWidth: 240)
                
                Divider().frame(height: 16)
                
                // Transport Buttons
                HStack(spacing: 6) {
                    // Play / Pause
                    Button(action: { playbackEngine.togglePlayback() }) {
                        Label(
                            playbackEngine.isPlaying ? "Pause" : "Play",
                            systemImage: playbackEngine.isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 11, weight: .bold))
                        .frame(minWidth: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(playbackEngine.isPlaying ? .orange : .blue)
                    .disabled(!hasScenario)
                    
                    // Step Backward (-0.1s)
                    Button(action: { playbackEngine.stepBackward() }) {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasScenario || !playbackEngine.canStepBackward)
                    
                    // Step Forward (+0.1s)
                    Button(action: { playbackEngine.stepForward() }) {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasScenario || !playbackEngine.canStepForward)
                    
                    // Reset to Beginning
                    Button(action: { playbackEngine.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasScenario)
                    
                    // Speed Multiplier
                    Button(action: { playbackEngine.cycleSpeed() }) {
                        Text(playbackEngine.speedLabel)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .frame(minWidth: 38)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(playbackEngine.playbackSpeedMultiplier != 1.0 ? .cyan : .gray)
                }
                
                // Tick Counter
                Text(playbackEngine.tickStatusString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(hasScenario ? .secondary : .tertiary)
                
                Spacer()
                
                // Alarm Toggle
                Toggle("Alarm", isOn: $simulateAlarm)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2)
                    .tint(.red)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .background(Color(red: 0.04, green: 0.04, blue: 0.05))
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
