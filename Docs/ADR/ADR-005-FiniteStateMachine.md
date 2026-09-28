# ADR 005: Sensor-Observed Finite State Machine (FSM) for Manual Lever Telemetry

- **Status**: Accepted & Implemented
- **Date**: 2026-09-08 (Updated: 2026-09-26)
- **Author**: Ben Self
- **Deciders**: Architecture Team, LeverPilot Core
- **Consulted**: Open Espresso Profile Format (OEPF) Community, Meticulous Firmware Review, Beanconqueror Core
- **Supersedes**: Legacy Prototype Machine Protocol & State Machine

---

## 1. Context & Problem Statement

Early prototypes of this application inherited a robotic, multi-step state machine requiring manual UI button interaction:

`ready` -> `select profile` -> `profileSelected` -> `"Set Ready"` -> `shotReady` -> `"Start"` -> `extracting` -> `cutoff` -> `shotEnded`

This model created three significant problems:

1. **UX Mismatch for Manual Lever Machines**: On a manual lever espresso machine (Flair 58), the barista’s hands are actively holding the lever, portafilter, or kettle. Forcing screen taps with wet coffee hands is high friction and unrealistic at the counter.
2. **The "Ghost State" Catch-22**: `shotReady` was an artificial blocking state. Replay frames and live test fixtures were frequently dropped as pre-shot noise.
3. **Commanded vs. Observed Architecture**: Automated machines (like Meticulous) issue actuator commands (`heating`, `retracting`, `purging`). On a Flair 58, the app possesses no actuators; the human barista is the motor. The app is an **Avionics Flight Director** observing passive Bluetooth sensors.

---

## 2. Decision

We replace the actuator-driven state machine with a **Sensor-Observed Finite State Machine**:

1. **Eliminate the `shotReady` Middleman**: Selecting/arming a profile immediately transitions to **`armed`**.
2. **Sensor-Inferred State Progression**: Leverage incoming Bluetooth telemetry (or recorded replay frames) to detect human lever actions and auto-advance machine states without screen taps.
3. **Hardware Command Hooks on Transition**: State transitions automatically drive hardware peripheral functions over Bluetooth (tare and reset scale timer on arm, start scale timer on auto-start, stop timer on shot conclusion).
4. **Soft Disconnection & Fault-Tolerance (ADR-009)**: Mid-flight BLE disconnects do **not** trigger an instant, destructive transition to `.error`. The engine enters degraded mode, holding valid metrics and suspending dead-flow auto-stops until connection recovery.
5. **Formal Core States**:
   - `idle`: Machine at rest, no profile armed.
   - `armed`: Profile loaded, scale tared and zeroed, observer listening strictly for physical lever pull.
   - `extracting`: Lever in motion, active OEPF trajectory evaluation, real-time HUD rendering.
   - `shotEnded`: Extraction complete (target yield reached or sustained dead-flow cutoff detected).

---

## 3. State Transition Matrix

```
   +-----------+
   |   idle    |<-----------------------------+
   +-----+-----+                              |
         | selectProfile(p) / arm             |
         v                                    | abort / reset
   +-----------+                              |
   |   armed   |------------------------------+
   +-----+-----+                              |
         | Auto-Start (Pressure >= 0.5 bar)   |
         v                                    |
   +-----------+                              |
   |extracting | (Holds state on BLE drop;    |
   +-----+-----+  attempts auto-reconnect)    |
         | Auto-Stop (Dead flow <= 0.15 mL/s sustained for 2.0s)
         v                                    |
   +-----------+                              |
   | shotEnded |------------------------------+
   +-----------+
```

### Detailed Transition Table

| From State | Event / Trigger | To State | Actions Taken by System |
| :--- | :--- | :--- | :--- |
| **`idle`** | `arm(profile:)` | **`armed`** | Load profile, compute initial plan curve, update stage pills, reset baselines. Send BLE tare and timer reset commands to scale. |
| **`armed`** | `pressure >= autoStartPressure` | **`extracting`** | **Auto-Start**: Snap Stage 0 `StageBaseline`, zero timer, start HUD tracking, trigger scale timer. |
| **`armed`** | `abort()` | **`idle`** | Unload active profile and clear HUD surface buffers. Send BLE stop timer command. |
| **`extracting`** | Stage exit trigger satisfied | **`extracting`** | Increment `activeStageIndex`, snap new `StageBaseline`, wipe stage chart slice. |
| **`extracting`** | Sensor signal drops (> 500ms) | **`extracting`** (Degraded) | Latch last weight; suspend dead-flow rule; display amber HUD warning banner; auto-reconnect in background. |
| **`extracting`** | Auto-Stop watchdog satisfied | **`shotEnded`** | **Auto-Stop**: Freeze HUD timers, stop scale timer, snap final yield and duration, trim trailing zero-flow samples. |
| **`extracting`** | User manual abort | **`idle`** | Halt extraction, clear execution state, stop scale timer. |
| **`shotEnded`** | Review dismissed | **`idle`** / **`armed`** | Reset for next extraction. |

---

## 4. Passive Sensor Inference Heuristics

| Physical Human Action | Sensor Telemetry Signature | Inferred FSM State |
| :--- | :--- | :--- |
| Barista sets cup on scale & arms recipe | App arms, scale tares to 0.0g, scale timer resets | **`.armed`** |
| Barista adjusts cup or fills chamber | Scale reads minor weight / vibration noise (< 0.5 bar) | Held in **`.armed`** (Weight ignored for start) |
| Barista pulls down on lever | Chamber pressure climbs >= 0.5 bar | **`.extracting`** (Auto-Start) |
| Liquid espresso enters cup | Scale weight increases, $dw/dt > 0.5\text{ mL/s}$ | First Drip logged; yield tracking active |
| Scale drops packets temporarily | Sensor silence > 500ms; weight latched | Held in **`.extracting`** (Dead-flow paused) |
| Flow ceases, lever released | Preconditions satisfied, flow <= 0.15 mL/s for 2.0s | **`.shotEnded`** (Auto-Stop Watchdog) |

---

## 5. Consequences

### Positive
- **Eliminates UI Ceremony**: The barista can pull back-to-back shots without touching the iPhone or iPad. Arming primes the entire lifecycle.
- **Unifies Simulation & Production Hardware**: A recorded JSON scenario (`ShotRecord`) and a live CoreBluetooth stream execute the **identical** code path in `ShotCoordinator`.
- **Fault-Tolerant Extraction**: Transient BLE drops do not destroy active pulls.
