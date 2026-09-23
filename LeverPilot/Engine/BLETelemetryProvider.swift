//
//  BLETelemetryProvider.swift
//  LeverPilot
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
    
    // Edge-Triggered Diagnostic State (Prevents log flooding at 10 Hz)
    private var prevIsScaleStale: Bool = false
    private var prevIsPressureStale: Bool = false
    
    // Weight Latching: Never default or drop to 0.0g during active extraction (ADR-009)
    private var latchedWeight: Double = 0.0
    
    // Signal Conditioning Ring Buffer (6 samples @ 10 Hz = 500ms window)
    private var weightHistory: [(timestamp: Double, weight: Double)] = []
    private let maxHistorySamples = 6
    private var lastRegressionTimestamp: Double? = nil
    
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
        self.latchedWeight = 0.0
        self.weightHistory.removeAll()
        self.lastRegressionTimestamp = nil
        self.prevIsScaleStale = false
        self.prevIsPressureStale = false
        
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
                
                // 2. Hardware Transport Staleness Evaluation (ADR-009)
                // Driven strictly by CoreBluetooth packet receipt heartbeats, NOT by value deltas
                let isScaleConnected = self.bleManager.slots[.scale]?.isConnected == true
                let isPressureConnected = self.bleManager.slots[.pressure]?.isConnected == true
                
                let scaleSlotStale = self.bleManager.slots[.scale]?.isStale ?? true
                let pressureSlotStale = self.bleManager.slots[.pressure]?.isStale ?? true
                
                let isScaleStale = !isScaleConnected || scaleSlotStale
                let isPressureStale = !isPressureConnected || pressureSlotStale
                
                // Edge-Triggered Diagnostics: Scale Connection & Staleness Transitions
                if isScaleStale != self.prevIsScaleStale {
                    self.prevIsScaleStale = isScaleStale
                    if isScaleStale {
                        print("[BLE] ⚠️ Scale packet stream LOST (connected: \(isScaleConnected), slotStale: \(scaleSlotStale))")
                    } else {
                        print("[BLE] ✅ Scale packet stream RESTORED (weight: \(String(format: "%.1f", rawWeight))g)")
                    }
                }
                
                // Edge-Triggered Diagnostics: Pressure Connection & Staleness Transitions
                if isPressureStale != self.prevIsPressureStale {
                    self.prevIsPressureStale = isPressureStale
                    if isPressureStale {
                        print("[BLE] ⚠️ Pressure gauge stream OFFLINE (connected: \(isPressureConnected), slotStale: \(pressureSlotStale))")
                    } else {
                        print("[BLE] ✅ Pressure gauge stream RESTORED (pressure: \(String(format: "%.1f", rawPressure)) bar)")
                    }
                }
                
                // 3. Weight Latching Invariant (ADR-009)
                // Continuously track live weight when scale stream is fresh; latch during disconnections
                if !isScaleStale && rawWeight > 0.0 {
                    self.latchedWeight = rawWeight
                }
                
                let effectiveWeight: Double
                if self.isExtracting {
                    effectiveWeight = isScaleStale ? self.latchedWeight : rawWeight
                } else {
                    effectiveWeight = rawWeight
                }
                
                // 4. Extraction Auto-Start Threshold (Trip exclusively on Pressure >= 0.5 bar)
                if !self.isExtracting {
                    if rawPressure >= 0.5 && !isPressureStale {
                        self.isExtracting = true
                        self.extractionStartTime = now
                        print("[BLE] 🚀 Live extraction threshold met (P = \(String(format: "%.2f", rawPressure)) bar >= 0.5 bar)")
                    }
                }
                
                // 5. Elapsed Shot Duration
                let shotElapsed: Double
                if let start = self.extractionStartTime, self.isExtracting {
                    shotElapsed = now.timeIntervalSince(start)
                } else {
                    shotElapsed = 0.0
                }
                
                // 6. Compute Flow (dw/dt) via Rolling Linear Regression
                var derivedFlow: Double
                #if DEBUG
                if self.forceZeroFlow || isScaleStale || !self.isExtracting {
                    derivedFlow = 0.0
                } else {
                    derivedFlow = self.calculateRegressionFlow(currentTime: shotElapsed, currentWeight: effectiveWeight, isStale: isScaleStale)
                }
                #else
                if isScaleStale || !self.isExtracting {
                    derivedFlow = 0.0
                } else {
                    derivedFlow = self.calculateRegressionFlow(currentTime: shotElapsed, currentWeight: effectiveWeight, isStale: isScaleStale)
                }
                #endif
                
                // 7. Emit Machine Frame with Transport Health Flags
                let frame = MachineFrame(
                    timestamp: shotElapsed,
                    absoluteTime: now,
                    state: self.isExtracting ? .extracting : .armed,
                    readings: [
                        .pressure: rawPressure,
                        .flow: derivedFlow,
                        .weight: effectiveWeight,
                        .time: shotElapsed,
                        .power: 100.0
                    ],
                    isScaleStale: isScaleStale,
                    isPressureStale: isPressureStale
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
        lastRegressionTimestamp = nil
        latchedWeight = 0.0
        prevIsScaleStale = false
        prevIsPressureStale = false
        #if DEBUG
        resetInjections()
        #endif
    }
    
    // MARK: - Ordinary Least Squares (OLS) Linear Regression for Flow Rate
    
    public func calculateRegressionFlow(currentTime: Double, currentWeight: Double, isStale: Bool = false) -> Double {
        guard !isStale else {
            weightHistory.removeAll()
            lastRegressionTimestamp = nil
            return 0.0
        }
        
        // Regression Gap Re-Anchoring (ADR-009): Purge history if delta_t > 0.5s to avoid dw/dt spikes
        if let lastT = lastRegressionTimestamp, (currentTime - lastT) > 0.5 {
            weightHistory.removeAll()
        }
        lastRegressionTimestamp = currentTime
        
        weightHistory.append((timestamp: currentTime, weight: currentWeight))
        if weightHistory.count > maxHistorySamples {
            weightHistory.removeFirst()
        }
        
        // Require at least 3 fresh contiguous samples to compute a robust slope
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
