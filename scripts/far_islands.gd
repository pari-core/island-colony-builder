# far_islands.gd
# Life on the small islands out at sea (see ISLANDS in island_terrain.gd): woods
# on their hills, palms on their beaches, and a handful of houses on the grassy
# land near the shore, some with smoke from the chimney. They are scenery only:
# nothing on them can be built, and the game's rules do not use them.
# A fixed seed puts everything in the same place every game.
class_name FarIslands
extends Node3D

const TREES := [
	preload("res://assets/nature/CommonTree_1.gltf"), preload("res://assets/nature/CommonTree_3.gltf"),
	preload("res://assets/nature/Pine_1.gltf"), preload("res://assets/nature/Pine_3.gltf"),
]
const PALM := preload("res://assets/environment/realistic_palm_tree_4_free.glb")
const HOUSE := preload("res://scenes/buildings/House.tscn")
const TREES_PER_ISLAND := 70
const PALMS_PER_ISLAND := 10
const HOUSES_PER_ISLAND := 4

var _rng := RandomNumberGenerator.new()
var _houses: Array[Node3D] = []

@onready var _terrain: Node = get_node("../Island/Terrain")


func _ready() -> void:
	_rng.seed = 404
	for island: Vector4 in _terrain.ISLANDS:
		_dress(island)


func get_houses() -> Array[Node3D]:
	return _houses


func _dress(island: Vector4) -> void:
	var centre := Vector2(island.x, island.y)
	var used: Array[Vector2] = []
	# Houses first, on fairly flat grass near the shore, facing the sea.
	var tries := 0
	var placed := 0
	while placed < HOUSES_PER_ISLAND and tries < 400:
		tries += 1
		var spot := centre + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * island.z * _rng.randf_range(0.45, 0.75)
		var height: float = _terrain.get_height_at(spot.x, spot.y)
		if height < 2.5 or height > 9.0 or _slope(spot) > 0.35 or _crowded(spot, used, 16.0):
			continue
		var house: Node3D = HOUSE.instantiate()
		add_child(house)
		house.position = Vector3(spot.x, height - 0.2, spot.y)
		var outward := spot - centre
		house.rotation.y = atan2(outward.x, outward.y) + _rng.randf_range(-0.4, 0.4)
		house.scale = Vector3.ONE * _rng.randf_range(0.85, 1.05)
		_houses.append(house)
		used.append(spot)
		placed += 1
	# Woods on the hills, thinning out towards the bare tops.
	_scatter(TREES, TREES_PER_ISLAND, island, used, 0.2, 0.85, 3.0, island.w * 0.8, 7.0, 1.2, 1.8)
	# Palms on the beach.
	_scatter([PALM], PALMS_PER_ISLAND, island, used, 0.8, 1.05, 0.9, 2.6, 6.0, 0.38, 0.55)


func _scatter(scenes: Array, count: int, island: Vector4, used: Array[Vector2], near: float, far: float, low: float, high: float, gap: float, small: float, big: float) -> void:
	var centre := Vector2(island.x, island.y)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 30:
		tries += 1
		var spot := centre + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * island.z * _rng.randf_range(near, far)
		var height: float = _terrain.get_height_at(spot.x, spot.y)
		if height < low or height > high or _crowded(spot, used, gap):
			continue
		var item: Node3D = (scenes[_rng.randi() % scenes.size()] as PackedScene).instantiate()
		add_child(item)
		item.position = Vector3(spot.x, height, spot.y)
		item.rotation.y = _rng.randf_range(0.0, TAU)
		item.scale = Vector3.ONE * _rng.randf_range(small, big)
		used.append(spot)
		placed += 1


# How steep the ground is here (0 = flat).
func _slope(spot: Vector2) -> float:
	var dx: float = _terrain.get_height_at(spot.x + 4.0, spot.y) - _terrain.get_height_at(spot.x - 4.0, spot.y)
	var dz: float = _terrain.get_height_at(spot.x, spot.y + 4.0) - _terrain.get_height_at(spot.x, spot.y - 4.0)
	return Vector2(dx, dz).length() / 8.0


func _crowded(spot: Vector2, used: Array[Vector2], gap: float) -> bool:
	for other in used:
		if spot.distance_to(other) < gap:
			return true
	return false
