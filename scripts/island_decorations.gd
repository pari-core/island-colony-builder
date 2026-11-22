# island_decorations.gd
# Places oak forests, beach palms and rocks around the town when the game starts.
# The flat centre is kept clear for building plots. A fixed random seed means
# everything lands in the same place every run.
#
# @tool means this also runs inside the Godot editor. The palms and rocks then
# appear in the 3D view, but not in the Scene panel, and are never saved into
# the scene file, because they are created fresh each time.
@tool
extends Node3D

const PALM_SCENE := preload("res://assets/environment/realistic_palm_tree_4_free.glb")
# The oak model is wrapped in Oak.tscn, which scales it to about 12 m tall and
# stands its trunk on the ground.
const OAK_SCENE := preload("res://scenes/island/Oak.tscn")
const ROCK_SCENE := preload("res://assets/environment/rock_moss_set_01/rock_moss_set_01_2k.gltf")
const GROUND_ROCK := preload("res://assets/nature/Rock_Medium_1.gltf")
# The stylised look (v2): KayKit's three trees and rocks (CC0) replace the
# realistic oak and rocks. Wherever the code below asks for OAK_SCENE, one of
# these trees is picked instead, and scaled up from the kit's small size.
# v2 village (2026-11-22): soft, painterly trees from Quaternius' Stylized Nature
# MegaKit (CC0), round leafy trees and pines, to match the team's picture.
const TREE_SCENES := [
	preload("res://assets/nature/CommonTree_1.gltf"),
	preload("res://assets/nature/CommonTree_2.gltf"),
	preload("res://assets/nature/CommonTree_3.gltf"),
	preload("res://assets/nature/CommonTree_4.gltf"),
	preload("res://assets/nature/CommonTree_5.gltf"),
	preload("res://assets/nature/Pine_1.gltf"),
	preload("res://assets/nature/Pine_2.gltf"),
	preload("res://assets/nature/Pine_3.gltf"),
]
const TREE_SIZE := 1.5           # The kit's trees are 7 to 9 m tall; this makes them 10 to 14 m.
const ROCK_SIZE := 6.0
# The team asked for a realistic environment again (2026-11-21), so the realistic
# oak and rocks are used; the KayKit trees above stay listed for the stylised look.
const REALISTIC := false   # v2 village: the stylised trees above.
# KayKit's leaves are teal by design, which looks odd on green grass. Their
# colours are multiplied by this, which turns the leaves green and keeps the
# trunks brown.
const TREE_TINT := Color(0.72, 1.0, 0.5)

const CLEAR_RADIUS := 22.0     # Nothing is placed closer to the centre than this (except
                               # beach palms and village trees), so the build squares and
                               # their roads stay clear. It was 204 m when there were 80
                               # squares; with 20 the land beyond them looked empty.
const VILLAGE_NEAR := 24.0     # Young trees grow just outside the town, between these
const VILLAGE_FAR := 180.0     # distances from the centre, so it sits among trees.
const OUTER_RADIUS := 270.0    # Search no further out than this.
const MIN_LAND_HEIGHT := 0.9   # Keeps objects off the wet beach and out of the sea.
const MAX_LAND_HEIGHT := 8.0   # Keeps objects off the bare rocky hill.
const FOREST_MAX_HEIGHT := 85.0  # Forests climb the mountain slopes, below the bare tops.
const FOREST_NEAR := 205.0     # Distant forests grow between these distances from the centre.
const FOREST_FAR := 470.0
const FOREST_SPREAD := 17.0    # How loosely the oaks in a distant forest are grouped.
const PALM_SPACING := 5.0      # Minimum gap between objects, in metres.
const OAK_SPACING := 7.0
const ROCK_SPACING := 14.0
const GROVE_SPREAD := 7.0      # How loosely the palms in a grove are grouped.
const COAST_LENGTH := 200.0    # Coastal palms grow this far north and south of the centre.
const COAST_BAND := 16.0       # How far inland from the shore the coastal palms grow.
const LOD_BIAS := 0.25         # Below 1.0, models switch to simpler versions sooner.

# The parts of the land where _scatter can place objects.
enum Area { ANYWHERE, GROVES, COAST, FORESTS, VILLAGE, SHORE }

@export var oak_count := 80            # Oaks in groves around the town.
@export var forest_oak_count := 850    # Oaks in the forests on the mountains and headland.
@export var forest_count := 110
@export var coast_palm_count := 0      # (v2 island: no palms; boulders line the shore instead.)
@export var shore_rock_count := 190
@export var rock_count := 18
@export var grove_count := 14
@export var village_tree_count := 280  # Trees among the houses (v2: the squares are spread out,
                                         # and Roads.prune() clears any that land on a square or road).

var _rng := RandomNumberGenerator.new()
var _used_spots: Array[Vector2] = []
var _grove_centres: Array[Vector2] = []
var _forest_centres: Array[Vector2] = []
var _cutout_materials := {}      # Leaf materials already converted, shared by all oaks.

# Terrain is an earlier sibling, so it is ready before this node.
@onready var _terrain: Node = get_parent().get_node("Terrain")


func _ready() -> void:
	_rng.seed = 2026
	_scatter(ROCK_SCENE, rock_count, ROCK_SPACING, 0.8, 1.4, Area.ANYWHERE)
	_pick_grove_centres()
	_scatter(OAK_SCENE, oak_count, OAK_SPACING, 0.75, 1.3, Area.GROVES)
	_scatter(OAK_SCENE, village_tree_count, OAK_SPACING, 0.4, 0.7, Area.VILLAGE)
	_scatter(OAK_SCENE, forest_oak_count, OAK_SPACING, 0.8, 1.5, Area.FORESTS)
	# Palms suit the beach, so they grow only along the coast.
	_scatter(PALM_SCENE, coast_palm_count, PALM_SPACING, 0.38, 0.6, Area.COAST)
	_scatter(ROCK_SCENE, shore_rock_count, 5.0, 1.6, 3.4, Area.SHORE)


# Chooses where the oak groves and distant forests grow. Grouping trees looks
# more natural than spreading them evenly, which forms an obvious ring around
# the flat centre.
func _pick_grove_centres() -> void:
	for i in grove_count:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(CLEAR_RADIUS + 6.0, CLEAR_RADIUS + 60.0)
		_grove_centres.append(Vector2(cos(angle), sin(angle)) * distance)
	for i in forest_count:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(FOREST_NEAR, FOREST_FAR)
		_forest_centres.append(Vector2(cos(angle), sin(angle)) * distance)


func _random_spot(area: Area) -> Vector2:
	if area == Area.GROVES:
		var offset := Vector2(_rng.randfn(0.0, GROVE_SPREAD), _rng.randfn(0.0, GROVE_SPREAD))
		return _grove_centres[_rng.randi_range(0, _grove_centres.size() - 1)] + offset
	if area == Area.FORESTS:
		var spread := Vector2(_rng.randfn(0.0, FOREST_SPREAD), _rng.randfn(0.0, FOREST_SPREAD))
		return _forest_centres[_rng.randi_range(0, _forest_centres.size() - 1)] + spread
	if area == Area.VILLAGE:
		var around := _rng.randf_range(0.0, TAU)
		return Vector2(cos(around), sin(around)) * _rng.randf_range(VILLAGE_NEAR, VILLAGE_FAR)
	if area == Area.SHORE:
		# Somewhere on the island's edge, round the whole coast, half in the water.
		var around := _rng.randf_range(-PI, PI)
		var outward := Vector2(cos(around), sin(around))
		var r := 140.0
		while r < 330.0 and _terrain.get_height_at(outward.x * r, outward.y * r) > 0.6:
			r += 2.0
		return outward * (r + _rng.randf_range(-6.0, 3.0))
	if area == Area.COAST:
		# Along the beach on the east side, a little way inland from the waterline.
		var z := _rng.randf_range(-COAST_LENGTH, COAST_LENGTH)
		return Vector2(_shore_x(z) - _rng.randf_range(1.0, COAST_BAND), z)
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(CLEAR_RADIUS, OUTER_RADIUS)
	return Vector2(cos(angle), sin(angle)) * distance


# Walks west from out at sea until it reaches land, and returns the x position
# of the shore at this z.
func _shore_x(z: float) -> float:
	var x := OUTER_RADIUS
	while x > 0.0:
		if _terrain.get_height_at(x, z) >= MIN_LAND_HEIGHT:
			return x
		x -= 2.0
	return x


# Tries random spots and keeps the ones that pass the checks in _is_valid_spot.
func _scatter(scene: PackedScene, count: int, spacing: float, min_scale: float, max_scale: float, area: Area) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 50:
		attempts += 1
		var spot := _random_spot(area)
		var height: float = _terrain.get_height_at(spot.x, spot.y)
		if not _is_valid_spot(spot, height, spacing, area):
			continue

		var is_tree := scene == OAK_SCENE and not REALISTIC
		var chosen: PackedScene = TREE_SCENES[_rng.randi() % TREE_SCENES.size()] if is_tree else scene
		var item: Node3D = chosen.instantiate()
		add_child(item)
		item.position = Vector3(spot.x, height, spot.y)
		item.rotation.y = _rng.randf_range(0.0, TAU)
		var size := TREE_SIZE if is_tree else 1.0   # (ROCK_SIZE was only for the KayKit rocks.)
		item.scale = Vector3.ONE * _rng.randf_range(min_scale, max_scale) * size
		_use_simpler_meshes(item)
		if scene == OAK_SCENE and REALISTIC:
			_use_cutout_leaves(item)
		_used_spots.append(spot)
		placed += 1

	if placed < count:
		push_warning("Only placed %d of %d %s." % [placed, count, scene.resource_path.get_file()])


# Removes every tree and rock for which should_go(position) is true. Roads calls
# this once the squares and roads are known, since they are placed after the
# decorations.
func prune(should_go: Callable) -> void:
	for item in get_children():
		if item is Node3D and should_go.call(item.position):
			remove_child(item)
			item.queue_free()


# Gives a tree green leaves (see TREE_TINT). Each tinted material is made once
# and shared by every tree.
func _tint(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				continue
			if not _cutout_materials.has(material):
				var tinted: BaseMaterial3D = material.duplicate()
				tinted.albedo_color = material.albedo_color * TREE_TINT
				_cutout_materials[material] = tinted
			node.set_surface_override_material(surface, _cutout_materials[material])
	for child in node.get_children():
		_tint(child)


# Godot keeps simpler versions of each imported model, called levels of detail,
# and uses them when a model is far away. This makes the switch happen sooner.
func _use_simpler_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		node.lod_bias = LOD_BIAS
	for child in node.get_children():
		_use_simpler_meshes(child)


# The oak's leaves are see-through textures set to blend smoothly, which is slow
# to draw for a whole forest and sorts badly. "Alpha scissor" draws each pixel
# either fully or not at all: much cheaper, and the leaves still cast shadows.
# Each converted material is made once and shared by every oak.
func _use_cutout_leaves(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null or material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if not _cutout_materials.has(material):
				var cutout: BaseMaterial3D = material.duplicate()
				cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				cutout.alpha_scissor_threshold = 0.4
				_cutout_materials[material] = cutout
			node.set_surface_override_material(surface, _cutout_materials[material])
	for child in node.get_children():
		_use_cutout_leaves(child)


func _is_valid_spot(spot: Vector2, height: float, spacing: float, area: Area) -> bool:
	if area == Area.SHORE:
		# Boulders sit at the waterline, but leave the landing beach (east) open.
		if height < -2.0 or height > 2.0:
			return false
		if spot.x > 100.0 and absf(spot.y) < 60.0:
			return false
		for other in _used_spots:
			if spot.distance_to(other) < spacing:
				return false
		return true
	if height < MIN_LAND_HEIGHT:
		return false
	if area == Area.COAST:
		# Beach palms grow only on the slope down to the sea, never on the flat
		# building land above it.
		if height > _terrain.LAND_HEIGHT - 0.05:
			return false
	else:
		var max_height := MAX_LAND_HEIGHT if area == Area.ANYWHERE else FOREST_MAX_HEIGHT
		var nearest := VILLAGE_NEAR if area == Area.VILLAGE else CLEAR_RADIUS
		if height > max_height or spot.length() < nearest:
			return false
		# Not on a pond's bank.
		if height < _terrain.LAND_HEIGHT - 0.3 and spot.length() < FOREST_NEAR:
			return false
	for other in _used_spots:
		if spot.distance_to(other) < spacing:
			return false
	return true
