//
//  BLETelemetryProvider.swift
//  VirtualEspressoMachine
//

import Foundation
import EspressoBLE

public final class BLETelemetryProvider: TelemetryProvider, @unchecked Sendable {
    
    public let frames: AsyncStream<MachineFrame>
    private var continuation: AsyncStream<MachineFrame>.Continuation?
    
    private let bleManager: EspressoBLEManager
    private var timerTask: Task<Void, Never>?
    
    // Clock Anchors: Distinguish armed waiting time from active extraction time
    private var isExtracting: Bool = false
    private var extractionStartTime: Date? = nil
    
    // Signal Conditioning Ring Buffer (6 samples @ 10 Hz = 500ms window)
    private var weightHistory: [(timestamp: Double, weight: Double)] = []
    private let maxHistorySamples = 6
    
    // MARK: - Bench Sensor Stimulation (DEBUG Only)
    #if DEBUG
    private var injectedPressure: Double? = nil
    private var injectedWeightOffset: Double = 0.0
    private var forceZeroFlow: Bool = false
    #endif
    
    public init(bleManager: EspressoBLEManager) {
        self.bleManager = bleManager
        
        var capturedContinuation: AsyncStream<MachineFrame>.Continuation?
        self.frames = AsyncStream { cont in
            capturedContinuation = cont
        }
        self.continuation = capturedContinuation
    }
    
    deinit {
        stop()
        continuation?.finish()
    }
    
    public func start() {
        stop()
        self.isExtracting = false
        self.extractionStartTime = nil
        
        timerTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                let now = Date()
                
                // 1. Ingest Sensor Values (Real BLE or Injected Bench Values)
                var rawPressure = self.bleManager.slots[.pressure]?.lastReading?.pressureBar ?? 0.0
                var rawWeight = self.bleManager.slots[.scale]?.lastReading?.weightGrams ?? 0.0
                
                #if DEBUG
                if let simP = self.injectedPressure { rawPressure = simP }
                rawWeight += self.injectedWeightOffset
                #endif
                
                // 2. Evaluate Extraction Threshold (Trip exclusively on Pressure >= 0.5 bar)
                if !self.isExtracting {
                    if rawPressure >= 0.5 {
                        self.isExtracting = true
                        self.extractionStartTime = now
                    }
                }
                
                // 3. Compute Elapsed Shot Time (0.0s while armed; ticks only after trip)
                let shotElapsed: Double
                if let start = self.extractionStartTime, self.isExtracting {
                    shotElapsed = now.timeIntervalSince(start)
                } else {
                    shotElapsed = 0.0
                }
                
                // 4. Compute Flow (dw/dt) via Rolling Linear Regression
                var derivedFlow: Double
                #if DEBUG
                if self.forceZeroFlow {
                    derivedFlow = 0.0
                } else {
                    derivedFlow = self.calculateRegressionFlow(currentTime: shotElapsed, currentWeight: rawWeight)
                }
                #else
                derivedFlow = self.calculateRegressionFlow(currentTime: shotElapsed, currentWeight: rawWeight)
                #endif
                
                // 5. Emit Frame with True Machine State (.armed while waiting, .extracting after trip)
                let frame = MachineFrame(
                    timestamp: shotElapsed,
                    absoluteTime: now,
                    state: self.isExtracting ? .extracting : .armed,
                    readings: [
                        .pressure: rawPressure,
                        .flow: derivedFlow,
                        .weight: rawWeight,
                        .time: shotElapsed,
                        .power: 100.0
                    ]
                )
                
                self.continuation?.yield(frame)
                
                // 10 Hz Metronome Cadence
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    
    public func stop() {
        timerTask?.cancel()
        timerTask = nil
        isExtracting = false
        extractionStartTime = nil
        weightHistory.removeAll()
        #if DEBUG
        resetInjections()
        #endif
    }
    
    // MARK: - Ordinary Least Squares (OLS) Linear Regression for Flow Rate
    
    private func calculateRegressionFlow(currentTime: Double, currentWeight: Double) -> Double {
        guard isExtracting else { return 0.0 }
        
        weightHistory.append((timestamp: currentTime, weight: currentWeight))
        if weightHistory.count > maxHistorySamples {
            weightHistory.removeFirst()
        }
        
        guard weightHistory.count >= 3 else { return 0.0 }
        
        let n = Double(weightHistory.count)
        var sumT = 0.0
        var sumW = 0.0
        var sumTT = 0.0
        var sumTW = 0.0
        
        for pt in weightHistory {
            sumT += pt.timestamp
            sumW += pt.weight
            sumTT += pt.timestamp * pt.timestamp
            sumTW += pt.timestamp * pt.weight
        }
        
        let denominator = (n * sumTT) - (sumT * sumT)
        guard abs(denominator) > 0.00001 else { return 0.0 }
        
        let slope = ((n * sumTW) - (sumT * sumW)) / denominator
        return max(0.0, (slope * 10.0).rounded() / 10.0)
    }
    
    // MARK: - Bench Hardware Stimulation (DEBUG Only)
    
    #if DEBUG
    public func stimulateLeverPush(_ bar: Double) {
        self.injectedPressure = bar
    }
    
    public func stimulateWeightDrip(_ grams: Double) {
        self.injectedWeightOffset += grams
    }
    
    public func stimulateFlowStop() {
        self.forceZeroFlow = true
    }
    
    public func resetInjections() {
        self.injectedPressure = nil
        self.injectedWeightOffset = 0.0
        self.forceZeroFlow = false
    }
    #endif
}
