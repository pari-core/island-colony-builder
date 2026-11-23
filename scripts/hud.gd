# hud.gd
# The v2 interface, in the style of the team's picture: dark rounded panels in
# the four corners of the screen.
#   Top left:     food, wood, stone and gold, each with its icon, the amount and
#                 how much it changes per minute, then people / homes.
#   Top right:    the day, a sun or moon and the time of day, and buttons to
#                 pause, play and fast-forward.
#   Bottom left:  the Build Menu: a card for each building with its picture,
#                 name and cost. Clicking one starts placing it.
#   Bottom right: a minimap of the island seen from above, with a frame showing
#                 where the camera is. Clicking it moves the view there.
# Everything is made in code; the icons are our own drawings (assets/ui/icons)
# and the building pictures are rendered from the game's models (assets/ui/thumbs).
# The old text bar stays in the scene, hidden, because other code and the tests
# still read it.
class_name Hud
extends Control

const PANEL_COLOUR := Color(0.1, 0.14, 0.2, 0.86)
const CARD_COLOUR := Color(0.2, 0.25, 0.32, 0.95)
const CHOSEN_COLOUR := Color(1.0, 0.8, 0.3)
const GOOD := Color(0.65, 0.95, 0.6)
const BAD := Color(1.0, 0.5, 0.42)
const ICONS := "res://assets/ui/icons/%s.png"
const THUMBS := "res://assets/ui/thumbs/%s.png"
const FAST_SPEED := 3.0          # How much faster the fast-forward button runs the game.
const MINIMAP_SIZE := 230
const MINIMAP_SPAN := 560.0      # Metres of island the minimap shows across.
const MINIMAP_REFRESH := 1.5     # Seconds between minimap redraws (it is costly to draw).
const RESOURCES := [
	[ResourceManager.Type.FOOD, "food"],
	[ResourceManager.Type.WOOD, "wood"],
	[ResourceManager.Type.STONE, "stone"],
	[ResourceManager.Type.GOLD, "gold"],
]

var _amounts := {}               # Resource type -> its amount label.
var _rates := {}                 # Resource type -> its "+N/min" label.
var _people_label: Label
var _day_label: Label
var _clock_label: Label
var _sky_icon: TextureRect
var _speed_buttons := {}         # "pause", "play", "fast" -> Button.
var _cards := {}                 # Building index -> card Button.
var _minimap_view: SubViewport
var _minimap_camera: Camera3D
var _minimap_frame: Panel
var _minimap_wait := 0.0

@onready var _resources: ResourceManager = get_node("../../ResourceManager")
@onready var _population: PopulationManager = get_node("../../PopulationManager")
@onready var _workers: WorkerManager = get_node("../../WorkerManager")
@onready var _map: MapManager = get_node("../../MapManager")
@onready var _builder: BuildingManager = get_node("../../BuildingManager")
@onready var _time: TimeManager = get_node("../../TimeManager")
@onready var _day_night: DayNight = get_node("../../DayNight")
@onready var _camera: Node = get_node("../../Camera3D")
@onready var _menu: ControllerMenu = get_node("../../ControllerMenu")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # The time buttons must work while paused.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resources()
	_build_clock()
	_build_toolbar()
	_build_minimap()
	_move_old_labels()


func _process(delta: float) -> void:
	_fit_notes()
	_update_resources()
	_update_clock()
	_update_toolbar()
	_update_puzzle_button()
	_minimap_wait -= delta
	if _minimap_wait <= 0.0:
		_minimap_wait = MINIMAP_REFRESH
		_minimap_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_minimap_frame()


# ---------------------------------------------------------------- Resources

func _build_resources() -> void:
	var panel := _panel()
	panel.position = Vector2(20, 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	for entry in RESOURCES:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.add_child(_icon(entry[1], 44))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", -4)
		var amount := _label("0", 28)
		var rate := _label("+0/min", 17, GOOD)
		column.add_child(amount)
		column.add_child(rate)
		item.add_child(column)
		row.add_child(item)
		_amounts[entry[0]] = amount
		_rates[entry[0]] = rate
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.35)
	line.custom_minimum_size = Vector2(2, 44)
	row.add_child(line)
	var people := HBoxContainer.new()
	people.add_theme_constant_override("separation", 8)
	people.add_child(_icon("people", 40))
	_people_label = _label("0 / 0", 28)
	people.add_child(_people_label)
	row.add_child(people)


func _update_resources() -> void:
	var per_minute := {}
	for type in ResourceManager.Type.values():
		per_minute[type] = 0.0
	for plot in _map.get_plots():
		if plot.building != null and plot.building_info.has("produces"):
			per_minute[plot.building_info.produces] += _workers.get_output(plot) * 60.0 / WorkerManager.PRODUCTION_SECONDS
	# Food is also eaten, so its rate is what is left over.
	per_minute[ResourceManager.Type.FOOD] -= _population.get_food_needed() * 60.0 / PopulationManager.UPKEEP_SECONDS
	for type in _amounts:
		var amount := _resources.get_amount(type)
		var full := amount >= _resources.get_capacity()
		(_amounts[type] as Label).text = str(amount)
		(_amounts[type] as Label).add_theme_color_override("font_color", Color(1.0, 0.78, 0.4) if full else Color.WHITE)
		var rate := roundi(per_minute[type])
		(_rates[type] as Label).text = ("+%d/min" if rate >= 0 else "%d/min") % rate
		(_rates[type] as Label).add_theme_color_override("font_color", GOOD if rate >= 0 else BAD)
	_people_label.text = "%d / %d" % [_population.get_population(), _population.get_housing_capacity()]


# ---------------------------------------------------------------- Clock

func _build_clock() -> void:
	var panel := _panel()
	_pin(panel, Control.PRESET_TOP_RIGHT, Vector2(-20, 16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_day_label = _label("Day 1", 28)
	top.add_child(_day_label)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.35)
	line.custom_minimum_size = Vector2(2, 36)
	top.add_child(line)
	_sky_icon = _icon("sun", 38)
	top.add_child(_sky_icon)
	_clock_label = _label("10:00 AM", 28)
	top.add_child(_clock_label)
	column.add_child(top)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 6)
	for name in ["pause", "play", "fast"]:
		var button := Button.new()
		button.icon = load(ICONS % name)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(52, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _box(Color(0.22, 0.27, 0.35, 0.9), 8))
		button.add_theme_stylebox_override("hover", _box(Color(0.3, 0.36, 0.46, 0.95), 8))
		button.add_theme_stylebox_override("pressed", _box(Color(0.35, 0.42, 0.52, 1.0), 8))
		button.pressed.connect(set_speed.bind(name))
		buttons.add_child(button)
		_speed_buttons[name] = button
	column.add_child(buttons)


# "pause" stops the game, "play" runs it normally, "fast" runs it FAST_SPEED times
# faster. Ignored while a menu or story is open, since those pause the game themselves.
func set_speed(speed: String) -> void:
	if _menu.is_open() or get_node("../StoryBox").is_open():
		return
	get_tree().paused = speed == "pause"
	Engine.time_scale = FAST_SPEED if speed == "fast" else 1.0


func get_speed() -> String:
	if get_tree().paused:
		return "pause"
	return "fast" if Engine.time_scale > 1.0 else "play"


func _update_clock() -> void:
	_day_label.text = "Day %d" % _time.get_day()
	_clock_label.text = get_clock_text()
	_sky_icon.texture = load(ICONS % ("moon" if _day_night.is_night() else "sun"))
	for name in _speed_buttons:
		(_speed_buttons[name] as Button).modulate = CHOSEN_COLOUR if name == get_speed() else Color.WHITE


# The time of day as a clock: sunrise is 6:00 AM, sunset 7:00 PM, and the night
# runs on to the next sunrise. To the nearest 10 minutes.
func get_clock_text() -> String:
	if not DayNight.enabled:
		return "12:00 PM"
	var phase := _day_night.get_phase()
	var hours := 6.0 + phase / DayNight.DAY_PART * 13.0 if phase < DayNight.DAY_PART else 19.0 + (phase - DayNight.DAY_PART) / (1.0 - DayNight.DAY_PART) * 11.0
	var minutes := int(round(fposmod(hours, 24.0) * 6.0)) * 10 % (24 * 60)
	var hour := minutes / 60
	return "%d:%02d %s" % [(hour + 11) % 12 + 1, minutes % 60, "AM" if hour < 12 else "PM"]


# ---------------------------------------------------------------- Build menu

func _build_menu() -> void:
	var panel := _panel()
	_pin(panel, Control.PRESET_BOTTOM_LEFT, Vector2(20, -20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	title.add_child(_icon("hammer", 34))
	title.add_child(_label("Build Menu", 26))
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for i in BuildingManager.BUILDINGS.size():
		var building: Dictionary = BuildingManager.BUILDINGS[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(118, 140)
		card.focus_mode = Control.FOCUS_NONE
		card.tooltip_text = "%s: %s" % [building.name, _resources.describe_cost(building.cost)]
		card.add_theme_stylebox_override("normal", _box(CARD_COLOUR, 10))
		card.add_theme_stylebox_override("hover", _box(CARD_COLOUR.lightened(0.15), 10))
		card.add_theme_stylebox_override("pressed", _box(CARD_COLOUR.lightened(0.25), 10))
		var inside := VBoxContainer.new()
		inside.set_anchors_preset(Control.PRESET_FULL_RECT)
		inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inside.add_theme_constant_override("separation", 0)
		var picture := TextureRect.new()
		picture.texture = load(THUMBS % building.name.to_lower().replace(" ", "_")) if ResourceLoader.exists(THUMBS % building.name.to_lower().replace(" ", "_")) else null
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(0, 74)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inside.add_child(picture)
		var name_label := _label(building.name, 14)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inside.add_child(name_label)
		var cost := _label(_short_cost(building.cost), 12, Color(0.85, 0.88, 0.95))
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # Long costs take two lines.
		cost.custom_minimum_size = Vector2(110, 0)
		inside.add_child(cost)
		card.add_child(inside)
		card.pressed.connect(choose_card.bind(i))
		grid.add_child(card)
		_cards[i] = card


# A card was clicked: choose that building and start placing it.
func choose_card(index: int) -> void:
	if not _builder.is_available(index):
		return
	if not _builder.is_placing():
		_builder.start_placement()
	_builder.choose_building(index)


func _update_cards() -> void:
	for index in _cards:
		var card: Button = _cards[index]
		card.visible = _builder.is_available(index)
		var affordable := _resources.can_afford(BuildingManager.BUILDINGS[index].cost)
		var chosen: bool = _builder.is_placing() and _builder.get_chosen_index() == index
		card.modulate = Color.WHITE if affordable else Color(0.6, 0.6, 0.6)
		card.add_theme_stylebox_override("normal", _box(CARD_COLOUR, 10, CHOSEN_COLOUR if chosen else Color(0, 0, 0, 0)))


# "20 Wood, 10 Stone" becomes "20 wood  10 stone", which fits on a card.
func _short_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for type in cost:
		parts.append("%d %s" % [cost[type], ResourceManager.NAMES[type].to_lower()])
	return "  ".join(parts)


# ---------------------------------------------------------------- Minimap

func _build_minimap() -> void:
	var panel := _panel()
	_pin(panel, Control.PRESET_BOTTOM_RIGHT, Vector2(-20, -20))
	var holder := SubViewportContainer.new()
	holder.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(_on_minimap_input)
	panel.add_child(holder)
	_minimap_view = SubViewport.new()
	_minimap_view.size = Vector2i(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	holder.add_child(_minimap_view)
	_minimap_camera = Camera3D.new()
	_minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_minimap_camera.size = MINIMAP_SPAN
	_minimap_camera.far = 1000.0
	_minimap_view.add_child(_minimap_camera)
	_minimap_camera.position = Vector3(0.0, 400.0, 0.0)
	_minimap_camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_minimap_frame = Panel.new()
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.border_color = Color.WHITE
	outline.set_border_width_all(2)
	_minimap_frame.add_theme_stylebox_override("panel", outline)
	_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_minimap_frame)


# The white frame: about the part of the island the camera shows.
func _update_minimap_frame() -> void:
	var focus: Vector3 = _camera.get_focus()
	var metres_shown := clampf(float(_camera.get("_distance")) * 0.9, 30.0, MINIMAP_SPAN)
	var scale := MINIMAP_SIZE / MINIMAP_SPAN
	var size := Vector2.ONE * metres_shown * scale
	var centre := Vector2(focus.x, focus.z) * scale + Vector2.ONE * MINIMAP_SIZE * 0.5
	_minimap_frame.position = centre - size * 0.5
	_minimap_frame.size = size


# Clicking the minimap moves the view to that spot.
func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var metres: Vector2 = (event.position - Vector2.ONE * MINIMAP_SIZE * 0.5) * MINIMAP_SPAN / MINIMAP_SIZE
		_camera.glide_to(Vector3(metres.x, 0.0, metres.y))


# ---------------------------------------------------------------- Toolbar

# v2 storybook design (2026-11-23): round parchment buttons in the bottom-left
# corner open the windows in screens.gd. B (Build) still starts placing at once.
var _toolbar_buttons := {}
func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "Toolbar"
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	_pin(bar, Control.PRESET_BOTTOM_LEFT, Vector2(20, -20))
	for entry in [["Build", "hammer", "build"], ["Help", "book", "help"], ["Settings", "gear", "settings"], ["Puzzle", "gold", "puzzle"], ["News", "bell", "notifications"]]:
		var button := Button.new()
		button.name = entry[0] + "Button"
		button.text = entry[0]
		button.icon = load(ICONS % entry[1])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.expand_icon = true
		button.custom_minimum_size = Vector2(92, 92)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", WoodenBoard.INK)
		button.add_theme_color_override("font_hover_color", WoodenBoard.INK)
		button.add_theme_color_override("font_disabled_color", Color(WoodenBoard.INK, 0.55))
		for state in ["normal", "hover", "pressed", "disabled"]:
			var paper := _box(Color(0.95, 0.89, 0.76, 0.97) if state != "hover" else Color(1.0, 0.95, 0.84), 16, Color(0.45, 0.29, 0.14))
			paper.content_margin_top = 8.0
			paper.content_margin_bottom = 6.0
			button.add_theme_stylebox_override(state, paper)
		var which: String = entry[2]
		button.pressed.connect(func() -> void:
			if which == "puzzle":
				get_node("../EventPuzzles").play_next()
			else:
				get_node("../Screens").open(which))
		bar.add_child(button)
		_toolbar_buttons[which] = button
	_puzzle_button = _toolbar_buttons["puzzle"]
	_puzzle_button.name = "PuzzleButton"


func _update_toolbar() -> void:
	var notes: int = get_node("../Screens").get_notes().size()
	(_toolbar_buttons["notifications"] as Button).text = "News (%d)" % notes if notes > 0 else "News"


# ---------------------------------------------------------------- Puzzle

var _puzzle_button: Button

# A button on the left side that opens the gold puzzle (gold_puzzle.gd).
func _build_puzzle_button() -> void:
	_puzzle_button = Button.new()
	_puzzle_button.name = "PuzzleButton"
	_puzzle_button.icon = load(ICONS % "gold")
	_puzzle_button.expand_icon = false
	_puzzle_button.focus_mode = Control.FOCUS_NONE
	_puzzle_button.add_theme_font_size_override("font_size", 20)
	_puzzle_button.add_theme_color_override("font_color", WoodenBoard.INK)
	_puzzle_button.add_theme_color_override("font_hover_color", WoodenBoard.INK)
	_puzzle_button.add_theme_color_override("font_disabled_color", Color(WoodenBoard.INK, 0.6))
	var paper := _box(Color(0.95, 0.89, 0.76, 0.96), 12, Color(0.45, 0.29, 0.14))
	for state in ["normal", "hover", "pressed", "disabled"]:
		_puzzle_button.add_theme_stylebox_override(state, paper)
	_puzzle_button.pressed.connect(func() -> void: get_node("../EventPuzzles").play_next())
	add_child(_puzzle_button)
	_pin(_puzzle_button, Control.PRESET_CENTER_LEFT, Vector2(20, 0))


func _update_puzzle_button() -> void:
	# One puzzle before each event, played whenever the player likes (event_puzzles.gd).
	var puzzles: EventPuzzles = get_node("../EventPuzzles")
	_puzzle_button.disabled = not puzzles.can_play()
	_puzzle_button.text = "Puzzle" if puzzles.can_play() else "Played"
	_puzzle_button.tooltip_text = "%s: earn %s, before the %s" % [puzzles.get_next_title(), puzzles.get_next_reward(), EventManager.NAMES[get_node("../../EventManager").get_next_type()]] if puzzles.can_play() else "Played. The next puzzle unlocks when the next event starts."


# ---------------------------------------------------------------- Other labels

# Moves the older text panels out of the way of the new corner panels.
func _move_old_labels() -> void:
	var ui := get_parent()
	(ui.get_node("ResourcePanel") as Control).visible = false
	var goal: Control = ui.get_node("GoalLabel")
	goal.offset_top = 104.0
	goal.offset_bottom = 260.0
	goal.add_theme_font_size_override("font_size", 20)
	var events: Control = ui.get_node("EventLabel")
	events.offset_top = 150.0
	events.offset_bottom = 340.0
	events.add_theme_font_size_override("font_size", 22)
	var selection: Control = ui.get_node("SelectionLabel")
	selection.offset_top = -500.0
	selection.offset_bottom = -340.0
	selection.add_theme_font_size_override("font_size", 22)
	# The white text becomes small parchment notes (team request, 2026-11-23).
	for note in [goal, events, selection, ui.get_node("PlacementLabel")]:
		_make_note(note)
	var hint := _menu.get_node_or_null("../UI/HintLabel") as Label
	if hint == null:
		for node in ui.find_children("HintLabel", "Label", true, false):
			hint = node
	if hint != null:
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.offset_right = 0.0
		hint.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))


# True if one of the corner panels covers this point on the screen, so a click
# there goes to the panel and not to the island behind it.
func covers(point: Vector2) -> bool:
	for child in get_children():
		if child is Control and child.visible and (child as Control).get_global_rect().has_point(point):
			return true
	return false


# A label turned into a parchment note: cream paper, a brown edge, dark ink.
var _notes: Array[Label] = []
func _make_note(label: Label) -> void:
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.95, 0.89, 0.76, 0.96)
	paper.border_color = Color(0.45, 0.29, 0.14)
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(10)
	paper.shadow_color = Color(0, 0, 0, 0.3)
	paper.shadow_size = 6
	paper.content_margin_left = 16.0
	paper.content_margin_right = 16.0
	paper.content_margin_top = 8.0
	paper.content_margin_bottom = 8.0
	label.add_theme_stylebox_override("normal", paper)
	label.add_theme_color_override("font_color", WoodenBoard.INK)
	label.add_theme_constant_override("outline_size", 0)
	_notes.append(label)


# Messages (team request, 2026-11-23: "make it come through animation and gone,
# then a small text of what is required"): the goal and event notes slide in
# when what they say changes, stay for NOTE_SECONDS, then fade away, leaving a
# small one-line reminder (their first line) that stays on screen.
const NOTE_SECONDS := 6.0
const FADING_NOTES := ["GoalLabel", "EventLabel"]
var _note_shape := {}            # Label -> its text with numbers removed, to notice real changes.
var _note_age := {}              # Label -> seconds since it last changed.
var _reminders := {}             # Label -> its small reminder Label.


func _shape(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("[0-9]+")
	return regex.sub(text, "#", true)


func _reminder_for(label: Label) -> Label:
	if not _reminders.has(label):
		var small := Label.new()
		small.name = label.name + "Reminder"
		small.add_theme_font_size_override("font_size", 16)
		small.add_theme_color_override("font_color", WoodenBoard.INK)
		var paper := _box(Color(0.95, 0.89, 0.76, 0.9), 8, Color(0.45, 0.29, 0.14))
		paper.content_margin_top = 3.0
		paper.content_margin_bottom = 3.0
		small.add_theme_stylebox_override("normal", paper)
		small.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.get_parent().add_child(small)
		_reminders[label] = small
	return _reminders[label]


# Each note shrinks to fit its text, and hides when it has none. Notes on the
# right of the screen grow leftwards, so they keep their right edge.
func _fit_notes() -> void:
	var delta := get_process_delta_time()
	for label in _notes:
		var has_text := label.text.strip_edges() != ""
		var shown := 1.0
		if label.name in FADING_NOTES:
			var shape := _shape(label.text)
			if _note_shape.get(label, "") != shape:
				_note_shape[label] = shape
				_note_age[label] = 0.0
			_note_age[label] = float(_note_age.get(label, 0.0)) + delta
			var age: float = _note_age[label]
			# Slide in over 0.4 s, stay, then fade out over 0.8 s.
			shown = clampf(age / 0.4, 0.0, 1.0) * (1.0 - clampf((age - NOTE_SECONDS) / 0.8, 0.0, 1.0))
			var small := _reminder_for(label)
			small.text = label.text.split("\n")[0] if has_text else ""
			small.visible = has_text and shown < 0.99
			small.modulate.a = 1.0 - shown
			small.reset_size()
			var screen := get_viewport_rect().size
			small.position = Vector2(20.0, 104.0) if label.name == "GoalLabel" else Vector2(screen.x - small.size.x - 20.0, 150.0)
		label.self_modulate.a = shown if has_text else 0.0
		label.modulate.a = shown if has_text else 0.0
		if has_text:
			label.reset_size()
			var screen := get_viewport_rect().size
			match label.name:
				"GoalLabel":
					label.position = Vector2(20.0 - 40.0 * (1.0 - label.modulate.a), 104.0)
				"EventLabel":
					label.position = Vector2(screen.x - label.size.x - 20.0 + 40.0 * (1.0 - label.modulate.a), 150.0)
				"SelectionLabel":
					label.position = Vector2(20.0, screen.y - label.size.y - 130.0)
				"PlacementLabel":
					label.position = Vector2((screen.x - label.size.x) * 0.5, 72.0)


# ---------------------------------------------------------------- Helpers

# Fixes a panel to a corner of the screen, "gap" pixels in from its edges, so it
# grows towards the middle of the screen as its contents need.
func _pin(panel: Control, corner: Control.LayoutPreset, gap: Vector2) -> void:
	panel.set_anchors_preset(corner)
	var right := corner == Control.PRESET_TOP_RIGHT or corner == Control.PRESET_BOTTOM_RIGHT
	var bottom := corner == Control.PRESET_BOTTOM_LEFT or corner == Control.PRESET_BOTTOM_RIGHT
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	panel.offset_left = gap.x
	panel.offset_right = gap.x
	panel.offset_top = gap.y
	panel.offset_bottom = gap.y


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL_COLOUR, 14))
	add_child(panel)
	return panel


func _box(colour: Color, radius: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(3)
	return box


func _icon(name: String, size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(ICONS % name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _label(text: String, size: int, colour := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
