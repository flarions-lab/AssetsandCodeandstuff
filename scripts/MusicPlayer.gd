extends Node

## MusicPlayer.gd — autoload that manages background music across all scenes.
## Plays tracks from HexMusic folder one after another, looping back to the start.
## Provides mute and volume control.
## Also draws its own bottom-left overlay (🎵 button) on a CanvasLayer.
## The button opens a popup (styled like the victory "New Game" window)
## showing the current track name, a Mute toggle, a Music Volume slider
## (kept in sync with the Main Menu's Settings > Music Volume slider via
## volume_changed), and a Hex Drones Volume slider that controls
## SoundManager's piece move/rotate/destroy/turn sound volume.

signal volume_changed(value: float)
signal mute_changed(muted: bool)
signal preferences_changed

const TRACKS := [
	"res://assets/HexAudio/HexMusic/TheDeadbyJohnTasoulas.mp3",
	"res://assets/HexAudio/HexMusic/OdysseybyJohnTasoulas.mp3",
	"res://assets/HexAudio/HexMusic/Voyager1byJohnTasoulas.mp3",
	"res://assets/HexAudio/HexMusic/Ultra by Savfk.mp3",
	"res://assets/HexAudio/HexMusic/DreamwalkebyInfractionr.mp3",
	"res://assets/HexAudio/HexMusic/HealerbyInfraction.mp3",
	"res://assets/HexAudio/HexMusic/Deflector by Ghostrifter Official.mp3",
	"res://assets/HexAudio/HexMusic/DystopiabyNeutrin05.mp3",
	"res://assets/HexAudio/HexMusic/AmnesiabyMoochi.mp3",
	"res://assets/HexAudio/HexMusic/DefenseMatrixbyVyra.mp3",
	"res://assets/HexAudio/HexMusic/NEONUNDERWORLDbyPunchDeck.mp3",
	"res://assets/HexAudio/HexMusic/CARBONbyLesionX.mp3",
	"res://assets/HexAudio/HexMusic/EdgeofTomorrow.mp3",
	"res://assets/HexAudio/HexMusic/HOME-HeadFirst.mp3",
	"res://assets/HexAudio/HexMusic/MiamiSkyc.mp3",
	"res://assets/HexAudio/HexMusic/NEON DRIVbyGhostrifter.mp3",
	"res://assets/HexAudio/HexMusic/SyntheticPleasuresbyMOKKA.mp3",
	"res://assets/HexAudio/HexMusic/TRY ITbyJoeCrotty.mp3",
	"res://assets/HexAudio/HexMusic/UTOPIAbyashutosh.mp3",
	"res://assets/HexAudio/HexMusic/VHSSynthwaveElectro.mp3",
]

## Estimated BPM for each track, parallel to TRACKS.
## Used by the "BPM" glow effect to pulse in time with the music.
const TRACK_BPMS := [
	120.0,  ## The Dead (John Tasoulas)
	110.0,  ## Odyssey (John Tasoulas)
	118.0,  ## Voyager 1 (John Tasoulas)
	128.0,  ## Ultra (Savfk)
	100.0,  ## Dreamwalker (Infraction)
	 95.0,  ## Healer (Infraction)
	140.0,  ## Deflector (Ghostrifter Official)
	130.0,  ## Dystopia (Neutrin05)
	120.0,  ## Amnesia (Moochi)
	128.0,  ## Defense Matrix (Vyra)
	140.0,  ## NEON UNDERWORLD (PunchDeck)
	135.0,  ## CARBON (Lesion X)
	125.0,  ## Edge of Tomorrow
	128.0,  ## Head First (HOME)
	100.0,  ## Miami Sky
	128.0,  ## NEON DRIV (Ghostrifter Official)
	125.0,  ## Synthetic Pleasures (MOKKA)
	130.0,  ## TRY IT (Joe Crotty)
	118.0,  ## UTOPIA (ashutosh)
	115.0,  ## VHS Synthwave Electro
]

## Friendly display names for the Audio popup's "Now Playing" label, parallel
## to TRACKS.
const TRACK_NAMES := [
	"The Dead (John Tasoulas)",
	"Odyssey (John Tasoulas)",
	"Voyager 1 (John Tasoulas)",
	"Ultra (Savfk)",
	"Dreamwalker (Infraction)",
	"Healer (Infraction)",
	"Deflector (Ghostrifter Official)",
	"Dystopia (Neutrin05)",
	"Amnesia (Moochi)",
	"Defense Matrix (Vyra)",
	"NEON UNDERWORLD (PunchDeck)",
	"CARBON (Lesion X)",
	"Edge of Tomorrow",
	"Head First (HOME)",
	"Miami Sky",
	"NEON DRIV (Ghostrifter Official)",
	"Synthetic Pleasures (MOKKA)",
	"TRY IT (Joe Crotty)",
	"UTOPIA (ashutosh)",
	"VHS Synthwave Electro",
]

const SAVE_FILE    := "user://music_settings.cfg"
const SAVE_SECTION := "music"

## "Matching blue with gold trim" accent used by the Audio popup, matching the
## victory popup's WIN_GOLD in UIManager.gd.
const AUDIO_GOLD := Color(1.0, 0.85, 0.35)

var _player:      AudioStreamPlayer
var _canvas:      CanvasLayer

## Live BPM detection state
var _spectrum:        AudioEffectSpectrumAnalyzerInstance = null
var _current_bpm:     float = 128.0
var _energy_avg:      float = 0.0
var _last_beat_sec:   float = -1.0
var _beat_intervals:  Array = []
var _beat_cooldown:   float = 0.0
const _BPM_HISTORY   := 6     ## beat intervals to average over
const _ONSET_RATIO   := 1.35  ## energy must exceed running-avg × this to count as a beat
const _MIN_INTERVAL  := 0.25  ## shortest valid beat gap (240 BPM ceiling)
const _MAX_INTERVAL  := 1.5   ## longest valid beat gap  (40  BPM floor)
var _audio_btn:      Button     ## overlay button -- opens the Audio popup
var _audio_backdrop: ColorRect  ## Audio popup dim background
var _audio_panel:    Panel      ## Audio popup main panel
var _track_label:    Label      ## "Now Playing: <track>" in the popup
var _popup_mute_btn: Button     ## Mute/Unmute toggle inside the popup
var _music_slider:   HSlider    ## Music Volume slider inside the popup
var _track_index: int   = 0
var _muted:       bool  = false
var _volume_db:   float = 1.0   ## linear 0–1 mapped to -30–0 dB
var _liked_set:    Dictionary = {}   ## track_idx -> true
var _disliked_set: Dictionary = {}   ## track_idx -> true
var _playlist:     Array      = []   ## shuffled weighted play order
var _playlist_pos: int        = 0
var _like_btn:     Button     = null
var _dislike_btn:  Button     = null

func _ready() -> void:
	_load_settings()
	## Round 38 — sync mute state to SoundManager (piece SFX) so Mute silences
	## everything, not just music. Deferred since MusicPlayer's _ready runs
	## before SoundManager's per the autoload order in project.godot.
	SoundManager.call_deferred("set_muted", _muted)
	_setup_player()
	_setup_overlay()
	_build_playlist()
	_play_track(_playlist[_playlist_pos])

# ---------------------------------------------------------------------------
# Audio player
# ---------------------------------------------------------------------------
func _setup_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_track_finished)
	_apply_volume()
	_setup_spectrum()

func _setup_spectrum() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectSpectrumAnalyzer:
			_spectrum = AudioServer.get_bus_effect_instance(bus_idx, i)
			return
	var effect := AudioEffectSpectrumAnalyzer.new()
	effect.buffer_length = 0.05
	effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	AudioServer.add_bus_effect(bus_idx, effect)
	_spectrum = AudioServer.get_bus_effect_instance(
		bus_idx, AudioServer.get_bus_effect_count(bus_idx) - 1)

func _play_track(index: int) -> void:
	_track_index = index % TRACKS.size()
	_current_bpm    = TRACK_BPMS[_track_index] if _track_index < TRACK_BPMS.size() else 128.0
	_last_beat_sec  = -1.0
	_beat_intervals.clear()
	_energy_avg     = 0.0
	_update_track_label()
	var path: String = TRACKS[_track_index]
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("MusicPlayer: failed to load track: " + path)
		_on_track_finished()   ## skip broken track
		return
	_player.stream = stream
	_player.play()
	print("MusicPlayer: playing " + path)
	print("MusicPlayer: is_playing=", _player.is_playing(), " vol_db=", _player.volume_db)
	_update_like_dislike_btns()

func _on_track_finished() -> void:
	_advance_playlist()

func skip_track() -> void:
	_advance_playlist()

func _advance_playlist() -> void:
	_playlist_pos += 1
	if _playlist_pos >= _playlist.size():
		_playlist.shuffle()
		_playlist_pos = 0
	_play_track(_playlist[_playlist_pos])

## Friendly name of the currently-playing track, for the Audio popup.
func get_track_name() -> String:
	if _track_index >= 0 and _track_index < TRACK_NAMES.size():
		return TRACK_NAMES[_track_index]
	return "Unknown Track"

func _process(delta: float) -> void:
	_detect_beat(delta)

func _detect_beat(delta: float) -> void:
	if _spectrum == null or not _player.playing:
		return
	_beat_cooldown -= delta
	var mag: Vector2 = _spectrum.get_magnitude_for_frequency_range(60.0, 200.0)
	var energy: float = (mag.x + mag.y) * 0.5
	_energy_avg = lerp(_energy_avg, energy, 0.12)
	if energy > _energy_avg * _ONSET_RATIO and energy > 0.003 and _beat_cooldown <= 0.0:
		var now: float = Time.get_ticks_msec() / 1000.0
		if _last_beat_sec > 0.0:
			var gap: float = now - _last_beat_sec
			if gap >= _MIN_INTERVAL and gap <= _MAX_INTERVAL:
				_beat_intervals.append(gap)
				if _beat_intervals.size() > _BPM_HISTORY:
					_beat_intervals.pop_front()
				var total: float = 0.0
				for g in _beat_intervals:
					total += g
				_current_bpm = 60.0 / (total / _beat_intervals.size())
		_last_beat_sec = now
		_beat_cooldown = _MIN_INTERVAL

## Live-detected BPM of the current track. Seeds from TRACK_BPMS on track
## change and converges to the actual tempo within a few beats.
func get_current_bpm() -> float:
	return _current_bpm

func get_playback_position() -> float:
	if _player != null and _player.playing:
		return _player.get_playback_position()
	return 0.0

func toggle_mute() -> void:
	print("toggle_mute called, was: ", _muted)
	_muted = not _muted
	print("toggle_mute now: ", _muted)
	_apply_volume()
	SoundManager.set_muted(_muted)
	_update_popup_mute_btn()
	mute_changed.emit(_muted)
	_save_settings()

func set_volume(linear: float) -> void:
	## linear: 0.0 (silent) → 1.0 (full)
	_volume_db = linear
	_apply_volume()
	_save_settings()
	volume_changed.emit(_volume_db)

func get_volume() -> float:
	return _volume_db

func is_muted() -> bool:
	return _muted

func _apply_volume() -> void:
	if _muted or _volume_db <= 0.0:
		## set_volume's contract is "0.0 (silent) -> 1.0 (full)" -- the old
		## lerp floor of -30 dB was still clearly audible, so sliding to 0
		## didn't actually reach silence.
		_player.volume_db = -80.0
	else:
		## Ceiling -6 dB ≈ 50% amplitude — music only, SoundManager is unaffected
		_player.volume_db = lerp(-30.0, -6.0, _volume_db)

# ---------------------------------------------------------------------------
# Overlay UI — bottom-right corner, visible in every scene
# ---------------------------------------------------------------------------
func _setup_overlay() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10   ## above game UI
	add_child(_canvas)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	row.offset_left   = 6
	row.offset_top    = 360
	row.add_theme_constant_override("separation", 6)
	_canvas.add_child(row)

	## Music button -- opens the popup (track name, mute, and volume sliders).
	_audio_btn = Button.new()
	_audio_btn.text = "🎵"
	_audio_btn.custom_minimum_size = Vector2(60, 40)
	_audio_btn.add_theme_font_size_override("font_size", 18)
	_audio_btn.tooltip_text = "Music & sound settings"
	_audio_btn.pressed.connect(_toggle_audio_popup)
	row.add_child(_audio_btn)

	_build_audio_popup()

# ---------------------------------------------------------------------------
# Audio popup -- styled like UIManager's victory "New Game" popup: a dim
# full-screen backdrop behind a centered, gold-trimmed deep-blue panel.
# ---------------------------------------------------------------------------
func _build_audio_popup() -> void:
	## Dim backdrop
	_audio_backdrop = ColorRect.new()
	_audio_backdrop.color = Color(0, 0, 0, 0.55)
	_audio_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_audio_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_audio_backdrop.visible = false
	_canvas.add_child(_audio_backdrop)

	## Centered popup panel
	_audio_panel = Panel.new()
	_audio_panel.anchor_left = 0.5; _audio_panel.anchor_top = 0.5
	_audio_panel.anchor_right = 0.5; _audio_panel.anchor_bottom = 0.5
	_audio_panel.offset_left = -200.0; _audio_panel.offset_top = -182.0
	_audio_panel.offset_right = 200.0; _audio_panel.offset_bottom = 182.0
	_audio_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_audio_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.16, 0.38, 0.97)
	style.set_corner_radius_all(16)
	style.border_color = AUDIO_GOLD
	style.set_border_width_all(3)
	style.shadow_color = Color(AUDIO_GOLD.r, AUDIO_GOLD.g, AUDIO_GOLD.b, 0.30)
	style.shadow_size = 8
	_audio_panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(_audio_panel)

	## X close button (top-right)
	var x_btn := Button.new()
	x_btn.text = "✕"
	x_btn.anchor_left = 1.0; x_btn.anchor_right = 1.0
	x_btn.offset_left = -46.0; x_btn.offset_top = 8.0
	x_btn.offset_right = -8.0;  x_btn.offset_bottom = 42.0
	x_btn.add_theme_font_size_override("font_size", 18)
	x_btn.pressed.connect(_close_audio_popup)
	_style_gold_button(x_btn)
	_audio_panel.add_child(x_btn)

	## Title
	var title := Label.new()
	title.text = "🎵"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.offset_left = 16.0; title.offset_right = -16.0
	title.offset_top = 14.0; title.offset_bottom = 50.0
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", AUDIO_GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.20))
	title.add_theme_constant_override("outline_size", 5)
	_audio_panel.add_child(title)

	## "Now Playing" track name
	_track_label = Label.new()
	_track_label.text = "Now Playing:\n" + get_track_name()
	_track_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_track_label.anchor_left = 0.0; _track_label.anchor_right = 1.0
	_track_label.offset_left = 16.0; _track_label.offset_right = -16.0
	_track_label.offset_top = 54.0; _track_label.offset_bottom = 112.0
	_track_label.add_theme_font_size_override("font_size", 14)
	_track_label.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	_audio_panel.add_child(_track_label)

	## Like / Dislike row
	var like_row := HBoxContainer.new()
	like_row.anchor_left = 0.0; like_row.anchor_right = 1.0
	like_row.offset_left = 16.0; like_row.offset_right = -16.0
	like_row.offset_top = 116.0; like_row.offset_bottom = 150.0
	like_row.add_theme_constant_override("separation", 10)
	_audio_panel.add_child(like_row)

	_like_btn = Button.new()
	_like_btn.text = "▲ Like"
	_like_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_like_btn.add_theme_font_size_override("font_size", 14)
	_like_btn.pressed.connect(func(): like_track(_track_index))
	_style_gold_button(_like_btn)
	like_row.add_child(_like_btn)

	_dislike_btn = Button.new()
	_dislike_btn.text = "▽ Dislike"
	_dislike_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dislike_btn.add_theme_font_size_override("font_size", 14)
	_dislike_btn.pressed.connect(func(): dislike_track(_track_index))
	_style_gold_button(_dislike_btn)
	like_row.add_child(_dislike_btn)

	## Skip + Mute row
	var btn_row := HBoxContainer.new()
	btn_row.anchor_left = 0.0; btn_row.anchor_right = 1.0
	btn_row.offset_left = 16.0; btn_row.offset_right = -16.0
	btn_row.offset_top = 158.0; btn_row.offset_bottom = 196.0
	btn_row.add_theme_constant_override("separation", 10)
	_audio_panel.add_child(btn_row)

	_popup_mute_btn = Button.new()
	_popup_mute_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup_mute_btn.add_theme_font_size_override("font_size", 14)
	_popup_mute_btn.pressed.connect(toggle_mute)
	_style_gold_button(_popup_mute_btn)
	btn_row.add_child(_popup_mute_btn)

	var skip_btn := Button.new()
	skip_btn.text = "⏭ Skip"
	skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip_btn.add_theme_font_size_override("font_size", 14)
	skip_btn.pressed.connect(func():
		skip_track()
		_update_track_label()
	)
	_style_gold_button(skip_btn)
	btn_row.add_child(skip_btn)

	## Music Volume -- mirrors the Main Menu's Settings > Music Volume slider
	## (both call MusicPlayer.set_volume / read get_volume, and stay in sync
	## live via volume_changed).
	var music_lbl := Label.new()
	music_lbl.text = "Music Volume"
	music_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_lbl.anchor_left = 0.0; music_lbl.anchor_right = 1.0
	music_lbl.offset_left = 16.0; music_lbl.offset_right = -16.0
	music_lbl.offset_top = 204.0; music_lbl.offset_bottom = 228.0
	music_lbl.add_theme_font_size_override("font_size", 14)
	music_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	_audio_panel.add_child(music_lbl)

	_music_slider = HSlider.new()
	_music_slider.min_value = 0.0
	_music_slider.max_value = 1.0
	_music_slider.step      = 0.01
	_music_slider.value     = _volume_db
	_music_slider.anchor_left = 0.0; _music_slider.anchor_right = 1.0
	_music_slider.offset_left = 16.0; _music_slider.offset_right = -16.0
	_music_slider.offset_top = 232.0; _music_slider.offset_bottom = 256.0
	_music_slider.value_changed.connect(set_volume)
	_audio_panel.add_child(_music_slider)
	volume_changed.connect(func(v: float): _music_slider.set_value_no_signal(v))

	## Hex Drones Volume -- piece move/rotate/destroy/turn sounds (SoundManager).
	var drones_lbl := Label.new()
	drones_lbl.text = "Hex Drones Volume"
	drones_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drones_lbl.anchor_left = 0.0; drones_lbl.anchor_right = 1.0
	drones_lbl.offset_left = 16.0; drones_lbl.offset_right = -16.0
	drones_lbl.offset_top = 266.0; drones_lbl.offset_bottom = 290.0
	drones_lbl.add_theme_font_size_override("font_size", 14)
	drones_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	_audio_panel.add_child(drones_lbl)

	var drones_slider := HSlider.new()
	drones_slider.min_value = 0.0
	drones_slider.max_value = 1.0
	drones_slider.step      = 0.01
	drones_slider.value     = SoundManager.get_volume()
	drones_slider.anchor_left = 0.0; drones_slider.anchor_right = 1.0
	drones_slider.offset_left = 16.0; drones_slider.offset_right = -16.0
	drones_slider.offset_top = 294.0; drones_slider.offset_bottom = 318.0
	drones_slider.value_changed.connect(SoundManager.set_volume)
	_audio_panel.add_child(drones_slider)

	_update_popup_mute_btn()

func _toggle_audio_popup() -> void:
	var now_visible: bool = not _audio_panel.visible
	_audio_backdrop.visible = now_visible
	_audio_panel.visible    = now_visible
	if now_visible:
		_update_track_label()
		_update_popup_mute_btn()
		_update_like_dislike_btns()

## Whether the Audio popup is currently open -- used by CameraController to
## suppress camera pan/rotate/zoom input while it's up.
func is_audio_popup_open() -> bool:
	return _audio_panel != null and _audio_panel.visible

func _close_audio_popup() -> void:
	_audio_backdrop.visible = false
	_audio_panel.visible    = false

func _update_track_label() -> void:
	if _track_label == null: return
	_track_label.text = "Now Playing:\n" + get_track_name()

func _update_popup_mute_btn() -> void:
	if _popup_mute_btn == null: return
	_popup_mute_btn.text = "🔇 Mute" if not _muted else "🔊 Unmute"

## Shared "blue with gold trim" button skin -- same look as the victory
## popup's buttons in UIManager.gd (_style_gold_button).
func _style_gold_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.24, 0.50, 1.0)
	normal.border_color = Color(AUDIO_GOLD.r, AUDIO_GOLD.g, AUDIO_GOLD.b, 0.85)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.19, 0.33, 0.64, 1.0)
	hover.border_color = AUDIO_GOLD

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.07, 0.13, 0.28, 1.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78))
	btn.add_theme_color_override("font_hover_color", AUDIO_GOLD)
	btn.add_theme_color_override("font_pressed_color", AUDIO_GOLD)

# ---------------------------------------------------------------------------
# Persist settings
# ---------------------------------------------------------------------------
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) == OK:
		_volume_db = float(cfg.get_value(SAVE_SECTION, "volume", 1.0))
		_muted     = bool(cfg.get_value(SAVE_SECTION,  "muted",  false))
		var liked_arr: Array = cfg.get_value(SAVE_SECTION, "liked", [])
		var disliked_arr: Array = cfg.get_value(SAVE_SECTION, "disliked", [])
		for idx in liked_arr:    _liked_set[int(idx)] = true
		for idx in disliked_arr: _disliked_set[int(idx)] = true

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "volume",   _volume_db)
	cfg.set_value(SAVE_SECTION, "muted",    _muted)
	cfg.set_value(SAVE_SECTION, "liked",    _liked_set.keys())
	cfg.set_value(SAVE_SECTION, "disliked", _disliked_set.keys())
	cfg.save(SAVE_FILE)

# ---------------------------------------------------------------------------
# Playlist — weighted shuffle (liked 2×, disliked excluded)
# ---------------------------------------------------------------------------
func _build_playlist() -> void:
	_playlist = []
	var base: Array = []
	for i in range(TRACKS.size()):
		if _disliked_set.has(i):
			continue
		base.append(i)
		if _liked_set.has(i):
			_playlist.append(i)   ## liked track inserted twice
	_playlist.append_array(base)
	_playlist.shuffle()
	if _playlist.is_empty():
		## all tracks disliked — fall back to full shuffled list
		for i in range(TRACKS.size()):
			_playlist.append(i)
		_playlist.shuffle()
	_playlist_pos = 0

# ---------------------------------------------------------------------------
# Like / Dislike / Neutral preference API
# ---------------------------------------------------------------------------
func get_like_state(idx: int) -> String:
	if _liked_set.has(idx):    return "liked"
	if _disliked_set.has(idx): return "disliked"
	return "neutral"

func like_track(idx: int) -> void:
	if _liked_set.has(idx):
		_liked_set.erase(idx)   ## toggle liked → neutral
	else:
		_liked_set[idx] = true
		_disliked_set.erase(idx)
	_build_playlist()
	_update_like_dislike_btns()
	_save_settings()
	preferences_changed.emit()

func dislike_track(idx: int) -> void:
	if _disliked_set.has(idx):
		_disliked_set.erase(idx)   ## toggle disliked → neutral
	else:
		_disliked_set[idx] = true
		_liked_set.erase(idx)
	_build_playlist()
	_update_like_dislike_btns()
	_save_settings()
	preferences_changed.emit()

func set_neutral(idx: int) -> void:
	_liked_set.erase(idx)
	_disliked_set.erase(idx)
	_build_playlist()
	_save_settings()
	preferences_changed.emit()

func _update_like_dislike_btns() -> void:
	if _like_btn == null or _dislike_btn == null: return
	var state: String = get_like_state(_track_index)
	_style_gold_button(_like_btn)
	_style_gold_button(_dislike_btn)
	if state == "liked":
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.10, 0.42, 0.14, 1.0)
		s.border_color = Color(0.30, 0.88, 0.40)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		_like_btn.add_theme_stylebox_override("normal", s)
		_like_btn.add_theme_color_override("font_color", Color(0.70, 1.0, 0.72))
	elif state == "disliked":
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.44, 0.08, 0.08, 1.0)
		s.border_color = Color(0.90, 0.28, 0.28)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		_dislike_btn.add_theme_stylebox_override("normal", s)
		_dislike_btn.add_theme_color_override("font_color", Color(1.0, 0.68, 0.68))
