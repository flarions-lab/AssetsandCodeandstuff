extends Node

## TutorialManager.gd — interactive in-game tutorial overlay.
## Start with TutorialManager.start_tutorial() before loading the game scene.

var tutorial_mode: bool = false
var _step:         int  = 0

var _canvas:    CanvasLayer = null
var _panel:     Panel       = null
var _title_lbl: Label       = null
var _body_lbl:  Label       = null
var _counter:   Label       = null
var _next_btn:  Button      = null
var _prev_btn:  Button      = null
var _hint_lbl:  Label       = null   ## floating pointer emoji

## Each step: title, body text, optional hint emoji + screen position
const STEPS: Array = [
	{
		"title": "Camera Controls",
		"body":  "Rotate the board:\n  PC — Right-click + drag left / right\n  Mobile — One stationary finger 1 slides left / right\n\nZoom:\n  PC — Scroll wheel\n  Mobile — Pinch fingers apart / together\n\nPan:\n  Left-click drag  /  single-finger drag\n\n▶  Try rotating the board, then press Next.",
		"hint": "", "hint_pos": Vector2(-1, -1)
	},
	{
		"title": "Rolling the Dice",
		"body":  "Every turn starts with a dice roll.\n\nThe result gives you 3–5 Movement Points to spend this turn.\n\n▶  Click Roll Dice (top-right) to try it.",
		"hint": "👆", "hint_pos": Vector2(980, 52)
	},
	{
		"title": "Selecting & Moving",
		"body":  "Click one of your pieces to select it.\n\nHighlighted hexes show where it can move.\nClick a highlighted hex to move there.\n\nEach move costs 1 Movement Point.\n\n▶  Select a piece and make a move.",
		"hint": "", "hint_pos": Vector2(-1, -1)
	},
	{
		"title": "Single-Blade Pieces",
		"body":  "The glowing lines on a piece are its BLADES.\n\nEach blade points to one direction you can move.\n\nA single-blade piece can only step in that one direction — but you can spend multiple points to move it multiple times.",
		"hint": "", "hint_pos": Vector2(-1, -1)
	},
	{
		"title": "Multi-Blade Pieces",
		"body":  "Pieces with MULTIPLE blades can move \"Diagonal\" using the corners instead of the side faces.\n\nWhen moving this way you will always land on the same color tile as you are on.",
		"hint": "", "hint_pos": Vector2(-1, -1)
	},
	{
		"title": "Edge Tiles & Rotation",
		"body":  "Tile on the edge can ROTATE.\n\n1. Select a piece along the edge .\n2. Click  'Rotate +60°'  to preview a 60° clockwise spin.\n3. Moving the piece —  commits the rotation.\n\n⚠  Rotate + Move costs 2 points total.\n    Rotate only (tap the same piece again) costs 1.\n\n▶  Try rotating an edge piece.",
		"hint": "👆", "hint_pos": Vector2(10, 500)
	},
	{
		"title": "Capturing Enemies",
		"body":  "Move your piece ONTO an enemy hex to capture it.\n\nThe enemy is removed from the board immediately.\n\nThe game ends the instant the last enemy is destroyed!\n\nChain multiple captures in one turn to sweep the board.",
		"hint": "", "hint_pos": Vector2(-1, -1)
	},
	{
		"title": "You're Ready!  🏆",
		"body":  "Eliminate ALL enemy Hex-Drones to win.\n\nKey reminders:\n  • 3–5 moves per turn\n  • Rotate + Move = 2 points\n  • Chain captures for maximum damage\n  • Defend threatened pieces\n\nGood luck, Commander!",
		"hint": "", "hint_pos": Vector2(-1, -1)
	}
]

func _ready() -> void:
	_build_overlay()
	_set_overlay_visible(false)
	get_tree().node_added.connect(_on_node_added)

# ---------------------------------------------------------------------------
func start_tutorial() -> void:
	tutorial_mode = true
	_step = 0

func end_tutorial() -> void:
	tutorial_mode = false
	_set_overlay_visible(false)

# ---------------------------------------------------------------------------
func _on_node_added(node: Node) -> void:
	if node.name == "Main" and node.get_parent() == get_tree().root:
		if tutorial_mode:
			call_deferred("_show_step")

# ---------------------------------------------------------------------------
func _build_overlay() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 50
	add_child(_canvas)

	_panel = Panel.new()
	_panel.anchor_left   = 0.0; _panel.anchor_top    = 0.0
	_panel.anchor_right  = 0.0; _panel.anchor_bottom = 0.0
	_panel.offset_left   = 8.0;   _panel.offset_top    = 152.0
	_panel.offset_right  = 360.0; _panel.offset_bottom = 512.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.93)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left   = 1; style.border_width_right  = 1
	style.border_width_top    = 1; style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	_panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(_panel)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14; root.offset_top = 10
	root.offset_right = -14; root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 18)
	root.add_child(_title_lbl)

	var div := Label.new()
	div.text = "────────────────────"
	div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	div.add_theme_font_size_override("font_size", 11)
	root.add_child(div)

	_body_lbl = Label.new()
	_body_lbl.autowrap_mode       = TextServer.AUTOWRAP_WORD
	_body_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_lbl.add_theme_font_size_override("font_size", 13)
	root.add_child(_body_lbl)

	_counter = Label.new()
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.add_theme_font_size_override("font_size", 11)
	root.add_child(_counter)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(btn_row)

	_prev_btn = Button.new()
	_prev_btn.text = "◀ Prev"
	_prev_btn.custom_minimum_size = Vector2(88, 34)
	_prev_btn.pressed.connect(_on_prev)
	btn_row.add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(108, 34)
	_next_btn.pressed.connect(_on_next)
	btn_row.add_child(_next_btn)

	var skip := Button.new()
	skip.text = "Skip ✕"
	skip.custom_minimum_size = Vector2(78, 34)
	skip.pressed.connect(end_tutorial)
	btn_row.add_child(skip)

	## Floating hint — positioned per step
	_hint_lbl = Label.new()
	_hint_lbl.add_theme_font_size_override("font_size", 30)
	_hint_lbl.visible = false
	_canvas.add_child(_hint_lbl)

func _set_overlay_visible(v: bool) -> void:
	if _panel:    _panel.visible    = v
	if _hint_lbl: _hint_lbl.visible = false

func _show_step() -> void:
	if not tutorial_mode: return
	_set_overlay_visible(true)

	var step: Dictionary = STEPS[_step]
	_title_lbl.text = step.get("title", "")
	_body_lbl.text  = step.get("body",  "")
	_counter.text   = "Step %d / %d" % [_step + 1, STEPS.size()]
	_next_btn.text  = "Finish ✓" if _step == STEPS.size() - 1 else "Next ▶"
	_prev_btn.disabled = (_step == 0)

	var hpos: Vector2  = step.get("hint_pos", Vector2(-1, -1))
	var htxt: String   = step.get("hint", "")
	if hpos.x >= 0.0 and htxt != "":
		_hint_lbl.text     = htxt
		_hint_lbl.position = hpos
		_hint_lbl.visible  = true
	else:
		_hint_lbl.visible = false

func _on_next() -> void:
	if _step >= STEPS.size() - 1:
		end_tutorial()
		return
	_step += 1
	_show_step()

func _on_prev() -> void:
	if _step <= 0: return
	_step -= 1
	_show_step()
