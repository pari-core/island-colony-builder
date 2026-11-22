# test_camera.gd
# Camera movement, rotation, zoom and limits, using simulated keys and mouse wheel.
# Run with a window (not headless):  <Godot> --path . --script res://tests/test_camera.gd
extends SceneTree

var fails := 0
var cam: Camera3D


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func hold(code: int, seconds: float) -> void:
	key(code, true)
	await create_timer(seconds).timeout
	key(code, false)
	await process_frame
	await process_frame


func wheel(button: int, count: int) -> void:
	for i in count:
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = button
			e.pressed = down
			Input.parse_input_event(e)
			await process_frame


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	cam = main.get_node("Camera3D")
	var terrain = main.get_node("Island/Terrain")
	const LIMIT_FOCUS := 450.0
	const MIN_ZOOM := 15.0
	const MAX_ZOOM := 430.0

	var before: Vector3 = cam.get("_focus")
	var forward := -Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z).normalized()
	await hold(KEY_W, 0.3)
	var moved: Vector3 = (cam.get("_focus") as Vector3) - before
	check("W moves the way the camera faces", moved.length() > 1.0 and moved.normalized().dot(forward) > 0.99)
	for pair in [[KEY_S, "S"], [KEY_A, "A"], [KEY_D, "D"], [KEY_UP, "Up"], [KEY_DOWN, "Down"], [KEY_LEFT, "Left"], [KEY_RIGHT, "Right"]]:
		before = cam.get("_focus")
		await hold(pair[0], 0.15)
		check(pair[1] + " moves", (cam.get("_focus") as Vector3).distance_to(before) > 0.5)
	var yaw: float = cam.get("_yaw")
	await hold(KEY_E, 0.2)
	check("E rotates", cam.get("_yaw") > yaw)
	yaw = cam.get("_yaw")
	await hold(KEY_Q, 0.2)
	check("Q rotates back", cam.get("_yaw") < yaw)

	var distance: float = cam.get("_target_distance")
	await wheel(MOUSE_BUTTON_WHEEL_UP, 3)
	check("wheel up zooms in", cam.get("_target_distance") < distance)
	distance = cam.get("_target_distance")
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 1)
	check("wheel down zooms out", cam.get("_target_distance") > distance)
	distance = cam.get("_target_distance")
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 3)
	Input.parse_input_event(pan)
	await process_frame
	check("trackpad swipe zooms", cam.get("_target_distance") > distance)
	distance = cam.get("_target_distance")
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.2
	Input.parse_input_event(pinch)
	await process_frame
	check("pinch zooms in", cam.get("_target_distance") < distance)

	await wheel(MOUSE_BUTTON_WHEEL_UP, 40)
	await create_timer(1.5).timeout
	check("closest zoom limit", is_equal_approx(cam.get("_target_distance"), MIN_ZOOM))
	var lowest := INF
	for code in [KEY_W, KEY_D, KEY_S, KEY_A]:
		key(code, true)
		for i in 60:
			await create_timer(0.1).timeout
			lowest = minf(lowest, cam.position.y - terrain.get_height_at(cam.position.x, cam.position.z))
		key(code, false)
		await process_frame
		check("view stays within %d m of the centre" % LIMIT_FOCUS, (cam.get("_focus") as Vector3).length() <= LIMIT_FOCUS + 0.01)
	check("camera stays above the ground (at least 5 m, v2: it may come low when zoomed in)", lowest >= 4.99, "lowest %.1f m" % lowest)
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 40)
	check("furthest zoom limit", is_equal_approx(cam.get("_target_distance"), MAX_ZOOM))

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
