//
//  AddToBeanconquerorSheet.swift
//  LeverPilot
//

import SwiftUI

public struct AddToBeanconquerorSheet: View {
    let record: ShotRecord
    
    @ObservedObject private var bqStorage = BQStorageManager.shared
    @ObservedObject private var handoff = BQHandoffCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @State private var selectedBean: BQBean? = nil
    @State private var isShowingFolderPicker: Bool = false
    
    public init(record: ShotRecord) {
        self.record = record
    }
    
    private var canAddBrew: Bool {
        selectedBean?.hasShareCode == true
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.appCard)
            
            Divider().background(Color.appBorderSubtle)
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Folder Connection Status Card
                    folderStatusCard
                    
                    if bqStorage.isConfigured {
                        // 2. Shot Summary Card
                        shotSummaryCard
                        
                        // 3. Active Beans Picker / List
                        beanSelectionCard
                    }
                }
                .padding(24)
            }
            
            Divider().background(Color.appBorderSubtle)
            
            // Bottom Action Footer
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.appFooter)
        }
        .frame(minWidth: 540, minHeight: 480)
        .background(Color.appCanvas)
        .sheet(isPresented: $isShowingFolderPicker) {
            DocumentPickerView { url in
                bqStorage.saveFolderBookmark(url: url)
            }
        }
        .onAppear {
            handoff.resetState()
            bqStorage.refresh()
            if selectedBean == nil {
                selectedBean = bqStorage.beans.first(where: \.hasShareCode) ?? bqStorage.beans.first
            }
        }
        .onDisappear {
            handoff.resetState()
        }
        .onChange(of: handoff.state) { _, newState in
            if newState == .transferred {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Brew to Beanconqueror")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                Text("Choose a coffee bean to record with this shot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Folder Status Card
    
    private var folderStatusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(bqStorage.isConfigured ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bqStorage.isConfigured ? "Beanconqueror Folder Linked" : "Folder Not Linked")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text(bqStorage.syncStatusMessage)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if bqStorage.isConfigured {
                Button {
                    bqStorage.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // High-Contrast Link / Change Folder Button (Replaces blue button)
            Button(action: { isShowingFolderPicker = true }) {
                Text(bqStorage.isConfigured ? "Change" : "Link Folder")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(bqStorage.isConfigured ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(bqStorage.isConfigured ? Theme.Surface.control : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.wellRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.wellRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    // MARK: - Shot Summary Card
    
    private var shotSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.profileName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("Ready to send to Beanconqueror")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 14) {
                metricPill(label: "Yield", val: String(format: "%.1fg", record.finalWeight), highlight: true)
                metricPill(label: "Time", val: String(format: "%02ds", Int(record.duration)))
                metricPill(label: "Temp", val: String(format: "%.0f°C", record.brewTemperature))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.wellRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.wellRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    private func metricPill(label: String, val: String, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(val)
                .font(.system(size: 11, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(highlight ? Color.telemetryWeight : .white)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Bean Selection Card
    
    private var beanSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SELECT BEAN")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bqStorage.beans.count) ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            if bqStorage.beans.isEmpty {
                Text("No active beans found in archive.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(bqStorage.beans) { bean in
                        beanRow(bean)
                    }
                }
            }
            
            if let selected = selectedBean, !selected.hasShareCode {
                missingShareCodeBanner
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.podRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.podRadius)
                .strokeBorder(Theme.Border.glassGradient, lineWidth: 1)
        )
    }
    
    private func beanRow(_ bean: BQBean) -> some View {
        let isSelected = selectedBean?.id == bean.id
        
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bean.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    if bean.hasShareCode {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
                Text(bean.roaster ?? "Unknown Roaster")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color.telemetryFlow) // Cockpit cyan
            }
        }
        .padding(10)
        .background(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedBean = bean
        }
    }
    
    private var missingShareCodeBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Bean Not Linked for Deep Linking")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Text("Beanconqueror requires minting a share code once. Open Beanconqueror, navigate to this bean, tap 'Share' / 'QR Code' once, then return here and tap Refresh.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Open Beanconqueror") {
                    if let url = URL(string: "beanconqueror://") {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button(action: { bqStorage.refresh() }) {
                    Text("Refresh")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.controlRadius))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
    }
    
    // MARK: - Footer
    
    private var footerBar: some View {
        let isDelivered = handoff.isDelivered(shotId: record.id)
        let isBusy = handoff.state == .transferring || handoff.state == .transferred

        return HStack {
            Spacer()
            
            // High-Contrast Primary Transfer Action
            Button {
                guard let bean = selectedBean, let shareCode = bean.internalShareCode else { return }
                handoff.addBrewToBeanconqueror(shareCode: shareCode, shot: record)
            } label: {
                HStack(spacing: 8) {
                    switch handoff.state {
                    case .transferring:
                        ProgressView()
                            .controlSize(.small)
                            .tint(canAddBrew ? .black : .white)
                        Text("Transferring...")
                            .font(.system(size: 13, weight: .bold))
                    case .transferred:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .black))
                        Text("Transferred!")
                            .font(.system(size: 13, weight: .bold))
                    case .timedOut:
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .black))
                        Text("Ready to Re-send")
                            .font(.system(size: 13, weight: .bold))
                    case .idle:
                        Image(systemName: isDelivered ? "arrow.clockwise" : "arrow.up.forward.app.fill")
                            .font(.system(size: 12, weight: .black))
                        Text(selectedBean?.hasShareCode == true
                             ? (isDelivered ? "Re-send to Beanconqueror" : "Add Brew in Beanconqueror")
                             : "Share Code Required")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .foregroundStyle(
                    handoff.state == .transferred ? Color.green :
                    (canAddBrew && !isBusy ? Color.black : Color.secondary)
                )
                .background(
                    handoff.state == .transferred ? Color.green.opacity(0.16) :
                    (canAddBrew && !isBusy ? Color.white : Theme.Surface.control)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cardRadius)
                        .strokeBorder(
                            handoff.state == .transferred ? Color.green.opacity(0.40) :
                            (canAddBrew && !isBusy ? Color.clear : Theme.Border.subtle),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!canAddBrew || isBusy)
        }
    }
}
