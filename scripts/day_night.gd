# day_night.gd
# Day and night. The sky turns once every CYCLE_DAYS in-game days (100 seconds
# of play): the sun rises in the east, crosses the sky and sets in the west, the
# sky glows orange at dusk, and then comes a short, moonlit night.
#
# The night is dim and blue but never black, so the colony can still be seen
# and played. Nothing here changes the rules of the game: it only moves and
# colours the light. Time stops while the game is paused, so the sky does too.
#
# The storm and the drought set the weather's light (see event_effects.gd); this
# script takes that and dims and tints it for the time of day, every frame.
class_name DayNight
extends Node

# Tests switch this off, so the light stays as it was at midday and screenshots
# and brightness checks do not depend on how long a test has run.
static var enabled := true

# One turn of the sky lasts this many in-game days. A single day (20 seconds)
# made the night flash by, so the sky turns more slowly than the calendar.
# The calendar, and everything that counts days, is unchanged.
const CYCLE_DAYS := 5.0
const START := 0.12              # The game begins this far into the first cycle: mid-morning.
const DAY_PART := 0.7            # Fraction of each day the sun is up; the rest is night.
const TWILIGHT := 0.07           # Fraction spent fading at dawn and at dusk.
const NOON_ELEVATION := 45.0     # Degrees above the horizon at midday.
const LOW_ELEVATION := 6.0       # Degrees above the horizon at sunrise and sunset.
const SUN_AZIMUTH_SWING := 140.0 # Degrees the sun travels from sunrise to sunset.
const SUN_AZIMUTH_NOON := 30.0   # Where the sun stands at midday (the scene's original sun).
const MOON_ELEVATION := 40.0
const MOON_AZIMUTH := -60.0
const MOON_LIGHT := 0.5          # Moonlight, compared with the weather's sunlight.
const TWILIGHT_LIGHT := 0.3      # The dimmest moment, as the sun hands over to the moon.
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
const LOW_SUN_COLOUR := Color(1.0, 0.62, 0.38)
const NIGHT_SKY_TOP := Color(0.1, 0.15, 0.3)
const NIGHT_SKY_HORIZON := Color(0.24, 0.3, 0.46)
const DUSK_HORIZON := Color(0.95, 0.58, 0.36)
const NIGHT_GROUND := Color(0.1, 0.12, 0.17)

var _day_ground := Color.BLACK
var _noon_transform: Transform3D

@onready var _time: TimeManager = get_node("../TimeManager")
@onready var _effects: EventEffects = get_node("../EventEffects")
@onready var _sun: DirectionalLight3D = get_node("../Sun")
@onready var _sky: ProceduralSkyMaterial = (get_node("../WorldEnvironment") as WorldEnvironment).environment.sky.sky_material


func _ready() -> void:
	_day_ground = _sky.ground_bottom_color
	_noon_transform = _sun.transform


# How far through the current turn of the sky it is, from 0 (sunrise) to 1
# (the next sunrise).
func get_phase() -> float:
	return fposmod(_time.get_days() / CYCLE_DAYS + START, 1.0)


# How much daylight there is, from 0 (night) to 1 (full day).
func get_daylight() -> float:
	if not enabled:
		return 1.0
	var phase := get_phase()
	return smoothstep(0.0, TWILIGHT, phase) * (1.0 - smoothstep(DAY_PART - TWILIGHT, DAY_PART, phase))


func is_night() -> bool:
	return get_daylight() < 0.5


# A word for the time of day, for the top bar.
func get_time_name() -> String:
	if not enabled:
		return "day"
	var phase := get_phase()
	if phase < TWILIGHT:
		return "dawn"
	if phase < DAY_PART * 0.4:
		return "morning"
	if phase < DAY_PART * 0.75:
		return "afternoon"
	if phase < DAY_PART:
		return "evening"
	return "night"


func _process(_delta: float) -> void:
	apply()


# Puts the weather's light on the sun and the sky, for this time of day.
func apply() -> void:
	var daylight := get_daylight()
	if not enabled:
		_sun.transform = _noon_transform
		_sun.light_energy = _effects.sun_energy
		_sun.light_color = _effects.sun_color
		_set_sky(_effects.sky_top, _effects.sky_horizon, _day_ground)
		return

	var phase := get_phase()
	# Above 0.5 daylight the light is the sun; below, the moon. At 0.5 both have
	# the same dim strength and colour, so the swap is hard to see.
	var handover := _effects.sun_energy * MOON_LIGHT * TWILIGHT_LIGHT / MOON_LIGHT
	if daylight >= 0.5:
		var arc := clampf(phase / DAY_PART, 0.0, 1.0)              # 0 at sunrise, 1 at sunset.
		var elevation := lerpf(LOW_ELEVATION, NOON_ELEVATION, sin(arc * PI))
		var azimuth := SUN_AZIMUTH_NOON + (arc - 0.5) * SUN_AZIMUTH_SWING
		_point_light(elevation, azimuth)
		var low := 1.0 - clampf((elevation - LOW_ELEVATION) / 30.0, 0.0, 1.0)   # 1 near the horizon.
		var up := (daylight - 0.5) * 2.0                            # 0 at the handover, 1 in full day.
		_sun.light_energy = lerpf(handover, _effects.sun_energy, up)
		_sun.light_color = MOON_COLOUR.lerp(_effects.sun_color.lerp(LOW_SUN_COLOUR, low * 0.8), up)
	else:
		_point_light(MOON_ELEVATION, MOON_AZIMUTH)
		var dark := (0.5 - daylight) * 2.0                           # 0 at the handover, 1 at full night.
		_sun.light_energy = lerpf(handover, _effects.sun_energy * MOON_LIGHT, dark)
		_sun.light_color = MOON_COLOUR

	# The sky darkens towards night, and its horizon glows at dawn and dusk.
	var night := 1.0 - daylight
	var glow := 1.0 - absf(daylight - 0.5) * 2.0    # 1 halfway through twilight.
	var horizon := _effects.sky_horizon.lerp(NIGHT_SKY_HORIZON, night).lerp(DUSK_HORIZON, glow * 0.6)
	_set_sky(_effects.sky_top.lerp(NIGHT_SKY_TOP, night), horizon, _day_ground.lerp(NIGHT_GROUND, night))


func _set_sky(top: Color, horizon: Color, ground: Color) -> void:
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = ground


# Points the light down from this height (degrees above the horizon) and
# direction (degrees round from north).
func _point_light(elevation: float, azimuth: float) -> void:
	_sun.rotation = Vector3(-deg_to_rad(elevation), deg_to_rad(azimuth), 0.0)
