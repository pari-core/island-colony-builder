# resource_manager.gd
# Keeps the colony's food, wood, stone and gold. Every change to a resource goes
# through this script, so its rules always apply:
#   - An amount can never go below zero.
#   - An amount can never go above the storage limit.
#   - Overflow rule: anything beyond the storage limit is lost.
#   - Each standing Warehouse raises the limit by WAREHOUSE_STORAGE for every
#     resource, times its level (1 to 3, see Warehouse upgrades). If a Warehouse collapses, the limit drops again, but nothing
#     already stored is thrown away: amounts above the limit stay, and nothing
#     more of that resource is stored until the amount falls below the limit.
class_name ResourceManager
extends Node

# The user interface listens to this signal, so it only updates when needed.
signal resources_changed

enum Type { FOOD, WOOD, STONE, GOLD }

const NAMES := {
	Type.FOOD: "Food",
	Type.WOOD: "Wood",
	Type.STONE: "Stone",
	Type.GOLD: "Gold",
}

# Starting values. These are first guesses, to be balanced once the game is playable.
const STARTING_AMOUNTS := {
	Type.FOOD: 150,
	Type.WOOD: 150,
	Type.STONE: 80,
	Type.GOLD: 20,
}
const STARTING_CAPACITY := 200
const WAREHOUSE_STORAGE := 200

var _amounts := STARTING_AMOUNTS.duplicate()
var _capacity := STARTING_CAPACITY

@onready var _map: MapManager = get_node("../MapManager")
@onready var _research: ResearchManager = get_node("../ResearchManager")


func get_amount(type: Type) -> int:
	return _amounts[type]


func get_capacity() -> int:
	return _capacity


# Works out the storage limit again from the standing Warehouses and the Storage
# Engineering research. Called when a building is placed, collapses or is
# repaired, and when research finishes.
func refresh_storage() -> void:
	var warehouses := 0
	for plot in _map.get_plots():
		if plot.building_info.get("name", "") == "Warehouse" and not plot.is_damaged:
			warehouses += plot.level
	var capacity := int((STARTING_CAPACITY + warehouses * WAREHOUSE_STORAGE) * _research.get_storage_multiplier())
	if capacity != _capacity:
		_capacity = capacity
		resources_changed.emit()


# Adds to a resource and returns how much was really stored. The rest is lost.
func add(type: Type, amount: int) -> int:
	if amount <= 0:
		return 0
	var stored := clampi(_capacity - _amounts[type], 0, amount)
	_amounts[type] += stored
	resources_changed.emit()
	return stored


# A cost is a dictionary such as { Type.WOOD: 20, Type.STONE: 10 }.
func can_afford(cost: Dictionary) -> bool:
	for type in cost:
		if _amounts[type] < cost[type]:
			return false
	return true


# Takes the whole cost and returns true, or takes nothing and returns false.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for type in cost:
		_amounts[type] -= cost[type]
	resources_changed.emit()
	return true


# Turns a cost into text for the screen, such as "20 Wood, 10 Stone".
func describe_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for type in cost:
		parts.append("%d %s" % [cost[type], NAMES[type]])
	return ", ".join(parts)


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).


func get_save_data() -> Dictionary:
	var amounts := []
	for type in Type.values():
		amounts.append(_amounts[type])
	return { "amounts": amounts }


# Called after the buildings are back, so the storage limit is already right.
func load_save_data(data: Dictionary) -> void:
	refresh_storage()
	var amounts: Array = data.get("amounts", [])
	for type in Type.values():
		if type < amounts.size():
			_amounts[type] = clampi(int(amounts[type]), 0, _capacity)
	resources_changed.emit()
