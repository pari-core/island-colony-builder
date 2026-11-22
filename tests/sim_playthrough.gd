# sim_playthrough.gd
# A scripted player that builds sensibly, to measure how long a win takes and
# whether a slow player survives (spec test T18, long play, and balance). Not part
# of run_all_tests.sh, because it is a measurement, not a pass or fail check.
# Time runs 10 times faster.
#
# Run with a window:
#   <Godot> --path . --script res://tests/sim_playthrough.gd              (fast player)
#   <Godot> --path . --script res://tests/sim_playthrough.gd -- slow      (slow player)
# The slow player waits 20 s before starting and then makes one move every 8 s.
extends SceneTree

const SPEED := 10.0
var main; var r; var b; var map; var w; var pop; var civ; var ev; var game


func _initialize() -> void:
	run()


func count(building_name: String) -> int:
	var n := 0
	for p in map.get_plots():
		if p.building_info.get("name", "") == building_name:
			n += 1
	return n


func build(k: int) -> bool:
	var cost: Dictionary = BuildingManager.BUILDINGS[k].cost
	for p in map.get_plots():
		if p.is_buildable():
			if not r.spend(cost):
				return false
			b.choose_building(k)
			b._place_building(p)
			return true
	return false


# Makes one move, in order of importance. Returns false if there is nothing to do.
func act() -> bool:
	# Put idle workers to work: farms first.
	if w.get_idle_count() > 0:
		for building_name in ["Farm", "Lumber Camp", "Quarry"]:
			for p in map.get_plots():
				if p.building_info.get("name", "") == building_name and w.assign_worker(p):
					return true
	if count("Farm") < 1:
		return build(1)
	if pop.get_housing_capacity() < pop.get_population() + 2 and pop.get_housing_capacity() < 28:
		if build(0):
			return true
	if count("Lumber Camp") < 1:
		return build(2)
	if count("Quarry") < 1:
		return build(3)
	if count("Farm") < 2 and pop.get_population() >= 14:
		return build(1)
	if count("Farm") < 3 and pop.get_population() >= 20:
		return build(1)
	# Train a civilian when a job is open and nobody is idle.
	var open := 0
	for p in map.get_plots():
		if p.building != null:
			open += w.get_slots(p) - w.get_workers_at(p).size()
	if open > 0 and w.get_idle_count() == 0 and r.get_amount(ResourceManager.Type.FOOD) > 60 and civ.get_count() > 0:
		for p in map.get_plots():
			if p.building_info.get("name", "") == "House" and not p.is_damaged:
				return civ.train_worker(p)
	return false


func run() -> void:
	var slow := OS.get_cmdline_user_args().has("slow")
	var start_delay := 20.0 if slow else 0.0
	var gap := 8.0 if slow else 0.0
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	r = main.get_node("ResourceManager"); b = main.get_node("BuildingManager"); map = main.get_node("MapManager")
	w = main.get_node("WorkerManager"); pop = main.get_node("PopulationManager"); civ = main.get_node("CivilianManager")
	ev = main.get_node("EventManager"); game = main.get_node("GameStateManager")
	Engine.time_scale = SPEED
	var t0 := Time.get_ticks_msec()
	var last_log := -100.0
	var last_act := -100.0
	var lowest_happiness := 100
	var lowest_food := 9999
	var events_seen := {}
	print("SIM %s player" % ("slow" if slow else "fast"))
	while true:
		for i in 6:
			await process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0 * SPEED
		lowest_happiness = mini(lowest_happiness, pop.get_happiness())
		lowest_food = mini(lowest_food, r.get_amount(ResourceManager.Type.FOOD))
		for e in ev.get_active():
			events_seen[EventManager.NAMES[e.type]] = true
		if game.get_state() != GameStateManager.State.PLAYING:
			print("SIM END at %.0f s: %s" % [t, game.get_reason()])
			break
		if t > 1500.0:
			print("SIM gave up at 1500 s")
			break
		if t >= start_delay and t - last_act >= gap:
			if gap > 0.0:
				if act() or (not ev.get_active().is_empty() and ev.respond()):
					last_act = t
			else:
				while act():
					pass
				if not ev.get_active().is_empty():
					ev.respond()
		if t - last_log >= 60.0:
			last_log = t
			print("SIM %4.0f s  people %d (w %d c %d) homes %d happy %d food %d wood %d stone %d  farms %d houses %d" % [t, pop.get_population(), pop.get_worker_count(), pop.get_civilian_count(), pop.get_housing_capacity(), pop.get_happiness(), r.get_amount(0), r.get_amount(1), r.get_amount(2), count("Farm"), count("House")])
	print("SIM lowest happiness %d, lowest food %d, events seen: %s" % [lowest_happiness, lowest_food, ", ".join(events_seen.keys())])
	paused = false
	quit()
