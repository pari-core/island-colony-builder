# drought_mission.gd
# "The Last Drop": the drought told as a short story with one mission, to build
# a Water Storage.
#
# EventManager still decides when a drought starts. This script decides what a
# drought is: the story, the mission, how hard food is hit and how it ends.
#
# First drought (the colony has no Water Storage):
#   1. Four pages of story, then the mission. The Water Storage joins the build list.
#   2. The player chooses where to build it. It costs wood and stone, and two idle
#      workers build it over three in-game days (see construction_manager.gd).
#   3. Farms make half their food until it is finished.
#   4. When it is finished the drought ends: a closing story, a little happiness,
#      and a food bonus for a short while as the farms recover.
#   5. If it is not finished within MAX_DAYS, the rain comes back anyway, but the
#      colony has suffered and loses happiness. It can still be built afterwards.
#
# Later droughts (the Water Storage is standing):
#   Farms make 80% instead of half, and the drought passes after PROTECTED_DAYS.
#
# The twist: the story says the old reservoir was near the riverbank. If the
# player builds within RIVERBANK_METRES of the river, the builders find the old
# foundation and the work is one day shorter. Nothing here is random, so every
# game plays the same way and the tests can check it.
#
# All the numbers are constants below, so they can be tuned in one place.
class_name DroughtMission
extends Node

signal mission_changed

enum Stage { NONE, MISSION, PROTECTED }

const BUILDING := "Water Storage"
const MAX_DAYS := 6.0            # A drought with no Water Storage ends by itself after this.
const PROTECTED_DAYS := 3.0      # How long a drought lasts once the Water Storage stands.
const FOOD_PROTECTED := 0.8      # Food multiplier in a drought with the Water Storage.
const RECOVERY_BONUS := 1.25     # Food multiplier just after the mission succeeds.
const RECOVERY_DAYS := 2.0       # How long that bonus lasts.
const SUCCESS_HAPPINESS := 5
const FAILURE_HAPPINESS := -10
const RIVERBANK_METRES := 55.0   # Building this close to the river finds the old foundation (square 19).
const TWIST_AT := 0.3            # The foundation is found when the work is this far along.
const TWIST_DAYS := 1.0          # Days of work the old foundation saves.
const CHATTER_DAYS := 0.3        # How often a villager says something during a drought.
const CHATTER_COLOUR := Color(1.0, 0.93, 0.8)

const TITLE := "THE LAST DROP"
const STORY := [
	"The sun has been burning brighter than ever. Days have passed without a single drop of rain. The river that once flowed beside your settlement is slowly drying up, and the farms are beginning to suffer.",
	"Your farmers have reported that the crops are withering. The remaining water supply will not last much longer. If nothing is done, food production across the colony will come to a standstill.",
	"An elderly villager approaches you with a suggestion. Years ago, this land had a large water reservoir that supplied nearby settlements. Its remains are still somewhere near the riverbank. Perhaps rebuilding a water storage facility is the only way to save your colony.",
	"The villagers are looking towards you for help. Gather the necessary materials and build a water storage facility before the drought gets worse!",
]
const STORY_TWIST := "A worker discovers that the old reservoir's foundation is still intact here by the riverbank. Construction can now be completed one day earlier."
const STORY_SUCCESS := [
	"The villagers gather around the newly restored water storage facility. What once seemed like a hopeless situation has become a new beginning for the settlement.",
	"The farms begin receiving water again, and the villagers return to their work. Your decision has saved the colony. But remember, the next drought may be even more challenging.",
]
const STORY_FAILURE := "At last, dark clouds gather and the rain returns. But it came too late for many of the crops, and the villagers are worn out and worried. Without a water storage facility, the next drought will hit just as hard."
const STORY_PROTECTED := "The sun burns down again and the river is falling. This time the colony is ready: the Water Storage is full, and the farms can keep going on what it holds."
const STORY_PROTECTED_END := "Rain at last. The Water Storage carried the colony through the dry days, and it is filling up again."
const CHATTER_WAITING := ["So thirsty...", "When will it rain?", "The river is so low", "The crops are dying", "We need water"]
const CHATTER_BUILDING := ["The tank is rising!", "Keep building!", "Water, soon", "Not long now"]

var _stage := Stage.NONE
var _days_in := 0.0              # Days since this drought began.
var _recovery_left := 0.0        # Days of the food bonus still to come.
var _twist_done := false
var _chatter_wait := 0.0
var _chatter_index := 0
var _completed := 0              # How many times the mission has been won.

@onready var _events: EventManager = get_node("../EventManager")
@onready var _builder: BuildingManager = get_node("../BuildingManager")
@onready var _construction: ConstructionManager = get_node("../ConstructionManager")
@onready var _map: MapManager = get_node("../MapManager")
@onready var _time: TimeManager = get_node("../TimeManager")
@onready var _population: PopulationManager = get_node("../PopulationManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _civilians: CivilianManager = get_node("../CivilianManager")
@onready var _popups: PopupManager = get_node("../Popups")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _story: StoryBox = get_node("../UI/StoryBox")


func _ready() -> void:
	_events.events_changed.connect(_on_events_changed)
	_time.time_passed.connect(_on_time_passed)
	_construction.construction_finished.connect(_on_construction_finished)


func get_stage() -> Stage:
	return _stage


# How many times the colony has built its way out of a drought.
func get_completed_count() -> int:
	return _completed


# Days of the food bonus still to come after a success.
func get_recovery_days_left() -> float:
	return _recovery_left


# Days until the rain comes back by itself.
func get_days_until_rain() -> float:
	match _stage:
		Stage.MISSION: return maxf(MAX_DAYS - _days_in, 0.0)
		Stage.PROTECTED: return maxf(PROTECTED_DAYS - _days_in, 0.0)
	return 0.0


# The entry for the Water Storage in the build list.
func get_building_info() -> Dictionary:
	for building: Dictionary in BuildingManager.BUILDINGS:
		if building.name == BUILDING:
			return building
	return {}


func get_building_cost() -> Dictionary:
	return get_building_info().cost


# True if a finished, undamaged Water Storage stands in the colony.
func has_water_storage() -> bool:
	for plot in _map.get_plots():
		if plot.building != null and plot.building_info.name == BUILDING and not plot.under_construction and not plot.is_damaged:
			return true
	return false


# The plot where the Water Storage stands or is being built, or null.
func get_storage_plot() -> BuildingPlot:
	for plot in _map.get_plots():
		if plot.building != null and plot.building_info.name == BUILDING:
			return plot
	return null


# True if this plot is close enough to the river to find the old foundation.
func is_on_riverbank(plot: BuildingPlot) -> bool:
	return _terrain.get_river_distance(plot.position.x, plot.position.z) <= RIVERBANK_METRES


# What food production is multiplied by right now. EventManager asks this.
func get_food_multiplier() -> float:
	match _stage:
		Stage.MISSION: return EventManager.DROUGHT_FOOD
		Stage.PROTECTED: return FOOD_PROTECTED
	return RECOVERY_BONUS if _recovery_left > 0.0 else 1.0


# One line for the event list on screen.
func describe() -> String:
	var rain := "Rain is %.1f days away" % get_days_until_rain()
	if _stage == Stage.PROTECTED:
		return "The Water Storage keeps farms at %d%%. %s" % [int(FOOD_PROTECTED * 100.0), rain]
	var plot := get_storage_plot()
	if plot == null:
		return "Farms make half food. MISSION: build a Water Storage (%s). Press B, then click a square. %s" % [_resources.describe_cost(get_building_cost()), rain]
	return "Farms make half food. Water Storage: %s. %s" % [_construction.get_status(plot), rain]


func _on_events_changed() -> void:
	var drought := _events.is_active(EventManager.Type.DROUGHT)
	if drought and _stage == Stage.NONE:
		_begin()
	elif not drought and _stage != Stage.NONE:
		# Something else ended the drought (a test, for example).
		_stage = Stage.NONE
		mission_changed.emit()


func _begin() -> void:
	_days_in = 0.0
	_chatter_wait = 0.0
	if has_water_storage():
		_stage = Stage.PROTECTED
		_story.tell(TITLE, [STORY_PROTECTED])
	else:
		_stage = Stage.MISSION
		_builder.unlock(BUILDING)
		# Already chosen, so pressing B and picking a square builds it.
		_builder.choose_building(BuildingManager.BUILDINGS.find(get_building_info()))
		var pages := STORY.duplicate()
		pages.append(_mission_text())
		_story.tell(TITLE, pages)
	mission_changed.emit()


# The last page of the opening story: what to do, and what it takes.
func _mission_text() -> String:
	var info := get_building_info()
	var text := "MISSION: SAVE THE COLONY\nObjective: construct a Water Storage.\nIt needs %s, %d idle workers and %d days." % [_resources.describe_cost(info.cost), info.builders, int(info.build_days)]
	if get_storage_plot() != null:
		return text + " Yours is already being built: keep its builders free to finish it."
	return text + " Press B (Build) and click a square: the Water Storage is already chosen (key 8)."


func _on_time_passed(days: float) -> void:
	_recovery_left = maxf(_recovery_left - days, 0.0)
	if _stage == Stage.NONE:
		return
	_days_in += days
	_chatter(days)
	if _stage == Stage.PROTECTED:
		if _days_in >= PROTECTED_DAYS:
			_stage = Stage.NONE
			_events.end_event(EventManager.Type.DROUGHT)
			_story.tell(TITLE, [STORY_PROTECTED_END])
			mission_changed.emit()
		return
	var plot := get_storage_plot()
	if plot != null and not _twist_done and _construction.is_site(plot) and _construction.get_progress(plot) >= TWIST_AT:
		_twist_done = true
		if is_on_riverbank(plot):
			_construction.shorten(plot, TWIST_DAYS)
			_popups.show_on(plot, "Old foundation found!", CHATTER_COLOUR)
			_story.tell(TITLE, [STORY_TWIST])
	if _days_in >= MAX_DAYS:
		_fail()


func _on_construction_finished(plot: BuildingPlot) -> void:
	if plot.building_info.name != BUILDING:
		return
	_fill_tank(plot)
	if _stage == Stage.MISSION:
		_succeed()


# The mission is won: the drought ends and the colony recovers.
func _succeed() -> void:
	_stage = Stage.NONE
	_completed += 1
	_recovery_left = RECOVERY_DAYS
	_events.end_event(EventManager.Type.DROUGHT)
	_population.change_happiness(SUCCESS_HAPPINESS)
	var pages := STORY_SUCCESS.duplicate()
	pages.append("EVENT COMPLETED - THE LAST DROP\nFood production restored, with a %d%% bonus for %d days.\nThe Water Storage stays, and softens every drought to come.\nHappiness +%d. The colony has survived the drought." % [roundi((RECOVERY_BONUS - 1.0) * 100.0), int(RECOVERY_DAYS), SUCCESS_HAPPINESS])
	_story.tell(TITLE, pages)
	mission_changed.emit()


# The rain came back before the Water Storage was finished.
func _fail() -> void:
	_stage = Stage.NONE
	_events.end_event(EventManager.Type.DROUGHT)
	_population.change_happiness(FAILURE_HAPPINESS)
	_story.tell(TITLE, [STORY_FAILURE, "THE DROUGHT IS OVER\nThe colony came through it, but not unharmed. Happiness %d.\nThe Water Storage can still be built, ready for the next drought." % FAILURE_HAPPINESS])
	mission_changed.emit()


# Water rises in the finished tank, and it gives a little bounce.
func _fill_tank(plot: BuildingPlot) -> void:
	var tank := plot.building
	if not tank.has_method("set_water"):
		return
	tank.set_water(0.0)
	var tween := tank.create_tween()
	tween.tween_property(tank, "scale", Vector3.ONE * 1.12, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(tank, "scale", Vector3.ONE, 0.35)
	tween.tween_method(tank.set_water, 0.0, 0.85, 4.0)


# Villagers talk about the drought: a short line floats up from one of them.
func _chatter(days: float) -> void:
	_chatter_wait -= days
	if _chatter_wait > 0.0 or _civilians.get_count() == 0:
		return
	_chatter_wait = CHATTER_DAYS
	var lines: Array = CHATTER_BUILDING if _stage == Stage.MISSION and get_storage_plot() != null else CHATTER_WAITING
	if _stage == Stage.PROTECTED:
		lines = ["Good thing we built the tank", "The tank will see us through"]
	var speaker: Civilian = _civilians.get_civilians()[_chatter_index % _civilians.get_count()]
	if not speaker.is_inside():
		_popups.show_at(speaker.get_ground_position() + Vector3.UP * 4.5, lines[_chatter_index % lines.size()], CHATTER_COLOUR)
	_chatter_index += 1


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd). The game cannot be saved
# during an event, so a drought is never under way in a save.

func get_save_data() -> Dictionary:
	return { "recovery_left": _recovery_left, "completed": _completed, "twist_done": _twist_done }


func load_save_data(data: Dictionary) -> void:
	_stage = Stage.NONE
	_recovery_left = clampf(float(data.get("recovery_left", 0.0)), 0.0, RECOVERY_DAYS)
	_completed = int(data.get("completed", 0))
	_twist_done = bool(data.get("twist_done", false))
	# A tank in a loaded game is already full.
	var plot := get_storage_plot()
	if plot != null and not plot.under_construction and plot.building.has_method("set_water"):
		plot.building.set_water(0.85)
