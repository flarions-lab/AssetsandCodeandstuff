extends Panel
class_name UpdatePanel

## UpdatePanel.gd — soft, dismissible "update available" UI, built in code.
## Opened from MainMenu's update badge (only shown once UpdateManager reports
## a newer version). Never blocks play — closing it or picking "Later" has no
## effect on the player's ability to keep playing the current version.

var _status_label:   Label
var _progress_bar:   ProgressBar
var _download_btn:   Button
var _restart_btn:    Button
var _later_btn:      Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(360, 220)
	offset_left = -180; offset_right = 180
	offset_top = -110; offset_bottom = 110
	visible = false

	var header := Label.new()
	header.text = "UPDATE AVAILABLE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 10; header.offset_bottom = 40
	add_child(header)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24; root.offset_top = 50
	root.offset_right = -24; root.offset_bottom = -20
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	## Added AFTER root so it sits on top for input priority — see the same
	## fix in MainMenu.gd's Hex Drones panel for why ordering matters here.
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -42; close_btn.offset_top = 8
	close_btn.offset_right = -10; close_btn.offset_bottom = 40
	close_btn.pressed.connect(func(): visible = false)
	add_child(close_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.add_theme_font_size_override("font_size", 14)
	root.add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = true
	_progress_bar.custom_minimum_size = Vector2(260, 22)
	_progress_bar.visible = false
	root.add_child(_progress_bar)

	_download_btn = Button.new()
	_download_btn.text = "DOWNLOAD & UPDATE"
	_download_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_download_btn.pressed.connect(_on_download_pressed)
	root.add_child(_download_btn)

	_restart_btn = Button.new()
	_restart_btn.text = "RESTART NOW"
	_restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_btn.visible = false
	_restart_btn.pressed.connect(func(): UpdateManager.restart_now())
	root.add_child(_restart_btn)

	_later_btn = Button.new()
	_later_btn.text = "LATER"
	_later_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_later_btn.pressed.connect(func(): visible = false)
	root.add_child(_later_btn)

	UpdateManager.update_download_failed.connect(_on_download_failed)
	UpdateManager.update_ready_to_restart.connect(_on_ready_to_restart)
	UpdateManager.update_download_progress.connect(_on_download_progress)

func open(version: String) -> void:
	visible = true
	_status_label.text = "Version %s is available." % version
	_download_btn.visible  = true
	_restart_btn.visible   = false
	_progress_bar.visible  = false
	_progress_bar.value    = 0.0

func _on_download_pressed() -> void:
	_download_btn.visible = false
	_progress_bar.visible = true
	_progress_bar.value   = 0.0
	_status_label.text = "Downloading update…"
	UpdateManager.start_download()

func _on_download_progress(fraction: float) -> void:
	_progress_bar.value = fraction

func _on_download_failed(reason: String) -> void:
	_status_label.text = reason
	_progress_bar.visible = false
	_download_btn.visible = true

func _on_ready_to_restart() -> void:
	_status_label.text = "Update downloaded. Restart to apply it — or keep\nplaying now and it'll apply next time you launch."
	_progress_bar.visible = false
	_restart_btn.visible = true
