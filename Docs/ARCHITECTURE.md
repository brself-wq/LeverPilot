# Architecture & Data Topology Specification

**Project:** LeverPilot  
**Target Platform:** iPadOS 17+, macOS 14+  
**Language / Concurrency:** Swift 6 (Strict Concurrency Checking)  
**Status:** MVP Candidate 0.0  
**Revision:** 2.0  
**Date:** September 26, 2026  

---

## 1. Executive Summary & Design Philosophy

LeverPilot is a high-precision digital twin and software copilot engineered for manual lever espresso platforms (specifically the Flair 58) equipped with Bluetooth transducers and smart scales, while supporting the Open Espresso Profile Format (OEPF) / Meticulous profile standard.

The application serves two distinct operational personas:
1. **The In-Flight Barista Copilot (Live Mode)**: Real-time, low-latency HUD telemetry providing target steering curves, delta guidance cues, limit guardrails, and automated shot-lifecycle detection via live Bluetooth Low Energy (BLE) hardware.
2. **The Roaster / Profile Studio (Workbench & History Mode)**: An inspection and rehearsal environment enabling profile evaluation, variable overrides, and shot replay (scrubbing historical pulls or synthetic test fixtures across any recipe).

In accordance with OEPF §4, unsupported motorized capabilities (such as motorized piston position or electrical power stages) utilize non-blocking visual approximation and pre-flight notices rather than synthetic emulation.

---

## 2. System Topology (The 5-Layer Stack)

The architecture enforces a strict unidirectional data flow. Higher layers observe lower layers; lower layers have zero knowledge of higher layers.

```
+-------------------------------------------------------------------------+
| Layer 4: Presentation & UI                                              |
| • BaristaHUDView • StageDynamicsChartView • LeftCockpitView             |
| • ExitTriggersPanelView • ProfileConsoleView • ShotHistoryBrowserView    |
+------------------------------------^------------------------------------+
                                     | Observes via @Observable / @State
+------------------------------------+------------------------------------+
| Layer 3: State & Orchestration                                          |
| ShotCoordinator (@MainActor @Observable class)                          |
| • Owns MachineState (.idle, .armed, .extracting, .shotEnded)            |
| • Tracks activeStageIndex & StageBaselines                              |
| • Evaluates stage transitions & auto-start / auto-stop heuristics       |
| • Manages guidance frame buffer and shot record synthesis               |
+------------------------------------^------------------------------------+
                                     | Consumes AsyncStream<MachineFrame>
+------------------------------------+------------------------------------+
| Layer 2: Engine & Telemetry Bridges                                     |
| +--------------------------------+  +---------------------------------+ |
| | ProfileExecutionEngine         |  | TelemetryProvider               | |
| | (Pure, Stateless Struct)       |  | (Protocol Contract)             | |
| | • Trajectory interpolation     |  +---------------------------------+ |
| | • Normalized trigger progress  |  | BLETelemetryProvider (Live)     | |
| | • Limit guardrail checks       |  | ScenarioTelemetryProvider (Sim) | |
| +--------------------------------+  +---------------------------------+ |
+------------------------------------^------------------------------------+
                                     | Streams Hardware / Mock Telemetry
+------------------------------------+------------------------------------+
| Layer 1: Hardware & Transceivers                                        |
| • EspressoBLEManager (CoreBluetooth central manager)                    |
| • BookooScaleDriver (GATT notifications / weight streaming)             |
| • BookooPressureDriver (GATT notifications / pressure streaming)        |
| • MeticulousServer (Embedded loopback listener for Beanconqueror)       |
+------------------------------------^------------------------------------+
                                     | Validates & Conforms
+------------------------------------+------------------------------------+
| Layer 0: OEPF Domain & Contracts                                        |
| • MeticulousProfile • MachineFrame • GuidanceFrame                      |
| • ShotRecord • SensorKey • MachineConfig                                |
+-------------------------------------------------------------------------+
```

---

## 3. Concurrency & Isolation Model (Swift 6)

1. **Stateless Core Engine (`ProfileExecutionEngine`)**:
   * Marked `nonisolated struct` with `Sendable` conformance.
   * Maintains **zero mutable state**, no internal timers, no background tasks, and no actor hops.
   * Operates as a pure mathematical function:
     `f(Stage, MachineFrame, StageBaseline, FinalWeight) -> StageEvaluationResult`
2. **Orchestrator (`ShotCoordinator`)**:
   * Isolated to `@MainActor` and marked `@Observable`.
   * Serves as the single source of truth for the active shot session, updating UI-bound properties synchronously on the main thread.
3. **Telemetry Streams (`TelemetryProvider`)**:
   * `protocol TelemetryProvider: AnyObject, Sendable`.
   * Decouples asynchronous sensor notification callbacks from UI rendering using Swift's native `AsyncStream<MachineFrame>`.
4. **Hardware Driver (`EspressoBLEManager`)**:
   * Manages CoreBluetooth delegate callbacks on a dedicated queue.
   * Exposes connection status via `@Observable` for low-frequency UI state, while streaming high-frequency readings safely.
5. **Loopback Server (`MeticulousServer`)**:
   * Isolated as a Swift 6 `actor`, guaranteeing thread-safe port binding, verbose logging configuration, and historical telemetry staging off the main runloop.

---

## 4. Telemetry Ingestion & In-Flight Processing

### 4.1. Metronome Ingestion Engine
Because the Bluetooth scale and pressure transducer operate on unsynchronized internal clocks and transmit packets with variable radio latency, the host application does not process incoming BLE packets directly in the UI.

1. **Sample-and-Hold Buffer**: Incoming raw packets from `EspressoBLE` asynchronously update a thread-safe cache:
   * `rawPressure` + timestamp
   * `rawWeight` + timestamp
2. **Dual-Channel Staleness Watchdog**:
   * Evaluates packet heartbeats independently for chamber pressure and cup weight.
   * If no packet arrives for > 500ms, the corresponding sensor is marked stale (`isScaleStale`, `isPressureStale`).
3. **Weight Latching Policy (ADR-009)**:
   * When scale packets stall or drop, the buffer **latches onto the last known valid weight**, strictly preventing drops to 0.0g during active extractions.
4. **10 Hz Clock Metronome**: A dedicated loop ticks precisely every 100ms (+/- 1ms):
   * Emits a synchronized, time-stamped `MachineFrame` with active sensor health metadata to the `ShotCoordinator`.

### 4.2. Signal Conditioning Algorithms

#### Flow Rate Derivation (Rolling Linear Regression)
Raw differentiation (`dw/dt`) amplifies discrete scale quantization noise and Bluetooth jitter, producing erratic spikes. 
The system buffers the most recent 6 samples (500ms window) and derives flow rate as the slope of the linear regression best-fit line:

$$\text{Flow Rate} = \frac{N \sum (t \cdot w) - \sum t \sum w}{N \sum (t^2) - (\sum t)^2}$$

This provides a responsive, smooth flow curve with minimal phase lag (< 60ms).

#### Regression Gap Re-Anchoring
To prevent wild `dw/dt` rate-of-change spikes when packet flow resumes after an RF gap:
* If the time delta between incoming scale packets exceeds 500ms ($\Delta t > 0.5\text{s}$), the 6-sample OLS regression history is **purged and re-anchored**.
* Flow calculation resumes only after accumulating 3 fresh, contiguous packets within standard timing tolerances.

#### Delta Deadbands
The UI `DeltaBadge` compares actual values against target setpoints using intentional deadbands:
* **Pressure Deadband**: $\pm 0.4\text{ bar}$.
* **Flow Deadband**: $\pm 0.3\text{ mL/s}$.
Variations within this window display as `"ON TARGET"`, preventing UI flickering.

#### HUD Chart Sliding Viewport Window (`StageDynamicsChartView`)
To preserve high-resolution visual feedback for manual lever pulls of open-ended duration without compressing the curve:
* The HUD dynamics chart enforces a bounded viewport window (`slidingWindowSpan = 25.0s`).
* **Phase A ($t_{\text{local}} \le 25.0\text{s}$)**: The domain is anchored at `0.0 ... max(25.0, horizon)`. The actual pull line grows from left to right.
* **Phase B ($t_{\text{local}} > 25.0\text{s}$)**: The chart automatically slides its visible X-domain: `(t_local - 25.0) ... t_local`. The active extraction coordinate remains pinned near the right edge of the chart at full visual resolution while earlier points roll out of view.

---

## 5. Shot Lifecycle & Extraction Heuristics

```
[.idle] ---> Select Profile ---> [.armed] (BLE Tare & Timer Reset)
                                      |
                                      | Pressure >= autoStartPressure (Auto-Start)
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
```

### 5.1. Auto-Start (Pressure Exclusivity)
* When state is `.armed`, extraction begins (`.extracting`, $t = 0.0\text{s}$) strictly when:
  $$\text{Chamber Pressure} \ge \text{autoStartPressure (default 0.5 bar)}$$
* Scale weight is intentionally excluded from auto-start evaluation. This prevents resting a cup on the scale, pouring kettle water into the brew chamber, or table vibrations from prematurely triggering the extraction clock.

### 5.2. Auto-Stop Safeguards (Beanconqueror Protocol)
To prevent premature termination during long pre-infusion blooms or slow saturation, auto-stop checks activate only after passing dual time and yield preconditions:
1. $\text{Elapsed Time} \ge 5.0\text{s}$, AND
2. $\text{Cup Weight} \ge 5.0\text{g}$ OR $\text{Yield} \ge \text{Dose}$ (1:1 ratio)

Once preconditions are satisfied, the shot transitions to `.shotEnded` if:
$$\text{Smoothed Flow} \le \text{deadFlowThreshold (default 0.15 mL/s) sustained for deadFlowSustainDuration (default 2.0s)}$$

**Dead-Flow Signal Loss Interlock**: Auto-stop heuristics are **temporarily suspended whenever scale telemetry is marked stale (`isScaleStale`)**. Missing scale packets are never interpreted as an intentional lever pull stop.

### 5.3. Post-Shot Retroactive Tail Trimming
When the dead-flow watchdog confirms the end of the shot, `ShotCoordinator` scans backwards through `capturedSamples` to find the initial timestamp where flow permanently fell below threshold. The archived duration and final yield are locked to that sample, and trailing silent samples are trimmed.

### 5.4. Profile Complete & Holding Setpoint State
Reaching the final recipe trigger enters `isProfileComplete`, holding the commanded setpoint steady and monitoring flow cutoff without terminating the pull mid-stream. Macro extraction conclusion is supervised strictly by physical telemetry (the sustained dead-flow watchdog) or manual barista abort.

---

## 6. Storage, Persistence, and State Boundaries

1. **Native Files App Integration**:
   * User profiles live in `<Documents>/Profiles/*.json`.
   * Completed shot records live in `<Documents>/ShotLogs/*.json`.
   * With `UIFileSharingEnabled = true` (`LSSupportsOpeningDocumentsInPlace = true`), users manage recipes and logs directly via the iPadOS / macOS Files app.
   * A one-time silent migration moves legacy profiles and logs from `Application Support` to `Documents`.
2. **Canonical Profile Assets**:
   * Bundled JSON profiles (e.g. factory presets) are read-only templates.
   * User adjustments made in the pre-flight UI generate an **ephemeral in-memory copy** via `resolveForExecution()`. Canonical files on disk remain untouched.
3. **Decoupled Delivery Ledger (Sidecar)**:
   * Historical shot logs are immutable flight records.
   * Beanconqueror export state is recorded in `UserDefaults` (`bq.delivered_shot_ids`), preserving the physical integrity of shot JSON files.
