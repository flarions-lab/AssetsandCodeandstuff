extends Node
## BackgroundManager.gd — autoload that manages the animated board backgrounds.
##
## Source GIFs live in assets/HexGifBackgrounds/. Since Godot 4 has no built-in
## animated-GIF player, each GIF is pre-converted (via tools/extract_gif_frames.ps1)
## into a folder of PNG frames + a manifest.json under
## assets/HexGifBackgrounds/frames/<id>/. This script discovers those folders at
## runtime, builds an AnimatedTexture from the frame sequence on demand, and
## persists the player's selection so AnimatedBackgroundDisplay.gd (in
## node_2d.tscn) can apply it behind the board.

signal background_changed

const SETTINGS_FILE    := "user://background_settings.cfg"
const SETTINGS_SECTION := "background"
const FRAMES_DIR        := "res://assets/HexGifBackgrounds/frames/"

## selected_id values of the form "<SOLID_COLOR_PREFIX><n>" mean "show a solid
## color" instead of an animated texture; <n> is a unique number identifying
## an entry in custom_colors (not a fixed array index, so ids stay stable when
## other presets are removed).
const SOLID_COLOR_PREFIX := "color:"

## Friendlier display names for known background ids. Anything not listed here
## falls back to a prettified version of the folder name.
const DISPLAY_NAMES := {
	"art_3d": "Art 3D",
	"art_pink": "Art Pink",
	"black_white_loop": "Black And White Loop",
	"art_pixel": "Art Pixel",
	"loop_space": "Loop Space",
	"star_wars_space": "Star Wars Space",
	"jamming_8bit": "Jamming 8-Bit",
	"space_glow_1": "Space Glow",
	"space_glow_2": "Space Glow II",
	"star_wars_art": "Star Wars Art",
	"big_love_heart": "Big Love Heart",
	"bw_4d_loop": "B&W 4D Loop",
	"bw_loop_xp": "B&W Loop",
	"colors_pan": "Colors Pan",
	"earth_space": "Earth Space",
	"glow_njorg": "Glow",
	"glow_bw": "Glow B&W",
	"lightning_glow": "Lightning Glow",
	"loop_satisfying": "Loop Satisfying",
	"perspective_loop": "Perspective Loop",
	"pink_spiral": "Pink Spiral",
	"pink_glow": "Pink Glow",
	"circuit_loop": "Circuit Loop",
	"ofthedayart": "Of The Day Art",
	"yellow_loop": "Yellow Loop",
}

## Per-background brightness multiplier (applied as a modulate on the display
## TextureRect). 1.0 = unchanged. Backgrounds not listed default to 1.0.
const BRIGHTNESS := {
	"art_3d": 0.5,
	"art_pink": 0.5,
	"loop_space": 0.5,
	"star_wars_space": 0.6,
	"jamming_8bit": 0.7,
	"space_glow_2": 0.75,
	"star_wars_art": 0.75,
	"glow_njorg": 0.45,   ## "Glow" — reduced 55% from full brightness
}

## Per-background playback speed multiplier (AnimatedTexture.speed_scale).
## 1.0 = unchanged, 0.6 = 40% slower. Backgrounds not listed default to 1.0.
const SPEED := {
	"art_pixel": 0.43,
	"star_wars_space": 0.5,
	"jamming_8bit": 0.7,
	"star_wars_art": 0.35,
}

## "" == no animated background (use the default board look).
## "<SOLID_COLOR_PREFIX><n>" == show the matching entry from custom_colors.
var selected_id: String = ""

## Reuse previously-built AnimatedTexture objects so switching back to a
## background doesn't cause a one-frame white flash from re-uploading frames.
var _texture_cache: Dictionary = {}

## User-created solid color presets: [{"id": "color:<n>", "color": Color}, ...]
## in the order they were added.
var custom_colors: Array = []

## Monotonically increasing counter used to mint new custom_colors ids.
var _next_color_num: int = 0

func _ready() -> void:
	_load_settings()

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

## Returns an Array of {"id": String, "name": String}, one per converted
## background folder found under FRAMES_DIR (sorted alphabetically by id).
func get_available_backgrounds() -> Array:
	var out: Array = []
	var dir := DirAccess.open(FRAMES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			if FileAccess.file_exists(FRAMES_DIR + entry + "/manifest.json"):
				out.append({"id": entry, "name": display_name(entry)})
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out

func display_name(id: String) -> String:
	if id.begins_with(SOLID_COLOR_PREFIX):
		var pos: int = _custom_color_index(id)
		return "Custom Color %d" % (pos + 1) if pos >= 0 else "Custom Color"
	if DISPLAY_NAMES.has(id):
		return DISPLAY_NAMES[id]
	return id.replace("_", " ").capitalize()

## Brightness multiplier to apply when displaying this background (1.0 = unchanged).
func brightness_for(id: String) -> float:
	return BRIGHTNESS.get(id, 1.0)

# ---------------------------------------------------------------------------
# Solid color presets
# ---------------------------------------------------------------------------

func _custom_color_index(id: String) -> int:
	for i in range(custom_colors.size()):
		if custom_colors[i]["id"] == id:
			return i
	return -1

## Adds a new solid-color preset, selects it, and returns its id.
func add_custom_color(color: Color) -> String:
	var id: String = SOLID_COLOR_PREFIX + str(_next_color_num)
	_next_color_num += 1
	custom_colors.append({"id": id, "color": color})
	_save_settings()
	set_selected(id)
	return id

## Removes a solid-color preset. If it was selected, falls back to "" (none).
func remove_custom_color(id: String) -> void:
	var idx: int = _custom_color_index(id)
	if idx < 0:
		return
	custom_colors.remove_at(idx)
	if selected_id == id:
		selected_id = ""
		background_changed.emit()
	_save_settings()

## Updates an existing preset's color. If it's the active selection, the
## display refreshes immediately.
func set_custom_color(id: String, color: Color) -> void:
	var idx: int = _custom_color_index(id)
	if idx < 0:
		return
	custom_colors[idx]["color"] = color
	_save_settings()
	if selected_id == id:
		background_changed.emit()

## Returns the Color for a "color:<n>" id, or a default gray if not found.
func get_custom_color(id: String) -> Color:
	var idx: int = _custom_color_index(id)
	if idx < 0:
		return Color(0.15, 0.15, 0.2)
	return custom_colors[idx]["color"]

# ---------------------------------------------------------------------------
# Selection persistence
# ---------------------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		selected_id = cfg.get_value(SETTINGS_SECTION, "selected_id", "")
		custom_colors = cfg.get_value(SETTINGS_SECTION, "custom_colors", [])
		_next_color_num = cfg.get_value(SETTINGS_SECTION, "next_color_num", 0)

		# Migrate the old single-solid-color format ("color" + selected_color)
		# into the new custom_colors list.
		if selected_id == "color":
			var legacy_color = cfg.get_value(SETTINGS_SECTION, "selected_color", null)
			if legacy_color is Color and custom_colors.is_empty():
				var id: String = SOLID_COLOR_PREFIX + str(_next_color_num)
				_next_color_num += 1
				custom_colors.append({"id": id, "color": legacy_color})
				selected_id = id
			else:
				selected_id = ""
			_save_settings()

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, "selected_id", selected_id)
	cfg.set_value(SETTINGS_SECTION, "custom_colors", custom_colors)
	cfg.set_value(SETTINGS_SECTION, "next_color_num", _next_color_num)
	cfg.save(SETTINGS_FILE)

func set_selected(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	_save_settings()
	for cached_id in _texture_cache:
		var t = _texture_cache[cached_id]
		if t is AnimatedTexture:
			t.speed_scale = SPEED.get(cached_id, 1.0) if cached_id == id else 0.0
	background_changed.emit()

## Like set_selected but does NOT persist to disk — used for the temporary
## bot-battle background so the player's saved choice is never overwritten.
func set_selected_no_save(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	for cached_id in _texture_cache:
		var t = _texture_cache[cached_id]
		if t is AnimatedTexture:
			t.speed_scale = SPEED.get(cached_id, 1.0) if cached_id == id else 0.0
	background_changed.emit()

# ---------------------------------------------------------------------------
# Texture building
# ---------------------------------------------------------------------------

## Builds (and returns) the texture to display for the given background id.
## Returns null for "" (no background) or if the id can't be loaded.
## Results are cached — repeated calls for the same id return the same object.
func build_texture(id: String) -> Texture2D:
	if id == "" or id.begins_with(SOLID_COLOR_PREFIX):
		return null
	if _texture_cache.has(id):
		return _texture_cache[id]
	var manifest_path := FRAMES_DIR + id + "/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return null

	var f := FileAccess.open(manifest_path, FileAccess.READ)
	var manifest = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(manifest) != TYPE_DICTIONARY:
		return null

	var frame_count: int = manifest.get("frame_count", 0)
	if frame_count <= 0:
		return null

	if frame_count == 1:
		var still: Texture2D = load(FRAMES_DIR + id + "/frame_0000.png")
		_texture_cache[id] = still
		return still

	var delays: Array = manifest.get("delays_ms", [])
	var anim := AnimatedTexture.new()
	anim.frames        = frame_count
	anim.current_frame = 0
	anim.speed_scale   = SPEED.get(id, 1.0)
	for i in range(frame_count):
		var tex: Texture2D = load(FRAMES_DIR + id + "/frame_%04d.png" % i)
		anim.set_frame_texture(i, tex)
		var delay_ms: float = float(delays[i]) if i < delays.size() else 100.0
		anim.set_frame_duration(i, delay_ms / 1000.0)
	_texture_cache[id] = anim
	return anim

## Convenience: builds the texture for the currently-selected background
## (or returns null if none is selected).
func build_selected_texture() -> Texture2D:
	return build_texture(selected_id)

## Returns the first-frame thumbnail for a background id, or null.
func get_thumbnail(id: String) -> Texture2D:
	if id == "" or id.begins_with(SOLID_COLOR_PREFIX):
		return null
	var path := FRAMES_DIR + id + "/frame_0000.png"
	if not FileAccess.file_exists(path):
		return null
	return load(path)
