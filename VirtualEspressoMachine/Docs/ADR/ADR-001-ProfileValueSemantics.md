# ADR 001: Value Semantics, Profile Immutability & Variable Resolution
#architecture/adr #oepf #profile #value-semantics

**Status:** Accepted (Retroactive)  
**Date:** September 2026  
**Target:** `Core/OEPF/MeticulousProfile.swift`, `ProfileStore.swift`  

---

## 1. Context
The Open Espresso Profile Format (OEPF) represents espresso brewing recipes as structured JSON with support for dynamic `$variables` (e.g. `$pressure_Peak`, `$weight_Yield`) injected across stages, knot points, exit triggers, and limit ceilings.

In an interactive iOS/macOS application, recipe profiles can be loaded from bundled files, imported from external sources, tweaked on-the-fly by the barista prior to extraction, and executed against a real-time guidance engine. Handling these models using shared reference types (`class`) creates severe data-race risks, accidental disk-file mutation, and complex state management across concurrent threads.

---

## 2. Architectural Decisions

### 2.1. Pure Swift Value Types
All profile schema entities (`Profile`, `Stage`, `Dynamics`, `Point`, `ExitTrigger`, `Limit`, `Variable`) are declared as **immutable Swift `struct`s** adhering to `Sendable`, `Codable`, `Equatable`, and `Hashable`.

### 2.2. Heterogeneous Value Representation (`VariableOrValue`)
Knot coordinates and trigger thresholds can be either a literal `Double` or an unescaped variable token (e.g. `"$pressure_1"`).
* Implemented as a custom Codable enum:
  ```swift
  public enum VariableOrValue: Codable, Equatable, Hashable, Sendable {
      case value(Double)
      case variable(String)
  }
  ```
* Adopts `ExpressibleByFloatLiteral`, `ExpressibleByIntegerLiteral`, and `ExpressibleByStringLiteral` to enable clean, declarative in-code profile definitions.
* Subscript access on `Point` simulates 2-element tuple coordinates `[x, y]` matching TypeScript/JSON array conventions without breaking struct safety.

### 2.3. Pure Functional Variable Substitution
* Profile variable resolution (`processProfileVariables(originalProfile:) throws -> Profile`) is implemented as a **pure function**.
* It takes an unresolved profile, parses the `variables` array into a lookup map, and performs non-destructive deep copy substitutions across all stages, points, and triggers.
* If a variable is missing or encounters a type mismatch (e.g. a `flow` variable injected into a `pressure` trigger), it throws a localized `ProfileError`.

### 2.4. Separation of Canonical vs. Ephemeral Profiles
* Profiles stored in the app bundle or local database are **read-only canonical templates**.
* When a barista adjusts a slider or stepper in the pre-flight UI, the application does *not* mutate the canonical profile on disk. Instead, it generates an ephemeral, resolved instance via `resolveForExecution()`.
* Permanent recipe edits are explicitly saved as new profile entities with unique UUIDs.

---

## 3. Consequences

### Positive:
* **Thread Safety**: Fully safe under Swift 6 strict concurrency checking. Profiles can be passed freely across actor boundaries without locks or defensive copying.
* **Predictable Execution**: The `ProfileExecutionEngine` operates exclusively on fully resolved, numeric profiles; it never evaluates string tokens during real-time 10 Hz extraction loops.
* **Data Integrity**: Bundled and imported profile assets remain pristine and uncorrupted by temporary brewing session tweaks.

### Negative / Trade-offs:
* Modifying a deeply nested knot requires full struct reassignment (managed cleanly by Swift's copy-on-write mechanisms).
