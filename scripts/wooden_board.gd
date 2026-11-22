# wooden_board.gd
# The board every menu and story is shown on: since v2, a sheet of parchment
# in a thin wooden frame, with a wooden ribbon for the title (it was planks).
# It is drawn by this script with shapes and colours, so it needs no picture
# file and fits whatever text is put on it.
#
# Anything added as a child (the menu text) is drawn on top of the wood.
class_name WoodenBoard
extends PanelContainer

const PLANK_HEIGHT := 58.0       # Roughly how tall each plank is, in pixels.
const FRAME := 10.0              # Width of the dark frame around the planks.
const PLANK_COLOURS := [Color(0.55, 0.36, 0.2), Color(0.5, 0.32, 0.17), Color(0.58, 0.39, 0.22), Color(0.47, 0.3, 0.16)]
const FRAME_COLOUR := Color(0.24, 0.14, 0.07)
const SEAM_COLOUR := Color(0.2, 0.11, 0.05, 0.9)
const GRAIN_COLOUR := Color(0.25, 0.14, 0.06, 0.28)
const NAIL_COLOUR := Color(0.75, 0.73, 0.68)
const SHADOW_COLOUR := Color(0, 0, 0, 0.45)
const PARCHMENT := Color(0.95, 0.89, 0.76)
const PARCHMENT_EDGE := Color(0.55, 0.38, 0.2)
const RIBBON_HEIGHT := 56.0      # The title sits on this wooden band.
# Text colours for the parchment.
const INK := Color(0.29, 0.18, 0.09)
const TITLE_INK := Color(1.0, 0.93, 0.78)
const LEAF := Color(0.42, 0.6, 0.3)
const LEAF_DARK := Color(0.27, 0.42, 0.2)

# Small leaves in the corners, like the team's storybook design.
var leaves := true


func _ready() -> void:
	# Space between the edge of the board and the text.
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 48.0
	padding.content_margin_right = 48.0
	padding.content_margin_top = 18.0
	padding.content_margin_bottom = 30.0
	add_theme_stylebox_override("panel", padding)
	resized.connect(queue_redraw)


func _draw() -> void:
	# v2 (2026-11-23, from the team's picture): a sheet of parchment in a thin
	# wooden frame, with a wooden ribbon across the top for the title.
	var random := RandomNumberGenerator.new()
	random.seed = 7
	draw_rect(Rect2(Vector2(8, 10), size), SHADOW_COLOUR)
	draw_rect(Rect2(Vector2.ZERO, size), FRAME_COLOUR)
	var inner := Rect2(Vector2(FRAME, FRAME), size - Vector2(FRAME, FRAME) * 2.0)
	draw_rect(inner, PARCHMENT)
	# Darker, uneven edges, as old paper has.
	for i in 6:
		draw_rect(inner.grow(-i * 5.0), Color(PARCHMENT_EDGE, 0.07), false, 5.0)
	for spot in 26:
		var p := inner.position + Vector2(random.randf() * inner.size.x, random.randf() * inner.size.y)
		draw_circle(p, random.randf_range(6.0, 22.0), Color(PARCHMENT_EDGE, 0.05))
	# The wooden ribbon behind the title.
	var ribbon := Rect2(inner.position.x + 30.0, inner.position.y + 6.0, inner.size.x - 60.0, RIBBON_HEIGHT)
	draw_rect(Rect2(ribbon.position + Vector2(3, 4), ribbon.size), Color(0, 0, 0, 0.3))
	draw_rect(ribbon, PLANK_COLOURS[0])
	for line in 6:
		var y := ribbon.position.y + random.randf_range(6.0, ribbon.size.y - 6.0)
		var points := PackedVector2Array()
		for s in 13:
			points.append(Vector2(ribbon.position.x + ribbon.size.x * s / 12.0, y + random.randf_range(-1.5, 1.5)))
		draw_polyline(points, GRAIN_COLOUR, 1.5, true)
	draw_rect(ribbon, FRAME_COLOUR, false, 3.0)
	# Leaves twining over the top-left and bottom-right corners.
	if leaves:
		for corner in [[Vector2(4, 4), 0.6], [Vector2(size.x - 4, size.y - 4), PI + 0.6]]:
			for n in 4:
				var angle: float = corner[1] + (n - 1.5) * 0.45
				var base: Vector2 = corner[0]
				var tip := base + Vector2.from_angle(angle) * (26.0 + n * 4.0)
				var side := Vector2.from_angle(angle + PI / 2.0) * 7.0
				draw_colored_polygon(PackedVector2Array([base, (base + tip) * 0.5 + side, tip, (base + tip) * 0.5 - side]), LEAF if n % 2 == 0 else LEAF_DARK)
				draw_line(base, tip, LEAF_DARK, 1.5, true)
	# Nails.
	var inset := FRAME + 12.0
	for corner in [Vector2(inset, size.y - inset), Vector2(size.x - inset, size.y - inset)]:
		draw_circle(corner + Vector2(1, 2), 5.0, Color(0, 0, 0, 0.35))
		draw_circle(corner, 4.0, NAIL_COLOUR)
