# story_box.gd
# A small wooden board at the bottom of the screen that tells a story, one page
# at a time. The words appear a few at a time, like someone telling it.
#
# The game waits while a story is open. Space, Enter or the Continue button
# first finishes the page that is still appearing, then turns to the next page.
# After the last page the board closes and the game carries on.
#
# Any script can tell a story: get_node("../UI/StoryBox").tell(title, pages).
class_name StoryBox
extends Control

signal story_finished

const LETTERS_PER_SECOND := 140.0   # Quick, so stories do not keep the player waiting.
const TEXT_WIDTH := 640.0        # Pixels. The board is this wide plus the picture and edges.
const BOTTOM_GAP := 46.0         # Pixels between the board and the bottom of the screen.
const SUN_COLOUR := Color(1.0, 0.78, 0.25)

# Tests that are not about stories switch them off here, so nothing pauses
# them. It is static, so it covers every scene a test loads.
static var enabled := true
# Stories are cut down to one short card (see shorten()). Tests switch this off
# to check the full text.
static var short := true
const MAX_LINES := 2             # Lines kept under each heading.
const SHORT_PAGE := 120          # A page this short is kept whole.

# Stories waiting their turn. Each is { "title": String, "pages": Array, "icon": String }.
var _queue: Array[Dictionary] = []
var _title := ""
var _pages: Array = []
var _page := 0
var _shown := 0.0                # Letters of this page shown so far.
var _icon := "sun"               # Which small picture is drawn beside the text.
var _picture: Control
var _board: WoodenBoard
var _title_label: Label
var _text_label: Label
var _page_label: Label
var _button: Button


func _ready() -> void:
	# Keep working while the game is paused: the story is what pauses it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _process(delta: float) -> void:
	_board.visible = is_open()
	if not is_open():
		return
	# Held every frame, so a menu closing behind the story cannot unpause the game.
	get_tree().paused = true
	_shown = minf(_shown + LETTERS_PER_SECOND * delta, _text_label.text.length())
	_text_label.visible_characters = int(_shown)
	_button.text = "Continue" if _page < _pages.size() - 1 or not _queue.is_empty() else "Close"
	_board.reset_size()
	_board.position = Vector2((size.x - _board.size.x) * 0.5, size.y - _board.size.y - BOTTOM_GAP)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("pad_action") or event.is_action_pressed("event_respond"):
		advance()
	# Every key is used up, so nothing behind the story reacts to it.
	if event is InputEventKey:
		get_viewport().set_input_as_handled()


# Tells a story. If one is already being told, this one waits its turn.
# icon is the small picture beside the text: "sun", "cross", "star", "coin", "boat", "hammer" or "cloud".
func tell(title: String, pages: Array, icon := "sun") -> void:
	if pages.is_empty() or not enabled:
		return
	_queue.append({ "title": title, "pages": shorten(pages) if short else pages, "icon": icon })
	if not is_open():
		_next_story()


# The short version of a story (see "short" above).
static func shorten(pages: Array) -> Array:
	# v3 (team request, 2026-11-23: "reduce the message content when an event
	# comes"): ONE card. It holds only the pages that tell the player something
	# (a heading in capitals, such as "DISEASE OUTBREAK!"), at most the last two,
	# each cut to its heading and first MAX_LINES lines. A story with no such page
	# keeps just the first sentence of its last page.
	var headed: Array[String] = []
	for page in pages:
		var lines := str(page).split("\n")
		if lines[0] == lines[0].to_upper() and lines[0].length() > 3:
			headed.append("\n".join(lines.slice(0, MAX_LINES + 1)))
	if not headed.is_empty():
		return ["\n\n".join(headed.slice(maxi(headed.size() - 2, 0)))]
	if pages.is_empty():
		return pages
	var last := str(pages[-1])
	var stop := last.find(". ")
	if last.length() <= SHORT_PAGE or stop < 0:
		return [last]
	return [last.substr(0, stop + 1)]


func is_open() -> bool:
	return not _pages.is_empty()


func get_title() -> String:
	return _title


# The whole text of the page being shown, or "" if no story is open.
func get_page_text() -> String:
	return str(_pages[_page]) if is_open() else ""


func get_page_number() -> int:
	return _page + 1 if is_open() else 0


func get_page_count() -> int:
	return _pages.size()


# True while the words of this page are still appearing.
func is_typing() -> bool:
	return is_open() and int(_shown) < _text_label.text.length()


# Continue: finishes the page that is appearing, or turns to the next one.
func advance() -> void:
	if not is_open():
		return
	if is_typing():
		_shown = _text_label.text.length()
		_text_label.visible_characters = -1
	elif _page < _pages.size() - 1:
		_show_page(_page + 1)
	else:
		_next_story()


# Closes every story at once. The tests use this.
func skip() -> void:
	_queue.clear()
	if is_open():
		_next_story()


func _next_story() -> void:
	if _queue.is_empty():
		_pages = []
		_board.visible = false
		get_tree().paused = false
		story_finished.emit()
		return
	var story: Dictionary = _queue.pop_front()
	_title = story.title
	_pages = story.pages
	_icon = story.icon
	_picture.queue_redraw()
	_title_label.text = _title
	get_tree().paused = true
	_show_page(0)


func _show_page(page: int) -> void:
	_page = page
	_shown = 0.0
	_text_label.text = str(_pages[page])
	_text_label.visible_characters = 0
	_page_label.text = "%d / %d" % [page + 1, _pages.size()]


# Builds the board: a title, a small sun beside the text, and a Continue button.
func _build() -> void:
	_board = WoodenBoard.new()
	_board.name = "Board"
	_board.visible = false
	add_child(_board)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_board.add_child(column)

	_title_label = _label(30, WoodenBoard.TITLE_INK)
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	column.add_child(row)
	var sun := Control.new()
	sun.custom_minimum_size = Vector2(84, 84)
	sun.draw.connect(_draw_icon.bind(sun))
	row.add_child(sun)
	_picture = sun
	_text_label = _label(22, WoodenBoard.INK)
	_text_label.name = "Text"
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(TEXT_WIDTH, 96)
	row.add_child(_text_label)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 18)
	column.add_child(bottom)
	_page_label = _label(18, WoodenBoard.INK)
	bottom.add_child(_page_label)
	_button = Button.new()
	_button.name = "Continue"
	_button.text = "Continue"
	_button.focus_mode = Control.FOCUS_NONE   # Space is read above, not by the button.
	_button.add_theme_font_size_override("font_size", 20)
	# A green button, like the picture's "Great!" and "Continue".
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.3, 0.62, 0.22) if state == "normal" else Color(0.36, 0.7, 0.27) if state == "hover" else Color(0.24, 0.5, 0.17)
		box.set_corner_radius_all(8)
		box.border_color = Color(0.17, 0.36, 0.1)
		box.set_border_width_all(2)
		box.content_margin_left = 26.0
		box.content_margin_right = 26.0
		box.content_margin_top = 6.0
		box.content_margin_bottom = 6.0
		_button.add_theme_stylebox_override(state, box)
	_button.add_theme_color_override("font_color", Color.WHITE)
	_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_button.pressed.connect(advance)
	bottom.add_child(_button)


func get_icon() -> String:
	return _icon


# The small picture beside the text, drawn from simple shapes.
func _draw_icon(on: Control) -> void:
	var centre := on.size * 0.5
	match _icon:
		"cross":   # A red cross on a white disc: sickness and medicine.
			on.draw_circle(centre, 34.0, Color(0.97, 0.95, 0.9))
			on.draw_rect(Rect2(centre - Vector2(8, 24), Vector2(16, 48)), Color(0.85, 0.12, 0.1))
			on.draw_rect(Rect2(centre - Vector2(24, 8), Vector2(48, 16)), Color(0.85, 0.12, 0.1))
			return
		"coin":    # A gold coin: trade.
			on.draw_circle(centre, 32.0, Color(0.75, 0.55, 0.12))
			on.draw_circle(centre, 27.0, Color(1.0, 0.82, 0.3))
			on.draw_circle(centre, 16.0, Color(0.9, 0.68, 0.18))
			return
		"star":    # A four-pointed sparkle: a lucky find.
			var points := PackedVector2Array()
			for i in 8:
				points.append(centre + Vector2.UP.rotated(i * TAU / 8.0) * (38.0 if i % 2 == 0 else 11.0))
			on.draw_colored_polygon(points, Color(1.0, 0.88, 0.4))
			on.draw_circle(centre, 7.0, Color(1.0, 0.98, 0.85))
			return
		"boat":    # A small sailing boat: people arriving by sea.
			on.draw_colored_polygon(PackedVector2Array([centre + Vector2(-34, 12), centre + Vector2(34, 12), centre + Vector2(22, 30), centre + Vector2(-22, 30)]), Color(0.42, 0.26, 0.13))
			on.draw_line(centre + Vector2(0, 12), centre + Vector2(0, -34), Color(0.3, 0.18, 0.08), 4.0)
			on.draw_colored_polygon(PackedVector2Array([centre + Vector2(4, -32), centre + Vector2(30, 6), centre + Vector2(4, 6)]), Color(0.97, 0.95, 0.9))
			on.draw_colored_polygon(PackedVector2Array([centre + Vector2(-4, -24), centre + Vector2(-24, 6), centre + Vector2(-4, 6)]), Color(0.9, 0.87, 0.8))
			return
		"cloud":   # A grey storm cloud with rain.
			on.draw_circle(centre + Vector2(-12, -6), 16.0, Color(0.55, 0.58, 0.64))
			on.draw_circle(centre + Vector2(10, -10), 20.0, Color(0.6, 0.63, 0.69))
			on.draw_rect(Rect2(centre + Vector2(-28, -6), Vector2(56, 16)), Color(0.55, 0.58, 0.64))
			for i in 4:
				var x := -18.0 + i * 12.0
				on.draw_line(centre + Vector2(x, 16), centre + Vector2(x - 5, 32), Color(0.3, 0.5, 0.85), 3.0, true)
			return
		"hammer":  # A hammer on a brick: a building accident and its repair.
			on.draw_circle(centre, 34.0, Color(0.97, 0.95, 0.9))
			on.draw_rect(Rect2(centre + Vector2(-22, 10), Vector2(44, 16)), Color(0.72, 0.36, 0.24))
			on.draw_line(centre + Vector2(-14, 4), centre + Vector2(14, -22), Color(0.45, 0.28, 0.12), 6.0, true)
			on.draw_colored_polygon(PackedVector2Array([centre + Vector2(4, -34), centre + Vector2(24, -14), centre + Vector2(18, -8), centre + Vector2(-2, -28)]), Color(0.4, 0.42, 0.46))
			return
	# Otherwise a burning sun: the picture for a drought.
	for i in 12:
		var direction := Vector2.RIGHT.rotated(i * TAU / 12.0)
		on.draw_line(centre + direction * 25.0, centre + direction * (40.0 if i % 2 == 0 else 34.0), SUN_COLOUR, 4.0, true)
	on.draw_circle(centre, 20.0, SUN_COLOUR)
	on.draw_circle(centre, 14.0, Color(1.0, 0.9, 0.55))


func _label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	if colour.v > 0.7:   # Only light text (the title on the ribbon) needs a dark edge.
		label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.03))
		label.add_theme_constant_override("outline_size", 8)
	return label
