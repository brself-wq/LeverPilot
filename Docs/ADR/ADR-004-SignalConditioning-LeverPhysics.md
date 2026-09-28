# ADR 004: Signal Conditioning & Manual Lever Auto-Start/Stop
#architecture/adr #espresso/lever #signal-processing

**Status:** Accepted & Implemented  
**Date:** September 2026  
**Target:** `Hardware/SignalConditioning`, `State/Heuristics`  

---

## 1. Context
Manual lever espresso machines (such as the Flair 58) combined with wireless Bluetooth sensors introduce physical realities that do not occur on robotic commercial machines:
1. **Bluetooth Latency Jitter**: Packet intervals vary by $\pm 20\text{ms}$. Calculating instantaneous flow rate via simple discrete differentiation ($\Delta w / \Delta t$) creates massive, unusable spikes (oscillating between 0 and 5 mL/s).
2. **Mechanical Vibration Noise**: Locking in the portafilter or resting hands on the lever causes transient scale tare shifts ($\pm 0.3\text{g}$).
3. **Chamber Vacuum (Suck-Back)**: Raising the lever arm to draw water creates a transient vacuum, causing pressure transducers to momentarily register zero or negative values.
4. **Hands-Free Operation**: Baristas operating a manual lever have both hands occupied and cannot tap an iPad screen to start or stop extraction timers.

---

## 2. Architectural Decisions

### 2.1. Dual Telemetry Streaming Pipelines
* **Pipeline A (Black Box Historical Logger)**: Records raw, unadulterated sensor data directly into `ShotRecord.samples`. Every pressure dip, channeling burst, and physical lever wobble is preserved for honest post-shot analysis and Visualizer.coffee export.
* **Pipeline B (Guidance & Execution Feed)**: Feeds `ProfileExecutionEngine` and the cockpit gauges. Applies filtering, deadbanding, and hysteresis to provide clean, actionable guidance cues without visual flickering.

### 2.2. Flow Rate Derivation via Rolling Linear Regression
* The application buffers a 6-sample ($500\text{ms}$) rolling window of $(t, w)$ coordinates and computes the best-fit linear regression slope:
  $$\text{Flow Rate} = \frac{N \sum (t \cdot w) - \sum t \sum w}{N \sum (t^2) - (\sum t)^2}$$
* This eliminates packet-arrival jitter spikes while maintaining low phase lag ($<60\text{ms}$).

### 2.3. Lever Auto-Start Heuristic
* **Trigger Condition**:
  $$\text{MachineState} == \text{.armed AND Pressure} \ge \text{autoStartPressure (default 0.5 bar)}$$
* **Rationale**: On a manual lever, pulling down pressurizes the water column before liquid drops into the cup. Triggering on pressure eliminates false starts caused by scale tare drift, table bumps, or cup placement.

### 2.4. First Drip Event Detection
* While the shot clock is running, the system registers a `firstDripTimestamp` when:
  $$\text{Weight} \ge 0.5\text{g}$$
* This provides puck saturation tracking without interfering with the primary timer.

### 2.5. Auto-Stop Preconditions & Dead-Flow Cutoff (Beanconqueror Protocol)
* **Preconditions**: To prevent cutting off the shot during low-flow pre-infusion, auto-stop checks activate only when:
  1. $\text{Elapsed Time} \ge 5.0\text{s}$
  2. $\text{Cup Weight} \ge 5.0\text{g}$ OR $\text{Yield} \ge \text{Dry Dose}$ (1:1 ratio)
* **Cutoff Execution**: Once preconditions are met, extraction transitions to `.shotEnded` if:
  $$\text{Smoothed Flow} \le 0.15\text{ mL/s sustained for } 2.0\text{s}$$
  OR
  $$\text{Current Weight} \ge \text{Profile Final Weight}$$

### 2.6. Post-Shot Retroactive Tail Trimming
* Because dead-flow cutoff requires a $2.0\text{s}$ confirmation window, the final recorded shot duration and metrics in `ShotRecord` are not calculated via naive arithmetic subtraction.
* Instead, upon watchdog cutoff trip, `ShotCoordinator` scans `capturedSamples` in reverse to locate the exact sample where flow first dropped below the cutoff threshold for the final sustained period.
* **Duration & Yield Snapping**:
  - $\text{Duration}_{\text{final}} = \text{Sample}_{\text{cutoff}}.\text{timestamp}$
  - $\text{Weight}_{\text{final}} = \text{Sample}_{\text{cutoff}}.\text{weight}$
* Trailing zero-flow samples are pruned from the archived record, guaranteeing that charts in `ShotRecordView`, Visualizer.coffee, and Beanconqueror reflect the true moment liquid stopped flowing.

### 2.7. Vacuum Clamping & Trigger Stabilization
* Transient negative pressure values ($<0.0\text{ bar}$) caused by lever raise are clamped to `0.0` in the ingestion layer.
* Safety limit alarms implement a **$0.5\text{ bar}$ hysteresis** to prevent buzzer stutter.

---

## 3. Consequences

### Positive:
* **Battle-Tested Reliability**: Adopts field-proven heuristics from Beanconqueror and Decent espresso workflows.
* **Clean Visual Feedback**: Eliminates erratic flow graphs and gauge flutter on the Barista HUD.
* **Preserved Raw Data**: Filtering is isolated to the guidance loop; raw diagnostic data is never lost or irreversibly altered.
