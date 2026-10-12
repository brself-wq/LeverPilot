//
//  QuickHardwareDockView.swift
//  LeverPilot
//

import SwiftUI
import EspressoBLE

public struct QuickHardwareDockView: View {
    @Bindable var bleManager: EspressoBLEManager
    @ObservedObject private var transponder = MeticulousTransponder.shared
    @State private var showingSettingsSheet: Bool = false
    
    public init(bleManager: EspressoBLEManager) {
        self.bleManager = bleManager
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            scalePill
            pressurePill
            
            Button(action: { showingSettingsSheet = true }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isAnyConnected ? .green : .secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            if transponder.state != .disabled {
                meticulousServerPill
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            HardwareSettingsSheet(bleManager: bleManager)
        }
    }
    
    private var isAnyConnected: Bool {
        bleManager.slots[.scale]?.isConnected == true || bleManager.slots[.pressure]?.isConnected == true
    }
    
    // MARK: - Scale Status Pill
    
    private var scalePill: some View {
        let slot = bleManager.slots[.scale]
        let isConnected = slot?.isConnected == true
        let weight = slot?.lastReading?.weightGrams
        
        return HStack(spacing: 6) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.telemetryWeight)
            
            if isConnected, let w = weight {
                Text(String(format: "%.1fg", w))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                Text("NO SCALE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - Pressure Status Pill
    
    private var pressurePill: some View {
        let slot = bleManager.slots[.pressure]
        let isConnected = slot?.isConnected == true
        let pressure = slot?.lastReading?.pressureBar
        
        return HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 10))
                .foregroundStyle(Color.telemetryPressure)
            
            if isConnected, let p = pressure {
                Text(String(format: "%.1f bar", p))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                Text("NO PRESSURE DEVICE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - Meticulous Emulation Server Pill
    
    private var meticulousServerPill: some View {
        let isActive = transponder.state == .active
        let pipColor = isActive
            ? Color(red: 0.18, green: 0.80, blue: 0.44)
            : Color.white.opacity(0.55)

        return ZStack {
            MeticulousGlyph(includePeriod: false)
                .fill(Color.white.opacity(isActive ? 0.98 : 0.70))
                .frame(width: 13, height: 13)
            
            Circle()
                .fill(pipColor)
                .frame(width: 3.5, height: 3.5)
                .offset(x: 4.8, y: 4.8)
                .shadow(color: isActive ? pipColor.opacity(0.8) : Color.clear, radius: isActive ? 2.5 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
        .animation(.easeInOut(duration: 0.25), value: transponder.state)
        .accessibilityLabel("Meticulous Transponder: \(isActive ? "Active" : "Standby")")
    }
}
