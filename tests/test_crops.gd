# test_crops.gd
# Crops that grow beside Farms, and the text that floats up from buildings.
# Run with a window:  <Godot> --path . --script res://tests/test_crops.gd
extends SceneTree

var fails := 0


func check(label: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		fails += 1


func _initialize() -> void:
	run()


func run() -> void:
	DayNight.enabled = false   # Keep the midday light, so results do not depend on the time of day.
	StoryBox.short = false     # Check the full story text; the game shows a shortened version.
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("EventManager/EventTimer").stop()
	main.get_node("PopulationManager/UpkeepTimer").stop()
	var map: MapManager = main.get_node("MapManager")
	var builder: BuildingManager = main.get_node("BuildingManager")
	var workers: WorkerManager = main.get_node("WorkerManager")
	var crops: CropManager = main.get_node("CropManager")
	var popups: PopupManager = main.get_node("Popups")
	var events: EventManager = main.get_node("EventManager")
	var r: ResourceManager = main.get_node("ResourceManager")
	var paths: PathGrid = main.get_node("PathGrid")
	var T := ResourceManager.Type
	# This test calls produce() itself, so the production timer is stopped.
	for child in workers.get_children():
		if child is Timer:
			child.stop()

	var farm := map.get_plot(1)
	var house := map.get_plot(2)
	builder.choose_building(1)
	builder._place_building(farm)
	builder.choose_building(0)
	builder._place_building(house)
	check("a Farm gets a field of crops, a House does not", crops.has_field(farm) and not crops.has_field(house))
	check("building shows floating text", popups.get_texts().has("Farm built") and popups.get_texts().has("House built"), str(popups.get_texts()))
	var area: Rect2 = paths.get_footprints()[0]
	check("the crops do not change the Farm's footprint for walking (the 10 m windmill alone, at most 14.2 m across however it is turned; the crop beds would make it about 24 m)", area.size.x <= 14.2 and area.size.y <= 14.2 and area.size.x >= 9.8, str(area.size))
	var field: Node3D = crops.get_node("Field01")
	var plants: MultiMeshInstance3D = field.find_children("*", "MultiMeshInstance3D", true, false)[0]
	check("two beds with 84 plants", field.find_children("*", "MeshInstance3D", true, false).size() == 2 and plants.multimesh.instance_count == 84)
	check("seedlings start small", absf(plants.multimesh.get_instance_transform(0).basis.get_scale().y / CropManager.SEEDLING_SIZE - 1.0) < 0.2)

	workers.produce()
	check("nothing grows without workers", crops.get_growth(farm) == 0.0)

	workers.assign_worker(farm)
	workers.assign_worker(farm)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and workers.get_output(farm) < 13:
		await process_frame
	check("two workers reach the Farm", workers.get_output(farm) == 13, str(workers.get_output(farm)))
	var young := crops.get_colour(farm, false)
	workers.produce()
	check("one cycle grows the crops one step of six", absf(crops.get_growth(farm) - 1.0 / 6.0) < 0.01, str(crops.get_growth(farm)))
	await process_frame
	check("making food shows +13 Food", popups.get_texts().has("+13 Food"), str(popups.get_texts()))
	for i in 5:
		workers.produce()
	check("six cycles make them fully grown", crops.is_ripe(farm) and crops.get_growth(farm) == 1.0)

	# The crops on screen catch up with the growth. Time runs faster here.
	Engine.time_scale = 10.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	Engine.time_scale = 1.0
	check("the plants on screen grow to full size", plants.multimesh.get_instance_transform(0).basis.get_scale().y >= 0.8)
	var ripe := crops.get_colour(farm, false)
	check("ripe crops are golden, young ones green", ripe.r > ripe.g and young.g > young.r, "%s %s" % [young, ripe])
	check("crops look dry in a drought", crops.get_colour(farm, true) != ripe)

	var harvests := [0]
	crops.harvested.connect(func(_plot: BuildingPlot) -> void: harvests[0] += 1)
	var food := r.get_amount(T.FOOD)
	workers.produce()
	check("the next cycle harvests and replants", harvests[0] == 1 and crops.get_growth(farm) == 0.0)
	check("harvesting does not change the food made", r.get_amount(T.FOOD) == mini(food + 13, r.get_capacity()))
	await process_frame
	check("the harvest shows Harvest!", popups.get_texts().has("Harvest!"), str(popups.get_texts()))

	r.add(T.FOOD, 1000)
	workers.produce()
	await process_frame
	check("full storage shows Storage full", popups.get_texts().has("Storage full"), str(popups.get_texts()))

	events.trigger(EventManager.Type.ACCIDENT)
	var before := crops.get_growth(farm)
	workers.produce()
	check("a collapsed Farm grows nothing", farm.is_damaged and crops.get_growth(farm) == before)

	# Floating text fades away and is removed.
	await create_timer(PopupManager.SECONDS + 0.5).timeout
	check("floating text disappears", popups.get_texts().is_empty(), str(popups.get_texts()))

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
