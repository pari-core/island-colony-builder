# test_population.gd
# Spec tests: T10, T17. Population (workers and civilians), food use, housing,
# happiness limits, population states, growth and civilians' animations.
# Run with a window:  <Godot> --path . --script res://tests/test_population.gd
extends SceneTree

var fails := 0


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func build_house(manager: Node, plot: BuildingPlot) -> void:
	manager.choose_building(0)
	manager._place_building(plot)


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var pop: PopulationManager = main.get_node("PopulationManager")
	pop.get_node("UpkeepTimer").stop()
	main.get_node("GameStateManager").enabled = false   # This test runs many hungry cycles.
	main.get_node("EventManager/EventTimer").stop()
	var r: ResourceManager = main.get_node("ResourceManager")
	var map: MapManager = main.get_node("MapManager")
	var builder: Node = main.get_node("BuildingManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var civilians: CivilianManager = main.get_node("CivilianManager")
	var bar: Label = main.get_node("UI/ResourcePanel/ResourceBar")
	var F := ResourceManager.Type.FOOD
	var plots := map.get_plots()

	check("starts with 6 workers and 4 civilians", pop.get_worker_count() == 6 and pop.get_civilian_count() == 4 and pop.get_population() == 10)
	check("starts Stable at 60, everyone sheltered by the landing camp", pop.get_happiness() == 60 and pop.get_state() == PopulationManager.State.STABLE and pop.get_homeless() == 0 and pop.get_housing_capacity() == 10)
	check("bar shows people and housing", bar.text.contains("People 10 (6 workers, 4 civilians)") and bar.text.contains("Homes 10/10"), bar.text)

	pop.upkeep()
	check("upkeep eats 2 per worker and 1 per civilian: 16 food", r.get_amount(F) == 134 and pop.was_fed())
	check("fed and sheltered: 60 + 2 = 62", pop.get_happiness() == 62)
	for i in 4:
		r.add(F, 30)
		pop.upkeep()
	check("no growth while the camp is full", pop.get_civilian_count() == 4)

	# Two more people than the camp holds.
	civilians.add_civilian()
	civilians.add_civilian()
	check("12 people, 2 without a home", pop.get_homeless() == 2 and bar.text.contains("Homes 12/10"), bar.text)
	var happiness := pop.get_happiness()
	for i in 4:
		r.add(F, 30)
		pop.upkeep()
	check("fed but 2 homeless: +2 - 2 = no change", pop.get_happiness() == happiness)
	check("no growth while anyone is homeless", pop.get_civilian_count() == 6)

	build_house(builder, plots[0])
	check("a House homes 4 more: all 12 housed, 2 spaces free", pop.get_homeless() == 0 and pop.get_housing_capacity() == 14)
	happiness = pop.get_happiness()
	r.add(F, 30)
	pop.upkeep()
	check("no growth before 2 good cycles", pop.get_civilian_count() == 6)
	r.add(F, 30)
	pop.upkeep()
	check("grows by one civilian after 2 good cycles", pop.get_civilian_count() == 7 and pop.get_worker_count() == 6)
	for i in 7:
		r.add(F, 30)
		pop.upkeep()
	check("grows until the homes are full, then stops", pop.get_population() == 14 and pop.get_civilian_count() == 8, str(pop.get_population()))
	check("fed and housed: happiness +2 each cycle", pop.get_happiness() == happiness + 18, "%d -> %d" % [happiness, pop.get_happiness()])

	r.spend({F: r.get_amount(F)})
	r.add(F, 5)
	happiness = pop.get_happiness()
	pop.upkeep()
	check("hungry: eats what is left, never below zero", r.get_amount(F) == 0 and not pop.was_fed())
	check("hungry: happiness -10", pop.get_happiness() == happiness - 10)
	build_house(builder, plots[3])
	for i in 6:
		pop.upkeep()
	check("no growth while hungry", pop.get_population() == 14)
	for i in 10:
		pop.upkeep()
	check("happiness never below 0", pop.get_happiness() == 0)
	for i in 60:
		r.add(F, 40)
		pop.upkeep()
	check("happiness never above 100", pop.get_happiness() == 100)

	# Output follows the population state. A Farm with Asha (5) and Ben (4) makes
	# 9 x 1.5 (the Farm's own boost) = 13 normally. Fractions are dropped.
	var farm := plots[5]
	builder.choose_building(1)
	builder._place_building(farm)
	workers.assign_worker(farm)
	workers.assign_worker(farm)
	for worker in workers.get_workers():
		if worker.job_plot == farm:
			worker.model.position = worker.target_position
	pop._happiness = 100
	check("Thriving output x1.25: 16", workers.get_output(farm) == 16, str(workers.get_output(farm)))
	pop._happiness = 50
	check("Stable output: 13", workers.get_output(farm) == 13)
	pop._happiness = 10
	check("Struggling output x0.75: 10", workers.get_output(farm) == 10, str(workers.get_output(farm)))

	# Civilians move and animate. A fresh colony is used, because the civilians above
	# have just been given new homes and are still walking to them.
	main.queue_free()
	var fresh: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(fresh)
	await process_frame
	await process_frame
	civilians = fresh.get_node("CivilianManager")
	main = fresh
	var person: Civilian = civilians.get_civilians()[0]
	var start := person.position
	var walked := false
	var idled := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and not (walked and idled):
		await process_frame
		if person.is_walking():
			walked = true
		elif walked:
			idled = true
	check("a civilian walks, then stands idle", walked and idled)
	check("civilians move and stay on the ground", person.position.distance_to(start) > 1.0 and absf(person.position.y - main.get_node("Island/Terrain").get_height_at(person.position.x, person.position.z)) < 0.01)
	var near_home := true
	for c in civilians.get_civilians():
		if Vector2(c.position.x - c.home.x, c.position.z - c.home.z).length() > Civilian.WANDER_MAX + 22.0:
			near_home = false
	check("civilians stay near their homes", near_home)

	# Going inside. Time runs 8 times faster here so the test does not take minutes.
	var pop2: PopulationManager = fresh.get_node("PopulationManager")
	pop2.get_node("UpkeepTimer").stop()
	fresh.get_node("GameStateManager").enabled = false
	fresh.get_node("EventManager/EventTimer").stop()
	var map2: MapManager = fresh.get_node("MapManager")
	var house_plot := map2.get_plots()[5]
	build_house(fresh.get_node("BuildingManager"), house_plot)
	var house := Vector3(house_plot.position.x, 0.0, house_plot.position.z)
	var all_home := true
	for c in civilians.get_civilians():
		if not c.has_house or not c.home.is_equal_approx(house):
			all_home = false
	check("with one House, every civilian lives there", all_home)
	Engine.time_scale = 8.0
	var went_in: Civilian = null
	var came_out := false
	var through_wall := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not came_out:
		await process_frame
		for c in civilians.get_civilians():
			var rel := Vector2(c.position.x - house.x, c.position.z - house.z)
			if c.visible and absf(rel.x) < 5.0 and absf(rel.y) < 3.5:
				through_wall = true
			if went_in == null and c.is_inside():
				went_in = c
				check("a civilian inside is hidden and counted", not c.visible and civilians.get_inside_count(house_plot) >= 1)
				var door := c.get_ground_position() - house
				var front := Civilian.DOOR.rotated(Vector3.UP, c.home_turn)   # The door turns with the House (v2).
				check("they went in at the front door", absf(door.x - front.x) < 0.1 and absf(door.z - front.z) < 0.1, str(door))
		if went_in != null and not went_in.is_inside():
			came_out = true
	Engine.time_scale = 1.0
	check("a civilian goes into their House", went_in != null)
	check("and comes back out later", came_out and went_in.visible)
	check("nobody walks through the House walls", not through_wall)

	# Training a civilian into a worker.
	var r2: ResourceManager = fresh.get_node("ResourceManager")
	var workers2: WorkerManager = fresh.get_node("WorkerManager")
	var food_before := r2.get_amount(F)
	check("training is offered on a House", civilians.get_training_problem(house_plot) == "")
	check("training is refused elsewhere", civilians.get_training_problem(map2.get_plots()[0]) != "")
	map2.select_plot(house_plot)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	key.pressed = true
	root.push_input(key)
	await process_frame
	check("pressing T on a selected House trains a worker", civilians.get_count() == 3)
	check("training turns a civilian into a worker for 10 food", civilians.get_count() == 3 and workers2.get_workers().size() == 7 and r2.get_amount(F) == food_before - 10)
	var newcomer: Worker = workers2.get_workers().back()
	check("the new worker starts at the House", Vector2(newcomer.model.position.x - house.x, newcomer.model.position.z - house.z).length() < Civilian.WANDER_MAX + 1.0)
	r2.spend({F: r2.get_amount(F)})
	check("no training without food", not civilians.train_worker(house_plot) and civilians.get_count() == 3)
	r2.add(F, 100)
	while civilians.get_count() > 0:
		civilians.train_worker(house_plot)
	check("no training without civilians", not civilians.train_worker(house_plot) and workers2.get_workers().size() == 10)
	civilians.add_civilian()
	civilians.add_civilian()
	civilians.add_civilian()
	civilians.train_worker(house_plot)
	civilians.train_worker(house_plot)
	check("never more than 12 workers", not civilians.train_worker(house_plot) and workers2.get_workers().size() == 12 and civilians.get_count() == 1)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
