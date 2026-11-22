# building_plot.gd
# One square piece of land where a building can go. It remembers its state and
# draws a coloured outline on the ground to show that state.
#
# "class_name" gives this script a global name, so other scripts can use
# BuildingPlot and BuildingPlot.State without loading this file themselves.
@tool
class_name BuildingPlot
extends MeshInstance3D

enum State { EMPTY, OCCUPIED, BLOCKED }
enum Preview { NONE, VALID, INVALID }

const SIZE := 24.0           # Width and depth, in metres. Leaves room around the largest building.
const BORDER_WIDTH := 0.4    # Thickness of the outline, in metres.

# Green and red are used only for the placement preview.
const STATE_COLOURS := {
	State.EMPTY: Color(1.0, 1.0, 1.0, 0.45),
	State.OCCUPIED: Color(0.3, 0.65, 1.0, 0.7),
	State.BLOCKED: Color(0.15, 0.15, 0.15, 0.8),
}
const SELECTED_COLOUR := Color(1.0, 0.85, 0.1, 1.0)
const PREVIEW_COLOURS := {
	Preview.VALID: Color(0.2, 1.0, 0.3, 1.0),
	Preview.INVALID: Color(1.0, 0.15, 0.1, 1.0),
}

var plot_id := 0
var building: Node3D = null     # The building standing here, if any.
var building_info := {}         # That building's entry from BuildingManager.BUILDINGS.
var is_damaged := false         # Set by the Building accident event until repaired.
var level := 1                  # Raised by upgrades (only Warehouses can be upgraded).
var under_construction := false # True while workers are still building it (see construction_manager.gd).

# Code after "set(value):" runs whenever something changes the value, so the
# outline can never show something different from what is stored here.
var state := State.EMPTY:
	set(value):
		state = value
		_refresh_outline()

var is_selected := false:
	set(value):
		is_selected = value
		_refresh_outline()

# Set during placement mode, to show whether a building can go on this plot.
var preview := Preview.NONE:
	set(value):
		preview = value
		_refresh_outline()

# Whether the outline shows when this plot is not selected. A selected plot
# always shows its outline, so the player can see what they picked.
var show_outline := true:
	set(value):
		show_outline = value
		_refresh_outline()

var _material := StandardMaterial3D.new()


func _init() -> void:
	# Unshaded means shadows and sunlight do not change the outline's colour.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = STATE_COLOURS[state]
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _build_outline()


# Returns true if a building can be placed here.
func is_buildable() -> bool:
	return state == State.EMPTY


# Returns true if this world position is inside the plot. Height is ignored.
func contains_point(point: Vector3) -> bool:
	var half := SIZE * 0.5
	# Squares can be turned (v2 village layout), so compare in the square's own directions.
	var local := (point - position).rotated(Vector3.UP, -rotation.y)
	return absf(local.x) <= half and absf(local.z) <= half


# A point given in the square's own directions (x across, z towards its front),
# turned into a position in the world.
func to_world(offset: Vector3) -> Vector3:
	return Vector3(position.x, 0.0, position.z) + offset.rotated(Vector3.UP, rotation.y)


func _refresh_outline() -> void:
	visible = show_outline or is_selected
	if preview != Preview.NONE:
		_material.albedo_color = PREVIEW_COLOURS[preview]
	elif is_selected:
		_material.albedo_color = SELECTED_COLOUR
	else:
		_material.albedo_color = STATE_COLOURS[state]


# Builds a flat square frame from four thin strips, one for each side.
func _build_outline() -> ArrayMesh:
	var outer := SIZE * 0.5
	var inner := outer - BORDER_WIDTH
	var strips := [
		Rect2(-outer, -outer, SIZE, BORDER_WIDTH),         # Far side
		Rect2(-outer, inner, SIZE, BORDER_WIDTH),          # Near side
		Rect2(-outer, -inner, BORDER_WIDTH, inner * 2.0),  # Left side
		Rect2(inner, -inner, BORDER_WIDTH, inner * 2.0),   # Right side
	]

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for strip: Rect2 in strips:
		var first := vertices.size()
		vertices.append(Vector3(strip.position.x, 0.0, strip.position.y))
		vertices.append(Vector3(strip.end.x, 0.0, strip.position.y))
		vertices.append(Vector3(strip.end.x, 0.0, strip.end.y))
		vertices.append(Vector3(strip.position.x, 0.0, strip.end.y))
		# Godot treats clockwise triangles as facing the viewer, here looking down.
		indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	var outline := ArrayMesh.new()
	outline.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return outline
