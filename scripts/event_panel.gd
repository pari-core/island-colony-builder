# event_panel.gd
# Lists active events on the right of the screen, with how to respond.
extends Label

@onready var _events: EventManager = get_node("../../EventManager")
@onready var _resources: ResourceManager = get_node("../../ResourceManager")


# Updated every frame, because the countdowns change every second.
func _process(_delta: float) -> void:
	var lines: Array[String] = []
	for event in _events.get_active():
		lines.append(_events.describe(event))
	if _events.is_waiting_for_player():
		lines.append("Next event waits until this is dealt with")
	elif not lines.is_empty():
		lines.append("Then %d s of calm before the next event" % int(EventManager.CALM_SECONDS))
	elif _events.is_waiting_for_resources():
		lines.append("Next event (%s) waits until %s, at most %d s" % [EventManager.NAMES[_events.get_next_type()], _events.get_wait_reason(), ceili(_events.get_extra_wait_left())])
	else:
		lines.append("Calm: next event in %d s" % ceili(_events.get_time_until_next()))
	if _events.get_notice() != "":
		lines.append(_events.get_notice())
	text = "\n".join(lines)
