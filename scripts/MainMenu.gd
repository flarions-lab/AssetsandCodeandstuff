extends Node

## MainMenu.gd — builds the entire main menu UI in code.

const PRESET_FILE    := "user://hex_color_presets.cfg"
const PRESET_SECTION := "presets"
const DRONE_PRESET_FILE := "user://drone_presets.cfg"

var _bg_callback: Callable

var _settings_panel:  Panel
var _colors_panel:    Panel
var _music_taste_panel: Panel
var _taste_liked_list:   VBoxContainer
var _taste_neutral_list: VBoxContainer
var _taste_disliked_list: VBoxContainer

## Play panel
var _play_panel:          Panel  = null
var _play_main_view:      VBoxContainer = null
var _play_local_view:     VBoxContainer = null
var _p1_bot_check:        CheckBox = null
var _p2_bot_check:        CheckBox = null
var _p1_diff_btns:        Array    = []
var _p2_diff_btns:        Array    = []
var _local_p1_diff:       int      = 1
var _local_p2_diff:       int      = 1

## Bot Battles panel
var _battle_panel: Panel = null

## Store panel (accounts/login + entitlement-gated store)
var _store_panel: Panel = null

## Account panel (login/register/switch-account) + the clickable username button
var _account_panel: Panel  = null
var _uname_btn:      Button = null

## Update-available badge + panel
var _update_panel:           Panel  = null
var _update_badge_btn:       Button = null
var _pending_update_version: String = ""

## Achievements panel
var _achievements_panel: Panel = null
var _achievements_list: VBoxContainer = null

## Bot profile definitions — each dict drives both the UI card and game setup.
## Sounds: index into SoundManager.SOUNDS (0-based).  Impact N = index N+1.
## Effects: screen_fx IDs per GameManager comment; drive_fx/destroy_fx per MainMenu DRIVE_EFFECTS/DESTROY_EFFECTS.
const BOT_PROFILES: Array = [
	{
		"id":            "bey",
		"name":          "Bey",
		"subtitle":      "Master of the Rotating Blade",
		"desc":          "Hunts multi-piece dives. Ignores defended single targets.\nStays at distance — then strikes with everything.",
		"drone_color":   Color(0.047, 0.251, 0.733, 1.0),
		"blade_color":   Color(0.831, 0.922, 0.918, 1.0),
		"drone_body":    "DronesDoubleBlackRing",
		"blade_variant": "HexBladesPowerStripe",
		"glow_inner":    Color(0.796, 0.0,   0.129, 1.0),
		"glow_outer":    Color(0.847, 0.847, 0.847, 0.4),
		"screen_fx":     7,
		"drive_fx":         6,
		"destroy_drive_fx": 7,
		"destroy_fx":       4,
		"snd_move":      13,
		"snd_rotate":    10,
		"snd_destroy":   6,
		"difficulty":    2,
		"glow_effect":   "Flicker",
		"glow_speed":    5.0,
	},
	{
		"id":            "tron",
		"name":          "Tron",
		"subtitle":      "Defender of the Grid",
		"desc":          "Holds the line on the grid with disciplined hard-mode play —\nluminous trails, circuit board, and a cold neon edge.",
		"drone_color":   Color("0b2d48"),
		"blade_color":   Color("c6ffff"),
		"drone_body":    "DronesBlankHollow",
		"blade_variant": "HexBladesShort",
		"glow_inner":    Color("043658"),
		"glow_outer":    Color("66fffb66"),
		"glow_effect":   "Trail",
		"glow_speed":    1.0,
		"screen_fx":        3,   ## Screen Shake Oscillate
		"drive_fx":         6,   ## Spin
		"destroy_drive_fx": 7,   ## Multi Spin
		"destroy_fx":       8,   ## Pixilate B
		"snd_move":      13,      ## Impact 12
		"snd_rotate":    7,       ## Impact 6
		"snd_destroy":   8,       ## Impact 7
		"snd_turn":      -1,      ## none
		"background":    "circuit_loop",
		"difficulty":    2,
	},
	{
		"id":            "clu",
		"name":          "CLU",
		"subtitle":      "Perfector of the Grid",
		"desc":          "Imposes a flawless, ruthless order on the grid —\nopens by seizing the centre, then grinds out perfection.",
		"drone_color":   Color("0a0b0ce5"),
		"blade_color":   Color("ff9c00"),
		"drone_body":    "DronesBlankHollow",
		"blade_variant": "HexBladesShort",
		"glow_inner":    Color("f79d02ce"),
		"glow_outer":    Color("f79d0281"),
		"glow_effect":   "Trail",
		"glow_speed":    1.0,
		"screen_fx":        3,   ## Screen Shake Oscillate
		"drive_fx":         6,   ## Spin
		"destroy_drive_fx": 7,   ## Multi Spin
		"destroy_fx":       8,   ## Pixilate B
		"snd_move":      13,      ## Impact 12
		"snd_rotate":    7,       ## Impact 6
		"snd_destroy":   8,       ## Impact 7
		"snd_turn":      -1,      ## none
		"background":    "circuit_loop",
		"difficulty":    2,
	},
	{
		"id":            "omnitrix",
		"name":          "Omni Trix",
		"subtitle":      "the Genetically Superior",
		"desc":          "Adapts to every threat with flawless genetic precision —\nsilver alien tech wrapped in a venom-green glow.",
		"drone_color":   Color("9e9e9e"),
		"blade_color":   Color("a1ff2f"),
		"drone_body":    "DronesBlankReverseGradient",
		"blade_variant": "HexBladesShort",
		"glow_effect":   "Breathing",
		"glow_opacity":  2.0,    ## 2× the max-slider opacity (extra-bright glow)
		"glow_speed":    5.0,    ## max speed
		"glow_inner":    Color("a1ff2f"),   ## card swatch only (per-state below override in-game)
		"glow_outer":    Color("a3b0b1"),
		"glow_selected_inner": Color("000000"),
		"glow_selected_outer": Color("a3b0b1"),
		"glow_move_inner":     Color("a1ff2f"),
		"glow_move_outer":     Color("a1ff2f"),
		"glow_capture_inner":  Color("000000"),
		"glow_capture_outer":  Color("a3b0b1"),
		"screen_fx":        8,   ## Flash
		"drive_fx":         4,   ## Flash
		"destroy_drive_fx": 4,   ## Flash
		"destroy_fx":       7,   ## Implode Flash
		"snd_move":      18,     ## Omnitrix Move
		"snd_rotate":    21,     ## Omnitrix Rotate
		"snd_destroy":   19,     ## Omnitrix Capture
		"snd_turn":      20,     ## Omnitrix Time In
		"difficulty":    2,
	},
	{
		"id":            "skynet",
		"name":          "Skynet",
		"subtitle":      "Successor of Man",
		"desc":          "Never retreats. A threatened unit is reinforced by another —\nor the attacker is eliminated. Cold steel and red logic.",
		"drone_color":   Color("68727e"),
		"blade_color":   Color("ff4c4c"),
		"drone_body":    "DronesMetallic",
		"blade_variant": "HexBladesSharpDash",
		"glow_effect":   "Flicker",
		"glow_opacity":  1.0,    ## max visible
		"glow_speed":    2.0,    ## 40% of max speed (5.0)
		"glow_inner":    Color("ff2c2c"),
		"glow_outer":    Color("a3b0b1"),
		"screen_fx":        10,  ## Inversion
		"drive_fx":         5,   ## Slide
		"drive_speed":      0.75,
		"destroy_drive_fx": 1,   ## Snap (instant — shares the one drive speed)
		"destroy_fx":       6,   ## Explode Flash
		"snd_move":      4,      ## Impact 3
		"snd_rotate":    11,     ## Impact 10
		"snd_destroy":   16,     ## Impact 15
		"snd_turn":      15,     ## Impact 14 (labelled "Project 14")
		"difficulty":    2,
	},
	{
		"id":            "microbots",
		"name":          "MicroBots",
		"subtitle":      "If you can think it, microbots do it",
		"desc":          "A swarm that never strays — every unit stays within reach of\nthe hive. Moves as one mass, even when it strikes.",
		"drone_color":   Color("0d0d0d"),
		"blade_color":   Color("302727"),
		"drone_body":    "DronesGradient",
		"blade_variant": "HexBladesSolid",
		"glow_effect":   "Trail",
		"glow_speed":    2.5,    ## 50% of max speed (5.0)
		"glow_inner":    Color("202020"),
		"glow_outer":    Color("2d2e2e"),
		"screen_fx":        9,   ## Darken
		"drive_fx":         2,   ## Fade
		"drive_speed":      0.6,
		"destroy_drive_fx": 5,   ## Slide
		"destroy_drive_speed": 0.35,
		"destroy_fx":       4,   ## Split
		"snd_move":      24,     ## Microbot Move
		"snd_rotate":    25,     ## Servo Whir
		"snd_destroy":   6,      ## Impact 5
		"snd_turn":      1,      ## Stone Tile
		"difficulty":    2,
	},
	{
		"id":            "candytech",
		"name":          "Candy Tech",
		"subtitle":      "Engineering from the Bubble Gum Princess",
		"desc":          "Engineering made from elemental candy — a short-sighted but\ndeep-thinking machine, forever trying to expand mother's empire.",
		"drone_color":   Color("eed4e9e9"),
		"blade_color":   Color("fc91f8fd"),
		"drone_body":    "DronesBlankPepperMint",
		"blade_variant": "HexBladesSharp",
		"glow_effect":   "Breathing",
		"glow_speed":    0.25,   ## 5% of max speed (5.0)
		"glow_inner":    Color("8c448c"),
		"glow_outer":    Color("f299c0"),
		"screen_fx":        3,   ## Screen Shake Oscillate
		"drive_fx":         5,   ## Slide
		"drive_speed":      0.5,
		"destroy_drive_fx": 5,   ## Slide
		"destroy_drive_speed": 0.15,
		"destroy_fx":       6,   ## Explode Flash
		"snd_move":      22,     ## Ballblamburgler
		"snd_rotate":    22,     ## Ballblamburgler
		"snd_destroy":   23,     ## Explosion
		"snd_turn":      1,      ## Stone Tile
		"difficulty":    2,
	},
]

## Puzzle panel
var _puzzle_panel:              Panel       = null
var _puzzle_tile_index:         int         = 0   ## 0-6 → tile types 1-7
var _puzzle_preview_drone_rect: TextureRect = null
var _puzzle_preview_blade_rect: TextureRect = null
var _puzzle_preview_tile_label: Label       = null

## Multiplayer panels
var _mp_mode_panel:   Panel   ## top-level: pick Browse or Matchmaking
var _mp_browse_panel: Panel   ## server-browser lobby list
var _mp_mm_panel:     Panel   ## matchmaking

## Browse panel widgets
var _browse_status:   Label
var _browse_list:     VBoxContainer
var _browse_name_field: LineEdit
var _browse_start_btn:  Button
var _browse_lobby_code_label: Label
var _browse_join_code_field: LineEdit

## Matchmaking panel widgets
var _mm_status:       Label
var _mm_find_btn:     Button
var _mm_cancel_btn:   Button
var _mm_start_btn:    Button

var _pick_p1_drone: ColorPickerButton
var _pick_p1_blade: ColorPickerButton
var _pick_p2_drone: ColorPickerButton
var _pick_p2_blade: ColorPickerButton
var _preset_list:   VBoxContainer
var _saved_drones_list: VBoxContainer = null
## Board-tile colour pickers (3 hexagons + a shared ColorPicker popup).
const _BOARD_HEX_TEX := preload("res://assets/Board-Tile_White.png")
var _tile_color_popup:  PopupPanel    = null
var _tile_color_picker: ColorPicker   = null
var _tile_color_group:  String        = ""
var _tile_color_btn:    TextureButton = null

## Hex Drones panel tab state
var _drones_colors_container: Control
var _drones_sounds_container: Control
var _drones_backgrounds_container: Control
var _drones_blades_container: Control
var _background_buttons: Dictionary = {}   ## id (String, "" = none) -> Button

## Drones tab state
var _drones_tab_player:        int         = 1
var _drones_blade_label:       Label       = null
var _drones_body_label:        Label       = null
var _drones_preview_drone_rect: TextureRect = null
var _drones_preview_blade_rect: TextureRect = null
var _drones_preview_player_hex: TextureRect = null
var _drones_preview_player_label: Label    = null
var _p1_blades_option:         OptionButton = null
var _p2_blades_option:         OptionButton = null
var _p1_body_option:           OptionButton = null
var _p2_body_option:           OptionButton = null

## Glow-tab containers + pickers
var _drones_glow_container:     Control     = null
var _glow_preview_drone_rect:   TextureRect = null
var _glow_preview_blade_rect:   TextureRect = null
var _glow_preview_tile_label:   Label       = null
var _glow_preview_tile_index:   int         = 0
var _glow_preview_player:       int         = 1
var _glow_preview_player_label: Label       = null
var _glow_preview_player_hex:   TextureRect = null
var _glow_preview_ring:         Control     = null
var _glow_active_type:          String      = "selected"
var _glow_opacity_slider:       HSlider     = null
var _glow_speed_slider:         HSlider     = null
## Per-player gradient enable toggles
var _glow_p1_grad_toggle: CheckButton = null
var _glow_p2_grad_toggle: CheckButton = null
## Inner pickers: [p1_sel, p1_mov, p1_cap, p2_sel, p2_mov, p2_cap]
var _glow_inner_picks: Array = []
## Outer pickers: same order
var _glow_outer_picks: Array = []

## Glow-effect toggle buttons, keyed by effect id — kept so lock-state can be
## refreshed later (see _refresh_all_lock_states).
var _glow_effect_btns: Dictionary = {}
const _GLOW_EFFECTS: Array = [["Pulse","Pulse"],["HeartBeat","Heart Beat"],["Breathing","Breathing"],
	["Trail","Trail"],["Flicker","Flicker"],["InwardPull","Inward Pull"],["OutwardPull","Outward Pull"],
	["BPM","BPM"],["Ring","Ring"]]

const SCREEN_EFFECTS: Array = [
	[0,  "None",                     ""],
	[1,  "Screen Shake Horizontal",  "0.2s"],
	[2,  "Screen Shake Vertical",    "0.2s"],
	[3,  "Screen Shake Oscillate",   "0.2s"],
	[5,  "Flip Clockwise",           "0.6s"],
	[6,  "Flip Counterclockwise",    "0.6s"],
	[7,  "Dramatic Zoom",            "0.4s"],
	[8,  "Flash",                    "0.2s"],
	[9,  "Darken",                   "0.3s"],
	[10, "Inversion",                "0.2s"],
]
const DRIVE_EFFECTS: Array = [
	[1, "Snap",       "Instant position change"],
	[2, "Fade",       "Fade out at origin, fade in at destination"],
	[3, "Zoom",       "Scale to zero, teleport, scale back up"],
	[4, "Flash",      "Brightness flashes before and after jump"],
	[5, "Slide",      "Piece glides to chosen tile"],
	[6, "Spin",       "Rotates 360° while gliding to chosen space"],
	[7, "Multi Spin", "Spins 1440° in place then slides to chosen space"],
	[8, "Pixilate",   "Dissolves into pixels then flashes into chosen position"],
]
const DESTROY_EFFECTS: Array = [
	[1, "Explode",       "Scale up and fade out"],
	[2, "Implode",       "Scale down and fade out"],
	[3, "Pixilate",      "Dissolve into scattered pixel chunks"],
	[4, "Split",         "Piece splits perpendicular to attack direction"],
	[5, "Flash",         "Brightness pulse then disappear"],
	[6, "Explode Flash", "Bright flash, then scale-up fade"],
	[7, "Implode Flash", "Bright flash, then scale-down fade"],
	[8, "Pixilate B",    "Like Pixilate, but pixels use the glow colour"],
	[9, "Knockout",      "Flash on impact, then fly off in the attack direction"],
]

## Screen-effects tab
var _drones_screen_container: Control    = null
var _screen_effect_btns:      Dictionary = {}
var _window_mode_btns:        Array      = []   ## [windowed_btn, borderless_btn, fullscreen_btn]

## Screen-tab per-player state
var _screen_edit_player: int    = 1
var _screen_p1_btn:      Button = null
var _screen_p2_btn:      Button = null

## Drive-tab containers + state
var _drones_drive_container:   Control      = null
var _drive_effect_btns:         Dictionary   = {}
var _drive_mode_btns:           Array        = []   ## [drive_btn, destroy_drive_btn]
var _drive_edit_mode:           int          = 0    ## 0 = Drive, 1 = Destroy Drive
var _drive_speed_slider:       HSlider      = null
var _drive_speed_label:        Label        = null
var _destroy_speed_slider:     HSlider      = null
var _destroy_speed_label:      Label        = null
var _drive_edit_player:        int          = 1
var _drive_preview_drone_rect: TextureRect  = null
var _drive_preview_blade_rect: TextureRect  = null
var _drive_preview_wrap:       Control      = null
var _drive_preview_player_label: Label      = null
var _drive_preview_player_hex:   TextureRect = null
var _drive_preview_animating:  bool         = false

## Destroy-tab containers + state
var _drones_destroy_container:   Control     = null
var _destroy_effect_btns:        Dictionary  = {}
var _destroy_preview_drone_rect: TextureRect = null
var _destroy_preview_blade_rect: TextureRect = null
var _destroy_preview_wrap:       Control     = null
var _destroy_preview_player:     int         = 1
var _destroy_preview_player_label: Label     = null
var _destroy_preview_player_hex:   TextureRect = null
var _destroy_preview_animating:  bool        = false

## Colors-tab live preview state
var _preview_tile_index:   int         = 0     ## 0–6, cycles through Tile types 1–7
var _preview_drone_rect:   TextureRect = null
var _preview_blade_rect:   TextureRect = null
var _preview_tile_label:   Label       = null
var _nav_left_blade:       TextureRect = null  ## blade TextureRect inside ◀ nav btn
var _nav_right_blade:      TextureRect = null  ## blade TextureRect inside ▶ nav btn
var _preview_player:       int         = 1     ## 1 = P1, 2 = P2
var _preview_player_label: Label       = null  ## "P1"/"P2" text inside the toggle btn
var _preview_player_hex:   TextureRect = null  ## hex body inside the toggle btn
var _background_list_vbox: VBoxContainer
var _sound_rows_p1:         Array = []
var _sound_rows_p2:         Array = []
var _sound_rows_p1_rotate:  Array = []
var _sound_rows_p2_rotate:  Array = []
var _sound_rows_p1_destroy: Array = []
var _sound_rows_p2_destroy: Array = []
var _sound_rows_p1_turn:    Array = []
var _sound_rows_p2_turn:    Array = []

func _ready() -> void:
	## Bot-battle visuals are temporary: undo any P2 customization a bot profile
	## applied, restoring the player's own choices. Runs on every menu load, so it
	## covers finishing a battle, quitting early, or otherwise returning here.
	GameManager.revert_bot_battle_profile()

	var canvas := CanvasLayer.new()
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	## Animated / solid-color background — mirrors AnimatedBackgroundDisplay in
	## the board scene so the player's Hex Drones background choice shows here too.
	var menu_bg_rect := TextureRect.new()
	menu_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu_bg_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	menu_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_bg_rect.visible = false
	canvas.add_child(menu_bg_rect)

	var menu_solid_rect := ColorRect.new()
	menu_solid_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_solid_rect.visible = false
	canvas.add_child(menu_solid_rect)

	_bg_callback = func():
		if BackgroundManager.selected_id.begins_with(BackgroundManager.SOLID_COLOR_PREFIX):
			menu_bg_rect.texture = null
			menu_bg_rect.visible = false
			menu_solid_rect.color   = BackgroundManager.get_custom_color(BackgroundManager.selected_id)
			menu_solid_rect.visible = true
			return
		menu_solid_rect.visible = false
		var tex: Texture2D = BackgroundManager.build_selected_texture()
		menu_bg_rect.texture = tex
		menu_bg_rect.visible = tex != null
		var b: float = BackgroundManager.brightness_for(BackgroundManager.selected_id)
		menu_bg_rect.modulate = Color(b, b, b, 1.0)

	_bg_callback.call()
	BackgroundManager.background_changed.connect(_bg_callback)

	## Small always-visible version label — lets update issues actually be
	## diagnosed (is the applied version advancing across restarts or not?)
	## instead of being a black box. Deliberately NOT at the very bottom edge:
	## this project's Android export uses edge_to_edge=true, so content there
	## can be rendered directly under the OS's own gesture bar / 3-button nav
	## UI and never actually be visible, even though it's genuinely drawing.
	## Top-left, with the same mobile safe-area clearance used for the
	## in-game HUD, avoids repeating that mistake at the other edge. Added
	## AFTER the background rects (menu_bg_rect/menu_solid_rect) so it draws
	## on top of them — previously it was added before them and got fully
	## covered whenever the player had a background selected.
	var version_top_inset: float = 36.0 if _is_mobile() else 0.0
	var version_lbl := Label.new()
	version_lbl.text = "v" + UpdateManager.get_current_version() + UpdateManager.get_status_suffix()
	version_lbl.add_theme_font_size_override("font_size", 12)
	version_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	version_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	version_lbl.offset_left = 8; version_lbl.offset_top = 6 + version_top_inset
	version_lbl.offset_right = 268; version_lbl.offset_bottom = 26 + version_top_inset
	canvas.add_child(version_lbl)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var col := VBoxContainer.new()
	col.alignment           = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(300, 0)
	center.add_child(col)

	var title := Label.new()
	title.text = "HEX-A-GONE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	col.add_child(title)

	## Username — click to log in / switch accounts.
	_spacer(col, 10)
	_uname_btn = Button.new()
	_uname_btn.text = AccountManager.username
	_uname_btn.flat = true
	_uname_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_uname_btn.add_theme_font_size_override("font_size", 14)
	_uname_btn.tooltip_text = "Click to log in or switch accounts"
	_uname_btn.pressed.connect(func(): _account_panel.open())
	col.add_child(_uname_btn)

	_update_badge_btn = Button.new()
	_update_badge_btn.text = "⬆ Update Available"
	_update_badge_btn.flat = true
	_update_badge_btn.visible = false
	_update_badge_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_update_badge_btn.add_theme_font_size_override("font_size", 13)
	_update_badge_btn.pressed.connect(func(): _update_panel.open(_pending_update_version))
	col.add_child(_update_badge_btn)

	_spacer(col, 30)
	_make_button(col, "PLAY",        _on_play)

	## REJOIN GAME — only shown when a previous online lobby code exists
	## (e.g. after returning to the menu or a connection error mid-game).
	if not NetworkManager.last_lobby_code.is_empty():
		_spacer(col, 12)
		var rejoin_btn := _make_button(col, "↩ REJOIN GAME", _on_rejoin)
		rejoin_btn.add_theme_font_size_override("font_size", 16)

	_spacer(col, 12)
	_make_button(col, "ACHIEVEMENTS", _on_achievements)
	_spacer(col, 12)
	_make_button(col, "HEX DRONES",  _on_colors)
	_spacer(col, 12)
	_make_button(col, "STORE",       _on_store)
	_spacer(col, 12)
	_make_button(col, "SETTINGS",    _on_settings)

	_account_panel    = preload("res://scripts/AccountPanel.gd").new()
	_store_panel      = preload("res://scripts/StorePanel.gd").new()
	_store_panel.account_panel = _account_panel
	_update_panel     = preload("res://scripts/UpdatePanel.gd").new()
	_settings_panel   = _build_settings_panel()
	_colors_panel     = _build_colors_panel()
	_mp_mode_panel    = _build_mp_mode_panel()
	_mp_browse_panel  = _build_mp_browse_panel()
	_mp_mm_panel      = _build_mp_mm_panel()
	_music_taste_panel = _build_music_taste_panel()
	_puzzle_panel     = _build_puzzles_panel()
	_play_panel       = _build_play_panel()
	_battle_panel     = _build_bot_battles_panel()
	_achievements_panel = _build_achievements_panel()

	canvas.add_child(_settings_panel)
	canvas.add_child(_colors_panel)
	canvas.add_child(_mp_mode_panel)
	canvas.add_child(_mp_browse_panel)
	canvas.add_child(_mp_mm_panel)
	canvas.add_child(_music_taste_panel)
	canvas.add_child(_puzzle_panel)
	canvas.add_child(_play_panel)
	canvas.add_child(_battle_panel)
	canvas.add_child(_store_panel)
	canvas.add_child(_account_panel)
	canvas.add_child(_achievements_panel)
	canvas.add_child(_update_panel)

	UpdateManager.update_available.connect(func(version: String):
		_pending_update_version = version
		_update_badge_btn.visible = true)
	if not UpdateManager._latest_version.is_empty():
		_pending_update_version = UpdateManager._latest_version
		_update_badge_btn.visible = true

	var refresh_uname_btn := func(): _uname_btn.text = AccountManager.username
	AccountManager.login_succeeded.connect(refresh_uname_btn)
	AccountManager.register_succeeded.connect(refresh_uname_btn)

	## First launch: no saved session token yet — prompt the player to
	## register/log in once. The token then persists in user://account.cfg, so
	## this won't fire again unless they explicitly switch accounts.
	if not AccountManager.is_logged_in():
		_account_panel.open()

	MusicPlayer.preferences_changed.connect(_rebuild_music_taste_lists)

	NetworkManager.lobby_ready.connect(_on_lobby_ready)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.connected_to_host.connect(_on_connected_to_host)
	NetworkManager.connection_failed.connect(_on_mp_connection_failed)
	NetworkManager.game_start_received.connect(_on_game_start_received)
	NetworkManager.lobby_list_received.connect(_on_lobby_list_received)
	NetworkManager.matchmake_waiting.connect(_on_matchmake_waiting)
	NetworkManager.matchmake_matched.connect(_on_matchmake_matched)

	## Entitlements can arrive asynchronously after this panel is already
	## built (e.g. login/sync still in flight at startup) — refresh every
	## gated selector's lock state whenever they change, not just at build time.
	AccountManager.entitlements_updated.connect(func(_e): _refresh_all_lock_states())
	## A freshly-earned achievement unlocks its assets immediately in
	## AchievementManager's own bookkeeping (local flag, checked by
	## is_unlocked() regardless of login state) — but that alone doesn't
	## touch the already-built gating UI. Without this, a local-only or not-
	## yet-synced unlock would show "COMPLETED" in the Achievements panel
	## (which re-checks fresh every time it opens) while the Hex Drones
	## panel kept showing the corresponding asset as Locked, since nothing
	## told it to recheck.
	AchievementManager.achievement_unlocked.connect(func(_id): _refresh_all_lock_states())

	## Bump every menu font size 15% and every button 20% bigger on mobile
	## (touch) devices, and pull each top-level panel in from the screen edges.
	if _is_mobile():
		_apply_mobile_font_scale(self, MOBILE_FONT_SCALE)
		_apply_mobile_button_scale(self, MOBILE_BUTTON_SCALE)
		var top_level_panels: Array = [
			_settings_panel, _colors_panel, _mp_mode_panel, _mp_browse_panel,
			_mp_mm_panel, _music_taste_panel, _puzzle_panel, _play_panel,
			_battle_panel, _store_panel, _account_panel, _achievements_panel,
		]
		for p in top_level_panels:
			if p != null:
				_apply_mobile_panel_inset(p, MOBILE_PANEL_INSET)

	## Return to puzzle drone-choice panel if coming back from "Drone Choice" button.
	if GameManager.return_to_puzzle_panel:
		GameManager.return_to_puzzle_panel = false
		_puzzle_panel.visible = true

# ---------------------------------------------------------------------------
# Mobile text scaling
# ---------------------------------------------------------------------------
const MOBILE_FONT_SCALE: float = 1.15

## Buttons are bumped 20% bigger, and top-level panels pulled 20px in from the
## screen edges, on mobile (touch) devices.
const MOBILE_BUTTON_SCALE: float = 1.2
const MOBILE_PANEL_INSET:  float = 20.0

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

## Recursively multiply every explicit font_size override under `node` by `factor`.
func _apply_mobile_font_scale(node: Node, factor: float) -> void:
	if node is Control:
		var c := node as Control
		if c.has_theme_font_size_override("font_size"):
			var sz: int = c.get_theme_font_size("font_size")
			c.add_theme_font_size_override("font_size", int(round(float(sz) * factor)))
	for child in node.get_children():
		_apply_mobile_font_scale(child, factor)

## Recursively multiply every Button's existing custom_minimum_size by `factor`
## (skips buttons with no minimum size set).
func _apply_mobile_button_scale(node: Node, factor: float) -> void:
	if node is BaseButton:
		var b := node as Control
		if b.custom_minimum_size != Vector2.ZERO:
			b.custom_minimum_size *= factor
	for child in node.get_children():
		_apply_mobile_button_scale(child, factor)

## Pulls a top-level panel in from the screen edges by `extra` on each side —
## NOT recursive, so it never touches nested PanelContainer cards (bot
## battle/achievement/store rows) that happen to also be Panels.
func _apply_mobile_panel_inset(panel: Control, extra: float) -> void:
	panel.offset_left   += extra
	panel.offset_top    += extra
	panel.offset_right  -= extra
	panel.offset_bottom -= extra

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------
func _spacer(parent: Control, h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)

func _make_button(parent: Control, label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text                = label
	btn.custom_minimum_size = Vector2(280, 54)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

## A PLAY-panel mode button + its description label, stacked in one column.
func _build_play_mode_button(parent: Control, label: String, desc: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(300, 64)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(cb)
	parent.add_child(btn)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(300, 0)
	parent.add_child(desc_lbl)

	return btn

## Populates an OptionButton with `names`/`values` pairs, disabling and
## labeling any entry not yet unlocked in `category` (achievement gating).
func _populate_option_locked(option: OptionButton, names: Array, values: Array, category: String) -> void:
	for i in names.size():
		var locked: bool = not AchievementManager.is_asset_unlocked(category, values[i])
		option.add_item(names[i] + (" (Locked)" if locked else ""), i)
		option.set_item_disabled(i, locked)

## Re-applies (without rebuilding) existing OptionButton item text/disabled
## state — used by _refresh_all_lock_states when entitlements change after
## these were first populated.
func _refresh_option_locked(option: OptionButton, names: Array, values: Array, category: String) -> void:
	if option == null: return
	for i in names.size():
		var locked: bool = not AchievementManager.is_asset_unlocked(category, values[i])
		option.set_item_text(i, names[i] + (" (Locked)" if locked else ""))
		option.set_item_disabled(i, locked)

## Re-checks and re-applies lock state on every already-built gated selector.
## Entitlements can finish syncing (login, achievement unlock, cross-device
## refresh) after these were first built, so this must be callable any time,
## not just once at construction — connected to
## AccountManager.entitlements_updated.
func _refresh_all_lock_states() -> void:
	_refresh_option_locked(_p1_blades_option, _DRONES_BLADE_NAMES, _DRONES_BLADE_VARIANTS, "blade")
	_refresh_option_locked(_p2_blades_option, _DRONES_BLADE_NAMES, _DRONES_BLADE_VARIANTS, "blade")
	_refresh_option_locked(_p1_body_option, GameManager.DRONE_BODY_NAMES, GameManager.DRONE_BODY_FOLDERS, "drone_body")
	_refresh_option_locked(_p2_body_option, GameManager.DRONE_BODY_NAMES, GameManager.DRONE_BODY_FOLDERS, "drone_body")

	if _background_list_vbox != null:
		_rebuild_background_list(_background_list_vbox)

	_refresh_all_sound_highlights()

	for ef_id in _screen_effect_btns.keys():
		var btn: Button = _screen_effect_btns[ef_id]
		var base: String = btn.text.trim_suffix(" (Locked)")
		var locked: bool = not AchievementManager.is_asset_unlocked("screen_fx", ef_id)
		btn.text = base + (" (Locked)" if locked else "")
		btn.disabled = locked

	for ef_id in _drive_effect_btns.keys():
		var btn: Button = _drive_effect_btns[ef_id]
		var base: String = btn.text.trim_suffix(" (Locked)")
		var locked: bool = not AchievementManager.is_asset_unlocked("drive_fx", ef_id)
		btn.text = base + (" (Locked)" if locked else "")
		btn.disabled = locked

	for ef_id in _destroy_effect_btns.keys():
		var btn: Button = _destroy_effect_btns[ef_id]
		var base: String = btn.text.trim_suffix(" (Locked)")
		var locked: bool = not AchievementManager.is_asset_unlocked("destroy_fx", ef_id)
		btn.text = base + (" (Locked)" if locked else "")
		btn.disabled = locked

	for eid in _glow_effect_btns.keys():
		var btn: Button = _glow_effect_btns[eid]
		var base: String = btn.text.trim_suffix(" (Locked)")
		var locked: bool = not AchievementManager.is_asset_unlocked("glow_effect", eid)
		btn.text = base + (" (Locked)" if locked else "")
		btn.disabled = locked

## Small "X" button in a panel's top-right corner — the standard close control
## for every full-screen menu panel (replaces the older bottom-bar "Close"
## button, which ate into content space and could overlap tall tab content).
func _close_btn(panel: Panel, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = Vector2(32, 32)
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -42; btn.offset_top = 8
	btn.offset_right = -10; btn.offset_bottom = 40
	btn.pressed.connect(cb)
	panel.add_child(btn)

## Widens a ScrollContainer's scrollbar -- the bar you click-and-drag to
## scroll -- so it's easier to grab. 2x on mobile (touch), 2.25x on desktop.
func _widen_scrollbar(sc: ScrollContainer) -> void:
	var base_w: float = 16.0
	var default_theme := ThemeDB.get_default_theme()
	if default_theme and default_theme.has_stylebox("scroll", "VScrollBar"):
		var min_w: float = default_theme.get_stylebox("scroll", "VScrollBar").get_minimum_size().x
		if min_w > 0.0:
			base_w = min_w
	var factor: float = 2.0 if _is_mobile() else 2.25
	var target: float = base_w * factor

	var vbar := sc.get_v_scroll_bar()
	if vbar:
		vbar.custom_minimum_size.x = target

	var hbar := sc.get_h_scroll_bar()
	if hbar:
		hbar.custom_minimum_size.y = target

# ---------------------------------------------------------------------------
# Play panel
# ---------------------------------------------------------------------------
func _build_play_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80; panel.offset_top = 40
	panel.offset_right = -80; panel.offset_bottom = -40
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var h := Label.new()
	h.text = "PLAY"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 32)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_top = 10; h.offset_bottom = 54
	panel.add_child(h)

	## ── Main view (mode selection) ──────────────────────────────────────────
	## Two columns side by side so all five modes fit without scrolling/overlap.
	_play_main_view = VBoxContainer.new()
	_play_main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_play_main_view.offset_left = 40; _play_main_view.offset_top = 60
	_play_main_view.offset_right = -40; _play_main_view.offset_bottom = -20
	_play_main_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_main_view.add_theme_constant_override("separation", 10)
	panel.add_child(_play_main_view)

	var subtitle := Label.new()
	subtitle.text = "choose how to find a match."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	_play_main_view.add_child(subtitle)

	_spacer(_play_main_view, 16)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 40)
	_play_main_view.add_child(columns)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 10)
	columns.add_child(left_col)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 10)
	columns.add_child(right_col)

	_build_play_mode_button(left_col, "TUTORIAL", "Learn the Basics", _on_tutorial)
	_build_play_mode_button(left_col, "LOCAL PLAY", "Play Against Self, Local Human, or Base Bots", _on_play_show_local)
	_build_play_mode_button(left_col, "BOT BATTLES", "Play against Bots of Certain Playstyles", _on_play_bot_battles)

	_build_play_mode_button(right_col, "PUZZLES", "Solve Hand-Crafted Capture Puzzles",
		func(): _play_panel.visible = false; _on_puzzles())
	_build_play_mode_button(right_col, "MULTIPLAYER", "Play Online Against Another Player",
		func(): _play_panel.visible = false; _on_multiplayer())

	## ── Local config view (bot assignment + difficulty) ─────────────────────
	_play_local_view = VBoxContainer.new()
	_play_local_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_play_local_view.offset_left = 40; _play_local_view.offset_top = 60
	_play_local_view.offset_right = -40; _play_local_view.offset_bottom = -20
	_play_local_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_local_view.add_theme_constant_override("separation", 10)
	_play_local_view.visible = false
	panel.add_child(_play_local_view)

	## Bot seat checkboxes
	var check_row := HBoxContainer.new()
	check_row.alignment = BoxContainer.ALIGNMENT_CENTER
	check_row.add_theme_constant_override("separation", 40)
	_play_local_view.add_child(check_row)

	_p1_bot_check = CheckBox.new()
	_p1_bot_check.text = "Bot plays P1"
	_p1_bot_check.add_theme_font_size_override("font_size", 14)
	_p1_bot_check.toggled.connect(func(_v): _refresh_local_diff_btns())
	check_row.add_child(_p1_bot_check)

	_p2_bot_check = CheckBox.new()
	_p2_bot_check.text = "Bot plays P2"
	_p2_bot_check.add_theme_font_size_override("font_size", 14)
	_p2_bot_check.toggled.connect(func(_v): _refresh_local_diff_btns())
	check_row.add_child(_p2_bot_check)

	_spacer(_play_local_view, 6)

	## Difficulty columns side by side
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 50)
	_play_local_view.add_child(diff_row)

	var diff_names := ["Easy", "Medium", "Hard", "Extra Hard"]

	var p1_col := VBoxContainer.new()
	p1_col.alignment = BoxContainer.ALIGNMENT_CENTER
	p1_col.add_theme_constant_override("separation", 4)
	diff_row.add_child(p1_col)
	var p1_hdr := Label.new()
	p1_hdr.text = "P1 Bot"
	p1_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p1_hdr.add_theme_font_size_override("font_size", 15)
	p1_col.add_child(p1_hdr)
	_p1_diff_btns.clear()
	for i in 4:
		var b := Button.new()
		b.text = diff_names[i]
		b.custom_minimum_size = Vector2(130, 36)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_local_p1_diff.bind(i))
		p1_col.add_child(b)
		_p1_diff_btns.append(b)

	var p2_col := VBoxContainer.new()
	p2_col.alignment = BoxContainer.ALIGNMENT_CENTER
	p2_col.add_theme_constant_override("separation", 4)
	diff_row.add_child(p2_col)
	var p2_hdr := Label.new()
	p2_hdr.text = "P2 Bot"
	p2_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2_hdr.add_theme_font_size_override("font_size", 15)
	p2_col.add_child(p2_hdr)
	_p2_diff_btns.clear()
	for i in 4:
		var b := Button.new()
		b.text = diff_names[i]
		b.custom_minimum_size = Vector2(130, 36)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_local_p2_diff.bind(i))
		p2_col.add_child(b)
		_p2_diff_btns.append(b)

	_spacer(_play_local_view, 12)

	var start_btn := Button.new()
	start_btn.text = "LOCAL PLAY"
	start_btn.custom_minimum_size = Vector2(220, 54)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.pressed.connect(_on_local_play_start)
	_play_local_view.add_child(start_btn)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.custom_minimum_size = Vector2(120, 36)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.pressed.connect(func():
		_play_local_view.visible = false
		_play_main_view.visible  = true
	)
	_play_local_view.add_child(back_btn)

	_close_btn(panel, func(): _play_panel.visible = false)
	return panel

func _on_play_show_local() -> void:
	_local_p1_diff = GameManager.p1_bot_difficulty
	_local_p2_diff = GameManager.p2_bot_difficulty
	_play_main_view.visible  = false
	_play_local_view.visible = true
	_refresh_local_diff_btns()

func _on_play_bot_battles() -> void:
	_play_panel.visible   = false
	_battle_panel.visible = true

func _build_bot_battles_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80; panel.offset_top = 40
	panel.offset_right = -80; panel.offset_bottom = -40
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var h := Label.new()
	h.text = "BOT BATTLES"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 30)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_top = 10; h.offset_bottom = 52
	panel.add_child(h)

	var sub := Label.new()
	sub.text = "Challenge bots with unique playstyles"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 54; sub.offset_bottom = 76
	panel.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 80; scroll.offset_bottom = -12
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_widen_scrollbar(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	for profile in BOT_PROFILES:
		list.add_child(_build_bot_card(profile))

	_close_btn(panel, func():
		_battle_panel.visible = false
		_play_panel.visible   = true
		_play_main_view.visible  = true
		_play_local_view.visible = false
	)
	return panel

func _build_bot_card(profile: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.14, 0.17, 0.25, 1.0)
	card_style.corner_radius_top_left     = 6
	card_style.corner_radius_top_right    = 6
	card_style.corner_radius_bottom_left  = 6
	card_style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", card_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)

	## Color swatch showing drone + blade colors
	var swatch_col := VBoxContainer.new()
	swatch_col.custom_minimum_size = Vector2(56, 0)
	swatch_col.alignment = BoxContainer.ALIGNMENT_CENTER
	swatch_col.add_theme_constant_override("separation", 4)
	row.add_child(swatch_col)

	var drone_swatch := ColorRect.new()
	drone_swatch.custom_minimum_size = Vector2(48, 24)
	drone_swatch.color = profile.get("drone_color", Color.WHITE)
	swatch_col.add_child(drone_swatch)

	var blade_swatch := ColorRect.new()
	blade_swatch.custom_minimum_size = Vector2(48, 12)
	blade_swatch.color = profile.get("blade_color", Color.WHITE)
	swatch_col.add_child(blade_swatch)

	var glow_swatch := ColorRect.new()
	glow_swatch.custom_minimum_size = Vector2(48, 8)
	glow_swatch.color = profile.get("glow_inner", Color.WHITE)
	swatch_col.add_child(glow_swatch)

	## Name + description
	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.alignment = BoxContainer.ALIGNMENT_CENTER
	info_col.add_theme_constant_override("separation", 4)
	row.add_child(info_col)

	var name_lbl := Label.new()
	name_lbl.text = profile.get("name", "Bot")
	name_lbl.add_theme_font_size_override("font_size", 20)
	info_col.add_child(name_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = profile.get("subtitle", "")
	subtitle_lbl.add_theme_font_size_override("font_size", 12)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	info_col.add_child(subtitle_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = profile.get("desc", "")
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_col.add_child(desc_lbl)

	## Fight button
	var fight_btn := Button.new()
	fight_btn.text = "FIGHT"
	fight_btn.custom_minimum_size = Vector2(90, 54)
	fight_btn.add_theme_font_size_override("font_size", 16)
	fight_btn.pressed.connect(_on_bot_battle_start.bind(profile))
	row.add_child(fight_btn)

	return card

func _build_achievements_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80; panel.offset_top = 40
	panel.offset_right = -80; panel.offset_bottom = -40
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var h := Label.new()
	h.text = "ACHIEVEMENTS"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 30)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_top = 10; h.offset_bottom = 52
	panel.add_child(h)

	var sub := Label.new()
	sub.text = "What's possible, and what it unlocks"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 54; sub.offset_bottom = 76
	panel.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 80; scroll.offset_bottom = -12
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_widen_scrollbar(scroll)

	_achievements_list = VBoxContainer.new()
	_achievements_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_achievements_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_achievements_list)

	_rebuild_achievements_list()

	_close_btn(panel, func(): _achievements_panel.visible = false)
	return panel

## Rebuilt each time the panel opens so completed/incomplete state is current.
func _rebuild_achievements_list() -> void:
	for child in _achievements_list.get_children():
		child.queue_free()
	for achievement in AchievementManager.ACHIEVEMENTS:
		if achievement.has("category"):
			var section := Label.new()
			section.text = achievement["category"]
			section.add_theme_font_size_override("font_size", 16)
			section.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
			_achievements_list.add_child(section)
		_achievements_list.add_child(_build_achievement_card(achievement))

func _build_achievement_card(achievement: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.14, 0.17, 0.25, 1.0)
	card_style.corner_radius_top_left     = 6
	card_style.corner_radius_top_right    = 6
	card_style.corner_radius_bottom_left  = 6
	card_style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", card_style)

	## Completed cards sit at base brightness; incomplete ones are 20% darker.
	var completed: bool = AchievementManager.is_unlocked(achievement.get("id", ""))
	card.modulate = Color(1, 1, 1, 1) if completed else Color(0.8, 0.8, 0.8, 1)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = achievement.get("name", "Achievement")
	name_lbl.add_theme_font_size_override("font_size", 18)
	col.add_child(name_lbl)

	if completed:
		var status_lbl := Label.new()
		status_lbl.text = "COMPLETED"
		status_lbl.add_theme_font_size_override("font_size", 12)
		status_lbl.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
		col.add_child(status_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = achievement.get("description", "")
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_lbl)

	var unlock_lbl := Label.new()
	unlock_lbl.text = "Unlocks: " + str(achievement.get("unlocks", "—"))
	unlock_lbl.add_theme_font_size_override("font_size", 13)
	unlock_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.75))
	col.add_child(unlock_lbl)

	return card

func _on_bot_battle_start(profile: Dictionary) -> void:
	_apply_all_glow_settings()
	GameManager.apply_bot_battle_profile(profile)
	GameManager.p1_is_bot  = false
	GameManager.p2_is_bot  = true
	GameManager.mp_player  = 1
	GameManager.active_bot_profile_id = profile.get("id", "")
	get_tree().change_scene_to_file("res://node_2d.tscn")

func _on_local_p1_diff(d: int) -> void:
	_local_p1_diff = d
	_refresh_local_diff_btns()

func _on_local_p2_diff(d: int) -> void:
	_local_p2_diff = d
	_refresh_local_diff_btns()

func _refresh_local_diff_btns() -> void:
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel.corner_radius_top_left     = 5
	sel.corner_radius_top_right    = 5
	sel.corner_radius_bottom_left  = 5
	sel.corner_radius_bottom_right = 5
	var p1_active: bool = _p1_bot_check != null and _p1_bot_check.button_pressed
	var p2_active: bool = _p2_bot_check != null and _p2_bot_check.button_pressed
	for i in _p1_diff_btns.size():
		var b: Button = _p1_diff_btns[i]
		b.disabled = not p1_active
		if p1_active and i == _local_p1_diff:
			b.add_theme_stylebox_override("normal", sel)
		else:
			b.remove_theme_stylebox_override("normal")
	for i in _p2_diff_btns.size():
		var b: Button = _p2_diff_btns[i]
		b.disabled = not p2_active
		if p2_active and i == _local_p2_diff:
			b.add_theme_stylebox_override("normal", sel)
		else:
			b.remove_theme_stylebox_override("normal")

func _on_local_play_start() -> void:
	_apply_all_glow_settings()
	var p1_bot: bool = _p1_bot_check.button_pressed
	var p2_bot: bool = _p2_bot_check.button_pressed
	GameManager.p1_is_bot = p1_bot
	GameManager.p2_is_bot = p2_bot
	if p1_bot and p2_bot:
		GameManager.mp_player = 0
	elif p2_bot:
		GameManager.mp_player = 1
	elif p1_bot:
		GameManager.mp_player = 2
	else:
		GameManager.mp_player = 0
	if p1_bot:
		GameManager.set_bot_difficulty(1, _local_p1_diff)
	if p2_bot:
		GameManager.set_bot_difficulty(2, _local_p2_diff)
	get_tree().change_scene_to_file("res://node_2d.tscn")

# ---------------------------------------------------------------------------
# Settings panel
# ---------------------------------------------------------------------------
func _build_settings_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80; panel.offset_top = 60
	panel.offset_right = -80; panel.offset_bottom = -60
	panel.visible = false

	var h := Label.new()
	h.text = "SETTINGS"; h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 26)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_top = 10; h.offset_bottom = 50
	panel.add_child(h)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40; root.offset_top = 60
	root.offset_right = -40; root.offset_bottom = -20
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	## Mute button — stays in sync with the popup's mute button via mute_changed.
	var mute_btn := Button.new()
	mute_btn.text = "🔇 Mute" if not MusicPlayer.is_muted() else "🔊 Unmute"
	mute_btn.custom_minimum_size = Vector2(200, 40)
	mute_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mute_btn.add_theme_font_size_override("font_size", 14)
	mute_btn.pressed.connect(MusicPlayer.toggle_mute)
	var sync_mute := func(m: bool): mute_btn.text = "🔇 Mute" if not m else "🔊 Unmute"
	MusicPlayer.mute_changed.connect(sync_mute)
	mute_btn.tree_exiting.connect(func(): MusicPlayer.mute_changed.disconnect(sync_mute))
	root.add_child(mute_btn)

	var music_lbl := Label.new()
	music_lbl.text = "Music Volume"
	music_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_lbl.add_theme_font_size_override("font_size", 16)
	root.add_child(music_lbl)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 10)
	slider_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(slider_row)

	var vol_low := Label.new()
	vol_low.text = "🔈"
	vol_low.add_theme_font_size_override("font_size", 18)
	slider_row.add_child(vol_low)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.01
	slider.value     = MusicPlayer.get_volume()
	slider.custom_minimum_size = Vector2(585, 32)
	slider.value_changed.connect(_on_music_volume_changed)
	## MusicPlayer outlives this scene — disconnect the sync lambda when the
	## slider leaves the tree to avoid a dangling reference crash.
	var sync_slider := func(v: float): slider.set_value_no_signal(v)
	MusicPlayer.volume_changed.connect(sync_slider)
	slider.tree_exiting.connect(func(): MusicPlayer.volume_changed.disconnect(sync_slider))
	slider_row.add_child(slider)

	var vol_high := Label.new()
	vol_high.text = "🔊"
	vol_high.add_theme_font_size_override("font_size", 18)
	slider_row.add_child(vol_high)

	var drones_lbl := Label.new()
	drones_lbl.text = "Hex Drones Volume"
	drones_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drones_lbl.add_theme_font_size_override("font_size", 16)
	root.add_child(drones_lbl)

	var drones_row := HBoxContainer.new()
	drones_row.add_theme_constant_override("separation", 10)
	drones_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(drones_row)

	var drones_low := Label.new()
	drones_low.text = "🔈"
	drones_low.add_theme_font_size_override("font_size", 18)
	drones_row.add_child(drones_low)

	var drones_slider := HSlider.new()
	drones_slider.min_value = 0.0
	drones_slider.max_value = 1.0
	drones_slider.step      = 0.01
	drones_slider.value     = SoundManager.get_volume()
	drones_slider.custom_minimum_size = Vector2(585, 32)
	drones_slider.value_changed.connect(SoundManager.set_volume)
	drones_row.add_child(drones_slider)

	var drones_high := Label.new()
	drones_high.text = "🔊"
	drones_high.add_theme_font_size_override("font_size", 18)
	drones_row.add_child(drones_high)

	var wm_lbl := Label.new()
	wm_lbl.text = "WINDOW MODE"
	wm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wm_lbl.add_theme_font_size_override("font_size", 15)
	root.add_child(wm_lbl)

	var wm_row := HBoxContainer.new()
	wm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	wm_row.add_theme_constant_override("separation", 8)
	root.add_child(wm_row)

	_window_mode_btns.clear()
	var wm_labels := ["Windowed", "Borderless", "Fullscreen"]
	for i in 3:
		var wm_btn := Button.new()
		wm_btn.text = wm_labels[i]
		wm_btn.custom_minimum_size = Vector2(110, 38)
		wm_btn.add_theme_font_size_override("font_size", 13)
		wm_btn.pressed.connect(_on_window_mode_selected.bind(i))
		wm_row.add_child(wm_btn)
		_window_mode_btns.append(wm_btn)
	_refresh_window_mode_btns()

	var taste_btn := Button.new()
	taste_btn.text = "MUSIC TASTE"
	taste_btn.custom_minimum_size = Vector2(200, 40)
	taste_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	taste_btn.add_theme_font_size_override("font_size", 14)
	taste_btn.pressed.connect(func():
		_settings_panel.visible = false
		_music_taste_panel.visible = true
		_rebuild_music_taste_lists()
	)
	root.add_child(taste_btn)

	_close_btn(panel, _on_settings_close)
	return panel

# ---------------------------------------------------------------------------
# Music Taste panel — drag-and-drop song preference sorter
# ---------------------------------------------------------------------------
func _build_music_taste_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60; panel.offset_top = 40
	panel.offset_right = -60; panel.offset_bottom = -40
	panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.18, 0.97)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var h := Label.new()
	h.text = "MUSIC TASTE"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 22)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_top = 12; h.offset_bottom = 48
	panel.add_child(h)

	var hint := Label.new()
	hint.text = "Drag songs between columns to sort your preferences"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 50; hint.offset_bottom = 72
	panel.add_child(hint)

	## Three-column container
	var cols := HBoxContainer.new()
	cols.anchor_left = 0.0; cols.anchor_right = 1.0
	cols.anchor_top  = 0.0; cols.anchor_bottom = 1.0
	cols.offset_left = 20; cols.offset_right = -20
	cols.offset_top  = 76; cols.offset_bottom = -12
	cols.add_theme_constant_override("separation", 12)
	panel.add_child(cols)

	var col_defs := [
		["♥ Liked", Color(0.25, 0.80, 0.35), "liked"],
		["Neutral",  Color(0.75, 0.82, 1.00), "neutral"],
		["✕ Disliked", Color(0.95, 0.35, 0.35), "disliked"],
	]
	for col_def in col_defs:
		var col_name: String = col_def[2]
		var col_box := VBoxContainer.new()
		col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_box.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		col_box.add_theme_constant_override("separation", 4)
		cols.add_child(col_box)

		var col_hdr := Label.new()
		col_hdr.text = col_def[0]
		col_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_hdr.add_theme_font_size_override("font_size", 15)
		col_hdr.add_theme_color_override("font_color", col_def[1])
		col_box.add_child(col_hdr)

		var sep_line := ColorRect.new()
		sep_line.color = col_def[1]
		sep_line.custom_minimum_size = Vector2(0, 2)
		sep_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_box.add_child(sep_line)

		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col_box.add_child(scroll)
		_widen_scrollbar(scroll)

		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 4)
		scroll.add_child(list)

		## Drop-target forwarding on the list VBox
		list.set_drag_forwarding(
			func(_pos): return null,
			func(_pos, data): return typeof(data) == TYPE_DICTIONARY and data.has("track"),
			func(_pos, data): _handle_taste_drop(int(data["track"]), col_name)
		)

		match col_name:
			"liked":   _taste_liked_list   = list
			"neutral": _taste_neutral_list  = list
			"disliked": _taste_disliked_list = list

	_close_btn(panel, _on_taste_close)
	return panel

func _handle_taste_drop(track_idx: int, col_name: String) -> void:
	if MusicPlayer.get_like_state(track_idx) == col_name: return
	match col_name:
		"liked":   MusicPlayer.like_track(track_idx)
		"disliked": MusicPlayer.dislike_track(track_idx)
		"neutral": MusicPlayer.set_neutral(track_idx)

func _rebuild_music_taste_lists() -> void:
	if _taste_liked_list == null: return
	for list in [_taste_liked_list, _taste_neutral_list, _taste_disliked_list]:
		for child in list.get_children():
			child.queue_free()

	for i in range(MusicPlayer.TRACK_NAMES.size()):
		var state: String = MusicPlayer.get_like_state(i)
		var target_list: VBoxContainer
		match state:
			"liked":   target_list = _taste_liked_list
			"disliked": target_list = _taste_disliked_list
			_:           target_list = _taste_neutral_list

		var track_idx := i
		var btn := Button.new()
		btn.text = MusicPlayer.TRACK_NAMES[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD

		btn.set_drag_forwarding(
			func(_pos): return {"track": track_idx},
			func(_pos, _data): return false,
			func(_pos, _data): pass
		)
		target_list.add_child(btn)

# ---------------------------------------------------------------------------
# Hex Drones panel  (Colors + Sounds tabs)
# ---------------------------------------------------------------------------
func _build_colors_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40; panel.offset_top = 20
	panel.offset_right = -40; panel.offset_bottom = -20
	panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14; root.offset_top = 8
	root.offset_right = -14; root.offset_bottom = -8
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	## Added AFTER root so it sits on top for input priority — root's rect
	## extends into this same top-right corner, and (being a Container, which
	## defaults to intercepting mouse input) would otherwise swallow most
	## clicks meant for this button since a later-added sibling gets input
	## priority over an earlier one in any overlapping region.
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -42; close_btn.offset_top = 8
	close_btn.offset_right = -10; close_btn.offset_bottom = 40
	close_btn.pressed.connect(_on_colors_close)
	panel.add_child(close_btn)

	## Title
	var title := Label.new()
	title.text = "HEX DRONES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	## Tab switcher row
	var tab_row := HBoxContainer.new()
	tab_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tab_row.add_theme_constant_override("separation", 8)
	root.add_child(tab_row)

	var tab_colors := Button.new()
	tab_colors.text = "COLORS"
	tab_colors.custom_minimum_size = Vector2(140, 36)
	tab_colors.add_theme_font_size_override("font_size", 15)

	var tab_sounds := Button.new()
	tab_sounds.text = "SOUNDS"
	tab_sounds.custom_minimum_size = Vector2(140, 36)
	tab_sounds.add_theme_font_size_override("font_size", 15)

	var tab_backgrounds := Button.new()
	tab_backgrounds.text = "BACKGROUNDS"
	tab_backgrounds.custom_minimum_size = Vector2(140, 36)
	tab_backgrounds.add_theme_font_size_override("font_size", 15)

	var tab_blades := Button.new()
	tab_blades.text = "DRONES"
	tab_blades.custom_minimum_size = Vector2(120, 36)
	tab_blades.add_theme_font_size_override("font_size", 15)

	var tab_glow := Button.new()
	tab_glow.text = "GLOW"
	tab_glow.custom_minimum_size = Vector2(100, 36)
	tab_glow.add_theme_font_size_override("font_size", 15)

	var tab_screen := Button.new()
	tab_screen.text = "SCREEN"
	tab_screen.custom_minimum_size = Vector2(110, 36)
	tab_screen.add_theme_font_size_override("font_size", 15)

	var tab_drive := Button.new()
	tab_drive.text = "DRIVE"
	tab_drive.custom_minimum_size = Vector2(100, 36)
	tab_drive.add_theme_font_size_override("font_size", 15)

	var tab_destroy := Button.new()
	tab_destroy.text = "DESTROY"
	tab_destroy.custom_minimum_size = Vector2(110, 36)
	tab_destroy.add_theme_font_size_override("font_size", 15)

	## Tab order, left → right: Drones, Colors, Glow, Drive, Destroy, Screen,
	## Sounds, Backgrounds.
	tab_row.add_child(tab_blades)
	tab_row.add_child(tab_colors)
	tab_row.add_child(tab_glow)
	tab_row.add_child(tab_drive)
	tab_row.add_child(tab_destroy)
	tab_row.add_child(tab_screen)
	tab_row.add_child(tab_sounds)
	tab_row.add_child(tab_backgrounds)

	## ── COLORS container ────────────────────────────────────────────────────
	_drones_colors_container = VBoxContainer.new()
	_drones_colors_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_colors_container.add_theme_constant_override("separation", 8)
	root.add_child(_drones_colors_container)

	## 3-column layout: saved presets (left) | preview + board tiles (centre) | pickers (right)
	var colors_top := HBoxContainer.new()
	colors_top.add_theme_constant_override("separation", 10)
	colors_top.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	colors_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drones_colors_container.add_child(colors_top)

	## Column 1 — saved presets list (far left, fills the height)
	var presets_col := VBoxContainer.new()
	presets_col.add_theme_constant_override("separation", 4)
	presets_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets_col.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	colors_top.add_child(presets_col)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets_col.add_child(scroll)
	_widen_scrollbar(scroll)

	_preset_list = VBoxContainer.new()
	_preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## Fill the scroll viewport and centre the rows vertically so the presets sit
	## at the same level as the (centred) preview and pickers; still scrolls if the
	## list grows past the viewport.
	_preset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preset_list.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(_preset_list)
	_rebuild_preset_list()

	## Column 2 — preview (centre, expands to fill remaining width)
	var preview_col := VBoxContainer.new()
	preview_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview_col.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_col.add_theme_constant_override("separation", 4)
	colors_top.add_child(preview_col)

	## Tile label + P1/P2 toggle in a centred sub-row
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_row.add_theme_constant_override("separation", 8)
	preview_col.add_child(top_row)

	_preview_tile_label = Label.new()
	_preview_tile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_tile_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_preview_tile_label.add_theme_font_size_override("font_size", 13)
	_preview_tile_label.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0))
	top_row.add_child(_preview_tile_label)

	var p1p2_toggle_btn := _make_hex_toggle_btn()
	p1p2_toggle_btn.pressed.connect(_on_toggle_preview_player)
	top_row.add_child(p1p2_toggle_btn)

	## Nav row: [◀ wide hex btn] [150×150 preview] [▶ wide hex btn]
	var nav_row := HBoxContainer.new()
	nav_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	nav_row.add_theme_constant_override("separation", 8)
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_col.add_child(nav_row)

	var prev_btn := _make_hex_nav_btn("◀", true)
	prev_btn.pressed.connect(_on_preview_prev)
	nav_row.add_child(prev_btn)

	var preview_wrap := Control.new()
	preview_wrap.custom_minimum_size = Vector2(150, 150)
	nav_row.add_child(preview_wrap)

	_preview_drone_rect = TextureRect.new()
	_preview_drone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_drone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_drone_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	preview_wrap.add_child(_preview_drone_rect)

	_preview_blade_rect = TextureRect.new()
	_preview_blade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_blade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_blade_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	preview_wrap.add_child(_preview_blade_rect)

	var next_btn := _make_hex_nav_btn("▶", false)
	next_btn.pressed.connect(_on_preview_next)
	nav_row.add_child(next_btn)

	## Column 3 — labelled colour pickers (far right). EXPAND_FILL balances the
	## presets column so the SHRINK_CENTER preview column stays centred.
	var picker_col := VBoxContainer.new()
	picker_col.add_theme_constant_override("separation", 10)
	picker_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_col.alignment = BoxContainer.ALIGNMENT_CENTER
	colors_top.add_child(picker_col)

	_pick_p1_drone = _picker_only(picker_col, GameManager.p1_color,       _on_p1_drone_changed, _on_reset_p1_drone, "Player 1  Drone :")
	_pick_p1_blade = _picker_only(picker_col, GameManager.p1_blade_color, _on_p1_blade_changed, _on_reset_p1_blade, "Player 1  Blade  :")
	_spacer(picker_col, 6)
	_pick_p2_drone = _picker_only(picker_col, GameManager.p2_color,       _on_p2_drone_changed, _on_reset_p2_drone, "Player 2  Drone :")
	_pick_p2_blade = _picker_only(picker_col, GameManager.p2_blade_color, _on_p2_blade_changed, _on_reset_p2_blade, "Player 2  Blade  :")

	_refresh_preview()

	## ── Board tile colours (centre column, below the preview) ──────────────
	var tiles_row := HBoxContainer.new()
	tiles_row.add_theme_constant_override("separation", 14)
	tiles_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tiles_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_col.add_child(tiles_row)

	var tiles_caption := Label.new()
	tiles_caption.text = "Board Tiles:"
	tiles_caption.add_theme_font_size_override("font_size", 12)
	tiles_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tiles_row.add_child(tiles_caption)

	for grp in [["black", "Black"], ["gray", "Gray"], ["white", "White"]]:
		var hb := TextureButton.new()
		hb.texture_normal = _BOARD_HEX_TEX
		hb.ignore_texture_size = true
		hb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		hb.custom_minimum_size = Vector2(40, 40)
		hb.tooltip_text = grp[1] + " tiles"
		hb.self_modulate = GameManager.board_tile_color(grp[0])
		hb.pressed.connect(_on_board_tile_hex_pressed.bind(grp[0], hb))
		tiles_row.add_child(hb)

	## Save as Preset + label (centre column)
	var save_btn := Button.new()
	save_btn.text = "Save as Preset"
	save_btn.custom_minimum_size = Vector2(200, 36)
	save_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	save_btn.pressed.connect(_on_save_preset)
	preview_col.add_child(save_btn)

	var div := Label.new()
	div.text = "── Saved Presets ──"
	div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	div.add_theme_font_size_override("font_size", 13)
	preview_col.add_child(div)

	## Bottom spacer: shrinks colors_top from the bottom so its centred content
	## sits ~35px higher (half the spacer height).
	_spacer(_drones_colors_container, 70)

	## ── SOUNDS container ────────────────────────────────────────────────────
	_drones_sounds_container = VBoxContainer.new()
	_drones_sounds_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_sounds_container.add_theme_constant_override("separation", 6)
	_drones_sounds_container.visible = false
	root.add_child(_drones_sounds_container)

	var outer_scroll := ScrollContainer.new()
	outer_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	outer_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drones_sounds_container.add_child(outer_scroll)
	_widen_scrollbar(outer_scroll)

	var sound_root := VBoxContainer.new()
	sound_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_root.add_theme_constant_override("separation", 8)
	outer_scroll.add_child(sound_root)

	## Helper: build one sound-type section
	var _build_sound_section = func(parent: VBoxContainer, header: String, player: int, sound_type: String) -> Array:
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 3)
		list.visible = false   ## collapsed by default

		var toggle_btn := Button.new()
		toggle_btn.text = "▶  " + header
		toggle_btn.add_theme_font_size_override("font_size", 14)
		toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle_btn.pressed.connect(func():
			list.visible = not list.visible
			toggle_btn.text = ("▼  " if list.visible else "▶  ") + header
		)
		parent.add_child(toggle_btn)
		parent.add_child(list)

		var rows: Array = []
		for i in range(SoundManager.sound_count()):
			rows.append(_sound_row_typed(list, i, player, sound_type))
		return rows

	## ── Player 1 ──
	var p1_div := Label.new()
	p1_div.text = "━━━  Player 1  ━━━"
	p1_div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p1_div.add_theme_font_size_override("font_size", 15)
	sound_root.add_child(p1_div)

	_sound_rows_p1         = _build_sound_section.call(sound_root, "Move Sound",     1, "move")
	_sound_rows_p1_rotate  = _build_sound_section.call(sound_root, "Rotation Sound", 1, "rotate")
	_sound_rows_p1_destroy = _build_sound_section.call(sound_root, "Destroy Sound",  1, "destroy")
	_sound_rows_p1_turn    = _build_sound_section.call(sound_root, "Turn Sound",     1, "turn")

	## ── Player 2 ──
	var p2_div := Label.new()
	p2_div.text = "━━━  Player 2  ━━━"
	p2_div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2_div.add_theme_font_size_override("font_size", 15)
	sound_root.add_child(p2_div)

	_sound_rows_p2         = _build_sound_section.call(sound_root, "Move Sound",     2, "move")
	_sound_rows_p2_rotate  = _build_sound_section.call(sound_root, "Rotation Sound", 2, "rotate")
	_sound_rows_p2_destroy = _build_sound_section.call(sound_root, "Destroy Sound",  2, "destroy")
	_sound_rows_p2_turn    = _build_sound_section.call(sound_root, "Turn Sound",     2, "turn")

	_refresh_all_sound_highlights()

	## ── BACKGROUNDS container ───────────────────────────────────────────────
	_drones_backgrounds_container = VBoxContainer.new()
	_drones_backgrounds_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_backgrounds_container.add_theme_constant_override("separation", 8)
	_drones_backgrounds_container.visible = false
	root.add_child(_drones_backgrounds_container)

	var bg_hint := Label.new()
	bg_hint.text = "Animated background behind the board (looping)."
	bg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	bg_hint.add_theme_font_size_override("font_size", 13)
	_drones_backgrounds_container.add_child(bg_hint)

	var bg_scroll := ScrollContainer.new()
	bg_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	bg_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drones_backgrounds_container.add_child(bg_scroll)
	_widen_scrollbar(bg_scroll)

	var bg_list := VBoxContainer.new()
	bg_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_list.add_theme_constant_override("separation", 6)
	bg_scroll.add_child(bg_list)
	_background_list_vbox = bg_list
	_rebuild_background_list(bg_list)

	## ── DRONES container ────────────────────────────────────────────────────
	_drones_blades_container = VBoxContainer.new()
	_drones_blades_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_blades_container.add_theme_constant_override("separation", 8)
	_drones_blades_container.visible = false
	root.add_child(_drones_blades_container)

	var drones_row := HBoxContainer.new()
	drones_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drones_row.add_theme_constant_override("separation", 16)
	_drones_blades_container.add_child(drones_row)

	## ── LEFT COLUMN: Player 1 ──────────────────────────────────────────────
	var drones_left := VBoxContainer.new()
	drones_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drones_left.add_theme_constant_override("separation", 8)
	drones_row.add_child(drones_left)

	var p1_title_lbl := Label.new()
	p1_title_lbl.text = "Player 1 Drone:"
	p1_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p1_title_lbl.add_theme_font_size_override("font_size", 14)
	drones_left.add_child(p1_title_lbl)

	var p1_body_sub_lbl := Label.new()
	p1_body_sub_lbl.text = "Drone Body:"
	p1_body_sub_lbl.add_theme_font_size_override("font_size", 12)
	drones_left.add_child(p1_body_sub_lbl)

	_p1_body_option = OptionButton.new()
	_p1_body_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p1_body_option.add_theme_font_size_override("font_size", 13)
	_populate_option_locked(_p1_body_option, GameManager.DRONE_BODY_NAMES, GameManager.DRONE_BODY_FOLDERS, "drone_body")
	_p1_body_option.select(maxi(GameManager.DRONE_BODY_FOLDERS.find(GameManager.p1_drone_body), 0))
	_p1_body_option.item_selected.connect(_on_p1_body_option_selected)
	drones_left.add_child(_p1_body_option)

	var p1_blade_sub_lbl := Label.new()
	p1_blade_sub_lbl.text = "Drone Blades:"
	p1_blade_sub_lbl.add_theme_font_size_override("font_size", 12)
	drones_left.add_child(p1_blade_sub_lbl)

	_p1_blades_option = OptionButton.new()
	_p1_blades_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p1_blades_option.add_theme_font_size_override("font_size", 13)
	_populate_option_locked(_p1_blades_option, _DRONES_BLADE_NAMES, _DRONES_BLADE_VARIANTS, "blade")
	_p1_blades_option.select(maxi(_DRONES_BLADE_VARIANTS.find(GameManager.p1_blade_variant), 0))
	_p1_blades_option.item_selected.connect(_on_p1_blades_option_selected)
	drones_left.add_child(_p1_blades_option)

	var left_spacer := Control.new()
	left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drones_left.add_child(left_spacer)

	## ── CENTER COLUMN ──────────────────────────────────────────────────────
	var drones_center := VBoxContainer.new()
	drones_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drones_center.add_theme_constant_override("separation", 10)
	drones_row.add_child(drones_center)

	## Nav row: [← Blades X/8 →] [Hex] [← Drones X/12 →]
	var drones_nav_hbox := HBoxContainer.new()
	drones_nav_hbox.add_theme_constant_override("separation", 8)
	drones_nav_hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drones_center.add_child(drones_nav_hbox)

	## Blade navigator (left of hex)
	var blade_nav_vbox := VBoxContainer.new()
	blade_nav_vbox.add_theme_constant_override("separation", 4)
	blade_nav_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drones_nav_hbox.add_child(blade_nav_vbox)

	var blade_arrows_hbox := HBoxContainer.new()
	blade_arrows_hbox.add_theme_constant_override("separation", 4)
	blade_nav_vbox.add_child(blade_arrows_hbox)

	var blade_prev_btn := Button.new()
	blade_prev_btn.text = "◀"
	blade_prev_btn.custom_minimum_size = Vector2(30, 30)
	blade_prev_btn.pressed.connect(_on_drones_prev_blade)
	blade_arrows_hbox.add_child(blade_prev_btn)

	_drones_blade_label = Label.new()
	_drones_blade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drones_blade_label.add_theme_font_size_override("font_size", 11)
	_drones_blade_label.custom_minimum_size = Vector2(80, 0)
	blade_arrows_hbox.add_child(_drones_blade_label)

	var blade_next_btn := Button.new()
	blade_next_btn.text = "▶"
	blade_next_btn.custom_minimum_size = Vector2(30, 30)
	blade_next_btn.pressed.connect(_on_drones_next_blade)
	blade_arrows_hbox.add_child(blade_next_btn)

	## P1/P2 toggle hex button
	_drones_tab_player = 1
	var drones_hex_btn := _make_drones_toggle_btn()
	drones_hex_btn.pressed.connect(_on_drones_toggle_player)
	drones_nav_hbox.add_child(drones_hex_btn)

	## Body navigator (right of hex)
	var body_nav_vbox := VBoxContainer.new()
	body_nav_vbox.add_theme_constant_override("separation", 4)
	body_nav_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drones_nav_hbox.add_child(body_nav_vbox)

	var body_arrows_hbox := HBoxContainer.new()
	body_arrows_hbox.add_theme_constant_override("separation", 4)
	body_nav_vbox.add_child(body_arrows_hbox)

	var body_prev_btn := Button.new()
	body_prev_btn.text = "◀"
	body_prev_btn.custom_minimum_size = Vector2(30, 30)
	body_prev_btn.pressed.connect(_on_drones_prev_body)
	body_arrows_hbox.add_child(body_prev_btn)

	_drones_body_label = Label.new()
	_drones_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drones_body_label.add_theme_font_size_override("font_size", 11)
	_drones_body_label.custom_minimum_size = Vector2(90, 0)
	body_arrows_hbox.add_child(_drones_body_label)

	var body_next_btn := Button.new()
	body_next_btn.text = "▶"
	body_next_btn.custom_minimum_size = Vector2(30, 30)
	body_next_btn.pressed.connect(_on_drones_next_body)
	body_arrows_hbox.add_child(body_next_btn)

	## Drone preview (body + blade stacked)
	var drones_prev_wrap := Control.new()
	drones_prev_wrap.custom_minimum_size = Vector2(120, 120)
	drones_prev_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drones_prev_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drones_center.add_child(drones_prev_wrap)

	_drones_preview_drone_rect = TextureRect.new()
	_drones_preview_drone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drones_preview_drone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drones_preview_drone_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_drones_preview_drone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drones_prev_wrap.add_child(_drones_preview_drone_rect)

	_drones_preview_blade_rect = TextureRect.new()
	_drones_preview_blade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drones_preview_blade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drones_preview_blade_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_drones_preview_blade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drones_prev_wrap.add_child(_drones_preview_blade_rect)

	## ── RIGHT COLUMN: Player 2 ─────────────────────────────────────────────
	var drones_right := VBoxContainer.new()
	drones_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drones_right.add_theme_constant_override("separation", 8)
	drones_row.add_child(drones_right)

	var p2_title_lbl := Label.new()
	p2_title_lbl.text = "Player 2 Drone:"
	p2_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2_title_lbl.add_theme_font_size_override("font_size", 14)
	drones_right.add_child(p2_title_lbl)

	var p2_body_sub_lbl := Label.new()
	p2_body_sub_lbl.text = "Drone Body:"
	p2_body_sub_lbl.add_theme_font_size_override("font_size", 12)
	drones_right.add_child(p2_body_sub_lbl)

	_p2_body_option = OptionButton.new()
	_p2_body_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p2_body_option.add_theme_font_size_override("font_size", 13)
	_populate_option_locked(_p2_body_option, GameManager.DRONE_BODY_NAMES, GameManager.DRONE_BODY_FOLDERS, "drone_body")
	_p2_body_option.select(maxi(GameManager.DRONE_BODY_FOLDERS.find(GameManager.p2_drone_body), 0))
	_p2_body_option.item_selected.connect(_on_p2_body_option_selected)
	drones_right.add_child(_p2_body_option)

	var p2_blade_sub_lbl := Label.new()
	p2_blade_sub_lbl.text = "Drone Blades:"
	p2_blade_sub_lbl.add_theme_font_size_override("font_size", 12)
	drones_right.add_child(p2_blade_sub_lbl)

	_p2_blades_option = OptionButton.new()
	_p2_blades_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p2_blades_option.add_theme_font_size_override("font_size", 13)
	_populate_option_locked(_p2_blades_option, _DRONES_BLADE_NAMES, _DRONES_BLADE_VARIANTS, "blade")
	_p2_blades_option.select(maxi(_DRONES_BLADE_VARIANTS.find(GameManager.p2_blade_variant), 0))
	_p2_blades_option.item_selected.connect(_on_p2_blades_option_selected)
	drones_right.add_child(_p2_blades_option)

	var right_spacer := Control.new()
	right_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drones_right.add_child(right_spacer)

	_refresh_drones_preview()

	## ── Save / load full drone presets ─────────────────────────────────────
	var save_drone_row := HBoxContainer.new()
	save_drone_row.add_theme_constant_override("separation", 10)
	save_drone_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drones_blades_container.add_child(save_drone_row)

	var save_p1_btn := Button.new()
	save_p1_btn.text = "Save Drone Data For Player 1"
	save_p1_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_p1_btn.add_theme_font_size_override("font_size", 13)
	save_p1_btn.pressed.connect(_on_save_drone.bind(1))
	save_drone_row.add_child(save_p1_btn)

	var save_p2_btn := Button.new()
	save_p2_btn.text = "Save Drone Data For Player 2"
	save_p2_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_p2_btn.add_theme_font_size_override("font_size", 13)
	save_p2_btn.pressed.connect(_on_save_drone.bind(2))
	save_drone_row.add_child(save_p2_btn)

	var saved_lbl := Label.new()
	saved_lbl.text = "Saved Drones:"
	saved_lbl.add_theme_font_size_override("font_size", 12)
	_drones_blades_container.add_child(saved_lbl)

	var saved_scroll := ScrollContainer.new()
	saved_scroll.custom_minimum_size = Vector2(0, 120)
	saved_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drones_blades_container.add_child(saved_scroll)
	_widen_scrollbar(saved_scroll)

	_saved_drones_list = VBoxContainer.new()
	_saved_drones_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved_scroll.add_child(_saved_drones_list)
	_rebuild_saved_drones_list()

	## ── GLOW container ──────────────────────────────────────────────────────────
	_drones_glow_container = VBoxContainer.new()
	_drones_glow_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_glow_container.add_theme_constant_override("separation", 8)
	_drones_glow_container.visible = false
	root.add_child(_drones_glow_container)

	## Top: 4-column layout (labels | preview | inner pickers | outer pickers)
	var glow_top := HBoxContainer.new()
	glow_top.add_theme_constant_override("separation", 10)
	glow_top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_drones_glow_container.add_child(glow_top)

	## Col 1 — row labels with per-player gradient toggles
	var glow_lbl_col := VBoxContainer.new()
	glow_lbl_col.add_theme_constant_override("separation", 0)
	glow_lbl_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	glow_top.add_child(glow_lbl_col)

	var p1_gr_row := HBoxContainer.new()
	p1_gr_row.add_theme_constant_override("separation", 6)
	p1_gr_row.custom_minimum_size = Vector2(0, 34)
	glow_lbl_col.add_child(p1_gr_row)
	var p1_gr_lbl := Label.new(); p1_gr_lbl.text = "Gradient"
	p1_gr_lbl.add_theme_font_size_override("font_size", 14)
	p1_gr_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p1_gr_row.add_child(p1_gr_lbl)
	_glow_p1_grad_toggle = CheckButton.new()
	_glow_p1_grad_toggle.text = "Enable"
	_glow_p1_grad_toggle.button_pressed = GameManager.p1_gradient_enabled
	_glow_p1_grad_toggle.toggled.connect(func(on): _on_glow_gradient_toggled(1, on))
	p1_gr_row.add_child(_glow_p1_grad_toggle)

	for txt in ["Player 1  Selected :", "Player 1  Move :", "Player 1  Capture :"]:
		var l := Label.new(); l.text = txt
		l.add_theme_font_size_override("font_size", 14)
		l.custom_minimum_size = Vector2(168, 34); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glow_lbl_col.add_child(l)

	var p2_gr_row := HBoxContainer.new()
	p2_gr_row.add_theme_constant_override("separation", 6)
	p2_gr_row.custom_minimum_size = Vector2(0, 34)
	glow_lbl_col.add_child(p2_gr_row)
	var p2_gr_lbl := Label.new(); p2_gr_lbl.text = "Gradient"
	p2_gr_lbl.add_theme_font_size_override("font_size", 14)
	p2_gr_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p2_gr_row.add_child(p2_gr_lbl)
	_glow_p2_grad_toggle = CheckButton.new()
	_glow_p2_grad_toggle.text = "Enable"
	_glow_p2_grad_toggle.button_pressed = GameManager.p2_gradient_enabled
	_glow_p2_grad_toggle.toggled.connect(func(on): _on_glow_gradient_toggled(2, on))
	p2_gr_row.add_child(_glow_p2_grad_toggle)

	for txt in ["Player 2  Selected :", "Player 2  Move :", "Player 2  Capture :"]:
		var l := Label.new(); l.text = txt
		l.add_theme_font_size_override("font_size", 14)
		l.custom_minimum_size = Vector2(168, 34); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glow_lbl_col.add_child(l)

	## Col 2 — drone preview (expands)
	var glow_preview_col := VBoxContainer.new()
	glow_preview_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glow_preview_col.alignment = BoxContainer.ALIGNMENT_CENTER
	glow_preview_col.add_theme_constant_override("separation", 4)
	glow_top.add_child(glow_preview_col)

	var glow_top_row := HBoxContainer.new()
	glow_top_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glow_top_row.add_theme_constant_override("separation", 8)
	glow_preview_col.add_child(glow_top_row)
	_glow_preview_tile_label = Label.new()
	_glow_preview_tile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glow_preview_tile_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_glow_preview_tile_label.add_theme_font_size_override("font_size", 13)
	_glow_preview_tile_label.add_theme_color_override("font_color", Color(0.75, 0.82, 1.0))
	glow_top_row.add_child(_glow_preview_tile_label)
	var glow_toggle_btn := _make_glow_toggle_btn()
	glow_toggle_btn.pressed.connect(_on_glow_toggle_player)
	glow_top_row.add_child(glow_toggle_btn)

	var glow_nav_row := HBoxContainer.new()
	glow_nav_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glow_nav_row.add_theme_constant_override("separation", 8)
	glow_nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	glow_preview_col.add_child(glow_nav_row)
	var glow_prev_btn := _make_hex_nav_btn("◀", true)
	glow_prev_btn.pressed.connect(_on_glow_preview_prev)
	glow_nav_row.add_child(glow_prev_btn)

	var glow_preview_wrap := Control.new()
	glow_preview_wrap.custom_minimum_size = Vector2(150, 150)
	glow_nav_row.add_child(glow_preview_wrap)
	_glow_preview_drone_rect = TextureRect.new()
	_glow_preview_drone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_preview_drone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glow_preview_drone_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	glow_preview_wrap.add_child(_glow_preview_drone_rect)
	_glow_preview_blade_rect = TextureRect.new()
	_glow_preview_blade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_preview_blade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glow_preview_blade_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	glow_preview_wrap.add_child(_glow_preview_blade_rect)

	var glow_next_btn := _make_hex_nav_btn("▶", false)
	glow_next_btn.pressed.connect(_on_glow_preview_next)
	glow_nav_row.add_child(glow_next_btn)

	## Col 3 — Inner pickers (header + 6 rows with spacer between P1/P2)
	var inner_col := VBoxContainer.new()
	inner_col.add_theme_constant_override("separation", 0)
	inner_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	glow_top.add_child(inner_col)
	var in_hdr := Label.new(); in_hdr.text = "Inner"
	in_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	in_hdr.add_theme_font_size_override("font_size", 14)
	in_hdr.custom_minimum_size = Vector2(70, 34)
	inner_col.add_child(in_hdr)

	## Col 4 — Outer pickers
	var outer_col := VBoxContainer.new()
	outer_col.add_theme_constant_override("separation", 0)
	outer_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	glow_top.add_child(outer_col)
	var out_hdr := Label.new(); out_hdr.text = "Outer"
	out_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	out_hdr.add_theme_font_size_override("font_size", 14)
	out_hdr.custom_minimum_size = Vector2(70, 34)
	outer_col.add_child(out_hdr)

	## Build 6 inner/outer picker pairs (P1 sel/mov/cap, spacer row, P2 sel/mov/cap)
	_glow_inner_picks.clear(); _glow_outer_picks.clear()
	var gm_inner := [
		GameManager.p1_glow_selected_inner, GameManager.p1_glow_move_inner, GameManager.p1_glow_capture_inner,
		GameManager.p2_glow_selected_inner, GameManager.p2_glow_move_inner, GameManager.p2_glow_capture_inner]
	var gm_outer := [
		GameManager.p1_glow_selected_outer, GameManager.p1_glow_move_outer, GameManager.p1_glow_capture_outer,
		GameManager.p2_glow_selected_outer, GameManager.p2_glow_move_outer, GameManager.p2_glow_capture_outer]
	var row_types := ["selected","move","capture","selected","move","capture"]
	var row_players := [1,1,1,2,2,2]
	for i in 6:
		if i == 3:   ## spacer before P2 (matches the gradient-toggle row height)
			var sp_in := Control.new(); sp_in.custom_minimum_size = Vector2(0, 34); inner_col.add_child(sp_in)
			var sp_out := Control.new(); sp_out.custom_minimum_size = Vector2(0, 34); outer_col.add_child(sp_out)
		var ip := ColorPickerButton.new()
		ip.color = gm_inner[i]; ip.custom_minimum_size = Vector2(64, 34)
		var rt_i: String = row_types[i]; var rp_i: int = row_players[i]; var ii: int = i
		ip.pressed.connect(func(): _glow_active_type = rt_i; _glow_preview_player = rp_i; _refresh_glow_preview())
		ip.color_changed.connect(func(c: Color): _on_glow_inner_changed(rp_i, rt_i, ii, c))
		inner_col.add_child(ip); _glow_inner_picks.append(ip)

		var op := ColorPickerButton.new()
		op.color = gm_outer[i]; op.custom_minimum_size = Vector2(64, 34)
		op.pressed.connect(func(): _glow_active_type = rt_i; _glow_preview_player = rp_i; _refresh_glow_preview())
		op.color_changed.connect(func(c: Color): _on_glow_outer_changed(rp_i, rt_i, ii, c))
		outer_col.add_child(op); _glow_outer_picks.append(op)

	_refresh_glow_preview()

	## ── Bottom: opacity, effect buttons, animated preview ring ─────────────────
	_drones_glow_container.add_child(HSeparator.new())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	_drones_glow_container.add_child(bottom)

	## Left: controls
	var ctrl_col := VBoxContainer.new()
	ctrl_col.add_theme_constant_override("separation", 8)
	ctrl_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(ctrl_col)

	var op_row := HBoxContainer.new(); op_row.add_theme_constant_override("separation", 8)
	ctrl_col.add_child(op_row)
	var op_lbl := Label.new(); op_lbl.text = "Opacity"
	op_lbl.custom_minimum_size = Vector2(64, 0); op_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	op_lbl.add_theme_font_size_override("font_size", 13); op_row.add_child(op_lbl)
	_glow_opacity_slider = HSlider.new()
	_glow_opacity_slider.min_value = 0.0; _glow_opacity_slider.max_value = 1.0
	_glow_opacity_slider.step = 0.01; _glow_opacity_slider.value = GameManager.glow_opacity
	_glow_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_glow_opacity_slider.value_changed.connect(_on_glow_opacity_changed)
	op_row.add_child(_glow_opacity_slider)

	var sp_row := HBoxContainer.new(); sp_row.add_theme_constant_override("separation", 8)
	ctrl_col.add_child(sp_row)
	var sp_lbl := Label.new(); sp_lbl.text = "Speed"
	sp_lbl.custom_minimum_size = Vector2(64, 0); sp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sp_lbl.add_theme_font_size_override("font_size", 13); sp_row.add_child(sp_lbl)
	_glow_speed_slider = HSlider.new()
	_glow_speed_slider.min_value = 0.1; _glow_speed_slider.max_value = 5.0
	_glow_speed_slider.step = 0.05; _glow_speed_slider.value = GameManager.glow_speed
	_glow_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_glow_speed_slider.value_changed.connect(_on_glow_speed_changed)
	sp_row.add_child(_glow_speed_slider)

	var eff_row := HBoxContainer.new(); eff_row.add_theme_constant_override("separation", 8)
	ctrl_col.add_child(eff_row)
	var eff_lbl := Label.new(); eff_lbl.text = "Effect"
	eff_lbl.custom_minimum_size = Vector2(64, 0); eff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eff_lbl.add_theme_font_size_override("font_size", 13); eff_row.add_child(eff_lbl)
	var eff_flow := HFlowContainer.new()
	eff_flow.add_theme_constant_override("h_separation", 6)
	eff_flow.add_theme_constant_override("v_separation", 6)
	eff_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eff_row.add_child(eff_flow)
	var eff_group := ButtonGroup.new()
	for pair in _GLOW_EFFECTS:
		var eid: String = pair[0]; var edsp: String = pair[1]
		var locked: bool = not AchievementManager.is_asset_unlocked("glow_effect", eid)
		var btn := Button.new(); btn.text = edsp + (" (Locked)" if locked else ""); btn.toggle_mode = true
		btn.disabled = locked
		btn.button_group = eff_group; btn.button_pressed = (GameManager.glow_effect == eid)
		_glow_effect_btns[eid] = btn
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_glow_effect_selected.bind(eid))
		eff_flow.add_child(btn)

	## Right: animated hex ring preview
	var ring_script := load("res://scripts/HexGlowRing.gd")
	_glow_preview_ring = ring_script.new() as Control
	_glow_preview_ring.custom_minimum_size = Vector2(130, 130)
	_glow_preview_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_glow_preview_ring)
	_refresh_glow_preview()

	var apply_btn := Button.new()
	apply_btn.text = "Apply Glow Settings"
	apply_btn.add_theme_font_size_override("font_size", 14)
	apply_btn.pressed.connect(_apply_all_glow_settings)
	ctrl_col.add_child(apply_btn)

	## ── SCREEN container ───────────────────────────────────────────────────────
	_drones_screen_container = VBoxContainer.new()
	_drones_screen_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_screen_container.add_theme_constant_override("separation", 6)
	_drones_screen_container.visible = false
	root.add_child(_drones_screen_container)

	_spacer(_drones_screen_container, 8)

	var screen_title := Label.new()
	screen_title.text = "CAPTURE SCREEN EFFECT"
	screen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_title.add_theme_font_size_override("font_size", 17)
	_drones_screen_container.add_child(screen_title)

	var screen_sub := Label.new()
	screen_sub.text = "Plays on the camera after each piece capture"
	screen_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_sub.add_theme_font_size_override("font_size", 12)
	screen_sub.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	_drones_screen_container.add_child(screen_sub)

	_spacer(_drones_screen_container, 4)

	var screen_player_row := HBoxContainer.new()
	screen_player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	screen_player_row.add_theme_constant_override("separation", 6)
	_drones_screen_container.add_child(screen_player_row)

	_screen_p1_btn = Button.new()
	_screen_p1_btn.text = "Player 1"
	_screen_p1_btn.custom_minimum_size = Vector2(100, 34)
	_screen_p1_btn.add_theme_font_size_override("font_size", 14)
	_screen_p1_btn.pressed.connect(_on_screen_player_select.bind(1))
	screen_player_row.add_child(_screen_p1_btn)

	_screen_p2_btn = Button.new()
	_screen_p2_btn.text = "Player 2"
	_screen_p2_btn.custom_minimum_size = Vector2(100, 34)
	_screen_p2_btn.add_theme_font_size_override("font_size", 14)
	_screen_p2_btn.pressed.connect(_on_screen_player_select.bind(2))
	screen_player_row.add_child(_screen_p2_btn)

	_spacer(_drones_screen_container, 4)

	var screen_scroll := ScrollContainer.new()
	screen_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_screen_container.add_child(screen_scroll)
	_widen_scrollbar(screen_scroll)

	var screen_list := VBoxContainer.new()
	screen_list.add_theme_constant_override("separation", 4)
	screen_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_scroll.add_child(screen_list)

	_screen_effect_btns.clear()
	for ef in SCREEN_EFFECTS:
		var ef_id:   int    = ef[0]
		var ef_name: String = ef[1]
		var ef_dur:  String = ef[2]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		screen_list.add_child(row)

		var fx_btn := Button.new()
		fx_btn.text = ef_name + (" (Locked)" if not AchievementManager.is_asset_unlocked("screen_fx", ef_id) else "")
		fx_btn.disabled = not AchievementManager.is_asset_unlocked("screen_fx", ef_id)
		fx_btn.custom_minimum_size = Vector2(260, 40)
		fx_btn.add_theme_font_size_override("font_size", 14)
		fx_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		fx_btn.pressed.connect(_on_screen_effect_selected.bind(ef_id))
		row.add_child(fx_btn)
		_screen_effect_btns[ef_id] = fx_btn

		if ef_dur != "":
			var dur_lbl := Label.new()
			dur_lbl.text = ef_dur
			dur_lbl.add_theme_font_size_override("font_size", 12)
			dur_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
			dur_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dur_lbl.custom_minimum_size = Vector2(36, 40)
			row.add_child(dur_lbl)

	_refresh_screen_effect_btns()

	## ── DRIVE container ────────────────────────────────────────────────────────
	_drones_drive_container = VBoxContainer.new()
	_drones_drive_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_drive_container.add_theme_constant_override("separation", 8)
	_drones_drive_container.visible = false
	root.add_child(_drones_drive_container)

	var drive_title := Label.new()
	drive_title.text = "TILE MOVE ANIMATION"
	drive_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drive_title.add_theme_font_size_override("font_size", 17)
	_drones_drive_container.add_child(drive_title)

	var drive_sub := Label.new()
	drive_sub.text = "Plays when a piece moves to a new tile"
	drive_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drive_sub.add_theme_font_size_override("font_size", 12)
	drive_sub.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	_drones_drive_container.add_child(drive_sub)

	_spacer(_drones_drive_container, 6)

	## Body: left (speed + effect list) | right (preview)
	var drive_body := HBoxContainer.new()
	drive_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drive_body.add_theme_constant_override("separation", 12)
	_drones_drive_container.add_child(drive_body)

	## ── Left column ──────────────────────────────────────────────────────────
	var drive_left := VBoxContainer.new()
	drive_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drive_left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	drive_left.add_theme_constant_override("separation", 6)
	drive_body.add_child(drive_left)

	## Speed slider row
	## Two independent speed sliders: Drive Speed (ordinary moves) and Destroy
	## Speed (the capturing move).
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 10)
	speed_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drive_left.add_child(speed_row)

	var speed_lbl := Label.new()
	speed_lbl.text = "Drive Speed"
	speed_lbl.add_theme_font_size_override("font_size", 14)
	speed_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_lbl.custom_minimum_size = Vector2(96, 28)
	speed_row.add_child(speed_lbl)

	_drive_speed_slider = HSlider.new()
	_drive_speed_slider.min_value = 0.0
	_drive_speed_slider.max_value = 1.0
	_drive_speed_slider.step = 0.01
	_drive_speed_slider.value = GameManager.p1_drive_anim_speed
	_drive_speed_slider.custom_minimum_size = Vector2(160, 28)
	speed_row.add_child(_drive_speed_slider)

	_drive_speed_label = Label.new()
	_drive_speed_label.text = "%.2fs" % GameManager.p1_drive_anim_speed
	_drive_speed_label.add_theme_font_size_override("font_size", 13)
	_drive_speed_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	_drive_speed_label.custom_minimum_size = Vector2(44, 28)
	_drive_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_row.add_child(_drive_speed_label)

	_drive_speed_slider.value_changed.connect(_on_drive_speed_changed)

	var dspeed_row := HBoxContainer.new()
	dspeed_row.add_theme_constant_override("separation", 10)
	dspeed_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drive_left.add_child(dspeed_row)

	var dspeed_lbl := Label.new()
	dspeed_lbl.text = "Destroy Speed"
	dspeed_lbl.add_theme_font_size_override("font_size", 14)
	dspeed_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dspeed_lbl.custom_minimum_size = Vector2(96, 28)
	dspeed_row.add_child(dspeed_lbl)

	_destroy_speed_slider = HSlider.new()
	_destroy_speed_slider.min_value = 0.0
	_destroy_speed_slider.max_value = 1.0
	_destroy_speed_slider.step = 0.01
	_destroy_speed_slider.value = GameManager.p1_destroy_drive_anim_speed
	_destroy_speed_slider.custom_minimum_size = Vector2(160, 28)
	dspeed_row.add_child(_destroy_speed_slider)

	_destroy_speed_label = Label.new()
	_destroy_speed_label.text = "%.2fs" % GameManager.p1_destroy_drive_anim_speed
	_destroy_speed_label.add_theme_font_size_override("font_size", 13)
	_destroy_speed_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	_destroy_speed_label.custom_minimum_size = Vector2(44, 28)
	_destroy_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dspeed_row.add_child(_destroy_speed_label)

	_destroy_speed_slider.value_changed.connect(_on_destroy_drive_speed_changed)

	## Mode selector: Drive | Destroy Drive
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	drive_left.add_child(mode_row)

	_drive_mode_btns.clear()
	for mi in 2:
		var mb := Button.new()
		mb.text = "Drive" if mi == 0 else "Destroy Drive"
		mb.custom_minimum_size = Vector2(130, 34)
		mb.add_theme_font_size_override("font_size", 13)
		mb.pressed.connect(_on_drive_mode_selected.bind(mi))
		mode_row.add_child(mb)
		_drive_mode_btns.append(mb)

	## Single scrollable effect list — highlights whichever mode is active
	var drive_scroll := ScrollContainer.new()
	drive_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drive_left.add_child(drive_scroll)
	_widen_scrollbar(drive_scroll)

	var drive_list := VBoxContainer.new()
	drive_list.add_theme_constant_override("separation", 4)
	drive_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drive_scroll.add_child(drive_list)

	_drive_effect_btns.clear()
	for ef in DRIVE_EFFECTS:
		var ef_id:   int    = ef[0]
		var ef_name: String = ef[1]
		var ef_desc: String = ef[2]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		drive_list.add_child(row)
		var ef_btn := Button.new()
		ef_btn.text = ef_name + (" (Locked)" if not AchievementManager.is_asset_unlocked("drive_fx", ef_id) else "")
		ef_btn.disabled = not AchievementManager.is_asset_unlocked("drive_fx", ef_id)
		ef_btn.custom_minimum_size = Vector2(90, 42)
		ef_btn.add_theme_font_size_override("font_size", 14)
		ef_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ef_btn.pressed.connect(_on_drive_effect_selected.bind(ef_id))
		row.add_child(ef_btn)
		_drive_effect_btns[ef_id] = ef_btn
		var desc_lbl := Label.new()
		desc_lbl.text = ef_desc
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc_lbl)

	## ── Right column (preview) ───────────────────────────────────────────────
	var drive_preview_col := VBoxContainer.new()
	drive_preview_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	drive_preview_col.add_theme_constant_override("separation", 8)
	drive_body.add_child(drive_preview_col)

	var drive_toggle_btn := _make_drive_toggle_btn()
	drive_toggle_btn.pressed.connect(_on_drive_toggle_player)
	drive_preview_col.add_child(drive_toggle_btn)

	## Preview stage: 160×80 clipping area with the piece wrap inside
	var drive_stage := Control.new()
	drive_stage.custom_minimum_size = Vector2(160, 80)
	drive_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drive_stage.clip_contents = true
	drive_preview_col.add_child(drive_stage)

	_drive_preview_wrap = Control.new()
	_drive_preview_wrap.custom_minimum_size = Vector2(80, 80)
	_drive_preview_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_drive_preview_wrap.position = Vector2(0.0, 0.0)
	drive_stage.add_child(_drive_preview_wrap)

	_drive_preview_drone_rect = TextureRect.new()
	_drive_preview_drone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drive_preview_drone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drive_preview_drone_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_drive_preview_drone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drive_preview_wrap.add_child(_drive_preview_drone_rect)

	_drive_preview_blade_rect = TextureRect.new()
	_drive_preview_blade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drive_preview_blade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drive_preview_blade_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_drive_preview_blade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drive_preview_wrap.add_child(_drive_preview_blade_rect)

	_refresh_drive_preview()

	var drive_play_btn := Button.new()
	drive_play_btn.text = "Preview ▶"
	drive_play_btn.custom_minimum_size = Vector2(110, 34)
	drive_play_btn.add_theme_font_size_override("font_size", 14)
	drive_play_btn.pressed.connect(_on_drive_preview_play)
	drive_preview_col.add_child(drive_play_btn)

	_refresh_drive_effect_btns()

	## ── DESTROY container ───────────────────────────────────────────────────────
	_drones_destroy_container = VBoxContainer.new()
	_drones_destroy_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_destroy_container.add_theme_constant_override("separation", 8)
	_drones_destroy_container.visible = false
	root.add_child(_drones_destroy_container)

	var destroy_title := Label.new()
	destroy_title.text = "DESTROY ANIMATION"
	destroy_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	destroy_title.add_theme_font_size_override("font_size", 17)
	_drones_destroy_container.add_child(destroy_title)

	var destroy_sub := Label.new()
	destroy_sub.text = "Animation played when a piece is captured"
	destroy_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	destroy_sub.add_theme_font_size_override("font_size", 12)
	destroy_sub.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	_drones_destroy_container.add_child(destroy_sub)

	_spacer(_drones_destroy_container, 6)

	var destroy_body := HBoxContainer.new()
	destroy_body.add_theme_constant_override("separation", 14)
	destroy_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drones_destroy_container.add_child(destroy_body)

	var destroy_scroll := ScrollContainer.new()
	destroy_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	destroy_body.add_child(destroy_scroll)
	_widen_scrollbar(destroy_scroll)

	var destroy_list := VBoxContainer.new()
	destroy_list.add_theme_constant_override("separation", 6)
	destroy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_scroll.add_child(destroy_list)

	_destroy_effect_btns.clear()
	for ef in DESTROY_EFFECTS:
		var ef_id:   int    = ef[0]
		var ef_name: String = ef[1]
		var ef_desc: String = ef[2]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		destroy_list.add_child(row)

		var ef_btn := Button.new()
		ef_btn.text = ef_name + (" (Locked)" if not AchievementManager.is_asset_unlocked("destroy_fx", ef_id) else "")
		ef_btn.disabled = not AchievementManager.is_asset_unlocked("destroy_fx", ef_id)
		ef_btn.custom_minimum_size = Vector2(120, 42)
		ef_btn.add_theme_font_size_override("font_size", 14)
		ef_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ef_btn.pressed.connect(_on_destroy_effect_selected.bind(ef_id))
		row.add_child(ef_btn)
		_destroy_effect_btns[ef_id] = ef_btn

		var desc_lbl := Label.new()
		desc_lbl.text = ef_desc
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc_lbl)

	var destroy_preview_col := VBoxContainer.new()
	destroy_preview_col.add_theme_constant_override("separation", 8)
	destroy_preview_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	destroy_preview_col.alignment = BoxContainer.ALIGNMENT_CENTER
	destroy_body.add_child(destroy_preview_col)

	var prev_top_row := HBoxContainer.new()
	prev_top_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prev_top_row.add_theme_constant_override("separation", 6)
	destroy_preview_col.add_child(prev_top_row)

	var destroy_toggle_btn := _make_destroy_toggle_btn()
	destroy_toggle_btn.pressed.connect(_on_destroy_toggle_player)
	prev_top_row.add_child(destroy_toggle_btn)

	_destroy_preview_wrap = Control.new()
	_destroy_preview_wrap.custom_minimum_size = Vector2(150, 150)
	_destroy_preview_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	destroy_preview_col.add_child(_destroy_preview_wrap)

	_destroy_preview_drone_rect = TextureRect.new()
	_destroy_preview_drone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destroy_preview_drone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_destroy_preview_drone_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_destroy_preview_wrap.add_child(_destroy_preview_drone_rect)

	_destroy_preview_blade_rect = TextureRect.new()
	_destroy_preview_blade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destroy_preview_blade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_destroy_preview_blade_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_destroy_preview_wrap.add_child(_destroy_preview_blade_rect)

	var preview_btn := Button.new()
	preview_btn.text = "Preview  ▶"
	preview_btn.custom_minimum_size = Vector2(130, 38)
	preview_btn.add_theme_font_size_override("font_size", 14)
	preview_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview_btn.pressed.connect(_on_destroy_preview_play)
	destroy_preview_col.add_child(preview_btn)

	_refresh_destroy_effect_btns()
	_refresh_destroy_preview()

	## Wire tab buttons after containers exist
	tab_colors.pressed.connect(_on_drones_tab_colors)
	tab_sounds.pressed.connect(_on_drones_tab_sounds)
	tab_backgrounds.pressed.connect(_on_drones_tab_backgrounds)
	tab_blades.pressed.connect(_on_drones_tab_blades)
	tab_glow.pressed.connect(_on_drones_tab_glow)
	tab_screen.pressed.connect(_on_drones_tab_screen)
	tab_drive.pressed.connect(_on_drones_tab_drive)
	tab_destroy.pressed.connect(_on_drones_tab_destroy)

	return panel

func _sound_row_typed(parent: VBoxContainer, idx: int, player: int, sound_type: String) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var preview_btn := Button.new()
	preview_btn.text = "▶"
	preview_btn.custom_minimum_size = Vector2(32, 28)
	preview_btn.add_theme_font_size_override("font_size", 13)
	preview_btn.pressed.connect(SoundManager.preview_sound.bind(idx))
	row.add_child(preview_btn)

	var select_btn := Button.new()
	select_btn.text = _sound_row_label(idx)
	select_btn.disabled = not AchievementManager.is_asset_unlocked("sound", SoundManager.sound_label(idx))
	select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_btn.custom_minimum_size = Vector2(0, 28)
	select_btn.add_theme_font_size_override("font_size", 13)
	select_btn.pressed.connect(_on_sound_selected.bind(player, sound_type, idx))
	row.add_child(select_btn)
	return select_btn

## A sound's label, suffixed with "(Locked)" if not yet unlocked.
func _sound_row_label(idx: int) -> String:
	var label: String = SoundManager.sound_label(idx)
	if not AchievementManager.is_asset_unlocked("sound", label):
		return label + " (Locked)"
	return label

func _refresh_all_sound_highlights() -> void:
	_refresh_sound_type(1, "move",    _sound_rows_p1)
	_refresh_sound_type(1, "rotate",  _sound_rows_p1_rotate)
	_refresh_sound_type(1, "destroy", _sound_rows_p1_destroy)
	_refresh_sound_type(1, "turn",    _sound_rows_p1_turn)
	_refresh_sound_type(2, "move",    _sound_rows_p2)
	_refresh_sound_type(2, "rotate",  _sound_rows_p2_rotate)
	_refresh_sound_type(2, "destroy", _sound_rows_p2_destroy)
	_refresh_sound_type(2, "turn",    _sound_rows_p2_turn)

func _refresh_sound_type(player: int, sound_type: String, rows: Array) -> void:
	var sel: int = SoundManager.get_selected(player, sound_type)
	for i in range(rows.size()):
		var btn: Button = rows[i]
		btn.text = ("✓  " if i == sel else "") + _sound_row_label(i)
		btn.disabled = not AchievementManager.is_asset_unlocked("sound", SoundManager.sound_label(i))

# -- Color presets ----------------------------------------------------------
func _load_presets() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PRESET_FILE) == OK:
		return cfg.get_value(PRESET_SECTION, "list", [])
	return []

func _save_presets_to_disk(presets: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(PRESET_SECTION, "list", presets)
	cfg.save(PRESET_FILE)

func _rebuild_preset_list() -> void:
	if _preset_list == null: return
	for child in _preset_list.get_children(): child.queue_free()
	var presets: Array = _load_presets()
	if presets.is_empty():
		var el := Label.new(); el.text = "(no saved presets)"
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preset_list.add_child(el); return
	for i in range(presets.size()):
		var e: Array = presets[i]
		if e.size() < 4: continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_swatch(row, e[0], "P1D"); _swatch(row, e[1], "P1B")
		_swatch(row, e[2], "P2D"); _swatch(row, e[3], "P2B")
		var ab := Button.new(); ab.text = "Apply"; ab.custom_minimum_size = Vector2(52,26)
		ab.pressed.connect(_on_apply_preset.bind(i)); row.add_child(ab)
		var db := Button.new(); db.text = "×"; db.custom_minimum_size = Vector2(26,26)
		db.pressed.connect(_on_delete_preset.bind(i)); row.add_child(db)
		_preset_list.add_child(row)

func _swatch(parent: Control, color: Color, label: String) -> void:
	## No label → a single clean colour chip (used by the drone-preset list).
	if label == "":
		var chip := ColorRect.new()
		chip.color = color
		chip.custom_minimum_size = Vector2(22, 22)
		parent.add_child(chip)
		return
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var rect := ColorRect.new(); rect.color = color; rect.custom_minimum_size = Vector2(18,18)
	box.add_child(rect)
	var lbl := Label.new(); lbl.text = label; lbl.add_theme_font_size_override("font_size", 10)
	box.add_child(lbl)
	parent.add_child(box)

# -- Color callbacks --------------------------------------------------------
func _push_colors() -> void: GameManager.apply_colors_live()

func _on_p1_drone_changed(c: Color) -> void:
	GameManager.p1_color = c; _push_colors()
	if _preview_player == 1: _refresh_preview()

func _on_p1_blade_changed(c: Color) -> void:
	GameManager.p1_blade_color = c; _push_colors()
	if _preview_player == 1: _refresh_preview()

func _on_p2_drone_changed(c: Color) -> void:
	GameManager.p2_color = c; _push_colors()
	if _preview_player == 2: _refresh_preview()

func _on_p2_blade_changed(c: Color) -> void:
	GameManager.p2_blade_color = c; _push_colors()
	if _preview_player == 2: _refresh_preview()

func _on_reset_p1_drone() -> void: _pick_p1_drone.color = Color.WHITE; _on_p1_drone_changed(Color.WHITE)
func _on_reset_p1_blade() -> void: _pick_p1_blade.color = Color.WHITE; _on_p1_blade_changed(Color.WHITE)
func _on_reset_p2_drone() -> void: _pick_p2_drone.color = Color.WHITE; _on_p2_drone_changed(Color.WHITE)
func _on_reset_p2_blade() -> void: _pick_p2_blade.color = Color.WHITE; _on_p2_blade_changed(Color.WHITE)

func _on_save_preset() -> void:
	var presets: Array = _load_presets()
	presets.append([_pick_p1_drone.color, _pick_p1_blade.color, _pick_p2_drone.color, _pick_p2_blade.color])
	_save_presets_to_disk(presets); _rebuild_preset_list()

func _on_apply_preset(index: int) -> void:
	var presets: Array = _load_presets()
	if index >= presets.size(): return
	var e: Array = presets[index]
	_pick_p1_drone.color = e[0]; _on_p1_drone_changed(e[0])
	_pick_p1_blade.color = e[1]; _on_p1_blade_changed(e[1])
	_pick_p2_drone.color = e[2]; _on_p2_drone_changed(e[2])
	_pick_p2_blade.color = e[3]; _on_p2_blade_changed(e[3])

func _on_delete_preset(index: int) -> void:
	var presets: Array = _load_presets()
	if index < presets.size():
		presets.remove_at(index); _save_presets_to_disk(presets); _rebuild_preset_list()

# -- Saved drone presets (full Hex-Drones customization) --------------------
func _load_drone_presets() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(DRONE_PRESET_FILE) == OK:
		return cfg.get_value(PRESET_SECTION, "drones", [])
	return []

func _save_drone_presets_to_disk(list: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(PRESET_SECTION, "drones", list)
	cfg.save(DRONE_PRESET_FILE)

func _on_save_drone(player: int) -> void:
	var list: Array = _load_drone_presets()
	list.append(GameManager.capture_drone_data(player))
	_save_drone_presets_to_disk(list)
	_rebuild_saved_drones_list()

func _rebuild_saved_drones_list() -> void:
	if _saved_drones_list == null: return
	for child in _saved_drones_list.get_children(): child.queue_free()
	var list: Array = _load_drone_presets()
	if list.is_empty():
		var el := Label.new(); el.text = "(no saved drones)"
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_saved_drones_list.add_child(el); return
	for i in range(list.size()):
		var d: Dictionary = list[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_swatch(row, d.get("color", Color.WHITE), "")
		_swatch(row, d.get("blade_color", Color.WHITE), "")
		_swatch(row, d.get("gsi", Color.WHITE), "")
		var bi: int = GameManager.DRONE_BODY_FOLDERS.find(String(d.get("drone_body", "DronesBlank")))
		var nm := Label.new()
		nm.text = (GameManager.DRONE_BODY_NAMES[bi] if bi >= 0 else "Drone") + " %d" % (i + 1)
		nm.add_theme_font_size_override("font_size", 11)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var p1b := Button.new(); p1b.text = "→P1"; p1b.custom_minimum_size = Vector2(40, 26)
		p1b.pressed.connect(_on_apply_drone.bind(i, 1)); row.add_child(p1b)
		var p2b := Button.new(); p2b.text = "→P2"; p2b.custom_minimum_size = Vector2(40, 26)
		p2b.pressed.connect(_on_apply_drone.bind(i, 2)); row.add_child(p2b)
		var db := Button.new(); db.text = "×"; db.custom_minimum_size = Vector2(26, 26)
		db.pressed.connect(_on_delete_drone.bind(i)); row.add_child(db)
		_saved_drones_list.add_child(row)

func _on_apply_drone(index: int, player: int) -> void:
	var list: Array = _load_drone_presets()
	if index >= list.size(): return
	GameManager.apply_drone_data(player, list[index])
	_sync_drones_tab_from_state()

func _on_delete_drone(index: int) -> void:
	var list: Array = _load_drone_presets()
	if index < list.size():
		list.remove_at(index); _save_drone_presets_to_disk(list); _rebuild_saved_drones_list()

# -- Board tile colour pickers ----------------------------------------------
func _on_board_tile_hex_pressed(group: String, btn: TextureButton) -> void:
	if _tile_color_popup == null:
		_tile_color_popup = PopupPanel.new()
		_tile_color_picker = ColorPicker.new()
		_tile_color_picker.edit_alpha = false
		_tile_color_popup.add_child(_tile_color_picker)
		add_child(_tile_color_popup)
		_tile_color_picker.color_changed.connect(_on_board_tile_color_changed)
	_tile_color_group = group
	_tile_color_btn   = btn
	_tile_color_picker.color = GameManager.board_tile_color(group)
	_tile_color_popup.popup(Rect2i(int(btn.global_position.x), int(btn.global_position.y + 56), 0, 0))

func _on_board_tile_color_changed(c: Color) -> void:
	if _tile_color_group == "":
		return
	GameManager.set_board_tile_color(_tile_color_group, c)
	if _tile_color_btn != null and is_instance_valid(_tile_color_btn):
		_tile_color_btn.self_modulate = c

## Re-sync the Drones-tab pickers + preview after applying a saved drone.
func _sync_drones_tab_from_state() -> void:
	if _p1_body_option:   _p1_body_option.select(maxi(GameManager.DRONE_BODY_FOLDERS.find(GameManager.p1_drone_body), 0))
	if _p2_body_option:   _p2_body_option.select(maxi(GameManager.DRONE_BODY_FOLDERS.find(GameManager.p2_drone_body), 0))
	if _p1_blades_option: _p1_blades_option.select(maxi(_DRONES_BLADE_VARIANTS.find(GameManager.p1_blade_variant), 0))
	if _p2_blades_option: _p2_blades_option.select(maxi(_DRONES_BLADE_VARIANTS.find(GameManager.p2_blade_variant), 0))
	_refresh_drones_preview()

# -- Colors-tab live preview ------------------------------------------------
## Tile types 1-7 match the Tile_N asset naming; the preview cycles through them.
const _PREVIEW_TILE_COUNT: int = 7

## Variant folder name → PNG filename suffix (mirrors HexBoard.BLADE_VARIANT_SUFFIX).
const _BLADE_SUFFIX: Dictionary = {
	"HexBladesGlowy":       "Lines_Glowy",
	"HexBladesOrnate":      "Ornate",
	"HexBladesPowerStripe": "PowerStripes",
	"HexBladesSharp":       "Sharp",
	"HexBladesSolid":       "Solid",
	"HexBladesStripes":     "Stripes",
	"HexBladesSharpDash":   "SharpDash",
	"HexBladesSolidSharp":  "SolidSharp",
	"HexBladesShort":       "Short",
	"HexBladesBanner":      "Banner",
	"HexBladesSword&Spear": "Sword&Spear",
}

## Drones tab — blade variant ordered list and display names.
const _DRONES_BLADE_VARIANTS: Array = [
	"HexBladesGlowy", "HexBladesOrnate", "HexBladesPowerStripe", "HexBladesSharp",
	"HexBladesSolid", "HexBladesStripes", "HexBladesSharpDash", "HexBladesSolidSharp",
	"HexBladesShort", "HexBladesBanner", "HexBladesSword&Spear",
]
const _DRONES_BLADE_NAMES: Array = [
	"Glowy", "Ornate", "Power Stripe", "Sharp", "Solid", "Stripes", "Sharp Dash", "Solid Sharp",
	"Short", "Banner", "Sword&Spear",
]

## ◀/▶ nav button using NextArrow.png (flipped horizontally for ◀).
func _make_hex_nav_btn(_arrow: String, is_left: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 80)
	btn.text = ""
	var clr   := StyleBoxFlat.new(); clr.bg_color   = Color(0, 0, 0, 0)
	var clr_h := clr.duplicate() as StyleBoxFlat; clr_h.bg_color = Color(1, 1, 1, 0.14)
	var clr_p := clr.duplicate() as StyleBoxFlat; clr_p.bg_color = Color(1, 1, 1, 0.26)
	btn.add_theme_stylebox_override("normal",  clr)
	btn.add_theme_stylebox_override("hover",   clr_h)
	btn.add_theme_stylebox_override("pressed", clr_p)
	btn.add_theme_stylebox_override("focus",   clr)

	var img_r := TextureRect.new()
	img_r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_r.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	var arrow_path := "res://assets/NextArrow.png"
	img_r.texture = load(arrow_path) if ResourceLoader.exists(arrow_path) else null
	## ▶ is NextArrow flipped horizontally; ◀ uses it as-is
	if not is_left:
		img_r.flip_h = true
	img_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(img_r)

	## Keep _nav_left_blade/_nav_right_blade null — no blade overlay on arrow buttons.
	return btn

## Small (48×48) hex-shaped P1/P2 toggle. Sets _preview_player_label so that
## _update_preview_player_btn() can update its text without storing the button itself.
func _make_hex_toggle_btn() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(48, 48)
	btn.text = ""
	var clr   := StyleBoxFlat.new(); clr.bg_color   = Color(0, 0, 0, 0)
	var clr_h := clr.duplicate() as StyleBoxFlat; clr_h.bg_color = Color(1, 1, 1, 0.18)
	var clr_p := clr.duplicate() as StyleBoxFlat; clr_p.bg_color = Color(1, 1, 1, 0.30)
	btn.add_theme_stylebox_override("normal",  clr)
	btn.add_theme_stylebox_override("hover",   clr_h)
	btn.add_theme_stylebox_override("pressed", clr_p)
	btn.add_theme_stylebox_override("focus",   clr)

	_preview_player_hex = TextureRect.new()
	_preview_player_hex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_player_hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_player_hex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	var hexy_path := GameManager.drone_body_path(GameManager.p1_drone_body, false)
	_preview_player_hex.texture = load(hexy_path) if ResourceLoader.exists(hexy_path) else null
	_preview_player_hex.modulate = Color(0.35, 0.45, 0.72, 0.90)
	_preview_player_hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_preview_player_hex)

	_preview_player_label = Label.new()
	_preview_player_label.text = "P1"
	_preview_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_player_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_preview_player_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_player_label.add_theme_font_size_override("font_size", 13)
	_preview_player_label.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	_preview_player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.80))
	_preview_player_label.add_theme_constant_override("outline_size", 4)
	_preview_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_preview_player_label)
	return btn

## Picker row without a label — just [ColorPickerButton][↺ Reset].
## Used in the right column of the 3-column Colors layout.
func _picker_only(parent: VBoxContainer, color: Color, cb: Callable, rst_cb: Callable, label_text: String = "") -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END   ## hug the right edge
	parent.add_child(row)

	if label_text != "":
		var lbl := Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(0, 34)
		row.add_child(lbl)

	var cpb := ColorPickerButton.new()
	cpb.color = color
	cpb.custom_minimum_size = Vector2(80, 34)
	cpb.color_changed.connect(cb)
	row.add_child(cpb)

	var rst := Button.new()
	rst.text = "↺"
	rst.custom_minimum_size = Vector2(34, 34)
	rst.pressed.connect(rst_cb)
	row.add_child(rst)
	return cpb

## Reload the preview TextureRects for the current tile index, blade variant, and player.
func _refresh_preview() -> void:
	if _preview_drone_rect == null or _preview_blade_rect == null:
		return
	var tile_n: int = _preview_tile_index + 1   ## 1-indexed
	var is_p2: bool = (_preview_player == 2)

	var drone_color: Color = GameManager.p2_color      if is_p2 else GameManager.p1_color
	var blade_color: Color = GameManager.p2_blade_color if is_p2 else GameManager.p1_blade_color

	if _preview_tile_label:
		_preview_tile_label.text = "Tile %d  /  %d" % [tile_n, _PREVIEW_TILE_COUNT]
		_preview_tile_label.add_theme_color_override("font_color", drone_color)
	if _preview_player_hex:
		_preview_player_hex.modulate = drone_color
	if _preview_player_label:
		_preview_player_label.add_theme_color_override("font_color", blade_color)

	var drone_path: String = GameManager.drone_body_path(
		GameManager.p2_drone_body if is_p2 else GameManager.p1_drone_body, is_p2)
	_preview_drone_rect.texture  = load(drone_path) if ResourceLoader.exists(drone_path) else null
	_preview_drone_rect.modulate = drone_color

	var variant: String = GameManager.p2_blade_variant if is_p2 else GameManager.p1_blade_variant
	var suffix:  String = _BLADE_SUFFIX.get(variant, "Lines_Glowy")
	var b_infix: String = "b_" if is_p2 else "_"
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_%d%s%s.png" % [variant, tile_n, b_infix, suffix]
	if ResourceLoader.exists(blade_path):
		_preview_blade_rect.texture = load(blade_path)
	else:
		var fb := "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_%d%sLines_Glowy.png" % [tile_n, b_infix]
		_preview_blade_rect.texture = load(fb) if ResourceLoader.exists(fb) else null
	_preview_blade_rect.modulate = blade_color

func _on_preview_prev() -> void:
	_preview_tile_index = (_preview_tile_index - 1 + _PREVIEW_TILE_COUNT) % _PREVIEW_TILE_COUNT
	_refresh_preview()

func _on_preview_next() -> void:
	_preview_tile_index = (_preview_tile_index + 1) % _PREVIEW_TILE_COUNT
	_refresh_preview()

func _on_toggle_preview_player() -> void:
	_preview_player = 2 if _preview_player == 1 else 1
	_update_preview_player_btn()
	_refresh_preview()

func _update_preview_player_btn() -> void:
	if _preview_player_label != null:
		_preview_player_label.text = "P%d" % _preview_player

func _update_nav_blade_textures() -> void:
	var variant: String = GameManager.p1_blade_variant
	var suffix:  String = _BLADE_SUFFIX.get(variant, "Lines_Glowy")
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_1_%s.png" % [variant, suffix]
	var tex: Texture2D = load(blade_path) if ResourceLoader.exists(blade_path) else null
	if _nav_left_blade:  _nav_left_blade.texture  = tex
	if _nav_right_blade: _nav_right_blade.texture = tex

# ---------------------------------------------------------------------------
# Glow tab — toggle button, preview, callbacks
# ---------------------------------------------------------------------------
## Same as _make_hex_toggle_btn but writes to _glow_preview_player_hex / _label.
func _make_glow_toggle_btn() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(48, 48)
	btn.text = ""
	var clr   := StyleBoxFlat.new(); clr.bg_color   = Color(0, 0, 0, 0)
	var clr_h := clr.duplicate() as StyleBoxFlat; clr_h.bg_color = Color(1, 1, 1, 0.18)
	var clr_p := clr.duplicate() as StyleBoxFlat; clr_p.bg_color = Color(1, 1, 1, 0.30)
	btn.add_theme_stylebox_override("normal",  clr)
	btn.add_theme_stylebox_override("hover",   clr_h)
	btn.add_theme_stylebox_override("pressed", clr_p)
	btn.add_theme_stylebox_override("focus",   clr)

	_glow_preview_player_hex = TextureRect.new()
	_glow_preview_player_hex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_preview_player_hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_glow_preview_player_hex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	var hexy_path := GameManager.drone_body_path(GameManager.p1_drone_body, false)
	_glow_preview_player_hex.texture = load(hexy_path) if ResourceLoader.exists(hexy_path) else null
	_glow_preview_player_hex.modulate = Color(0.35, 0.45, 0.72, 0.90)
	_glow_preview_player_hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_glow_preview_player_hex)

	_glow_preview_player_label = Label.new()
	_glow_preview_player_label.text = "P1"
	_glow_preview_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glow_preview_player_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_glow_preview_player_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_preview_player_label.add_theme_font_size_override("font_size", 13)
	_glow_preview_player_label.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	_glow_preview_player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.80))
	_glow_preview_player_label.add_theme_constant_override("outline_size", 4)
	_glow_preview_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_glow_preview_player_label)
	return btn

func _refresh_glow_preview() -> void:
	if _glow_preview_drone_rect == null or _glow_preview_blade_rect == null: return
	var tile_n: int = _glow_preview_tile_index + 1
	var is_p2: bool = (_glow_preview_player == 2)

	var drone_color: Color = GameManager.p2_color      if is_p2 else GameManager.p1_color
	var blade_color: Color = GameManager.p2_blade_color if is_p2 else GameManager.p1_blade_color

	if _glow_preview_tile_label:
		_glow_preview_tile_label.text = "Tile %d  /  %d" % [tile_n, _PREVIEW_TILE_COUNT]
		_glow_preview_tile_label.add_theme_color_override("font_color", drone_color)
	if _glow_preview_player_hex:
		_glow_preview_player_hex.modulate = drone_color
	if _glow_preview_player_label:
		_glow_preview_player_label.add_theme_color_override("font_color", blade_color)

	var drone_path: String = GameManager.drone_body_path(
		GameManager.p2_drone_body if is_p2 else GameManager.p1_drone_body, is_p2)
	_glow_preview_drone_rect.texture  = load(drone_path) if ResourceLoader.exists(drone_path) else null
	_glow_preview_drone_rect.modulate = drone_color

	var variant: String = GameManager.p2_blade_variant if is_p2 else GameManager.p1_blade_variant
	var suffix:  String = _BLADE_SUFFIX.get(variant, "Lines_Glowy")
	var b_infix: String = "b_" if is_p2 else "_"
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_%d%s%s.png" % [variant, tile_n, b_infix, suffix]
	if ResourceLoader.exists(blade_path):
		_glow_preview_blade_rect.texture = load(blade_path)
	else:
		var fb := "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_%d%sLines_Glowy.png" % [tile_n, b_infix]
		_glow_preview_blade_rect.texture = load(fb) if ResourceLoader.exists(fb) else null
	_glow_preview_blade_rect.modulate = blade_color

	if _glow_preview_ring != null:
		var inner: Color; var outer: Color
		match _glow_active_type:
			"move":
				inner = GameManager.p2_glow_move_inner    if is_p2 else GameManager.p1_glow_move_inner
				outer = GameManager.p2_glow_move_outer    if is_p2 else GameManager.p1_glow_move_outer
			"capture":
				inner = GameManager.p2_glow_capture_inner if is_p2 else GameManager.p1_glow_capture_inner
				outer = GameManager.p2_glow_capture_outer if is_p2 else GameManager.p1_glow_capture_outer
			_:
				inner = GameManager.p2_glow_selected_inner if is_p2 else GameManager.p1_glow_selected_inner
				outer = GameManager.p2_glow_selected_outer if is_p2 else GameManager.p1_glow_selected_outer
		var grad_enabled: bool = GameManager.p2_gradient_enabled if is_p2 else GameManager.p1_gradient_enabled
		_glow_preview_ring.call("set_colors", inner, outer, grad_enabled,
			GameManager.glow_effect, GameManager.glow_opacity, GameManager.glow_speed)

func _apply_all_glow_settings() -> void:
	var row_types   := ["selected", "move", "capture", "selected", "move", "capture"]
	var row_players := [1, 1, 1, 2, 2, 2]
	for i in _glow_inner_picks.size():
		GameManager.set_glow_colors(row_players[i], row_types[i],
			_glow_inner_picks[i].color, _glow_outer_picks[i].color)
	if _glow_p1_grad_toggle: GameManager.set_glow_gradient_enabled(1, _glow_p1_grad_toggle.button_pressed)
	if _glow_p2_grad_toggle: GameManager.set_glow_gradient_enabled(2, _glow_p2_grad_toggle.button_pressed)
	if _glow_opacity_slider: GameManager.set_glow_opacity(_glow_opacity_slider.value)
	if _glow_speed_slider:   GameManager.set_glow_speed(_glow_speed_slider.value)

func _on_glow_opacity_changed(val: float) -> void:
	GameManager.set_glow_opacity(val)
	_refresh_glow_preview()

func _on_glow_speed_changed(val: float) -> void:
	GameManager.set_glow_speed(val)
	_refresh_glow_preview()

func _on_glow_gradient_toggled(player: int, on: bool) -> void:
	GameManager.set_glow_gradient_enabled(player, on)
	_refresh_glow_preview()

func _on_glow_effect_selected(eff_id: String) -> void:
	GameManager.set_glow_effect(eff_id)
	_refresh_glow_preview()

func _on_glow_toggle_player() -> void:
	_glow_preview_player = 2 if _glow_preview_player == 1 else 1
	if _glow_preview_player_label != null:
		_glow_preview_player_label.text = "P%d" % _glow_preview_player
	_refresh_glow_preview()

func _on_glow_preview_prev() -> void:
	_glow_preview_tile_index = (_glow_preview_tile_index - 1 + _PREVIEW_TILE_COUNT) % _PREVIEW_TILE_COUNT
	_refresh_glow_preview()

func _on_glow_preview_next() -> void:
	_glow_preview_tile_index = (_glow_preview_tile_index + 1) % _PREVIEW_TILE_COUNT
	_refresh_glow_preview()

func _on_glow_inner_changed(player: int, type: String, idx: int, c: Color) -> void:
	var outer: Color = _glow_outer_picks[idx].color if idx < _glow_outer_picks.size() else Color.WHITE
	GameManager.set_glow_colors(player, type, c, outer)
	_glow_active_type    = type
	_glow_preview_player = player
	_refresh_glow_preview()

func _on_glow_outer_changed(player: int, type: String, idx: int, c: Color) -> void:
	var inner: Color = _glow_inner_picks[idx].color if idx < _glow_inner_picks.size() else Color.WHITE
	GameManager.set_glow_colors(player, type, inner, c)
	_glow_active_type    = type
	_glow_preview_player = player
	_refresh_glow_preview()

# ===========================================================================
# MULTIPLAYER — Mode select panel
# ===========================================================================
func _build_mp_mode_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80; panel.offset_top = 80
	panel.offset_right = -80; panel.offset_bottom = -80
	panel.visible = false

	## Fully opaque -- the default theme panel background lets the menu
	## behind it show through.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	bg_style.corner_radius_top_left     = 8
	bg_style.corner_radius_top_right    = 8
	bg_style.corner_radius_bottom_left  = 8
	bg_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", bg_style)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20; root.offset_top = 12
	root.offset_right = -20; root.offset_bottom = -20
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 18)
	panel.add_child(root)

	var title := Label.new()
	title.text = "MULTIPLAYER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Play online — choose how to find a match."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	root.add_child(sub)

	_spacer(root, 10)

	## Server Browse button
	var browse_btn := Button.new()
	browse_btn.text = "SERVER BROWSING"
	browse_btn.custom_minimum_size = Vector2(300, 64)
	browse_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	browse_btn.add_theme_font_size_override("font_size", 19)
	browse_btn.pressed.connect(_on_open_browse)
	root.add_child(browse_btn)

	var browse_desc := Label.new()
	browse_desc.text = "See open lobbies and join one, or create your own with a custom name."
	browse_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	browse_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	browse_desc.add_theme_font_size_override("font_size", 12)
	root.add_child(browse_desc)

	_spacer(root, 6)

	## Matchmaking button
	var mm_btn := Button.new()
	mm_btn.text = "MATCHMAKING"
	mm_btn.custom_minimum_size = Vector2(300, 64)
	mm_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mm_btn.add_theme_font_size_override("font_size", 19)
	mm_btn.pressed.connect(_on_open_matchmaking)
	root.add_child(mm_btn)

	var mm_desc := Label.new()
	mm_desc.text = "Skip the lobby — get auto-matched with another player instantly."
	mm_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mm_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	mm_desc.add_theme_font_size_override("font_size", 12)
	root.add_child(mm_desc)

	## Rejoin last game — only shown if a previous lobby code exists
	if not NetworkManager.last_lobby_code.is_empty():
		_spacer(root, 10)
		var rejoin_btn := Button.new()
		rejoin_btn.text = "↩  Rejoin Last Game  (" + NetworkManager.last_lobby_code + ")"
		rejoin_btn.custom_minimum_size = Vector2(300, 46)
		rejoin_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rejoin_btn.add_theme_font_size_override("font_size", 15)
		rejoin_btn.pressed.connect(_on_rejoin)
		root.add_child(rejoin_btn)

	_close_btn(panel, _on_mp_mode_close)
	return panel

# ===========================================================================
# MULTIPLAYER — Server Browse panel
# ===========================================================================
func _build_mp_browse_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40; panel.offset_top = 20
	panel.offset_right = -40; panel.offset_bottom = -20
	panel.visible = false

	## Fully opaque -- the default theme panel background lets the menu
	## behind it show through.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.12, 0.17, 1.0)
	bg_style.corner_radius_top_left     = 8
	bg_style.corner_radius_top_right    = 8
	bg_style.corner_radius_bottom_left  = 8
	bg_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", bg_style)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16; root.offset_top = 8
	root.offset_right = -16; root.offset_bottom = -20
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	## Title row with Back button
	var title_row := HBoxContainer.new()
	root.add_child(title_row)

	var back_btn := Button.new()
	back_btn.text = "◀ Back"
	back_btn.custom_minimum_size = Vector2(80, 32)
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.pressed.connect(_on_browse_back)
	title_row.add_child(back_btn)

	var title := Label.new()
	title.text = "SERVER BROWSING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_spacer(title_row, 0)   ## balance the back btn
	var spacer_r := Control.new()
	spacer_r.custom_minimum_size = Vector2(80, 0)
	title_row.add_child(spacer_r)

	## Create lobby section
	var create_header := Label.new()
	create_header.text = "── Create a Lobby ──"
	create_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_header.add_theme_font_size_override("font_size", 13)
	root.add_child(create_header)

	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	create_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(create_row)

	_browse_name_field = LineEdit.new()
	_browse_name_field.placeholder_text = "Lobby name  (optional)"
	_browse_name_field.custom_minimum_size = Vector2(220, 42)
	_browse_name_field.add_theme_font_size_override("font_size", 15)
	create_row.add_child(_browse_name_field)

	var create_btn := Button.new()
	create_btn.text = "CREATE"
	create_btn.custom_minimum_size = Vector2(90, 42)
	create_btn.add_theme_font_size_override("font_size", 15)
	create_btn.pressed.connect(_on_browse_create)
	create_row.add_child(create_btn)

	## Join-by-code section
	var join_header := Label.new()
	join_header.text = "── Join a Lobby ──"
	join_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_header.add_theme_font_size_override("font_size", 13)
	root.add_child(join_header)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(join_row)

	_browse_join_code_field = LineEdit.new()
	_browse_join_code_field.placeholder_text = "Enter lobby code"
	_browse_join_code_field.custom_minimum_size = Vector2(220, 42)
	_browse_join_code_field.add_theme_font_size_override("font_size", 15)
	_browse_join_code_field.text_submitted.connect(func(_t): _on_browse_join_by_code())
	join_row.add_child(_browse_join_code_field)

	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(90, 42)
	join_btn.add_theme_font_size_override("font_size", 15)
	join_btn.pressed.connect(_on_browse_join_by_code)
	join_row.add_child(join_btn)

	## Lobby code display (visible once hosted)
	_browse_lobby_code_label = Label.new()
	_browse_lobby_code_label.text = ""
	_browse_lobby_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_browse_lobby_code_label.add_theme_font_size_override("font_size", 14)
	_browse_lobby_code_label.visible = false
	root.add_child(_browse_lobby_code_label)

	## START GAME button (visible once peer joins)
	_browse_start_btn = Button.new()
	_browse_start_btn.text = "START GAME"
	_browse_start_btn.custom_minimum_size = Vector2(200, 46)
	_browse_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_browse_start_btn.visible = false
	_browse_start_btn.add_theme_font_size_override("font_size", 16)
	_browse_start_btn.pressed.connect(_on_browse_start)
	root.add_child(_browse_start_btn)

	## Open lobbies list section
	var list_header_row := HBoxContainer.new()
	list_header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(list_header_row)

	var list_title := Label.new()
	list_title.text = "── Open Lobbies ──"
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_title.add_theme_font_size_override("font_size", 13)
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header_row.add_child(list_title)

	var refresh_btn := Button.new()
	refresh_btn.text = "↻ Refresh"
	refresh_btn.custom_minimum_size = Vector2(90, 30)
	refresh_btn.add_theme_font_size_override("font_size", 12)
	refresh_btn.pressed.connect(_on_browse_refresh)
	list_header_row.add_child(refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_widen_scrollbar(scroll)

	_browse_list = VBoxContainer.new()
	_browse_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_browse_list)

	## Status label
	_browse_status = Label.new()
	_browse_status.text = "Fetching lobby list…"
	_browse_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_browse_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_browse_status.add_theme_font_size_override("font_size", 13)
	root.add_child(_browse_status)

	_close_btn(panel, _on_browse_close)
	return panel

# ===========================================================================
# MULTIPLAYER — Matchmaking panel
# ===========================================================================
func _build_mp_mm_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80; panel.offset_top = 80
	panel.offset_right = -80; panel.offset_bottom = -80
	panel.visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20; root.offset_top = 12
	root.offset_right = -20; root.offset_bottom = -20
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 16)
	panel.add_child(root)

	## Title row with Back button
	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(title_row)

	var back_btn := Button.new()
	back_btn.text = "◀ Back"
	back_btn.custom_minimum_size = Vector2(80, 32)
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.pressed.connect(_on_mm_back)
	title_row.add_child(back_btn)

	var title := Label.new()
	title.text = "MATCHMAKING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var spacer_r := Control.new()
	spacer_r.custom_minimum_size = Vector2(80, 0)
	title_row.add_child(spacer_r)

	var desc := Label.new()
	desc.text = "Click Find Match to enter the queue.\nWhen another player is waiting you will be paired instantly."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 14)
	root.add_child(desc)

	_spacer(root, 10)

	_mm_find_btn = Button.new()
	_mm_find_btn.text = "FIND MATCH"
	_mm_find_btn.custom_minimum_size = Vector2(240, 58)
	_mm_find_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mm_find_btn.add_theme_font_size_override("font_size", 20)
	_mm_find_btn.pressed.connect(_on_mm_find)
	root.add_child(_mm_find_btn)

	_mm_cancel_btn = Button.new()
	_mm_cancel_btn.text = "Cancel Search"
	_mm_cancel_btn.custom_minimum_size = Vector2(180, 40)
	_mm_cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mm_cancel_btn.add_theme_font_size_override("font_size", 14)
	_mm_cancel_btn.visible = false
	_mm_cancel_btn.pressed.connect(_on_mm_cancel)
	root.add_child(_mm_cancel_btn)

	_mm_status = Label.new()
	_mm_status.text = ""
	_mm_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mm_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_mm_status.add_theme_font_size_override("font_size", 14)
	root.add_child(_mm_status)

	_mm_start_btn = Button.new()
	_mm_start_btn.text = "START GAME"
	_mm_start_btn.custom_minimum_size = Vector2(200, 48)
	_mm_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mm_start_btn.visible = false
	_mm_start_btn.add_theme_font_size_override("font_size", 16)
	_mm_start_btn.pressed.connect(_on_mm_start)
	root.add_child(_mm_start_btn)

	_close_btn(panel, _on_mm_close)
	return panel

# ===========================================================================
# Button callbacks — navigation
# ===========================================================================
func _on_play() -> void:
	_play_main_view.visible  = true
	_play_local_view.visible = false
	_play_panel.visible      = true
func _on_multiplayer() -> void: _mp_mode_panel.visible = true
func _on_tutorial() -> void:
	GameManager.p1_is_bot = false
	GameManager.p2_is_bot = false
	GameManager.mp_player  = 0
	TutorialManager.start_tutorial()
	get_tree().change_scene_to_file("res://node_2d.tscn")

func _on_colors()      -> void: _colors_panel.visible  = true; _rebuild_preset_list()
func _on_settings()    -> void: _settings_panel.visible = true; _refresh_window_mode_btns()
func _on_store()       -> void: _store_panel.open()
func _on_achievements() -> void:
	_achievements_panel.visible = true
	_rebuild_achievements_list()

## Android/mobile hardware back button — steps back one menu level instead of
## quitting (requires application/config/quit_on_go_back=false in
## project.godot). Checked nested-to-outer since only one overlay is ever
## visible at a time in this menu's design.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST: return

	if _mp_browse_panel != null and _mp_browse_panel.visible:
		_on_browse_close()
	elif _mp_mm_panel != null and _mp_mm_panel.visible:
		_on_mm_close()
	elif _mp_mode_panel != null and _mp_mode_panel.visible:
		_on_mp_mode_close()
	elif _battle_panel != null and _battle_panel.visible:
		_battle_panel.visible   = false
		_play_panel.visible     = true
		_play_main_view.visible = true
		_play_local_view.visible = false
	elif _play_panel != null and _play_panel.visible and _play_local_view.visible:
		_play_local_view.visible = false
		_play_main_view.visible  = true
	elif _play_panel != null and _play_panel.visible:
		_play_panel.visible = false
	elif _puzzle_panel != null and _puzzle_panel.visible:
		_on_puzzles_close()
	elif _colors_panel != null and _colors_panel.visible:
		_on_colors_close()
	elif _settings_panel != null and _settings_panel.visible:
		_on_settings_close()
	elif _store_panel != null and _store_panel.visible:
		_store_panel.visible = false
	elif _account_panel != null and _account_panel.visible:
		_account_panel.visible = false
	elif _achievements_panel != null and _achievements_panel.visible:
		_achievements_panel.visible = false
	## else: nothing open — no-op, never quit the app via back.

func _on_colors_close()   -> void: _colors_panel.visible   = false
func _on_settings_close() -> void: _settings_panel.visible = false

func _on_puzzles()       -> void: _puzzle_panel.visible = true
func _on_puzzles_close() -> void:
	_puzzle_panel.visible = false
	_play_panel.visible   = true

## Total puzzle drone choices: 7 specific tiles + 1 Random slot (index 7).
const _PUZZLE_TILE_COUNT: int = 8

func _on_puzzle_prev() -> void:
	_puzzle_tile_index = (_puzzle_tile_index - 1 + _PUZZLE_TILE_COUNT) % _PUZZLE_TILE_COUNT
	_refresh_puzzle_preview()

func _on_puzzle_next() -> void:
	_puzzle_tile_index = (_puzzle_tile_index + 1) % _PUZZLE_TILE_COUNT
	_refresh_puzzle_preview()

func _refresh_puzzle_preview() -> void:
	if _puzzle_preview_drone_rect == null or _puzzle_preview_blade_rect == null: return
	var is_random: bool    = (_puzzle_tile_index == _PUZZLE_TILE_COUNT - 1)
	var drone_color: Color = GameManager.p1_color
	var blade_color: Color = GameManager.p1_blade_color
	if _puzzle_preview_tile_label != null:
		_puzzle_preview_tile_label.text = "Random  /  %d" % _PREVIEW_TILE_COUNT if is_random \
			else "Tile %d  /  %d" % [_puzzle_tile_index + 1, _PREVIEW_TILE_COUNT]
		_puzzle_preview_tile_label.add_theme_color_override("font_color", drone_color)
	if is_random:
		_puzzle_preview_drone_rect.texture  = null
		_puzzle_preview_blade_rect.texture  = null
		_puzzle_preview_drone_rect.modulate = drone_color
		_puzzle_preview_blade_rect.modulate = blade_color
		## Show a "?" label in place of the sprite (reuse the tile-label position).
		if _puzzle_preview_tile_label != null:
			_puzzle_preview_tile_label.text = "?  (Random Drone)\nDifferent every puzzle!"
		return
	var tile_n: int = _puzzle_tile_index + 1
	var drone_path: String = GameManager.drone_body_path(GameManager.p1_drone_body, false)
	_puzzle_preview_drone_rect.texture  = load(drone_path) if ResourceLoader.exists(drone_path) else null
	_puzzle_preview_drone_rect.modulate = drone_color
	var variant: String = GameManager.p1_blade_variant
	var suffix:  String = _BLADE_SUFFIX.get(variant, "Lines_Glowy")
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_%d_%s.png" % [variant, tile_n, suffix]
	if ResourceLoader.exists(blade_path):
		_puzzle_preview_blade_rect.texture = load(blade_path)
	else:
		var fb := "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_%d_Lines_Glowy.png" % tile_n
		_puzzle_preview_blade_rect.texture = load(fb) if ResourceLoader.exists(fb) else null
	_puzzle_preview_blade_rect.modulate = blade_color

func _on_start_puzzle() -> void:
	## Index 7 = Random: SID 0 tells GameManager to pick a new random SID each puzzle.
	var chosen_sid: int = 0 if _puzzle_tile_index == _PUZZLE_TILE_COUNT - 1 else _puzzle_tile_index + 1
	_puzzle_panel.visible = false
	GameManager.p1_is_bot         = false
	GameManager.p2_is_bot         = false
	GameManager.mp_player          = 1
	GameManager._pending_puzzle_sid = chosen_sid   ## picked up by _try_init_game_nodes
	get_tree().change_scene_to_file("res://node_2d.tscn")

func _build_puzzles_panel() -> Panel:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40; panel.offset_top = 20
	panel.offset_right = -40; panel.offset_bottom = -20
	panel.visible = false

	## Title
	var title := Label.new()
	title.text = "PUZZLES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 16; title.offset_bottom = 56
	panel.add_child(title)

	## Instructions
	var info := Label.new()
	info.text = "Choose your drone.\nCapture all enemies in 5 moves!"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_font_size_override("font_size", 14)
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info.offset_top = 60; info.offset_bottom = 110
	panel.add_child(info)

	## Drone preview widget (centered, 140×140)
	var preview_wrap := Control.new()
	preview_wrap.anchor_left  = 0.5; preview_wrap.anchor_right  = 0.5
	preview_wrap.anchor_top   = 0.0; preview_wrap.anchor_bottom = 0.0
	preview_wrap.offset_left  = -70; preview_wrap.offset_right  = 70
	preview_wrap.offset_top   = 118; preview_wrap.offset_bottom = 258
	panel.add_child(preview_wrap)

	_puzzle_preview_drone_rect = TextureRect.new()
	_puzzle_preview_drone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_puzzle_preview_drone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_puzzle_preview_drone_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	preview_wrap.add_child(_puzzle_preview_drone_rect)

	_puzzle_preview_blade_rect = TextureRect.new()
	_puzzle_preview_blade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_puzzle_preview_blade_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_puzzle_preview_blade_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	preview_wrap.add_child(_puzzle_preview_blade_rect)

	## ◀ / ▶ nav buttons
	var prev_btn := Button.new()
	prev_btn.text = "◀"
	prev_btn.anchor_left  = 0.5; prev_btn.anchor_right  = 0.5
	prev_btn.anchor_top   = 0.0; prev_btn.anchor_bottom = 0.0
	prev_btn.offset_left  = -110; prev_btn.offset_right  = -74
	prev_btn.offset_top   = 168;  prev_btn.offset_bottom = 208
	prev_btn.add_theme_font_size_override("font_size", 18)
	prev_btn.pressed.connect(_on_puzzle_prev)
	panel.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "▶"
	next_btn.anchor_left  = 0.5; next_btn.anchor_right  = 0.5
	next_btn.anchor_top   = 0.0; next_btn.anchor_bottom = 0.0
	next_btn.offset_left  = 74;  next_btn.offset_right  = 110
	next_btn.offset_top   = 168; next_btn.offset_bottom = 208
	next_btn.add_theme_font_size_override("font_size", 18)
	next_btn.pressed.connect(_on_puzzle_next)
	panel.add_child(next_btn)

	## Tile label below preview
	_puzzle_preview_tile_label = Label.new()
	_puzzle_preview_tile_label.text = "Tile 1  /  7"
	_puzzle_preview_tile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puzzle_preview_tile_label.add_theme_font_size_override("font_size", 14)
	_puzzle_preview_tile_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_puzzle_preview_tile_label.offset_top = 264; _puzzle_preview_tile_label.offset_bottom = 292
	panel.add_child(_puzzle_preview_tile_label)

	## Start Puzzle button
	var start_btn := Button.new()
	start_btn.text = "START PUZZLE"
	start_btn.anchor_left  = 0.5; start_btn.anchor_right  = 0.5
	start_btn.anchor_top   = 0.0; start_btn.anchor_bottom = 0.0
	start_btn.offset_left  = -110; start_btn.offset_right  = 110
	start_btn.offset_top   = 300;  start_btn.offset_bottom = 346
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(_on_start_puzzle)
	panel.add_child(start_btn)

	_close_btn(panel, _on_puzzles_close)
	_refresh_puzzle_preview()
	return panel
func _on_taste_close()    -> void:
	_music_taste_panel.visible = false
	_settings_panel.visible    = true

func _on_music_volume_changed(value: float) -> void: MusicPlayer.set_volume(value)

func _on_rejoin() -> void:
	## Reconnect to the last lobby and drop straight back into the game scene.
	## GameManager.start_game() restores the saved snapshot (if still within the
	## 2-minute window) and resyncs with whoever is still in the game.
	GameManager.pending_rejoin = true
	GameManager.p1_is_bot      = false
	GameManager.p2_is_bot      = false
	NetworkManager.rejoin()
	get_tree().change_scene_to_file("res://node_2d.tscn")

func _on_drones_tab_colors() -> void:
	_drones_colors_container.visible      = true
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = false

func _on_drones_tab_sounds() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = true
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = false

func _on_drones_tab_backgrounds() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = true
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = false

func _on_drones_tab_blades() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = true
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = false

func _on_drones_tab_glow() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = true
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = false

func _on_drones_tab_screen() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = true
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = false
	_refresh_screen_effect_btns()

func _on_screen_player_select(p: int) -> void:
	_screen_edit_player = p
	_refresh_screen_effect_btns()

func _on_drones_tab_drive() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = true
	_drones_destroy_container.visible     = false
	var spd: float = GameManager.drive_speed_for(_drive_edit_player)
	if _drive_speed_slider != null:
		_drive_speed_slider.value = spd
	if _drive_speed_label != null:
		_drive_speed_label.text = "%.2fs" % spd
	_refresh_drive_mode_btns()
	_refresh_drive_effect_btns()
	_refresh_drive_preview()

func _on_window_mode_selected(mode: int) -> void:
	GameManager.set_window_mode(mode)
	_refresh_window_mode_btns()

func _refresh_window_mode_btns() -> void:
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel.corner_radius_top_left     = 5
	sel.corner_radius_top_right    = 5
	sel.corner_radius_bottom_left  = 5
	sel.corner_radius_bottom_right = 5
	for i in _window_mode_btns.size():
		var btn: Button = _window_mode_btns[i]
		if i == GameManager.window_mode:
			btn.add_theme_stylebox_override("normal", sel)
		else:
			btn.remove_theme_stylebox_override("normal")

func _on_screen_effect_selected(id: int) -> void:
	GameManager.set_screen_effect(_screen_edit_player, id)
	_refresh_screen_effect_btns()

func _refresh_screen_effect_btns() -> void:
	## Highlight the P1/P2 selector buttons
	var sel_player_style := StyleBoxFlat.new()
	sel_player_style.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel_player_style.corner_radius_top_left     = 5
	sel_player_style.corner_radius_top_right    = 5
	sel_player_style.corner_radius_bottom_left  = 5
	sel_player_style.corner_radius_bottom_right = 5
	if _screen_p1_btn != null:
		if _screen_edit_player == 1:
			_screen_p1_btn.add_theme_stylebox_override("normal", sel_player_style)
		else:
			_screen_p1_btn.remove_theme_stylebox_override("normal")
	if _screen_p2_btn != null:
		if _screen_edit_player == 2:
			_screen_p2_btn.add_theme_stylebox_override("normal", sel_player_style)
		else:
			_screen_p2_btn.remove_theme_stylebox_override("normal")
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel_style.corner_radius_top_left     = 5
	sel_style.corner_radius_top_right    = 5
	sel_style.corner_radius_bottom_left  = 5
	sel_style.corner_radius_bottom_right = 5
	for ef_id in _screen_effect_btns.keys():
		var btn: Button = _screen_effect_btns[ef_id]
		if ef_id == GameManager.screen_effect_for(_screen_edit_player):
			btn.add_theme_stylebox_override("normal", sel_style)
		else:
			btn.remove_theme_stylebox_override("normal")

func _on_drive_mode_selected(mode: int) -> void:
	_drive_edit_mode = mode
	_refresh_drive_mode_btns()
	_refresh_drive_effect_btns()
	_refresh_drive_preview()

## Point both speed sliders/labels at the player currently being edited. Drive and
## Destroy speeds are independent, each with its own always-visible slider.
func _sync_drive_speed_sliders() -> void:
	var dspd: float = GameManager.drive_speed_for(_drive_edit_player)
	var xspd: float = GameManager.destroy_drive_speed_for(_drive_edit_player)
	if _drive_speed_slider != null:   _drive_speed_slider.value = dspd
	if _drive_speed_label != null:    _drive_speed_label.text = "%.2fs" % dspd
	if _destroy_speed_slider != null: _destroy_speed_slider.value = xspd
	if _destroy_speed_label != null:  _destroy_speed_label.text = "%.2fs" % xspd

func _on_drive_effect_selected(id: int) -> void:
	if _drive_edit_mode == 0:
		GameManager.set_drive_effect(_drive_edit_player, id, GameManager.drive_speed_for(_drive_edit_player))
	else:
		GameManager.set_destroy_drive_effect(_drive_edit_player, id)
	_refresh_drive_effect_btns()

func _on_drive_speed_changed(value: float) -> void:
	GameManager.set_drive_effect(_drive_edit_player, GameManager.drive_effect_for(_drive_edit_player), value)
	if _drive_speed_label != null:
		_drive_speed_label.text = "%.2fs" % value

func _on_destroy_drive_speed_changed(value: float) -> void:
	GameManager.set_destroy_drive_speed(_drive_edit_player, value)
	if _destroy_speed_label != null:
		_destroy_speed_label.text = "%.2fs" % value

func _on_drive_toggle_player() -> void:
	_drive_edit_player = 2 if _drive_edit_player == 1 else 1
	if _drive_preview_player_label != null:
		_drive_preview_player_label.text = "P%d" % _drive_edit_player
	_sync_drive_speed_sliders()
	_refresh_drive_mode_btns()
	_refresh_drive_effect_btns()
	_refresh_drive_preview()

func _refresh_drive_mode_btns() -> void:
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel.corner_radius_top_left     = 5
	sel.corner_radius_top_right    = 5
	sel.corner_radius_bottom_left  = 5
	sel.corner_radius_bottom_right = 5
	for i in _drive_mode_btns.size():
		var btn: Button = _drive_mode_btns[i]
		if i == _drive_edit_mode:
			btn.add_theme_stylebox_override("normal", sel)
		else:
			btn.remove_theme_stylebox_override("normal")

func _refresh_drive_effect_btns() -> void:
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel_style.corner_radius_top_left     = 5
	sel_style.corner_radius_top_right    = 5
	sel_style.corner_radius_bottom_left  = 5
	sel_style.corner_radius_bottom_right = 5
	var current_id: int = GameManager.drive_effect_for(_drive_edit_player) if _drive_edit_mode == 0 \
						  else GameManager.destroy_drive_effect_for(_drive_edit_player)
	for ef_id in _drive_effect_btns.keys():
		var btn: Button = _drive_effect_btns[ef_id]
		if ef_id == current_id:
			btn.add_theme_stylebox_override("normal", sel_style)
		else:
			btn.remove_theme_stylebox_override("normal")

func _make_drive_toggle_btn() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(48, 48)
	btn.text = ""
	var clr   := StyleBoxFlat.new(); clr.bg_color = Color(0, 0, 0, 0)
	var clr_h := clr.duplicate() as StyleBoxFlat; clr_h.bg_color = Color(1, 1, 1, 0.18)
	var clr_p := clr.duplicate() as StyleBoxFlat; clr_p.bg_color = Color(1, 1, 1, 0.30)
	btn.add_theme_stylebox_override("normal",  clr)
	btn.add_theme_stylebox_override("hover",   clr_h)
	btn.add_theme_stylebox_override("pressed", clr_p)
	btn.add_theme_stylebox_override("focus",   clr)

	_drive_preview_player_hex = TextureRect.new()
	_drive_preview_player_hex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drive_preview_player_hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drive_preview_player_hex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	var hexy_path := GameManager.drone_body_path(GameManager.p1_drone_body, false)
	_drive_preview_player_hex.texture = load(hexy_path) if ResourceLoader.exists(hexy_path) else null
	_drive_preview_player_hex.modulate = Color(0.35, 0.45, 0.72, 0.90)
	_drive_preview_player_hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_drive_preview_player_hex)

	_drive_preview_player_label = Label.new()
	_drive_preview_player_label.text = "P1"
	_drive_preview_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drive_preview_player_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_drive_preview_player_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drive_preview_player_label.add_theme_font_size_override("font_size", 13)
	_drive_preview_player_label.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	_drive_preview_player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.80))
	_drive_preview_player_label.add_theme_constant_override("outline_size", 4)
	_drive_preview_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_drive_preview_player_label)
	return btn

func _refresh_drive_preview() -> void:
	if _drive_preview_drone_rect == null or _drive_preview_wrap == null: return
	_drive_preview_animating = false
	_drive_preview_wrap.position = Vector2(0.0, 0.0)
	_drive_preview_wrap.scale    = Vector2.ONE
	_drive_preview_wrap.modulate = Color.WHITE
	var is_p2: bool = (_drive_edit_player == 2)
	var drone_color: Color = GameManager.p2_color       if is_p2 else GameManager.p1_color
	var blade_color: Color = GameManager.p2_blade_color  if is_p2 else GameManager.p1_blade_color
	if _drive_preview_player_hex != null:
		_drive_preview_player_hex.modulate = drone_color
	if _drive_preview_player_label != null:
		_drive_preview_player_label.add_theme_color_override("font_color", blade_color)
	var drone_path: String = GameManager.drone_body_path(
		GameManager.p2_drone_body if is_p2 else GameManager.p1_drone_body, is_p2)
	_drive_preview_drone_rect.texture  = load(drone_path) if ResourceLoader.exists(drone_path) else null
	_drive_preview_drone_rect.modulate = drone_color
	var variant: String = GameManager.p2_blade_variant if is_p2 else GameManager.p1_blade_variant
	var suffix:  String = _BLADE_SUFFIX.get(variant, "Lines_Glowy")
	var b_infix: String = "b_" if is_p2 else "_"
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_1%s%s.png" % [variant, b_infix, suffix]
	if ResourceLoader.exists(blade_path):
		_drive_preview_blade_rect.texture = load(blade_path)
	else:
		var fb := "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_1%sLines_Glowy.png" % b_infix
		_drive_preview_blade_rect.texture = load(fb) if ResourceLoader.exists(fb) else null
	_drive_preview_blade_rect.modulate = blade_color

func _on_drive_preview_play() -> void:
	if _drive_preview_animating or _drive_preview_wrap == null: return
	_drive_preview_animating = true
	_animate_drive_preview()

func _animate_drive_preview() -> void:
	if _drive_preview_wrap == null: return
	## Reset starting state: piece at left side of stage
	_drive_preview_wrap.scale    = Vector2.ONE
	_drive_preview_wrap.modulate = Color.WHITE
	_drive_preview_wrap.position = Vector2(0.0, 0.0)
	_drive_preview_wrap.pivot_offset = Vector2(40.0, 40.0)
	var to_pos   := Vector2(80.0, 0.0)
	var dur: float = maxf(
		GameManager.drive_speed_for(_drive_edit_player) if _drive_edit_mode == 0 \
		else GameManager.destroy_drive_speed_for(_drive_edit_player), 0.25)
	var tw := create_tween()
	var _preview_effect_id: int = GameManager.drive_effect_for(_drive_edit_player) if _drive_edit_mode == 0 \
								  else GameManager.destroy_drive_effect_for(_drive_edit_player)
	match _preview_effect_id:
		2:  ## Fade
			var half: float = dur * 0.5
			tw.tween_property(_drive_preview_wrap, "modulate:a", 0.0, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			tw.tween_callback(func(): _drive_preview_wrap.position = to_pos)
			tw.tween_property(_drive_preview_wrap, "modulate:a", 1.0, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		3:  ## Zoom
			var half: float = dur * 0.5
			tw.tween_property(_drive_preview_wrap, "scale", Vector2.ZERO, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
			tw.tween_callback(func(): _drive_preview_wrap.position = to_pos)
			tw.tween_property(_drive_preview_wrap, "scale", Vector2.ONE, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		4:  ## Flash
			var seg: float = dur / 7.0
			var bright := Color(1.6, 1.6, 1.6, 1.0)
			var normal := Color(1.0, 1.0, 1.0, 1.0)
			var gone   := Color(1.6, 1.6, 1.6, 0.0)
			tw.tween_property(_drive_preview_wrap, "modulate", bright, seg)
			tw.tween_property(_drive_preview_wrap, "modulate", normal, seg)
			tw.tween_property(_drive_preview_wrap, "modulate", gone,   seg)
			tw.tween_callback(func(): _drive_preview_wrap.position = to_pos; _drive_preview_wrap.modulate = Color(1.6, 1.6, 1.6, 0.0))
			tw.tween_property(_drive_preview_wrap, "modulate", bright, seg)
			tw.tween_property(_drive_preview_wrap, "modulate", normal, seg)
			tw.tween_property(_drive_preview_wrap, "modulate", bright, seg)
			tw.tween_property(_drive_preview_wrap, "modulate", normal, seg)
		5:  ## Slide
			tw.set_ease(Tween.EASE_IN_OUT)
			tw.set_trans(Tween.TRANS_QUART)
			tw.tween_property(_drive_preview_wrap, "position", to_pos, dur)
		6:  ## Spin
			_drive_preview_wrap.rotation = 0.0
			tw.set_parallel(true)
			tw.tween_property(_drive_preview_wrap, "rotation", TAU, dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(_drive_preview_wrap, "position", to_pos, dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.set_parallel(false)
			tw.tween_callback(func(): _drive_preview_wrap.rotation = 0.0)
		7:  ## Multi Spin
			_drive_preview_wrap.rotation = 0.0
			var spin_dur: float = dur * 0.65
			var slide_dur: float = dur * 0.35
			tw.tween_property(_drive_preview_wrap, "rotation", TAU * 4.0, spin_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_callback(func(): _drive_preview_wrap.rotation = 0.0)
			tw.tween_property(_drive_preview_wrap, "position", to_pos, slide_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUART)
		8:  ## Pixilate
			var hide_dur: float = dur * 0.3
			var flash_dur: float = dur * 0.25
			var settle_dur: float = dur * 0.25
			tw.tween_property(_drive_preview_wrap, "modulate:a", 0.0, hide_dur).set_ease(Tween.EASE_IN)
			tw.tween_callback(func(): _drive_preview_wrap.position = to_pos; _drive_preview_wrap.modulate = Color(2.0, 2.0, 2.0, 0.0))
			tw.tween_property(_drive_preview_wrap, "modulate", Color(2.0, 2.0, 2.0, 1.0), flash_dur).set_ease(Tween.EASE_OUT)
			tw.tween_property(_drive_preview_wrap, "modulate", Color.WHITE, settle_dur).set_ease(Tween.EASE_IN_OUT)
		_:  ## Snap (1 or default) — short pause then jump
			tw.tween_interval(0.12)
			tw.tween_callback(func(): _drive_preview_wrap.position = to_pos)
			tw.tween_interval(0.15)
	tw.tween_callback(_refresh_drive_preview)

func _make_destroy_toggle_btn() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(48, 48)
	btn.text = ""
	var clr   := StyleBoxFlat.new(); clr.bg_color = Color(0, 0, 0, 0)
	var clr_h := clr.duplicate() as StyleBoxFlat; clr_h.bg_color = Color(1, 1, 1, 0.18)
	var clr_p := clr.duplicate() as StyleBoxFlat; clr_p.bg_color = Color(1, 1, 1, 0.30)
	btn.add_theme_stylebox_override("normal",  clr)
	btn.add_theme_stylebox_override("hover",   clr_h)
	btn.add_theme_stylebox_override("pressed", clr_p)
	btn.add_theme_stylebox_override("focus",   clr)

	_destroy_preview_player_hex = TextureRect.new()
	_destroy_preview_player_hex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destroy_preview_player_hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_destroy_preview_player_hex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	var hexy_path := GameManager.drone_body_path(GameManager.p1_drone_body, false)
	_destroy_preview_player_hex.texture = load(hexy_path) if ResourceLoader.exists(hexy_path) else null
	_destroy_preview_player_hex.modulate = Color(0.35, 0.45, 0.72, 0.90)
	_destroy_preview_player_hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_destroy_preview_player_hex)

	_destroy_preview_player_label = Label.new()
	_destroy_preview_player_label.text = "P1"
	_destroy_preview_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_destroy_preview_player_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_destroy_preview_player_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_destroy_preview_player_label.add_theme_font_size_override("font_size", 13)
	_destroy_preview_player_label.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	_destroy_preview_player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.80))
	_destroy_preview_player_label.add_theme_constant_override("outline_size", 4)
	_destroy_preview_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_destroy_preview_player_label)
	return btn

func _on_destroy_toggle_player() -> void:
	_destroy_preview_player = 2 if _destroy_preview_player == 1 else 1
	if _destroy_preview_player_label != null:
		_destroy_preview_player_label.text = "P%d" % _destroy_preview_player
	_refresh_destroy_preview()
	_refresh_destroy_effect_btns()

func _on_drones_tab_destroy() -> void:
	_drones_colors_container.visible      = false
	_drones_sounds_container.visible      = false
	_drones_backgrounds_container.visible = false
	_drones_blades_container.visible      = false
	_drones_glow_container.visible        = false
	_drones_screen_container.visible      = false
	_drones_drive_container.visible       = false
	_drones_destroy_container.visible     = true
	_refresh_destroy_preview()
	_refresh_destroy_effect_btns()

func _on_destroy_effect_selected(id: int) -> void:
	GameManager.set_destroy_effect(_destroy_preview_player, id)
	_refresh_destroy_effect_btns()

func _on_destroy_preview_play() -> void:
	if _destroy_preview_animating or _destroy_preview_wrap == null: return
	_destroy_preview_animating = true
	_animate_destroy_preview()

func _refresh_destroy_effect_btns() -> void:
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color = Color(0.18, 0.45, 0.85, 0.40)
	sel_style.corner_radius_top_left     = 5
	sel_style.corner_radius_top_right    = 5
	sel_style.corner_radius_bottom_left  = 5
	sel_style.corner_radius_bottom_right = 5
	for ef_id in _destroy_effect_btns.keys():
		var btn: Button = _destroy_effect_btns[ef_id]
		if ef_id == GameManager.destroy_effect_for(_destroy_preview_player):
			btn.add_theme_stylebox_override("normal", sel_style)
		else:
			btn.remove_theme_stylebox_override("normal")

func _refresh_destroy_preview() -> void:
	if _destroy_preview_drone_rect == null or _destroy_preview_wrap == null: return
	_destroy_preview_animating = false
	_destroy_preview_wrap.position = Vector2.ZERO
	_destroy_preview_wrap.scale    = Vector2.ONE
	_destroy_preview_wrap.modulate = Color.WHITE
	var is_p2: bool = (_destroy_preview_player == 2)
	var drone_color: Color = GameManager.p2_color       if is_p2 else GameManager.p1_color
	var blade_color: Color = GameManager.p2_blade_color  if is_p2 else GameManager.p1_blade_color
	if _destroy_preview_player_hex != null:
		_destroy_preview_player_hex.modulate = drone_color
	if _destroy_preview_player_label != null:
		_destroy_preview_player_label.add_theme_color_override("font_color", blade_color)
	var drone_path: String = GameManager.drone_body_path(
		GameManager.p2_drone_body if is_p2 else GameManager.p1_drone_body, is_p2)
	_destroy_preview_drone_rect.texture  = load(drone_path) if ResourceLoader.exists(drone_path) else null
	_destroy_preview_drone_rect.modulate = drone_color
	var variant: String = GameManager.p2_blade_variant if is_p2 else GameManager.p1_blade_variant
	var suffix:  String = _BLADE_SUFFIX.get(variant, "Lines_Glowy")
	var b_infix: String = "b_" if is_p2 else "_"
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_1%s%s.png" % [variant, b_infix, suffix]
	if ResourceLoader.exists(blade_path):
		_destroy_preview_blade_rect.texture = load(blade_path)
	else:
		var fb := "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_1%sLines_Glowy.png" % b_infix
		_destroy_preview_blade_rect.texture = load(fb) if ResourceLoader.exists(fb) else null
	_destroy_preview_blade_rect.modulate = blade_color

func _animate_destroy_preview() -> void:
	if _destroy_preview_wrap == null: return
	_destroy_preview_wrap.pivot_offset = Vector2(75.0, 75.0)
	var dur: float = 0.5
	var tw := create_tween()
	match GameManager.destroy_effect_for(_destroy_preview_player):
		1:  ## Explode
			tw.tween_property(_destroy_preview_wrap, "scale", Vector2(3.5, 3.5), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		2:  ## Implode
			tw.tween_property(_destroy_preview_wrap, "scale", Vector2.ZERO, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tw.parallel().tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		3:  ## Pixilate — shimmer dissolve approximation
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(1.6, 1.6, 1.6, 1.00), dur * 0.12)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(0.7, 0.7, 0.7, 0.70), dur * 0.15)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(1.4, 1.4, 1.4, 0.45), dur * 0.15)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(0.3, 0.3, 0.3, 0.20), dur * 0.18)
			tw.tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur * 0.40)
		4:  ## Split — flatten horizontally to suggest splitting apart
			tw.tween_property(_destroy_preview_wrap, "scale", Vector2(0.0, 1.2), dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
		5:  ## Flash
			var bright := Color(2.8, 2.8, 2.8, 1.0)
			var normal := Color(1.0, 1.0, 1.0, 1.0)
			var seg: float = dur / 5.0
			tw.tween_property(_destroy_preview_wrap, "modulate", bright, seg).set_ease(Tween.EASE_OUT)
			tw.tween_property(_destroy_preview_wrap, "modulate", normal, seg).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(_destroy_preview_wrap, "modulate", bright, seg).set_ease(Tween.EASE_OUT)
			tw.tween_property(_destroy_preview_wrap, "modulate:a", 0.0, seg * 2.0).set_ease(Tween.EASE_IN)
		6:  ## Explode Flash
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(3.0, 3.0, 3.0, 1.0), dur * 0.2).set_ease(Tween.EASE_OUT)
			tw.tween_property(_destroy_preview_wrap, "scale", Vector2(3.5, 3.5), dur * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur * 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		7:  ## Implode Flash
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(3.0, 3.0, 3.0, 1.0), dur * 0.2).set_ease(Tween.EASE_OUT)
			tw.tween_property(_destroy_preview_wrap, "scale", Vector2.ZERO, dur * 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tw.parallel().tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur * 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		8:  ## Pixilate B — same shimmer dissolve as Pixilate (glow colour shows in-game)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(1.6, 1.6, 1.6, 1.00), dur * 0.12)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(0.7, 0.7, 0.7, 0.70), dur * 0.15)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(1.4, 1.4, 1.4, 0.45), dur * 0.15)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(0.3, 0.3, 0.3, 0.20), dur * 0.18)
			tw.tween_property(_destroy_preview_wrap, "modulate:a", 0.0, dur * 0.40)
		9:  ## Knockout — flash on impact, fly off to the right
			_destroy_preview_wrap.pivot_offset = Vector2(75.0, 75.0)
			var ko_offset := Vector2(110.0, 0.0)
			tw.tween_property(_destroy_preview_wrap, "modulate", Color(3.5, 3.5, 3.5, 1.0), dur * 0.08).set_ease(Tween.EASE_OUT)
			tw.tween_property(_destroy_preview_wrap, "position",
				_destroy_preview_wrap.position + ko_offset, dur * 0.92)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			tw.parallel().tween_property(_destroy_preview_wrap, "modulate", Color(1.0, 1.0, 1.0, 0.0), dur * 0.92)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(_destroy_preview_wrap, "scale", Vector2(0.65, 0.65), dur * 0.92)\
				.set_ease(Tween.EASE_IN)
	tw.tween_callback(_refresh_destroy_preview)

## Builds the P1/P2 hex toggle button used in the center of the Drones tab.
func _make_drones_toggle_btn() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(60, 60)
	btn.text = ""
	var clr   := StyleBoxFlat.new(); clr.bg_color   = Color(0, 0, 0, 0)
	var clr_h := clr.duplicate() as StyleBoxFlat; clr_h.bg_color = Color(1, 1, 1, 0.18)
	var clr_p := clr.duplicate() as StyleBoxFlat; clr_p.bg_color = Color(1, 1, 1, 0.30)
	btn.add_theme_stylebox_override("normal",  clr)
	btn.add_theme_stylebox_override("hover",   clr_h)
	btn.add_theme_stylebox_override("pressed", clr_p)
	btn.add_theme_stylebox_override("focus",   clr)

	_drones_preview_player_hex = TextureRect.new()
	_drones_preview_player_hex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drones_preview_player_hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drones_preview_player_hex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_drones_preview_player_hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_drones_preview_player_hex)

	_drones_preview_player_label = Label.new()
	_drones_preview_player_label.text = "P1"
	_drones_preview_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drones_preview_player_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_drones_preview_player_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drones_preview_player_label.add_theme_font_size_override("font_size", 13)
	_drones_preview_player_label.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	_drones_preview_player_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.80))
	_drones_preview_player_label.add_theme_constant_override("outline_size", 4)
	_drones_preview_player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_drones_preview_player_label)
	return btn

func _on_drones_toggle_player() -> void:
	_drones_tab_player = 2 if _drones_tab_player == 1 else 1
	if _drones_preview_player_label != null:
		_drones_preview_player_label.text = "P%d" % _drones_tab_player
	_refresh_drones_preview()

func _on_drones_prev_blade() -> void:
	var cur: String = GameManager.p1_blade_variant if _drones_tab_player == 1 else GameManager.p2_blade_variant
	var idx: int = _DRONES_BLADE_VARIANTS.find(cur)
	var n: int = _DRONES_BLADE_VARIANTS.size()
	for _i in n:
		idx = (idx - 1 + n) % n
		if AchievementManager.is_asset_unlocked("blade", _DRONES_BLADE_VARIANTS[idx]):
			break
	_apply_drones_blade(idx)

func _on_drones_next_blade() -> void:
	var cur: String = GameManager.p1_blade_variant if _drones_tab_player == 1 else GameManager.p2_blade_variant
	var idx: int = _DRONES_BLADE_VARIANTS.find(cur)
	var n: int = _DRONES_BLADE_VARIANTS.size()
	for _i in n:
		idx = (idx + 1) % n
		if AchievementManager.is_asset_unlocked("blade", _DRONES_BLADE_VARIANTS[idx]):
			break
	_apply_drones_blade(idx)

func _apply_drones_blade(idx: int) -> void:
	var variant: String = _DRONES_BLADE_VARIANTS[idx]
	GameManager.set_blade_variant(_drones_tab_player, variant)
	if _drones_tab_player == 1 and _p1_blades_option != null:
		_p1_blades_option.select(idx)
	elif _drones_tab_player == 2 and _p2_blades_option != null:
		_p2_blades_option.select(idx)
	_refresh_drones_preview()
	_update_nav_blade_textures()
	_refresh_preview()
	_refresh_glow_preview()
	_refresh_drive_preview()
	_refresh_destroy_preview()

func _on_p1_blades_option_selected(idx: int) -> void:
	if not AchievementManager.is_asset_unlocked("blade", _DRONES_BLADE_VARIANTS[idx]):
		_p1_blades_option.select(maxi(_DRONES_BLADE_VARIANTS.find(GameManager.p1_blade_variant), 0))
		return
	GameManager.set_blade_variant(1, _DRONES_BLADE_VARIANTS[idx])
	if _drones_tab_player == 1:
		_refresh_drones_preview()
	_update_nav_blade_textures()
	_refresh_preview()
	_refresh_glow_preview()
	_refresh_drive_preview()
	_refresh_destroy_preview()

func _on_p2_blades_option_selected(idx: int) -> void:
	if not AchievementManager.is_asset_unlocked("blade", _DRONES_BLADE_VARIANTS[idx]):
		_p2_blades_option.select(maxi(_DRONES_BLADE_VARIANTS.find(GameManager.p2_blade_variant), 0))
		return
	GameManager.set_blade_variant(2, _DRONES_BLADE_VARIANTS[idx])
	if _drones_tab_player == 2:
		_refresh_drones_preview()
	_refresh_preview()
	_refresh_glow_preview()
	_refresh_drive_preview()
	_refresh_destroy_preview()

func _on_drones_prev_body() -> void:
	var cur: String = GameManager.p1_drone_body if _drones_tab_player == 1 else GameManager.p2_drone_body
	var idx: int = GameManager.DRONE_BODY_FOLDERS.find(cur)
	var n: int = GameManager.DRONE_BODY_FOLDERS.size()
	for _i in n:
		idx = (idx - 1 + n) % n
		if AchievementManager.is_asset_unlocked("drone_body", GameManager.DRONE_BODY_FOLDERS[idx]):
			break
	_apply_drones_body(idx)

func _on_drones_next_body() -> void:
	var cur: String = GameManager.p1_drone_body if _drones_tab_player == 1 else GameManager.p2_drone_body
	var idx: int = GameManager.DRONE_BODY_FOLDERS.find(cur)
	var n: int = GameManager.DRONE_BODY_FOLDERS.size()
	for _i in n:
		idx = (idx + 1) % n
		if AchievementManager.is_asset_unlocked("drone_body", GameManager.DRONE_BODY_FOLDERS[idx]):
			break
	_apply_drones_body(idx)

func _apply_drones_body(idx: int) -> void:
	var folder: String = GameManager.DRONE_BODY_FOLDERS[idx]
	GameManager.set_drone_body(_drones_tab_player, folder)
	if _drones_tab_player == 1 and _p1_body_option != null:
		_p1_body_option.select(idx)
	elif _drones_tab_player == 2 and _p2_body_option != null:
		_p2_body_option.select(idx)
	_refresh_drones_preview()
	_refresh_preview()
	_refresh_glow_preview()
	_refresh_drive_preview()
	_refresh_destroy_preview()

func _on_p1_body_option_selected(idx: int) -> void:
	if not AchievementManager.is_asset_unlocked("drone_body", GameManager.DRONE_BODY_FOLDERS[idx]):
		_p1_body_option.select(maxi(GameManager.DRONE_BODY_FOLDERS.find(GameManager.p1_drone_body), 0))
		return
	GameManager.set_drone_body(1, GameManager.DRONE_BODY_FOLDERS[idx])
	if _drones_tab_player == 1:
		_refresh_drones_preview()
	_refresh_preview()
	_refresh_glow_preview()
	_refresh_drive_preview()
	_refresh_destroy_preview()

func _on_p2_body_option_selected(idx: int) -> void:
	if not AchievementManager.is_asset_unlocked("drone_body", GameManager.DRONE_BODY_FOLDERS[idx]):
		_p2_body_option.select(maxi(GameManager.DRONE_BODY_FOLDERS.find(GameManager.p2_drone_body), 0))
		return
	GameManager.set_drone_body(2, GameManager.DRONE_BODY_FOLDERS[idx])
	if _drones_tab_player == 2:
		_refresh_drones_preview()
	_refresh_preview()
	_refresh_glow_preview()
	_refresh_drive_preview()
	_refresh_destroy_preview()

func _refresh_drones_preview() -> void:
	if _drones_preview_drone_rect == null or _drones_preview_blade_rect == null:
		return
	var is_p2: bool = (_drones_tab_player == 2)
	var drone_color: Color = GameManager.p2_color       if is_p2 else GameManager.p1_color
	var blade_color: Color = GameManager.p2_blade_color  if is_p2 else GameManager.p1_blade_color

	if _drones_preview_player_hex != null:
		_drones_preview_player_hex.modulate = drone_color
	if _drones_preview_player_label != null:
		_drones_preview_player_label.add_theme_color_override("font_color", blade_color)

	var body_folder: String  = GameManager.p2_drone_body    if is_p2 else GameManager.p1_drone_body
	var blade_variant: String = GameManager.p2_blade_variant if is_p2 else GameManager.p1_blade_variant

	var blade_idx: int = _DRONES_BLADE_VARIANTS.find(blade_variant)
	if blade_idx < 0: blade_idx = 0
	if _drones_blade_label != null:
		_drones_blade_label.text = "Blades %d / %d" % [blade_idx + 1, _DRONES_BLADE_VARIANTS.size()]
	var body_idx: int = GameManager.DRONE_BODY_FOLDERS.find(body_folder)
	if body_idx < 0: body_idx = 0
	if _drones_body_label != null:
		_drones_body_label.text = "Drones %d / %d" % [body_idx + 1, GameManager.DRONE_BODY_FOLDERS.size()]

	var drone_path: String = GameManager.drone_body_path(body_folder, is_p2)
	_drones_preview_drone_rect.texture  = load(drone_path) if ResourceLoader.exists(drone_path) else null
	_drones_preview_drone_rect.modulate = drone_color

	var suffix: String  = _BLADE_SUFFIX.get(blade_variant, "Lines_Glowy")
	var b_infix: String = "b_" if is_p2 else "_"
	var blade_path := "res://assets/HexPieces/HexBlades/%s/Tile_1%s%s.png" % [blade_variant, b_infix, suffix]
	if ResourceLoader.exists(blade_path):
		_drones_preview_blade_rect.texture = load(blade_path)
	else:
		var fb := "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_1%sLines_Glowy.png" % b_infix
		_drones_preview_blade_rect.texture = load(fb) if ResourceLoader.exists(fb) else null
	_drones_preview_blade_rect.modulate = blade_color

func _rebuild_background_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
	_background_buttons.clear()

	## "None" option — disables the animated background entirely.
	_background_buttons[""] = _background_row(list, "", "None (Default)", null)

	## User-created solid color presets, each with its own select/edit/remove row.
	for entry in BackgroundManager.custom_colors:
		var cid: String = entry["id"]
		_background_buttons[cid] = _background_color_row(list, cid, entry["color"])

	var add_color_btn := Button.new()
	add_color_btn.custom_minimum_size = Vector2(0, 40)
	add_color_btn.add_theme_font_size_override("font_size", 14)
	add_color_btn.text = "+  Add Custom Color"
	add_color_btn.pressed.connect(_on_add_custom_color)
	list.add_child(add_color_btn)

	for entry in BackgroundManager.get_available_backgrounds():
		var id: String = entry["id"]
		var thumb: Texture2D = BackgroundManager.get_thumbnail(id)
		var label: String = entry["name"]
		var locked: bool = not AchievementManager.is_asset_unlocked("background", id)
		if locked:
			label += " (Locked)"
		var row_btn := _background_row(list, id, label, thumb)
		row_btn.disabled = locked
		_background_buttons[id] = row_btn

	_refresh_background_highlights()

func _background_row(parent: VBoxContainer, id: String, label: String, thumb: Texture2D) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", 14)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if thumb != null:
		btn.icon = thumb
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 40)

	btn.text = "  " + label
	btn.pressed.connect(_on_background_selected.bind(id))
	parent.add_child(btn)
	return btn

## Builds a row for a user-created solid color preset: a select button
## (shows the preset name + checkmark when active), a color picker swatch to
## edit the color in place, and a remove button.
func _background_color_row(parent: VBoxContainer, id: String, color: Color) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "  " + BackgroundManager.display_name(id)
	btn.pressed.connect(_on_background_selected.bind(id))
	row.add_child(btn)

	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(48, 48)
	picker.color = color
	picker.color_changed.connect(_on_custom_color_changed.bind(id))
	row.add_child(picker)

	var remove_btn := Button.new()
	remove_btn.custom_minimum_size = Vector2(36, 48)
	remove_btn.add_theme_font_size_override("font_size", 14)
	remove_btn.text = "x"
	remove_btn.pressed.connect(_on_remove_custom_color.bind(id))
	row.add_child(remove_btn)

	return btn

func _on_custom_color_changed(color: Color, id: String) -> void:
	BackgroundManager.set_custom_color(id, color)

func _on_remove_custom_color(id: String) -> void:
	BackgroundManager.remove_custom_color(id)
	_rebuild_background_list(_background_list_vbox)

func _on_add_custom_color() -> void:
	BackgroundManager.add_custom_color(Color(0.5, 0.5, 0.5))
	_rebuild_background_list(_background_list_vbox)

func _on_background_selected(id: String) -> void:
	BackgroundManager.set_selected(id)
	_refresh_background_highlights()

func _refresh_background_highlights() -> void:
	for id in _background_buttons.keys():
		var btn: Button = _background_buttons[id]
		var base: String = "None (Default)" if id == "" else BackgroundManager.display_name(id)
		btn.text = ("✓  " if id == BackgroundManager.selected_id else "  ") + base

func _on_sound_selected(player: int, sound_type: String, idx: int) -> void:
	SoundManager.set_sound(player, sound_type, idx)
	SoundManager.preview_sound(idx)
	_refresh_all_sound_highlights()

func _on_mp_mode_close() -> void:
	NetworkManager.disconnect_all()
	_mp_mode_panel.visible = false
	_play_panel.visible    = true

func _on_open_browse() -> void:
	_mp_mode_panel.visible   = false
	_mp_browse_panel.visible = true
	_browse_status.text      = "Fetching lobby list…"
	_browse_lobby_code_label.visible = false
	_browse_start_btn.visible        = false
	NetworkManager.list_lobbies()

func _on_open_matchmaking() -> void:
	_mp_mode_panel.visible = false
	_mp_mm_panel.visible   = true
	_mm_status.text        = ""
	_mm_find_btn.visible   = true
	_mm_cancel_btn.visible = false
	_mm_start_btn.visible  = false

# -- Browse panel -----------------------------------------------------------
func _on_browse_back() -> void:
	NetworkManager.disconnect_all()
	_browse_status.text              = ""
	_browse_lobby_code_label.visible = false
	_browse_start_btn.visible        = false
	_clear_browse_list()
	_mp_browse_panel.visible = false
	_mp_mode_panel.visible   = true

func _on_browse_close() -> void:
	NetworkManager.disconnect_all()
	_browse_lobby_code_label.visible = false
	_browse_start_btn.visible        = false
	_clear_browse_list()
	_mp_browse_panel.visible = false

func _on_browse_refresh() -> void:
	_browse_status.text = "Refreshing…"
	_clear_browse_list()
	NetworkManager.list_lobbies()

func _on_browse_create() -> void:
	var name_text := _browse_name_field.text.strip_edges()
	if name_text.is_empty():
		name_text = "Open Lobby"
	_browse_status.text              = "Creating lobby…"
	_browse_lobby_code_label.visible = false
	_browse_start_btn.visible        = false
	NetworkManager.host(name_text)

func _on_browse_join_by_code() -> void:
	var code := _browse_join_code_field.text.strip_edges().to_upper()
	if code.is_empty():
		_browse_status.text = "Enter a lobby code to join."
		return
	_browse_status.text              = "Joining " + code + "…"
	_browse_lobby_code_label.visible = false
	_browse_start_btn.visible        = false
	NetworkManager.join(code)

func _on_browse_start() -> void:
	NetworkManager.send_start()
	_launch_mp_game()

func _clear_browse_list() -> void:
	if _browse_list == null: return
	for c in _browse_list.get_children(): c.queue_free()

# -- Matchmaking panel -------------------------------------------------------
func _on_mm_back() -> void:
	NetworkManager.cancel_matchmake()
	NetworkManager.disconnect_all()
	_mm_status.text        = ""
	_mm_find_btn.visible   = true
	_mm_cancel_btn.visible = false
	_mm_start_btn.visible  = false
	_mp_mm_panel.visible   = false
	_mp_mode_panel.visible = true

func _on_mm_close() -> void:
	NetworkManager.cancel_matchmake()
	NetworkManager.disconnect_all()
	_mm_status.text        = ""
	_mm_find_btn.visible   = true
	_mm_cancel_btn.visible = false
	_mm_start_btn.visible  = false
	_mp_mm_panel.visible   = false

func _on_mm_find() -> void:
	_mm_status.text        = "Searching for an opponent…"
	_mm_find_btn.visible   = false
	_mm_cancel_btn.visible = true
	_mm_start_btn.visible  = false
	NetworkManager.matchmake()

func _on_mm_cancel() -> void:
	NetworkManager.cancel_matchmake()
	NetworkManager.disconnect_all()
	_mm_status.text        = "Search cancelled."
	_mm_find_btn.visible   = true
	_mm_cancel_btn.visible = false

func _on_mm_start() -> void:
	NetworkManager.send_start()
	_launch_mp_game()

# ===========================================================================
# NetworkManager signal receivers
# ===========================================================================

## Called after hosting — browse panel
func _on_lobby_ready(code: String) -> void:
	_browse_status.text = "Lobby created!  Waiting for a player to join…"
	_browse_lobby_code_label.text    = "Code: " + code + "  (players can also join from the list)"
	_browse_lobby_code_label.visible = true
	_browse_start_btn.visible        = false

## Called when guest joins
func _on_peer_joined() -> void:
	## Could be from browse panel (host) or matchmaking
	if _mp_browse_panel.visible:
		_browse_status.text       = "Player 2 connected!  Press START when ready."
		_browse_start_btn.visible = true
	elif _mp_mm_panel.visible:
		## Matchmaking host — guest joined, host presses START
		_mm_status.text       = "Opponent found!  Press START when ready."
		_mm_start_btn.visible = true
		_mm_cancel_btn.visible = false

func _on_peer_left() -> void:
	if _mp_browse_panel.visible:
		_browse_status.text       = "Other player disconnected."
		_browse_start_btn.visible = false
	elif _mp_mm_panel.visible:
		_mm_status.text       = "Opponent disconnected."
		_mm_start_btn.visible = false

func _on_connected_to_host() -> void:
	if _mp_browse_panel.visible:
		_browse_status.text = "Connected!  Waiting for host to start…"
	elif _mp_mm_panel.visible:
		_mm_status.text = "Connected!  Waiting for host to start…"

func _on_mp_connection_failed() -> void:
	if _mp_browse_panel.visible:
		_browse_status.text = "Connection failed.  Check the relay URL in NetworkManager.gd."
	elif _mp_mm_panel.visible:
		_mm_status.text       = "Connection failed."
		_mm_find_btn.visible   = true
		_mm_cancel_btn.visible = false

func _on_game_start_received() -> void:
	_launch_mp_game()

func _on_lobby_list_received(lobbies: Array) -> void:
	_clear_browse_list()
	if lobbies.is_empty():
		var empty := Label.new()
		empty.text = "No open lobbies right now.\nCreate one above or check back soon."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.add_theme_font_size_override("font_size", 13)
		_browse_list.add_child(empty)
		_browse_status.text = ""
		return

	for entry in lobbies:
		var code: String       = entry.get("code", "")
		var lobby_name: String = entry.get("name", "Open Lobby")
		var age:  int          = entry.get("age",  0)
		var age_str := str(age) + "s ago" if age < 60 else str(age / 60.0).pad_decimals(0) + "m ago"

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := Label.new()
		name_lbl.text = lobby_name
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)

		var age_lbl := Label.new()
		age_lbl.text = age_str
		age_lbl.add_theme_font_size_override("font_size", 12)
		age_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(age_lbl)

		var join_btn := Button.new()
		join_btn.text = "JOIN"
		join_btn.custom_minimum_size = Vector2(70, 34)
		join_btn.add_theme_font_size_override("font_size", 14)
		join_btn.pressed.connect(_on_join_listed_lobby.bind(code))
		row.add_child(join_btn)

		_browse_list.add_child(row)

	_browse_status.text = str(lobbies.size()) + " open " + ("lobby" if lobbies.size() == 1 else "lobbies") + " found."

func _on_join_listed_lobby(code: String) -> void:
	_browse_status.text = "Joining " + code + "…"
	_clear_browse_list()
	NetworkManager.join(code)

func _on_matchmake_waiting() -> void:
	_mm_status.text        = "Searching for an opponent…\n(In queue — will match when another player joins)"
	_mm_cancel_btn.visible = true

func _on_matchmake_matched() -> void:
	_mm_status.text        = "Match found!"
	_mm_cancel_btn.visible = false
	if NetworkManager.is_host:
		## Host side: wait for the peer_joined signal to show START
		_mm_status.text = "Match found!  Both players connected."
		_mm_start_btn.visible = true
	else:
		## Guest side: wait for host to press START
		_mm_status.text = "Match found!  Waiting for host to start…"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
func _launch_mp_game() -> void:
	_mp_browse_panel.visible = false
	_mp_mm_panel.visible     = false
	_mp_mode_panel.visible   = false
	GameManager.p1_is_bot    = false
	GameManager.p2_is_bot    = false
	GameManager.mp_player    = 1 if NetworkManager.is_host else 2
	get_tree().change_scene_to_file("res://node_2d.tscn")

func _exit_tree() -> void:
	if _bg_callback.is_valid() and BackgroundManager.background_changed.is_connected(_bg_callback):
		BackgroundManager.background_changed.disconnect(_bg_callback)
