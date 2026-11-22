# test_research.gd
# Spec test: T13. The three research upgrades: their order, cost and time, and
# what each one changes (food, wood and stone production, the storage limit).
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_research.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree

const T := ResourceManager.Type

var fails := 0


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


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


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	StoryBox.enabled = false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("EventManager/EventTimer").stop()
	var r: ResourceManager = main.get_node("ResourceManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var research: ResearchManager = main.get_node("ResearchManager")
	var map: MapManager = main.get_node("MapManager")
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	var popups: PopupManager = main.get_node("Popups")
	menu.close_menu()
	get_root().get_tree().paused = false

	# ------------------------------------------------------------ Before a Lab
	check("there are three upgrades besides the vaccine", ResearchManager.UPGRADES == ["farming", "tools", "storage"] and ResearchManager.PROJECTS.size() == 4)
	check("without a Lab nothing can be researched", not research.start("farming") and research.get_problem("farming") == "Research needs a working Research Lab", research.get_problem("farming"))

	r.add(T.WOOD, 50)
	r.add(T.STONE, 100)
	var farm := build(main, "Farm", 2)
	var camp := build(main, "Lumber Camp", 5)
	var quarry := build(main, "Quarry", 6)
	var lab := build(main, "Research Lab", 3)
	for plot: BuildingPlot in [farm, camp, quarry]:
		workers.assign_worker(plot)
		workers.assign_worker(plot)
	for worker in workers.get_workers():
		worker.model.position = worker.target_position
	check("before research: 13 food, 7 wood, 8 stone a cycle", workers.get_output(farm) == 13 and workers.get_output(camp) == 7 and workers.get_output(quarry) == 8, "%d %d %d" % [workers.get_output(farm), workers.get_output(camp), workers.get_output(quarry)])
	check("before research the storage limit is 200", r.get_capacity() == 200)

	# ------------------------------------------------------------ The order
	check("Efficient Tools needs Improved Farming first", not research.start("tools") and research.get_problem("tools") == "Research Improved Farming first", research.get_problem("tools"))
	check("Storage Engineering needs Efficient Tools first", not research.start("storage") and research.get_problem("storage") == "Research Efficient Tools first", research.get_problem("storage"))
	check("statuses: ready, locked, locked", research.get_status("farming") == "ready" and research.get_status("tools") == "locked" and research.get_status("storage") == "locked")
	r.spend({ T.GOLD: r.get_amount(T.GOLD) })
	check("with no gold it is refused, and says what it needs", not research.start("farming") and research.get_problem("farming") == "Not enough resources (needs 10 Gold)", research.get_problem("farming"))

	# ------------------------------------------------------------ The Lab's menu
	r.add(T.GOLD, 60)
	map.select_plot(lab)
	await process_frame
	var panel: String = main.get_node("UI/SelectionLabel").text
	check("the panel lists the upgrades", panel.contains("Upgrades (Space for the menu): Improved Farming ready, Efficient Tools locked, Storage Engineering locked"), panel.replace("\n", " / "))
	menu.open_building_menu()
	var texts := menu.get_item_texts()
	var first := texts.find("Research Improved Farming: food production +20% (10 Gold, 30 s)")
	check("the Lab's menu offers all three with effect, cost and time", first > 0 and texts.has("Research Efficient Tools: wood and stone production +20% (15 Gold, 40 s)") and texts.has("Research Storage Engineering: storage limit +25% (20 Gold, 40 s)"), str(texts))
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://research_menu.png")
	menu.move_highlight(first - menu.get_highlight())
	menu.confirm()
	check("choosing it in the menu starts it for 10 gold", research.get_current() == "farming" and r.get_amount(T.GOLD) == 50, "%s %d" % [research.get_current(), r.get_amount(T.GOLD)])
	menu.close_menu()
	get_root().get_tree().paused = false

	# ------------------------------------------------------------ Improved Farming
	check("the Lab does one project at a time", not research.start("vaccine") and research.get_problem("vaccine") == "The Lab is busy with Improved Farming", research.get_problem("vaccine"))
	research._process(15.0)
	check("halfway after 15 s, and nothing has changed yet", research.get_status("farming") == "50%" and workers.get_output(farm) == 13, research.get_status("farming"))
	research._process(15.0)
	check("finished after 30 s", research.is_finished("farming") and research.get_current() == "")
	check("the Farm now makes 16 food (13.5 x 1.2, fractions dropped)", workers.get_output(farm) == 16, str(workers.get_output(farm)))
	check("wood and stone are unchanged", workers.get_output(camp) == 7 and workers.get_output(quarry) == 8)
	check("a popup says so over the Lab", popups.get_texts().has("Improved Farming researched"), str(popups.get_texts()))
	var food := r.get_amount(T.FOOD)
	r.spend({ T.FOOD: 100 })
	food = r.get_amount(T.FOOD)
	workers.produce()
	check("a production cycle really adds 16 food", r.get_amount(T.FOOD) == food + 16, str(r.get_amount(T.FOOD) - food))
	check("it cannot be researched twice", not research.start("farming") and research.get_problem("farming") == "Improved Farming is already researched")

	# ------------------------------------------------------------ Efficient Tools
	check("Efficient Tools starts for 15 gold", research.start("tools") and r.get_amount(T.GOLD) == 35)
	research._process(40.0)
	check("after 40 s: 8 wood and 9 stone a cycle", research.is_finished("tools") and workers.get_output(camp) == 8 and workers.get_output(quarry) == 9, "%d %d" % [workers.get_output(camp), workers.get_output(quarry)])
	check("food stays at 16", workers.get_output(farm) == 16)

	# ------------------------------------------------------------ Storage Engineering
	check("Storage Engineering starts for 20 gold", research.start("storage") and r.get_amount(T.GOLD) == 15)
	lab.is_damaged = true
	research._process(40.0)
	check("research stands still while the Lab is collapsed", research.get_current() == "storage" and r.get_capacity() == 200)
	lab.is_damaged = false
	research._process(40.0)
	check("after 40 s the storage limit is 250 (200 x 1.25)", research.is_finished("storage") and r.get_capacity() == 250, str(r.get_capacity()))
	build(main, "Warehouse", 7)
	check("with a Warehouse it is 500 (400 x 1.25)", r.get_capacity() == 500, str(r.get_capacity()))
	check("the vaccine is still separate and unresearched", not research.is_finished("vaccine") and research.get_problem("vaccine") == "")
	# process_frame is sent before the nodes update, so wait for two.
	await process_frame
	await process_frame
	panel = main.get_node("UI/SelectionLabel").text
	check("the panel shows all three done", panel.contains("Improved Farming done, Efficient Tools done, Storage Engineering done"), panel.replace("\n", " / "))

	# ------------------------------------------------------------ Save and load
	var saved := research.get_save_data()
	research.load_save_data({})
	check("an empty save has no upgrades: 13 food, 7 wood, limit 400", workers.get_output(farm) == 13 and workers.get_output(camp) == 7 and r.get_capacity() == 400, "%d %d %d" % [workers.get_output(farm), workers.get_output(camp), r.get_capacity()])
	research.load_save_data(saved)
	check("loading brings all three back: 16 food, 8 wood, limit 500", workers.get_output(farm) == 16 and workers.get_output(camp) == 8 and r.get_capacity() == 500, "%d %d %d" % [workers.get_output(farm), workers.get_output(camp), r.get_capacity()])

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
