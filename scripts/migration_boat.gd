# migration_boat.gd
# The boat that brings the settlers in the Migration event ("NEW ARRIVALS").
#
# When a migration starts, the boat appears far out at sea to the east, with the
# newcomers standing on its deck. While the story is being read the game is
# paused, so the boat waits out there. Then it sails in and drops anchor off the
# eastern beach, the newcomers step ashore and walk to the town, and after a
# short wait the boat sails away and disappears.
#
# The newcomers are real workers from the start (EventManager adds them); they
# are only marked "aboard", which stops WorkerManager walking them until the
# boat lands. Nothing here is random.
#
# The model is "Swedish royal yacht Amadis" by the Finnish Heritage Agency
# (Museovirasto), CC BY 4.0. See documentation/asset_licences.md.
class_name MigrationBoat
extends Node3D

enum Stage { AWAY, SAILING_IN, LANDING, SAILING_OUT }

const MODEL := preload("res://assets/boats/swedish_royal_yacht_amadis.glb")
const MODEL_SCALE := 0.009       # The model is in centimetres; this makes it 26 m long.
const MODEL_TURN := -PI / 2.0    # Turns the model so its bow points west, at the beach.
const MODEL_SINK := 0.4          # Metres the keel's lowest point sits below the origin, after scaling.
const SEA_DISTANCE := 260.0      # Metres off the beach where the boat appears and leaves.
const ANCHOR_DISTANCE := 32.0    # Metres off the beach where it drops anchor.
const SAIL_SPEED := 22.0         # Metres per second, so sailing in takes about 10 seconds.
const LANDING_SECONDS := 4.0     # How long it stays at anchor once the newcomers are ashore.
const DECK_HEIGHT := 1.3         # Metres above the water where the newcomers stand.
const DECK_SPOTS := [Vector3(0.0, 0.0, -2.5), Vector3(0.0, 0.0, 2.5), Vector3(2.5, 0.0, 0.0), Vector3(-2.5, 0.0, 0.0)]
const BOB_HEIGHT := 0.2          # Metres the boat rises and falls on the waves.
const BOB_SPEED := 1.4           # Radians per second.
const ROLL := 0.025              # Radians the boat rolls from side to side.

var _stage := Stage.AWAY
var _model: Node3D
var _passengers: Array[Worker] = []
var _wait := 0.0
var _clock := 0.0
var _was_migrating := false
var _glide_pending := false

@onready var _events: EventManager = get_node("../EventManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _water: Node3D = get_node("../Island/Water")
@onready var _camera: Node = get_node("../Camera3D")


func _ready() -> void:
	_model = MODEL.instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.rotation.y = MODEL_TURN
	_model.position.y = MODEL_SINK
	add_child(_model)
	visible = false
	_events.events_changed.connect(_on_events_changed)


func get_stage() -> Stage:
	return _stage


func get_passengers() -> Array[Worker]:
	return _passengers


# Where the boat drops anchor, off the eastern beach.
func get_anchor() -> Vector3:
	return _events.get_beach_position() + Vector3(ANCHOR_DISTANCE, 0.0, 0.0)


# Where the boat appears and where it sails back to.
func get_sea_start() -> Vector3:
	return _events.get_beach_position() + Vector3(SEA_DISTANCE, 0.0, 0.0)


# A migration has just begun: put the boat out at sea with the newcomers aboard.
func _on_events_changed() -> void:
	var migrating := _events.is_active(EventManager.Type.MIGRATION)
	if migrating and not _was_migrating:
		_arrive()
	_was_migrating = migrating


func _arrive() -> void:
	var event: Dictionary = _events.get_active().filter(func(e: Dictionary) -> bool: return e.type == EventManager.Type.MIGRATION)[0]
	var all := _workers.get_workers()
	_passengers.clear()
	for i in range(all.size() - int(event.joined), all.size()):
		all[i].aboard = true
		_passengers.append(all[i])
	var start := get_sea_start()
	position = Vector3(start.x, _water.global_position.y, start.z)
	visible = true
	_stage = Stage.SAILING_IN
	_glide_pending = true
	_carry()


func _process(delta: float) -> void:
	if _stage == Stage.AWAY:
		return
	_clock += delta
	# Show the boat coming in, once the story has been read and the game runs.
	if _glide_pending:
		_glide_pending = false
		_camera.glide_to(get_anchor())
	match _stage:
		Stage.SAILING_IN:
			position.x = move_toward(position.x, get_anchor().x, SAIL_SPEED * delta)
			if is_equal_approx(position.x, get_anchor().x):
				_land()
		Stage.LANDING:
			_wait -= delta
			if _wait <= 0.0:
				_stage = Stage.SAILING_OUT
		Stage.SAILING_OUT:
			position.x = move_toward(position.x, get_sea_start().x, SAIL_SPEED * delta)
			if is_equal_approx(position.x, get_sea_start().x):
				_stage = Stage.AWAY
				visible = false
	# Rise and fall on the waves, and roll a little.
	position.y = _water.global_position.y + sin(_clock * BOB_SPEED) * BOB_HEIGHT
	rotation.x = sin(_clock * BOB_SPEED * 0.8) * ROLL
	_carry()


# Keeps the newcomers standing on the deck while the boat moves.
func _carry() -> void:
	for i in _passengers.size():
		var worker := _passengers[i]
		if is_instance_valid(worker.model) and worker.aboard:
			worker.model.position = position + DECK_SPOTS[i % DECK_SPOTS.size()] + Vector3.UP * DECK_HEIGHT
			worker.model.rotation.y = -PI / 2.0   # Facing the island.


# At anchor: the newcomers step onto the beach and walk to the town.
func _land() -> void:
	var beach := _events.get_beach_position()
	for i in _passengers.size():
		var worker := _passengers[i]
		if not is_instance_valid(worker.model):
			continue
		var spot := beach + Vector3(-2.0, 0.0, (i - (_passengers.size() - 1) * 0.5) * 2.0)
		worker.model.position = Vector3(spot.x, _terrain.get_height_at(spot.x, spot.z), spot.z)
		worker.aboard = false
	_passengers.clear()
	_workers.workers_changed.emit()
	_stage = Stage.LANDING
	_wait = LANDING_SECONDS
