# building_manager.gd
# Handles placing buildings on plots: choosing a building, the see-through preview, the green or red
# indicators, the cost display, confirming and cancelling.
#
# While placing, this script uses the mouse clicks and the Esc key itself, so the
# plot selection in MapManager does not react to them as well.
#
# Upgrades: a building with an "upgrades" list can be upgraded on its own plot,
# one level at a time (U, or the ESP32 Action menu later). Each list entry is the
# cost of the next level. The model grows a little with each level, and a sign
# above it ("Lv 2") shows the level from any distance.
class_name BuildingManager
extends Node3D

signal building_placed(plot: BuildingPlot)
signal building_upgraded(plot: BuildingPlot)

# Every building the player can place. Costs are first guesses, to be balanced
# once the game is playable. To add a building, add it to this list and add a key
# for it in Project Settings > Input Map.
const BUILDINGS := [
	{
		"name": "House",
		"scene": preload("res://scenes/buildings/House.tscn"),
		"cost": { ResourceManager.Type.WOOD: 20, ResourceManager.Type.STONE: 10 },
	},
	{
		"name": "Farm",
		"scene": preload("res://scenes/buildings/Farm.tscn"),
		"cost": { ResourceManager.Type.WOOD: 25 },
		"produces": ResourceManager.Type.FOOD,
		"worker_slots": 2,
		"output_scale": 1.5,   # One Farm comfortably feeds the first colony.
	},
	{
		"name": "Lumber Camp",
		"scene": preload("res://scenes/buildings/LumberCamp.tscn"),
		"cost": { ResourceManager.Type.WOOD: 20, ResourceManager.Type.STONE: 5 },
		"produces": ResourceManager.Type.WOOD,
		"worker_slots": 2,
	},
	{
		"name": "Quarry",
		"scene": preload("res://scenes/buildings/Quarry.tscn"),
		"cost": { ResourceManager.Type.WOOD: 25 },
		"produces": ResourceManager.Type.STONE,
		"worker_slots": 2,
	},
	{
		"name": "Warehouse",
		"scene": preload("res://scenes/buildings/Warehouse.tscn"),
		"cost": { ResourceManager.Type.WOOD: 30, ResourceManager.Type.STONE: 20 },
		# Costs of level 2 and level 3. Each level adds storage (see resource_manager.gd).
		"upgrades": [
			{ ResourceManager.Type.WOOD: 40, ResourceManager.Type.STONE: 30 },
			{ ResourceManager.Type.WOOD: 60, ResourceManager.Type.STONE: 50 },
		],
	},
	{
		"name": "Research Lab",
		"scene": preload("res://scenes/buildings/ResearchLab.tscn"),
		"cost": { ResourceManager.Type.WOOD: 25, ResourceManager.Type.STONE: 15, ResourceManager.Type.GOLD: 10 },
	},
	{
		"name": "Mine",
		"scene": preload("res://scenes/buildings/Mine.tscn"),
		"cost": { ResourceManager.Type.WOOD: 30, ResourceManager.Type.STONE: 15 },
		"produces": ResourceManager.Type.GOLD,
		"worker_slots": 2,
		# Gold is valuable, so a Mine makes less than other buildings: 40% of its
		# workers' productivity.
		"output_scale": 0.4,
	},
	{
		"name": "Water Storage",
		"scene": preload("res://scenes/buildings/WaterStorage.tscn"),
		"cost": { ResourceManager.Type.WOOD: 10, ResourceManager.Type.STONE: 5 },
		"locked": true,        # Hidden until the first drought (see drought_mission.gd).
		"limit": 1,            # The colony can only have one.
		"build_days": 3.0,     # Takes time to build (see construction_manager.gd).
		"builders": 2,
	},
	# The three landmarks. Finishing all of them wins the game (see
	# game_state_manager.gd). They are dear and slow on purpose, to give spare
	# wood, stone and gold a use. Each cost follows what the landmark is made of,
	# and each fits inside the starting storage limit of 200.
	{
		"name": "Lighthouse",
		"scene": preload("res://scenes/buildings/Lighthouse.tscn"),
		"cost": { ResourceManager.Type.WOOD: 150, ResourceManager.Type.STONE: 120, ResourceManager.Type.GOLD: 40 },
		"landmark": true,
		"limit": 1,
		"build_days": 5.0,
		"builders": 3,
	},
	{
		"name": "Harbour",
		"scene": preload("res://scenes/buildings/Harbour.tscn"),
		"cost": { ResourceManager.Type.WOOD: 180, ResourceManager.Type.STONE: 40, ResourceManager.Type.GOLD: 20 },
		"landmark": true,
		"limit": 1,
		"build_days": 3.0,
		"builders": 3,
	},
	{
		"name": "Town Hall",
		"scene": preload("res://scenes/buildings/TownHall.tscn"),
		"cost": { ResourceManager.Type.WOOD: 150, ResourceManager.Type.STONE: 150, ResourceManager.Type.GOLD: 50 },
		"landmark": true,
		"limit": 1,
		"build_days": 4.0,
		"builders": 3,
	},
]

const PREVIEW_VALID_COLOUR := Color(0.2, 1.0, 0.3, 0.45)
const PREVIEW_INVALID_COLOUR := Color(1.0, 0.15, 0.1, 0.45)
const UPGRADE_GROWTH := 0.1      # Each level makes the model 10% bigger.
const UPGRADE_SECONDS := 0.6     # How long the growing animation takes.
const LEVEL_SIGN_HEIGHT := 3.0   # Metres above the top of the model.
const LEVEL_SIGN_NAME := "LevelSign"
const MOUSE_WAKE_PIXELS := 2.0   # The mouse must move this far to take the cursor back.

var _is_placing := false
var _chosen_index := 0           # Which entry of BUILDINGS is being placed.
var _preview: Node3D = null
var _preview_material := StandardMaterial3D.new()
var _hovered_plot: BuildingPlot = null
# The controller test switches this off, so a moving mouse cannot disturb it.
var mouse_enabled := true

var _follow_mouse := true        # False while the controller's arrows hold the cursor.
var _last_mouse := Vector2.ZERO
var _unlocked := {}              # Names of "locked" buildings the player may now build.

@onready var _map: MapManager = get_node("../MapManager")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _label: Label = get_node("../UI/PlacementLabel")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _population: PopulationManager = get_node("../PopulationManager")


func _ready() -> void:
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# If resources change during placement, the green or red preview must update.
	_resources.resources_changed.connect(_refresh_preview)


# While placing, follow the mouse every frame. Checking only when the mouse moves
# would miss the plot changing because the camera moved.
func _process(_delta: float) -> void:
	if not _is_placing:
		return
	# Moving the mouse takes the cursor back from the controller's arrows.
	var mouse := get_viewport().get_mouse_position()
	if mouse_enabled and mouse.distance_to(_last_mouse) > MOUSE_WAKE_PIXELS:
		_last_mouse = mouse
		_follow_mouse = true
	if mouse_enabled and _follow_mouse:
		_set_hovered_plot(_map.get_plot_under_screen_point(mouse))


# Nodes later in the scene receive input first, and BuildingManager comes after
# MapManager. set_input_as_handled() stops MapManager receiving the same input.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build"):
		if _is_placing:
			cancel_placement()
		else:
			start_placement()
		get_viewport().set_input_as_handled()
	elif not _is_placing and event.is_action_pressed("upgrade_building"):
		var plot := _map.get_selected_plot()
		if plot != null and plot.building != null:
			upgrade(plot)
			get_viewport().set_input_as_handled()
	elif not _is_placing:
		return
	elif event.is_action_pressed("ui_cancel"):
		cancel_placement()
		get_viewport().set_input_as_handled()
	elif _choose_from_keys(event):
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_hovered_plot(_map.get_plot_under_screen_point(event.position))
		confirm_placement()
		get_viewport().set_input_as_handled()


# Enters placement mode. The keyboard and the ESP32 Build button can both call this.
func start_placement() -> void:
	if _is_placing:
		return
	_is_placing = true
	_map.select_plot(null)
	_map.set_outlines_visible(true)
	_preview = _create_preview()
	_preview.visible = false
	add_child(_preview)
	_label.visible = true
	_follow_mouse = true
	_last_mouse = get_viewport().get_mouse_position()
	_refresh_preview()


# Changes which building is being placed. The ESP32 encoder can call this too.
func choose_building(index: int) -> void:
	if index < 0 or index >= BUILDINGS.size() or index == _chosen_index or not is_available(index):
		return
	_chosen_index = index
	if _is_placing:
		_preview.queue_free()
		_preview = _create_preview()
		add_child(_preview)
		_refresh_preview()


func get_chosen_index() -> int:
	return _chosen_index


# False for a "locked" building that has not been unlocked yet. Those are left
# out of the build list.
func is_available(index: int) -> bool:
	var building: Dictionary = BUILDINGS[index]
	return not building.get("locked", false) or _unlocked.has(building.name)


# Adds a locked building to the build list. Returns false if it was already there.
func unlock(building_name: String) -> bool:
	if _unlocked.has(building_name):
		return false
	_unlocked[building_name] = true
	_refresh_preview()
	return true


# Why this building cannot be placed anywhere right now, or "" if it can.
# This is about the building itself, not about the square or the cost.
func get_placement_problem(index: int) -> String:
	var building: Dictionary = BUILDINGS[index]
	if not is_available(index):
		return "The %s is not available yet" % building.name
	if building.has("limit"):
		var built := 0
		for plot in _map.get_plots():
			if plot.building != null and plot.building_info.name == building.name:
				built += 1
		if built >= building.limit:
			return "The colony already has a %s" % building.name
	return ""


# Puts the placement cursor on a plot. The controller's arrows use this. The
# cursor stays there until the mouse moves.
func set_cursor_plot(plot: BuildingPlot) -> void:
	if _is_placing:
		_follow_mouse = false
		_set_hovered_plot(plot)


func get_cursor_plot() -> BuildingPlot:
	return _hovered_plot


# True while the mouse, not the controller, decides where the cursor is.
func is_following_mouse() -> bool:
	return _follow_mouse


func get_chosen_building() -> Dictionary:
	return BUILDINGS[_chosen_index]


# Leaves placement mode without building anything.
func cancel_placement() -> void:
	if _is_placing:
		_stop_placing()


# Builds on the plot under the pointer, if that is allowed. An invalid plot keeps
# placement mode open, so the player can pick another plot or cancel.
func confirm_placement() -> void:
	if not _is_placing or _hovered_plot == null or not _hovered_plot.is_buildable():
		return
	if get_placement_problem(_chosen_index) != "":
		return
	# spend() takes the cost only if all of it can be paid.
	if not _resources.spend(get_chosen_building().cost):
		return
	var plot := _hovered_plot
	_stop_placing()
	_place_building(plot)


func is_placing() -> bool:
	return _is_placing


# The highest level this plot's building can reach (1 if it has no upgrades).
func get_max_level(plot: BuildingPlot) -> int:
	return plot.building_info.get("upgrades", []).size() + 1


# The cost of this plot's next level, or an empty dictionary if there is none.
func get_upgrade_cost(plot: BuildingPlot) -> Dictionary:
	var upgrades: Array = plot.building_info.get("upgrades", [])
	return upgrades[plot.level - 1] if plot.level - 1 < upgrades.size() else {}


# Returns why this plot cannot be upgraded now, or "" if it can.
func get_upgrade_problem(plot: BuildingPlot) -> String:
	if plot == null or plot.building == null or get_max_level(plot) == 1:
		return "This building cannot be upgraded"
	if plot.level >= get_max_level(plot):
		return "Fully upgraded (level %d)" % plot.level
	if plot.is_damaged:
		return "Repair it before upgrading"
	if not _resources.can_afford(get_upgrade_cost(plot)):
		return "Not enough resources to upgrade (needs %s)" % _resources.describe_cost(get_upgrade_cost(plot))
	return ""


# Raises the building on this plot by one level. Returns false, and prints why,
# if that is not possible.
func upgrade(plot: BuildingPlot) -> bool:
	var problem := get_upgrade_problem(plot)
	if problem != "":
		print(problem)
		return false
	_resources.spend(get_upgrade_cost(plot))
	plot.level += 1
	_resources.refresh_storage()
	_update_level_sign(plot)
	var size := Vector3.ONE * (1.0 + UPGRADE_GROWTH * (plot.level - 1))
	var tween := create_tween()
	tween.tween_property(plot.building, "scale", size, UPGRADE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The bigger model covers more ground, so paths are worked out again.
	tween.finished.connect(get_node("../PathGrid").refresh)
	building_upgraded.emit(plot)
	print("Upgraded the %s on plot %d to level %d" % [plot.building_info.name, plot.plot_id, plot.level])
	return true


func _stop_placing() -> void:
	_is_placing = false
	_set_hovered_plot(null)
	_preview.queue_free()
	_preview = null
	_map.set_outlines_visible(false)
	_label.visible = false


# Checks the number keys. Returns true if one of them chose a building.
func _choose_from_keys(event: InputEvent) -> bool:
	for i in BUILDINGS.size():
		# Only buildings with a number key in the Input Map can be chosen this way.
		if InputMap.has_action("choose_building_%d" % (i + 1)) and event.is_action_pressed("choose_building_%d" % (i + 1)):
			choose_building(i)
			return true
	return false


func _place_building(plot: BuildingPlot) -> void:
	var chosen := get_chosen_building()
	var building: Node3D = chosen.scene.instantiate()
	add_child(building)
	building.position = _ground_position(plot)
	building.rotation.y = plot.rotation.y
	plot.state = BuildingPlot.State.OCCUPIED
	plot.building = building
	plot.building_info = chosen
	if chosen.has("upgrades"):
		_add_level_sign(plot)
	# Workers and civilians now walk around the new building.
	get_node("../PathGrid").refresh()
	_resources.refresh_storage()
	_population.notify_housing_changed()
	building_placed.emit(plot)
	print("Built a %s on plot %d" % [chosen.name, plot.plot_id])


# A text sign floating above the building. It always faces the camera and stays
# the same size on screen at every zoom, so the level is easy to read.
func _add_level_sign(plot: BuildingPlot) -> void:
	var top := 0.0
	for mesh: GeometryInstance3D in plot.building.find_children("*", "GeometryInstance3D", true, false):
		top = maxf(top, (mesh.global_transform * mesh.get_aabb()).end.y - plot.building.position.y)
	var sign := Label3D.new()
	sign.name = LEVEL_SIGN_NAME
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.fixed_size = true
	sign.pixel_size = 0.0007
	sign.font_size = 40
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.85, 0.3)
	sign.no_depth_test = true    # Never hidden behind the roof or trees.
	sign.position = Vector3(0.0, top + LEVEL_SIGN_HEIGHT, 0.0)
	plot.building.add_child(sign)
	_update_level_sign(plot)


func _update_level_sign(plot: BuildingPlot) -> void:
	var sign: Label3D = plot.building.get_node_or_null(LEVEL_SIGN_NAME)
	if sign != null:
		sign.text = "Lv %d" % plot.level


# Remembers the plot under the pointer and updates the preview to match.
func _set_hovered_plot(plot: BuildingPlot) -> void:
	if plot == _hovered_plot:
		return
	if _hovered_plot != null:
		_hovered_plot.preview = BuildingPlot.Preview.NONE
	_hovered_plot = plot
	_refresh_preview()


# Updates the outline colour, the see-through House and the label to match the
# plot under the pointer and the resources available.
func _refresh_preview() -> void:
	if not _is_placing:
		return
	var chosen := get_chosen_building()
	var problem := get_placement_problem(_chosen_index)
	var can_pay := _resources.can_afford(chosen.cost) and problem == ""
	var status := "Point at a square, or use the arrows"
	if problem != "":
		status = problem
	elif not can_pay:
		status = "Not enough resources"
	if _hovered_plot != null:
		var allowed := can_pay and _hovered_plot.is_buildable()
		_hovered_plot.preview = BuildingPlot.Preview.VALID if allowed else BuildingPlot.Preview.INVALID
		_preview_material.albedo_color = PREVIEW_VALID_COLOUR if allowed else PREVIEW_INVALID_COLOUR
		_preview.position = _ground_position(_hovered_plot)
		_preview.rotation.y = _hovered_plot.rotation.y
		if not _hovered_plot.is_buildable():
			status = "Cannot build here: this plot is not empty"
		elif can_pay:
			status = "Click to build here, or press Action"
	_preview.visible = _hovered_plot != null
	_label.text = "%s. Cost: %s\n%s. Back or Esc to cancel." % [chosen.name, _resources.describe_cost(chosen.cost), status]


# Lists the choices, with the current one in brackets.
func _building_menu_text() -> String:
	var parts: Array[String] = []
	var landmarks: Array[String] = []
	for i in BUILDINGS.size():
		if not is_available(i):
			continue
		# The number shown is the key that chooses it: 1 to 9, then 0. Buildings
		# past the tenth have no key, and are chosen from the list (Space).
		var entry: String = BUILDINGS[i].name if i > 9 else "%d %s" % [(i + 1) % 10, BUILDINGS[i].name]
		entry = "[%s]" % entry if i == _chosen_index else entry
		if BUILDINGS[i].has("landmark"):
			landmarks.append(entry)
		else:
			parts.append(entry)
	return "   ".join(parts) + "\nLandmarks: " + "   ".join(landmarks)


# A copy of the chosen building that is see-through and casts no shadow.
func _create_preview() -> Node3D:
	var preview: Node3D = get_chosen_building().scene.instantiate()
	_apply_preview_look(preview)
	return preview


func _apply_preview_look(node: Node) -> void:
	if node is GeometryInstance3D:
		node.material_override = _preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_preview_look(child)


func _ground_position(plot: BuildingPlot) -> Vector3:
	return Vector3(plot.position.x, _terrain.LAND_HEIGHT, plot.position.z)


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


# Each building is saved as its plot number, its name and its level.
func get_save_data() -> Dictionary:
	var buildings := []
	for plot in _map.get_plots():
		if plot.building != null:
			buildings.append({ "plot": plot.plot_id, "name": plot.building_info.name, "level": plot.level })
	return { "buildings": buildings, "unlocked": _unlocked.keys() }


# Puts every saved building back, free of charge, at its saved level.
func load_save_data(data: Dictionary) -> void:
	_unlocked.clear()
	for building_name in data.get("unlocked", []):
		_unlocked[str(building_name)] = true
	var chosen_before := _chosen_index
	for entry: Dictionary in data.get("buildings", []):
		var plot := _map.get_plot(int(entry.get("plot", 0)))
		var index := _index_of_building(str(entry.get("name", "")))
		if plot == null or index < 0 or not plot.is_buildable():
			continue   # The file names a plot or building this game does not have.
		_chosen_index = index
		_place_building(plot)
		plot.level = clampi(int(entry.get("level", 1)), 1, get_max_level(plot))
		plot.building.scale = Vector3.ONE * (1.0 + UPGRADE_GROWTH * (plot.level - 1))
		_update_level_sign(plot)
	_chosen_index = chosen_before
	get_node("../PathGrid").refresh()
	_resources.refresh_storage()


func _index_of_building(building_name: String) -> int:
	for i in BUILDINGS.size():
		if BUILDINGS[i].name == building_name:
			return i
	return -1
