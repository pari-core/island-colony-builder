# test_migration_boat.gd
# Spec test: T12 (Migration). The ship that brings the newcomers: it waits at
# sea while the story is read, sails in, anchors off the eastern beach, lands
# the newcomers, and sails away again.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_migration_boat.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree

const S := MigrationBoat.Stage

var fails := 0
var main: Node


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func frames(count: int) -> void:
	for i in count:
		await process_frame


func shot(file: String, at: Vector3, from: Vector3) -> void:
	var camera: Camera3D = main.get_node("Camera3D")
	camera.set_process(false)
	camera.global_position = at + from
	camera.look_at(at + Vector3(0, 4, 0))
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/%s.png" % file)
	camera.set_process(true)


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await frames(2)
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("EventManager/EventTimer").stop()
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	menu.close_menu()
	main.get_tree().paused = false
	var events: EventManager = main.get_node("EventManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var boat: MigrationBoat = main.get_node("MigrationBoat")
	var story: StoryBox = main.get_node("UI/StoryBox")
	var beach := events.get_beach_position()

	check("no ship before a migration", not boat.visible and boat.get_stage() == S.AWAY)

	# ------------------------------------------------------------ It appears at sea
	events.trigger(EventManager.Type.MIGRATION)
	var newcomers := workers.get_workers().slice(6, 10)
	check("a migration puts the ship far out at sea, 260 m off the beach", boat.visible and boat.get_stage() == S.SAILING_IN and absf(boat.position.x - (beach.x + 260.0)) < 0.01, str(boat.position))
	check("the four newcomers are aboard", boat.get_passengers().size() == 4 and newcomers.all(func(n: Worker) -> bool: return n.aboard))
	check("they stand on the deck, not on the beach", absf(newcomers[0].model.position.x - boat.position.x) < 3.0 and newcomers[0].model.position.y > boat.position.y + 1.0, str(newcomers[0].model.position))
	check("the story opens and pauses the game", story.is_open() and paused)
	var waiting_at := boat.position.x
	await create_timer(0.5).timeout
	check("while the story is open the ship waits", boat.position.x == waiting_at)
	await shot("migration_ship_at_sea", boat.position, Vector3(-30, 16, 42))
	story.skip()
	await frames(2)
	check("the story closed, the game runs again", not story.is_open() and not paused)

	# ------------------------------------------------------------ It sails in
	await create_timer(3.0).timeout
	check("it sails towards the beach", boat.position.x < waiting_at - 40.0 and boat.get_stage() == S.SAILING_IN, "%.1f" % boat.position.x)
	check("the newcomers ride along on the deck", newcomers[0].aboard and absf(newcomers[0].model.position.x - boat.position.x) < 3.0)
	check("it rides the waves, close to the water", absf(boat.position.y - main.get_node("Island/Water").global_position.y) <= MigrationBoat.BOB_HEIGHT + 0.01)
	var t0 := Time.get_ticks_msec()
	while boat.get_stage() == S.SAILING_IN and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	check("it anchors 32 m off the beach", boat.get_stage() == S.LANDING and absf(boat.position.x - (beach.x + 32.0)) < 0.01, str(boat.position))

	# ------------------------------------------------------------ The newcomers land
	check("the newcomers step onto the beach", not newcomers[0].aboard and not newcomers[1].aboard and absf(newcomers[0].model.position.x - (beach.x - 2.0)) < 0.5, str(newcomers[0].model.position))
	await frames(2)
	await shot("migration_ship_landing", beach + Vector3(14, 0, 0), Vector3(-40, 22, 52))
	await create_timer(1.0).timeout
	check("and walk to the town", newcomers[0].model.position.x < beach.x - 5.0, str(newcomers[0].model.position))

	# ------------------------------------------------------------ It leaves
	t0 = Time.get_ticks_msec()
	while boat.get_stage() == S.LANDING and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	await create_timer(1.0).timeout
	check("after a short wait it sails away", boat.get_stage() == S.SAILING_OUT and boat.position.x > beach.x + 40.0, "%s %.1f" % [boat.get_stage(), boat.position.x])
	t0 = Time.get_ticks_msec()
	while boat.get_stage() != S.AWAY and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	check("and disappears out at sea", boat.get_stage() == S.AWAY and not boat.visible)

	# ------------------------------------------------------------ A full colony
	events.end_event(EventManager.Type.MIGRATION)
	while workers.get_workers().size() < WorkerManager.WORKER_LIST.size():
		workers.add_worker()
	events.trigger(EventManager.Type.MIGRATION)
	check("with no room for newcomers the ship still comes, carrying nobody ashore", boat.visible and boat.get_passengers().is_empty())
	story.skip()

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
