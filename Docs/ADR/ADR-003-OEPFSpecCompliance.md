# ADR 003: OEPF Spec Compliance & Flair 58 Guidance Engine
#architecture/adr #espresso/copilot/engine #meticulous/spec

**Status:** Accepted & Verified  
**Date:** September 8, 2026 (Updated: September 26, 2026)  
**Target:** `ProfileExecutionEngine.swift`, `MeticulousComplianceTests.swift`  
**Verification:** 31 / 31 tests passing (0 skipped)  

---

## Executive Summary
This record formalizes the architectural boundary between **macro machine supervision** and **micro stage evaluation**, establishes the mathematical foundation for continuous trigger progress across ascending/decaying sensor channels, defines zero-order hold setpoint dynamics, and documents a critical Swift enum shadowing trap resolved during implementation.

---

## 1. Global `final_weight` Responsibility & Shot Termination

### The Problem
In the Open Espresso Profile Format (OEPF) / Meticulous profile schema, `final_weight` is declared as a global profile field (target cup yield, e.g. 36.0g). Early test drafts treated `final_weight` as an intra-stage trigger that caused `shouldAdvanceStage = true`. 

*Failure Mode:* If preinfusion hits target weight (severe channeling, accidental flush, or scale tare glitch), advancing stage pushes the machine into 9-bar infusion into an already full cup.

### Firmware Parity & Physical Reality
1. **Meticulous Firmware Parity:** In physical Meticulous firmware, piston stall, user abort, and target weight cutoff operate as **external supervisor interrupts / kernel exceptions**. They immediately abort stage execution rather than transitioning between stages.
2. **Flair 58 Manual Lever Reality:** The manual lever has no motor to cut power. Brew termination is governed by sensor-layer heuristics:
   - Minimum brew time: $t \ge 5.0\text{s}$
   - Minimum brew yield: $w \ge 5.0\text{g}$ (or $\text{yield} : \text{dose} \ge 1:1$)
   - Trailing flow cutoff: $\text{flow} \le 0.15\text{ mL/s}$ for $2.0\text{s}$

### Architectural Decision
* **`ProfileExecutionEngine` remains a pure stage evaluator:** It does *not* treat global `final_weight` as an intra-stage advance trigger when explicit stage triggers are defined.
* **`ShotCoordinator` owns the shot lifecycle:** When target weight or end-of-pull heuristics trip, the coordinator commands transition directly into `.shotEnded`.
* **Engine Responsibility:** The engine reports `yieldProgress = min(1.0, currentWeight / finalWeightTarget)` on `GuidanceFrame` for HUD progress display without causing stage advancement.

---

## 2. Decay Exit Triggers (`<=`) & Continuous Racetrack Progress

### The Problem
Meticulous profile exit triggers support comparison operators (`>=` and `<=`). In physical firmware, these are instantaneous boolean transitions (e.g. `pressure <= 4.0 bar` trips the stage).

However, the Barista HUD provides continuous visual feedback via circular racetrack progress bars ($0.0 \to 1.0$). For decaying metrics (e.g. pressure declining from 9 bar to 4 bar), standard ratio math (`current / target`) clamps 8.0 bar / 4.0 bar to 100% immediately.

### Spec Foundation
The OEPF schema specifies `relative: true | false` on exit triggers (e.g. $+15\text{g}$ or $+10\text{s}$ relative to stage entry). Supporting relative triggers *fundamentally requires* snapshotting sensor values at stage entry.

### Architectural Decision
1. **Expanded `StageBaseline`:** Added `entryPressure: Double = 0.0` and `entryFlow: Double = 0.0` with backwards-compatible default arguments.
2. **Unified Progress Formula:** Ascending and decaying triggers resolve through a single unified mapping:
   $$\text{progress} = \text{clamp}\left(\frac{V_{\text{current}} - V_{\text{start}}}{V_{\text{target}} - V_{\text{start}}}, \ 0.0, \ 1.0\right)$$
   - **Ascending ($4 \to 9\text{ bar}$):** At 6.5 bar $\implies (6.5 - 4) / (9 - 4) = +2.5 / 5 = \mathbf{50\%}$
   - **Decaying ($9 \to 4\text{ bar}$):** At 6.5 bar $\implies (6.5 - 9) / (4 - 9) = -2.5 / -5 = \mathbf{50\%}$
3. **Graceful Fallback:** If `baseline.entryPressure` is omitted or zero, the engine safely resolves $V_{\text{start}}$ from the first knot setpoint (`stage.dynamics.points.first?.y`).

---

## 3. Dynamics Step Interpolation (`.none`) vs. Linear Lerp

### The Problem
`ProfileExecutionEngine` previously applied linear interpolation (`lerp`) across all knot intervals. Meticulous profiles define `DynamicsInterpolationType`:
- `.linear`: Continuous ramp over time/weight.
- `.none`: Zero-order hold / instantaneous step.
- `.curve`: Sigmoidal / spline curve.

### Decent Espresso Analogy & Control Logic
Analogous to Decent Espresso’s **"fast"** (instant step) vs **"smooth"** (ramp):
- `.none` represents a Heaviside step function. The setpoint instantly steps to the interval setpoint with zero smoothing.
- For a manual lever barista, this instructs an immediate change in applied lever pressure (e.g. instant transition from 2 bar preinfusion to 9 bar infusion).

### Architectural Decision
* **Target Setpoint:** In `evaluateTarget`, when interpolation is `.none`, the engine holds $p_0.y$ constant across $x \in [p_0.x, p_1.x)$ without lerping.
* **Chart Waveform:** In `generatePlanCurve`, when interpolation is `.none`, the engine generates square step coordinates `(p0.x, p0.y) -> (p1.x, p0.y) -> (p1.x, p1.y)` to accurately render rectangular steps in SwiftUI Charts.

---

## 4. Swift Optional Shadowing Bug (`Optional.none`)

### Incident Analysis
During test verification, `testStepInterpolation_HoldsPreviousKnot_WithoutLerping` unexpectedly returned `5.0` (linear lerp) instead of `2.0` (step hold).

### Root Cause & Resolution
The parameter was originally declared as an optional enum:
```swift
interpolation: DynamicsInterpolationType? = .linear
```
When callers passed `.none`, the compiler resolved `.none` as `Optional.none` (i.e. `nil`), falling back to the `.linear` path!
To eliminate this ambiguity, the parameter was made non-optional with a concrete default:
```swift
interpolation: DynamicsInterpolationType = .linear
```
This ensures `DynamicsInterpolationType.none` is evaluated deterministically as the zero-order hold interpolation case.
