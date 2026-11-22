# popup_manager.gd
# Small pieces of text that float up from a building and fade away, so the player
# can see things happening: "+9 Food" each time a building makes something,
# "Storage full", "Harvest!", "Farm built", "Level 2" and "New worker".
#
# Each one is a Label3D: text placed in the 3D world that always faces the camera
# and stays the same size on screen at any zoom.
class_name PopupManager
extends Node3D

const RISE := 5.0                # Metres the text floats up.
const SECONDS := 1.8             # How long it lasts.
const ABOVE_ROOF := 1.5          # Metres above the top of the building it starts.
const STACK_GAP := 58.0          # Pixels between two texts shown at once on one building.
const RESOURCE_COLOURS := {
	ResourceManager.Type.FOOD: Color(0.75, 1.0, 0.45),
	ResourceManager.Type.WOOD: Color(0.95, 0.7, 0.4),
	ResourceManager.Type.STONE: Color(0.88, 0.9, 0.95),
	ResourceManager.Type.GOLD: Color(1.0, 0.85, 0.3),
}
const GOOD_COLOUR := Color(1.0, 0.95, 0.75)
const BAD_COLOUR := Color(1.0, 0.4, 0.3)

var _tops := {}                  # Building -> height of its roof above the ground.
var _stacked := {}               # Plot -> how many texts started on it this frame.

@onready var _builder: BuildingManager = get_node("../BuildingManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _civilians: CivilianManager = get_node("../CivilianManager")
@onready var _crops: CropManager = get_node("../CropManager")


func _ready() -> void:
	_workers.produced.connect(_on_produced)
	_crops.harvested.connect(func(plot: BuildingPlot) -> void: show_on(plot, "Harvest!", RESOURCE_COLOURS[ResourceManager.Type.GOLD]))
	_builder.building_placed.connect(func(plot: BuildingPlot) -> void: show_on(plot, ("Building the %s" if plot.under_construction else "%s built") % plot.building_info.name, GOOD_COLOUR))
	get_node("../ConstructionManager").construction_finished.connect(func(plot: BuildingPlot) -> void: show_on(plot, "%s built" % plot.building_info.name, GOOD_COLOUR))
	_builder.building_upgraded.connect(func(plot: BuildingPlot) -> void: show_on(plot, "Level %d" % plot.level, GOOD_COLOUR))
	var research: ResearchManager = get_node("../ResearchManager")
	# The vaccine has its own "VACCINE READY!" (see disease_mission.gd).
	research.research_finished.connect(func(id: String) -> void:
		if id != "vaccine":
			show_on(research.get_working_lab(), "%s researched" % ResearchManager.PROJECTS[id].name, GOOD_COLOUR))
	_civilians.worker_trained.connect(func(plot: BuildingPlot) -> void: show_on(plot, "New worker", GOOD_COLOUR))


func _process(_delta: float) -> void:
	_stacked.clear()


# The text of every popup on screen now, for tests and debugging.
func get_texts() -> Array[String]:
	var texts: Array[String] = []
	for child in get_children():
		texts.append((child as Label3D).text)
	return texts


# Floats a piece of text up from the roof of this plot's building.
func show_on(plot: BuildingPlot, text: String, colour: Color) -> void:
	if plot == null or plot.building == null:
		return
	# A second text on the same building in the same frame starts higher.
	var stack: int = _stacked.get(plot, 0)
	_stacked[plot] = stack + 1
	var start := plot.building.global_position + Vector3.UP * (_roof_height(plot.building) + ABOVE_ROOF)
	show_at(start, text, colour, stack)


# Floats a piece of text up from a point in the world.
# line lifts the text by whole lines, so two texts in one place do not overlap.
func show_at(start: Vector3, text: String, colour: Color, line := 0) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0007
	label.font_size = 44
	label.offset = Vector2(0.0, line * STACK_GAP)
	label.outline_size = 12
	label.modulate = colour
	label.no_depth_test = true   # Never hidden behind a roof or a tree.
	add_child(label)
	label.global_position = start
	# Rise and fade together, then remove the label.
	var clear := Color(colour, 0.0)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position", start + Vector3.UP * RISE, SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate", clear, SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "outline_modulate", Color(0, 0, 0, 0), SECONDS).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _on_produced(plot: BuildingPlot, stored: int) -> void:
	var type: ResourceManager.Type = plot.building_info.produces
	if stored > 0:
		show_on(plot, "+%d %s" % [stored, ResourceManager.NAMES[type]], RESOURCE_COLOURS[type])
	else:
		show_on(plot, "Storage full", BAD_COLOUR)


# The height of the building's roof above its base, measured once and remembered.
func _roof_height(building: Node3D) -> float:
	if not _tops.has(building):
		var top := 0.0
		for mesh: GeometryInstance3D in building.find_children("*", "GeometryInstance3D", true, false):
			if not mesh is Label3D:
				top = maxf(top, (mesh.global_transform * mesh.get_aabb()).end.y - building.global_position.y)
		_tops[building] = top
	return _tops[building]


# Removes every text on screen. Used after loading a saved game, so the screen
# does not fill with "built" texts for buildings that were already there.
func clear() -> void:
	for child in get_children():
		child.queue_free()
