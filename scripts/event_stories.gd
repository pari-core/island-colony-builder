# event_stories.gd
# Stories for the lighter events: Resource discovery, Building accident, Trade
# opportunity and Migration. The two missions have their own scripts (drought_mission.gd
# and disease_mission.gd).
#
# EventManager still decides when each event starts and what it does. This
# script adds the telling: an opening story, the trade's decision board, and a
# closing story that depends on what the player did.
#
#   A LUCKY FIND (Resource discovery): workers find a grove and a hillside of
#     loose stone. Lumber Camps and Quarries make 50% more for a while. The
#     ending says how much was gathered, or that the find went unused.
#   THE MERCHANT'S SAIL (Trade opportunity): a ship offers gold for wood. A
#     board asks for an answer: accept or decline. Each has its own ending.
#   NEW ARRIVALS (Migration): two workers arrive by ship (see migration_boat.gd). The player has two
#     in-game days to make sure everyone has a home. If they do, the colony is
#     a little happier; if not, the ending says who is left without one.
#
# The story text is in the constants below, so it is easy to edit.
class_name EventStories
extends Node

const E := EventManager.Type
const T := ResourceManager.Type
const WELCOME_HAPPINESS := 3     # Given when the newcomers all have a home in time.

const FIND_TITLE := "A LUCKY FIND"
const FIND_STORY := [
	"At dawn, two workers set out along the old forest path to look for fresh timber. By midday they had not returned, and the colony began to worry.",
	"Then they came running back, out of breath and grinning. Beyond the trees they had discovered a grove of tall, straight oaks, and beside it a hillside of loose stone that splits cleanly with a single blow.",
	"The find will not last. Once the best trees are felled and the loose stone is carried off, the work will be as hard as ever. For now, every swing of the axe and the pick counts for more.",
]
const FIND_USED := "The last of the tall oaks has been felled and the loose stone is gone. The workers who found them are the heroes of the evening meal, and the colony's stores are fuller for it."
const FIND_UNUSED := "The grove and the hillside were left almost untouched. With nobody sent to work them, the best of the find has gone to waste. Next time, have workers at a Lumber Camp and a Quarry."

const TRADE_TITLE := "THE MERCHANT'S SAIL"
const TRADE_STORY := [
	"A sail has appeared on the horizon. By the time the lookout reaches the square, a merchant ship is already dropping anchor off the eastern beach.",
	"Her captain comes ashore with an offer. His shipwrights are short of timber, and the harbour he trades from needs stone for its wall. He will pay in gold for either, or for both, but he knows a colony cannot sell what it needs to survive.",
	"Gold is hard to come by here, but wood is what builds the colony's houses. The captain will not wait long. The decision is yours.",
]
const TRADE_ACCEPTED := "The cargo of %s is rowed out to the ship, and a small chest of gold is carried up the beach. The captain tips his hat and promises to speak well of the colony in every port."
const TRADE_DECLINED := "The captain shrugs, wishes the colony well and returns to his ship. By evening the sail is a speck on the horizon, and the wood is still in the stores."

const ACCIDENT_TITLE := "A BUILDING COLLAPSES"
const ACCIDENT_START := "BUILDING ACCIDENT!\nThe %s has collapsed and makes nothing until it is repaired.\nPress Action (Space) to send 2 idle workers to repair it for %s."
const ACCIDENT_NOTHING := "A tremor shakes the island, but there is nothing built yet to damage."
const ACCIDENT_END := "REPAIRED!\nThe %s is standing again and back at work."

const STORM_TITLE := "THE GREAT STORM"
const STORM_START := "STORM!\nWind and rain lash the island: all production slows to 75%% for %d seconds.\nKeep everyone working and wait it out."
const STORM_END := "THE STORM HAS PASSED\nThe skies clear and production is back to normal."

const ARRIVAL_TITLE := "NEW ARRIVALS"
const ARRIVAL_STORY := [
	"A sailing ship has been sighted, heading for the eastern beach. It sits low in the water, and the people on its deck are waving.",
	"They are settlers from a village further down the coast, driven out by a failed harvest. They have heard of your colony, and they ask for nothing but a chance to work.",
	"More hands will help the colony grow. But they must eat, and they need a roof over their heads. If there is no room for them, the whole colony will feel it.",
]
const ARRIVAL_FULL := "A sailing ship anchors off the eastern beach, but the colony already has all the workers it can hold. The travellers rest a while, share their news and sail on."
const ARRIVAL_HOUSED := "The newcomers have settled in. There is a bed for everyone, and in the evening their voices join the others around the fire. The colony feels a little more like home."
const ARRIVAL_HOMELESS := "The newcomers are working hard, but there are not enough beds. Some of the colony are sleeping in the open, and people are beginning to grumble."

var _running := {}               # Which of the three events were active at the last check.
var _awaiting_trade := false     # The trade's story is being told; the question comes next.
var _trade_answer := ""          # "accepted" or "declined", once the board is answered.
var _trade_offer := 0            # Which of the captain's offers was accepted.
var _trade_deal := {}            # That offer, kept for the closing story.
var _gathered := { T.WOOD: 0, T.STONE: 0 }   # Made during the current discovery.
var _joined := 0                 # Workers who arrived in the current migration.
var _collapsed := ""             # The building the current accident damaged.

@onready var _events: EventManager = get_node("../EventManager")
@onready var _workers: WorkerManager = get_node("../WorkerManager")
@onready var _resources: ResourceManager = get_node("../ResourceManager")
@onready var _population: PopulationManager = get_node("../PopulationManager")
@onready var _menu: ControllerMenu = get_node("../ControllerMenu")
@onready var _story: StoryBox = get_node("../UI/StoryBox")


func _ready() -> void:
	_events.events_changed.connect(_on_events_changed)
	_workers.produced.connect(_on_produced)
	_story.story_finished.connect(_on_story_finished)


# How much wood and stone the current (or last) discovery has brought in.
func get_gathered(type: ResourceManager.Type) -> int:
	return _gathered.get(type, 0)


# The answers on the trade's board: the captain's three offers, then decline.
# ControllerMenu shows them. An offer the colony cannot afford says why.
func get_trade_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var offers := _events.get_trade_offers()
	for i in offers.size():
		var deal: Dictionary = offers[i]
		var terms: String = "Give %s, receive %d Gold." % [_resources.describe_cost(deal.give), deal.gold] if deal.possible else deal.problem + "."
		items.append({
			"text": "%s\n     %s" % [deal.name, terms],
			"action": func() -> bool:
				_trade_answer = "accepted"
				_trade_offer = i
				_trade_deal = deal
				if _events.accept_trade(i):
					return true
				_trade_answer = ""
				return false,
			"problem": _events.get_trade_problem(i),
			"closes": true,
		})
	items.append({
		"text": "Decline\n     Keep everything. The ship sails on.",
		"action": func() -> bool:
			_trade_answer = "declined"
			return _events.decline(),
		"closes": true,
	})
	return items


# Compares what is active now with last time, to see what started and ended.
func _on_events_changed() -> void:
	for type: EventManager.Type in [E.DISCOVERY, E.TRADE, E.MIGRATION, E.ACCIDENT, E.STORM]:
		var active := _events.is_active(type)
		var was: bool = _running.get(type, false)
		_running[type] = active
		if not StoryBox.enabled:
			continue
		if active and not was:
			_started(type)
		elif was and not active:
			_ended(type)


func _started(type: EventManager.Type) -> void:
	match type:
		E.STORM:
			_story.tell(STORM_TITLE, [STORM_START % int(QuickGame.duration(E.STORM))], "cloud")
		E.DISCOVERY:
			_gathered = { T.WOOD: 0, T.STONE: 0 }
			var pages := FIND_STORY.duplicate()
			var notice := "RESOURCE DISCOVERY!\nLumber Camps and Quarries make %d%% more for %d seconds." % [roundi((EventManager.DISCOVERY_BONUS - 1.0) * 100.0), int(QuickGame.duration(E.DISCOVERY))]
			if _count_gatherers() == 0:
				notice += "\nNobody is working at one yet: send workers there now to make the most of it."
			else:
				notice += "\n%d of your workers are there to make the most of it." % _count_gatherers()
			pages.append(notice)
			_story.tell(FIND_TITLE, pages, "star")
		E.ACCIDENT:
			var accident: Dictionary = _events.get_active().filter(func(e: Dictionary) -> bool: return e.type == E.ACCIDENT)[0]
			if accident.plot == null:
				_collapsed = ""
				_story.tell(ACCIDENT_TITLE, [ACCIDENT_NOTHING], "hammer")
				return
			_collapsed = (accident.plot as BuildingPlot).building_info.name
			_story.tell(ACCIDENT_TITLE, [ACCIDENT_START % [_collapsed, _resources.describe_cost(EventManager.REPAIR_COST)]], "hammer")
		E.TRADE:
			_trade_answer = ""
			_awaiting_trade = true
			_story.tell(TRADE_TITLE, TRADE_STORY, "coin")
		E.MIGRATION:
			var event: Dictionary = _events.get_active().filter(func(e: Dictionary) -> bool: return e.type == E.MIGRATION)[0]
			_joined = event.joined
			if _joined == 0:
				_story.tell(ARRIVAL_TITLE, [ARRIVAL_FULL], "boat")
				return
			var names: Array[String] = []
			for worker in _workers.get_workers().slice(-_joined):
				names.append(worker.worker_name)
			var pages := ARRIVAL_STORY.duplicate()
			pages.append("MIGRATION!\n%d new workers have joined the colony: %s.\nEach eats %d food at every meal." % [_joined, _list(names), PopulationManager.FOOD_PER_WORKER])
			var homeless := _population.get_homeless()
			var days := maxi(1, roundi(QuickGame.duration(E.MIGRATION) / TimeManager.DAY_SECONDS))
			if homeless > 0:
				pages.append("MISSION: MAKE THEM WELCOME\n%d people have no home. Build a House (it holds %d) within %d days, so that everyone has a bed." % [homeless, PopulationManager.PEOPLE_PER_HOUSE, days])
			else:
				pages.append("MISSION: MAKE THEM WELCOME\nThere is a bed for everyone. Keep it that way for %d days and the newcomers will settle in." % days)
			_story.tell(ARRIVAL_TITLE, pages, "boat")


func _ended(type: EventManager.Type) -> void:
	match type:
		E.STORM:
			_story.tell(STORM_TITLE, [STORM_END], "cloud")
		E.ACCIDENT:
			if _collapsed != "":
				_story.tell(ACCIDENT_TITLE, [ACCIDENT_END % _collapsed], "hammer")
		E.DISCOVERY:
			var wood: int = _gathered[T.WOOD]
			var stone: int = _gathered[T.STONE]
			if wood + stone == 0:
				_story.tell(FIND_TITLE, [FIND_UNUSED, "THE FIND IS SPENT\nNo wood or stone was gathered while it lasted."], "star")
			else:
				_story.tell(FIND_TITLE, [FIND_USED, "EVENT COMPLETED - A LUCKY FIND\nGathered while the find lasted: %d Wood and %d Stone." % [wood, stone]], "star")
		E.TRADE:
			_awaiting_trade = false
			if _menu.get_mode() == ControllerMenu.Mode.CHOICE:
				_menu.close_menu()
			if _trade_answer == "accepted":
				var deal: Dictionary = _trade_deal
				var cargo := "timber and stone" if deal.give.size() == 2 else "stone" if deal.give.has(T.STONE) else "timber"
				_story.tell(TRADE_TITLE, [TRADE_ACCEPTED % cargo, "TRADE COMPLETED - %s\n%s given. %d Gold received." % [deal.name.to_upper(), _resources.describe_cost(deal.give), deal.gold]], "coin")
			else:
				_story.tell(TRADE_TITLE, [TRADE_DECLINED, "THE SHIP HAS SAILED\nNothing given, nothing gained."], "coin")
		E.MIGRATION:
			if _joined == 0:
				return
			var homeless := _population.get_homeless()
			if homeless == 0:
				_population.change_happiness(WELCOME_HAPPINESS)
				_story.tell(ARRIVAL_TITLE, [ARRIVAL_HOUSED, "EVENT COMPLETED - NEW ARRIVALS\nEveryone has a home. Happiness +%d." % WELCOME_HAPPINESS], "boat")
			else:
				_story.tell(ARRIVAL_TITLE, [ARRIVAL_HOMELESS, "NO ROOM FOR EVERYONE\n%d people have no home. Happiness falls at every meal until Houses are built for them." % homeless], "boat")


# After the trade's story, the board asks for an answer.
func _on_story_finished() -> void:
	if _awaiting_trade and _events.is_active(E.TRADE):
		_awaiting_trade = false
		_menu.open_choice("What will you tell the captain?", get_trade_items)


# "Gita, Hari, Isla and Jai".
static func _list(names: Array[String]) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]


# Counts what the discovery brings in, for the closing story.
func _on_produced(plot: BuildingPlot, stored: int) -> void:
	if _events.is_active(E.DISCOVERY) and _gathered.has(plot.building_info.produces):
		_gathered[plot.building_info.produces] += stored


# Workers who have a job making wood or stone.
func _count_gatherers() -> int:
	var count := 0
	for worker in _workers.get_workers():
		if worker.job_plot != null and worker.job_plot.building_info.get("produces", -1) in [T.WOOD, T.STONE]:
			count += 1
	return count
