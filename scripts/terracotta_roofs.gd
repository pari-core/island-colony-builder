# terracotta_roofs.gd
# Gives a KayKit building red terracotta roofs, like the team's picture (v2,
# 2026-11-22). KayKit colours its roofs with a material called "Brown"; this
# swaps in a copy of that material coloured #B9573C (the brief's roof colour),
# leaving walls, wood and stone as they are. The model files are unchanged.
extends Node3D

const ROOF_MATERIAL := "Brown"
const TERRACOTTA := Color(0.725, 0.341, 0.235)

static var _red_roof: BaseMaterial3D = null   # Made once, shared by every building.


func _ready() -> void:
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == ROOF_MATERIAL:
				if _red_roof == null:
					_red_roof = material.duplicate()
					_red_roof.albedo_color = TERRACOTTA
				mesh.set_surface_override_material(surface, _red_roof)
