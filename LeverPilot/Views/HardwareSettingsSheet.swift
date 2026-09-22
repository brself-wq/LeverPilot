//
//  HardwareSettingsSheet.swift
//  LeverPilot
//

import SwiftUI
import EspressoBLE
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct HardwareSettingsSheet: View {
    @Bindable var bleManager: EspressoBLEManager
    @Environment(\.dismiss) private var dismiss
    
    public init(bleManager: EspressoBLEManager) {
        self.bleManager = bleManager
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.appOverlay)
            
            Divider().background(Theme.Border.subtle)
            
            // Radio Health Banner (if unauthorized or powered off)
            if bleManager.centralState == .unauthorized || bleManager.centralState == .poweredOff {
                radioStatusBanner
            }
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Paired Hardware Slots
                    activeSlotsSection
                    
                    // 2. Discovered Devices & Pairing
                    discoveredDevicesSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .background(Color.appCanvas)
        .onAppear {
            if bleManager.isBluetoothReady {
                bleManager.startScanning()
            }
        }
        .onDisappear {
            bleManager.stopScanning()
        }
        .onChange(of: bleManager.isBluetoothReady) { _, ready in
            if ready {
                bleManager.startScanning()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bluetooth Devices")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            Button(action: toggleScan) {
                HStack(spacing: 6) {
                    if bleManager.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                        Text("Searching...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(!bleManager.isBluetoothReady)
            
            // High-Contrast Primary Done Button
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
    }
    
    // MARK: - Radio Status Banner
    
    private var radioStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: bleManager.centralState == .unauthorized ? "lock.shield.fill" : "bolt.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bleManager.centralState == .unauthorized ? "Bluetooth Permission Required" : "Bluetooth is Turned Off")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text(bleManager.centralState == .unauthorized
                     ? "LeverPilot needs Bluetooth to connect your scale and pressure gauge."
                     : "Enable Bluetooth in Control Center or Settings to connect peripherals.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if bleManager.centralState == .unauthorized {
                Button("Open Settings") {
                    openSystemSettings()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    // MARK: - Paired Slots
    
    private var activeSlotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAIRED DEVICES")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 14) {
                deviceSlotCard(
                    role: .scale,
                    title: "SCALE",
                    icon: "scalemass.fill",
                    slot: bleManager.slots[.scale]
                )
                
                deviceSlotCard(
                    role: .pressure,
                    title: "PRESSURE DEVICE",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    slot: bleManager.slots[.pressure]
                )
            }
        }
    }
    
    @ViewBuilder
    private func deviceSlotCard(role: BLEDeviceRole, title: String, icon: String, slot: ActiveDeviceSlot?) -> some View {
        let isConnected = slot?.isConnected == true
        let isPaired = slot?.id != nil
        let themeColor: Color = role == .scale ? Color.telemetryWeight : Color.telemetryPressure
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(themeColor)
                    Text(title)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? Color.green : (isPaired ? Color.orange : Color.red.opacity(0.7)))
                        .frame(width: 6, height: 6)
                    Text(isConnected ? "CONNECTED" : (isPaired ? "SEARCHING..." : "UNPAIRED"))
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isConnected ? .green : (isPaired ? .orange : .secondary))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.pillRadius))
            }
            
            if isConnected, let slot = slot {
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.name ?? "Connected Device")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    
                    if role == .scale, let weight = slot.lastReading?.weightGrams {
                        Text(String(format: "%.1f g", weight))
                            .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(themeColor)
                    } else if role == .pressure, let pressure = slot.lastReading?.pressureBar {
                        Text(String(format: "%.2f bar", pressure))
                            .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(themeColor)
                    } else {
                        Text("--")
                            .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    if let battery = slot.smoothedBattery {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(for: battery))
                                .foregroundStyle(battery < 20 ? .red : .secondary)
                            Text("\(battery)%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if slot.rssi != 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.secondary)
                            Text("\(slot.rssi) dBm")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Divider().background(Theme.Border.hair)
                
                HStack {
                    if role == .scale {
                        Button(action: { bleManager.tareScale() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Tare")
                            }
                            .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Spacer()
                    
                    Button("Forget", role: .destructive) {
                        bleManager.forget(role: role)
                        UserDefaults.standard.removeObject(forKey: "ble.device.\(role.rawValue)")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.telemetryAlert)
                }
            } else if isPaired {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 8)
                    Text(slot?.name ?? "Saved Device")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Looking for signal... Turn device on to connect.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                }
                
                Divider().background(Theme.Border.hair)
                
                HStack {
                    Spacer()
                    Button("Forget", role: .destructive) {
                        bleManager.forget(role: role)
                        UserDefaults.standard.removeObject(forKey: "ble.device.\(role.rawValue)")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.telemetryAlert)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer(minLength: 12)
                    Text("No \(role.rawValue) Paired")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Select a discovered device below")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    // MARK: - Discovered Devices Section
    
    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DISCOVERED DEVICES")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bleManager.discoveredDevices.count) FOUND")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            if bleManager.discoveredDevices.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if bleManager.isScanning {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.secondary)
                            Text("Searching for nearby devices...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text("No devices found. Ensure devices are turned on.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 32)
                    Spacer()
                }
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.wellRadius))
            } else {
                VStack(spacing: 8) {
                    ForEach(bleManager.discoveredDevices) { device in
                        discoveredDeviceRow(device)
                    }
                }
            }
        }
    }
    
    private func discoveredDeviceRow(_ device: DiscoveredDevice) -> some View {
        HStack {
            Image(systemName: device.role == .scale ? "scalemass.fill" : "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text(device.role == .scale ? "Scale" : "Pressure Device")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Text("\(device.rssi) dBm")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.trailing, 10)
            
            // High-Contrast Connect Button (Replaces generic blue)
            Button("Connect") {
                bleManager.select(device: device)
                UserDefaults.standard.set(device.id.uuidString, forKey: "ble.device.\(device.role.rawValue)")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }
    
    // MARK: - Helpers
    
    private func toggleScan() {
        if bleManager.isScanning {
            bleManager.stopScanning()
        } else {
            bleManager.startScanning()
        }
    }
    
    private func batteryIcon(for percentage: Int) -> String {
        switch percentage {
        case 85...100: return "battery.100percent"
        case 60..<85:  return "battery.75percent"
        case 35..<60:  return "battery.50percent"
        case 10..<35:  return "battery.25percent"
        default:       return "battery.0percent"
        }
    }
}
