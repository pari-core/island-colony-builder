# island_details.gd
# Small touches that make the island feel lived in (v2, from the team's picture):
#   - a waterfall pouring off the cliff into the lake, with spray at its foot;
#   - a wooden jetty on the eastern beach, with a rowing boat tied up beside it;
#   - a campfire in the town square, flickering, with smoke;
#   - smoke rising from the chimney of every House that is built.
# All of it is made from simple shapes and particles in code, so there are no
# model files or licences. None of it changes the game's rules.
class_name IslandDetails
extends Node3D

const FALL_WIDTH := 11.0
const JETTY_LENGTH := 30.0
const JETTY_WIDTH := 4.0
const JETTY_Z := -12.0           # Beside the ship's landing place, not in its way.
const CAMPFIRE := Vector3(0.0, 0.0, -8.0)
const WOOD := Color(0.45, 0.3, 0.18)
const DARK_WOOD := Color(0.3, 0.2, 0.12)
const STONE := Color(0.5, 0.48, 0.45)

@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _events: EventManager = get_node("../EventManager")
@onready var _builder: BuildingManager = get_node("../BuildingManager")


var _signs := {}                 # Plot -> its warning sign (Label3D).
var _sign_wait := 0.0

@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _map: MapManager = get_node("../MapManager")


func _ready() -> void:
	_add_waterfall()
	_add_jetty()
	_add_campfire()
	_builder.building_placed.connect(func(plot: BuildingPlot) -> void:
		if plot.building_info.name == "House":
			_add_chimney_smoke(plot.building)
		elif plot.building_info.name == "Farm":
			_add_fence(plot))


# Signs over work buildings that are not making anything (team report,
# 2026-11-23: "the wood is not increasing"): "No workers: select it and add one"
# when nobody works there, and "Storage full" when its goods have no room left.
func _process(delta: float) -> void:
	_sign_wait -= delta
	if _sign_wait > 0.0:
		return
	_sign_wait = 0.5
	for plot in _map.get_plots():
		var text := ""
		if plot.building != null and plot.building_info.has("produces") and not plot.under_construction:
			if _workers.get_workers_at(plot).is_empty():
				text = "No workers: select it and add one"
			elif _resources.get_amount(plot.building_info.produces) >= _resources.get_capacity():
				text = "Storage full: build a Warehouse"
		var sign: Label3D = _signs.get(plot)
		if text == "":
			if sign != null:
				sign.queue_free()
				_signs.erase(plot)
			continue
		if sign == null:
			sign = Label3D.new()
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.fixed_size = true
			sign.pixel_size = 0.0006
			sign.font_size = 34
			sign.outline_size = 10
			sign.modulate = Color(1.0, 0.86, 0.55)
			sign.outline_modulate = Color(0.25, 0.13, 0.05)
			sign.no_depth_test = true
			add_child(sign)
			sign.position = Vector3(plot.position.x, _terrain.get_height_at(plot.position.x, plot.position.z) + 16.0, plot.position.z)
			_signs[plot] = sign
		sign.text = text


# ---------------------------------------------------------------- Waterfall

func _add_waterfall() -> void:
	var cliff: Vector2 = _terrain.CLIFF_CENTRE
	# The lip: the point on the cliff's edge facing the lake, where the water falls.
	var lake: Vector2 = _terrain.LAKE_CENTRE
	var out := (lake - cliff).normalized()
	var lip: Vector2 = cliff + out * (_terrain.CLIFF_RADIUS - 6.0)
	var top: float = _terrain.get_height_at(lip.x, lip.y)
	var foot: Vector2 = cliff + out * (_terrain.CLIFF_RADIUS + 2.5)
	var bottom := 0.0                # The lake's surface.
	var fall := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(FALL_WIDTH, top - bottom)
	fall.mesh = quad
	fall.material_override = _waterfall_material()
	add_child(fall)
	var middle: Vector2 = (lip + foot) * 0.5
	fall.position = Vector3(middle.x, (top + bottom) * 0.5, middle.y)
	fall.rotation.y = atan2(out.x, out.y)
	fall.name = "Waterfall"
	var spray := _particles(Color(0.92, 0.97, 1.0, 0.7), 60, 1.2, Vector3(0, 3.5, 0), 2.5, 0.9)
	add_child(spray)
	spray.position = Vector3(foot.x, 0.3, foot.y)
	spray.name = "Spray"


func _waterfall_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, unshaded;
uniform sampler2D streaks : repeat_enable;
void fragment() {
	// Streaks of white water rush down; the edges fade out.
	float flow = texture(streaks, vec2(UV.x * 1.5, UV.y * 0.6 - TIME * 1.4)).r;
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	vec3 water = mix(vec3(0.45, 0.75, 0.95), vec3(1.0), smoothstep(0.35, 0.75, flow));
	ALBEDO = water;
	ALPHA = edge * mix(0.55, 0.95, flow);
}
"""
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var texture := NoiseTexture2D.new()
	texture.width = 128
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("streaks", texture)
	return material


# ---------------------------------------------------------------- Jetty and boat

func _add_jetty() -> void:
	# Where the sand meets the sea along the jetty's line. (Worked out here, since
	# EventManager may not be ready yet.)
	var x := 260.0
	while x > 0.0 and _terrain.get_height_at(x, JETTY_Z) < 0.6:
		x -= 1.0
	var start := Vector3(x - 6.0, 0.0, JETTY_Z)
	var deck_height := 1.4
	# The deck: planks from the sand out over the water.
	for i in int(JETTY_LENGTH / 1.0):
		var plank := _box(Vector3(0.9, 0.15, JETTY_WIDTH), WOOD if i % 2 == 0 else DARK_WOOD.lightened(0.15))
		plank.position = start + Vector3(i + 0.5, deck_height, 0.0)
	# Posts down into the water.
	for i in range(0, int(JETTY_LENGTH) + 1, 5):
		for side in [-1.0, 1.0]:
			var post := _cylinder(0.18, 3.2, DARK_WOOD)
			post.position = start + Vector3(i, deck_height - 1.4, side * (JETTY_WIDTH * 0.5 + 0.1))
	# A lamp post at the end.
	var lamp := _cylinder(0.12, 3.0, DARK_WOOD)
	lamp.position = start + Vector3(JETTY_LENGTH - 0.5, deck_height + 1.5, JETTY_WIDTH * 0.5)
	# The rowing boat, tied up alongside.
	var boat := Node3D.new()
	boat.name = "RowingBoat"
	add_child(boat)
	boat.position = start + Vector3(JETTY_LENGTH - 8.0, 0.15, -JETTY_WIDTH * 0.5 - 2.0)
	var hull := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = 1.2
	shape.bottom_radius = 0.7
	shape.height = 5.5
	hull.mesh = shape
	hull.material_override = _material(WOOD)
	hull.rotation = Vector3(0.0, 0.0, PI / 2.0)
	hull.scale = Vector3(1.0, 1.0, 0.55)
	boat.add_child(hull)
	var seat := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(0.4, 0.1, 1.5)
	seat.mesh = board
	seat.material_override = _material(DARK_WOOD)
	seat.position = Vector3(0.0, 0.55, 0.0)
	boat.add_child(seat)


# ---------------------------------------------------------------- Campfire

func _add_campfire() -> void:
	var at := Vector3(CAMPFIRE.x, _terrain.get_height_at(CAMPFIRE.x, CAMPFIRE.z), CAMPFIRE.z)
	var fire := Node3D.new()
	fire.name = "Campfire"
	add_child(fire)
	fire.position = at
	for i in 8:   # A ring of stones.
		var stone := _sphere(0.35, STONE)
		fire.add_child(stone)
		stone.position = Vector3(cos(i * TAU / 8.0), 0.15, sin(i * TAU / 8.0)) * 1.2
	for i in 3:   # Crossed logs.
		var log := _cylinder(0.14, 1.6, WOOD)
		remove_child(log)   # _cylinder adds it here; it belongs to the fire.
		fire.add_child(log)
		log.position = Vector3(0.0, 0.25, 0.0)
		log.rotation = Vector3(PI / 2.0 - 0.35, i * TAU / 3.0, 0.0)
	var flames := _particles(Color(1.0, 0.55, 0.15, 0.9), 40, 0.7, Vector3(0, 2.2, 0), 0.35, 0.5)
	(flames.process_material as ParticleProcessMaterial).scale_min = 0.6
	fire.add_child(flames)
	flames.position.y = 0.4
	var smoke := _particles(Color(0.5, 0.5, 0.5, 0.35), 20, 3.5, Vector3(0.3, 1.6, 0), 0.4, 1.4)
	fire.add_child(smoke)
	smoke.position.y = 1.5
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.0
	light.omni_range = 9.0
	fire.add_child(light)
	light.position.y = 1.0


func _add_chimney_smoke(house: Node3D) -> void:
	var smoke := _particles(Color(0.85, 0.85, 0.85, 0.45), 14, 4.0, Vector3(0.4, 1.2, 0), 0.5, 1.2)
	smoke.name = "ChimneySmoke"
	house.add_child(smoke)
	smoke.position = Vector3(2.0, 8.0, -1.5)


# A wooden fence round a Farm's square, open at the front (towards the path),
# like the fenced fields in the team's picture.
func _add_fence(plot: BuildingPlot) -> void:
	# Kept apart from the building, so it does not count as part of its walls
	# (workers stand inside the fence to work the fields).
	var fence := Node3D.new()
	fence.name = "Fence%d" % plot.plot_id
	add_child(fence)
	fence.position = Vector3(plot.position.x, _terrain.get_height_at(plot.position.x, plot.position.z), plot.position.z)
	fence.rotation.y = plot.rotation.y
	var half := BuildingPlot.SIZE * 0.5 - 0.6
	var corners := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var posts := int(length / 2.4)
		for i in posts + 1:
			var t := float(i) / posts
			var p := a.lerp(b, t)
			# Leave a gate in the middle of the front side (+z).
			if side == 2 and absf(p.x) < 2.5:
				continue
			var post := _cylinder(0.09, 1.2, DARK_WOOD)
			remove_child(post)
			fence.add_child(post)
			post.position = Vector3(p.x, 0.6, p.y)
		for height in [0.45, 0.95]:
			for piece in ([[a, b]] if side != 2 else [[a, Vector2(-2.5, half)], [Vector2(2.5, half), b]]):
				var from: Vector2 = piece[0]
				var to: Vector2 = piece[1]
				var rail := _box(Vector3(0.07, 0.09, from.distance_to(to)), WOOD)
				remove_child(rail)
				fence.add_child(rail)
				var middle := (from + to) * 0.5
				rail.position = Vector3(middle.x, height, middle.y)
				rail.rotation.y = atan2(to.x - from.x, to.y - from.y)


# ---------------------------------------------------------------- Helpers

# Soft round puffs that drift up and fade: used for fire, smoke and spray.
func _particles(colour: Color, amount: int, life: float, velocity: Vector3, spread: float, size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = life
	var process := ParticleProcessMaterial.new()
	process.direction = velocity.normalized()
	process.initial_velocity_min = velocity.length() * 0.7
	process.initial_velocity_max = velocity.length()
	process.spread = 25.0
	process.gravity = Vector3.ZERO
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = spread
	var fade := Gradient.new()
	fade.set_color(0, colour)
	fade.set_color(1, Color(colour, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	process.scale_min = 0.8
	process.scale_max = 1.6
	particles.process_material = process
	var puff := SphereMesh.new()
	puff.radius = size * 0.5
	puff.height = size
	puff.radial_segments = 8
	puff.rings = 4
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	puff.material = look
	particles.draw_pass_1 = puff
	return particles


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m


func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	node.mesh = b
	node.material_override = _material(colour)
	add_child(node)
	return node


func _cylinder(radius: float, height: float, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 8
	node.mesh = c
	node.material_override = _material(colour)
	add_child(node)
	return node


func _sphere(radius: float, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 1.6
	node.mesh = s
	node.material_override = _material(colour)
	return node
