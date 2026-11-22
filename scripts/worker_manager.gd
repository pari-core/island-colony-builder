# worker_manager.gd
# Creates the workers, gives them jobs and runs production.
#
# Rules:
#   - Each worker has at most one job.
#   - Each building has a limited number of worker slots.
#   - Output is fixed: it depends only on which workers are working, never on chance.
#   - A worker only produces after reaching the job.
#   - The colony's happiness raises or lowers output (see population_manager.gd).
#   - Sick workers produce nothing until they are treated.
#
# The worker model has no walking animation, so workers slide along in a fixed pose.
# Routes go around buildings (see path_grid.gd).
class_name WorkerManager
extends Node3D

# The user interface listens to this, so it updates when jobs change.
signal workers_changed
# Sent after a building makes something. stored is how much fitted into storage.
signal produced(plot: BuildingPlot, stored: int)

const WORKER_SCENE := preload("res://scenes/characters/Worker.tscn")

# Each worker's productivity is how much they make per production cycle. The
# first STARTING_WORKERS are there from the start; the rest join later, in this
# order, through population growth and the Migration event.
const WORKER_LIST := [
	{ "name": "Asha", "productivity": 5 },
	{ "name": "Ben", "productivity": 4 },
	{ "name": "Chen", "productivity": 4 },
	{ "name": "Dara", "productivity": 3 },
	{ "name": "Eli", "productivity": 3 },
	{ "name": "Farah", "productivity": 5 },
	{ "name": "Gita", "productivity": 4 },
	{ "name": "Hari", "productivity": 3 },
	{ "name": "Isla", "productivity": 4 },
	{ "name": "Jai", "productivity": 5 },
	{ "name": "Kiran", "productivity": 3 },
	{ "name": "Leela", "productivity": 4 },
]
const STARTING_WORKERS := 6

const PRODUCTION_SECONDS := 5.0
const MOVE_SPEED := 12.0         # Metres per second. Faster than real walking, to suit the game.
const IDLE_SPACING := 2.0        # Gap between idle workers, standing in the island's centre.
# Where the two workers stand on a plot, relative to its centre.
const SLOT_OFFSETS := [Vector3(-10.0, 0.0, 10.0), Vector3(10.0, 0.0, 10.0)]
# Where repair workers stand, on the other side of the building.
const REPAIR_OFFSETS := [Vector3(-10.0, 0.0, -10.0), Vector3(10.0, 0.0, -10.0)]

var _workers: Array[Worker] = []

@onready var _map: MapManager = get_node("../MapManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _population: PopulationManager = get_node("../PopulationManager")
@onready var _events: EventManager = get_node("../EventManager")
@onready var _research: ResearchManager = get_node("../ResearchManager")
@onready var _paths: PathGrid = get_node("../PathGrid")


func _ready() -> void:
	for i in STARTING_WORKERS:
		add_worker()


	# A Timer node calls produce() every PRODUCTION_SECONDS seconds.
	var timer := Timer.new()
	timer.wait_time = PRODUCTION_SECONDS
	timer.timeout.connect(produce)
	add_child(timer)
	timer.start()


# Slides each moving worker a little closer to its target every frame.
func _process(delta: float) -> void:
	for worker in _workers:
		# A newcomer on the migration boat is carried by the boat (migration_boat.gd).
		if worker.aboard or not worker.is_moving():
			continue
		var model := worker.model
		# Work out a new route when the target changes or a building goes up.
		if worker.path_goal != worker.target_position or worker.path_version != _paths.version or worker.path.is_empty():
			worker.path = _paths.find_path(model.position, worker.target_position)
			worker.path_goal = worker.target_position
			worker.path_version = _paths.version
		var here := Vector2(model.position.x, model.position.z)
		var goal := Vector2(worker.path[0].x, worker.path[0].z)
		var direction := goal - here
		if direction.length() > 0.0:
			model.rotation.y = atan2(direction.x, direction.y)
		here = here.move_toward(goal, MOVE_SPEED * delta)
		if here == goal and worker.path.size() > 1:
			worker.path.pop_front()
		# Follow the ground, so workers walk over hills instead of through them.
		model.position = Vector3(here.x, _terrain.get_height_at(here.x, here.y), here.y)
		if not worker.is_moving():
			model.position = worker.target_position
			model.rotation.y = worker.target_rotation
			# The building's output changes now that the worker has arrived.
			workers_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var plot := _map.get_selected_plot()
	if plot == null:
		return
	if event.is_action_pressed("assign_worker"):
		assign_worker(plot)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("remove_worker"):
		remove_worker(plot)
		get_viewport().set_input_as_handled()


func get_workers() -> Array[Worker]:
	return _workers


# Adds the next worker from WORKER_LIST. They appear at start_position if one is
# given (for example the beach, for migrants) and walk to the idle workers;
# otherwise they appear with the idle workers. Returns false when everyone on the
# list has already joined.
func add_worker(start_position = null) -> bool:
	if _workers.size() >= WORKER_LIST.size():
		return false
	var entry: Dictionary = WORKER_LIST[_workers.size()]
	var worker := Worker.new(entry.name, entry.productivity)
	worker.model = WORKER_SCENE.instantiate()
	worker.model.scale = Vector3.ONE * Civilian.BODY_SCALE   # Same size as civilians.
	add_child(worker.model)
	_workers.append(worker)
	_update_targets()
	# A new worker appears, then everyone else slides to make room.
	worker.model.position = worker.target_position if start_position == null else start_position
	worker.model.rotation.y = worker.target_rotation
	workers_changed.emit()
	return true


# Removes the newest worker, who leaves the colony. Returns false if there are no
# workers, or if that worker is busy with a repair or on the way to be treated
# (they stay until that is finished). GameStateManager calls this when happiness
# is 0. Only the newest worker ever leaves, so names in WORKER_LIST stay in order.
func remove_last_worker() -> bool:
	if _workers.is_empty():
		return false
	var leaver: Worker = _workers.back()
	if leaver.repair_plot != null or leaver.treatment_plot != null:
		return false
	_workers.pop_back()
	leaver.model.queue_free()
	_jobs_changed()
	return true


# Sends up to max_count idle workers to repair a collapsed building, and returns
# them. The list is empty if nobody is idle.
func send_repair_crew(plot: BuildingPlot, max_count: int) -> Array[Worker]:
	var crew: Array[Worker] = []
	for worker in _workers:
		if crew.size() < max_count and worker.is_idle():
			worker.repair_plot = plot
			crew.append(worker)
	if not crew.is_empty():
		_jobs_changed()
	return crew


# Sends sick workers to the Research Lab to be vaccinated. They keep their jobs
# and go back to them once treated.
func send_for_treatment(lab: BuildingPlot, patients: Array[Worker]) -> void:
	for worker in patients:
		worker.treatment_plot = lab
	_jobs_changed()


# Marks a worker as treated and sends them back to their job, or to the idle group.
func finish_treatment(worker: Worker) -> void:
	worker.is_sick = false
	worker.treatment_plot = null
	_jobs_changed()


# Recalculates where every worker should go, after another system changed them.
func refresh_targets() -> void:
	_jobs_changed()


# Sends a repair crew back to the idle workers.
func release_repair_crew(crew: Array[Worker]) -> void:
	for worker in crew:
		worker.repair_plot = null
	_jobs_changed()


func get_idle_count() -> int:
	return _workers.filter(func(worker: Worker) -> bool: return worker.is_idle()).size()


# Returns the workers on this plot, in the order they were assigned.
func get_workers_at(plot: BuildingPlot) -> Array[Worker]:
	return _workers.filter(func(worker: Worker) -> bool: return worker.job_plot == plot)


# Returns how many workers this plot's building can employ.
func get_slots(plot: BuildingPlot) -> int:
	return plot.building_info.get("worker_slots", 0)


# Gives the plot the first idle worker. Returns false if that is not possible.
func assign_worker(plot: BuildingPlot) -> bool:
	if get_workers_at(plot).size() >= get_slots(plot):
		return false
	for worker in _workers:
		if worker.is_idle():
			worker.job_plot = plot
			_jobs_changed()
			return true
	return false


# Makes the plot's most recently assigned worker idle. Returns false if it has none.
func remove_worker(plot: BuildingPlot) -> bool:
	var here := get_workers_at(plot)
	if here.is_empty():
		return false
	here[-1].job_plot = null
	_jobs_changed()
	return true


# Returns how much this plot's building makes per cycle with the workers who have
# reached it, adjusted for the colony's happiness, any events and research. Fractions are
# dropped. A building damaged by an accident makes nothing until it is repaired.
func get_output(plot: BuildingPlot) -> int:
	if plot.is_damaged or not plot.building_info.has("produces"):
		return 0
	var total := 0
	for worker in get_workers_at(plot):
		if not worker.is_moving() and not worker.is_sick:
			total += worker.productivity
	var multiplier := _population.get_productivity() * _events.get_output_multiplier(plot.building_info.produces)
	multiplier *= plot.building_info.get("output_scale", 1.0)
	multiplier *= _research.get_output_multiplier(plot.building_info.produces)
	return int(total * multiplier)


# One production cycle: each working building adds its workers' output.
func produce() -> void:
	for plot in _map.get_plots():
		if plot.building_info.has("produces") and get_output(plot) > 0:
			var stored := _resources.add(plot.building_info.produces, get_output(plot))
			produced.emit(plot, stored)


func _jobs_changed() -> void:
	_update_targets()
	workers_changed.emit()


# Sends working models to their plots, and idle ones to the island's centre.
func _update_targets() -> void:
	var idle_index := 0
	var used_slots := {}
	var used_repair_spots := {}
	var treatment_index := 0
	for worker in _workers:
		if worker.treatment_plot != null:
			# Patients wait in a ring around the Research Lab.
			var angle := treatment_index * TAU / 8.0
			treatment_index += 1
			var lab := worker.treatment_plot
			var ring := Vector3(cos(angle), 0.0, sin(angle)) * 13.0
			worker.target_position = Vector3(lab.position.x, _terrain.LAND_HEIGHT, lab.position.z) + ring
			worker.target_rotation = atan2(-ring.x, -ring.z)
		elif worker.repair_plot != null:
			var plot := worker.repair_plot
			var spot: int = used_repair_spots.get(plot, 0)
			used_repair_spots[plot] = spot + 1
			# Offsets are in the square's own directions, so turn them with it.
			var repair_offset: Vector3 = (REPAIR_OFFSETS[spot % REPAIR_OFFSETS.size()] as Vector3).rotated(Vector3.UP, plot.rotation.y)
			worker.target_position = Vector3(plot.position.x, _terrain.LAND_HEIGHT, plot.position.z) + repair_offset
			worker.target_rotation = atan2(-repair_offset.x, -repair_offset.z)
		elif worker.is_idle():
			var x := (idle_index - (_workers.size() - 1) * 0.5) * IDLE_SPACING
			worker.target_position = Vector3(x, _terrain.LAND_HEIGHT, 0.0)
			worker.target_rotation = 0.0
			idle_index += 1
		else:
			var plot := worker.job_plot
			var slot: int = used_slots.get(plot, 0)
			used_slots[plot] = slot + 1
			var offset: Vector3 = (SLOT_OFFSETS[slot] as Vector3).rotated(Vector3.UP, plot.rotation.y)
			worker.target_position = Vector3(plot.position.x, _terrain.LAND_HEIGHT, plot.position.z) + offset
			# On arrival, the worker turns to face the building.
			worker.target_rotation = atan2(-offset.x, -offset.z)


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


# One entry for each worker, in order: the plot number of their job, or -1 for
# none. Names and productivity come from WORKER_LIST, so they are not saved.
func get_save_data() -> Dictionary:
	var jobs := []
	for worker in _workers:
		jobs.append(-1 if worker.job_plot == null else worker.job_plot.plot_id)
	return { "jobs": jobs }


# Called after the buildings are back. Workers appear at their jobs.
func load_save_data(data: Dictionary) -> void:
	var jobs: Array = data.get("jobs", [])
	# Nobody is repairing or building yet in a game that is being loaded.
	for worker in _workers:
		worker.repair_plot = null
	while _workers.size() > jobs.size() and remove_last_worker():
		pass
	while _workers.size() < jobs.size() and add_worker():
		pass
	for i in mini(jobs.size(), _workers.size()):
		var plot := _map.get_plot(int(jobs[i]))
		_workers[i].job_plot = null
		if plot != null and get_workers_at(plot).size() < get_slots(plot):
			_workers[i].job_plot = plot
	_update_targets()
	for worker in _workers:
		worker.model.position = worker.target_position
		worker.model.rotation.y = worker.target_rotation
	workers_changed.emit()
