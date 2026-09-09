# Domain Glossary

### Coffee Extraction Physics
* **Pre-infusion / Soak**: Wetting the coffee puck at low pressure (1.0–3.0 bar) to saturate grounds, eliminate air pockets, and reduce channeling.
* **First Drip**: The timestamp and weight threshold (typically $\ge 0.5\text{g}$) when the first drops of liquid fall through the portafilter into the cup.
* **Puck Resistance**: Dynamic hydraulic resistance calculated in real-time as $\text{Pressure} / \text{Flow}$ ($\text{bar} / (\text{mL/s})$).
* **Lever Suck-Back**: Transient vacuum created in the brew chamber when raising a manual lever arm. Causes pressure transducers to read zero or slightly negative.

### Engine & Profiling Concepts
* **Knot**: A coordinate pair $(x, y)$ in a stage's dynamics array defining a target setpoint $y$ at domain progress $x$.
* **Horizon**: The maximum anticipated domain span ($x$) of a stage used to render the full trajectory curve on the HUD.
* **Zero-Order Hold (`.none`)**: Step interpolation mode where the setpoint instantly jumps and holds the knot value without ramping.
* **Deadband**: An intentional tolerance zone around a target setpoint where the system considers the pull "ON TARGET", preventing visual indicator jitter.
* **Guardrail**: A safety limit capping pressure or flow. Exceeding a guardrail trips an audio/visual alarm.
* **Tail Trimming**: Subtracting the post-extraction dead-flow confirmation window (e.g. 1.5s) from the final archived duration in `ShotRecord`.
