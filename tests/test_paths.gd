# test_paths.gd
# Workers and civilians walk around buildings, never through them.
# Run with a window:  <Godot> --path . --script res://tests/test_paths.gd
extends SceneTree

var fails := 0


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


var _plots: Array = []


# v2: buildings are turned with their squares. This is the building's ground
# area in its own directions (x across, z front to back), from its meshes.
func local_box(building: Node3D) -> Rect2:
	var to_local := building.global_transform.affine_inverse()
	var box := Rect2()
	var first := true
	for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (to_local * mesh.global_transform) * mesh.get_aabb()
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		box = r if first else box.merge(r)
		first = false
	# Scale (upgrades) is part of the building's own transform, so apply it.
	return Rect2(box.position * building.scale.x, box.size * building.scale.x)


# Returns the building's area if this point is inside a building, shrunk slightly
# so that standing right against a wall does not count, or an empty Rect2.
# (The path grid blocks a larger, square-on area around each turned building,
# so walkers keep well clear; this checks the building itself.)
func inside_building(_paths: PathGrid, point: Vector3) -> Rect2:
	for plot in _plots:
		if plot.building == null:
			continue
		var b: Node3D = plot.building
		var local := (point - b.position).rotated(Vector3.UP, -b.rotation.y)
		var area := local_box(b)
		if area.grow(-0.3).has_point(Vector2(local.x, local.z)):
			return area
	return Rect2()


func line_hits_building(paths: PathGrid, a: Vector3, b: Vector3) -> bool:
	for s in 101:
		var p := a.lerp(b, s / 100.0)
		if inside_building(paths, p).has_area():
			return true
	return false


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("EventManager/EventTimer").stop()
	var paths: PathGrid = main.get_node("PathGrid")
	var map: MapManager = main.get_node("MapManager")
	var builder: Node = main.get_node("BuildingManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var civilians: CivilianManager = main.get_node("CivilianManager")
	var r: ResourceManager = main.get_node("ResourceManager")

	check("no buildings: a straight line", paths.find_path(Vector3(-60, 0, 0), Vector3(60, 0, 0)).size() == 1)

	# A building on every plot (all 20), so the town is packed solid: Houses and
	# every kind of work building.
	var kinds := [0, 0, 0, 1, 2, 3, 6, 1, 4, 5, 1, 2, 3, 6, 1, 4, 5, 0, 0, 0]
	var plots: Array = map.get_plots()
	for i in plots.size():
		for t in ResourceManager.Type.values():
			r.add(t, 200)
		builder.choose_building(kinds[i % kinds.size()])
		builder._place_building(plots[i])
	check("20 footprints measured", paths.get_footprints().size() == 20)
	_plots = plots
	var fits := true
	for i in plots.size():
		if not Rect2(-12.0, -12.0, 24.0, 24.0).encloses(local_box(plots[i].building)):
			fits = false
	check("each building stays inside its plot", fits)

	# Routes across the whole building area.
	# v2: from the town square to the front of every building, as workers and
	# civilians walk, across the whole scattered village.
	var trips := []
	for plot in plots:
		trips.append([Vector3.ZERO, plot.to_world(Vector3(0.0, 0.0, BuildingPlot.SIZE * 0.5 + 2.0))])
	trips.append_array([
		[Vector3(145, 0, 0), plots[3].position + (WorkerManager.SLOT_OFFSETS[0] as Vector3).rotated(Vector3.UP, plots[3].rotation.y)],   # Beach to a job spot
	])
	var all_clear := true
	for trip in trips:
		var here: Vector3 = trip[0]
		var route := paths.find_path(trip[0], trip[1])
		if not route.back().is_equal_approx(trip[1]):
			all_clear = false
		for point in route:
			if line_hits_building(paths, here, point):
				all_clear = false
				print("  crosses a building between ", here, " and ", point)
			here = point
	check("routes reach their goal without crossing a building", all_clear)

	# Everyone moving at once: jobs on every work building, civilians wandering and
	# going in and out of Houses. Time runs 8 times faster.
	for plot in plots:
		while workers.assign_worker(plot):
			pass
	Engine.time_scale = 8.0
	var crossed := ""
	var visited_door := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await process_frame
		for worker in workers.get_workers():
			if inside_building(paths, worker.model.position).has_area():
				crossed = "worker %s at %s" % [worker.worker_name, worker.model.position]
		for c in civilians.get_civilians():
			if c.visible and inside_building(paths, c.position).has_area():
				crossed = "civilian at %s" % c.position
			if c.is_inside():
				visited_door = true
	Engine.time_scale = 1.0
	check("no worker or civilian walks through a building", crossed == "", crossed)
	var arrived := true
	for worker in workers.get_workers():
		if worker.is_moving():
			arrived = false
	check("every worker still reaches their spot", arrived)
	check("civilians still get in through their doors", visited_door)

	# A building placed in someone's way: they find a new route.
	var main2: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main2)
	await process_frame
	main2.get_node("EventManager/EventTimer").stop()
	var w2: WorkerManager = main2.get_node("WorkerManager")
	var map2: MapManager = main2.get_node("MapManager")
	var b2: Node = main2.get_node("BuildingManager")
	var paths2: PathGrid = main2.get_node("PathGrid")
	var far_plot := map2.get_plot(12)
	b2.choose_building(1)
	b2._place_building(far_plot)
	var worker: Worker = w2.get_workers()[0]
	worker.model.position = Vector3(far_plot.position.x, 2.2, far_plot.position.z - 40.0)
	w2.assign_worker(far_plot)
	await process_frame
	b2.choose_building(3)
	b2._place_building(map2.get_plot(8))
	b2._place_building(map2.get_plot(7))
	var old_version := worker.path_version
	await process_frame
	check("a new building makes walkers re-plan", worker.path_version != old_version and worker.path_version == paths2.version)
	main2.queue_free()

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
