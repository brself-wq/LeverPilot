# OEPF Spec Compliance & Architectural Deviations
#meticulous/spec #compliance #oepf

## 1. Compliance Matrix

| OEPF Schema Field | Swift Domain Type | Parsing & Validation Behavior |
| :--- | :--- | :--- |
| `temperature` | `Double` | Setpoint water temperature in °C. |
| `final_weight` | `Double` | Target cup yield in grams. Supervised by Shot Coordinator. |
| `variables` | `[Variable]` | Injected parameters referenced via `$variable_key`. Resolved before shot start. |
| `stages[].dynamics.points` | `[Point]` | Normalized to `(x, y)` tuples. Subscripted matching TypeScript `[0], [1]`. |
| `stages[].dynamics.over` | `DynamicsInterpolationOverType` | `.time`, `.weight`, `.pistonPosition`. |
| `stages[].dynamics.interpolation` | `DynamicsInterpolationType` | `.linear` (lerp), `.none` (zero-order hold step), `.curve` (spline). |
| `stages[].exit_triggers` | `[ExitTrigger]` | Multi-trigger evaluation using short-circuit OR logic. |
| `stages[].limits` | `[Limit]` | Operational ceilings monitored on every frame. |

---

## 2. Formal Deviations & Technical Rationale

### A. Global `final_weight` as Supervisor Cutoff
* **OEPF Ambiguity**: Some profile implementations treat `final_weight` as an implicit exit trigger inside every stage.
* **Engine Decision**: In LeverStudio / BaristaPilot, `ProfileExecutionEngine` does *not* trip `shouldAdvanceStage` when `final_weight` is reached if explicit stage exit triggers are pending. Doing so on a manual lever machine would advance a pre-infusion stage into a 9-bar infusion stage into an already full cup. Shot completion is strictly supervised by the `ShotCoordinator`.

### B. Unified Decay Trigger Progress Mapping
* For descending exit triggers (`comparison == "<="`), progress is calculated against the stage entry baseline:
  $$\text{progress} = \text{clamp}\left(\frac{V_{\text{current}} - V_{\text{start}}}{V_{\text{target}} - V_{\text{start}}}, \ 0.0, \ 1.0\right)$$
  Where $V_{\text{start}}$ is captured in `StageBaseline.entryPressure` or `entryFlow` upon stage entry.

### C. Overrun Flatline Rule
* If the domain variable ($x$) exceeds the maximum defined knot in a stage, the target setpoint ($y$) clamps to the final knot's value indefinitely until an exit trigger condition is met.

### D. Exit Trigger `relative` Defaulting & Semantic Rules
* **Schema Normalization**: In accordance with the OEPF schema and developer normalization models, if `relative` is omitted from an exit trigger definition, it defaults to `false`.
* **Semantic Behavior**:
  - `relative: true`: Evaluates against stage-local delta values ($t - t_0$ for time, $w - w_0$ for weight).
  - `relative: false` (Default): Evaluates against absolute total elapsed shot time ($t_{\text{shot}}$) or cumulative scale yield.
* **Time Trigger Hazard**: Absolute time triggers (`relative: false`) measure from extraction initiation ($t = 0.0\text{s}$, valve close / auto-start trip). If an absolute time trigger is set shorter than the elapsed time of preceding stages, the stage exits immediately (0.0s duration). Recipe authors are advised to explicitly set `relative: true` for stage durations (e.g. blooms, soaks).

### E. Profile Completion vs. Physical Extraction Lifetime
* **OEPF Assumption**: Profile completion inherently halts physical machine flow (motor retracts).
* **Flair 58 Lever Deviation**: On a manual lever, the human barista controls the hydraulic piston. Physical extraction may conclude *before* all profile stages complete (early blonde / channel cut) or *after* all stages have expired (lingering lever pull).
* **Resolution**: Profile stage completion advances the digital twin's guidance state, but macro extraction termination is supervised by physical telemetry (the 2.0s dead-flow watchdog $\le 0.1\text{ g/s}$) and target weight cutoffs.

---

## 3. Handling Incompatibilities in Machine Capabilities (OEPF §4 Compliance)

The Flair 58 is a manual, human-powered lever platform equipped with Bluetooth pressure and scale transducers. It lacks a motorized piston actuator and a linear piston displacement sensor. BaristaPilot implements OEPF §4 (*Handling Incompatibilities in Machine Capabilities*) as follows:

1. **`piston_position` Dynamics & Triggers**:
   - **Approach**: Interpretation Fallback / Approximation.
   - Manual levers do not possess a linear displacement transducer. Profiles configuring `dynamics.over = pistonPosition` or exit triggers on `piston_position` cannot be directly measured.
   - For MVP, BaristaPilot will display a pre-flight incompatibility warning when such a profile is selected, informing the user that piston position parameters cannot be monitored or driven.

2. **`type = power` Stages**:
   - **Approach**: Visual Operator Effort Guidance.
   - Motor current control is mechanically inapplicable to manual levers. Power stages (0–100%) are rendered on the HUD as a suggested relative pulling effort guide for the human operator.

3. **Pre-Flight Validation**:
   - Profiles requiring capabilities unsupported by the manual lever hardware trigger non-blocking informational warnings in the pre-flight check, maintaining recipe portability without crashing the execution engine.
