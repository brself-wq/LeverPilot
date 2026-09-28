# ADR 008: Centralized Settings, Domain Heuristics & Invariant Boundary Management
#architecture/adr #settings #configuration #machine-config #refactoring

**Status:** Accepted & Implemented  
**Date:** September 19, 2026 (Updated: September 26, 2026)  
**Author:** Ben Self  
**Deciders:** Architecture Team, LeverPilot Core  
**Target:** `Stores/SettingsStore`, `Views/SettingsView`, `Interfaces/MachineConfig`, `Engine/ShotCoordinator`  

---

## 1. Context & Problem Statement

As LeverPilot evolved from a simulator harness into an operational espresso copilot, prototype magic numbers and hardcoded literals proliferated across the codebase:
1. **The Silent Config Bypass**: `MachineConfig.swift` defined an extensible `autoStartRule` defaulting to `0.8 bar`, yet `ShotCoordinator.processTelemetryFrame` hardcoded an inline check for `currentPressure >= 0.5 bar`, ignoring its own configuration model.
2. **Duplicated Workflow Defaults**: The reference ground coffee dose (`18.0g`) was independently hardcoded in `ProfileConsoleView`, `ProfileVariableOverridesView`, and `ShotCoordinator`.
3. **Console Flooding**: `MeticulousServer` emitted high-frequency `print()` statements for every incoming HTTP request line, OPTIONS preflight, and Socket.IO heartbeat ping, obscuring critical engine and BLE logs.
4. **Display Sleep During Long Pulls**: Without explicit display power management, the iPad screen would dim or sleep during slow pre-infusions.

---

## 2. Architectural Decisions

### 2.1. The 3-Tier Constant & Settings Hierarchy
To maintain clean separation of concerns, all numerical and behavioral values are strictly partitioned into three tiers:

* **Tier A: System & Protocol Invariants (Compiled Constants)**
  - *Definition*: Immutable physical, mathematical, or platform standards that **no user should adjust**.
  - *Examples*: 10 Hz sampling metronome ($100\text{ms}$ interval), OLS linear regression buffer size (6 samples), loopback IP (`127.0.0.1`), HUD sliding window span ($25.0\text{s}$), and Bluetooth GATT Service UUIDs.
  - *Storage*: Scoped static properties or private constants. Never exposed in user-facing settings.

* **Tier B: Machine & Extraction Heuristics (`MachineConfig`)**
  - *Definition*: Operational rules governing the physical digital twin and extraction lifecycle.
  - *Examples*: `autoStartRule` (sensor channel, comparison operator, threshold), `autoStop` cutoff flow rate ($0.15\text{ mL/s}$), sustain duration ($2.0\text{s}$), and deadbands.
  - *Storage*: `MachineConfig` struct. Consumed directly by `ShotCoordinator` and `ProfileExecutionEngine`.

* **Tier C: User Preferences & Workflow Defaults (`SettingsStore`)**
  - *Definition*: Persistent user choices that adapt the application to the barista’s coffee equipment, basket size, and workflow.
  - *Storage*: `@Observable @MainActor SettingsStore`, automatically persisted in `UserDefaults`.

```
┌────────────────────────────────────────────────────────┐
│ Tier C: User Preferences (SettingsStore)               │
│ • defaultDose • autoStartPressure • deadFlowThreshold  │
│ • deadFlowSustainDuration • meticulousPort             │
│ • verboseServerLogging • keepDisplayAwake              │
└───────────────────────────┬────────────────────────────┘
                            │ Hydrates on Arm / Launch
                            ▼
┌────────────────────────────────────────────────────────┐
│ Tier B: Machine Heuristics (MachineConfig)             │
│ • autoStartRule.threshold • autoStop.cutoffRule        │
│ • autoStop.sustainDuration • tolerances.deadbands      │
└───────────────────────────┬────────────────────────────┘
                            │ Consumed Every Frame
                            ▼
┌────────────────────────────────────────────────────────┐
│ Tier A: Engine Invariants (ShotCoordinator / Providers)│
│ • 10 Hz Metronome • OLS Regression Buffer • GATT UUIDs │
│ • StageDynamicsChartView.slidingWindowSpan (25.0s)     │
└────────────────────────────────────────────────────────┘
```

### 2.2. The Line: Defining the 7 Essential Settings
An espresso machine copilot must feel like an industrial appliance, not a software debugger. We formally draw the line at **7 user-tunable settings**:
1. **Default Ground Dose** ($18.0\text{g}$ baseline, range $7.0\text{g} \dots 30.0\text{g}$): Adapts the console to the barista's specific basket capacity.
2. **Auto-Start Pressure Gate** ($0.5\text{ bar}$ baseline, range $0.2 \dots 3.0\text{ bar}$): Accommodates mechanical lever play across different manual lever setups.
3. **Dead-Flow Cutoff Threshold** ($0.15\text{ mL/s}$ baseline, range $0.05 \dots 1.0\text{ mL/s}$): Prevents premature cutoffs on slow-dripping dark roasts or prolonged saturation.
4. **Dead-Flow Sustain Duration** ($2.0\text{s}$ baseline, range $1.0 \dots 10.0\text{s}$): Controls confirmation latency before locking shot duration.
5. **Meticulous Loopback Port** (`8080` baseline, range $1024 \dots 65535$): Prevents local port collisions on shared development Macs or iPads.
6. **Verbose Server Traffic Logging** (`false` baseline): Dynamically mutes Socket.IO and HTTP polling logs in stdout.
7. **Keep Display Awake While Brewing** (`true` baseline): Prevents the display from dimming or sleeping while armed or actively extracting.

### 2.3. Dynamic Reconfiguration Architecture
Settings updates take effect immediately:
* **Dynamic Log Muting**: Toggling `verboseServerLogging` flips `MeticulousServer.shared.verboseLogging` in memory on the next runloop tick.
* **Server Listener Guard**: `MeticulousServer.configure(port:verbose:)` restarts `NWListener` only if the port number has actually changed, eliminating port collisions.
* **Shot Synchronization**: `LeverPilotApp.launchShot` invokes `coordinator.configure(from: settingsStore)` immediately prior to arming, ensuring every extraction evaluates the latest user thresholds.

---

## 3. Consequences

### Positive
* **Elimination of Silent Bypasses**: `ShotCoordinator` strictly enforces `machineConfig.autoStartRule.isSatisfied(by: frame)`.
* **Zero Hardcoded Recipe Doses**: Changing default dose in Settings propagates seamlessly into initial console sessions and recipe override resets.
* **Quiet, High-Signal Logs**: Standard stdout remains clean, surfacing real Bluetooth events and stage transitions while retaining instant on-demand network traffic inspection.
