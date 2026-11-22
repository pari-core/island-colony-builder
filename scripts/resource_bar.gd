# resource_bar.gd
# Shows the resources, happiness and housing along the top of the screen.
extends Label

@onready var _resources: ResourceManager = get_node("../../../ResourceManager")
@onready var _population: PopulationManager = get_node("../../../PopulationManager")
@onready var _time: TimeManager = get_node("../../../TimeManager")


func _ready() -> void:
	_resources.resources_changed.connect(_refresh)
	_population.population_changed.connect(_refresh)
	get_node("../../../CivilianManager").civilians_changed.connect(_refresh)
	get_node("../../../WorkerManager").workers_changed.connect(_refresh)
	_time.day_started.connect(func(_day: int) -> void: _refresh())
	_refresh()


# The time of day changes without any signal, so check it a few times a second.
var _shown_time := ""
func _process(_delta: float) -> void:
	var now: String = get_node("../../../DayNight").get_time_name()
	if now != _shown_time:
		_refresh()


func _refresh() -> void:
	_shown_time = get_node("../../../DayNight").get_time_name()
	var parts: Array[String] = ["Day %d, %s" % [_time.get_day(), _shown_time]]
	for type in ResourceManager.Type.values():
		parts.append("%s %d/%d" % [ResourceManager.NAMES[type], _resources.get_amount(type), _resources.get_capacity()])
	var state: String = PopulationManager.STATE_NAMES[_population.get_state()]
	parts.append("Happiness %d (%s)" % [_population.get_happiness(), state])
	parts.append("People %d (%d workers, %d civilians)" % [_population.get_population(), _population.get_worker_count(), _population.get_civilian_count()])
	# People against homes, like a resource against its limit: 14/14 means the
	# colony cannot grow until another House is built.
	parts.append("Homes %d/%d" % [_population.get_population(), _population.get_housing_capacity()])
	text = "      ".join(parts)
