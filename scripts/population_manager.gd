# population_manager.gd
# Feeds and houses the colony's people, and tracks happiness from 0 to 100.
# The population is the workers plus the civilians.
#
# Every upkeep cycle:
#   1. Everyone eats food: workers more than civilians. If there is not enough,
#      the colony is hungry.
#   2. Happiness rises if everyone was fed and falls if not.
#   3. Happiness falls a little for every person without a home. The landing camp
#      homes the first CAMP_HOMES people; each House homes PEOPLE_PER_HOUSE more.
#   4. Population grows by one civilian after GROWTH_CYCLES good cycles in a row: everyone
#      fed, everyone housed and a free space in a House. (New workers arrive
#      through the Migration event.)
# Happiness sets the population state, which changes how much workers produce.
# Nothing here is random, so the same choices always give the same result.
class_name PopulationManager
extends Node

# The user interface listens to this, so it updates when anything here changes.
signal population_changed
# GameStateManager listens to these to check the win and lose conditions.
signal upkeep_started
signal upkeep_finished

enum State { STRUGGLING, STABLE, THRIVING }

const STATE_NAMES := {
	State.STRUGGLING: "Struggling",
	State.STABLE: "Stable",
	State.THRIVING: "Thriving",
}
# How much workers produce in each state, compared with normal.
const PRODUCTIVITY := {
	State.STRUGGLING: 0.75,
	State.STABLE: 1.0,
	State.THRIVING: 1.25,
}

# First guesses, to be balanced once the game is playable.
const UPKEEP_SECONDS := 10.0
const FOOD_PER_WORKER := 2
const FOOD_PER_CIVILIAN := 1
const PEOPLE_PER_HOUSE := 4
const CAMP_HOMES := 10           # The landing camp shelters the first settlers, so nobody
                                 # is homeless at the start. Houses are needed to grow.
const STARTING_HAPPINESS := 60
const FED_CHANGE := 2            # Added when everyone was fed.
const HUNGRY_CHANGE := -10       # Added when there was not enough food.
const HOMELESS_CHANGE := -1      # Added for each person without a home.
const THRIVING_FROM := 70        # Happiness at or above this is Thriving.
const STABLE_FROM := 40          # Happiness at or above this is Stable.
const GROWTH_CYCLES := 2         # Good cycles in a row needed for a new civilian.

var _happiness := STARTING_HAPPINESS
var _was_fed := true
var _good_cycles := 0

@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _map: MapManager = get_node("../MapManager")
@onready var _civilians: CivilianManager = get_node("../CivilianManager")


func _ready() -> void:
	var timer := Timer.new()
	timer.name = "UpkeepTimer"
	timer.wait_time = UPKEEP_SECONDS
	timer.timeout.connect(upkeep)
	add_child(timer)
	timer.start()


func get_happiness() -> int:
	return _happiness


func get_state() -> State:
	if _happiness >= THRIVING_FROM:
		return State.THRIVING
	if _happiness >= STABLE_FROM:
		return State.STABLE
	return State.STRUGGLING


func get_productivity() -> float:
	return PRODUCTIVITY[get_state()]


func was_fed() -> bool:
	return _was_fed


func get_population() -> int:
	return _workers.get_workers().size() + _civilians.get_count()


func get_worker_count() -> int:
	return _workers.get_workers().size()


func get_civilian_count() -> int:
	return _civilians.get_count()


func get_housing_capacity() -> int:
	var houses := 0
	for plot in _map.get_plots():
		# A collapsed House gives no homes until it is repaired.
		if plot.building_info.get("name", "") == "House" and not plot.is_damaged:
			houses += 1
	return CAMP_HOMES + houses * PEOPLE_PER_HOUSE


func get_homeless() -> int:
	return maxi(0, get_population() - get_housing_capacity())


func get_food_needed() -> int:
	return get_worker_count() * FOOD_PER_WORKER + get_civilian_count() * FOOD_PER_CIVILIAN


# One upkeep cycle. The timer calls this, and tests can call it directly.
func upkeep() -> void:
	upkeep_started.emit()
	var needed := get_food_needed()
	var food := _resources.get_amount(ResourceManager.Type.FOOD)
	_was_fed = food >= needed
	# Eat what there is. spend() never lets the amount go below zero.
	_resources.spend({ ResourceManager.Type.FOOD: mini(needed, food) })

	var change := FED_CHANGE if _was_fed else HUNGRY_CHANGE
	change += get_homeless() * HOMELESS_CHANGE
	var old_state := get_state()
	_happiness = clampi(_happiness + change, 0, 100)
	if get_state() != old_state:
		print("Colony is now %s" % STATE_NAMES[get_state()])

	# Growth: only while fed, fully housed and with room in a House.
	if _was_fed and get_homeless() == 0 and get_population() < get_housing_capacity():
		_good_cycles += 1
		if _good_cycles >= GROWTH_CYCLES:
			_good_cycles = 0
			if _civilians.add_civilian():
				print("A new civilian joined the colony")
	else:
		_good_cycles = 0
	population_changed.emit()
	upkeep_finished.emit()


# Events use this to raise or lower happiness. It stays between 0 and 100.
func change_happiness(amount: int) -> void:
	_happiness = clampi(_happiness + amount, 0, 100)
	population_changed.emit()


# Called when Houses are built, collapse or are repaired, so homes and the
# housing numbers on screen stay current.
func notify_housing_changed() -> void:
	_civilians.update_homes()
	population_changed.emit()


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


func get_save_data() -> Dictionary:
	return {
		"happiness": _happiness,
		"was_fed": _was_fed,
		"good_cycles": _good_cycles,
		"upkeep_left": get_node("UpkeepTimer").time_left,
	}


func load_save_data(data: Dictionary) -> void:
	_happiness = clampi(int(data.get("happiness", STARTING_HAPPINESS)), 0, 100)
	_was_fed = bool(data.get("was_fed", true))
	_good_cycles = int(data.get("good_cycles", 0))
	# Carry on from where the countdown to the next meal was. start() also changes
	# the timer's usual wait, so that is put back straight away.
	var timer: Timer = get_node("UpkeepTimer")
	var left := float(data.get("upkeep_left", 0.0))
	timer.start(left if left > 0.0 and left < UPKEEP_SECONDS else UPKEEP_SECONDS)
	timer.wait_time = UPKEEP_SECONDS
	population_changed.emit()
