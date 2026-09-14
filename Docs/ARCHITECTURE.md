# Architecture & Data Topology Specification

**Project:** BaristaPilot (formerly VirtualEspressoMachine)  
**Target Platform:** iOS 17+, macOS 14+  
**Language / Concurrency:** Swift 5.9 / Swift 6 (Strict Concurrency Checking)  
**Status:** Accepted Architecture Blueprint  
**Revision:** 1.2  
**Date:** September 2026  

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
┌─────────────────────────────────────────────────────────────────────────┐
│ Layer 4: Presentation & UI │
│ • BaristaHUDView • StageDynamicsChartView • LeftCockpitView │
│ • SimulatorControlDock • ExitTriggersPanelView • ProfileInspector │
└────────────────────────────────────▲────────────────────────────────────┘
│ Observes via @Observable / State
┌────────────────────────────────────┴────────────────────────────────────┐
│ Layer 3: State & Orchestration │
│ ShotCoordinator (Actor) │
│ • Owns MachineState (.ready, .armed, .extracting, .shotEnded) │
│ • Tracks activeStageIndex & StageBaselines │
│ • Evaluates stage transitions & auto-start / auto-stop heuristics │
│ • Routes frames to Pipeline A (Logger) and Pipeline B (Guidance) │
└────────────────────────────────────▲────────────────────────────────────┘
│ Consumes AsyncStream<MachineFrame>
┌────────────────────────────────────┴────────────────────────────────────┐
│ Layer 2: Engine & Telemetry Bridges │
│ ┌────────────────────────────────┐ ┌──────────────────────────────┐ │
│ │ ProfileExecutionEngine │ │ TelemetryProvider │ │
│ │ (Pure, Stateless Struct) │ │ (Protocol Contract) │ │
│ │ • Trajectory interpolation │ ├──────────────────────────────┤ │
│ │ • Normalized trigger progress │ │ BLETelemetryProvider (Live) │ │
│ │ • Limit guardrail checks │ │ ReplayTelemetryProvider (Sim)│ │
│ └────────────────────────────────┘ └──────────────────────────────┘ │
└────────────────────────────────────▲────────────────────────────────────┘
│ Streams Hardware / Mock Telemetry
┌────────────────────────────────────┴────────────────────────────────────┐
│ Layer 1: Hardware & Transceivers │
│ • EspressoBLEManager (CoreBluetooth central manager) │
│ • BookooScaleDriver (GATT 0xFFE / weight streaming) │
│ • BookooPressureDriver (GATT 0xFFF / pressure streaming) │
│ • PlaybackEngine (10 Hz scenario timeline replay) │
└────────────────────────────────────▲────────────────────────────────────┘
│ Validates & Conforms
┌────────────────────────────────────┴────────────────────────────────────┐
│ Layer 0: OEPF Domain & Contracts │
│ • MeticulousProfile • MachineFrame • GuidanceFrame │
│ • ShotRecord • SensorKey • MachineConfig │
└─────────────────────────────────────────────────────────────────────────┘
code
Code
---

## 3. Concurrency & Isolation Model (Swift 6)

1. **Stateless Core Engine (`ProfileExecutionEngine`)**:
   * Marked `nonisolated struct` with `Sendable` conformance.
   * Maintains **zero mutable state**, no internal timers, no background tasks, and no actor hops.
   * Operates as a pure mathematical function:
     $$f(\text{Stage}, \text{MachineFrame}, \text{StageBaseline}, \text{FinalWeight}) \to \text{StageEvaluationResult}$$
2. **Orchestrator (`ShotCoordinator`)**:
   * Isolated to `@MainActor` and marked `@Observable`.
   * Serves as the single source of truth for the active shot session, updating UI-bound properties synchronously on the main thread.
3. **Telemetry Streams (`TelemetryProvider`)**:
   * `protocol TelemetryProvider: AnyObject, Sendable`.
   * Decouples asynchronous sensor notification callbacks from UI rendering using Swift's native `AsyncStream<MachineFrame>`.
4. **Hardware Driver (`EspressoBLEManager`)**:
   * Manages CoreBluetooth delegate callbacks on a dedicated queue.
   * Mutates connection lifecycle flags via `@Observable` for low-frequency UI changes, but routes high-frequency (10–20 Hz) numerical readings through a decoupled callback to avoid SwiftUI view evaluation thrashing.

---

## 4. Telemetry Ingestion & In-Flight Processing

### 4.1. The Metronome Ingestion Engine
Because the Bluetooth scale and pressure transducer operate on unsynchronized internal clocks and transmit packets with variable radio latency, the host application does not process incoming BLE packets directly in the UI.

1. **Sample-and-Hold Buffer**: Incoming raw packets from `EspressoBLE` asynchronously update a thread-safe cache:
   * `latestWeight: Double` + `latestWeightTimestamp: Date`
   * `latestPressure: Double` + `latestPressureTimestamp: Date`
2. **10 Hz Clock Metronome**: A dedicated loop ticks precisely every $100\text{ms}$ ($\pm 1\text{ms}$):
   * Retrieves the latest cached sensor values.
   * Evaluates the staleness watchdog (flags an alert if no packet was received within $500\text{ms}$).
   * Computes derived smoothed flow rate.
   * Emits a synchronized, time-stamped `MachineFrame` to the `ShotCoordinator`.

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
Raw differentiation ($\Delta w / \Delta t$) amplifies discrete scale quantization noise and Bluetooth jitter, producing massive erratic spikes. 
The system buffers the most recent 6 samples ($500\text{ms}$ window) and derives flow rate as the slope of the linear regression best-fit line:

$$\text{Flow Rate} = \frac{N \sum (t \cdot w) - \sum t \sum w}{N \sum (t^2) - (\sum t)^2}$$

This provides a responsive, smooth flow curve with less than $60\text{ms}$ phase lag.

#### Delta Bandwidth (Deadbands)
The UI `DeltaBadge` compares actual values against target setpoints using intentional deadbands:
* **Pressure Deadband**: $\pm 0.4\text{ bar}$.
* **Flow Deadband**: $\pm 0.3\text{ mL/s}$.
Variations within this window display as `"ON TARGET"`, preventing UI flickering.

#### Limit Guardrail Hysteresis
To prevent rapid alarm toggling when a manual lever pull hovers near a safety ceiling:
* **Alarm Trip**: Triggered instantly when $\text{Actual} \ge \text{LimitValue}$ (e.g. $9.0\text{ bar}$).
* **Alarm Reset**: Requires $\text{Actual} \le \text{LimitValue} - 0.5\text{ bar}$ (e.g. falls below $8.5\text{ bar}$) before clearing.

#### Decay Trigger Persistence
To prevent brief muscle tremors on a manual lever from prematurely tripping a descending exit trigger:
* A decaying condition (e.g. $\text{pressure} \le 4.0\text{ bar}$) must evaluate to `true` for **two consecutive 100ms ticks** ($200\text{ms}$) before triggering stage advancement.

---

## 5. Shot Lifecycle & Extraction Heuristics

The `ShotCoordinator` supervises macro state transitions:
code
Code
[.idle] ──► Select Profile ──► [.armed] (BLE Tare & Timer Reset)
                                      │
                                      │ Pressure >= 0.5 bar (Auto-Start)
                                      ▼
                                 [.extracting] ◄──┐
                                      │           │ Evaluate Stage Triggers
                 Check Auto-Stop      │           │ Advance Stage & Baseline
                 or Weight Cutoff     └───┬───────┘
                                          ▼
                                     [.shotEnded] (BLE Stop Timer)
                                          │
                                          │ Clean / Reset
                                          ▼
                                       [.idle]
code
Code
### 5.1. Auto-Start (Pressure Exclusivity)
* When state is `.armed`, extraction begins (`.extracting`, $t = 0.0\text{s}$) strictly when:
  $$\text{Chamber Pressure} \ge 0.5\text{ bar}$$
* Scale weight is intentionally excluded from auto-start evaluation. This prevents resting a cup on the scale, pouring kettle water into the brew chamber, or table vibrations from prematurely triggering the extraction clock.

### 5.2. First Drip Event
* Recorded as an informational metadata marker at the exact timestamp when:
  $$\text{Weight} \ge 0.5\text{g}$$
* Used to calculate and display pre-infusion puck saturation duration without modifying the main shot clock.

### 5.3. Auto-Stop Safeguards (Beanconqueror Protocol)
To prevent premature termination during long pre-infusion blooms or slow saturation, auto-stop checks activate only after passing dual time and yield preconditions:
1. $\text{Elapsed Time} \ge 5.0\text{s}$, **AND**
2. $\text{Cup Weight} \ge 5.0\text{g}$ OR $\text{Yield} \ge \text{Dose}$ (1:1 ratio)

Once preconditions are satisfied, the shot transitions to `.shotEnded` if:
$$\text{Smoothed Flow} \le 0.1\text{ g/s sustained continuously for } 2.0\text{ seconds}$$
OR
$$\text{Current Weight} \ge \text{Target Final Weight}$$

### 5.4. Post-Shot Tail Trimming
Because confirmation of dead flow requires $2.0\text{s}$ of sustained low flow, the final recorded shot duration in `ShotRecord` subtracts this confirmation tail:
$$\text{Duration}_{\text{final}} = \text{Duration}_{\text{actual}} - 2.0\text{s}$$

### 5.5. Physical Lever Lifecycle vs. Profile Execution Boundary
On automated robotic machines (like Meticulous), recipe profiles command actuators directly; reaching the final stage exit trigger physically stops the motor.

On a manual lever (Flair 58), the profile acts as an in-flight flight director:
1. **Early Terminations**: The barista may release the lever early (due to choking or channeling), which is cleanly caught by the 2.0s dead-flow watchdog or manual abort.
2. **Extended Overrun Pulls**: If liquid is still flowing after the profile's final stage concludes, physical extraction continues. Future architecture will introduce an **Overrun / Free-Flow** state keeping the HUD active until the dead-flow watchdog or manual abort terminates the shot.

### 5.6. Peripheral Hardware Timer Synchronization
* On transition to `.armed`, the application issues hardware BLE commands to tare the scale and reset the onboard timer.
* On transition to `.extracting`, the application triggers the scale's onboard timer start.
* On transition to `.shotEnded` or `.idle` (abort), the scale's timer is stopped.

---

## 6. Mathematical Evaluation & OEPF Compliance

### 6.1. Stage Baselines
The `StageBaseline` captures the snapshot state at the instant of stage entry:
* `startTime`: Shot timestamp at stage entry.
* `startWeight`: Accumulated cup weight at stage entry.
* `entryPressure`: Actual pressure at stage entry.
* `entryFlow`: Actual flow at stage entry.

### 6.2. Target Setpoint Interpolation
For a given domain progress value $x$ across defined knots $[p_0, p_1]$:
* **Linear (`.linear`)**: Standard linear interpolation:
  $$y(x) = p_0.y + \left(\frac{x - p_0.x}{p_1.x - p_0.x}\right)(p_1.y - p_0.y)$$
* **Zero-Order Hold (`.none`)**: Instantaneous step. Holds $p_0.y$ constant across $x \in [p_0.x, p_1.x)$ without ramping.
* **Overrun Flatline**: For any $x \ge p_{\text{last}}.x$, $y(x) = p_{\text{last}}.y$.

### 6.3. Continuous Trigger Progress Formula
Ascending ($\ge$) and decaying ($\le$) exit triggers compute normalized progress ($0.0 \to 1.0$) for HUD racetrack meters:

$$\text{Progress} = \text{clamp}\left(\frac{V_{\text{current}} - V_{\text{start}}}{V_{\text{target}} - V_{\text{start}}}, \ 0.0, \ 1.0\right)$$

* **Ascending Trigger** (e.g. $2 \to 8\text{ bar}$): At $5\text{ bar} \implies (5 - 2) / (8 - 2) = 3 / 6 = \mathbf{50\%}$.
* **Decaying Trigger** (e.g. $9 \to 4\text{ bar}$): At $6.5\text{ bar} \implies (6.5 - 9) / (4 - 9) = -2.5 / -5 = \mathbf{50\%}$.

### 6.4. Relative vs. Absolute Trigger Normalization
Exit triggers evaluate according to their `relative` flag (which defaults to `false` when omitted):

1. **Relative Triggers (`relative: true`)**:
   - **Time**: $t_{\text{local}} = \max(0.0, \ t_{\text{actual}} - t_{\text{baseline}})$.
   - **Weight**: $w_{\text{local}} = \max(0.0, \ w_{\text{actual}} - w_{\text{baseline}})$.
   - **Pressure / Flow**: Evaluated relative to stage entry baseline ($V_{\text{actual}} - V_{\text{baseline}}$).

2. **Absolute Triggers (`relative: false`, default)**:
   - **Time**: $t_{\text{shot}} = t_{\text{actual}}$ (Total extraction elapsed time since auto-start trip at $t = 0.0\text{s}$). Progress is mapped along the stage span:
     $$\text{Progress} = \text{clamp}\left(\frac{t_{\text{actual}} - t_{\text{baseline}}}{t_{\text{target}} - t_{\text{baseline}}}, \ 0.0, \ 1.0\right)$$
   - **Weight**: Evaluated against total accumulated cup weight ($w_{\text{actual}}$).
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
