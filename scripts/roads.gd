# roads.gd
# Dirt roads between the build squares, and one road out to the eastern beach
# where ships land.
#
# The roads are painted onto the ground, not built as separate objects: this
# script draws them into a black-and-white picture (white = road), and the
# terrain shader (scenes/island/terrain.gdshader) mixes a dirt colour into the
# grass wherever the picture is white. Painted roads follow every bump in the
# ground and can never float above it or flicker.
#
# v2: the roads wind between the scattered squares (see _plan_roads), so each
# building has a road at its door. Roads are only for looks:
# workers still walk the shortest way round buildings (see path_grid.gd).
class_name Roads
extends Node

const AREA := 320.0              # Metres covered by the road picture, centred on the town square.
const PIXELS_PER_METRE := 1.0
const WIDTH := 3.2               # Metres. The lanes between squares are 4 m wide.
const EDGE := 1.2                # Metres over which a road's edge fades into the grass.
const BEACH_ROAD_Z := 18.0       # The road to the beach runs along the lane at this z.
const FRONT_GAP := 2.0           # Metres in front of a square where its road starts.
const PLAZA_RADIUS := 18.0       # The open sandy square round the campfire.
const RING_PIECES := 90          # Straight pieces that make up one ring path.
const RING_WANDER := 3.0         # Metres a ring path wanders in and out.
const SPOKE_SPACING := 1.2       # Least angle (radians) between two spokes on the same ring.
const MAX_ARC := 1.5             # Ring paths do not run across gaps wider than this (radians).
const BEND := 0.1                # How far a road bends, as a share of its length.
const CURVE_PIECES := 10         # Straight pieces that make up one bending road.

var _segments: Array[Array] = []  # Each road piece: [start, end], as Vector2 on the ground (x, z).

@onready var _map: MapManager = get_node("../MapManager")
@onready var _terrain: MeshInstance3D = get_node("../Island/Terrain")


func _ready() -> void:
	_plan_roads()
	_paint()
	# Clear any tree or rock standing on a square or a road.
	get_node("../Island/Decorations").prune(func(spot: Vector3) -> bool:
		if is_on_road(spot.x, spot.z, 1.5):
			return true
		for plot in _map.get_plots():
			var local := (spot - plot.position).rotated(Vector3.UP, -plot.rotation.y)
			if absf(local.x) < BuildingPlot.SIZE * 0.5 + 4.0 and absf(local.z) < BuildingPlot.SIZE * 0.5 + 4.0:
				return true
		return false)


# All the road pieces, for tests.
func get_segments() -> Array[Array]:
	return _segments


# True if this spot (x, z) is on a road or right beside one.
func is_on_road(x: float, z: float, margin := 0.0) -> bool:
	if _on_plaza(x, z, margin):
		return true
	for segment in _segments:
		if _distance_to_segment(Vector2(x, z), segment[0], segment[1]) < WIDTH * 0.5 + margin:
			return true
	return false


# The paths, laid out like the team's picture (2026-11-22): a sandy plaza round
# the campfire, a ring path between each ring of squares (see MapManager.RINGS),
# a few spokes joining the rings through the gaps between squares, a short path
# from each square's front to the nearest ring, and a road down to the beach.
# The rings wander a little in and out, so they look worn in, not drawn.
func _plan_roads() -> void:
	# v2 tidy village (2026-11-22): straight paths run between the rows and
	# columns of squares, round the plaza; each square's front has a short path
	# to the nearest one; a road leaves the east side for the beach.
	var seen := {}
	var step := MapManager.GRID_STEP
	var reach := step * 2.5
	for lane: float in [-1.5 * step, -0.5 * step, 0.5 * step, 1.5 * step]:
		_add_segment(Vector2(lane, -reach), Vector2(lane, reach), seen)
		_add_segment(Vector2(-reach, lane), Vector2(reach, lane), seen)
	for plot in _map.get_plots():
		var front3: Vector3 = plot.to_world(Vector3(0.0, 0.0, BuildingPlot.SIZE * 0.5 + FRONT_GAP))
		var door3: Vector3 = plot.to_world(Vector3(0.0, 0.0, step * 0.5))
		_add_segment(Vector2(front3.x, front3.z), Vector2(door3.x, door3.z), seen)
	var end := _beach_end()
	_add_curve(Vector2(reach, BEACH_ROAD_Z), end, seen)


func _ring_point(radius: float, angle: float) -> Vector2:
	return Vector2.from_angle(angle) * (radius + sin(angle * 3.0 + radius) * RING_WANDER)


# A road piece over the plaza counts as road too.
func _on_plaza(x: float, z: float, margin: float) -> bool:
	return Vector2(x, z).length() < PLAZA_RADIUS + margin


# True if the straight line from a to b passes over a build square (other than
# right at its ends, where it meets the front of its own square).
func _crosses_square(a: Vector2, b: Vector2) -> bool:
	for plot in _map.get_plots():
		var centre := Vector2(plot.position.x, plot.position.z)
		var closest := Geometry2D.get_closest_point_to_segment(centre, a, b)
		if closest.distance_to(centre) < BuildingPlot.SIZE * 0.78:
			return true
	return false


# Where the road to the beach ends: on the sand, along BEACH_ROAD_Z.
func _beach_end() -> Vector2:
	var x := 60.0
	while x < AREA * 0.5 - 2.0 and _terrain.get_height_at(x, BEACH_ROAD_Z) > _terrain.LAND_HEIGHT - 0.4:
		x += 1.0
	return Vector2(x, BEACH_ROAD_Z)


# A gently bending road from a to b, made of short straight pieces. The bend
# goes to one side or the other depending on where the road is, so it is the
# same every game.
func _add_curve(a: Vector2, b: Vector2, seen: Dictionary) -> void:
	var middle := (a + b) * 0.5
	var side := (b - a).orthogonal().normalized()
	var bend := sin(a.x * 0.13 + b.y * 0.07) * BEND * a.distance_to(b)
	var control := middle + side * bend
	var last := a
	for i in range(1, CURVE_PIECES + 1):
		var t := float(i) / CURVE_PIECES
		var point := a.lerp(control, t).lerp(control.lerp(b, t), t)
		_add_segment(last, point, seen)
		last = point


# Adds a straight road piece once, even if two roads would draw the same piece.
func _add_segment(a: Vector2, b: Vector2, seen: Dictionary) -> void:
	var key := "%d,%d,%d,%d" % ([roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y)] if a < b else [roundi(b.x), roundi(b.y), roundi(a.x), roundi(a.y)])
	if seen.has(key):
		return
	seen[key] = true
	_segments.append([a, b])


# Draws the roads into a picture and hands it to the terrain shader.
func _paint() -> void:
	var size := int(AREA * PIXELS_PER_METRE)
	var image := Image.create(size, size, false, Image.FORMAT_L8)
	var reach := WIDTH * 0.5 + EDGE * 0.5
	for segment in _segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var low := _to_pixel(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach)
		var high := _to_pixel(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach)
		for py in range(maxi(low.y, 0), mini(high.y + 1, size)):
			for px in range(maxi(low.x, 0), mini(high.x + 1, size)):
				var spot := Vector2((px + 0.5) / PIXELS_PER_METRE - AREA * 0.5, (py + 0.5) / PIXELS_PER_METRE - AREA * 0.5)
				var d := _distance_to_segment(spot, a, b)
				var value := 1.0 - smoothstep(WIDTH * 0.5 - EDGE * 0.5, reach, d)
				if value > image.get_pixel(px, py).r:
					image.set_pixel(px, py, Color(value, value, value))
	# The plaza: a round patch of path, fading at its edge.
	for py in size:
		for px in size:
			var spot := Vector2((px + 0.5) / PIXELS_PER_METRE - AREA * 0.5, (py + 0.5) / PIXELS_PER_METRE - AREA * 0.5)
			var value := 1.0 - smoothstep(PLAZA_RADIUS - 1.5, PLAZA_RADIUS + 1.5, spot.length())
			if value > image.get_pixel(px, py).r:
				image.set_pixel(px, py, Color(value, value, value))
	var material := _terrain.material_override as ShaderMaterial
	material.set_shader_parameter("road_mask", ImageTexture.create_from_image(image))
	material.set_shader_parameter("road_area", AREA)


func _to_pixel(spot: Vector2) -> Vector2i:
	return Vector2i(floori((spot.x + AREA * 0.5) * PIXELS_PER_METRE), floori((spot.y + AREA * 0.5) * PIXELS_PER_METRE))


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
