# worker.gd
# The data for one worker. This is a plain class, not a node, and it keeps a link
# to the worker's 3D model on the island.
class_name Worker
extends RefCounted

var worker_name := ""
var productivity := 0            # Resources produced per production cycle. Never random.
var job_plot: BuildingPlot = null  # Where this worker works. null means no job.
var repair_plot: BuildingPlot = null  # A collapsed building this worker is repairing.
var is_sick := false             # Set by a disease outbreak. Sick workers produce nothing.
var treatment_plot: BuildingPlot = null  # The Research Lab this worker is walking to for a vaccine.
var aboard := false             # On the migration boat: carried by it, and does not walk until it lands.
var model: Node3D = null
var target_position := Vector3.ZERO  # Where the model is heading.
var target_rotation := 0.0           # Which way it faces once it gets there.
var path: Array[Vector3] = []        # Points still to walk through, ending at target_position.
var path_goal := Vector3.INF         # The target the path was worked out for.
var path_version := -1               # PathGrid.version when the path was worked out.


func _init(new_name: String, new_productivity: int) -> void:
	worker_name = new_name
	productivity = new_productivity


func is_idle() -> bool:
	return job_plot == null and repair_plot == null and treatment_plot == null


# Height is ignored, because the model follows the ground as it moves.
func is_moving() -> bool:
	return Vector2(model.position.x, model.position.z) != Vector2(target_position.x, target_position.z)
