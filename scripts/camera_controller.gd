# camera_controller.gd
# Lets the player move, rotate and zoom the camera around the island.
#
# How it works: the camera orbits an invisible "focus" point on the ground.
#   - Moving slides the focus point across the map.
#   - Rotating swings the camera around the focus point.
#   - Zooming changes how far the camera is from the focus point.
# Each frame the camera's position is worked out again from those three values.
#
# Keys are read through named actions (camera_forward and so on), which are set
# in Project > Project Settings > Input Map. The script never checks a specific
# key, so the ESP32 controller can later trigger these same actions.
extends Camera3D

# All distances are in metres.
const MAX_FOCUS_RADIUS := 450.0  # How far the view can roam from the town: out past the
                                 # forests, but short of the edge of the distant land.
const MIN_DISTANCE := 15.0       # Closest zoom, near enough to see people clearly.
const MAX_DISTANCE := 430.0      # Furthest zoom. Keeps the island a sensible size.
const ZOOM_STEP := 0.9           # Each wheel notch multiplies the distance by this.
const ZOOM_SMOOTHING := 5.0      # Higher = the zoom catches up with its target faster.
# v2 camera, like a village builder: zoomed in, the view tilts towards the
# horizon to show buildings from the side; zoomed out, it looks more steeply
# down to show the map. Zooming also moves towards the point under the mouse.
const PITCH_NEAR := 24.0         # Degrees looking down when fully zoomed in.
const PITCH_FAR := 62.0          # Degrees looking down when fully zoomed out.
const TRACKPAD_ZOOM_SPEED := 0.1 # How strongly a two-finger swipe zooms.
const MIN_CLEARANCE := 5.0       # The camera stays at least this far above the ground.
const GROUND_SMOOTHING := 4.0    # Higher = the view follows hills more quickly.
const GLIDE_SMOOTHING := 6.0     # Higher = the view reaches a chosen plot faster.
const GLIDE_DISTANCE := 140.0    # Gliding to a plot zooms in to at least this close.

@export var move_speed := 0.35   # Fraction of the current distance moved per second.
@export var rotate_speed := 1.5  # Radians per second.

# These starting values frame the whole island.
var _focus := Vector3(0.0, 0.0, 6.0)
var _yaw := deg_to_rad(-45.0)    # Which side of the focus point the camera is on.
var _pitch := deg_to_rad(45.0)   # How steeply the camera looks down; follows the zoom (see _pitch_for).
# v2: the view starts close to the town, like the village builder the team chose.
var _distance := 150.0
var _target_distance := 150.0    # The zoom level that _distance glides towards.
var _ground_height := 2.2        # Height of the ground under the focus point, smoothed.
var _glide_target = null         # A point the focus is gliding to, or null.

# While true, the controller's arrow buttons do not move the camera, because a
# menu or the build cursor is using them. W, A, S and D still work.
var pad_locked := false

# Island comes after Camera3D in the scene, but it already exists when this runs.
@onready var _terrain: Node = get_node("../Island/Terrain")


func _ready() -> void:
	_update_transform()


# _process runs every frame. delta is the time since the last frame, in seconds.
# Multiplying by delta keeps the speed the same on fast and slow computers.
func _process(delta: float) -> void:
	# Move. Speed grows with distance so it feels the same at every zoom level.
	var input := Input.get_vector("camera_left", "camera_right", "camera_forward", "camera_back")
	if not pad_locked:
		input += Input.get_vector("pad_left", "pad_right", "pad_up", "pad_down")
		input = input.limit_length(1.0)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	_focus += (right * input.x - forward * input.y) * move_speed * _distance * delta
	# Glide to a requested point, unless the player is steering.
	if input != Vector2.ZERO:
		_glide_target = null
	elif _glide_target != null:
		_focus = _focus.lerp(_glide_target, 1.0 - exp(-GLIDE_SMOOTHING * delta))
		if _focus.distance_to(_glide_target) < 0.05:
			_glide_target = null
	_focus = _focus.limit_length(MAX_FOCUS_RADIUS)

	# Rotate.
	_yaw += Input.get_axis("camera_rotate_left", "camera_rotate_right") * rotate_speed * delta

	# Zoom. Gliding towards the target looks smoother than jumping to it.
	_distance = lerpf(_distance, _target_distance, 1.0 - exp(-ZOOM_SMOOTHING * delta))

	# Follow the ground height, so the view stays centred when crossing the hill.
	var ground: float = maxf(_terrain.get_height_at(_focus.x, _focus.z), 0.0)
	_ground_height = lerpf(_ground_height, ground, 1.0 - exp(-GROUND_SMOOTHING * delta))

	_update_transform()


# _unhandled_input only receives input that the user interface did not use, so
# scrolling over a future menu will not zoom the camera as well.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_zoom_by(ZOOM_STEP, _mouse_point(event))
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom_by(1.0 / ZOOM_STEP, _mouse_point(event))
	# A Mac trackpad sends gestures, not mouse wheel events, so these are separate.
	elif event is InputEventPanGesture:
		_zoom_by(1.0 + event.delta.y * TRACKPAD_ZOOM_SPEED, _mouse_point(event))
	elif event is InputEventMagnifyGesture:
		_zoom_by(1.0 / event.factor, _mouse_point(event))


# The point on the ground under the mouse, or null for keys and buttons.
func _mouse_point(event: InputEvent):
	if not (event is InputEventMouse or event is InputEventGesture):
		return null
	var ground := Plane(Vector3.UP, _ground_height)
	var hit = ground.intersects_ray(project_ray_origin(event.position), project_ray_normal(event.position))
	return null if hit == null else Vector3(hit.x, 0.0, hit.z)


# The point on the ground that the camera is looking at.
func get_focus() -> Vector3:
	return _focus


func get_yaw() -> float:
	return _yaw


# Smoothly centres the view on a point, zooming in if the view is very far out.
# The controller uses this to follow its cursor.
func glide_to(point: Vector3) -> void:
	_glide_target = Vector3(point.x, 0.0, point.z).limit_length(MAX_FOCUS_RADIUS)
	_target_distance = minf(_target_distance, GLIDE_DISTANCE)


# Turns the view by an angle in radians. Works while the game is paused.
func rotate_view(angle: float) -> void:
	_yaw += angle
	_update_transform()


# Zooms by one step: in if steps is negative, out if positive.
func zoom_steps(steps: int) -> void:
	_zoom_by(pow(1.0 / ZOOM_STEP, steps))


# Zooms by a factor. Given a point (under the mouse), the view also slides
# towards it when zooming in, and away when zooming out, so that point stays
# under the mouse, as in map and builder games.
func _zoom_by(factor: float, towards = null) -> void:
	var before := _target_distance
	_target_distance = clampf(_target_distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	if towards != null:
		var share := 1.0 - _target_distance / before
		_glide_target = null
		_focus = (_focus + ((towards as Vector3) - _focus) * share).limit_length(MAX_FOCUS_RADIUS)


# How steeply the camera looks down at this distance.
func _pitch_for(distance: float) -> float:
	var t := sqrt(clampf(inverse_lerp(MIN_DISTANCE, MAX_DISTANCE, distance), 0.0, 1.0))
	return deg_to_rad(lerpf(PITCH_NEAR, PITCH_FAR, t))


# Places the camera from the focus point, yaw, pitch and distance, then aims it.
func _update_transform() -> void:
	_pitch = _pitch_for(_distance)
	var direction := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	)
	var target := _focus + Vector3.UP * _ground_height
	var new_position := target + direction * _distance
	# Rise if needed, so the camera never ends up inside the hill.
	var ground_below: float = _terrain.get_height_at(new_position.x, new_position.z)
	new_position.y = maxf(new_position.y, ground_below + MIN_CLEARANCE)
	position = new_position
	look_at(target)
