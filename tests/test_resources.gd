# test_resources.gd
# Spec tests: T06, T07, T11, T17. Resource rules: storage limit and overflow, no negative amounts, costs, unaffordable builds.
# Run from the project folder, with a window (not headless), and do not move the
# mouse while it runs:
#   <Godot> --path . --script res://tests/test_resources.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree
const OUT := "user://"
var fails := 0
var cam: Camera3D
var mgr: Node
func check(t: String, ok: bool, d := "") -> void:
	print(("PASS " if ok else "FAIL ") + t + "  " + d)
	if not ok: fails += 1
func _initialize() -> void:
	run()
func key(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new(); e.physical_keycode = code; e.keycode = code; e.pressed = down
		Input.parse_input_event(e)
		await process_frame
		await process_frame
func hover(point: Vector3) -> void:
	# Moving the real pointer is not instant, and someone may be using the mouse.
	# Keep moving it until the game sees it at the target, for up to 1.5 seconds.
	var target := cam.unproject_position(point)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		root.warp_mouse(target)
		await process_frame
		await process_frame
		if root.get_mouse_position().distance_to(target) < 3.0:
			break
	await process_frame
	await process_frame
func click(point: Vector3) -> void:
	var p := cam.unproject_position(point) * Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	for down in [true, false]:
		var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; e.position = p; e.global_position = p
		Input.parse_input_event(e)
		await process_frame
		await process_frame
func build_on(p: BuildingPlot) -> void:
	await key(KEY_B)
	await hover(p.position)
	await click(p.position)
# v2: buildings are turned with their squares. This is the building's ground
# area in its own directions (x across, z front to back), from its meshes.
func local_box(building: Node3D) -> Rect2:
	var to_local := building.global_transform.affine_inverse()
	var box := Rect2()
	var first := true
	for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (to_local * mesh.global_transform) * mesh.get_aabb()
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		box = r if first else box.merge(r)
		first = false
	# Scale (upgrades) is part of the building's own transform, so apply it.
	return Rect2(box.position * building.scale.x, box.size * building.scale.x)


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	StoryBox.enabled = false   # The accident tells a story; this test is about storage.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	# Stop food use and happiness changes, so this test's exact numbers hold.
	main.get_node("PopulationManager/UpkeepTimer").stop()
	var r: ResourceManager = main.get_node("ResourceManager")
	var bar: Label = main.get_node("UI/ResourcePanel/ResourceBar")
	var map: Node = main.get_node("MapManager")
	mgr = main.get_node("BuildingManager")
	cam = main.get_node("Camera3D")
	var label: Label = main.get_node("UI/PlacementLabel")
	var T := ResourceManager.Type
	check("starting amounts", r.get_amount(T.FOOD) == 150 and r.get_amount(T.WOOD) == 150 and r.get_amount(T.STONE) == 80 and r.get_amount(T.GOLD) == 20)
	check("bar shows amounts", bar.text.contains("Food 150/200") and bar.text.contains("Gold 20/200"), bar.text)
	var n := [0]
	r.resources_changed.connect(func(): n[0] += 1)
	check("add stores amount", r.add(T.FOOD, 30) == 30 and r.get_amount(T.FOOD) == 180 and n[0] == 1)
	check("bar updates", bar.text.contains("Food 180/200"))
	check("overflow is lost", r.add(T.FOOD, 80) == 20 and r.get_amount(T.FOOD) == 200)
	check("add at full stores nothing", r.add(T.FOOD, 5) == 0 and r.get_amount(T.FOOD) == 200)
	check("negative add ignored", r.add(T.FOOD, -50) == 0 and r.get_amount(T.FOOD) == 200)
	check("can afford exact amount", r.can_afford({T.GOLD: 20}))
	check("cannot afford one more", not r.can_afford({T.GOLD: 21}))
	var wood: int = r.get_amount(T.WOOD)
	check("failed spend takes nothing", not r.spend({T.WOOD: 10, T.GOLD: 999}) and r.get_amount(T.WOOD) == wood and r.get_amount(T.GOLD) == 20)
	check("exact spend reaches zero, never negative", r.spend({T.GOLD: 20}) and r.get_amount(T.GOLD) == 0 and not r.spend({T.GOLD: 1}) and r.get_amount(T.GOLD) == 0)
	check("cost text", r.describe_cost({T.WOOD: 20, T.STONE: 10}) == "20 Wood, 10 Stone")
	var plots: Array = map.get_plots()
	cam.set("_focus", Vector3.ZERO); cam.set("_distance", 260.0); cam.set("_target_distance", 260.0)
	await create_timer(0.8).timeout
	# v2: only squares that are on screen and not under a corner panel can be clicked.
	var hud: Hud = main.get_node("UI/HUD")
	plots = plots.filter(func(p: BuildingPlot) -> bool:
		var pixel := cam.unproject_position(p.position)
		return get_root().get_visible_rect().grow(-20.0).has_point(pixel) and not hud.covers(pixel))
	check("at least eight squares can be clicked", plots.size() >= 8, str(plots.size()))
	await key(KEY_B)
	check("label shows real cost", label.text.contains("20 Wood, 10 Stone"), label.text.replace("\n", " / "))
	await key(KEY_ESCAPE)
	check("cancel costs nothing", r.get_amount(T.WOOD) == 150 and r.get_amount(T.STONE) == 80)
	await build_on(plots[0])
	check("House spends 20 wood and 10 stone", r.get_amount(T.WOOD) == 130 and r.get_amount(T.STONE) == 70 and plots[0].building != null)
	await key(KEY_B); await hover(plots[0].position); await click(plots[0].position)
	check("occupied plot costs nothing", r.get_amount(T.WOOD) == 130 and r.get_amount(T.STONE) == 70)
	await key(KEY_ESCAPE)
	for i in [1, 2, 3, 4, 5, 6]:
		await build_on(plots[i])
	check("seven Houses leave 10 wood and 10 stone", r.get_amount(T.WOOD) == 10 and r.get_amount(T.STONE) == 10, "wood %d stone %d" % [r.get_amount(T.WOOD), r.get_amount(T.STONE)])
	await key(KEY_B)
	await hover(plots[7].position)
	check("cannot afford shows red", plots[7].preview == BuildingPlot.Preview.INVALID and label.text.contains("Not enough resources"))
	await click(plots[7].position)
	check("cannot afford builds nothing", plots[7].building == null and mgr.is_placing() and r.get_amount(T.WOOD) == 10)
	r.add(T.WOOD, 10)
	await process_frame
	check("gaining resources turns preview green", plots[7].preview == BuildingPlot.Preview.VALID and label.text.contains("Click to build here"))
	await click(plots[7].position)
	check("builds once affordable", plots[7].building != null and r.get_amount(T.WOOD) == 0 and r.get_amount(T.STONE) == 0)
	# A click on the resource bar must not act on the world behind it.
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = Vector2(640, 10); e.global_position = e.position
	Input.parse_input_event(e)
	await process_frame
	await process_frame
	check("bar click selects nothing", map.get_selected_plot() == null)
	# Warehouses raise the storage limit. A fresh colony, built without the mouse.
	main.queue_free()
	var m2: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(m2)
	await process_frame
	m2.get_node("EventManager/EventTimer").stop()
	m2.get_node("PopulationManager/UpkeepTimer").stop()
	var r2: ResourceManager = m2.get_node("ResourceManager")
	var b2: Node = m2.get_node("BuildingManager")
	var ev2: EventManager = m2.get_node("EventManager")
	var bar2: Label = m2.get_node("UI/ResourcePanel/ResourceBar")
	var plots2: Array = m2.get_node("MapManager").get_plots()
	b2.choose_building(4)
	b2._place_building(plots2[0])
	await process_frame
	check("a Warehouse raises storage to 400", r2.get_capacity() == 400 and bar2.text.contains("Wood 150/400"), bar2.text)
	r2.add(T.WOOD, 1000)
	check("overflow is lost at the new limit", r2.get_amount(T.WOOD) == 400)
	r2.add(T.STONE, 1000)
	b2._place_building(plots2[1])
	check("two Warehouses: 600", r2.get_capacity() == 600)
	r2.add(T.WOOD, 1000)
	ev2.trigger(EventManager.Type.ACCIDENT)
	check("a collapsed Warehouse stops counting", plots2[0].is_damaged and r2.get_capacity() == 400)
	check("stored amounts are kept above the lower limit", r2.get_amount(T.WOOD) == 600)
	check("nothing more stored while above the limit", r2.add(T.WOOD, 10) == 0 and r2.get_amount(T.WOOD) == 600)
	r2.spend({T.WOOD: 250})
	check("stored again once below the limit", r2.add(T.WOOD, 100) == 50 and r2.get_amount(T.WOOD) == 400)
	ev2._end(ev2._find(EventManager.Type.ACCIDENT))
	check("repairing it brings storage back to 600", not plots2[0].is_damaged and r2.get_capacity() == 600)
	m2.get_node("MapManager").select_plot(plots2[1])
	await process_frame
	check("Warehouse panel shows what it adds", m2.get_node("UI/SelectionLabel").text.contains("Level 1 of 3: adds 200 storage for each resource (storage now 600)"), m2.get_node("UI/SelectionLabel").text)
	# Warehouse upgrades, with the U key on the selected Warehouse.
	var paths2: PathGrid = m2.get_node("PathGrid")
	var sel2: Label = m2.get_node("UI/SelectionLabel")
	var house2: BuildingPlot = plots2[2]
	b2.choose_building(0)
	b2._place_building(house2)
	check("a House cannot be upgraded", b2.get_upgrade_problem(house2) == "This building cannot be upgraded")
	r2.spend({T.WOOD: r2.get_amount(T.WOOD), T.STONE: r2.get_amount(T.STONE)})
	check("upgrade refused without resources", b2.get_upgrade_problem(plots2[1]).contains("needs 40 Wood, 30 Stone") and not b2.upgrade(plots2[1]))
	await process_frame
	check("panel says what the upgrade needs", sel2.text.contains("Not enough resources to upgrade"), sel2.text)
	r2.add(T.WOOD, 300)
	r2.add(T.STONE, 300)
	await process_frame
	check("panel offers the upgrade", sel2.text.contains("U: upgrade to level 2 (40 Wood, 30 Stone)"), sel2.text)
	var area_before: Rect2 = paths2.get_footprints()[1]
	await key(KEY_U)
	check("U upgrades to level 2 for 40 wood and 30 stone", plots2[1].level == 2 and r2.get_amount(T.WOOD) == 260 and r2.get_amount(T.STONE) == 270)
	check("level 2 Warehouse adds 400: storage 800", r2.get_capacity() == 800)
	await create_timer(0.8).timeout
	check("the model grows 10%", plots2[1].building.scale.is_equal_approx(Vector3.ONE * 1.1), str(plots2[1].building.scale))
	check("paths go around the bigger model", paths2.get_footprints()[1].get_area() > area_before.get_area() * 1.15)
	check("panel shows level 2", sel2.text.contains("Level 2 of 3: adds 400 storage"), sel2.text)
	check("level 3 costs 60 wood and 50 stone", b2.upgrade(plots2[1]) and plots2[1].level == 3 and r2.get_amount(T.WOOD) == 200 and r2.get_capacity() == 1000)
	await create_timer(0.8).timeout
	var sign: Label3D = plots2[1].building.get_node("LevelSign")
	check("the sign above it shows Lv 3", sign.text == "Lv 3" and (plots2[0].building.get_node("LevelSign") as Label3D).text == "Lv 1")
	check("Houses have no level sign", house2.building.get_node_or_null("LevelSign") == null)
	check("no level 4", not b2.upgrade(plots2[1]) and b2.get_upgrade_problem(plots2[1]) == "Fully upgraded (level 3)")
	var fits := Rect2(-12.0, -12.0, 24.0, 24.0).encloses(local_box(plots2[1].building))   # In the square's own directions (v2).
	check("a level 3 Warehouse still fits its plot", fits)
	ev2.trigger(EventManager.Type.ACCIDENT)
	check("a collapsed Warehouse cannot be upgraded", plots2[0].is_damaged and b2.get_upgrade_problem(plots2[0]) == "Repair it before upgrading")
	check("collapse removes only that Warehouse's storage", r2.get_capacity() == 800)
	m2.queue_free()
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
