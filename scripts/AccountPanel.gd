extends Panel
class_name AccountPanel

## AccountPanel.gd — login/register/switch-account UI, built in code.
##
## Opened automatically from MainMenu on first launch (no saved session token
## yet) and whenever the player clicks their username under the HEX-A-GONE
## title to switch accounts. Closes itself on a successful login/register.

var _logged_out_view: VBoxContainer
var _logged_in_view:  VBoxContainer
var _error_label:     Label
var _username_field:  LineEdit
var _password_field:  LineEdit
var _email_field:     LineEdit
var _welcome_label:   Label
var _platforms_label: Label
var _link_steam_btn:  Button
var _link_google_btn: Button
var _info_label:      Label
var _suppress_next_auto_close: bool = false

## Both shown regardless of OS for now, since both use PlatformAuth.gd's dev
## stub token and there's nothing platform-specific to gate on yet. Once real
## SDKs are added, restrict Steam to desktop and Google Play to Android
## (e.g. `OS.get_name() == "Android"`).
const _SHOW_STEAM_BTN: bool  = true
const _SHOW_GOOGLE_BTN: bool = true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(400, 460)
	offset_left = -200; offset_right = 200
	offset_top = -230; offset_bottom = 230
	visible = false

	var header := Label.new()
	header.text = "ACCOUNT"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 10; header.offset_bottom = 44
	add_child(header)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24; root.offset_top = 54
	root.offset_right = -24; root.offset_bottom = -20
	root.add_theme_constant_override("separation", 10)
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

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.modulate = Color(1, 0.4, 0.4)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_error_label)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.modulate = Color(0.6, 0.8, 1.0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_info_label)

	_logged_out_view = _build_logged_out_view()
	_logged_in_view  = _build_logged_in_view()
	root.add_child(_logged_out_view)
	root.add_child(_logged_in_view)

	AccountManager.login_succeeded.connect(_on_auth_succeeded)
	AccountManager.register_succeeded.connect(_on_auth_succeeded)
	AccountManager.login_failed.connect(func(err): _error_label.text = err)
	AccountManager.register_failed.connect(func(err): _error_label.text = err)
	AccountManager.platform_link_succeeded.connect(func(): _error_label.text = "")
	AccountManager.platform_link_failed.connect(func(err): _error_label.text = err)
	AccountManager.linked_platforms_updated.connect(_on_linked_platforms_updated)
	AccountManager.new_platform_account_created.connect(_on_new_platform_account_created)

	_refresh_view()

## Opens the panel showing the account form (i.e. to switch accounts).
## If already logged in, shows the "logged in as X" view with a switch option
## instead of forcing an immediate logout.
func open() -> void:
	visible = true
	_error_label.text = ""
	_info_label.text = ""
	_username_field.text = ""
	_password_field.text = ""
	_email_field.text = ""
	_refresh_view()

func _refresh_view() -> void:
	var logged_in := AccountManager.is_logged_in()
	_logged_out_view.visible = not logged_in
	_logged_in_view.visible  = logged_in
	if logged_in:
		_welcome_label.text = "Logged in as " + AccountManager.username
		AccountManager.fetch_linked_platforms()

func _on_linked_platforms_updated(platforms: Array) -> void:
	var lines: Array = []
	lines.append("Steam: " + ("Linked" if platforms.has("steam") else "Not linked"))
	lines.append("Google Play: " + ("Linked" if platforms.has("google_play") else "Not linked"))
	_platforms_label.text = "\n".join(lines)
	_link_steam_btn.visible  = _SHOW_STEAM_BTN and not platforms.has("steam")
	_link_google_btn.visible = _SHOW_GOOGLE_BTN and not platforms.has("google_play")

func _on_auth_succeeded() -> void:
	_error_label.text = ""
	if _suppress_next_auto_close:
		_suppress_next_auto_close = false
		_refresh_view()
		return
	visible = false

## A platform login just created a brand-new account rather than logging into
## a previously-linked one. Keep the panel open (see _on_auth_succeeded) and
## warn — this usually means the player forgot they already have an account
## and is about to end up with progress split across two accounts.
func _on_new_platform_account_created() -> void:
	_suppress_next_auto_close = true
	_info_label.text = "This platform wasn't linked to an existing account, so a new one was created.\n\nAlready have an account? Log out, log in with it, then use \"Link Steam\" / \"Link Google Play\" instead to keep your unlockables together."

func _build_logged_out_view() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	_username_field = LineEdit.new()
	_username_field.placeholder_text = "Username"
	v.add_child(_username_field)

	_email_field = LineEdit.new()
	_email_field.placeholder_text = "Email (for registration)"
	v.add_child(_email_field)

	_password_field = LineEdit.new()
	_password_field.placeholder_text = "Password"
	_password_field.secret = true
	v.add_child(_password_field)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(row)

	var login_btn := Button.new()
	login_btn.text = "LOG IN"
	login_btn.pressed.connect(func():
		_error_label.text = ""; _info_label.text = ""
		AccountManager.login(_username_field.text, _password_field.text))
	row.add_child(login_btn)

	var register_btn := Button.new()
	register_btn.text = "REGISTER"
	register_btn.pressed.connect(func():
		_error_label.text = ""; _info_label.text = ""
		AccountManager.register(_username_field.text, _email_field.text, _password_field.text))
	row.add_child(register_btn)

	var divider := Label.new()
	divider.text = "— or —"
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider.add_theme_font_size_override("font_size", 12)
	v.add_child(divider)

	if _SHOW_STEAM_BTN:
		var steam_btn := Button.new()
		steam_btn.text = "Continue with Steam"
		steam_btn.pressed.connect(func():
			_error_label.text = ""; _info_label.text = ""
			AccountManager.login_with_platform("steam", preload("res://scripts/PlatformAuth.gd").get_dev_token("steam")))
		v.add_child(steam_btn)

	if _SHOW_GOOGLE_BTN:
		var google_btn := Button.new()
		google_btn.text = "Continue with Google Play"
		google_btn.pressed.connect(func():
			_error_label.text = ""; _info_label.text = ""
			AccountManager.login_with_platform("google_play", preload("res://scripts/PlatformAuth.gd").get_dev_token("google_play")))
		v.add_child(google_btn)

	return v

func _build_logged_in_view() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	_welcome_label = Label.new()
	_welcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_welcome_label)

	var switch_btn := Button.new()
	switch_btn.text = "SWITCH ACCOUNT"
	switch_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	switch_btn.pressed.connect(func():
		AccountManager.logout()
		_username_field.text = ""
		_password_field.text = ""
		_email_field.text = ""
		_info_label.text = ""
		_refresh_view())
	v.add_child(switch_btn)

	_platforms_label = Label.new()
	_platforms_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_platforms_label.add_theme_font_size_override("font_size", 13)
	v.add_child(_platforms_label)

	_link_steam_btn = Button.new()
	_link_steam_btn.text = "Link Steam"
	_link_steam_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_link_steam_btn.pressed.connect(func():
		AccountManager.link_platform("steam", preload("res://scripts/PlatformAuth.gd").get_dev_token("steam")))
	v.add_child(_link_steam_btn)

	_link_google_btn = Button.new()
	_link_google_btn.text = "Link Google Play"
	_link_google_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_link_google_btn.pressed.connect(func():
		AccountManager.link_platform("google_play", preload("res://scripts/PlatformAuth.gd").get_dev_token("google_play")))
	v.add_child(_link_google_btn)

	return v
