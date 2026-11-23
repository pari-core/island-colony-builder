# event_manager.gd
# Runs the seven events from the project specification (section 15). Events come
# on a fixed schedule, in a fixed order, so every game plays the same way.
#
# Some events change output for a while; others need the player to respond:
#   Enter: accept a trade, send the sick to be vaccinated or send workers to repair.
#   N: decline a trade.
# These are separate functions, so the ESP32 Action button can call them later.
#
# Schedule: only one event happens at a time. When it ends, or the player has dealt
# with it, a calm period of CALM_SECONDS begins so the colony can recover. After
# that, the next event also waits until the colony has the resources to answer it
# (READY_NEEDS, for example wood and stone to repair a collapse), but never longer
# than MAX_EXTRA_WAIT, so a colony that saves nothing still meets every event.
# The visuals for each event are in event_effects.gd.
class_name EventManager
extends Node

# The user interface and visual effects listen to these.
signal events_changed
signal building_collapsed(plot: BuildingPlot)
signal building_repaired(plot: BuildingPlot)
# Sent when an outbreak is over. cured is true if every sick worker was treated
# with the vaccine, and false if the illness passed by itself.
signal disease_ended(cured: bool)

# STORM is last so saved games keep their numbers (it was removed and brought back).
enum Type { DROUGHT, DISCOVERY, DISEASE, TRADE, MIGRATION, ACCIDENT, STORM }

const NAMES := {
	Type.DROUGHT: "Drought",
	Type.DISCOVERY: "Resource discovery",
	Type.DISEASE: "Disease outbreak",
	Type.TRADE: "Trade opportunity",
	Type.MIGRATION: "Migration",
	Type.ACCIDENT: "Building accident",
	Type.STORM: "Storm",
}

# The order events happen in. After the last one, the list starts again.
# An easy event comes between the two missions, so the player gets a breather.
# Team decisions, 2026-11-23: the Building accident replaces the Trade
# opportunity, and the Storm is a sixth event. Trade still works (the tests and
# the debug tools can start it) but is left out of the schedule.
const ORDER := [Type.DISCOVERY, Type.DROUGHT, Type.ACCIDENT, Type.DISEASE, Type.STORM, Type.MIGRATION]

# First guesses, to be balanced once the game is playable.
const FIRST_EVENT_SECONDS := 60.0
const CALM_SECONDS := 90.0       # Quiet time after an event ends before the next can start.
const MAX_EXTRA_WAIT := 90.0     # Longest the next event waits for resources after the calm.
const DURATIONS := {             # Seconds each event lasts, or waits for a response.
	Type.DROUGHT: -1.0,          # Lasts until the drought mission ends it (see drought_mission.gd).
	Type.DISCOVERY: 60.0,
	Type.DISEASE: 120.0,         # Without treatment, the sick recover by themselves after this.
	Type.TRADE: 30.0,
	Type.MIGRATION: 40.0,        # Two in-game days to find the newcomers a home.
	Type.STORM: 60.0,
	Type.ACCIDENT: -1.0,         # -1 means it has no countdown: it lasts until the building is repaired.
}
const DROUGHT_FOOD := 0.5        # Food output multiplier during a drought.
const STORM_OUTPUT := 0.75       # All output multiplier during a storm.
const DISCOVERY_BONUS := 1.5     # Wood and stone output multiplier during a discovery.
const DISEASE_HAPPINESS := -5    # Happiness change when an outbreak starts.
# Once the vaccine is researched, treatment is free: the sick walk to the Research
# Lab and recover when they get there. Charging food would trap the colony, because
# sick Farm workers cannot grow it.
const TREATED_HAPPINESS := 10    # Happiness change when people are treated.
# The merchant captain's offers (team decision, 2026-11-20). They are worked out
# from what the colony holds when the ship arrives, so an offer never asks for
# more than the colony has, never leaves it short, and never pays more gold than
# there is room for:
#   - Timber: half the wood. Stone: half the stone. Timber and stone: a quarter
#     of each.
#   - Goods are rounded down to tens, and no offer takes more than TRADE_MAX of
#     one resource, so at least half of every store always stays at home.
#   - Every TRADE_GOODS_PER_GOLD wood or stone pays 1 gold. That is better than
#     the colony can do itself (wood is about 2.5 times easier to make than
#     gold), right for a once-a-game visitor, but not so good that the Mine
#     stops mattering.
#   - If the gold would not fit in storage, the offer is cut down to fit.
#   - An offer that would take less than TRADE_MIN in all is not made.
# Nothing is random: the same stores always give the same offers.
const TRADE_SHARE := 0.5
const TRADE_BOTH_SHARE := 0.25
const TRADE_MAX := 100
const TRADE_MIN := 20
const TRADE_GOODS_PER_GOLD := 2  # Wood or stone for each gold (team decision, 2026-11-20).
# Four newcomers: one House's worth (PEOPLE_PER_HOUSE), so the migration asks
# the player for exactly one new House. Team request, 2026-11-23: "more than 2".
const MIGRANTS := 4
const REPAIR_COST := { ResourceManager.Type.WOOD: 10, ResourceManager.Type.STONE: 5 }
const REPAIR_CREW := 2           # The most workers sent to repair.
const REPAIR_SECONDS := 20.0     # Work needed once the crew arrives (twice as long with one worker).
const NOTICE_SECONDS := 4.0
const DROUGHT_FOOD_STORE := { ResourceManager.Type.FOOD: 50 }

# Each active event is a dictionary with "type" and "time_left" (seconds, or -1),
# and for accidents also "plot", "crew" and "progress".
var _active: Array[Dictionary] = []
var _next_index := 0
var _faced := {}                 # The event types that have happened and ended, as keys.
var _timer := Timer.new()
var _notice := ""                # A short message, such as why a response failed.
var _notice_time := 0.0
var _waiting_for_resources := false   # The calm is over; the next event waits for resources.
var _extra_wait := 0.0

@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _population: PopulationManager = get_node("../PopulationManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _map: MapManager = get_node("../MapManager")
@onready var _research: ResearchManager = get_node("../ResearchManager")
@onready var _terrain: Node = get_node("../Island/Terrain")
@onready var _drought: DroughtMission = get_node("../DroughtMission")


func _ready() -> void:
	_timer.name = "EventTimer"
	_timer.wait_time = QuickGame.first_event()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_timer.start()


func _process(delta: float) -> void:
	_notice_time = maxf(_notice_time - delta, 0.0)
	# The calm period only counts down while no event is running.
	_timer.paused = not _active.is_empty()
	var changed := false
	for event in _active.duplicate():
		if event.type == Type.DISEASE and event.treating:
			changed = _update_treatment(event) or changed
		elif event.type == Type.ACCIDENT:
			changed = _update_repair(event, delta) or changed
		elif event.time_left >= 0.0:
			event.time_left -= delta
			if event.time_left <= 0.0:
				_end(event)
				changed = true
	if changed:
		events_changed.emit()
	# Checked after the events above, so a new event does not lose this frame's time.
	if _waiting_for_resources and _active.is_empty():
		_extra_wait += delta
		if is_ready_for_next() or _extra_wait >= QuickGame.max_extra_wait():
			_start_scheduled_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("event_respond"):
		respond()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("event_decline"):
		decline()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_next_event"):
		trigger_next()
		get_viewport().set_input_as_handled()


func get_active() -> Array[Dictionary]:
	return _active


func is_active(type: Type) -> bool:
	return _find(type) != null


func get_time_until_next() -> float:
	return _timer.time_left


# True once the calm is over and the next event is waiting for resources.
func is_waiting_for_resources() -> bool:
	return _waiting_for_resources


# Seconds left before the next event comes anyway, even without the resources.
func get_extra_wait_left() -> float:
	return maxf(QuickGame.max_extra_wait() - _extra_wait, 0.0)


func get_next_type() -> Type:
	return ORDER[_next_index]


# What the colony should have saved before the next event: enough to answer it.
# Events that need nothing return an empty dictionary.
func get_ready_needs() -> Dictionary:
	match get_next_type():
		Type.TRADE:
			# The ship comes once the captain has something to ask for.
			for offer in make_trade_offers():
				if offer.possible:
					return {}
			return { ResourceManager.Type.WOOD: TRADE_MIN * 2 }
		Type.ACCIDENT:
			return REPAIR_COST
		Type.DROUGHT:
			# Food to live on, and the materials for a Water Storage if there is none.
			var needs := DROUGHT_FOOD_STORE.duplicate()
			if not _drought.has_water_storage():
				needs.merge(_drought.get_building_cost())
			return needs
		Type.DISEASE:
			if not _research.is_finished("vaccine"):
				return ResearchManager.PROJECTS.vaccine.cost
	return {}


# A building site also holds the next event back, so a new event does not
# arrive while the colony is still busy building.
func is_ready_for_next() -> bool:
	return _resources.can_afford(get_ready_needs()) and get_node("../ConstructionManager").get_sites().is_empty()


# What the next event is waiting for, in words for the screen: an unfinished
# building first, then any resources still missing. "" if it is not waiting.
func get_wait_reason() -> String:
	var sites: Array = get_node("../ConstructionManager").get_sites()
	if not sites.is_empty():
		return "the %s is finished building" % (sites[0] as BuildingPlot).building_info.name
	var needs := get_ready_needs()
	if not _resources.can_afford(needs):
		var missing := {}
		for type in needs:
			if _resources.get_amount(type) < needs[type]:
				missing[type] = needs[type]
		return "you have %s" % _resources.describe_cost(missing)
	return ""


# True while an outbreak or a collapsed building still needs dealing with.
func is_waiting_for_player() -> bool:
	var accident = _find(Type.ACCIDENT)
	return is_active(Type.DISEASE) or (accident != null and accident.plot != null)


# Every second worker falls sick (the 1st, 3rd, 5th and so on), so an outbreak
# always hits the same people and about half the colony keeps working.
func get_patients() -> Array[Worker]:
	return _workers.get_workers().filter(func(worker: Worker) -> bool: return worker.is_sick)




func get_notice() -> String:
	return _notice if _notice_time > 0.0 else ""


# Multiplies a building's output while events are running.
func get_output_multiplier(resource: ResourceManager.Type) -> float:
	var multiplier := 1.0
	# The drought mission decides how hard a drought hits food, and gives a
	# short bonus after the colony beats one.
	if resource == ResourceManager.Type.FOOD:
		multiplier *= _drought.get_food_multiplier()
	if is_active(Type.STORM):
		multiplier *= STORM_OUTPUT
	if is_active(Type.DISCOVERY) and resource in [ResourceManager.Type.WOOD, ResourceManager.Type.STONE]:
		multiplier *= DISCOVERY_BONUS
	return multiplier


# Starts the next event in ORDER. The schedule timer calls this, and the debug key
# (F9) can call it to show events during testing and the demo.
# Starts the schedule again from the beginning: the first event comes after
# QuickGame.first_event() seconds. Called when a game is chosen on the main menu.
func restart_schedule() -> void:
	if not _timer.is_stopped():
		_timer.start(QuickGame.first_event())


func trigger_next() -> void:
	var type: Type = ORDER[_next_index]
	_next_index = (_next_index + 1) % ORDER.size()
	trigger(type)


func trigger(type: Type) -> void:
	if is_active(type):
		return
	var event := { "type": type, "time_left": QuickGame.duration(type), "plot": null, "crew": [], "progress": 0.0, "treating": false, "cured": false, "joined": 0, "offer": -1 }
	match type:
		Type.DISEASE:
			var workers := _workers.get_workers()
			for i in range(0, workers.size(), 2):
				workers[i].is_sick = true
			_population.change_happiness(DISEASE_HAPPINESS)
		Type.TRADE:
			event.offers = make_trade_offers()   # Fixed for as long as the ship waits.
		Type.MIGRATION:
			for i in MIGRANTS:
				if _workers.add_worker(get_beach_position()):
					event.joined += 1
		Type.ACCIDENT:
			event.plot = _first_building()
			if event.plot == null:
				event.time_left = 10.0   # Nothing to damage: just show the message briefly.
			else:
				event.plot.is_damaged = true
				building_collapsed.emit(event.plot)
				_resources.refresh_storage()
				_population.notify_housing_changed()
	_active.append(event)
	print("Event: %s" % NAMES[type])
	events_changed.emit()
	_workers.workers_changed.emit()


# How many of the scheduled events the colony has been through, from start to
# end. Both ways of winning need all of them (see game_state_manager.gd).
func get_faced_count() -> int:
	var count := 0
	for type: Type in ORDER:
		if _faced.has(type):
			count += 1
	return count


func has_faced_all() -> bool:
	return get_faced_count() == ORDER.size()


# Ends an event early. Missions use this: the drought ends when its mission does.
func end_event(type: Type) -> bool:
	var event = _find(type)
	if event == null:
		return false
	_end(event)
	events_changed.emit()
	return true


# Enter: responds to the first event that is waiting for a response.
func respond() -> bool:
	if is_active(Type.TRADE):
		# Enter takes the first offer that can be accepted; the board shows all three.
		if get_first_trade() < 0:
			return _fail("The captain has nothing to offer: decline (N)")
		return accept_trade(get_first_trade())
	var disease = _find(Type.DISEASE)
	if disease != null and not disease.treating:
		if not _research.is_finished("vaccine"):
			return _fail("No vaccine yet: select the Research Lab and press R")
		if not _research.has_working_lab():
			return _fail("Treatment needs a working Research Lab")
		disease.treating = true
		_workers.send_for_treatment(_research.get_working_lab(), get_patients())
		events_changed.emit()
		return true
	var accident = _find(Type.ACCIDENT)
	if accident != null and accident.plot != null and accident.crew.is_empty():
		if not _resources.can_afford(REPAIR_COST):
			return _fail("Not enough resources to repair")
		var crew := _workers.send_repair_crew(accident.plot, REPAIR_CREW)
		if crew.is_empty():
			return _fail("No idle workers: remove a worker from a job first (K)")
		_resources.spend(REPAIR_COST)
		accident.crew = crew
		events_changed.emit()
		return true
	return false


# The captain's offers for the colony's stores right now. Each is a dictionary:
# name, give (resources), gold, possible, and problem (why not, if not possible).
func make_trade_offers() -> Array[Dictionary]:
	var wood := ResourceManager.Type.WOOD
	var stone := ResourceManager.Type.STONE
	var room := maxi(_resources.get_capacity() - _resources.get_amount(ResourceManager.Type.GOLD), 0)
	var offers: Array[Dictionary] = [
		_make_offer("Timber", { wood: _trade_share(wood, TRADE_SHARE) }, room, "you have too little wood"),
		_make_offer("Stone", { stone: _trade_share(stone, TRADE_SHARE) }, room, "you have too little stone"),
		_make_offer("Timber and stone", { wood: _trade_share(wood, TRADE_BOTH_SHARE), stone: _trade_share(stone, TRADE_BOTH_SHARE) }, room, "you have too little wood and stone"),
	]
	# The mixed offer only makes sense with some of each.
	var both := offers[2]
	if both.possible and both.give.size() < 2:
		both.possible = false
		both.problem = "Not offered: you have too little wood and stone"
	return offers


# The offers on the table: fixed when the ship arrived, so they do not change
# while the player is choosing. Before a ship comes, the offers it would make.
func get_trade_offers() -> Array[Dictionary]:
	var trade = _find(Type.TRADE)
	if trade != null and trade.has("offers"):
		return trade.offers
	return make_trade_offers()


func _trade_share(type: ResourceManager.Type, share: float) -> int:
	return mini(int(_resources.get_amount(type) * share) / 10 * 10, TRADE_MAX)


func _make_offer(offer_name: String, give: Dictionary, room: int, too_little: String) -> Dictionary:
	var total := 0
	for type in give:
		total += give[type]
	var problem := ""
	# Cut the goods down so the gold fits in storage.
	if total / TRADE_GOODS_PER_GOLD > room:
		var scale := float(room) / float(total / TRADE_GOODS_PER_GOLD)
		total = 0
		for type in give.keys():
			give[type] = int(give[type] * scale) / 10 * 10
			total += give[type]
		too_little = "your gold store is full"
	for type in give.keys():
		if give[type] == 0:
			give.erase(type)
	if total < TRADE_MIN:
		problem = "Not offered: %s" % too_little
	return { "name": offer_name, "give": give, "gold": total / TRADE_GOODS_PER_GOLD, "possible": problem == "", "problem": problem }


# Accepts one of the captain's offers (an index into get_trade_offers()): gives
# the goods and takes the gold, then the ship leaves. Returns false if it cannot
# be accepted, and nothing changes.
func accept_trade(offer: int) -> bool:
	var trade = _find(Type.TRADE)
	var offers := get_trade_offers()
	if trade == null or offer < 0 or offer >= offers.size():
		return false
	if get_trade_problem(offer) != "":
		return _fail(get_trade_problem(offer))
	var deal: Dictionary = offers[offer]
	_resources.spend(deal.give)
	_resources.add(ResourceManager.Type.GOLD, deal.gold)
	trade.offer = offer
	_end(trade)
	events_changed.emit()
	return true


# Why an offer cannot be accepted now, or "" if it can.
func get_trade_problem(offer: int) -> String:
	var deal: Dictionary = get_trade_offers()[offer]
	if not deal.possible:
		return deal.problem
	for type in deal.give:
		if _resources.get_amount(type) < deal.give[type]:
			return "Needs %s, you have %d" % [_resources.describe_cost(deal.give), _resources.get_amount(type)]
	return ""


# The first offer that can be accepted, or -1 if none can.
func get_first_trade() -> int:
	for i in get_trade_offers().size():
		if get_trade_problem(i) == "":
			return i
	return -1


# N: turns down a trade offer.
func decline() -> bool:
	var trade = _find(Type.TRADE)
	if trade == null:
		return false
	_end(trade)
	events_changed.emit()
	return true


# A spot on the eastern beach, where migrants and traders arrive.
func get_beach_position() -> Vector3:
	var x := 200.0
	while x > 0.0 and _terrain.get_height_at(x, 0.0) < 0.6:
		x -= 1.0
	return Vector3(x, _terrain.get_height_at(x, 0.0), 0.0)


# Describes an active event for the screen, including how to respond.
func describe(event: Dictionary) -> String:
	var time := "" if event.time_left < 0.0 else " (%d s)" % ceili(event.time_left)
	var text := ""
	match event.type:
		Type.DROUGHT: text = _drought.describe()
		Type.STORM: text = "Storm: all production slowed to 75%"
		Type.DISCOVERY: text = "Wood and stone production +50%"
		Type.DISEASE:
			var sick := "%d of %d workers sick and not working" % [get_patients().size(), _workers.get_workers().size()]
			if event.treating:
				text = "%d sick workers walking to the Research Lab for the vaccine" % get_patients().size()
			elif _research.is_finished("vaccine"):
				text = "%s. Enter: send them to the Research Lab for the vaccine" % sick
			elif _research.get_current() == "vaccine":
				text = "%s. Vaccine research: %d%%" % [sick, int(_research.get_progress() * 100.0)]
			else:
				text = "%s. Research a vaccine at the Research Lab (R), or wait" % sick
		Type.TRADE:
			var first := get_first_trade()
			if first < 0:
				text = "A merchant ship waits for your answer. N: decline"
			else:
				var deal: Dictionary = get_trade_offers()[first]
				text = "A merchant ship waits for your answer. Enter: give %s for %d Gold, N: decline" % [_resources.describe_cost(deal.give), deal.gold]
		Type.MIGRATION: text = "%d new workers arrived by sea: they need homes and food" % event.joined
		Type.ACCIDENT:
			if event.plot == null:
				text = "No buildings were damaged"
			elif event.crew.is_empty():
				text = "%s on plot %d collapsed. Enter: send workers to repair (%s)" % [event.plot.building_info.name, event.plot.plot_id, _resources.describe_cost(REPAIR_COST)]
			else:
				text = "Repairing %s: %d%%" % [event.plot.building_info.name, int(event.progress * 100.0)]
	return "%s%s: %s" % [NAMES[event.type], time, text]


# The calm period is over. Start the next event now if the colony is ready for it,
# otherwise wait (see _process).
func _on_timer() -> void:
	if is_ready_for_next():
		_start_scheduled_event()
	else:
		_waiting_for_resources = true
		_extra_wait = 0.0


func _start_scheduled_event() -> void:
	_waiting_for_resources = false
	trigger_next()
	# The timer is paused while the event runs, and starts again from the full calm
	# period when the event ends (see _end).
	_timer.start(QuickGame.calm())


# Each sick worker recovers on reaching the Research Lab. When the last one is
# treated, the outbreak ends and happiness rises. Returns true if anything changed.
func _update_treatment(event: Dictionary) -> bool:
	var changed := false
	for worker in get_patients():
		if worker.treatment_plot != null and not worker.is_moving():
			_workers.finish_treatment(worker)
			changed = true
	if get_patients().is_empty():
		_population.change_happiness(TREATED_HAPPINESS)
		event.cured = true
		_end(event)
		return true
	return changed


# Repair moves forward only while crew members are at the building. Returns true
# if the screen needs updating.
func _update_repair(event: Dictionary, delta: float) -> bool:
	if event.plot == null:
		event.time_left -= delta
		if event.time_left <= 0.0:
			_end(event)
			return true
		return false
	var working := 0
	for worker in event.crew:
		if not worker.is_moving():
			working += 1
	if working == 0:
		return false
	var before := int(event.progress * 100.0)
	event.progress += delta * working / (REPAIR_SECONDS * REPAIR_CREW)
	if event.progress >= 1.0:
		_end(event)
		return true
	return int(event.progress * 100.0) != before


func _end(event: Dictionary) -> void:
	if event.type == Type.DISEASE:
		for worker in _workers.get_workers():
			worker.is_sick = false
			worker.treatment_plot = null
		_workers.refresh_targets()
	if event.type == Type.ACCIDENT and event.plot != null:
		event.plot.is_damaged = false
		building_repaired.emit(event.plot)
		if not event.crew.is_empty():
			_workers.release_repair_crew(event.crew)
	_active.erase(event)
	_faced[event.type] = true
	# The calm begins once nothing is happening. A stopped timer means the schedule
	# was switched off (the tests do this), so it stays off.
	if _active.is_empty() and not _timer.is_stopped():
		_timer.start(QuickGame.calm())
	_resources.refresh_storage()
	_population.notify_housing_changed()
	_workers.workers_changed.emit()
	if event.type == Type.DISEASE:
		disease_ended.emit(event.cured)


func _fail(message: String) -> bool:
	_notice = message
	_notice_time = NOTICE_SECONDS
	return false


func _find(type: Type):
	for event in _active:
		if event.type == type:
			return event
	return null


# The building that collapses: the one with the lowest plot number, so the result
# is always the same.
func _first_building() -> BuildingPlot:
	for plot in _map.get_plots():
		if plot.building != null and not plot.is_damaged and not plot.under_construction:
			return plot
	return null


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


# Only the schedule is saved. The game cannot be saved while an event is
# happening, so there is never an active event to store.
func get_save_data() -> Dictionary:
	return {
		"next_index": _next_index,
		"calm_left": _timer.time_left,
		"waiting": _waiting_for_resources,
		"extra_wait": _extra_wait,
		"faced": _faced.keys(),
	}


func load_save_data(data: Dictionary) -> void:
	_next_index = posmod(int(data.get("next_index", 0)), ORDER.size())
	_waiting_for_resources = bool(data.get("waiting", false))
	_extra_wait = float(data.get("extra_wait", 0.0))
	_faced.clear()
	for type in data.get("faced", []):
		_faced[int(type)] = true
	if _waiting_for_resources:
		_timer.stop()
	else:
		var left := float(data.get("calm_left", 0.0))
		_timer.start(left if left > 0.0 and left < QuickGame.calm() else QuickGame.calm())
	events_changed.emit()
