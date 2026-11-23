# test_event_puzzles.gd
# A different puzzle before every event (team request, 2026-11-23), the 5-minute
# Quick Game, and the one-card event messages.
# Run with a window:  <Godot> --path . --script res://tests/test_event_puzzles.gd
extends SceneTree

var fails := 0


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


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
	var events: EventManager = main.get_node("EventManager")
	events.get_node("EventTimer").stop()
	main.get_node("PopulationManager/UpkeepTimer").stop()
	var puzzles: EventPuzzles = main.get_node("UI/EventPuzzles")
	var memory: GoldPuzzle = main.get_node("UI/GoldPuzzle")
	var r: ResourceManager = main.get_node("ResourceManager")
	var T := ResourceManager.Type
	var E := EventManager.Type

	# Puzzles never open by themselves: the event starts straight away.
	check("no puzzle is open when the game starts", not puzzles.is_open() and not paused)
	events._next_index = EventManager.ORDER.find(E.ACCIDENT)
	events._start_scheduled_event()
	check("a scheduled event starts without opening a puzzle", events.is_active(E.ACCIDENT) and not puzzles.is_open() and not paused)
	events.end_event(E.ACCIDENT)
	await process_frame

	# One puzzle before each event, whenever the player likes: Builder's Sums
	# before the accident.
	events._next_index = EventManager.ORDER.find(E.ACCIDENT)
	check("the next event's puzzle can be played", puzzles.can_play() and puzzles.get_next_title() == "Builder's Sums", puzzles.get_next_title())
	var hud: Hud = main.get_node("UI/HUD")
	await process_frame
	var button: Button = hud.get_node("Toolbar/PuzzleButton")
	check("the toolbar's Puzzle button is ready, and says what it earns", not button.disabled and button.text == "Puzzle" and button.tooltip_text.contains("15 Stone"), button.tooltip_text)
	button.pressed.emit()
	check("the button opens Builder's Sums and pauses the game", puzzles.is_open() and puzzles.get_kind() == "sums" and paused)
	var stone := r.get_amount(T.STONE)
	for i in 3:
		puzzles.pick(puzzles.get_answer())
		await wait(1.1)
	check("three right sums earn 45 stone", r.get_amount(T.STONE) == stone + 45 and puzzles.get_earned() == 45, "%d -> %d" % [stone, r.get_amount(T.STONE)])
	puzzles.close()
	await process_frame
	await process_frame
	check("closing it unpauses, and no event starts", not puzzles.is_open() and not paused and events.get_active().is_empty())
	check("it can only be played once before the event", not puzzles.can_play() and not puzzles.play_next() and button.disabled and button.text == "Played")
	events._start_scheduled_event()
	await process_frame
	await process_frame
	check("when the event starts, the next event's puzzle unlocks", events.is_active(E.ACCIDENT) and puzzles.can_play() and puzzles.get_next_title() == "Find the Sick Plant" and not button.disabled, puzzles.get_next_title())
	events.end_event(E.ACCIDENT)

	# Rain Dance (before the drought): watch, then repeat.
	puzzles.open(E.DROUGHT)
	check("Rain Dance first shows the pattern", puzzles.is_showing_pattern())
	var food := r.get_amount(T.FOOD)
	puzzles.pick(0)
	check("picks are ignored while the pattern shows", r.get_amount(T.FOOD) == food)
	while puzzles.is_showing_pattern():
		await wait(0.2)
	for i in EventPuzzles.SEQUENCE_LENGTH:
		puzzles.pick(puzzles.get_answer())
		await wait(1.1)
	check("repeating all 4 steps earns 40 food", r.get_amount(T.FOOD) == mini(food + 40, r.get_capacity()), "%d -> %d" % [food, r.get_amount(T.FOOD)])
	puzzles.close()

	# Rain Dance: a wrong step ends it.
	puzzles.open(E.DROUGHT)
	while puzzles.is_showing_pattern():
		await wait(0.2)
	puzzles.pick((puzzles.get_answer() + 1) % 4)
	await wait(1.1)
	check("a wrong step ends Rain Dance with nothing earned", puzzles.get_earned() == 0 and puzzles.get_round() >= EventPuzzles.SEQUENCE_LENGTH)
	puzzles.close()

	# Find the Sick Plant: one wrong, two right.
	var gold := r.get_amount(T.GOLD)
	puzzles.open(E.DISEASE)
	puzzles.pick((puzzles.get_answer() + 1) % EventPuzzles.ODD_GRID)
	await wait(1.1)
	for i in 2:
		puzzles.pick(puzzles.get_answer())
		await wait(1.1)
	check("Find the Sick Plant: 2 of 3 right earns 10 gold", r.get_amount(T.GOLD) == gold + 10, "%d -> %d" % [gold, r.get_amount(T.GOLD)])
	puzzles.close()

	# Newcomers' Words: the right option is the real word.
	puzzles.open(E.MIGRATION)
	var words: Array[String] = []
	for set: Array in EventPuzzles.WORDS:
		words.append(EventPuzzles._title_case(set[0]))
	var shown: String = puzzles._rounds[0].options[puzzles.get_answer()]
	check("Newcomers' Words: the answer is a real colony word", shown in words, shown)
	check("the scrambled word is not the answer as written", not puzzles._question.text.ends_with(shown.to_upper()), puzzles._question.text)
	puzzles.close()
	check("Skip closes a puzzle at once", not puzzles.is_open() and not paused)

	# Storm Watch: count the houses.
	var wood := r.get_amount(T.WOOD)
	puzzles.open(E.STORM)
	var homes: int = puzzles._rounds[0].field.count("home")
	check("Storm Watch shows 12 pictures, and the answer is the number of houses", puzzles._field.visible and puzzles._field.get_child_count() == 12 and int(puzzles._rounds[0].options[puzzles.get_answer()]) == homes, "%d houses" % homes)
	for i in 3:
		puzzles.pick(puzzles.get_answer())
		await wait(1.1)
	check("three right counts earn 45 wood", r.get_amount(T.WOOD) == mini(wood + 45, r.get_capacity()), "%d -> %d" % [wood, r.get_amount(T.WOOD)])
	puzzles.close()
	puzzles.open(E.DISEASE)
	check("other puzzles hide the pictures", not puzzles._field.visible)
	puzzles.close()

	# Before a discovery the puzzle is the memory game, even while its own cooldown runs.
	memory.open()
	memory.close()
	events._next_index = EventManager.ORDER.find(E.DISCOVERY)
	puzzles._played_for = -1
	check("before a discovery the puzzle is Memory Match", puzzles.get_next_title() == "Memory Match")
	check("it opens the memory game", puzzles.play_next() and memory.is_open() and puzzles.get_kind() == "memory")
	memory.close()
	await process_frame
	check("closing it starts nothing", not memory.is_open() and not paused and events.get_active().is_empty())

	# Switched off (the other tests do this), there is no puzzle to play.
	EventPuzzles.enabled = false
	puzzles._played_for = -1
	check("with puzzles off, none can be played", not puzzles.can_play() and not puzzles.play_next())
	EventPuzzles.enabled = true

	# The 5-minute Quick Game.
	check("full game timings by default", QuickGame.calm() == 90.0 and QuickGame.first_event() == 60.0 and QuickGame.landmarks_to_win() == 3)
	QuickGame.on = true
	check("quick game: 15 s to the first event and between events", QuickGame.first_event() == 15.0 and QuickGame.calm() == 15.0)
	check("quick game: short events, half the build days, one landmark wins",
		QuickGame.duration(E.DISCOVERY) == 60.0 and QuickGame.duration(E.DISEASE) == 60.0 and QuickGame.duration(E.STORM) == 60.0 and QuickGame.duration(E.DROUGHT) < 0.0
		and QuickGame.days(3.0) == 1.5 and QuickGame.landmarks_to_win() == 1 and QuickGame.win_population() == 18)
	# A calm before each of the six events; the accident lasts as long as its
	# repair (about 30 s with the walk).
	var all_events := QuickGame.first_event() + 5 * QuickGame.calm() + EventManager.REPAIR_SECONDS + 10.0
	for type in [E.DISCOVERY, E.DISEASE, E.STORM, E.MIGRATION]:
		all_events += QuickGame.duration(type)
	all_events += QuickGame.days(DroughtMission.MAX_DAYS) * TimeManager.DAY_SECONDS
	check("quick game: six events of about a minute take 7 to 8 minutes", all_events >= 420.0 and all_events <= 480.0, "%d s" % all_events)
	QuickGame.on = false
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	menu.open_start_menu()
	check("the main menu offers Quick Game and Full Game", "Quick Game (8 min)" in menu.get_item_texts() and "Full Game" in menu.get_item_texts(), str(menu.get_item_texts()))
	menu.confirm()
	check("choosing Quick Game turns it on", QuickGame.on)
	QuickGame.on = false

	# One short card per event message.
	var card := StoryBox.shorten(DroughtMission.STORY + ["MISSION: SAVE THE COLONY\nObjective: construct a Water Storage.\nIt needs 10 Wood.\nMore."])
	check("an event story becomes one card with just its instructions", card.size() == 1 and str(card[0]).begins_with("MISSION") and not "More." in str(card[0]), str(card))
	check("a long story with no instructions keeps one sentence", StoryBox.shorten(DiseaseMission.STORY_CURED).size() == 1 and str(StoryBox.shorten(DiseaseMission.STORY_CURED)[0]).count(". ") == 0)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
