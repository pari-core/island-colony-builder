# town_hall.gd
# The Town Hall landmark: a long plastered hall on a stone step, with a red
# roof, a row of columns at the front and a clock tower in the middle.
# The shapes and how they appear while building come from landmark_model.gd.
extends LandmarkModel


func _build() -> void:
	add_box(Vector3(21.0, 0.8, 15.0), Vector3(0.0, 0.4, 0.0), STONE, 0.0)
	add_box(Vector3(18.0, 6.0, 10.0), Vector3(0.0, 3.8, -1.0), PLASTER, 0.2)

	# The porch: four columns and the beam they carry.
	for x: float in [-6.0, -2.0, 2.0, 6.0]:
		add_cylinder(0.5, 0.45, 5.6, Vector3(x, 3.6, 5.5), STONE, 0.4, 14)
	add_box(Vector3(14.0, 0.7, 2.2), Vector3(0.0, 6.75, 5.0), STONE, 0.45)
	add_box(Vector3(2.2, 3.6, 0.3), Vector3(0.0, 2.6, 4.1), DARK_WOOD, 0.45)

	# The roof of the hall, its ridge running left to right.
	add_roof(Vector3(11.2, 3.4, 19.0), Vector3(0.0, 8.5, -1.0), ROOF_RED, 0.6, PI / 2.0)

	# The clock tower.
	add_box(Vector3(4.2, 7.0, 4.2), Vector3(0.0, 10.3, -1.0), PLASTER, 0.75)
	add_cylinder(1.2, 1.2, 0.2, Vector3(0.0, 11.6, 1.2), GOLD, 0.85).rotation.x = PI / 2.0
	add_cylinder(3.3, 0.05, 4.0, Vector3(0.0, 15.8, -1.0), ROOF_RED, 0.9, 4).rotation.y = PI / 4.0
	add_sphere(0.45, Vector3(0.0, 18.1, -1.0), GOLD, 1.0)
	add_scaffold(11.0, 14.0)
