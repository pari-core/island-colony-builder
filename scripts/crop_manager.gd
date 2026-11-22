# crop_manager.gd
# Grows crops beside every Farm, so the player can see the farm working.
#
# Each Farm gets two beds of soil, one down each side of the building, planted
# with rows of crops. The crops are only for show: the food a Farm makes still
# comes from its workers, exactly as before.
#
#   - Every production cycle in which the Farm makes food, the crops grow a step.
#   - After GROW_CYCLES steps they are fully grown and turn golden.
#   - On the next cycle they are harvested: the beds go back to seedlings and
#     the "harvested" signal is sent (PopupManager shows "Harvest!").
#   - With no workers, or while the Farm is collapsed, nothing grows.
#   - During a drought the crops look dry.
#
# The plants are made by this script from thin leaf shapes, so no model file is
# needed. All the plants of one Farm are drawn together as a MultiMesh, which is
# Godot's fast way to draw many copies of one shape.
class_name CropManager
extends Node3D

signal harvested(plot: BuildingPlot)

const GROW_CYCLES := 6           # Production cycles from seedling to fully grown.
const BED_X := 9.9               # Each bed's centre, metres from the Farm's centre.
const BED_WIDTH := 3.2
const BED_LENGTH := 14.0
const BED_HEIGHT := 0.25
const ROWS := 3                  # Rows of plants in each bed.
const PLANTS_PER_ROW := 14
const PLANT_HEIGHT := 1.5        # Metres, fully grown.
const SEEDLING_SIZE := 0.12      # Size just after planting, as a fraction of full size.
const LEAVES := 7                # Leaves in each plant.
const SOIL_COLOUR := Color(0.24, 0.16, 0.1)
const YOUNG_COLOUR := Color(0.3, 0.62, 0.18)
const RIPE_COLOUR := Color(0.86, 0.7, 0.25)
const DRY_COLOUR := Color(0.6, 0.5, 0.28)
const GROW_SPEED := 1.0 / (GROW_CYCLES * WorkerManager.PRODUCTION_SECONDS)   # Per second.
const CUT_SPEED := 2.5           # How fast harvested crops shrink back, per second.

# One entry per Farm: plot -> { "node", "plants", "material", "growth", "shown", "places" }.
# "growth" is how grown the crops are (0 to 1); "shown" glides towards it.
var _fields := {}
var _plant_mesh: ArrayMesh
var _soil_material := StandardMaterial3D.new()

@onready var _builder: BuildingManager = get_node("../BuildingManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _events: EventManager = get_node("../EventManager")
@onready var _terrain: Node = get_node("../Island/Terrain")


func _ready() -> void:
	_plant_mesh = _make_plant_mesh()
	_soil_material.albedo_color = SOIL_COLOUR
	_soil_material.roughness = 1.0
	_builder.building_placed.connect(_on_building_placed)
	_workers.produced.connect(_on_produced)


func _process(delta: float) -> void:
	var dry := _events.is_active(EventManager.Type.DROUGHT)
	for plot in _fields:
		var field: Dictionary = _fields[plot]
		var speed := GROW_SPEED if field.growth > field.shown else CUT_SPEED
		var shown := move_toward(field.shown, field.growth, speed * delta)
		if shown != field.shown:
			field.shown = shown
			_update_plants(field)
		field.material.albedo_color = get_colour(plot, dry)


func has_field(plot: BuildingPlot) -> bool:
	return _fields.has(plot)


# How grown this Farm's crops are, from 0 (just planted) to 1 (ready to harvest).
func get_growth(plot: BuildingPlot) -> float:
	return _fields[plot].growth if _fields.has(plot) else 0.0


func is_ripe(plot: BuildingPlot) -> bool:
	return get_growth(plot) >= 1.0


# The colour of this Farm's crops: green, turning golden as they ripen, or dry.
func get_colour(plot: BuildingPlot, dry: bool) -> Color:
	var shown: float = _fields[plot].shown
	var colour := YOUNG_COLOUR.lerp(RIPE_COLOUR, smoothstep(0.65, 1.0, shown))
	return colour.lerp(DRY_COLOUR, 0.7) if dry else colour


func _on_building_placed(plot: BuildingPlot) -> void:
	if plot.building_info.name == "Farm":
		_add_field(plot)


# Called after each production cycle, for each building that made something.
func _on_produced(plot: BuildingPlot, _stored: int) -> void:
	if not _fields.has(plot):
		return
	var field: Dictionary = _fields[plot]
	if field.growth >= 1.0:
		field.growth = 0.0
		harvested.emit(plot)
	else:
		# snappedf removes tiny rounding errors, so six steps reach exactly 1.
		field.growth = minf(snappedf(field.growth + 1.0 / GROW_CYCLES, 0.001), 1.0)
		if field.growth > 0.99:
			field.growth = 1.0


func _add_field(plot: BuildingPlot) -> void:
	var node := Node3D.new()
	node.name = "Field%02d" % plot.plot_id
	add_child(node)
	node.position = Vector3(plot.position.x, _terrain.LAND_HEIGHT, plot.position.z)
	node.rotation.y = plot.rotation.y

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true   # Leaves are darker at the base.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED   # Leaves are seen from both sides.
	material.roughness = 0.9
	material.albedo_color = YOUNG_COLOUR

	var plants := MultiMesh.new()
	plants.transform_format = MultiMesh.TRANSFORM_3D
	plants.mesh = _plant_mesh
	plants.instance_count = 2 * ROWS * PLANTS_PER_ROW
	var places: Array[Transform3D] = []
	# The same seed for the same plot, so a Farm's crops always look the same.
	var random := RandomNumberGenerator.new()
	random.seed = plot.plot_id
	for side: float in [-1.0, 1.0]:
		var soil := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BED_WIDTH, BED_HEIGHT, BED_LENGTH)
		soil.mesh = box
		soil.material_override = _soil_material
		soil.position = Vector3(side * BED_X, BED_HEIGHT * 0.5 - 0.05, 0.0)
		node.add_child(soil)
		for row in ROWS:
			for i in PLANTS_PER_ROW:
				var x := side * BED_X + (row - (ROWS - 1) * 0.5) * (BED_WIDTH / ROWS)
				var z := (i + 0.5) / PLANTS_PER_ROW * BED_LENGTH - BED_LENGTH * 0.5
				var turn := Basis(Vector3.UP, random.randf() * TAU)
				var size := random.randf_range(0.85, 1.15)
				places.append(Transform3D(turn.scaled(Vector3.ONE * size), Vector3(x, BED_HEIGHT - 0.05, z)))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = plants
	instance.material_override = material
	node.add_child(instance)
	var field := { "node": node, "plants": plants, "material": material, "growth": 0.0, "shown": 0.0, "places": places }
	_fields[plot] = field
	_update_plants(field)


# Sets every plant's size from how grown the field looks.
func _update_plants(field: Dictionary) -> void:
	var size := lerpf(SEEDLING_SIZE, 1.0, field.shown)
	for i in field.places.size():
		var place: Transform3D = field.places[i]
		field.plants.set_instance_transform(i, Transform3D(place.basis.scaled(Vector3.ONE * size), place.origin))


# One plant: a few thin leaves rising from the same point and bending outwards.
# Each leaf is two flat pieces, narrow at the tip.
func _make_plant_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed = 11
	var dark := Color(0.55, 0.55, 0.55)   # Multiplied with the crop colour at the base.
	for leaf in LEAVES:
		var angle := TAU * leaf / LEAVES + random.randf_range(-0.3, 0.3)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var lean := random.randf_range(0.12, 0.38)
		var tall := PLANT_HEIGHT * random.randf_range(0.75, 1.0)
		var base := out * 0.03
		var middle := out * (lean * 0.45) + Vector3.UP * tall * 0.55
		var tip := out * lean * 1.6 + Vector3.UP * tall
		var points := [base - side * 0.1, base + side * 0.1, middle - side * 0.09, middle + side * 0.09, tip]
		var colours := [dark, dark, Color.WHITE, Color.WHITE, Color.WHITE]
		for corner: int in [0, 1, 2, 1, 3, 2, 2, 3, 4]:
			# Normals point mostly up, so both sides of a leaf catch the sun.
			tool.set_normal((Vector3.UP + out * 0.4).normalized())
			tool.set_color(colours[corner])
			tool.add_vertex(points[corner])
	return tool.commit()


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


# How grown each Farm's crops are, by plot number.
func get_save_data() -> Dictionary:
	var fields := []
	for plot: BuildingPlot in _fields:
		fields.append({ "plot": plot.plot_id, "growth": _fields[plot].growth })
	return { "fields": fields }


# Called after the buildings are back, so every Farm already has its field.
func load_save_data(data: Dictionary) -> void:
	for entry: Dictionary in data.get("fields", []):
		var plot: BuildingPlot = get_node("../MapManager").get_plot(int(entry.get("plot", 0)))
		if plot != null and _fields.has(plot):
			var field: Dictionary = _fields[plot]
			field.growth = clampf(float(entry.get("growth", 0.0)), 0.0, 1.0)
			field.shown = field.growth
			_update_plants(field)
