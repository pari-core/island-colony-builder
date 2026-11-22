# test_workers.gd
# Spec tests: T05, T09. Jobs, worker slots, one job per worker, sliding to jobs, production amounts and timer.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_workers.gd
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
func build(number_key: int, p: BuildingPlot) -> void:
	await key(KEY_B); await key(number_key); await hover(p.position); await click(p.position)
func arrive(w: WorkerManager) -> void:
	var t0 := Time.get_ticks_msec()
	while w.get_workers().any(func(x): return x.is_moving()) and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
func perf(label: String) -> void:
	await create_timer(1.0).timeout
	print("%s prim %.2fM draws %d vram %d MB cpu %.2f ms" % [label, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576, RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())])
func shot(n: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + n + ".png")
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
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var map: Node = main.get_node("MapManager"); var w: WorkerManager = main.get_node("WorkerManager"); cam = main.get_node("Camera3D")
	var r: ResourceManager = main.get_node("ResourceManager"); var panel: Label = main.get_node("UI/SelectionLabel")
	var T := ResourceManager.Type
	var plots: Array = map.get_plots()
	cam.set("_focus", Vector3.ZERO); cam.set("_distance", 230.0); cam.set("_target_distance", 230.0)
	await create_timer(0.8).timeout
	check("six workers, all idle", w.get_workers().size() == 6 and w.get_idle_count() == 6)
	var farm: BuildingPlot = plots[1]; var lumber: BuildingPlot = plots[5]; var quarry: BuildingPlot = plots[6]; var house: BuildingPlot = plots[2]
	await build(KEY_2, farm); await build(KEY_3, lumber); await build(KEY_4, quarry); await build(KEY_1, house)
	var start := [r.get_amount(T.FOOD), r.get_amount(T.WOOD), r.get_amount(T.STONE)]
	w.produce()
	check("nothing produced without workers", r.get_amount(T.FOOD) == start[0] and r.get_amount(T.WOOD) == start[1] and r.get_amount(T.STONE) == start[2])
	check("house has no slots, refuses", not w.assign_worker(house) and w.get_idle_count() == 6)
	check("empty plot refuses", not w.assign_worker(plots[9]))
	await click(farm.position)
	check("panel shows selected building", panel.visible and panel.text.contains("Farm") and panel.text.contains("Workers 0/2"), panel.text.replace("\n", " / "))
	await key(KEY_J)
	var asha: Worker = w.get_workers()[0]
	var from: Vector3 = asha.model.position
	check("J assigns Asha, on the way", asha.job_plot == farm and w.get_idle_count() == 5 and panel.text.contains("on the way") and asha.is_moving(), panel.text.replace("\n", " / "))
	check("no output before arriving", w.get_output(farm) == 0)
	var fb := r.get_amount(T.FOOD)
	w.produce()
	check("walking worker produces nothing", r.get_amount(T.FOOD) == fb)
	await create_timer(0.5).timeout
	var moved: float = asha.model.position.distance_to(from)
	check("slides at about 12 m/s", moved > 4.0 and moved < 8.0, "%.1f m in 0.5 s" % moved)
	check("stays on the ground", absf(asha.model.position.y - 2.2) < 0.001)
	cam.set("_focus", asha.model.position * Vector3(1, 0, 1)); cam.set("_distance", 30.0); cam.set("_target_distance", 30.0)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "worker_moving.png")
	cam.set("_focus", Vector3.ZERO); cam.set("_distance", 230.0); cam.set("_target_distance", 230.0)
	await arrive(w)
	await create_timer(0.8).timeout
	check("arrives and gives output (Farm x1.5: 5 -> 7)", not asha.is_moving() and w.get_output(farm) == 7 and not panel.text.contains("on the way"), panel.text.replace("\n", " / "))
	await key(KEY_J)
	await arrive(w)
	check("second worker fills farm (9 -> 13)", w.get_output(farm) == 13 and w.get_workers_at(farm).size() == 2)
	await key(KEY_J)
	check("third refused, slots full", w.get_workers_at(farm).size() == 2 and w.get_idle_count() == 4)
	await arrive(w)
	check("worker stands on plot", w.get_workers()[0].model.position.distance_to(farm.position + Vector3(-10, -0.1, 10).rotated(Vector3.UP, farm.rotation.y)) < 0.01)
	await key(KEY_K)
	check("removed worker heads back", w.get_workers()[1].is_moving())
	await arrive(w)
	check("K removes latest", w.get_workers()[1].is_idle() and w.get_output(farm) == 7)
	await click(lumber.position); await key(KEY_J)
	await click(quarry.position); await key(KEY_J)
	await click(farm.position); await key(KEY_J)
	await arrive(w)
	await create_timer(0.8).timeout
	var idle := true
	for x in w.get_workers():
		if x.is_idle(): pass
	check("each worker has one job", w.get_workers().filter(func(x): return not x.is_idle()).size() == 4)
	check("output fixed by worker", w.get_output(farm) == 12 and w.get_output(lumber) == 4 and w.get_output(quarry) == 4, "farm %d lumber %d quarry %d" % [w.get_output(farm), w.get_output(lumber), w.get_output(quarry)])
	# Leave room below the storage limit, so the amounts added are exact.
	r.spend({T.FOOD: 100})
	var f0 := r.get_amount(T.FOOD); var w0 := r.get_amount(T.WOOD); var s0 := r.get_amount(T.STONE)
	w.produce()
	check("one cycle adds exact amounts", r.get_amount(T.FOOD) == f0 + 12 and r.get_amount(T.WOOD) == w0 + 4 and r.get_amount(T.STONE) == s0 + 4)
	w.produce()
	check("second cycle is identical", r.get_amount(T.FOOD) == f0 + 24 and r.get_amount(T.WOOD) == w0 + 8 and r.get_amount(T.STONE) == s0 + 8)
	var f1 := r.get_amount(T.FOOD)
	var t0 := Time.get_ticks_msec()
	while r.get_amount(T.FOOD) == f1 and Time.get_ticks_msec() - t0 < 7000:
		await process_frame
	check("timer produces on its own", r.get_amount(T.FOOD) == f1 + 12, "after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	r.add(T.FOOD, 500)
	w.produce()
	check("production respects storage limit", r.get_amount(T.FOOD) == r.get_capacity())
	await key(KEY_ESCAPE)
	check("panel hides with no selection", not panel.visible)
	await key(KEY_J)
	check("J with no selection does nothing", w.get_workers().filter(func(x): return not x.is_idle()).size() == 4)
	# v2: click an empty square that is on screen and not under a corner panel.
	var hud: Hud = main.get_node("UI/HUD")
	var empty: BuildingPlot = null
	for p in plots:
		var pixel := cam.unproject_position(p.position)
		if empty == null and p.building == null and get_root().get_visible_rect().grow(-20.0).has_point(pixel) and not hud.covers(pixel):
			empty = p
	await click(empty.position)
	check("empty plot panel", panel.text.contains("Empty"), panel.text)
	await key(KEY_ESCAPE)
	await perf("4 working 2 idle, start distance")
	var meshes := []
	for x in w.get_workers(): x.model.visible = false
	await perf("workers hidden")
	for x in w.get_workers(): x.model.visible = true
	cam.set("_focus", Vector3.ZERO); cam.set("_distance", 30.0); cam.set("_target_distance", 30.0)
	await create_timer(0.6).timeout
	await perf("closest zoom, on idle workers")
	await shot("workers_idle")
	await click(farm.position)
	cam.set("_focus", farm.position * Vector3(1, 0, 1)); cam.set("_distance", 40.0); cam.set("_target_distance", 40.0)
	await create_timer(0.6).timeout
	await perf("close to farm")
	await shot("workers_farm")
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
