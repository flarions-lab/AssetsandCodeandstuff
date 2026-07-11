extends Node2D

## HexHighlight.gd
## Draws pulsing glowing hex borders over selected pieces and valid move cells.

var selected_color:         Color = Color.WHITE
var selected_outer:         Color = Color(1.0, 1.0, 1.0, 0.4)
var move_color:             Color = Color.WHITE
var move_outer:             Color = Color(1.0, 1.0, 1.0, 0.4)
var capture_color:          Color = Color.WHITE
var capture_outer:          Color = Color(1.0, 1.0, 1.0, 0.4)
var friendly_capture_color: Color = Color(1.0, 0.55, 0.0, 1.0)

@export var pulse_speed:  float = 2.0
@export var pulse_min:    float = 0.3
@export var pulse_max:    float = 1.0
@export var border_width: float = 3.0
@export var glow_layers:  int   = 4
@export var glow_spread:  float = 2.5

var glow_opacity: float  = 1.0
var glow_speed:   float  = 1.0
var glow_effect:  String = "Pulse"

## Trail glow opacity: drones keep a steady glow at PASSIVE_OPACITY when not
## selected, brightened by ACTIVE_MULT (+50%) while a drone is selected/moving.
const PASSIVE_OPACITY := 0.45
const ACTIVE_MULT     := 1.5
var _active: bool = false

## Move trail: a brighter glow that lags behind a moving drone and fades over the
## drive (move) animation duration, so the glow slowly streaks after the piece.
const TRAIL_LAG   := 0.40   ## fraction of the move the glow lags behind the sprite
const TRAIL_TAIL  := 7      ## number of fading blobs streaking back along the path
const TRAIL_STEP  := 0.084  ## path fraction between blobs (tail length = TAIL × STEP)
var _trail_active: bool   = false
var _trail_from:   Vector2i = Vector2i.ZERO
var _trail_to:     Vector2i = Vector2i.ZERO
var _trail_t:      float   = 0.0
var _trail_dur:    float   = 0.0

var _selected_coords:  Array[Vector2i] = []
var _move_coords:      Array[Vector2i] = []
var _capture_coords:   Array[Vector2i] = []
var _friendly_coords:  Array[Vector2i] = []
var _pulse_time:       float = 0.0
var _board_layer:      TileMapLayer = null
var _hex_verts:        PackedVector2Array = PackedVector2Array()
var _flicker_val:      float = 1.0
var _flicker_timer:    float = 0.0

var _fade_multiplier:  float = 1.0
var _fade_tween:       Tween = null
var _ring_angle:       float = 0.0

func _ready() -> void:
	_board_layer = get_parent().get_node_or_null("BoardLayer")
	_build_hex_verts()

func _build_hex_verts() -> void:
	_hex_verts.clear()
	for i in 6:
		var a = deg_to_rad(60.0 * i + 30.0)
		_hex_verts.append(Vector2(cos(a), sin(a)))

func _process(delta: float) -> void:
	_pulse_time += delta
	if glow_effect == "Flicker":
		_flicker_timer -= delta * glow_speed
		if _flicker_timer <= 0.0:
			_flicker_val   = randf_range(0.3, 1.0)
			_flicker_timer = randf_range(0.04, 0.18)
	if glow_effect == "Ring":
		_ring_angle = fmod(_ring_angle + delta * 720.0 * glow_speed, 360.0)
	if _trail_active:
		_trail_t += delta
		if _trail_t >= _trail_dur:
			_trail_active = false
	queue_redraw()

func _compute_pulse() -> float:
	var pt := _pulse_time * glow_speed
	if glow_effect == "Breathing":
		return lerp(0.1, 1.0, sin(pt * 0.33 * TAU) * 0.5 + 0.5)
	if glow_effect == "HeartBeat":
		var tm := fmod(pt, 1.2) / 1.2
		return lerp(pulse_min, pulse_max,
			maxf(maxf(0.0, 1.0 - abs(tm - 0.08) / 0.07),
				 maxf(0.0, 1.0 - abs(tm - 0.22) / 0.07)))
	if glow_effect == "Flicker":
		return _flicker_val
	if glow_effect == "BPM":
		var beat_sec := 60.0 / MusicPlayer.get_current_bpm()
		var beat_phase := fmod(MusicPlayer.get_playback_position(), beat_sec) / beat_sec
		var bpm_t := maxf(0.0, 1.0 - beat_phase * 1.8)
		return lerp(0.35, minf(pulse_max, 0.95), bpm_t * bpm_t)
	return lerp(pulse_min, pulse_max, sin(pt * pulse_speed * TAU) * 0.5 + 0.5)

func _draw() -> void:
	if _board_layer == null:
		return
	## Steady glow at PASSIVE_OPACITY when idle; +50% and lightly pulsing while a
	## drone is selected/moving. glow_opacity remains the player's master setting.
	var level := PASSIVE_OPACITY * (ACTIVE_MULT if _active else 1.0) * glow_opacity
	var pulse: float = level * _fade_multiplier
	if _active:
		pulse = level * lerp(0.85, 1.0, _compute_pulse()) * _fade_multiplier
	for coord in _selected_coords:
		_draw_hex_glow(coord, selected_color, selected_outer, pulse, 1.5)
	for coord in _move_coords:
		_draw_hex_glow(coord, move_color, move_outer, pulse)
	for coord in _capture_coords:
		_draw_hex_glow(coord, capture_color, capture_outer, pulse)
	for coord in _friendly_coords:
		_draw_hex_glow(coord, friendly_capture_color, friendly_capture_color, pulse)

	## Move trail — a directional tail of soft light streaking BACK toward where
	## the drone came from (not an omnidirectional halo), fading out.
	if _trail_active and _trail_dur > 0.0:
		var p: float = clampf(_trail_t / _trail_dur, 0.0, 1.0)
		var lead_p: float = clampf(p - TRAIL_LAG, 0.0, 1.0)   ## lags behind the sprite
		var from_c: Vector2 = _board_layer.map_to_local(_trail_from) * _board_layer.scale.x
		var to_c: Vector2   = _board_layer.map_to_local(_trail_to)   * _board_layer.scale.x
		var base_pulse: float = PASSIVE_OPACITY * ACTIVE_MULT * glow_opacity * (1.0 - p)
		for i in TRAIL_TAIL:
			var bp: float = clampf(lead_p - float(i) * TRAIL_STEP, 0.0, 1.0)  ## back toward start
			var f: float  = 1.0 - float(i) / float(TRAIL_TAIL)               ## fainter + smaller back
			_draw_trail_glow(from_c.lerp(to_c, bp), selected_color, selected_outer, base_pulse * f, 0.45 + 0.55 * f)

func _draw_hex_glow(coord: Vector2i, inner: Color, outer: Color, pulse: float, outer_boost: float = 1.0) -> void:
	_draw_hex_glow_at(_board_layer.map_to_local(coord) * _board_layer.scale.x, inner, outer, pulse, outer_boost)

## Soft, edgeless "slow light" blob for one point of the move trail: a few faint,
## tight overlapping rings with NO crisp hex border. Small radius / little spread
## so the tail reads as light streaking BACK rather than radiating outward.
func _draw_trail_glow(center: Vector2, inner: Color, outer: Color, pulse: float, radius_scale: float = 1.0) -> void:
	var scale_factor = _board_layer.scale.x
	var tile_size    = _board_layer.tile_set.tile_size
	var radius       = (tile_size.x * scale_factor) / 2.0 * 0.50 * radius_scale   ## smaller
	var soft_layers  = 4
	for layer in range(soft_layers, 0, -1):
		var spread   = glow_spread * float(layer) * 0.8          ## tighter — less radiating
		var alpha    = pulse * (float(layer) / soft_layers) * 0.36   ## +20% opaqueness
		var col      = inner.lerp(outer, float(layer - 1) / float(max(soft_layers - 1, 1)))
		var glow_pts = PackedVector2Array()
		for v in _hex_verts:
			glow_pts.append(center + v * (radius + spread))
		## Soft strokes (no thin crisp edge) keep it a light blob, not a hex.
		draw_polyline(_close_polygon(glow_pts), Color(col.r, col.g, col.b, alpha), border_width + spread * 0.6, true)

func _ring_ev(angle_deg: float) -> float:
	const ARC_HALF := 30.0
	const AMBIENT  := 0.12
	var diff := fmod(abs(angle_deg - _ring_angle) + 360.0, 360.0)
	if diff > 180.0:
		diff = 360.0 - diff
	if diff >= ARC_HALF:
		return AMBIENT
	return lerp(AMBIENT, 1.0, cos(diff / ARC_HALF * PI * 0.5))

func _draw_ring_glow_at(center: Vector2, radius: float, inner: Color, outer: Color, pulse: float, outer_boost: float) -> void:
	const SEGS := 10
	for layer in range(glow_layers, 0, -1):
		var spread     := glow_spread * layer
		var r_layer    := radius + spread
		var base_alpha := pulse * (float(layer) / glow_layers) * 2.04 * outer_boost
		var layer_t    := float(layer - 1) / float(max(glow_layers - 1, 1))
		var base_col   := inner.lerp(outer, layer_t)
		var w          := border_width + spread * 0.5
		for edge in 6:
			var v0 := center + _hex_verts[edge]           * r_layer
			var v1 := center + _hex_verts[(edge + 1) % 6] * r_layer
			for seg in SEGS:
				var p0  := v0.lerp(v1, float(seg)     / SEGS)
				var p1  := v0.lerp(v1, float(seg + 1) / SEGS)
				var mid := (p0 + p1) * 0.5
				var ang := rad_to_deg(atan2(mid.y - center.y, mid.x - center.x))
				if ang < 0.0:
					ang += 360.0
				draw_line(p0, p1, Color(base_col.r, base_col.g, base_col.b, _ring_ev(ang) * base_alpha), w, true)
	for edge in 6:
		var v0 := center + _hex_verts[edge]           * radius
		var v1 := center + _hex_verts[(edge + 1) % 6] * radius
		for seg in SEGS:
			var p0  := v0.lerp(v1, float(seg)     / SEGS)
			var p1  := v0.lerp(v1, float(seg + 1) / SEGS)
			var mid := (p0 + p1) * 0.5
			var ang := rad_to_deg(atan2(mid.y - center.y, mid.x - center.x))
			if ang < 0.0:
				ang += 360.0
			draw_line(p0, p1, Color(inner.r, inner.g, inner.b, _ring_ev(ang) * pulse * 4.0), border_width, true)

func _draw_hex_glow_at(center: Vector2, inner: Color, outer: Color, pulse: float, outer_boost: float = 1.0) -> void:
	var scale_factor = _board_layer.scale.x
	var tile_size    = _board_layer.tile_set.tile_size
	var radius       = (tile_size.x * scale_factor) / 2.0 * 0.92

	if glow_effect == "Ring":
		_draw_ring_glow_at(center, radius, inner, outer, pulse, outer_boost)
		return

	var pts = PackedVector2Array()
	for v in _hex_verts:
		pts.append(center + v * radius)

	for layer in range(glow_layers, 0, -1):
		var spread   = glow_spread * layer
		var alpha    = pulse * (float(layer) / glow_layers) * 0.51 * outer_boost
		var layer_t  = float(layer - 1) / float(max(glow_layers - 1, 1))
		var col      = inner.lerp(outer, layer_t)
		var glow_pts = PackedVector2Array()
		for v in _hex_verts:
			glow_pts.append(center + v * (radius + spread))
		draw_polyline(_close_polygon(glow_pts), Color(col.r, col.g, col.b, alpha), border_width + spread * 0.5, true)

	draw_polyline(_close_polygon(pts), Color(inner.r, inner.g, inner.b, pulse), border_width, true)

func _close_polygon(pts: PackedVector2Array) -> PackedVector2Array:
	var c = PackedVector2Array(pts)
	c.append(pts[0])
	return c

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func apply_glow_settings(sel_in: Color, sel_out: Color,
		mov_in: Color, mov_out: Color,
		cap_in: Color, cap_out: Color,
		_use_gradient: bool, p_opacity: float,
		p_speed: float, p_effect: String) -> void:
	selected_color = sel_in
	selected_outer = sel_out
	move_color     = mov_in
	move_outer     = mov_out
	capture_color  = cap_in
	capture_outer  = cap_out
	glow_opacity   = p_opacity
	glow_speed     = p_speed
	glow_effect    = p_effect

func set_highlights(
		selected:   Array[Vector2i],
		moves:      Array[Vector2i],
		captures:   Array[Vector2i],
		friendlies: Array[Vector2i] = [],
		active:     bool = false) -> void:
	_cancel_fade()
	_active           = active
	_selected_coords  = selected
	_move_coords      = moves
	_capture_coords   = captures
	_friendly_coords  = friendlies

## Start a glow trail that streaks from `from_coord` to `to_coord` over `dur`
## seconds (the drive/move animation duration), lagging behind the drone sprite.
## The streak is exclusive to the "Trail" glow effect — every other effect moves
## without it.
func start_move_trail(from_coord: Vector2i, to_coord: Vector2i, dur: float) -> void:
	if glow_effect != "Trail":
		_trail_active = false
		return
	_trail_from   = from_coord
	_trail_to     = to_coord
	_trail_t      = 0.0
	_trail_dur    = maxf(dur, 0.01)
	_trail_active = true

func clear() -> void:
	_selected_coords.clear()
	_move_coords.clear()
	_capture_coords.clear()
	_friendly_coords.clear()

func fade_out_and_clear(duration: float = 0.5) -> void:
	_cancel_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade_multiplier", 0.0, duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fade_tween.tween_callback(_on_fade_complete)

func _cancel_fade() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_fade_multiplier = 1.0

func _on_fade_complete() -> void:
	clear()
	_fade_multiplier = 1.0
	_fade_tween      = null
