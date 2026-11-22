# disease_mission.gd
# "The Silent Plague": the disease outbreak told as a short story with one
# decision, to pay for a vaccine or to wait.
#
# The rules of the outbreak itself have not changed and still live in
# event_manager.gd and research_manager.gd:
#   - Every second worker falls sick and makes nothing. Happiness -5.
#   - The vaccine is researched at the Research Lab: 15 gold, 45 seconds.
#   - With the vaccine, the sick are sent to the Lab and each recovers on
#     arriving. When the last one is treated, happiness +10.
#   - Left alone, everyone recovers after 120 seconds, with no reward.
#   - These two timers count seconds of play, as before, not in-game days.
#
# This script adds the telling: the opening story, a board that asks the player
# what to do, signs that show the research and each cure, and a different
# closing story for each ending. The outbreak can only end one way, so only one
# closing story is told and happiness is only given once.
class_name DiseaseMission
extends Node3D

enum Choice { NONE, VACCINE, WAIT }

const TITLE := "THE SILENT PLAGUE"
const SIGN_HEIGHT := 13.0        # Metres above the ground the research sign floats.
const GOOD_COLOUR := Color(0.7, 1.0, 0.75)

const STORY := [
	"It was supposed to be another peaceful morning in the colony. Workers were heading to the farms, builders were gathering materials, and the settlement was slowly growing.",
	"But something unusual has begun to happen. One by one, villagers are falling ill. Some complain of dizziness and weakness, while others are too exhausted to continue working.",
	"Before long, every second worker has fallen sick. The farms are slowing down, construction has nearly come to a halt, and worried villagers are gathering around the settlement.",
]
const STORY_SOLUTION := [
	"The colony's Research Lab may hold the answer. The researchers believe they can develop a vaccine, but it will require %s and some time to complete.",
	"However, not everyone believes a vaccine is necessary. Some villagers think the illness will pass on its own. The decision is now yours.",
]
const STORY_HAVE_VACCINE := "This time the colony is prepared. The Research Lab already holds the vaccine from the last outbreak. The sick only need to be sent there. The decision is now yours."
const STORY_VACCINE_READY := "The researchers finally emerge from the laboratory with good news. After hours of effort, a vaccine has been successfully developed."
const STORY_CURED := [
	"One by one, the sick workers make their way to the Research Lab for treatment. Slowly, the colony begins to recover.",
	"As the last worker receives the vaccine, relief spreads throughout the settlement. The workers return to their duties, and hope is restored.",
]
const STORY_WAITED := [
	"With no immediate treatment available, the colony enters a period of uncertainty. The sick workers rest while the others continue managing the settlement.",
	"After some time, the illness finally begins to fade. One by one, the workers recover and return to their duties.",
]

# The tests of the outbreak's rules switch the story off, so nothing pauses them.
var story_enabled := true

var _active := false
var _choice := Choice.NONE
var _awaiting_choice := false    # The opening story is being told; the question comes next.
var _gold_spent := false         # True if this outbreak's vaccine research was paid for.
var _was_researching := false
var _sick_before: Array[Worker] = []
var _sign: Label3D

@onready var _events: EventManager = get_node("../EventManager")
@onready var _research: ResearchManager = get_node("../ResearchManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _popups: PopupManager = get_node("../Popups")
@onready var _menu: ControllerMenu = get_node("../ControllerMenu")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _story: StoryBox = get_node("../UI/StoryBox")


func _ready() -> void:
	_events.events_changed.connect(_on_events_changed)
	_events.disease_ended.connect(_on_disease_ended)
	_research.research_changed.connect(_on_research_changed)
	_workers.workers_changed.connect(_on_workers_changed)
	_story.story_finished.connect(_on_story_finished)
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.fixed_size = true
	_sign.pixel_size = 0.0007
	_sign.font_size = 36
	_sign.outline_size = 12
	_sign.modulate = GOOD_COLOUR
	_sign.no_depth_test = true
	_sign.visible = false
	add_child(_sign)


# The sign over the Research Lab follows the research every frame.
func _process(_delta: float) -> void:
	var lab := _research.get_working_lab()
	_sign.visible = lab != null and _research.get_current() == "vaccine"
	if _sign.visible:
		_sign.position = Vector3(lab.position.x, _terrain.LAND_HEIGHT + SIGN_HEIGHT, lab.position.z)
		_sign.text = "Vaccine research %d%%" % int(_research.get_progress() * 100.0)


func is_active() -> bool:
	return _active


# What the player chose for this outbreak.
func get_choice() -> Choice:
	return _choice


func get_sick_count() -> int:
	return _events.get_patients().size()


func get_healthy_count() -> int:
	return _workers.get_workers().size() - get_sick_count()


# The answers on the decision board. ControllerMenu shows them.
func get_choice_items() -> Array[Dictionary]:
	var wait_seconds := int(EventManager.DURATIONS[EventManager.Type.DISEASE])
	var wait := {
		"text": "Wait for natural recovery\n     Free. The sick rest and recover in about %d seconds." % wait_seconds,
		"action": func() -> bool:
			_choice = Choice.WAIT
			return true,
		"closes": true,
	}
	if _research.is_finished("vaccine"):
		return [{
			"text": "Use the vaccine\n     Free. Send the sick to the Research Lab: each recovers on arriving. Happiness +%d." % EventManager.TREATED_HAPPINESS,
			"action": _choose_treatment,
			"problem": "Treatment needs a working Research Lab",
			"closes": true,
		}, wait]
	var project: Dictionary = ResearchManager.PROJECTS.vaccine
	return [{
		"text": "Research a vaccine\n     %s, %d seconds at the Research Lab. Then send the sick there. Happiness +%d." % [_resources.describe_cost(project.cost), int(project.seconds), EventManager.TREATED_HAPPINESS],
		"action": _choose_research,
		"problem": _research_problem(),
		"closes": true,
	}, wait]


func _on_events_changed() -> void:
	var outbreak := _events.is_active(EventManager.Type.DISEASE)
	if outbreak and not _active:
		_begin()


func _begin() -> void:
	_active = true
	_choice = Choice.NONE
	_gold_spent = false
	_was_researching = _research.get_current() == "vaccine"
	_sick_before = _events.get_patients()
	if not story_enabled or not StoryBox.enabled:
		return
	var pages := STORY.duplicate()
	pages.append("DISEASE OUTBREAK!\n%d of %d workers are sick and temporarily unable to work.\nColony happiness has decreased by %d points." % [get_sick_count(), _workers.get_workers().size(), -EventManager.DISEASE_HAPPINESS])
	if _research.is_finished("vaccine"):
		pages.append(STORY_HAVE_VACCINE)
	else:
		pages.append(STORY_SOLUTION[0] % _resources.describe_cost(ResearchManager.PROJECTS.vaccine.cost))
		pages.append(STORY_SOLUTION[1])
	_awaiting_choice = true
	_story.tell(TITLE, pages, "cross")


# After the opening story, the board asks what to do.
func _on_story_finished() -> void:
	if _awaiting_choice and _active:
		_awaiting_choice = false
		_menu.open_choice("How will you handle the outbreak?", get_choice_items)


func _research_problem() -> String:
	if not _research.has_working_lab():
		return "There is no working Research Lab: build one first, or wait"
	if _research.get_current() != "":
		return "The Research Lab is busy"
	return "Not enough gold (needs %s)" % _resources.describe_cost(ResearchManager.PROJECTS.vaccine.cost)


func _choose_research() -> bool:
	# Research that was already running when the outbreak began counts too.
	if _research.get_current() != "vaccine" and not _research.start("vaccine"):
		return false
	_choice = Choice.VACCINE
	return true


func _choose_treatment() -> bool:
	if not _events.respond():
		return false
	_choice = Choice.VACCINE
	return true


# Notices the moment the vaccine research starts and the moment it is finished.
func _on_research_changed() -> void:
	var researching := _research.get_current() == "vaccine"
	if _active and researching and not _was_researching:
		_gold_spent = true
		_choice = Choice.VACCINE
	if _active and _was_researching and _research.is_finished("vaccine"):
		var lab := _research.get_working_lab()
		if lab != null:
			_popups.show_on(lab, "VACCINE READY!", GOOD_COLOUR)
		if story_enabled:
			_story.tell(TITLE, [STORY_VACCINE_READY, "VACCINE READY!\nPress Enter (or Space on the controller) to send the %d sick workers to the Research Lab. Each one recovers on arriving." % get_sick_count()], "cross")
	_was_researching = researching


# A worker who was sick and no longer is has just been treated: show it.
func _on_workers_changed() -> void:
	if not _active:
		return
	var sick := _events.get_patients()
	for worker in _sick_before:
		if not sick.has(worker) and is_instance_valid(worker.model) and _events.is_active(EventManager.Type.DISEASE):
			_popups.show_at(worker.model.global_position + Vector3.UP * 4.5, "Cured!", GOOD_COLOUR)
	_sick_before = sick


# The outbreak is over. It ends exactly once, one way or the other.
func _on_disease_ended(cured: bool) -> void:
	if not _active:
		return
	_active = false
	_awaiting_choice = false
	_sick_before = []
	# A board still asking the question no longer has anything to ask.
	if _menu.get_mode() == ControllerMenu.Mode.CHOICE:
		_menu.close_menu()
	if not story_enabled or not StoryBox.enabled:
		return
	if cured:
		var pages := STORY_CURED.duplicate()
		pages.append("OUTBREAK CONTAINED!\nAll sick workers recovered.\nWorker productivity restored.\nHappiness increases by %d points." % EventManager.TREATED_HAPPINESS)
		_story.tell(TITLE, pages, "cross")
	else:
		var pages := STORY_WAITED.duplicate()
		if _gold_spent:
			pages.append("The colony has survived the outbreak. The vaccine was not ready in time, but the research carries on for the next one.")
			pages.append("THE COLONY HAS RECOVERED!\nAll sick workers recovered.\nWorker productivity restored.")
		else:
			pages.append("The colony has survived the outbreak, even without spending its precious gold.")
			pages.append("THE COLONY HAS RECOVERED!\nAll sick workers recovered.\nWorker productivity restored.\nNo gold spent.")
		_story.tell(TITLE, pages, "cross")
