# test_buildings.gd
# Spec tests: T08. Choosing each building with keys 1 to 6, placing it, charging its cost and fitting its plot.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_buildings.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
# Chooses each building with its number key and places all six.
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
func hover(point: Vector3) -> void:
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
	var p := cam.unproject_position(point) * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	for down in [true, false]:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
		Input.parse_input_event(e)
		await process_frame
		await process_frame
func shot(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
func footprint(n: Node, parent: Transform3D, box: Array) -> void:
	var xf := parent
	if n is Node3D: xf = parent * n.transform
	if n is MeshInstance3D and n.mesh:
		var b: AABB = xf * n.get_aabb()
		box[0] = b if box[0] == null else box[0].merge(b)
	for c in n.get_children(): footprint(c, xf, box)
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
	var map: Node = main.get_node("MapManager"); var mgr: Node = main.get_node("BuildingManager"); cam = main.get_node("Camera3D")
	var r: ResourceManager = main.get_node("ResourceManager"); var label: Label = main.get_node("UI/PlacementLabel")
	var plots: Array = map.get_plots()
	cam.set("_focus", Vector3(0, 0, 0)); cam.set("_distance", 230.0); cam.set("_target_distance", 230.0)
	await create_timer(0.8).timeout
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
	# v2: the corner panels cover parts of the screen, so use six squares that can
	# be seen and clicked.
	var hud: Hud = main.get_node("UI/HUD")
	var targets := []
	for i in plots.size():
		var on_screen := cam.unproject_position(plots[i].position)
		if targets.size() < 6 and get_root().get_visible_rect().grow(-40.0).has_point(on_screen) and not hud.covers(on_screen):
			targets.append(i)
	var names := ["House", "Farm", "Lumber Camp", "Quarry", "Warehouse", "Research Lab"]
	await key(KEY_1)
	check("number key outside placement does nothing", mgr.get_chosen_building().name == "House" and not mgr.is_placing())
	for i in 6:
		var p: BuildingPlot = plots[targets[i]]
		var before := [r.get_amount(ResourceManager.Type.WOOD), r.get_amount(ResourceManager.Type.STONE), r.get_amount(ResourceManager.Type.GOLD)]
		await key(KEY_B)
		await key(keys[i])
		check("key %d chooses %s" % [i + 1, names[i]], mgr.get_chosen_building().name == names[i] and label.text.contains("[%d %s]" % [i + 1, names[i]]))
		await hover(p.position)
		check(names[i] + " previews green", p.preview == BuildingPlot.Preview.VALID)
		if i == 1:
			await shot("six_menu")
		await click(p.position)
		var cost: Dictionary = mgr.BUILDINGS[i].cost
		var ok: bool = p.building != null and p.state == BuildingPlot.State.OCCUPIED
		ok = ok and r.get_amount(ResourceManager.Type.WOOD) == before[0] - cost.get(ResourceManager.Type.WOOD, 0)
		ok = ok and r.get_amount(ResourceManager.Type.STONE) == before[1] - cost.get(ResourceManager.Type.STONE, 0)
		ok = ok and r.get_amount(ResourceManager.Type.GOLD) == before[2] - cost.get(ResourceManager.Type.GOLD, 0)
		check(names[i] + " builds and charges its cost", ok, "wood %d stone %d gold %d" % [r.get_amount(ResourceManager.Type.WOOD), r.get_amount(ResourceManager.Type.STONE), r.get_amount(ResourceManager.Type.GOLD)])
		# Measured in the building's own directions, since buildings are turned with
		# their squares (v2).
		var box := [null]
		for part in p.building.get_children():
			footprint(part, Transform3D.IDENTITY, box)
		var c: AABB = box[0]
		var half := 12.0
		var fits := c.position.x >= -half and c.end.x <= half and c.position.z >= -half and c.end.z <= half
		check(names[i] + " fits its plot, sits on ground", fits and absf(c.position.y) < 0.2, "size %.1f x %.1f, %.1f tall, bottom %.2f" % [c.size.x, c.size.z, c.size.y, c.position.y])
	check("no resource went negative", r.get_amount(ResourceManager.Type.WOOD) >= 0 and r.get_amount(ResourceManager.Type.STONE) >= 0 and r.get_amount(ResourceManager.Type.GOLD) >= 0)
	await key(KEY_B)
	await key(KEY_6)
	await key(KEY_1)
	await hover(plots[0].position)
	check("chosen building changes during preview", mgr.get_chosen_building().name == "House")
	await key(KEY_ESCAPE)
	await shot("six_wide")
	print("prim %.2fM draws %d vram %d MB" % [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	for i in 6:
		var p: BuildingPlot = plots[targets[i]]
		cam.set("_focus", p.position * Vector3(1, 0, 1)); cam.set("_distance", 50.0); cam.set("_target_distance", 50.0)
		await create_timer(0.6).timeout
		await shot("six_" + str(i))
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
