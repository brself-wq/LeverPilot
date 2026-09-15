//
//  ShotHistoryBrowserView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import Charts
import MeticulousProfile

public struct ShotHistoryBrowserView: View {
    let scenarioStore: ScenarioStore
    
    @State private var selectedShotID: String? = nil
    @State private var searchQuery: String = ""
    @State private var showCopiedBanner: Bool = false
    
    public init(scenarioStore: ScenarioStore) {
        self.scenarioStore = scenarioStore
    }
    
    // MARK: - Filtered & Sorted Scenarios
    
    private var filteredShots: [ShotRecord] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return scenarioStore.scenarios
        }
        return scenarioStore.scenarios.filter { shot in
            shot.profileName.localizedCaseInsensitiveContains(query) ||
            (shot.beanName?.localizedCaseInsensitiveContains(query) ?? false) ||
            (shot.beanRoaster?.localizedCaseInsensitiveContains(query) ?? false) ||
            (shot.grinderModel?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    
    private var selectedShot: ShotRecord? {
        if let id = selectedShotID {
            return filteredShots.first(where: { $0.id == id }) ?? filteredShots.first
        }
        return filteredShots.first
    }
    
    private var selectedIndex: Int? {
        guard let shot = selectedShot else { return nil }
        return filteredShots.firstIndex(where: { $0.id == shot.id })
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                Divider().background(Color.white.opacity(0.08))
                
                if filteredShots.isEmpty {
                    emptyStateView
                } else {
                    HStack(spacing: 0) {
                        // MASTER COLUMN: Scrollable shot history cards
                        masterShotList
                            .frame(width: 320)
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // DETAIL PANE: Multi-stream telemetry & shot notes
                        if let shot = selectedShot {
                            detailView(for: shot)
                        }
                    }
                }
            }
            
            if showCopiedBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Visualizer JSON copied to clipboard")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.14, green: 0.14, blue: 0.18), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            if selectedShotID == nil {
                selectedShotID = filteredShots.first?.id
            }
        }
    }
    
    // MARK: - Top Bar & Traversal Controls
    
    private var topBar: some View {
        HStack(spacing: 14) {
            // Traversal Chevrons
            HStack(spacing: 6) {
                Button(action: selectPreviousShot) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!canStepBackward)
                
                Button(action: selectNextShot) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!canStepForward)
            }
            
            if let idx = selectedIndex, !filteredShots.isEmpty {
                Text(String(format: "%02d / %02d", idx + 1, filteredShots.count))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Search Input Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                TextField("Search recipe, roaster, bean...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 220)
                
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
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
        }
    }
    
    // MARK: - Master Shot List
    
    private var masterShotList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredShots) { shot in
                    shotRowCard(shot: shot, isSelected: shot.id == selectedShot?.id)
                        .onTapGesture {
                            selectedShotID = shot.id
                        }
                }
            }
            .padding(14)
            // Bottom clearance for the universal hamburger menu
            .padding(.bottom, 60)
        }
    }
    
    private func shotRowCard(shot: ShotRecord, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shot.profileName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Spacer()
                
                if shot.isAborted {
                    Text("ABORTED")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
            }
            
            HStack {
                Text(formattedDate(shot.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text(String(format: "%.1fg", shot.finalWeight))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.90, green: 0.68, blue: 0.28))
                    
                    Text(String(format: "%02d:%02ds", Int(shot.duration) / 60, Int(shot.duration) % 60))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Detail Pane (Telemetry Chart & Metadata)
    
    private func detailView(for shot: ShotRecord) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Dominant Multi-Stream Extraction Chart
                meticulousGraphCard(for: shot)
                
                // Dial-In Parameters and Notes
                dialInAndNotesCard(for: shot)
                
                // Read-only Export Action Bar
                exportActionBar(for: shot)
            }
            .padding(20)
        }
    }
    
    // MARK: - Telemetry Chart Card
    
    private func meticulousGraphCard(for shot: ShotRecord) -> some View {
        let peakPressure = shot.samples.map(\.pressure).max() ?? 0.0
        let flows = shot.samples.map(\.flow).filter { $0 > 0.1 }
        let avgFlow = flows.isEmpty ? 0.0 : flows.reduce(0, +) / Double(flows.count)
        
        return VStack(spacing: 12) {
            // Chart Legends
            HStack(spacing: 16) {
                legendItem(color: Color(red: 0.0, green: 0.70, blue: 0.95), label: "Pressure (bar)")
                legendItem(color: Color(red: 0.20, green: 0.85, blue: 0.65), label: "Flow (mL/s)")
                legendItem(color: Color(red: 0.95, green: 0.72, blue: 0.25), label: "Weight (g)")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            // Chart Body
            Chart {
                ForEach(shot.samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.pressure),
                        series: .value("Stream", "Pressure")
                    )
                    .foregroundStyle(Color(red: 0.0, green: 0.70, blue: 0.95))
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
                    .interpolationMethod(.monotone)
                    
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.flow),
                        series: .value("Stream", "Flow")
                    )
                    .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .interpolationMethod(.monotone)
                    
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.weight * 0.2),
                        series: .value("Stream", "Weight")
                    )
                    .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.25))
                    .lineStyle(StrokeStyle(lineWidth: 2.0))
                    .interpolationMethod(.monotone)
                }
                
                if let last = shot.samples.last {
                    PointMark(x: .value("Time", last.timestamp), y: .value("Value", last.weight * 0.2))
                        .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.25))
                        .symbolSize(50)
                    PointMark(x: .value("Time", last.timestamp), y: .value("Value", last.flow))
                        .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.65))
                        .symbolSize(40)
                }
            }
            .chartYScale(domain: 0...14)
            .chartYAxis {
                AxisMarks(values: [0, 2, 4, 6, 8, 10, 12, 14]) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 240)
            .padding(.horizontal, 14)
            
            // Summary Metric Footer Strip
            HStack {
                summaryMetric(label: "Duration", val: String(format: "%02d:%02d", Int(shot.duration) / 60, Int(shot.duration) % 60))
                Spacer()
                summaryMetric(label: "Peak Press.", val: String(format: "%.1f bar", peakPressure))
                Spacer()
                summaryMetric(label: "Avg Flow", val: String(format: "%.1f ml/s", avgFlow))
                Spacer()
                summaryMetric(label: "Yield", val: String(format: "%.1f g", shot.finalWeight), highlight: true)
                Spacer()
                summaryMetric(label: "Temp", val: String(format: "%.0f°C", shot.brewTemperature))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Dial-In Parameters & Notes
    
    private func dialInAndNotesCard(for shot: ShotRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DIAL-IN PARAMETERS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    metadataPill(label: "Roaster", val: shot.beanRoaster ?? "Unspecified")
                    metadataPill(label: "Bean", val: shot.beanName ?? "Unspecified")
                }
                
                HStack(spacing: 12) {
                    metadataPill(label: "Grinder", val: shot.grinderModel ?? "Unspecified")
                    metadataPill(label: "Setting", val: shot.grindSetting ?? "Unspecified")
                    metadataPill(label: "Dose", val: shot.doseWeight != nil ? String(format: "%.1fg", shot.doseWeight!) : "--")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
            .cornerRadius(10)
            
            if let notes = shot.tastingNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TASTING NOTES")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.secondary)
                    
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Export Action Bar (Read-Only)
    
    private func exportActionBar(for shot: ShotRecord) -> some View {
        HStack(spacing: 12) {
            Button(action: { copyVisualizerJSON(shot: shot) }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy Beanconqueror JSON")
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            ShareLink(
                item: visualizerJSONString(shot: shot),
                preview: SharePreview("Shot: \(shot.profileName)", image: Image(systemName: "cup.and.saucer.fill"))
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Traversal Actions
    
    private var canStepBackward: Bool {
        guard let idx = selectedIndex else { return false }
        return idx > 0
    }
    
    private var canStepForward: Bool {
        guard let idx = selectedIndex else { return false }
        return idx < filteredShots.count - 1
    }
    
    private func selectPreviousShot() {
        guard let idx = selectedIndex, canStepBackward else { return }
        selectedShotID = filteredShots[idx - 1].id
    }
    
    private func selectNextShot() {
        guard let idx = selectedIndex, canStepForward else { return }
        selectedShotID = filteredShots[idx + 1].id
    }
    
    // MARK: - Helpers
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
    
    private func summaryMetric(label: String, val: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(val)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(highlight ? Color(red: 0.95, green: 0.72, blue: 0.25) : .white)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
    
    private func metadataPill(label: String, val: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(val)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func copyVisualizerJSON(shot: ShotRecord) {
        let json = visualizerJSONString(shot: shot)
        #if os(iOS)
        UIPasteboard.general.string = json
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        #endif
        withAnimation { showCopiedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showCopiedBanner = false }
        }
    }
    
    private func visualizerJSONString(shot: ShotRecord) -> String {
        let payload = shot.toVisualizerPayload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Shot Records Found")
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchQuery.isEmpty {
                Button("Clear Search") {
                    searchQuery = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
