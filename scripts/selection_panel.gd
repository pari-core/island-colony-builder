# selection_panel.gd
# Describes the selected plot in the bottom corner of the screen. This is a simple
# first version, and the full interface comes later.
extends Label

@onready var _map: MapManager = get_node("../../MapManager")
@onready var _workers: WorkerManager = get_node("../../WorkerManager")
@onready var _population: PopulationManager = get_node("../../PopulationManager")
@onready var _research: ResearchManager = get_node("../../ResearchManager")
@onready var _resources: ResourceManager = get_node("../../ResourceManager")
@onready var _civilians: CivilianManager = get_node("../../CivilianManager")
@onready var _builder: BuildingManager = get_node("../../BuildingManager")


# Updated every frame, so progress such as research is always current.
func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var plot := _map.get_selected_plot()
	visible = plot != null
	if plot != null:
		text = _describe(plot)


func _describe(plot: BuildingPlot) -> String:
	if plot.building == null:
		var status := "Empty" if plot.is_buildable() else "Blocked"
		return "Plot %d: %s" % [plot.plot_id, status]

	var lines: Array[String] = ["Plot %d: %s" % [plot.plot_id, plot.building_info.name]]
	if plot.under_construction:
		lines.append(get_node("../../ConstructionManager").get_status(plot))
	if plot.is_damaged:
		lines.append("Collapsed: does nothing until workers repair it (Enter)")
	if plot.building_info.name == "Research Lab":
		lines.append(_describe_research())
		var upgrades: Array[String] = []
		for id: String in ResearchManager.UPGRADES:
			upgrades.append("%s %s" % [ResearchManager.PROJECTS[id].name, _research.get_status(id)])
		lines.append("Upgrades (Space for the menu): %s" % ", ".join(upgrades))
	if plot.building_info.name == "Warehouse":
		var adds := "adds nothing until repaired" if plot.is_damaged else "adds %d storage for each resource" % (ResourceManager.WAREHOUSE_STORAGE * plot.level)
		lines.append("Level %d of %d: %s (storage now %d)" % [plot.level, _builder.get_max_level(plot), adds, _resources.get_capacity()])
		var problem := _builder.get_upgrade_problem(plot)
		if problem == "":
			lines.append("U: upgrade to level %d (%s)" % [plot.level + 1, _resources.describe_cost(_builder.get_upgrade_cost(plot))])
		else:
			lines.append(problem)
	if plot.building_info.name == "House":
		lines.append("Home for up to %d people, %d inside now" % [PopulationManager.PEOPLE_PER_HOUSE, _civilians.get_inside_count(plot)])
		if not plot.is_damaged:
			var problem := _civilians.get_training_problem(plot)
			if problem == "":
				lines.append("T: train a civilian into a worker (%s)" % _resources.describe_cost(CivilianManager.TRAIN_COST))
			else:
				lines.append(problem)
	var slots := _workers.get_slots(plot)
	if slots == 0:
		return "\n".join(lines)

	var names: Array[String] = []
	for worker in _workers.get_workers_at(plot):
		var status := ", sick" if worker.is_sick else ", on the way" if worker.is_moving() else ""
		names.append("%s (%d%s)" % [worker.worker_name, worker.productivity, status])
	lines.append("Workers %d/%d: %s" % [names.size(), slots, ", ".join(names) if names.size() > 0 else "none"])
	var resource_name: String = ResourceManager.NAMES[plot.building_info.produces]
	var state: String = PopulationManager.STATE_NAMES[_population.get_state()]
	lines.append("Makes %d %s every %d seconds (colony %s, x%s)" % [_workers.get_output(plot), resource_name, WorkerManager.PRODUCTION_SECONDS, state, _population.get_productivity()])
	lines.append("J add worker (%d idle), K remove worker" % _workers.get_idle_count())
	return "\n".join(lines)


func _describe_research() -> String:
	if _research.is_finished("vaccine"):
		return "Vaccine ready: Enter treats a disease outbreak"
	if _research.get_current() == "vaccine":
		return "Researching vaccine: %d%%" % int(_research.get_progress() * 100.0)
	var project: Dictionary = ResearchManager.PROJECTS.vaccine
	return "R: research a vaccine (%s, %d s)" % [_resources.describe_cost(project.cost), project.seconds]
