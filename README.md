# LeverPilot

> Avionics Flight Copilot for Manual Lever Espresso Machines  
> Bringing Meticulous Open Espresso Profiles to the Flair 58.

## What is LeverPilot?
LeverPilot is an iPadOS and macOS application designed for manual lever espresso machines. It acts as an avionics flight director during extraction: observing real-time Bluetooth telemetry (pressure and cup weight), evaluating complex multi-stage recipes written in the Open Espresso Profile Format (OEPF), and providing instant guidance to the barista operating the lever.

    [ Chamber Pressure ]       [ Cup Weight ]
       (Bookoo Gauge)           (Bookoo Scale)
              │                       │
              └───────────┬───────────┘
                          ▼ (10 Hz BLE)
                  ┌───────────────┐
                  │  LeverPilot   │ ◄── OEPF Profile
                  │  (iPad Cockpit)
                  └───────┬───────┘
                          ▼ (Local Loopback 127.0.0.1:8080)
                  ┌───────────────┐
                  │ Beanconqueror │ ──► Visualizer.coffee
                  └───────────────┘

## Key Features
- Hands-Free Extraction:
  - Auto-Start: Triggers strictly on hydraulic pressure (>= 0.5 bar), ignoring scale bumps or cup placement.
  - Auto-Stop Watchdog: Automatically ends the shot and snaps true yield after sustained low flow, retroactively trimming trailing zero-flow samples.
- Flight Director HUD:
  - High-contrast, glanceable telemetry from 3 feet away at counter height.
  - Real-time delta guidance badges ("PULL HARDER", "EASE OFF", "ON TARGET").
  - Continuous circular progress racetracks for ascending and decaying triggers.
- Fault-Tolerant Signal Conditioning (ADR-009):
  - 6-sample rolling Ordinary Least Squares (OLS) linear regression for jitter-free flow rate (dw/dt).
  - Weight-latching prevents graph dropouts or premature auto-stops during 2.4 GHz radio hiccups.
- Beanconqueror Integration (Zero Cloud Dependency):
  - Emulates the local Meticulous HTTP/Engine.IO server on 127.0.0.1:8080.
  - Deep-links directly into Beanconqueror's "Add Brew" workflow with one tap.
  - Tracks exported status via a decoupled delivery ledger without mutating immutable historical records.
- Native Files App Support:
  - Profiles and shot logs live in the iPad's Files app under On My iPad/LeverPilot. Drag and drop .json profiles to add them instantly.

## Hardware Compatibility
Tested and optimized for:
- Machine: Flair 58 (or any manual lever espresso machine)
- Pressure Transducer: Bookoo Pressure Transducer
- Smart Scale: Bookoo Scale (Themis / Mini)

## Project Status & Philosophy
Notice: This is a personal hobby project built by a retired engineer for daily use on a Flair 58. It is shared as a gift to the open-source coffee community under GPL-3.0. There is no commercial backing, no SLA, and no commitment to support arbitrary hardware combinations. Forks and pull requests are welcome!

## Building from Source
1. Requires macOS Sonoma/Sequoia, Xcode 16+, and Swift 6.
2. Open LeverPilot.xcodeproj in Xcode.
3. Select the LeverPilot scheme and build for My Mac or an iPad.

## Acknowledgments & Disclaimers
- Beanconqueror: Sincere thanks to Lars Saalbach for building an exceptional open-source brew logbook and championing open coffee tool integrations.
- Meticulous: Built to support the Open Espresso Profile Format (OEPF) and emulate the Meticulous machine API for telemetry handoff. LeverPilot is an independent community project and is not affiliated with, sponsored by, or endorsed by Meticulous Home Inc.
- Flair Espresso: Designed as a copilot for the Flair 58. Flair is a trademark of Intact Idea LLC.

## License
Released under the GNU General Public License v3.0 (GPL-3.0). See LICENSE for details.
