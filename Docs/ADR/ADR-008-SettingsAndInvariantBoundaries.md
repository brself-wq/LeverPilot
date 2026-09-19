# ADR 008: Centralized Settings, Domain Heuristics & Invariant Boundary Management
#architecture/adr #settings #configuration #machine-config #refactoring

**Status:** Accepted & Implemented  
**Date:** September 19, 2026  
**Author:** Ben Self  
**Deciders:** Architecture Team, BaristaPilot Core  
**Target:** `Stores/SettingsStore`, `Views/SettingsView`, `Interfaces/MachineConfig`, `Engine/ShotCoordinator`  

---

## 1. Context & Problem Statement

As BaristaPilot evolved from a simulator harness into an operational espresso copilot, prototype magic numbers and hardcoded literals proliferated across the codebase:
1. **The Silent Config Bypass**: `MachineConfig.swift` defined an extensible `autoStartRule` defaulting to `0.8 bar`, yet `ShotCoordinator.processTelemetryFrame` hardcoded an inline check for `currentPressure >= 0.5 bar`, completely ignoring its own configuration model.
2. **Duplicated Workflow Defaults**: The reference ground coffee dose (`18.0g`) was independently hardcoded in `ProfileConsoleView`, `ProfileVariableOverridesView`, and `ShotCoordinator`.
3. **Console Flooding**: `MeticulousServer` emitted high-frequency `print()` statements for every incoming HTTP request line, OPTIONS preflight, and Socket.IO heartbeat ping, obscuring critical engine and BLE logs.
4. **Hardcoded Viewport Geometries**: The HUD chart viewport window was fixed at `25.0s`, and the server listener was statically bound to port `8080`.

Without a centralized settings authority, adjusting the machine for different roast styles, different portafilter basket capacities, or local network port collisions required source code modifications.

---

## 2. Architectural Decisions

### 2.1. The 3-Tier Constant & Settings Hierarchy
To prevent architectural bloat and maintain clear code separation, all numeric values are strictly divided into three tiers:

* **Tier A: System & Protocol Invariants (Compiled Constants)**
  - *Definition*: Immutable physical, mathematical, or platform standards that **no user should ever adjust**.
  - *Examples*: 10 Hz sampling metronome ($100\text{ms}$ interval), OLS linear regression buffer size (6 samples), loopback IP (`127.0.0.1`), Socket.IO packet framing (`40{"sid"...}`), and Bluetooth GATT Service UUIDs.
  - *Storage*: Scoped enums or private file constants. Never exposed in user-facing settings.

* **Tier B: Machine & Extraction Heuristics (`MachineConfig`)**
  - *Definition*: Operational rules governing the physical digital twin and extraction lifecycle.
  - *Examples*: `autoStartRule` (sensor channel, comparison operator, threshold), `autoStop` cutoff flow rate ($0.15\text{ mL/s}$), sustain duration ($2.0\text{s}$), and deadbands.
  - *Storage*: `MachineConfig` struct. Consumed directly by `ShotCoordinator` and `ProfileExecutionEngine`. **Engine classes are strictly forbidden from checking raw numeric literals directly.**

* **Tier C: User Preferences & Workflow Defaults (`SettingsStore`)**
  - *Definition*: Persistent user choices that adapt the application to the barista’s coffee equipment, basket size, and iPad layout.
  - *Storage*: `@Observable @MainActor SettingsStore`, automatically persisted in `UserDefaults`.
┌────────────────────────────────────────────────────────┐
│ Tier C: User Preferences (SettingsStore) │
│ • defaultDose • autoStartPressure • deadFlowThreshold │
│ • deadFlowSustainDuration • meticulousPort • windowSpan│
└───────────────────────────┬────────────────────────────┘
│ Hydrates on Arm / Launch
▼
┌────────────────────────────────────────────────────────┐
│ Tier B: Machine Heuristics (MachineConfig) │
│ • autoStartRule.threshold • autoStop.cutoffRule │
│ • autoStop.sustainDuration • tolerances.deadbands │
└───────────────────────────┬────────────────────────────┘
│ Consumed Every Frame
▼
┌────────────────────────────────────────────────────────┐
│ Tier A: Engine Invariants (ShotCoordinator / Providers)│
│ • 10 Hz Metronome • OLS Regression Buffer • GATT UUIDs │
└────────────────────────────────────────────────────────┘
code
Code
### 2.2. The Line: Defining the 7 Essential Settings
An espresso machine copilot must feel like an industrial appliance, not an engineering debugger. We formally draw the line at **7 user-tunable settings**:
1. **Default Ground Dose** ($18.0\text{g}$ baseline, range $7.0\text{g} \dots 30.0\text{g}$): Adapts the console to the barista's specific basket capacity.
2. **Auto-Start Pressure Gate** ($0.5\text{ bar}$ baseline, range $0.2 \dots 3.0\text{ bar}$): Accommodates mechanical lever play across different manual lever setups.
3. **Dead-Flow Cutoff Threshold** ($0.15\text{ mL/s}$ baseline, range $0.05 \dots 1.0\text{ mL/s}$): Prevents premature cutoffs on slow-dripping dark roasts or prolonged saturation.
4. **Dead-Flow Sustain Duration** ($2.0\text{s}$ baseline, range $1.0 \dots 10.0\text{s}$): Controls confirmation latency before locking shot duration.
5. **Meticulous Loopback Port** (`8080` baseline, range $1024 \dots 65535$): Prevents local port collisions on shared development Macs or iPads.
6. **Verbose Server Traffic Logging** (`false` baseline): Dynamically mutes Socket.IO and HTTP polling logs in stdout.
7. **Chart Sliding Window Span** ($25.0\text{s}$ baseline, range $10.0 \dots 60.0\text{s}$): Customizes horizontal time-horizon resolution on the Barista HUD.

*Excluded / Kept as Constants*: Beanconqueror precondition gates ($5.0\text{s} / 5.0\text{g}$), HUD delta deadbands ($0.4\text{ bar} / 0.3\text{ mL/s}$), and OLS regression samples (6).

### 2.3. Dynamic Reconfiguration Architecture
Settings updates take effect immediately without requiring application or server restarts:
* **Dynamic Log Muting**: Toggling `verboseServerLogging` flips `MeticulousServer.shared.verboseLogging` in memory on the next runloop tick; subsequent HTTP frames immediately stop printing to stdout.
* **Server Listener Guard**: `MeticulousServer.configure(port:verbose:)` restarts `NWListener` only if the port number has actually changed, eliminating dual-listener port collisions (`Address already in use`).
* **Shot Synchronization**: `VirtualEspressoMachineApp.launchShot` invokes `coordinator.configure(from: settingsStore)` immediately prior to arming, ensuring every extraction evaluates the latest user thresholds.

### 2.4. Cross-Platform Menu Order Normalization
To resolve an iPadOS presentation anomaly where upward-expanding menus flip items into `.priority` order (placing the first item at the bottom), all navigation menus declare **`.menuOrder(.fixed)`**, guaranteeing identical top-to-bottom layout across macOS and iPadOS:
1. `Settings`
2. *(Divider)*
3. `Brew`
4. `History`
5. `Workbench` *(Disabled)*

---

## 3. Consequences

### Positive
* **Elimination of Silent Bypasses**: `ShotCoordinator` now strictly enforces `machineConfig.autoStartRule.isSatisfied(by: frame)`, restoring architectural integrity to the engine.
* **Zero Hardcoded Recipe Doses**: Changing the default dose in Settings propagates seamlessly into initial console sessions and recipe override resets.
* **Quiet, High-Signal Logs**: Standard stdout remains clean, surfacing real Bluetooth events and stage transitions while retaining instant on-demand network traffic inspection.
* **Unified State Authority**: All user configuration flows through a single `@Observable` `SettingsStore`.

### Negative / Trade-offs
* Requires explicitly passing `settingsStore` or forwarding parameters through container views to reach deeply nested chart subviews.
