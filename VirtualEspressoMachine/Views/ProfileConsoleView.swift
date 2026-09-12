//
//  ProfileConsoleView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile
import EspressoBLE

// MARK: - App-side Conformance
extension Profile: @retroactive Identifiable {}

public struct ProfileConsoleView: View {
    let profiles: [Profile]
    let bleManager: EspressoBLEManager
    let scenarioStore: ScenarioStore
    let onSelectProfile: (Profile) -> Void
    let onSelectScenario: ((Profile, ShotRecord) -> Void)?
    let onCustomizeProfile: ((Profile) -> Void)?
    
    @AppStorage("lastSelectedProfileID") private var lastSelectedProfileID: String = ""
    
    @State private var activeIndex: Int = 0
    @State private var knobRotation: Double = 0.0
    @State private var dragAccumulator: Double = 0.0
    @State private var searchFilter: String = ""
    
    // Active Configure Modal State
    @State private var profileToCustomize: Profile?
    
    public init(
        profiles: [Profile],
        bleManager: EspressoBLEManager,
        scenarioStore: ScenarioStore,
        onSelectProfile: @escaping (Profile) -> Void,
        onSelectScenario: ((Profile, ShotRecord) -> Void)? = nil,
        onCustomizeProfile: ((Profile) -> Void)? = nil
    ) {
        self.profiles = profiles
        self.bleManager = bleManager
        self.scenarioStore = scenarioStore
        self.onSelectProfile = onSelectProfile
        self.onSelectScenario = onSelectScenario
        self.onCustomizeProfile = onCustomizeProfile
    }
    
    private var filteredProfiles: [Profile] {
        let query = searchFilter.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.author.localizedCaseInsensitiveContains(query)
        }
    }
    
    private var activeProfile: Profile? {
        guard !filteredProfiles.isEmpty else { return nil }
        let safeIndex = min(max(activeIndex, 0), filteredProfiles.count - 1)
        return filteredProfiles[safeIndex]
    }
    
    private var accentColor: Color {
        Color(hex: activeProfile?.display?.accentColor)
    }
    
    private func doseWeight(for profile: Profile) -> Double {
        return 18.0
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06)
                .ignoresSafeArea()
            
            if profiles.isEmpty {
                emptyCatalogView
            } else {
                VStack(spacing: 0) {
                    // 1. Top Bar: Balanced Hardware/Debug (Left) vs Search/Count (Right)
                    consoleTopBar
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                    
                    Spacer(minLength: 12)
                    
                    // 2. Centered Hero Dossier
                    if let profile = activeProfile {
                        ProfileHeroDossierView(
                            profile: profile,
                            accentColor: accentColor,
                            dose: doseWeight(for: profile),
                            onCustomize: {
                                if let onCustomizeProfile {
                                    onCustomizeProfile(profile)
                                } else {
                                    profileToCustomize = profile
                                }
                            }
                        )
                        .padding(.horizontal, 28)
                        .transition(.opacity)
                        .id(profile.id)
                    } else {
                        noSearchResultsView
                            .frame(maxWidth: 1040, minHeight: 380)
                            .padding(.horizontal, 28)
                    }
                    
                    Spacer(minLength: 16)
                    
                    // 3. Hardware Rotary Encoder Deck
                    RotaryEncoderDeck(
                        knobAngle: knobRotation,
                        accentColor: accentColor,
                        isDisabled: activeProfile == nil,
                        onTurnLeft: { stepProfile(by: -1) },
                        onTurnRight: { stepProfile(by: 1) },
                        onPushCenter: {
                            if let p = activeProfile {
                                lastSelectedProfileID = p.id
                                onSelectProfile(p)
                            }
                        },
                        onDragKnob: handleKnobDrag
                    )
                    .padding(.bottom, 22)
                }
            }
            
            // Native keyboard shortcuts
            Group {
                Button("") { stepProfile(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { stepProfile(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") {
                    if let p = activeProfile {
                        lastSelectedProfileID = p.id
                        onSelectProfile(p)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        // Configure Modal Sheet
        .sheet(item: $profileToCustomize) { profile in
            ProfileVariableOverridesView(
                profile: profile,
                initialDose: doseWeight(for: profile),
                onApply: { modified in
                    profileToCustomize = nil
                    onSelectProfile(modified)
                },
                onCancel: {
                    profileToCustomize = nil
                }
            )
        }
        .onAppear {
            restoreLastSelection()
        }
        .onChange(of: searchFilter) { _, _ in
            activeIndex = 0
        }
    }
    
    // MARK: - Top Console Bar
    
    private var consoleTopBar: some View {
        HStack(spacing: 12) {
            // LEFT: Hardware Dock + DEBUG Bench
            QuickHardwareDockView(bleManager: bleManager)
            
            #if DEBUG
            debugBenchMenu
            #endif
            
            Spacer()
            
            // RIGHT: Search Bar + Index Readout
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                TextField("Search recipe name or author...", text: $searchFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 200)
                
                if !searchFilter.isEmpty {
                    Button(action: { searchFilter = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            Text(String(format: "%02d / %02d", filteredProfiles.isEmpty ? 0 : activeIndex + 1, filteredProfiles.count))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
        }
    }
    
    // MARK: - DEBUG Bench Menu
    
    #if DEBUG
    private var debugBenchMenu: some View {
        Menu {
            Section("Scenario Playback") {
                if scenarioStore.scenarios.isEmpty {
                    Text("No Mock Scenarios Loaded")
                } else {
                    ForEach(scenarioStore.scenarios, id: \.id) { scenario in
                        Button {
                            if let profile = activeProfile {
                                onSelectScenario?(profile, scenario) ?? onSelectProfile(profile)
                            }
                        } label: {
                            Label(scenario.id, systemImage: "doc.text")
                        }
                    }
                }
            }
            
            Section("Manual Origin Trip") {
                Button {
                    if let profile = activeProfile {
                        onSelectProfile(profile)
                    }
                } label: {
                    Label("START: Launch Shot", systemImage: "play.fill")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 9))
                Text("DEBUG")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(6)
        }
    }
    #endif
    
    // MARK: - Rotary Gestures & Helpers
    
    private func stepProfile(by delta: Int) {
        guard !filteredProfiles.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let next = (activeIndex + delta) % filteredProfiles.count
            activeIndex = next < 0 ? filteredProfiles.count - 1 : next
            knobRotation += Double(delta) * 30.0
            if let p = activeProfile {
                lastSelectedProfileID = p.id
            }
        }
    }
    
    private func handleKnobDrag(translationX: Double) {
        let sensitivity = 1.2
        let stepThreshold = 32.0
        
        let delta = translationX - dragAccumulator
        knobRotation += delta * sensitivity
        dragAccumulator = translationX
        
        if abs(dragAccumulator) > stepThreshold {
            let direction = dragAccumulator > 0 ? 1 : -1
            stepProfile(by: direction)
            dragAccumulator = 0.0
        }
    }
    
    private func restoreLastSelection() {
        guard !profiles.isEmpty else { return }
        if let foundIndex = profiles.firstIndex(where: { $0.id == lastSelectedProfileID }) {
            activeIndex = foundIndex
        } else {
            activeIndex = 0
            lastSelectedProfileID = profiles[0].id
        }
    }
    
    private var noSearchResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No recipes match \"\(searchFilter)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Clear Search") {
                searchFilter = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(16)
    }
    
    private var emptyCatalogView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cup.and.saucer")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Catalog Empty")
                .font(.headline)
        }
    }
}
