# landmark_model.gd
# Shared code for the landmarks that are drawn from simple shapes: the Harbour
# and the Town Hall. (The Lighthouse has its own
# script, lighthouse.gd, because its tower grows smoothly.)
#
# A landmark's own script extends this one and only says which shapes it is made
# of, in _build(). Every shape is given the moment in the work when it appears,
# from 0.0 (there from the start) to 1.0 (only when finished), so the landmark
# is seen going up piece by piece while it is being built.
class_name LandmarkModel
extends Node3D

const STONE := Color(0.56, 0.54, 0.5)
const DARK_STONE := Color(0.4, 0.39, 0.37)
const WOOD := Color(0.47, 0.31, 0.17)
const DARK_WOOD := Color(0.3, 0.19, 0.1)
const PLASTER := Color(0.9, 0.86, 0.76)
const ROOF_RED := Color(0.6, 0.2, 0.14)
const IRON := Color(0.16, 0.16, 0.17)
const POLE := Color(0.72, 0.6, 0.4)
const GOLD := Color(0.95, 0.75, 0.25)
const CLOTH := Color(0.92, 0.9, 0.84)

var _parts: Array[Dictionary] = []   # Each is { "node": Node3D, "at": float }.
var _scaffold := Node3D.new()
var _progress := 1.0


# _init runs as soon as the building is created, before it is put in the world,
# so the see-through placement preview already has its shapes.
func _init() -> void:
	add_child(_scaffold)
	_build()
	set_progress(1.0)


# Each landmark fills this in with its own shapes.
func _build() -> void:
	pass


# How far built the landmark looks, from 0 (just marked out) to 1 (finished).
func set_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	for part in _parts:
		(part.node as Node3D).visible = _progress >= part.at
	_scaffold.visible = _progress < 1.0


func get_progress() -> float:
	return _progress


# How many of the landmark's shapes can be seen now. Tests use this.
func get_visible_parts() -> int:
	var count := 0
	for part in _parts:
		if (part.node as Node3D).visible:
			count += 1
	return count


func get_part_count() -> int:
	return _parts.size()


func is_scaffolded() -> bool:
	return _scaffold.visible


# ---------------------------------------------------------------- Shapes
# Each of these adds one shape and returns it. "at" is when it appears.

func add_box(size: Vector3, centre: Vector3, colour: Color, at: float, turn := 0.0) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _add(shape, centre, colour, at, turn)


# A cylinder, or a cone if top_radius is close to 0. centre is its middle.
func add_cylinder(bottom_radius: float, top_radius: float, height: float, centre: Vector3, colour: Color, at: float, sides := 24) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom_radius
	shape.top_radius = top_radius
	shape.height = height
	shape.radial_segments = sides
	return _add(shape, centre, colour, at, 0.0)


# A roof with two sloping sides: a prism lying along the z axis.
func add_roof(size: Vector3, centre: Vector3, colour: Color, at: float, turn := 0.0) -> MeshInstance3D:
	var shape := PrismMesh.new()
	shape.size = size
	return _add(shape, centre, colour, at, turn)


func add_sphere(radius: float, centre: Vector3, colour: Color, at: float) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	return _add(shape, centre, colour, at, 0.0)


# Four poles and a ring of planks around the landmark, shown only while building.
func add_scaffold(half_width: float, height: float) -> void:
	for i in 4:
		var angle := i * TAU / 4.0 + TAU / 8.0
		var corner := Vector3(cos(angle), 0.0, sin(angle)) * half_width * 1.414
		_scaffold.add_child(_plain_box(Vector3(0.3, height, 0.3), corner + Vector3.UP * height * 0.5, 0.0))
		var side := i * TAU / 4.0
		var middle := Vector3(cos(side), 0.0, sin(side)) * half_width
		_scaffold.add_child(_plain_box(Vector3(0.25, 0.15, half_width * 2.0), middle + Vector3.UP * height * 0.45, -side))


func _add(shape: Mesh, centre: Vector3, colour: Color, at: float, turn: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(colour)
	node.position = centre
	node.rotation.y = turn
	add_child(node)
	_parts.append({ "node": node, "at": at })
	return node


func _plain_box(size: Vector3, centre: Vector3, turn: float) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(POLE)
	node.position = centre
	node.rotation.y = turn
	return node


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	return material
