//
//  ContentView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile

struct ContentView: View {
    @State private var machine = MockVirtualEspressoMachine()
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Machine Status Banner
                Section("Machine State") {
                    HStack {
                        Text("Current State:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(machine.state.rawValue.uppercased())
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundStyle(machine.state.isExtracting ? .green : .blue)
                    }
                    
                    if let active = machine.activeProfile {
                        HStack {
                            Text("Active Recipe:")
                            Spacer()
                            Text(active.name)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Target Yield:")
                            Spacer()
                            Text(String(format: "%.1f g", active.finalWeight))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Live extraction readouts
                    if machine.state.isExtracting || machine.state == .shotEnded {
                        HStack {
                            Text("Elapsed: \(String(format: "%.1fs", machine.currentFrame.timestamp))")
                            Spacer()
                            Text("P: \(String(format: "%.1f bar", machine.currentFrame[.pressure] ?? 0.0))")
                            Spacer()
                            Text("W: \(String(format: "%.1f g", machine.currentFrame[.weight] ?? 0.0))")
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                    
                    // Control Buttons
                    HStack {
                        if machine.state == .profileSelected || machine.state == .ready {
                            Button("Set Ready") { machine.setToShotReady() }
                                .buttonStyle(.bordered)
                        } else if machine.state == .shotReady {
                            Button("Start Extraction") { machine.startExtraction() }
                                .buttonStyle(.borderedProminent)
                        } else if machine.state.isExtracting {
                            Button("Abort", role: .destructive) { machine.abort() }
                                .buttonStyle(.bordered)
                        } else if machine.state == .shotEnded {
                            Button("Clean & Reset") { machine.setToCleanupComplete() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 4)
                }
                
                // MARK: - Bundled Profiles List
                Section("Bundled Profiles (\(machine.profileStore.profiles.count))") {
                    if machine.profileStore.profiles.isEmpty {
                        Text("No profiles found in bundle.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(machine.profileStore.profiles, id: \.id) { profile in
                            Button(action: {
                                machine.selectProfile(profile)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("\(profile.stages.count) stages • \(String(format: "%.0f°C", profile.temperature)) • \(String(format: "%.0fg", profile.finalWeight))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if machine.activeProfile?.id == profile.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Virtual Espresso")
        }
    }
}

#Preview {
    ContentView()
}
