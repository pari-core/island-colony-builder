// water.gdshader
// The sea: clear and turquoise in the shallows, deep blue further out, with
// moving ripples and a thin line of foam where it meets the shore.
shader_type spatial;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;

// v2 bay: bright turquoise over sand, azure a little deeper, deep blue far out.
// Team palette: #42C6C2 turquoise shallows, #168DB8 Mediterranean blue, #075A83 deep.
uniform vec3 shallow_color : source_color = vec3(0.259, 0.776, 0.761);
uniform vec3 middle_color : source_color = vec3(0.086, 0.553, 0.722);
uniform vec3 deep_color : source_color = vec3(0.027, 0.353, 0.514);
uniform float depth_range = 14.0;     // Metres of water before it looks fully deep.
uniform float foam_width = 0.7;       // Metres of water depth that show foam. (v2: white surf round the rocks.)
uniform float ripple_size = 22.0;     // Metres covered by one copy of the ripples.

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Find how far the ground is behind the water surface at this pixel.
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ground = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	ground.xyz /= ground.w;
	float water_depth = max(VERTEX.z - ground.z, 0.0);
	float deepness = clamp(water_depth / depth_range, 0.0, 1.0);

	// Two ripple layers drift in different directions so the motion never repeats obviously.
	vec2 uv = world_position.xz / ripple_size;
	vec3 ripples_a = texture(ripple_a, uv + TIME * vec2(0.012, 0.007)).rgb;
	vec3 ripples_b = texture(ripple_b, uv * 0.6 - TIME * vec2(0.006, 0.011)).rgb;

	float foam = (1.0 - smoothstep(0.0, foam_width, water_depth)) * 0.65;

	vec3 water = mix(shallow_color, middle_color, smoothstep(0.0, 0.35, deepness));
	water = mix(water, deep_color, smoothstep(0.3, 1.0, deepness));
	ALBEDO = mix(water, vec3(0.95), foam);
	ALPHA = mix(0.55, 1.0, smoothstep(0.0, 0.5, deepness));   // Opaque when deep, so the seabed edge never shows.
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
	NORMAL_MAP = mix(ripples_a, ripples_b, 0.5);
	NORMAL_MAP_DEPTH = 0.5;
}
