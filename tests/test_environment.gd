# test_environment.gd
# The scenery of the v2 village: winding dirt roads linking the scattered build
# squares, the town square and the beach, ponds in the fields, and trees among
# the houses but never on a build square, a road or in water.
# Run from the project folder, with a window (not headless):
#   <Godot> --path . --script res://tests/test_environment.gd
# It prints PASS or FAIL for each check and ends with "RESULT fails=N".
extends SceneTree

var fails := 0


func check(text: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ") + text + "  " + detail)
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
	var roads: Roads = main.get_node("Roads")
	var map: MapManager = main.get_node("MapManager")
	var terrain = main.get_node("Island/Terrain")
	var half := BuildingPlot.SIZE * 0.5

	# ------------------------------------------------------------ Roads
	var segments := roads.get_segments()
	check("there are paths between the rows and columns, and to every door", segments.size() >= 8 + map.get_plots().size(), str(segments.size()))
	var every_square_has_a_road := true
	var road_on_square := false
	for plot in map.get_plots():
		var front: Vector3 = plot.to_world(Vector3(0.0, 0.0, half + Roads.FRONT_GAP))
		if not roads.is_on_road(front.x, front.z):
			every_square_has_a_road = false
		if roads.is_on_road(plot.position.x, plot.position.z):
			road_on_square = true
	check("a road starts at the front of every square", every_square_has_a_road)
	check("no road runs over the middle of a square", not road_on_square)
	check("a road reaches the town square", roads.is_on_road(0.0, 0.0))
	var beach := main.get_node("EventManager").get_beach_position() as Vector3
	check("a road runs to the beach", roads.is_on_road(beach.x - 6.0, Roads.BEACH_ROAD_Z, 3.0))
	var mask: Texture2D = (terrain.material_override as ShaderMaterial).get_shader_parameter("road_mask")
	check("the roads are painted into the terrain's road picture", mask != null and mask.get_width() == int(Roads.AREA * Roads.PIXELS_PER_METRE))
	var image := mask.get_image()
	var first: Vector3 = map.get_plot(1).to_world(Vector3(0.0, 0.0, half + Roads.FRONT_GAP))
	var on := image.get_pixel(int(Roads.AREA * 0.5 + first.x), int(Roads.AREA * 0.5 + first.z)).r
	var off := image.get_pixel(int(Roads.AREA * 0.5 + map.get_plot(1).position.x), int(Roads.AREA * 0.5 + map.get_plot(1).position.z)).r
	check("the picture is white on a road and black in a square's middle", on > 0.9 and off < 0.05, "%.2f %.2f" % [on, off])

	# ------------------------------------------------------------ Ponds
	var wet := 0
	for pond: Vector3 in terrain.PONDS:
		if terrain.get_height_at(pond.x, pond.y) < -1.0:
			wet += 1
	check("all three ponds hold water (their middles are below sea level)", wet == 3 and terrain.PONDS.size() == 3)
	var dry_squares := true
	for plot in map.get_plots():
		for pond: Vector3 in terrain.PONDS:
			if Vector2(plot.position.x, plot.position.z).distance_to(Vector2(pond.x, pond.y)) < pond.z * 1.3 + 20.0:
				dry_squares = false
	check("no pond comes near a build square", dry_squares)

	# ------------------------------------------------------------ Trees
	var decorations: Node = main.get_node("Island/Decorations")
	var near_town := 0
	var on_road := 0
	var in_water := 0
	for item in decorations.get_children():
		var spot := Vector2(item.position.x, item.position.z)
		if spot.length() < 130.0:
			near_town += 1
		if roads.is_on_road(spot.x, spot.y):
			on_road += 1
		# Boulders line the shore half in the water on purpose (v2 island); trees never.
		if item.position.y < 0.9 and not item.scene_file_path.contains("rock"):
			in_water += 1
	check("trees stand among the houses (inside 130 m of the town square)", near_town >= 60, str(near_town))
	check("none on a road", on_road == 0, str(on_road))
	check("no trees in water (shore boulders may be)", in_water == 0, str(in_water))

	await create_timer(0.5).timeout
	var camera: Camera3D = main.get_node("Camera3D")
	camera.set_process(false)
	camera.global_position = Vector3(-120, 150, 160)
	camera.look_at(Vector3(0, 0, 10))
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://documentation/evidence/environment_roads_ponds.png")

	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)
