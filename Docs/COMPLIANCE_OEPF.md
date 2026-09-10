# OEPF Spec Compliance & Architectural Deviations
#meticulous/spec #compliance #oepf

## 1. Compliance Matrix

| OEPF Schema Field | Swift Domain Type | Parsing & Validation Behavior |
| :--- | :--- | :--- |
| `temperature` | `Double` | Setpoint water temperature in °C. |
| `final_weight` | `Double` | Target cup yield in grams. Owned by Shot Coordinator supervisor. |
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
* **Engine Decision**: In LeverStudio, `ProfileExecutionEngine` does *not* trip `shouldAdvanceStage` when `final_weight` is reached if explicit stage exit triggers are pending. Doing so on a manual lever machine would advance a preinfusion stage into a 9-bar infusion stage into an already full cup. Shot completion is strictly supervised by the `ShotCoordinator`.

### B. Unified Decay Trigger Progress Mapping
* For descending exit triggers (`comparison == "<="`), progress is calculated against the stage entry baseline:
  $$\text{progress} = \text{clamp}\left(\frac{V_{\text{current}} - V_{\text{start}}}{V_{\text{target}} - V_{\text{start}}}, \ 0.0, \ 1.0\right)$$
  Where $V_{\text{start}}$ is captured in `StageBaseline.entryPressure` or `entryFlow` upon stage entry.

### C. Overrun Flatline Rule
* If the domain variable ($x$) exceeds the maximum defined knot in a stage, the target setpoint ($y$) clamps to the final knot's value indefinitely until an exit trigger condition is met.
