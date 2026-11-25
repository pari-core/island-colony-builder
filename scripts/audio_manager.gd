# audio_manager.gd
# Music and sound effects. All the sounds are self-made by tools/make_sounds.py.
#
#   Music     calm music and gentle sea waves, looping, all game long
#   Win       a bright rising tune when the colony wins (the music goes quiet)
#   Lose      three slow falling notes when the colony is lost
#   Build     wooden knocks when a building is placed
#   Event     a two-note bell when a new event starts
#   Danger    a low warning when the colony starts starving or its storage fills
#   Click     a soft tick for Action, Select and Back
#
# The Volume slider in Settings sets the master volume (screens.gd).
class_name AudioManager
extends Node

const MUSIC_DB := -12.0          # The music sits quietly under the game.
const WAVES_DB := -20.0
const QUIET_MUSIC_DB := -26.0    # On the win and lose screens.
const EFFECT_DB := -4.0
const CHECK_EVERY := 0.5         # Seconds between danger checks.

const SOUNDS := {
	"win": preload("res://assets/audio/win.wav"),
	"lose": preload("res://assets/audio/lose.wav"),
	"build": preload("res://assets/audio/build.wav"),
	"event": preload("res://assets/audio/event.wav"),
	"danger": preload("res://assets/audio/danger.wav"),
	"click": preload("res://assets/audio/click.wav"),
}

@onready var _state: GameStateManager = get_node("../GameStateManager")
@onready var _buildings: BuildingManager = get_node("../BuildingManager")
@onready var _events: EventManager = get_node("../EventManager")

var _music: AudioStreamPlayer
var _waves: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _last_state := GameStateManager.State.PLAYING
var _event_count := 0
var _in_danger := false
var _check_timer := 0.0
var _played: Array[String] = []  # The latest effects played, for the tests.


func _ready() -> void:
	# Keep playing while the game is paused (stories, menus, end screens).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = _looping_player(preload("res://assets/audio/music_calm.wav"), MUSIC_DB)
	_waves = _looping_player(preload("res://assets/audio/ambience_waves.wav"), WAVES_DB)
	for i in 4:   # A few players, so effects can overlap.
		var player := AudioStreamPlayer.new()
		player.volume_db = EFFECT_DB
		add_child(player)
		_effects.append(player)
	_buildings.building_placed.connect(func(_plot: BuildingPlot) -> void: play("build"))
	_events.events_changed.connect(_on_events_changed)
	_state.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_EVERY
	var danger := _state.get_state() == GameStateManager.State.PLAYING \
			and (_state.get_starvation_seconds_left() >= 0 or _state.get_storage_seconds_left() >= 0)
	if danger and not _in_danger:
		play("danger")
	_in_danger = danger


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_action") or event.is_action_pressed("pad_select") or event.is_action_pressed("pad_back"):
		play("click")


# Plays one sound effect by name (see SOUNDS).
func play(sound: String) -> void:
	if not SOUNDS.has(sound):
		return
	_played.append(sound)
	if _played.size() > 20:
		_played.pop_front()
	var player := _effects[0]
	for p in _effects:   # Use a free player if there is one.
		if not p.playing:
			player = p
			break
	player.stream = SOUNDS[sound]
	player.play()


func get_played() -> Array[String]:
	return _played


func is_music_playing() -> bool:
	return _music.playing


func _looping_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.play)   # Start again at the end: the files loop seamlessly.
	player.play()
	return player


func _on_events_changed() -> void:
	var count := _events.get_active().size()
	if count > _event_count:
		play("event")
	_event_count = count


func _on_state_changed() -> void:
	var state := _state.get_state()
	if state == _last_state:
		return
	if state == GameStateManager.State.WON:
		play("win")
	elif state == GameStateManager.State.LOST:
		play("lose")
	# Quieter music on the end screens, back to normal when playing again.
	var ended := state == GameStateManager.State.WON or state == GameStateManager.State.LOST
	create_tween().tween_property(_music, "volume_db", QUIET_MUSIC_DB if ended else MUSIC_DB, 1.0)
	_last_state = state
