# test_selection.gd
# Selecting plots with real mouse clicks through the game window, from several
# camera views. Run with a window (not headless) and do not move the mouse:
#   <Godot> --path . --script res://tests/test_selection.gd
extends SceneTree

var fails := 0
var map: MapManager
var cam: Camera3D


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


# Converts a world position to window pixels and clicks there.
func click_world(point: Vector3) -> void:
	var pixel := cam.unproject_position(point) * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = pixel
		e.global_position = pixel
		Input.parse_input_event(e)
		await process_frame
		await process_frame


func view(focus: Vector3, yaw: float, distance: float) -> void:
	cam.set("_focus", focus)
	cam.set("_yaw", deg_to_rad(yaw))
	cam.set("_distance", distance)
	cam.set("_target_distance", distance)
	await create_timer(0.8).timeout


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	map = main.get_node("MapManager")
	cam = main.get_node("Camera3D")
	var plots := map.get_plots()
	var corner := BuildingPlot.SIZE * 0.5 - 1.0

	for v in [[Vector3(-18, 0, 0), -45.0, 370.0, "start"], [Vector3(-18, 0, 0), 135.0, 300.0, "rotated"], [Vector3.ZERO, 20.0, 180.0, "closer"]]:
		await view(v[0], v[1], v[2])
		# The wide views show every plot. The closer view shows only the middle of
		# the town, so it checks the plots within 90 m of the town square.
		var shown: Array = plots if v[2] > 250.0 else plots.filter(func(p: BuildingPlot) -> bool: return Vector2(p.position.x, p.position.z).length() < 90.0)
		# v2: the corner panels cover parts of the screen; a click there belongs to
		# the panel, so only squares that can be seen and clicked are tried.
		var hud: Hud = main.get_node("UI/HUD")
		var clickable := func(point: Vector3) -> bool:
			var pixel := cam.unproject_position(point)
			return not cam.is_position_behind(point) and get_root().get_visible_rect().grow(-10.0).has_point(pixel) and not hud.covers(pixel)
		shown = shown.filter(func(p: BuildingPlot) -> bool: return clickable.call(p.position))
		var right := 0
		for plot in shown:
			await click_world(plot.position)
			if map.get_selected_plot() == plot:
				right += 1
		check("every plot centre selects itself, view " + v[3], right == shown.size(), "%d of %d" % [right, shown.size()])
		# The first square whose four corners can all be clicked.
		var target: BuildingPlot = null
		for p in shown:
			var all_clear := true
			for offset in [Vector3(corner, 0, corner), Vector3(-corner, 0, corner), Vector3(corner, 0, -corner), Vector3(-corner, 0, -corner)]:
				var spot: Vector3 = p.to_world(offset)
				if not clickable.call(Vector3(spot.x, p.position.y, spot.z)):
					all_clear = false
			if all_clear and target == null:
				target = p
		var corners := 0
		for offset in [Vector3(corner, 0, corner), Vector3(-corner, 0, corner), Vector3(corner, 0, -corner), Vector3(-corner, 0, -corner)]:
			var spot: Vector3 = target.to_world(offset)   # Squares are turned (v2).
			await click_world(Vector3(spot.x, target.position.y, spot.z))
			if map.get_selected_plot() == target:
				corners += 1
		check("clicks near the corners select it, view " + v[3], corners == 4, "%d of 4" % corners)
		var lane: Vector3 = target.to_world(Vector3(BuildingPlot.SIZE * 0.5 + 2.0, 0, 0))   # Just outside its side.
		await click_world(Vector3(lane.x, target.position.y, lane.z))
		check("click in the lane between plots clears the selection, view " + v[3], map.get_selected_plot() == null)

	await view(Vector3(-18, 0, 0), -45.0, 370.0)
	await click_world(plots[6].position)
	var others_hidden := true
	for plot in plots:
		if plot != plots[6] and plot.visible:
			others_hidden = false
	check("only the selected plot shows, in yellow", plots[6].visible and others_hidden and plots[6].material_override.albedo_color == BuildingPlot.SELECTED_COLOUR)
	await click_world(plots[2].position)
	check("selection moves to another plot", map.get_selected_plot() == plots[2] and not plots[6].visible)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	await process_frame
	check("Esc clears the selection", map.get_selected_plot() == null)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
