# Renders a small picture of each building for the Build Menu cards, from the
# game's own models. Run once: <Godot> --path . --script res://tests/_thumbs.gd
extends SceneTree
func _initialize() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(256, 192)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.7
	view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.3
	view.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	view.add_child(cam)
	for b in BuildingManager.BUILDINGS:
		var model: Node3D = b.scene.instantiate()
		view.add_child(model)
		await process_frame
		var box := AABB()
		var first := true
		for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = m.global_transform * m.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		var centre := box.get_center()
		var size := box.size.length()
		cam.position = centre + Vector3(1.0, 0.75, 1.15).normalized() * size * 1.75
		cam.look_at(centre)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var name: String = b.name.to_lower().replace(" ", "_")
		view.get_texture().get_image().save_png("res://assets/ui/thumbs/%s.png" % name)
		print("THUMB ", name)
		model.queue_free()
		await process_frame
	quit()
