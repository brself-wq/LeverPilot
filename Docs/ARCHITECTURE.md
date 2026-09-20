# Architecture & Data Topology Specification

**Project:** BaristaPilot (formerly VirtualEspressoMachine)  
**Target Platform:** iOS 17+, macOS 14+  
**Language / Concurrency:** Swift 5.9 / Swift 6 (Strict Concurrency Checking)  
**Status:** Accepted Architecture Blueprint  
**Revision:** 1.3  
**Date:** September 20, 2026  

---

## 1. Executive Summary & Design Philosophy

BaristaPilot is a high-precision digital twin and software copilot engineered for manual lever espresso platforms (specifically the Flair 58) equipped with Bluetooth transducers and smart scales, while supporting the Open Espresso Profile Format (OEPF) / Meticulous profile standard.

The application serves two distinct operational personas:
1. **The In-Flight Barista Copilot (Live Mode)**: Real-time, low-latency HUD telemetry providing target steering curves, delta guidance cues, limit guardrails, and automated shot-lifecycle detection via live Bluetooth Low Energy (BLE) hardware.
2. **The Roaster / Profile Studio (Workbench Mode)**: An offline sandbox environment enabling profile inspection (variable dependency mapping, stage tree decompilation, JSON validation) and shot simulation (scrubbing previous historical pulls or synthetic test fixtures across any recipe).

In accordance with OEPF §4, unsupported motorized capabilities (such as motorized piston position or electrical power stages) utilize non-blocking visual approximation and pre-flight notices rather than synthetic emulation.

---

## 2. System Topology (The 5-Layer Stack)

The architecture enforces a strict unidirectional data flow. Higher layers observe lower layers; lower layers have zero knowledge of higher layers.

+-------------------------------------------------------------------------+
| Layer 4: Presentation & UI                                              |
| • BaristaHUDView • StageDynamicsChartView • LeftCockpitView             |
| • SimulatorControlDock • ExitTriggersPanelView • ProfileInspector       |
+------------------------------------^------------------------------------+
                                     | Observes via @Observable / State
+------------------------------------+------------------------------------+
| Layer 3: State & Orchestration                                          |
| ShotCoordinator (Actor)                                                 |
| • Owns MachineState (.ready, .armed, .extracting, .shotEnded)           |
| • Tracks activeStageIndex & StageBaselines                              |
| • Evaluates stage transitions & auto-start / auto-stop heuristics       |
| • Routes frames to Pipeline A (Logger) and Pipeline B (Guidance)        |
+------------------------------------^------------------------------------+
                                     | Consumes AsyncStream<MachineFrame>
+------------------------------------+------------------------------------+
| Layer 2: Engine & Telemetry Bridges                                     |
| +--------------------------------+  +---------------------------------+ |
| | ProfileExecutionEngine         |  | TelemetryProvider               | |
| | (Pure, Stateless Struct)       |  | (Protocol Contract)             | |
| | • Trajectory interpolation     |  +---------------------------------+ |
| | • Normalized trigger progress  |  | BLETelemetryProvider (Live)     | |
| | • Limit guardrail checks       |  | ReplayTelemetryProvider (Sim)   | |
| +--------------------------------+  +---------------------------------+ |
+------------------------------------^------------------------------------+
                                     | Streams Hardware / Mock Telemetry
+------------------------------------+------------------------------------+
| Layer 1: Hardware & Transceivers                                        |
| • EspressoBLEManager (CoreBluetooth central manager)                    |
| • BookooScaleDriver (GATT 0xFFE / weight streaming)                     |
| • BookooPressureDriver (GATT 0xFFF / pressure streaming)                |
| • PlaybackEngine (10 Hz scenario timeline replay)                       |
+------------------------------------^------------------------------------+
                                     | Validates & Conforms
+------------------------------------+------------------------------------+
| Layer 0: OEPF Domain & Contracts                                        |
| • MeticulousProfile • MachineFrame • GuidanceFrame                      |
| • ShotRecord • SensorKey • MachineConfig                                |
+-------------------------------------------------------------------------+

---

## 3. Concurrency & Isolation Model (Swift 6)

1. **Stateless Core Engine (`ProfileExecutionEngine`)**:
   * Marked `nonisolated struct` with `Sendable` conformance.
   * Maintains **zero mutable state**, no internal timers, no background tasks, and no actor hops.
   * Operates as a pure mathematical function:
     f(Stage, MachineFrame, StageBaseline, FinalWeight) -> StageEvaluationResult
2. **Orchestrator (`ShotCoordinator`)**:
   * Isolated to `@MainActor` and marked `@Observable`.
   * Serves as the single source of truth for the active shot session, updating UI-bound properties synchronously on the main thread.
3. **Telemetry Streams (`TelemetryProvider`)**:
   * `protocol TelemetryProvider: AnyObject, Sendable`.
   * Decouples asynchronous sensor notification callbacks from UI rendering using Swift's native `AsyncStream<MachineFrame>`.
4. **Hardware Driver (`EspressoBLEManager`)**:
   * Manages CoreBluetooth delegate callbacks on a dedicated queue.
   * Mutates connection lifecycle flags via `@Observable` for low-frequency UI changes, but routes high-frequency (10–20 Hz) numerical readings through a decoupled callback to avoid SwiftUI view evaluation thrashing.
5. **Loopback Server (`MeticulousServer`)**:
   * Isolated as a Swift 6 `actor`, guaranteeing thread-safe port binding, verbose logging configuration, and historical telemetry buffer access off the main runloop.

---

## 4. Telemetry Ingestion & In-Flight Processing

### 4.1. The Metronome Ingestion Engine
Because the Bluetooth scale and pressure transducer operate on unsynchronized internal clocks and transmit packets with variable radio latency, the host application does not process incoming BLE packets directly in the UI.

1. **Sample-and-Hold Buffer**: Incoming raw packets from `EspressoBLE` asynchronously update a thread-safe cache:
   * `latestWeight: Double` + `latestWeightTimestamp: Date`
   * `latestPressure: Double` + `latestPressureTimestamp: Date`
2. **Dual-Channel Staleness Watchdog**:
   * Evaluates packet heartbeats independently for chamber pressure and cup weight.
   * If no packet arrives for > 500ms, the corresponding sensor is marked stale (`isScaleStale`, `isPressureStale`).
3. **Weight Latching Policy**:
   * When scale packets stall or drop, the buffer **latches onto the last known valid weight**, strictly preventing drops to 0.0g during active extractions.
4. **10 Hz Clock Metronome**: A dedicated loop ticks precisely every 100ms (+/- 1ms):
   * Retrieves the latest cached sensor values (or latched values).
   * Computes derived smoothed flow rate.
   * Emits a synchronized, time-stamped `MachineFrame` with active sensor health metadata to the `ShotCoordinator`.

### 4.2. Dual Telemetry Streaming
Every synchronized frame is forked into two distinct pipelines:

* **Pipeline A: The Black Box Logger (Archival)**:
  - Captures raw, unadulterated sensor values (`timestamp`, `pressure`, `weight`, `rawFlow`).
  - Preserves real-world human artifacts, puck channeling, pressure drops, and scale disturbances.
  - Saved directly into `ShotRecord.samples` and exported to cloud analytics (Visualizer.coffee / Beanconqueror).
* **Pipeline B: The Guidance Feed (Barista Copilot)**:
  - Feeds `ProfileExecutionEngine` and `BaristaHUDView`.
  - Applies signal conditioning to prevent visual noise and rapid UI indicator jitter.

### 4.3. Signal Conditioning Algorithms

#### Flow Rate Derivation (Rolling Linear Regression)
Raw differentiation (dw/dt) amplifies discrete scale quantization noise and Bluetooth jitter, producing massive erratic spikes. 
The system buffers the most recent 6 samples (500ms window) and derives flow rate as the slope of the linear regression best-fit line:

Flow Rate = (N * sum(t*w) - sum(t)*sum(w)) / (N * sum(t^2) - (sum(t))^2)

This provides a responsive, smooth flow curve with less than 60ms phase lag.

#### Regression Gap Re-Anchoring
To prevent wild dw/dt rate-of-change spikes when packet flow resumes after an RF gap:
* If the time delta between incoming scale packets exceeds 500ms (delta_t > 0.5s), the 6-sample OLS regression history is **purged and re-anchored**.
* Flow calculation resumes only after accumulating 3 fresh, contiguous packets within standard timing tolerances.

#### Delta Bandwidth (Deadbands)
The UI `DeltaBadge` compares actual values against target setpoints using intentional deadbands:
* **Pressure Deadband**: +/- 0.4 bar.
* **Flow Deadband**: +/- 0.3 mL/s.
Variations within this window display as `"ON TARGET"`, preventing UI flickering.

#### Limit Guardrail Hysteresis
To prevent rapid alarm toggling when a manual lever pull hovers near a safety ceiling:
* **Alarm Trip**: Triggered instantly when Actual >= LimitValue (e.g. 9.0 bar).
* **Alarm Reset**: Requires Actual <= LimitValue - 0.5 bar (e.g. falls below 8.5 bar) before clearing.

#### Decay Trigger Persistence
To prevent brief muscle tremors on a manual lever from prematurely tripping a descending exit trigger:
* A decaying condition (e.g. pressure <= 4.0 bar) must evaluate to `true` for **two consecutive 100ms ticks** (200ms) before triggering stage advancement.

#### HUD Chart Sliding Viewport Window (StageDynamicsChartView)
Stages on a manual lever have dynamic, open-ended durations that cannot be known in advance. To preserve high-resolution visual feedback for manual lever control without compressing the curve into an unreadable scale:
* The HUD dynamics chart enforces a bounded viewport window (nominal 25.0s).
* **Phase A (t_local <= 25.0s)**: The domain is anchored at [0.0 ... max(25.0, horizon)]. The actual pull line grows from left to right.
* **Phase B (t_local > 25.0s)**: The chart automatically slides its visible X-domain: [(t_local - 25.0) ... t_local]. The active extraction coordinate remains pinned near the right edge of the chart at full visual resolution while earlier points roll out of view.

---

## 5. Shot Lifecycle & Extraction Heuristics

The `ShotCoordinator` supervises macro state transitions:

[.idle] ---> Select Profile ---> [.armed] (BLE Tare & Timer Reset)
                                      |
                                      | Pressure >= 0.5 bar (Auto-Start)
                                      v
                                 [.extracting] <---+
                                      |            | Evaluate Stage Triggers
                 Check Auto-Stop      |            | Advance Stage & Baseline
                 or Weight Cutoff     +----+-------+
                                           v
                                      [.shotEnded] (BLE Stop Timer)
                                           |
                                           | Clean / Reset
                                           v
                                        [.idle]

### 5.1. Auto-Start (Pressure Exclusivity)
* When state is `.armed`, extraction begins (`.extracting`, t = 0.0s) strictly when:
  Chamber Pressure >= 0.5 bar
* Scale weight is intentionally excluded from auto-start evaluation. This prevents resting a cup on the scale, pouring kettle water into the brew chamber, or table vibrations from prematurely triggering the extraction clock.

### 5.2. First Drip Event
* Recorded as an informational metadata marker at the exact timestamp when:
  Weight >= 0.5g
* Used to calculate and display pre-infusion puck saturation duration without modifying the main shot clock.

### 5.3. Auto-Stop Safeguards (Beanconqueror Protocol)
To prevent premature termination during long pre-infusion blooms or slow saturation, auto-stop checks activate only after passing dual time and yield preconditions:
1. Elapsed Time >= 5.0s, AND
2. Cup Weight >= 5.0g OR Yield >= Dose (1:1 ratio)

Once preconditions are satisfied, the shot transitions to `.shotEnded` if:
Smoothed Flow <= 0.1 g/s sustained continuously for 2.0 seconds
OR
Current Weight >= Target Final Weight

**Dead-Flow Signal Loss Interlock**: Auto-stop heuristics are **temporarily suspended whenever scale telemetry is marked stale (`isScaleStale`)**. Missing scale packets must never be interpreted as an intentional lever pull stop.

### 5.4. Post-Shot Retroactive Tail Trimming
When the dead-flow watchdog (<= 0.15 mL/s for 2.0s) confirms the end of the shot, `ShotCoordinator` scans backwards through `capturedSamples` to find the initial timestamp where flow permanently fell below threshold. The archived duration and final yield are locked to that sample, and trailing silent samples are trimmed.

### 5.5. Profile Complete & Holding Setpoint State
Stage advancement and profile completion govern the digital twin's guidance state, not the physical machine's power state. Reaching the final recipe trigger enters `isProfileComplete`, holding the commanded setpoint steady and monitoring flow cutoff without terminating the pull mid-stream.

On a manual lever (Flair 58), the profile acts as an in-flight flight director:
1. **Early Terminations**: The barista may release the lever early (due to choking or channeling), which is cleanly caught by the 2.0s dead-flow watchdog or manual abort.
2. **Extended Overrun Pulls**: If liquid is still flowing after the profile's final stage concludes, physical extraction continues, holding setpoint until the dead-flow watchdog or manual abort terminates the shot.

### 5.6. Peripheral Hardware Timer Synchronization & Reconnection Immunity
* On transition to `.armed`, the application issues hardware BLE commands to tare the scale and reset the onboard timer.
* On transition to `.extracting`, the application triggers the scale's onboard timer start.
* On transition to `.shotEnded` or `.idle` (abort), the scale's timer is stopped.
* **Mid-Flight Reconnect Safeguard**: Re-establishing a Bluetooth connection while the machine is actively in `.extracting` never issues a tare command or timer reset, preserving continuous extraction measurements.

---

## 6. Mathematical Evaluation & OEPF Compliance

### 6.1. Stage Baselines
The `StageBaseline` captures the snapshot state at the instant of stage entry:
* `startTime`: Shot timestamp at stage entry.
* `startWeight`: Accumulated cup weight at stage entry.
* `entryPressure`: Actual pressure at stage entry.
* `entryFlow`: Actual flow at stage entry.

### 6.2. Target Setpoint Interpolation
For a given domain progress value x across defined knots [p0, p1]:
* **Linear (`.linear`)**: Standard linear interpolation:
  y(x) = p0.y + ((x - p0.x) / (p1.x - p0.x)) * (p1.y - p0.y)
* **Zero-Order Hold (`.none`)**: Instantaneous step. Holds p0.y constant across x in [p0.x, p1.x) without ramping.
* **Overrun Flatline**: For any x >= plast.x, y(x) = plast.y.

### 6.3. Continuous Trigger Progress Formula
Ascending (>=) and decaying (<=) exit triggers compute normalized progress (0.0 -> 1.0) for HUD racetrack meters:

Progress = clamp((V_current - V_start) / (V_target - V_start), 0.0, 1.0)

* **Ascending Trigger** (e.g. 2 -> 8 bar): At 5 bar => (5 - 2) / (8 - 2) = 3 / 6 = 50%.
* **Decaying Trigger** (e.g. 9 -> 4 bar): At 6.5 bar => (6.5 - 9) / (4 - 9) = -2.5 / -5 = 50%.

### 6.4. Relative vs. Absolute Trigger Normalization
Exit triggers evaluate according to their `relative` flag (which defaults to `false` when omitted):

1. **Relative Triggers (`relative: true`)**:
   - **Time**: t_local = max(0.0, t_actual - t_baseline).
   - **Weight**: w_local = max(0.0, w_actual - w_baseline).
   - **Pressure / Flow**: Evaluated relative to stage entry baseline (V_actual - V_baseline).

2. **Absolute Triggers (`relative: false`, default)**:
   - **Time**: t_shot = t_actual (Total extraction elapsed time since auto-start trip at t = 0.0s). Progress is mapped along the stage span:
     Progress = clamp((t_actual - t_baseline) / (t_target - t_baseline), 0.0, 1.0)
   - **Weight**: Evaluated against total accumulated cup weight (w_actual).
   - **Pressure / Flow**: Evaluated against raw instantaneous gauge readings.

---

## 7. Storage, Persistence, and State Boundaries

1. **Canonical Profile Assets**:
   * Bundled JSON profiles (e.g. `Dark_Side_of_the_Lever.json`) are **read-only constants**.
   * User adjustments made in the pre-flight UI generate an **ephemeral in-memory copy** via `resolveForExecution()`.
   * Modified recipes are saved as distinct user profiles with generated UUIDs in `Application Support/Profiles/`.
2. **Historical Shot Database**:
   * Every completed shot serializes to a `ShotRecord`.
   * Persistence utilizes **SwiftData** (with fallback to JSON documents in `Application Support/Shots/`), indexed by `id`, `profileId`, and `timestamp`.
   * `ShotRecord` contains built-in serializers for **Visualizer.coffee** and **Beanconqueror** schema exports.
