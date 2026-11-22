# Automated tests

Each `test_*.gd` file starts the real game scene, plays it with simulated keys and
mouse clicks, and prints `PASS` or `FAIL` for every check, ending with
`RESULT fails=N`.

## Running them

From this project folder (the one with `project.godot`):

```bash
bash tests/run_all_tests.sh
```

A game window opens for each test. Do not move the mouse or switch windows while
they run: some tests move the real mouse pointer, and a test window that is
covered or in the background can freeze and fail a timed check.

To run one test:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path . --script res://tests/test_events.gd
```

Screenshots that some tests take are saved in Godot's user data folder
(`user://`), not in the project.

## Coverage of the specification's tests (T01 to T20)

| Spec test | Covered by | Status |
|---|---|---|
| T01 Power-on, T02 Buttons, T03 Encoder, T04 Debounce | ESP32 hardware test sketch (`firmware/hardware_test/`) | Not automated; ESP32 link not built yet |
| T05 Resource collection | `test_workers.gd`, `test_mine.gd`, `test_paths.gd` (walking around buildings) | Automated |
| T06 Resource consumption | `test_placement.gd`, `test_resources.gd` | Automated |
| T07 Insufficient resource | `test_resources.gd`, `test_placement.gd` | Automated |
| T08 Building | `test_buildings.gd`, `test_plots.gd`, `test_mine.gd` | Automated |
| T09 Worker conflict | `test_workers.gd` | Automated |
| T10 Population | `test_population.gd` | Automated |
| T11 Storage | `test_resources.gd`, `test_workers.gd` | Automated |
| T12 Event | `test_events.gd`, `test_drought.gd` (the drought story, mission and Water Storage), `test_disease.gd` (the outbreak story, decision and both endings), `test_stories.gd` (the discovery, trade and migration stories) | Automated |
| Crops and floating text (our addition) | `test_crops.gd` | Automated |
| Controller inputs and menus (keyboard stand-ins) | `test_controller.gd` | Automated; the real ESP32 is not involved |
| Migration ship (our addition) | `test_migration_boat.gd` | Automated |
| Day and night (our addition) | `test_day_night.gd` | Automated |
| Roads, ponds and trees (our addition) | `test_environment.gd` | Automated |
| T13 Research | `test_events.gd` (vaccine), `test_research.gd` (the three upgrades) | Automated |
| T14 Win, T15 Lose | `test_game_state.gd`, `test_landmark.gd` (winning by building the three landmarks) | Automated |
| T16 Save/load | `test_save.gd` | Automated |
| T17 Boundary | `test_resources.gd`, `test_population.gd`, `test_game_state.gd` (one below each threshold) | Partly |
| T18 Long play | none | To do |
| T19 Usability | none | Manual: a new player plays without coaching |
| T20 Regression | `run_all_tests.sh` | Run all tests after every change |

`test_camera.gd` and `test_selection.gd` cover controls that the specification does
not number.
