# research_manager.gd
# Research done at the Research Lab. There are four projects:
#
#   Vaccine              Lets the colony treat disease outbreaks.
#   Improved Farming     Farms make 20% more food.
#   Efficient Tools      Lumber Camps and Quarries make 20% more. Needs Improved Farming.
#   Storage Engineering  The storage limit is 25% higher. Needs Efficient Tools.
#
# The three upgrades form a simple chain (the "upgrade tree" of section 16 of the
# specification); the vaccine stands alone. One project runs at a time, and it
# only moves forward while a working Research Lab stands. An upgrade lasts for
# the rest of the game.
#
# To research: select a built Research Lab and press Space for its menu. R is a
# shortcut for the vaccine.
class_name ResearchManager
extends Node

signal research_changed
# Sent once when a project is finished.
signal research_finished(id: String)

const FARMING_BONUS := 1.2       # Food from Farms, with Improved Farming.
const TOOLS_BONUS := 1.2         # Wood and stone, with Efficient Tools.
const STORAGE_BONUS := 1.25      # The storage limit, with Storage Engineering.

# First guesses, to be balanced once the game is playable.
const PROJECTS := {
	"vaccine": {
		"name": "Vaccine",
		"cost": { ResourceManager.Type.GOLD: 15 },
		"seconds": 45.0,
		"effect": "treats disease outbreaks",
	},
	"farming": {
		"name": "Improved Farming",
		"cost": { ResourceManager.Type.GOLD: 10 },
		"seconds": 30.0,
		"effect": "food production +20%",
	},
	"tools": {
		"name": "Efficient Tools",
		"cost": { ResourceManager.Type.GOLD: 15 },
		"seconds": 40.0,
		"effect": "wood and stone production +20%",
		"requires": "farming",
	},
	"storage": {
		"name": "Storage Engineering",
		"cost": { ResourceManager.Type.GOLD: 20 },
		"seconds": 40.0,
		"effect": "storage limit +25%",
		"requires": "tools",
	},
}
# The upgrades, in the order they must be researched.
const UPGRADES := ["farming", "tools", "storage"]

var _finished := {}
var _current := ""               # The project being researched, or "" for none.
var _progress := 0.0             # Seconds of research done on the current project.

@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _map: MapManager = get_node("../MapManager")


# Research only moves forward while a working Research Lab stands.
func _process(delta: float) -> void:
	if _current == "" or not has_working_lab():
		return
	_progress += delta
	if _progress >= PROJECTS[_current].seconds:
		var id := _current
		_finished[id] = true
		print("Research finished: %s" % PROJECTS[id].name)
		_current = ""
		_progress = 0.0
		_resources.refresh_storage()
		research_changed.emit()
		research_finished.emit(id)


func _unhandled_input(event: InputEvent) -> void:
	var plot := _map.get_selected_plot()
	if plot == null or plot.building_info.get("name", "") != "Research Lab":
		return
	if event.is_action_pressed("start_research"):
		start("vaccine")
		get_viewport().set_input_as_handled()


func has_working_lab() -> bool:
	return get_working_lab() != null


# Returns the first Research Lab that is standing, or null if there is none.
func get_working_lab() -> BuildingPlot:
	for plot in _map.get_plots():
		if plot.building_info.get("name", "") == "Research Lab" and not plot.is_damaged:
			return plot
	return null


func is_finished(id: String) -> bool:
	return _finished.has(id)


func get_current() -> String:
	return _current


# Returns how far the current project is, from 0.0 to 1.0.
func get_progress() -> float:
	return 0.0 if _current == "" else _progress / PROJECTS[_current].seconds


# How much more buildings make of this resource because of research: 1.0 is no
# change. worker_manager.gd multiplies production by this.
func get_output_multiplier(type: ResourceManager.Type) -> float:
	if type == ResourceManager.Type.FOOD and is_finished("farming"):
		return FARMING_BONUS
	if (type == ResourceManager.Type.WOOD or type == ResourceManager.Type.STONE) and is_finished("tools"):
		return TOOLS_BONUS
	return 1.0


# How much bigger the storage limit is because of research: 1.0 is no change.
# resource_manager.gd multiplies the limit by this.
func get_storage_multiplier() -> float:
	return STORAGE_BONUS if is_finished("storage") else 1.0


# Why this project cannot be started now, or "" if it can.
func get_problem(id: String) -> String:
	var project: Dictionary = PROJECTS[id]
	if is_finished(id):
		return "%s is already researched" % project.name
	if _current == id:
		return "Already researching %s" % project.name
	if _current != "":
		return "The Lab is busy with %s" % PROJECTS[_current].name
	if not has_working_lab():
		return "Research needs a working Research Lab"
	if project.has("requires") and not is_finished(project.requires):
		return "Research %s first" % PROJECTS[project.requires].name
	if not _resources.can_afford(project.cost):
		return "Not enough resources (needs %s)" % _resources.describe_cost(project.cost)
	return ""


# One line about a project for menus: name, effect, cost and time.
func describe(id: String) -> String:
	var project: Dictionary = PROJECTS[id]
	return "%s: %s (%s, %d s)" % [project.name, project.effect, _resources.describe_cost(project.cost), int(project.seconds)]


# A few words on how far a project is, for the selection panel.
func get_status(id: String) -> String:
	if is_finished(id):
		return "done"
	if _current == id:
		return "%d%%" % int(get_progress() * 100.0)
	var project: Dictionary = PROJECTS[id]
	if project.has("requires") and not is_finished(project.requires):
		return "locked"
	return "ready"


# Starts a project and pays for it. Returns false if that is not possible.
func start(id: String) -> bool:
	if get_problem(id) != "":
		return false
	if not _resources.spend(PROJECTS[id].cost):
		return false
	_current = id
	_progress = 0.0
	research_changed.emit()
	return true


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


func get_save_data() -> Dictionary:
	return { "finished": _finished.keys(), "current": _current, "progress": _progress }


func load_save_data(data: Dictionary) -> void:
	_finished.clear()
	for id in data.get("finished", []):
		if PROJECTS.has(id):
			_finished[id] = true
	_current = str(data.get("current", ""))
	if not PROJECTS.has(_current):
		_current = ""
	_progress = float(data.get("progress", 0.0)) if _current != "" else 0.0
	_resources.refresh_storage()
	research_changed.emit()
