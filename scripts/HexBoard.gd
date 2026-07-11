extends Node2D

## HexBoard.gd
## Rotation is tracked per TILE TYPE (source_id), not per board position.
## Since each tile type appears only once per player, source_id is a stable key
## that never changes when a piece moves — no coord-sync needed.

const DIR_UL := 0
const DIR_UR := 1
const DIR_R  := 2
const DIR_DR := 3
const DIR_DL := 4
const DIR_L  := 5

const TILE_DIR_INDICES := {
	## P1 originals
	1:  [DIR_UL, DIR_R,  DIR_DL],
	2:  [DIR_UL, DIR_UR, DIR_DR, DIR_L],
	3:  [DIR_UL, DIR_UR, DIR_R,  DIR_DR],
	4:  [DIR_UL, DIR_DR, DIR_DL, DIR_L],
	5:  [DIR_UR, DIR_R,  DIR_DL, DIR_L],
	## P1 twins (unique source_ids so each piece has its own rotation slot)
	0:  [DIR_UL, DIR_R,  DIR_DL],           ## twin of 1
	20: [DIR_UL, DIR_UR, DIR_DR, DIR_L],    ## twin of 2
	50: [DIR_UR, DIR_R,  DIR_DL, DIR_L],    ## twin of 5
	## 7 / 70 handled in _get_tile7_moves
	## P2 originals
	11: [DIR_DR, DIR_L,  DIR_UR],
	12: [DIR_DL, DIR_R,  DIR_DR, DIR_UL],
	13: [DIR_UL, DIR_UR, DIR_R,  DIR_DR],
	14: [DIR_UL, DIR_DR, DIR_DL, DIR_L],
	15: [DIR_UR, DIR_R,  DIR_DL, DIR_L],
	## P2 twins
	18: [DIR_DR, DIR_L,  DIR_UR],           ## twin of 11
	19: [DIR_DL, DIR_R,  DIR_DR, DIR_UL],   ## twin of 12
	21: [DIR_UR, DIR_R,  DIR_DL, DIR_L],    ## twin of 15
	## 17 / 22 handled in _get_tile7_moves
}

const TILE7_BASE_CUBE_OFFSETS: Array[Vector3i] = [
	Vector3i( 2, -1, -1),
	Vector3i( 1,  1, -2),
	Vector3i(-1,  0,  1),
]

@export var tile6_max_distance: int = 2

## Maps each source_id → [tile_number, is_b_variant] for dynamic path building.
## tile_number (1-7) matches the Tile_N part of each asset filename.
## is_b_variant true → P2 mirror pieces that use the "Tile_Nb_" prefix.
const BLADE_TILE_MAP: Dictionary = {
	0:  [1, false],   ## P1 twin of 1
	1:  [1, false],
	2:  [2, false],
	3:  [3, false],
	4:  [4, false],
	5:  [5, false],
	6:  [6, false],
	7:  [7, false],
	11: [1, true],
	12: [2, true],
	13: [3, true],
	14: [4, true],
	15: [5, true],
	16: [6, true],
	17: [7, true],
	18: [1, true],    ## P2 twin of 11
	19: [2, true],    ## P2 twin of 12
	20: [2, false],   ## P1 twin of 2
	21: [5, true],    ## P2 twin of 15
	22: [7, true],    ## P2 twin of 17
	50: [5, false],   ## P1 twin of 5
	70: [7, false],   ## P1 twin of 7
}

## Maps each variant folder name → the PNG filename suffix for that variant.
const BLADE_VARIANT_SUFFIX: Dictionary = {
	"HexBladesGlowy":       "Lines_Glowy",
	"HexBladesOrnate":      "Ornate",
	"HexBladesPowerStripe": "PowerStripes",
	"HexBladesSharp":       "Sharp",
	"HexBladesSolid":       "Solid",
	"HexBladesStripes":     "Stripes",
	"HexBladesSharpDash":     "SharpDash",
	"HexBladesSolidSharp":     "SolidSharp",
	"HexBladesShort":         "Short",
	"HexBladesBanner":        "Banner",
	"HexBladesSword&Spear":    "Sword&Spear",
		}

## Edge tile atlas source_ids — only pieces on these tiles may rotate.
const EDGE_TILE_IDS := [80, 90, 100]

## Fallback player assignment by source_id.
## Used when the TileSet custom_data "Player" is 0 / unset for newer tiles.
const SOURCE_PLAYER := {
	0: 1, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 20: 1, 50: 1, 70: 1,
	11: 2, 12: 2, 13: 2, 14: 2, 15: 2, 16: 2, 17: 2, 18: 2, 19: 2, 21: 2, 22: 2
}

var board_layer:     TileMapLayer
var highlight_layer: TileMapLayer
var piece_layer:     TileMapLayer

## coord -> { "source_id": int, "player": int, "preview_offset": float }
var pieces: Dictionary = {}

## Authoritative piece counts per player, maintained by move_piece.
## Never derived from the `pieces` dict, so the temporary virtual-piece
## injections used by get_valid_move_coords_for (bot planning) cannot
## corrupt win detection.
var _piece_count: Dictionary = {1: 0, 2: 0}
## Piece count per player at game start — used for early-game / pieces-lost checks.
var _starting_piece_count: Dictionary = {1: 0, 2: 0}

## coord -> Node2D container  (child 0 = drone Sprite2D, child 1 = blade Sprite2D)
## Rotating / moving the container rotates / moves both sprites together.
var piece_sprites: Dictionary = {}

## Shared textures loaded once in _ready()
var _drone_p1:       Texture2D  = null   ## Empty Hexy.png  — Player 1 body
var _drone_p2:       Texture2D  = null   ## Empty Hexyb.png — Player 2 body
var _blade_textures: Dictionary = {}     ## source_id -> Texture2D

## source_id -> int (0-5)  — rotation step for each tile type.
## Key never changes on move because source_id is identity, not position.
var tile_rot: Dictionary = {}

func _ready() -> void:
	board_layer     = get_node("BoardLayer")
	piece_layer     = get_node("PieceLayer")
	highlight_layer = get_node("HighlightLayer")
	_load_piece_textures()

func _load_piece_textures() -> void:
	var dp1 := GameManager.drone_body_path(GameManager.p1_drone_body, false)
	if ResourceLoader.exists(dp1):
		_drone_p1 = load(dp1)
	else:
		push_warning("HexBoard: P1 drone not found: " + dp1)

	var dp2 := GameManager.drone_body_path(GameManager.p2_drone_body, true)
	if ResourceLoader.exists(dp2):
		_drone_p2 = load(dp2)
	else:
		push_warning("HexBoard: P2 drone not found: " + dp2)

	_reload_blade_textures_for_variants(GameManager.p1_blade_variant, GameManager.p2_blade_variant)

# ---------------------------------------------------------------------------
# Rotation helpers — keyed by source_id
# ---------------------------------------------------------------------------
func _rot_step(sid: int) -> int:
	return tile_rot.get(sid, 0)

func _set_rot(sid: int, step: int) -> void:
	tile_rot[sid] = ((step % 6) + 6) % 6

func _rot_degrees(sid: int) -> float:
	return _rot_step(sid) * 60.0

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func setup_board() -> void:
	for s in piece_sprites.values():
		s.queue_free()
	piece_sprites.clear()
	pieces.clear()
	tile_rot.clear()
	highlight_layer.clear()
	_piece_count = {1: 0, 2: 0}
	_read_pieces_from_layer()
	## Count pieces per player from what was just loaded
	for coord in pieces:
		var p: int = pieces[coord]["player"]
		if p in _piece_count: _piece_count[p] += 1
	_starting_piece_count = _piece_count.duplicate()   ## for "pieces lost" / early-game checks
	_build_piece_sprites(true)

# ---------------------------------------------------------------------------
# State serialization (rejoin / network resync)
# ---------------------------------------------------------------------------
## Snapshot the full board into a JSON-safe Dictionary.
func serialize_state() -> Dictionary:
	var plist: Array = []
	for coord in pieces:
		plist.append({
			"x": coord.x, "y": coord.y,
			"sid": pieces[coord]["source_id"], "p": pieces[coord]["player"],
		})
	var rot: Dictionary = {}
	for sid in tile_rot:
		rot[str(sid)] = tile_rot[sid]
	return {"pieces": plist, "rot": rot}

## Rebuild the board from a snapshot produced by serialize_state().
func apply_state(state: Dictionary) -> void:
	for s in piece_sprites.values():
		s.queue_free()
	piece_sprites.clear()
	pieces.clear()
	tile_rot.clear()
	highlight_layer.clear()
	_piece_count = {1: 0, 2: 0}

	var plist: Array = state.get("pieces", [])
	for e in plist:
		var coord := Vector2i(int(e["x"]), int(e["y"]))
		var pl: int = int(e["p"])
		pieces[coord] = {"source_id": int(e["sid"]), "player": pl, "preview_offset": 0.0}
		if pl in _piece_count: _piece_count[pl] += 1

	var rot: Dictionary = state.get("rot", {})
	for k in rot:
		tile_rot[int(k)] = int(rot[k])

	_build_piece_sprites()
	clear_highlights()

func _read_pieces_from_layer() -> void:
	var bcells = board_layer.get_used_cells()
	var pcells = piece_layer.get_used_cells()
	if bcells.is_empty() or pcells.is_empty():
		push_error("Board or piece layer is empty"); return
	var off = board_layer.get_used_rect().position - piece_layer.get_used_rect().position
	for coord in pcells:
		var sid = piece_layer.get_cell_source_id(coord)
		if sid == -1: continue
		var td = piece_layer.get_cell_tile_data(coord)
		if td == null: continue
		var adj = coord + off
		var player: int = td.get_custom_data("Player") as int
		if player == 0:   ## custom data unset — fall back to source_id table
			player = SOURCE_PLAYER.get(sid, 0)
		pieces[adj]   = { "source_id": sid, "player": player, "preview_offset": 0.0 }
		tile_rot[sid] = 0   ## all pieces start at step 0 (0°)

# ---------------------------------------------------------------------------
# Sprite system
# ---------------------------------------------------------------------------
func _build_piece_sprites(animate: bool = false) -> void:
	piece_layer.visible = false
	## Read colours once from GameManager (autoload) so every sprite is tinted
	## correctly from the moment it's created — no separate apply pass needed.
	## Direct autoload access — guaranteed non-null, no path lookup.
	var p1_drone_col: Color = GameManager.p1_color
	var p1_blade_col: Color = GameManager.p1_blade_color
	var p2_drone_col: Color = GameManager.p2_color
	var p2_blade_col: Color = GameManager.p2_blade_color
	var coords: Array = pieces.keys()
	if animate:
		## Sort P1 first, then P2, so teams slide in as distinct waves.
		coords.sort_custom(func(a, b): return pieces[a]["player"] < pieces[b]["player"])
	var idx: int = 0
	for coord in coords:
		_create_piece_sprite(coord, p1_drone_col, p1_blade_col, p2_drone_col, p2_blade_col,
				idx if animate else -1)
		idx += 1

func _create_piece_sprite(coord: Vector2i,
						  p1_dc: Color, p1_bc: Color,
						  p2_dc: Color, p2_bc: Color,
						  slide_idx: int = -1) -> void:
	var sid:    int      = pieces[coord]["source_id"]
	var player: int      = pieces[coord]["player"]
	var drone_tex: Texture2D = _drone_p1 if player == 1 else _drone_p2
	var drone_col: Color = p1_dc if player == 1 else p2_dc
	var blade_col: Color = p1_bc if player == 1 else p2_bc

	## Container — owns position AND rotation so both children move together.
	var container := Node2D.new()
	var target_pos: Vector2 = board_layer.map_to_local(coord) * board_layer.scale.x
	container.position         = target_pos
	container.rotation_degrees = _rot_degrees(sid)
	add_child(container)
	piece_sprites[coord] = container

	## Slide-in on game start: each piece drops from above its target with a
	## small per-piece delay so teams arrive in staggered waves. One short-lived
	## Tween per piece — no _process overhead, freed automatically on finish.
	if slide_idx >= 0:
		var drop: float = board_layer.tile_set.tile_size.y * board_layer.scale.y * 6.0
		container.position = target_pos + Vector2(0.0, -drop)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_QUART)
		tw.tween_property(container, "position", target_pos, 0.4).set_delay(slide_idx * 0.05)

	## Common scale: fit the 576 × 576 source art to the tile display size.
	var til      = board_layer.tile_set.tile_size
	var spr_scale := Vector2(board_layer.scale.x * til.x / 576.0,
							 board_layer.scale.y * til.y / 576.0)

	## ── Drone sprite (hex body — modulated by team drone colour) ───────────
	if drone_tex:
		var drone := Sprite2D.new()
		drone.texture        = drone_tex
		drone.scale          = spr_scale
		drone.modulate       = drone_col
		drone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		container.add_child(drone)     ## child index 0

	## ── Blade sprite (movement indicator — blade colour) ────────────────────
	if _blade_textures.has(sid):
		var blade := Sprite2D.new()
		blade.texture        = _blade_textures[sid]
		blade.scale          = spr_scale
		blade.modulate       = blade_col
		blade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		container.add_child(blade)     ## child index 1

func _sync_sprite_rotation(coord: Vector2i) -> void:
	if not piece_sprites.has(coord) or not pieces.has(coord): return
	var sid     = pieces[coord]["source_id"]
	var preview = pieces[coord].get("preview_offset", 0.0)
	piece_sprites[coord].rotation_degrees = _rot_degrees(sid) + preview

# ---------------------------------------------------------------------------
# Movement validation
# ---------------------------------------------------------------------------
func get_valid_move_coords(coord: Vector2i) -> Array[Vector2i]:
	if not pieces.has(coord): return []
	var piece   = pieces[coord]
	var sid:    int = piece["source_id"]
	var player: int = piece["player"]

	if sid == 6 or sid == 16: return _get_color_based_moves(coord, player)
	if sid == 7  or sid == 70: return _get_tile7_moves(coord, 0)    ## P1 right-facing
	if sid == 17 or sid == 22: return _get_tile7_moves(coord, 3)    ## P2 left-facing

	var preview_step: int = int(round(piece.get("preview_offset", 0.0) / 60.0))
	var steps: int = (_rot_step(sid) + preview_step + 6) % 6
	## CW rotation: (idx + steps) % 6 shifts directions CW to match sprite CW rotation.
	var nb    = board_layer.get_surrounding_cells(coord)
	var valid: Array[Vector2i] = []
	for idx in TILE_DIR_INDICES.get(sid, []):
		var ridx: int = (idx + steps) % 6
		if ridx < nb.size() and _is_board_cell(nb[ridx]):
			valid.append(nb[ridx])
	return valid

func _get_color_based_moves(coord: Vector2i, _player: int) -> Array[Vector2i]:
	var src = board_layer.get_cell_source_id(coord)
	var ids: Array = []
	if   src in [9,  90]:      ids = [9, 90]
	elif src in [8,  80]:      ids = [8, 80]
	elif src in [10, 20, 100]: ids = [10, 20, 100]
	else: return []
	var cands: Array = []
	for cell in board_layer.get_used_cells():
		if cell == coord: continue
		if not (board_layer.get_cell_source_id(cell) in ids): continue
		var d = _hex_dist(coord, cell)
		if d <= tile6_max_distance:
			cands.append({ "coord": cell, "dist": d })
	cands.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var valid: Array[Vector2i] = []
	for i in range(min(6, cands.size())):
		valid.append(cands[i]["coord"])
	return valid

func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var ac = _to_cube(a); var bc = _to_cube(b)
	return (abs(ac.x-bc.x) + abs(ac.y-bc.y) + abs(ac.z-bc.z)) >> 1

func _to_cube(o: Vector2i) -> Vector3i:
	var q: int = o.x - ((o.y - (o.y & 1)) >> 1)
	return Vector3i(q, o.y, -q - o.y)

func _get_tile7_moves(coord: Vector2i, base_offset: int) -> Array[Vector2i]:
	var sid = pieces[coord]["source_id"] if pieces.has(coord) else 0
	var preview_step: int = int(round(pieces[coord].get("preview_offset", 0.0) / 60.0)) if pieces.has(coord) else 0
	var steps: int = (_rot_step(sid) + preview_step + base_offset + 6) % 6
	## CW rotation: _rot_ccw(bv, (6-steps)%6) = rotate bv CW by `steps` steps.
	var cw_steps: int = (6 - steps) % 6
	var pc = _to_cube(coord)
	var valid: Array[Vector2i] = []
	for bv: Vector3i in TILE7_BASE_CUBE_OFFSETS:
		var t = _from_cube(pc + _rot_ccw(bv, cw_steps))
		if _is_board_cell(t):
			valid.append(t)
	return valid

func _rot_ccw(v: Vector3i, s: int) -> Vector3i:
	var q := v.x; var r := v.y; var z := v.z
	match s % 6:
		1: return Vector3i(-z,-q,-r)
		2: return Vector3i( r, z, q)
		3: return Vector3i(-q,-r,-z)
		4: return Vector3i( z, q, r)
		5: return Vector3i(-r,-z,-q)
	return v

func _from_cube(c: Vector3i) -> Vector2i:
	return Vector2i(c.x + ((c.y - (c.y & 1)) >> 1), c.y)

func _is_board_cell(coord: Vector2i) -> bool:
	return board_layer.get_cell_source_id(coord) != -1

## Load (or reload) blade textures for both players. P1 sids (is_b=false) use p1_variant;
## P2 sids (is_b=true) use p2_variant. Falls back to Glowy when a file is missing.
func _reload_blade_textures_for_variants(p1_variant: String, p2_variant: String) -> void:
	var file_cache: Dictionary = {}
	_blade_textures.clear()
	for sid in BLADE_TILE_MAP:
		var entry: Array = BLADE_TILE_MAP[sid]
		var tile_n: int  = entry[0]
		var is_b:   bool = entry[1]
		var variant: String = p2_variant if is_b else p1_variant
		var suffix: String  = BLADE_VARIANT_SUFFIX.get(variant, "Lines_Glowy")
		var fname: String   = "Tile_" + str(tile_n) + ("b_" if is_b else "_") + suffix + ".png"
		var cache_key: String = variant + "/" + fname
		if not file_cache.has(cache_key):
			var path: String = "res://assets/HexPieces/HexBlades/" + variant + "/" + fname
			if ResourceLoader.exists(path):
				file_cache[cache_key] = load(path)
			else:
				var fb: String = "res://assets/HexPieces/HexBlades/HexBladesGlowy/Tile_" \
					+ str(tile_n) + ("b_" if is_b else "_") + "Lines_Glowy.png"
				if ResourceLoader.exists(fb):
					file_cache[cache_key] = load(fb)
				else:
					push_warning("HexBoard: blade not found: " + path)
		if file_cache.has(cache_key):
			_blade_textures[sid] = file_cache[cache_key]

## Called by GameManager.set_blade_variant() to swap blade textures without reloading the scene.
func reload_blade_textures(p1_variant: String, p2_variant: String) -> void:
	_reload_blade_textures_for_variants(p1_variant, p2_variant)
	for coord in piece_sprites.keys():
		if not pieces.has(coord): continue
		var sid: int = pieces[coord]["source_id"]
		var container: Node2D = piece_sprites[coord]
		if container.get_child_count() < 2: continue
		var blade: Sprite2D = container.get_child(1) as Sprite2D
		if blade != null:
			blade.texture = _blade_textures.get(sid, null)

## Called by GameManager.set_drone_body() to swap drone body textures without reloading.
func reload_drone_bodies(p1_folder: String, p2_folder: String) -> void:
	var dp1 := GameManager.drone_body_path(p1_folder, false)
	var dp2 := GameManager.drone_body_path(p2_folder, true)
	if ResourceLoader.exists(dp1): _drone_p1 = load(dp1)
	if ResourceLoader.exists(dp2): _drone_p2 = load(dp2)
	for coord in piece_sprites.keys():
		if not pieces.has(coord): continue
		var player: int = pieces[coord]["player"]
		var container: Node2D = piece_sprites[coord]
		if container.get_child_count() < 1: continue
		var drone: Sprite2D = container.get_child(0) as Sprite2D
		if drone != null:
			drone.texture = _drone_p1 if player == 1 else _drone_p2

## Apply drone + blade colour modulates to every piece on the board.
func apply_piece_colors(p1_drone: Color, p1_blade: Color,
						p2_drone: Color, p2_blade: Color) -> void:
	for coord in piece_sprites:
		if not pieces.has(coord): continue
		var player: int = pieces[coord]["player"]
		var dc := p1_drone if player == 1 else p2_drone
		var bc := p1_blade if player == 1 else p2_blade
		var container: Node2D = piece_sprites[coord]
		if container.get_child_count() >= 1:
			container.get_child(0).modulate = dc   ## drone
		if container.get_child_count() >= 2:
			container.get_child(1).modulate = bc   ## blade

## Public hex-distance wrapper for use by GameManager bot.
func hex_distance(a: Vector2i, b: Vector2i) -> int:
	return _hex_dist(a, b)

func is_edge_tile(coord: Vector2i) -> bool:
	## Returns true if the board tile at coord is an edge tile (atlas ids 80/90/100).
	return board_layer.get_cell_source_id(coord) in EDGE_TILE_IDS

# ---------------------------------------------------------------------------
# Piece actions
# ---------------------------------------------------------------------------
func move_piece(from: Vector2i, to: Vector2i) -> void:
	var sid:    int = pieces[from]["source_id"]
	var player: int = pieces[from]["player"]

	pieces.erase(from)
	piece_layer.erase_cell(from)

	var is_capture := pieces.has(to)

	## Gather destroy params now (before erasing) but hold them for delayed fire.
	var _cap_sprite   = null
	var _cap_effect:  int   = 0
	var _cap_angle:   float = 0.0
	var _cap_player:  int   = 0
	if is_capture:
		var cap_player: int = pieces[to]["player"]
		_cap_player = cap_player
		if cap_player in _piece_count:
			_piece_count[cap_player] = max(0, _piece_count[cap_player] - 1)
		pieces.erase(to)
		piece_layer.erase_cell(to)
		if piece_sprites.has(to):
			_cap_sprite  = piece_sprites[to]
			piece_sprites.erase(to)
			var from_pix: Vector2 = board_layer.map_to_local(from) * board_layer.scale.x
			var to_pix:   Vector2 = board_layer.map_to_local(to)   * board_layer.scale.x
			_cap_angle  = (to_pix - from_pix).angle()
			_cap_effect = GameManager.destroy_effect_for(cap_player)

	pieces[to] = { "source_id": sid, "player": player, "preview_offset": 0.0 }
	piece_layer.set_cell(to, sid, Vector2i(0, 0))
	if not is_capture:
		SoundManager.play_move(player)

	if piece_sprites.has(from):
		var s           = piece_sprites[from]
		var target_pos: Vector2 = board_layer.map_to_local(to) * board_layer.scale.x
		piece_sprites.erase(from)
		s.rotation_degrees = _rot_degrees(sid)
		piece_sprites[to]  = s
		var _drive_fx: int  = GameManager.destroy_drive_effect_for(player) if is_capture else GameManager.drive_effect_for(player)
		var _drive_dur: float = GameManager.destroy_drive_speed_for(player) if is_capture else GameManager.drive_speed_for(player)
		_animate_piece_move(s, s.position, target_pos, _drive_fx, _drive_dur)
		## Glow trail lagging behind the moving drone, timed to the drive speed.
		var _hl = _get_highlight()
		if _hl: _hl.start_move_trail(from, to, _drive_dur)
		if is_capture and _cap_sprite != null:
			## Fire destroy + sound after 70% of the drive animation completes.
			var delay: float = _drive_dur * 0.7
			var dtw := create_tween()
			dtw.tween_interval(delay)
			dtw.tween_callback(func():
				_animate_destroy(_cap_sprite, _cap_effect, _cap_angle, _cap_player)
				SoundManager.play_destroy(player)
			)
	elif is_capture:
		## No moving sprite — fire destroy immediately (nothing to sync to).
		if _cap_sprite != null:
			_animate_destroy(_cap_sprite, _cap_effect, _cap_angle, _cap_player)
		SoundManager.play_destroy(player)
	clear_highlights()

## Animate a piece sprite from its current visual position to target_pos.
## effect: 1=Snap, 2=Fade, 3=Zoom, 4=Flash, 5=Slide.
func _animate_piece_move(s: Node2D, from_pos: Vector2, to_pos: Vector2, effect: int, dur: float) -> void:
	## Kill any in-progress tween on this sprite so chain-moves don't stack.
	if s.has_meta("drive_tween"):
		var prev = s.get_meta("drive_tween")
		if prev != null and prev.is_valid():
			prev.kill()
	## Simulation mode: instant snap — no tweens that could outlive the piece node
	if GameManager.simulation_mode:
		s.position = to_pos
		return

	if effect == 2:  ## Fade
		var half: float = maxf(dur * 0.5, 0.01)
		s.position = from_pos
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.tween_property(s, "modulate:a", 0.0, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func(): s.position = to_pos)
		tw.tween_property(s, "modulate:a", 1.0, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	elif effect == 3:  ## Zoom
		var half: float = maxf(dur * 0.5, 0.01)
		s.position = from_pos
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.tween_property(s, "scale", Vector2.ZERO, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
		tw.tween_callback(func(): s.position = to_pos)
		tw.tween_property(s, "scale", Vector2.ONE, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	elif effect == 4:  ## Flash
		var seg: float = maxf(dur / 7.0, 0.01)
		s.position = from_pos
		var bright := Color(1.6, 1.6, 1.6, 1.0)
		var normal := Color(1.0, 1.0, 1.0, 1.0)
		var gone   := Color(1.6, 1.6, 1.6, 0.0)
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.tween_property(s, "modulate", bright, seg)
		tw.tween_property(s, "modulate", normal, seg)
		tw.tween_property(s, "modulate", gone,   seg)
		tw.tween_callback(func(): s.position = to_pos; s.modulate = Color(1.6, 1.6, 1.6, 0.0))
		tw.tween_property(s, "modulate", bright, seg)
		tw.tween_property(s, "modulate", normal, seg)
		tw.tween_property(s, "modulate", bright, seg)
		tw.tween_property(s, "modulate", normal, seg)

	elif effect == 5:  ## Slide
		s.position = from_pos
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.set_ease(Tween.EASE_IN_OUT)
		tw.set_trans(Tween.TRANS_QUART)
		tw.tween_property(s, "position", to_pos, maxf(dur, 0.01))

	elif effect == 6:  ## Spin — rotates 360° while gliding to destination
		s.position = from_pos
		s.rotation = 0.0
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.set_parallel(true)
		tw.tween_property(s, "rotation", TAU, maxf(dur, 0.01)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(s, "position", to_pos, maxf(dur, 0.01)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.set_parallel(false)
		tw.tween_callback(func(): s.rotation = 0.0)

	elif effect == 7:  ## Multi Spin — 1440° in place then slides
		s.position = from_pos
		s.rotation = 0.0
		var spin_dur: float = maxf(dur * 0.65, 0.01)
		var slide_dur: float = maxf(dur * 0.35, 0.01)
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.tween_property(s, "rotation", TAU * 4.0, spin_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_callback(func(): s.rotation = 0.0)
		tw.tween_property(s, "position", to_pos, slide_dur).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUART)

	elif effect == 8:  ## Pixilate — scatter chunks at origin, flash in at destination
		s.position = from_pos
		s.modulate  = Color.WHITE
		var piece_color := Color.WHITE
		if s.get_child_count() > 0 and s.get_child(0) is CanvasItem:
			piece_color = (s.get_child(0) as CanvasItem).modulate
		piece_color.a = 1.0
		var scatter_dur: float = maxf(dur * 0.45, 0.12)
		for _i in 16:
			var px := Polygon2D.new()
			var h := 5.5
			px.polygon  = PackedVector2Array([Vector2(-h,-h), Vector2(h,-h), Vector2(h,h), Vector2(-h,h)])
			px.color    = piece_color
			px.position = from_pos + Vector2(randf_range(-22.0, 22.0), randf_range(-22.0, 22.0))
			add_child(px)
			var vel := Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0))
			var ptw := create_tween()
			ptw.tween_property(px, "position", px.position + vel, scatter_dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			ptw.parallel().tween_property(px, "modulate:a", 0.0, scatter_dur).set_ease(Tween.EASE_IN)
			ptw.tween_callback(px.queue_free)
		var tw := create_tween()
		s.set_meta("drive_tween", tw)
		tw.tween_property(s, "modulate:a", 0.0, maxf(dur * 0.3, 0.01)).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): s.position = to_pos; s.modulate = Color(2.0, 2.0, 2.0, 0.0))
		tw.tween_property(s, "modulate", Color(2.0, 2.0, 2.0, 1.0), maxf(dur * 0.2, 0.01)).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "modulate", Color.WHITE, maxf(dur * 0.25, 0.01)).set_ease(Tween.EASE_IN_OUT)

	else:  ## Snap (1 or default)
		s.position = to_pos

## Animate removal of a captured piece. Frees s after the animation completes.
## effect: 1=Explode, 2=Implode, 3=Pixilate, 4=Split, 5=Flash, 6=Explode Flash,
## 7=Implode Flash, 8=Pixilate B (Pixilate using the player's glow colour),
## 9=Knockout (flash on impact, piece flies off in attack direction).
## attack_angle: angle (radians) of the attacker's movement direction, used by Split and Knockout.
## player: the destroyed drone's owner, used by Pixilate B to fetch its glow colour.
func _animate_destroy(s: Node2D, effect: int, attack_angle: float = 0.0, player: int = 1) -> void:
	if s.has_meta("drive_tween"):
		var prev = s.get_meta("drive_tween")
		if prev != null and prev.is_valid():
			prev.kill()
	s.scale    = Vector2.ONE
	s.modulate = Color.WHITE
	const DUR: float = 0.5
	match effect:
		1:  ## Explode — scale up + fade out
			var tw := create_tween()
			tw.tween_property(s, "scale", Vector2(3.5, 3.5), DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(s, "modulate:a", 0.0, DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(s.queue_free)
		2:  ## Implode — scale to zero + fade out
			var tw := create_tween()
			tw.tween_property(s, "scale", Vector2.ZERO, DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tw.parallel().tween_property(s, "modulate:a", 0.0, DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(s.queue_free)
		3:  ## Pixilate — dissolve into scattered pixel chunks
			_animate_destroy_pixelate(s, DUR)
		4:  ## Split — two halves fly perpendicular to attack direction
			_animate_destroy_split(s, attack_angle, DUR)
		5:  ## Flash — brightness pulse then disappear
			var tw := create_tween()
			var bright := Color(2.8, 2.8, 2.8, 1.0)
			var normal := Color(1.0, 1.0, 1.0, 1.0)
			var seg: float = DUR / 5.0
			tw.tween_property(s, "modulate", bright, seg).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "modulate", normal, seg).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(s, "modulate", bright, seg).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "modulate:a", 0.0, seg * 2.0).set_ease(Tween.EASE_IN)
			tw.tween_callback(s.queue_free)
		6:  ## Explode Flash — bright flash then scale-up fade
			var tw := create_tween()
			tw.tween_property(s, "modulate", Color(3.0, 3.0, 3.0, 1.0), DUR * 0.2).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "scale", Vector2(3.5, 3.5), DUR * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(s, "modulate:a", 0.0, DUR * 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(s.queue_free)
		7:  ## Implode Flash — bright flash then scale-down fade
			var tw := create_tween()
			tw.tween_property(s, "modulate", Color(3.0, 3.0, 3.0, 1.0), DUR * 0.2).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "scale", Vector2.ZERO, DUR * 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tw.parallel().tween_property(s, "modulate:a", 0.0, DUR * 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(s.queue_free)
		8:  ## Pixilate B — like Pixilate, but chunks use the drone's glow colour
			_animate_destroy_pixelate(s, DUR, GameManager.glow_color_for(player))
		9:  ## Knockout — flash on impact, then fly off in the attack direction
			var tw := create_tween()
			var start_pos := s.position
			var fly_dir := Vector2(cos(attack_angle), sin(attack_angle))
			tw.tween_property(s, "modulate", Color(3.5, 3.5, 3.5, 1.0), DUR * 0.08).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "position", start_pos + fly_dir * 150.0, DUR * 0.92)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
			tw.parallel().tween_property(s, "modulate", Color(1.0, 1.0, 1.0, 0.0), DUR * 0.92)\
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(s, "scale", Vector2(0.65, 0.65), DUR * 0.92)\
				.set_ease(Tween.EASE_IN)
			tw.tween_callback(s.queue_free)
		_:
			s.queue_free()

## override_color: when given (a Color), the pixel chunks use it instead of the
## drone sprite's own colour — this is what Pixilate B passes (the glow colour).
func _animate_destroy_pixelate(s: Node2D, dur: float, override_color = null) -> void:
	var piece_color := Color.WHITE
	if override_color != null:
		piece_color = override_color
	elif s.get_child_count() > 0 and s.get_child(0) is CanvasItem:
		piece_color = (s.get_child(0) as CanvasItem).modulate
	piece_color.a = 1.0
	const COUNT:   int   = 20
	const PX_SIZE: float = 11.0
	for _i in COUNT:
		var px := Polygon2D.new()
		var h: float = PX_SIZE * 0.5
		px.polygon  = PackedVector2Array([
			Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)
		])
		px.color    = piece_color
		px.position = s.position + Vector2(randf_range(-26.0, 26.0), randf_range(-26.0, 26.0))
		add_child(px)
		var vel := Vector2(randf_range(-75.0, 75.0), randf_range(-95.0, -8.0))
		var tw := create_tween()
		tw.tween_property(px, "position", px.position + vel, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(px, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tw.tween_callback(px.queue_free)
	var tw_src := create_tween()
	tw_src.tween_property(s, "modulate:a", 0.0, dur * 0.35).set_ease(Tween.EASE_IN)
	tw_src.tween_callback(s.queue_free)

func _animate_destroy_split(s: Node2D, attack_angle: float, dur: float) -> void:
	var perp_angle: float = attack_angle + PI * 0.5
	var spread := Vector2(cos(perp_angle), sin(perp_angle)) * 90.0
	for i in 2:
		var half := Node2D.new()
		half.position = s.position
		half.rotation = s.rotation
		add_child(half)
		for ci in s.get_child_count():
			half.add_child(s.get_child(ci).duplicate())
		var dir: float = 1.0 if i == 0 else -1.0
		var tw := create_tween()
		tw.tween_property(half, "position", s.position + spread * dir, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(half, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(half, "scale", Vector2(0.5, 0.5), dur).set_ease(Tween.EASE_IN)
		tw.tween_callback(half.queue_free)
	s.queue_free()

func preview_rotate_piece(coord: Vector2i, preview_deg: float) -> void:
	if not pieces.has(coord): return
	pieces[coord]["preview_offset"] = preview_deg
	_sync_sprite_rotation(coord)

func commit_rotate_piece(coord: Vector2i, degrees: float) -> void:
	if not pieces.has(coord): return
	var sid         = pieces[coord]["source_id"]
	var player: int = pieces[coord]["player"]
	var delta: int  = int(round(degrees / 60.0))
	_set_rot(sid, _rot_step(sid) + delta)
	pieces[coord]["preview_offset"] = 0.0
	if piece_sprites.has(coord):
		piece_sprites[coord].rotation_degrees = _rot_degrees(sid)
	SoundManager.play_rotate(player)
	clear_highlights()

func _process(_delta: float) -> void:
	## Skip the per-frame sprite re-sync while the bot is thinking. The search runs
	## on a background thread that briefly mutates pieces/tile_rot during rotated
	## move lookups (get_valid_move_coords_for_rotated); reading them here on the
	## main thread at the same time races and can crash (signal 11). The board is
	## visually static during thinking, so nothing is lost — it re-syncs right after.
	if GameManager._bot_thinking:
		return
	## Re-sync sprites every frame from tile_rot (keyed by sid — never corrupted by moves).
	for coord in piece_sprites:
		if not pieces.has(coord): continue
		var sid     = pieces[coord]["source_id"]
		var preview = pieces[coord].get("preview_offset", 0.0)
		piece_sprites[coord].rotation_degrees = _rot_degrees(sid) + preview

# ---------------------------------------------------------------------------
# Queries & highlights
# ---------------------------------------------------------------------------
func get_piece_at(coord: Vector2i) -> Dictionary:
	return pieces.get(coord, {})

## Returns true when a player has at least one piece alive.
## Uses the dedicated counter — immune to virtual-piece query injections.
func player_has_pieces(player: int) -> bool:
	return _piece_count.get(player, 0) > 0

## Puzzle mode: clear board and place a single player piece.
func setup_puzzle_board(player_coord: Vector2i, player_sid: int) -> void:
	for s in piece_sprites.values():
		s.queue_free()
	piece_sprites.clear()
	pieces.clear()
	tile_rot.clear()
	highlight_layer.clear()
	_piece_count = {1: 0, 2: 0}
	pieces[player_coord]  = {"source_id": player_sid, "player": 1, "preview_offset": 0.0}
	tile_rot[player_sid]  = 0
	_piece_count[1]       = 1

## Puzzle mode: register one additional piece (call before finish_puzzle_setup).
func add_puzzle_piece(coord: Vector2i, sid: int, player: int) -> void:
	pieces[coord] = {"source_id": sid, "player": player, "preview_offset": 0.0}
	tile_rot[sid] = 0
	if player in _piece_count:
		_piece_count[player] += 1

## Puzzle mode: build sprites after all pieces have been registered.
func finish_puzzle_setup() -> void:
	_build_piece_sprites(true)

func get_player_pieces(player: int) -> Array:
	var r := []
	for c in pieces:
		if pieces[c]["player"] == player: r.append(c)
	return r

func is_valid_move(from: Vector2i, to: Vector2i) -> bool:
	return to in get_valid_move_coords(from)

## Returns valid moves for a piece (source_id = sid) if it were placed at at_coord.
## Temporarily injects a virtual piece to reuse the existing movement logic,
## then restores the original state — safe for bot planning, no persistent mutation.
func get_valid_move_coords_for(at_coord: Vector2i, sid: int) -> Array[Vector2i]:
	var had_piece := pieces.has(at_coord)
	var saved: Dictionary = pieces.get(at_coord, {})
	pieces[at_coord] = {"source_id": sid, "player": SOURCE_PLAYER.get(sid, 1), "preview_offset": 0.0}
	var moves := get_valid_move_coords(at_coord)
	if had_piece: pieces[at_coord] = saved
	else:         pieces.erase(at_coord)
	return moves

## Combines get_valid_move_coords_for and get_valid_move_coords_rotated: valid
## moves for a piece (source_id = sid) placed at at_coord, as if it had
## extra_steps of CW rotation applied. Used by chain-threat lookahead to ask
## "what could this piece reach from here if it rotated first?" — both the
## virtual placement and the rotation are restored, no persistent mutation.
func get_valid_move_coords_for_rotated(at_coord: Vector2i, sid: int, extra_steps: int) -> Array[Vector2i]:
	var had_piece := pieces.has(at_coord)
	var saved: Dictionary = pieces.get(at_coord, {})
	pieces[at_coord] = {"source_id": sid, "player": SOURCE_PLAYER.get(sid, 1), "preview_offset": 0.0}
	var orig_rot: int = _rot_step(sid)
	_set_rot(sid, orig_rot + extra_steps)
	var moves := get_valid_move_coords(at_coord)
	_set_rot(sid, orig_rot)
	if had_piece: pieces[at_coord] = saved
	else:         pieces.erase(at_coord)
	return moves

## Returns valid moves as if the piece at coord had extra_steps of CW rotation applied.
## Used by the Hard bot to evaluate rotate-then-move sequences without mutating state.
func get_valid_move_coords_rotated(coord: Vector2i, extra_steps: int) -> Array[Vector2i]:
	if not pieces.has(coord): return []
	var sid: int  = pieces[coord]["source_id"]
	var orig: int = _rot_step(sid)
	_set_rot(sid, orig + extra_steps)
	var moves: Array[Vector2i] = get_valid_move_coords(coord)
	_set_rot(sid, orig)   ## restore — no side effects
	return moves

func highlight_player_pieces(player: int) -> void:
	var sel: Array[Vector2i] = []
	for c in pieces:
		if pieces[c]["player"] == player: sel.append(c)
	var h = _get_highlight()
	if h:
		var gm := get_node_or_null("/root/GameManager")
		if gm: gm.apply_glow_to_highlight(h, player)
		var none: Array[Vector2i] = []
		h.set_highlights(sel, none, none, none)

func highlight_valid_moves(coord: Vector2i) -> void:
	if not pieces.has(coord): return
	var player: int = pieces[coord]["player"]
	var valid = get_valid_move_coords(coord)
	var moves:      Array[Vector2i] = []
	var captures:   Array[Vector2i] = []
	var friendlies: Array[Vector2i] = []
	for t in valid:
		if pieces.has(t):
			if pieces[t]["player"] == player: friendlies.append(t)
			else:                             captures.append(t)
		else:
			moves.append(t)
	var h = _get_highlight()
	if h:
		var gm := get_node_or_null("/root/GameManager")
		if gm: gm.apply_glow_to_highlight(h, player)
		h.set_highlights([coord] as Array[Vector2i], moves, captures, friendlies, true)

func clear_highlights() -> void:
	highlight_layer.clear()
	var h = _get_highlight()
	if h: h.clear()

## Fade all highlights to zero over `duration` seconds then clear.
func fade_out_highlights(duration: float = 0.5) -> void:
	highlight_layer.clear()
	var h = _get_highlight()
	if h: h.fade_out_and_clear(duration)
	else: clear_highlights()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var coord = board_layer.local_to_map(board_layer.to_local(get_global_mouse_position()))
	var gm    = get_node("/root/GameManager")
	if not _is_board_cell(coord): return
	if gm.current_state != 2: return
	if gm.selected_coord != Vector2i(-999, -999):
		if coord == gm.selected_coord:
			gm.select_piece_at(coord)
		elif is_valid_move(gm.selected_coord, coord):
			gm.move_selected_piece_to(coord)
	else:
		if pieces.has(coord) and pieces[coord]["player"] == gm.current_player:
			gm.select_piece_at(coord)

var _highlight: Node2D = null
func _get_highlight() -> Node2D:
	if _highlight == null:
		_highlight = get_node_or_null("HexHighlight")
	return _highlight
