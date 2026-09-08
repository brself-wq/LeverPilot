//
//  StageDynamicsChartView.swift
//  VirtualEspressoMachine
//
//  Created by Ben Self on 9/8/26.
//


//
//  StageDynamicsChartView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import Charts
import MeticulousProfile

public struct StageDynamicsChartView: View {
    let planCurve: [PlanPoint]
    let actualHistory: [ActualPoint]
    let domainLabel: String
    let activeMetric: SensorKey
    
    public init(
        planCurve: [PlanPoint],
        actualHistory: [ActualPoint],
        domainLabel: String,
        activeMetric: SensorKey
    ) {
        self.planCurve = planCurve
        self.actualHistory = actualHistory
        self.domainLabel = domainLabel
        self.activeMetric = activeMetric
    }
    
    private var themeColor: Color {
        activeMetric.themeColor
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("OVER: \(domainLabel.uppercased())")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeColor.opacity(0.15))
                    .foregroundStyle(themeColor)
                    .clipShape(Capsule())
                
                Spacer()
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("╌╌")
                            .fontWeight(.black)
                            .foregroundStyle(themeColor.opacity(0.6))
                        Text("Plan (Target)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("──")
                            .fontWeight(.black)
                            .foregroundStyle(themeColor)
                        Text("Actual Pull")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Chart {
                ForEach(planCurve) { pt in
                    LineMark(
                        x: .value("Domain", pt.x),
                        y: .value("Value", pt.y),
                        series: .value("Stream", "Plan")
                    )
                    .foregroundStyle(themeColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                }
                
                ForEach(actualHistory) { pt in
                    LineMark(
                        x: .value("Domain", pt.x),
                        y: .value("Value", pt.y),
                        series: .value("Stream", "Actual")
                    )
                    .foregroundStyle(themeColor)
                    .lineStyle(StrokeStyle(lineWidth: 3.5))
                }
                
                if let current = actualHistory.last {
                    PointMark(
                        x: .value("Domain", current.x),
                        y: .value("Value", current.y)
                    )
                    .symbolSize(80)
                    .foregroundStyle(Color.white)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    if let val = value.as(Double.self) {
                        let unit = domainLabel.lowercased() == "weight" ? "g" : "s"
                        AxisValueLabel("\(Int(val))\(unit)")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }
}