extends Camera2D

@export var zoom_min:           float = 0.5
@export var zoom_max:           float = 3.0
@export var zoom_step:          float = 0.125
@export var rotate_sensitivity: float = 0.4
@export var snap_degrees:       float = 15.0   ## nearest increment to snap to
@export var snap_speed:         float = 10.0   ## higher = snappier settle

# ── PC state ────────────────────────────────────────────────────────────────
var _is_rotating:  bool  = false
var _last_mouse_x: float = 0.0

# ── Touch state ─────────────────────────────────────────────────────────────
var _touch_points: Dictionary = {}
var _touch_prev:   Dictionary = {}

## 2-finger gesture classification — resets when the second finger goes down.
## "" = undecided, "zoom" | "rotate" = committed type this gesture.
var _pinch_type:       String = ""
var _pinch_rot_accum:  float  = 0.0  ## total radians rotated this gesture (for revert)
var _pinch_zoom_start: float  = 1.0  ## zoom.x when this gesture began (for revert)

# ── World node ──────────────────────────────────────────────────────────────
var _world: Node2D = null
var _ui_manager: Node = null

# ── Snap state ──────────────────────────────────────────────────────────────
var _snapping:     bool  = false
var _snap_target:  float = 0.0   ## radians

# ── Screen-shake state ──────────────────────────────────────────────────────
var _shake_active: bool  = false
var _shake_start:  float = 0.0
var _shake_dur:    float = 0.2
var _shake_h:      bool  = false
var _shake_v:      bool  = false
var _shake_osc:    bool  = false


# ── Flip animation state ────────────────────────────────────────────────────
var _flip_start_rot: float   = 0.0
var _flip_start_pos: Vector2 = Vector2.ZERO
var _flip_pivot:     Vector2 = Vector2.ZERO

# ── Overlay FX layer (flash / darken / inversion) ───────────────────────────
var _fx_layer: CanvasLayer  = null
var _fx_white: ColorRect    = null
var _fx_black: ColorRect    = null
var _fx_invert: ColorRect   = null

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_world      = get_node_or_null("/root/Main/HexBoard")
	_ui_manager = get_node_or_null("/root/Main/UIManager")
	_center_on_board()
	_build_fx_layer()
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("piece_captured_for_screen_fx"):
		gm.piece_captured_for_screen_fx.connect(_on_piece_captured)

## True while a modal popup (victory screen, bot-difficulty panel, or
## MusicPlayer's Audio popup) covers the board -- camera pan/rotate/zoom
## input is suppressed while one of these is open.
func _popups_open() -> bool:
	if MusicPlayer.is_audio_popup_open():
		return true
	if _ui_manager != null and _ui_manager.has_method("is_modal_popup_open") and _ui_manager.is_modal_popup_open():
		return true
	return false

func _center_on_board() -> void:
	var board_layer = get_node_or_null("/root/Main/HexBoard/BoardLayer")
	if board_layer == null: _fallback_center(); return
	var used_rect: Rect2i = board_layer.get_used_rect()
	if used_rect.size == Vector2i.ZERO: _fallback_center(); return
	var center_coord = used_rect.position + used_rect.size / 2
	global_position  = board_layer.to_global(board_layer.map_to_local(center_coord))

func _fallback_center() -> void:
	global_position = get_viewport().get_visible_rect().size / 2.0

# ── Snap animation ──────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	## Screen-shake effect — runs independently of snap animation
	if _shake_active:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - _shake_start
		if elapsed >= _shake_dur:
			offset = Vector2.ZERO
			_shake_active = false
		else:
			var progress: float = elapsed / _shake_dur
			var amp: float = 14.0 * (1.0 - progress)
			var freq: float = 45.0
			if _shake_osc:
				offset = Vector2(sin(elapsed * freq) * amp, cos(elapsed * freq * 0.67) * amp)
			elif _shake_h:
				offset = Vector2(sin(elapsed * freq) * amp, 0.0)
			else:
				offset = Vector2(0.0, sin(elapsed * freq) * amp)

	## Rotation snap animation (unchanged)
	if not _snapping or _world == null:
		return
	if _popups_open():
		return
	var diff: float = _angle_diff(_world.rotation, _snap_target)
	if abs(diff) < 0.001:
		## Close enough — snap to exact target and stop
		_rotate_world(_snap_target - _world.rotation)
		_snapping = false
		return
	## Smooth exponential decay toward target
	_rotate_world(diff * snap_speed * delta)

## Shortest signed angle from 'from' to 'to' (both radians)
func _angle_diff(from: float, to: float) -> float:
	var d: float = fmod(to - from, TAU)
	if d > PI:  d -= TAU
	if d < -PI: d += TAU
	return d

# ── Snap trigger ────────────────────────────────────────────────────────────
func _start_snap() -> void:
	if _world == null:
		return
	var deg: float        = rad_to_deg(_world.rotation)
	var snap_target_deg: float = round(deg / snap_degrees) * snap_degrees
	_snap_target = deg_to_rad(snap_target_deg)
	_snapping    = true

func _cancel_snap() -> void:
	_snapping = false

# ── Input ───────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:

	## A popup (victory screen, bot-difficulty panel, Audio popup) covers the
	## board -- drop any camera input and clear in-progress drag/rotate state
	## so nothing is left "stuck" once the popup closes.
	if _popups_open():
		_is_rotating      = false
		_pinch_type       = ""
		_pinch_rot_accum  = 0.0
		_touch_points.clear()
		_touch_prev.clear()
		return

	## ── Mouse wheel zoom ──────────────────────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = _clamp_vec(Vector2.ONE * snappedf(zoom.x + zoom_step, zoom_step))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = _clamp_vec(Vector2.ONE * snappedf(zoom.x - zoom_step, zoom_step))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_cancel_snap()
				_is_rotating  = true
				_last_mouse_x = event.position.x
			else:
				_is_rotating = false
				_start_snap()

	## ── Right-drag rotation (PC) ──────────────────────────────────────────
	if event is InputEventMouseMotion and _is_rotating:
		var dx: float = event.position.x - _last_mouse_x
		_rotate_world(deg_to_rad(dx * rotate_sensitivity))
		_last_mouse_x = event.position.x

	## ── Touch begin / end ─────────────────────────────────────────────────
	if event is InputEventScreenTouch:
		if event.pressed:
			_cancel_snap()
			_touch_points[event.index] = event.position
			_touch_prev[event.index]   = event.position
			## Second finger down — start a fresh 2-finger gesture record.
			if _touch_points.size() == 2:
				_pinch_type       = ""
				_pinch_rot_accum  = 0.0
				_pinch_zoom_start = zoom.x
		else:
			_touch_points.erase(event.index)
			_touch_prev.erase(event.index)
			_pinch_type      = ""
			_pinch_rot_accum = 0.0
			if _touch_points.is_empty():
				_start_snap()

	## ── Touch drag ────────────────────────────────────────────────────────
	if event is InputEventScreenDrag:
		_touch_prev[event.index]   = _touch_points.get(event.index, event.position)
		_touch_points[event.index] = event.position

		if _touch_points.size() == 1:
			## 1 finger drag = pan
			position -= event.relative / zoom.x

		elif _touch_points.size() == 2:
			var keys:  Array   = _touch_points.keys()
			var posA:  Vector2 = _touch_points[keys[0]]
			var posB:  Vector2 = _touch_points[keys[1]]
			var prevA: Vector2 = _touch_prev.get(keys[0], posA)
			var prevB: Vector2 = _touch_prev.get(keys[1], posB)
			var dA:    Vector2 = posA - prevA
			var dB:    Vector2 = posB - prevB

			## Classify by dominant axis this frame:
			##   vertical separation change → zoom
			##   horizontal average movement → rotate
			var vert_delta: float = abs(posA.y - posB.y) - abs(prevA.y - prevB.y)
			var horiz_avg:  float = (dA.x + dB.x) * 0.5
			var intent: String = "zoom" if abs(vert_delta) >= abs(horiz_avg) else "rotate"

			## If the type just switched, revert what the previous type applied.
			if _pinch_type != "" and intent != _pinch_type:
				if _pinch_type == "rotate":
					_rotate_world(-_pinch_rot_accum)
					_pinch_rot_accum = 0.0
				else:
					zoom = _clamp_vec(Vector2.ONE * _pinch_zoom_start)
			_pinch_type = intent

			if intent == "zoom":
				var dist_now:  float = abs(posA.y - posB.y)
				var dist_prev: float = abs(prevA.y - prevB.y)
				if dist_prev > 0.0:
					zoom = _clamp_vec(Vector2.ONE * snappedf(zoom.x * (1.0 + (dist_now - dist_prev) * 0.002), zoom_step))
			else:
				var rot: float = deg_to_rad(horiz_avg * rotate_sensitivity)
				_rotate_world(rot)
				_pinch_rot_accum += rot

	## ── Trackpad pinch ────────────────────────────────────────────────────
	if event is InputEventMagnifyGesture:
		zoom = _clamp_vec(Vector2.ONE * snappedf(zoom.x * event.factor, zoom_step))

# ── Helpers ─────────────────────────────────────────────────────────────────
func _rotate_world(angle_rad: float) -> void:
	if _world == null or angle_rad == 0.0:
		return
	var pivot: Vector2 = global_position
	_world.global_position = pivot + (_world.global_position - pivot).rotated(angle_rad)
	_world.rotation += angle_rad

func _clamp_vec(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, zoom_min, zoom_max), clampf(v.y, zoom_min, zoom_max))

# ── Overlay FX layer build ───────────────────────────────────────────────────
func _build_fx_layer() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 10
	add_child(_fx_layer)

	_fx_white = ColorRect.new()
	_fx_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_white.color = Color.WHITE
	_fx_white.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_fx_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_fx_white)

	_fx_black = ColorRect.new()
	_fx_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_black.color = Color.BLACK
	_fx_black.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_fx_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_fx_black)

	## Inversion rect — shader reads the screen and outputs inverted RGB.
	## modulate.a (animated 0→1→0) controls the blend strength via COLOR.a.
	_fx_invert = ColorRect.new()
	_fx_invert.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_invert.color = Color.WHITE
	_fx_invert.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_fx_invert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var invert_shader := Shader.new()
	invert_shader.code = "shader_type canvas_item;\nuniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest_mipmap;\nvoid fragment() {\n\tvec4 s = texture(SCREEN_TEXTURE, SCREEN_UV);\n\tCOLOR = vec4(1.0 - s.rgb, COLOR.a);\n}"
	var invert_mat := ShaderMaterial.new()
	invert_mat.shader = invert_shader
	_fx_invert.material = invert_mat
	_fx_layer.add_child(_fx_invert)

# ── Capture effect dispatcher ────────────────────────────────────────────────
func _on_piece_captured(board_pos: Vector2i, capturing_player: int) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	match gm.screen_effect_for(capturing_player):
		1: _fx_shake(true,  false, false)
		2: _fx_shake(false, true,  false)
		3: _fx_shake(false, false, true)
		5: _fx_flip(true)
		6: _fx_flip(false)
		7: _fx_zoom(board_pos)
		8: _fx_flash()
		9: _fx_darken()
		10: _fx_inversion()

# ── Individual effects ───────────────────────────────────────────────────────

func _fx_shake(h: bool, v: bool, osc: bool) -> void:
	_shake_h      = h
	_shake_v      = v
	_shake_osc    = osc
	_shake_dur    = 0.2
	_shake_start  = Time.get_ticks_msec() / 1000.0
	_shake_active = true

func _fx_flip(clockwise: bool) -> void:
	if _world == null:
		return
	_cancel_snap()
	_flip_start_rot = _world.rotation
	_flip_start_pos = _world.global_position
	_flip_pivot     = global_position          ## camera position = rotation pivot
	var dir: float  = 1.0 if clockwise else -1.0
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_method(_apply_flip_abs.bind(dir), 0.0, TAU, 0.3)
	tween.tween_callback(_finish_flip)

func _apply_flip_abs(progress: float, dir: float) -> void:
	if _world == null:
		return
	var angle: float       = progress * dir
	_world.rotation        = _flip_start_rot + angle
	_world.global_position = _flip_pivot + (_flip_start_pos - _flip_pivot).rotated(angle)

func _finish_flip() -> void:
	if _world != null:
		## TAU rotation is identity — restore exact start state to kill any float drift.
		_world.rotation        = _flip_start_rot
		_world.global_position = _flip_start_pos
	_start_snap()

func _fx_zoom(board_pos: Vector2i) -> void:
	var orig_zoom: Vector2 = zoom
	## Try to aim at the capturing piece's world position
	var aim_offset: Vector2 = Vector2.ZERO
	var board_layer = get_node_or_null("/root/Main/HexBoard/BoardLayer")
	if board_layer != null:
		var world_pos: Vector2 = board_layer.to_global(board_layer.map_to_local(board_pos))
		## Shift offset so the piece stays centered as we zoom in
		aim_offset = (world_pos - global_position) * (1.0 - 1.0 / 1.75)
	var orig_offset: Vector2 = offset
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(self, "zoom",   _clamp_vec(orig_zoom * 1.75),  0.12)
	tween.parallel().tween_property(self, "offset", orig_offset + aim_offset, 0.12)
	tween.tween_interval(0.1)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "zoom",   orig_zoom,   0.18)
	tween.parallel().tween_property(self, "offset", orig_offset, 0.18)

func _fx_flash() -> void:
	_fx_white.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_fx_white, "modulate:a", 0.70, 0.05)
	tween.tween_property(_fx_white, "modulate:a", 0.0,  0.05)
	tween.tween_property(_fx_white, "modulate:a", 0.70, 0.05)
	tween.tween_property(_fx_white, "modulate:a", 0.0,  0.05)

func _fx_darken() -> void:
	_fx_black.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_fx_black, "modulate:a", 0.65, 0.15)
	tween.tween_property(_fx_black, "modulate:a", 0.0,  0.15)

func _fx_inversion() -> void:
	_fx_invert.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_fx_invert, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(0.1)
	tween.tween_property(_fx_invert, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
