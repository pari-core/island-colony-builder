# island_terrain.gd
# Builds the land as a 3D mesh when the game starts. (The file keeps its old name
# from when the colony stood on an island.)
#
# The setting is ordinary mainland with a coast on one side: the sea and a beach
# lie to the east, and grassy land with rolling hills stretches away to the
# north, west and south. A river runs from a lake in the west to the sea.
#
# How it works: the land is a large grid of points. For each point we ask
# get_height_at() how high the ground should be, then join the points into
# triangles. The noise uses fixed seeds, so the land is identical every run.
#
# Two meshes are built: a detailed one around the town (1 m squares), and a
# coarse one for the distant land (12 m squares), which the camera only ever
# sees from far away.
#
# @tool means this script also runs inside the Godot editor, so the land is
# visible while working on scenes, not only when the game is running.
@tool
extends MeshInstance3D

# All distances are in metres (1 Godot unit = 1 metre).
const MAP_SIZE := 600.0          # Width and depth of the detailed grid: the whole island (v2).
const CELL_SIZE := 1.5           # Gap between grid points. Smaller = more detail.
const FAR_SIZE := 2400.0         # Width and depth of the coarse grid for distant land.
const FAR_CELL_SIZE := 12.0      # Gap between its grid points.
const FAR_DROP := 0.15           # The coarse grid sits this much lower, so the two grids
                                 # never flicker where they overlap.
const LAND_HEIGHT := 2.2         # Height of the flat building area above the sea.
const SEA_FLOOR_HEIGHT := -5.0   # Height of the ground far out under the water.
const HIDDEN_SEABED_HEIGHT := -4.9  # Deep water is opaque, so ground this low is never seen.
const FLAT_RADIUS := 215.0       # The land is flat out to here, for building, apart from the
                                 # rocky hill, the lake, the river and the beach.
const COAST_X := 152.0           # The sea begins about this far east (+x) of the centre.
const COAST_WOBBLE := 14.0       # How far the coastline wanders in or out.
const FAR_HILLS_START := FLAT_RADIUS  # Rolling hills begin where the flat land ends...
const FAR_HILLS_FULL := 400.0    # ...and reach their full height here.
const FAR_HILLS_HEIGHT := 9.0    # Roughly how tall the distant hills are. Low enough to stay
                                 # grassy: the coarse mesh makes rock patches look blocky.

const ROCK_HILL_CENTRE := Vector2(30.0, -168.0)  # Where the big rocky hill stands (v2: north of the village grid).
const ROCK_HILL_RADIUS := 52.0   # How far the rocky hill spreads.
const ROCK_HILL_HEIGHT := 20.0   # Roughly how tall it is at the middle.

# The river runs west to east, south (+z) of the town, from a lake to the sea.
const LAKE_CENTRE := Vector2(-168.0, 136.0)  # The lake the river flows out of.
const LAKE_RADIUS := 20.0
const RIVER_Z := 130.0           # Average distance of the river south of the centre.
const RIVER_WIND := 9.0          # How far its bends swing north and south.
const RIVER_BEND_LENGTH := 150.0 # Metres from one bend to the next like it.
const RIVER_BED_HEIGHT := -2.5   # The bed is below sea level, so water fills it.
const RIVER_BANK_WIDTH := 5.0    # Width of the slope from the land down to the water.

# Small ponds in the fields around the town: x, z and radius in metres. Each is a
# bowl below sea level, so the sea's water plane fills it. Their edges wander in
# and out (POND_WOBBLE), so they do not look like perfect circles. They are well away from
# the build squares, the rocky hill, the river and the beach.
const PONDS := [Vector3(-112.0, -64.0, 13.0), Vector3(104.0, -72.0, 10.0), Vector3(-96.0, 80.0, 11.0)]
const POND_BED_HEIGHT := -1.6
const POND_WOBBLE := 0.28        # How far the edge wanders, as a share of the radius.
const POND_BANK_WIDTH := 3.5     # A short bank, so only a thin ring of sand shows.

# v2 island (team decision, 2026-11-21, from a picture of a small island): sea on
# every side, a ragged coast of rocks and sandy coves, and a rocky cliff in the
# west with a waterfall that feeds the lake and the river. The mountain, headland
# and offshore-island settings below are switched off (heights 0, empty lists),
# kept only so the "bay" look can be brought back.
const ISLAND_RADIUS := 236.0     # Average distance of the coast from the town square...
const ISLAND_WOBBLE := 22.0      # ...wandering in and out by up to this much...
const LAKE_BULGE := 52.0         # ...and reaching further out round the lake and cliff.
const CLIFF_CENTRE := Vector2(-212.0, 124.0)
const CLIFF_RADIUS := 30.0
const CLIFF_HEIGHT := 30.0

# Earlier v2 "Mediterranean bay" landscape (team decision, 2026-11-21, from a photo of a
# turquoise bay): steep green mountains with rocky crags ring the valley where the
# town stands; to the north-east a long green headland curves out to sea and
# shelters a shallow turquoise bay; the open sea beyond is deep blue, with
# islands on the horizon. The valley itself is unchanged, so every build square
# stays flat.
const MOUNT_START := 205.0       # Mountains begin rising this far from the town square...
const MOUNT_FULL := 360.0        # ...and reach full height here (a gentler, greener rise).
const MOUNT_HEIGHT := 0.0        # Roughly how tall the mountains are. (0: the island has none.)
const ISLAND_CELL_SIZE := 3.0    # Gap between grid points on the small islands' own meshes.
const SEA_SHALLOW := -2.6        # Depth of the bay near the beach: shows as turquoise.
const SEA_DEEP := -32.0          # Depth of the open sea: shows as deep blue.
const SHELF_START := 70.0        # The sea stays shallow and turquoise this far out from the beach...
const SHELF_WIDTH := 260.0       # ...then deepens until this far out.
# The headland: a curving ridge of hills, given as points along its spine.
const HEADLAND: Array[Vector2] = []   # (The bay look used a curving headland here.)
const HEADLAND_WIDTH := 48.0     # Half-width of the headland at the shore.
const HEADLAND_HEIGHT := 48.0
# Islands out at sea: x, z, radius and height.
# Small islands out at sea, a few hundred metres off the main island (team
# request, 2026-11-22): x, z, radius and the height of their mountain. Each has
# a beach, grassy hills and a peak; far_islands.gd puts trees and houses on them.
const ISLANDS: Array[Vector4] = [
	Vector4(560.0, -330.0, 95.0, 62.0),
	Vector4(-500.0, -440.0, 120.0, 78.0),
	Vector4(600.0, 360.0, 70.0, 34.0),
	Vector4(-580.0, 300.0, 65.0, 30.0),
]

var _coast_noise := FastNoiseLite.new()
var _hill_noise := FastNoiseLite.new()
var _rock_noise := FastNoiseLite.new()


func _ready() -> void:
	_coast_noise.seed = 2026
	_coast_noise.frequency = 0.012
	_hill_noise.seed = 7
	_hill_noise.frequency = 0.03
	_rock_noise.seed = 41
	_rock_noise.frequency = 0.035
	mesh = _build_mesh(MAP_SIZE, CELL_SIZE, 0.0)
	_add_far_land()


# The mesh is rebuilt on every load, so it must not be saved into scene files,
# which would make them huge. This tells Godot not to store the mesh property.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE


# Adds the coarse mesh for distant land as a child node. It leaves a hole where
# the detailed mesh is, apart from a small overlap so no gap can show.
func _add_far_land() -> void:
	var far := get_node_or_null("FarLand") as MeshInstance3D
	if far == null:
		far = MeshInstance3D.new()
		far.name = "FarLand"
		add_child(far)
	far.material_override = material_override
	far.position.y = -FAR_DROP
	far.mesh = _build_mesh(FAR_SIZE, FAR_CELL_SIZE, MAP_SIZE * 0.5 - FAR_CELL_SIZE, Vector2.ZERO, true)
	# Each small island gets its own finer mesh, so its hills are smooth up close;
	# the coarse mesh leaves a gap there (see _build_mesh).
	for i in ISLANDS.size():
		var island: Vector4 = ISLANDS[i]
		var name := "IslandLand%d" % i
		var land := get_node_or_null(name) as MeshInstance3D
		if land == null:
			land = MeshInstance3D.new()
			land.name = name
			add_child(land)
		land.material_override = material_override
		land.mesh = _build_mesh(island.z * 2.8, ISLAND_CELL_SIZE, 0.0, Vector2(island.x, island.y))


# Returns the ground height at a world position. Other scripts use this to
# place objects on the land, so it must stay the single source of truth.
func get_height_at(x: float, z: float) -> float:
	var distance := Vector2(x, z).length()

	# "land" is 1.0 inland and falls to 0.0 out at sea, which lies to the east.
	# The noise makes the coastline wander instead of running dead straight.
	var coast := COAST_X + _coast_noise.get_noise_2d(z, 0.0) * COAST_WOBBLE
	var land := 1.0 - smoothstep(coast - 22.0, coast + 6.0, x)
	# The island's own coast, all the way round.
	var angle := atan2(z, x)
	var toward_lake := maxf(cos(angle - atan2(LAKE_CENTRE.y, LAKE_CENTRE.x)), 0.0)
	var radius := ISLAND_RADIUS + _coast_noise.get_noise_2d(cos(angle) * 60.0, sin(angle) * 60.0) * ISLAND_WOBBLE + LAKE_BULGE * pow(toward_lake, 6.0)
	land = minf(land, 1.0 - smoothstep(radius - 26.0, radius + 6.0, distance))
	# The sea floor drops away from every shore: turquoise shallows, then deep blue.
	var from_shore := maxf(x - coast, distance - radius)   # Sea lies beyond either coast.
	var deep := smoothstep(SHELF_START * 0.4, SHELF_WIDTH * 0.7, from_shore)
	# Each small island has its own ring of shallows.
	for island: Vector4 in ISLANDS:
		var off := Vector2(x, z).distance_to(Vector2(island.x, island.y)) - island.z
		deep = minf(deep, smoothstep(0.0, 90.0, off))
	var sea_floor := lerpf(SEA_SHALLOW, SEA_DEEP, deep)
	var height: float = lerpf(sea_floor, LAND_HEIGHT, land)

	# Mountains rise all round the valley. Ridged noise gives sharp crests and
	# gullies. They stay low beside the river, so it runs out through a gap.
	var rise := smoothstep(MOUNT_START, MOUNT_FULL, distance)
	var ridge := 1.0 - absf(_hill_noise.get_noise_2d(x * 0.12, z * 0.12))
	var bumps := 0.5 + _rock_noise.get_noise_2d(x * 0.5, z * 0.5) * 0.5
	var valley := smoothstep(14.0, 120.0, absf(z - _river_z(x)))
	height += rise * MOUNT_HEIGHT * (0.45 + ridge * ridge * 0.75 + bumps * 0.2) * valley * land

	# The headland and the islands rise out of the sea.
	height = maxf(height, _headland_height(x, z, sea_floor))
	for island: Vector4 in ISLANDS:
		var from_island := Vector2(x, z).distance_to(Vector2(island.x, island.y))
		if from_island < island.z * 1.3:
			var shape := 1.0 - smoothstep(0.0, island.z, from_island)
			# A wide grassy shoulder, then the hill or mountain in the middle.
			var top := island.w * pow(shape, 2.2) * (0.75 + bumps * 0.5) + LAND_HEIGHT * smoothstep(0.0, 0.25, shape) + 4.0 * smoothstep(0.2, 0.6, shape)
			height = maxf(height, lerpf(sea_floor, top, smoothstep(0.0, 0.12, shape)))

	height += _rock_hill_height(x, z)
	# The cliff stands over the lake's west shore, so it is added after the lake
	# is dug, and its east face drops straight into the water.
	return maxf(_carve_water(x, z, height), _cliff_height(x, z))


# The cliff: a flat-topped rocky hill with steep sides, west of the lake. The
# waterfall (waterfall.gd) pours off its east face into the lake.
func _cliff_height(x: float, z: float) -> float:
	var from_cliff := Vector2(x, z).distance_to(CLIFF_CENTRE)
	if from_cliff > CLIFF_RADIUS + 10.0:
		return -INF
	var crag := _rock_noise.get_noise_2d(x * 1.5, z * 1.5) * 3.0
	var shape := 1.0 - smoothstep(CLIFF_RADIUS - 6.0, CLIFF_RADIUS + 2.0, from_cliff + crag)
	return LAND_HEIGHT + CLIFF_HEIGHT * shape + crag * shape


# The headland: highest along its spine, falling to the sea on both sides.
func _headland_height(x: float, z: float, sea_floor: float) -> float:
	if HEADLAND.is_empty():
		return sea_floor
	var p := Vector2(x, z)
	var nearest := INF
	var along := 0.0
	var total := 0.0
	for i in HEADLAND.size() - 1:
		var a: Vector2 = HEADLAND[i]
		var b: Vector2 = HEADLAND[i + 1]
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(c)
		if d < nearest:
			nearest = d
			along = total + a.distance_to(c)
		total += a.distance_to(b)
	# It narrows and gets lower towards its tip.
	var tip := clampf(along / total, 0.0, 1.0)
	var width := HEADLAND_WIDTH * lerpf(1.0, 0.45, tip)
	if nearest > width * 1.6:
		return sea_floor
	var shape := 1.0 - smoothstep(0.0, width, nearest)
	var noise := 0.75 + _rock_noise.get_noise_2d(x * 0.8, z * 0.8) * 0.5
	var top := HEADLAND_HEIGHT * lerpf(1.0, 0.35, tip) * shape * noise + LAND_HEIGHT
	return lerpf(sea_floor, top, smoothstep(0.0, 0.18, shape))


# Extra height from the big rocky hill. The noise adds jagged ridges.
func _rock_hill_height(x: float, z: float) -> float:
	var from_centre := Vector2(x, z).distance_to(ROCK_HILL_CENTRE)
	if from_centre >= ROCK_HILL_RADIUS:
		return 0.0
	var shape := 1.0 - smoothstep(0.0, ROCK_HILL_RADIUS, from_centre)
	var ridges := 0.75 + absf(_rock_noise.get_noise_2d(x, z)) * 0.8
	return ROCK_HILL_HEIGHT * shape * ridges


# How far this spot is from the middle of the river, in metres.
func get_river_distance(x: float, z: float) -> float:
	return absf(z - _river_z(x))


# Where the middle of the river is (its z position) at this x.
func _river_z(x: float) -> float:
	return RIVER_Z + sin(x * TAU / RIVER_BEND_LENGTH) * RIVER_WIND


# Lowers the ground for the lake and the river, and returns the new height.
func _carve_water(x: float, z: float, height: float) -> float:
	# The lake: a bowl in the ground.
	var from_lake := Vector2(x, z).distance_to(LAKE_CENTRE)
	var amount := 1.0 - smoothstep(LAKE_RADIUS, LAKE_RADIUS + RIVER_BANK_WIDTH * 1.6, from_lake)

	# The river starts at the lake and gets wider towards the sea.
	if x > LAKE_CENTRE.x:
		var along := clampf((x - LAKE_CENTRE.x) / (COAST_X - LAKE_CENTRE.x), 0.0, 1.0)
		var half_width: float = lerpf(3.0, 7.0, along)
		var from_river := absf(z - _river_z(x))
		amount = maxf(amount, 1.0 - smoothstep(half_width, half_width + RIVER_BANK_WIDTH, from_river))

	# minf means the water can only lower the ground, never raise the seabed.
	height = minf(height, lerpf(height, RIVER_BED_HEIGHT, amount))

	# The ponds: smaller, shallower bowls.
	for i in PONDS.size():
		var pond: Vector3 = PONDS[i]
		var offset := Vector2(x - pond.x, z - pond.y)
		if offset.length() > pond.z * (1.0 + POND_WOBBLE) + POND_BANK_WIDTH:
			continue
		# The radius changes with the direction from the middle, by two waves
		# that differ for each pond.
		var angle := offset.angle()
		var radius := pond.z * (1.0 + POND_WOBBLE * (0.6 * sin(2.0 * angle + i * 1.7) + 0.4 * sin(3.0 * angle + i * 2.9)))
		var depth := 1.0 - smoothstep(radius, radius + POND_BANK_WIDTH, offset.length())
		height = minf(height, lerpf(height, POND_BED_HEIGHT, depth))
	return height


# Works out which way the ground faces at a point, by comparing the heights on
# either side of it. Lighting needs this to shade slopes correctly.
func _normal_at(x: float, z: float, step: float) -> Vector3:
	var slope_x := get_height_at(x + step, z) - get_height_at(x - step, z)
	var slope_z := get_height_at(x, z + step) - get_height_at(x, z - step)
	return Vector3(-slope_x, 2.0 * step, -slope_z).normalized()


# Builds a square grid of land, "size" metres across with "cell" metres between
# points. Squares that lie wholly within "hole" metres of the centre (in both
# directions) are left out; 0 means no hole.
# centre moves the grid (the small islands use this). skip_islands leaves out
# squares that a small island's own mesh covers.
func _build_mesh(size: float, cell: float, hole: float, centre := Vector2.ZERO, skip_islands := false) -> ArrayMesh:
	var points_per_side := int(size / cell) + 1
	var half := size * 0.5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()

	# Step 1: create every grid point.
	for row in points_per_side:
		for col in points_per_side:
			var x := col * cell - half + centre.x
			var z := row * cell - half + centre.y
			vertices.append(Vector3(x, get_height_at(x, z), z))
			normals.append(_normal_at(x, z, cell))
			tangents.append_array([1.0, 0.0, 0.0, -1.0])

	# Step 2: join each square of four points into two triangles.
	for row in points_per_side - 1:
		for col in points_per_side - 1:
			var top_left := row * points_per_side + col
			var top_right := top_left + 1
			var bottom_left := top_left + points_per_side
			var bottom_right := bottom_left + 1
			# Skip squares that are entirely hidden under deep water. This saves
			# a lot of drawing, because the lit view and every shadow pass skip them.
			if maxf(maxf(vertices[top_left].y, vertices[top_right].y), maxf(vertices[bottom_left].y, vertices[bottom_right].y)) < HIDDEN_SEABED_HEIGHT:
				continue
			# Skip squares covered by the detailed mesh.
			if hole > 0.0:
				var a := vertices[top_left]
				var b := vertices[bottom_right]
				if maxf(absf(a.x), absf(b.x)) <= hole and maxf(absf(a.z), absf(b.z)) <= hole:
					continue
			if skip_islands and _covered_by_island(vertices[top_left], vertices[bottom_right]):
				continue
			indices.append_array([top_left, top_right, bottom_left])
			indices.append_array([top_right, bottom_right, bottom_left])

	# Step 3: hand the data to Godot as a mesh.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices

	var new_mesh := ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return new_mesh


# True if this square lies inside the area a small island's own mesh draws.
func _covered_by_island(a: Vector3, b: Vector3) -> bool:
	var middle := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
	for island: Vector4 in ISLANDS:
		var half := island.z * 1.4 - FAR_CELL_SIZE
		if absf(middle.x - island.x) < half and absf(middle.y - island.y) < half:
			return true
	return false
