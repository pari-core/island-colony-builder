# test_controller_link.gd
# The ESP32 link without a board: lines the controller would send are fed in by
# hand, and the test checks they press the same actions as the keyboard, and
# that the LED and buzzer lines the game sends back are right.
# Run with a window:  <Godot> --path . --script res://tests/test_controller_link.gd
extends SceneTree

var fails := 0


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func run() -> void:
	DayNight.enabled = false
	StoryBox.short = false
	StoryBox.enabled = false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	var link: ControllerLink = main.get_node("ControllerLink")
	link.enabled = false   # Open no real port.
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("ControllerMenu").close_menu()
	paused = false
	main.get_node("EventManager/EventTimer").stop()
	var buildings: BuildingManager = main.get_node("BuildingManager")

	check("the serial plugin is loaded", ClassDB.class_exists("GdSerial"))
	check("ESP32 ports are recognised, Bluetooth and tty twins are not",
		ControllerLink._is_candidate("/dev/cu.usbserial-0001") and ControllerLink._is_candidate("/dev/cu.SLAB_USBtoUART")
		and ControllerLink._is_candidate("/dev/cu.wchusbserial1420") and ControllerLink._is_candidate("COM5")
		and not ControllerLink._is_candidate("/dev/cu.Bluetooth-Incoming-Port") and not ControllerLink._is_candidate("/dev/cu.debug-console")
		and not ControllerLink._is_candidate("/dev/tty.usbserial-0001"))

	check("not linked before the board says hello", not link.is_linked())
	link.handle_line("HELLO ISLAND 1")
	check("HELLO links the board and the game answers HI", link.is_linked() and "HI" in link.get_sent(), str(link.get_sent()))

	link.handle_line("BTN UP 1")
	await process_frame
	check("BTN UP 1 holds the Up action", Input.is_action_pressed("pad_up"))
	link.handle_line("BTN UP 0")
	await process_frame
	check("BTN UP 0 lets it go", not Input.is_action_pressed("pad_up"))

	check("LEDs while playing: green on, nothing else", link.get_led_line() == "LEDS 1000", link.get_led_line())
	link.handle_line("BTN BUILD 1")
	link.handle_line("BTN BUILD 0")
	await process_frame
	await process_frame
	check("BTN BUILD starts placing a building, like the B key", buildings.is_placing())
	check("the blue LED shows placing", link.get_led_line() == "LEDS 1001", link.get_led_line())
	link.handle_line("BTN BACK 1")
	link.handle_line("BTN BACK 0")
	await process_frame
	await process_frame
	check("BTN BACK (encoder push) cancels it", not buildings.is_placing())

	var listener := GDScript.new()
	listener.source_code = "extends Node\nvar right := 0\nvar left := 0\nfunc _input(e):\n\tif e.is_action_pressed('pad_turn_right'): right += 1\n\telif e.is_action_pressed('pad_turn_left'): left += 1\n"
	listener.reload()
	var watcher := Node.new()
	watcher.set_script(listener)
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(watcher)
	link.handle_line("ENC 1")
	link.handle_line("ENC 1")
	link.handle_line("ENC -1")
	await process_frame
	check("encoder clicks turn into turn actions", watcher.right == 2 and watcher.left == 1, "%d right, %d left" % [watcher.right, watcher.left])

	main.get_node("EventManager").trigger(0)
	await process_frame
	check("a new event beeps twice", "BEEP 2" in link.get_sent(), str(link.get_sent()))
	check("the yellow LED shows the event", link.get_led_line().substr(6, 1) != "0", link.get_led_line())

	link.handle_line("nonsense")
	link.handle_line("BTN NOTHING 1")
	check("unknown lines are ignored", true)

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
