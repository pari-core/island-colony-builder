# test_stories.gd
# The stories for the three lighter events: Resource discovery ("A Lucky Find"),
# Trade opportunity ("The Merchant's Sail") and Migration ("New Arrivals").
# Run with a window:  <Godot> --path . --script res://tests/test_stories.gd
extends SceneTree

const T := ResourceManager.Type
const E := EventManager.Type
const OUT := "res://documentation/evidence/"

var fails := 0
var main: Node
var events: EventManager
var stories: EventStories
var story: StoryBox
var menu: ControllerMenu
var workers: WorkerManager
var r: ResourceManager
var pop: PopulationManager


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func new_game() -> void:
	if main != null:
		main.queue_free()
		await process_frame
	paused = false
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	main.get_node("PopulationManager/UpkeepTimer").stop()
	main.get_node("BuildingManager").mouse_enabled = false
	main.get_node("TimeManager").set_process(false)
	events = main.get_node("EventManager")
	stories = main.get_node("EventStories")
	story = main.get_node("UI/StoryBox")
	menu = main.get_node("ControllerMenu")
	workers = main.get_node("WorkerManager")
	r = main.get_node("ResourceManager")
	pop = main.get_node("PopulationManager")
	for child in workers.get_children():
		if child is Timer:
			child.stop()


func build(index: int, plot_id: int) -> BuildingPlot:
	var builder: BuildingManager = main.get_node("BuildingManager")
	var plot: BuildingPlot = main.get_node("MapManager").get_plot(plot_id)
	builder._chosen_index = index
	builder._place_building(plot)
	return plot


func arrive() -> void:
	for worker in workers.get_workers():
		worker.model.position = worker.target_position


# Shows the whole of the page being told, then saves a picture of the screen.
func shot(file: String) -> void:
	if story.is_typing():
		story.advance()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + file)


func page(number: int) -> String:
	return str(story._pages[number - 1]) if number <= story.get_page_count() else ""


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	# ------------------------------------------------------------ A Lucky Find
	await new_game()
	var lumber := build(2, 3)
	var quarry := build(3, 4)
	workers.assign_worker(lumber)
	workers.assign_worker(lumber)
	workers.assign_worker(quarry)
	arrive()
	events.trigger(E.DISCOVERY)
	check("the discovery opens its story and the game waits", story.is_open() and paused and story.get_title() == "A LUCKY FIND" and story.get_page_count() == 4 and story.get_icon() == "star")
	check("workers discover the grove and the hillside", page(1).begins_with("At dawn, two workers set out") and page(2).contains("they had discovered a grove of tall, straight oaks"))
	check("the notice gives the real bonus, time and workers", page(4) == "RESOURCE DISCOVERY!\nLumber Camps and Quarries make 50% more for 60 seconds.\n3 of your workers are there to make the most of it.", page(4))
	story.advance(); story.advance(); story.advance(); story.advance(); story.advance(); story.advance()
	await shot("story_discovery.png")
	story.skip()
	check("then the game carries on with the bonus", not paused and workers.get_output(lumber) == 13, str(workers.get_output(lumber)))
	var wood := r.get_amount(T.WOOD)
	var stone := r.get_amount(T.STONE)
	workers.produce()
	workers.produce()
	var got_wood := r.get_amount(T.WOOD) - wood
	var got_stone := r.get_amount(T.STONE) - stone
	check("what the find brings in is counted", got_wood > 0 and got_stone > 0 and stories.get_gathered(T.WOOD) == got_wood and stories.get_gathered(T.STONE) == got_stone, "%d wood %d stone" % [got_wood, got_stone])
	events._process(61.0)
	check("when it ends, the closing story says what was gathered", story.is_open() and story.get_page_text().begins_with("The last of the tall oaks has been felled") and page(2) == "EVENT COMPLETED - A LUCKY FIND\nGathered while the find lasted: %d Wood and %d Stone." % [got_wood, got_stone], page(2))
	story.skip()
	workers.produce()
	check("production after the find is not counted", stories.get_gathered(T.WOOD) == got_wood)

	await new_game()
	events.trigger(E.DISCOVERY)
	check("with nobody at a Lumber Camp or Quarry, the notice says so", page(4).contains("Nobody is working at one yet"), page(4))
	story.skip()
	events._process(61.0)
	check("and the ending says the find went to waste", story.get_page_text().begins_with("The grove and the hillside were left almost untouched") and page(2).begins_with("THE FIND IS SPENT"), page(2))
	story.skip()

	# ------------------------------------------------------------ The Merchant's Sail
	# Known stores when the ship arrives: 200 wood, 70 stone, 20 gold (limit 200).
	r.spend({ T.WOOD: r.get_amount(T.WOOD), T.STONE: r.get_amount(T.STONE), T.GOLD: r.get_amount(T.GOLD) })
	r.add(T.WOOD, 200)
	r.add(T.STONE, 70)
	r.add(T.GOLD, 20)
	events.trigger(E.TRADE)
	check("the trade opens its story", story.is_open() and story.get_title() == "THE MERCHANT'S SAIL" and story.get_page_count() == 3 and story.get_icon() == "coin" and page(1).begins_with("A sail has appeared on the horizon"))
	check("no board asks anything during the story", menu.get_mode() == ControllerMenu.Mode.NONE)
	story.skip()
	check("then a board asks for an answer, and the game waits", menu.get_mode() == ControllerMenu.Mode.CHOICE and paused)
	var texts := menu.get_item_texts()
	check("offers worked out from the stores: half the wood (capped at 100), half the stone, a quarter of each", texts == [
		"Timber\n     Give 100 Wood, receive 50 Gold.",
		"Stone\n     Give 30 Stone, receive 15 Gold.",
		"Timber and stone\n     Give 50 Wood, 10 Stone, receive 30 Gold.",
		"Decline\n     Keep everything. The ship sails on.",
	], str(texts))
	await shot("story_trade.png")
	check("the board's title is the question", (main.get_node("UI/MenuPanel").find_child("TitleLabel", true, false) as Label).text == "What will you tell the captain?")
	r.add(T.STONE, 100)
	await process_frame
	check("the offers stay fixed while the ship waits", menu.get_item_texts()[1] == "Stone\n     Give 30 Stone, receive 15 Gold.")
	r.spend({ T.STONE: 100 })
	menu.confirm()
	check("timber: 100 wood for 50 gold, half the wood stays", not menu.is_open() and not events.is_active(E.TRADE) and r.get_amount(T.WOOD) == 100 and r.get_amount(T.GOLD) == 70 and r.get_amount(T.STONE) == 70, "%d %d" % [r.get_amount(T.WOOD), r.get_amount(T.GOLD)])
	check("the ending names the cargo", story.is_open() and story.get_page_text().begins_with("The cargo of timber is rowed out to the ship") and page(2) == "TRADE COMPLETED - TIMBER\n100 Wood given. 50 Gold received.", page(2))
	story.skip()

	# Little stone: the stone and mixed offers are not made, and say why.
	r.spend({ T.STONE: 55 })   # 15 stone left: half is 7, under the smallest offer.
	events.trigger(E.TRADE)
	story.skip()
	texts = menu.get_item_texts()
	check("with 15 stone, no stone offer, and the reason is on the board", texts[1] == "Stone\n     Not offered: you have too little stone." and texts[2] == "Timber and stone\n     Not offered: you have too little wood and stone.", str(texts))
	menu.move_highlight(1)
	menu.confirm()
	check("choosing it is refused with the same reason", menu.is_open() and menu.get_message() == "Not offered: you have too little stone" and r.get_amount(T.STONE) == 15, menu.get_message())
	menu.move_highlight(2)
	menu.confirm()
	story.skip()

	# Nearly full gold: the offer is cut down so no gold is wasted.
	r.add(T.GOLD, 170 - r.get_amount(T.GOLD))
	r.add(T.WOOD, 200)   # Full wood: timber would be 100 wood for 50 gold, more than fits.
	events.trigger(E.TRADE)
	story.skip()
	texts = menu.get_item_texts()
	check("with room for only 30 gold, timber is cut to 60 wood for 30 gold", texts[0] == "Timber\n     Give 60 Wood, receive 30 Gold.", texts[0])
	menu.confirm()
	check("and the gold fits: 200 of 200", r.get_amount(T.GOLD) == 200)
	story.skip()
	events.trigger(E.TRADE)
	story.skip()
	check("with the gold store full, nothing is offered", menu.get_item_texts()[0] == "Timber\n     Not offered: your gold store is full.", menu.get_item_texts()[0])
	menu.move_highlight(3)
	menu.confirm()
	story.skip()
	r.spend({ T.GOLD: 150 })
	check("and the game carries on", not paused)

	events.trigger(E.TRADE)
	story.skip()
	wood = r.get_amount(T.WOOD)
	var gold := r.get_amount(T.GOLD)
	menu.move_highlight(3)
	menu.confirm()
	check("declining changes nothing and ends the event", not events.is_active(E.TRADE) and r.get_amount(T.WOOD) == wood and r.get_amount(T.GOLD) == gold)
	check("the declining ending is told", story.get_page_text().begins_with("The captain shrugs") and page(2) == "THE SHIP HAS SAILED\nNothing given, nothing gained.", page(2))
	story.skip()

	# ------------------------------------------------------------ New Arrivals
	events.trigger(E.MIGRATION)
	check("the migration opens its story: 4 workers arrive", workers.get_workers().size() == 10 and story.get_title() == "NEW ARRIVALS" and story.get_page_count() == 5 and story.get_icon() == "boat" and page(1).begins_with("A sailing ship has been sighted"))
	check("the notice names the newcomers", page(4) == "MIGRATION!\n4 new workers have joined the colony: Gita, Hari, Isla and Jai.\nEach eats 2 food at every meal.", page(4))
	check("the mission says how many need a home, and how long there is", page(5) == "MISSION: MAKE THEM WELCOME\n4 people have no home. Build a House (it holds 4) within 2 days, so that everyone has a bed.", page(5))
	story.advance(); story.advance(); story.advance(); story.advance(); story.advance(); story.advance(); story.advance(); story.advance()
	await shot("story_migration.png")
	story.skip()
	var happy := pop.get_happiness()
	build(0, 1)
	check("a House gives everyone a home", pop.get_homeless() == 0)
	events._process(39.0)
	check("the event lasts 2 days", events.is_active(E.MIGRATION) and not story.is_open())
	events._process(2.0)
	check("with everyone housed, the welcome ending is told and happiness +3", story.get_page_text().begins_with("The newcomers have settled in") and page(2) == "EVENT COMPLETED - NEW ARRIVALS\nEveryone has a home. Happiness +3." and pop.get_happiness() == happy + 3, page(2))
	story.skip()

	await new_game()
	events.trigger(E.MIGRATION)
	story.skip()
	happy = pop.get_happiness()
	events._process(41.0)
	check("with no House built, the other ending is told and nothing is given", story.get_page_text().begins_with("The newcomers are working hard, but there are not enough beds") and page(2).begins_with("NO ROOM FOR EVERYONE\n4 people have no home") and pop.get_happiness() == happy, page(2))
	story.skip()

	while workers.add_worker():
		pass
	events.trigger(E.MIGRATION)
	check("a full colony takes nobody in: one page, no mission", workers.get_workers().size() == 12 and story.get_page_count() == 1 and story.get_page_text().begins_with("A sailing ship anchors off the eastern beach, but the colony already has all the workers"))
	story.skip()
	events._process(41.0)
	check("and no ending is told", not story.is_open())

	# ------------------------------------------------------------ Pictures and the switch
	await new_game()
	events.trigger(E.DROUGHT)
	check("the drought's picture is the sun", story.get_icon() == "sun")
	story.skip()
	events.end_event(E.DROUGHT)
	events.trigger(E.DISEASE)
	check("the plague's picture is the cross", story.get_icon() == "cross")
	story.skip()
	menu.move_highlight(1)
	menu.confirm()
	events._process(121.0)
	story.skip()
	StoryBox.enabled = false
	events.trigger(E.DISCOVERY)
	events.trigger(E.TRADE)
	check("switched off, no story or board opens and nothing pauses", not story.is_open() and not menu.is_open() and not paused)
	StoryBox.enabled = true

	paused = false
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
