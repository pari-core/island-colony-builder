# civilian_manager.gd
# Creates the colony's civilians and gives each one a home to wander around.
#
# Civilians live in Houses, eat food and count towards happiness. They do not take
# jobs themselves, but the player can train one into a worker: select a House and
# press T (train_worker). This costs TRAIN_COST, and the new worker appears where
# the civilian was. Growing civilians is therefore how the colony gets new workers.
#
# Each House has room for PEOPLE_PER_HOUSE people, workers and civilians together
# (see population_manager.gd). Civilians without a House wander in the centre of
# the island.
class_name CivilianManager
extends Node3D

signal civilians_changed
signal worker_trained(plot: BuildingPlot)

const STARTING_CIVILIANS := 4
const MAX_CIVILIANS := 20
# Men and women take turns, so the colony has both.
const MODELS := [
	{ "walking": preload("res://assets/characters/civilians/female_walking.fbx"), "idle": preload("res://assets/characters/civilians/female_idle.fbx") },
	{ "walking": preload("res://assets/characters/civilians/male_walking.fbx"), "idle": preload("res://assets/characters/civilians/male_idle.fbx") },
]
const CENTRE := Vector3(0.0, 0.0, 0.0)
const TRAIN_COST := { ResourceManager.Type.FOOD: 10 }

var _civilians: Array[Civilian] = []
var _idle_animations: Array[Animation] = []
var _created := 0   # Civilians ever created. Picks the model and route seed.

@onready var _map: MapManager = get_node("../MapManager")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _paths: PathGrid = get_node("../PathGrid")


func _ready() -> void:
	# Take the idle animation out of each idle file once, so every civilian can share it.
	for model in MODELS:
		var source: Node = model.idle.instantiate()
		var player := _find_player(source)
		var library := player.get_animation_library("")
		_idle_animations.append(library.get_animation(library.get_animation_list()[0]))
		source.free()
	for i in STARTING_CIVILIANS:
		add_civilian()


# T on a selected House trains a civilian into a worker.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("train_worker"):
		var plot := _map.get_selected_plot()
		if plot != null and plot.building_info.get("name", "") == "House":
			train_worker(plot)
			get_viewport().set_input_as_handled()


func get_count() -> int:
	return _civilians.size()


func get_civilians() -> Array[Civilian]:
	return _civilians


# Adds a civilian, standing at their home. Returns false at the maximum.
func add_civilian() -> bool:
	if _civilians.size() >= MAX_CIVILIANS:
		return false
	var index := _civilians.size()
	var civilian := Civilian.new()
	add_child(civilian)
	var model: Dictionary = MODELS[_created % MODELS.size()]
	var houses := _get_houses()
	var home := CENTRE if houses.is_empty() else houses[index % houses.size()]
	var start := home + Vector3(Civilian.WANDER_MIN, 0.0, 0.0).rotated(Vector3.UP, index * 1.3)
	civilian.position = Vector3(start.x, _terrain.get_height_at(start.x, start.z), start.z)
	civilian.setup(model.walking, _idle_animations[_created % MODELS.size()], _terrain, _paths, 1000 + _created)
	civilian.set_home(home, not houses.is_empty(), _turn_at(home))
	_created += 1
	_civilians.append(civilian)
	civilians_changed.emit()
	return true


# Returns why a civilian cannot be trained at this plot, or "" if they can.
func get_training_problem(plot: BuildingPlot) -> String:
	if plot == null or plot.building_info.get("name", "") != "House" or plot.is_damaged:
		return "Select a standing House to train a worker"
	if _civilians.is_empty():
		return "There are no civilians to train"
	if _workers.get_workers().size() >= WorkerManager.WORKER_LIST.size():
		return "The colony already has the most workers (%d)" % WorkerManager.WORKER_LIST.size()
	if not _resources.can_afford(TRAIN_COST):
		return "Not enough food to train a worker (needs %s)" % _resources.describe_cost(TRAIN_COST)
	return ""


# Turns a civilian into a worker, preferring one who lives in this House. The new
# worker appears where the civilian was (at the door if they were inside) and
# walks to the idle line. Returns false, and prints why, if it is not possible.
func train_worker(plot: BuildingPlot) -> bool:
	var problem := get_training_problem(plot)
	if problem != "":
		print(problem)
		return false
	var house := Vector3(plot.position.x, 0.0, plot.position.z)
	var chosen: Civilian = _civilians.back()
	for civilian in _civilians:
		if civilian.has_house and civilian.home.is_equal_approx(house):
			chosen = civilian
	_resources.spend(TRAIN_COST)
	_workers.add_worker(chosen.get_ground_position())
	_civilians.erase(chosen)
	chosen.queue_free()
	update_homes()
	civilians_changed.emit()
	worker_trained.emit(plot)
	print("A civilian was trained into a worker")
	return true


# Removes the newest civilian, who leaves the colony. Returns false if there are
# none. GameStateManager calls this when happiness is 0.
func remove_civilian() -> bool:
	if _civilians.is_empty():
		return false
	var leaver: Civilian = _civilians.pop_back()
	leaver.queue_free()
	update_homes()
	civilians_changed.emit()
	return true


# How many civilians are inside this House right now.
func get_inside_count(plot: BuildingPlot) -> int:
	var house := Vector3(plot.position.x, 0.0, plot.position.z)
	var count := 0
	for civilian in _civilians:
		if civilian.is_inside() and civilian.home.is_equal_approx(house):
			count += 1
	return count


# Gives civilians new homes after a House is built, collapses or is repaired.
# Civilians share out the standing Houses in turn. Without a House, home is the
# centre of the island.
func update_homes() -> void:
	var houses := _get_houses()
	for i in _civilians.size():
		if houses.is_empty():
			_civilians[i].set_home(CENTRE, false)
		else:
			_civilians[i].set_home(houses[i % houses.size()], true, _turn_at(houses[i % houses.size()]))


# The rotation of the House standing at this position, or 0 if there is none.
func _turn_at(house: Vector3) -> float:
	var plot := _map.get_plot_at(house)
	return 0.0 if plot == null else plot.rotation.y


func _get_houses() -> Array[Vector3]:
	var houses: Array[Vector3] = []
	for plot in _map.get_plots():
		if plot.building_info.get("name", "") == "House" and not plot.is_damaged:
			houses.append(Vector3(plot.position.x, 0.0, plot.position.z))
	return houses


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


func get_save_data() -> Dictionary:
	return { "count": _civilians.size(), "created": _created }


# Called after the buildings are back, so civilians get their homes.
func load_save_data(data: Dictionary) -> void:
	var count := clampi(int(data.get("count", STARTING_CIVILIANS)), 0, MAX_CIVILIANS)
	while _civilians.size() > count:
		remove_civilian()
	while _civilians.size() < count:
		add_civilian()
	_created = maxi(int(data.get("created", _created)), _created)
	update_homes()
