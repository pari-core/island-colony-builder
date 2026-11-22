# harbour.gd
# The Harbour landmark: a wooden quay on posts with a harbour office, a loading
# crane, a mooring mast with a flag, and crates and barrels waiting to be shipped.
# The shapes and how they appear while building come from landmark_model.gd.
extends LandmarkModel

const BLUE := Color(0.16, 0.33, 0.55)


func _build() -> void:
	# The quay: a deck of planks on a row of posts.
	for x: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for z: float in [-6.5, 6.5]:
			add_cylinder(0.35, 0.35, 1.6, Vector3(x, 0.8, z), DARK_WOOD, 0.0, 10)
	add_box(Vector3(19.0, 0.4, 15.0), Vector3(0.0, 1.6, 0.0), WOOD, 0.15)

	# The harbour office.
	add_box(Vector3(7.0, 4.0, 6.0), Vector3(-5.0, 3.8, -3.5), PLASTER, 0.35)
	add_roof(Vector3(7.8, 2.4, 6.8), Vector3(-5.0, 7.0, -3.5), ROOF_RED, 0.5)
	add_box(Vector3(1.4, 2.4, 0.3), Vector3(-5.0, 3.0, -0.45), DARK_WOOD, 0.5)

	# The crane: a post, a long arm, a rope and a hook.
	add_cylinder(0.45, 0.35, 9.0, Vector3(5.5, 6.3, -3.0), DARK_WOOD, 0.6, 12)
	var arm := add_box(Vector3(0.4, 0.4, 9.0), Vector3(5.5, 10.3, 0.5), DARK_WOOD, 0.7)
	arm.rotation.x = -0.25
	add_cylinder(0.06, 0.06, 4.0, Vector3(5.5, 7.5, 4.6), IRON, 0.75, 6)
	add_box(Vector3(0.5, 0.5, 0.5), Vector3(5.5, 5.4, 4.6), IRON, 0.75)

	# Goods on the quay.
	add_box(Vector3(1.8, 1.8, 1.8), Vector3(2.0, 2.7, 4.5), POLE, 0.85)
	add_box(Vector3(1.8, 1.8, 1.8), Vector3(4.0, 2.7, 4.8), POLE, 0.85, 0.4)
	add_box(Vector3(1.6, 1.6, 1.6), Vector3(3.0, 4.4, 4.6), POLE, 0.9, 0.2)
	add_cylinder(0.7, 0.7, 1.6, Vector3(-1.5, 2.6, 5.0), WOOD, 0.9, 14)
	add_cylinder(0.7, 0.7, 1.6, Vector3(-3.2, 2.6, 5.2), WOOD, 0.9, 14)

	# The mast and its flag go up last.
	add_cylinder(0.18, 0.12, 12.0, Vector3(-8.0, 7.8, 5.5), POLE, 0.95, 10)
	add_box(Vector3(2.6, 1.5, 0.08), Vector3(-6.6, 12.8, 5.5), BLUE, 1.0)
	add_scaffold(10.5, 9.0)
