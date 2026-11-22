# water_storage.gd
# The Water Storage building: a round wooden tank on a stone base.
#
# It is made here from simple shapes, because the project has no tank model.
# That also lets it be shown half built: set_progress() raises the wall bit by
# bit, and set_water() fills it.
extends Node3D

const BASE_RADIUS := 5.2
const BASE_HEIGHT := 0.7
const WALL_RADIUS := 4.4
const WALL_HEIGHT := 4.2
const BAND_HEIGHTS := [1.3, 2.8, 4.3]   # Metres above the ground.
const BASE_PART := 0.15          # The first 15% of the work lays the base.
const WALL_PART := 0.7           # The next 70% raises the wall.
const STONE := Color(0.56, 0.54, 0.5)
const WOOD := Color(0.47, 0.31, 0.17)
const DARK_WOOD := Color(0.3, 0.19, 0.1)
const IRON := Color(0.16, 0.16, 0.17)
const POLE := Color(0.72, 0.6, 0.4)
const WATER := Color(0.1, 0.34, 0.55)

var _base: MeshInstance3D
var _wall: MeshInstance3D
var _rim: MeshInstance3D
var _water: MeshInstance3D
var _bands: Array[MeshInstance3D] = []
var _scaffold := Node3D.new()
var _water_level := 0.0


# _init runs as soon as the building is created, before it is put in the world,
# so the see-through placement preview already has its shapes.
func _init() -> void:
	_base = _cylinder(BASE_RADIUS, BASE_HEIGHT, STONE, 1.0)
	_wall = _cylinder(WALL_RADIUS, WALL_HEIGHT, WOOD, 0.85)
	for height: float in BAND_HEIGHTS:
		var band := _cylinder(WALL_RADIUS + 0.08, 0.2, IRON, 0.5)
		band.position.y = height
		_bands.append(band)
	_rim = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = WALL_RADIUS - 0.35
	ring.outer_radius = WALL_RADIUS + 0.2
	_rim.mesh = ring
	_rim.material_override = _material(DARK_WOOD, 0.85)
	_rim.position.y = BASE_HEIGHT + WALL_HEIGHT
	add_child(_rim)
	_water = _cylinder(WALL_RADIUS - 0.3, 0.1, WATER, 0.08)
	(_water.material_override as StandardMaterial3D).metallic = 0.3

	# Scaffolding: four poles and four planks, shown only while building.
	add_child(_scaffold)
	for i in 4:
		var angle := i * TAU / 4.0 + TAU / 8.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		_scaffold.add_child(_box(Vector3(0.25, 6.0, 0.25), out * (WALL_RADIUS + 1.3) + Vector3.UP * 3.0, 0.0))
		var side := i * TAU / 4.0
		var middle := Vector3(cos(side), 0.0, sin(side)) * (WALL_RADIUS + 0.95)
		_scaffold.add_child(_box(Vector3(0.2, 0.12, 8.4), middle + Vector3.UP * 2.6, -side))
	set_progress(1.0)
	set_water(0.85)


# How far built the tank looks, from 0 (just marked out) to 1 (finished).
func set_progress(progress: float) -> void:
	var base_done := clampf(progress / BASE_PART, 0.0, 1.0)
	_base.scale.y = lerpf(0.25, 1.0, base_done)
	_base.position.y = BASE_HEIGHT * 0.5 * _base.scale.y
	var wall_done := clampf((progress - BASE_PART) / WALL_PART, 0.0, 1.0)
	_wall.visible = wall_done > 0.0
	_wall.scale.y = maxf(wall_done, 0.02)
	_wall.position.y = BASE_HEIGHT + WALL_HEIGHT * 0.5 * wall_done
	var wall_top := BASE_HEIGHT + WALL_HEIGHT * wall_done
	for band in _bands:
		band.visible = wall_done > 0.0 and wall_top >= band.position.y
	_rim.visible = progress >= BASE_PART + WALL_PART
	_scaffold.visible = progress < 1.0
	_update_water()


# How full the tank is, from 0 (empty) to 1 (to the brim).
func set_water(level: float) -> void:
	_water_level = clampf(level, 0.0, 1.0)
	_update_water()


func get_water() -> float:
	return _water_level


func _update_water() -> void:
	_water.visible = _water_level > 0.0 and _rim.visible
	_water.position.y = BASE_HEIGHT + 0.2 + (WALL_HEIGHT - 0.3) * _water_level


func _cylinder(radius: float, height: float, colour: Color, roughness: float) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 28
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(colour, roughness)
	node.position.y = height * 0.5
	add_child(node)
	return node


func _box(size: Vector3, at: Vector3, turn: float) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(POLE, 0.9)
	node.position = at
	node.rotation.y = turn
	return node


func _material(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	return material
