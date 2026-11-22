# construction_manager.gd
# Buildings that take time to build.
#
# A building with "build_days" in BuildingManager.BUILDINGS does not appear
# finished. It starts as a building site, and idle workers walk over and build
# it over that many in-game days. Buildings without "build_days" are finished
# at once, as before.
#
# Rules:
#   - A site takes up to "builders" idle workers. They are busy until it is done.
#   - Work only moves forward while a builder is standing at the site. With one
#     builder out of two it goes at half speed.
#   - Time comes from TimeManager, in days, never from a seconds timer.
#   - A site does nothing useful until it is finished.
#
# Builders are sent with the same function that sends a repair crew, so they
# cannot be given a second job at the same time.
class_name ConstructionManager
extends Node3D

signal construction_started(plot: BuildingPlot)
signal construction_finished(plot: BuildingPlot)

const SIGN_HEIGHT := 9.0         # Metres above the ground the progress sign floats.
const SHORTEST_DAYS := 0.25      # shorten() never makes a job quicker than this.

# Plot -> { "done": days of work done, "total": days needed, "builders": int,
# "crew": Array[Worker], "sign": Label3D }
var _sites := {}

@onready var _builder: BuildingManager = get_node("../BuildingManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _time: TimeManager = get_node("../TimeManager")
@onready var _terrain: Node = get_node("../Island/Terrain")


func _ready() -> void:
	_builder.building_placed.connect(_on_building_placed)
	_time.time_passed.connect(_on_time_passed)


func is_site(plot: BuildingPlot) -> bool:
	return _sites.has(plot)


# The plots being built on now.
func get_sites() -> Array:
	return _sites.keys()


# How far built this plot is, from 0 to 1. A finished building returns 1.
func get_progress(plot: BuildingPlot) -> float:
	if not _sites.has(plot):
		return 1.0
	return clampf(_sites[plot].done / _sites[plot].total, 0.0, 1.0)


# Days of work still to do, with the full crew.
func get_days_left(plot: BuildingPlot) -> float:
	return maxf(_sites[plot].total - _sites[plot].done, 0.0) if _sites.has(plot) else 0.0


func get_crew(plot: BuildingPlot) -> Array:
	return _sites[plot].crew if _sites.has(plot) else []


# How many builders are standing at the site and working.
func get_working(plot: BuildingPlot) -> int:
	var working := 0
	for worker: Worker in get_crew(plot):
		if not worker.is_moving() and not worker.is_sick and worker.treatment_plot == null:
			working += 1
	return working


# Makes the job this many days shorter. Returns false if this is not a site.
func shorten(plot: BuildingPlot, days: float) -> bool:
	if not _sites.has(plot):
		return false
	_sites[plot].total = maxf(_sites[plot].total - days, SHORTEST_DAYS)
	_show_progress(plot)
	return true


# One line for the screen about this site.
func get_status(plot: BuildingPlot) -> String:
	if not _sites.has(plot):
		return ""
	var site: Dictionary = _sites[plot]
	var percent := int(get_progress(plot) * 100.0)
	if site.crew.is_empty():
		return "%d%% built. Waiting for idle workers: take %d off their jobs" % [percent, site.builders]
	if get_working(plot) == 0:
		return "%d%% built. The builders are on their way" % percent
	return "%d%% built by %d of %d builders, %.1f days left" % [percent, get_working(plot), site.builders, get_days_left(plot) * site.builders / get_working(plot)]


func _on_building_placed(plot: BuildingPlot) -> void:
	if not plot.building_info.has("build_days"):
		return
	plot.under_construction = true
	var sign := Label3D.new()
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.fixed_size = true
	sign.pixel_size = 0.0007
	sign.font_size = 36
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.9, 0.55)
	sign.no_depth_test = true
	add_child(sign)
	sign.position = Vector3(plot.position.x, _terrain.LAND_HEIGHT + SIGN_HEIGHT, plot.position.z)
	_sites[plot] = {
		"done": 0.0,
		"total": float(plot.building_info.build_days),
		"builders": int(plot.building_info.get("builders", 1)),
		"crew": [],
		"sign": sign,
	}
	_fill_crew(plot)
	_show_progress(plot)
	construction_started.emit(plot)


func _on_time_passed(days: float) -> void:
	for plot: BuildingPlot in _sites.keys():
		var site: Dictionary = _sites[plot]
		_fill_crew(plot)
		site.done += days * get_working(plot) / site.builders
		if site.done >= site.total:
			_finish(plot, false)
		else:
			_show_progress(plot)


# Takes idle workers until the site has all the builders it needs.
func _fill_crew(plot: BuildingPlot) -> void:
	var site: Dictionary = _sites[plot]
	if site.crew.size() < site.builders:
		site.crew.append_array(_workers.send_repair_crew(plot, site.builders - site.crew.size()))


func _show_progress(plot: BuildingPlot) -> void:
	var site: Dictionary = _sites[plot]
	if plot.building.has_method("set_progress"):
		plot.building.set_progress(get_progress(plot))
	if site.crew.is_empty():
		site.sign.text = "Needs %d idle workers" % site.builders
	else:
		site.sign.text = "Building %d%%" % int(get_progress(plot) * 100.0)


# quiet is true when a saved game is loaded: the building is simply finished,
# with no signal, so nothing celebrates it a second time.
func _finish(plot: BuildingPlot, quiet: bool) -> void:
	var site: Dictionary = _sites[plot]
	_sites.erase(plot)
	site.sign.queue_free()
	plot.under_construction = false
	if plot.building.has_method("set_progress"):
		plot.building.set_progress(1.0)
	if not site.crew.is_empty():
		var crew: Array[Worker] = []
		crew.assign(site.crew)
		_workers.release_repair_crew(crew)
	get_node("../PathGrid").refresh()
	if not quiet:
		print("Finished building the %s on plot %d" % [plot.building_info.name, plot.plot_id])
		construction_finished.emit(plot)


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).

func get_save_data() -> Dictionary:
	var sites := []
	for plot: BuildingPlot in _sites:
		sites.append({ "plot": plot.plot_id, "done": _sites[plot].done, "total": _sites[plot].total })
	return { "sites": sites }


# Called after the buildings and workers are back. Putting a building back
# starts it as a site, so here each one is either set to its saved progress or,
# if the save does not list it, finished.
func load_save_data(data: Dictionary) -> void:
	var saved := {}
	for entry: Dictionary in data.get("sites", []):
		saved[int(entry.get("plot", 0))] = entry
	for plot: BuildingPlot in _sites.keys():
		if saved.has(plot.plot_id):
			var site: Dictionary = _sites[plot]
			site.total = maxf(float(saved[plot.plot_id].get("total", site.total)), SHORTEST_DAYS)
			site.done = clampf(float(saved[plot.plot_id].get("done", 0.0)), 0.0, site.total * 0.999)
			site.crew = []   # Loading the workers sent everyone back; pick builders again.
			_fill_crew(plot)
			_show_progress(plot)
		else:
			_sites[plot].crew = []
			_finish(plot, true)
