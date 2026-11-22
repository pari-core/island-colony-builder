# event_effects.gd
# Shows each event on the island, using only built-in Godot effects:
#   Storm: dark sky, dim light, fog and rain.
#   Drought: harsh warm light, hazy sky and dry yellow grass.
#   Resource discovery: sparkles over Lumber Camps and Quarries (or the rocky hill).
#   Trade opportunity: a golden beacon on the beach where traders landed.
#   Disease outbreak: a red cross over each sick worker until they reach the Lab.
#   Migration: new workers walk in from the beach (see worker_manager.gd).
#   Building accident: the building tilts and sinks in a cloud of dust, and rises
#   again once repaired.
class_name EventEffects
extends Node3D

const WEATHER_SECONDS := 2.0     # How long the sky takes to change.
const COLLAPSE_SECONDS := 1.5
const COLLAPSE_TILT := 16.0      # Degrees the building leans when it collapses.
const COLLAPSE_SINK := 3.0       # Metres it sinks into the ground.
const ROCKY_HILL := Vector3(33.0, 18.0, -128.0)

const STORM_LOOK := {
	"sun_energy": 0.35, "sun_color": Color(0.8, 0.85, 0.95),
	"sky_top": Color(0.22, 0.25, 0.3), "sky_horizon": Color(0.42, 0.45, 0.48),
}
const DROUGHT_LOOK := {
	"sun_energy": 1.35, "sun_color": Color(1.0, 0.9, 0.74),
	"sky_top": Color(0.38, 0.55, 0.78), "sky_horizon": Color(0.88, 0.8, 0.62),
}
const DRY_GRASS := Color(0.97, 0.93, 0.5)
const STORM_FOG_DENSITY := 0.0015
const DROUGHT_WATER_DROP := 1.1  # Metres the river and sea fall in a drought.
const WATER_SECONDS := 12.0      # The water falls and rises slowly.

# The weather's light and sky. The storm and the drought change these, and
# DayNight (day_night.gd) puts them on the sun and the sky every frame, dimmed
# and tinted for the time of day.
var sun_energy := 1.0
var sun_color := Color.WHITE
var sky_top := Color.WHITE
var sky_horizon := Color.WHITE

var _normal_look := {}
var _normal_grass := Color.WHITE
var _rain: GPUParticles3D
var _water_target := 0.0
var _water_tween: Tween
var _temporary: Array[Node] = []   # Sparkles, beacon and red crosses, rebuilt on each change.

@onready var _events: EventManager = get_node("../EventManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _map: MapManager = get_node("../MapManager")
@onready var _sun: DirectionalLight3D = get_node("../Sun")
@onready var _environment: Environment = get_node("../WorldEnvironment").environment
@onready var _sky: ProceduralSkyMaterial = _environment.sky.sky_material
@onready var _terrain_material: ShaderMaterial = get_node("../Island/Terrain").material_override
@onready var _camera: Camera3D = get_node("../Camera3D")
@onready var _water: Node3D = get_node("../Island/Water")


func _ready() -> void:
	_normal_look = {
		"sun_energy": _sun.light_energy, "sun_color": _sun.light_color,
		"sky_top": _sky.sky_top_color, "sky_horizon": _sky.sky_horizon_color,
	}
	sun_energy = _sun.light_energy
	sun_color = _sun.light_color
	sky_top = _sky.sky_top_color
	sky_horizon = _sky.sky_horizon_color
	# The scene does not set grass_tint, so the shader's own default is in use.
	# Setting it here makes it readable and changeable. Keep in step with terrain.gdshader.
	var tint = _terrain_material.get_shader_parameter("grass_tint")
	_normal_grass = tint if tint != null else Color(0.8, 1.0, 0.48)
	_terrain_material.set_shader_parameter("grass_tint", _normal_grass)
	_rain = _make_rain()
	# The rain is attached to the camera, so it is always in view.
	_camera.add_child(_rain)
	_events.events_changed.connect(_refresh)
	_events.building_collapsed.connect(_collapse)
	_events.building_repaired.connect(_restore)
	_workers.workers_changed.connect(_refresh)


func _refresh() -> void:
	var storm := _events.is_active(EventManager.Type.STORM)
	var drought := _events.is_active(EventManager.Type.DROUGHT)
	_set_weather(STORM_LOOK if storm else DROUGHT_LOOK if drought else _normal_look, storm)
	_set_grass(DRY_GRASS if drought else _normal_grass)
	_set_water_level(-DROUGHT_WATER_DROP if drought else 0.0)
	_rain.emitting = storm

	for node in _temporary:
		node.queue_free()
	_temporary.clear()
	if _events.is_active(EventManager.Type.DISCOVERY):
		var spots: Array[Vector3] = []
		for plot in _map.get_plots():
			if plot.building_info.get("name", "") in ["Lumber Camp", "Quarry"]:
				spots.append(plot.building.position + Vector3(0, 4, 0))
		if spots.is_empty():
			spots.append(ROCKY_HILL)
		for spot in spots:
			_add_temporary(_make_sparkles(Color(1.0, 0.85, 0.3)), spot)
	if _events.is_active(EventManager.Type.TRADE):
		var beach := _events.get_beach_position()
		_add_temporary(_make_beacon(), beach + Vector3(0, 30, 0))
		_add_temporary(_make_sparkles(Color(1.0, 0.8, 0.2)), beach + Vector3(0, 3, 0))
	if _events.is_active(EventManager.Type.DISEASE):
		for worker in _events.get_patients():
			var mark := _make_sick_mark()
			worker.model.add_child(mark)
			mark.position = Vector3(0, 2.6, 0)
			_temporary.append(mark)


func _add_temporary(node: Node3D, at: Vector3) -> void:
	add_child(node)
	node.position = at
	_temporary.append(node)


func _set_weather(look: Dictionary, foggy: bool) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "sun_energy", look.sun_energy, WEATHER_SECONDS)
	tween.tween_property(self, "sun_color", look.sun_color, WEATHER_SECONDS)
	tween.tween_property(self, "sky_top", look.sky_top, WEATHER_SECONDS)
	tween.tween_property(self, "sky_horizon", look.sky_horizon, WEATHER_SECONDS)
	if foggy:
		_environment.fog_enabled = true
		_environment.fog_light_color = Color(0.5, 0.53, 0.56)
	tween.tween_property(_environment, "fog_density", STORM_FOG_DENSITY if foggy else 0.0, WEATHER_SECONDS)


# Lowers or raises the water. The river bed is shallow, so a small drop leaves
# the river narrow, with wide dry banks.
func _set_water_level(height: float) -> void:
	if _water_target == height:
		return
	_water_target = height
	if _water_tween != null:
		_water_tween.kill()
	_water_tween = create_tween()
	_water_tween.tween_property(_water, "position:y", height, WATER_SECONDS)


func _set_grass(colour: Color) -> void:
	var from: Color = _terrain_material.get_shader_parameter("grass_tint")
	var tween := create_tween()
	tween.tween_method(func(c: Color) -> void: _terrain_material.set_shader_parameter("grass_tint", c), from, colour, WEATHER_SECONDS)


func _collapse(plot: BuildingPlot) -> void:
	var building := plot.building
	var tween := create_tween().set_parallel()
	tween.tween_property(building, "rotation:x", deg_to_rad(COLLAPSE_TILT), COLLAPSE_SECONDS)
	tween.tween_property(building, "rotation:z", deg_to_rad(-COLLAPSE_TILT * 0.5), COLLAPSE_SECONDS)
	tween.tween_property(building, "position:y", building.position.y - COLLAPSE_SINK, COLLAPSE_SECONDS)
	var dust := _make_dust()
	add_child(dust)
	dust.position = building.position + Vector3(0, 2, 0)
	dust.emitting = true
	get_tree().create_timer(5.0).timeout.connect(dust.queue_free)


func _restore(plot: BuildingPlot) -> void:
	var building := plot.building
	var tween := create_tween().set_parallel()
	tween.tween_property(building, "rotation", Vector3.ZERO, COLLAPSE_SECONDS)
	tween.tween_property(building, "position:y", plot.position.y - MapManager.GROUND_LIFT, COLLAPSE_SECONDS)


# ---------- Effect builders ----------

func _particle_material(colour: Color, size: Vector2, additive: bool) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	return quad


func _make_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.amount = 2500
	rain.lifetime = 0.8
	rain.local_coords = false
	rain.emitting = false
	rain.position = Vector3(0, 0, -35)
	rain.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(35, 20, 25)
	process.direction = Vector3(0.15, -1, 0)
	process.spread = 3.0
	process.initial_velocity_min = 40.0
	process.initial_velocity_max = 45.0
	process.gravity = Vector3(0, -20, 0)
	rain.process_material = process
	var drop := _particle_material(Color(0.78, 0.82, 0.9, 0.3), Vector2(0.03, 1.2), false)
	(drop.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rain.draw_pass_1 = drop
	return rain


func _make_sparkles(colour: Color) -> GPUParticles3D:
	var sparkles := GPUParticles3D.new()
	sparkles.amount = 70
	sparkles.lifetime = 2.5
	sparkles.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 8.0
	process.direction = Vector3.UP
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 3.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.2
	sparkles.process_material = process
	sparkles.draw_pass_1 = _particle_material(colour, Vector2(0.6, 0.6), true)
	return sparkles


func _make_beacon() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.2
	cylinder.bottom_radius = 1.2
	cylinder.height = 60.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.8, 0.3, 0.5)
	cylinder.material = material
	beam.mesh = cylinder
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return beam


func _make_sick_mark() -> Label3D:
	var mark := Label3D.new()
	mark.text = "+"
	mark.font_size = 160
	mark.pixel_size = 0.012
	mark.modulate = Color(0.9, 0.1, 0.1)
	mark.outline_modulate = Color.WHITE
	mark.outline_size = 28
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	return mark


func _make_dust() -> GPUParticles3D:
	var dust := GPUParticles3D.new()
	dust.amount = 120
	dust.lifetime = 3.0
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.emitting = false
	dust.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 40, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 7.0
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 6.0
	process.gravity = Vector3(0, -1.0, 0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 1.0
	process.scale_max = 2.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	dust.process_material = process
	dust.draw_pass_1 = _particle_material(Color(0.55, 0.5, 0.42, 0.55), Vector2(3, 3), false)
	return dust
