# controller_link.gd
# Connects the game to the team's ESP32 controller over the USB cable, using the
# GdSerial plugin (addons/gdserial, MIT licence).
#
# The ESP32 (firmware/island_controller) sends one line of text per input:
#   "HELLO ISLAND 1"  every 2 s until the game answers "HI"
#   "BTN UP 1"        UP pressed (0 = released). Names: UP DOWN LEFT RIGHT
#                     BUILD ACTION SELECT MENU BACK
#   "ENC 1" / "ENC -1"  the encoder turned one click right / left
# Each line becomes the same input action the keyboard fires (see
# controller_menu.gd), so the controller and keyboard always do the same thing.
#
# The game sends back:
#   "LEDS gyrb"  one digit per LED (0 off, 1 on, 2 blinking):
#                green  = the colony is fine (blinks when the game is won)
#                yellow = an event is on (blinks while it waits for an answer)
#                red    = danger: starving or storage full (blinks when lost)
#                blue   = placing a building
#   "BEEP n"     1 a building was placed, 2 a new event, 3 the game ended
#   "HAPPY n"    happiness 0-100, shown on the controller's TFT as a bar
#
# Finding the board: every few seconds, while not connected, the link opens the
# next USB serial port and waits for "HELLO ISLAND". Bluetooth and debug ports
# are skipped. If the board is unplugged, the link starts looking again.
class_name ControllerLink
extends Node

signal connected(port: String)
signal disconnected

const BAUD := 115200
const SEARCH_EVERY := 1.0        # Seconds between looks for a new port.
const HELLO_WAIT := 4.0          # Seconds to wait for HELLO on a port (opening resets the ESP32).
const LED_EVERY := 0.25          # Seconds between LED updates.
const BUTTON_ACTIONS := {
	"UP": "pad_up", "DOWN": "pad_down", "LEFT": "pad_left", "RIGHT": "pad_right",
	"BUILD": "build", "ACTION": "pad_action", "SELECT": "pad_select",
	"MENU": "pad_menu", "BACK": "pad_back",
}
# Port names that can be an ESP32's USB chip (CP210x, CH340, FTDI, native USB).
const PORT_HINTS := ["usbserial", "usbmodem", "slab_usbtouart", "wchusbserial", "ttyusb", "ttyacm", "com"]

var enabled := true              # Tests switch this off so no real port is opened.
var _serial: Object = null       # GdSerial, or null if the plugin is missing.
var _port := ""                  # The port being tried or used.
var _is_connected := false
var _waited := 0.0               # Seconds spent waiting for HELLO on _port.
var _search_timer := 0.0
var _tried: Array[String] = []   # Ports already tried in this round.
var _buffer := ""
var _led_timer := 0.0
var _last_leds := ""
var _last_happy := ""
var _sent: Array[String] = []    # Every line sent, newest last (for tests).

@onready var _state: GameStateManager = get_node("../GameStateManager")
@onready var _events: EventManager = get_node("../EventManager")
@onready var _buildings: BuildingManager = get_node("../BuildingManager")
@onready var _population: PopulationManager = get_node("../PopulationManager")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # The pause menu must work too.
	if ClassDB.class_exists("GdSerial"):
		_serial = ClassDB.instantiate("GdSerial")
	_buildings.building_placed.connect(func(_plot: BuildingPlot) -> void: beep(1))
	_events.events_changed.connect(_on_events_changed)
	_state.state_changed.connect(func() -> void:
		if _state.get_state() == GameStateManager.State.WON or _state.get_state() == GameStateManager.State.LOST:
			beep(3))


func is_linked() -> bool:
	return _is_connected


func get_port() -> String:
	return _port if _is_connected else ""


func get_sent() -> Array[String]:
	return _sent


func _process(delta: float) -> void:
	if not enabled or _serial == null:
		return
	if _port == "":
		_search_timer -= delta
		if _search_timer <= 0.0:
			_search_timer = SEARCH_EVERY
			_try_next_port()
		return
	if not _serial.is_open():
		_lost()
		return
	_read_lines()
	if not _is_connected:
		_waited += delta
		if _waited > HELLO_WAIT:
			_serial.close()   # Not our board: try the next port.
			_port = ""
		return
	_led_timer -= delta
	if _led_timer <= 0.0:
		_led_timer = LED_EVERY
		_send_leds()
		_send_happiness()


func _try_next_port() -> void:
	var ports: Dictionary = _serial.list_ports()
	var candidates: Array[String] = []
	for key in ports:
		var info = ports[key]
		var name := str(info.get("port_name", key)) if info is Dictionary else str(key)
		if _is_candidate(name):
			candidates.append(name)
	candidates.sort()
	for name in candidates:
		if name in _tried:
			continue
		_tried.append(name)
		_serial.set_port(name)
		_serial.set_baud_rate(BAUD)
		_serial.set_timeout(5)
		if _serial.open():
			_port = name
			_waited = 0.0
			_buffer = ""
			return
	_tried.clear()   # All tried: start the round again next time.


static func _is_candidate(name: String) -> bool:
	var lower := name.to_lower()
	if "bluetooth" in lower or "debug" in lower:
		return false
	if lower.begins_with("/dev/tty.") :
		return false   # On a Mac the /dev/cu. twin is the one to open.
	for hint: String in PORT_HINTS:
		if hint in lower:
			return true
	return false


func _read_lines() -> void:
	var waiting: int = _serial.bytes_available()
	if waiting <= 0:
		return
	_buffer += _serial.read_string(waiting)
	while "\n" in _buffer:
		var cut := _buffer.find("\n")
		var line := _buffer.substr(0, cut).strip_edges()
		_buffer = _buffer.substr(cut + 1)
		if line != "":
			handle_line(line)
	if _buffer.length() > 200:
		_buffer = ""   # Noise with no line ends.


# One line from the controller. Public so tests can feed lines without a board.
func handle_line(line: String) -> void:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	match parts[0]:
		"HELLO":
			if parts.size() >= 2 and parts[1] == "ISLAND":
				var was_connected := _is_connected
				_is_connected = true
				_last_leds = ""
				_last_happy = ""
				send("HI")
				if not was_connected:
					connected.emit(_port)
					_notify("Controller connected")
					beep(1)
		"BTN":
			if parts.size() >= 3 and parts[1] == "BUILD" and not _buildings.is_placing() \
					and get_node_or_null("../UI/Screens") != null and not _game_over():
				# The Build button opens the Build Menu (like the bottom-left Build
				# button); the building chosen there is placed with the joystick.
				# While placing, it cancels like the B key (below).
				if parts[2] == "1":
					var screens: Screens = get_node("../UI/Screens")
					if screens.get_open_name() == "build":
						screens.close()
					else:
						screens.open("build")
			elif parts.size() >= 3 and BUTTON_ACTIONS.has(parts[1]):
				_fire(BUTTON_ACTIONS[parts[1]], parts[2] == "1")
				# The win and lose screens answer Enter and Backspace keys.
				if parts[2] == "1" and _game_over():
					if parts[1] == "ACTION":
						_tap("event_respond")
					elif parts[1] == "BACK":
						_tap("event_decline")
		"ENC":
			if parts.size() >= 2:
				_tap("pad_turn_right" if parts[1].to_int() > 0 else "pad_turn_left")


func _game_over() -> bool:
	return _state.get_state() == GameStateManager.State.WON or _state.get_state() == GameStateManager.State.LOST


func _fire(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)   # Menus react to the press itself...
	# ...and the camera reads whether an arrow is held, which must not depend
	# on the game window having the keyboard focus.
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _tap(action: String) -> void:
	_fire(action, true)
	_fire(action, false)


# What the four LEDs should show now, as "LEDS gyrb".
func get_led_line() -> String:
	var state := _state.get_state()
	var green := "2" if state == GameStateManager.State.WON else ("0" if state == GameStateManager.State.LOST else "1")
	var yellow := "0"
	if not _events.get_active().is_empty():
		yellow = "2" if _events.is_waiting_for_player() else "1"
	var red := "0"
	if state == GameStateManager.State.LOST:
		red = "2"
	elif _state.get_starvation_seconds_left() >= 0 or _state.get_storage_seconds_left() >= 0:
		red = "1"
	var blue := "1" if _buildings.is_placing() else "0"
	return "LEDS " + green + yellow + red + blue


func _send_leds() -> void:
	var line := get_led_line()
	if line != _last_leds:
		# The colony has just come into danger (red turns on): sound a warning.
		if _last_leds.length() == 9 and _last_leds[7] == "0" and line[7] == "1":
			beep(2)
		_last_leds = line
		send(line)


func get_happiness_line() -> String:
	return "HAPPY %d" % _population.get_happiness()


func _send_happiness() -> void:
	var line := get_happiness_line()
	if line != _last_happy:
		_last_happy = line
		send(line)


func beep(kind: int) -> void:
	send("BEEP %d" % kind)


func send(line: String) -> void:
	_sent.append(line)
	if _sent.size() > 50:
		_sent.pop_front()
	if _serial != null and _serial.is_open() and not _serial.writeline(line):
		_serial.close()   # The cable was pulled out.
		_lost()


var _event_count := 0
func _on_events_changed() -> void:
	var count := _events.get_active().size()
	if count > _event_count:
		beep(2)
	_event_count = count


func _lost() -> void:
	var was_connected := _is_connected
	_is_connected = false
	_port = ""
	_tried.clear()
	if was_connected:
		disconnected.emit()
		_notify("Controller unplugged")


func _notify(text: String) -> void:
	var screens := get_node_or_null("../UI/Screens")
	if screens != null and screens.has_method("notify"):
		screens.notify(text, "gear")


func _exit_tree() -> void:
	if _serial != null and _serial.is_open():
		_serial.writeline("BYE")
		_serial.close()
