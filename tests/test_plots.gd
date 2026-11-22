# test_plots.gd
# Spec tests: T08 (valid locations), map tile states. Checks the build squares (plots),
# the flat building area and plot states.
# Can run headless:  <Godot> --headless --path . --script res://tests/test_plots.gd
extends SceneTree

var fails := 0


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var map: MapManager = main.get_node("MapManager")
	var terrain = main.get_node("Island/Terrain")
	var plots := map.get_plots()
	var half := BuildingPlot.SIZE * 0.5

	check("20 plots (the spec asks for at least 12)", plots.size() == 20 and MapManager.MAX_PLOTS == 20, str(plots.size()))
	var ids := {}
	for plot in plots:
		ids[plot.plot_id] = true
	check("IDs 1 to 20, all different", ids.size() == 20 and map.get_plot(1) == plots[0] and map.get_plot(20) == plots[19])
	check("no plot 0 or 21", map.get_plot(0) == null and map.get_plot(21) == null)
	var outwards := true
	for i in range(1, plots.size()):
		if Vector2(plots[i].position.x, plots[i].position.z).length() < Vector2(plots[i - 1].position.x, plots[i - 1].position.z).length() - 0.01:
			outwards = false
	check("plots are numbered from the town square outwards, the first 36 m out", outwards and is_equal_approx(Vector2(plots[0].position.x, plots[0].position.z).length(), MapManager.GRID_STEP))
	var across := 0
	for plot in plots:
		if plot.position.z > terrain.RIVER_Z:
			across += 1
	check("no plots across the river", across == 0)

	var flat := true
	var furthest := 0.0
	for plot in plots:
		for dx in [-half, half]:
			for dz in [-half, half]:
				var corner: Vector3 = plot.to_world(Vector3(dx, 0.0, dz))   # Squares are turned (v2).
				var x: float = corner.x
				var z: float = corner.z
				furthest = maxf(furthest, Vector2(x, z).length())
				if absf(terrain.get_height_at(x, z) - terrain.LAND_HEIGHT) > 0.001:
					flat = false
	check("every plot corner on flat land", flat, "furthest corner %.1f m" % furthest)

	# v2 village layout: squares are scattered and turned, never closer than MIN_GAP.
	var closest := INF
	var spread := 0.0
	var turned := 0
	for i in plots.size():
		spread = maxf(spread, Vector2(plots[i].position.x, plots[i].position.z).length())
		if absf(plots[i].rotation.y) > 0.05:
			turned += 1
		for j in range(i + 1, plots.size()):
			closest = minf(closest, Vector2(plots[i].position.x, plots[i].position.z).distance_to(Vector2(plots[j].position.x, plots[j].position.z)))
	# v2 tidy village: a 5 x 5 grid, 36 m apart, plaza in the middle, corners left green.
	var on_grid := true
	var faces_plaza := true
	for plot in plots:
		var cell := Vector2(plot.position.x, plot.position.z) / MapManager.GRID_STEP
		if not cell.is_equal_approx(cell.round()) or absf(cell.x) > 2.0 or absf(cell.y) > 2.0 or (absf(cell.x) == 2.0 and absf(cell.y) == 2.0) or cell == Vector2.ZERO:
			on_grid = false
		var front: Vector3 = plot.to_world(Vector3(0, 0, 1)) - Vector3(plot.position.x, 0, plot.position.z)
		if front.dot(-Vector3(plot.position.x, 0, plot.position.z).normalized()) < 0.7:
			faces_plaza = false
	check("squares never overlap: centres 36 m apart", is_equal_approx(closest, MapManager.GRID_STEP), "%.1f m" % closest)
	check("squares stand on a tidy 5 x 5 grid round the plaza", on_grid)
	check("every square faces the plaza", faces_plaza)
	check("town square in the middle stays free", map.get_plot_at(Vector3.ZERO) == null)

	var decorations: Node = main.get_node("Island/Decorations")
	var on_plots := 0
	for item in decorations.get_children():
		for plot in plots:
			var d: Vector3 = (item.position - plot.position).rotated(Vector3.UP, -plot.rotation.y).abs()
			if d.x < half + 2.0 and d.z < half + 2.0:
				on_plots += 1
	check("no palms or rocks on plots", on_plots == 0 and decorations.get_child_count() > 0, "%d objects checked" % decorations.get_child_count())

	check("all plots start EMPTY", plots.all(func(p): return p.state == BuildingPlot.State.EMPTY and p.is_buildable()))
	check("outlines hidden during play", plots.all(func(p): return not p.visible))
	map.set_outlines_visible(true)
	check("outlines can be shown", plots.all(func(p): return p.is_visible_in_tree()))
	map.set_outlines_visible(false)

	var plot := map.get_plot(3)
	var empty_colour: Color = plot.material_override.albedo_color
	plot.state = BuildingPlot.State.OCCUPIED
	check("OCCUPIED: new colour, not buildable", plot.material_override.albedo_color != empty_colour and not plot.is_buildable())
	plot.state = BuildingPlot.State.BLOCKED
	check("BLOCKED: not buildable", not plot.is_buildable())
	plot.state = BuildingPlot.State.EMPTY
	check("back to EMPTY", plot.material_override.albedo_color == empty_colour and plot.is_buildable())
	check("other plots unaffected", map.get_plot(4).state == BuildingPlot.State.EMPTY)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
