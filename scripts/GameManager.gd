extends Node

## GameManager.gd

enum GameState { SETUP, ROLL_DICE, SPEND_MOVEMENT, CHECK_WIN, GAME_OVER }

signal state_changed(new_state: int)
signal turn_changed(player: int)
signal dice_rolled(die_a: int, die_b: int, total: int)
signal movement_spent(points_remaining: int)
signal piece_selected(coord: Vector2i)
signal pending_rotation_changed(degrees: float)
signal game_over(winner: int)
signal bot_mode_changed(p1_bot: bool, p2_bot: bool)
signal bot_difficulty_changed(player: int, difficulty: int)
signal piece_captured_for_screen_fx(board_pos: Vector2i, capturing_player: int)

var board:       Node2D
var dice_roller: Node
var ui_manager:  CanvasLayer

var current_state:   int = 0
var current_player:  int = 1
var movement_points: int = 0
var selected_coord:  Vector2i = Vector2i(-999, -999)
var pending_rotation: float = 0.0

## Round 35 — "A>rotate>A>rotate>A is 1 movement": the first time a piece
## rotates while staying on its current tile this turn costs 1 point as
## normal and is recorded here. Any FURTHER rotation of that SAME piece on
## that SAME tile (no hop in between) this turn is free. Cleared whenever
## that piece leaves this tile (move_selected_piece_to / _net_apply_move) and
## at the end of every turn (_end_turn).
var _rotation_credit_coord: Vector2i = Vector2i(-999, -999)
var _rotation_credit_sid:   int      = -1

## mp_player: 0 = solo (can move both), 1 = P1 device, 2 = P2 device
var mp_player:  int = 0
## p1_is_bot / p2_is_bot: which seat(s) are AI-controlled. Both true = bot-vs-bot
## (used to compare bot models/difficulties; runs slower since both sides run
## full _plan_turn searches — expected, not a bug).
var p1_is_bot: bool = false
var p2_is_bot: bool = false
## p1_bot_difficulty / p2_bot_difficulty: per-seat AI difficulty, set
## independently so bot-vs-bot can pit different difficulties against each
## other. 0 = Easy, 1 = Medium, 2 = Hard, 3 = Extra Hard
var p1_bot_difficulty: int = 1
var p2_bot_difficulty: int = 1

func _is_bot(player: int) -> bool:
	return p1_is_bot if player == 1 else p2_is_bot

func _current_bot_difficulty() -> int:
	return p1_bot_difficulty if current_player == 1 else p2_bot_difficulty

## Hard-bot playstyle strategies — selected each turn based on board state.
const STRATEGY_GRID     := 0   ## patient formation advance, all pieces supported
const STRATEGY_DIVE     := 1   ## one piece raids deep for 2+ captures
const STRATEGY_TRADE    := 2   ## bait sacrifice, then take the taker
const STRATEGY_ROTATION := 3   ## edge positioning for orientation advantage

## Revenge tracking — maps enemy source_id → number of bot pieces it captured
## during the human's last roll.  Snapshot at bot-turn start; +300 per capture (additive).
var _revenge_capture_counts: Dictionary = {}   ## filled while human moves

## Round 38 — "toggling vs-Bot mid-think". _bot_act sets this true for its
## entire duration (including any free-rotation continuation via
## _bot_act_inner's recursive self-call), so set_bot_assignment can tell the
## bot is actively computing/playing its turn. Changing
## p1_is_bot/p2_is_bot/mp_player out from under that crashes downstream move
## execution (the in-flight best["from"]/best["to"] gets resolved under a
## player assignment that no longer matches), so the assignment is deferred
## via _pending_bot_assignment and applied once _bot_act finishes.
var _bot_thinking:           bool = false
var _bot_thread:             Thread = null  ## Round 45: background search thread
## Empty = nothing pending. [p1_bot, p2_bot] = assignment to apply once
## _bot_act finishes.
var _pending_bot_assignment: Array = []

## ===========================================================================
## Bot turn-scoped state — reset at the start of each bot turn (see the
## reset block in _bot_act_inner's turn-start section, ~line 649).
## ===========================================================================
## Safety bound for _bot_act's free-rotation recursion (see "Handle
## Rotate-only" below) — guarantees the bot's turn always makes real progress
## even if the planner repeatedly proposes an already-credited rotation.
var _bot_free_rotation_chain_count: int = 0

var _bot_strategy: int = STRATEGY_GRID
## Strategy is chosen once per turn (start of turn) then locked for that turn.
var _bot_strategy_locked: bool = false

## Snapshot of _revenge_capture_counts (declared above) taken at the start of
## the bot's turn; +300 per capture (additive) while the bot is thinking.
var _bot_revenge_active: Dictionary = {}

## Movement-burn tracking — every square a bot piece VACATES this turn is stored
## here.  A non-capture move BACK onto any vacated square is a "movement burn"
## (−500).  This catches not just the immediate A→B→A retrace but longer
## oscillation cycles (A→B→C→A).  Cleared each turn and on any rotation
## (a rotated retrace is not an immediate burn, per spec).
var _bot_recent_squares: Array = []

## Dive tracking — source_id of the piece currently chaining captures (Medium).
## -1 means no active dive.
var _bot_diving_sid: int = -1

## Post-capture drift — set true when the bot took a piece, can't chain a second,
## and still has movement to spend.  While true, end-of-turn distance scores are
## polarized (negatives −100, positives +100) so the leftover repositioning is
## decisive.  Reset at turn start and whenever another capture is made.
var _bot_drift_amplify: bool = false
## The tile a bot piece just captured onto (the exposed forward piece).  During
## drift, leftover movement is rewarded for bringing a DIFFERENT piece into
## recapture range of this tile — defending the piece that just took.
var _bot_last_capture_tile: Vector2i = Vector2i(-999, -999)

func set_bot_difficulty(player: int, d: int) -> void:
	var clamped: int = clampi(d, 0, 3)
	if player == 1:
		p1_bot_difficulty = clamped
	else:
		p2_bot_difficulty = clamped
	bot_difficulty_changed.emit(player, clamped)

## Backup of the player's P2 customization, taken when a bot-battle profile is
## applied so it can be restored on return to the menu. Empty = nothing to revert.
var _bot_battle_backup: Dictionary = {}

## Apply a bot-battle profile to P2 in-memory only (no save to disk).
## Call this before change_scene_to_file so start_game() picks up the values.
## The player's own P2 customization is snapshotted first and restored by
## revert_bot_battle_profile() when they return to the menu.
func apply_bot_battle_profile(profile: Dictionary) -> void:
	## Snapshot the player's customization ONCE (guard against re-apply without a
	## revert in between, which would otherwise back up the bot's values).
	if _bot_battle_backup.is_empty():
		_bot_battle_backup = {
			"p2_color": p2_color, "p2_blade_color": p2_blade_color,
			"p2_drone_body": p2_drone_body, "p2_blade_variant": p2_blade_variant,
			"p2_glow_selected_inner": p2_glow_selected_inner, "p2_glow_selected_outer": p2_glow_selected_outer,
			"p2_glow_move_inner": p2_glow_move_inner, "p2_glow_move_outer": p2_glow_move_outer,
			"p2_glow_capture_inner": p2_glow_capture_inner, "p2_glow_capture_outer": p2_glow_capture_outer,
			"p2_screen_effect_id": p2_screen_effect_id, "p2_drive_effect_id": p2_drive_effect_id,
			"p2_destroy_drive_effect_id": p2_destroy_drive_effect_id, "p2_destroy_effect_id": p2_destroy_effect_id,
			"snd_move": SoundManager.p2_sound_idx, "snd_rotate": SoundManager.p2_rotate_sound_idx,
			"snd_destroy": SoundManager.p2_destroy_sound_idx, "snd_turn": SoundManager.p2_turn_sound_idx,
			"glow_effect": glow_effect, "glow_speed": glow_speed, "glow_opacity": glow_opacity,
			"p2_drive_anim_speed": p2_drive_anim_speed,
			"p2_destroy_drive_anim_speed": p2_destroy_drive_anim_speed,
			"p2_bot_difficulty": p2_bot_difficulty,
			"background": BackgroundManager.selected_id,
		}
	active_bot_profile_id = profile.get("id", "")
	p2_color              = profile.get("drone_color", p2_color)
	p2_blade_color        = profile.get("blade_color",  p2_blade_color)
	p2_drone_body         = profile.get("drone_body",   p2_drone_body)
	p2_blade_variant      = profile.get("blade_variant", p2_blade_variant)
	## Glow colours: a profile may set one glow_inner/outer for every state, or
	## override individual states (selected/move/capture) for finer control.
	var gi: Color = profile.get("glow_inner", p2_glow_selected_inner)
	var go: Color = profile.get("glow_outer", p2_glow_selected_outer)
	p2_glow_selected_inner = profile.get("glow_selected_inner", gi)
	p2_glow_selected_outer = profile.get("glow_selected_outer", go)
	p2_glow_move_inner     = profile.get("glow_move_inner",     gi)
	p2_glow_move_outer     = profile.get("glow_move_outer",     go)
	p2_glow_capture_inner  = profile.get("glow_capture_inner",  gi)
	p2_glow_capture_outer  = profile.get("glow_capture_outer",  go)
	p2_screen_effect_id   = profile.get("screen_fx",  p2_screen_effect_id)
	p2_drive_effect_id         = profile.get("drive_fx",         p2_drive_effect_id)
	p2_destroy_drive_effect_id = profile.get("destroy_drive_fx", p2_destroy_drive_effect_id)
	p2_destroy_effect_id  = profile.get("destroy_fx", p2_destroy_effect_id)
	SoundManager.p2_sound_idx         = profile.get("snd_move",    SoundManager.p2_sound_idx)
	SoundManager.p2_rotate_sound_idx  = profile.get("snd_rotate",  SoundManager.p2_rotate_sound_idx)
	SoundManager.p2_destroy_sound_idx = profile.get("snd_destroy", SoundManager.p2_destroy_sound_idx)
	SoundManager.p2_turn_sound_idx    = profile.get("snd_turn",    SoundManager.p2_turn_sound_idx)
	if profile.has("glow_effect"):  glow_effect  = profile["glow_effect"]
	if profile.has("glow_speed"):   glow_speed   = profile["glow_speed"]
	if profile.has("glow_opacity"): glow_opacity = profile["glow_opacity"]
	if profile.has("drive_speed"): p2_drive_anim_speed = profile["drive_speed"]
	if profile.has("destroy_drive_speed"): p2_destroy_drive_anim_speed = profile["destroy_drive_speed"]
	if profile.has("background"):  BackgroundManager.set_selected_no_save(profile["background"])
	set_bot_difficulty(2, profile.get("difficulty", 2))

## Restore the player's P2 customization saved by apply_bot_battle_profile and
## clear the active bot profile. No-op if no bot battle was active, so it is safe
## to call unconditionally on every menu load — this is what makes the bot-battle
## visuals temporary and survives the player leaving the game early.
func revert_bot_battle_profile() -> void:
	active_bot_profile_id = ""
	if _bot_battle_backup.is_empty():
		return
	var b: Dictionary = _bot_battle_backup
	p2_color                   = b["p2_color"]
	p2_blade_color             = b["p2_blade_color"]
	p2_drone_body              = b["p2_drone_body"]
	p2_blade_variant           = b["p2_blade_variant"]
	p2_glow_selected_inner     = b["p2_glow_selected_inner"]
	p2_glow_selected_outer     = b["p2_glow_selected_outer"]
	p2_glow_move_inner         = b["p2_glow_move_inner"]
	p2_glow_move_outer         = b["p2_glow_move_outer"]
	p2_glow_capture_inner      = b["p2_glow_capture_inner"]
	p2_glow_capture_outer      = b["p2_glow_capture_outer"]
	p2_screen_effect_id        = b["p2_screen_effect_id"]
	p2_drive_effect_id         = b["p2_drive_effect_id"]
	p2_destroy_drive_effect_id = b["p2_destroy_drive_effect_id"]
	p2_destroy_effect_id       = b["p2_destroy_effect_id"]
	SoundManager.p2_sound_idx         = b["snd_move"]
	SoundManager.p2_rotate_sound_idx  = b["snd_rotate"]
	SoundManager.p2_destroy_sound_idx = b["snd_destroy"]
	SoundManager.p2_turn_sound_idx    = b["snd_turn"]
	glow_effect       = b["glow_effect"]
	glow_speed        = b["glow_speed"]
	glow_opacity      = b.get("glow_opacity", glow_opacity)
	p2_drive_anim_speed = b.get("p2_drive_anim_speed", p2_drive_anim_speed)
	p2_destroy_drive_anim_speed = b.get("p2_destroy_drive_anim_speed", p2_destroy_drive_anim_speed)
	p2_bot_difficulty = b["p2_bot_difficulty"]
	BackgroundManager.set_selected_no_save(b["background"])
	_bot_battle_backup.clear()

var p1_color:       Color = Color(0.35, 0.65, 1.0)
var p1_blade_color: Color = Color(1.0,  1.0,  0.3)
var p2_color:       Color = Color(1.0,  0.55, 0.1)
var p2_blade_color: Color = Color(1.0,  0.9,  0.5)

## Active bot-battle profile ID — "" means standard local play bot.
## Set by MainMenu before scene change; BotDecisionTree reads it to pick a playstyle.
var active_bot_profile_id: String = ""

## Puzzle mode — set by start_puzzle(), cleared on a full new game.
var puzzle_mode:        bool = false
var puzzle_chosen_sid:  int  = 1
var puzzle_budget:      int  = 5   ## movement points for the current puzzle layout
## Set by MainMenu before scene change so _try_init_game_nodes knows to call
## start_puzzle instead of start_game.  Reset to -1 immediately after use.
var _pending_puzzle_sid: int = -1
## Set by UIManager's "Drone Choice" button so MainMenu._ready() opens the puzzle panel.
var return_to_puzzle_panel: bool = false

## Per-player highlight glow colors. Defaults match HexHighlight's @export values.
const GLOW_FILE    := "user://hex_glow_colors.cfg"
const GLOW_SECTION := "glow"
const DEFAULT_GLOW_SELECTED := Color(1.0, 0.9, 0.0, 1.0)
const DEFAULT_GLOW_MOVE     := Color(0.0, 0.8, 1.0, 1.0)
const DEFAULT_GLOW_CAPTURE  := Color(1.0, 0.2, 0.2, 1.0)
## Per-player, per-type inner/outer glow colors (gradient always blends inner→outer).
var p1_gradient_enabled:    bool  = true
var p1_glow_selected_inner: Color = Color(1.0, 0.9, 0.0, 1.0)
var p1_glow_selected_outer: Color = Color(1.0, 0.5, 0.0, 0.4)
var p1_glow_move_inner:     Color = Color(0.0, 0.8, 1.0, 1.0)
var p1_glow_move_outer:     Color = Color(0.0, 0.3, 0.8, 0.4)
var p1_glow_capture_inner:  Color = Color(1.0, 0.2, 0.2, 1.0)
var p1_glow_capture_outer:  Color = Color(0.8, 0.0, 0.0, 0.4)
var p2_gradient_enabled:    bool  = true
var p2_glow_selected_inner: Color = Color(1.0, 0.9, 0.0, 1.0)
var p2_glow_selected_outer: Color = Color(0.6, 0.0, 1.0, 0.4)
var p2_glow_move_inner:     Color = Color(0.0, 0.8, 1.0, 1.0)
var p2_glow_move_outer:     Color = Color(0.0, 0.3, 0.8, 0.4)
var p2_glow_capture_inner:  Color = Color(1.0, 0.2, 0.2, 1.0)
var p2_glow_capture_outer:  Color = Color(0.8, 0.0, 0.0, 0.4)
## Global glow display settings
var glow_opacity: float  = 1.0
var glow_speed:   float  = 1.0
var glow_effect:  String = "Pulse"

## Screen capture effect — index into CameraController's effect list.
## 0 = None, 1 = Shake H, 2 = Shake V, 3 = Oscillate, 5 = Flip CW,
## 6 = Flip CCW, 7 = Dramatic Zoom, 8 = Flash, 9 = Darken, 10 = Inversion.
## Set by SimulationRunner when running headless batch games.
## Skips win popup, win screen, and reduces bot timer delays to 0.
var simulation_mode: bool = false

const SCREEN_FX_FILE    := "user://screen_effects.cfg"
const SCREEN_FX_SECTION := "screen_fx"
var p1_screen_effect_id: int = 0
var p2_screen_effect_id: int = 0

## 1 = Snap, 2 = Fade, 3 = Zoom, 4 = Flash, 5 = Slide.
const DRIVE_FX_FILE    := "user://drive_effects.cfg"
const DRIVE_FX_SECTION := "drive_fx"
var p1_drive_effect_id:         int   = 1
var p2_drive_effect_id:         int   = 1
var p1_destroy_drive_effect_id: int   = 1
var p2_destroy_drive_effect_id: int   = 1
var p1_drive_anim_speed:        float = 0.3
var p2_drive_anim_speed:        float = 0.3
## Separate animation duration for the DESTROY drive (the capturing move), so a
## capture can glide/snap at a different speed than an ordinary move.
var p1_destroy_drive_anim_speed: float = 0.3
var p2_destroy_drive_anim_speed: float = 0.3

## 1=Explode 2=Implode 3=Pixilate 4=Split 5=Flash 6=Explode Flash 7=Implode Flash
const DESTROY_FX_FILE    := "user://destroy_effects.cfg"
const DESTROY_FX_SECTION := "destroy_fx"
var p1_destroy_effect_id: int = 1
var p2_destroy_effect_id: int = 1

## Window mode: 0 = Windowed, 1 = Borderless Windowed, 2 = Fullscreen.
const WINDOW_MODE_FILE    := "user://hex_window_mode.cfg"
const WINDOW_MODE_SECTION := "window"
var window_mode: int = 0

## Blade style variant — folder name inside assets/HexPieces/HexBlades/, per player.
## Persisted to user://hex_blade_variant.cfg so the choice survives sessions.
const BLADE_VARIANT_FILE    := "user://hex_blade_variant.cfg"
const BLADE_VARIANT_SECTION := "blade"
var p1_blade_variant: String = "HexBladesGlowy"
var p2_blade_variant: String = "HexBladesGlowy"

## Drone body variant — folder name inside assets/HexPieces/BlankHexDrones/, per player.
const DRONE_BODY_FILE    := "user://hex_drone_body.cfg"
const DRONE_BODY_SECTION := "drone_body"
var p1_drone_body: String = "DronesBlank"
var p2_drone_body: String = "DronesBlank"

## 12 drone body variant descriptors (order matches display in Drones tab).
const DRONE_BODY_FOLDERS: Array = [
	"DronesBlank", "DronesBlackRing", "DronesBlankBlackStar", "DronesBlankBlackWeb",
	"DronesBlankBlackX", "DronesBlankInnerTriangle", "DronesBlankReverseStar", "DronesBlankReverseWeb",
	"DronesBlankSquare", "DronesBlankTriangle", "DronesDoubleBlackRing", "DronesGradient",
	"DronesBlank6PointStar", "DronesBlank6PointStarHollow", "DronesBlankGear",
	"DronesBlankHeart", "DronesBlankHollow", "DronesBlankRing", "DronesBlankReverseGradient",
	"DronesMetallic", "DronesBlankRedSwirl", "DronesBlankSwirl", "DronesBlankPepperMint",
]
const DRONE_BODY_NAMES: Array = [
	"Blank", "Black Ring", "Black Star", "Black Web", "Black X", "Inner Triangle",
	"Reverse Star", "Reverse Web", "Square", "Triangle", "Double Ring", "Gradient",
	"6-Point Star", "6-Point Star Hollow", "Gear", "Heart", "Hollow", "Ring", "Reverse Gradient",
	"Metallic", "Red Swirl", "Swirl", "Peppermint",
]
const DRONE_BODY_FILES: Dictionary = {
	"DronesBlank":              ["Empty Hexy.png",              "Empty Hexyb.png"],
	"DronesBlackRing":          ["EmptyHexBlackRing.png",       "EmptyHexbBlackRing.png"],
	"DronesBlankBlackStar":     ["EmptyHexBlackStar.png",       "EmptyHexbBlackStar.png"],
	"DronesBlankBlackWeb":      ["EmptyHexBlackWeb.png",        "EmptyHexbBlackWeb.png"],
	"DronesBlankBlackX":        ["EmptyHexBlackX.png",          "EmptyHexbBlackX.png"],
	"DronesBlankInnerTriangle": ["EmptyHexInnerTriangle.png",   "EmptyHexbInnerTriangle.png"],
	"DronesBlankReverseStar":   ["EmptyHexReverseStar.png",     "EmptyHexbReverseStar.png"],
	"DronesBlankReverseWeb":    ["EmptyHexReverseWeb.png",      "EmptyHexbReverseWeb.png"],
	"DronesBlankSquare":        ["EmptyHexSquare.png",          "EmptyHexbSquare.png"],
	"DronesBlankTriangle":      ["EmptyHexTriangle.png",        "EmptyHexbTriangle.png"],
	"DronesDoubleBlackRing":    ["EmptyHexDoubleBlackRing.png", "EmptyHexbDoubleBlackRing.png"],
	"DronesGradient":           ["EmptyHexGradient.png",        "EmptyHexbGradient.png"],
	"DronesBlank6PointStar":       ["EmptyHex6PointStar.png",        "EmptyHexb6PointStar.png"],
	"DronesBlank6PointStarHollow": ["EmptyHexHollow6PointStar.png",  "EmptyHexbHollow6PointStar.png"],
	"DronesBlankGear":             ["EmptyHexGear.png",              "EmptyHexbGear.png"],
	"DronesBlankHeart":            ["EmptyHexHeart.png",             "EmptyHexbHeart.png"],
	"DronesBlankHollow":           ["EmptyHexHollow.png",            "EmptyHexbHollow.png"],
	"DronesBlankRing":             ["EmptyHexRing.png",              "EmptyHexbRing.png"],
	"DronesBlankReverseGradient":  ["EmptyHexReverseGradient.png",  "EmptyHexbReverseGradient.png"],
	"DronesMetallic":              ["EmptyHexMetallic.png",         "EmptyHexbMetallic.png"],
	"DronesBlankRedSwirl":         ["EmptyHexRedSwirl.png",         "EmptyHexbRedSwirl.png"],
	"DronesBlankSwirl":            ["EmptyHexSwirl.png",            "EmptyHexbSwirl.png"],
	"DronesBlankPepperMint":       ["EmptyHexPepperMint.png",       "EmptyHexbPepperMint.png"],
}

var _decision_tree: BotDecisionTree

# ── Rejoin / state-sync ──────────────────────────────────────────────────────
const REJOIN_STATE_FILE := "user://hex_rejoin_state.cfg"
const REJOIN_WINDOW_SEC: float = 120.0   ## 2-minute grace window
## "Authority timestamp" of our current board — advances on every applied move.
## The most-advanced (largest) timestamp wins when two clients resync on rejoin.
var _state_authority_ts: float = 0.0
## Round 30 — monotonically increasing counter, bumped alongside
## _state_authority_ts on every applied move/rotation. BotDecisionTree uses
## this (get_board_version) to tell whether its prewarmed geometry cache is
## still fresh for the current board, without relying on wall-clock precision.
var _board_version: int = 0
## Round 13 (item 1.5) — wall-clock start time of the current match
## (Time.get_unix_time_from_system()), set in start_game() and synced via
## _serialize_game_state/apply_synced_state so a rejoin/resync doesn't reset
## the match clock. Used by get_elapsed_time_str() for the win popup's total
## game time (item 2).
var _game_start_unix: float = 0.0
## Board state snapshots for Replay/Undo — index 0 = initial board (player=1),
## each subsequent entry = board at start of that player's turn, final entry
## has player=0 (game-over). Populated by start_game(), _end_turn(), and every
## game_over.emit site. Cleared on new game.
var _game_states: Array = []
## Set by the menu Rejoin button so the next game-scene init restores from disk.
var pending_rejoin: bool = false

func _ready() -> void:
	_load_window_mode()
	_load_blade_variant()
	_load_drone_bodies()
	_load_glow_colors()
	_load_screen_fx()
	_load_drive_fx()
	_load_destroy_fx()
	_load_board_tiles()
	_decision_tree = BotDecisionTree.new(self)
	get_tree().node_added.connect(_on_node_added_to_tree)
	get_tree().node_removed.connect(_on_node_removed_from_tree)
	## NetworkManager autoloads AFTER GameManager, so wire its signals deferred
	## (by the next idle frame every autoload singleton exists).
	call_deferred("_connect_net_signals")
	call_deferred("_try_init_game_nodes")

func _load_screen_fx() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SCREEN_FX_FILE) == OK:
		p1_screen_effect_id = cfg.get_value(SCREEN_FX_SECTION, "p1_effect_id", 0)
		p2_screen_effect_id = cfg.get_value(SCREEN_FX_SECTION, "p2_effect_id", 0)

func screen_effect_for(player: int) -> int:
	return p1_screen_effect_id if player == 1 else p2_screen_effect_id

func set_screen_effect(player: int, id: int) -> void:
	if player == 1:
		p1_screen_effect_id = id
	else:
		p2_screen_effect_id = id
	var cfg := ConfigFile.new()
	cfg.set_value(SCREEN_FX_SECTION, "p1_effect_id", p1_screen_effect_id)
	cfg.set_value(SCREEN_FX_SECTION, "p2_effect_id", p2_screen_effect_id)
	cfg.save(SCREEN_FX_FILE)

func _load_drive_fx() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DRIVE_FX_FILE) == OK:
		p1_drive_effect_id         = cfg.get_value(DRIVE_FX_SECTION, "p1_effect_id",          p1_drive_effect_id)
		p2_drive_effect_id         = cfg.get_value(DRIVE_FX_SECTION, "p2_effect_id",          p2_drive_effect_id)
		p1_destroy_drive_effect_id = cfg.get_value(DRIVE_FX_SECTION, "p1_destroy_drive_id",   p1_destroy_drive_effect_id)
		p2_destroy_drive_effect_id = cfg.get_value(DRIVE_FX_SECTION, "p2_destroy_drive_id",   p2_destroy_drive_effect_id)
		p1_drive_anim_speed        = cfg.get_value(DRIVE_FX_SECTION, "p1_anim_speed",         p1_drive_anim_speed)
		p2_drive_anim_speed        = cfg.get_value(DRIVE_FX_SECTION, "p2_anim_speed",         p2_drive_anim_speed)
		p1_destroy_drive_anim_speed = cfg.get_value(DRIVE_FX_SECTION, "p1_destroy_anim_speed", p1_destroy_drive_anim_speed)
		p2_destroy_drive_anim_speed = cfg.get_value(DRIVE_FX_SECTION, "p2_destroy_anim_speed", p2_destroy_drive_anim_speed)

func drive_effect_for(player: int) -> int:
	return p1_drive_effect_id if player == 1 else p2_drive_effect_id

func destroy_drive_effect_for(player: int) -> int:
	return p1_destroy_drive_effect_id if player == 1 else p2_destroy_drive_effect_id

func drive_speed_for(player: int) -> float:
	return p1_drive_anim_speed if player == 1 else p2_drive_anim_speed

func destroy_drive_speed_for(player: int) -> float:
	return p1_destroy_drive_anim_speed if player == 1 else p2_destroy_drive_anim_speed

func set_destroy_drive_speed(player: int, speed: float) -> void:
	if player == 1:
		p1_destroy_drive_anim_speed = clampf(speed, 0.0, 1.0)
	else:
		p2_destroy_drive_anim_speed = clampf(speed, 0.0, 1.0)
	_save_drive_fx()

func set_drive_effect(player: int, id: int, speed: float) -> void:
	if player == 1:
		p1_drive_effect_id  = id
		p1_drive_anim_speed = clampf(speed, 0.0, 1.0)
	else:
		p2_drive_effect_id  = id
		p2_drive_anim_speed = clampf(speed, 0.0, 1.0)
	_save_drive_fx()

func set_destroy_drive_effect(player: int, id: int) -> void:
	if player == 1: p1_destroy_drive_effect_id = id
	else:           p2_destroy_drive_effect_id = id
	_save_drive_fx()

func _save_drive_fx() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(DRIVE_FX_SECTION, "p1_effect_id",        p1_drive_effect_id)
	cfg.set_value(DRIVE_FX_SECTION, "p2_effect_id",        p2_drive_effect_id)
	cfg.set_value(DRIVE_FX_SECTION, "p1_destroy_drive_id", p1_destroy_drive_effect_id)
	cfg.set_value(DRIVE_FX_SECTION, "p2_destroy_drive_id", p2_destroy_drive_effect_id)
	cfg.set_value(DRIVE_FX_SECTION, "p1_anim_speed",       p1_drive_anim_speed)
	cfg.set_value(DRIVE_FX_SECTION, "p2_anim_speed",       p2_drive_anim_speed)
	cfg.set_value(DRIVE_FX_SECTION, "p1_destroy_anim_speed", p1_destroy_drive_anim_speed)
	cfg.set_value(DRIVE_FX_SECTION, "p2_destroy_anim_speed", p2_destroy_drive_anim_speed)
	cfg.save(DRIVE_FX_FILE)

func _load_destroy_fx() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DESTROY_FX_FILE) == OK:
		p1_destroy_effect_id = cfg.get_value(DESTROY_FX_SECTION, "p1_effect_id", p1_destroy_effect_id)
		p2_destroy_effect_id = cfg.get_value(DESTROY_FX_SECTION, "p2_effect_id", p2_destroy_effect_id)

func destroy_effect_for(player: int) -> int:
	return p1_destroy_effect_id if player == 1 else p2_destroy_effect_id

## A player's primary glow colour (used by the Pixilate B destroy effect).
func glow_color_for(player: int) -> Color:
	return p1_glow_selected_inner if player == 1 else p2_glow_selected_inner

func set_destroy_effect(player: int, id: int) -> void:
	if player == 1:
		p1_destroy_effect_id = id
	else:
		p2_destroy_effect_id = id
	var cfg := ConfigFile.new()
	cfg.set_value(DESTROY_FX_SECTION, "p1_effect_id", p1_destroy_effect_id)
	cfg.set_value(DESTROY_FX_SECTION, "p2_effect_id", p2_destroy_effect_id)
	cfg.save(DESTROY_FX_FILE)

func _load_window_mode() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WINDOW_MODE_FILE) == OK:
		window_mode = cfg.get_value(WINDOW_MODE_SECTION, "mode", 0)
	_apply_window_mode(window_mode)

func set_window_mode(mode: int) -> void:
	window_mode = mode
	var cfg := ConfigFile.new()
	cfg.set_value(WINDOW_MODE_SECTION, "mode", mode)
	cfg.save(WINDOW_MODE_FILE)
	_apply_window_mode(mode)

func _apply_window_mode(mode: int) -> void:
	match mode:
		1:  ## Borderless Windowed — remove decoration, then maximize
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		2:  ## Fullscreen
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:  ## Windowed (default)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			## Toggle between Fullscreen and the previous non-fullscreen mode.
			var next: int = 0 if window_mode == 2 else 2
			set_window_mode(next)

func _load_blade_variant() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BLADE_VARIANT_FILE) == OK:
		p1_blade_variant = cfg.get_value(BLADE_VARIANT_SECTION, "p1_variant", "HexBladesGlowy")
		p2_blade_variant = cfg.get_value(BLADE_VARIANT_SECTION, "p2_variant", "HexBladesGlowy")

func _load_drone_bodies() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DRONE_BODY_FILE) == OK:
		p1_drone_body = cfg.get_value(DRONE_BODY_SECTION, "p1_body", "DronesBlank")
		p2_drone_body = cfg.get_value(DRONE_BODY_SECTION, "p2_body", "DronesBlank")

func _load_glow_colors() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(GLOW_FILE) != OK: return
	p1_gradient_enabled    = bool(cfg.get_value(GLOW_SECTION, "p1_grad_en",       true))
	p1_glow_selected_inner = Color(cfg.get_value(GLOW_SECTION, "p1_sel_in",        Color(1.0,0.9,0.0,1.0)))
	p1_glow_selected_outer = Color(cfg.get_value(GLOW_SECTION, "p1_sel_out",       Color(1.0,0.5,0.0,0.4)))
	p1_glow_move_inner     = Color(cfg.get_value(GLOW_SECTION, "p1_mov_in",        Color(0.0,0.8,1.0,1.0)))
	p1_glow_move_outer     = Color(cfg.get_value(GLOW_SECTION, "p1_mov_out",       Color(0.0,0.3,0.8,0.4)))
	p1_glow_capture_inner  = Color(cfg.get_value(GLOW_SECTION, "p1_cap_in",        Color(1.0,0.2,0.2,1.0)))
	p1_glow_capture_outer  = Color(cfg.get_value(GLOW_SECTION, "p1_cap_out",       Color(0.8,0.0,0.0,0.4)))
	p2_gradient_enabled    = bool(cfg.get_value(GLOW_SECTION, "p2_grad_en",       true))
	p2_glow_selected_inner = Color(cfg.get_value(GLOW_SECTION, "p2_sel_in",        Color(1.0,0.9,0.0,1.0)))
	p2_glow_selected_outer = Color(cfg.get_value(GLOW_SECTION, "p2_sel_out",       Color(0.6,0.0,1.0,0.4)))
	p2_glow_move_inner     = Color(cfg.get_value(GLOW_SECTION, "p2_mov_in",        Color(0.0,0.8,1.0,1.0)))
	p2_glow_move_outer     = Color(cfg.get_value(GLOW_SECTION, "p2_mov_out",       Color(0.0,0.3,0.8,0.4)))
	p2_glow_capture_inner  = Color(cfg.get_value(GLOW_SECTION, "p2_cap_in",        Color(1.0,0.2,0.2,1.0)))
	p2_glow_capture_outer  = Color(cfg.get_value(GLOW_SECTION, "p2_cap_out",       Color(0.8,0.0,0.0,0.4)))
	glow_opacity           = float(cfg.get_value(GLOW_SECTION, "opacity",           1.0))
	glow_speed             = float(cfg.get_value(GLOW_SECTION, "speed",             1.0))
	glow_effect            = str(cfg.get_value(GLOW_SECTION,   "effect",            "Pulse"))

func _save_glow_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(GLOW_SECTION, "p1_grad_en",  p1_gradient_enabled)
	cfg.set_value(GLOW_SECTION, "p1_sel_in",   p1_glow_selected_inner)
	cfg.set_value(GLOW_SECTION, "p1_sel_out",  p1_glow_selected_outer)
	cfg.set_value(GLOW_SECTION, "p1_mov_in",   p1_glow_move_inner)
	cfg.set_value(GLOW_SECTION, "p1_mov_out",  p1_glow_move_outer)
	cfg.set_value(GLOW_SECTION, "p1_cap_in",   p1_glow_capture_inner)
	cfg.set_value(GLOW_SECTION, "p1_cap_out",  p1_glow_capture_outer)
	cfg.set_value(GLOW_SECTION, "p2_grad_en",  p2_gradient_enabled)
	cfg.set_value(GLOW_SECTION, "p2_sel_in",   p2_glow_selected_inner)
	cfg.set_value(GLOW_SECTION, "p2_sel_out",  p2_glow_selected_outer)
	cfg.set_value(GLOW_SECTION, "p2_mov_in",   p2_glow_move_inner)
	cfg.set_value(GLOW_SECTION, "p2_mov_out",  p2_glow_move_outer)
	cfg.set_value(GLOW_SECTION, "p2_cap_in",   p2_glow_capture_inner)
	cfg.set_value(GLOW_SECTION, "p2_cap_out",  p2_glow_capture_outer)
	cfg.set_value(GLOW_SECTION, "opacity",     glow_opacity)
	cfg.set_value(GLOW_SECTION, "speed",       glow_speed)
	cfg.set_value(GLOW_SECTION, "effect",      glow_effect)
	cfg.save(GLOW_FILE)

func set_glow_colors(player: int, type: String, inner: Color, outer: Color) -> void:
	if player == 1:
		match type:
			"selected": p1_glow_selected_inner = inner; p1_glow_selected_outer = outer
			"move":     p1_glow_move_inner     = inner; p1_glow_move_outer     = outer
			"capture":  p1_glow_capture_inner  = inner; p1_glow_capture_outer  = outer
	else:
		match type:
			"selected": p2_glow_selected_inner = inner; p2_glow_selected_outer = outer
			"move":     p2_glow_move_inner     = inner; p2_glow_move_outer     = outer
			"capture":  p2_glow_capture_inner  = inner; p2_glow_capture_outer  = outer
	_save_glow_config()
	_push_glow_settings_to_highlight()

func set_glow_gradient_enabled(player: int, enabled: bool) -> void:
	if player == 1: p1_gradient_enabled = enabled
	else:           p2_gradient_enabled = enabled
	_save_glow_config()
	_push_glow_settings_to_highlight()

func set_glow_opacity(val: float) -> void:
	glow_opacity = clampf(val, 0.0, 1.0)
	_save_glow_config()
	_push_glow_settings_to_highlight()

func set_glow_speed(val: float) -> void:
	glow_speed = clampf(val, 0.1, 5.0)
	_save_glow_config()
	_push_glow_settings_to_highlight()

func set_glow_effect(eff: String) -> void:
	glow_effect = eff
	_save_glow_config()
	_push_glow_settings_to_highlight()

func _push_glow_settings_to_highlight() -> void:
	if board == null: return
	var h: Node2D = board.get_node_or_null("HexHighlight") as Node2D
	if h == null: return
	apply_glow_to_highlight(h, current_player)

func apply_glow_to_highlight(highlight: Node2D, player: int) -> void:
	var p1 := (player == 1)
	highlight.callv("apply_glow_settings", [
		p1_glow_selected_inner if p1 else p2_glow_selected_inner,
		p1_glow_selected_outer if p1 else p2_glow_selected_outer,
		p1_glow_move_inner     if p1 else p2_glow_move_inner,
		p1_glow_move_outer     if p1 else p2_glow_move_outer,
		p1_glow_capture_inner  if p1 else p2_glow_capture_inner,
		p1_glow_capture_outer  if p1 else p2_glow_capture_outer,
		p1_gradient_enabled    if p1 else p2_gradient_enabled,
		glow_opacity, glow_speed, glow_effect])

func set_blade_variant(player: int, variant: String) -> void:
	if player == 1:
		p1_blade_variant = variant
	else:
		p2_blade_variant = variant
	var cfg := ConfigFile.new()
	cfg.set_value(BLADE_VARIANT_SECTION, "p1_variant", p1_blade_variant)
	cfg.set_value(BLADE_VARIANT_SECTION, "p2_variant", p2_blade_variant)
	cfg.save(BLADE_VARIANT_FILE)
	if board != null:
		board.reload_blade_textures(p1_blade_variant, p2_blade_variant)

func set_drone_body(player: int, folder: String) -> void:
	if player == 1:
		p1_drone_body = folder
	else:
		p2_drone_body = folder
	var cfg := ConfigFile.new()
	cfg.set_value(DRONE_BODY_SECTION, "p1_body", p1_drone_body)
	cfg.set_value(DRONE_BODY_SECTION, "p2_body", p2_drone_body)
	cfg.save(DRONE_BODY_FILE)
	if board != null:
		board.reload_drone_bodies(p1_drone_body, p2_drone_body)

## ── Saved drone presets ────────────────────────────────────────────────────
## Snapshot EVERY piece of a player's Hex Drones customization into a Dictionary
## (colours, body, blade, all glow, screen/drive/destroy effects + speeds, sounds,
## and the shared glow effect/speed/opacity). Round-trips through ConfigFile.
func capture_drone_data(player: int) -> Dictionary:
	var P: String = "p%d_" % player
	return {
		"color": get(P + "color"), "blade_color": get(P + "blade_color"),
		"drone_body": get(P + "drone_body"), "blade_variant": get(P + "blade_variant"),
		"gsi": get(P + "glow_selected_inner"), "gso": get(P + "glow_selected_outer"),
		"gmi": get(P + "glow_move_inner"),     "gmo": get(P + "glow_move_outer"),
		"gci": get(P + "glow_capture_inner"),  "gco": get(P + "glow_capture_outer"),
		"grad": get(P + "gradient_enabled"),
		"screen": get(P + "screen_effect_id"),
		"drive": get(P + "drive_effect_id"),   "drive_spd": get(P + "drive_anim_speed"),
		"ddrive": get(P + "destroy_drive_effect_id"), "ddrive_spd": get(P + "destroy_drive_anim_speed"),
		"destroy": get(P + "destroy_effect_id"),
		"snd_move": SoundManager.get(P + "sound_idx"), "snd_rotate": SoundManager.get(P + "rotate_sound_idx"),
		"snd_destroy": SoundManager.get(P + "destroy_sound_idx"), "snd_turn": SoundManager.get(P + "turn_sound_idx"),
		"glow_effect": glow_effect, "glow_speed": glow_speed, "glow_opacity": glow_opacity,
	}

## Apply a captured drone snapshot to `player`, persisting and refreshing every
## affected subsystem (board colours/bodies/blades, glow, effects, sounds).
func apply_drone_data(player: int, d: Dictionary) -> void:
	var P: String = "p%d_" % player
	set(P + "color",                d.get("color", get(P + "color")))
	set(P + "blade_color",          d.get("blade_color", get(P + "blade_color")))
	set(P + "glow_selected_inner",  d.get("gsi", get(P + "glow_selected_inner")))
	set(P + "glow_selected_outer",  d.get("gso", get(P + "glow_selected_outer")))
	set(P + "glow_move_inner",      d.get("gmi", get(P + "glow_move_inner")))
	set(P + "glow_move_outer",      d.get("gmo", get(P + "glow_move_outer")))
	set(P + "glow_capture_inner",   d.get("gci", get(P + "glow_capture_inner")))
	set(P + "glow_capture_outer",   d.get("gco", get(P + "glow_capture_outer")))
	set(P + "gradient_enabled",     d.get("grad", get(P + "gradient_enabled")))
	glow_effect  = d.get("glow_effect", glow_effect)
	glow_speed   = d.get("glow_speed", glow_speed)
	glow_opacity = d.get("glow_opacity", glow_opacity)
	SoundManager.set(P + "sound_idx",        int(d.get("snd_move",    SoundManager.get(P + "sound_idx"))))
	SoundManager.set(P + "rotate_sound_idx", int(d.get("snd_rotate",  SoundManager.get(P + "rotate_sound_idx"))))
	SoundManager.set(P + "destroy_sound_idx",int(d.get("snd_destroy", SoundManager.get(P + "destroy_sound_idx"))))
	SoundManager.set(P + "turn_sound_idx",   int(d.get("snd_turn",    SoundManager.get(P + "turn_sound_idx"))))
	SoundManager._save_settings()
	## Effects via their setters so each persists to its own config file.
	set_screen_effect(player,        int(d.get("screen", get(P + "screen_effect_id"))))
	set_drive_effect(player,         int(d.get("drive", get(P + "drive_effect_id"))), float(d.get("drive_spd", get(P + "drive_anim_speed"))))
	set_destroy_drive_effect(player, int(d.get("ddrive", get(P + "destroy_drive_effect_id"))))
	set_destroy_drive_speed(player,  float(d.get("ddrive_spd", get(P + "destroy_drive_anim_speed"))))
	set_destroy_effect(player,       int(d.get("destroy", get(P + "destroy_effect_id"))))
	## Body + blade reload the board textures.
	set_blade_variant(player, String(d.get("blade_variant", get(P + "blade_variant"))))
	set_drone_body(player,    String(d.get("drone_body", get(P + "drone_body"))))
	_save_glow_config()
	_push_glow_settings_to_highlight()
	apply_colors_live()

## ── Board tile colours ─────────────────────────────────────────────────────
## Three recolourable base shades shared by regular AND edge tiles (the recolour
## shader matches each tile pixel to the nearest base shade by luminance). Defaults
## reproduce the original Black/Gray/White art exactly.
const BOARD_TILE_FILE := "user://board_tiles.cfg"
var board_tile_black: Color = Color(0.20, 0.20, 0.20)
var board_tile_gray:  Color = Color(0.61, 0.61, 0.61)
var board_tile_white: Color = Color(0.96, 0.96, 0.96)
var _board_tile_shader: Shader = preload("res://assets/shaders/board_tile_recolor.gdshader")

func _load_board_tiles() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BOARD_TILE_FILE) == OK:
		board_tile_black = cfg.get_value("board", "black", board_tile_black)
		board_tile_gray  = cfg.get_value("board", "gray",  board_tile_gray)
		board_tile_white = cfg.get_value("board", "white", board_tile_white)

func _save_board_tiles() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("board", "black", board_tile_black)
	cfg.set_value("board", "gray",  board_tile_gray)
	cfg.set_value("board", "white", board_tile_white)
	cfg.save(BOARD_TILE_FILE)

func board_tile_color(group: String) -> Color:
	match group:
		"gray":  return board_tile_gray
		"white": return board_tile_white
	return board_tile_black

func set_board_tile_color(group: String, c: Color) -> void:
	match group:
		"black": board_tile_black = c
		"gray":  board_tile_gray  = c
		"white": board_tile_white = c
	_save_board_tiles()
	apply_board_tile_colors()

## Assign the recolour shader to the board tile layer and push the 3 colours. A
## no-op when no board exists (e.g. on the main menu) — colours take effect next game.
func apply_board_tile_colors() -> void:
	if board == null or not is_instance_valid(board): return
	var bl: TileMapLayer = board.board_layer
	if bl == null: return
	var mat := bl.material as ShaderMaterial
	if mat == null or mat.shader != _board_tile_shader:
		mat = ShaderMaterial.new()
		mat.shader = _board_tile_shader
		bl.material = mat
	mat.set_shader_parameter("col_black", board_tile_black)
	mat.set_shader_parameter("col_gray",  board_tile_gray)
	mat.set_shader_parameter("col_white", board_tile_white)

## Returns the resource path for a drone body texture.
func drone_body_path(folder: String, is_p2: bool) -> String:
	var files: Array = DRONE_BODY_FILES.get(folder, ["Empty Hexy.png", "Empty Hexyb.png"])
	return "res://assets/HexPieces/BlankHexDrones/%s/%s" % [folder, files[1 if is_p2 else 0]]

## Rejoin / state-sync wiring — deferred so NetworkManager is guaranteed ready.
func _connect_net_signals() -> void:
	if NetworkManager.game_state_received.is_connected(_on_net_state_received): return
	NetworkManager.game_state_received.connect(_on_net_state_received)
	NetworkManager.opponent_forfeited.connect(_on_net_opponent_forfeited)
	NetworkManager.peer_joined.connect(_on_net_peer_back)
	NetworkManager.connected_to_host.connect(_on_net_peer_back)
	NetworkManager.peer_left.connect(_on_net_disconnect)
	NetworkManager.connection_failed.connect(_on_net_disconnect)

func _on_node_added_to_tree(node: Node) -> void:
	if node.name == "Main" and node.get_parent() == get_tree().root:
		call_deferred("_try_init_game_nodes")

func _on_node_removed_from_tree(node: Node) -> void:
	if node.name == "Main":
		board       = null
		dice_roller = null
		ui_manager  = null

func _try_init_game_nodes() -> void:
	board       = get_node_or_null("/root/Main/HexBoard")
	dice_roller = get_node_or_null("/root/Main/DiceRoller")
	ui_manager  = get_node_or_null("/root/Main/UIManager")
	if board == null or dice_roller == null or ui_manager == null: return
	if simulation_mode:
		dice_roller.animate_roll = false
	if not dice_roller.dice_result.is_connected(_on_dice_rolled):
		dice_roller.dice_result.connect(_on_dice_rolled)
	if _pending_puzzle_sid >= 0:
		var sid: int = _pending_puzzle_sid
		_pending_puzzle_sid = -1
		start_puzzle(sid)
	else:
		start_game()

func start_game() -> void:
	puzzle_mode = false
	_revenge_capture_counts.clear()
	_bot_revenge_active.clear()
	_bot_recent_squares.clear()
	_bot_diving_sid = -1
	_bot_drift_amplify = false
	_bot_strategy_locked = false
	board.setup_board()
	apply_board_tile_colors()
	## CLU (bot battle) takes the first move — it plays P2 but goes first.
	var start_player: int = 2 if active_bot_profile_id == "clu" else 1
	_game_states.clear()
	_game_states.append({"board": board.serialize_state(), "player": start_player})
	board.apply_piece_colors(p1_color, p1_blade_color, p2_color, p2_blade_color)
	current_player = start_player
	_state_authority_ts = 0.0
	_game_start_unix = Time.get_unix_time_from_system()

	## ── Rejoin restore ──────────────────────────────────────────────────────
	## Launched from the menu's Rejoin button: restore the saved snapshot and
	## push it to the peer so both sides converge on the newest state.
	if pending_rejoin and NetworkManager.is_multiplayer:
		pending_rejoin = false
		var saved: Dictionary = _load_rejoin_state()
		if not saved.is_empty():
			apply_synced_state(saved)
			_state_authority_ts = float(saved.get("ts", 0.0))
			call_deferred("send_current_state")
			return

	_set_state(GameState.ROLL_DICE)

## Start a puzzle session with the player controlling a single drone of type
## `chosen_sid`.  Generates a procedural enemy chain of 3-5 pieces and gives
## the player 5 movement points to capture all of them.
func start_puzzle(chosen_sid: int) -> void:
	puzzle_mode       = true
	puzzle_chosen_sid = chosen_sid   ## keep 0 so New Game re-randomizes next time
	## SID 0 = Random mode: pick a fresh random drone each time.
	if chosen_sid == 0:
		chosen_sid = randi() % 7 + 1
	p1_is_bot  = false
	p2_is_bot  = false
	mp_player  = 1   ## human is always P1
	_revenge_capture_counts.clear()
	_bot_revenge_active.clear()
	_bot_recent_squares.clear()
	_bot_diving_sid      = -1
	_bot_drift_amplify   = false
	_bot_strategy_locked = false
	_game_start_unix = Time.get_unix_time_from_system()
	_generate_puzzle(chosen_sid)

func _generate_puzzle(player_sid: int) -> void:
	var all_cells: Array[Vector2i] = board.board_layer.get_used_cells()
	if all_cells.is_empty(): return
	## Pick the board-center cell as the player start position.
	var rect: Rect2i  = board.board_layer.get_used_rect()
	var center: Vector2i = rect.position + rect.size / 2
	var start_pos: Vector2i = all_cells[0]
	var best_dist: float = 1e9
	for c in all_cells:
		var d: float = Vector2(float(c.x - center.x), float(c.y - center.y)).length()
		if d < best_dist:
			best_dist = d
			start_pos = c
	board.setup_puzzle_board(start_pos, player_sid)
	## Random starting rotation for the player piece.
	var player_rot: int = randi() % 6
	board.tile_rot[player_sid] = player_rot
	## Build a 5-position chain; enemies land at every-other index (0, 2, 4).
	## With 50% probability the LAST enemy (chain[4]) is placed at a cell only
	## reachable by rotating from chain[3].  That costs 1 extra movement point
	## (rotate at chain[3] + move to chain[4]), so the budget becomes 6 instead
	## of 5.  The dice display is updated to reflect the actual budget.
	const CHAIN_LEN: int = 5
	var chain: Array          = []
	var visited: Dictionary   = {start_pos: true}
	var cur_pos: Vector2i     = start_pos
	var prev_dir: Vector2i    = Vector2i(0, 0)
	var rotation_required: bool = false

	for step in range(CHAIN_LEN):
		var candidates: Array = []

		## On the last step, try (50% chance) to pick a cell reachable ONLY with
		## rotation — but ONLY if cur_pos is an edge tile, since rotation is not
		## available on non-edge tiles and would soft-lock the puzzle.
		var try_rot: bool = (step == CHAIN_LEN - 1) and (randi() % 2 == 0) \
							and board.is_edge_tile(cur_pos)
		if try_rot:
			var moves_base: Array = board.get_valid_move_coords_for_rotated(cur_pos, player_sid, 0)
			var moves_base_set: Dictionary = {}
			for m in moves_base: moves_base_set[m] = true
			## Try each of the 5 other rotation steps (relative to tile_rot) for rotation-only cells.
			for delta in range(1, 6):
				var moves_r: Array = board.get_valid_move_coords_for_rotated(cur_pos, player_sid, delta)
				for m in moves_r:
					if not visited.has(m) and not moves_base_set.has(m):
						candidates.append(m)
				if not candidates.is_empty():
					rotation_required = true
					break

		## Fallback (or normal step): cells reachable at the piece's current rotation (extra_steps=0).
		if candidates.is_empty():
			var moves: Array = board.get_valid_move_coords_for_rotated(cur_pos, player_sid, 0)
			for m in moves:
				if not visited.has(m): candidates.append(m)

		if candidates.is_empty(): break

		## Prefer candidates that change direction (avoid straight-line chains).
		if prev_dir != Vector2i(0, 0):
			var turning: Array = candidates.filter(func(c): return (c - cur_pos) != prev_dir)
			if not turning.is_empty():
				candidates = turning

		candidates.shuffle()
		var next_pos: Vector2i = candidates[0]
		prev_dir = next_pos - cur_pos
		chain.append(next_pos)
		visited[next_pos] = true
		cur_pos = next_pos

	var enemy_sids: Array = [11, 12, 13, 14, 15, 16, 17]
	var enemy_coords: Array = []
	var idx: int = 0
	for ep in chain:
		if idx % 2 == 0:
			board.add_puzzle_piece(ep, enemy_sids[randi() % enemy_sids.size()], 2)
			enemy_coords.append(ep)
		idx += 1
	## 20% chance: remove one random enemy (never the furthest one) to raise difficulty.
	if enemy_coords.size() > 1 and randi() % 5 == 0:
		var droppable: Array = enemy_coords.slice(0, enemy_coords.size() - 1)
		var drop_coord: Vector2i = droppable[randi() % droppable.size()]
		board.pieces.erase(drop_coord)
		board._piece_count[2] = maxi(0, board._piece_count[2] - 1)

	board.finish_puzzle_setup()
	board.apply_piece_colors(p1_color, p1_blade_color, p2_color, p2_blade_color)
	_game_states.clear()
	_game_states.append({"board": board.serialize_state(), "player": 1})
	current_player  = 1
	## Budget: 1pt per chain step + 1 extra if last hop needs rotation.
	puzzle_budget   = chain.size() + (1 if rotation_required else 0)
	movement_points = puzzle_budget
	_set_state(GameState.SPEND_MOVEMENT)
	call_deferred("_start_piece_glow")
	## Sync dice display to the actual budget (die values capped at 5 each).
	var die_a: int = mini(movement_points, 5)
	var die_b: int = movement_points - die_a
	dice_rolled.emit(die_a, die_b, movement_points)

## Restart the current puzzle from its initial layout (no regeneration).
func restart_puzzle() -> void:
	if not puzzle_mode or _game_states.is_empty(): return
	board.apply_state(_game_states[0]["board"])
	board.apply_piece_colors(p1_color, p1_blade_color, p2_color, p2_blade_color)
	_game_states.resize(1)
	current_player  = 1
	movement_points = puzzle_budget
	_set_state(GameState.SPEND_MOVEMENT)
	call_deferred("_start_piece_glow")
	var die_a: int = mini(puzzle_budget, 5)
	var die_b: int = puzzle_budget - die_a
	dice_rolled.emit(die_a, die_b, puzzle_budget)

func apply_colors_live() -> void:
	if is_instance_valid(board):
		board.apply_piece_colors(p1_color, p1_blade_color, p2_color, p2_blade_color)

# ---------------------------------------------------------------------------
# Match timer (Round 13, item 1.5)
# ---------------------------------------------------------------------------
## Wall-clock seconds elapsed since _game_start_unix (set in start_game(), and
## kept in sync across rejoin/resync via _serialize_game_state/apply_synced_state).
func get_elapsed_seconds() -> float:
	if _game_start_unix <= 0.0: return 0.0
	return max(0.0, Time.get_unix_time_from_system() - _game_start_unix)

## Total match time as "M:SS", or "H:MM:SS" once a match runs an hour or longer.
## Used by the win popup (UIManager._on_game_over) and the live HUD timer.
func get_elapsed_time_str() -> String:
	var total: int = int(round(get_elapsed_seconds()))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var seconds: int = total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%d:%02d" % [minutes, seconds]

# ---------------------------------------------------------------------------
# Turn ownership
# ---------------------------------------------------------------------------
func _is_my_turn() -> bool:
	if _is_bot(current_player): return false
	## Solo (mp_player=0): always allowed.
	## MP (mp_player=1 or 2): only act on your own turn.
	if mp_player == 0: return true
	return mp_player == current_player

func set_bot_assignment(p1: bool, p2: bool) -> void:
	if _bot_thinking:
		_pending_bot_assignment = [p1, p2]
		return
	_apply_bot_assignment(p1, p2)

func _apply_bot_assignment(p1: bool, p2: bool) -> void:
	p1_is_bot = p1
	p2_is_bot = p2
	if p1_is_bot and p2_is_bot:
		mp_player = 0   ## bot-vs-bot — no human seat, _is_my_turn() gates via _is_bot
	elif p2_is_bot:
		mp_player = 1   ## human is P1 (existing default)
	elif p1_is_bot:
		mp_player = 2   ## human is P2 (new — previously impossible)
	else:
		mp_player = 0   ## solo — can move both
	bot_mode_changed.emit(p1_is_bot, p2_is_bot)
	if _is_bot(current_player):
		match current_state:
			GameState.ROLL_DICE:
				var t1 := 0.0 if simulation_mode else 0.3
				get_tree().create_timer(t1).timeout.connect(_bot_roll, CONNECT_ONE_SHOT)
			GameState.SPEND_MOVEMENT:
				var t2 := 0.0 if simulation_mode else 0.2
				get_tree().create_timer(t2).timeout.connect(_bot_act, CONNECT_ONE_SHOT)

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------
func _set_state(new_state: int) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	match new_state:
		GameState.ROLL_DICE:
			selected_coord   = Vector2i(-999, -999)
			pending_rotation = 0.0
			ui_manager.show_roll_prompt(current_player)
			if _is_bot(current_player):
				var t_roll := 0.0 if simulation_mode else 0.3
				get_tree().create_timer(t_roll).timeout.connect(_bot_roll, CONNECT_ONE_SHOT)
		GameState.SPEND_MOVEMENT:
			ui_manager.show_movement_prompt(movement_points)
			if _is_bot(current_player):
				var t_act := 0.0 if simulation_mode else 0.2
				get_tree().create_timer(t_act).timeout.connect(_bot_act, CONNECT_ONE_SHOT)
		GameState.CHECK_WIN:
			_check_win_condition()

# ---------------------------------------------------------------------------
# Piece glow
# ---------------------------------------------------------------------------
func _start_piece_glow() -> void:
	if current_state != GameState.SPEND_MOVEMENT: return
	board.clear_highlights()
	board.highlight_player_pieces(current_player)

# ---------------------------------------------------------------------------
# Human actions
# ---------------------------------------------------------------------------
func roll_dice() -> void:
	if current_state != GameState.ROLL_DICE: return
	if not _is_my_turn(): return
	dice_roller.roll()

func select_piece_at(coord: Vector2i) -> void:
	if current_state != GameState.SPEND_MOVEMENT: return
	if not _is_my_turn(): return
	var piece = board.get_piece_at(coord)
	if piece.is_empty() or piece["player"] != current_player: return

	if selected_coord == coord:
		_confirm_rotation()
		return

	if selected_coord != Vector2i(-999, -999):
		board.preview_rotate_piece(selected_coord, 0.0)

	selected_coord   = coord
	pending_rotation = 0.0
	piece_selected.emit(coord)
	board.highlight_valid_moves(coord)
	ui_manager.show_piece_selected(piece["source_id"])

func preview_rotate_selected() -> void:
	if selected_coord == Vector2i(-999, -999):
		ui_manager.show_message("Select a piece first.")
		return
	if not board.is_edge_tile(selected_coord):
		ui_manager.show_message("Rotation only available on edge tiles.")
		return
	pending_rotation = fmod(pending_rotation + 60.0, 360.0)
	board.preview_rotate_piece(selected_coord, pending_rotation)
	pending_rotation_changed.emit(pending_rotation)
	board.highlight_valid_moves(selected_coord)

func _confirm_rotation() -> void:
	if pending_rotation == 0.0:
		deselect_piece()
		return
	var _rc = selected_coord
	var _rsid: int = board.get_piece_at(_rc).get("source_id", -1)
	board.commit_rotate_piece(selected_coord, pending_rotation)
	if NetworkManager.is_multiplayer:
		NetworkManager.send_rotate(_rc, pending_rotation)
	pending_rotation = 0.0
	selected_coord   = Vector2i(-999, -999)
	## Round 35 — rotating again without having left this tile is free.
	var cost: int = _rotation_point_cost(_rc, _rsid)
	if cost > 0:
		_spend_points(cost)

func deselect_piece() -> void:
	if selected_coord == Vector2i(-999, -999): return
	board.preview_rotate_piece(selected_coord, 0.0)
	pending_rotation = 0.0
	selected_coord   = Vector2i(-999, -999)
	board.clear_highlights()
	_start_piece_glow()
	ui_manager.show_movement_prompt(movement_points)

func move_selected_piece_to(target: Vector2i) -> void:
	if current_state != GameState.SPEND_MOVEMENT: return
	if selected_coord == Vector2i(-999, -999): return
	var is_valid = board.is_valid_move(selected_coord, target)
	if not is_valid: return

	var _rot := pending_rotation
	var costs_two: bool = (_rot != 0.0)

	## Rotation + move costs 2 points
	if costs_two and movement_points < 2:
		ui_manager.show_message("Need 2 points to move with rotation!")
		return

	if pending_rotation != 0.0:
		board.commit_rotate_piece(selected_coord, pending_rotation)
		pending_rotation = 0.0
	var _from = selected_coord

	## Round 35 — this piece is leaving its tile; any same-tile rotation
	## credit it held no longer applies.
	if _from == _rotation_credit_coord:
		_rotation_credit_coord = Vector2i(-999, -999)
		_rotation_credit_sid   = -1

	## Track captures of bot pieces — count per attacker for revenge module
	var captured: Dictionary = board.get_piece_at(target)
	if not captured.is_empty():
		piece_captured_for_screen_fx.emit(target, current_player)
	if not captured.is_empty() and _is_bot(captured["player"]):
		var attacker: Dictionary = board.get_piece_at(selected_coord)
		if not attacker.is_empty():
			var rsid: int = attacker["source_id"]
			_revenge_capture_counts[rsid] = _revenge_capture_counts.get(rsid, 0) + 1

	board.move_piece(selected_coord, target)
	_touch_state()
	selected_coord = Vector2i(-999, -999)
	if NetworkManager.is_multiplayer:
		NetworkManager.send_move(_from, target, _rot)

	var enemy: int = 3 - current_player
	if not board.player_has_pieces(enemy):
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		game_over.emit(current_player)
		return

	_spend_points(2 if costs_two else 1)

func _on_dice_rolled(die_a: int, die_b: int, total: int) -> void:
	movement_points = 4 if simulation_mode else total
	_touch_state()
	SoundManager.play_turn(current_player)   ## dice settled → turn sound
	dice_rolled.emit(die_a, die_b, total)
	_set_state(GameState.SPEND_MOVEMENT)
	call_deferred("_start_piece_glow")
	if NetworkManager.is_multiplayer:
		NetworkManager.send_dice(die_a, die_b, total)

# ---------------------------------------------------------------------------
# Point spending
# ---------------------------------------------------------------------------
## Round 35 — "rotating then rotating again without leaving your tile is all
## 1 movement", for human and bot alike. Returns the point cost (0 or 1) of
## confirming a rotation of the piece `sid` currently sitting on `coord`: 1
## the first time this piece rotates while staying on this tile this turn,
## 0 for every subsequent same-tile rotation. Updates the credit bookkeeping
## as a side effect; the credit is cleared when this piece leaves `coord`
## (move_selected_piece_to / _net_apply_move) or the turn ends (_end_turn).
func _rotation_point_cost(coord: Vector2i, sid: int) -> int:
	if coord == _rotation_credit_coord and sid == _rotation_credit_sid:
		return 0
	_rotation_credit_coord = coord
	_rotation_credit_sid   = sid
	return 1

## arm_bot: when false, don't schedule the next _bot_act timer.  Used by the
## rotate-then-capture flow so the rotation spend doesn't queue a SECOND
## _bot_act on top of the one the following move already arms (double-speed bug).
func _spend_points(n: int, arm_bot: bool = true) -> void:
	## Round 35 — a real spend means progress was made; the free-rotation
	## safety counter only needs to bound consecutive FREE rotations.
	_bot_free_rotation_chain_count = 0
	movement_points -= n
	movement_spent.emit(movement_points)
	if movement_points <= 0:
		_set_state(GameState.CHECK_WIN)
	else:
		ui_manager.show_movement_prompt(movement_points)
		_start_piece_glow()
		if _is_bot(current_player) and arm_bot:
			var t_spend := 0.0 if simulation_mode else maxf(0.2, drive_speed_for(current_player))
			get_tree().create_timer(t_spend).timeout.connect(_bot_act, CONNECT_ONE_SHOT)

## Round 38 — pieces with source_id 6/16 are fully rotation-symmetric (see
## _candidate_rot_steps in BotDecisionTree) and have a very narrow movement
## pattern -- if this is the ONLY piece a player has left, it realistically
## can never maneuver into a capture of the opponent's last piece, so the
## game would otherwise stall forever. Being reduced to just one of these
## is treated as a loss.
func _last_piece_is_stuck(player: int) -> bool:
	var pieces: Array = board.get_player_pieces(player)
	if pieces.size() != 1:
		return false
	var sid: int = board.get_piece_at(pieces[0]).get("source_id", -1)
	return sid == 6 or sid == 16

func _check_win_condition() -> void:
	## Puzzle mode: only P1 plays; P2 pieces are the targets.
	if puzzle_mode:
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		if not board.player_has_pieces(2):
			game_over.emit(1)   ## all enemies captured — puzzle solved
		else:
			game_over.emit(0)   ## out of moves — puzzle failed
		return
	var p1_alive: bool = board.player_has_pieces(1)
	var p2_alive: bool = board.player_has_pieces(2)
	if not p1_alive:
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		game_over.emit(2)
	elif not p2_alive:
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		game_over.emit(1)
	elif _last_piece_is_stuck(1):
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		game_over.emit(2)
	elif _last_piece_is_stuck(2):
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		game_over.emit(1)
	else:
		_end_turn()

func _end_turn() -> void:
	## Round 35 — same-tile rotation credit doesn't carry across turns.
	_rotation_credit_coord = Vector2i(-999, -999)
	_rotation_credit_sid   = -1
	## Safety net: if any win condition was missed by the in-move early-exit,
	## catch it here before handing control to the next player.
	if not board.player_has_pieces(1):
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER); game_over.emit(2); return
	if not board.player_has_pieces(2):
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER); game_over.emit(1); return
	current_player = 2 if current_player == 1 else 1
	_game_states.append({"board": board.serialize_state(), "player": current_player})
	turn_changed.emit(current_player)
	## Round 30 — "think ahead during the roll": the board is now fixed for the
	## bot's upcoming turn (nothing moves again until the bot acts), so prime
	## its geometry cache immediately, during the roll-dice delay/animation,
	## instead of waiting until _bot_act's evaluate_position call.
	if _is_bot(current_player):
		_decision_tree.prewarm_move_cache(board, board.get_player_pieces(current_player), board.get_player_pieces(3 - current_player))
	_set_state(GameState.ROLL_DICE)

# ---------------------------------------------------------------------------
# Network receive handlers
# ---------------------------------------------------------------------------
func _net_apply_dice(die_a: int, die_b: int, total: int) -> void:
	movement_points = total
	_touch_state()
	SoundManager.play_turn(current_player)   ## dice settled → turn sound
	dice_rolled.emit(die_a, die_b, total)
	_set_state(GameState.SPEND_MOVEMENT)
	call_deferred("_start_piece_glow")

func _net_apply_move(from: Vector2i, to: Vector2i, rot_deg: float) -> void:
	if rot_deg != 0.0:
		board.commit_rotate_piece(from, rot_deg)
	board.move_piece(from, to)
	_touch_state()
	selected_coord = Vector2i(-999, -999)
	## Round 35 — this piece is leaving its tile; any same-tile rotation
	## credit it held no longer applies.
	if from == _rotation_credit_coord:
		_rotation_credit_coord = Vector2i(-999, -999)
		_rotation_credit_sid   = -1
	var enemy: int = 3 - current_player
	if not board.player_has_pieces(enemy):
		_game_states.append({"board": board.serialize_state(), "player": 0})
		_set_state(GameState.GAME_OVER)
		game_over.emit(current_player)
		return
	_spend_points(2 if rot_deg != 0.0 else 1)

func _net_apply_rotate(coord: Vector2i, degrees: float) -> void:
	var sid: int = board.get_piece_at(coord).get("source_id", -1)
	board.commit_rotate_piece(coord, degrees)
	_touch_state()
	selected_coord = Vector2i(-999, -999)
	## Round 35 — mirror the sender's free-rotation determination (see
	## _confirm_rotation): rotating again without having left this tile is free.
	var cost: int = _rotation_point_cost(coord, sid)
	if cost > 0:
		_spend_points(cost)

# ---------------------------------------------------------------------------
# Rejoin / state synchronization
# ---------------------------------------------------------------------------
## Advance our board's authority timestamp — called on every applied action.
func _touch_state() -> void:
	_state_authority_ts = Time.get_unix_time_from_system()
	_board_version += 1

## Round 30 — see _board_version / BotDecisionTree.prewarm_move_cache.
func get_board_version() -> int:
	return _board_version

## Snapshot the whole game (board + turn state) into a JSON-safe Dictionary.
func _serialize_game_state() -> Dictionary:
	if not is_instance_valid(board): return {}
	return {
		"board":           board.serialize_state(),
		"current_player":  current_player,
		"state":           current_state,
		"movement_points": movement_points,
		"ts":              _state_authority_ts,
		"code":            NetworkManager.last_lobby_code,
		"game_start_unix": _game_start_unix,
	}

## Restore a snapshot produced by _serialize_game_state().
func apply_synced_state(gs: Dictionary) -> void:
	if not is_instance_valid(board) or not gs.has("board"): return
	board.apply_state(gs.get("board", {}))
	apply_colors_live()
	current_player   = int(gs.get("current_player", 1))
	movement_points  = int(gs.get("movement_points", 0))
	selected_coord   = Vector2i(-999, -999)
	pending_rotation = 0.0
	_game_start_unix = float(gs.get("game_start_unix", _game_start_unix))
	turn_changed.emit(current_player)
	_set_state(int(gs.get("state", GameState.ROLL_DICE)))

## Push our current live board to the peer (used right after a rejoin handshake).
func send_current_state() -> void:
	if not NetworkManager.is_multiplayer: return
	NetworkManager.send_state(_serialize_game_state())

## Peer (re)connected — send them our live board so they resync to us.
func _on_net_peer_back() -> void:
	if not NetworkManager.is_multiplayer or not is_instance_valid(board): return
	if current_state == GameState.GAME_OVER: return
	call_deferred("send_current_state")

## Received the peer's board.  Apply it only if it is at least as advanced as
## ours (largest timestamp wins → the last player to disconnect is authoritative).
func _on_net_state_received(gs: Dictionary) -> void:
	if not is_instance_valid(board): return
	var ts: float = float(gs.get("ts", 0.0))
	if ts < _state_authority_ts: return
	apply_synced_state(gs)
	_state_authority_ts = ts
	_clear_rejoin_state()

## Opponent abandoned the match (chose a fresh game) → we are the winner.
func _on_net_opponent_forfeited() -> void:
	declare_local_winner()

## Declare the local player the winner (opponent forfeited or timed out).
func declare_local_winner() -> void:
	if current_state == GameState.GAME_OVER: return
	var me: int = mp_player if mp_player != 0 else current_player
	_clear_rejoin_state()
	_set_state(GameState.GAME_OVER)
	game_over.emit(me)

## Local player gives up rejoining and wants a fresh game → opponent wins.
func forfeit_match() -> void:
	if NetworkManager.is_multiplayer:
		NetworkManager.send_forfeit()
	_clear_rejoin_state()

## Returns all board-state snapshots for the win-popup Replay button.
## Each entry: {"board": serialize_state() result, "player": int}
## Index 0 = initial board; last entry = game-over board (player=0).
func get_game_states() -> Array:
	return _game_states

## Undo the last completed turn: restore the board to the state just before the
## game-ending turn, return the appropriate player to ROLL_DICE. Used by the
## win-popup Undo button (local games only — meaningless in multiplayer).
## Returns true on success, false if there is nothing to undo.
func undo_last_turn() -> bool:
	## Need at least the initial state + one turn snapshot + the game-over state.
	if _game_states.size() < 2: return false
	## Pop the game-over entry (player=0) if present.
	if _game_states.back().get("player", 0) == 0:
		_game_states.pop_back()
	if _game_states.is_empty(): return false
	var restore: Dictionary = _game_states.back()
	board.apply_state(restore["board"])
	current_player = restore["player"]
	## Reset game-machine variables so the undone player can roll fresh.
	selected_coord = Vector2i(-999, -999)
	pending_rotation = 0.0
	movement_points = 0
	_rotation_credit_coord = Vector2i(-999, -999)
	_rotation_credit_sid   = -1
	_bot_thinking          = false
	_bot_strategy_locked   = false
	_bot_recent_squares.clear()
	board.clear_highlights()
	_set_state(GameState.ROLL_DICE)
	return true

## Save the live board so a full app restart can still rejoin within the window.
func _on_net_disconnect() -> void:
	if not NetworkManager.is_multiplayer or not is_instance_valid(board): return
	if current_state == GameState.GAME_OVER: return
	_save_rejoin_state()

func _save_rejoin_state() -> void:
	var gs: Dictionary = _serialize_game_state()
	if gs.is_empty(): return
	var cfg := ConfigFile.new()
	cfg.set_value("rejoin", "state",     gs)
	cfg.set_value("rejoin", "code",      NetworkManager.last_lobby_code)
	cfg.set_value("rejoin", "mp_player", mp_player)
	cfg.set_value("rejoin", "saved_at",  Time.get_unix_time_from_system())
	cfg.save(REJOIN_STATE_FILE)

## Returns the saved snapshot if it is for the current lobby and still within the
## 2-minute window (else {}).  Also restores mp_player so the rejoiner keeps
## controlling their own side.
func _load_rejoin_state() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(REJOIN_STATE_FILE) != OK: return {}
	var code: String = cfg.get_value("rejoin", "code", "")
	if code != NetworkManager.last_lobby_code: return {}
	var saved_at: float = float(cfg.get_value("rejoin", "saved_at", 0.0))
	if Time.get_unix_time_from_system() - saved_at > REJOIN_WINDOW_SEC: return {}
	mp_player = int(cfg.get_value("rejoin", "mp_player", mp_player))
	return cfg.get_value("rejoin", "state", {})

func _clear_rejoin_state() -> void:
	if FileAccess.file_exists(REJOIN_STATE_FILE):
		DirAccess.remove_absolute(REJOIN_STATE_FILE)

# ---------------------------------------------------------------------------
# Bot
# ---------------------------------------------------------------------------
func _bot_roll() -> void:
	if _is_bot(current_player) and current_state == GameState.ROLL_DICE:
		roll_dice_bot()

func roll_dice_bot() -> void:
	if current_state != GameState.ROLL_DICE: return
	## Snapshot revenge data gathered during the human's last turn, then reset
	## the accumulator so it's ready for the next human turn.
	## (Must snapshot BEFORE clearing so the bot can use it when it acts.)
	_bot_revenge_active = _revenge_capture_counts.duplicate()
	_revenge_capture_counts.clear()
	## Reset all per-turn trackers
	_bot_recent_squares.clear()
	_bot_diving_sid        = -1
	_bot_strategy_locked   = false
	_bot_drift_amplify     = false
	_bot_last_capture_tile = Vector2i(-999, -999)
	_bot_free_rotation_chain_count = 0
	dice_roller.roll()

## Round 38 — thin wrapper around _bot_act_inner that tracks _bot_thinking so
## set_bot_assignment can detect the bot is mid-turn and defer bot-assignment
## changes until the bot finishes acting (including any recursive
## free-rotation continuations), avoiding a state race that crashes
## downstream move logic.
func _bot_act() -> void:
	if not _is_bot(current_player) or current_state != GameState.SPEND_MOVEMENT: return
	_bot_thinking = true
	await _bot_act_inner()
	_bot_thinking = false
	if not _pending_bot_assignment.is_empty():
		var pending: Array = _pending_bot_assignment
		_pending_bot_assignment = []
		_apply_bot_assignment(pending[0], pending[1])

func _bot_act_inner() -> void:
	if not _is_bot(current_player) or current_state != GameState.SPEND_MOVEMENT: return
	## Guard against stale timer firing against the pre-reset board (no pieces yet)
	if board == null or not board.player_has_pieces(current_player): return

	## ── Lock the playstyle strategy once at the start of the turn ────────────
	if not _bot_strategy_locked:
		_bot_strategy        = _bot_choose_strategy()
		_bot_strategy_locked = true

	## ── Dive continuation (Medium + Hard): keep chaining captures with the ──
	## same piece before re-evaluating the whole board, so multi-capture dives
	## aren't abandoned mid-sequence.
	if _current_bot_difficulty() >= 1 and _bot_diving_sid >= 0:
		var dive := _bot_find_dive_capture(_bot_diving_sid)
		if not dive.is_empty():
			## Took a second piece — still chaining, not drifting.
			_bot_drift_amplify     = false
			_bot_last_capture_tile = dive["to"]
			_bot_recent_squares.append(dive["from"])
			select_piece_bot(dive["from"])
			move_selected_piece_to(dive["to"])
			return
		## Captured last move, no second capture, and movement remains (we're in
		## _bot_act) → drift: polarize the end-of-turn distance scores.
		_bot_diving_sid    = -1
		_bot_drift_amplify = true

	## ── Decision tree evaluation ────────────────────────────────────────────────
	var my_pieces: Array = board.get_player_pieces(current_player)
	var enemy_pieces: Array = board.get_player_pieces(3 - current_player)

	## Round 45 — run the entire AI search on a background Thread so the engine
	## main loop stays responsive (animations, input, OS events) during the
	## search. The board is frozen (read-only) while the bot thinks, so thread
	## reads of board state are safe. We yield process_frame in a loop until
	## the thread finishes, then read the result back on the main thread.
	## In simulation mode skip the thread + frame-yield loop entirely —
	## the fast-path plan is synchronous and < 100ms; no need to animate.
	var best: Dictionary
	if simulation_mode:
		_decision_tree.evaluate_position_in_thread(board, my_pieces, enemy_pieces,
			current_player, movement_points, _bot_revenge_active, _bot_recent_squares)
		best = _decision_tree._bot_thread_result
	else:
		ui_manager.show_bot_thinking()
		await get_tree().process_frame
		if _bot_thread != null:
			_bot_thread.wait_to_finish()
		_bot_thread = Thread.new()
		_bot_thread.start(_decision_tree.evaluate_position_in_thread.bind(
			board, my_pieces, enemy_pieces, current_player, movement_points,
			_bot_revenge_active, _bot_recent_squares
		))
		while _bot_thread.is_alive():
			await get_tree().process_frame
		_bot_thread.wait_to_finish()
		_bot_thread = null
		best = _decision_tree._bot_thread_result
		ui_manager.hide_bot_thinking()

	if best.is_empty():
		## Fallback to legacy best move if decision tree fails
		best = _bot_best_move()
		if best.is_empty():
			_set_state(GameState.CHECK_WIN)
			return

	## Handle Rotate-only (pure mobility rotation)
	if best.has("rotate_only"):
		var rot_sid: int = board.get_piece_at(best["from"]).get("source_id", -1)
		board.commit_rotate_piece(best["from"], best.get("rotate_only", 0.0))
		_touch_state()   ## bumps _board_version so BotDecisionTree's _geo_moves_cache refreshes
		_bot_diving_sid = -1
		_bot_recent_squares.clear()
		## Round 35 — rotating again without having left this tile is free.
		## If the planner still proposes rotating this same (already-credited)
		## piece, don't wait for the 0.5s re-arm timer -- continue the turn
		## immediately. _bot_free_rotation_chain_count bounds this recursion
		## (reset to 0 on any real spend) so a stuck planner can't loop forever.
		var rot_cost: int = _rotation_point_cost(best["from"], rot_sid)
		if rot_cost == 0 and _bot_free_rotation_chain_count < 8:
			_bot_free_rotation_chain_count += 1
			await _bot_act_inner()
		else:
			_spend_points(1)
		return

	## Handle Rotate-then-Capture (rotation unlocks a capture)
	if best.has("pre_rotate"):
		var pre_sid: int = board.get_piece_at(best["from"]).get("source_id", -1)
		board.commit_rotate_piece(best["from"], best.get("pre_rotate", 0.0))
		_touch_state()   ## bumps _board_version so BotDecisionTree's _geo_moves_cache refreshes
		_bot_recent_squares.clear()   ## rotation breaks the burn chain
		## Round 35 — rotating again without having left this tile is free.
		var pre_cost: int = _rotation_point_cost(best["from"], pre_sid)
		if pre_cost > 0:
			_spend_points(pre_cost, false)
		if current_state != GameState.SPEND_MOVEMENT: return

	## Handle Movement-Burn (A>B>A pattern)
	if best.get("action", "") == "Move Burn":
		_bot_recent_squares.append(best["from"])
		select_piece_bot(best["from"])
		move_selected_piece_to(best["to"])
		_bot_recent_squares.append(best["to"])  ## burn tracking
		return

	## Handle Dive (suicidal attack)
	if best.get("action", "") == "Dive":
		var tp_dive: Dictionary = board.get_piece_at(best["to"])
		if not tp_dive.is_empty() and tp_dive["player"] != current_player:
			_bot_diving_sid        = board.get_piece_at(best["from"]).get("source_id", -1)
			_bot_drift_amplify     = false
			_bot_last_capture_tile = best["to"]
		_bot_recent_squares.append(best["from"])
		select_piece_bot(best["from"])
		move_selected_piece_to(best["to"])
		return

	## Handle all capture actions (Commit Path, Defend, Reposition, etc.)
	var tp_pre: Dictionary = board.get_piece_at(best["to"])
	if not tp_pre.is_empty() and tp_pre["player"] != current_player:
		_bot_diving_sid        = board.get_piece_at(best["from"]).get("source_id", -1)
		_bot_drift_amplify     = false   ## a fresh capture — chaining may resume
		_bot_last_capture_tile = best["to"]
	else:
		_bot_diving_sid = -1

	_bot_recent_squares.append(best["from"])
	select_piece_bot(best["from"])
	move_selected_piece_to(best["to"])

func select_piece_bot(coord: Vector2i) -> void:
	if current_state != GameState.SPEND_MOVEMENT: return
	var piece: Dictionary = board.get_piece_at(coord)
	if piece.is_empty() or piece["player"] != current_player: return
	selected_coord   = coord
	pending_rotation = 0.0
	board.highlight_valid_moves(coord)

## Find the best capture the diving piece (identified by source_id) can make
## from its current board position.  Returns {} when no captures are available.
func _bot_find_dive_capture(sid: int) -> Dictionary:
	var enemy_pieces: Array = board.get_player_pieces(3 - current_player)
	var my_pieces:    Array = board.get_player_pieces(current_player)
	for coord in my_pieces:
		var p: Dictionary = board.get_piece_at(coord)
		if p.get("source_id", -1) != sid: continue
		var best_score: float = 0.0
		var best: Dictionary = {}
		for target in board.get_valid_move_coords(coord):
			var tp: Dictionary = board.get_piece_at(target)
			if tp.is_empty() or tp["player"] == current_player: continue
			## Value this capture with the full model: oppression + defending +
			## special-tile bonus + priority-take + revenge.
			var s: float = _capture_worth(target, my_pieces, enemy_pieces)
			var sim: Array = enemy_pieces.duplicate(); sim.erase(target)
			s += PRIORITY_TAKE_BONUS * float(1 + _capture_chain_count_for(target, sid, sim, 4))
			s += REVENGE_BONUS * float(_bot_revenge_active.get(tp["source_id"], 0))
			if s > best_score:
				best_score = s
				best = {"from": coord, "to": target}
		return best   ## found the piece (may be empty if no captures)
	return {}

# ── Strategy selection ───────────────────────────────────────────────────────
## Evaluates the current board state and picks the most advantageous playstyle
## for this turn (locked once per turn in _bot_act):
##   DIVE     — a piece can chain 2+ captures this turn (diving = taking pieces)
##   TRADE    — a favorable bait trade is set up (see _favorable_trade_available)
##   ROTATION — early game with an edge piece available
##   GRID     — default formation advance
func _bot_choose_strategy() -> int:
	var my_count:    int = board.get_player_pieces(current_player).size()
	var enemy_count: int = board.get_player_pieces(3 - current_player).size()

	## DIVE and TRADE both spend/risk material, so only commit to them when the
	## bot is at parity or ahead on pieces (can afford the trade).  When behind,
	## fall through to the safer GRID/ROTATION formation play.
	var has_material: bool = my_count >= enemy_count

	## DIVE — a bot piece can chain 2+ captures this turn: commit to the raid.
	if has_material and _max_capture_chain_available() >= 2:
		return STRATEGY_DIVE

	## TRADE — a favorable bait/recapture trade is available.
	if has_material and _favorable_trade_available():
		return STRATEGY_TRADE

	## ROTATION — very early game with an edge piece: invest a turn in orientation.
	## Only worthwhile when most pieces are still alive and formation is forming.
	if (my_count + enemy_count) >= 10 and _has_rotation_opportunity():
		return STRATEGY_ROTATION

	## GRID — default: advance in formation with every piece supported.
	return STRATEGY_GRID

## True if any bot piece is currently on an edge tile (rotation eligible).
func _has_rotation_opportunity() -> bool:
	for coord in board.get_player_pieces(current_player):
		if board.is_edge_tile(coord): return true
	return false

## TRADE is only worthwhile with a real bait setup:
##   • a bot "bait" piece an enemy can capture next turn,
##   • a supporting bot piece 2–3 movement-chain from the bait,
##   • we can recapture on the bait's square,
##   • the enemy taker can make ONLY that one capture (no further chain), and
##   • the trade is net even-or-better (taker is worth ≥ the bait).
func _favorable_trade_available() -> bool:
	var my:      Array = board.get_player_pieces(current_player)
	var enemies: Array = board.get_player_pieces(3 - current_player)
	if my.size() < 2 or enemies.is_empty(): return false

	for bait in my:
		if not _is_threatened(bait, enemies): continue   ## bait must be takeable
		var bait_line: int = _piece_blade_count(bait)

		## A supporting friendly must sit 2–3 movement-chain from the bait.
		var supported: bool = false
		for s in my:
			if s == bait: continue
			var s_sid: int = board.get_piece_at(s).get("source_id", -1)
			if s_sid < 0: continue
			var d: int = _chain_dist_to_nearest(s, s_sid, [bait], 4)
			if d >= 2 and d <= 3: supported = true; break
		if not supported: continue

		## Each enemy that can take the bait must be recapturable, limited to a
		## single capture, and worth at least as much as the bait.
		for ec in enemies:
			if not board.get_valid_move_coords(ec).has(bait): continue
			var can_recapture: bool = false
			for s2 in my:
				if s2 == bait: continue
				if board.get_valid_move_coords(s2).has(bait): can_recapture = true; break
			if not can_recapture: continue
			var ec_sid: int = board.get_piece_at(ec).get("source_id", -1)
			var others: Array = my.duplicate(); others.erase(bait)
			if _capture_chain_count_for(bait, ec_sid, others, 4) > 0: continue
			if _piece_blade_count(ec) >= bait_line:
				return true
	return false

# ── Bot decisions — three difficulty levels ──────────────────────────────────
func _bot_best_move() -> Dictionary:
	var best_score: float = -INF
	var best:         Dictionary = {}
	var enemy_pieces: Array = board.get_player_pieces(3 - current_player)
	var my_pieces:    Array = board.get_player_pieces(current_player)

	match _current_bot_difficulty():
		0:   ## Easy — blade-based values + high noise, never self-destructs
			for coord in my_pieces:
				for target in board.get_valid_move_coords(coord):
					var s := _bot_score_easy(coord, target, enemy_pieces)
					if s > best_score:
						best_score = s; best = {"from": coord, "to": target}

		1:   ## Medium — full value system + light cohesion (level 1)
			for coord in my_pieces:
				for target in board.get_valid_move_coords(coord):
					var s := _bot_score_advanced(coord, target, enemy_pieces, my_pieces, 1)
					if s > best_score:
						best_score = s; best = {"from": coord, "to": target}

		2:   ## Hard — full value system + strategy modifiers + restricted rotation
			for coord in my_pieces:
				for target in board.get_valid_move_coords(coord):
					var s := _bot_score_advanced(coord, target, enemy_pieces, my_pieces, 2)
					if s > best_score:
						best_score = s; best = {"from": coord, "to": target}

				## ── Restricted rotation (spec) ──────────────────────────────────
				## The bot only rotates when:
				##   (a) the rotation enables a CAPTURE not otherwise reachable, or
				##   (b) it increases the piece's move count by the highest amount,
				##       taken as a pure mobility rotation (no step).
				## Tile 6/6b (colour-teleport) ignore rotation entirely — skipped.
				var sid_rot: int = board.get_piece_at(coord).get("source_id", -1)
				if board.is_edge_tile(coord) and movement_points >= 2 \
				   and sid_rot != 6 and sid_rot != 16:
					var straight_moves: Array = board.get_valid_move_coords(coord)
					var base_n: int = straight_moves.size()
					var best_gain: int      = 0
					var best_gain_steps: int = 0

					for rot_steps in range(1, 6):
						var rmoves: Array = board.get_valid_move_coords_rotated(coord, rot_steps)

						## (b) track the rotation with the greatest mobility gain
						var gain: int = rmoves.size() - base_n
						if gain > best_gain:
							best_gain = gain; best_gain_steps = rot_steps

						## (a) rotate-then-capture: only score rotations that unlock a
						## capture the straight orientation can't reach.
						for target in rmoves:
							var tp: Dictionary = board.get_piece_at(target)
							var unlocks_capture: bool = (not straight_moves.has(target)
								and not tp.is_empty() and tp["player"] != current_player)
							if not unlocks_capture: continue
							var s2 := _bot_score_advanced(coord, target, enemy_pieces, my_pieces, 2)
							if s2 > best_score:
								best_score = s2
								best = {"from": coord, "to": target, "pre_rotate": rot_steps * 60.0}

					## (b) pure mobility rotation — only the single best-gain rotation,
					## valued modestly (mobility is useful but minor vs. captures).
					if best_gain > 0:
						var mob_score: float = float(best_gain) * 40.0
						if _bot_strategy == STRATEGY_ROTATION: mob_score += 150.0
						if mob_score > best_score:
							best_score = mob_score
							best = {"from": coord, "rotate_only": best_gain_steps * 60.0}
	return best

# ===========================================================================
# Piece value constants
# ===========================================================================
## Legacy blade-value constants — used ONLY by the Easy bot (_bot_score_easy).
const BLADE_VAL:       float = 100.0
const UNDEF_MULT:      float = 2.0   ## ×2 for undefended pieces (legacy: Easy bot only)

# ===========================================================================
# SPEC-DRIVEN VALUE MODEL  (Medium + Hard)
# ===========================================================================
## DEFENDING penalty — enemy tiles within 4 movement-chain that defend a target
## (its "defenders").  Capturing a well-defended piece is penalised because it
## gets recaptured.  Indexed [defender count 0..5, 6 = "5+"][line 1=single/2=double].
const DEFENDING_RANGE: int = 4
const DEFENDING_VALUE := {
	0: {1:    0.0, 2:    0.0},
	1: {1: -100.0, 2: -200.0},
	2: {1: -200.0, 2: -400.0},
	3: {1: -300.0, 2: -600.0},
	4: {1: -400.0, 2: -800.0},
	5: {1: -500.0, 2: -1000.0},
	6: {1: -600.0, 2: -1500.0},   ## 5+
}

## OPPRESSION bonus — friendly tiles within 4 movement-chain that threaten a
## target.  Local superiority lets us take even defended pieces.  Indexed
## [oppressor count 1..5, 6 = "5+"][line]; 0 oppressors → 0.
const OPPRESSION_RANGE: int = 4
const OPPRESSION_VALUE := {
	1: {1: 100.0, 2:  300.0},
	2: {1: 200.0, 2:  600.0},
	3: {1: 300.0, 2:  800.0},
	4: {1: 400.0, 2: 1000.0},
	5: {1: 500.0, 2: 1500.0},
	6: {1: 750.0, 2: 2000.0},     ## 5+
}

## Captures are the game's top priority: any net-positive capture is lifted above
## EVERY non-capture positioning move by this offset, so positioning is only ever
## a tiebreaker among non-captures — never competes with taking a piece.
const CAPTURE_TIER:          float = 10000.0
const PRIORITY_TAKE_BONUS:   float = 600.0   ## × captures reachable in a 5-chain
const THREAT_TAKE_BONUS:     float = 600.0   ## × our pieces the captured enemy could chain-take in 5
const REVENGE_BONUS:         float = 1000.0   ## × pieces this enemy took last turn
const MOVEMENT_BURN_PEN:     float = -500.0  ## A→B→A with no capture and no rotation
const NEAREST_PIECE_BONUS:   float = 30.0    ## move closes distance to nearest enemy
const DEFENDED_CHAIN_RANGE:  int   = 4       ## defended target: chain ≤ 4 moves
const UNDEFENDED_CHAIN_RANGE: int  = 4       ## undefended target: chain ≤ 5 moves

## Capture bonus for taking specific high-value ENEMY pieces (by source_id).
## Tiles 7/70 (knights) +200, tile 6 (teleporter) +300.
const CAPTURE_BONUS := {7: 200.0, 70: 200.0, 6: 300.0}

## Loss penalty for losing a specific BOT piece (by source_id) — subtracted from
## the round score when that piece is threatened (would be captured next turn).
## Bot is always Player 2, so these are the P2 source_ids.  21 (5b twin) mirrors 15.
const PIECE_LOSS := {
	11:  -800.0, 18:  -800.0,
	12:  -900.0, 19:  -900.0,
	13:  -900.0, 14:  -900.0,
	15:  -600.0, 21:  -600.0,
	16: -2000.0,
	17: -1500.0, 22: -1500.0,
}
const PIECE_LOSS_DEFAULT: float = -500.0   ## fallback for any unlisted bot piece

## Start-of-turn approach priority by movement-chain distance to nearest enemy.
## Rewards closing into striking range, but kept well below capture values so it
## never outweighs an actual take (peak 500).
const START_DIST_PRIORITY := {1: 750.0, 2: 500.0, 3: 250.0, 4: 100.0, 5: 10.0}
const START_DIST_FAR: float = -30.0   ## > 5 chain moves away

## ── End-of-turn distance incentive — THREE categories per piece, scored for the
## expected end-of-turn resting position (applied only on the LAST move):
##   A — my piece's chain distance to the nearest enemy   (offensive reach/exposure)
##   B — the nearest enemy's chain distance to my piece   (incoming threat)
##   C — my piece's chain distance to the nearest teammate (formation spacing)
## A — my piece's chain distance to the nearest enemy (offence: closer is better).
const END_MY_TO_ENEMY := {1: 50.0, 2: 40.0, 3: 30.0, 4: 20.0, 5: 10.0}
const END_MY_TO_ENEMY_FAR: float = -5.0     ## > 5
## B — the nearest enemy's chain distance to my piece (defence: closer is worse).
const END_ENEMY_TO_ME := {1: -300.0, 2: -250.0, 3: -200.0, 4: -20.0, 5: -10.0}
const END_ENEMY_TO_ME_FAR: float = 10.0     ## > 5
## C — my piece's chain distance to the nearest teammate (formation: 3–4 ideal).
const END_TEAMMATE := {0: -1000.0, 1: -500.0, 2: -250.0, 3: 100.0, 4: 35.0, 5: -50.0}
const END_TEAMMATE_FAR: float = -100.0      ## > 5

# ── Easy scoring — blade values + high noise ──────────────────────────────────
func _bot_score_easy(from: Vector2i, to: Vector2i, enemy_pieces: Array) -> float:
	var to_piece: Dictionary = board.get_piece_at(to)
	if not to_piece.is_empty() and to_piece["player"] == current_player:
		return -INF   ## Easy never destroys own pieces
	## Never retrace — easy bot does not movement-burn under any circumstance
	if to_piece.is_empty() and _bot_recent_squares.has(to):
		return -INF

	var score: float = 0.0
	if not to_piece.is_empty() and to_piece["player"] != current_player:
		score += _piece_blade_count(to) * BLADE_VAL   ## +100 per blade
	if not enemy_pieces.is_empty():
		score += float(_min_enemy_dist(from, enemy_pieces)
					  - _min_enemy_dist(to, enemy_pieces)) * 5.0
	if board.is_edge_tile(to): score += 10.0
	score += randf() * (_piece_blade_count(to) + 1) * BLADE_VAL * 0.8   ## noise scales with piece value
	return score

# ── Advanced scoring (Medium + Hard) — STRICT TIERS ───────────────────────────
# Captures are the #1 priority; positioning is only ever a tiebreaker among
# non-capture moves and can NEVER drag a capture down.
#
# TIER 1  CAPTURES — net piece value only (no positioning):
#   OPPRESSION bonus (friendlies within 4 chain) + DEFENDING penalty (enemies
#   within 4 chain) + CAPTURE_BONUS (7/70/6) + THREAT (×3000 per of our pieces the
#   enemy could chain-take) + priority take (+300 × chain) + revenge
#   − recapture risk (PIECE_LOSS of our piece, unless DIVE charges in)
#   → net > 0 : CAPTURE_TIER + net   (always beats any non-capture)
#   → net ≤ 0 : net                  (a bad trade falls below positioning)
#
# TIER 2  NON-CAPTURE POSITIONING — reposition then defend:
#   END 3-category distance tables (A/B/C) + escape + defend-captured-tile
#   + small approach nudge + movement-burn penalty + strategy modifiers.
#
# Piece take values are recomputed every call, so they update after every move.
# cohesion_level: 1 = Medium, 2 = Hard (Hard adds strategy modifiers + rotation).
# ─────────────────────────────────────────────────────────────────────────────
func _bot_score_advanced(from: Vector2i, to: Vector2i,
						 enemy_pieces: Array, my_pieces: Array,
						 cohesion_level: int) -> float:
	var to_piece: Dictionary = board.get_piece_at(to)
	var from_sid: int        = board.get_piece_at(from).get("source_id", -1)
	var from_line: int       = _piece_blade_count(from)

	## Never move onto a friendly piece (would self-capture).
	if not to_piece.is_empty() and to_piece["player"] == current_player:
		return -INF

	var is_capture: bool = (not to_piece.is_empty() and to_piece["player"] != current_player)
	var remaining:  int  = movement_points - 1

	## Recapture risk — value of OUR piece if it can be taken at `to` next turn.
	var to_threatened: bool  = _is_threatened(to, enemy_pieces)
	var risk_loss:     float = 0.0
	if to_threatened:
		var mydef: int = _count_friendly_support(to, my_pieces, from)
		var loss_mag: float = absf(float(PIECE_LOSS.get(from_sid, PIECE_LOSS_DEFAULT)))
		risk_loss = loss_mag * (1.0 if mydef == 0 else 0.35)

	# ═══════════════════════════════════════════════════════════════════════
	# TIER 1 — CAPTURES.  Scored purely on NET PIECE VALUE.  Positioning is NOT
	# considered here; a net-positive capture always outranks ANY non-capture
	# move (CAPTURE_TIER offset).  This is the game's #1 priority.
	# ═══════════════════════════════════════════════════════════════════════
	if is_capture:
		## Base worth = Oppression bonus + Defending penalty + special-tile bonus.
		var net: float = _capture_worth(to, my_pieces, enemy_pieces)

		## THREAT ELIMINATION — large priority for removing an enemy that can
		## chain-capture many of OUR pieces in a 5-move chain.  Taking the threat is
		## usually better than repositioning to dodge it.
		var threat_n: int = _capture_chain_count_for(to, int(to_piece["source_id"]), my_pieces, 5)
		net += THREAT_TAKE_BONUS * float(threat_n)

		## Priority take: +300 × captures reachable in a 5-chain (this one + chain)
		var sim_enemies: Array = enemy_pieces.duplicate(); sim_enemies.erase(to)
		net += PRIORITY_TAKE_BONUS * float(1 + _capture_chain_count_for(to, from_sid, sim_enemies, 5))

		## Revenge: ×REVENGE_BONUS per piece this enemy took last turn
		net += REVENGE_BONUS * float(_bot_revenge_active.get(to_piece["source_id"], 0))

		## Recapture risk — subtract our piece's value if it would be lost, UNLESS
		## the DIVE strategy says charge in regardless.
		var dive_charge: bool = (cohesion_level >= 2 and _bot_strategy == STRATEGY_DIVE)
		if to_threatened and not dive_charge:
			net -= risk_loss

		## Net-positive captures sit in the top tier (more value = higher).
		## Net-negative captures (bad trades) fall below positioning.
		if net > 0.0:
			return CAPTURE_TIER + net + randf() * 3.0
		return net + randf() * 3.0

	# ═══════════════════════════════════════════════════════════════════════
	# TIER 2 — NON-CAPTURE POSITIONING.  Only reached when no capture is chosen.
	# Goal order: reposition (advance / formation) then defend.
	# ═══════════════════════════════════════════════════════════════════════
	var score: float = 0.0

	## Movement burn — revisiting a square vacated this turn.
	if _bot_recent_squares.has(to):
		score += MOVEMENT_BURN_PEN

	## Defending — moving INTO a square where we'd be captured costs the loss.
	if to_threatened:
		score -= risk_loss

	## Escape — leaving a threatened square for a safe one saves ~half its loss.
	if _is_threatened(from, enemy_pieces) and not to_threatened:
		score += absf(float(PIECE_LOSS.get(from_sid, PIECE_LOSS_DEFAULT))) * 0.5

	## End-of-turn 3-category distance scoring (reposition + defend), always.
	score += _end_spacing_score(to, from_sid, from, my_pieces, enemy_pieces)

	## Small approach nudge toward a reachable capture (never overrides spacing).
	var ed: int = _chain_dist_to_nearest(to, from_sid, enemy_pieces, 6)
	if remaining > 0 and ed <= remaining:
		score += _start_dist_priority(ed)

	## Nearest-piece nudge.
	if not enemy_pieces.is_empty() and _min_enemy_dist(to, enemy_pieces) < _min_enemy_dist(from, enemy_pieces):
		score += NEAREST_PIECE_BONUS

	## Defend the just-captured tile (post-capture drift) — bring a DIFFERENT piece
	## into recapture range of the exposed forward piece when it is threatened.
	if _bot_drift_amplify and from != _bot_last_capture_tile \
	   and _bot_last_capture_tile != Vector2i(-999, -999):
		if _is_threatened(_bot_last_capture_tile, enemy_pieces) \
		   and board.get_valid_move_coords_for(to, from_sid).has(_bot_last_capture_tile):
			var fwd_sid: int = board.get_piece_at(_bot_last_capture_tile).get("source_id", -1)
			score += absf(float(PIECE_LOSS.get(fwd_sid, PIECE_LOSS_DEFAULT))) * 0.5

	## Playstyle strategy modifiers (Hard only).
	if cohesion_level >= 2:
		match _bot_strategy:
			STRATEGY_TRADE:
				## Bait: reward placing a piece an enemy can take where a second piece
				## of ours can recapture (positive trade only).
				for ec in enemy_pieces:
					if not board.get_valid_move_coords(ec).has(to): continue
					for bc in my_pieces:
						if bc == from: continue
						if not board.get_valid_move_coords(bc).has(to): continue
						## Trade up: enemy worth − our worth (intrinsic line worth).
						var bait: float = (_table2_value(OPPRESSION_VALUE, 1, _piece_blade_count(ec)) \
										 - _table2_value(OPPRESSION_VALUE, 1, from_line)) * 0.5
						if bait > 0.0: score += bait
						break
			STRATEGY_ROTATION:
				if board.is_edge_tile(to): score += 200.0
			STRATEGY_GRID:
				if not enemy_pieces.is_empty() and ed >= 3 and ed <= 5:
					score += 100.0

	return score + randf() * 3.0

# ===========================================================================
# SPEC value + distance helpers (Medium + Hard)
# ===========================================================================
## Max number of captures a piece (sid) can make starting at pos within a chain.
## Uses virtual position queries so multi-hop chains are seen, not just 1 step.
func _capture_chain_count_for(pos: Vector2i, sid: int, enemies: Array, moves_left: int) -> int:
	if moves_left <= 0 or enemies.is_empty(): return 0
	var best: int = 0
	for t in board.get_valid_move_coords_for(pos, sid):
		if enemies.has(t):
			var reduced: Array = enemies.duplicate(); reduced.erase(t)
			var d: int = 1 + _capture_chain_count_for(t, sid, reduced, moves_left - 1)
			if d > best: best = d
	return best

## BFS: minimum number of MOVES for a piece (sid) at `start` to reach any tile
## in `targets`.  Returns 999 if none reachable within max_depth.  This is the
## "movement chain distance" the spec's distance tables are based on.
func _chain_dist_to_nearest(start: Vector2i, sid: int, targets: Array, max_depth: int) -> int:
	if targets.is_empty(): return 999
	var target_set: Dictionary = {}
	for t in targets: target_set[t] = true
	if target_set.has(start): return 0
	var visited: Dictionary = {start: true}
	var frontier: Array = [start]
	var depth: int = 0
	while depth < max_depth and not frontier.is_empty():
		depth += 1
		var nxt: Array = []
		for pos in frontier:
			for nb in board.get_valid_move_coords_for(pos, sid):
				if target_set.has(nb): return depth
				if not visited.has(nb):
					visited[nb] = true
					nxt.append(nb)
		frontier = nxt
	return 999

## Start-of-turn approach priority for a movement-chain distance to nearest enemy.
func _start_dist_priority(d: int) -> float:
	if d <= 1: return float(START_DIST_PRIORITY[1])
	if d >= 6 or not START_DIST_PRIORITY.has(d): return START_DIST_FAR
	return float(START_DIST_PRIORITY[d])

## Look up a chain-distance table (keys 1..5) with a >5/unreachable fallback.
func _dist_table(d: int, table: Dictionary, far: float) -> float:
	if d < 0 or d > 5: return far      ## > 5 / unreachable
	if table.has(d): return float(table[d])
	return far

## Look up a [count(0..5, 6="5+")][line 1/2] value table (Defending / Oppression).
func _table2_value(table: Dictionary, count: int, line: int) -> float:
	var c: int = clampi(count, 0, 6)
	var l: int = 2 if line >= 2 else 1
	if not table.has(c): return 0.0
	var row: Dictionary = table[c]
	return float(row[l])

## Count of `pieces` (excluding any sitting on `target`) within `max_range`
## movement-chain of `target` — drives Oppression (friendly) and Defending (enemy).
func _count_within_chain(target: Vector2i, pieces: Array, max_range: int) -> int:
	var n: int = 0
	for c in pieces:
		if c == target: continue
		var sid: int = board.get_piece_at(c).get("source_id", -1)
		if sid < 0: continue
		if _chain_dist_to_nearest(c, sid, [target], max_range) <= max_range:
			n += 1
	return n

## Net worth of capturing the enemy at `target`: oppression bonus + defending
## penalty + special-tile capture bonus.  Shared by the main scorer and dives.
func _capture_worth(target: Vector2i, my_pieces: Array, enemy_pieces: Array) -> float:
	var line: int = _piece_blade_count(target)
	var defending:  int = _count_within_chain(target, enemy_pieces, DEFENDING_RANGE)
	var oppression: int = _count_within_chain(target, my_pieces,    OPPRESSION_RANGE)
	var v: float = _table2_value(DEFENDING_VALUE, defending, line) \
				 + _table2_value(OPPRESSION_VALUE, oppression, line)
	var tp: Dictionary = board.get_piece_at(target)
	if not tp.is_empty():
		v += float(CAPTURE_BONUS.get(int(tp["source_id"]), 0.0))
	return v

## Drift polarization: push a distance score 100 further from zero in its own
## direction (negatives −100, positives +100, zero unchanged).  Applied to each
## end-of-turn distance category when _bot_drift_amplify is set.
func _polarize(v: float) -> float:
	if v > 0.0: return v + 100.0
	if v < 0.0: return v - 100.0
	return v

## Minimum number of MOVES any enemy needs to reach `pos` (incoming-threat range).
func _enemy_reach_dist(pos: Vector2i, enemies: Array, max_depth: int) -> int:
	var best: int = 999
	for ec in enemies:
		var esid: int = board.get_piece_at(ec).get("source_id", -1)
		if esid < 0: continue
		var d: int = _chain_dist_to_nearest(ec, esid, [pos], max_depth)
		if d < best: best = d
		if best <= 1: break   ## already adjacent-reachable, can't beat that
	return best

## End-of-turn distance incentive for a piece (sid) resting at `pos` — three
## categories scored against the expected end-of-turn board:
##   A — my distance to nearest enemy        (offensive reach / over-exposure)
##   B — nearest enemy's distance to me       (incoming threat)
##   C — distance to nearest teammate         (formation spacing)
func _end_spacing_score(pos: Vector2i, sid: int, moved_from: Vector2i,
						my_pieces: Array, enemy_targets: Array) -> float:
	## Post-capture drift: polarize each category score by ±100 (away from zero)
	## so leftover-movement repositioning after an unchained capture is decisive.
	var amp: bool = _bot_drift_amplify

	## A — my piece's reach to the nearest enemy
	var da: int = _chain_dist_to_nearest(pos, sid, enemy_targets, 6)
	var sa: float = _dist_table(da, END_MY_TO_ENEMY, END_MY_TO_ENEMY_FAR)

	## B — the nearest enemy's reach to my piece
	var db: int = _enemy_reach_dist(pos, enemy_targets, 6)
	var sb: float = _dist_table(db, END_ENEMY_TO_ME, END_ENEMY_TO_ME_FAR)

	## C — nearest teammate (exclude the moved piece's origin)
	var sc: float = _teammate_spacing_score(pos, sid, moved_from, my_pieces)

	if amp:
		sa = _polarize(sa); sb = _polarize(sb)   ## sc already polarized inside
	return sa + sb + sc

## Category C in isolation — formation spacing to the nearest teammate.
## Used both inside the end-of-turn score and on approach moves so the bot
## never clusters 1–2 chain-steps from a teammate, even while diving in.
func _teammate_spacing_score(pos: Vector2i, sid: int, moved_from: Vector2i,
							 my_pieces: Array) -> float:
	var friends: Array = []
	for c in my_pieces:
		if c == moved_from: continue
		friends.append(c)
	var dc: int = _chain_dist_to_nearest(pos, sid, friends, 6)
	var sc: float = _dist_table(dc, END_TEAMMATE, END_TEAMMATE_FAR)
	if _bot_drift_amplify: sc = _polarize(sc)
	return sc

## Largest capture chain (count) any bot piece can currently make — drives the
## DIVE strategy selection.
func _max_capture_chain_available() -> int:
	var enemies: Array = board.get_player_pieces(3 - current_player)
	if enemies.is_empty(): return 0
	var best: int = 0
	for c in board.get_player_pieces(current_player):
		var sid: int = board.get_piece_at(c).get("source_id", -1)
		if sid < 0: continue
		var n: int = _capture_chain_count_for(c, sid, enemies, 5)
		if n > best: best = n
	return best

# ── Helper: piece line-count (1 = single-line, 2 = double-line) ───────────────
## Double-line pieces are tiles 6/6b (teleport) and 7/7b (knight) — the
## diagonal movers.  Everything else is single-line.  Feeds the PIECE_VALUE
## table (column 1 = single, column 2 = double).
func _piece_blade_count(coord: Vector2i) -> int:
	var piece: Dictionary = board.get_piece_at(coord)
	if piece.is_empty(): return 0
	var sid: int = piece["source_id"]
	match sid:
		6, 16, 7, 17, 70, 22: return 2   ## double-line (diagonal movers)
		_:                     return 1   ## single-line

# ── Helper: count of OTHER friendly pieces that can reach pos in 1 step ───────
## "defenders" of a square — drives risk valuation and the value table.
func _count_friendly_support(pos: Vector2i, my_pieces: Array, from: Vector2i) -> int:
	var n: int = 0
	for coord in my_pieces:
		if coord == from: continue
		if board.get_valid_move_coords(coord).has(pos): n += 1
	return n

## True if any enemy can legally step onto coord in one move
func _is_threatened(coord: Vector2i, enemy_pieces: Array) -> bool:
	for ec in enemy_pieces:
		if board.get_valid_move_coords(ec).has(coord): return true
	return false

func _min_enemy_dist(coord: Vector2i, enemy_pieces: Array) -> int:
	var min_d: int = 9999
	for ec in enemy_pieces:
		var d = board.hex_distance(coord, ec)
		if d < min_d: min_d = d
	return min_d
