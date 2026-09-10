# ADR 005: Sensor-Observed Finite State Machine (FSM) for Manual Lever Telemetry

- **Status**: Accepted
- **Date**: 2026-09-08
- **Author**: Ben Self
- **Deciders**: Architecture Team, BaristaPilot Core
- **Consulted**: Open Espresso Profile Format (OEPF) Community, Meticulous Firmware Review
- **Supersedes**: Legacy Prototype Machine Protocol & State Machine

---

## 1. Context & Problem Statement

Early prototypes of this application inherited a robotic, multi-step state machine from an early mock (`MockVirtualEspressoMachine`), requiring manual UI interaction:

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
3. **Formalize 6 Core States**:
   - `idle`: Machine at rest, connected or disconnected, no profile loaded.
   - `armed`: Profile loaded, baselines reset, observer listening for physical lever pull.
   - `extracting`: Lever in motion, active OEPF trajectory evaluation, real-time HUD rendering.
   - `shotEnded`: Extraction complete (target yield reached or flow cessation detected).
   - `purging`: Wastewater chamber flush detected or prompted.
   - `error`: Sensor disconnection, stalled shot, limit breach abort, or profile corruption.

---

## 3. State Transition Matrix

```
       +-----------+
       |   idle    |<-----------------------------+
       +-----+-----+                              |
             | selectProfile(p)                   |
             v                                    | reset / deselect
       +-----------+                              |
       |   armed   |------------------------------+
       +-----+-----+                              |
             | Auto-Start (P >= 0.5 bar OR W >= 0.5g)
             v                                    |
       +-----------+                              |
       |extracting |                              |
       +-----+-----+                              |
             | Auto-Stop (flow <= 0.1 g/s OR W >= finalWeight)
             v                                    |
       +-----------+                              |
       | shotEnded |------------------------------+
       +-----+-----+                              |
             | Wastewater Flush (P blip, scale empty)
             v                                    |
       +-----------+                              |
       |  purging  |------------------------------+
       +-----------+

  [Any State] --(Hardware Disconnect / Fatal Abort)--> [ error ]
```

### Detailed Transition Table

| From State | Event / Trigger | To State | Actions Taken by System |
| :--- | :--- | :--- | :--- |
| **`idle`** | `selectProfile(profile)` | **`armed`** | Load profile, compute initial plan curve, update stage pills, reset baselines. |
| **`armed`** | `pressure >= 0.5 bar` OR `weight >= 0.5g` OR replay tick | **`extracting`** | **Auto-Start**: Snap Stage 0 `StageBaseline` (t0, w0, entryPressure, entryFlow), start HUD chart tracking. |
| **`armed`** | `abort()` or recipe deselected | **`idle`** | Unload active profile and clear HUD surface buffers. |
| **`extracting`** | Stage exit trigger satisfied (`shouldAdvanceStage == true`) | **`extracting`** | Increment `activeStageIndex`, snap new `StageBaseline`, wipe stage history slice. |
| **`extracting`** | Final stage trigger satisfied OR Auto-Stop condition met | **`shotEnded`** | **Auto-Stop**: Freeze HUD timers, capture final yield and nominal duration. |
| **`extracting`** | User manual abort or panic stop | **`idle`** | Halt extraction, clear execution state. |
| **`shotEnded`** | Secondary lever push with cup removed (P approx 1 to 2 bar) | **`purging`** | Mark chamber flush in progress. |
| **`shotEnded`** / **`purging`** | `resetExecutionState()` | **`armed`** | Ready for immediate repeat pull of current recipe. |
| **`shotEnded`** / **`purging`** | `abort()` | **`idle`** | Reset to standby. |
| **Any State** | BLE drop, fatal parsing exception, or shot stall | **`error`** | Engage limit alarm visual banner, log diagnostics, permit safe reset. |

---

## 4. Passive Sensor Inference Heuristics

Because the Flair 58 is a purely mechanical lever, the system uses passive telemetry signatures to detect the espresso ritual:

| Physical Human Action | Sensor Telemetry Signature | Inferred FSM State |
| :--- | :--- | :--- |
| Barista sets cup on scale | Scale weight stabilizes > 0.5g | Scale auto-tare cue / Cup Ready |
| Barista pulls down on lever | Chamber pressure climbs >= 0.5 bar | **`.extracting`** (Auto-Start) |
| Liquid espresso enters cup | Scale weight increases, dW/dt > 0.5 g/s | First Drip logged; yield tracking active |
| Barista releases lever or removes cup | Pressure plunges to 0.0 bar, flow <= 0.1 g/s for > 1.5s | **`.shotEnded`** (Auto-Stop) |
| Barista expels wastewater into dreg cup | Pressure spikes to 1.0 - 2.5 bar while scale is cleared | **`.purging`** |
| Chamber fully purged, lever resting | Pressure stable at 0.0 bar for > 5.0s | Ready for **`.armed`** or **`.idle`** |

---

## 5. Consequences

### Positive
- **Eliminates UI Ceremony**: The barista can pull back-to-back shots without touching the iPhone or iPad. Selecting a recipe once primes the entire lifecycle.
- **Unifies Simulation & Production Hardware**: A recorded JSON scenario (`ShotRecord`) and a live CoreBluetooth stream execute the **identical** code path in `ShotCoordinator`.
- **Resolves Headless Test Divergence**: Unit tests no longer require artificial calls to `setToShotReady()`. Tests and UI share the exact same state machine.
- **Fail-Safe Operation**: The explicit **`.error`** state provides a safe landing zone for Bluetooth packet dropouts, motor protection stalls, or malformed profile schemas.

### Negative / Mitigations
- **Risk of False Auto-Start from Scale Bumps**: Placing a heavy portafilter or tamping on the scale could trigger auto-start if weight alone were used.
  - *Mitigation*: Auto-Start requires sustained chamber pressure (>= 0.5 bar) as the primary signal, with weight acting only as a secondary confirmation.
