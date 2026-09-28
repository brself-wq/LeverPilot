# ADR 006: Console Navigation & Global Destination Architecture
Date: September 14, 2026 (Updated: September 26, 2026)
Status: Accepted & Implemented (MVP Candidate 0.0)
Author: Ben Self
Deciders: Architecture Team, LeverPilot Core

## Context & Constraints
- Primary Form Factor: iPad 11" in Landscape.
- Brewing vs System Separation: The center rotary dial owns the active extraction loop. All secondary destinations (Shot History, Recipe Library, Settings) must be full-screen views, not modal popups or sheets.
- Spatial Integrity: The top navigation bar is reserved for telemetry/search pills. The recipe card occupies the center. The bottom bar contains the rotary dial flanked by dark empty space.

## Decision
1. **Single Unified Entry Point**: A universal `[ ☰ ]` hamburger menu anchored at the bottom-left corner of the console screen (`padding(.leading, 28)`).
2. **Centering Invariance**: Pinned inside a `ZStack` alongside `RotaryEncoderDeck`, guaranteeing the rotary dial remains geometrically dead-center on the display.
3. **Visual Language**: High-contrast control style adopting theme tokens (`Theme.Surface.control`, `Theme.Border.glassGradient`).
4. **Layered App Architecture**: `LeverPilotApp` manages root view routing via `AppDestination`:
   - `.brew`: Active `ProfileConsoleView` with carousel, rotary deck, and pre-flight validation.
   - `.history`: Master-Detail `ShotHistoryBrowserView` with telemetry inspection and Beanconqueror export.
   - `.settings`: `SettingsView` governing machine watchdogs, default dose, and server settings.
   - `.workbench`: Reserved offline profiling sandbox.

## Implementation Verification
- **`ShotHistoryBrowserView`**: Fully implemented with master list, native swipe-to-delete, detailed multi-stream telemetry chart, and "Add to Beanconqueror" export action.
- **`HardwareSettingsSheet`**: Dedicated peripheral management sheet with direct RSSI, battery levels, zero/tare controls, and device forgetting.
- **`AddToBeanconquerorSheet`**: Embedded export modal with active bean picker and deep-link handoff coordinator.
