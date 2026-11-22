# controller_menu.gd
# Lets the whole game be played with the ESP32 controller's nine inputs: four
# arrows, Select, Action, Build, Menu, and the encoder (turn and push).
#
# Each input is a named action in Project Settings > Input Map. For now each has
# a keyboard key, so the menus can be tested without the controller. Later the
# ESP32 link will fire the same actions, and nothing here needs to change.
#
#   Input           Key         What it does
#   Arrows          Arrow keys  Move the view. In a menu: move up and down the
#                               list. While building: move to the next square.
#   Select          Tab         Jump to the next building and select it.
#   Action          Space       Open the selected building's menu, confirm a
#                               menu item, or accept an event. While building:
#                               open the list of buildings for the chosen square.
#   Build           B           Start or stop placing a building.
#   Menu            M           Open or close the pause menu.
#   Encoder turn    - and =     Zoom. In a menu: move through the list. While
#                               building: change which building is placed.
#   Encoder push    Backspace   Back: close a menu, cancel building, clear the
#                               selection, or decline an event.
#
# This node comes after the other managers in Main.tscn, so it receives input
# before them. It runs while the game is paused, so the pause menu works.
class_name ControllerMenu
extends Node

signal menu_changed

enum Mode { NONE, BUILDING, PAUSE, BUILD_PICK, START, CHOICE }

const ROTATE_STEP := PI / 4.0    # One "Rotate view" press turns the view 45 degrees.
const MESSAGE_SECONDS := 3.0     # How long "Done" or a reason stays in the menu.
const BOARD_SIDE_GAP := 60.0     # Pixels between the building list and the screen edge.

var _mode := Mode.NONE
var _index := 0                  # Which menu item is highlighted.
var _message := ""
var _message_time := 0.0
var _choice_title := ""          # For Mode.CHOICE: the question on the board.
var _choice_items := Callable()  # For Mode.CHOICE: a function that returns the answers.
var _panel: WoodenBoard
var _title_label: Label
var _item_box: VBoxContainer
var _message_label: Label
var _hint_label: Label
var _highlight_box := StyleBoxFlat.new()

# The start board is shown once each time the game is launched, not after
# "Restart the game". A static variable keeps its value when the scene reloads.
static var _has_started := false

@onready var _map: MapManager = get_node("../MapManager")
@onready var _builder: BuildingManager = get_node("../BuildingManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _civilians: CivilianManager = get_node("../CivilianManager")
@onready var _research: ResearchManager = get_node("../ResearchManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _events: EventManager = get_node("../EventManager")
@onready var _state: GameStateManager = get_node("../GameStateManager")
@onready var _saves: SaveManager = get_node("../SaveManager")
@onready var _camera: Camera3D = get_node("../Camera3D")
@onready var _ui: CanvasLayer = get_node("../UI")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_labels()
	_map.selection_changed.connect(_on_selection_changed)
	# Deferred, so the scene has finished loading before the check below.
	_show_start_if_playing.call_deferred()


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message = ""
	# The arrows belong to the menu or the build cursor while either is open.
	_camera.pad_locked = _mode != Mode.NONE or _builder.is_placing()
	_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if _game_has_ended():
		_end_screen_input(event)
	elif _mode != Mode.NONE:
		_menu_input(event)
	elif _builder.is_placing():
		_placing_input(event)
	else:
		_free_input(event)


func get_mode() -> Mode:
	return _mode


func is_open() -> bool:
	return _mode != Mode.NONE


# The highlighted item's position in the list, starting at 0.
func get_highlight() -> int:
	return _index


# The text of every item in the open menu, for tests and debugging.
func get_item_texts() -> Array[String]:
	var texts: Array[String] = []
	for item in _get_items():
		texts.append(item.text)
	return texts


# Opens the menu of actions for the selected building. Returns false if no
# building is selected.
func open_building_menu() -> bool:
	var plot := _map.get_selected_plot()
	if plot == null or plot.building == null:
		return false
	_open(Mode.BUILDING)
	return true


# The message under the menu items: "Done", or why an item was refused.
func get_message() -> String:
	return _message


# Opens the main menu. The game waits behind it until "New Game" (or Continue) is chosen.
func open_start_menu() -> void:
	_open(Mode.START)
	get_tree().paused = true


# Opens the list of buildings for the square under the build cursor. Returns
# false if there is no empty square under the cursor.
func open_build_menu() -> bool:
	var plot := _builder.get_cursor_plot()
	if not _builder.is_placing() or plot == null or not plot.is_buildable():
		return false
	_open(Mode.BUILD_PICK)
	# Put the highlight on the building that is already chosen.
	var items := _get_items()
	for i in items.size():
		if items[i].get("building", -1) == _builder.get_chosen_index():
			_index = i
	return true


# Opens a board that asks the player a question, for story events. The game
# waits until one answer is chosen; Back cannot close it. get_items is a
# function that returns the answers, in the same form as every other menu item,
# so each answer can say why it is not possible right now.
func open_choice(title: String, get_items: Callable) -> void:
	_choice_title = title
	_choice_items = get_items
	_open(Mode.CHOICE)
	get_tree().paused = true


# Opens the pause menu. The game stops until it is closed.
func open_pause_menu() -> void:
	_open(Mode.PAUSE)
	get_tree().paused = true


func close_menu() -> void:
	if _mode == Mode.PAUSE or _mode == Mode.START or _mode == Mode.CHOICE:
		get_tree().paused = false
	if _mode == Mode.START:
		_has_started = true
	_mode = Mode.NONE
	_message = ""
	menu_changed.emit()


# Moves the highlight up (-1) or down (+1), wrapping round at the ends.
func move_highlight(step: int) -> void:
	var items := _get_items()
	if items.size() > 0:
		_index = posmod(_index + step, items.size())
	# In the building list, the see-through preview shows the highlighted building.
	if _mode == Mode.BUILD_PICK and _index < items.size() and items[_index].has("building"):
		_builder.choose_building(items[_index].building)


# Does the highlighted item.
func confirm() -> void:
	var items := _get_items()
	if _index >= items.size():
		return
	var item: Dictionary = items[_index]
	var worked: bool = item.action.call()
	if _mode == Mode.NONE:
		return   # The item closed the menu.
	if item.get("closes", false) and worked:
		close_menu()
		return
	_message = "Done" if worked else item.get("problem", "Not possible right now")
	_message_time = MESSAGE_SECONDS


# Selects the next building after the selected one, in plot order, and centres
# the view on it. Returns false if there are no buildings.
func select_next_building() -> bool:
	var built: Array[BuildingPlot] = []
	for plot in _map.get_plots():
		if plot.building != null:
			built.append(plot)
	if built.is_empty():
		return false
	var next := built[(built.find(_map.get_selected_plot()) + 1) % built.size()]
	_map.select_plot(next)
	_camera.glide_to(next.position)
	return true


# Moves the build cursor one square in a direction on the screen (for example
# Vector2.UP). If there is no square right next door, for example at the lake,
# it jumps to the nearest one further on.
func move_build_cursor(screen_direction: Vector2) -> void:
	if not _builder.is_placing():
		return
	var from := _builder.get_cursor_plot()
	var target: BuildingPlot = null
	if from == null or _builder.is_following_mouse():
		target = _nearest_empty_plot(_camera.get_focus())   # The first press picks a start.
	elif screen_direction == Vector2.ZERO:
		return
	else:
		target = _neighbour(from, screen_direction)
	if target != null:
		_builder.set_cursor_plot(target)
		_camera.glide_to(target.position)


# ---------------------------------------------------------------- Input

func _free_input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_menu"):
		open_pause_menu()
	elif event.is_action_pressed("pad_select"):
		select_next_building()
	elif event.is_action_pressed("pad_action"):
		# With a building selected, Action opens its menu. Otherwise it answers
		# an event, or selects the first building.
		if not open_building_menu():
			if not _events.respond():
				select_next_building()
	elif event.is_action_pressed("pad_back"):
		if _map.get_selected_plot() != null:
			_map.select_plot(null)
		else:
			_events.decline()
	elif event.is_action_pressed("pad_turn_left"):
		_camera.zoom_steps(-1)
	elif event.is_action_pressed("pad_turn_right"):
		_camera.zoom_steps(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _placing_input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_up", true):
		move_build_cursor(Vector2.UP)
	elif event.is_action_pressed("pad_down", true):
		move_build_cursor(Vector2.DOWN)
	elif event.is_action_pressed("pad_left", true):
		move_build_cursor(Vector2.LEFT)
	elif event.is_action_pressed("pad_right", true):
		move_build_cursor(Vector2.RIGHT)
	elif event.is_action_pressed("pad_action"):
		# With a square chosen, Action opens the list of buildings for it.
		if _builder.get_cursor_plot() == null or _builder.is_following_mouse():
			move_build_cursor(Vector2.ZERO)
		else:
			open_build_menu()
	elif event.is_action_pressed("pad_back"):
		_builder.cancel_placement()
	elif event.is_action_pressed("pad_turn_left"):
		_cycle_building(-1)
	elif event.is_action_pressed("pad_turn_right"):
		_cycle_building(1)
	elif event.is_action_pressed("pad_menu"):
		_builder.cancel_placement()
		open_pause_menu()
	else:
		return
	get_viewport().set_input_as_handled()


func _menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_up", true) or event.is_action_pressed("pad_turn_left"):
		move_highlight(-1)
	elif event.is_action_pressed("pad_down", true) or event.is_action_pressed("pad_turn_right"):
		move_highlight(1)
	elif event.is_action_pressed("pad_action"):
		confirm()
	elif event.is_action_pressed("pad_back") or event.is_action_pressed("pad_menu") or event.is_action_pressed("ui_cancel"):
		# The start board and a story choice only close when an item is chosen.
		if _mode != Mode.START and _mode != Mode.CHOICE:
			close_menu()
	elif not event is InputEventKey:
		return   # The mouse and trackpad still work behind the menu.
	# Every key is used up, so nothing behind the menu reacts to it.
	get_viewport().set_input_as_handled()


# On the win or lose screen: Action restarts, Back keeps playing after a win.
func _end_screen_input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_action"):
		get_viewport().set_input_as_handled()
		_state.restart()
	elif event.is_action_pressed("pad_back"):
		get_viewport().set_input_as_handled()
		_state.keep_playing()


func _game_has_ended() -> bool:
	return _state.get_state() == GameStateManager.State.WON or _state.get_state() == GameStateManager.State.LOST


func _cycle_building(step: int) -> void:
	var count := BuildingManager.BUILDINGS.size()
	var index := _builder.get_chosen_index()
	# Step past any building that is still locked.
	for i in count:
		index = posmod(index + step, count)
		if _builder.is_available(index):
			break
	_builder.choose_building(index)


# ---------------------------------------------------------------- Menus

func _open(mode: Mode) -> void:
	_mode = mode
	_index = 0
	_message = ""
	menu_changed.emit()


# The selected building went away or changed, so its menu no longer applies.
func _on_selection_changed(_plot: BuildingPlot) -> void:
	if _mode == Mode.BUILDING:
		close_menu()


# Every item in the open menu. Each has: text, action (a function that returns
# true if it worked), and optionally problem (why it cannot be done now) and
# closes (true if the menu closes after it works).
func _get_items() -> Array[Dictionary]:
	match _mode:
		Mode.BUILDING: return _building_items()
		Mode.PAUSE: return _pause_items()
		Mode.BUILD_PICK: return _build_items()
		Mode.START: return _start_items()
		Mode.CHOICE:
			var items: Array[Dictionary] = []
			items.assign(_choice_items.call())
			return items
	return []


func _building_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var plot := _map.get_selected_plot()
	if plot == null or plot.building == null:
		return items
	var kind: String = plot.building_info.name
	var slots := _workers.get_slots(plot)
	if slots > 0:
		var here := _workers.get_workers_at(plot).size()
		items.append({
			"text": "Add a worker (%d of %d here, %d idle)" % [here, slots, _workers.get_idle_count()],
			"action": func() -> bool: return _workers.assign_worker(plot),
			"problem": "No free place here" if here >= slots else "No idle workers" if _workers.get_idle_count() == 0 else "Not possible right now",
		})
		items.append({
			"text": "Remove a worker",
			"action": func() -> bool: return _workers.remove_worker(plot),
			"problem": "No workers here",
		})
	if kind == "House":
		items.append({
			"text": "Train a civilian into a worker (%s)" % _resources.describe_cost(CivilianManager.TRAIN_COST),
			"action": func() -> bool: return _civilians.train_worker(plot),
			"problem": _civilians.get_training_problem(plot),
		})
	if _builder.get_max_level(plot) > 1:
		var cost := _builder.get_upgrade_cost(plot)
		items.append({
			"text": "Upgrade to level %d (%s)" % [plot.level + 1, _resources.describe_cost(cost)] if not cost.is_empty() else "Upgrade",
			"action": func() -> bool: return _builder.upgrade(plot),
			"problem": _builder.get_upgrade_problem(plot),
		})
	if kind == "Research Lab":
		var project: Dictionary = ResearchManager.PROJECTS.vaccine
		items.append({
			"text": "Research a vaccine (%s, %d s)" % [_resources.describe_cost(project.cost), project.seconds],
			"action": func() -> bool: return _research.start("vaccine"),
			"problem": "The vaccine is already researched" if _research.is_finished("vaccine") else "Already researching" if _research.get_current() == "vaccine" else "Not enough resources, or the Lab is damaged",
		})
		for id: String in ResearchManager.UPGRADES:
			items.append({
				"text": "Research %s" % _research.describe(id),
				"action": func() -> bool: return _research.start(id),
				"problem": _research.get_problem(id),
			})
	items.append({ "text": "Close", "action": func() -> bool: return true, "closes": true })
	return items


func _pause_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{ "text": "Resume", "action": func() -> bool: return true, "closes": true },
	]
	items.append({
		"text": "Start the next event now: %s (for testing)" % EventManager.NAMES[_events.get_next_type()],
		"action": _start_next_event,
		"problem": "Another event is still happening",
		"closes": true,
	})
	var puzzle := get_node_or_null("../UI/GoldPuzzle") as GoldPuzzle
	if puzzle != null:
		items.append({
			"text": "Play the gold puzzle" if puzzle.is_ready() else "Gold puzzle (ready in %d s)" % ceili(puzzle.get_cooldown()),
			"action": func() -> bool:
				close_menu()
				return puzzle.open(),
			"problem": "The next puzzle is not ready yet",
			"closes": true,
		})
	items.append({ "text": "Rotate view left", "action": func() -> bool: _camera.rotate_view(-ROTATE_STEP); return true })
	items.append({ "text": "Rotate view right", "action": func() -> bool: _camera.rotate_view(ROTATE_STEP); return true })
	items.append({ "text": "Save the game", "action": _saves.save_game, "problem": _save_problem() })
	if _saves.has_save():
		items.append({
			"text": "Load the saved game (%s)" % _saves.get_save_time(),
			"action": _saves.load_game,
			"problem": "The saved game could not be loaded",
			"closes": true,
		})
	items.append({ "text": "Restart the game", "action": func() -> bool: close_menu(); _state.restart(); return true })
	items.append({ "text": "Quit the game", "action": func() -> bool: get_tree().quit(); return true })
	return items


# One line for each building, with its cost. Choosing one builds it on the
# square under the cursor.
func _build_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for i in BuildingManager.BUILDINGS.size():
		# Locked buildings are left out. Each line remembers which building it is
		# ("building"), because its position in the list is then not its number.
		if not _builder.is_available(i):
			continue
		var building: Dictionary = BuildingManager.BUILDINGS[i]
		var problem := _builder.get_placement_problem(i)
		var days := "" if not building.has("build_days") else ", %d days to build" % int(building.build_days)
		items.append({
			"building": i,
			"text": "%s  -  %s%s" % [building.name, _resources.describe_cost(building.cost), days],
			"action": func() -> bool:
				_builder.choose_building(i)
				_builder.confirm_placement()
				return not _builder.is_placing(),
			"problem": problem if problem != "" else "Not enough resources for a %s" % building.name,
			"closes": true,
		})
	items.append({ "text": "Back to choosing a square", "action": func() -> bool: return true, "closes": true })
	return items


func _start_items() -> Array[Dictionary]:
	# The main menu (v2 storybook design): Continue, New Game, How to Play,
	# Settings, Credits and Quit. The windows open over the menu.
	var screens := get_node_or_null("../UI/Screens") as Screens
	var items: Array[Dictionary] = []
	if _saves.has_save():
		items.append({
			"text": "Continue (%s)" % _saves.get_save_time(),
			"action": _saves.load_game,
			"problem": "The saved game could not be loaded",
			"closes": true,
		})
	items.append({ "text": "New Game", "action": func() -> bool: return true, "closes": true })
	if screens != null:
		for entry in [["How to Play", "help"], ["Settings", "settings"], ["Credits", "credits"]]:
			var which: String = entry[1]
			items.append({ "text": entry[0], "action": func() -> bool:
				screens.open(which)
				return true })
	items.append({ "text": "Quit", "action": func() -> bool: get_tree().quit(); return true })
	return items


# Why the game cannot be saved right now, for the message under the menu.
func _save_problem() -> String:
	var problem := _saves.get_save_problem()
	return problem if problem != "" else "The save file could not be written"


# Shows the start board when the game itself is running. The automated tests
# load the scene in a different way, and skip it.
func _show_start_if_playing() -> void:
	if not _has_started and get_tree().current_scene == get_parent():
		open_start_menu()


# Events come one at a time, so this is refused while one is still happening.
func _start_next_event() -> bool:
	if not _events.get_active().is_empty():
		return false
	_events.trigger_next()
	return true


# ---------------------------------------------------------------- Build cursor

# Turns a direction on the screen into one of the four grid directions on the
# ground, using which way the camera faces. Returns a direction in x and z.
func _ground_direction(screen_direction: Vector2) -> Vector2:
	var yaw: float = _camera.get_yaw()
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var wanted := right * screen_direction.x - forward * screen_direction.y
	# The squares stand on a grid (v2 tidy village), so snap to the nearest grid
	# direction. Turn it a little first, so a view at exactly 45 degrees (the
	# starting view) still gives four different directions.
	wanted = wanted.rotated(0.01)
	if absf(wanted.x) > absf(wanted.y):
		return Vector2(signf(wanted.x), 0.0)
	return Vector2(0.0, signf(wanted.y))


# The closest plot in that direction, strongly preferring one straight ahead.
# v2: the squares are scattered, so an arrow goes to the nearest square within a
# 90 degree wedge in that direction on screen. Only if there is none does it look
# wider (the old rule below), so the cursor never gets stuck.
func _neighbour(from: BuildingPlot, screen_direction: Vector2) -> BuildingPlot:
	var direction := _ground_direction(screen_direction)
	var nearest: BuildingPlot = null
	var nearest_distance := INF
	for plot in _map.get_plots():
		var offset := Vector2(plot.position.x - from.position.x, plot.position.z - from.position.z)
		if plot == from or offset.length() < 1.0:
			continue
		if offset.normalized().dot(direction) >= cos(PI / 4.0) and offset.length() < nearest_distance:
			nearest_distance = offset.length()
			nearest = plot
	if nearest != null:
		return nearest
	var best: BuildingPlot = null
	var best_score := INF
	for plot in _map.get_plots():
		var offset := Vector2(plot.position.x - from.position.x, plot.position.z - from.position.z)
		var along := offset.dot(direction)
		if along < 1.0:
			continue
		var across := absf(offset.dot(Vector2(-direction.y, direction.x)))
		var score := along + across * 3.0
		if score < best_score:
			best_score = score
			best = plot
	return best


func _nearest_empty_plot(point: Vector3) -> BuildingPlot:
	var best: BuildingPlot = null
	var best_distance := INF
	for plot in _map.get_plots():
		var distance := Vector2(plot.position.x - point.x, plot.position.z - point.z).length()
		if plot.is_buildable() and distance < best_distance:
			best_distance = distance
			best = plot
	return best


# ---------------------------------------------------------------- Screen

func _create_labels() -> void:
	# The menu: a wooden board in the middle of the screen, holding a title,
	# one line of text for each item, and a message.
	_panel = WoodenBoard.new()
	_panel.name = "MenuPanel"
	_panel.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_title_label = _board_label(40, Color(1.0, 0.86, 0.45))
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(420, 10)   # Also the narrowest the board gets.
	column.add_child(gap)
	_item_box = VBoxContainer.new()
	_item_box.name = "Items"
	_item_box.add_theme_constant_override("separation", 4)
	column.add_child(_item_box)
	_message_label = _board_label(24, Color(0.62, 0.2, 0.1))
	_message_label.name = "MessageLabel"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_message_label)
	_ui.add_child(_panel)

	# The highlighted item sits on a lighter strip with a gold edge.
	_highlight_box.bg_color = Color(0.85, 0.66, 0.35, 0.35)
	_highlight_box.border_color = Color(0.6, 0.38, 0.15)
	_highlight_box.set_border_width_all(2)
	_highlight_box.set_corner_radius_all(6)
	_highlight_box.content_margin_left = 14.0
	_highlight_box.content_margin_right = 14.0

	# One line along the bottom saying what each input does right now.
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -34.0
	_hint_label.offset_bottom = -4.0
	_hint_label.offset_right = -24.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 8)
	_ui.add_child(_hint_label)


# Text for the board: cream letters with a dark edge, like paint on wood.
func _board_label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	# Light text (the title on the wooden ribbon) gets a dark edge; ink on the
	# parchment needs none.
	if colour.v > 0.7:
		label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03))
		label.add_theme_constant_override("outline_size", 8)
	return label


func _refresh_labels() -> void:
	_panel.visible = _mode != Mode.NONE
	if _mode != Mode.NONE:
		var items := _get_items()
		_index = clampi(_index, 0, maxi(items.size() - 1, 0))
		_title_label.text = _menu_title()
		_message_label.text = _message
		# Reuse the item labels, adding or hiding some as the list changes length.
		while _item_box.get_child_count() < items.size():
			_item_box.add_child(_board_label(30, WoodenBoard.INK))
		for i in _item_box.get_child_count():
			var label: Label = _item_box.get_child(i)
			label.visible = i < items.size()
			if not label.visible:
				continue
			label.text = items[i].text
			var plain := StyleBoxEmpty.new()
			plain.content_margin_left = 14.0
			plain.content_margin_right = 14.0
			label.add_theme_stylebox_override("normal", _highlight_box if i == _index else plain)
			label.add_theme_color_override("font_color", Color(0.55, 0.25, 0.05) if i == _index else WoodenBoard.INK)
		# Shrink to fit the list, then centre the board. The building list goes
		# to the right instead, so the square being built on stays in view.
		_panel.reset_size()
		var screen := _panel.get_viewport_rect().size
		_panel.position = ((screen - _panel.size) * 0.5).round()
		if _mode == Mode.BUILD_PICK:
			_panel.position.x = screen.x - _panel.size.x - BOARD_SIDE_GAP
	_hint_label.visible = not _game_has_ended()
	_hint_label.text = _hint_text()


func _menu_title() -> String:
	match _mode:
		Mode.PAUSE: return "Game paused"
		Mode.START: return "Island Colony"
		Mode.CHOICE: return _choice_title
		Mode.BUILD_PICK: return "Build on plot %d" % (_builder.get_cursor_plot().plot_id if _builder.get_cursor_plot() != null else 0)
	var plot := _map.get_selected_plot()
	return "" if plot == null else "%s on plot %d" % [plot.building_info.get("name", "Building"), plot.plot_id]


func _hint_text() -> String:
	if get_node("../UI/StoryBox").is_open():
		return "Space or Enter: continue"
	if _mode == Mode.START or _mode == Mode.CHOICE:
		return "Up/Down: choose     Space: do it"   # These two cannot be closed with Back.
	if _mode != Mode.NONE:
		return "Up/Down: choose     Space: do it     Backspace: close"
	if _builder.is_placing():
		return "Arrows: move square     Space: choose a building     Backspace: cancel"
	var action := "Space: building menu     Backspace: deselect" if _map.get_selected_plot() != null else "Space: answer event     Backspace: decline" if not _events.get_active().is_empty() else "Space: select a building"
	return "Arrows: move     - and =: zoom     Tab: next building     %s     B: build     M: menu" % action
