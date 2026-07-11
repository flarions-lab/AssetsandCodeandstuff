extends CanvasLayer

## UIManager.gd

@onready var turn_label:      Label          = $TurnLabel
@onready var move_info_label: Label          = $MoveInfoLabel
@onready var die1_label:      Label          = $DicePanel/HBox/Die1Label
@onready var die2_label:      Label          = $DicePanel/HBox/Die2Label
@onready var die_total_label: Label          = $DicePanel/HBox/DieTotalLabel
@onready var roll_button:     Button         = $RollButton
@onready var rotate_button:   Button         = $RotatePanel/RotateButton
@onready var rotate_panel:    PanelContainer = $RotatePanel
@onready var win_screen:      Control        = $WinScreen
@onready var win_label:       Label          = $WinScreen/WinLabel

var bot_toggle:        Button
var _reconnect_label:  Label
var _rejoin_btn:       Button       ## in-game rejoin (shown on disconnect)
var _forfeit_btn:      Button       ## ✕ — abandon the match (opponent wins)
var _win_title:        Label        ## victory popup title ("Victory!")
var _win_subtitle:     Label        ## victory popup sub-text (winner + total time)
var _win_backdrop:     ColorRect    ## victory popup dim background
var _win_panel:        Panel        ## victory popup main panel (title/buttons)
var _win_minimized_btn: Button      ## "minimized" victory popup — tap to restore
var _win_menu_btn:     Button       ## "Return to Menu" / "Drone Choice" in puzzle mode
var _win_undo_btn:     Button       ## "↩ Undo Turn" / "Retry" in puzzle mode
var _difficulty_panel: Panel
var _diff_buttons:     Array = []   ## [[p1 easy/medium/hard/extra_hard btns], [p2 ...]]
var _bot_popup:        Panel
var _p1_bot_check:     CheckButton
var _p2_bot_check:     CheckButton

## Round 13 (item 1.5) — live "total game time" HUD label, bottom-center.
var _game_timer_label:    Label
var _game_timer_last_sec: int = -1

## Large puzzle timer — top-center, only visible in puzzle mode.
var _puzzle_timer_label: Label

## Mobile text scaling — all UI font sizes are bumped 15% on touch devices.
const MOBILE_FONT_SCALE: float = 1.15

## Mobile button sizing — buttons are bumped 20% bigger on touch devices.
const MOBILE_BUTTON_SCALE: float = 1.2

## Mobile safe-area clearance for the top HUD row (username/settings/menu),
## which otherwise sits a few pixels from the screen edge — right under the
## OS status bar (signal/battery/clock) and any rounded screen corners.
const MOBILE_TOP_INSET:  float = 36.0
const MOBILE_SIDE_INSET: float = 8.0

## Round 13 (item 2) — "matching blue with gold trim" accent color, shared by
## the victory popup's border/glow, title text, and button trim.
const WIN_GOLD := Color(1.0, 0.85, 0.35)

## Rejoin grace window (mirrors GameManager.REJOIN_WINDOW_SEC).
const REJOIN_WINDOW_SEC: float = 120.0
var _rejoin_active:   bool  = false
var _rejoin_deadline: float = 0.0
var _i_stayed:        bool  = false   ## true if our socket survived the drop

## Dice face images (BlankHexDie1..5) + roll animation state.
var _die_a_tex:       TextureRect
var _die_b_tex:       TextureRect
var _die_textures:    Array = []      ## [face1 … face5]
var _dice_rolling:    bool  = false
var _dice_anim_accum: float = 0.0
var _dice_anim_flip:  bool  = false

## "Bot is thinking" indicator (round 11): 4-frame hex-glass animation
## (assets/BotThinkingAnim/ThinkingHexGlass{3,2,1,0}.png, 250x250 each, played
## in that order then looped) that also spins continuously while visible.
## Shown by GameManager._bot_act for the duration of
## _decision_tree.evaluate_position() — on Extra Hard that search can take
## several seconds (see BotDecisionTree round 11 header / _search_extra_hard).
var _thinking_icon:       TextureRect
var _thinking_label:      Label
var _thinking_frames:     Array = []   ## [Glass3, Glass2, Glass1, Glass0] — looped in that order
var _thinking_frame_idx:  int   = 0
var _thinking_anim_accum: float = 0.0
const THINKING_FRAME_SEC:  float = 0.12   ## seconds each frame is shown
const THINKING_SPIN_SPEED: float = 180.0  ## degrees/second

## Replay / undo — managed by the win-popup Replay and Undo buttons.
var _replay_panel:      Control = null  ## pause/play bar shown during replay
var _replay_play_btn:   Button  = null  ## "⏸ Pause" / "▶ Play" toggle
var _replay_turn_label: Label   = null  ## "Turn N / M" indicator in replay bar
var _replay_timer:      Timer   = null  ## steps board through _game_states_cache
var _replay_index:      int     = 0
var _replay_paused:     bool    = false
var _game_states_cache: Array   = []   ## snapshot of GameManager._game_states

func _ready() -> void:
	win_screen.visible   = false
	rotate_panel.visible = false

	## ── Top-left: keep only the username + settings icon ────────────────────
	move_info_label.visible = false                  ## remove instructional text
	turn_label.text          = AccountManager.username
	turn_label.clip_text     = true
	var top_inset:  float = MOBILE_TOP_INSET  if _is_mobile() else 0.0
	var side_inset: float = MOBILE_SIDE_INSET if _is_mobile() else 0.0
	turn_label.offset_left   = 10.0 + side_inset;  turn_label.offset_top    = 8.0 + top_inset
	turn_label.offset_right  = 150.0 + side_inset; turn_label.offset_bottom = 34.0 + top_inset

	## Roll button + dice panel sit in the top-right, below the (now taller-on-
	## mobile) menu button — push them down by the same inset so they don't
	## overlap it.
	roll_button.offset_top    += top_inset
	roll_button.offset_bottom += top_inset
	var dice_panel = get_node_or_null("DicePanel")
	if dice_panel:
		dice_panel.offset_top    += top_inset
		dice_panel.offset_bottom += top_inset

	roll_button.pressed.connect(_on_roll_pressed)
	rotate_button.pressed.connect(_on_rotate_pressed)

	## Dice face images + roll animation
	_build_dice_images()
	var dr := get_node_or_null("/root/Main/DiceRoller")
	if dr != null and dr.has_signal("roll_started"):
		dr.roll_started.connect(_on_roll_started)

	var gm = get_node("/root/GameManager")
	gm.state_changed.connect(_on_state_changed)
	gm.turn_changed.connect(_on_turn_changed)
	gm.dice_rolled.connect(_on_dice_rolled)
	gm.movement_spent.connect(_on_movement_spent)
	gm.game_over.connect(_on_game_over)
	gm.piece_selected.connect(_on_piece_selected)
	gm.pending_rotation_changed.connect(_on_pending_rotation_changed)
	gm.bot_mode_changed.connect(_on_bot_mode_changed)

	NetworkManager.peer_left.connect(_on_peer_left_ingame)
	NetworkManager.peer_joined.connect(_on_peer_rejoined_ingame)
	## A rejoin succeeds as either connected_to_host (guest) or peer_joined (host).
	NetworkManager.connected_to_host.connect(_on_peer_rejoined_ingame)
	NetworkManager.connection_failed.connect(_on_rejoin_failed_ingame)
	NetworkManager.opponent_username_received.connect(_on_opponent_username_received)
	gm.bot_difficulty_changed.connect(_on_difficulty_changed)

	## Bot controls (vs-Bot toggle + difficulty settings) are only offered in plain
	## local play — never in multiplayer, puzzles, or bot battles (where the
	## opponent is fixed). _pending_puzzle_sid covers the case where puzzle_mode
	## hasn't been applied yet (deferred init), active_bot_profile_id marks a bot
	## battle (set before the scene loaded).
	var show_bot_controls: bool = not NetworkManager.is_multiplayer \
		and not gm.puzzle_mode and gm._pending_puzzle_sid < 0 \
		and gm.active_bot_profile_id == ""

	## Bot toggle — hidden in multiplayer
	bot_toggle = Button.new()
	bot_toggle.text          = "vs Bot: OFF"
	bot_toggle.anchor_left   = 1.0; bot_toggle.anchor_top    = 1.0
	bot_toggle.anchor_right  = 1.0; bot_toggle.anchor_bottom = 1.0
	bot_toggle.offset_left   = -160.0; bot_toggle.offset_top    = -58.0
	bot_toggle.offset_right  =  -10.0; bot_toggle.offset_bottom = -10.0
	bot_toggle.grow_horizontal = Control.GROW_DIRECTION_BEGIN; bot_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bot_toggle)
	bot_toggle.pressed.connect(_on_bot_toggle_pressed)
	bot_toggle.visible = show_bot_controls

	## Bot assignment popup — opened by bot_toggle. Two independent checkboxes:
	## checking only one assigns the bot to that seat; checking both is
	## bot-vs-bot (used to compare bot models — runs slower, expected).
	_bot_popup = _build_bot_popup()
	_bot_popup.visible = false
	add_child(_bot_popup)

	## Reconnect status label (MP only, shown on peer_left)
	_reconnect_label = Label.new()
	_reconnect_label.anchor_left  = 0.5; _reconnect_label.anchor_right  = 0.5
	_reconnect_label.anchor_top   = 0.0; _reconnect_label.anchor_bottom = 0.0
	_reconnect_label.offset_left  = -200.0; _reconnect_label.offset_right  = 200.0
	_reconnect_label.offset_top   =   48.0; _reconnect_label.offset_bottom =  74.0
	_reconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reconnect_label.add_theme_font_size_override("font_size", 13)
	_reconnect_label.visible = false
	add_child(_reconnect_label)

	## In-game Rejoin button (MP only, shown on disconnect / connection error)
	_rejoin_btn = Button.new()
	_rejoin_btn.text = "↩ Rejoin Game"
	_rejoin_btn.anchor_left  = 0.5; _rejoin_btn.anchor_right  = 0.5
	_rejoin_btn.anchor_top   = 0.0; _rejoin_btn.anchor_bottom = 0.0
	_rejoin_btn.offset_left  = -90.0; _rejoin_btn.offset_right  = 90.0
	_rejoin_btn.offset_top   =  80.0; _rejoin_btn.offset_bottom = 116.0
	_rejoin_btn.add_theme_font_size_override("font_size", 14)
	_rejoin_btn.visible = false
	_rejoin_btn.pressed.connect(_on_rejoin_pressed)
	add_child(_rejoin_btn)

	## Forfeit (✕) — abandon the match for a fresh game; opponent is declared winner.
	_forfeit_btn = Button.new()
	_forfeit_btn.text = "✕"
	_forfeit_btn.anchor_left  = 0.5; _forfeit_btn.anchor_right  = 0.5
	_forfeit_btn.anchor_top   = 0.0; _forfeit_btn.anchor_bottom = 0.0
	_forfeit_btn.offset_left  = 96.0; _forfeit_btn.offset_right  = 132.0
	_forfeit_btn.offset_top   = 80.0; _forfeit_btn.offset_bottom = 116.0
	_forfeit_btn.add_theme_font_size_override("font_size", 16)
	_forfeit_btn.tooltip_text = "Give up rejoining and start fresh (opponent wins)"
	_forfeit_btn.visible = false
	_forfeit_btn.pressed.connect(_on_forfeit_pressed)
	add_child(_forfeit_btn)

	## ── Bot difficulty settings icon + panel (solo/bot mode only) ──────────
	_difficulty_panel = _build_difficulty_panel()
	_difficulty_panel.visible = false
	add_child(_difficulty_panel)

	var settings_icon := TextureButton.new()
	var icon_tex := load("res://assets/Settingsicon.png") as Texture2D
	if icon_tex:
		settings_icon.texture_normal = icon_tex
	settings_icon.custom_minimum_size = Vector2(29, 29)   ## original 36 × 0.8
	settings_icon.ignore_texture_size = true
	settings_icon.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	settings_icon.anchor_left   = 0.0; settings_icon.anchor_top    = 0.0
	settings_icon.anchor_right  = 0.0; settings_icon.anchor_bottom = 0.0
	## Sit immediately to the right of the username label (no overlap).
	settings_icon.offset_left   = 156.0 + side_inset; settings_icon.offset_top    = 6.0 + top_inset
	settings_icon.offset_right  = 185.0 + side_inset; settings_icon.offset_bottom = 35.0 + top_inset
	settings_icon.visible = show_bot_controls
	## Hover glow
	settings_icon.mouse_entered.connect(func():
		settings_icon.modulate = Color(1.6, 1.4, 0.5))
	settings_icon.mouse_exited.connect(func():
		settings_icon.modulate = Color(1.0, 1.0, 1.0))
	settings_icon.pressed.connect(func():
		settings_icon.modulate = Color(1.0, 1.0, 1.0)
		_difficulty_panel.visible = not _difficulty_panel.visible)
	add_child(settings_icon)

	## Menu button
	var menu_btn := Button.new()
	menu_btn.text = "⬅ Menu"
	menu_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_btn.offset_left   = -110.0 - side_inset; menu_btn.offset_top    =  8.0 + top_inset
	menu_btn.offset_right  =   -8.0 - side_inset; menu_btn.offset_bottom = 38.0 + top_inset
	menu_btn.pressed.connect(_on_menu_pressed)
	add_child(menu_btn)

	## Victory popup (New Game / Return to Menu / X close)
	_build_win_popup()

	## Replay pause/play bar (hidden until a replay starts).
	_build_replay_controls()

	## "Bot is thinking" spinner (hidden until show_bot_thinking()).
	_build_bot_thinking_icon()

	## Live "total game time" HUD (Round 13, item 1.5).
	_build_game_timer_label()

	## Large top-center timer for puzzle mode.
	_build_puzzle_timer_label()

	## Bump every font size 15% and every button 20% bigger on mobile (touch) devices.
	if _is_mobile():
		_apply_mobile_font_scale(self, MOBILE_FONT_SCALE)
		_apply_mobile_button_scale(self, MOBILE_BUTTON_SCALE)

# ---------------------------------------------------------------------------
# Victory popup
# ---------------------------------------------------------------------------
func _build_win_popup() -> void:
	## Make the win screen a full-screen modal layer. The layer itself no
	## longer eats clicks — only whichever of _win_backdrop/_win_panel (open
	## state) or _win_minimized_btn (minimized state) is visible does, so the
	## board stays interactive while minimized.
	win_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_screen.offset_left = 0; win_screen.offset_top = 0
	win_screen.offset_right = 0; win_screen.offset_bottom = 0
	win_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Dim backdrop
	_win_backdrop = ColorRect.new()
	_win_backdrop.color = Color(0, 0, 0, 0.55)
	_win_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP   ## eat clicks behind it
	win_screen.add_child(_win_backdrop)
	win_screen.move_child(_win_backdrop, 0)

	## Centered popup panel
	_win_panel = Panel.new()
	_win_panel.anchor_left = 0.5; _win_panel.anchor_top = 0.5
	_win_panel.anchor_right = 0.5; _win_panel.anchor_bottom = 0.5
	_win_panel.offset_left = -220.0; _win_panel.offset_top = -170.0
	_win_panel.offset_right = 220.0; _win_panel.offset_bottom = 215.0
	_win_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	## Round 13 (item 2) — "matching blue with gold trim": a deep royal-blue
	## panel (echoing p1_color) with a thick gold border + soft gold glow.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.16, 0.38, 0.97)
	style.set_corner_radius_all(16)
	style.border_color = WIN_GOLD
	style.set_border_width_all(3)
	style.shadow_color = Color(WIN_GOLD.r, WIN_GOLD.g, WIN_GOLD.b, 0.30)
	style.shadow_size = 8
	_win_panel.add_theme_stylebox_override("panel", style)
	win_screen.add_child(_win_panel)

	## X close button (top-right of the panel) — minimizes the popup rather
	## than dismissing it entirely (see _on_win_close).
	var x_btn := Button.new()
	x_btn.text = "✕"
	x_btn.anchor_left = 1.0; x_btn.anchor_right = 1.0
	x_btn.offset_left = -46.0; x_btn.offset_top = 8.0
	x_btn.offset_right = -8.0;  x_btn.offset_bottom = 42.0
	x_btn.add_theme_font_size_override("font_size", 18)
	x_btn.pressed.connect(_on_win_close)
	_style_gold_button(x_btn)
	_win_panel.add_child(x_btn)

	## Hide the scene's stray win label; use a fresh centered title.
	win_label.visible = false
	_win_title = Label.new()
	_win_title.text = "Victory!"
	_win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_win_title.anchor_left = 0.0; _win_title.anchor_right = 1.0
	_win_title.offset_left = 16.0; _win_title.offset_right = -16.0
	_win_title.offset_top = 44.0; _win_title.offset_bottom = 94.0
	_win_title.add_theme_font_size_override("font_size", 32)
	_win_title.add_theme_color_override("font_color", WIN_GOLD)
	_win_title.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.20))
	_win_title.add_theme_constant_override("outline_size", 5)
	_win_panel.add_child(_win_title)

	## Sub-title — winner + flavor text + total match time (item 1.5/2).
	## Filled in by _on_game_over via GameManager.get_elapsed_time_str().
	_win_subtitle = Label.new()
	_win_subtitle.text = ""
	_win_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	_win_subtitle.anchor_left = 0.0; _win_subtitle.anchor_right = 1.0
	_win_subtitle.offset_left = 16.0; _win_subtitle.offset_right = -16.0
	_win_subtitle.offset_top = 100.0; _win_subtitle.offset_bottom = 218.0
	_win_subtitle.add_theme_font_size_override("font_size", 16)
	_win_subtitle.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	_win_panel.add_child(_win_subtitle)

	## Action buttons (New Game / Return to Menu)
	var new_btn := Button.new()
	new_btn.text = "New Game"
	new_btn.anchor_left = 0.5; new_btn.anchor_right = 0.5
	new_btn.anchor_top = 1.0;  new_btn.anchor_bottom = 1.0
	new_btn.offset_left = -180.0; new_btn.offset_right = -8.0
	new_btn.offset_top = -86.0;   new_btn.offset_bottom = -46.0
	new_btn.add_theme_font_size_override("font_size", 16)
	new_btn.pressed.connect(_on_new_game_pressed)
	_style_gold_button(new_btn)
	_win_panel.add_child(new_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Return to Menu"
	menu_btn.anchor_left = 0.5; menu_btn.anchor_right = 0.5
	menu_btn.anchor_top = 1.0;  menu_btn.anchor_bottom = 1.0
	menu_btn.offset_left = 8.0;  menu_btn.offset_right = 180.0
	menu_btn.offset_top = -86.0; menu_btn.offset_bottom = -46.0
	menu_btn.add_theme_font_size_override("font_size", 16)
	menu_btn.pressed.connect(_on_menu_pressed)
	_style_gold_button(menu_btn)
	_win_panel.add_child(menu_btn)
	_win_menu_btn = menu_btn

	## Second row: Undo Last Turn (left) + Replay Game (right)
	var undo_btn := Button.new()
	undo_btn.text = "↩ Undo Turn"
	undo_btn.anchor_left = 0.5; undo_btn.anchor_right = 0.5
	undo_btn.anchor_top = 1.0;  undo_btn.anchor_bottom = 1.0
	undo_btn.offset_left = -180.0; undo_btn.offset_right = -8.0
	undo_btn.offset_top = -42.0;   undo_btn.offset_bottom = -8.0
	undo_btn.add_theme_font_size_override("font_size", 14)
	undo_btn.pressed.connect(_on_undo_pressed)
	undo_btn.visible = not NetworkManager.is_multiplayer
	_style_gold_button(undo_btn)
	_win_panel.add_child(undo_btn)
	_win_undo_btn = undo_btn

	var replay_btn := Button.new()
	replay_btn.text = "▶ Replay"
	replay_btn.anchor_left = 0.5; replay_btn.anchor_right = 0.5
	replay_btn.anchor_top = 1.0;  replay_btn.anchor_bottom = 1.0
	replay_btn.offset_left = 8.0;  replay_btn.offset_right = 180.0
	replay_btn.offset_top = -42.0; replay_btn.offset_bottom = -8.0
	replay_btn.add_theme_font_size_override("font_size", 14)
	replay_btn.pressed.connect(_on_replay_pressed)
	_style_gold_button(replay_btn)
	_win_panel.add_child(replay_btn)

	## Timer that steps through board states during replay.
	_replay_timer = Timer.new()
	_replay_timer.wait_time = 0.9
	_replay_timer.autostart = false
	_replay_timer.timeout.connect(_step_replay)
	add_child(_replay_timer)

	## Minimized indicator — shown instead of the full popup after the X is
	## tapped. Same width/right-alignment as DicePanel, sitting in the empty
	## space just below it. Tapping it restores the New Game / Return to Menu
	## popup (_on_win_restore).
	_win_minimized_btn = Button.new()
	_win_minimized_btn.text = "🏆 Game Over\n(tap to view)"
	_win_minimized_btn.anchor_left = 1.0; _win_minimized_btn.anchor_right = 1.0
	_win_minimized_btn.anchor_top = 0.0;  _win_minimized_btn.anchor_bottom = 0.0
	_win_minimized_btn.offset_left = -204.0; _win_minimized_btn.offset_right = -1.0
	_win_minimized_btn.offset_top = 218.0;   _win_minimized_btn.offset_bottom = 330.0
	_win_minimized_btn.add_theme_font_size_override("font_size", 14)
	_win_minimized_btn.visible = false
	_win_minimized_btn.pressed.connect(_on_win_restore)
	_style_gold_button(_win_minimized_btn)
	win_screen.add_child(_win_minimized_btn)

## Round 13 (item 2) — shared "matching blue with gold trim" button skin for
## every button on/around the victory popup (X close, New Game, Return to
## Menu, minimized indicator): deep-blue fill with a gold border in the normal
## state, brightening on hover/press, gold-tinted text throughout.
func _style_gold_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.24, 0.50, 1.0)
	normal.border_color = Color(WIN_GOLD.r, WIN_GOLD.g, WIN_GOLD.b, 0.85)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.19, 0.33, 0.64, 1.0)
	hover.border_color = WIN_GOLD

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.07, 0.13, 0.28, 1.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78))
	btn.add_theme_color_override("font_hover_color", WIN_GOLD)
	btn.add_theme_color_override("font_pressed_color", WIN_GOLD)

## ── Replay controls bar ──────────────────────────────────────────────────────

func _build_replay_controls() -> void:
	_replay_panel = PanelContainer.new()
	_replay_panel.anchor_left   = 0.5;  _replay_panel.anchor_right  = 0.5
	_replay_panel.anchor_top    = 1.0;  _replay_panel.anchor_bottom = 1.0
	_replay_panel.offset_left   = -160.0; _replay_panel.offset_right  = 160.0
	_replay_panel.offset_top    = -70.0;  _replay_panel.offset_bottom = -10.0
	_replay_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.16, 0.38, 0.92)
	style.set_corner_radius_all(10)
	style.border_color = WIN_GOLD
	style.set_border_width_all(2)
	_replay_panel.add_theme_stylebox_override("panel", style)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	_replay_panel.add_child(hbox)

	var restart_btn := Button.new()
	restart_btn.text = "⏮"
	restart_btn.add_theme_font_size_override("font_size", 18)
	restart_btn.pressed.connect(_restart_replay)
	_style_gold_button(restart_btn)
	hbox.add_child(restart_btn)

	_replay_play_btn = Button.new()
	_replay_play_btn.text = "⏸ Pause"
	_replay_play_btn.add_theme_font_size_override("font_size", 14)
	_replay_play_btn.pressed.connect(_toggle_replay_pause)
	_style_gold_button(_replay_play_btn)
	hbox.add_child(_replay_play_btn)

	_replay_turn_label = Label.new()
	_replay_turn_label.add_theme_font_size_override("font_size", 13)
	_replay_turn_label.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	hbox.add_child(_replay_turn_label)

	add_child(_replay_panel)

## ── Undo / Replay button handlers ────────────────────────────────────────────

func _on_undo_pressed() -> void:
	if GameManager.puzzle_mode:
		win_screen.visible = false
		_win_minimized_btn.visible = false
		GameManager.restart_puzzle()
		return
	if not GameManager.undo_last_turn(): return
	win_screen.visible = false
	if _game_timer_label != null:
		_game_timer_label.visible = true

func _on_replay_pressed() -> void:
	_game_states_cache = GameManager.get_game_states().duplicate()
	if _game_states_cache.size() < 2: return
	_replay_index = 0
	_replay_paused = false
	_apply_replay_step()
	_replay_turn_label.text = _replay_turn_text()
	_replay_play_btn.text = "⏸ Pause"
	_replay_panel.visible = true
	## Minimize win popup so the board is visible but still accessible.
	_on_win_close()
	_replay_timer.start()

func _step_replay() -> void:
	_replay_index += 1
	if _replay_index >= _game_states_cache.size():
		_replay_timer.stop()
		_replay_panel.visible = false
		_on_win_restore()
		return
	_apply_replay_step()
	_replay_turn_label.text = _replay_turn_text()

func _apply_replay_step() -> void:
	var board = get_node_or_null("/root/Main/HexBoard")
	if board == null: return
	var entry: Dictionary = _game_states_cache[_replay_index]
	board.apply_state(entry["board"])

func _toggle_replay_pause() -> void:
	_replay_paused = not _replay_paused
	if _replay_paused:
		_replay_timer.stop()
		_replay_play_btn.text = "▶ Play"
	else:
		_replay_timer.start()
		_replay_play_btn.text = "⏸ Pause"

func _restart_replay() -> void:
	_replay_timer.stop()
	_replay_index = 0
	_replay_paused = false
	_replay_play_btn.text = "⏸ Pause"
	_apply_replay_step()
	_replay_turn_label.text = _replay_turn_text()
	_replay_timer.start()

func _replay_turn_text() -> String:
	## Don't count the final game-over snapshot as a "turn".
	var total: int = max(0, _game_states_cache.size() - 1)
	return "Turn %d / %d" % [_replay_index, total]

## Whether a modal popup (victory screen or bot-difficulty panel) is open --
## used by CameraController to suppress camera pan/rotate/zoom input while
## one of these is covering the board.
func is_modal_popup_open() -> bool:
	return (_win_panel != null and _win_panel.visible and win_screen.visible) \
		or (_difficulty_panel != null and _difficulty_panel.visible) \
		or (_bot_popup != null and _bot_popup.visible)

func _on_win_close() -> void:
	## Minimize instead of fully dismissing — tap the indicator (bottom-right
	## of DicePanel) to bring the New Game / Return to Menu popup back.
	_win_backdrop.visible = false
	_win_panel.visible = false
	_win_minimized_btn.visible = true

func _on_win_restore() -> void:
	_win_backdrop.visible = true
	_win_panel.visible = true
	_win_minimized_btn.visible = false

func _on_new_game_pressed() -> void:
	win_screen.visible = false
	_win_minimized_btn.visible = false
	if GameManager.puzzle_mode:
		## Regenerate a new puzzle with the same chosen drone.
		GameManager.start_puzzle(GameManager.puzzle_chosen_sid)
		return
	_win_backdrop.visible = true
	_win_panel.visible = true
	if NetworkManager.is_multiplayer:
		## A fresh online game needs a new handshake — go back to the menu.
		_on_menu_pressed()
	else:
		get_tree().reload_current_scene()

func _on_rejoin_pressed() -> void:
	_reconnect_label.text    = "Rejoining game…"
	_reconnect_label.visible = true
	_rejoin_btn.visible      = false
	NetworkManager.rejoin()

# ---------------------------------------------------------------------------
# Mobile text scaling
# ---------------------------------------------------------------------------
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
## (skips buttons with no minimum size set, so incidental zero-size buttons
## used purely for hit-testing aren't affected).
func _apply_mobile_button_scale(node: Node, factor: float) -> void:
	if node is BaseButton:
		var b := node as Control
		if b.custom_minimum_size != Vector2.ZERO:
			b.custom_minimum_size *= factor
	for child in node.get_children():
		_apply_mobile_button_scale(child, factor)

# ---------------------------------------------------------------------------
# Player name helpers
# ---------------------------------------------------------------------------
func _player_name(player: int) -> String:
	if NetworkManager.is_multiplayer:
		return AccountManager.username if player == GameManager.mp_player \
			else NetworkManager.opponent_username
	if GameManager.p1_is_bot or GameManager.p2_is_bot:
		if not GameManager._is_bot(player):
			return AccountManager.username
		if GameManager.p1_is_bot and GameManager.p2_is_bot:
			## Bot-vs-bot — show each side's difficulty so the two can be told apart.
			var labels := ["Easy", "Medium", "Hard", "Extra Hard"]
			var diff: int = GameManager.p1_bot_difficulty if player == 1 else GameManager.p2_bot_difficulty
			return "Bot (%s)" % labels[diff]
		return "Bot"
	return "Player %d" % player

# ---------------------------------------------------------------------------
# Show helpers
# ---------------------------------------------------------------------------
func show_roll_prompt(_player: int) -> void:
	roll_button.visible  = true
	rotate_panel.visible = false

func show_movement_prompt(_points: int) -> void:
	roll_button.visible  = false
	rotate_panel.visible = true

func show_piece_selected(_source_id: int) -> void:
	pass   ## piece-selection feedback is shown via board highlights

func show_message(_msg: String) -> void:
	pass   ## top-left text area removed

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------
func _on_state_changed(state: int) -> void:
	match state:
		3, 4:
			roll_button.visible  = false
			rotate_panel.visible = false

func _on_turn_changed(_player: int) -> void:
	turn_label.text = AccountManager.username

func _on_dice_rolled(die_a: int, die_b: int, total: int) -> void:
	## Dice settled — stop the roll animation and show the rolled faces.
	_dice_rolling = false
	if _die_a_tex != null and die_a >= 1 and die_a <= 5:
		_die_a_tex.texture = _die_textures[die_a - 1]
	if _die_b_tex != null and die_b >= 1 and die_b <= 5:
		_die_b_tex.texture = _die_textures[die_b - 1]
	die_total_label.text = "  Total: %d" % total

func _on_movement_spent(points_remaining: int) -> void:
	var gm := get_node("/root/GameManager")
	var p1_xh: bool = gm.p1_is_bot and gm.p1_bot_difficulty == 3
	var p2_xh: bool = gm.p2_is_bot and gm.p2_bot_difficulty == 3
	if p1_xh or p2_xh: return
	die_total_label.text = "  Total: %d" % points_remaining

# ---------------------------------------------------------------------------
# Dice face images + roll animation
# ---------------------------------------------------------------------------
func _build_dice_images() -> void:
	for i in range(1, 6):
		_die_textures.append(load("res://assets/BlankHexDie%d.png" % i))
	## Replace the A/B text labels with face images in the dice panel HBox.
	die1_label.visible = false
	die2_label.visible = false
	var hbox: Node = die_total_label.get_parent()
	_die_a_tex = _make_die_rect()
	_die_b_tex = _make_die_rect()
	hbox.add_child(_die_a_tex); hbox.move_child(_die_a_tex, 0)
	hbox.add_child(_die_b_tex); hbox.move_child(_die_b_tex, 1)

func _make_die_rect() -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = Vector2(46, 46)
	r.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not _die_textures.is_empty():
		r.texture = _die_textures[0]
	return r

func _on_roll_started() -> void:
	_dice_rolling    = true
	_dice_anim_accum = 0.0
	die_total_label.text = "  Total: —"

# ---------------------------------------------------------------------------
# "Bot is thinking" indicator (round 11)
# ---------------------------------------------------------------------------
func _build_bot_thinking_icon() -> void:
	for i in [3, 2, 1, 0]:
		_thinking_frames.append(load("res://assets/BotThinkingAnim/ThinkingHexGlass%d.png" % i))

	_thinking_icon = TextureRect.new()
	_thinking_icon.custom_minimum_size = Vector2(64, 64)
	_thinking_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_thinking_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thinking_icon.pivot_offset = Vector2(32, 32)
	if not _thinking_frames.is_empty():
		_thinking_icon.texture = _thinking_frames[0]
	_thinking_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Top-center of the screen — clear of the username/settings cluster
	## (left) and the dice/roll/menu cluster (right).
	_thinking_icon.anchor_left   = 0.5; _thinking_icon.anchor_right  = 0.5
	_thinking_icon.anchor_top    = 0.0; _thinking_icon.anchor_bottom = 0.0
	_thinking_icon.offset_left   = -32.0; _thinking_icon.offset_right  = 32.0
	_thinking_icon.offset_top    =   8.0; _thinking_icon.offset_bottom = 72.0
	_thinking_icon.visible = false
	add_child(_thinking_icon)

	_thinking_label = Label.new()
	_thinking_label.text = "Bot is thinking…"
	_thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thinking_label.add_theme_font_size_override("font_size", 13)
	_thinking_label.anchor_left   = 0.5; _thinking_label.anchor_right  = 0.5
	_thinking_label.anchor_top    = 0.0; _thinking_label.anchor_bottom = 0.0
	_thinking_label.offset_left   = -90.0; _thinking_label.offset_right  = 90.0
	_thinking_label.offset_top    =  74.0; _thinking_label.offset_bottom = 96.0
	_thinking_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thinking_label.visible = false
	add_child(_thinking_label)

## Shown by GameManager._bot_act for the duration of evaluate_position().
func show_bot_thinking() -> void:
	_thinking_frame_idx  = 0
	_thinking_anim_accum = 0.0
	if not _thinking_frames.is_empty():
		_thinking_icon.texture = _thinking_frames[0]
	_thinking_icon.rotation_degrees = 0.0
	_thinking_icon.visible  = true
	_thinking_label.visible = true

func hide_bot_thinking() -> void:
	_thinking_icon.visible  = false
	_thinking_label.visible = false

# ---------------------------------------------------------------------------
# Live match timer (Round 13, item 1.5)
# ---------------------------------------------------------------------------
## Small "⏱ M:SS" readout, bottom-center, ticking once per second via
## _process (see _process). Hidden once the victory popup appears
## (_on_game_over) — the popup shows the frozen final time via
## GameManager.get_elapsed_time_str() instead.
func _build_game_timer_label() -> void:
	_game_timer_label = Label.new()
	_game_timer_label.text = "⏱ 0:00"
	_game_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_timer_label.add_theme_font_size_override("font_size", 14)
	_game_timer_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_game_timer_label.anchor_left = 0.5; _game_timer_label.anchor_right = 0.5
	_game_timer_label.anchor_top  = 1.0; _game_timer_label.anchor_bottom = 1.0
	_game_timer_label.offset_left  = -60.0; _game_timer_label.offset_right  = 60.0
	_game_timer_label.offset_top   = -28.0; _game_timer_label.offset_bottom =  -6.0
	_game_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game_timer_label)

func _build_puzzle_timer_label() -> void:
	_puzzle_timer_label = Label.new()
	_puzzle_timer_label.text = "0:00"
	_puzzle_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puzzle_timer_label.add_theme_font_size_override("font_size", 52)
	_puzzle_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	_puzzle_timer_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_puzzle_timer_label.add_theme_constant_override("shadow_offset_x", 2)
	_puzzle_timer_label.add_theme_constant_override("shadow_offset_y", 2)
	_puzzle_timer_label.anchor_left   = 0.5
	_puzzle_timer_label.anchor_right  = 0.5
	_puzzle_timer_label.anchor_top    = 0.0
	_puzzle_timer_label.anchor_bottom = 0.0
	_puzzle_timer_label.offset_left   = -120.0
	_puzzle_timer_label.offset_right  =  120.0
	_puzzle_timer_label.offset_top    =   10.0
	_puzzle_timer_label.offset_bottom =   72.0
	_puzzle_timer_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_puzzle_timer_label.visible       = false
	add_child(_puzzle_timer_label)

func _on_game_over(winner: int) -> void:
	if GameManager.simulation_mode: return
	win_screen.visible = true
	_win_backdrop.visible = true
	_win_panel.visible = true
	_win_minimized_btn.visible = false
	if _game_timer_label != null:
		_game_timer_label.visible = false
	var total_time := GameManager.get_elapsed_time_str()
	if GameManager.puzzle_mode:
		if winner == 1:
			if _win_title != null:   _win_title.text = "Puzzle Complete!"
			if _win_subtitle != null:
				_win_subtitle.text = "All enemies captured!\nTime: %s\n\nPlay Again for a new challenge." % total_time
		else:
			if _win_title != null:   _win_title.text = "Out of Moves!"
			if _win_subtitle != null:
				_win_subtitle.text = "Enemies still remain...\nPress Retry to replay this exact layout."
		## Swap bottom-row buttons to puzzle-specific actions.
		if _win_undo_btn != null:
			_win_undo_btn.text    = "Retry"
			_win_undo_btn.visible = true
			_style_gold_button(_win_undo_btn)
		if _win_menu_btn != null:
			_win_menu_btn.text = "Drone Choice"
			_style_gold_button(_win_menu_btn)
	else:
		var winner_name := _player_name(winner)
		if _win_title != null:   _win_title.text = "Victory!"
		if _win_subtitle != null:
			_win_subtitle.text = "%s Wins!\nAll enemy Hex-Drones destroyed.\nTotal Time: %s" % [winner_name, total_time]
		## Restore standard button labels/styles (in case a prior puzzle changed them).
		if _win_undo_btn != null:
			_win_undo_btn.text    = "↩ Undo Turn"
			_win_undo_btn.visible = not NetworkManager.is_multiplayer
			_style_gold_button(_win_undo_btn)
		if _win_menu_btn != null:
			_win_menu_btn.text = "Return to Menu"
			_style_gold_button(_win_menu_btn)

func _on_piece_selected(_coord: Vector2i) -> void:
	rotate_button.text = "Rotate +60° (preview: 0°)"

func _on_pending_rotation_changed(degrees: float) -> void:
	rotate_button.text = "Rotate +60° (preview: %d°)" % int(degrees)

func _on_bot_mode_changed(p1_bot: bool, p2_bot: bool) -> void:
	_p1_bot_check.set_pressed_no_signal(p1_bot)
	_p2_bot_check.set_pressed_no_signal(p2_bot)
	if p1_bot and p2_bot:
		bot_toggle.text = "vs Bot: P1+P2"
	elif p1_bot:
		bot_toggle.text = "vs Bot: ON (P1)"
	elif p2_bot:
		bot_toggle.text = "vs Bot: ON (P2)"
	else:
		bot_toggle.text = "vs Bot: OFF"

func _on_peer_left_ingame() -> void:
	if not NetworkManager.is_multiplayer: return
	if GameManager.current_state == 4: return   ## already game over
	## Whoever still holds an open socket is the player who "stayed".
	_i_stayed = NetworkManager.is_connected_to_relay()
	_rejoin_active   = true
	_rejoin_deadline = Time.get_unix_time_from_system() + REJOIN_WINDOW_SEC
	_reconnect_label.visible = true
	_rejoin_btn.visible      = not _i_stayed   ## only the dropped player rejoins
	_forfeit_btn.visible     = true
	set_process(true)

func _on_peer_rejoined_ingame() -> void:
	if not NetworkManager.is_multiplayer: return
	_end_rejoin_window()
	_reconnect_label.text    = "✓ Reconnected!"
	_reconnect_label.visible = true
	get_tree().create_timer(3.0).timeout.connect(
		func(): _reconnect_label.visible = false, CONNECT_ONE_SHOT)

func _on_rejoin_failed_ingame() -> void:
	if not NetworkManager.is_multiplayer: return
	if not _rejoin_active: return
	_reconnect_label.text = "⚠ Rejoin failed — retrying is possible until the timer ends."
	_rejoin_btn.visible   = not _i_stayed

func _process(delta: float) -> void:
	## "Bot is thinking" spinner: spin continuously, cycling frames
	## 3 -> 2 -> 1 -> 0 -> loop. `while` (not `if`) so a single long
	## computation chunk between Extra Hard's process_frame yields still
	## advances by the correct number of frames instead of falling behind.
	if _thinking_icon != null and _thinking_icon.visible:
		_thinking_icon.rotation_degrees = wrapf(_thinking_icon.rotation_degrees + THINKING_SPIN_SPEED * delta, 0.0, 360.0)
		_thinking_anim_accum += delta
		while _thinking_anim_accum >= THINKING_FRAME_SEC:
			_thinking_anim_accum -= THINKING_FRAME_SEC
			_thinking_frame_idx = (_thinking_frame_idx + 1) % _thinking_frames.size()
			_thinking_icon.texture = _thinking_frames[_thinking_frame_idx]

	## Live "total game time" HUD (Round 13, item 1.5) — re-stringify only when
	## the whole-second value actually changes.
	var elapsed_sec: int = int(GameManager.get_elapsed_seconds())
	var sec_changed: bool = (elapsed_sec != _game_timer_last_sec)
	if sec_changed:
		_game_timer_last_sec = elapsed_sec
	if _game_timer_label != null and _game_timer_label.visible and sec_changed:
		_game_timer_label.text = "⏱ " + GameManager.get_elapsed_time_str()

	## Large puzzle timer — visible only during puzzle mode, hidden on win screen.
	if _puzzle_timer_label != null:
		_puzzle_timer_label.visible = GameManager.puzzle_mode and not win_screen.visible
		if _puzzle_timer_label.visible and sec_changed:
			_puzzle_timer_label.text = GameManager.get_elapsed_time_str()

	## Dice roll animation — alternate face 1 and face 5 until the result lands.
	if _dice_rolling and _die_a_tex != null:
		_dice_anim_accum += delta
		if _dice_anim_accum >= 0.08:
			_dice_anim_accum = 0.0
			_dice_anim_flip = not _dice_anim_flip
			_die_a_tex.texture = _die_textures[0] if _dice_anim_flip else _die_textures[4]
			_die_b_tex.texture = _die_textures[4] if _dice_anim_flip else _die_textures[0]

	## 2-minute rejoin window countdown.
	if _rejoin_active:
		var rem: float = _rejoin_deadline - Time.get_unix_time_from_system()
		if rem <= 0.0:
			_on_rejoin_timeout()
		else:
			var mm: int = int(rem) / 60
			var ss: int = int(rem) % 60
			var who := "Opponent disconnected" if _i_stayed else "You disconnected"
			_reconnect_label.text = "%s — rejoin window %d:%02d" % [who, mm, ss]

func _end_rejoin_window() -> void:
	_rejoin_active       = false
	_rejoin_btn.visible  = false
	_forfeit_btn.visible = false

func _on_rejoin_timeout() -> void:
	_end_rejoin_window()
	if _i_stayed:
		## Opponent never came back → we win.
		_reconnect_label.text = "Opponent did not rejoin — you win!"
		GameManager.declare_local_winner()
	else:
		## We failed to rejoin in time → match forfeited, back to menu.
		_reconnect_label.text = "Rejoin window expired."
		GameManager.forfeit_match()
		_on_menu_pressed()

func _on_forfeit_pressed() -> void:
	## Abandon the match: opponent is declared the winner; we get a fresh start.
	_end_rejoin_window()
	GameManager.forfeit_match()
	_on_menu_pressed()

func _on_opponent_username_received(_uname: String) -> void:
	pass   ## turn label refreshes on next turn_changed signal

func _build_difficulty_panel() -> Panel:
	var panel := Panel.new()
	panel.anchor_left   = 0.0; panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left   = 196.0; panel.offset_top    = 41.0
	panel.offset_right  = 368.0; panel.offset_bottom = 271.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6; col.offset_top = 4
	col.offset_right = -6; col.offset_bottom = -4
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	## Two independent groups so bot-vs-bot can pit different difficulties
	## against each other (P1's setting only matters once "Bot plays P1" is
	## checked, same for P2 — see _build_bot_popup).
	_diff_buttons = [
		_build_difficulty_group(col, "P1 Bot", 1),
		_build_difficulty_group(col, "P2 Bot", 2),
	]

	_refresh_difficulty_buttons()
	return panel

func _build_difficulty_group(col: VBoxContainer, header_text: String, player: int) -> Array:
	var header := Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 13)
	col.add_child(header)

	var labels := ["Easy", "Medium", "Hard", "Extra Hard"]
	var buttons: Array = []
	for i in range(4):
		var btn := Button.new()
		btn.text = labels[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_set_difficulty.bind(player, i))
		col.add_child(btn)
		buttons.append(btn)
	return buttons

func _build_bot_popup() -> Panel:
	var panel := Panel.new()
	panel.anchor_left   = 1.0; panel.anchor_top    = 1.0
	panel.anchor_right  = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left   = -170.0; panel.offset_top    = -134.0
	panel.offset_right  =  -10.0; panel.offset_bottom =  -64.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN; panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6; col.offset_top = 4
	col.offset_right = -6; col.offset_bottom = -4
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	_p1_bot_check = CheckButton.new()
	_p1_bot_check.text = "Bot plays P1"
	_p1_bot_check.add_theme_font_size_override("font_size", 13)
	_p1_bot_check.toggled.connect(_on_bot_check_toggled.unbind(1))
	col.add_child(_p1_bot_check)

	_p2_bot_check = CheckButton.new()
	_p2_bot_check.text = "Bot plays P2"
	_p2_bot_check.add_theme_font_size_override("font_size", 13)
	_p2_bot_check.toggled.connect(_on_bot_check_toggled.unbind(1))
	col.add_child(_p2_bot_check)

	return panel

func _refresh_difficulty_buttons() -> void:
	var active_labels := ["★ Easy", "★ Medium", "★ Hard", "★ Extra Hard"]
	var normal_labels := ["Easy",   "Medium",   "Hard",   "Extra Hard"]
	var current := [GameManager.p1_bot_difficulty, GameManager.p2_bot_difficulty]
	for p in range(_diff_buttons.size()):
		for i in range(_diff_buttons[p].size()):
			_diff_buttons[p][i].text = active_labels[i] if i == current[p] else normal_labels[i]

func _on_set_difficulty(player: int, d: int) -> void:
	GameManager.set_bot_difficulty(player, d)

func _on_difficulty_changed(_player: int, _d: int) -> void:
	_refresh_difficulty_buttons()

func _on_roll_pressed()       -> void: get_node("/root/GameManager").roll_dice()
func _on_rotate_pressed()     -> void: get_node("/root/GameManager").preview_rotate_selected()
func _on_bot_toggle_pressed() -> void:
	_bot_popup.visible = not _bot_popup.visible

func _on_bot_check_toggled() -> void:
	get_node("/root/GameManager").set_bot_assignment(_p1_bot_check.button_pressed, _p2_bot_check.button_pressed)
## Android/mobile hardware back button — navigate back rather than quit
## (requires application/config/quit_on_go_back=false in project.godot).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST: return
	if _difficulty_panel != null and _difficulty_panel.visible:
		_difficulty_panel.visible = false
		return
	_on_menu_pressed()

func _on_menu_pressed() -> void:
	if GameManager.puzzle_mode:
		win_screen.visible = false
		_win_minimized_btn.visible = false
		GameManager.puzzle_mode = false
		GameManager.return_to_puzzle_panel = true
		NetworkManager.disconnect_all()
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return
	NetworkManager.disconnect_all()
	get_tree().change_scene_to_file("res://main_menu.tscn")
