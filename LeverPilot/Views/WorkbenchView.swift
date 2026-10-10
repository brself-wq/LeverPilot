//
//  WorkbenchView.swift
//  LeverPilot
//

import SwiftUI
import Charts
import MeticulousProfile

@MainActor
public struct WorkbenchView: View {
    let scenarioStore: ScenarioStore
    
    @State private var controller = ShotPlaybackController()
    @State private var selectedShotID: String? = nil
    @State private var isPlayingBack: Bool = false
    
    public init(scenarioStore: ScenarioStore) {
        self.scenarioStore = scenarioStore
    }
    
    private var shots: [ShotRecord] {
        scenarioStore.scenarios
    }
    
    private var mountedShot: ShotRecord? {
        if let id = selectedShotID, let found = shots.first(where: { $0.id == id }) {
            return found
        }
        return shots.first
    }
    
    public var body: some View {
        ZStack {
            Color.appCanvas
                .ignoresSafeArea()
            
            // STAGE 1: Forensic Lab & Toolchain Rack
            VStack(spacing: 0) {
                labHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                Divider().background(Color.appBorderSubtle)
                
                if shots.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            // 1. Mounted Subject Shelf
                            mountedSubjectSection
                            
                            // 2. The Toolchain Pipeline Deck
                            toolchainPipelineSection
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                    }
                }
            }
            .opacity(isPlayingBack ? 0 : 1)
            
            // STAGE 2: Full Cockpit Replay Overlay
            if isPlayingBack, let shot = mountedShot {
                cockpitPlaybackOverlay(for: shot)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onAppear {
            if selectedShotID == nil {
                selectedShotID = shots.first?.id
            }
        }
    }
    
    // MARK: - Header
    
    private var labHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.cyan)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("WORKBENCH / FORENSIC LAB")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Mount an extraction artifact to run telemetry playback and diagnostic pipelines.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let count = shots.count as Int?, count > 0 {
                Text("\(count) ARTIFACTS AVAILABLE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04), in: Capsule())
            }
        }
    }
    
    // MARK: - Section 1: Mounted Subject Shelf (Horizontal Artifact Carousel)
    
    private var mountedSubjectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MOUNTED ARTIFACT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let shot = mountedShot {
                    Text("PULLED \(formattedDate(shot.timestamp).uppercased())")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shots) { shot in
                        artifactSpecimenCard(shot: shot, isSelected: shot.id == mountedShot?.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedShotID = shot.id
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func artifactSpecimenCard(shot: ShotRecord, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Profile Art or Fallback Glyphs
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.cyan : .secondary)
            }
            
            // Specimen Identification
            VStack(alignment: .leading, spacing: 3) {
                Text(shot.profileName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(String(format: "%.1fg", shot.finalWeight))
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.telemetryWeight)
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 8))
                    
                    Text(String(format: "%02d:%02ds", Int(shot.duration) / 60, Int(shot.duration) % 60))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, alignment: .leading)
            
            // Micro Sparkline Stamp
            microSparkline(for: shot)
                .frame(width: 80, height: 32)
        }
        .padding(10)
        .background(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .strokeBorder(isSelected ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
    }
    
    private func microSparkline(for shot: ShotRecord) -> some View {
        // Stride samples so 300+ ticks render as a smooth vector curve
        let displaySamples = shot.samples.enumerated().compactMap { index, sample in
            index % 2 == 0 ? sample : nil
        }
        
        return Chart {
            ForEach(displaySamples) { sample in
                // 1. Subtle gradient fill under the pressure curve
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Pressure", sample.pressure)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.telemetryPressure.opacity(0.35), Color.telemetryPressure.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
                
                // 2. Crisp telemetry pressure stroke
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Pressure", sample.pressure)
                )
                .foregroundStyle(Color.telemetryPressure)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...12)
    }
    
    // MARK: - Section 2: The Toolchain Pipeline Deck
    
    private var toolchainPipelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORENSIC TOOLCHAIN PIPELINES")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                // Tool 1: ACTIVE - Cockpit Playback
                cockpitReplayToolCard
                
                // Tool 2: ROADMAP - AI Shot Forensics
                roadmapToolCard(
                    icon: "sparkles",
                    title: "AI Extraction Forensics",
                    subtitle: "Hydraulic puck stability & channeling detection.",
                    badge: "ROADMAP"
                )
                
                // Tool 3: ROADMAP - Visualizer Export
                roadmapToolCard(
                    icon: "square.and.arrow.up.fill",
                    title: "Visualizer & Cloud Export",
                    subtitle: "Publish extraction telemetry to Visualizer.coffee.",
                    badge: "ROADMAP"
                )
                
                // Tool 4: ROADMAP - Recipe Tuner
                roadmapToolCard(
                    icon: "slider.horizontal.3",
                    title: "Recipe Tuner & Feedback",
                    subtitle: "Refine stage transition triggers based on puck decay.",
                    badge: "ROADMAP"
                )
            }
        }
    }
    
    // MARK: - Active Tool 1 Card: Cockpit Replay
    
    private var cockpitReplayToolCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cockpit Replay")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                    Text("Sub-second HUD flight review")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("OPERATIONAL")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
            
            Text("Step through 10 Hz pressure & flow vectors, overlay target corridors, and evaluate barista steering accuracy against OEPF dynamic ramps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button(action: {
                if let shot = mountedShot {
                    startPlayback(for: shot)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Launch Cockpit Replay")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                .shadow(color: Color.blue.opacity(0.4), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(mountedShot == nil)
        }
        .padding(18)
        .frame(minHeight: 180)
        .background(Theme.Surface.overlay)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .strokeBorder(Color.blue.opacity(0.4), lineWidth: 1.5)
        )
    }
    
    // MARK: - Roadmap Tool Card Template
    
    private func roadmapToolCard(icon: String, title: String, subtitle: String, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(badge)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
            
            Text("Tool module offline. Reserved pipeline endpoint for the post-flight forensics and profile calibration suite.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            HStack {
                Text("Pipeline Staged")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.6))
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.controlRadius)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(18)
        .frame(minHeight: 180)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(0.65)
    }
    
    // MARK: - Stage 2: Cockpit Playback Overlay
    
    private func cockpitPlaybackOverlay(for shot: ShotRecord) -> some View {
        ZStack(alignment: .bottom) {
            BaristaHUDView(
                frame: controller.guidanceFrame,
                planCurve: controller.planCurve,
                actualHistory: controller.actualHistory,
                exitTriggerItems: controller.exitTriggerItems,
                stagePills: controller.stagePills,
                domainLabel: controller.domainLabel,
                finalWeightTarget: controller.resolvedTargetWeight,
                nominalDuration: controller.nominalDuration,
                windowSpan: StageDynamicsChartView.slidingWindowSpan,
                isAlarmActive: controller.guidanceFrame.isAlarmActive,
                elapsedTime: controller.currentTimestamp,
                stageTime: max(0.0, controller.currentTimestamp - controller.stageBaseline.startTime),
                actualWeight: controller.currentSample?.weight ?? 0.0,
                approachProgress: controller.approachProgress
            )
            
            // Movable, Compact Floating Transport Dock
            ShotPlaybackView(scenario: shot, controller: controller)
                .frame(maxWidth: 540)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { exitPlayback() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Theme.Surface.control, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(5)
        }
    }
    
    // MARK: - Actions
    
    private func startPlayback(for shot: ShotRecord) {
        controller.load(scenario: shot)
        withAnimation(.easeInOut(duration: 0.25)) {
            isPlayingBack = true
        }
    }
    
    private func exitPlayback() {
        controller.stop()
        withAnimation(.easeInOut(duration: 0.2)) {
            isPlayingBack = false
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Recorded Shot Artifacts")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Pull an espresso shot or import from Beanconqueror to populate the lab.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
