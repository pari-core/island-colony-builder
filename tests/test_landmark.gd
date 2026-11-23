# test_landmark.gd
# Spec test: T14. The three landmarks (Lighthouse, Harbour, Town Hall) and the
# second way to win: their place in the build list, their costs, building them
# over days, the goal line, and winning only when all three are finished.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_landmark.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree

const T := ResourceManager.Type
const S := GameStateManager.State
const LIGHTHOUSE := 8            # The Lighthouse's place in BuildingManager.BUILDINGS.
const NAMES := ["Lighthouse", "Harbour", "Town Hall"]

var fails := 0
var main: Node
var workers: WorkerManager


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


# Puts every worker where they are walking to.
func arrive() -> void:
	for worker in workers.get_workers():
		worker.model.position = worker.target_position


func key(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
		await process_frame


func view_site(plot: BuildingPlot) -> void:
	var camera: Camera3D = main.get_node("Camera3D")
	camera.set_process(false)
	camera.global_position = plot.position + Vector3(-34, 30, 44)
	camera.look_at(plot.position + Vector3(0, 11, 0))


func shot(file: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/%s.png" % file)


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	StoryBox.enabled = false
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("EventManager/EventTimer").stop()
	var r: ResourceManager = main.get_node("ResourceManager")
	workers = main.get_node("WorkerManager")
	var builder: BuildingManager = main.get_node("BuildingManager")
	var construction: ConstructionManager = main.get_node("ConstructionManager")
	var time: TimeManager = main.get_node("TimeManager")
	var game: GameStateManager = main.get_node("GameStateManager")
	var map: MapManager = main.get_node("MapManager")
	var goal: Label = main.get_node("UI/GoalLabel")
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	var label: Label = main.get_node("UI/PlacementLabel")
	menu.close_menu()
	main.get_tree().paused = false

	# ------------------------------------------------------------ In the list
	check("there are three landmarks, in this order", GameStateManager.get_landmark_names() == NAMES, str(GameStateManager.get_landmark_names()))
	var costs := []
	var fits := true
	for info in GameStateManager.get_landmarks():
		costs.append("%s: %s, %d workers, %d days" % [info.name, r.describe_cost(info.cost), info.builders, int(info.build_days)])
		for type in info.cost:
			fits = fits and info.cost[type] <= ResourceManager.STARTING_CAPACITY
	check("each has its own cost, crew and days", costs == [
		"Lighthouse: 150 Wood, 120 Stone, 40 Gold, 3 workers, 5 days",
		"Harbour: 180 Wood, 40 Stone, 20 Gold, 3 workers, 3 days",
		"Town Hall: 150 Wood, 150 Stone, 50 Gold, 3 workers, 4 days",
	], str(costs))
	check("every cost fits inside the starting storage limit of 200", fits)
	check("the Lighthouse is building 9, after the Water Storage", BuildingManager.BUILDINGS[LIGHTHOUSE].name == "Lighthouse" and BuildingManager.BUILDINGS[LIGHTHOUSE - 1].name == "Water Storage")
	await process_frame
	await process_frame
	check("the goal panel offers them as a second way to win", goal.text.contains("Or: build all 3 landmarks (0 done): Lighthouse, Harbour, Town Hall"), goal.text.replace("\n", " / "))

	# ------------------------------------------------------------ Choosing them
	builder.start_placement()
	await key(KEY_9)
	check("key 9 chooses the Lighthouse while placing", builder.get_chosen_building().name == "Lighthouse", builder.get_chosen_building().name)
	check("the build text lists the landmarks on their own line", label.text.contains("\nLandmarks: [9 Lighthouse]   0 Harbour   Town Hall"), label.text.replace("\n", " / "))
	await key(KEY_0)
	check("key 0 chooses the Harbour", builder.get_chosen_building().name == "Harbour", builder.get_chosen_building().name)
	var first := map.get_plot(1)
	builder.set_cursor_plot(first)
	menu.open_build_menu()
	var list := menu.get_item_texts()
	check("the list opens on the chosen building, though the hidden Water Storage shifts the lines", list[menu.get_highlight()].begins_with("Harbour") and menu.get_highlight() == 8, "%d %s" % [menu.get_highlight(), str(list)])
	menu.move_highlight(1)
	check("moving down one line chooses the Town Hall for the preview", builder.get_chosen_building().name == "Town Hall", builder.get_chosen_building().name)
	await create_timer(0.3).timeout
	await shot("landmark_list")
	menu.close_menu()
	builder.choose_building(LIGHTHOUSE)
	check("at the start the colony cannot afford the Lighthouse", not r.can_afford(BuildingManager.BUILDINGS[LIGHTHOUSE].cost) and first.preview == BuildingPlot.Preview.INVALID)
	builder.confirm_placement()
	check("so nothing is built", first.building == null)

	# ------------------------------------------------------------ Building the Lighthouse
	r.add(T.WOOD, 50)
	r.add(T.STONE, 120)
	r.add(T.GOLD, 20)
	builder.confirm_placement()
	check("placing it takes 150 wood, 120 stone and 40 gold", first.building != null and r.get_amount(T.WOOD) == 50 and r.get_amount(T.STONE) == 80 and r.get_amount(T.GOLD) == 0, "%d %d %d" % [r.get_amount(T.WOOD), r.get_amount(T.STONE), r.get_amount(T.GOLD)])
	check("it starts as a building site with 3 builders", first.under_construction and construction.get_crew(first).size() == 3)
	check("only one Lighthouse is allowed", builder.get_placement_problem(LIGHTHOUSE) == "The colony already has a Lighthouse")
	arrive()
	time.advance(2.5)
	var tower: Array = first.building._sections
	check("after 2.5 days it is half built: lower bands up, no lamp", absf(construction.get_progress(first) - 0.5) < 0.001 and tower[0].visible and not tower[4].visible and not first.building.is_lit())
	await process_frame
	await process_frame
	check("the goal panel shows its progress", goal.text.contains("(0 done): Lighthouse 50%, Harbour,"), goal.text.replace("\n", " / "))
	time.advance(2.6)
	check("after 5 days it is finished and lit", not first.under_construction and first.building.is_lit() and game.get_landmarks_built() == 1)
	check("one landmark does not win the game", game.get_state() == S.PLAYING and not main.get_tree().paused)
	await process_frame
	await process_frame
	check("the goal panel counts it", goal.text.contains("(1 done): Lighthouse done, Harbour,"), goal.text.replace("\n", " / "))

	# ------------------------------------------------------------ The other two
	var plots := { "Lighthouse": first }
	var plot_ids := { "Harbour": 3, "Town Hall": 5 }
	for landmark_name: String in ["Harbour", "Town Hall"]:
		var index := LIGHTHOUSE + NAMES.find(landmark_name)
		var info: Dictionary = BuildingManager.BUILDINGS[index]
		for type in info.cost:
			r.add(type, info.cost[type])
		var site := map.get_plot(plot_ids[landmark_name])
		builder.start_placement()
		builder.choose_building(index)
		builder.set_cursor_plot(site)
		builder.confirm_placement()
		plots[landmark_name] = site
		var model: LandmarkModel = site.building
		check("%s: placed as a site with %d builders, showing only its first parts" % [landmark_name, info.builders], site.under_construction and construction.get_crew(site).size() == info.builders and model.get_visible_parts() < model.get_part_count() and model.is_scaffolded(), "%d of %d" % [model.get_visible_parts(), model.get_part_count()])
		arrive()
		time.advance(info.build_days * 0.5)
		var half := model.get_visible_parts()
		check("%s: half built shows more, but not all" % landmark_name, half > 1 and half < model.get_part_count(), "%d of %d" % [half, model.get_part_count()])
		if landmark_name == "Town Hall":
			check("two done and the third half built: still playing", game.get_landmarks_built() == 2 and game.get_state() == S.PLAYING)
			view_site(site)
			await shot("landmark_town_hall_building")
		time.advance(info.build_days * 0.5 + 0.1)
		check("%s: finished, every part shown, scaffolding gone" % landmark_name, not site.under_construction and model.get_visible_parts() == model.get_part_count() and not model.is_scaffolded())

	# ------------------------------------------------------------ All three win
	check("all three stand, but no event has been faced: not won yet", game.get_landmarks_built() == 3 and game.get_state() == S.PLAYING)
	await process_frame
	await process_frame
	check("the goal panel says what is still missing", goal.text.contains("(3 done)") and goal.text.contains("Both need all 6 events faced first (0 so far)"), goal.text.replace("\n", " / "))
	var events: EventManager = main.get_node("EventManager")
	for type: EventManager.Type in EventManager.ORDER:
		events._faced[type] = true
	main.get_node("PopulationManager").upkeep()
	check("once all five events are faced, the next upkeep cycle wins the game", game.get_state() == S.WON and main.get_tree().paused and game.get_reason() == "The colony raised all 3 landmarks: Lighthouse, Harbour, Town Hall.", game.get_reason())
	var end_text := game.get_end_text()
	check("the end screen shows the win", game.has_node("EndScreen/Confetti") and end_text.contains("YOU WIN") and end_text.contains("3 landmarks"), end_text.replace("\n", " / "))
	check("the builders are free again", workers.get_idle_count() == 6)
	game.keep_playing()
	check("N carries on in free play", game.get_state() == S.FREE_PLAY and not main.get_tree().paused)
	for landmark_name: String in NAMES:
		view_site(plots[landmark_name])
		await shot("landmark_%s" % landmark_name.to_lower().replace(" ", "_"))

	# ------------------------------------------------------------ Loading does not win again
	var saved_buildings := builder.get_save_data()
	var saved_sites := construction.get_save_data()
	game._state = S.PLAYING
	builder.load_save_data(saved_buildings)
	construction.load_save_data(saved_sites)
	check("all three come back finished from a save", game.get_landmarks_built() == 3 and map.get_plot(1).building.is_lit())
	check("but loading them does not win the game a second time", game.get_state() == S.PLAYING)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
