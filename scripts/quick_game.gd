# quick_game.gd
# The short game for the live demo, chosen on the main menu as "Quick Game".
# Team requests, 2026-11-23: first "within 5 mins", then "each event 1 min,
# total gameplay 7-8 min" once the Storm became a sixth event.
#
# The rules stay the same; only the clock and the finish line move:
#   - the first event comes after 15 s instead of 60 s, and the calm between
#     events is 15 s instead of 90 s
#   - every event lasts about 1 minute: 15 + 6 x 60 + 5 x 15 = 450 s, 7.5 min
#     (the drought is 3 short days; an accident lasts until it is repaired)
#   - buildings and the drought take half as many days
#   - one landmark (any of the three) wins instead of all three, or 18 people
#     instead of 24 for 2 good cycles instead of 3
# All five events must still be faced to win, as in the full game.
#
# QuickGame.on is static, so every script can ask it. It is false in the full
# game and in the tests.
class_name QuickGame
extends RefCounted

static var on := false

const FIRST_EVENT_SECONDS := 15.0
const CALM_SECONDS := 15.0
const MAX_EXTRA_WAIT := 10.0
const DURATIONS := {             # Seconds, by EventManager.Type name.
	"DROUGHT": -1.0, "DISCOVERY": 60.0, "DISEASE": 60.0, "STORM": 60.0,
	"TRADE": 60.0, "MIGRATION": 60.0, "ACCIDENT": -1.0,
}
const DAYS_SCALE := 0.5          # Building and drought days.
const LANDMARKS_TO_WIN := 1
const WIN_POPULATION := 18
const WIN_CYCLES := 2


static func first_event() -> float:
	return FIRST_EVENT_SECONDS if on else EventManager.FIRST_EVENT_SECONDS


static func calm() -> float:
	return CALM_SECONDS if on else EventManager.CALM_SECONDS


static func max_extra_wait() -> float:
	return MAX_EXTRA_WAIT if on else EventManager.MAX_EXTRA_WAIT


static func duration(type: EventManager.Type) -> float:
	if on:
		return DURATIONS[EventManager.Type.keys()[type]]
	return EventManager.DURATIONS[type]


static func days(full_days: float) -> float:
	return full_days * DAYS_SCALE if on else full_days


static func landmarks_to_win() -> int:
	return LANDMARKS_TO_WIN if on else GameStateManager.get_landmarks().size()


static func win_population() -> int:
	return WIN_POPULATION if on else GameStateManager.WIN_POPULATION


static func win_cycles() -> int:
	return WIN_CYCLES if on else GameStateManager.WIN_CYCLES
