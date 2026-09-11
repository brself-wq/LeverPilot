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
    
    private var brewRatioString: String {
        guard let dose = record.doseWeight, dose > 0 else { return "1 : --" }
        let ratio = record.finalWeight / dose
        return String(format: "1 : %.2f", ratio)
    }
    
    private var peakPressure: Double {
        record.samples.map(\.pressure).max() ?? 0.0
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                topHeaderBar
                
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 16) {
                        scorecardHeroStrip
                        telemetryMultiStreamChart
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 16) {
                        puckPrepSpecsCard
                        tastingNotesCard
                        Spacer(minLength: 0)
                        exportActionBar
                    }
                    .frame(width: 380)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            
            if showCopiedBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Visualizer JSON Copied to Clipboard")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Top Header Bar
    
    private var topHeaderBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXTRACTION RECORD")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                
                Text(record.profileName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            Button {
                onSave(record)
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Text("SAVE TO HISTORY")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Scorecard Hero Strip
    
    private var scorecardHeroStrip: some View {
        HStack(spacing: 12) {
            metricBlock(label: "DOSE", value: String(format: "%.1fg", record.doseWeight ?? 18.0), color: .white)
            metricBlock(label: "YIELD", value: String(format: "%.1fg", record.finalWeight), color: Color(red: 0.90, green: 0.68, blue: 0.28))
            metricBlock(label: "RATIO", value: brewRatioString, color: .orange)
            metricBlock(label: "TIME", value: String(format: "%.1fs", record.duration), color: .cyan)
            metricBlock(label: "PEAK P", value: String(format: "%.1f bar", peakPressure), color: Color(red: 0.15, green: 0.68, blue: 0.38))
        }
    }
    
    private func metricBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1)
            
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Multi-Stream Telemetry Chart
    
    private var telemetryMultiStreamChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STREAM HISTORY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                
                Spacer()
                
                HStack(spacing: 14) {
                    legendPill(color: Color(red: 0.15, green: 0.68, blue: 0.38), label: "Pressure (bar)")
                    legendPill(color: .cyan, label: "Flow (mL/s)")
                    legendPill(color: Color(red: 0.90, green: 0.68, blue: 0.28), label: "Weight / 5 (g)")
                }
            }
            
            Chart {
                chartMarks
            }
            .chartXSelection(value: $selectedTimestamp)
            .chartXAxis {
                AxisMarks {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ChartContentBuilder
    private var chartMarks: some ChartContent {
        let pressureColor = Color(red: 0.15, green: 0.68, blue: 0.38)
        let weightColor = Color(red: 0.90, green: 0.68, blue: 0.28).opacity(0.7)
        
        ForEach(record.samples) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Pressure", sample.pressure),
                series: .value("Stream", "Pressure")
            )
            .foregroundStyle(pressureColor)
            .lineStyle(StrokeStyle(lineWidth: 2.2))
            
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Flow", sample.flow),
                series: .value("Stream", "Flow")
            )
            .foregroundStyle(Color.cyan)
            .lineStyle(StrokeStyle(lineWidth: 1.8))
            
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Weight", sample.weight / 5.0),
                series: .value("Stream", "Weight")
            )
            .foregroundStyle(weightColor)
            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        }
        
        if let t = selectedTimestamp {
            RuleMark(x: .value("Selected", t))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func legendPill(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dial-In Specs Card
    
    private var puckPrepSpecsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DIAL-IN PARAMETERS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            
            VStack(spacing: 8) {
                specInputRow(title: "Roaster", text: Binding(
                    get: { record.beanRoaster ?? "" },
                    set: { record.beanRoaster = $0 }
                ))
                specInputRow(title: "Bean / Origin", text: Binding(
                    get: { record.beanName ?? "" },
                    set: { record.beanName = $0 }
                ))
                HStack(spacing: 8) {
                    specInputRow(title: "Grinder", text: Binding(
                        get: { record.grinderModel ?? "" },
                        set: { record.grinderModel = $0 }
                    ))
                    specInputRow(title: "Setting", text: Binding(
                        get: { record.grindSetting ?? "" },
                        set: { record.grindSetting = $0 }
                    ))
                    .frame(width: 110)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func specInputRow(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            
            TextField(title, text: text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(red: 0.16, green: 0.16, blue: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Tasting Notes
    
    private var tastingNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TASTING NOTES & EVALUATION")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            
            TextField("Acidity, body, sweetness, defects...", text: Binding(
                get: { record.tastingNotes ?? "" },
                set: { record.tastingNotes = $0 }
            ), axis: .vertical)
            .lineLimit(3...4)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(8)
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Export Action Bar
    
    private var exportActionBar: some View {
        HStack(spacing: 10) {
            Button {
                let payload = record.toVisualizerPayload()
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                   let json = String(data: data, encoding: .utf8) {
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
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("COPY VISUALIZER JSON")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color(red: 0.18, green: 0.18, blue: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            
            ShareLink(
                item: visualizerJSONString(),
                preview: SharePreview("Espresso Shot: \(record.profileName)", image: Image(systemName: "cup.and.saucer.fill"))
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(red: 0.18, green: 0.18, blue: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
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
