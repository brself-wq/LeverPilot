//
//  ProfileConsoleView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile

// MARK: - App-side Conformance (Does not touch MeticulousProfile library)
extension Profile: @retroactive Identifiable {}

public struct ProfileConsoleView: View {
    let profiles: [Profile]
    let onSelectProfile: (Profile) -> Void
    let onCustomizeProfile: ((Profile) -> Void)?
    
    @AppStorage("lastSelectedProfileID") private var lastSelectedProfileID: String = ""
    
    @State private var activeIndex: Int = 0
    @State private var knobRotation: Double = 0.0
    @State private var dragAccumulator: Double = 0.0
    @State private var searchFilter: String = ""
    
    // Active Tweak Modal State
    @State private var profileToCustomize: Profile?
    
    public init(
        profiles: [Profile],
        onSelectProfile: @escaping (Profile) -> Void,
        onCustomizeProfile: ((Profile) -> Void)? = nil
    ) {
        self.profiles = profiles
        self.onSelectProfile = onSelectProfile
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
    
    // MARK: - Stubbed Dose Store Lookup
    private func doseWeight(for profile: Profile) -> Double {
        // Placeholder for future ProfileStore / DoseStore lookup
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
                    // 1. Top Bar: Search & Index Readout
                    consoleTopBar
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                    
                    Spacer(minLength: 12)
                    
                    // 2. Extracted Centered Hero Dossier
                    if let profile = activeProfile {
                        ProfileHeroDossierView(
                            profile: profile,
                            accentColor: accentColor,
                            dose: doseWeight(for: profile),
                            onCustomize: {
                                profileToCustomize = profile
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
                    
                    // 3. Extracted Hardware Rotary Encoder Deck
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
    
    // MARK: - Rotary Logic & Gestures
    
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
    
    // MARK: - Top Console Bar
    
    private var consoleTopBar: some View {
        HStack(spacing: 16) {
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                TextField("Search recipe name or author...", text: $searchFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 220)
                
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
