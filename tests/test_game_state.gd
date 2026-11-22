# test_game_state.gd
# Spec tests: T14 (win), T15 (lose), T17 (boundaries). Win and lose thresholds,
# people leaving, the score, the goal line, the end screen and restarting.
# Run with a window:  <Godot> --path . --script res://tests/test_game_state.gd
extends SceneTree

const S := GameStateManager.State
const F := ResourceManager.Type.FOOD

var fails := 0
var main: Node
var game: GameStateManager
var pop: PopulationManager
var r: ResourceManager
var goal: Label


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


# A fresh colony with its timers stopped, so only this test moves time forward.
func new_game() -> void:
	if main != null:
		main.queue_free()
	paused = false
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	pop = main.get_node("PopulationManager")
	pop.get_node("UpkeepTimer").stop()
	game = main.get_node("GameStateManager")
	r = main.get_node("ResourceManager")
	goal = main.get_node("UI/GoalLabel")


func fill_storage() -> void:
	for type in ResourceManager.Type.values():
		r.add(type, 9999)


func end_text() -> String:
	var label: Label = game.get_node_or_null("EndScreen/Text")
	return "" if label == null else label.text


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	# Start of the game.
	await new_game()
	await process_frame
	check("starts in play", game.get_state() == S.PLAYING and not paused and end_text() == "")
	check("goal line shows the target and progress", goal.text == "Goal: 24 people (now 10) and happiness 70 (now 60)\nOr: build all 3 landmarks (0 done): Lighthouse, Harbour, Town Hall\nBoth need all 5 events faced first (0 so far)\nHOMES FULL (10/10): nobody new will join. Build a House (20 Wood, 10 Stone) for 4 more people", goal.text)
	check("score: 10 people x 10 + happiness 60 = 160", game.get_score() == 160, str(game.get_score()))

	# Lose by starvation: 6 hungry cycles in a row.
	r.spend({F: r.get_amount(F)})
	for i in 5:
		pop.upkeep()
	await process_frame
	check("5 hungry cycles: still playing", game.get_state() == S.PLAYING and game.get_starvation_seconds_left() == 10)
	check("starvation warning counts down", goal.text.contains("STARVING") and goal.text.contains("lost in 10 s"), goal.text)
	r.add(F, 100)
	pop.upkeep()
	check("one fed cycle resets the count", game.get_state() == S.PLAYING and game.get_starvation_seconds_left() == -1)
	# A fresh colony, so that people leaving does not empty it before it starves.
	await new_game()
	r.spend({F: r.get_amount(F)})
	for i in 5:
		pop.upkeep()
	check("5 more hungry cycles: still playing", game.get_state() == S.PLAYING)
	pop.upkeep()
	check("6th hungry cycle in a row: lost by starvation", game.get_state() == S.LOST and game.get_reason().contains("starved"), game.get_reason())
	check("1 person left during the famine (happiness reaches 0 on the 6th cycle)", pop.get_population() == 9, str(pop.get_population()))
	check("the game pauses and the end screen shows", paused and end_text().contains("COLONY LOST") and end_text().contains("Score") and end_text().contains("Press Enter"), end_text())
	var people := pop.get_population()
	pop.upkeep()
	check("nothing more happens after the game ends", pop.get_population() == people and game.get_state() == S.LOST)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key)
	await process_frame
	check("Enter on the end screen starts again (unpauses)", not paused)

	# Lose by full storage: all four at the limit for 6 cycles in a row.
	await new_game()
	for i in 5:
		fill_storage()
		pop.upkeep()
	await process_frame
	check("5 full cycles: still playing, with a warning", game.get_state() == S.PLAYING and goal.text.contains("STORAGE ALL FULL") and goal.text.contains("lose in 10 s"), goal.text)
	fill_storage()
	r.spend({ResourceManager.Type.GOLD: 1})
	pop.upkeep()
	check("one resource below the limit resets the count", game.get_storage_seconds_left() == -1 and game.get_state() == S.PLAYING)
	for i in 5:
		fill_storage()
		pop.upkeep()
	check("5 more full cycles: still playing", game.get_state() == S.PLAYING)
	fill_storage()
	pop.upkeep()
	check("6th full cycle in a row: lost by full storage", game.get_state() == S.LOST and game.get_reason().contains("Storage"), game.get_reason())

	# People leave while happiness is 0: civilians first, then workers.
	await new_game()
	var workers: WorkerManager = main.get_node("WorkerManager")
	var civilians: CivilianManager = main.get_node("CivilianManager")
	pop._happiness = 1
	r.spend({F: r.get_amount(F)})
	pop.upkeep()   # Hungry (-10): happiness 0.
	check("happiness 0: a civilian leaves first", pop.get_happiness() == 0 and civilians.get_count() == 3 and workers.get_workers().size() == 6)
	await process_frame
	check("warning that people are leaving", goal.text.contains("HAPPINESS IS 0"), goal.text)
	pop._happiness = 50
	pop.upkeep()
	check("nobody leaves while happiness is above 0", pop.get_population() == 9)
	# Starve the colony, clearing the starvation count each cycle so that only the
	# leaving rule is tested. (In normal play starvation ends the game first.)
	r.spend({F: r.get_amount(F)})
	for i in 3:
		pop._happiness = 0
		game._hungry_cycles = 0
		pop.upkeep()
	check("then the last civilians leave", civilians.get_count() == 0 and workers.get_workers().size() == 6)
	var last: Worker = workers.get_workers().back()
	last.repair_plot = main.get_node("MapManager").get_plot(1)
	game._hungry_cycles = 0
	pop.upkeep()
	check("a worker busy repairing does not leave", workers.get_workers().size() == 6)
	last.repair_plot = null
	for i in 5:
		game._hungry_cycles = 0
		pop.upkeep()
	check("workers leave one per cycle: 1 left, still playing", workers.get_workers().size() == 1 and game.get_state() == S.PLAYING)
	game._hungry_cycles = 0
	pop.upkeep()
	check("nobody left: lost", pop.get_population() == 0 and game.get_state() == S.LOST and game.get_reason().contains("Everyone has left"), game.get_reason())

	# Win: 24 people and happiness 70, for 3 cycles in a row.
	await new_game()
	civilians = main.get_node("CivilianManager")
	var builder: Node = main.get_node("BuildingManager")
	var plots: Array = main.get_node("MapManager").get_plots()
	builder.choose_building(0)
	for i in 4:
		builder._place_building(plots[i])
	for i in 13:
		civilians.add_civilian()
	check("23 people in the camp and 4 Houses", pop.get_population() == 23 and pop.get_homeless() == 0)
	pop._happiness = 100
	pop._good_cycles = -1000   # Holds growth back, so the numbers below stay exact.
	r.add(F, 200)
	pop.upkeep()
	check("23 people is not enough, even at happiness 100", game.get_win_cycles() == 0 and game.get_state() == S.PLAYING)
	civilians.add_civilian()
	pop._happiness = 67
	r.add(F, 200)
	pop.upkeep()
	check("24 people but happiness 69 is not enough", pop.get_population() == 24 and pop.get_happiness() == 69 and game.get_win_cycles() == 0)
	r.add(F, 200)
	pop.upkeep()
	r.add(F, 200)
	pop.upkeep()
	await process_frame
	check("24 people and happiness 70+: 2 cycles held, still playing", game.get_win_cycles() == 2 and game.get_state() == S.PLAYING)
	check("goal line says how long to hold", goal.text.contains("hold it for 10 more seconds"), goal.text)
	r.add(F, 200)
	pop.upkeep()
	await process_frame
	await process_frame
	check("3rd cycle, but no event has been faced: not won yet", game.get_state() == S.PLAYING and game.get_win_cycles() == 3 and goal.text.contains("Goal reached: keep it until every event has been faced"), goal.text)
	var events: EventManager = game.get_node("../EventManager")
	for type: EventManager.Type in [EventManager.Type.DISCOVERY, EventManager.Type.DROUGHT, EventManager.Type.TRADE, EventManager.Type.DISEASE]:
		events._faced[type] = true
	r.add(F, 200)
	pop.upkeep()
	check("four of the five events faced: still not won", events.get_faced_count() == 4 and game.get_state() == S.PLAYING)
	events._faced[EventManager.Type.MIGRATION] = true
	r.add(F, 200)
	pop.upkeep()
	check("all five faced and the goal still held: won", game.get_state() == S.WON and paused, game.get_reason())
	check("end screen shows the win and the score", end_text().contains("YOU WIN") and end_text().contains("Score %d" % game.get_score()), end_text())
	check("score: 24 x 10 + happiness 79 + 4 buildings x 5 = 339", game.get_score() == 339, str(game.get_score()))
	check("the win screen offers to keep playing", end_text().contains("N to keep playing"), end_text())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://game_won.png")

	# Keep playing after the win: no more winning or losing.
	var n_key := InputEventKey.new()
	n_key.physical_keycode = KEY_N
	n_key.pressed = true
	root.push_input(n_key)
	await process_frame
	await process_frame
	check("N keeps playing: free play, unpaused, end screen gone", game.get_state() == S.FREE_PLAY and not paused and end_text() == "")
	check("goal line shows free play", goal.visible and goal.text.contains("Free play"), goal.text)
	r.spend({F: r.get_amount(F)})
	for i in 8:
		pop.upkeep()
	check("free play cannot be lost, even after 8 hungry cycles", game.get_state() == S.FREE_PLAY and not paused)
	check("but people still leave at happiness 0", pop.get_happiness() == 0 and pop.get_population() < 24, str(pop.get_population()))

	# A dip resets the hold.
	await new_game()
	civilians = main.get_node("CivilianManager")
	builder = main.get_node("BuildingManager")
	plots = main.get_node("MapManager").get_plots()
	builder.choose_building(0)
	for i in 6:
		builder._place_building(plots[i])
	for i in 14:
		civilians.add_civilian()
	pop._happiness = 90
	for i in 2:
		r.add(F, 200)
		pop.upkeep()
	r.spend({F: r.get_amount(F)})
	pop._happiness = 70
	pop.upkeep()   # Hungry: happiness drops to 60.
	check("dropping below the target resets the hold", game.get_win_cycles() == 0 and game.get_state() == S.PLAYING)

	# Switched off, nothing ends (used by the other tests).
	game.enabled = false
	for i in 8:
		pop.upkeep()
	check("switched off: the game never ends", game.get_state() == S.PLAYING and not paused)

	# A real restart: the scene is loaded the way the game itself loads it.
	main.queue_free()
	main = null
	paused = false
	change_scene_to_file("res://scenes/Main.tscn")
	for i in 5:
		await process_frame
	var first := current_scene
	# The real game opens on the main menu. Choose "New Game", as a player would.
	var board: ControllerMenu = first.get_node("ControllerMenu")
	check("the real game opens on the start board, paused", board.get_mode() == ControllerMenu.Mode.START and paused)
	board.confirm()
	check("New Game begins play", not board.is_open() and not paused)
	first.get_node("EventManager/EventTimer").stop()
	var pop1: PopulationManager = first.get_node("PopulationManager")
	pop1.get_node("UpkeepTimer").stop()
	var r1: ResourceManager = first.get_node("ResourceManager")
	r1.spend({F: r1.get_amount(F)})
	for i in 6:
		pop1.upkeep()
	var game1: GameStateManager = first.get_node("GameStateManager")
	check("lost in the real scene", game1.get_state() == S.LOST and paused)
	check("goal line hides behind the end screen", not first.get_node("UI/GoalLabel").visible)
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter)
	for i in 10:
		await process_frame
	var second := current_scene
	check("Enter loads a brand new game", second != null and second != first and not paused)
	check("the start board is not shown again after a restart", not second.get_node("ControllerMenu").is_open())
	if second != null and second != first:
		var pop2: PopulationManager = second.get_node("PopulationManager")
		var game2: GameStateManager = second.get_node("GameStateManager")
		check("the new game starts fresh", pop2.get_population() == 10 and pop2.get_happiness() == 60 and second.get_node("ResourceManager").get_amount(F) == 150 and game2.get_state() == S.PLAYING and game2.get_node_or_null("EndScreen") == null)

	paused = false
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
