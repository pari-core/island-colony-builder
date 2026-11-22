# Spec compliance and design decisions

Source: *Pinnacle 1, Project 19: Colony Builder Mini-Game, Detailed Specification*.
Team named in the spec: pari, mahi, nivi, devanshi. Supervisor: Prof. Dr. Rabinder Henry. Coordinator: Dr. Rishika Aggrawal.

## Deviations from the spec

| # | Spec says | Our decision | Status |
|---|---|---|---|
| 1 | TFT display for map, resources and menus (sections 3, 5.1, 7, 27 and 28, test T01, final checklist) | No TFT. All information is shown in the Godot UI on the MacBook. The ESP32 panel uses buttons, encoder, LEDs and an optional buzzer. | **Needs staff confirmation** |
| 2 | Godot or Python/Pygame with a 2D map and sprite tools (section 32) | Godot 4.7.2 in realistic 3D. The handbook allows an approved engine. | **Needs staff confirmation** |

Section 28 includes "TFT dashboard remains synchronized with the game engine". Our proposed equivalent is that the Godot dashboard stays synchronised with the game state, and that the UI responds to every panel command.

## Requirements to track (beyond the original project prompt)

- Construction has a build time, and workers may be tied up while building.
- Score is tracked (EconomyManager).
- Storage overflow follows a documented rule.
- Save/load works, or reset behaviour is documented.
- Map tiles have EMPTY, OCCUPIED and BLOCKED states, with roads or paths connecting colony areas.
- Resources never go negative unless defined as debt.
- A test/debug layer provides logs, deterministic scenarios and regression tests.
- Win and lose thresholds are documented as exact numbers.
- Test cases T01 to T20 have recorded evidence, plus a bug log.
- Testing covers functional, boundary, hardware, usability, balance, performance and regression evidence.
- Asset and licence audit is completed.
- Deliverables D1 to D10 include the BOM, final report (15 to 20 pages, IEEE references) and a 3 to 5 minute live demo.
- At least five credible references are collected, with what each contributed.
- Every team member can explain the resource model, state machine, hardware interface and their own contribution.

## Hardware points to check before wiring

The spec's GPIO table is an example only and must be checked against the actual board.

- GPIO 34 and 35 (encoder) are input-only on ESP32-WROOM boards and have no internal pull-ups, so they need external pull-ups unless the encoder module provides them.
- GPIO 12 (Event button) is a boot strapping pin and can stop the board booting if held high at reset.
- The spec suggests an enclosure of 240 to 280 mm for a panel with a TFT. Removing the TFT changes the layout, but the handbook still asks for about 30 cm minimum characteristic size.
