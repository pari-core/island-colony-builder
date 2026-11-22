# test_day_night.gd
# Day and night: the sun's path, the moonlit night, the sky's colours, the
# smooth handover at dusk and dawn, the time of day in the top bar, and the
# storm's darker light still showing through.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_day_night.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree

var fails := 0
var main: Node
var time: TimeManager
var day_night: DayNight


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


# Moves the clock to this point of the second turn of the sky (0 is sunrise)
# and applies the light.
func set_phase(phase: float) -> void:
	time._days = (1.0 + phase - DayNight.START) * DayNight.CYCLE_DAYS
	day_night.apply()


func brightness(colour: Color) -> float:
	return (colour.r + colour.g + colour.b) / 3.0


func shot(file: String) -> void:
	main.get_node("ControllerMenu").close_menu()
	main.get_tree().paused = false
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/%s.png" % file)


func run() -> void:
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	DayNight.enabled = true
	StoryBox.enabled = false
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("EventManager/EventTimer").stop()
	main.get_node("ControllerMenu").close_menu()
	main.get_tree().paused = false
	time = main.get_node("TimeManager")
	time.set_process(false)          # The test sets the time itself.
	day_night = main.get_node("DayNight")
	var sun: DirectionalLight3D = main.get_node("Sun")
	var sky: ProceduralSkyMaterial = main.get_node("WorldEnvironment").environment.sky.sky_material
	var effects: EventEffects = main.get_node("EventEffects")
	var full := effects.sun_energy

	# ------------------------------------------------------------ The start
	check("one turn of the sky lasts 5 in-game days: 100 seconds", DayNight.CYCLE_DAYS * TimeManager.DAY_SECONDS == 100.0)
	check("the game starts mid-morning, in full daylight", time.get_days() < 0.01 and absf(day_night.get_phase() - DayNight.START) < 0.01 and day_night.get_daylight() == 1.0 and day_night.get_time_name() == "morning", "days %.4f phase %.3f light %.2f %s" % [time.get_days(), day_night.get_phase(), day_night.get_daylight(), day_night.get_time_name()])

	# ------------------------------------------------------------ The sun's path
	set_phase(0.1)
	var morning_height := -sun.rotation_degrees.x
	var morning_turn := sun.rotation_degrees.y
	set_phase(DayNight.DAY_PART * 0.5)
	check("at midday the sun is 45 degrees up, at full strength", absf(-sun.rotation_degrees.x - 45.0) < 0.1 and absf(sun.light_energy - full) < 0.01, "%.1f %.2f" % [-sun.rotation_degrees.x, sun.light_energy])
	check("it is lower in the morning", morning_height < 40.0 and morning_height > DayNight.LOW_ELEVATION, "%.1f" % morning_height)
	set_phase(0.6)
	check("and moves across the sky from morning to evening", sun.rotation_degrees.y > morning_turn + 60.0, "%.1f to %.1f" % [morning_turn, sun.rotation_degrees.y])
	check("the evening sun is warmer (more red than blue)", sun.light_color.r - sun.light_color.b > 0.2, str(sun.light_color))

	# ------------------------------------------------------------ Night
	set_phase(0.85)
	check("at night: moonlight, blue, dimmer than day but not dark", day_night.is_night() and sun.light_color.b > sun.light_color.r and sun.light_energy < full * 0.6 and sun.light_energy >= full * 0.4, "%.2f" % sun.light_energy)
	check("the moon stands high, so it lights the land from above", -sun.rotation_degrees.x > 30.0)
	var night_sky := brightness(sky.sky_top_color)
	set_phase(0.35)
	check("the night sky is much darker than the day sky", night_sky < brightness(sky.sky_top_color) * 0.5, "%.2f vs %.2f" % [night_sky, brightness(sky.sky_top_color)])
	check("time names: dawn, morning, afternoon, evening, night", _names() == ["dawn", "morning", "afternoon", "evening", "night"], str(_names()))

	# ------------------------------------------------------------ Smooth changes
	var biggest_jump := 0.0
	var dimmest := INF
	set_phase(0.0)
	var last := sun.light_energy
	for i in range(1, 1001):
		set_phase(i / 1000.0)
		biggest_jump = maxf(biggest_jump, absf(sun.light_energy - last))
		dimmest = minf(dimmest, sun.light_energy)
		last = sun.light_energy
	check("the light never jumps: no step bigger than 3% across the whole day", biggest_jump < full * 0.03, "%.3f" % biggest_jump)
	check("it never goes black: the dimmest moment is 30% of daylight", absf(dimmest - full * DayNight.TWILIGHT_LIGHT) < 0.01, "%.2f" % dimmest)
	set_phase(0.67)
	check("the horizon glows orange at dusk", sky.sky_horizon_color.r > sky.sky_horizon_color.b, str(sky.sky_horizon_color))

	# ------------------------------------------------------------ It follows the clock
	time.set_process(true)
	set_phase(0.3)
	var before := sun.rotation_degrees.y
	await create_timer(1.0).timeout
	check("as time passes the sun moves", sun.rotation_degrees.y > before + 1.0, "%.1f to %.1f" % [before, sun.rotation_degrees.y])
	main.get_tree().paused = true
	await process_frame
	before = sun.rotation_degrees.y
	await create_timer(0.5).timeout
	check("while the game is paused the sky stands still", sun.rotation_degrees.y == before)
	main.get_tree().paused = false
	time.set_process(false)

	# ------------------------------------------------------------ The top bar
	var label: Label = _find_bar()
	set_phase(0.85)
	await process_frame
	await process_frame
	check("the top bar says it is night", label != null and label.text.begins_with("Day %d, night" % time.get_day()), "" if label == null else label.text.left(20))

	# ------------------------------------------------------------ With the weather
	var events: EventManager = main.get_node("EventManager")
	set_phase(0.35)
	var clear_day := sun.light_energy
	events.trigger(EventManager.Type.STORM)
	await create_timer(EventEffects.WEATHER_SECONDS + 0.3).timeout
	set_phase(0.35)
	check("a storm by day is still dark", sun.light_energy < clear_day * 0.4, "%.2f" % sun.light_energy)
	events.end_event(EventManager.Type.STORM)
	await create_timer(EventEffects.WEATHER_SECONDS + 0.3).timeout

	# ------------------------------------------------------------ Pictures
	time.set_process(false)
	for item in [[0.6, "day_night_evening"], [0.85, "day_night_night"]]:
		set_phase(item[0])
		await shot(item[1])
		set_phase(item[0])

	# ------------------------------------------------------------ Switched off
	DayNight.enabled = false
	set_phase(0.85)
	check("switched off (as in the other tests), it is always midday", day_night.get_daylight() == 1.0 and absf(sun.light_energy - full) < 0.01 and day_night.get_time_name() == "day")

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _names() -> Array:
	var names := []
	for phase in [0.03, 0.2, 0.4, 0.6, 0.85]:
		set_phase(phase)
		names.append(day_night.get_time_name())
	return names


func _find_bar() -> Label:
	for node in main.get_node("UI").find_children("*", "Label", true, false):
		if (node as Label).text.begins_with("Day "):
			return node
	return null
