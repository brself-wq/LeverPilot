//
//  SimulatorControlDockView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/7/26.
//

import SwiftUI
import MeticulousProfile

public struct SimulatorControlDockView: View {
    // Stores & Selections
    let profiles: [Profile]
    let scenarios: [ShotRecord]
    let selectedProfile: Profile?
    let selectedScenario: ShotRecord?
    
    let onSelectProfile: (Profile) -> Void
    let onSelectScenario: (ShotRecord) -> Void
    
    // Playback Engine Binding
    @Bindable var playbackEngine: PlaybackEngine
    
    // Simulator Visual Alarm
    @Binding var simulateAlarm: Bool
    
    private var canControl: Bool {
        selectedProfile != nil && selectedScenario != nil
    }
    
    public init(
        profiles: [Profile],
        scenarios: [ShotRecord],
        selectedProfile: Profile?,
        selectedScenario: ShotRecord?,
        playbackEngine: PlaybackEngine,
        simulateAlarm: Binding<Bool>,
        onSelectProfile: @escaping (Profile) -> Void,
        onSelectScenario: @escaping (ShotRecord) -> Void
    ) {
        self.profiles = profiles
        self.scenarios = scenarios
        self.selectedProfile = selectedProfile
        self.selectedScenario = selectedScenario
        self.playbackEngine = playbackEngine
        self._simulateAlarm = simulateAlarm
        self.onSelectProfile = onSelectProfile
        self.onSelectScenario = onSelectScenario
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // 1. Profile Selector Menu (Unselected by default)
            Menu {
                ForEach(profiles, id: \.id) { profile in
                    Button(profile.name) {
                        onSelectProfile(profile)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                    Text(selectedProfile?.name ?? "Select Profile")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(selectedProfile != nil ? 0.12 : 0.06))
                .foregroundStyle(selectedProfile != nil ? .primary : .secondary)
                .cornerRadius(6)
            }
            
            // 2. Scenario Fixture Selector Menu (Clean & Compact)
            Menu {
                ForEach(scenarios, id: \.id) { scenario in
                    Button(scenario.id) {
                        onSelectScenario(scenario)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                    Text(selectedScenario?.id ?? "Select Scenario")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(selectedScenario != nil ? 0.12 : 0.06))
                .foregroundStyle(selectedScenario != nil ? .primary : .secondary)
                .cornerRadius(6)
            }
            
            Divider().frame(height: 16)
            
            // 3. Playback Transport Controls
            HStack(spacing: 6) {
                // Play / Pause
                Button(action: { playbackEngine.togglePlayback() }) {
                    Label(
                        playbackEngine.isPlaying ? "Pause" : "Play",
                        systemImage: playbackEngine.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.system(size: 11, weight: .bold))
                    .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(playbackEngine.isPlaying ? .orange : .blue)
                .disabled(!canControl)
                
                // Step Backward (-0.1s)
                Button(action: { playbackEngine.stepBackward() }) {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canControl || !playbackEngine.canStepBackward)
                
                // Step Forward (+0.1s)
                Button(action: { playbackEngine.stepForward() }) {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canControl || !playbackEngine.canStepForward)
                
                // Reset to Beginning
                Button(action: { playbackEngine.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canControl)
                
                // Speed Multiplier (0.25x -> 0.5x -> 1.0x -> 2.0x)
                Button(action: { playbackEngine.cycleSpeed() }) {
                    Text(playbackEngine.speedLabel)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .frame(minWidth: 42)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(playbackEngine.playbackSpeedMultiplier != 1.0 ? .cyan : .gray)
            }
            
            // 4. Tick Counter Display
            Text(playbackEngine.tickStatusString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(selectedScenario != nil ? .secondary : .tertiary)
            
            Spacer()
            
            // 5. Alarm Toggle
            Toggle("Alarm", isOn: $simulateAlarm)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption2)
                .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.04, green: 0.04, blue: 0.05))
    }
}
