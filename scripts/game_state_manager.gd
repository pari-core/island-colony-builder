# game_state_manager.gd
# Decides when the game is won or lost, keeps the score, and shows the end screen.
#
# Everything is checked once per upkeep cycle (every 10 seconds, see
# population_manager.gd), so the thresholds are exact and easy to test:
#
# Both ways of winning also need the colony to have been through every event in
# the schedule (EventManager.ORDER) at least once, so a game cannot be won
# before the player has faced them all.
#
#   WIN   WIN_POPULATION people or more AND happiness WIN_HAPPINESS or more,
#         for WIN_CYCLES upkeep cycles in a row.
#   WIN   All the landmarks are finished (the buildings marked "landmark" in
#         BuildingManager.BUILDINGS: Lighthouse, Harbour and Town Hall).
#         Checked when a landmark is finished and each upkeep cycle.
#   LOSE  Starvation: not enough food for STARVE_CYCLES cycles in a row.
#   LOSE  Storage full: food, wood, stone and gold all at the storage limit for
#         STORAGE_CYCLES cycles in a row (checked just before the colony eats).
#   LOSE  Nobody left: while happiness is 0, one person leaves each cycle,
#         civilians first. The game is lost when the population reaches 0.
#
# When the game ends, the scene tree is paused and an end screen shows the result
# and the score. Enter (event_respond, the ESP32 Action button later) starts a
# new game. After a win, N (event_decline, the ESP32 Back later) keeps playing
# the same colony in free play: the game can no longer be won or lost, so every
# event can still be shown, but people still leave if happiness is 0.
class_name GameStateManager
extends Node

signal state_changed

enum State { PLAYING, WON, LOST, FREE_PLAY }

const WIN_POPULATION := 24
const WIN_HAPPINESS := 70
const WIN_CYCLES := 3
const STARVE_CYCLES := 6
const STORAGE_CYCLES := 6
# Score: points for each person, each point of happiness and each building.
const SCORE_PER_PERSON := 10
const SCORE_PER_HAPPINESS := 1
const SCORE_PER_BUILDING := 5

# Tests that call upkeep() many times switch this off, so the game does not end
# or lose people in the middle of them.
var enabled := true

var _state := State.PLAYING
var _reason := ""                # Why the game ended, for the end screen.
var _win_cycles := 0
var _hungry_cycles := 0
var _full_cycles := 0
var _storage_was_full := false   # Sampled before the colony eats.
var _end_screen: CanvasLayer = null

@onready var _population: PopulationManager = get_node("../PopulationManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _civilians: CivilianManager = get_node("../CivilianManager")
@onready var _map: MapManager = get_node("../MapManager")
@onready var _events: EventManager = get_node("../EventManager")


func _ready() -> void:
	# Keep running while the tree is paused, so Enter can restart the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_population.upkeep_started.connect(_on_upkeep_started)
	_population.upkeep_finished.connect(_on_upkeep_finished)
	get_node("../ConstructionManager").construction_finished.connect(_on_construction_finished)


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.WON and _state != State.LOST:
		return
	if event.is_action_pressed("event_respond"):
		get_viewport().set_input_as_handled()
		restart()
	elif _state == State.WON and event.is_action_pressed("event_decline"):
		get_viewport().set_input_as_handled()
		keep_playing()


func get_state() -> State:
	return _state


func get_reason() -> String:
	return _reason


# Cycles in a row that the win target has been met (0 to WIN_CYCLES).
func get_win_cycles() -> int:
	return _win_cycles


# Seconds until the colony starves, or -1 if it is not hungry.
func get_starvation_seconds_left() -> int:
	if _hungry_cycles == 0:
		return -1
	return int((STARVE_CYCLES - _hungry_cycles) * PopulationManager.UPKEEP_SECONDS)


# Seconds until full storage loses the game, or -1 if storage is not all full.
func get_storage_seconds_left() -> int:
	if _full_cycles == 0:
		return -1
	return int((STORAGE_CYCLES - _full_cycles) * PopulationManager.UPKEEP_SECONDS)


func get_score() -> int:
	var buildings := 0
	for plot in _map.get_plots():
		if plot.building != null:
			buildings += 1
	return (_population.get_population() * SCORE_PER_PERSON
		+ _population.get_happiness() * SCORE_PER_HAPPINESS
		+ buildings * SCORE_PER_BUILDING)


# Starts a new game by loading the scene again.
func restart() -> void:
	get_tree().paused = false
	if get_tree().current_scene != null:
		get_tree().reload_current_scene()


# Carries on with the same colony after a win, with no more winning or losing.
func keep_playing() -> void:
	if _state != State.WON:
		return
	_state = State.FREE_PLAY
	_end_screen.queue_free()
	_end_screen = null
	get_tree().paused = false
	state_changed.emit()


# The second way to win: every landmark is finished. A landmark that comes back
# from a saved game sends no signal, so loading cannot win a second time.
func _on_construction_finished(plot: BuildingPlot) -> void:
	if plot.building_info.has("landmark"):
		_check_landmark_win()


# Wins if every landmark is finished and every event has been faced. Checked
# when a landmark is finished, and again each upkeep cycle in case the last
# event ends after the last landmark. (Waiting for the cycle lets an event's
# closing story be read first.)
func _check_landmark_win() -> void:
	if not enabled or _state != State.PLAYING:
		return
	if get_landmarks_built() < get_landmarks().size() or not _events.has_faced_all():
		return
	_finish(State.WON, "The colony raised all %d landmarks: %s." % [get_landmarks().size(), ", ".join(get_landmark_names())])
	state_changed.emit()


# The landmarks' entries in BuildingManager.BUILDINGS, in list order.
static func get_landmarks() -> Array[Dictionary]:
	var landmarks: Array[Dictionary] = []
	for building: Dictionary in BuildingManager.BUILDINGS:
		if building.has("landmark"):
			landmarks.append(building)
	return landmarks


static func get_landmark_names() -> Array[String]:
	var names: Array[String] = []
	for building in get_landmarks():
		names.append(building.name)
	return names


# The plot a landmark stands on (finished or still a building site), or null.
func get_landmark_plot(landmark_name: String) -> BuildingPlot:
	for plot in _map.get_plots():
		if plot.building != null and plot.building_info.name == landmark_name:
			return plot
	return null


# How many landmarks are finished.
func get_landmarks_built() -> int:
	var built := 0
	for landmark_name in get_landmark_names():
		var plot := get_landmark_plot(landmark_name)
		if plot != null and not plot.under_construction:
			built += 1
	return built


func _on_upkeep_started() -> void:
	_storage_was_full = true
	for type in ResourceManager.Type.values():
		if _resources.get_amount(type) < _resources.get_capacity():
			_storage_was_full = false


func _on_upkeep_finished() -> void:
	if not enabled or _state == State.WON or _state == State.LOST:
		return

	# People leave a colony with no happiness left.
	if _population.get_happiness() == 0:
		if _civilians.remove_civilian():
			print("A civilian left the unhappy colony")
		elif _workers.remove_last_worker():
			print("A worker left the unhappy colony")
	if _state == State.FREE_PLAY:
		return

	_hungry_cycles = 0 if _population.was_fed() else _hungry_cycles + 1
	_full_cycles = _full_cycles + 1 if _storage_was_full else 0
	var target_met := _population.get_population() >= WIN_POPULATION and _population.get_happiness() >= WIN_HAPPINESS
	_win_cycles = _win_cycles + 1 if target_met else 0

	if _population.get_population() == 0:
		_finish(State.LOST, "Everyone has left the colony.")
	elif _hungry_cycles >= STARVE_CYCLES:
		_finish(State.LOST, "The colony starved: no food for %d seconds." % int(STARVE_CYCLES * PopulationManager.UPKEEP_SECONDS))
	elif _full_cycles >= STORAGE_CYCLES:
		_finish(State.LOST, "Storage was completely full for %d seconds, and everything new was wasted." % int(STORAGE_CYCLES * PopulationManager.UPKEEP_SECONDS))
	elif _win_cycles >= WIN_CYCLES and _events.has_faced_all():
		_finish(State.WON, "The colony reached %d people with happiness %d." % [_population.get_population(), _population.get_happiness()])
	else:
		_check_landmark_win()
	state_changed.emit()


func _finish(new_state: State, reason: String) -> void:
	_state = new_state
	_reason = reason
	print("Game over: %s %s" % ["WON." if new_state == State.WON else "LOST.", reason])
	_show_end_screen()
	get_tree().paused = true


# A dark sheet over the game with the result in the middle. It is built here in
# code because it only exists once the game has ended.
func _show_end_screen() -> void:
	_end_screen = CanvasLayer.new()
	_end_screen.name = "EndScreen"
	_end_screen.layer = 10
	add_child(_end_screen)

	var sheet := ColorRect.new()
	sheet.color = Color(0.0, 0.0, 0.0, 0.65)
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.add_child(sheet)

	var won := _state == State.WON
	var text := Label.new()
	text.name = "Text"
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 40)
	text.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4) if won else Color(1.0, 0.55, 0.5))
	text.text = "%s\n\n%s\n\nPeople %d     Happiness %d     Score %d\n\n%s" % [
		"YOU WIN" if won else "COLONY LOST",
		_reason,
		_population.get_population(),
		_population.get_happiness(),
		get_score(),
		"Press Enter to play again, or N to keep playing this colony" if won else "Press Enter to play again",
	]
	_end_screen.add_child(text)


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


func get_save_data() -> Dictionary:
	return {
		"free_play": _state == State.FREE_PLAY,
		"win_cycles": _win_cycles,
		"hungry_cycles": _hungry_cycles,
		"full_cycles": _full_cycles,
	}


# A finished game cannot be saved, so the state is always playing or free play.
func load_save_data(data: Dictionary) -> void:
	_state = State.FREE_PLAY if bool(data.get("free_play", false)) else State.PLAYING
	_win_cycles = int(data.get("win_cycles", 0))
	_hungry_cycles = int(data.get("hungry_cycles", 0))
	_full_cycles = int(data.get("full_cycles", 0))
	state_changed.emit()
