//
//  LeverPilotApp.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile
import EspressoBLE
#if os(iOS)
import UIKit
#endif

@main
struct LeverPilotApp: App {
    
    // MARK: - App-Level Shared Singletons
    @State private var profileStore = ProfileStore()
    @State private var scenarioStore = ScenarioStore()
    @State private var settingsStore = SettingsStore()
    @State private var bleManager = EspressoBLEManager(savedDevices: loadSavedBLEDevices())
    @State private var coordinator = ShotCoordinator()
    @State private var activeTelemetryProvider: (any TelemetryProvider)?
    @State private var showAbortConfirmation: Bool = false
    
    // MARK: - Scene Phase & Power Management
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Root Navigation Destination
    @State private var currentDestination: AppDestination = .brew
    
    // MARK: - Active Extraction / Shot Modal Overlays
    @State private var activeExtractionProfile: Profile? = nil
    @State private var completedRecordForReview: ShotRecord? = nil
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // 1. BASE LAYER: Active Workspace
                Group {
                    switch currentDestination {
                    case .brew:
                        ProfileConsoleView(
                            profiles: profileStore.profiles,
                            bleManager: bleManager,
                            scenarioStore: scenarioStore,
                            settings: settingsStore,
                            onArm: { sessionProfile, dose, primedScenario in
                                launchShot(with: sessionProfile, dose: dose, primedScenario: primedScenario)
                            }
                        )
                    case .history:
                        ShotHistoryBrowserView(scenarioStore: scenarioStore)
                    case .settings:
                        SettingsView(settings: settingsStore)
                    case .workbench:
                        EmptyView()
                    }
                }
                .transition(.opacity)
                
                // 2. UNIVERSAL BOTTOM-LEFT HAMBURGER MENU
                VStack {
                    Spacer()
                    HStack {
                        universalHamburgerMenu
                            .padding(.leading, 28)
                            .padding(.bottom, 22)
                        Spacer()
                    }
                }
                
                // 3. EXTRACTION LAYER: Cross-Platform HUD (Visible only in flight)
                if activeExtractionProfile != nil {
                    BaristaHUDView(
                        frame: coordinator.guidanceFrame,
                        planCurve: coordinator.planCurve,
                        actualHistory: coordinator.actualHistory,
                        exitTriggerItems: coordinator.exitTriggerItems,
                        stagePills: coordinator.stagePills,
                        domainLabel: coordinator.currentStage?.dynamics.over.rawValue.capitalized ?? "Time",
                        finalWeightTarget: coordinator.resolvedTargetWeight,
                        nominalDuration: 32.0,
                        windowSpan: StageDynamicsChartView.slidingWindowSpan,
                        isAlarmActive: coordinator.isAlarmActive,
                        elapsedTime: coordinator.elapsedTime,
                        stageTime: coordinator.stageTime,
                        actualWeight: coordinator.actualWeight,
                        isScaleStale: coordinator.currentFrame.isScaleStale,
                        isPressureStale: coordinator.currentFrame.isPressureStale
                    )
                    .onChange(of: coordinator.state) { _, newState in
                        if newState == .extracting {
                            bleManager.startScaleTimer()
                        } else if newState == .shotEnded {
                            concludeShot()
                        }
                        updateIdleTimer()
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showAbortConfirmation = true
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .frame(width: 26, height: 26)
                                .background(Theme.Surface.control, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(14)
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
                
                // 4. ACCESSIBLE ABORT CONFIRMATION MODAL
                if showAbortConfirmation {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(25)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showAbortConfirmation = false
                            }
                        }
                    
                    abortConfirmationCard
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .zIndex(30)
                }
                
                // 5. POST-SHOT LAYER: Full-Screen Shot Record / Shot History
                if let shotRecord = completedRecordForReview {
                    ShotRecordView(
                        record: shotRecord,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                completedRecordForReview = nil
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(40)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                Task {
                    await MeticulousServer.shared.configure(
                        port: settingsStore.meticulousPort,
                        verbose: settingsStore.verboseServerLogging
                    )
                }
                updateIdleTimer()
            }
            .onChange(of: scenePhase) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: settingsStore.keepDisplayAwake) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: activeExtractionProfile) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: settingsStore.meticulousPort) { _, newPort in
                Task {
                    await MeticulousServer.shared.configure(
                        port: newPort,
                        verbose: settingsStore.verboseServerLogging
                    )
                }
            }
            .onChange(of: settingsStore.verboseServerLogging) { _, newVerbose in
                Task {
                    await MeticulousServer.shared.setVerboseLogging(newVerbose)
                }
            }
        }
    }
    
    // MARK: - Display Idle Timer Management
    
    private func updateIdleTimer() {
        #if os(iOS)
        let isBrewingActive = activeExtractionProfile != nil
            && (coordinator.state == .armed || coordinator.state == .extracting)
        
        let shouldKeepAwake = settingsStore.keepDisplayAwake
            && scenePhase == .active
            && isBrewingActive
        
        UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake
        #endif
    }
    
    // MARK: - Universal Hamburger Menu
    
    private var universalHamburgerMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .settings }
            } label: {
                Label(AppDestination.settings.rawValue, systemImage: AppDestination.settings.systemImage)
            }
            
            Divider()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .brew }
            } label: {
                Label(AppDestination.brew.rawValue, systemImage: AppDestination.brew.systemImage)
            }
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { currentDestination = .history }
            } label: {
                Label(AppDestination.history.rawValue, systemImage: AppDestination.history.systemImage)
            }
            
            Button {} label: {
                Label(AppDestination.workbench.rawValue, systemImage: AppDestination.workbench.systemImage)
            }
            .disabled(true)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(8)
            .background(Theme.Surface.control)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                    .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
            )
        }
        .menuOrder(.fixed)
        .menuStyle(.borderlessButton)
        .tint(.white)
        .fixedSize()
    }
    
    // MARK: - High-Contrast Abort Dialog
    
    private var abortConfirmationCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Stop Shot?")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                
                Text("The current pull will end and will not be saved to your history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                // High-Contrast Destructive Action Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAbortConfirmation = false
                    }
                    abortShot()
                }) {
                    Text("Stop Shot")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42)) // High-luminance coral
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                                .strokeBorder(Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.40), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                // Neutral Resume Action Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAbortConfirmation = false
                    }
                }) {
                    Text("Keep Brewing")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Theme.Surface.overlay)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.heroRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.heroRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 24, y: 8)
    }
    
    // MARK: - Machine Lifecycle Handlers
    
    private func launchShot(with profile: Profile, dose: Double? = nil, primedScenario: ShotRecord? = nil) {
        coordinator.configure(from: settingsStore)
        let resolvedDose = dose ?? settingsStore.defaultDose
        coordinator.arm(with: profile, dose: resolvedDose, store: profileStore)
        
        let provider: any TelemetryProvider
        if let primedScenario {
            let scenarioProvider = ScenarioTelemetryProvider(scenario: primedScenario)
            provider = scenarioProvider
            self.activeTelemetryProvider = provider
            coordinator.attach(telemetryProvider: provider)
            scenarioProvider.start()
        } else {
            bleManager.tareScale()
            bleManager.resetScaleTimer()
            
            let ble = BLETelemetryProvider(bleManager: bleManager)
            provider = ble
            self.activeTelemetryProvider = provider
            coordinator.attach(telemetryProvider: provider)
            ble.start()
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeExtractionProfile = profile
        }
    }
    
    private func concludeShot() {
        bleManager.stopScaleTimer()
        activeTelemetryProvider?.stop()
        activeTelemetryProvider = nil
        coordinator.detachTelemetry()
        
        if let finishedRecord = coordinator.completedShotRecord {
            try? scenarioStore.recordCompletedShot(finishedRecord)
            
            withAnimation(.easeInOut(duration: 0.25)) {
                activeExtractionProfile = nil
                completedRecordForReview = finishedRecord
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                activeExtractionProfile = nil
            }
        }
    }
    
    private func abortShot() {
        bleManager.stopScaleTimer()
        activeTelemetryProvider?.stop()
        activeTelemetryProvider = nil
        coordinator.detachTelemetry()
        coordinator.abort()
        
        withAnimation(.easeInOut(duration: 0.25)) {
            activeExtractionProfile = nil
        }
    }
    
    private static func loadSavedBLEDevices() -> [BLEDeviceRole: UUID] {
        var saved: [BLEDeviceRole: UUID] = [:]
        for role in BLEDeviceRole.allCases {
            if let raw = UserDefaults.standard.string(forKey: "ble.device.\(role.rawValue)"),
               let uuid = UUID(uuidString: raw) {
                saved[role] = uuid
            }
        }
        return saved
    }
}
