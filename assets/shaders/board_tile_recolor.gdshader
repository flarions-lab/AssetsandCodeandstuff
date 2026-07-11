shader_type canvas_item;

// Recolours the three board-tile base shades (Black / Gray / White) to user-chosen
// colours. Per-pixel luminance of the TEXTURE decides which of the three groups a
// pixel belongs to; the pixel is then filled with that group's chosen colour at full
// brightness.
//
// NOTE: we deliberately do NOT multiply by the incoming COLOR. The board tiles carry a
// per-tile modulate encoding their original Black/Gray/White shade — multiplying by it
// re-darkened the recolour (e.g. red x 0.2 = dark red on Black tiles). Ignoring it lets
// every tile show its chosen colour at the same full brightness, so Black/Gray/White
// recoloured to the same colour look identical. The hex silhouette is kept via t.a.
uniform vec4 col_black : source_color = vec4(0.20, 0.20, 0.20, 1.0);
uniform vec4 col_gray  : source_color = vec4(0.61, 0.61, 0.61, 1.0);
uniform vec4 col_white : source_color = vec4(0.96, 0.96, 0.96, 1.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float lum = (t.r + t.g + t.b) / 3.0;
	vec3 target;
	if (lum < 0.405) {            // black band
		target = col_black.rgb;
	} else if (lum < 0.785) {     // gray band
		target = col_gray.rgb;
	} else {                      // white band
		target = col_white.rgb;
	}
	COLOR = vec4(target, t.a);
}
