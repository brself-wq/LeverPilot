//
//  ProfileHeroDossierView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile

public struct ProfileHeroDossierView: View {
    let profile: Profile
    let accentColor: Color
    let dose: Double
    let onCustomize: () -> Void
    var onOpenSettings: (() -> Void)? = nil
    
    public init(
        profile: Profile,
        accentColor: Color,
        dose: Double = 18.0,
        onCustomize: @escaping () -> Void,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.accentColor = accentColor
        self.dose = dose
        self.onCustomize = onCustomize
        self.onOpenSettings = onOpenSettings
    }
    
    private var tweakButtonLabel: String {
        if profile.variables.isEmpty {
            return "Tweak"
        } else {
            return "Tweak (\(profile.variables.count))"
        }
    }
    
    public var body: some View {
        ZStack {
            // LAYER 1: Dead-center Artwork Image (Pure visual, non-interactive)
            artworkJacket
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(accentColor, lineWidth: 3)
                )
                .shadow(color: accentColor.opacity(0.35), radius: 16, y: 0)
                .allowsHitTesting(false) // Prevents shadow/frame from intercepting button taps
            
            // LAYER 2: Interactive Perimeter Content
            VStack {
                // Top: Header & Settings
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let onOpenSettings {
                            Button(action: onOpenSettings) {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 9))
                                    Text("SETTINGS")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 2)
                        }
                        
                        Text(profile.name)
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text("by \(profile.author)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        if let description = profile.display?.shortDescription ?? profile.display?.description,
                           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: 380, alignment: .leading)
                        }
                    }
                    
                    Spacer()
                }
                
                Spacer()
                
                // Bottom: Specs & Tweak Button (ALWAYS visible & clickable)
                HStack(spacing: 12) {
                    specCard(icon: "cup.and.saucer.fill", title: "Dose", val: String(format: "%.1fg", dose))
                    specCard(icon: "scalemass.fill", title: "Final Weight", val: String(format: "%.1fg", profile.finalWeight))
                    specCard(icon: "thermometer.medium", title: "Temperature", val: String(format: "%.0f°C", profile.temperature))
                    
                    Spacer()
                    
                    Button(action: onCustomize) {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            Text(tweakButtonLabel)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .tint(accentColor)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 1040, minHeight: 380)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var artworkJacket: some View {
        ZStack {
            if let imagePath = profile.display?.image, !imagePath.isEmpty {
                AsyncImage(url: URL(string: imagePath)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 220, height: 220)
                            .clipped()
                    default:
                        generativeBackdrop
                    }
                }
            } else {
                generativeBackdrop
            }
        }
        .frame(width: 220, height: 220)
        .clipped()
    }
    
    private var generativeBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.85), Color(red: 0.1, green: 0.1, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "cup.and.heat.waves.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.white.opacity(0.12))
        }
    }
    
    private func specCard(icon: String, title: String, val: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(val)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}
