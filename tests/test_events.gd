# test_events.gd
# Spec tests: T12, T13. All seven events, their visuals, collapse and repair, outbreaks and vaccine research.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_events.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree
const OUT := "user://"
var fails := 0
var cam: Camera3D
func check(t: String, ok: bool, d := "") -> void:
	print(("PASS " if ok else "FAIL ") + t + "  " + d)
	if not ok: fails += 1
func _initialize() -> void:
	run()
func key(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new(); e.physical_keycode = code; e.keycode = code; e.pressed = down
		Input.parse_input_event(e)
		await process_frame
		await process_frame
func place(mgr: Node, index: int, p: BuildingPlot) -> void:
	mgr.choose_building(index)
	mgr._place_building(p)
func arrive(w: WorkerManager) -> void:
	var t0 := Time.get_ticks_msec()
	while w.get_workers().any(func(x): return x.is_moving()) and Time.get_ticks_msec() - t0 < 25000:
		await process_frame
func view(focus: Vector3, dist: float) -> void:
	cam.set("_focus", focus * Vector3(1, 0, 1)); cam.set("_distance", dist); cam.set("_target_distance", dist)
func shot(n: String) -> void:
	await create_timer(2.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "ev_" + n + ".png")

func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	# This test checks the rules of each event. The stories have their own tests
	# (test_drought.gd, test_disease.gd and test_stories.gd).
	StoryBox.enabled = false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ev: EventManager = main.get_node("EventManager")
	var fx: EventEffects = main.get_node("EventEffects")
	var pop: PopulationManager = main.get_node("PopulationManager")
	var res: ResearchManager = main.get_node("ResearchManager")
	pop.get_node("UpkeepTimer").stop()
	var timer: Timer = ev.get_node("EventTimer")
	timer.stop()
	cam = main.get_node("Camera3D")
	var r: ResourceManager = main.get_node("ResourceManager"); var map: Node = main.get_node("MapManager"); var mgr: Node = main.get_node("BuildingManager"); var w: WorkerManager = main.get_node("WorkerManager")
	var sun: DirectionalLight3D = main.get_node("Sun"); var env: Environment = main.get_node("WorldEnvironment").environment
	var label: Label = main.get_node("UI/EventLabel")
	var R := ResourceManager.Type; var E := EventManager.Type
	var plots: Array = map.get_plots()
	var farm: BuildingPlot = plots[1]; var lumber: BuildingPlot = plots[5]; var quarry: BuildingPlot = plots[6]; var lab: BuildingPlot = plots[10]
	place(mgr, 1, farm); place(mgr, 2, lumber); place(mgr, 3, quarry)
	for p in [farm, farm, lumber, lumber, quarry]: w.assign_worker(p)
	await arrive(w)
	var base := [w.get_output(farm), w.get_output(lumber), w.get_output(quarry)]
	check("base output (Farm x1.5: 9 -> 13)", base == [13, 7, 3], str(base))
	var normal_energy := sun.light_energy
	# Discovery
	ev.trigger(E.DISCOVERY)
	check("discovery: wood and stone +50%", ev.is_active(E.DISCOVERY) and w.get_output(lumber) == 10 and w.get_output(quarry) == 4 and w.get_output(farm) == 13)
	check("discovery sparkles over Lumber Camp and Quarry", fx._temporary.size() == 2)
	view(lumber.position, 90.0)
	await shot("discovery")
	ev._process(61.0)
	check("discovery ends, sparkles go", not ev.is_active(E.DISCOVERY) and fx._temporary.is_empty())
	# Trade
	ev.trigger(E.TRADE)
	check("trade shows beacon on the beach", fx._temporary.size() == 2 and ev.get_beach_position().x > 100.0, str(ev.get_beach_position()))
	view(ev.get_beach_position(), 120.0)
	await shot("trade")
	var wood := r.get_amount(R.WOOD); var gold := r.get_amount(R.GOLD)
	var offer: Dictionary = ev.get_trade_offers()[0]   # Fixed when the ship arrived.
	var half: int = offer.give[R.WOOD]
	await key(KEY_ENTER)
	check("Enter accepts the timber offer: half the wood, 1 gold for every 2", half >= 20 and offer.gold == half / EventManager.TRADE_GOODS_PER_GOLD and r.get_amount(R.WOOD) == wood - half and r.get_amount(R.GOLD) == gold + offer.gold and not ev.is_active(E.TRADE), "%d wood, %d gold" % [r.get_amount(R.WOOD), r.get_amount(R.GOLD)])
	var gold_after := r.get_amount(R.GOLD)
	ev.trigger(E.TRADE)
	await key(KEY_N)
	check("N declines trade", not ev.is_active(E.TRADE) and r.get_amount(R.GOLD) == gold_after)
	# Storm
	ev.trigger(E.STORM)
	check("storm: output 75%, rain on", w.get_output(farm) == 10 and fx._rain.emitting)
	view(Vector3.ZERO, 200.0)
	await shot("storm")
	check("storm darkens the sky and adds fog", sun.light_energy < normal_energy * 0.4 and env.fog_enabled and env.fog_density > 0.001, "sun %.2f fog %.4f" % [sun.light_energy, env.fog_density])
	ev._process(46.0)
	await create_timer(2.3).timeout
	check("storm ends, weather returns", not fx._rain.emitting and absf(sun.light_energy - normal_energy) < 0.01 and env.fog_density < 0.0001)
	# Migration
	ev.trigger(E.MIGRATION)
	var gita: Worker = w.get_workers()[6]
	check("migrants start on the ship, out at sea", w.get_workers().size() == 8 and gita.aboard and gita.model.position.x > 300.0 and gita.is_moving(), str(gita.model.position))
	# Skip the sail in (test_migration_boat.gd checks it): put the ship at anchor.
	var ship: MigrationBoat = main.get_node("MigrationBoat")
	ship.position.x = ship.get_anchor().x
	await process_frame
	await process_frame
	check("once it anchors they step ashore and walk in", not gita.aboard and gita.model.position.x > 100.0 and gita.is_moving(), str(gita.model.position))
	await create_timer(1.0).timeout
	var ground: float = main.get_node("Island/Terrain").get_height_at(gita.model.position.x, gita.model.position.z)
	check("walking migrants follow the ground", absf(gita.model.position.y - ground) < 0.01, "%.2f vs %.2f" % [gita.model.position.y, ground])
	await arrive(w)
	# Drought
	ev.trigger(E.DROUGHT)
	check("drought: food halved", w.get_output(farm) == 6 and w.get_output(lumber) == 7)
	view(Vector3.ZERO, 200.0)
	await shot("drought")
	var tint: Color = main.get_node("Island/Terrain").material_override.get_shader_parameter("grass_tint")
	check("drought dries the grass", tint.r > 0.95 and tint.g < 0.95, str(tint))
	# A drought has no countdown now: its mission ends it.
	ev.end_event(E.DROUGHT)
	# Accident on the lowest-numbered building (the Farm on plot 2)
	var farm_y: float = farm.building.position.y
	ev.trigger(E.ACCIDENT)
	check("accident collapses the first building", farm.is_damaged and w.get_output(farm) == 0)
	view(farm.position, 70.0)
	await shot("collapse")
	check("building leans and sinks", farm.building.rotation.x > 0.2 and farm.building.position.y < farm_y - 2.5, "tilt %.2f y %.2f" % [farm.building.rotation.x, farm.building.position.y])
	ev._process(500.0)
	check("stays collapsed until repaired", farm.is_damaged)
	wood = r.get_amount(R.WOOD); var stone := r.get_amount(R.STONE)
	var idle_before := w.get_idle_count()
	await key(KEY_ENTER)
	var crew: Array = ev._find(E.ACCIDENT).crew
	check("Enter sends 2 idle workers and pays", crew.size() == 2 and w.get_idle_count() == idle_before - 2 and r.get_amount(R.WOOD) == wood - 10 and r.get_amount(R.STONE) == stone - 5)
	ev._process(5.0)
	check("no progress until the crew arrives", ev._find(E.ACCIDENT).progress == 0.0)
	await arrive(w)
	await shot("repairing")
	var p0: float = ev._find(E.ACCIDENT).progress
	ev._process(10.0)
	await process_frame
	check("2 workers repair half in 10 s", absf(ev._find(E.ACCIDENT).progress - p0 - 0.5) < 0.01 and label.text.contains("Repairing"), label.text)
	ev._process(10.0 - p0 * 20.0 - 0.1)
	check("not finished just before 20 s of work", farm.is_damaged)
	ev._process(0.5)
	await create_timer(1.7).timeout
	check("repaired: rises again, works again, crew released", not farm.is_damaged and absf(farm.building.rotation.x) < 0.01 and absf(farm.building.position.y - farm_y) < 0.01 and w.get_output(farm) == 13 and w.get_idle_count() == idle_before)
	# Disease and vaccine
	var happy := pop.get_happiness()
	ev.trigger(E.DISEASE)
	var patients := ev.get_patients()
	var all := w.get_workers()
	check("disease: every second worker is sick, -5 happiness", patients.size() == ceili(all.size() / 2.0) and all[0].is_sick and not all[1].is_sick and all[2].is_sick and pop.get_happiness() == happy - 5, "%d of %d sick" % [patients.size(), all.size()])
	check("red cross over each sick worker only", fx._temporary.size() == patients.size())
	var farm_crew := w.get_workers_at(farm)
	var healthy := 0
	for x in farm_crew:
		if not x.is_sick: healthy += x.productivity
	check("sick workers make nothing, healthy ones keep working", w.get_output(farm) == int(healthy * 1.5) and healthy > 0, "farm %d" % w.get_output(farm))
	view(Vector3.ZERO, 40.0)
	await shot("disease")
	timer.start(1.0)
	await create_timer(1.5).timeout
	check("schedule timer waits while disease is untreated", ev.get_active().size() == 1 and timer.paused, "active %d" % ev.get_active().size())
	# Hold the schedule here, so a new event cannot arrive during the checks below.
	timer.stop()
	check("Enter without vaccine does nothing", not ev.respond() and ev.is_active(E.DISEASE) and ev.get_notice().contains("vaccine"))
	check("research needs a Research Lab", not res.start("vaccine"))
	r.add(R.WOOD, 50); r.add(R.STONE, 30); r.add(R.GOLD, 30)
	place(mgr, 5, lab)
	gold = r.get_amount(R.GOLD)
	map.select_plot(lab)
	await key(KEY_R)
	check("R at the Lab starts vaccine research for 15 gold", res.get_current() == "vaccine" and r.get_amount(R.GOLD) == gold - 15)
	res._process(46.0)
	check("vaccine finished after 45 s", res.is_finished("vaccine"))
	map.select_plot(null)
	r.spend({R.FOOD: r.get_amount(R.FOOD)})
	happy = pop.get_happiness()
	var sick_farm_worker: Worker = null
	for x in w.get_workers_at(farm):
		if x.is_sick: sick_farm_worker = x
	await key(KEY_ENTER)
	check("Enter with no food still works: treatment is free", ev._find(E.DISEASE) != null and ev._find(E.DISEASE).treating and r.get_amount(R.FOOD) == 0)
	check("sick workers walk to the Lab, keeping their jobs", sick_farm_worker.treatment_plot == lab and sick_farm_worker.job_plot == farm and sick_farm_worker.is_moving())
	view(lab.position, 70.0)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "ev_treatment.png")
	await arrive(w)
	await process_frame
	await process_frame
	check("all treated on arrival: outbreak ends, +10 happiness, crosses go", not ev.is_active(E.DISEASE) and ev.get_patients().is_empty() and pop.get_happiness() == happy + 10 and fx._temporary.is_empty(), "active %s patients %d happy %d->%d marks %d" % [ev.is_active(E.DISEASE), ev.get_patients().size(), happy, pop.get_happiness(), fx._temporary.size()])
	check("treated workers head back to their jobs", sick_farm_worker.treatment_plot == null and sick_farm_worker.job_plot == farm)
	await arrive(w)
	check("farm back to full output", w.get_output(farm) == 13)
	await process_frame
	check("schedule resumes after treatment", not timer.paused)
	timer.stop()
	ev.trigger(E.DISEASE)
	ev._process(121.0)
	check("untreated outbreak ends by itself, everyone recovers", not ev.is_active(E.DISEASE) and ev.get_patients().is_empty())
	# Accident on a House, with no idle workers
	var main2: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main2)
	await process_frame
	var ev2: EventManager = main2.get_node("EventManager"); var p2: PopulationManager = main2.get_node("PopulationManager"); var w2: WorkerManager = main2.get_node("WorkerManager")
	var house: BuildingPlot = main2.get_node("MapManager").get_plots()[0]
	place(main2.get_node("BuildingManager"), 0, house)
	check("camp homes 10 and a House 4 more", p2.get_housing_capacity() == PopulationManager.CAMP_HOMES + PopulationManager.PEOPLE_PER_HOUSE)
	ev2.trigger(E.ACCIDENT)
	check("collapsed House homes nobody, the camp still does", house.is_damaged and p2.get_housing_capacity() == PopulationManager.CAMP_HOMES)
	for x in w2.get_workers(): x.job_plot = house
	check("no idle workers: repair refused", not ev2.respond() and ev2.get_notice().contains("No idle"))
	main2.queue_free()
	var main3: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main3)
	await process_frame
	var ev3: EventManager = main3.get_node("EventManager")
	ev3.trigger(E.ACCIDENT)
	check("accident with no buildings shows a message", ev3.describe(ev3.get_active()[0]).contains("No buildings"))
	ev3._process(11.0)
	check("message clears", ev3.get_active().is_empty())
	main3.queue_free()

	# Schedule: one event at a time, a calm period after each, and the next event
	# waits for the resources to answer it (but not forever).
	var main4: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main4)
	await process_frame
	main4.get_node("PopulationManager/UpkeepTimer").stop()
	var ev4: EventManager = main4.get_node("EventManager")
	var r4: ResourceManager = main4.get_node("ResourceManager")
	var t4: Timer = ev4.get_node("EventTimer")
	var label4: Label = main4.get_node("UI/EventLabel")
	check("first event after 60 s of calm", absf(t4.time_left - EventManager.FIRST_EVENT_SECONDS) < 1.0 and ev4.get_active().is_empty())
	await process_frame
	check("panel shows the calm countdown", label4.text.contains("Calm: next event in"), label4.text)
	t4.start(0.1)
	await create_timer(0.3).timeout
	check("Discovery starts when the calm ends", ev4.is_active(E.DISCOVERY))
	await create_timer(0.3).timeout
	check("calm countdown is held while the event runs", t4.paused and label4.text.contains("Then 90 s of calm"), label4.text)
	ev4._process(61.0)
	await process_frame
	await process_frame
	check("a full calm starts when the event ends", ev4.get_active().is_empty() and absf(t4.time_left - EventManager.CALM_SECONDS) < 1.0 and not t4.paused, "active %d left %.1f paused %s" % [ev4.get_active().size(), t4.time_left, t4.paused])
	check("the schedule has five events, a mission after each easy one", str(EventManager.ORDER) == str([E.DISCOVERY, E.DROUGHT, E.TRADE, E.DISEASE, E.MIGRATION]) and ev4.get_next_type() == E.DROUGHT)
	ev4._next_index = EventManager.ORDER.find(E.TRADE)
	r4.spend({R.WOOD: r4.get_amount(R.WOOD), R.STONE: r4.get_amount(R.STONE)})
	t4.start(0.1)
	await create_timer(0.3).timeout
	check("Trade waits until there is wood or stone to trade", not ev4.is_active(E.TRADE) and ev4.is_waiting_for_resources())
	check("panel says what the next event needs", label4.text.contains("Trade") and label4.text.contains("40 Wood"), label4.text)
	r4.add(R.WOOD, 40)
	await process_frame
	await process_frame
	check("Trade starts once the wood is there", ev4.is_active(E.TRADE) and not ev4.is_waiting_for_resources())
	ev4.decline()
	await process_frame
	ev4._next_index = EventManager.ORDER.find(E.DROUGHT)   # Needs 10 wood and 5 stone for the Water Storage.
	r4.spend({R.WOOD: r4.get_amount(R.WOOD)})
	t4.start(0.1)
	await create_timer(0.3).timeout
	check("Drought waits for the Water Storage's materials", ev4.is_waiting_for_resources() and ev4.get_active().is_empty())
	ev4._process(EventManager.MAX_EXTRA_WAIT + 1.0)
	check("but comes anyway after the longest wait", ev4.is_active(E.DROUGHT), "active %s waiting %s" % [str(ev4.get_active().map(func(e): return e.type)), ev4.is_waiting_for_resources()])
	# A building site holds the next event back too, and the panel must say so,
	# not ask for resources the colony already has.
	ev4.end_event(E.DROUGHT)
	await process_frame
	var builder4: BuildingManager = main4.get_node("BuildingManager")
	for type in R.values():
		r4.add(type, 200)
	builder4.choose_building(8)   # The Lighthouse: 5 days to build.
	builder4._place_building(main4.get_node("MapManager").get_plot(2))
	ev4._next_index = EventManager.ORDER.find(E.TRADE)
	t4.start(0.1)
	await create_timer(0.3).timeout
	check("with plenty of wood, Trade still waits for the building site", ev4.is_waiting_for_resources() and r4.get_amount(R.WOOD) >= 40 and not ev4.is_active(E.TRADE))
	check("and the panel names the building, not resources", label4.text.contains("(Trade opportunity) waits until the Lighthouse is finished building") and not label4.text.contains("you have"), label4.text)
	main4.queue_free()
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
