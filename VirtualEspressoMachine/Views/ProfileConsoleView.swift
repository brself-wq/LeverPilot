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
    let onArm: (Profile, ShotRecord?) -> Void
    
    @AppStorage("lastSelectedProfileID") private var lastSelectedProfileID: String = ""
    
    @State private var activeIndex: Int = 0
    @State private var knobRotation: Double = 0.0
    @State private var dragAccumulator: Double = 0.0
    @State private var searchFilter: String = ""
    
    // In-memory working copy isolated from ProfileStore
    @State private var sessionProfile: Profile? = nil
    @State private var sessionDose: Double = 18.0
    
    // Debug desk stimulation: primed scenario bypassing physical BLE
    @State private var primedScenario: ShotRecord? = nil
    
    // Active Configure Modal State
    @State private var isShowingOverridesSheet: Bool = false
    
    // Pre-Flight Diagnostic Alert State
    @State private var isShowingPreFlightAlert: Bool = false
    @State private var preFlightIssues: [PreFlightIssue] = []
    
    public init(
        profiles: [Profile],
        bleManager: EspressoBLEManager,
        scenarioStore: ScenarioStore,
        onArm: @escaping (Profile, ShotRecord?) -> Void
    ) {
        self.profiles = profiles
        self.bleManager = bleManager
        self.scenarioStore = scenarioStore
        self.onArm = onArm
    }
    
    private var filteredProfiles: [Profile] {
        let query = searchFilter.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.author.localizedCaseInsensitiveContains(query)
        }
    }
    
    private var catalogProfile: Profile? {
        guard !filteredProfiles.isEmpty else { return nil }
        let safeIndex = min(max(activeIndex, 0), filteredProfiles.count - 1)
        return filteredProfiles[safeIndex]
    }
    
    private var accentColor: Color {
        Color(hex: sessionProfile?.display?.accentColor)
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06)
                .ignoresSafeArea()
            
            if profiles.isEmpty {
                emptyCatalogView
            } else {
                VStack(spacing: 0) {
                    // 1. Top Bar: Hardware/Debug (Left) vs Search/Count (Right)
                    consoleTopBar
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                    
                    Spacer(minLength: 12)
                    
                    // 2. Centered Hero Dossier (Renders the in-memory session copy)
                    if let profile = sessionProfile {
                        ProfileHeroDossierView(
                            profile: profile,
                            accentColor: accentColor,
                            dose: sessionDose,
                            onCustomize: {
                                isShowingOverridesSheet = true
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
                        isDisabled: sessionProfile == nil,
                        onTurnLeft: { stepProfile(by: -1) },
                        onTurnRight: { stepProfile(by: 1) },
                        onPushCenter: handleCenterPush,
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
                Button("") { handleCenterPush() }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        // Configure Modal Sheet: Modifies sessionProfile directly
        .sheet(isPresented: $isShowingOverridesSheet) {
            if let profile = sessionProfile {
                ProfileVariableOverridesView(
                    profile: profile,
                    initialDose: sessionDose,
                    onApply: { modified, newDose in
                        self.sessionProfile = modified
                        self.sessionDose = newDose
                        self.isShowingOverridesSheet = false
                    },
                    onCancel: {
                        self.isShowingOverridesSheet = false
                    }
                )
            }
        }
        // Pre-Flight Diagnostic Checklist Alert
        .alert("Cannot Arm Machine", isPresented: $isShowingPreFlightAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(formattedPreFlightMessage)
        }
        .onAppear {
            if sessionProfile == nil {
                restoreLastSelection()
                syncSessionProfile()
            }
        }
        .onChange(of: searchFilter) { _, _ in
            activeIndex = 0
            syncSessionProfile()
        }
    }
    
    // MARK: - Pre-Flight Arming Action
    
    private func handleCenterPush() {
        guard let profile = sessionProfile else { return }
        
        let issues = PreFlightValidator.evaluate(
            profile: profile,
            bleManager: bleManager,
            primedScenario: primedScenario
        )
        
        if issues.isEmpty {
            lastSelectedProfileID = profile.id
            onArm(profile, primedScenario)
        } else {
            self.preFlightIssues = issues
            self.isShowingPreFlightAlert = true
        }
    }
    
    private var formattedPreFlightMessage: String {
        let bullets = preFlightIssues.map { "• \($0.description)" }.joined(separator: "\n")
        return "The machine cannot transition to armed state until the following are resolved:\n\n\(bullets)"
    }
    
    // MARK: - Top Console Bar
    
    private var consoleTopBar: some View {
        HStack(spacing: 12) {
            QuickHardwareDockView(bleManager: bleManager)
            
            #if DEBUG
            debugBenchMenu
            #endif
            
            Spacer()
            
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
            Section("Telemetry Source Override") {
                Button {
                    primedScenario = nil
                } label: {
                    HStack {
                        Text("Live Bluetooth (Hardware)")
                        if primedScenario == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(scenarioStore.mockScenarios, id: \.id) { scenario in
                    Button {
                        primedScenario = scenario
                    } label: {
                        HStack {
                            Text(scenario.id)
                            if primedScenario?.id == scenario.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: primedScenario != nil ? "bolt.horizontal.fill" : "ladybug.fill")
                    .font(.system(size: 9))
                Text(primedScenario != nil ? "SIM: \(primedScenario!.id.prefix(8))" : "DEBUG")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
            }
            .foregroundStyle(primedScenario != nil ? .cyan : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((primedScenario != nil ? Color.cyan : Color.orange).opacity(0.15))
            .cornerRadius(6)
        }
    }
    #endif
    
    // MARK: - Profile Navigation & Session Synchronization
    
    private func stepProfile(by delta: Int) {
        guard !filteredProfiles.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let next = (activeIndex + delta) % filteredProfiles.count
            activeIndex = next < 0 ? filteredProfiles.count - 1 : next
            knobRotation += Double(delta) * 30.0
            syncSessionProfile()
        }
    }
    
    private func syncSessionProfile() {
        if let current = catalogProfile {
            self.sessionProfile = current
            self.sessionDose = 18.0
            self.lastSelectedProfileID = current.id
        } else {
            self.sessionProfile = nil
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
