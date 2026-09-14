# ADR-006: Console Navigation & Global Destination Architecture
Date: September 14, 2026
Status: Accepted / Implemented (Scaffolding on `feature/ui-console-navigation-hub`)

## Context & Constraints
- Primary Form Factor: iPad 11" in Landscape.
- Brewing vs System Separation: The center rotary dial owns the active extraction loop. All secondary destinations (Shot History, Recipe Library, Hardware Manager, Settings) must be full-screen views, not modal popups or sheets.
- Spatial Integrity: The top navigation bar is already dense with telemetry/search pills. The recipe card occupies the center. The bottom bar contains the rotary dial flanked by dark empty space.

## Decision
1. Single Unified Entry Point: A single `[ ☰ ]` button anchored at the bottom-left corner of the console screen.
2. Centering Invariance: Pinned inside a `ZStack` alongside `RotaryEncoderDeck` with `padding(.leading, 28)`. This guarantees the rotary dial remains geometrically dead-center on the display.
3. Visual Language: 44x44 circular button using existing app token values (`Color.white.opacity(0.06)` fill, `0.08` stroke).
4. Layered App Architecture: `VirtualEspressoMachineApp` manages full-screen view transitions via `ConsoleDestination` (`Layer 4` in root `ZStack`, matching the pattern established for `ShotRecordView`).

## Next Steps When Resumed
1. Implement `ShotHistoryBrowserView` (Master-Detail curve inspector using `ScenarioStore`) to replace the `.history` placeholder.
2. Implement BeanConqueror JSON file export action inside the history inspector.
3. Wire hardware battery/status diagnostics into the `.hardware` placeholder.
