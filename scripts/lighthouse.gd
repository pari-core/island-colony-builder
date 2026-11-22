# lighthouse.gd
# The Lighthouse, the colony's landmark: a tall white tower with red bands on a
# stone base, with a lamp room and a red roof on top.
#
# Like the Water Storage it is made here from simple shapes, because the project
# has no lighthouse model. That also lets it be shown half built:
# set_progress() raises the tower bit by bit, and the lamp is lit at the end.
extends Node3D

const BASE_RADIUS := 6.5
const BASE_HEIGHT := 1.6
const TOWER_BOTTOM := 4.2        # Radius of the tower at its foot.
const TOWER_TOP := 2.6           # Radius under the gallery.
const TOWER_HEIGHT := 20.0
const SECTIONS := 5              # Bands of the tower: white, red, white, red, white.
const GALLERY_RADIUS := 3.8
const GALLERY_HEIGHT := 0.5
const LAMP_RADIUS := 2.0
const LAMP_HEIGHT := 3.0
const ROOF_HEIGHT := 2.6
const BASE_PART := 0.1           # The first 10% of the work lays the base.
const TOWER_PART := 0.7          # The next 70% raises the tower.
const STONE := Color(0.56, 0.54, 0.5)
const WHITE := Color(0.93, 0.92, 0.88)
const RED := Color(0.72, 0.13, 0.1)
const IRON := Color(0.16, 0.16, 0.17)
const POLE := Color(0.72, 0.6, 0.4)
const GLASS := Color(1.0, 0.93, 0.6)
const DOOR := Color(0.3, 0.19, 0.1)

var _base: MeshInstance3D
var _sections: Array[MeshInstance3D] = []
var _door: MeshInstance3D
var _gallery: MeshInstance3D
var _rail: MeshInstance3D
var _lamp: MeshInstance3D
var _roof: MeshInstance3D
var _light := OmniLight3D.new()
var _scaffold := Node3D.new()
var _lit := false


# _init runs as soon as the building is created, before it is put in the world,
# so the see-through placement preview already has its shapes.
func _init() -> void:
	_base = _cylinder(BASE_RADIUS, BASE_RADIUS, BASE_HEIGHT, STONE, 1.0)
	_base.position.y = BASE_HEIGHT * 0.5

	# The tower narrows towards the top, one band at a time.
	var section_height := TOWER_HEIGHT / SECTIONS
	for i in SECTIONS:
		var bottom := lerpf(TOWER_BOTTOM, TOWER_TOP, float(i) / SECTIONS)
		var top := lerpf(TOWER_BOTTOM, TOWER_TOP, float(i + 1) / SECTIONS)
		var section := _cylinder(top, bottom, section_height, WHITE if i % 2 == 0 else RED, 0.8)
		section.position.y = BASE_HEIGHT + section_height * (i + 0.5)
		_sections.append(section)

	_door = _box(Vector3(1.6, 2.8, 0.4), Vector3(0.0, BASE_HEIGHT + 1.4, TOWER_BOTTOM - 0.15), 0.0, DOOR)
	add_child(_door)

	var tower_top := BASE_HEIGHT + TOWER_HEIGHT
	_gallery = _cylinder(GALLERY_RADIUS, GALLERY_RADIUS, GALLERY_HEIGHT, IRON, 0.6)
	_gallery.position.y = tower_top + GALLERY_HEIGHT * 0.5
	_rail = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = GALLERY_RADIUS - 0.2
	ring.outer_radius = GALLERY_RADIUS
	_rail.mesh = ring
	_rail.material_override = _material(IRON, 0.6)
	_rail.position.y = tower_top + GALLERY_HEIGHT + 1.1
	add_child(_rail)

	_lamp = _cylinder(LAMP_RADIUS, LAMP_RADIUS, LAMP_HEIGHT, GLASS, 0.1)
	_lamp.position.y = tower_top + GALLERY_HEIGHT + LAMP_HEIGHT * 0.5
	_roof = _cylinder(0.05, LAMP_RADIUS + 0.5, ROOF_HEIGHT, RED, 0.7)
	_roof.position.y = tower_top + GALLERY_HEIGHT + LAMP_HEIGHT + ROOF_HEIGHT * 0.5

	_light.light_color = GLASS
	_light.light_energy = 6.0
	_light.omni_range = 60.0
	_light.position.y = _lamp.position.y
	add_child(_light)

	# Scaffolding: four tall poles and two rings of planks, shown only while building.
	add_child(_scaffold)
	for i in 4:
		var angle := i * TAU / 4.0 + TAU / 8.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		_scaffold.add_child(_box(Vector3(0.3, 22.0, 0.3), out * (TOWER_BOTTOM + 2.2) + Vector3.UP * 11.0, 0.0, POLE))
		var side := i * TAU / 4.0
		var middle := Vector3(cos(side), 0.0, sin(side)) * (TOWER_BOTTOM + 1.55)
		for height: float in [7.0, 14.0]:
			_scaffold.add_child(_box(Vector3(0.25, 0.15, 9.2), middle + Vector3.UP * height, -side, POLE))
	set_progress(1.0)


# How far built the Lighthouse looks, from 0 (just marked out) to 1 (finished).
func set_progress(progress: float) -> void:
	var base_done := clampf(progress / BASE_PART, 0.0, 1.0)
	_base.scale.y = lerpf(0.2, 1.0, base_done)
	_base.position.y = BASE_HEIGHT * 0.5 * _base.scale.y

	# Each band of the tower appears when the work reaches it, and grows upwards.
	var tower_done := clampf((progress - BASE_PART) / TOWER_PART, 0.0, 1.0)
	var section_height := TOWER_HEIGHT / SECTIONS
	for i in SECTIONS:
		var done := clampf(tower_done * SECTIONS - i, 0.0, 1.0)
		var section := _sections[i]
		section.visible = done > 0.0
		section.scale.y = maxf(done, 0.02)
		section.position.y = BASE_HEIGHT + section_height * (i + 0.5 * done)
	_door.visible = tower_done > 0.2

	# The gallery, the lamp room and the roof come last, in that order.
	var top_start := BASE_PART + TOWER_PART
	_gallery.visible = progress >= top_start
	_rail.visible = progress >= top_start
	_lamp.visible = progress >= top_start + 0.1
	_roof.visible = progress >= top_start + 0.15
	_scaffold.visible = progress < 1.0
	_set_lit(progress >= 1.0)


# True once the lamp is shining, which only a finished Lighthouse does.
func is_lit() -> bool:
	return _lit


func _set_lit(lit: bool) -> void:
	_lit = lit
	_light.visible = lit
	var glass := _lamp.material_override as StandardMaterial3D
	glass.emission_enabled = lit
	glass.emission = GLASS
	glass.emission_energy_multiplier = 3.0


func _cylinder(top_radius: float, bottom_radius: float, height: float, colour: Color, roughness: float) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = top_radius
	shape.bottom_radius = bottom_radius
	shape.height = height
	shape.radial_segments = 32
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(colour, roughness)
	add_child(node)
	return node


func _box(size: Vector3, at: Vector3, turn: float, colour: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = _material(colour, 0.9)
	node.position = at
	node.rotation.y = turn
	return node


func _material(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	return material
