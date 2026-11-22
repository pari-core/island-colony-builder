# map_manager.gd
# Creates the building plots and is the one place other systems ask about them.
#
# Buildings can go anywhere on the flat land around the town. That land is
# divided into a grid of build squares (called plots in the code): each is a
# 24 m square with a 4 m lane to the next, and holds one building. A square is
# only created where the ground is flat, so there are none on the rocky hill,
# the lake, the river or the beach, and none across the river, which has no
# bridge. The middle square is left out too: it is the town square, where idle
# workers wait and homeless civilians wander.
#
# Plots are numbered from the centre outwards, so plot 1 is beside the town
# square. Only the MAX_PLOTS nearest the town square are made (team decision,
# 2026-11-18): with so few places to build, choosing what goes where is part of
# the game.
#
# The outlines are hidden during normal play and only appear while the player is
# placing a building, or on the plot that is selected. Hiding them does not affect
# the plots or their states.
#
# @tool means the plots also appear in the Godot editor's 3D view, where they stay
# visible for checking the layout. They are not saved into the scene file, because
# they are created fresh each time.
@tool
class_name MapManager
extends Node3D

# Other systems, such as the future user interface, can connect to this signal to
# hear when the selection changes. The plot is null when nothing is selected.
signal selection_changed(plot: BuildingPlot)

const SPACING := 28.0        # Centre-to-centre distance: a 24 m plot plus a 4 m lane.
const BUILD_RADIUS := 185.0  # Plot centres lie within this distance of the town square.
const FLAT_MARGIN := 2.0     # The ground must be flat this far beyond a plot's edges.
const GROUND_LIFT := 0.1     # Raises outlines slightly so they do not flicker into the ground.
const MAX_PLOTS := 20        # How many build squares there are. The spec asks for at least 12.
# v2 "village" layout (team decision, 2026-11-21): the squares are no longer a
# tidy block. They are scattered over the land around the town square, a
# different distance apart, each turned to face roughly towards the square, the
# way a village grows. A fixed seed puts them in the same places every game.
const LAYOUT_SEED := 2027
const SPREAD_NEAR := 36.0    # The nearest squares start this far from the town square...
const SPREAD_FAR := 165.0    # ...and the furthest are this far out.
const MIN_GAP := 36.0        # Least distance between two squares' centres (room for a road and trees).
const FACE_JITTER := 0.12    # Radians a square may turn away from facing the town square.
# The rings: radius in metres, how many squares, and where the first one starts (radians).
const RINGS := [Vector3(44.0, 7.0, 0.3), Vector3(82.0, 9.0, 0.1), Vector3(120.0, 9.0, 0.55), Vector3(156.0, 9.0, 0.25)]   # (The earlier ring layout.)
const GRID_STEP := 36.0      # Centre to centre: a 24 m square and a 12 m path between.
const RING_JITTER := 0.05    # Radians a square may slip along its ring.
const POND_CLEARANCE := 26.0 # Metres between a pond's edge and a square's centre.

var _plots: Array[BuildingPlot] = []
var _selected_plot: BuildingPlot = null

# Island comes before MapManager in the scene, so the terrain is already ready.
@onready var _terrain: Node = get_node("../Island/Terrain")


func _ready() -> void:
	# Collect every grid position that can hold a plot, then number them from the
	# centre outwards. Sorting by z and x as well keeps the order the same every run.
	# v2 village (team decision, 2026-11-22, "arrange them properly in an
	# order"): the squares stand on a tidy grid round the central plaza: five by
	# five, GRID_STEP apart, with the plaza in the middle cell and the four
	# corners left as greenery. Each square faces the plaza.
	var spots: Array[Vector2] = []
	var turns := {}
	for row in range(-2, 3):
		for column in range(-2, 3):
			if row == 0 and column == 0:
				continue   # The plaza.
			if absi(row) == 2 and absi(column) == 2:
				continue   # The corners stay green.
			var spot := Vector2(column, row) * GRID_STEP
			# Face the plaza: along whichever direction leads back to it most.
			var turn := (0.0 if spot.y < 0.0 else PI) if absf(spot.y) >= absf(spot.x) else (PI / 2.0 if spot.x < 0.0 else -PI / 2.0)
			if _can_hold_plot(spot, turn):
				spots.append(spot)
				turns[spot] = turn
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := a.length_squared()
		var db := b.length_squared()
		if not is_equal_approx(da, db):
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for spot in spots:
		_add_plot(spot.x, spot.y)
		_plots.back().rotation.y = turns[spot]
	# Engine.is_editor_hint() is true when running inside the Godot editor.
	if not Engine.is_editor_hint():
		set_outlines_visible(false)


# Plot selection. BuildingManager takes these inputs first during placement mode.
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("ui_cancel"):
		select_plot(null)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select_plot(get_plot_under_screen_point(event.position))


# Shows or hides the outlines of all plots, except the selected one.
func set_outlines_visible(value: bool) -> void:
	for plot in _plots:
		plot.show_outline = value


# Selects a plot, or clears the selection if plot is null. The mouse uses this,
# and the ESP32 controller can use it too.
func select_plot(plot: BuildingPlot) -> void:
	if plot == _selected_plot:
		return
	if _selected_plot != null:
		_selected_plot.is_selected = false
	_selected_plot = plot
	if plot != null:
		plot.is_selected = true
		print("Selected plot %d, buildable: %s" % [plot.plot_id, plot.is_buildable()])
	else:
		print("Selection cleared")
	selection_changed.emit(plot)


# Returns the selected plot, or null if nothing is selected.
func get_selected_plot() -> BuildingPlot:
	return _selected_plot


# Returns the plot containing this world position, or null if there is none.
func get_plot_at(point: Vector3) -> BuildingPlot:
	for plot in _plots:
		if plot.contains_point(point):
			return plot
	return null


# Finds which plot is under a point on the screen. The camera gives a line going
# into the world, and we work out where that line meets the flat building ground.
func get_plot_under_screen_point(screen_point: Vector2) -> BuildingPlot:
	var camera := get_viewport().get_camera_3d()
	var ground := Plane(Vector3.UP, _terrain.LAND_HEIGHT)
	var hit: Variant = ground.intersects_ray(
		camera.project_ray_origin(screen_point),
		camera.project_ray_normal(screen_point)
	)
	return null if hit == null else get_plot_at(hit)


# Returns every plot, nearest the town square first. Plot IDs start at 1.
func get_plots() -> Array[BuildingPlot]:
	return _plots


# Returns the plot with this ID, or null if there is no such plot.
func get_plot(plot_id: int) -> BuildingPlot:
	if plot_id < 1 or plot_id > _plots.size():
		return null
	return _plots[plot_id - 1]


# True if a plot can be created with its centre here: not the town square, close
# enough to the town, on the town's side of the river, and on flat ground.
func _can_hold_plot(spot: Vector2, turn := 0.0) -> bool:
	if spot.length() > BUILD_RADIUS:
		return false
	if spot.y > _terrain.RIVER_Z - 20.0:
		return false   # Across or beside the river. There is no bridge yet.
	for pond: Vector3 in _terrain.PONDS:
		if spot.distance_to(Vector2(pond.x, pond.y)) < pond.z + POND_CLEARANCE:
			return false
	# The ground must be flat under the whole square (turned as it will be) and a
	# little beyond its edges.
	var reach := BuildingPlot.SIZE * 0.5 + FLAT_MARGIN
	for dx: float in [-reach, 0.0, reach]:
		for dz: float in [-reach, 0.0, reach]:
			var p := spot + Vector2(dx, dz).rotated(-turn)
			if absf(_terrain.get_height_at(p.x, p.y) - _terrain.LAND_HEIGHT) > 0.01:
				return false
	return true


func _add_plot(x: float, z: float) -> void:
	var plot := BuildingPlot.new()
	plot.plot_id = _plots.size() + 1
	plot.name = "Plot%02d" % plot.plot_id
	add_child(plot)
	plot.position = Vector3(x, _terrain.get_height_at(x, z) + GROUND_LIFT, z)
	_plots.append(plot)
