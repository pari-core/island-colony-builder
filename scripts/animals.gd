# animals.gd
# Farm animals in the fields around the town: cows and horses that wander and
# graze, and small flocks of sheep and pigs that stand about and now and then
# hop to a new spot. They are only for looks and have no effect on the game.
#
# The models are Quaternius' "LowPoly Animated Farm Animal Pack" (CC0). Cows and
# horses have walking animations; sheep and pigs only have "idle" and "jump", so
# they hop when they move.
#
# Every animal has a home spot in a field and only wanders a short way from it.
# A fixed random seed puts them in the same places every game.
class_name Animals
extends Node3D

const HERDS := [
	# kind, home (x, z), how many
	["Cow", Vector2(-128.0, -38.0), 3],
	["Cow", Vector2(70.0, -104.0), 2],
	["Horse", Vector2(-120.0, 100.0), 2],
	["Sheep", Vector2(-86.0, -104.0), 4],
	["Sheep", Vector2(118.0, -46.0), 3],
	["Pig", Vector2(-104.0, 52.0), 3],
]
const MODELS := {
	"Cow": preload("res://assets/animals/Cow.fbx"),
	"Horse": preload("res://assets/animals/Horse.fbx"),
	"Sheep": preload("res://assets/animals/Sheep.fbx"),
	"Pig": preload("res://assets/animals/Pig.fbx"),
}
const SCALE := { "Cow": 0.38, "Horse": 0.4, "Sheep": 0.4, "Pig": 0.34 }
const ROAM := 14.0               # Metres an animal wanders from its home.
const WALK_SPEED := 1.6          # Metres per second for cows and horses.
const HOP_SPEED := 2.2           # Sheep and pigs move in short hops.
const REST_MIN := 3.0            # Seconds spent grazing between walks.
const REST_MAX := 9.0

var _animals: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

@onready var _terrain: Node = get_node("../Island/Terrain")


func _ready() -> void:
	_rng.seed = 77
	for herd: Array in HERDS:
		for i in int(herd[2]):
			_add(herd[0], herd[1])


func get_animals() -> Array[Dictionary]:
	return _animals


func _add(kind: String, home: Vector2) -> void:
	var body := Node3D.new()            # Turns to face where the animal goes.
	add_child(body)
	var model: Node3D = MODELS[kind].instantiate()
	model.scale = Vector3.ONE * SCALE[kind]
	body.add_child(model)
	var spot := _free_spot(home)
	body.position = _ground(spot)
	body.rotation.y = _rng.randf_range(0.0, TAU)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var animal := { "kind": kind, "home": home, "body": body, "player": player, "target": spot, "rest": _rng.randf_range(0.0, REST_MAX) }
	_play(animal, "Idle")
	_animals.append(animal)


func _process(delta: float) -> void:
	for animal in _animals:
		var body: Node3D = animal.body
		var here := Vector2(body.position.x, body.position.z)
		if animal.rest > 0.0:
			animal.rest -= delta
			if animal.rest <= 0.0:
				animal.target = _free_spot(animal.home)
				_play(animal, _move_animation(animal.kind))
			continue
		var target: Vector2 = animal.target
		var speed := WALK_SPEED if _move_animation(animal.kind) != "Jump" else HOP_SPEED
		var next := here.move_toward(target, speed * delta)
		if next != here:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(target.x - here.x, target.y - here.y), minf(delta * 4.0, 1.0))
		body.position = _ground(next)
		if next == target:
			animal.rest = _rng.randf_range(REST_MIN, REST_MAX)
			_play(animal, "Idle")


func _move_animation(kind: String) -> String:
	return "WalkSlow" if kind in ["Cow", "Horse"] else "Jump"


func _play(animal: Dictionary, name: String) -> void:
	var player: AnimationPlayer = animal.player
	if player == null:
		return
	var full := "Armature|" + name
	if not player.has_animation(full):
		return
	player.get_animation(full).loop_mode = Animation.LOOP_LINEAR
	player.play(full, 0.3)


# A spot near home on dry, flat land.
func _free_spot(home: Vector2) -> Vector2:
	for attempt in 20:
		var spot := home + Vector2(_rng.randf_range(-ROAM, ROAM), _rng.randf_range(-ROAM, ROAM))
		if _terrain.get_height_at(spot.x, spot.y) > _terrain.LAND_HEIGHT - 0.2:
			return spot
	return home


func _ground(spot: Vector2) -> Vector3:
	return Vector3(spot.x, _terrain.get_height_at(spot.x, spot.y), spot.y)
