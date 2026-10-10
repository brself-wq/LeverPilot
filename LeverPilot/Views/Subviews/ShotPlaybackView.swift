//
//  ShotPlaybackView.swift
//  LeverPilot
//

import SwiftUI
import MeticulousProfile

public struct ShotPlaybackView: View {
    let scenario: ShotRecord
    @Bindable var controller: ShotPlaybackController
    
    // MARK: - Drag / Movable State
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    
    public init(scenario: ShotRecord, controller: ShotPlaybackController) {
        self.scenario = scenario
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 5) {
            // Drag Handle Capsule
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 32, height: 4)
                .padding(.top, 4)
            
            // 1. Telemetry Scrubber Bar
            if scenario.samples.count > 1 {
                HStack(spacing: 8) {
                    Text(String(format: "%02d:%04.1fs", Int(controller.currentTimestamp) / 60, controller.currentTimestamp.truncatingRemainder(dividingBy: 60)))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.telemetryWeight)
                        .frame(width: 52, alignment: .leading)
                    
                    Slider(
                        value: Binding(
                            get: { Double(controller.currentSampleIndex) },
                            set: { controller.seek(to: Int($0)) }
                        ),
                        in: 0...Double(scenario.samples.count - 1),
                        step: 1.0
                    )
                    .tint(.cyan)
                    
                    Text(String(format: "%02d:%04.1fs", Int(scenario.duration) / 60, scenario.duration.truncatingRemainder(dividingBy: 60)))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.horizontal, 12)
            }
            
            // 2. Compact Floating Transport Deck
            HStack(spacing: 8) {
                // Reset to beginning
                Button(action: { controller.reset() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Theme.Surface.control)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.Border.glassGradient, lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                // Step Backward (-0.1s)
                Button(action: { controller.stepBackward() }) {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Theme.Surface.control)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.Border.glassGradient, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canStepBackward)
                .opacity(controller.canStepBackward ? 1.0 : 0.4)
                
                // Play / Pause Primary Button
                Button(action: { controller.togglePlayback() }) {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(controller.isPlaying ? Color.orange : Color.blue)
                        .clipShape(Circle())
                        .shadow(color: (controller.isPlaying ? Color.orange : Color.blue).opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                
                // Step Forward (+0.1s)
                Button(action: { controller.stepForward() }) {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Theme.Surface.control)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.Border.glassGradient, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canStepForward)
                .opacity(controller.canStepForward ? 1.0 : 0.4)
                
                // Playback Speed Multiplier Pill
                Button(action: { controller.cycleSpeed() }) {
                    Text(controller.speedLabel)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(controller.playbackSpeedMultiplier != 1.0 ? Color.cyan : Color.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Theme.Surface.control)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Border.glassGradient, lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Telemetry Stage & Tick Status
                HStack(spacing: 6) {
                    Text("STAGE \(controller.activeStageIndex + 1)")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    
                    Text("\(controller.currentSampleIndex)/\(scenario.samples.count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 4)
        .background(Theme.Surface.overlay)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 14, y: 5)
        // Freeform Movable Offset & Gesture
        .offset(
            x: accumulatedOffset.width + dragOffset.width,
            y: accumulatedOffset.height + dragOffset.height
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    accumulatedOffset.width += value.translation.width
                    accumulatedOffset.height += value.translation.height
                    dragOffset = .zero
                }
        )
    }
}
