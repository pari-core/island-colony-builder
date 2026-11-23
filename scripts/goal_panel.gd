# goal_panel.gd
# Shows the goal of the game in the top left corner, with progress towards it,
# and warnings while the colony is in danger of losing.
extends Label

@onready var _game: GameStateManager = get_node("../../GameStateManager")
@onready var _population: PopulationManager = get_node("../../PopulationManager")
@onready var _builder: BuildingManager = get_node("../../BuildingManager")
@onready var _resources: ResourceManager = get_node("../../ResourceManager")
@onready var _construction: ConstructionManager = get_node("../../ConstructionManager")


func _ready() -> void:
	# Hidden once the game ends, because the end screen takes over.
	_game.state_changed.connect(_update_visible)


# Shown during play, except while the build menu is open, because its text uses
# the same space.
func _update_visible() -> void:
	var playing := _game.get_state() in [GameStateManager.State.PLAYING, GameStateManager.State.FREE_PLAY]
	visible = playing and not _builder.is_placing()


# Updated every frame. The text is short, so this costs almost nothing.
func _process(_delta: float) -> void:
	_update_visible()
	if _game.get_state() == GameStateManager.State.FREE_PLAY:
		text = "Free play: you have already won. Score %d" % _game.get_score()
		if _population.get_happiness() == 0:
			text += "\nHAPPINESS IS 0: people are leaving the colony"
		return
	var lines: Array[String] = ["Goal: %d people (now %d) and happiness %d (now %d)" % [
		QuickGame.win_population(), _population.get_population(),
		GameStateManager.WIN_HAPPINESS, _population.get_happiness(),
	]]
	lines.append(_landmark_line())
	var events: EventManager = get_node("../../EventManager")
	if not events.has_faced_all():
		lines.append("Both need all %d events faced first (%d so far)" % [EventManager.ORDER.size(), events.get_faced_count()])
	# New people only join while there is a free home, so say when there is none.
	if _population.get_population() >= _population.get_housing_capacity():
		var house: Dictionary = BuildingManager.BUILDINGS[0]
		lines.append("HOMES FULL (%d/%d): nobody new will join. Build a House (%s) for %d more people" % [
			_population.get_population(), _population.get_housing_capacity(),
			_resources.describe_cost(house.cost), PopulationManager.PEOPLE_PER_HOUSE,
		])
	var held := _game.get_win_cycles()
	if held > 0:
		var seconds := maxi(0, int((QuickGame.win_cycles() - held) * PopulationManager.UPKEEP_SECONDS))
		lines.append("Goal reached: hold it for %d more seconds to win" % seconds if seconds > 0 else "Goal reached: keep it until every event has been faced")
	if _game.get_starvation_seconds_left() >= 0:
		lines.append("STARVING: get food, or the colony is lost in %d s" % _game.get_starvation_seconds_left())
	if _game.get_storage_seconds_left() >= 0:
		lines.append("STORAGE ALL FULL: spend or upgrade a Warehouse, or lose in %d s" % _game.get_storage_seconds_left())
	if _population.get_happiness() == 0:
		lines.append("HAPPINESS IS 0: people are leaving the colony")
	text = "\n".join(lines)


# The second way to win: each landmark, and whether it is done or how far built.
func _landmark_line() -> String:
	var parts: Array[String] = []
	for landmark_name in GameStateManager.get_landmark_names():
		var plot := _game.get_landmark_plot(landmark_name)
		if plot == null:
			parts.append(landmark_name)
		elif plot.under_construction:
			parts.append("%s %d%%" % [landmark_name, int(_construction.get_progress(plot) * 100.0)])
		else:
			parts.append("%s done" % landmark_name)
	if QuickGame.on:
		return "Or: build any 1 landmark (%d done): %s" % [_game.get_landmarks_built(), ", ".join(parts)]
	return "Or: build all %d landmarks (%d done): %s" % [parts.size(), _game.get_landmarks_built(), ", ".join(parts)]
