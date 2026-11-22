# test_disease.gd
# "The Silent Plague": the outbreak's story, the decision board, the vaccine and
# both endings. The outbreak's rules themselves are tested in test_events.gd.
# Run with a window:  <Godot> --path . --script res://tests/test_disease.gd
extends SceneTree

const T := ResourceManager.Type
const E := EventManager.Type
const C := DiseaseMission.Choice
const OUT := "res://documentation/evidence/"

var fails := 0
var main: Node
var events: EventManager
var mission: DiseaseMission
var story: StoryBox
var menu: ControllerMenu
var research: ResearchManager
var workers: WorkerManager
var r: ResourceManager
var pop: PopulationManager
var popups: PopupManager


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
	mission = main.get_node("DiseaseMission")
	story = main.get_node("UI/StoryBox")
	menu = main.get_node("ControllerMenu")
	research = main.get_node("ResearchManager")
	workers = main.get_node("WorkerManager")
	r = main.get_node("ResourceManager")
	pop = main.get_node("PopulationManager")
	popups = main.get_node("Popups")
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


func key(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.pressed = down
		root.push_input(e)
		await process_frame


func shot(file: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + file)


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	# ------------------------------------------------------------ The story
	await new_game()
	var farm := build(1, 2)
	workers.assign_worker(farm)
	workers.assign_worker(farm)
	arrive()
	var happy := pop.get_happiness()
	events.trigger(E.DISEASE)
	check("the outbreak: 3 of 6 workers sick, happiness -5", mission.get_sick_count() == 3 and mission.get_healthy_count() == 3 and pop.get_happiness() == happy - 5 and mission.is_active())
	check("it opens the story and the game waits", story.is_open() and paused and story.get_title() == "THE SILENT PLAGUE" and story.get_page_count() == 6, str(story.get_page_count()))
	check("scene 1: an ordinary morning", story.get_page_text().begins_with("It was supposed to be another peaceful morning"))
	story.advance(); story.advance()
	check("scene 2: something is wrong", story.get_page_text().begins_with("But something unusual has begun to happen"))
	story.advance(); story.advance()
	check("scene 3: the outbreak", story.get_page_text().begins_with("Before long, every second worker has fallen sick"))
	story.advance(); story.advance()
	check("then the urgent notice, with the real numbers", story.get_page_text() == "DISEASE OUTBREAK!\n3 of 6 workers are sick and temporarily unable to work.\nColony happiness has decreased by 5 points.", story.get_page_text())
	story.advance()
	await shot("disease_story.png")
	story.advance()
	check("scene 4: a possible solution, with the real cost", story.get_page_text().contains("it will require 15 Gold and some time"), story.get_page_text())
	story.advance(); story.advance()
	check("and the decision is the player's", story.get_page_text().ends_with("The decision is now yours."))
	check("no board asks anything while the story is being told", menu.get_mode() == ControllerMenu.Mode.NONE)
	story.advance(); story.advance()

	# ------------------------------------------------------------ The decision
	check("after the story a board asks what to do, and the game still waits", not story.is_open() and menu.get_mode() == ControllerMenu.Mode.CHOICE and paused)
	var texts := menu.get_item_texts()
	check("option A: research a vaccine, with cost and time", texts.size() == 2 and texts[0].begins_with("Research a vaccine") and texts[0].contains("15 Gold, 45 seconds at the Research Lab") and texts[0].contains("Happiness +10"), str(texts))
	check("option B: wait, free, 120 seconds", texts[1].begins_with("Wait for natural recovery") and texts[1].contains("Free") and texts[1].contains("120 seconds"), texts[1])
	await shot("disease_choice.png")
	check("the board's title is the question", (main.get_node("UI/MenuPanel").find_child("TitleLabel", true, false) as Label).text == "How will you handle the outbreak?")
	await key(KEY_BACKSPACE)
	check("Back cannot close it: an answer is needed", menu.get_mode() == ControllerMenu.Mode.CHOICE and paused)
	var gold := r.get_amount(T.GOLD)
	menu.confirm()
	check("without a Research Lab, option A is refused and says why", menu.is_open() and menu.get_message().contains("no working Research Lab") and r.get_amount(T.GOLD) == gold and mission.get_choice() == C.NONE, menu.get_message())

	# ------------------------------------------------------------ Waiting
	await key(KEY_DOWN)
	await key(KEY_SPACE)
	check("choosing to wait closes the board and the game carries on", not menu.is_open() and not paused and mission.get_choice() == C.WAIT)
	var line := events.describe(events.get_active()[0])
	check("the event list counts down and counts the sick", line.begins_with("Disease outbreak (120 s): 3 of 6 workers sick"), line)
	check("the sick make nothing", workers.get_output(farm) == int(4 * 1.5), str(workers.get_output(farm)))
	events._process(119.0)
	check("after 119 seconds they are still sick", events.is_active(E.DISEASE) and mission.get_sick_count() == 3)
	events._process(2.0)
	check("after 120 seconds everyone recovers", not events.is_active(E.DISEASE) and mission.get_sick_count() == 0 and not mission.is_active() and workers.get_output(farm) == 13)
	check("with no reward: happiness is not raised", pop.get_happiness() == happy - 5)
	check("the waiting ending is told", story.is_open() and story.get_page_count() == 4 and story.get_page_text().begins_with("With no immediate treatment available"))
	check("it says no gold was spent", str(story._pages[2]).contains("even without spending its precious gold") and str(story._pages[3]) == "THE COLONY HAS RECOVERED!\nAll sick workers recovered.\nWorker productivity restored.\nNo gold spent." and r.get_amount(T.GOLD) == gold)
	story.skip()
	check("then the game carries on", not paused and not story.is_open())

	# ------------------------------------------------------------ The vaccine
	await new_game()
	farm = build(1, 2)
	var lab := build(5, 3)
	workers.assign_worker(farm)
	workers.assign_worker(farm)
	arrive()
	r.spend({ T.GOLD: 10 })
	happy = pop.get_happiness()
	events.trigger(E.DISEASE)
	story.skip()
	menu.confirm()
	check("without 15 gold, option A is refused and says why", menu.is_open() and menu.get_message() == "Not enough gold (needs 15 Gold)" and research.get_current() == "", menu.get_message())
	r.add(T.GOLD, 20)
	gold = r.get_amount(T.GOLD)
	menu.confirm()
	check("with the gold, research starts and 15 gold is taken", not menu.is_open() and not paused and research.get_current() == "vaccine" and r.get_amount(T.GOLD) == gold - 15 and mission.get_choice() == C.VACCINE)
	research._process(20.0)
	await process_frame
	var sign: Label3D = mission._sign
	check("a sign over the Research Lab shows the research", sign.visible and sign.text == "Vaccine research 44%" and absf(sign.position.x - lab.position.x) < 0.01, sign.text)
	check("and so does the event list", events.describe(events.get_active()[0]).contains("Vaccine research: 44%"), events.describe(events.get_active()[0]))
	var camera: Camera3D = main.get_node("Camera3D")
	camera.set_process(false)
	camera.global_position = lab.position + Vector3(-34, 34, 40)
	camera.look_at(lab.position + Vector3(0, 4, 0))
	await shot("disease_research.png")
	research._process(26.0)
	check("after 45 seconds the vaccine is ready and the good news is told", research.is_finished("vaccine") and story.is_open() and story.get_page_text().begins_with("The researchers finally emerge from the laboratory"))
	check("with a notice of what to do next", str(story._pages[1]).begins_with("VACCINE READY!") and str(story._pages[1]).contains("send the 3 sick workers") and popups.get_texts().has("VACCINE READY!"), str(story._pages[1]))
	story.skip()
	await process_frame
	await process_frame
	check("the research sign goes away", not sign.visible)
	check("nobody is cured yet", mission.get_sick_count() == 3 and events.is_active(E.DISEASE))

	# ------------------------------------------------------------ Treatment
	check("Enter sends the sick to the Research Lab", events.respond() and events.get_patients()[0].treatment_plot == lab)
	var first: Worker = events.get_patients()[0]
	first.model.position = first.target_position
	events._process(0.01)
	check("the first to arrive is cured at once, with a sign", not first.is_sick and mission.get_sick_count() == 2 and popups.get_texts().has("Cured!"), str(popups.get_texts()))
	check("happiness waits for the last one", pop.get_happiness() == happy - 5 and events.is_active(E.DISEASE))
	events._process(0.01)
	check("a cured worker is not treated twice", mission.get_sick_count() == 2 and first.treatment_plot == null)
	# Each cure makes the others shuffle round the Lab, so they arrive in turn.
	for i in 3:
		arrive()
		events._process(0.01)
	check("when the last is treated the outbreak ends: happiness +10", not events.is_active(E.DISEASE) and mission.get_sick_count() == 0 and pop.get_happiness() == happy + 5 and not mission.is_active(), "active %s sick %d happy %d->%d mission %s" % [events.is_active(E.DISEASE), mission.get_sick_count(), happy, pop.get_happiness(), mission.is_active()])
	check("the vaccine ending is told", story.is_open() and story.get_page_count() == 3 and story.get_page_text().begins_with("One by one, the sick workers make their way"))
	check("it ends on OUTBREAK CONTAINED", str(story._pages[2]) == "OUTBREAK CONTAINED!\nAll sick workers recovered.\nWorker productivity restored.\nHappiness increases by 10 points.", str(story._pages[2]))
	story.skip()
	events._process(200.0)
	check("the outbreak ends only once: no second ending, no second reward", not story.is_open() and pop.get_happiness() == happy + 5)
	arrive()
	check("the workers are back at work", workers.get_output(farm) == 13)

	# ------------------------------------------------------------ The next outbreak
	events.trigger(E.DISEASE)
	check("the next outbreak's story knows the vaccine exists", story.get_page_count() == 5 and str(story._pages[4]).begins_with("This time the colony is prepared"))
	story.skip()
	texts = menu.get_item_texts()
	check("option A is now to use the vaccine, free", texts[0].begins_with("Use the vaccine") and texts[0].contains("Free"), texts[0])
	gold = r.get_amount(T.GOLD)
	menu.confirm()
	check("choosing it sends the sick to the Lab at no cost", not menu.is_open() and events.get_patients()[0].treatment_plot == lab and r.get_amount(T.GOLD) == gold)
	for i in 4:
		arrive()
		events._process(0.01)
	check("and they are cured", not events.is_active(E.DISEASE))
	story.skip()

	# ------------------------------------------------------------ Research too slow
	await new_game()
	build(5, 3)
	events.trigger(E.DISEASE)
	story.skip()
	menu.confirm()
	research._process(30.0)
	events._process(121.0)
	check("if the illness passes before the vaccine is ready, the waiting ending is told", not events.is_active(E.DISEASE) and story.get_page_text().begins_with("With no immediate treatment available"))
	check("but it does not claim no gold was spent", str(story._pages[2]).contains("research carries on") and not str(story._pages[3]).contains("No gold spent"), str(story._pages[3]))
	story.skip()
	check("and the research carries on for next time", research.get_current() == "vaccine")

	# ------------------------------------------------------------ Changing your mind
	await new_game()
	build(5, 3)
	events.trigger(E.DISEASE)
	story.skip()
	menu.move_highlight(1)
	menu.confirm()
	check("after choosing to wait", mission.get_choice() == C.WAIT)
	check("the vaccine can still be researched at the Lab", research.start("vaccine") and mission.get_choice() == C.VACCINE)

	paused = false
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
