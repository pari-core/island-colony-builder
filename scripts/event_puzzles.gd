# event_puzzles.gd
# A short puzzle before every scheduled event, each one different, to earn
# resources (team request, 2026-11-23: "put some different puzzle before every
# event to gain some resources").
#
#   Before            Puzzle                  How it works                     Earns
#   Discovery         Memory Match            Find the 6 pairs (gold_puzzle)   up to 25 Gold
#   Drought           Rain Dance              Watch 4 pictures light up, then  10 Food a step
#                                             repeat them in order
#   Accident          Builder's Sums          3 quick sums, pick the answer    15 Stone each
#   Disease           Find the Sick Plant     3 grids of leaves: pick the one  5 Gold each
#                                             that looks different
#   Storm             Storm Watch             3 jumbles of 12 pictures: count  15 Wood each
#                                             the houses before the storm hits
#   Migration         Newcomers' Words        3 scrambled words, pick the      15 Wood each
#                                             real one
#
# v2 (team request, 2026-11-23: "I wanna play puzzle whenever I want before the
# event"): a puzzle never opens by itself. Each upcoming event has one puzzle,
# played whenever the player likes from the toolbar's Puzzle button or the pause
# menu, once per event. When the event starts, the next event's puzzle unlocks.
# The game pauses while a puzzle is open. A wrong answer shows the right one and
# moves on; it never costs anything. "Skip" closes it early.
#
# Played with the mouse, or the controller: arrows move, Action picks, Back skips.
# Questions come from a seeded random generator, so tests can predict them.
class_name EventPuzzles
extends Control

signal finished(earned: int)

# Tests that are not about puzzles switch them off, so nothing pauses them.
static var enabled := true

const E := EventManager.Type
const R := ResourceManager.Type
const ICONS := "res://assets/ui/icons/%s.png"
const SEQUENCE_PICTURES := ["sun", "leaf", "food", "moon"]
const SEQUENCE_LENGTH := 4
const FLASH_SECONDS := 0.55      # How long each picture lights up in Rain Dance.
const FEEDBACK_SECONDS := 0.9    # How long "Correct!" or the right answer shows.
const ROUNDS := 3
const ODD_GRID := 9
const FIELD_SIZE := 12           # Pictures in each Storm Watch jumble.
const FIELD_OTHERS := ["tree", "sun", "leaf", "star", "people"]
const WORDS := [
	["HOUSE", "HORSE", "HOSE"], ["BREAD", "BEARD", "BRAND"], ["STONE", "TONES", "NOTES"],
	["BOAT", "BOOT", "BEAT"], ["FARM", "FORM", "FIRM"], ["WHEAT", "WHALE", "WHEEL"],
	["PLANK", "PLANT", "PLANE"], ["SHORE", "SHARE", "SHIRE"],
]
# Event -> [kind, title, what it earns, resource, amount per right answer]
const PUZZLES := {
	E.DROUGHT: ["sequence", "Rain Dance", "Repeat the pattern to call the rain.", R.FOOD, 10],
	E.ACCIDENT: ["sums", "Builder's Sums", "Help the builders count their materials.", R.STONE, 15],
	E.DISEASE: ["odd", "Find the Sick Plant", "Pick the leaf that looks different.", R.GOLD, 5],
	E.STORM: ["count", "Storm Watch", "Count the houses before the storm hits.", R.WOOD, 15],
	E.MIGRATION: ["words", "Newcomers' Words", "The newcomers' signs are scrambled. Pick the real word.", R.WOOD, 15],
}

var _kind := ""
var _resource := R.GOLD
var _per_right := 0
var _rounds: Array[Dictionary] = []   # Each: { "question", "options": [text or icon], "answer": int, "tints" }
var _round := 0
var _right := 0
var _earned := 0
var _highlight := 0
var _wait := 0.0                 # Counts down while feedback shows.
var _flash: Array[int] = []      # Rain Dance: pictures still to flash.
var _flash_time := 0.0
var _played := 0
var _done := false
var _memory_open := false
var _started := 0                # Events started so far this game.
var _played_for := -1            # The value of _started when the last puzzle was played.
var _last_active := 0

var _board: WoodenBoard
var _title: Label
var _intro: Label
var _question: Label
var _grid: GridContainer
var _field: GridContainer        # Storm Watch: the pictures to count.
var _buttons: Array[Button] = []
var _status: Label
var _skip: Button

@onready var _resources: ResourceManager = get_node("../../ResourceManager")
@onready var _events: EventManager = get_node("../../EventManager")
@onready var _memory: GoldPuzzle = get_node("../GoldPuzzle")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_board.visible = false
	_memory.closed.connect(_on_memory_closed)
	_events.events_changed.connect(_on_events_changed)


func is_open() -> bool:
	return _board.visible or _memory_open


func get_kind() -> String:
	return _kind


func get_earned() -> int:
	return _earned


# The right option of the current round, for tests.
func get_answer() -> int:
	return _rounds[_round].answer if _round < _rounds.size() else -1


func get_round() -> int:
	return _round


func is_showing_pattern() -> bool:
	return not _flash.is_empty()


# True while the next event's puzzle has not been played yet.
func can_play() -> bool:
	return enabled and not is_open() and _played_for != _started


# The puzzle waiting for the next event, such as "Rain Dance".
func get_next_title() -> String:
	var type := _events.get_next_type()
	return "Memory Match" if type == E.DISCOVERY else str(PUZZLES[type][1]) if PUZZLES.has(type) else ""


# What it earns, for the button's tooltip.
func get_next_reward() -> String:
	var type := _events.get_next_type()
	if type == E.DISCOVERY:
		return "up to %d Gold" % GoldPuzzle.MAX_REWARD
	if not PUZZLES.has(type):
		return ""
	return "%d %s per right answer" % [PUZZLES[type][4], str(ResourceManager.Type.keys()[PUZZLES[type][3]]).capitalize()]


# Opens the next event's puzzle (the toolbar button and the pause menu call
# this). Returns false if it was already played for this event.
func play_next() -> bool:
	if not can_play():
		return false
	var type := _events.get_next_type()
	if type == E.DISCOVERY:
		if not _memory.open(true):
			return false
		_kind = "memory"
		_memory_open = true
	elif PUZZLES.has(type):
		open(type)
	else:
		return false
	_played_for = _started
	return true


# A new event has started: the next event's puzzle unlocks.
func _on_events_changed() -> void:
	var active := _events.get_active().size()
	if active > _last_active:
		_started += 1
		var screens := get_node_or_null("../Screens")
		if enabled and screens != null and get_next_title() != "":
			screens.notify("New puzzle ready: %s (before the %s)" % [get_next_title(), EventManager.NAMES[_events.get_next_type()]], "star")
	_last_active = active


func open(type: EventManager.Type) -> void:
	var info: Array = PUZZLES[type]
	_kind = info[0]
	_resource = info[3]
	_per_right = info[4]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + _played
	_played += 1
	_rounds = _make_rounds(rng)
	_round = 0
	_right = 0
	_earned = 0
	_highlight = 0
	_wait = 0.0
	_done = false
	_title.text = "Puzzle: " + info[1]
	_intro.text = "%s  Each right answer: +%d %s." % [info[2], _per_right, _resource_name()]
	_skip.text = "Skip"
	_board.visible = true
	get_tree().paused = true
	if _kind == "sequence":
		_flash = (_rounds[0].sequence as Array).duplicate()
		_flash_time = FLASH_SECONDS + 0.4   # A short pause before the first flash.
	_show_round()


func _make_rounds(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var rounds: Array[Dictionary] = []
	match _kind:
		"sequence":
			var sequence: Array[int] = []
			for i in SEQUENCE_LENGTH:
				sequence.append(rng.randi_range(0, SEQUENCE_PICTURES.size() - 1))
			# Each step of the pattern is one round with the same four pictures.
			for i in SEQUENCE_LENGTH:
				rounds.append({ "question": "Step %d of %d: which came next?" % [i + 1, SEQUENCE_LENGTH], "options": SEQUENCE_PICTURES, "icons": true, "answer": sequence[i], "sequence": sequence })
		"sums":
			var goods := ["Planks", "Stones", "Nails", "Beams"]
			for i in ROUNDS:
				var a := rng.randi_range(6, 19)
				var b := rng.randi_range(4, 15)
				var minus := rng.randf() < 0.4 and a > b
				var total := a - b if minus else a + b
				var wrong := [total + rng.randi_range(1, 3), total - rng.randi_range(1, 3)]
				var options := [str(total), str(wrong[0]), str(wrong[1])]
				var answer := _shuffle_options(options, 0, rng)
				var good: String = goods[rng.randi() % goods.size()]
				rounds.append({ "question": "%d %s %s %d %s = ?" % [a, good, "-" if minus else "+", b, good], "options": options, "icons": false, "answer": answer })
		"odd":
			for i in ROUNDS:
				var options: Array = []
				for n in ODD_GRID:
					options.append("leaf")
				rounds.append({ "question": "Round %d of %d: which leaf is sick?" % [i + 1, ROUNDS], "options": options, "icons": true, "answer": rng.randi_range(0, ODD_GRID - 1), "odd": true })
		"count":
			for i in ROUNDS:
				var houses := rng.randi_range(3, 7)
				var field: Array = []
				for n in FIELD_SIZE:
					field.append("home" if n < houses else FIELD_OTHERS[rng.randi() % FIELD_OTHERS.size()])
				_shuffle_options(field, 0, rng)
				var options := [str(houses), str(houses + 1), str(houses - 1)]
				var answer := _shuffle_options(options, 0, rng)
				rounds.append({ "question": "Round %d of %d: how many houses?" % [i + 1, ROUNDS], "options": options, "icons": false, "answer": answer, "field": field })
		"words":
			var order := range(WORDS.size())
			for i in range(order.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var swap = order[i]
				order[i] = order[j]
				order[j] = swap
			for i in ROUNDS:
				var trio: Array = WORDS[order[i]]
				var word: String = trio[0]
				var options := [_title_case(trio[0]), _title_case(trio[1]), _title_case(trio[2])]
				var answer := _shuffle_options(options, 0, rng)
				rounds.append({ "question": "Unscramble:  %s" % _scramble(word, rng), "options": options, "icons": false, "answer": answer })
	return rounds


# Shuffles options in place and returns where the right one (at index right) went.
static func _shuffle_options(options: Array, right: int, rng: RandomNumberGenerator) -> int:
	var correct = options[right]
	for i in range(options.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = options[i]
		options[i] = options[j]
		options[j] = swap
	return options.find(correct)


static func _scramble(word: String, rng: RandomNumberGenerator) -> String:
	var letters := word.split("")
	for attempt in 10:
		for i in range(letters.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := letters[i]
			letters[i] = letters[j]
			letters[j] = swap
		if "".join(letters) != word:
			break
	return " ".join(letters)


static func _title_case(word: String) -> String:
	return word.substr(0, 1) + word.substr(1).to_lower()


func _resource_name() -> String:
	return str(ResourceManager.Type.keys()[_resource]).capitalize()


# Picks option index in the current round.
func pick(index: int) -> void:
	if not _board.visible or _done or _wait > 0.0 or not _flash.is_empty():
		return
	var current: Dictionary = _rounds[_round]
	if index < 0 or index >= (current.options as Array).size():
		return
	var correct := index == int(current.answer)
	if correct:
		_right += 1
		_earned += _resources.add(_resource, _per_right)
		_status.text = "Correct!  +%d %s" % [_per_right, _resource_name()]
	elif current.get("icons", false) and not current.has("odd"):
		_status.text = "Not quite: it was the %s." % SEQUENCE_PICTURES[int(current.answer)]
	elif current.has("odd"):
		_status.text = "Not quite: it was the one marked."
	else:
		_status.text = "Not quite: it was %s." % str(current.options[int(current.answer)])
	_mark(int(current.answer), index)
	# A wrong step ends Rain Dance: the pattern is broken.
	if _kind == "sequence" and not correct:
		_round = _rounds.size() - 1
	_wait = FEEDBACK_SECONDS


func _next_round() -> void:
	_round += 1
	if _round >= _rounds.size():
		_done = true
		_question.text = "Puzzle complete!"
		_status.text = "You earned %d %s!" % [_earned, _resource_name()] if _earned > 0 else "No reward this time."
		_skip.text = "Continue"
		for button in _buttons:
			button.visible = false
		return
	_highlight = 0
	_show_round()


func close() -> void:
	if not _board.visible:
		return
	_board.visible = false
	get_tree().paused = false
	_flash.clear()
	finished.emit(_earned)


func _on_memory_closed() -> void:
	if not _memory_open:
		return
	_memory_open = false
	finished.emit(0)


func _process(delta: float) -> void:
	if not _board.visible:
		return
	get_tree().paused = true
	if not _flash.is_empty():
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash.pop_front()
			_flash_time = FLASH_SECONDS
			if _flash.is_empty():
				_question.text = _rounds[_round].question
				_status.text = "Now repeat it, in order."
			_show_flash()
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_next_round()


func _input(event: InputEvent) -> void:
	if not _board.visible:
		return
	var count := _buttons.filter(func(b: Button) -> bool: return b.visible).size()
	var columns := maxi(_grid.columns, 1)
	if event.is_action_pressed("pad_left", true):
		_highlight = posmod(_highlight - 1, maxi(count, 1))
	elif event.is_action_pressed("pad_right", true):
		_highlight = posmod(_highlight + 1, maxi(count, 1))
	elif event.is_action_pressed("pad_up", true):
		_highlight = posmod(_highlight - columns, maxi(count, 1))
	elif event.is_action_pressed("pad_down", true):
		_highlight = posmod(_highlight + columns, maxi(count, 1))
	elif event.is_action_pressed("pad_action") or event.is_action_pressed("event_respond"):
		if _done:
			close()
		else:
			pick(_highlight)
	elif event.is_action_pressed("pad_back") or event.is_action_pressed("ui_cancel"):
		close()
	elif not event is InputEventKey:
		return
	_paint()
	get_viewport().set_input_as_handled()


func _show_round() -> void:
	var current: Dictionary = _rounds[_round]
	var options: Array = current.options
	_grid.columns = 3 if current.has("odd") else (4 if current.get("icons", false) else 3)
	_question.text = "Watch the pattern..." if not _flash.is_empty() else current.question
	# Storm Watch shows its pictures above the answers.
	_field.visible = current.has("field")
	for child in _field.get_children():
		child.free()
	for picture: String in current.get("field", []):
		var image := TextureRect.new()
		image.texture = load(ICONS % picture)
		image.custom_minimum_size = Vector2(54, 54)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_field.add_child(image)
	if _flash.is_empty() and _round == 0:
		_status.text = "Pick an answer."
	elif not _flash.is_empty():
		_status.text = ""
	for i in _buttons.size():
		var button := _buttons[i]
		button.visible = i < options.size()
		if not button.visible:
			continue
		if current.get("icons", false):
			button.icon = load(ICONS % options[i])
			button.text = ""
			button.custom_minimum_size = Vector2(96, 96)
			# Find the Sick Plant: the odd one is drawn brown and turned.
			var sick: bool = current.has("odd") and i == int(current.answer)
			button.modulate = Color(1.0, 0.62, 0.35) if sick else Color.WHITE
			button.rotation_degrees = 0.0
		else:
			button.icon = null
			button.text = str(options[i])
			button.custom_minimum_size = Vector2(150, 70)
			button.modulate = Color.WHITE
	_paint()
	_board.reset_size.call_deferred()   # Shrink or grow the board to fit this round.


func _show_flash() -> void:
	_paint()
	if not _flash.is_empty():
		var lit: int = _flash[0]
		_style(_buttons[lit], Color(1.0, 0.95, 0.55), Color(1.0, 0.75, 0.2), 6)


# Colours every option: the highlighted one gets a gold border.
func _paint() -> void:
	for i in _buttons.size():
		_style(_buttons[i], Color(0.98, 0.94, 0.84), Color(1.0, 0.75, 0.2) if i == _highlight and _flash.is_empty() else Color(0.45, 0.3, 0.15), 4 if i == _highlight and _flash.is_empty() else 2)


# After a pick: the right answer green, a wrong pick red.
func _mark(right: int, picked: int) -> void:
	_style(_buttons[right], Color(0.75, 0.92, 0.65), Color(0.2, 0.55, 0.2), 5)
	if picked != right:
		_style(_buttons[picked], Color(0.98, 0.72, 0.65), Color(0.7, 0.2, 0.15), 5)


static func _style(button: Button, fill: Color, border: Color, width: int) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(10)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, box)


func _build() -> void:
	_board = WoodenBoard.new()
	_board.name = "EventPuzzleBoard"
	add_child(_board)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_board.add_child(column)
	_title = _label(28, WoodenBoard.TITLE_INK)
	_title.custom_minimum_size = Vector2(560, WoodenBoard.RIBBON_HEIGHT - 10.0)
	_title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03))
	_title.add_theme_constant_override("outline_size", 8)
	column.add_child(_title)
	_intro = _label(17, WoodenBoard.INK)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size = Vector2(560, 0)   # A wrapping label needs a width.
	column.add_child(_intro)
	_question = _label(24, WoodenBoard.INK)
	column.add_child(_question)
	_field = GridContainer.new()
	_field.columns = 6
	_field.add_theme_constant_override("h_separation", 10)
	_field.add_theme_constant_override("v_separation", 10)
	var field_centre := CenterContainer.new()
	field_centre.add_child(_field)
	column.add_child(field_centre)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	var centre := CenterContainer.new()
	centre.add_child(_grid)
	column.add_child(centre)
	for i in ODD_GRID:
		var button := Button.new()
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 26)
		button.add_theme_color_override("font_color", WoodenBoard.INK)
		button.add_theme_color_override("font_hover_color", WoodenBoard.INK)
		button.pressed.connect(func() -> void:
			_highlight = i
			pick(i))
		_grid.add_child(button)
		_buttons.append(button)
	_status = _label(20, Color(0.25, 0.4, 0.15))
	column.add_child(_status)
	_skip = Button.new()
	_skip.text = "Skip"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 20)
	_skip.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_skip)
	column.add_child(row)
	_board.resized.connect(func() -> void:
		_board.position = (get_viewport_rect().size - _board.size) * 0.5)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label
