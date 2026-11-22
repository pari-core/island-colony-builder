# ground_cover.gd
# Fills the island so it never looks bare (team request, 2026-11-22): bushes,
# flowering bushes, clumps of flowers, grass tufts, clover, ferns, mushrooms,
# pebbles and small rocks, from Quaternius' Stylized Nature MegaKit (CC0).
#
# Plants grow in clumps, not evenly: a noise pattern decides where each kind is
# common, so there are meadows of flowers, patches of fern and so on. Nothing
# grows on a build square, a path, the town square or in water.
#
# There are thousands of plants, so each kind is drawn as one MultiMesh (one
# object drawn many times at once), which is far quicker than a node per plant.
# A fixed seed puts everything in the same place every game. Only for looks.
class_name GroundCover
extends Node3D

const NATURE := "res://assets/nature/%s.gltf"
# name, how many, smallest and largest size, how clumped (0 = everywhere, 0.4 = only in clumps), casts a shadow
const KINDS := [
	["Bush_Common", 140, 1.2, 1.8, 0.4, true],   # Only in clumps (team: "too scattered").
	["Flower_3_Group", 220, 0.45, 0.75, 0.3, false],
	["Flower_4_Group", 160, 0.45, 0.75, 0.3, false],
	["Grass_Common_Short", 1100, 0.6, 1.1, 0.0, false],
	["Grass_Wispy_Tall", 600, 0.5, 0.95, 0.1, false],
	["Clover_1", 350, 0.5, 0.9, 0.2, false],
	["Fern_1", 180, 0.9, 1.5, 0.3, false],
	["Mushroom_Common", 70, 0.8, 1.3, 0.35, false],
	["Pebble_Round_1", 220, 1.5, 3.0, 0.0, false],
	["Rock_Medium_1", 70, 0.5, 1.2, 0.1, true],
]
const REACH := 228.0             # Plants grow up to this far from the town square.
const SQUARE_CLEAR := 18.0       # The town square stays open round the campfire.

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _counts := {}                # Kind -> how many were placed, for tests.

@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _map: MapManager = get_node("../MapManager")
@onready var _roads: Roads = get_node("../Roads")


func _ready() -> void:
	_rng.seed = 512
	_noise.seed = 9
	_noise.frequency = 0.02
	for kind: Array in KINDS:
		_grow(kind)
	_plant_village()


func get_counts() -> Dictionary:
	return _counts


func _grow(kind: Array) -> void:
	var source: Node3D = load(NATURE % kind[0]).instantiate()
	var part: MeshInstance3D = source.find_children("*", "MeshInstance3D", true, false)[0]
	var offset := part.transform
	var transforms: Array[Transform3D] = []
	var offset_noise := _rng.randf_range(0.0, 500.0)   # Each kind clumps in its own places.
	var tries := 0
	while transforms.size() < int(kind[1]) and tries < int(kind[1]) * 40:
		tries += 1
		var spot := Vector2.from_angle(_rng.randf_range(0.0, TAU)) * sqrt(_rng.randf()) * REACH
		if _noise.get_noise_2d(spot.x + offset_noise, spot.y) * 0.5 + 0.5 < float(kind[4]) + 0.2:
			continue
		var height: float = _terrain.get_height_at(spot.x, spot.y)
		if not _is_free(spot, height):
			continue
		var size := _rng.randf_range(kind[2], kind[3])
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		transforms.append(Transform3D(basis, Vector3(spot.x, height, spot.y)) * offset)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = part.mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var drawn := MultiMeshInstance3D.new()
	drawn.name = kind[0]
	drawn.multimesh = multimesh
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind[5] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_make_green(drawn, kind[0], part.mesh)
	# Small plants are not worth drawing from far away.
	if not kind[5]:
		drawn.visibility_range_end = 260.0
	add_child(drawn)
	_counts[kind[0]] = transforms.size()
	source.free()


# The village itself (team request, 2026-11-23: "put trees and bushes in between
# squares"): hedges of bushes and flowers along both sides of every path between
# the squares, and small groves in the four green corners of the grid.
const HEDGE_STEP := 2.2         # Metres between bushes in a hedge.
const VILLAGE_TREES := [
	"res://assets/nature/CommonTree_2.gltf", "res://assets/nature/CommonTree_4.gltf",
	"res://assets/nature/CommonTree_5.gltf", "res://assets/nature/Pine_2.gltf",
]
func _plant_village() -> void:
	var step := MapManager.GRID_STEP
	var reach := step * 2.4
	var bushes: Array[Transform3D] = []
	for lane: float in [-1.5 * step, -0.5 * step, 0.5 * step, 1.5 * step]:
		# Neat, unbroken hedges (team request, 2026-11-23): a green bush every
		# HEDGE_STEP metres down both sides of the path, all much the same size.
		for side: float in [-3.6, 3.6]:
			var along := -reach
			while along < reach:
				along += HEDGE_STEP
				for spot: Vector2 in [Vector2(lane + side, along), Vector2(along, lane + side)]:
					var height: float = _terrain.get_height_at(spot.x, spot.y)
					if not _is_free(spot, height):
						continue
					var size := _rng.randf_range(1.1, 1.25)
					bushes.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size), Vector3(spot.x, height, spot.y)))
	_draw_many("Bush_Common", bushes, "VillageBushes", true)
	# Small groves in the grid's four empty corners.
	for corner: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
		var centre := corner * step
		for i in 6:
			var spot := centre + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-10.0, 10.0))
			var height: float = _terrain.get_height_at(spot.x, spot.y)
			if not _is_free(spot, height):
				continue
			var tree: Node3D = load(VILLAGE_TREES[_rng.randi() % VILLAGE_TREES.size()]).instantiate()
			add_child(tree)
			tree.position = Vector3(spot.x, height, spot.y)
			tree.rotation.y = _rng.randf_range(0.0, TAU)
			tree.scale = Vector3.ONE * _rng.randf_range(1.1, 1.6)
	_counts["VillageBushes"] = bushes.size()


func _draw_many(model: String, places: Array[Transform3D], node_name: String, shadow: bool) -> void:
	var source: Node3D = load(NATURE % model).instantiate()
	var part: MeshInstance3D = source.find_children("*", "MeshInstance3D", true, false)[0]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = part.mesh
	multimesh.instance_count = places.size()
	for i in places.size():
		multimesh.set_instance_transform(i, places[i] * part.transform)
	var drawn := MultiMeshInstance3D.new()
	drawn.name = node_name
	drawn.multimesh = multimesh
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_make_green(drawn, model, part.mesh)
	add_child(drawn)
	source.free()


# The pack paints its common bush with red autumn leaves; the team wanted green
# hedges, so it gets the green leaves the common trees use instead.
const GREEN_LEAVES := preload("res://assets/nature/Leaves_NormalTree_C.png")
func _make_green(drawn: GeometryInstance3D, model: String, mesh: Mesh) -> void:
	if model != "Bush_Common":
		return
	var leaves := mesh.surface_get_material(0).duplicate() as BaseMaterial3D
	leaves.albedo_texture = GREEN_LEAVES
	drawn.material_override = leaves


# On dry, fairly flat land, away from squares, paths, the town square and water.
func _is_free(spot: Vector2, height: float) -> bool:
	if height < _terrain.LAND_HEIGHT - 0.4 or height > _terrain.LAND_HEIGHT + 10.0:
		return false
	if spot.length() < SQUARE_CLEAR:
		return false
	if _roads.is_on_road(spot.x, spot.y, 0.8):
		return false
	for plot in _map.get_plots():
		var local := (Vector3(spot.x, 0.0, spot.y) - plot.position).rotated(Vector3.UP, -plot.rotation.y)
		if absf(local.x) < BuildingPlot.SIZE * 0.5 + 2.0 and absf(local.z) < BuildingPlot.SIZE * 0.5 + 2.0:
			return false
	return true
