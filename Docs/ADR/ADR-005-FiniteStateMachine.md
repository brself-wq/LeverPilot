# ADR 005: Sensor-Observed Finite State Machine (FSM) for Manual Lever Telemetry

- **Status**: Accepted
- **Date**: 2026-09-08 (Updated: 2026-09-20)
- **Author**: Ben Self
- **Deciders**: Architecture Team, BaristaPilot Core
- **Consulted**: Open Espresso Profile Format (OEPF) Community, Meticulous Firmware Review, Beanconqueror Core
- **Supersedes**: Legacy Prototype Machine Protocol & State Machine

---

## 1. Context & Problem Statement

Early prototypes of this application inherited a robotic, multi-step state machine from an early mock (`MockLeverPilot`), requiring manual UI interaction:

`ready` -> `select profile` -> `profileSelected` -> `"Set Ready" button` -> `shotReady` -> `"Start" button` -> `extracting` -> `cutoff` -> `shotEnded` -> `"Clean" button` -> `cleaning`

This model created three significant problems:

1. **UX Mismatch for Manual Lever Machines**: On a manual lever espresso machine (Flair 58), the barista’s hands are actively holding the lever, portafilter, or kettle. Forcing the barista to tap software buttons on an iPad with wet, coffee-covered hands is high friction and unrealistic at the coffee counter.
2. **The "Ghost State" Catch-22**: When we decoupled the HUD simulator from the legacy mock, `shotReady` became an artificial blocking state. Unit tests expected a manual transition to `shotReady`, whereas the simulator UI only selected a profile. This caused incoming playback frames to be dropped as pre-shot noise, locking the simulator graph.
3. **Commanded vs. Observed Architecture**: Firmware from automated robotic machines (like Meticulous) maintains states like `heating`, `infusion`, `retracting`, and `purging`. These are **actuator commands** sent to stepper motors and heating elements. On a Flair 58, the app possesses no actuators; the human barista is the motor. The app is an **Avionics Flight Director** observing passive Bluetooth sensors (chamber pressure transducer and smart scale).

---

## 2. Decision

We replace the actuator-driven, multi-button state machine with a **Sensor-Observed Finite State Machine**:

1. **Eliminate the `shotReady` Middleman**: Collapse `profileSelected` and `shotReady` into a single **`armed`** state. Selecting a profile immediately arms the digital twin observer.
2. **Sensor-Inferred State Progression**: Leverage incoming Bluetooth telemetry (or recorded replay frames) to detect human lever actions and auto-advance machine states without screen taps.
3. **Hardware Command Hooks on Transition**: State transitions automatically drive hardware peripheral functions over Bluetooth (e.g. tare and reset scale timer on arm, start scale timer on auto-start, stop timer on shot conclusion).
4. **Soft Disconnection & Fault-Tolerance**: Mid-flight BLE disconnects do **not** trigger an instant, destructive transition to `.error`. The engine enters a degraded signal-searching mode, holding valid metrics and suppressing dead-flow auto-stops while auto-reconnect attempts recovery.
5. **Formalize 6 Core States**:
   - `idle`: Machine at rest, connected or disconnected, no profile loaded.
   - `armed`: Profile loaded, scale tared and zeroed, observer listening strictly for physical lever pull.
   - `extracting`: Lever in motion, active OEPF trajectory evaluation, real-time HUD rendering.
   - `shotEnded`: Extraction complete (target yield reached or sustained dead-flow cutoff detected).
   - `purging`: Wastewater chamber flush detected or prompted.
   - `error`: Fatal parsing exception, unrecoverable sensor failure, limit breach abort, or profile corruption.

---

## 3. State Transition Matrix

   +-----------+
   |   idle    |<-----------------------------+
   +-----+-----+                              |
         | selectProfile(p)                   |
         v                                    | reset / deselect
   +-----------+                              |
   |   armed   |------------------------------+
   +-----+-----+                              |
         | Auto-Start (Pressure >= 0.5 bar)   |
         v                                    |
   +-----------+                              |
   |extracting | (Holds state on BLE drop;   |
   +-----+-----+  attempts auto-reconnect)    |
         | Auto-Stop (Dead flow <= 0.1 g/s sustained OR W >= target)
         v                                    |
   +-----------+                              |
   | shotEnded |------------------------------+
   +-----+-----+                              |
         | Wastewater Flush (P blip, scale empty)
         v                                    |
   +-----------+                              |
   |  purging  |------------------------------+
   +-----------+

[Fatal Exception / Limit Breach / User Abort] ------------> [ error ]

### Detailed Transition Table

| From State | Event / Trigger | To State | Actions Taken by System |
| :--- | :--- | :--- | :--- |
| **`idle`** | `selectProfile(profile)` | **`armed`** | Load profile, compute initial plan curve, update stage pills, reset baselines. Send BLE tare and timer reset commands to scale. |
| **`armed`** | `pressure >= 0.5 bar` (or replay tick) | **`extracting`** | **Auto-Start**: Snap Stage 0 `StageBaseline` (t0, w0, entryPressure, entryFlow), zero timer, start HUD chart tracking, send BLE start timer command to scale. |
| **`armed`** | `abort()` or recipe deselected | **`idle`** | Unload active profile and clear HUD surface buffers. Send BLE stop timer command. |
| **`extracting`** | Stage exit trigger satisfied (`shouldAdvanceStage == true`) | **`extracting`** | Increment `activeStageIndex`, snap new `StageBaseline`, wipe stage chart slice. |
| **`extracting`** | Sensor signal drops (> 500ms) | **`extracting`** (Degraded) | Latch last weight; suppress dead-flow rule; display amber HUD warning banner; auto-reconnect peripheral in background. |
| **`extracting`** | Final stage trigger satisfied OR Auto-Stop condition met | **`shotEnded`** | **Auto-Stop**: Freeze HUD timers, stop scale onboard timer, snapshot final yield and recorded duration. |
| **`extracting`** | User manual abort or panic stop | **`idle`** | Halt extraction, clear execution state, send BLE stop timer command. |
| **`shotEnded`** | Secondary lever push with cup removed (P approx 1 to 2 bar) | **`purging`** | Mark chamber flush in progress. |
| **`shotEnded`** / **`purging`** | `resetExecutionState()` | **`armed`** | Ready for immediate repeat pull of current recipe. Zero scale and timer. |
| **`shotEnded`** / **`purging`** | `abort()` | **`idle`** | Reset to standby. |
| **Any State** | Fatal unrecoverable failure or profile corruption | **`error`** | Engage limit alarm visual banner, log diagnostics, permit safe reset. |

---

## 4. Passive Sensor Inference Heuristics

Because the Flair 58 is a purely mechanical lever, the system uses passive telemetry signatures to detect the espresso ritual:

| Physical Human Action | Sensor Telemetry Signature | Inferred FSM State |
| :--- | :--- | :--- |
| Barista sets cup on scale & arms recipe | App arms, scale tares to 0.0g, scale timer resets | **`.armed`** |
| Barista adjusts cup or fills chamber | Scale reads minor weight / vibration noise (< 0.5 bar) | Held in **`.armed`** (Weight ignored for start) |
| Barista pulls down on lever | Chamber pressure climbs >= 0.5 bar | **`.extracting`** (Auto-Start) |
| Liquid espresso enters cup | Scale weight increases, dw/dt > 0.5 g/s | First Drip logged; yield tracking active |
| Scale drops packets temporarily | Sensor silence > 500ms; weight latched | Held in **`.extracting`** (Dead-flow paused) |
| Flow ceases, lever released | Preconditions satisfied, flow <= 0.1 g/s for 2.0s | **`.shotEnded`** (Auto-Stop Watchdog) |
| Barista expels wastewater into dreg cup | Pressure spikes to 1.0–2.5 bar while scale is cleared | **`.purging`** |
| Chamber fully purged, lever resting | Pressure stable at 0.0 bar for > 5.0s | Ready for **`.armed`** or **`.idle`** |

---

## 5. Consequences

### Positive
- **Eliminates UI Ceremony**: The barista can pull back-to-back shots without touching the iPhone or iPad. Arming primes the entire lifecycle.
- **Unifies Simulation & Production Hardware**: A recorded JSON scenario (`ShotRecord`) and a live CoreBluetooth stream execute the **identical** code path in `ShotCoordinator`.
- **Fault-Tolerant Extraction**: Transient BLE drops do not destroy active pulls.
- **Hardware Mirroring**: Bookoo scale OLED timer stays locked in sync with the digital copilot.

### Negative / Mitigations
- **Blind Basket Pulls Without Water Flow**: A blind basket extraction produces zero grams (w = 0.0g), meaning the weight-gated dead-flow auto-stop watchdog will not fire automatically.
  - *Mitigation*: Blind basket pulls are terminated cleanly by profile time exit triggers or by the manual HUD abort (`xmark`).
