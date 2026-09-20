# Domain Glossary

### Coffee Extraction Physics
* **Pre-infusion / Soak**: Wetting the coffee puck at low pressure (1.0–3.0 bar) to saturate grounds, eliminate air pockets, and reduce channeling.
* **First Drip**: The timestamp and weight threshold (typically >= 0.5g) when the first drops of liquid fall through the portafilter into the cup.
* **Puck Resistance**: Dynamic hydraulic resistance calculated in real-time as Pressure / Flow (bar / (mL/s)).
* **Lever Suck-Back**: Transient vacuum created in the brew chamber when raising a manual lever arm. Causes pressure transducers to read zero or slightly negative.

### Engine & Profiling Concepts
* **Knot**: A coordinate pair (x, y) in a stage's dynamics array defining a target setpoint y at domain progress x.
* **Horizon**: The maximum anticipated domain span (x) of a stage used to render the full trajectory curve on the HUD.
* **Zero-Order Hold (`.none`)**: Step interpolation mode where the setpoint instantly jumps and holds the knot value without ramping.
* **Deadband**: An intentional tolerance zone around a target setpoint where the system considers the pull "ON TARGET", preventing visual indicator jitter.
* **Guardrail**: A safety limit capping pressure or flow. Exceeding a guardrail trips an audio/visual alarm.
* **Tail Trimming**: Subtracting the post-extraction dead-flow confirmation window (e.g. 1.5s) from the final archived duration in `ShotRecord`.
* **Stage-Relative Exit Trigger (`relative: true`)**: A condition evaluated strictly against the local delta accumulated since entering the current stage (e.g. elapsed stage time t - t0, or stage yield w - w0).
* **Absolute Shot Exit Trigger (`relative: false`)**: A condition evaluated against the cumulative extraction timeline or aggregate scale yield since shot start (t = 0.0s). Default behavior when `relative` is omitted in the OEPF schema.

### Fault Tolerance & Signal Continuity
* **Sensor Staleness / Heartbeat**: The duration threshold (500ms) after which the absence of incoming GATT notifications marks a sensor degraded (`isStale = true`).
* **Weight Latching**: The safety practice of freezing the last verified positive weight reading during a radio dropout to prevent downward graph spikes, zero-weight collapse, and erroneous flow calculations.
* **Regression Re-Anchoring**: Purging the 6-sample OLS rolling buffer when the time delta between packets exceeds 500ms (delta_t > 0.5s) to prevent burst arrivals from producing false 15+ mL/s rate-of-change spikes.
* **Mid-Flight Reconnection Immunity**: A safeguard ensuring that re-establishing a Bluetooth connection during `.extracting` never issues a tare command, zeroes the shot clock, or re-arms the state coordinator.

### Integration & Persistence Concepts
* **Delivery Ledger (Sidecar)**: An isolated persistence store (`UserDefaults`) recording successfully transferred telemetry IDs without mutating the original, immutable physical flight records (`ShotRecord`).
* **Loopback REST Emulation**: A local TCP listener (`NWListener`) running on `127.0.0.1:8080` that implements the Meticulous machine API and Engine.IO/Socket.IO presence protocols, allowing third-party apps (Beanconqueror) to ingest telemetry curves without cloud dependencies.
* **Handoff State**: An explicit finite state machine (`.idle` -> `.transferring` -> `.transferred` -> `.timedOut`) governing cross-app deep-linking and locking out repetitive user button taps.
* **Anti-Rage-Click Lockout**: A defensive UI state pattern that disables action buttons and presents active indeterminate progress spinners during asynchronous cross-app dispatch to eliminate duplicate task creation in Stage Manager / Split View.
* **Sliding Viewport Span**: The configurable horizontal domain window (typically 20–30s) rendered on `StageDynamicsChartView`. Once elapsed stage time exceeds this window, the X-axis continuously scrolls to keep the live extraction point pinned near the right edge of the display.
