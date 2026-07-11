extends Panel
class_name StorePanel

## StorePanel.gd — entitlement-gated store UI. Built entirely in code and
## added as a child panel from MainMenu.gd, following the same "build once,
## toggle .visible" pattern as the other menu panels.
##
## Ownership is always shown from AccountManager.entitlements, which is only
## ever populated from the server's /account/me response — never asserted
## locally. Login/registration itself lives in AccountPanel (shared with the
## username button on the main menu) rather than being duplicated here.

## Set by MainMenu right after both panels are created.
var account_panel: Panel = null

var _catalog_http: HTTPRequest
var _items: Array = []

var _logged_out_view: VBoxContainer
var _logged_in_view:  VBoxContainer
var _welcome_label:   Label
var _item_list:       VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 80; offset_top = 60
	offset_right = -80; offset_bottom = -60
	visible = false

	_catalog_http = HTTPRequest.new()
	add_child(_catalog_http)
	_catalog_http.request_completed.connect(_on_catalog_received)

	var header := Label.new()
	header.text = "STORE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 10; header.offset_bottom = 50
	add_child(header)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40; root.offset_top = 60
	root.offset_right = -40; root.offset_bottom = -40
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	## Added AFTER root so it sits on top for input priority — see the same
	## fix in MainMenu.gd's Hex Drones panel for why ordering matters here.
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -46; close_btn.offset_top = 10
	close_btn.offset_right = -10; close_btn.offset_bottom = 46
	close_btn.pressed.connect(func(): visible = false)
	add_child(close_btn)

	_logged_out_view = _build_logged_out_view()
	_logged_in_view  = _build_logged_in_view()
	root.add_child(_logged_out_view)
	root.add_child(_logged_in_view)

	AccountManager.login_succeeded.connect(_refresh_view)
	AccountManager.register_succeeded.connect(_refresh_view)
	AccountManager.entitlements_updated.connect(func(_e): _refresh_item_rows())

	_refresh_view()

func open() -> void:
	visible = true
	_refresh_view()

func _refresh_view() -> void:
	var logged_in := AccountManager.is_logged_in()
	_logged_out_view.visible = not logged_in
	_logged_in_view.visible  = logged_in
	if logged_in:
		_welcome_label.text = "Logged in as " + AccountManager.username
		_fetch_catalog()

func _build_logged_out_view() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var msg := Label.new()
	msg.text = "Log in to view the store."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)

	var login_btn := Button.new()
	login_btn.text = "LOG IN"
	login_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	login_btn.pressed.connect(func():
		visible = false
		if account_panel: account_panel.open())
	v.add_child(login_btn)

	return v

func _build_logged_in_view() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	_welcome_label = Label.new()
	_welcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_welcome_label)

	_item_list = VBoxContainer.new()
	_item_list.add_theme_constant_override("separation", 6)
	v.add_child(_item_list)

	return v

func _fetch_catalog() -> void:
	_catalog_http.request(AccountManager.API_BASE + "/store/items")

func _on_catalog_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200: return
	var json = JSON.parse_string(body.get_string_from_utf8())
	_items = json.get("items", []) if json is Dictionary else []
	_refresh_item_rows()

func _refresh_item_rows() -> void:
	if _item_list == null: return
	for child in _item_list.get_children():
		child.queue_free()
	for item in _items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_item_list.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = "%s — $%.2f" % [item.get("name", ""), item.get("price_cents", 0) / 100.0]
		name_lbl.custom_minimum_size = Vector2(260, 0)
		row.add_child(name_lbl)

		var owned: bool = AccountManager.entitlements.has(item.get("sku", ""))
		var action_btn := Button.new()
		action_btn.text = "OWNED" if owned else "BUY"
		action_btn.disabled = owned
		var item_id: int = item.get("id", -1)
		action_btn.pressed.connect(func(): AccountManager.purchase(item_id))
		row.add_child(action_btn)
