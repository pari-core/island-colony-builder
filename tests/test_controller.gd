# test_controller.gd
# Playing with only the controller's inputs (their keyboard stand-ins): the build
# cursor, the building menu, the pause menu with "Start the next event now",
# answering events, and the win screen. The mouse is never used.
# Run with a window:  <Godot> --path . --script res://tests/test_controller.gd
extends SceneTree

var fails := 0


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func key(code: int, times := 1) -> void:
	for i in times:
		for down in [true, false]:
			var e := InputEventKey.new()
			e.physical_keycode = code
			e.pressed = down
			root.push_input(e)
			await process_frame
			await process_frame


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	# The events' stories are tested elsewhere; here they would pause the game.
	StoryBox.enabled = false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	main.get_node("PopulationManager/UpkeepTimer").stop()
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	var map: MapManager = main.get_node("MapManager")
	var builder: BuildingManager = main.get_node("BuildingManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var events: EventManager = main.get_node("EventManager")
	var state: GameStateManager = main.get_node("GameStateManager")
	var r: ResourceManager = main.get_node("ResourceManager")
	var cam: Camera3D = main.get_node("Camera3D")
	var panel: Control = main.get_node("UI/MenuPanel")
	var hint: Label = main.get_node("UI/HintLabel")
	var T := ResourceManager.Type
	state.enabled = false
	builder.mouse_enabled = false   # Someone may be using the mouse while this runs.

	# Nothing built yet.
	await key(KEY_TAB)
	check("Select with no buildings selects nothing", map.get_selected_plot() == null)
	await key(KEY_SPACE)
	check("Action with no buildings opens no menu", not menu.is_open() and not panel.visible)
	check("the hint line shows the free-play inputs", hint.text.contains("B: build") and hint.text.contains("M: menu"), hint.text)

	# Building with the cursor.
	await key(KEY_B)
	check("Build starts placement and locks the arrows", builder.is_placing() and cam.pad_locked)
	await key(KEY_RIGHT)
	var start := builder.get_cursor_plot()
	var nearest: BuildingPlot = null
	for plot in map.get_plots():
		if nearest == null or plot.position.distance_to(cam.get_focus()) < nearest.position.distance_to(cam.get_focus()):
			nearest = plot
	check("the first arrow puts the cursor on the empty square nearest the view", start != null and start == nearest and not builder.is_following_mouse(), str(start.position if start else null))
	# v2: the squares are scattered, so each arrow goes to the nearest square in
	# that direction on screen (within 45 degrees either side).
	var reached := {}
	var right_way := true
	var last: BuildingPlot = null
	for code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		await key(code)
		var now := builder.get_cursor_plot()
		reached[now] = true
		last = now
		var on_screen := cam.unproject_position(now.position) - cam.unproject_position(start.position)
		var wanted: Vector2 = { KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT }[code]
		if now == start or on_screen.normalized().dot(wanted) < 0.5:
			right_way = false
			print("  arrow %d: square %d at %s on screen" % [code, now.plot_id, on_screen])
		builder.set_cursor_plot(start)
		await process_frame
	check("the four arrows reach four different squares", reached.size() == 4)
	check("each arrow moves the cursor that way on screen", right_way)
	await create_timer(1.5).timeout
	check("the view glides to the square the cursor moved to", cam.get_focus().distance_to(Vector3(last.position.x, 0, last.position.z)) < 1.0, str(cam.get_focus()))
	await key(KEY_SPACE)
	check("Action opens the list of buildings for the square", menu.get_mode() == ControllerMenu.Mode.BUILD_PICK and panel.visible and builder.is_placing())
	var list := menu.get_item_texts()
	check("it lists the seven buildings and three landmarks with costs, then Back", list.size() == 11 and list[0] == "House  -  20 Wood, 10 Stone" and list[6].begins_with("Mine") and list[7] == "Lighthouse  -  150 Wood, 120 Stone, 40 Gold, 5 days to build" and list[9].begins_with("Town Hall") and list[10] == "Back to choosing a square", str(list))
	await key(KEY_UP, 5)
	check("Up wraps to the Mine and the preview follows", menu.get_highlight() == 6 and builder.get_chosen_building().name == "Mine")
	await key(KEY_BACKSPACE)
	check("Back returns to choosing a square", not menu.is_open() and builder.is_placing() and builder.get_cursor_plot() == start)
	r.spend({ T.WOOD: r.get_amount(T.WOOD) - 10 })
	await key(KEY_SPACE)
	await key(KEY_SPACE)
	check("a building that costs too much is refused with a reason", menu.is_open() and start.building == null and menu.get_message() == "Not enough resources for a Mine", menu.get_message())
	r.add(T.WOOD, 140)
	await key(KEY_DOWN, 6)
	check("Down wraps round to the Farm", menu.get_item_texts()[menu.get_highlight()].begins_with("Farm") and builder.get_chosen_building().name == "Farm")
	await key(KEY_SPACE)
	check("Action builds the Farm on the square", not menu.is_open() and not builder.is_placing() and start.building != null and start.building_info.name == "Farm")
	check("the arrows move the view again", not cam.pad_locked)
	await key(KEY_B)
	await key(KEY_BACKSPACE)
	check("Back cancels placement", not builder.is_placing())

	# The building menu.
	await key(KEY_TAB)
	check("Select jumps to the Farm", map.get_selected_plot() == start)
	await key(KEY_SPACE)
	check("Action opens the Farm's menu", menu.get_mode() == ControllerMenu.Mode.BUILDING and panel.visible and cam.pad_locked)
	var texts := menu.get_item_texts()
	check("the menu lists add, remove and close", texts.size() == 3 and texts[0].begins_with("Add a worker") and texts[1] == "Remove a worker" and texts[2] == "Close", str(texts))
	await key(KEY_SPACE, 2)
	check("Action twice adds two workers", workers.get_workers_at(start).size() == 2)
	await key(KEY_SPACE)
	check("a third is refused and the menu says why", workers.get_workers_at(start).size() == 2 and menu.get_message() == "No free place here")
	await key(KEY_DOWN)
	await key(KEY_SPACE)
	check("Down then Action removes one", menu.get_highlight() == 1 and workers.get_workers_at(start).size() == 1)
	await key(KEY_B)
	check("Build does nothing while a menu is open", not builder.is_placing() and menu.is_open())
	await key(KEY_UP, 2)
	check("Up wraps round to Close", menu.get_highlight() == 2)
	await key(KEY_SPACE)
	check("Close closes the menu and keeps the selection", not menu.is_open() and map.get_selected_plot() == start)
	await key(KEY_SPACE)
	await key(KEY_BACKSPACE)
	check("Back closes the menu too", not menu.is_open() and map.get_selected_plot() == start)
	await key(KEY_BACKSPACE)
	check("Back again clears the selection", map.get_selected_plot() == null)

	# The pause menu.
	await key(KEY_M)
	check("Menu pauses the game", menu.get_mode() == ControllerMenu.Mode.PAUSE and paused)
	texts = menu.get_item_texts()
	var next_event := -1
	var rotate := -1
	for i in texts.size():
		if texts[i].begins_with("Start the next event now: Resource discovery") or texts[i].begins_with("Start the next event now:"): next_event = i
		if texts[i] == "Rotate view right": rotate = i
	check("it lists the next event and the view", next_event == 1 and rotate > 0, str(texts))
	texts = menu.get_item_texts()
	var yaw: float = cam.get_yaw()
	await key(KEY_DOWN, texts.find("Rotate view right") - menu.get_highlight())
	await key(KEY_SPACE)
	check("Rotate view right turns the view 45 degrees while paused", absf(cam.get_yaw() - yaw - PI / 4.0) < 0.001)
	await key(KEY_UP, menu.get_highlight() - 1)
	check("the highlight is on the next event", menu.get_item_texts()[menu.get_highlight()].begins_with("Start the next event now"))
	await key(KEY_SPACE)
	check("it starts the event, closes the menu and resumes", events.get_active().size() == 1 and not menu.is_open() and not paused)
	await key(KEY_M)
	await key(KEY_DOWN)
	await key(KEY_SPACE)
	check("a second event is refused while one is happening", events.get_active().size() == 1 and menu.is_open())
	await key(KEY_M)
	check("Menu again closes it and resumes", not menu.is_open() and not paused)

	# Answering events with Action and Back.
	for event in events.get_active().duplicate():
		events._end(event)
	events.trigger(EventManager.Type.TRADE)
	var wood := r.get_amount(T.WOOD)
	var half: int = events.get_trade_offers()[0].give[T.WOOD]   # Fixed when the ship arrived.
	await key(KEY_SPACE)
	check("Action accepts a trade (the timber offer: half the wood)", not events.is_active(EventManager.Type.TRADE) and r.get_amount(T.WOOD) == wood - half)
	events.trigger(EventManager.Type.TRADE)
	await key(KEY_BACKSPACE)
	check("Back declines a trade", not events.is_active(EventManager.Type.TRADE) and r.get_amount(T.WOOD) == wood - half)

	# The start board. Pointed at a file that does not exist, so a game the player
	# has saved does not add "Continue saved game" to it.
	menu.get_node("../SaveManager").save_path = "user://no_such_save.json"
	menu.open_start_menu()
	await process_frame
	check("the main menu pauses the game", paused and str(menu.get_item_texts()) == str(["Quick Game (8 min)", "Full Game", "How to Play", "Settings", "Credits", "Quit"]), str(menu.get_item_texts()))
	await key(KEY_BACKSPACE)
	check("Back does not skip the start board", menu.get_mode() == ControllerMenu.Mode.START)
	await key(KEY_SPACE)
	check("New Game begins play", not menu.is_open() and not paused)

	# The win screen.
	state._finish(GameStateManager.State.WON, "test")
	await process_frame
	await key(KEY_M)
	check("Menu does nothing on the win screen", not menu.is_open())
	await key(KEY_BACKSPACE)
	check("Back keeps playing after a win", state.get_state() == GameStateManager.State.FREE_PLAY and not paused)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
