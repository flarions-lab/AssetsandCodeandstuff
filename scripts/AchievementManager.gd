extends Node

## AchievementManager.gd — detects achievement conditions during play, tracks
## which are unlocked, and gates cosmetic/effect selection accordingly.
##
## Local-only players (no account) only ever get user://achievements.cfg —
## no network calls are made while logged out. Once logged in, unlocks are
## also synced to the server as real entitlements (source='achievement'),
## enabling cross-platform progression. Logging in for the first time also
## pushes up whatever was already earned locally (see sync_local_to_server).

signal achievement_unlocked(id: String)

const SAVE_FILE := "user://achievements.cfg"

## Display metadata for the Achievements panel (scripts/MainMenu.gd). Lives here
## rather than in MainMenu.gd so it (and the toast popups below) work
## regardless of which scene is active when an achievement unlocks.
const ACHIEVEMENTS: Array = [
	## -- All Game Modes ------------------------------------------------------
	{
		"category":    "All Game Modes",
		"id":          "win_easy",
		"name":        "Win on Easy",
		"description": "Win a game on Easy difficulty.",
		"unlocks":     "Solid drone blade variant",
	},
	{
		"id":          "win_medium",
		"name":        "Win on Medium",
		"description": "Win a game on Medium difficulty.",
		"unlocks":     "Power Lines drone blade variant",
	},
	{
		"id":          "win_hard",
		"name":        "Win on Hard",
		"description": "Win a game on Hard difficulty.",
		"unlocks":     "Sharp blade variant",
	},
	{
		"id":          "win_extra_hard",
		"name":        "Win on Extra Hard",
		"description": "Win a game on Extra Hard difficulty.",
		"unlocks":     "Solid Sharp blade variant",
	},
	{
		"id":          "win_puzzle",
		"name":        "Puzzle Solved",
		"description": "Win a Puzzles game.",
		"unlocks":     "Ornate blade variant",
	},
	{
		"id":          "win_3_tiles_remaining",
		"name":        "Dominant Victory",
		"description": "Win a game with 3+ tiles remaining.",
		"unlocks":     "Dramatic zoom screen animation",
	},
	{
		"id":          "triple_capture",
		"name":        "Triple Threat",
		"description": "Take 3 opposing tiles in a single turn.",
		"unlocks":     "Spiderweb and Reverse Spiderweb drone bodies",
	},
	{
		"id":          "like_a_song",
		"name":        "Music Fan",
		"description": "Like a song.",
		"unlocks":     "BPM Glow effect",
	},

	## -- Bot Battles ----------------------------------------------------------
	{
		"category":    "Bot Battles",
		"id":          "defeat_bey",
		"name":        "Defeat Bey",
		"description": "Defeat Bey, Master of the Rotating Blade.",
		"unlocks":     "Spin and Multi Spin drive/destroy-drive animations, and the Split destroy animation",
	},
	{
		"id":          "defeat_tron",
		"name":        "Defeat Tron",
		"description": "Defeat Tron, Defender of the Grid.",
		"unlocks":     "Hollow drone body and Circuit Loop background",
	},
	{
		"id":          "defeat_clu",
		"name":        "Defeat CLU",
		"description": "Defeat CLU, Perfector of the Grid.",
		"unlocks":     "Trail glow effect and Pixilate destroy animation",
	},
	{
		"id":          "defeat_omnitrix",
		"name":        "Defeat OmniTrix",
		"description": "Defeat OmniTrix, the Genetically Superior.",
		"unlocks":     "All sounds named \"OmniTrix\" and the Explode Flash destroy animation",
	},
	{
		"id":          "defeat_skynet",
		"name":        "Defeat Skynet",
		"description": "Defeat Skynet, Successor of Man.",
		"unlocks":     "Metallic drone body",
	},
	{
		"id":          "defeat_microbots",
		"name":        "Defeat MicroBots",
		"description": "Defeat MicroBots — if you can think it, MicroBots can do it.",
		"unlocks":     "Sounds: Microbot Move and Servo Whir, and the Darken screen effect",
	},
	{
		"id":          "defeat_candytech",
		"name":        "Defeat Candy Tech",
		"description": "Defeat Candy Tech, Engineering from the Bubble Gum Princess.",
		"unlocks":     "Peppermint, Swirl, and Red Swirl drone bodies, and Sounds: Ballblamburgler and Explosion",
	},

	## -- Multiplayer -----------------------------------------------------------
	{
		"category":    "Multiplayer",
		"id":          "first_mp_win",
		"name":        "First Online Win",
		"description": "Win your first Multiplayer game.",
		"unlocks":     "Heartbeat background",
	},
]

## category key (from ACHIEVEMENT_UNLOCKS reward dicts) -> display label used
## in the "(Variant Type) Unlocked" follow-up popup.
const _CATEGORY_LABELS: Dictionary = {
	"glow_effect": "Glow Effect",
	"drone_body":  "Drone Body",
	"blade":       "Drone Blade",
	"background":  "Background",
	"sound":       "Sound",
	"screen_fx":   "Screen Animation",
	"drive_fx":    "Drive Animation",
	"destroy_fx":  "Destroy Animation",
}

## id -> array of {category, value} unlock keys. Keep in sync with the server's
## relay_server/achievements.js ACHIEVEMENT_CATALOG when adding achievements.
const ACHIEVEMENT_UNLOCKS: Dictionary = {
	"win_easy":               [{"category": "blade", "value": "HexBladesSolid"}],
	"win_medium":             [{"category": "blade", "value": "HexBladesPowerStripe"}],
	"win_hard":                [{"category": "blade", "value": "HexBladesSharp"}],
	"win_extra_hard":          [{"category": "blade", "value": "HexBladesSolidSharp"}],
	"win_puzzle":              [{"category": "blade", "value": "HexBladesOrnate"}],
	"win_3_tiles_remaining":   [{"category": "screen_fx", "value": 7}],
	"triple_capture": [
		{"category": "drone_body", "value": "DronesBlankBlackWeb"},
		{"category": "drone_body", "value": "DronesBlankReverseWeb"},
	],
	"like_a_song": [{"category": "glow_effect", "value": "BPM"}],
	"defeat_bey": [
		{"category": "drive_fx",   "value": 6},
		{"category": "drive_fx",   "value": 7},
		{"category": "destroy_fx", "value": 4},
	],
	"defeat_tron": [
		{"category": "drone_body",  "value": "DronesBlankHollow"},
		{"category": "background",  "value": "circuit_loop"},
	],
	"defeat_clu": [
		{"category": "glow_effect", "value": "Trail"},
		{"category": "destroy_fx",  "value": 3},
	],
	"defeat_omnitrix": [
		{"category": "sound",       "value": "Omnitrix Move"},
		{"category": "sound",       "value": "Omnitrix Capture"},
		{"category": "sound",       "value": "Omnitrix Time In"},
		{"category": "sound",       "value": "Omnitrix Rotate"},
		{"category": "destroy_fx",  "value": 6},
	],
	"defeat_skynet":    [{"category": "drone_body", "value": "DronesMetallic"}],
	"defeat_microbots": [
		{"category": "sound",     "value": "Microbot Move"},
		{"category": "sound",     "value": "Servo Whir"},
		{"category": "screen_fx", "value": 9},
	],
	"defeat_candytech": [
		{"category": "drone_body", "value": "DronesBlankPepperMint"},
		{"category": "drone_body", "value": "DronesBlankSwirl"},
		{"category": "drone_body", "value": "DronesBlankRedSwirl"},
		{"category": "sound",      "value": "Ballblamburgler"},
		{"category": "sound",      "value": "Explosion"},
	],
	"first_mp_win": [{"category": "background", "value": "heartbeat"}],
}

var _local: Dictionary = {} ## achievement id -> true
var _turn_capture_count: Dictionary = {} ## player (int) -> captures this turn
var _toast: CanvasLayer

func _ready() -> void:
	_load()

	_toast = preload("res://scripts/AchievementToast.gd").new()
	add_child(_toast)

	GameManager.game_over.connect(_on_game_over)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.piece_captured_for_screen_fx.connect(_on_piece_captured)
	MusicPlayer.preferences_changed.connect(_on_music_preferences_changed)
	AccountManager.login_succeeded.connect(sync_local_to_server)
	AccountManager.register_succeeded.connect(sync_local_to_server)

func is_unlocked(id: String) -> bool:
	if _local.get(id, false):
		return true
	if not AccountManager.is_logged_in():
		return false
	var rewards: Array = ACHIEVEMENT_UNLOCKS.get(id, [])
	if rewards.is_empty():
		return false
	for reward in rewards:
		if not AccountManager.entitlements.has(_sku_for(id, reward)):
			return false
	return true

## True if `value` in `category` isn't gated by any achievement (default-free),
## or is gated but already unlocked.
func is_asset_unlocked(category: String, value) -> bool:
	var owning_id := _achievement_for_asset(category, value)
	if owning_id.is_empty():
		return true
	return is_unlocked(owning_id)

func unlock(id: String) -> void:
	if not ACHIEVEMENT_UNLOCKS.has(id): return
	var already_local: bool = _local.get(id, false)
	_local[id] = true
	if not already_local:
		_save()
		achievement_unlocked.emit(id)
		_show_unlock_toasts(id)
	if AccountManager.is_logged_in():
		AccountManager.unlock_achievement(id)

## "Achievement Unlocked: <name>" followed by one "(Variant Type) Unlocked"
## popup per distinct category that achievement grants.
func _show_unlock_toasts(id: String) -> void:
	if _toast == null: return
	_toast.show_toast("ACHIEVEMENT UNLOCKED\n" + _name_for(id))
	var shown: Dictionary = {}
	for reward in ACHIEVEMENT_UNLOCKS.get(id, []):
		var category: String = reward["category"]
		if shown.get(category, false): continue
		shown[category] = true
		var label: String = _CATEGORY_LABELS.get(category, category)
		_toast.show_toast(label + " Unlocked")

func _name_for(id: String) -> String:
	for entry in ACHIEVEMENTS:
		if entry.get("id", "") == id:
			return entry.get("name", id)
	return id

## Pushes every locally-earned achievement to the server. Safe to call
## repeatedly — the server-side grant is idempotent.
func sync_local_to_server() -> void:
	if not AccountManager.is_logged_in(): return
	for id in _local.keys():
		AccountManager.unlock_achievement(id)

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

func _human_seat() -> int:
	if GameManager.mp_player != 0:
		return GameManager.mp_player
	if GameManager.p1_is_bot and GameManager.p2_is_bot:
		return 0 ## bot vs bot — no human played
	if GameManager.p1_is_bot:
		return 2
	if GameManager.p2_is_bot:
		return 1
	return -1 ## local hotseat — both seats are human

const _BOT_PROFILE_ACHIEVEMENTS := {
	"bey": "defeat_bey", "tron": "defeat_tron", "clu": "defeat_clu",
	"omnitrix": "defeat_omnitrix", "skynet": "defeat_skynet",
	"microbots": "defeat_microbots", "candytech": "defeat_candytech",
}
const _DIFFICULTY_ACHIEVEMENTS := ["win_easy", "win_medium", "win_hard", "win_extra_hard"]

func _on_game_over(winner: int) -> void:
	if winner == 0:
		return ## puzzle failure or no winner

	if GameManager.puzzle_mode:
		if winner == 1:
			unlock("win_puzzle")
		return

	var human_seat := _human_seat()
	if human_seat == 0:
		return ## bot vs bot, nobody to credit

	var human_won: bool = (human_seat == -1) or (winner == human_seat)
	if not human_won:
		return

	if NetworkManager.is_multiplayer:
		unlock("first_mp_win")
	elif GameManager.active_bot_profile_id != "":
		var achievement_id: String = _BOT_PROFILE_ACHIEVEMENTS.get(GameManager.active_bot_profile_id, "")
		if not achievement_id.is_empty():
			unlock(achievement_id)
	elif human_seat != -1:
		var bot_seat: int = 3 - human_seat
		var is_opponent_bot: bool = GameManager.p1_is_bot if bot_seat == 1 else GameManager.p2_is_bot
		if is_opponent_bot:
			var difficulty: int = GameManager.p1_bot_difficulty if bot_seat == 1 else GameManager.p2_bot_difficulty
			if difficulty >= 0 and difficulty < _DIFFICULTY_ACHIEVEMENTS.size():
				unlock(_DIFFICULTY_ACHIEVEMENTS[difficulty])

	if GameManager.board and GameManager.board.get_player_pieces(winner).size() >= 3:
		unlock("win_3_tiles_remaining")

func _on_turn_changed(_player: int) -> void:
	_turn_capture_count.clear()

func _on_piece_captured(_board_pos: Vector2i, capturing_player: int) -> void:
	var count: int = _turn_capture_count.get(capturing_player, 0) + 1
	_turn_capture_count[capturing_player] = count
	if count >= 3 and capturing_player == _human_seat():
		unlock("triple_capture")

func _on_music_preferences_changed() -> void:
	for i in range(MusicPlayer.TRACKS.size()):
		if MusicPlayer.get_like_state(i) == "liked":
			unlock("like_a_song")
			return

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _achievement_for_asset(category: String, value) -> String:
	for id in ACHIEVEMENT_UNLOCKS.keys():
		for reward in ACHIEVEMENT_UNLOCKS[id]:
			if reward["category"] == category and reward["value"] == value:
				return id
	return ""

## Numeric effect ids don't carry a name — mirror the descriptive slugs used in
## relay_server/achievements.js's skus for the specific ids we ever gate.
const _EFFECT_ID_SLUGS := {
	"screen_fx":  {7: "dramatic_zoom", 9: "darken"},
	"drive_fx":   {6: "spin", 7: "multispin"},
	"destroy_fx": {3: "pixilate", 4: "split", 6: "explodeflash"},
}

## Mirrors relay_server/achievements.js's sku naming so is_unlocked() can check
## AccountManager.entitlements for a logged-in account.
func _sku_for(_achievement_id: String, reward: Dictionary) -> String:
	var category: String = reward["category"]
	var value = reward["value"]
	match category:
		"blade":
			return "blade_" + str(value).trim_prefix("HexBlades").to_lower()
		"drone_body":
			return "dronebody_" + str(value).trim_prefix("Drones").trim_prefix("Blank").to_lower()
		"background":
			return "bg_" + str(value)
		"sound":
			return "sound_" + str(value).to_lower().replace(" ", "_")
		"screen_fx", "drive_fx", "destroy_fx":
			var slug: String = _EFFECT_ID_SLUGS.get(category, {}).get(value, str(value))
			return category.replace("_", "") + "_" + slug
		"glow_effect":
			return "glow_" + str(value).to_lower()
	return ""

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) == OK:
		for id in cfg.get_section_keys("achievements"):
			_local[id] = cfg.get_value("achievements", id, false)

func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _local.keys():
		cfg.set_value("achievements", id, _local[id])
	cfg.save(SAVE_FILE)
