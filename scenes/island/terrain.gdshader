// terrain.gdshader
// Paints the island: sand near the water, grass higher up, bare rock on steep
// slopes and high ground, and dirt roads where roads.gd says.
shader_type spatial;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float texture_size = 16.0;      // Metres covered by one copy of a texture.
uniform float sand_top = 1.6;           // Height where sand turns to grass. (v2: a wider beach.)
uniform float blend_width = 0.45;       // Width of that transition.
uniform vec3 grass_tint : source_color = vec3(0.8, 1.0, 0.48);
// v2 stylised look: the photo textures are mixed with flat, bright colours, so
// the ground looks painted rather than photographed and matches the models.
uniform float stylise = 0.45;           // 0 = photo textures only, 1 = flat colours only. (v2 island: the picture's bright greens.)
uniform vec3 forest_tint : source_color = vec3(0.55, 0.68, 0.42);  // Darker green on the mountain slopes.
uniform vec3 flat_grass : source_color = vec3(0.475, 0.663, 0.29);   // #79A94A, meadow green (team palette).
uniform vec3 flat_sand : source_color = vec3(0.91, 0.824, 0.627);   // #E8D2A0, warm beach beige.
uniform float rock_slope_start = 0.6;   // Ground flatter than this stays grass (1.0 = level).
uniform float rock_slope_full = 0.32;   // Ground steeper than this is fully rock. (v2: green, wooded slopes; rock only on cliffs.)
uniform float rock_texture_size = 34.0; // Metres covered by one copy of the rock texture.
// The roads: white where there is a road, drawn by scripts/roads.gd. Black (no
// roads) until the game sets it, so the editor shows plain grass.
uniform sampler2D road_mask : hint_default_black, filter_linear;
uniform float road_area = 320.0;        // Metres the road picture covers, centred on the town.
uniform vec3 road_tint : source_color = vec3(0.86, 0.74, 0.58);
uniform float road_strength = 0.85;    // How fully the dirt covers the grass in the middle of a road.

// Patches of dry, brownish grass scattered over the meadows (v2 village).
uniform vec3 dry_grass : source_color = vec3(0.72, 0.64, 0.36);
uniform float dry_amount = 0.55;        // How strongly the patches show.

varying vec3 world_position;

// Smooth random values over the ground, for the dry patches.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float patches(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.3 + 7.1) * 0.3 + value_noise(p * 5.1 + 3.3) * 0.1;
}
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_position.xz / texture_size;
	// A second, larger sample hides the repeating pattern of the texture.
	vec2 uv_large = world_position.zx / (texture_size * 3.7);

	vec3 grass = mix(texture(grass_albedo, uv).rgb, texture(grass_albedo, uv_large).rgb, 0.5) * grass_tint;
	vec3 sand = texture(sand_albedo, uv).rgb;
	// Keep a little of the texture's light and dark, so the flat colour is not dead.
	float grass_shade = dot(grass, vec3(0.33)) / 0.33;
	grass = mix(grass, flat_grass * mix(0.85, 1.1, clamp(grass_shade, 0.0, 1.0)), stylise);
	sand = mix(sand, flat_sand, stylise);

	// Use the grass pattern to make the sand line uneven, not a perfect ring.
	float wobble = (texture(grass_albedo, uv_large).g - 0.4) * 1.1;
	float grass_amount = smoothstep(sand_top - blend_width, sand_top + blend_width, world_position.y + wobble);

	vec3 grass_ao_rough = texture(grass_arm, uv).rgb;
	vec3 sand_ao_rough = texture(sand_arm, uv).rgb;

	// Sand close to the waterline looks darker because it is wet.
	float wet = 1.0 - smoothstep(0.05, 0.6, world_position.y);

	// Rock shows on steep slopes and high ground, but not on beaches and river banks.
	vec2 rock_uv = world_position.xz / rock_texture_size;
	vec3 rock_ao_rough = texture(rock_arm, rock_uv).rgb;
	float steepness = smoothstep(rock_slope_start, rock_slope_full, world_normal.y);
	// Bare rock only near the mountain tops; the slopes below stay green.
	float high_ground = smoothstep(80.0, 105.0, world_position.y + wobble * 12.0);
	float rock_amount = max(steepness, high_ground) * smoothstep(2.5, 4.0, world_position.y);

	// Dry, brownish patches here and there in the meadows.
	float dry = smoothstep(0.58, 0.72, patches(world_position.xz * 0.018)) * dry_amount;
	grass = mix(grass, dry_grass * (0.85 + grass_shade * 0.15), dry);
	// Higher up, the grass gives way to the darker green of wooded slopes.
	grass *= mix(vec3(1.0), forest_tint, smoothstep(8.0, 45.0, world_position.y));
	vec3 land_albedo = mix(sand * (1.0 - wet * 0.4), grass, grass_amount);
	float land_ao = mix(sand_ao_rough.r, grass_ao_rough.r, grass_amount);
	float land_rough = mix(sand_ao_rough.g * (1.0 - wet * 0.5), grass_ao_rough.g, grass_amount);
	vec3 land_normal = mix(texture(sand_normal, uv).rgb, texture(grass_normal, uv).rgb, grass_amount);

	// Dirt roads: the sand texture, darkened to earth. The grass pattern makes
	// the edges uneven, like a worn path.
	vec2 road_uv = world_position.xz / road_area + 0.5;
	float road = texture(road_mask, road_uv).r;
	road = smoothstep(0.3, 0.7, road + wobble * 0.35) * grass_amount * road_strength;
	land_albedo = mix(land_albedo, sand * road_tint, road);
	land_rough = mix(land_rough, 0.95, road);

	ALBEDO = mix(land_albedo, texture(rock_albedo, rock_uv).rgb, rock_amount);
	AO = mix(land_ao, rock_ao_rough.r, rock_amount);
	ROUGHNESS = mix(land_rough, rock_ao_rough.g, rock_amount);
	NORMAL_MAP = mix(land_normal, texture(rock_normal, rock_uv).rgb, rock_amount);
}
