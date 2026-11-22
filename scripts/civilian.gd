# civilian.gd
# One civilian: a person who lives in the colony. They wander around their home,
# playing the walking animation while they move and the idle animation while they
# stand. Civilians with a House go inside through the front door every few walks,
# stay in for a while, then come back out. Civilians without a House just wander.
#
# Their wandering uses their own random number generator with a fixed seed, so a
# civilian always takes the same route each game.
#
# Routes go around every building, including their own House (see path_grid.gd).
class_name Civilian
extends Node3D

enum Mode { WANDER, GOING_IN, INSIDE }

# People are drawn 1.5 times real size (2.7 m tall), so they are easy to see from
# the strategy camera. They still fit under the House door (3.3 m).
const BODY_SCALE := 1.5
const WALK_SPEED := 2.4          # Metres per second: a real walking pace (1.6) times BODY_SCALE,
                                 # so the feet match the ground instead of sliding.
const WANDER_MIN := 13.0         # Closest a wander spot can be to the home's centre.
const WANDER_MAX := 18.0         # Furthest it can be.
const PAUSE_MIN := 3.0           # Seconds standing still between walks.
const PAUSE_MAX := 8.0
const WALKS_MIN := 2             # Walks around the House before going in.
const WALKS_MAX := 4
const INSIDE_MIN := 15.0         # Seconds spent inside the House.
const INSIDE_MAX := 30.0
const WALK_ANIMATION := "walk"
const IDLE_ANIMATION := "idle"

# Where a civilian goes in and out of their House: just outside the middle of
# its front (+z) side. (v2: the KayKit house is 13 m wide and 12.8 m deep.)
const DOOR := Vector3(0.0, 0.0, 7.2)

var home := Vector3.ZERO         # Where this civilian wanders around.
var home_turn := 0.0             # The House's rotation, in radians.
var has_house := false           # False while homeless: no door to go into.
var _mode := Mode.WANDER
var _path: Array[Vector3] = []   # Points still to walk through, in order.
var _pause := 0.0
var _walks_left := 0
var _inside_time := 0.0
var _rng := RandomNumberGenerator.new()
var _player: AnimationPlayer
var _terrain: Node
var _paths: PathGrid
var _path_version := -1          # PathGrid.version when _path was worked out.


# Builds the civilian from a walking model, and borrows the idle animation from a
# second file of the same character. Both come from Mixamo with the same skeleton,
# so the idle animation fits the walking model.
func setup(walking_scene: PackedScene, idle_animation: Animation, terrain: Node, paths: PathGrid, seed_value: int) -> void:
	_terrain = terrain
	_paths = paths
	_rng.seed = seed_value
	var body: Node3D = walking_scene.instantiate()
	body.scale = Vector3.ONE * BODY_SCALE
	add_child(body)
	_player = _find_player(body)
	var library := _player.get_animation_library("")
	var walk: Animation = library.get_animation(library.get_animation_list()[0]).duplicate()
	walk.loop_mode = Animation.LOOP_LINEAR
	library.add_animation(WALK_ANIMATION, walk)
	var idle := idle_animation.duplicate()
	idle.loop_mode = Animation.LOOP_LINEAR
	library.add_animation(IDLE_ANIMATION, idle)
	_pause = _rng.randf_range(0.0, PAUSE_MAX)
	_walks_left = _rng.randi_range(1, WALKS_MAX)
	_player.play(IDLE_ANIMATION)


func is_walking() -> bool:
	return _player.current_animation == WALK_ANIMATION and _mode != Mode.INSIDE


func is_inside() -> bool:
	return _mode == Mode.INSIDE


# Where the civilian is, or the door they will come out of if they are inside.
func get_ground_position() -> Vector3:
	return _door_position() if is_inside() else position


# Gives the civilian a new home. Anyone inside the old House comes out of its door
# first, and anyone on the way to the old door turns round.
# turn is the House's rotation (v2 village layout), so the door turns with it.
func set_home(new_home: Vector3, is_house: bool, turn := 0.0) -> void:
	if new_home.is_equal_approx(home) and is_house == has_house:
		return
	if _mode == Mode.INSIDE:
		_appear_at(_door_position())
	home = new_home
	home_turn = turn
	has_house = is_house
	_mode = Mode.WANDER
	if _pause <= 0.0:
		_start_wander_walk()


func _process(delta: float) -> void:
	if _mode == Mode.INSIDE:
		_inside_time -= delta
		if _inside_time <= 0.0:
			_come_out()
		return
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0:
			_start_next_walk()
		return
	if _path.is_empty():
		return
	# A building went up since this route was worked out: find a new one.
	if _path_version != _paths.version:
		_walk_to(_path.back())
	var here := Vector2(position.x, position.z)
	var goal := Vector2(_path[0].x, _path[0].z)
	if here.distance_to(goal) < 0.05:
		_path.pop_front()
		if _path.is_empty():
			_arrive()
		return
	var direction := goal - here
	rotation.y = atan2(direction.x, direction.y)
	here = here.move_toward(goal, WALK_SPEED * delta)
	position = Vector3(here.x, _terrain.get_height_at(here.x, here.y), here.y)


# Called when the last point of a walk is reached.
func _arrive() -> void:
	if _mode == Mode.GOING_IN:
		_mode = Mode.INSIDE
		_inside_time = _rng.randf_range(INSIDE_MIN, INSIDE_MAX)
		visible = false
		_player.pause()   # No need to animate someone nobody can see.
	else:
		_pause = _rng.randf_range(PAUSE_MIN, PAUSE_MAX)
		_player.play(IDLE_ANIMATION, 0.3)


# After a pause: either head home through the door, or walk to another spot.
func _start_next_walk() -> void:
	if has_house and _walks_left <= 0:
		_mode = Mode.GOING_IN
		_walk_to(_door_position())
	else:
		_walks_left -= 1
		_start_wander_walk()


func _start_wander_walk() -> void:
	_walk_to(_pick_spot())


func _walk_to(goal: Vector3) -> void:
	_path = _paths.find_path(position, goal)
	_path_version = _paths.version
	_player.play(WALK_ANIMATION, 0.3)


# A spot in a ring around the home, outside any building. Homeless civilians
# wander in the centre, where a spot can land on a building, so it tries again.
func _pick_spot() -> Vector3:
	var spot := home
	for attempt in 10:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(WANDER_MIN, WANDER_MAX)
		spot = home + Vector3(cos(angle), 0.0, sin(angle)) * distance
		if not _paths.is_blocked(spot):
			break
	return spot


# Steps out of the door and walks on to a wander spot.
func _come_out() -> void:
	_appear_at(_door_position())
	_mode = Mode.WANDER
	_walks_left = _rng.randi_range(WALKS_MIN, WALKS_MAX)
	_start_wander_walk()


func _appear_at(point: Vector3) -> void:
	position = point
	visible = true


func _door_position() -> Vector3:
	var door := home + DOOR.rotated(Vector3.UP, home_turn)
	return Vector3(door.x, _terrain.get_height_at(door.x, door.z), door.z)


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
