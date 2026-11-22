# time_manager.gd
# The colony's calendar. Time is counted in in-game days, and anything that
# should take "3 days" listens to this script instead of counting seconds itself.
#
# One day lasts DAY_SECONDS of play. The clock stops whenever the game is paused,
# because paused nodes are not processed.
class_name TimeManager
extends Node

# Sent every frame with how much of a day has just gone by (a small fraction).
signal time_passed(days: float)
# Sent when a new day begins.
signal day_started(day: int)

const DAY_SECONDS := 20.0        # How long one in-game day lasts.

var _days := 0.0                 # Days gone by since the game began, with fractions.


func _process(delta: float) -> void:
	advance(delta / DAY_SECONDS)


# Moves the calendar forward. Tests call this to skip ahead.
func advance(days: float) -> void:
	if days <= 0.0:
		return
	var before := get_day()
	_days += days
	time_passed.emit(days)
	if get_day() != before:
		day_started.emit(get_day())


# The day shown on screen. The game begins on day 1.
func get_day() -> int:
	return int(_days) + 1


# Days gone by since the game began, with fractions.
func get_days() -> float:
	return _days


# ---------------------------------------------------------------- Save and load
# SaveManager calls these two (see save_manager.gd).

func get_save_data() -> Dictionary:
	return { "days": _days }


func load_save_data(data: Dictionary) -> void:
	_days = maxf(float(data.get("days", 0.0)), 0.0)
	day_started.emit(get_day())
