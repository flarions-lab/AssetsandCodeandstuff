extends CanvasLayer

## AchievementToast.gd — a small queued popup for achievement/unlock
## notifications. Created as a child of the AchievementManager autoload, so it
## renders above whatever scene is active (menu or in-game) and survives scene
## changes.

var _queue: Array = [] ## [{text, duration}, ...]
var _busy: bool = false

var _panel: PanelContainer
var _label: Label

func _ready() -> void:
	layer = 20

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_top    = 40
	_panel.offset_left   = -220
	_panel.offset_right  = 220
	_panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_panel.modulate      = Color(1, 1, 1, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.17, 0.94)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left   = 20
	style.content_margin_right  = 20
	style.content_margin_top    = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 18)
	_panel.add_child(_label)

func show_toast(text: String, duration: float = 2.2) -> void:
	_queue.append({"text": text, "duration": duration})
	_process_queue()

func _process_queue() -> void:
	if _busy or _queue.is_empty(): return
	_busy = true
	var item: Dictionary = _queue.pop_front()
	_label.text = item["text"]
	_panel.modulate = Color(1, 1, 1, 0)

	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tw.tween_interval(item["duration"])
	tw.tween_property(_panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		_busy = false
		_process_queue())
