# gold_puzzle.gd
# A mini puzzle for extra gold (team request, 2026-11-23): a memory game of
# twelve face-down cards, six pairs of the colony's pictures (food, wood, stone,
# gold, people, a house). Turn two cards at a time; a matching pair stays face
# up. Finding all six pairs pays gold: the fewer moves, the more gold.
#
#   Reward: MAX_REWARD gold for a perfect game (6 moves), one less for every
#   extra move, but never under MIN_REWARD.
#   After a puzzle, the next one can be played COOLDOWN seconds later, so it
#   is a bonus, not a way round the economy.
#
# The game is paused while the puzzle is open. It is played with the mouse, or
# with the controller: arrows move, Action turns a card, Back closes.
# The cards are shuffled with a fixed seed per puzzle, so it is testable.
class_name GoldPuzzle
extends Control

signal solved(gold: int)
signal closed

const PICTURES := ["food", "wood", "stone", "gold", "people", "home"]
const COLUMNS := 4
const MAX_REWARD := 25
const MIN_REWARD := 8
const COOLDOWN := 90.0           # Seconds of play between puzzles.
const SHOW_MISMATCH := 0.7       # Seconds two unmatched cards stay face up.
const ICONS := "res://assets/ui/icons/%s.png"
const BACK_COLOUR := Color(0.36, 0.24, 0.13)
const FACE_COLOUR := Color(0.98, 0.94, 0.84)

var _cards: Array[String] = []   # The picture on each card.
var _shown: Array[bool] = []     # Face up for good (matched).
var _turned: Array[int] = []     # Cards turned this move (0, 1 or 2).
var _moves := 0
var _pairs := 0
var _played := 0                 # Puzzles started, for the shuffle seed.
var _cooldown := 0.0
var _highlight := 0
var _wait := 0.0                 # Counts down while a mismatch is on show.
var _board: WoodenBoard
var _buttons: Array[Button] = []
var _status: Label
var _close: Button

@onready var _resources: ResourceManager = get_node("../../ResourceManager")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_board.visible = false


func is_open() -> bool:
	return _board.visible


func is_ready() -> bool:
	return _cooldown <= 0.0


func get_cooldown() -> float:
	return _cooldown


func get_moves() -> int:
	return _moves


func get_pairs() -> int:
	return _pairs


func get_cards() -> Array[String]:
	return _cards


# Gold for finishing in this many moves.
static func reward_for(moves: int) -> int:
	return clampi(MAX_REWARD - (moves - PICTURES.size()), MIN_REWARD, MAX_REWARD)


# Deals a new puzzle and shows it. Returns false while the cooldown runs, unless
# forced (before a Discovery event, see event_puzzles.gd).
func open(forced := false) -> bool:
	if (not is_ready() and not forced) or is_open():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + _played
	_played += 1
	_cards.clear()
	for picture in PICTURES:
		_cards.append(picture)
		_cards.append(picture)
	for i in range(_cards.size() - 1, 0, -1):   # Shuffle (Fisher-Yates).
		var j := rng.randi_range(0, i)
		var swap := _cards[i]
		_cards[i] = _cards[j]
		_cards[j] = swap
	_shown.clear()
	for i in _cards.size():
		_shown.append(false)
	_turned.clear()
	_moves = 0
	_pairs = 0
	_highlight = 0
	_close.text = "Give up"
	_board.visible = true
	get_tree().paused = true
	_refresh()
	return true


func close() -> void:
	if not is_open():
		return
	_board.visible = false
	get_tree().paused = false
	_cooldown = COOLDOWN
	closed.emit()


# Turns a card face up. The second card of a move is compared with the first.
func turn(index: int) -> void:
	if not is_open() or _wait > 0.0 or _pairs == PICTURES.size():
		return
	if _shown[index] or index in _turned:
		return
	_turned.append(index)
	if _turned.size() == 2:
		_moves += 1
		if _cards[_turned[0]] == _cards[_turned[1]]:
			_shown[_turned[0]] = true
			_shown[_turned[1]] = true
			_turned.clear()
			_pairs += 1
			if _pairs == PICTURES.size():
				var gold := reward_for(_moves)
				_resources.add(ResourceManager.Type.GOLD, gold)
				_close.text = "Collect"
				solved.emit(gold)
		else:
			_wait = SHOW_MISMATCH
	_refresh()


func _process(delta: float) -> void:
	if not is_open():
		if not get_tree().paused:
			_cooldown = maxf(_cooldown - delta, 0.0)
		return
	get_tree().paused = true
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_turned.clear()
			_refresh()


# The controller (and keyboard) while the puzzle is open. _input runs before any
# other node's input handling, so nothing behind the puzzle reacts.
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("pad_left", true):
		_highlight = posmod(_highlight - 1, _cards.size())
	elif event.is_action_pressed("pad_right", true):
		_highlight = posmod(_highlight + 1, _cards.size())
	elif event.is_action_pressed("pad_up", true):
		_highlight = posmod(_highlight - COLUMNS, _cards.size())
	elif event.is_action_pressed("pad_down", true):
		_highlight = posmod(_highlight + COLUMNS, _cards.size())
	elif event.is_action_pressed("pad_action") or event.is_action_pressed("event_respond"):
		if _pairs == PICTURES.size():
			close()
		else:
			turn(_highlight)
	elif event.is_action_pressed("pad_back") or event.is_action_pressed("pad_menu") or event.is_action_pressed("ui_cancel"):
		close()
	elif not event is InputEventKey:
		return
	_refresh()
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	for i in _buttons.size():
		var face_up := _shown[i] or i in _turned
		var button := _buttons[i]
		button.icon = load(ICONS % _cards[i]) if face_up else null
		button.text = "" if face_up else "?"
		var box := StyleBoxFlat.new()
		box.bg_color = FACE_COLOUR if face_up else BACK_COLOUR
		box.set_corner_radius_all(10)
		box.border_color = Color(1.0, 0.75, 0.2) if i == _highlight else Color(0.25, 0.15, 0.07)
		box.set_border_width_all(4 if i == _highlight else 2)
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, box)
	if _pairs == PICTURES.size():
		_status.text = "Solved in %d moves: +%d gold!" % [_moves, reward_for(_moves)]
	else:
		# The best prize still possible: each remaining pair found in one move.
		_status.text = "Find the pairs.  Pairs %d / %d   Moves %d   (up to %d gold)" % [_pairs, PICTURES.size(), _moves, reward_for(_moves + PICTURES.size() - _pairs)]


func _build() -> void:
	_board = WoodenBoard.new()
	_board.name = "PuzzleBoard"
	add_child(_board)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_board.add_child(column)
	var title := Label.new()
	title.text = "Memory Puzzle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(0, WoodenBoard.RIBBON_HEIGHT - 10.0)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", WoodenBoard.TITLE_INK)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03))
	title.add_theme_constant_override("outline_size", 8)
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for i in PICTURES.size() * 2:
		var button := Button.new()
		button.custom_minimum_size = Vector2(110, 110)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 44)
		button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		button.pressed.connect(func() -> void:
			_highlight = i
			turn(i))
		grid.add_child(button)
		_buttons.append(button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", WoodenBoard.INK)
	column.add_child(_status)
	_close = Button.new()
	_close.text = "Give up"
	_close.focus_mode = Control.FOCUS_NONE
	_close.add_theme_font_size_override("font_size", 20)
	_close.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_close)
	column.add_child(row)
	_board.resized.connect(func() -> void:
		_board.position = (get_viewport_rect().size - _board.size) * 0.5)
