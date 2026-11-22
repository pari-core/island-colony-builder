# test_placement.gd
# Spec tests: T06, T07, T08. Placing a House: preview colours, building, refusing occupied and blocked plots, cancelling.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_placement.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
# Drives placement with real key and mouse events through the game window.
extends SceneTree
const OUT := "user://"
var fails := 0
var map: Node
var mgr: Node
var cam: Camera3D
var label: Label
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
func pixel(point: Vector3) -> Vector2:
	return cam.unproject_position(point) * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
func mouse_to(point: Vector3) -> void:
	# Moving the real pointer is not instant, and someone may be using the mouse.
	# Keep moving it until the game sees it at the target, for up to 1.5 seconds.
	var target := cam.unproject_position(point)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		root.warp_mouse(target)
		await process_frame
		await process_frame
		if root.get_mouse_position().distance_to(target) < 3.0:
			break
	await process_frame
	await process_frame
func click(point: Vector3) -> void:
	var p := pixel(point)
	for down in [true, false]:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
		Input.parse_input_event(e)
		await process_frame
		await process_frame
func houses() -> int:
	var n := 0
	for c in mgr.get_children():
		if c != mgr.get("_preview"): n += 1
	return n
func shot(name: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	# Stop food use and happiness changes, so this test's exact numbers hold.
	main.get_node("PopulationManager/UpkeepTimer").stop()
	map = main.get_node("MapManager"); mgr = main.get_node("BuildingManager"); cam = main.get_node("Camera3D"); label = main.get_node("UI/PlacementLabel")
	var plots: Array = map.get_plots()
	var a: BuildingPlot = plots[5]; var b: BuildingPlot = plots[6]
	cam.set("_focus", a.position * Vector3(1, 0, 1)); cam.set("_distance", 95.0); cam.set("_target_distance", 95.0)
	await create_timer(0.8).timeout
	check("starts with no buildings or mode", houses() == 0 and not mgr.is_placing() and not label.visible)
	await click(a.position)
	check("outside placement a click selects", map.get_selected_plot() == a)
	await key(KEY_B)
	check("B enters placement, clears selection", mgr.is_placing() and map.get_selected_plot() == null)
	check("all outlines show, label shows cost", plots.all(func(q): return q.visible) and label.visible and label.text.contains("Cost"), label.text.replace("\n", " / "))
	await mouse_to(a.position)
	check("hover shows green outline", a.material_override.albedo_color == BuildingPlot.PREVIEW_COLOURS[BuildingPlot.Preview.VALID])
	var ghost: Node3D = mgr.get("_preview")
	check("ghost on hovered plot", ghost.visible and absf(ghost.position.x - a.position.x) < 0.01 and absf(ghost.position.z - a.position.z) < 0.01)
	await shot("place_valid")
	await key(KEY_ESCAPE)
	check("Esc cancels with nothing built", not mgr.is_placing() and houses() == 0 and a.is_buildable() and a.preview == BuildingPlot.Preview.NONE)
	check("cancel hides outlines and label", plots.all(func(q): return not q.visible) and not label.visible)
	await key(KEY_B); await key(KEY_B)
	check("B again also cancels", not mgr.is_placing() and houses() == 0)
	await key(KEY_B)
	await mouse_to(a.position)
	await click(a.position)
	check("click builds and leaves mode", not mgr.is_placing() and houses() == 1 and a.state == BuildingPlot.State.OCCUPIED and a.building != null)
	check("no selection from the build click", map.get_selected_plot() == null)
	check("outlines hidden after build", plots.all(func(q): return not q.visible))
	await shot("place_built")
	await key(KEY_B)
	await mouse_to(a.position)
	check("occupied plot shows red", a.material_override.albedo_color == BuildingPlot.PREVIEW_COLOURS[BuildingPlot.Preview.INVALID])
	check("label says cannot build", label.text.contains("Cannot build"))
	await shot("place_invalid")
	await click(a.position)
	check("click on occupied builds nothing, stays in mode", mgr.is_placing() and houses() == 1)
	b.state = BuildingPlot.State.BLOCKED
	await mouse_to(b.position)
	await click(b.position)
	check("blocked plot rejected", mgr.is_placing() and houses() == 1 and b.state == BuildingPlot.State.BLOCKED)
	b.state = BuildingPlot.State.EMPTY
	await click(a.position + Vector3(14, 0, 0))
	check("click in the lane between plots builds nothing", mgr.is_placing() and houses() == 1)
	await mouse_to(a.position + Vector3(14, 0, 0))
	check("ghost hidden off plots", not mgr.get("_preview").visible)
	await mouse_to(b.position)
	await click(b.position)
	check("second House on another plot", houses() == 2 and b.state == BuildingPlot.State.OCCUPIED and not mgr.is_placing())
	var ground_ok := true
	for p in [a, b]:
		if absf(p.building.position.y - 2.2) > 0.001: ground_ok = false
	check("houses stand on the ground", ground_ok)
	await click(a.position)
	check("occupied plot can still be selected", map.get_selected_plot() == a and not a.is_buildable())
	await key(KEY_ESCAPE)
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
