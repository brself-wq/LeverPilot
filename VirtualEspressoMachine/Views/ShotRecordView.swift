//
//  ShotRecordView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import Charts
import MeticulousProfile

public struct ShotRecordView: View {
    @State private var record: ShotRecord
    let onSave: (ShotRecord) -> Void
    let onDismiss: () -> Void
    
    @State private var selectedTimestamp: Double? = nil
    @State private var showCopiedBanner: Bool = false
    
    public init(
        record: ShotRecord,
        onSave: @escaping (ShotRecord) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._record = State(initialValue: record)
        self.onSave = onSave
        self.onDismiss = onDismiss
    }
    
    private var peakPressure: Double {
        record.samples.map(\.pressure).max() ?? 0.0
    }
    
    private var averageFlow: Double {
        let flows = record.samples.map(\.flow).filter { $0 > 0.1 }
        guard !flows.isEmpty else { return 0.0 }
        return flows.reduce(0, +) / Double(flows.count)
    }

    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.09, green: 0.09, blue: 0.11))
                
                Divider().background(Color.white.opacity(0.08))
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Dominant Meticulous-style Chart Card
                        meticulousGraphCard
                        
                        // 2. Dial-In Metadata & Tasting Notes
                        dialInAndNotesSection
                    }
                    .padding(24)
                }
                
                Divider().background(Color.white.opacity(0.08))
                
                footerActionBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
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
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(record.profileName)
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)
                    
                    Text(String(format: "⏱ %02d:%02ds", Int(record.duration) / 60, Int(record.duration) % 60))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    
                    Text(String(format: "⚖️ %.1fg", record.finalWeight))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.90, green: 0.68, blue: 0.28))
                    
                    Text(String(format: "🌡 %.0f°C", record.brewTemperature))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                onSave(record)
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                    Text("SAVE TO HISTORY")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Meticulous Graph Card
    
    private var meticulousGraphCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                legendItem(color: Color(red: 0.0, green: 0.70, blue: 0.95), label: "Pressure (bar)")
                legendItem(color: Color(red: 0.20, green: 0.85, blue: 0.65), label: "Flow (mL/s)")
                legendItem(color: Color(red: 0.95, green: 0.72, blue: 0.25), label: "Weight (g)")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            Chart {
                ForEach(record.samples) { sample in
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
                
                if let last = record.samples.last {
                    PointMark(x: .value("Time", last.timestamp), y: .value("Value", last.weight * 0.2))
                        .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.25))
                        .symbolSize(60)
                    PointMark(x: .value("Time", last.timestamp), y: .value("Value", last.flow))
                        .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.65))
                        .symbolSize(50)
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
            .frame(height: 260)
            .padding(.horizontal, 14)
            
            HStack {
                summaryMetric(label: "Time", val: String(format: "%02d:%02d", Int(record.duration) / 60, Int(record.duration) % 60))
                Spacer()
                summaryMetric(label: "Peak Press.", val: String(format: "%.1f bar", peakPressure))
                Spacer()
                summaryMetric(label: "Avg Flow", val: String(format: "%.1f ml/s", averageFlow))
                Spacer()
                summaryMetric(label: "Yield", val: String(format: "%.1f g", record.finalWeight), highlight: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.03))
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    // MARK: - Dial-In Parameters & Tasting Notes
    
    private var dialInAndNotesSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("DIAL-IN PARAMETERS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    fieldInput(label: "Roaster", text: Binding(get: { record.beanRoaster ?? "" }, set: { record.beanRoaster = $0 }))
                    fieldInput(label: "Bean / Origin", text: Binding(get: { record.beanName ?? "" }, set: { record.beanName = $0 }))
                    HStack(spacing: 8) {
                        fieldInput(label: "Grinder", text: Binding(get: { record.grinderModel ?? "" }, set: { record.grinderModel = $0 }))
                        fieldInput(label: "Setting", text: Binding(get: { record.grindSetting ?? "" }, set: { record.grindSetting = $0 }))
                            .frame(width: 100)
                    }
                }
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("TASTING NOTES")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                TextField("Acidity, sweetness, channel events, mouthfeel...", text: Binding(get: { record.tastingNotes ?? "" }, set: { record.tastingNotes = $0 }), axis: .vertical)
                    .lineLimit(4...5)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
            }
            .padding(14)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Footer Actions
    
    private var footerActionBar: some View {
        HStack(spacing: 12) {
            Button(action: copyVisualizerJSON) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Export Beanconqueror JSON")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            ShareLink(
                item: visualizerJSONString(),
                preview: SharePreview("Shot: \(record.profileName)", image: Image(systemName: "cup.and.saucer.fill"))
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
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
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(highlight ? Color(red: 0.95, green: 0.72, blue: 0.25) : .white)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
    
    private func fieldInput(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.tertiary)
            TextField(label, text: text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
        }
    }
    
    private func copyVisualizerJSON() {
        let json = visualizerJSONString()
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
    
    private func visualizerJSONString() -> String {
        let payload = record.toVisualizerPayload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
