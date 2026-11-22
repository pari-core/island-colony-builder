# screens.gd
# The storybook windows of v2 (team design, 2026-11-23): cream parchment with a
# wooden title ribbon, a round close button, small leaves in the corners, sage
# green for the main action and warm brown ink. The island itself stays
# realistic 3D; only the interface is illustrated.
#   Build Menu:    tabs (Housing, Farming, Production, Storage, Landmarks), a card
#                  per building, and a detail panel with a green Place button.
#   How to Play:   tabs (Basics, Building, Resources, Events), three cards each.
#   Settings:      graphics quality, brightness, camera speed, volume,
#                  fullscreen and VSync, kept in user://settings.cfg.
#   Credits:       the team and every asset's author and licence.
#   Notifications: a log of what happened (shortages, happiness, harvests,
#                  events), newest first, with how long ago.
# Each window pauses the game while it is open (except Notifications) and closes
# with its X, the Back button or Esc.
class_name Screens
extends Control

const ICONS := "res://assets/ui/icons/%s.png"
const THUMBS := "res://assets/ui/thumbs/%s.png"
const SAGE := Color(0.42, 0.6, 0.33)
const SAGE_DARK := Color(0.27, 0.42, 0.2)
const TERRACOTTA := Color(0.73, 0.34, 0.24)
const CARD := Color(0.98, 0.93, 0.82)
const CARD_EDGE := Color(0.62, 0.45, 0.25)
const SETTINGS_FILE := "user://settings.cfg"
const MAX_NOTES := 30

const BUILD_TABS := [
	["Housing", "home", ["House"]],
	["Farming", "food", ["Farm", "Water Storage"]],
	["Production", "hammer", ["Lumber Camp", "Quarry", "Mine"]],
	["Storage", "book", ["Warehouse", "Research Lab"]],
	["Landmarks", "trophy", ["Lighthouse", "Harbour", "Town Hall"]],
]
const DESCRIPTIONS := {
	"House": "A cosy home for 4 settlers. Homes let the colony grow.",
	"Farm": "Grows food in fenced fields. 2 workers.",
	"Water Storage": "Stores water to protect the farms in a drought.",
	"Lumber Camp": "Fells trees for wood. 2 workers.",
	"Quarry": "Cuts stone from the rocks. 2 workers.",
	"Mine": "Digs for gold, slowly. 2 workers.",
	"Warehouse": "Raises the storage limit of every resource by 200.",
	"Research Lab": "Researches the vaccine and upgrades.",
	"Lighthouse": "A landmark. Build all three to win.",
	"Harbour": "A landmark. Build all three to win.",
	"Town Hall": "A landmark. Build all three to win.",
}
const HELP_TABS := [
	["Basics", "home", [
		["Build Your Colony", "Open the Build Menu, pick a building and place it on a square.", "house"],
		["Put People to Work", "Select a building and add workers. Work buildings without workers make nothing.", "lumber_camp"],
		["Keep Them Happy", "Food, homes and good choices in events raise happiness.", "smile"],
	]],
	["Building", "hammer", [
		["Choose a Square", "Squares stand round the plaza. Green means you can build there.", "farm"],
		["Pay the Cost", "Each building costs wood, stone or gold, shown on its card.", "wood"],
		["Watch It Rise", "Bigger buildings take days and builders to finish.", "lighthouse"],
	]],
	["Resources", "wood", [
		["Food", "Farms grow it; everyone eats it. Run out and the colony starves.", "food"],
		["Wood and Stone", "From Lumber Camps and Quarries. Storage holds 200 of each.", "stone"],
		["Gold", "From the Mine, trade, and the memory puzzle.", "gold"],
	]],
	["Events", "star", [
		["Five Events", "Discovery, drought, trade, disease and migration, one after another.", "star"],
		["Make a Choice", "Some events ask what to do. Each answer has a cost and a result.", "warning"],
		["Win", "24 people and happiness 70, or all three landmarks, after facing every event.", "trophy"],
	]],
]
const CREDITS := [
	"Island Colony Builder: Pinnacle 1, Project 19",
	"Team: pari, mahi, nivi, devanshi",
	"Made with Godot 4.7 (MIT licence)",
	"",
	"KayKit Medieval Builder Pack by Kay Lousberg (CC0)",
	"Stylized Nature MegaKit and Farm Animals by Quaternius (CC0)",
	"Ground, rock and sky textures from Poly Haven (CC0)",
	"Swedish royal yacht Amadis by the Finnish Heritage Agency (CC BY 4.0)",
	"Realistic Palm Tree 4 Free by Next Spring (CC BY 4.0)",
	"Oak tree by massive-graphisme (CC BY 4.0)",
	"Wooden Log Cabin, Old Wooden Shed by donnichols (CC BY 4.0)",
	"Log pile by 00amza (CC BY 4.0)",
	"Wooden Storage Hangar by Everex (CC BY 4.0)",
	"317 Washington Street by hamma085 (CC BY 4.0)",
	"Stylized Gold Mine by nico_hartl (CC BY 4.0)",
	"Settler characters from Sketchfab and Mixamo (see documentation/asset_licences.md)",
	"Icons and interface drawn by the team",
]

var _window: WoodenBoard = null  # The window that is open, or null.
var _window_name := ""
var _paused_by_window := false
var _notes: Array[Dictionary] = []   # { "text", "icon", "time" }
var _last_happiness := -1
var _last_check := 0.0
var _build_tab := 0
var _build_choice := 0
var _help_tab := 0
var _settings := { "quality": 2, "brightness": 1.0, "camera": 0.35, "volume": 0.8, "fullscreen": false, "vsync": true }

@onready var _builder: BuildingManager = get_node("../../BuildingManager")
@onready var _resources: ResourceManager = get_node("../../ResourceManager")
@onready var _population: PopulationManager = get_node("../../PopulationManager")
@onready var _events: EventManager = get_node("../../EventManager")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	_events.events_changed.connect(_on_events_changed)
	get_node("../../CropManager").harvested.connect(func(_plot: BuildingPlot) -> void: notify("A harvest is ready on a farm!", "food"))


func is_open() -> bool:
	return _window != null


func get_open_name() -> String:
	return _window_name


func get_notes() -> Array[Dictionary]:
	return _notes


# ---------------------------------------------------------------- Windows

func open(which: String) -> void:
	close()
	get_parent().move_child(self, get_parent().get_child_count() - 1)   # Above any menu board.
	match which:
		"build": _open_build()
		"help": _open_help()
		"settings": _open_settings()
		"credits": _open_credits()
		"notifications": _open_notifications()
	_window_name = which
	if which != "notifications" and not get_tree().paused:
		get_tree().paused = true
		_paused_by_window = true


func close() -> void:
	if _window == null:
		return
	_window.queue_free()
	_window = null
	_window_name = ""
	if _paused_by_window:
		get_tree().paused = false
		_paused_by_window = false


func _input(event: InputEvent) -> void:
	if _window != null and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pad_back") or event.is_action_pressed("pad_menu")):
		close()
		get_viewport().set_input_as_handled()


# A parchment window with a title on its ribbon and a round close button.
func _frame(title: String, icon: String, width: float) -> VBoxContainer:
	_window = WoodenBoard.new()
	_window.leaves = true
	add_child(_window)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(width, 0)
	column.add_theme_constant_override("separation", 14)
	_window.add_child(column)
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, WoodenBoard.RIBBON_HEIGHT - 8.0)
	column.add_child(head)
	var left := Control.new()
	left.custom_minimum_size = Vector2(44, 0)
	head.add_child(left)
	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	if icon != "":
		name_row.add_child(_icon(icon, 34))
	name_row.add_child(_text(title, 30, WoodenBoard.TITLE_INK, true))
	head.add_child(name_row)
	var x := _round_button("×", close)
	head.add_child(x)
	_window.resized.connect(func() -> void:
		if is_instance_valid(_window):
			_window.position = ((get_viewport_rect().size - _window.size) * 0.5).floor())
	return column


func _open_build() -> void:
	var column := _frame("Build Menu", "hammer", 860.0)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for i in BUILD_TABS.size():
		tabs.add_child(_tab(BUILD_TABS[i][0], BUILD_TABS[i][1], i == _build_tab, func() -> void:
			_build_tab = i
			_build_choice = 0
			open("build")))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var names: Array = BUILD_TABS[_build_tab][2]
	var shown: Array[int] = []
	for building_name: String in names:
		var index := _index_of(building_name)
		if index < 0 or not _builder.is_available(index):
			continue
		shown.append(index)
	_build_choice = clampi(_build_choice, 0, maxi(shown.size() - 1, 0))
	for n in shown.size():
		var index := shown[n]
		var info: Dictionary = BuildingManager.BUILDINGS[index]
		var card := _card_button(n == _build_choice, func() -> void:
			_build_choice = n
			open("build"))
		var inside := _stack(card)
		inside.add_child(_picture(info.name, 86))
		inside.add_child(_text(info.name, 16, WoodenBoard.INK, false, true))
		inside.add_child(_cost_row(info.cost, 14))
		grid.add_child(card)
	if shown.is_empty():
		grid.add_child(_text("Nothing to build here yet.", 18, WoodenBoard.INK))
		return
	var chosen: Dictionary = BuildingManager.BUILDINGS[shown[_build_choice]]
	var detail := PanelContainer.new()
	detail.custom_minimum_size = Vector2(250, 0)
	detail.add_theme_stylebox_override("panel", _paper(CARD, 12))
	body.add_child(detail)
	var info_column := VBoxContainer.new()
	info_column.add_theme_constant_override("separation", 8)
	detail.add_child(info_column)
	info_column.add_child(_picture(chosen.name, 130))
	info_column.add_child(_text(chosen.name, 24, WoodenBoard.INK, false, true))
	var about := _text(DESCRIPTIONS.get(chosen.name, ""), 16, WoodenBoard.INK, false, true)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(220, 0)
	info_column.add_child(about)
	var cost := HBoxContainer.new()
	cost.alignment = BoxContainer.ALIGNMENT_CENTER
	cost.add_child(_text("Cost:", 16, WoodenBoard.INK))
	cost.add_child(_cost_row(chosen.cost, 16))
	info_column.add_child(cost)
	var place := _sage_button("Place", func() -> void:
		var index := shown[_build_choice]
		close()
		if not _builder.is_placing():
			_builder.start_placement()
		_builder.choose_building(index))
	place.disabled = not _resources.can_afford(chosen.cost)
	info_column.add_child(place)
	if place.disabled:
		info_column.add_child(_text("Not enough resources yet", 14, TERRACOTTA, false, true))


func _open_help() -> void:
	var column := _frame("How to Play", "book", 900.0)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for i in HELP_TABS.size():
		tabs.add_child(_tab(HELP_TABS[i][0], HELP_TABS[i][1], i == _help_tab, func() -> void:
			_help_tab = i
			open("help")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var steps: Array = HELP_TABS[_help_tab][2]
	for n in steps.size():
		var step: Array = steps[n]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _paper(CARD, 12))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inside := VBoxContainer.new()
		inside.add_theme_constant_override("separation", 8)
		card.add_child(inside)
		inside.add_child(_text("%d. %s" % [n + 1, step[0]], 20, WoodenBoard.INK, false, true))
		var body := _text(step[1], 16, WoodenBoard.INK, false, true)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(240, 66)
		inside.add_child(body)
		inside.add_child(_picture(step[2], 120))
		row.add_child(card)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	nav.add_child(_round_button("‹", func() -> void:
		_help_tab = posmod(_help_tab - 1, HELP_TABS.size())
		open("help")))
	for i in HELP_TABS.size():
		nav.add_child(_text("●" if i == _help_tab else "○", 18, WoodenBoard.INK))
	nav.add_child(_round_button("›", func() -> void:
		_help_tab = posmod(_help_tab + 1, HELP_TABS.size())
		open("help")))
	column.add_child(nav)


func _open_settings() -> void:
	var column := _frame("Settings", "gear", 620.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 14)
	column.add_child(grid)
	grid.add_child(_text("Graphics Quality", 20, WoodenBoard.INK))
	var quality := OptionButton.new()
	for q in ["Low", "Medium", "High"]:
		quality.add_item(q)
	quality.selected = int(_settings.quality)
	quality.item_selected.connect(func(q: int) -> void: _change_setting("quality", q))
	grid.add_child(quality)
	for item in [["Brightness", "brightness", 0.6, 1.4], ["Camera Sensitivity", "camera", 0.15, 0.7], ["Volume", "volume", 0.0, 1.0]]:
		grid.add_child(_text(item[0], 20, WoodenBoard.INK))
		var slider := HSlider.new()
		slider.min_value = item[2]
		slider.max_value = item[3]
		slider.step = 0.01
		slider.value = float(_settings[item[1]])
		slider.custom_minimum_size = Vector2(260, 24)
		slider.value_changed.connect(func(v: float) -> void: _change_setting(item[1], v))
		grid.add_child(slider)
	for item in [["Fullscreen", "fullscreen"], ["VSync", "vsync"]]:
		grid.add_child(_text(item[0], 20, WoodenBoard.INK))
		var box := CheckBox.new()
		box.button_pressed = bool(_settings[item[1]])
		box.toggled.connect(func(on: bool) -> void: _change_setting(item[1], on))
		grid.add_child(box)
	grid.add_child(_text("Language", 20, WoodenBoard.INK))
	grid.add_child(_text("English", 20, WoodenBoard.INK))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 14)
	buttons.add_child(_plain_button("Reset", func() -> void:
		_settings = { "quality": 2, "brightness": 1.0, "camera": 0.35, "volume": 0.8, "fullscreen": false, "vsync": true }
		_apply_settings()
		open("settings")))
	buttons.add_child(_sage_button("Apply", func() -> void:
		_save_settings()
		close()))
	column.add_child(buttons)


func _open_credits() -> void:
	var column := _frame("Credits", "star", 720.0)
	for line: String in CREDITS:
		var label := _text(line, 18 if line != CREDITS[0] else 22, WoodenBoard.INK, false, true)
		column.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_sage_button("Close", close))
	column.add_child(row)


func _open_notifications() -> void:
	var column := _frame("Notifications", "bell", 620.0)
	if _notes.is_empty():
		column.add_child(_text("Nothing new yet.", 18, WoodenBoard.INK, false, true))
	var now := Time.get_ticks_msec()
	for note in _notes.slice(0, 8):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(_icon(note.icon, 34))
		var text := _text(note.text, 18, WoodenBoard.INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var minutes := int((now - int(note.time)) / 60000)
		row.add_child(_text("just now" if minutes < 1 else "%dm ago" % minutes, 15, Color(WoodenBoard.INK, 0.7)))
		column.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(_plain_button("Clear All", func() -> void:
		_notes.clear()
		open("notifications")))
	column.add_child(buttons)


# ---------------------------------------------------------------- Notifications

# Adds a line to the notifications log (newest first).
func notify(text: String, icon: String) -> void:
	_notes.push_front({ "text": text, "icon": icon, "time": Time.get_ticks_msec() })
	if _notes.size() > MAX_NOTES:
		_notes.resize(MAX_NOTES)


func _on_events_changed() -> void:
	for event in _events.get_active():
		var text := "%s has begun!" % EventManager.NAMES[event.type]
		if _notes.is_empty() or _notes[0].text != text:
			notify(text, "warning" if event.type in [EventManager.Type.DROUGHT, EventManager.Type.DISEASE, EventManager.Type.STORM] else "star")


func _process(delta: float) -> void:
	_last_check -= delta
	if _last_check > 0.0:
		return
	_last_check = 3.0
	var happiness := _population.get_happiness()
	if _last_happiness >= 0 and absi(happiness - _last_happiness) >= 5:
		notify("Happiness has %s to %d." % ["risen" if happiness > _last_happiness else "fallen", happiness], "smile")
	_last_happiness = happiness
	for entry in [[ResourceManager.Type.FOOD, "food", "Food"], [ResourceManager.Type.WOOD, "wood", "Wood"], [ResourceManager.Type.STONE, "stone", "Stone"]]:
		var amount := _resources.get_amount(entry[0])
		var text := "Your %s supply is running low!" % entry[2].to_lower()
		if amount < 20 and (_notes.is_empty() or _notes[0].text != text):
			notify(text, entry[1])


# ---------------------------------------------------------------- Settings

func _change_setting(key: String, value) -> void:
	_settings[key] = value
	_apply_settings()


func _apply_settings() -> void:
	var main := get_node("../..")
	var environment: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	environment.adjustment_enabled = true
	environment.adjustment_brightness = float(_settings.brightness)
	var quality := int(_settings.quality)
	environment.ssao_enabled = quality >= 2
	(main.get_node("Sun") as DirectionalLight3D).shadow_enabled = quality >= 1
	main.get_node("Camera3D").move_speed = float(_settings.camera)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(_settings.volume), 0.001)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _settings.vsync else DisplayServer.VSYNC_DISABLED)
	if get_tree().current_scene == main:   # Not in the automated tests.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS_FILE) == OK:
		for key in _settings:
			_settings[key] = file.get_value("settings", key, _settings[key])
	_apply_settings.call_deferred()


func _save_settings() -> void:
	var file := ConfigFile.new()
	for key in _settings:
		file.set_value("settings", key, _settings[key])
	file.save(SETTINGS_FILE)


# ---------------------------------------------------------------- Pieces

func _index_of(building_name: String) -> int:
	for i in BuildingManager.BUILDINGS.size():
		if BuildingManager.BUILDINGS[i].name == building_name:
			return i
	return -1


func _picture(name: String, height: float) -> TextureRect:
	var picture := TextureRect.new()
	var thumb := THUMBS % name.to_lower().replace(" ", "_")
	picture.texture = load(thumb) if ResourceLoader.exists(thumb) else load(ICONS % name) if ResourceLoader.exists(ICONS % name) else null
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(0, height)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _cost_row(cost: Dictionary, size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for type in cost:
		row.add_child(_icon(["food", "wood", "stone", "gold"][type], size + 6))
		row.add_child(_text(str(cost[type]), size, WoodenBoard.INK))
	return row


func _stack(button: Button) -> VBoxContainer:
	var inside := VBoxContainer.new()
	inside.set_anchors_preset(Control.PRESET_FULL_RECT)
	inside.offset_left = 6
	inside.offset_right = -6
	inside.offset_top = 6
	inside.offset_bottom = -6
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_theme_constant_override("separation", 2)
	button.add_child(inside)
	return inside


func _card_button(chosen: bool, action: Callable) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(170, 150)
	card.focus_mode = Control.FOCUS_NONE
	var paper := _paper(CARD, 12, Color(1.0, 0.75, 0.25) if chosen else CARD_EDGE, 4 if chosen else 2)
	for state in ["normal", "hover", "pressed"]:
		card.add_theme_stylebox_override(state, paper if state != "hover" else _paper(CARD.lightened(0.3), 12, Color(1.0, 0.75, 0.25), 3))
	card.pressed.connect(action)
	return card


func _tab(label: String, icon: String, active: bool, action: Callable) -> Button:
	var tab := Button.new()
	tab.text = label
	tab.icon = load(ICONS % icon)
	tab.expand_icon = false
	tab.focus_mode = Control.FOCUS_NONE
	tab.add_theme_font_size_override("font_size", 18)
	tab.add_theme_color_override("font_color", WoodenBoard.INK)
	tab.add_theme_color_override("font_hover_color", WoodenBoard.INK)
	tab.add_theme_constant_override("icon_max_width", 24)
	var colour := Color(0.99, 0.86, 0.55) if active else Color(0.9, 0.82, 0.66)
	for state in ["normal", "hover", "pressed"]:
		tab.add_theme_stylebox_override(state, _paper(colour if state != "hover" else colour.lightened(0.1), 10, CARD_EDGE, 2))
	tab.pressed.connect(action)
	return tab


func _sage_button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var colour := SAGE if state == "normal" else SAGE.lightened(0.12) if state == "hover" else SAGE_DARK if state == "pressed" else Color(0.6, 0.6, 0.55)
		button.add_theme_stylebox_override(state, _paper(colour, 10, SAGE_DARK, 2))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	button.pressed.connect(action)
	return button


func _plain_button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", WoodenBoard.INK)
	button.add_theme_color_override("font_hover_color", WoodenBoard.INK)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, _paper(Color(0.9, 0.8, 0.62) if state != "hover" else Color(0.95, 0.86, 0.7), 10, CARD_EDGE, 2))
	button.pressed.connect(action)
	return button


func _round_button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed"]:
		var b := _paper(Color(0.45, 0.28, 0.14) if state != "hover" else Color(0.58, 0.36, 0.18), 22, Color(0.25, 0.14, 0.06), 3)
		b.content_margin_top = 0.0
		b.content_margin_bottom = 2.0
		button.add_theme_stylebox_override(state, b)
	button.pressed.connect(action)
	return button


func _paper(colour: Color, radius: int, edge := Color(0, 0, 0, 0), width := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	if width > 0:
		box.border_color = edge
		box.set_border_width_all(width)
	box.shadow_color = Color(0, 0, 0, 0.15)
	box.shadow_size = 3
	return box


func _icon(name: String, size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(ICONS % name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _text(text: String, size: int, colour: Color, edge := false, centre := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	if edge:
		label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03))
		label.add_theme_constant_override("outline_size", 8)
	if centre:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
