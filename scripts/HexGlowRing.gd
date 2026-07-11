extends Control

## HexGlowRing.gd — animated hex glow preview ring used in the Glow settings panel.

var inner_color:  Color = Color(1.0, 0.9, 0.0, 1.0)
var outer_color:  Color = Color(1.0, 0.5, 0.0, 0.4)
var use_gradient: bool  = true
var glow_effect:  String = "Pulse"
var glow_opacity: float  = 1.0
var glow_speed:   float  = 1.0

var _t:             float = 0.0
var _flicker_val:   float = 1.0
var _flicker_timer: float = 0.0
var _grad_phase:    float = 0.0
var _ring_angle:    float = 0.0

const LAYERS := 5
const PULSE_SPEED := 2.0
const PULSE_MIN   := 0.3
const PULSE_MAX   := 1.0

func set_colors(inner: Color, outer: Color, p_use_gradient: bool,
		p_effect: String, p_opacity: float, p_speed: float = 1.0) -> void:
	inner_color  = inner
	outer_color  = outer
	use_gradient = p_use_gradient
	glow_effect  = p_effect
	glow_opacity = p_opacity
	glow_speed   = p_speed
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	match glow_effect:
		"Flicker":
			_flicker_timer -= delta * glow_speed
			if _flicker_timer <= 0.0:
				_flicker_val   = randf_range(0.3, 1.0)
				_flicker_timer = randf_range(0.04, 0.18)
		"InwardPull", "OutwardPull":
			_grad_phase += delta * 0.4 * glow_speed
		"Ring":
			_ring_angle = fmod(_ring_angle + delta * 720.0 * glow_speed, 360.0)
	queue_redraw()

func _compute_ev() -> float:
	var t: float = _t * glow_speed
	match glow_effect:
		"Pulse":     return lerp(PULSE_MIN, PULSE_MAX, sin(t * PULSE_SPEED * TAU) * 0.5 + 0.5)
		"Breathing": return lerp(0.1, 1.0, sin(t * 0.33 * TAU) * 0.5 + 0.5)
		"HeartBeat":
			var tm := fmod(t, 1.2) / 1.2
			return lerp(PULSE_MIN, PULSE_MAX,
				maxf(maxf(0.0, 1.0 - abs(tm - 0.08) / 0.07),
					 maxf(0.0, 1.0 - abs(tm - 0.22) / 0.07)))
		"Flicker":   return _flicker_val
		"BPM":
			var beat_sec: float = 60.0 / MusicPlayer.get_current_bpm()
			var beat_phase: float = fmod(_t, beat_sec) / beat_sec
			var bpm_t: float = maxf(0.0, 1.0 - beat_phase * 1.8)
			return lerp(0.35, minf(PULSE_MAX, 0.95), bpm_t * bpm_t)
		"Ring":      return 1.0
		_:           return lerp(PULSE_MIN, PULSE_MAX, sin(t * PULSE_SPEED * TAU) * 0.5 + 0.5)

func _layer_color(layer: int, ev: float) -> Color:
	var alpha   := ev * (float(layer) / LAYERS) * 0.45 * glow_opacity
	var layer_t := float(layer - 1) / float(LAYERS - 1)
	var col: Color
	if use_gradient:
		match glow_effect:
			"InwardPull":
				col = inner_color.lerp(outer_color, lerp(layer_t, 0.0, sin(_grad_phase * TAU) * 0.5 + 0.5))
			"OutwardPull":
				col = inner_color.lerp(outer_color, lerp(layer_t, 1.0, sin(_grad_phase * TAU) * 0.5 + 0.5))
			_:
				col = inner_color.lerp(outer_color, layer_t)
	else:
		col = inner_color
	return Color(col.r, col.g, col.b, alpha)

func _draw() -> void:
	var center := size / 2.0
	var radius: float = min(size.x, size.y) / 2.0 * 0.80
	var ev     := _compute_ev()

	if glow_effect == "Ring":
		_draw_ring(center, radius)
		return

	var verts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i + 30.0)
		verts.append(center + Vector2(cos(a), sin(a)) * radius)
	verts.append(verts[0])

	for layer in range(LAYERS, 0, -1):
		var spread := 3.0 * float(layer)
		var gv     := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * i + 30.0)
			gv.append(center + Vector2(cos(a), sin(a)) * (radius + spread))
		gv.append(gv[0])
		draw_polyline(gv, _layer_color(layer, ev), 2.5 + spread * 0.35, true)

	var border_a := ev * glow_opacity
	draw_polyline(verts, Color(inner_color.r, inner_color.g, inner_color.b, border_a), 3.0, true)

func _ring_ev(angle_deg: float) -> float:
	const ARC_HALF := 30.0
	const AMBIENT  := 0.12
	var diff := fmod(abs(angle_deg - _ring_angle) + 360.0, 360.0)
	if diff > 180.0:
		diff = 360.0 - diff
	if diff >= ARC_HALF:
		return AMBIENT
	return lerp(AMBIENT, 1.0, cos(diff / ARC_HALF * PI * 0.5))

func _draw_ring(center: Vector2, radius: float) -> void:
	const SEGS := 12
	var hex_verts: Array[Vector2] = []
	for i in 6:
		var a := deg_to_rad(60.0 * i + 30.0)
		hex_verts.append(Vector2(cos(a), sin(a)))

	for layer in range(LAYERS, 0, -1):
		var spread    := 3.0 * float(layer)
		var r_layer   := radius + spread
		var w         := 2.5 + spread * 0.35
		var layer_t   := float(layer - 1) / float(LAYERS - 1) if LAYERS > 1 else 0.0
		var base_col  : Color = inner_color.lerp(outer_color, layer_t) if use_gradient else inner_color
		var base_alpha := (float(layer) / LAYERS) * 1.80 * glow_opacity
		for edge in 6:
			var v0 := center + hex_verts[edge]           * r_layer
			var v1 := center + hex_verts[(edge + 1) % 6] * r_layer
			for seg in SEGS:
				var p0  := v0.lerp(v1, float(seg)     / SEGS)
				var p1  := v0.lerp(v1, float(seg + 1) / SEGS)
				var mid := (p0 + p1) * 0.5
				var ang := rad_to_deg(atan2(mid.y - center.y, mid.x - center.x))
				if ang < 0.0:
					ang += 360.0
				draw_line(p0, p1, Color(base_col.r, base_col.g, base_col.b, _ring_ev(ang) * base_alpha), w, true)

	for edge in 6:
		var v0 := center + hex_verts[edge]           * radius
		var v1 := center + hex_verts[(edge + 1) % 6] * radius
		for seg in SEGS:
			var p0  := v0.lerp(v1, float(seg)     / SEGS)
			var p1  := v0.lerp(v1, float(seg + 1) / SEGS)
			var mid := (p0 + p1) * 0.5
			var ang := rad_to_deg(atan2(mid.y - center.y, mid.x - center.x))
			if ang < 0.0:
				ang += 360.0
			draw_line(p0, p1, Color(inner_color.r, inner_color.g, inner_color.b, _ring_ev(ang) * 4.0 * glow_opacity), 3.0, true)
