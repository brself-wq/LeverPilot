# ADR 009: BLE Fault-Tolerance, Telemetry Continuity & Sensor Staleness Policy
#architecture/adr #ble #telemetry #heuristics #fault-tolerance #beanconqueror

**Status:** Accepted & Implemented  
**Date:** September 20, 2026 (Updated: September 26, 2026)  
**Author:** Ben Self  
**Deciders:** Architecture Team, LeverPilot Core  
**Target:** `EspressoBLE`, `LeverPilot/Engine/BLETelemetryProvider`, `LeverPilot/Engine/ShotCoordinator`, `LeverPilot/Views/BaristaHUDView`  

---

## 1. Context & Problem Statement

Real-world manual lever espresso extraction paired with wireless Bluetooth Low Energy (BLE) peripherals (Bookoo Scale and Bookoo Pressure Transducer) introduces radio link edge cases that do not occur in wired or simulated environments:

1. **RF Packet Drops & Arrival Jitter**: CoreBluetooth notification packets occasionally stall for 500ms to 2.0s due to 2.4 GHz interference, physical obstruction, or connection interval latency.
2. **The "Dead-Flow" False Cutoff Trap**: In `ShotCoordinator`, an extraction is automatically concluded if liquid flow drops below threshold (<= 0.15 mL/s for 2.0s). If a scale drops packets or stalls, raw weight updates halt. Naive implementations interpret sensor silence as zero flow, falsely terminating the barista’s live extraction mid-pull.
3. **Regression Derivative Spikes**: The 6-sample rolling linear regression calculates flow rate as a derivative of weight over time (dw/dt). If packets resume after a 1.5s silence with a timestamp jump or burst arrivals, standard formulas compute wild mathematical artifacts (e.g. flow spiking to 18+ mL/s).
4. **Mid-Flight Reconnect Invalidation**: When a peripheral reconnects mid-extraction, naive initializers fire tare commands or reset timers, obliterating cumulative yield and desynchronizing the extraction clock.
5. **Silent Radio Dropouts**: If Bluetooth is disabled in Control Center or unauthorized, the application previously failed silently with background logs, stranding the barista.

---

## 2. Architectural Decisions

Drawing on empirical heuristics proven in the field by Beanconqueror, the digital twin enforces seven core fault-tolerance invariants:

### 2.1. Dual-Channel Sensor Staleness & Heartbeat Watchdogs
Both hardware slots (`scale` and `pressure`) maintain independent packet heartbeat timestamps (`lastPacketDate`).
* **Degraded / Stale Threshold (500ms)**: If no GATT notification arrives within 500ms, the sensor slot is flagged as `isStale = true`.
* **Telemetry Health Metadata**: `MachineFrame` and `BLETelemetryProvider` expose active channel health flags (`isScaleStale`, `isPressureStale`) alongside raw numerical values.

### 2.2. Weight Latching Invariant (No Drop to 0.0g)
During scale packet silence or transient disconnection:
* The sample-and-hold buffer **latches onto the last verified positive weight reading** (`lastKnownWeight`).
* The system is **strictly forbidden from falling back to 0.0g** during active extraction. This prevents catastrophic downward spikes on the HUD chart and preserves cumulative yield.

### 2.3. Dead-Flow Auto-Stop Suppression Under Signal Degradation
To prevent premature shot cutoff during radio interruptions:
* The `ShotCoordinator` dead-flow watchdog (<= 0.15 mL/s for 2.0s) is **suspended whenever `isScaleStale` is active**.
* The auto-stop rule evaluates strictly against *measured zero flow* (connected scale reporting unchanging weight), never against *sensor silence* (missing packets).

### 2.4. Regression Gap Re-Anchoring
To eliminate dw/dt rate-of-change spikes when packet flow resumes after a gap:
* If the time delta between incoming scale packets exceeds 500ms (delta_t > 0.5s), the 6-sample OLS regression history (`weightHistory`) is **purged and re-anchored**.
* Flow calculation resumes only after accumulating 3 fresh, contiguous packets within standard timing tolerances.

### 2.5. Mid-Flight Reconnection Immunity
Re-establishing a Bluetooth connection while the machine is in `.extracting` must never corrupt the active extraction:
* **No Re-Tare**: The manager is strictly forbidden from issuing a hardware tare command on reconnect.
* **No Timer Reset**: The scale onboard timer must not be zeroed or re-initialized.
* **No HUD Chart Wipe**: The HUD chart retains its active curve and continues uninterrupted.

### 2.6. Listener Hygiene on Auto-Reconnect
To prevent duplicate callback leaks and notification stacking when a peripheral disconnects and reconnects multiple times:
* Existing characteristic subscriptions and continuation listeners are explicitly torn down before re-attaching notifications.

### 2.7. Granular CoreBluetooth State Surfacing & User Alerts
* **Console Deck Alert**: If Bluetooth is `.poweredOff` or `.unauthorized`, pre-flight arming is blocked with an actionable alert routing the barista to iOS Settings.
* **HUD Signal Banner**: If a sensor drops during active extraction, an amber non-blocking badge (`SCALE SIGNAL LOST` or `PRESSURE DEVICE OFFLINE`) is displayed on the HUD without shifting layout geometry.

---

## 3. Consequences

### Positive
* **Invulnerable Extractions**: Transient radio drops or RF interference will never ruin a shot through premature auto-stop cutoffs or zero-weight spikes.
* **Continuous Flight Record**: Telemetry graphs remain smooth, monotonic, and physically plausible across packet gaps.
* **Seamless Hardware Recovery**: Moving a scale out of range and returning it resumes data ingestion without barista intervention.
* **Swift 6 Strict Concurrency Safe**: Health flags and heartbeat evaluations flow deterministically through the decoupled `MachineFrame` stream.
