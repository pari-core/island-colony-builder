# non_metal_building.gd
# Some downloaded models mark wood and brick as fully metal. Metal shows mostly
# sky reflections and very little of its own colour, so those buildings look almost
# black. This script runs on the building and turns that setting off. The original
# model files are not changed.
extends Node3D

# All copies of a building share these fixed materials, which keeps drawing cheap.
static var _fixed_materials := {}


func _ready() -> void:
	_fix_materials(self)


func _fix_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(i)
			if original is StandardMaterial3D:
				node.set_surface_override_material(i, _non_metal_copy(original))
	for child in node.get_children():
		_fix_materials(child)


func _non_metal_copy(original: StandardMaterial3D) -> StandardMaterial3D:
	if not _fixed_materials.has(original):
		var copy: StandardMaterial3D = original.duplicate()
		copy.metallic = 0.0
		_fixed_materials[original] = copy
	return _fixed_materials[original]
