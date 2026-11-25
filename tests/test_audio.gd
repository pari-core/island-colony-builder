# test_audio.gd
# Music and sound effects: the music loops all game, and building, events, winning
# and losing each play their own sound.
# Run with a window:  <Godot> --path . --script res://tests/test_audio.gd
extends SceneTree

var fails := 0


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func run() -> void:
	DayNight.enabled = false
	StoryBox.enabled = false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	main.get_node("ControllerLink").enabled = false
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("ControllerMenu").close_menu()
	paused = false
	main.get_node("EventManager/EventTimer").stop()
	var audio: AudioManager = main.get_node("AudioManager")
	var builder: BuildingManager = main.get_node("BuildingManager")
	var state: GameStateManager = main.get_node("GameStateManager")

	check("the calm music is playing", audio.is_music_playing())
	for name in AudioManager.SOUNDS:
		check("the %s sound loads" % name, AudioManager.SOUNDS[name] != null and AudioManager.SOUNDS[name].get_length() > 0.05)

	builder.start_placement()
	builder.set_cursor_plot(main.get_node("MapManager").get_plots()[0])
	builder.confirm_placement()
	await process_frame
	check("placing a building plays the build sound", "build" in audio.get_played(), str(audio.get_played()))

	main.get_node("EventManager").trigger(EventManager.Type.DISCOVERY)
	await process_frame
	check("a new event plays the event bell", "event" in audio.get_played(), str(audio.get_played()))

	state._finish(GameStateManager.State.WON, "test")
	state.state_changed.emit()
	await process_frame
	check("winning plays the win sound", audio.get_played().back() == "win", str(audio.get_played()))
	check("the music keeps playing on the end screen", audio.is_music_playing())

	state._finish(GameStateManager.State.LOST, "test")
	state.state_changed.emit()
	await process_frame
	check("losing plays the lose sound", audio.get_played().back() == "lose", str(audio.get_played()))

	print("RESULT fails=%d" % fails)
	quit(fails)
