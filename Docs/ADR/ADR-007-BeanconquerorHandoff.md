# ADR 007: Beanconqueror Integration, Local Loopback REST Emulation & Delivery Ledger Sidecar
#architecture/adr #integrations #beanconqueror #telemetry #loopback #immutability

**Status:** Accepted & Implemented  
**Date:** September 19, 2026  
**Author:** Ben Self  
**Deciders:** Architecture Team, BaristaPilot Core  
**Target:** `Integrations/Beanconqueror`, `Integrations/Meticulous`, `Views/ShotHistoryBrowserView`, `Views/ShotRecordView`  

---

## 1. Context & Problem Statement

Beanconqueror (BQ) is the specialty coffee community’s open-source standard for brew logging, bean inventory, grinder dial-in, and Visualizer.coffee cloud syncing. 

In early design iterations, BaristaPilot considered directly implementing cloud synchronization to Visualizer.coffee and building out a bean/grinder logbook. This was rejected: duplicating logbook UI, roaster catalogs, tasting notes, and cloud authentication inside a real-time extraction copilot adds bloat and pulls focus away from in-flight telemetry and hydraulic lever physics.

However, handing off extraction data from BaristaPilot to Beanconqueror presented distinct architectural challenges:
1. **The Foreign Mutation Hazard**: Injecting Beanconqueror foreign keys, sync statuses, or external timestamps into BaristaPilot’s local `ShotRecord` violates our **Immutable Flight Recorder** principle.
2. **Sandboxed Cross-App Communication**: On iOS/iPadOS, two independent applications cannot share in-memory address space or SQLite databases directly.
3. **Transfer Race Conditions & Rage-Clicking**: In Split View or Stage Manager on iPadOS, dispatching a deep-link handoff while the user rapidly taps the export button can trigger concurrent background assertions and socket collisions.
4. **Payload Delivery Verification**: Beanconqueror's custom URL scheme triggers the brew creation workflow, but does not confirm whether telemetry was successfully read.

---

## 2. Architectural Decisions

### 2.1. The Immutable Flight Recorder Principle
A `ShotRecord` on disk represents **physical reality as observed by Bluetooth sensors**. 
* Historical shot logs (`Application Support/VirtualEspressoMachine/ShotLogs/*.json`) are write-once, immutable documents.
* BaristaPilot **never** writes Beanconqueror IDs, external preparation UUIDs, or remote sync timestamps back into historical shot files.

### 2.2. Sidecar Delivery Ledger
To track which shots have been transferred to Beanconqueror without mutating the underlying shot records, we implement an independent **Delivery Ledger Sidecar**:
* Backed by a lightweight `Set<String>` in `UserDefaults` (`bq.delivered_shot_ids`).
* Stores strictly the canonical `shot.id` of successfully transferred extractions.
* Drives glanceable green `[☕ BQ]` status badges on historical shot cards and toggles UI action button copy between *"Add to Beanconqueror"* and *"Re-send to Beanconqueror"*.

### 2.3. Local Loopback REST Emulation (`MeticulousServer`)
Rather than engineering proprietary file-sharing formats, BaristaPilot embeds a lightweight TCP listener (`NWListener`) bound strictly to `127.0.0.1:8080`:
* **Zero Cloud Dependency**: Operates entirely over local device loopback.
* **Meticulous REST Compatibility**: Implements standard Meticulous endpoints expected by Beanconqueror:
  - `OPTIONS *`: Universal CORS preflight response.
  - `/socket.io/?...`: Engine.IO/Socket.IO presence handshake confirming the machine is "online".
  - `GET /api/v1/settings`: Settings verification handshake.
  - `POST /api/v1/history`: Serves staged extraction telemetry (`dump_data: false` for listing, `dump_data: true` for full 10 Hz time-series curves).
* **Payload Serialization (`ShotRecord+Meticulous.swift`)**: Normalizes BaristaPilot’s 10 Hz `ShotSample` series into standard floating-point arrays with Unix epoch timestamps in seconds.

### 2.4. Stateful Handoff Lifecycle (`HandoffState`)
`BQHandoffCoordinator` exposes an observable finite state machine managing the export workflow:
* **`.idle`**: Standby; ready to dispatch.
* **`.transferring`**: Shot is staged on `MeticulousServer`; deep-link dispatched; action button locked with an inline spinner (`ProgressView`) to prevent double-tap race conditions.
* **`.transferred`**: Loopback server confirms BQ completed `dump_data: true` fetch; UI transitions to a green checkmark (`[✓ Transferred!]`); sheet auto-dismisses after a 1.2s delay.
* **`.timedOut`**: Watchdog timer expires without BQ consuming the payload; transitions cleanly to an explicit *"Ready to Re-send"* state without stranding the barista.
+--------+ User Taps +--------------+ dump_data:true +---------------+
| .idle | ------------> | .transferring| -----------------> | .transferred |
+--------+ "Add Brew" +--------------+ (Delivery Hook) +-------+-------+
^ | |
| | 25s Watchdog | 1.2s Timer
| v v
| Reset / Retry +--------------+ Auto-Dismiss
+------------------- | .timedOut | Sheet
+--------------+
code
Code
### 2.5. Background Task Assertion & Watchdogs
To guarantee telemetry delivery when iOS switches focus to Beanconqueror:
1. `BQHandoffCoordinator` opens a `UIApplication.shared.beginBackgroundTask` assertion before dispatching the deep-link URL.
2. Upon verified delivery (`onShotDelivered`), a 2.0s grace buffer elapses before releasing the background assertion.
3. A 25.0s fallback watchdog automatically releases the background assertion if Beanconqueror is closed or abandoned.

### 2.6. Headless Test Decoupling
`BQHandoffCoordinator` exposes an injectable `openURLHandler: (@MainActor (URL) -> Void)?`. In production, it dispatches to `UIApplication.shared.open`. In automated XCTest suites, it is mocked with a local closure, allowing full state machine and URL generation testing without popping open external applications on the host device.

---

## 3. Consequences

### Positive
* **Zero Ecosystem Redundancy**: Offloads bean database management, grinder grind-setting tracking, sensory notes, and Visualizer syncing entirely to Beanconqueror.
* **Bulletproof Anti-Rage Protection**: Baristas cannot spam the export button during app-switching transitions in Stage Manager or Split View.
* **Preserved Historical Integrity**: Flight logs remain pristine physical records. Wiping or resetting Beanconqueror has zero impact on BaristaPilot’s disk database.
* **Glanceable Ledger**: Baristas can immediately inspect history to confirm which morning pulls have been cataloged.

### Negative / Trade-offs
* **One-Way Loopback Handoff**: Because Beanconqueror does not write foreign IDs back into `Beanconqueror.json`, BaristaPilot cannot detect if a user later deletes a brew inside Beanconqueror. The ledger tracks *delivery*, not remote database state.
