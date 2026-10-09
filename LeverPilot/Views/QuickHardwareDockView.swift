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
            // 1. Scale Quick Pill
            scalePill
            
            // 2. Pressure Quick Pill
            pressurePill
            
            // 3. Hardware Manager Antenna Button (Sole trigger for pairing sheet)
            Button(action: { showingSettingsSheet = true }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isAnyConnected ? .green : .secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            // 4. Meticulous Machine Interface Status (Trailing Position)
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
        HStack(spacing: 5) {
            // Meticulous 'M.' Vector Emblem
            ZStack {
                MeticulousGlyph()
                    .fill(Color.white.opacity(transponder.state == .active ? 0.95 : 0.45))
                    .frame(width: 13, height: 13)
                
                // Active dot illuminates in Meticulous Red (#FF1E00) on client activity
                if transponder.state == .active {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.12, blue: 0.0))
                        .frame(width: 3.5, height: 3.5)
                        .offset(x: 4.8, y: 4.8)
                }
            }
            
            Text(transponder.state == .active ? "ACTIVE" : "STANDBY")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(transponder.state == .active ? .white : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(transponder.state == .active ? 0.08 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(transponder.state == .active ? Color.white.opacity(0.20) : Color.clear, lineWidth: 1)
        )
    }
}
