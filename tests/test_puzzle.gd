# test_puzzle.gd
# The gold puzzle: a memory game of six pairs. Opening it pauses the game; a
# matching pair stays face up, a wrong pair turns back; finishing pays gold
# (fewer moves, more gold); after it closes the next puzzle waits 90 seconds.
# Run with a window:  <Godot> --path . --script res://tests/test_puzzle.gd
extends SceneTree

var fails := 0


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	StoryBox.enabled = false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("ControllerMenu").close_menu()
	paused = false
	main.get_node("EventManager/EventTimer").stop()
	var puzzle: GoldPuzzle = main.get_node("UI/GoldPuzzle")
	var r: ResourceManager = main.get_node("ResourceManager")
	var hud: Hud = main.get_node("UI/HUD")
	await process_frame
	var button: Button = hud.get_node("Toolbar/PuzzleButton")
	check("a toolbar button offers the puzzle", button.visible and not button.disabled and button.text == "Puzzle", button.text)

	check("rewards: 25 gold for a perfect 6 moves, one less per extra move, at least 8", GoldPuzzle.reward_for(6) == 25 and GoldPuzzle.reward_for(10) == 21 and GoldPuzzle.reward_for(40) == 8)
	check("the button opens it, and the game pauses", puzzle.open() and puzzle.is_open() and paused)
	var cards := puzzle.get_cards().duplicate()   # A copy: the puzzle reuses its list.
	check("twelve cards, two of each of six pictures", cards.size() == 12 and cards.count("gold") == 2 and cards.count("home") == 2)

	# A wrong pair turns back.
	# Card 0 and the first card with a different picture.
	var wrong := 1
	while cards[wrong] == cards[0]:
		wrong += 1
	puzzle.turn(0)
	puzzle.turn(wrong)
	check("a wrong pair counts a move and is not kept", puzzle.get_moves() == 1 and puzzle.get_pairs() == 0)
	await create_timer(GoldPuzzle.SHOW_MISMATCH + 0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/v2_puzzle.png")

	# Solve it perfectly from here: each pair in one move.
	var gold := r.get_amount(ResourceManager.Type.GOLD)
	var done := {}
	for i in cards.size():
		if done.has(i):
			continue
		var j := cards.find(cards[i], i + 1)
		puzzle.turn(i)
		puzzle.turn(j)
		done[i] = true
		done[j] = true
	check("all six pairs found in 7 moves", puzzle.get_pairs() == 6 and puzzle.get_moves() == 7, "%d moves" % puzzle.get_moves())
	check("it pays 24 gold (7 moves)", r.get_amount(ResourceManager.Type.GOLD) == gold + 24, str(r.get_amount(ResourceManager.Type.GOLD) - gold))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/v2_puzzle_solved.png")
	puzzle.close()
	check("closing it unpauses the game and starts the 90 s wait", not puzzle.is_open() and not paused and absf(puzzle.get_cooldown() - 90.0) < 0.1)
	check("another puzzle is refused until then", not puzzle.open())
	await process_frame
	await process_frame
	check("the button shows the wait", button.disabled and button.text.ends_with(" s") and button.tooltip_text.begins_with("Next puzzle in"), button.text)
	puzzle._cooldown = 0.0
	check("after the wait it can be played again, with a new shuffle", puzzle.open() and puzzle.get_cards() != cards)
	puzzle.close()

	# The controller: Menu > "Play the gold puzzle".
	puzzle._cooldown = 0.0
	var menu: ControllerMenu = main.get_node("ControllerMenu")
	menu.open_pause_menu()
	var texts := menu.get_item_texts()
	check("the pause menu offers the puzzle for the controller", texts.has("Play the gold puzzle"), str(texts))
	menu.close_menu()
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
