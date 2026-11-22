# Architecture

Status: mainland environment, camera controls, 15 build squares across the flat land, plot selection, placing all seven buildings, the resource system, Warehouse upgrades, workers, civilians, walking around buildings, production, population growth, happiness, events with visuals, vaccine research, win and lose conditions and a score. The other research upgrades, saving, roads, the controller menus and the ESP32 link do not exist yet.

## Current scenes

`scenes/Main.tscn` is the game's starting scene.

| Node | Type | Purpose |
|---|---|---|
| Main | Node3D | Root of the game world |
| WorldEnvironment | WorldEnvironment | Sky, ambient light, tone mapping, ambient occlusion |
| Sun | DirectionalLight3D | Main light, casts shadows |
| Camera3D | Camera3D, `scripts/camera_controller.gd` | Angled top-down view that the player can move, rotate and zoom (15 to 430 m from the focus point) |
| Island | Instance of `scenes/island/Island.tscn` | The environment |
| MapManager | Node3D, `scripts/map_manager.gd` | Creates the build squares (plots) wherever the land is flat, handles selecting them and gives other systems access to them |
| BuildingManager | Node3D, `scripts/building_manager.gd` | Placement mode: preview, green and red indicators, cost display, confirm and cancel |
| ResourceManager | Node, `scripts/resource_manager.gd` | Holds food, wood, stone and gold, and applies the resource rules |
| UI/ResourcePanel/ResourceBar | Label, `scripts/resource_bar.gd` | Shows resource amounts along the top of the screen |
| WorkerManager | Node3D, `scripts/worker_manager.gd` | Creates the six workers, assigns jobs and runs production |
| PathGrid | Node, `scripts/path_grid.gd` | Finds walking routes around buildings for workers and civilians: a 2 m grid over the island, with each building's measured footprint plus 1 m marked solid; AStarGrid2D finds the cells and the route is straightened into long lines. Rebuilt when a building is placed; anyone walking then re-plans |
| CivilianManager | Node3D, `scripts/civilian_manager.gd`, `scripts/civilian.gd` | Creates civilians, gives them homes, trains civilians into workers (T on a House); each civilian wanders near home, goes in and out of the House door, with walk and idle animations |
| PopulationManager | Node, `scripts/population_manager.gd` | Food use, housing, happiness, growth and the population state |
| TimeManager | Node, `scripts/time_manager.gd` | The calendar: in-game days of 20 seconds each |
| ConstructionManager | Node3D, `scripts/construction_manager.gd` | Buildings that take days and builders to finish (the Water Storage) |
| DiseaseMission | Node3D, `scripts/disease_mission.gd` | The disease outbreak as a story with a decision: research a vaccine or wait |
| DroughtMission | Node, `scripts/drought_mission.gd` | The drought as a story and a mission to build a Water Storage |
| UI/StoryBox | Control, `scripts/story_box.gd` | A small board that tells a story page by page while the game waits |
| SaveManager | Node, `scripts/save_manager.gd` | Saves the colony to a file and loads it back |
| EventManager | Node, `scripts/event_manager.gd` | Runs the seven events one at a time, with a calm period and a resource check before each, and handles responses |
| ResearchManager | Node, `scripts/research_manager.gd` | Research at the Research Lab: the vaccine and three upgrades |
| EventEffects | Node3D, `scripts/event_effects.gd` | Shows each event on the island with built-in Godot effects |
| GameStateManager | Node, `scripts/game_state_manager.gd` | Checks the win and lose conditions each upkeep cycle, makes people leave an unhappy colony, keeps the score, shows the end screen and restarts the game |
| UI/GoalLabel | Label, `scripts/goal_panel.gd` | Shows the goal, progress towards it and warnings before a loss |
| UI/EventLabel | Label, `scripts/event_panel.gd` | Lists active events and how to respond |
| UI/SelectionLabel | Label, `scripts/selection_panel.gd` | Describes the selected plot, its workers and its output |
| UI/PlacementLabel | CanvasLayer with a Label | Shows the cost and status during placement mode |

`scenes/island/Island.tscn` holds the environment.

| Node | Script or shader | Purpose |
|---|---|---|
| Terrain | `scripts/island_terrain.gd`, `scenes/island/terrain.gdshader` | Builds the land, coast, lake, river and hills from a height function, as a detailed mesh around the town and a coarse one for distant land, and blends sand, grass and rock by height and slope |
| Water | `scenes/island/water.gdshader` | Sea with depth-based colour, ripples and shoreline foam |
| Decorations | `scripts/island_decorations.gd` | Places rocks, oak groves around the town, oak forests on the distant hills and palms along the beach |

Design rules:

- Scale: 1 Godot unit = 1 metre.
- The land within 215 m of the centre is flat at 2.2 m for building, apart from the rocky hill, the lake, the river and the beach.
- `get_height_at()` in `island_terrain.gd` is the single source of ground height.
- Setting (team decision, 2026-11-12): ordinary mainland with a coast on one side, replacing the island. The sea and beach lie to the east (+x, about 152 m from the centre); grassy land stretches away north, west and south. The file and node names still say "island".
- From 215 m the land rolls up into larger hills (about 9 m, low enough to stay grassy, because rock patches look blocky on the coarse mesh), kept low beside the river. The camera can roam up to 450 m from the centre.
- The river is carved below sea level, so water fills it. It runs west to east about 130 m south of the centre, from a lake at (-168, 136) to the sea.
- Two meshes: 1 m squares for the 420 m around the town, and 12 m squares for 2400 m of distant land, set 0.15 m lower with a small overlap so no gap or flicker shows. The small hills fade out before the join because the coarse mesh cannot show them.
- Trees: 80 oaks in 14 groves around the town and 170 in 26 forests on the distant hills (215 to 470 m out), using the Oak tree model chosen by the team (7,112 triangles, CC BY 4.0). `scenes/island/Oak.tscn` scales it to about 12 m and stands its trunk on the ground. Its leaves are switched from blended to cut-out transparency (alpha scissor), which is cheaper for a forest and still casts shadows. Palms now grow only along the beach.
- Terrain squares hidden under deep water are not built, and palms and rocks switch to simpler levels of detail early (`LOD_BIAS`), to keep drawing cost down.
- Terrain and decorations use fixed random seeds, so the land is identical on every run.

## Building plots

`scripts/building_plot.gd` defines one 24 m square plot. Each plot has an ID from 1 to 12, a state (EMPTY, OCCUPIED or BLOCKED) and a ground outline coloured by that state: white, blue or dark grey. Green and red are reserved for the placement preview.

The outlines are hidden during normal play and appear while placing a building. Hiding them does not affect the plots or their states.

Placement mode starts with the `build` action (B key). A click confirms; Esc or `build` again cancels. `start_placement()`, `confirm_placement()` and `cancel_placement()` can also be called by the ESP32 later. In placement mode, keys 1 to 6 choose the building (`choose_building_1` to `_6`, or `choose_building()` for the ESP32 later). Costs are first guesses, listed in `BUILDINGS` in `building_manager.gd`, and are spent when placed. A plot shows red if it is not empty or the colony cannot pay. Placing is instant until build time is added.

## Resources

The colony starts with 150 food, 150 wood, 80 stone and 20 gold, enough for one of each building, with storage for 200 of each. These values are first guesses, to be balanced later.

- No negative amounts: a cost is either paid in full or not at all.
- Overflow rule: anything beyond the storage limit is lost.
- Each standing Warehouse adds 200 storage for every resource per level (200, 400, 600 and so on). A Warehouse can be upgraded on its own plot with U while selected: level 2 costs 40 wood and 30 stone, level 3 costs 60 wood and 50 stone, so one level 3 Warehouse adds 600. It must be standing (not collapsed) to upgrade. The model grows 10% per level and paths are worked out again around it. A gold "Lv N" sign floats above each Warehouse; it faces the camera and keeps the same size on screen at every zoom. A collapsed Warehouse stops counting until repaired; amounts already above the lower limit are kept, but nothing more of that resource is stored until it falls below the limit.
- Gold comes from the Mine (key 7: 30 wood, 15 stone, 2 worker slots). A Mine makes 40% of its workers' productivity in gold, fractions dropped, so gold stays scarce. Trades also give gold. The Mine uses the Stylized Gold Mine model, chosen by the team; it is cartoon-styled, unlike the other realistic buildings.

## Workers and production

There are six workers, defined in `WORKER_LIST` in `worker_manager.gd`, each with a fixed productivity (Asha 5, Ben 4, Chen 4, Dara 3, Eli 3, Farah 5).

- Each worker has at most one job. Farm, Lumber Camp and Quarry each have two worker slots; other buildings have none yet.
- Select a building, then press J to add the first idle worker or K to remove the latest. `assign_worker()` and `remove_worker()` can also be called by the ESP32 later.
- Every 5 seconds, each building adds the total productivity of the workers who have reached it: Farm makes food, Lumber Camp wood, Quarry stone. There is no randomness.
- A Farm makes 1.5 times its workers' productivity (Asha and Ben: 9 becomes 13), so one Farm comfortably feeds the first colony.
- Output is multiplied by the population state (below), with fractions dropped.
- Idle workers stand in the centre of the island. The model has no skeleton or animation, so workers slide to their job at 12 m/s in a fixed pose. Their routes go around buildings (see PathGrid). Mixamo is an option for real walking later (team decision, 2026-11-05).

Build anywhere (team decision, 2026-11-14): the flat land around the town is a grid of build squares, called plots in the code. Each is a 24 m square with a 4 m lane to the next, 28 m centre to centre, and holds one building. `MapManager` creates a square wherever the ground is flat for 2 m beyond its edges, within 185 m of the centre and on the town's side of the river (there is no bridge), which gives 80 possible squares. Since 2026-11-18 only the nearest to the town square are used (`MapManager.MAX_PLOTS`; the spec asks for at least 12), at the team's request: with few places, choosing what goes where is part of the game. It was 15, then 20 the same day. A winning colony needs about 10 to 12 buildings, so there are some spare, but no building can be removed once placed. None are on the rocky hill, the lake, the river or the beach. The middle square is left out as the town square, where idle workers wait and homeless civilians wander. Plots are numbered from the town square outwards. This replaced 20 fixed plots; a fully free placement was rejected because the ESP32 buttons can step from square to square but cannot place a building freely. All start EMPTY. Nothing sets a plot to OCCUPIED or BLOCKED yet; later systems will.

Clicking a plot selects it through `MapManager.select_plot()`, which the ESP32 can also call later. The selected plot shows a yellow outline, and `selection_changed` tells other systems. Clicking elsewhere or pressing Esc clears the selection.

## Population and happiness

Values are first guesses, set in `population_manager.gd`. Every 10 seconds:

1. Each worker eats 2 food and each civilian 1 (16 at the start). If there is not enough, they eat what is left and the colony is hungry. Food never goes below zero.
2. Happiness changes by +2 if everyone was fed, or -10 if hungry.
3. Happiness changes by -1 for each person without a home. The landing camp homes the first 10 people, and each House homes 4 more, workers and civilians together.
4. Population grows by one civilian after 2 cycles in a row (20 seconds) with everyone fed, everyone housed and a free space in a House, up to 20 civilians. New workers come from training civilians (T on a selected House, 10 food each) or the Migration event, up to 12 workers.

The colony starts with 6 workers and 4 civilians, all sheltered by the landing camp, so nobody is homeless at the start. Houses are needed for the colony to grow. (The camp is a rule only; it has no model on the island yet.)

Civilians live in Houses, eat food and count towards happiness. They do not take jobs, but the player can train one into a worker: select a standing House and press T, for 10 food. A civilian living in that House is chosen, and the new worker appears where they were. They share out the standing Houses in turn (homeless ones wander in the island centre), walk to a spot 13 to 18 m from their home at 2.4 m/s with the Mixamo walking animation, then stand with the idle animation for 3 to 8 seconds. Civilians with a House go inside through the front door every 2 to 4 walks, stay hidden inside for 15 to 30 seconds, then come back out. Their routes go around every building (see PathGrid). If their House collapses, anyone inside comes out. Each civilian has its own fixed random seed, so routes repeat every game. Disease affects only workers.

Workers and civilians are drawn 1.5 times real size (2.7 m tall) so they are easy to see from the strategy camera; they still fit under the House door (3.3 m). Civilians walk 1.5 times faster to match, so their feet do not slide.

Happiness stays between 0 and 100 and sets the population state:

| State | Happiness | Output |
|---|---|---|
| Thriving | 70 to 100 | x1.25 |
| Stable | 40 to 69 | x1.0 |
| Struggling | 0 to 39 | x0.75 |

## Orders board (removed)

Removed on 2026-11-15 at the team's request: it added a second thing to watch beside the events, and made gold come in too fast. Gold now comes only from the Mine and the Trade event. The old code is in the git history (`scripts/order_manager.gd`, `scripts/order_panel.gd`, `tests/test_orders.gd`).

## The landmarks

Added 2026-11-16 for two reasons: the specification asks for at least two win conditions (its example Win 2 is "Construct required landmark"), and spare wood, stone and gold had little use late in the game. A single Lighthouse proved too easy when the team played it, and five felt out of balance with the first win condition, so the team settled on three.

| Landmark | Cost | Builders | Days | Key |
|---|---|---|---|---|
| Lighthouse | 150 wood, 120 stone, 40 gold | 3 | 5 | 9 |
| Harbour | 180 wood, 40 stone, 20 gold | 3 | 3 | 0 |
| Town Hall | 150 wood, 150 stone, 50 gold | 3 | 4 | list |

- **Costs follow what each is made of** (the Harbour is mostly wood, the Town Hall the dearest). All three together need 480 wood, 310 stone and 110 gold, and 12 days of building if done one after another. Every single cost fits inside the starting storage limit of 200. These numbers are first guesses, aimed at a game of about 10 minutes and at being about as hard as the first win condition; neither has been checked by playing.
- **Choosing them:** keys 9 and 0 while placing, or the build list (Space), which shows all of them. The placement text lists them on their own "Landmarks:" line. They come after the Water Storage in `BuildingManager.BUILDINGS`, so the Water Storage keeps key 8; each line of the build list now remembers which building it is, because a hidden building shifts the lines.
- **Building them:** through `construction_manager.gd`, like the Water Storage. One of each.
- **Winning:** `GameStateManager` listens for `construction_finished` and wins when every building marked `"landmark"` is finished. Landmarks that come back from a saved game send no signal, so loading cannot win twice.
- **Shown:** the goal panel's second line, for example "Or: build all 3 landmarks (1 done): Lighthouse done, Harbour 40%, Town Hall".
- **The models** are drawn in code; no downloaded asset is used. The Lighthouse has its own script (`lighthouse.gd`: its tower grows smoothly and its lamp lights when finished). The Harbour and Town Hall extend `landmark_model.gd`, where each shape is given the moment in the work when it appears, so they go up piece by piece inside scaffolding. To add a landmark, write a script like `harbour.gd` and add an entry marked `"landmark": true`.

## Winning, losing and score

Everything is checked once per upkeep cycle (10 seconds), in `scripts/game_state_manager.gd`. These are the exact thresholds:

| Result | Condition |
|---|---|
| Win 1: thriving colony | 24 or more people and happiness 70 or more, for 3 cycles in a row (30 seconds) |
| Win 2: landmarks | All three landmarks are finished (see "The landmarks" above). Checked the moment a landmark's construction ends |
| Lose: starvation | Not enough food for 6 cycles in a row (60 seconds) |
| Lose: storage full | Food, wood, stone and gold all at the storage limit for 6 cycles in a row (60 seconds), checked just before the colony eats |
| Lose: nobody left | The population reaches 0 |

While happiness is 0, one person leaves each cycle: the newest civilian first, then the newest worker (a worker busy with a repair or on the way to treatment stays). Any cycle that breaks a condition resets its count. The goal line in the top left shows progress and counts down each danger in seconds.

**Both wins also need every event in the schedule to have been faced once** (added 2026-11-16): discovery, drought, trade, disease and migration, each from start to end. The team found the first win could be reached after a single event. `EventManager` remembers the event types that have ended (`get_faced_count()`, `has_faced_all()`, saved with the game), and the goal panel shows "Both need all 5 events faced first (2 so far)". With 90 seconds of calm before each event, the shortest possible game is about 11 minutes, and up to about 14 if the drought and the outbreak run their full length.

Score = 10 for each person + happiness + 5 for each building. When the game ends, the scene tree pauses and an end screen shows the result, the reason and the score; Enter starts a new game by reloading the scene. After a win, N keeps playing the same colony in free play: it can no longer be won or lost (so every event can still be shown), but people still leave at happiness 0.

The team chose these rules on 2026-11-12. The poster's "storage full" loss was read as all four resources full, because one full resource is normal play.

## Events

The events follow the example table in section 15 of the specification. Effects and numbers are first guesses. **Five events are in the schedule** (changed 2026-11-15, team decision: seven felt crowded), in a fixed order with an easy one between the two missions: Resource discovery, Drought, Trade opportunity, Disease outbreak, Migration, then repeat. Storm and Building accident still work and are still tested, but are left out of the schedule (`EventManager.ORDER`); adding one back is one word in that list. The specification asks for at least five event types. Only one event runs at a time. The first comes after 60 seconds of calm. When an event ends, or the player has dealt with it, 90 seconds of calm begins, and the countdown is held while an event runs. After the calm, the next event also waits until the colony has the resources to answer it and has no building site still being worked on, but never more than 90 seconds:

| Next event | Waits until the colony has |
|---|---|
| Trade opportunity | Enough wood or stone for one offer (40 of either) |
| Drought | 50 food (a store to get through it), plus 10 wood and 5 stone for the Water Storage if there is none |
| Building accident (not in the schedule) | 10 wood and 5 stone (the repair) |
| Disease outbreak | 15 gold for vaccine research, unless the vaccine is already researched |
| Others | nothing |

The event panel shows the calm countdown, or what the next event is waiting for. F9 starts the next event at once, for testing and the demo.

| Event | Effect | Player response |
|---|---|---|
| Drought | Food output x0.5 until the mission ends (at most 6 days); x0.8 for 3 days once the Water Storage stands | Build the Water Storage (see "The Last Drop" below) |
| Storm (not in the schedule) | All output x0.75 for 45 s | Prioritise essential work |
| Resource discovery | Wood and stone output x1.5 for 60 s | Put workers on wood and stone |
| Disease outbreak | Every second worker falls sick (1st, 3rd, 5th...) and produces nothing; happiness -5; the sick recover by themselves after 120 s | Research the vaccine once, then Enter: the sick walk to the Research Lab and recover on arrival (free); happiness +10 when all are treated |
| Trade opportunity | Three offers worked out from the stores: half the wood, half the stone, or a quarter of each, for 1 gold for every 2 | A board asks which to accept, or decline (see "Event stories" below) |
| Migration | 2 new workers arrive from the eastern beach; lasts 2 in-game days (40 s) | Make sure everyone has a home before it ends: happiness +3 |
| Building accident (not in the schedule) | The building with the lowest plot number collapses and stops working (a collapsed House homes nobody) | Enter: pay 10 wood and 5 stone and send up to 2 idle workers; they repair it in 20 s once there (40 s with one) |

Visuals (`event_effects.gd`, built-in effects only, no downloaded assets): Storm darkens the sky, dims the sun and adds fog and rain; Drought brightens and warms the light and dries the grass; Resource discovery shows sparkles over Lumber Camps and Quarries (or the rocky hill); Trade shows a golden beacon on the beach; Disease shows a red cross over each sick worker until they reach the Lab; Migration shows workers walking in from the beach; Building accident tilts and sinks the building in a dust cloud, and it rises again when repaired.

Vaccine research: select a built Research Lab and press R. It costs 15 gold and takes 45 seconds while the Lab stands.

## Research upgrades

Added 2026-11-15, from the examples in section 16 of the specification. Numbers are first guesses.

| Upgrade | Effect | Cost | Time | Needs |
|---|---|---|---|---|
| Improved Farming | Food production x1.2 | 10 gold | 30 s | nothing |
| Efficient Tools | Wood and stone production x1.2 | 15 gold | 40 s | Improved Farming |
| Storage Engineering | Storage limit x1.25 | 20 gold | 40 s | Efficient Tools |

- **Why +20% and not the specification's +10%:** amounts are whole numbers with fractions dropped, so +10% often changed nothing (7 wood stays 7).
- **The tree** is one chain of three; the vaccine stands alone. The Lab does one project at a time, and research stands still while the Lab is collapsed.
- **How to research:** select the Research Lab and press Space for its menu. A refused item says why ("Research Improved Farming first", "Not enough resources (needs 10 Gold)", "The Lab is busy with ...").
- **Where the effect is applied:** `ResearchManager.get_output_multiplier(type)` is multiplied into `WorkerManager.get_output()`, and `get_storage_multiplier()` into `ResourceManager.refresh_storage()`. An upgrade lasts for the rest of the game and is saved.
- **Shown:** the selection panel lists each upgrade as ready, locked, a percentage or done, and "... researched" floats over the Lab when one finishes.

Workers now follow the ground height while moving, so they walk over hills.

Events only run together if F9 starts one early; their effects then multiply. While an outbreak or a collapsed building is waiting to be dealt with, the calm does not start. The spec's Storm also slows construction; building is instant for now, so only production slows.

## Days, construction and the drought mission ("The Last Drop")

Added 2026-11-15. The drought is now a short story with one mission, to build a Water Storage, instead of a 60-second food penalty. Four scripts do this, each usable on its own:

- **Day clock** (`scripts/time_manager.gd`, node `TimeManager`): counts in-game days; one day is 20 seconds of play (`DAY_SECONDS`). It sends `time_passed(days)` every frame and `day_started(day)`. The top bar shows "Day N". Anything measured in days listens to this clock and never counts seconds itself. The clock stops while the game is paused.
- **Construction** (`scripts/construction_manager.gd`, node `ConstructionManager`): a building with `build_days` in `BuildingManager.BUILDINGS` starts as a building site. Up to `builders` idle workers are sent to it (with the same function that sends a repair crew, so they cannot hold a second job), and work moves forward only while a builder stands at the site: one of two builders works at half speed. A sign over the site shows the percentage. Only the Water Storage uses this so far; other buildings are still finished at once.
- **Water Storage** (`scripts/water_storage.gd`, `scenes/buildings/WaterStorage.tscn`): 10 wood, 5 stone, 2 builders, 3 days. A round wooden tank on a stone base, made from simple shapes in code because the project has no tank model; this also lets it rise bit by bit while it is built. It is hidden from the build list until the first drought (`"locked"`), and the colony can have only one (`"limit"`).
- **Story board** (`scripts/story_box.gd`, node `UI/StoryBox`): a small wooden board at the bottom of the screen that tells a story page by page, the words appearing a few at a time. The game waits while it is open. Space, Enter or the Continue button finishes the page, then turns it.
- **Drought mission** (`scripts/drought_mission.gd`, node `DroughtMission`): EventManager still decides when a drought starts; this script decides what it is.

How a drought plays:

| Situation | What happens |
|---|---|
| First drought, no Water Storage | Four story pages and a mission page. Farms make half food. The Water Storage joins the build list and the player chooses where to put it. |
| The Water Storage is finished in time | The drought ends, a closing story is told, happiness +5, and farms make 25% more for 2 days. |
| It is not finished within 6 days | The rain returns anyway, with a different ending and happiness -10. It can still be built afterwards. |
| Later droughts, Water Storage standing | One story page. Farms make 80%, and the drought passes after 3 days. |

- **The twist:** the story says the old reservoir was near the riverbank. If the Water Storage is built within 80 m of the river (squares 12 and 19; this was 55 m, but none of the nearest squares is that close), the builders find the old foundation a third of the way in and the work is one day shorter. This is not random: the specification asks for a deterministic, testable game, so the surprise depends on where the player builds.
- **Shown on the island:** the grass, crops and sky dry out as before; the river and sea now fall by 1.1 m over 12 seconds and rise again afterwards; civilians say short lines about the drought; the tank rises with scaffolding and fills with water when finished.
- **Before a drought** the schedule now waits for 50 food plus the Water Storage's wood and stone (if there is none), for at most 90 seconds as before.
- **What the next event waits for** (shown on the right): after the calm, the next event also waits while any building site is unfinished, such as a landmark, for at most 90 seconds. Until 2026-11-18 the panel only ever mentioned resources, so it asked for amounts the colony already had; `EventManager.get_wait_reason()` now names the building first ("waits until the Lighthouse is finished building"), and otherwise only the resources still missing.
- **Not done:** background music (the project has no sound yet), workers carrying materials (the worker model has no animations), cracked ground, and a tank model. All the numbers are constants at the top of `drought_mission.gd`, `time_manager.gd` and the Water Storage's entry in `BUILDINGS`.

## The disease mission ("The Silent Plague")

Added 2026-11-15. `scripts/disease_mission.gd` (node `DiseaseMission`) tells the disease outbreak as a story with one decision. The rules of the outbreak did not change and still live in `event_manager.gd` and `research_manager.gd`: every second worker falls sick and makes nothing, happiness -5; the vaccine costs 15 gold and 45 seconds at the Research Lab; with it the sick are sent to the Lab and each recovers on arriving, and happiness rises by 10 when the last is treated; left alone, everyone recovers after 120 seconds with no reward. These two timers count seconds of play, as the team asked for this event, not in-game days.

What the mission adds:

- **Opening story:** three scenes, an urgent notice with the real numbers ("3 of 6 workers are sick"), then the possible solution. Told on the story board (`UI/StoryBox`) while the game waits.
- **The decision:** a wooden board asks "How will you handle the outbreak?" with two answers, each showing its cost, time and result. Back cannot close it. "Research a vaccine" is refused, with the reason, without a working Research Lab or without 15 gold. Choosing to wait does not lock the player in: the vaccine can still be researched at the Lab afterwards. The board is `ControllerMenu.open_choice(title, get_items)`, which any later event can use.
- **Shown on the island:** a "Vaccine research 44%" sign over the Research Lab, "VACCINE READY!" when it finishes, and "Cured!" over each worker as they are treated. The red crosses over sick workers were already there. The event list shows the countdown, "3 of 6 workers sick" and the research percentage.
- **Two endings:** treating everyone gives the vaccine ending and "OUTBREAK CONTAINED!"; letting it pass gives the waiting ending and "THE COLONY HAS RECOVERED!". The outbreak ends exactly once (`EventManager.disease_ended(cured)`), so only one ending is told and happiness is given once. If gold was spent but the illness passed before the vaccine was ready, the ending does not say "No gold spent", and the research carries on.
- **Later outbreaks:** with the vaccine already researched, the story says so and the first answer becomes "Use the vaccine", free.
- **Not done:** sick workers sitting or resting (the worker model has no animations; they stand at their posts under a red cross), sound and music, and choosing sick workers one at a time (they are all sent together).

## Event stories (discovery, trade, migration)

Added 2026-11-15, so that every event in the schedule is told as a story. `scripts/event_stories.gd` (node `EventStories`) covers the three lighter events; the two missions keep their own scripts. The story text was drafted for the team to edit and sits in constants at the top of the script.

| Event | Title | Opening | What the player does | Endings |
|---|---|---|---|---|
| Resource discovery | A LUCKY FIND | Two workers discover a grove of oaks and a hillside of loose stone; a notice gives the bonus and how many workers are placed to use it | Put workers at a Lumber Camp and a Quarry | Says how much wood and stone was gathered, or that the find went to waste |
| Trade opportunity | THE MERCHANT'S SAIL | A merchant ship anchors; its captain offers gold for wood or stone | Answers a board: one of three offers (one that cannot be made says why, e.g. "Not offered: you have too little stone") or decline | One naming the cargo accepted, one for declining |
| Migration | NEW ARRIVALS | A boat of settlers arrives; a notice names the two new workers; a mission page says how many people need a home | Builds a House within 2 days if anyone is homeless | Everyone housed: happiness +3. Otherwise: says how many have no home |

- **The captain's offers** (changed 2026-11-19, then 2026-11-20, team decisions). A single fixed offer of 30 wood for 15 gold was too small to matter; fixed big offers could ask for more than the colony had. The team asked that the amounts never exceed the stores or leave the colony short. So the offers are now worked out from the stores when the ship arrives (`EventManager.make_trade_offers()`), and stay fixed while the board is open:

| Offer | Asks for | Pays |
|---|---|---|
| Timber | Half the wood | 1 gold for every 2 |
| Stone | Half the stone | 1 gold for every 2 |
| Timber and stone | A quarter of each | 1 gold for every 2 |

  Amounts are rounded down to tens and capped at 100 of each resource, so at least half of every store always stays at home. If the gold would not fit in storage, the offer is cut down to fit, so no gold is wasted. An offer of under 20 goods is not made, and the board says why ("Not offered: you have too little stone", "your gold store is full"). Example with 200 wood, 70 stone and 20 gold: 100 wood for 50 gold, 30 stone for 15 gold, or 50 wood and 10 stone for 30 gold. The rate (`TRADE_GOODS_PER_GOLD`) was first 2 gold for every 5, which the team found too little for a once-a-game event, then 1 gold each, which paid nearly all the landmarks' gold at once and made the Mine hardly matter. 1 gold for every 2 is better than the colony can do itself (wood is about 2.5 times easier to make than gold) while still costing wood the landmarks need. Enter (without the board) takes the first offer that can be made.
- **Pictures:** the story board draws a small picture for each story from simple shapes: a sun (drought), a red cross (disease), a sparkle (discovery), a coin (trade) and a boat (migration).
- **Tests switch stories off** with `StoryBox.enabled = false` when they are checking an event's rules, so nothing pauses them. The stories have their own tests.

## Crops and floating text

These two scripts make the colony's activity visible. Neither changes any game number.

- **Crops** (`scripts/crop_manager.gd`, node `CropManager`): every Farm gets two soil beds with 84 plants, one bed down each side of the building. Each production cycle in which the Farm makes food, the crops grow one step; after six steps (30 seconds) they are full size and golden; on the next cycle they are harvested and start again. Nothing grows without workers or while the Farm is collapsed, and crops look dry during a drought. The plants are thin leaf shapes built in code and drawn as one MultiMesh per Farm, so there is no model file. The beds sit outside the Farm's measured footprint, so walking routes are unchanged.
- **Floating text** (`scripts/popup_manager.gd`, node `Popups`): text rises from a building's roof and fades over 1.8 seconds: "+13 Food" in the resource's colour each time a building makes something, "Storage full" in red when none of it fits, "Harvest!", "Farm built", "Level 2" and "New worker". Two texts on one building at once are stacked.
- **Signals added for this:** `WorkerManager.produced(plot, stored)`, `BuildingManager.building_placed(plot)` and `building_upgraded(plot)`, `CivilianManager.worker_trained(plot)`, `CropManager.harvested(plot)`.

## Save and load

`scripts/save_manager.gd` (node `SaveManager`) writes the colony to one file, `user://island_colony_save.json`, and loads it back. The file is JSON, so it can be opened and read.

- **Who saves what:** each manager has `get_save_data()` and `load_save_data()` for its own part, and SaveManager only collects the parts and hands them out again. Saved: the day, buildings (plot, name, level, and which locked buildings are unlocked), building sites and their progress, the drought mission's results, each worker's job, the number of civilians, resources, happiness and the countdown to the next meal, the event schedule, the orders board, research, crop growth, and the win and lose counters.
- **Loading starts from a new game:** the scene is loaded again and the save is put into it, buildings first, because jobs, homes, the storage limit and crop fields depend on them. Nothing from the old game can be left behind.
- **Where to find it:** "Save the game" and "Load the saved game" in the pause menu, and "Continue saved game" on the start board when a save exists. Both show when the save was made.
- **Limits, on purpose:** there is one save, and saving again replaces it. The game cannot be saved while an event is happening or after it has ended; the menu says why. Workers and civilians appear at their jobs and homes, not where they were standing. The camera position is not saved.
- **Bad files:** a damaged file, or one from another version of the save layout (`VERSION`), is refused and the menus do not offer it. Entries that name a plot or building the game does not have are skipped.

## Controller inputs and menus

`scripts/controller_menu.gd` (node `ControllerMenu`) lets the whole game be played with the ESP32 controller's nine inputs. Each input is a named action in the Input Map with a keyboard key for testing. The ESP32 link, when built, will fire the same actions.

| Input | Action | Test key | Free play | While building | In a menu |
|---|---|---|---|---|---|
| Arrows | `pad_up/down/left/right` | Arrow keys | Move the view | Move the cursor to the next square | Move the highlight |
| Select | `pad_select` | Tab | Jump to the next building | | |
| Action | `pad_action` | Space | Open the selected building's menu; with nothing selected, answer an event | Open the list of buildings for the cursor square | Do the highlighted item |
| Build | `build` | B | Start placing | Stop placing | |
| Menu | `pad_menu` | M | Open the pause menu | Cancel and open the pause menu | Close |
| Encoder turn | `pad_turn_left/right` | - and = | Zoom | Change the building (for mouse players) | Move the highlight |
| Encoder push | `pad_back` | Backspace | Clear the selection; with nothing selected, decline an event | Cancel | Close |

- **Wooden board:** every menu is drawn on a wooden signboard by `scripts/wooden_board.gd`. The planks, grain, frame and nails are drawn with shapes in code, so there is no picture file and no asset licence.
- **Start board:** shown once when the game is launched, with Start game and Quit. The game waits behind it. It is skipped after "Restart the game" and in the automated tests.
- **Building with the controller:** Build, move to a square with the arrows, Action to open the list of buildings with their costs, choose one, Action to place it. The see-through preview shows the highlighted building. Back returns to choosing a square.
- **Building menu:** lists only what the selected building can do: add or remove a worker, train a civilian (House), upgrade (Warehouse), research a vaccine or an upgrade (Research Lab). A refused item shows the reason in the menu.
- **Pause menu:** pauses the game. Items: resume, start the next event now (for testing events without the F9 key), rotate the view, restart, quit.
- **Build cursor:** the arrows move between build squares in the four grid directions, matched to the camera's facing, and jump over gaps such as the town square. The view glides to follow. Moving the mouse takes the cursor back.
- **Win and lose screens:** Action restarts, Back keeps playing after a win.
- **Hint line:** the bottom-right of the screen always lists what each input does at that moment.
- The older keys (J, K, T, U, R, 1 to 7, 8 to 0, Enter, N, F9) and the mouse still work. W, A, S and D always move the view; the arrow keys now belong to the controller actions.

## Asset decisions

- Civilians use the casual-clothing man and woman, rigged and animated on Mixamo (idle and walking, in `assets/characters/civilians/`). The original GLB files (T-pose, no skeleton) stay in `assets/characters/` but are not used.
- The Stylized Gold Mine also marks its materials as metal, so it uses `scripts/non_metal_building.gd`.

- Warehouse and Research Lab use `scripts/non_metal_building.gd`, because their models mark wood and brick as fully metal, which made them look almost black. The model files are unchanged.

- Worker: `assets/characters/industrial_safety_worker_walking.glb`, in a static pose.
- `assets/characters/female_worker_waking_cat.glb` stays in the project but is not used, because its animation distorts in Godot.

## Planned modules (spec section 19)

InputManager, GameStateManager, MapManager, ResourceManager, BuildingManager, WorkerManager, PopulationManager, EventManager, ResearchManager, EconomyManager, TimeManager, UIManager, FeedbackManager, SaveManager, and a test/debug layer.

Controller layout chosen by the team (2026-11-05), 8 push buttons plus the rotary encoder:

| Control | Function |
|---|---|
| Up, Down, Left, Right | Move camera |
| Build | Open building options |
| Action | Confirm placement or interact |
| Select | Select a building or object |
| Menu | Pause, settings and exit |
| Rotary encoder | Not yet assigned; proposed for choosing options, zoom and cancel |

Plan agreed 2026-11-10 (not built yet): the whole game works with these 9 inputs by using small on-screen menus instead of one key per command, and a plot cursor instead of the mouse.

| Control | Normal play | In a menu or while placing |
|---|---|---|
| Up, Down, Left, Right | Move camera | Move between plots or menu items |
| Select | Jump to the next plot or building | |
| Action | Open the selected building's actions (add or remove worker, train, research, upgrade) | Confirm |
| Build | Open the build menu | |
| Menu | Pause menu (save, load, rotate camera, quit) | |
| Encoder turn | Zoom | Scroll the list |
| Encoder push | Back, cancel, decline a trade | Back |

During an event alert, Action accepts and the encoder push declines. The keyboard keys stay for testing. `documentation/hardware/esp32_wiring_diagram.svg` still shows a different list of buttons and needs updating.

The ESP32 reads and debounces physical input, and the game validates each command against colony state before applying it. Keyboard and mouse remain fully usable without the panel.

This file will be updated as each module is built.

## The migration ship

Added 2026-11-18. `scripts/migration_boat.gd` (node `MigrationBoat`) brings the newcomers of the Migration event by sea, using the "Swedish royal yacht Amadis" model (Finnish Heritage Agency, CC BY 4.0, 26 m long after scaling; about 455,000 triangles and 64 MB, so it is only shown during a migration).

- When a migration starts, the ship appears 260 m off the eastern beach with the newcomers standing on its deck. They are real workers from the start, marked `aboard`, which stops `WorkerManager` walking them.
- While the story is open the game is paused, so the ship waits. Then the camera glides to the beach and the ship sails in at 22 m/s (about 10 seconds), rising and rolling gently on the waves.
- It anchors 32 m off the beach. The newcomers are put on the sand and walk to the town as usual. After 4 seconds it sails back out and disappears.
- With no room for newcomers the ship still comes and goes, landing nobody. The story text now says "a sailing ship" instead of "a small boat".

## Day and night

Added 2026-11-18. `scripts/day_night.gd` (node `DayNight`) turns the sky once every 5 in-game days (`DayNight.CYCLE_DAYS`), which is 100 seconds of play. It first followed the in-game day (20 seconds), but the team found day and night far too short. The calendar and everything that counts days are unchanged, so the top bar's day number goes up five times per turn of the sky. Nothing in the rules changes: it only moves and colours the light.

- The game starts mid-morning. The sun is up for 70% of each day: it rises low in the east, stands 45 degrees up at midday and sets in the west, turning orange as it gets low, with an orange glow on the horizon at dusk and dawn.
- The other 30% (30 seconds) is night: moonlight from high up, blue and at half the day's strength, under a dark blue sky. The night is kept bright enough to play.
- At the handover between sun and moon both are at 30% strength with the same colour, so the light never jumps or goes black (tested over 1,000 steps of a day).
- The storm and the drought still set the weather's light (`EventEffects.sun_energy`, `sun_color`, `sky_top`, `sky_horizon`); DayNight dims and tints it for the time of day every frame.
- The top bar shows the time of day: "Day 3, evening". It stops while the game is paused.
- Tests set `DayNight.enabled = false`, which keeps the midday light, so their brightness checks and screenshots do not depend on how long they ran. `test_day_night.gd` switches it on.

## Roads, ponds and trees near the town

Added 2026-11-21, after the team compared the game with Settlement Survival and found the town empty. Built from code and the existing textures and oak model; no new assets.

- **Roads** (`scripts/roads.gd`, node `Roads`): a dirt road along every side of every build square, in the 4 m lanes between them, and one road east to the beach where ships land. They are painted into the ground: the script draws a black-and-white picture of the roads (1 pixel per metre, 320 m across), and `terrain.gdshader` mixes a dirt colour (the sand texture, tinted) into the grass where it is white. Painted roads follow the ground exactly and cannot float or flicker. They are only for looks: workers still take the shortest way.
- **Ponds** (`island_terrain.gd`, `PONDS`): three bowls in the fields, 10 to 13 m across, below sea level, so the sea's water plane fills them. Their edges wander in and out so they are not circles. They are well away from the build squares; in a drought they shrink with the river.
- **Trees close to the town** (`island_decorations.gd`): nothing could grow within 204 m of the centre, which made sense for 80 squares but left an empty ring around 20. Groves now start at 92 m, and 40 young oaks grow just outside the town (86 to 125 m). The beach road and the ponds' banks are kept clear.
- Tested by `tests/test_environment.gd`.
