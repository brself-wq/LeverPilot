# ADR 002: Pluggable Telemetry Architecture & Stream Decoupling
#architecture/adr #telemetry #bluetooth #simulation

**Status:** Accepted
**Date:** September 2026
**Target:** `Hardware/TelemetryProvider`, `State/ShotCoordinator`

---

## 1. Context
The application must fulfill two distinct operating modes:
1. **Live Extraction Mode**: Ingesting real-time pressure from a Bluetooth transducer and weight from a Bluetooth smart scale via the `EspressoBLE` package.
2. **Simulation & Rehearsal Mode**: Stepping or playing through recorded historical pulls or synthetic test scenarios via `PlaybackEngine`.

Coupling the Barista HUD, the profile execution engine, or the shot coordinator directly to CoreBluetooth or `PlaybackEngine` creates architectural rigidity, duplicate state machines, and makes headless unit testing impossible.

---

## 2. Architectural Decisions

### 2.1. Abstract `TelemetryProvider` Protocol
All telemetry sources must conform to an asynchronous streaming contract:

```swift
public protocol TelemetryProvider: AnyObject, Sendable {
    /// 10 Hz stream of synchronized, time-stamped machine frames
    var frameStream: AsyncStream<MachineFrame> { get }
    
    func start() async throws
    func stop() async
}
```

### 2.2. Decoupled Provider Implementations
* **`BLETelemetryProvider`**: Connects to physical hardware via `EspressoBLEManager`. Merges asynchronous scale notifications and pressure indications through a sample-and-hold buffer, sampled at 10 Hz.
* **`ReplayTelemetryProvider`**: Wraps `PlaybackEngine`. Ticks through `ShotRecord.samples` and yields an identical `MachineFrame` stream.
* **`ManualInputProvider` (Optional/Testing)**: Allows synthetic frame injection via UI sliders or script drivers.

### 2.3. Agnostic Downstream Consumer (`ShotCoordinator`)
* The `ShotCoordinator` and `ProfileExecutionEngine` consume only `MachineFrame` instances emitted by the provider.
* The execution logic has **zero awareness** of whether a reading originated from an over-the-air GATT notification or a JSON test fixture.

### 2.4. Separation of High-Frequency Telemetry from SwiftUI State
* High-frequency numerical updates (10–20 Hz) bypass SwiftUI `@Observable` property bindings and stream through `AsyncStream`.
* Only macro state changes (`MachineState`, active stage index, guardrail alarms) and the final 10 Hz `GuidanceFrame` update SwiftUI views, preventing frame-rate drops on iOS devices.

---

## 3. Consequences

### Positive:
* **True Dual-Persona Architecture**: The app switches between offline Profile Studio and live Barista Copilot simply by swapping the injected `TelemetryProvider`.
* **Headless Integration Testing**: 35-second multi-stage shot scenarios can be tested completely in XCTest without instantiating CoreBluetooth, UI views, or mock timer loops.
* **Driver Independence**: Swapping or adding new hardware drivers (e.g. Acaia, Decent, or DIY transducers) in `EspressoBLE` requires zero changes to the guidance engine or UI.

### Negative / Trade-offs:
* Requires maintaining an asynchronous bridging layer (`AsyncStream`) between delegate callbacks and the coordinator.
