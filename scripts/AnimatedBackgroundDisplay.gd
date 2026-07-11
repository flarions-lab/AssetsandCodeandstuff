extends CanvasLayer
## AnimatedBackgroundDisplay.gd — lives on the "BackgroundLayer" CanvasLayer in
## node_2d.tscn (the board scene), behind everything else (layer = -10).
##
## Applies whichever animated background the player picked in the
## Hex Drones > Backgrounds tab (BackgroundManager.selected_id), stretched to
## fill the screen. If no background is selected, this layer just stays hidden
## and the board's normal look shows through.

@onready var _rect: TextureRect = $TextureRect
@onready var _color_rect: ColorRect = $ColorRect

func _ready() -> void:
	_apply()
	BackgroundManager.background_changed.connect(_apply)

func _apply() -> void:
	if BackgroundManager.selected_id.begins_with(BackgroundManager.SOLID_COLOR_PREFIX):
		_rect.texture = null
		_rect.visible = false
		_color_rect.color = BackgroundManager.get_custom_color(BackgroundManager.selected_id)
		_color_rect.visible = true
		visible = true
		return

	_color_rect.visible = false
	var tex: Texture2D = BackgroundManager.build_selected_texture()
	_rect.texture = tex
	_rect.visible = tex != null
	visible = tex != null
	var b: float = BackgroundManager.brightness_for(BackgroundManager.selected_id)
	_rect.modulate = Color(b, b, b, 1.0)
