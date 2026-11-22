# test_drought.gd
# "The Last Drop": the day clock, the Water Storage and its construction, the
# drought story and mission, and how they are saved.
# Run with a window:  <Godot> --path . --script res://tests/test_drought.gd
extends SceneTree

const PATH := "user://test_drought_save.json"
const T := ResourceManager.Type
const E := EventManager.Type
const TANK := 7                  # The Water Storage's place in BuildingManager.BUILDINGS.

var fails := 0
var main: Node
var time: TimeManager
var events: EventManager
var builder: BuildingManager
var construction: ConstructionManager
var mission: DroughtMission
var story: StoryBox
var workers: WorkerManager
var r: ResourceManager
var pop: PopulationManager
var map: MapManager


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


# A new colony with every timer and the clock stopped, so only this test moves time.
func new_game() -> void:
	if main != null:
		main.queue_free()
		await process_frame
	paused = false
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("SaveManager").save_path = PATH
	main.get_node("BuildingManager").mouse_enabled = false
	time = main.get_node("TimeManager")
	time.set_process(false)
	events = main.get_node("EventManager")
	builder = main.get_node("BuildingManager")
	construction = main.get_node("ConstructionManager")
	mission = main.get_node("DroughtMission")
	story = main.get_node("UI/StoryBox")
	workers = main.get_node("WorkerManager")
	r = main.get_node("ResourceManager")
	pop = main.get_node("PopulationManager")
	map = main.get_node("MapManager")
	for child in workers.get_children():
		if child is Timer:
			child.stop()


func build(index: int, plot_id: int) -> BuildingPlot:
	var plot := map.get_plot(plot_id)
	builder._chosen_index = index
	builder._place_building(plot)
	return plot


# Everyone is at once where they were walking to.
func arrive() -> void:
	for worker in workers.get_workers():
		worker.model.position = worker.target_position


func key(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.pressed = down
		root.push_input(e)
		await process_frame


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

	# ------------------------------------------------------------ The day clock
	await new_game()
	var bar: Label = main.get_node("UI/ResourcePanel/ResourceBar")
	check("the game starts on day 1", time.get_day() == 1 and bar.text.begins_with("Day 1, "), bar.text.left(20))
	time.advance(0.6)
	check("part of a day does not change the date", time.get_day() == 1)
	time.advance(0.6)
	check("day 2 begins, and the top bar shows it", time.get_day() == 2 and bar.text.begins_with("Day 2, "), bar.text.left(20))
	check("one day is 20 seconds of play", TimeManager.DAY_SECONDS == 20.0)

	# ------------------------------------------------------------ Before the drought
	var farm := build(1, 2)
	workers.assign_worker(farm)
	workers.assign_worker(farm)
	arrive()
	check("the Farm makes 13 food", workers.get_output(farm) == 13, str(workers.get_output(farm)))
	check("the Water Storage is hidden at first", not builder.is_available(TANK) and not builder._building_menu_text().contains("Water Storage"))
	builder.choose_building(TANK)
	check("and cannot be chosen", builder.get_chosen_index() != TANK)
	events._next_index = EventManager.ORDER.find(E.DROUGHT)
	var needs := events.get_ready_needs()
	check("the drought waits for food and the Water Storage's materials", needs.get(T.FOOD) == 50 and needs.get(T.WOOD) == 10 and needs.get(T.STONE) == 5, str(needs))

	# ------------------------------------------------------------ The story
	events.trigger(E.DROUGHT)
	await process_frame
	check("the drought opens the story and the game waits", story.is_open() and paused and story.get_title() == "THE LAST DROP" and story.get_page_count() == 5)
	check("page 1 is the warning, appearing a few letters at a time", story.get_page_text().begins_with("The sun has been burning") and story.is_typing() and (story.get_node("Board").find_child("Text", true, false) as Label).visible_characters < 20)
	story.advance()
	check("Continue first finishes the page", story.get_page_number() == 1 and not story.is_typing())
	story.advance()
	check("then turns to page 2, the problem", story.get_page_number() == 2 and story.get_page_text().begins_with("Your farmers have reported"))
	await key(KEY_SPACE)
	await key(KEY_SPACE)
	check("Space works too: page 3, the discovery", story.get_page_number() == 3 and story.get_page_text().contains("near the riverbank"), str(story.get_page_number()))
	await key(KEY_B)
	check("other keys do nothing while the story is open", not builder.is_placing() and story.get_page_number() == 3)
	story.advance(); story.advance()
	check("page 4 is the objective", story.get_page_text().begins_with("The villagers are looking towards you"))
	story.advance(); story.advance()
	check("page 5 is the mission, with its cost", story.get_page_text().begins_with("MISSION: SAVE THE COLONY") and story.get_page_text().contains("10 Wood, 5 Stone, 2 idle workers and 3 days"), story.get_page_text())
	var board: Control = story.get_node("Board")
	check("the story board is small and at the bottom", board.visible and board.size.y < root.size.y * 0.45 and board.position.y > root.size.y * 0.5, "%s at %s" % [board.size, board.position])
	story.advance()   # Shows the whole page for the picture.
	await process_frame
	await process_frame
	check("the key hint says how to continue", (main.get_node("UI/HintLabel") as Label).text == "Space or Enter: continue")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/drought_story.png")
	story.advance()
	check("after the last page the game carries on", not story.is_open() and not paused)

	# ------------------------------------------------------------ The drought
	var fx: Node = main.get_node("EventEffects")
	check("farms make half food", mission.get_stage() == DroughtMission.Stage.MISSION and workers.get_output(farm) == 6, str(workers.get_output(farm)))
	check("the river starts to fall", fx._water_target < -1.0)
	check("the event list shows the mission", events.describe(events.get_active()[0]).contains("MISSION: build a Water Storage (10 Wood, 5 Stone)"), events.describe(events.get_active()[0]))
	check("the Water Storage is now in the build list", builder.is_available(TANK) and builder._building_menu_text().contains("8 Water Storage"))
	time.advance(0.31)
	check("villagers talk about the drought", main.get_node("Popups").get_texts().has("So thirsty..."), str(main.get_node("Popups").get_texts()))

	# ------------------------------------------------------------ Placing it
	var wood := r.get_amount(T.WOOD)
	var stone := r.get_amount(T.STONE)
	r.spend({ T.WOOD: wood })
	check("the mission has already chosen the Water Storage to build", builder.get_chosen_index() == TANK)
	builder.start_placement()
	builder.choose_building(0)
	r.add(T.FOOD, 50)
	await key(KEY_8)
	check("key 8 chooses the Water Storage while placing", builder.get_chosen_index() == TANK, str(builder.get_chosen_index()))
	var site := map.get_plot(1)
	builder.set_cursor_plot(site)
	check("without the wood the square shows red", site.preview == BuildingPlot.Preview.INVALID and main.get_node("UI/PlacementLabel").text.contains("Not enough resources"))
	builder.confirm_placement()
	check("and nothing is built", site.building == null and builder.is_placing())
	r.add(T.WOOD, wood)
	check("with the wood the square shows green", site.preview == BuildingPlot.Preview.VALID)
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	menu.open_build_menu()
	var list := menu.get_item_texts()
	check("the controller's list has it, with cost and days", list.size() == 12 and list[7] == "Water Storage  -  10 Wood, 5 Stone, 3 days to build", str(list))
	menu.close_menu()
	builder.confirm_placement()
	check("placing it takes 10 wood and 5 stone", site.building != null and r.get_amount(T.WOOD) == wood - 10 and r.get_amount(T.STONE) == stone - 5)
	check("it starts as a building site", site.under_construction and construction.is_site(site) and construction.get_progress(site) == 0.0 and not mission.has_water_storage())
	check("2 idle workers are sent to build it", construction.get_crew(site).size() == 2 and workers.get_idle_count() == 2 and construction.get_crew(site)[0].repair_plot == site)
	check("the text says building, not built", main.get_node("Popups").get_texts().has("Building the Water Storage") and not main.get_node("Popups").get_texts().has("Water Storage built"))
	check("only one Water Storage is allowed", builder.get_placement_problem(TANK) == "The colony already has a Water Storage")
	var wall: MeshInstance3D = site.building._wall
	check("the site shows only a base and scaffolding", not wall.visible and site.building._scaffold.visible)

	# ------------------------------------------------------------ Building it
	time.advance(1.0)
	check("no work is done while the builders are walking", construction.get_progress(site) == 0.0 and construction.get_status(site).contains("on their way"), construction.get_status(site))
	arrive()
	time.advance(1.5)
	check("1.5 days of work is half of it", absf(construction.get_progress(site) - 0.5) < 0.001 and absf(construction.get_days_left(site) - 1.5) < 0.001, str(construction.get_progress(site)))
	check("the wall is half up", wall.visible and absf(wall.scale.y - 0.5) < 0.01, str(wall.scale.y))
	check("the status and the sign show the progress", construction.get_status(site).begins_with("50% built by 2 of 2 builders, 1.5 days left") and (construction._sites[site].sign as Label3D).text == "Building 50%", construction.get_status(site))
	check("the event list shows the progress", events.describe(events.get_active()[0]).contains("Water Storage: 50% built"))
	check("no foundation is found away from the river", not mission.is_on_riverbank(site) and not story.is_open())
	check("a building site cannot collapse in an accident", events._first_building() == farm)
	var builder_one: Worker = construction.get_crew(site)[0]
	builder_one.model.position += Vector3(30, 0, 0)
	time.advance(0.5)
	check("one builder alone works at half speed", absf(construction.get_days_left(site) - 1.25) < 0.001, str(construction.get_days_left(site)))
	arrive()
	view_site(site)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/drought_building.png")

	# ------------------------------------------------------------ Finishing it
	var happiness := pop.get_happiness()
	time.advance(1.3)
	check("after 3 days of work it is finished", not site.under_construction and not construction.is_site(site) and mission.has_water_storage())
	check("the builders go back to being idle", workers.get_idle_count() == 4 and builder_one.repair_plot == null)
	check("the drought ends and the closing story opens", not events.is_active(E.DROUGHT) and story.is_open() and paused and story.get_page_text().begins_with("The villagers gather around"))
	check("it ends on the completion page", story.get_page_count() == 3 and str(story._pages[2]).begins_with("EVENT COMPLETED - THE LAST DROP"), str(story._pages[2]))
	story.advance(); story.advance(); story.advance(); story.advance(); story.advance()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/drought_completed.png")
	story.skip()
	check("the colony is a little happier", pop.get_happiness() == happiness + 5 and mission.get_completed_count() == 1)
	check("farms get a 25% bonus while they recover", workers.get_output(farm) == 16, str(workers.get_output(farm)))
	check("the river rises again", fx._water_target == 0.0)
	check("the text says built", main.get_node("Popups").get_texts().has("Water Storage built"))
	await create_timer(2.0).timeout
	check("the tank fills with water", site.building.get_water() > 0.1 and site.building._water.visible, str(site.building.get_water()))
	time.advance(2.0)
	check("after 2 days food is back to normal", workers.get_output(farm) == 13)

	# ------------------------------------------------------------ The next drought
	events.trigger(E.DROUGHT)
	check("the next drought has a one-page story", story.is_open() and story.get_page_count() == 1 and story.get_page_text().contains("This time the colony is ready"))
	story.skip()
	check("with the Water Storage, farms make 80%", mission.get_stage() == DroughtMission.Stage.PROTECTED and workers.get_output(farm) == 10, str(workers.get_output(farm)))
	time.advance(2.9)
	check("it is still dry after 2.9 days", events.is_active(E.DROUGHT))
	time.advance(0.2)
	check("and the rain returns after 3", not events.is_active(E.DROUGHT) and story.get_page_text().begins_with("Rain at last"))
	story.skip()

	# ------------------------------------------------------------ Saving a finished tank
	var saver: SaveManager = main.get_node("SaveManager")
	var day := time.get_day()
	check("the colony with its Water Storage can be saved", saver.save_game())
	await new_game()
	saver = main.get_node("SaveManager")
	saver.apply(saver.read_save())
	await process_frame
	site = map.get_plot(1)
	check("loading brings back a finished, full Water Storage", mission.has_water_storage() and not construction.is_site(site) and site.building.get_water() > 0.8 and not site.building._scaffold.visible)
	check("and the day, the unlocked building and the mission count", time.get_day() == day and builder.is_available(TANK) and mission.get_completed_count() == 1, "day %d" % time.get_day())
	check("nobody is left building it", workers.get_idle_count() == 4)

	# ------------------------------------------------------------ Failing the mission
	await new_game()
	events.trigger(E.DROUGHT)
	story.skip()
	time.advance(5.9)
	check("with nothing built, the drought lasts 5.9 days", events.is_active(E.DROUGHT) and pop.get_happiness() == 60)
	time.advance(0.2)
	check("after 6 days the rain returns by itself", not events.is_active(E.DROUGHT) and mission.get_stage() == DroughtMission.Stage.NONE)
	check("but the colony suffered: happiness -10 and a different ending", pop.get_happiness() == 50 and story.get_page_text().begins_with("At last, dark clouds gather"), story.get_page_text().left(40))
	story.skip()
	check("the Water Storage can still be built afterwards", builder.is_available(TANK) and mission.get_completed_count() == 0)

	# ------------------------------------------------------------ The riverbank twist
	await new_game()
	events.trigger(E.DROUGHT)
	story.skip()
	var bank := map.get_plot(19)
	check("plot 19 is the one by the river", map.get_plots().filter(func(p: BuildingPlot) -> bool: return mission.is_on_riverbank(p)).map(func(p: BuildingPlot) -> int: return p.plot_id) == [19])
	build(TANK, 19)
	arrive()
	time.advance(0.8)
	check("nothing is found in the first part of the work", not story.is_open() and absf(construction.get_days_left(bank) - 2.2) < 0.001)
	time.advance(0.2)
	check("a third of the way in, the old foundation is found", story.is_open() and story.get_page_text().contains("foundation is still intact"), story.get_page_text().left(50))
	check("which saves one day of work", absf(construction.get_days_left(bank) - 1.0) < 0.001, str(construction.get_days_left(bank)))
	story.skip()
	time.advance(1.01)
	check("so it is finished after 2 days, and the mission is won", not bank.under_construction and mission.get_completed_count() == 1 and not events.is_active(E.DROUGHT))
	story.skip()

	# ------------------------------------------------------------ No idle workers
	await new_game()
	var jobs := [build(1, 2), build(2, 3), build(3, 4)]
	for plot: BuildingPlot in jobs:
		workers.assign_worker(plot)
		workers.assign_worker(plot)
	arrive()
	events.trigger(E.DROUGHT)
	story.skip()
	site = build(TANK, 1)
	check("with everyone at work, the site has no builders", construction.get_crew(site).is_empty() and construction.get_status(site).contains("Waiting for idle workers") and (construction._sites[site].sign as Label3D).text == "Needs 2 idle workers", construction.get_status(site))
	time.advance(1.0)
	check("and no work is done", construction.get_progress(site) == 0.0)
	workers.remove_worker(jobs[1])
	time.advance(0.01)
	check("a worker taken off a job becomes a builder", construction.get_crew(site).size() == 1)
	arrive()
	time.advance(1.0)
	check("and builds at half speed", absf(construction.get_progress(site) - 0.5 / 3.0) < 0.01, str(construction.get_progress(site)))

	# ------------------------------------------------------------ Saving a building site
	saver = main.get_node("SaveManager")
	check("the game cannot be saved during the drought", not saver.save_game())
	# The lone builder steps away, so the work stops and the drought runs out.
	construction.get_crew(site)[0].model.position += Vector3(30, 0, 0)
	time.advance(5.0)
	story.skip()
	check("the site is still there after the drought failed", construction.is_site(site) and not events.is_active(E.DROUGHT))
	var progress := construction.get_progress(site)
	check("now it can be saved", saver.save_game())
	await new_game()
	saver = main.get_node("SaveManager")
	saver.apply(saver.read_save())
	await process_frame
	site = map.get_plot(1)
	check("loading brings back the half-built site", construction.is_site(site) and site.under_construction and absf(construction.get_progress(site) - progress) < 0.001 and not mission.has_water_storage(), "%.3f vs %.3f" % [construction.get_progress(site), progress])
	check("with a builder from the idle workers", construction.get_crew(site).size() == 1 and workers.get_idle_count() == 0)
	arrive()
	time.advance(3.0)
	time.advance(3.0)
	check("finished outside a drought, it just stands ready: no story", not site.under_construction and mission.has_water_storage() and not story.is_open() and mission.get_completed_count() == 0)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	paused = false
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)


# Points the camera at a plot from close by, for the screenshot.
func view_site(plot: BuildingPlot) -> void:
	var camera: Camera3D = main.get_node("Camera3D")
	camera.set_process(false)
	camera.global_position = plot.position + Vector3(-26, 24, 30)
	camera.look_at(plot.position + Vector3(0, 3, 0))
