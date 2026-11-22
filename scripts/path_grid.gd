# path_grid.gd
# Finds walking routes around buildings, for workers and civilians.
#
# How it works: the middle of the island is divided into squares (cells) 2 m
# across. Each cell covered by a building, plus a small gap around it, is marked
# "solid". Godot's AStarGrid2D then finds the shortest chain of free cells between
# two points, and the chain is straightened into a few long lines, so people walk
# naturally instead of zig-zagging from cell to cell.
#
# The grid is rebuilt whenever a building is placed (BuildingManager calls
# refresh()). Each rebuild raises "version", so anyone already walking knows to
# work out a new route that avoids the new building.
#
# Only buildings are avoided. Palms and rocks grow outside the building area, so
# they are left out to keep the grid small.
class_name PathGrid
extends Node

const HALF_SIZE := 230.0         # The grid covers -230 to 230 m: all the building land.
const CELL := 2.0                # Cell width, in metres.
const GAP := 1.0                 # Free space kept around each building, in metres.
const LINE_STEP := 0.5           # How finely straight lines are checked, in metres.

var version := 0
var _astar := AStarGrid2D.new()
var _footprints: Array[Rect2] = []   # Each building's ground area, without the gap.

@onready var _map: MapManager = get_node("../MapManager")


func _ready() -> void:
	var cells := int(HALF_SIZE * 2.0 / CELL)
	_astar.region = Rect2i(0, 0, cells, cells)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()


# Marks every building's cells as solid again. Call after a building is placed.
func refresh() -> void:
	_astar.fill_solid_region(_astar.region, false)
	_footprints.clear()
	for plot in _map.get_plots():
		if plot.building != null:
			var area := _measure(plot.building)
			_footprints.append(area)
			var grown := area.grow(GAP)
			var first := _cell_at(grown.position.x, grown.position.y)
			var last := _cell_at(grown.end.x, grown.end.y)
			_astar.fill_solid_region(Rect2i(first, last - first + Vector2i.ONE), true)
	version += 1


# The ground area of each building, for tests and debugging.
func get_footprints() -> Array[Rect2]:
	return _footprints


# True if this point is inside a building or the gap around it.
func is_blocked(point: Vector3) -> bool:
	var cell := _cell_at(point.x, point.z)
	return _astar.is_in_boundsv(cell) and _astar.is_point_solid(cell)


# Returns the points to walk through, in order, ending exactly at goal. If start
# or goal is right next to a building (a worker's job spot, a House door), the
# route leaves or reaches it by the nearest free cell.
func find_path(start: Vector3, goal: Vector3) -> Array[Vector3]:
	var direct: Array[Vector3] = [goal]
	if _line_is_clear(start, goal):
		return direct
	var from := _nearest_free(_cell_at(start.x, start.z))
	var to := _nearest_free(_cell_at(goal.x, goal.z))
	if from == Vector2i(-1, -1) or to == Vector2i(-1, -1):
		return direct
	var cells := _astar.get_id_path(from, to)
	if cells.is_empty():
		return direct

	# Cell centres, then the exact goal. Height is filled in while walking.
	var points: Array[Vector3] = []
	for cell in cells:
		points.append(_cell_centre(cell))
	points.append(goal)

	# Straighten: from each point, jump to the furthest later point that can be
	# reached in a clear line.
	var route: Array[Vector3] = []
	var here := start
	var i := 0
	while i < points.size():
		var furthest := i
		for j in range(points.size() - 1, i, -1):
			if _line_is_clear(here, points[j]):
				furthest = j
				break
		route.append(points[furthest])
		here = points[furthest]
		i = furthest + 1
	return route


# True if a straight walk from a to b crosses no solid cell. The cells that a and
# b themselves are in are allowed, so walks to and from a doorway still work.
func _line_is_clear(a: Vector3, b: Vector3) -> bool:
	var start_cell := _cell_at(a.x, a.z)
	var end_cell := _cell_at(b.x, b.z)
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var steps := maxi(int(flat.length() / LINE_STEP), 1)
	for s in steps + 1:
		var t := float(s) / steps
		var cell := _cell_at(a.x + flat.x * t, a.z + flat.y * t)
		if cell == start_cell or cell == end_cell:
			continue
		if _astar.is_in_boundsv(cell) and _astar.is_point_solid(cell):
			return false
	return true


# The closest free cell, searching outwards in squares. (-1, -1) if none is near.
func _nearest_free(cell: Vector2i) -> Vector2i:
	cell = cell.clamp(Vector2i.ZERO, _astar.region.size - Vector2i.ONE)
	for ring in 12:
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for x in range(cell.x - ring, cell.x + ring + 1):
			for y in range(cell.y - ring, cell.y + ring + 1):
				var c := Vector2i(x, y)
				if maxi(absi(x - cell.x), absi(y - cell.y)) != ring:
					continue
				if not _astar.is_in_boundsv(c) or _astar.is_point_solid(c):
					continue
				var d := Vector2(c - cell).length()
				if d < best_distance:
					best_distance = d
					best = c
		if best != Vector2i(-1, -1):
			return best
	return Vector2i(-1, -1)


# The ground area a building covers, measured from its visible meshes.
func _measure(building: Node3D) -> Rect2:
	var box := AABB()
	var first := true
	for mesh: GeometryInstance3D in building.find_children("*", "GeometryInstance3D", true, false):
		if mesh is Label3D:
			continue   # Floating signs are not part of the building's ground area.
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func _cell_at(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + HALF_SIZE) / CELL), floori((z + HALF_SIZE) / CELL))


func _cell_centre(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL - HALF_SIZE, 0.0, (cell.y + 0.5) * CELL - HALF_SIZE)
