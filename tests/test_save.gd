# test_save.gd
# Saving the colony to a file and loading it back.
# Run with a window:  <Godot> --path . --script res://tests/test_save.gd
extends SceneTree

const PATH := "user://test_save.json"   # Not the player's own save file.
const T := ResourceManager.Type

var fails := 0


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


# A new colony that saves to the test file, with its timers stopped.
func new_game() -> Node:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("SaveManager").save_path = PATH
	stop_timers(main)
	return main


func stop_timers(main: Node) -> void:
	main.get_node("EventManager/EventTimer").stop()
	main.get_node("PopulationManager/UpkeepTimer").stop()
	for child in main.get_node("WorkerManager").get_children():
		if child is Timer:
			child.stop()


func building_index(building_name: String) -> int:
	for i in BuildingManager.BUILDINGS.size():
		if BuildingManager.BUILDINGS[i].name == building_name:
			return i
	return -1


func build(main: Node, building_name: String, plot_id: int) -> BuildingPlot:
	var builder: BuildingManager = main.get_node("BuildingManager")
	var plot: BuildingPlot = main.get_node("MapManager").get_plot(plot_id)
	builder.choose_building(building_index(building_name))
	builder._place_building(plot)
	return plot


# Everything about a colony that a save must bring back, as text to compare.
func snapshot(main: Node) -> Dictionary:
	var r: ResourceManager = main.get_node("ResourceManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var crops: CropManager = main.get_node("CropManager")
	var pop: PopulationManager = main.get_node("PopulationManager")
	var research: ResearchManager = main.get_node("ResearchManager")
	var game: GameStateManager = main.get_node("GameStateManager")
	var buildings := []
	var growth := []
	for plot: BuildingPlot in main.get_node("MapManager").get_plots():
		if plot.building != null:
			buildings.append("%d %s L%d" % [plot.plot_id, plot.building_info.name, plot.level])
			if crops.has_field(plot):
				growth.append("%d %.2f" % [plot.plot_id, crops.get_growth(plot)])
	var jobs := []
	for worker in workers.get_workers():
		jobs.append("%s:%d" % [worker.worker_name, -1 if worker.job_plot == null else worker.job_plot.plot_id])
	return {
		"resources": str([r.get_amount(T.FOOD), r.get_amount(T.WOOD), r.get_amount(T.STONE), r.get_amount(T.GOLD)]),
		"capacity": str(r.get_capacity()),
		"buildings": str(buildings),
		"jobs": str(jobs),
		"civilians": str(main.get_node("CivilianManager").get_count()),
		"happiness": str(pop.get_happiness()),
		"housing": str(pop.get_housing_capacity()),
		"vaccine": str(research.is_finished("vaccine")),
		"crops": str(growth),
		"next event": str(main.get_node("EventManager").get_next_type()),
		"starving": str(game.get_starvation_seconds_left()),
		"score": str(game.get_score()),
	}


func differences(a: Dictionary, b: Dictionary) -> String:
	var text := ""
	for key in a:
		if a[key] != b[key]:
			text += "%s: %s -> %s. " % [key, a[key], b[key]]
	return text


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

	# ------------------------------------------------------------ Build a colony
	var main: Node = await new_game()
	var saver: SaveManager = main.get_node("SaveManager")
	var r: ResourceManager = main.get_node("ResourceManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var events: EventManager = main.get_node("EventManager")
	var pop: PopulationManager = main.get_node("PopulationManager")
	var game: GameStateManager = main.get_node("GameStateManager")
	var builder: BuildingManager = main.get_node("BuildingManager")
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	check("no save at the start", not saver.has_save() and saver.get_save_time() == "" and saver.read_save().is_empty())
	menu.open_pause_menu()
	var texts := menu.get_item_texts()
	check("pause menu offers Save, and Load only once a save exists", texts.has("Save the game") and not str(texts).contains("Load the saved game"), str(texts))
	menu.close_menu()

	build(main, "House", 1)
	var farm := build(main, "Farm", 2)
	var warehouse := build(main, "Warehouse", 3)
	build(main, "Lumber Camp", 5)
	for type in T.values():
		r.add(type, 400)
	check("the Warehouse is upgraded to level 2", builder.upgrade(warehouse) and warehouse.level == 2)
	workers.assign_worker(farm)
	workers.assign_worker(farm)
	workers.assign_worker(main.get_node("MapManager").get_plot(5))
	for worker in workers.get_workers():
		worker.model.position = worker.target_position
	for i in 3:
		workers.produce()
	var civilians: CivilianManager = main.get_node("CivilianManager")
	civilians.add_civilian()
	civilians.add_civilian()
	check("a civilian is trained into a 7th worker", civilians.train_worker(main.get_node("MapManager").get_plot(1)) and workers.get_workers().size() == 7)
	main.get_node("ResearchManager")._finished["vaccine"] = true
	events._next_index = 3
	pop._happiness = 73
	game._hungry_cycles = 2
	for type in T.values():
		r.spend({ type: r.get_amount(type) })
	r.add(T.FOOD, 211)
	r.add(T.WOOD, 97)
	r.add(T.STONE, 43)
	r.add(T.GOLD, 18)
	await create_timer(0.8).timeout   # Lets the upgrade animation finish.

	# ------------------------------------------------------------ Saving
	events.trigger(EventManager.Type.DISCOVERY)
	check("cannot save during an event", not saver.save_game() and saver.get_save_problem().contains("event") and not saver.has_save(), saver.get_save_problem())
	events._end(events.get_active()[0])
	events.get_node("EventTimer").stop()
	check("can save once the event is over", saver.get_save_problem() == "" and saver.save_game())
	check("the save file exists and can be read", FileAccess.file_exists(PATH) and saver.has_save() and int(saver.read_save().version) == SaveManager.VERSION)
	check("the save has a time", saver.get_save_time().length() == 16, saver.get_save_time())
	var text := FileAccess.get_file_as_string(PATH)
	check("the file is readable text with every part", text.contains("\"buildings\"") and text.contains("\"Warehouse\"") and text.contains("\"workers\"") and text.contains("\"crops\""))
	check("load_game is only for the running game", not saver.load_game())
	menu.open_pause_menu()
	check("pause menu now offers Load", str(menu.get_item_texts()).contains("Load the saved game (20"), str(menu.get_item_texts()))
	menu.close_menu()
	var before := snapshot(main)
	check("the colony to save has 4 buildings, 7 workers and half-grown crops", before.buildings.contains("3 Warehouse L2") and before.jobs.contains("Gita") and before.crops == str(["2 0.50"]), str(before))

	# ------------------------------------------------------------ Loading
	main.queue_free()
	await process_frame
	main = await new_game()
	saver = main.get_node("SaveManager")
	var fresh := snapshot(main)
	check("a new game is different from the saved one", differences(before, fresh) != "")
	saver.apply(saver.read_save())
	var upkeep: Timer = main.get_node("PopulationManager/UpkeepTimer")
	check("the countdown to the next meal carries on, then goes back to 10 s", not upkeep.is_stopped() and upkeep.time_left <= 10.0 and upkeep.wait_time == PopulationManager.UPKEEP_SECONDS, "%.1f" % upkeep.time_left)
	stop_timers(main)
	await process_frame
	await process_frame
	var after := snapshot(main)
	check("loading brings back the whole colony", differences(before, after) == "", differences(before, after))
	workers = main.get_node("WorkerManager")
	farm = main.get_node("MapManager").get_plot(2)
	warehouse = main.get_node("MapManager").get_plot(3)
	check("workers are standing at their jobs and working", workers.get_workers_at(farm).size() == 2 and workers.get_output(farm) > 0, str(workers.get_output(farm)))
	check("the upgraded Warehouse is bigger and shows its level", absf(warehouse.building.scale.x - 1.1) < 0.001 and (warehouse.building.get_node("LevelSign") as Label3D).text == "Lv 2")
	check("the Farm has its field again", main.get_node("CropManager").get_node_or_null("Field02") != null)
	check("walking routes go round all 4 buildings", main.get_node("PathGrid").get_footprints().size() == 4)
	check("no 'built' text floats up after loading", main.get_node("Popups").get_texts().is_empty(), str(main.get_node("Popups").get_texts()))
	check("loading costs nothing", after.resources == str([211, 97, 43, 18]), after.resources)
	main.get_node("PopulationManager").upkeep()
	check("the game carries on after the next meal", main.get_node("GameStateManager").get_state() == GameStateManager.State.PLAYING)

	# ------------------------------------------------------------ Bad files
	main.queue_free()
	await process_frame
	main = await new_game()
	saver = main.get_node("SaveManager")
	var good := FileAccess.get_file_as_string(PATH)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("this is not a save file {{{")
	file.close()
	check("a damaged file is refused", not saver.has_save() and saver.read_save().is_empty())
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(good.replace("\"version\": %d" % SaveManager.VERSION, "\"version\": 99"))
	file.close()
	check("a file from another version is refused", not saver.has_save())
	saver.apply({ "population": { "happiness": 50, "upkeep_left": 4.0 }, "workers": { "jobs": [99, 2, -1] }, "buildings": { "buildings": [{ "plot": 9999, "name": "House", "level": 1 }, { "plot": 4, "name": "Castle", "level": 1 }] } })
	var meal: Timer = main.get_node("PopulationManager/UpkeepTimer")
	check("a meal that was 4 s away is still 4 s away, and the one after is 10 s", meal.time_left > 3.5 and meal.time_left <= 4.0 and meal.wait_time == 10.0, "%.2f" % meal.time_left)
	stop_timers(main)
	await process_frame
	workers = main.get_node("WorkerManager")
	check("a file with impossible entries does no harm", workers.get_workers().size() == 3 and workers.get_idle_count() == 3 and snapshot(main).buildings == "[]", snapshot(main).buildings)
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(good)
	file.close()

	# ------------------------------------------------------------ The real game
	main.queue_free()
	await process_frame
	paused = false
	change_scene_to_file("res://scenes/Main.tscn")
	for i in 5:
		await process_frame
	var first := current_scene
	first.get_node("SaveManager").save_path = PATH
	menu = first.get_node("ControllerMenu")
	check("the main menu offers to continue the saved game, first", menu.get_mode() == ControllerMenu.Mode.START and menu.get_item_texts().size() == 7 and menu.get_item_texts()[0].begins_with("Continue (20"), str(menu.get_item_texts()))
	menu.confirm()   # Continue is the first item, already highlighted.
	for i in 10:
		await process_frame
	var second := current_scene
	check("Continue loads the save into a new scene, unpaused", second != null and second != first and not paused and not second.get_node("ControllerMenu").is_open())
	stop_timers(second)
	second.get_node("SaveManager").save_path = PATH
	check("the continued game is the saved colony", differences(before, snapshot(second)) == "", differences(before, snapshot(second)))

	# Change the colony, save from the pause menu, change it again, then load.
	build(second, "House", 7)
	menu = second.get_node("ControllerMenu")
	menu.open_pause_menu()
	menu.move_highlight(menu.get_item_texts().find("Save the game"))
	menu.confirm()
	check("Save in the pause menu says Done", menu.get_message() == "Done" and menu.is_open(), menu.get_message())
	menu.close_menu()
	var saved := snapshot(second)
	build(second, "Farm", 8)
	second.get_node("PopulationManager")._happiness = 5
	menu.open_pause_menu()
	texts = menu.get_item_texts()
	var load_item := -1
	for i in texts.size():
		if texts[i].begins_with("Load the saved game"):
			load_item = i
	menu.move_highlight(load_item)
	menu.confirm()
	for i in 10:
		await process_frame
	var third := current_scene
	check("Load in the pause menu starts a new scene, unpaused", third != null and third != second and not paused and not third.get_node("ControllerMenu").is_open())
	stop_timers(third)
	check("it is the colony as it was saved, with 5 buildings", differences(saved, snapshot(third)) == "" and snapshot(third).buildings.contains("7 House") and not snapshot(third).buildings.contains("8 Farm"), differences(saved, snapshot(third)))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	paused = false
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
