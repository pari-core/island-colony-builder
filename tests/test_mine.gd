# test_mine.gd
# Spec tests: T05, T08. The gold Mine: choosing it, its cost, gold output and size.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_mine.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree
var fails := 0
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
func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("EventManager/EventTimer").stop()
	var mgr: Node = main.get_node("BuildingManager"); var w: WorkerManager = main.get_node("WorkerManager"); var r: ResourceManager = main.get_node("ResourceManager")
	var map: Node = main.get_node("MapManager"); var label: Label = main.get_node("UI/PlacementLabel")
	var mine: BuildingPlot = map.get_plots()[4]
	await key(KEY_B); await key(KEY_7)
	check("key 7 chooses the Mine", mgr.get_chosen_building().name == "Mine" and label.text.contains("[7 Mine]") and label.text.contains("30 Wood, 15 Stone"), label.text.replace("\n", " / "))
	await key(KEY_ESCAPE)
	var wood := r.get_amount(ResourceManager.Type.WOOD)
	check("Mine affordable at the start", r.can_afford(mgr.get_chosen_building().cost))
	mgr._place_building(mine)
	w.assign_worker(mine); w.assign_worker(mine)
	for x in w.get_workers(): x.model.position = x.target_position
	check("2 workers (5 + 4) make 3 gold: 9 x 0.4, fractions dropped", w.get_output(mine) == 3, str(w.get_output(mine)))
	var gold := r.get_amount(ResourceManager.Type.GOLD)
	w.produce()
	check("a cycle adds 3 gold", r.get_amount(ResourceManager.Type.GOLD) == gold + 3)
	var box := [null]
	var f := func(n: Node, xf: Transform3D, me: Callable) -> void:
		var t := xf
		if n is Node3D: t = xf * n.transform
		if n is MeshInstance3D and n.mesh:
			var b: AABB = t * n.get_aabb()
			box[0] = b if box[0] == null else box[0].merge(b)
		for c in n.get_children(): me.call(c, t, me)
	f.call(mine.building, Transform3D.IDENTITY, f)
	var bb: AABB = box[0]
	bb.position -= mine.building.position
	check("Mine fits its plot", bb.position.x >= -12 and bb.end.x <= 12 and bb.position.z >= -12 and bb.end.z <= 12 and absf(bb.position.y) < 0.3, str(bb))
	var cam = main.get_node("Camera3D")
	cam.set("_focus", mine.position * Vector3(1, 0, 1)); cam.set("_distance", 50.0); cam.set("_target_distance", 50.0)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mine.png")
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
