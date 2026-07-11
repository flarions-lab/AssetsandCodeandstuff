extends Node

## SoundManager.gd — autoload that manages piece movement sounds.
## Each player independently picks their move sound from the available library.

## Emitted whenever the "Hex Drones Volume" changes, so the Main Menu's
## Settings > SFX Volume slider and the Audio popup's "Hex Drones Volume"
## slider can stay in sync (mirrors MusicPlayer.volume_changed).
signal volume_changed(value: float)

const SAVE_FILE    := "user://sound_settings.cfg"
const SAVE_SECTION := "sounds"

## All available sounds with display names.
## Movement sounds first, then the destroy-sound collection.
const SOUNDS: Array = [
	{ "label": "Felt Hex",    "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/feltHexpiecesound.mp3" },
	{ "label": "Stone Tile",  "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/StoneTileSound.mp3" },
	{ "label": "Impact 1",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexDestroySound1.mp3" },
	{ "label": "Impact 2",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound2.mp3" },
	{ "label": "Impact 3",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound3.mp3" },
	{ "label": "Impact 4",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound4.mp3" },
	{ "label": "Impact 5",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound5.mp3" },
	{ "label": "Impact 6",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound6.mp3" },
	{ "label": "Impact 7",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound7.mp3" },
	{ "label": "Impact 8",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound8.mp3" },
	{ "label": "Impact 9",    "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound9.mp3" },
	{ "label": "Impact 10",   "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound10.mp3" },
	{ "label": "Impact 11",   "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound11.mp3" },
	{ "label": "Impact 12",   "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound12.mp3" },
	{ "label": "Impact 13",   "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound13.mp3" },
	{ "label": "Project 14",  "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/Project 14.mp3" },
	{ "label": "Impact 15",   "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/HexPieceDestroySound15.mp3" },
	{ "label": "Glass Clink", "path": "res://assets/HexAudio/HexSounds/HexTurnSounds/Glass Clinking.mp3" },
	{ "label": "Omnitrix Move",    "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/OmnitrixMoveSound.mp3" },
	{ "label": "Omnitrix Capture", "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/OmnitrixCapture.mp3" },
	{ "label": "Omnitrix Time In", "path": "res://assets/HexAudio/HexSounds/HexTurnSounds/OmnitrixTimeIn.mp3" },
	{ "label": "Omnitrix Rotate",  "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/OmniTrixRotate.mp3" },
	{ "label": "Ballblamburgler",  "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/Ballblamburgler.mp3" },
	{ "label": "Explosion",        "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/Explosion.mp3" },
	{ "label": "Microbot Move",    "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/MicroBotMove.mp3" },
	{ "label": "Servo Whir",       "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/ServoWhir.mp3" },
	{ "label": "Banner Move",     "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/BannerMove.mp3" },
	{ "label": "Banner Rotate",   "path": "res://assets/HexAudio/HexSounds/HexPieceMovementSounds/BannerRotateSound.mp3" },
	{ "label": "Blade Destroy",   "path": "res://assets/HexAudio/HexSounds/HexPieceDestroySounds/BladeDestroySound.mp3" },
	{ "label": "Goat Horn",       "path": "res://assets/HexAudio/HexSounds/HexTurnSounds/GoatHorn.mp3" },
]

## Index of the default turn sound (Glass Clink — appended last).
const TURN_SOUND_DEFAULT: int = 17

## -1 = no selection; a random sound from SOUNDS is picked each play until
## the player explicitly chooses one in Settings > Sounds.
var p1_sound_idx:         int = -1
var p2_sound_idx:         int = -1
var p1_rotate_sound_idx:  int = -1
var p2_rotate_sound_idx:  int = -1
var p1_destroy_sound_idx: int = -1
var p2_destroy_sound_idx: int = -1
var p1_turn_sound_idx:    int = -1   ## played when the dice settle
var p2_turn_sound_idx:    int = -1

## "Hex Drones Volume" — covers all piece sounds played through this manager
## (move/rotate/destroy/turn). linear 0–1, mapped to -80–(-6) dB. Set from the
## MusicPlayer Audio popup's "Hex Drones Volume" slider.
var _volume_db: float = 1.0

## Round 38 — mirrors MusicPlayer's mute state so the Audio popup's Mute
## button silences piece SFX too, without affecting the saved volume slider.
var _muted: bool = false

## Master Volume multiplier (0–1), set from the Main Menu's Settings >
## Master Volume slider via MusicPlayer.set_master_volume, which keeps both
## MusicPlayer and SoundManager in sync. Scales the final applied dB on top
## of _volume_db without altering the stored "Hex Drones Volume" value.
var _master_volume: float = 1.0

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_load_settings()
	_apply_volume()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func play_move(player: int) -> void:
	var idx: int = p1_sound_idx if player == 1 else p2_sound_idx
	_play_index(idx)

func play_rotate(player: int) -> void:
	var idx: int = p1_rotate_sound_idx if player == 1 else p2_rotate_sound_idx
	_play_index(idx)

func play_destroy(player: int) -> void:
	var idx: int = p1_destroy_sound_idx if player == 1 else p2_destroy_sound_idx
	_play_index(idx)

func play_turn(player: int) -> void:
	var idx: int = p1_turn_sound_idx if player == 1 else p2_turn_sound_idx
	_play_index(idx)

func preview_sound(idx: int) -> void:
	_play_index(idx)

func set_sound(player: int, type: String, idx: int) -> void:
	match type:
		"move":
			if player == 1: p1_sound_idx = idx
			else:            p2_sound_idx = idx
		"rotate":
			if player == 1: p1_rotate_sound_idx = idx
			else:            p2_rotate_sound_idx = idx
		"destroy":
			if player == 1: p1_destroy_sound_idx = idx
			else:            p2_destroy_sound_idx = idx
		"turn":
			if player == 1: p1_turn_sound_idx = idx
			else:            p2_turn_sound_idx = idx
	_save_settings()

func get_selected(player: int, type: String) -> int:
	match type:
		"move":    return p1_sound_idx        if player == 1 else p2_sound_idx
		"rotate":  return p1_rotate_sound_idx if player == 1 else p2_rotate_sound_idx
		"destroy": return p1_destroy_sound_idx if player == 1 else p2_destroy_sound_idx
		"turn":    return p1_turn_sound_idx    if player == 1 else p2_turn_sound_idx
	return 0

func sound_count() -> int:
	return SOUNDS.size()

func sound_label(idx: int) -> String:
	return SOUNDS[idx].get("label", "Sound " + str(idx + 1))

## "Hex Drones Volume" -- applies to every sound played through this manager
## (move/rotate/destroy/turn for both players). linear: 0.0 (silent) → 1.0 (full).
func set_volume(linear: float) -> void:
	_volume_db = clampf(linear, 0.0, 1.0)
	_apply_volume()
	_save_settings()
	volume_changed.emit(_volume_db)

func get_volume() -> float:
	return _volume_db

func set_muted(m: bool) -> void:
	_muted = m
	_apply_volume()

func is_muted() -> bool:
	return _muted

## Called by MusicPlayer.set_master_volume to keep the Master Volume
## multiplier in sync between both audio channels.
func set_master_volume(linear: float) -> void:
	_master_volume = clampf(linear, 0.0, 1.0)
	_apply_volume()
	_save_settings()

func _apply_volume() -> void:
	if _muted:
		_player.volume_db = -80.0
		return
	## Ceiling 0 dB = full amplitude (2× the old -6 dB ceiling, so SFX cut
	## through the music more easily). Floor -80 dB ≈ silent.
	_player.volume_db = lerp(-80.0, 0.0, _volume_db * _master_volume)

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
func _play_index(idx: int) -> void:
	var actual := idx
	if actual == -1:
		var available: Array = []
		for i in SOUNDS.size():
			if AchievementManager.is_asset_unlocked("sound", SOUNDS[i].get("label", "")):
				available.append(i)
		if available.is_empty():
			return
		actual = available[randi() % available.size()]
	if actual < 0 or actual >= SOUNDS.size():
		return
	var path: String = SOUNDS[actual].get("path", "")
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("SoundManager: could not load " + path)
		return
	_player.stream = stream
	_player.play()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) == OK:
		p1_sound_idx         = int(cfg.get_value(SAVE_SECTION, "p1_move",    -1))
		p2_sound_idx         = int(cfg.get_value(SAVE_SECTION, "p2_move",    -1))
		p1_rotate_sound_idx  = int(cfg.get_value(SAVE_SECTION, "p1_rotate",  -1))
		p2_rotate_sound_idx  = int(cfg.get_value(SAVE_SECTION, "p2_rotate",  -1))
		p1_destroy_sound_idx = int(cfg.get_value(SAVE_SECTION, "p1_destroy", -1))
		p2_destroy_sound_idx = int(cfg.get_value(SAVE_SECTION, "p2_destroy", -1))
		p1_turn_sound_idx    = int(cfg.get_value(SAVE_SECTION, "p1_turn",    -1))
		p2_turn_sound_idx    = int(cfg.get_value(SAVE_SECTION, "p2_turn",    -1))
		_volume_db           = float(cfg.get_value(SAVE_SECTION, "hex_drones_volume", 1.0))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "p1_move",    p1_sound_idx)
	cfg.set_value(SAVE_SECTION, "p2_move",    p2_sound_idx)
	cfg.set_value(SAVE_SECTION, "p1_rotate",  p1_rotate_sound_idx)
	cfg.set_value(SAVE_SECTION, "p2_rotate",  p2_rotate_sound_idx)
	cfg.set_value(SAVE_SECTION, "p1_destroy", p1_destroy_sound_idx)
	cfg.set_value(SAVE_SECTION, "p2_destroy", p2_destroy_sound_idx)
	cfg.set_value(SAVE_SECTION, "p1_turn",    p1_turn_sound_idx)
	cfg.set_value(SAVE_SECTION, "p2_turn",    p2_turn_sound_idx)
	cfg.set_value(SAVE_SECTION, "hex_drones_volume", _volume_db)
	cfg.save(SAVE_FILE)
