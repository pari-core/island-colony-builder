# save_manager.gd
# Saves the colony to a file and loads it back.
#
# The file is JSON: plain text that can be opened and read. Godot keeps it in the
# game's own data folder, which "user://" stands for.
#
# Each manager knows how to save and load its own part: it has get_save_data(),
# which returns a dictionary, and load_save_data(), which takes one back. This
# script only collects the parts into one file and hands them out again.
#
# Loading always starts from a brand new game: the scene is loaded again, and
# then the saved parts are put into it. That way nothing from the old game can
# be left behind.
#
# Rules:
#   - The game cannot be saved while an event is happening, or after it has been
#     won or lost. Events have many moving parts (repair crews, sick workers), so
#     saving waits until the island is calm.
#   - There is one save. Saving again replaces it.
#   - Workers and civilians appear at their jobs and homes, not where they stood.
class_name SaveManager
extends Node

signal game_saved
signal game_loaded

const VERSION := 1               # Raised when the file's layout changes. Older files are refused.
const DEFAULT_PATH := "user://island_colony_save.json"

# The parts of a save: the name used in the file, and the node that owns it.
# They are loaded in this order. Buildings come first, because jobs, homes, the
# storage limit and crop fields all depend on them.
const PARTS := [
	["time", "TimeManager"],
	["buildings", "BuildingManager"],
	["workers", "WorkerManager"],
	["construction", "ConstructionManager"],
	["civilians", "CivilianManager"],
	["research", "ResearchManager"],
	["resources", "ResourceManager"],
	["population", "PopulationManager"],
	["events", "EventManager"],
	["crops", "CropManager"],
	["drought", "DroughtMission"],
	["state", "GameStateManager"],
]

# A save waiting to be put into the scene that is about to load. A static
# variable keeps its value when the scene is loaded again.
static var _pending := {}

# The tests use a different file, so they never touch the player's save.
var save_path := DEFAULT_PATH

@onready var _events: EventManager = get_node("../EventManager")
@onready var _state: GameStateManager = get_node("../GameStateManager")
@onready var _popups: PopupManager = get_node("../Popups")


func _ready() -> void:
	if not _pending.is_empty():
		var data := _pending
		_pending = {}
		# Deferred, so every manager has finished starting up first.
		apply.call_deferred(data)


# Returns why the game cannot be saved now, or "" if it can.
func get_save_problem() -> String:
	if _state.get_state() == GameStateManager.State.WON or _state.get_state() == GameStateManager.State.LOST:
		return "The game has ended"
	if not _events.get_active().is_empty():
		return "Wait for the event to end, then save"
	return ""


# Writes the colony to the save file. Returns false if that is not possible.
func save_game() -> bool:
	if get_save_problem() != "":
		return false
	var data := { "version": VERSION, "saved_at": Time.get_datetime_string_from_system(false, true) }
	for part: Array in PARTS:
		data[part[0]] = get_node("../" + part[1]).get_save_data()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		print("Could not write the save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("Game saved")
	game_saved.emit()
	return true


# Reads the save file. Returns an empty dictionary if there is no file, or it is
# damaged, or it was made by a different version of the game.
func read_save() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK:
		return {}
	var data = json.data
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return {}
	return data


func has_save() -> bool:
	return not read_save().is_empty()


# When the save was made, such as "2026-11-15 14:02", or "" if there is none.
func get_save_time() -> String:
	return str(read_save().get("saved_at", "")).left(16)


# Loads the saved game: starts the scene again, then puts the save into it.
# Returns false if there is nothing to load. Only the running game can do this;
# tests that build the scene themselves call apply() on a new scene instead.
func load_game() -> bool:
	var data := read_save()
	if data.is_empty() or get_tree().current_scene != get_parent():
		return false
	_pending = data
	get_tree().paused = false
	# Deferred, so the menu that asked for this can finish closing first.
	get_tree().reload_current_scene.call_deferred()
	return true


# Puts a save into this scene, which must be a brand new game.
func apply(data: Dictionary) -> void:
	for part: Array in PARTS:
		var saved = data.get(part[0])
		if saved is Dictionary:
			get_node("../" + part[1]).load_save_data(saved)
	_popups.clear()
	print("Game loaded")
	game_loaded.emit()
