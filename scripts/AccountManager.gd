extends Node

## AccountManager.gd — cross-platform account login, session token, and
## server-owned entitlements (owned store items). Entitlements are always
## fetched fresh from the relay server; the local cache is for UI display
## only and is never treated as the source of truth for ownership.

const SAVE_FILE := "user://account.cfg"
const API_BASE := "https://hex-relay-server-2.onrender.com"

signal login_succeeded
signal login_failed(error: String)
signal register_succeeded
signal register_failed(error: String)
signal entitlements_updated(entitlements: Array)
signal platform_link_succeeded
signal platform_link_failed(error: String)
signal linked_platforms_updated(platforms: Array)
## Fired instead of login_succeeded when a platform login creates a brand-new
## account rather than logging into a previously-linked one — the UI should
## warn the player, since it usually means they forgot they already have an
## account and are about to fragment their progress across two accounts.
signal new_platform_account_created

var username: String = "Player"
var token: String = ""
var entitlements: Array = []
var linked_platforms: Array = []

var _http: HTTPRequest
## register/login/refresh/purchase/link/etc. all share this one HTTPRequest
## node, and HTTPRequest can only run one request at a time — queue instead
## of firing directly, since e.g. refresh_entitlements() at boot and
## fetch_linked_platforms() from AccountPanel opening moments later can
## easily overlap otherwise ("HTTPRequest is processing a request" error).
var _http_busy: bool = false
var _http_queue: Array = [] ## [{kind, url, headers, method, body}, ...]
var _current_kind: String = "" ## kind of the request _http is running right now

## Achievement unlocks get their own request queue/node — AchievementManager may
## call unlock_achievement() several times in a burst (e.g. syncing local-only
## progress up on first login), and HTTPRequest only handles one call at a time.
var _achievement_http: HTTPRequest
var _achievement_queue: Array = []
var _achievement_busy: bool = false

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_achievement_http = HTTPRequest.new()
	add_child(_achievement_http)
	_achievement_http.request_completed.connect(_on_achievement_request_completed)

	_load()
	if not token.is_empty():
		refresh_entitlements()

func is_logged_in() -> bool:
	return not token.is_empty()

func register(new_username: String, email: String, password: String) -> void:
	var body := JSON.stringify({"username": new_username, "email": email, "password": password})
	_enqueue_request("register", API_BASE + "/auth/register", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func login(username_or_email: String, password: String) -> void:
	var body := JSON.stringify({"username_or_email": username_or_email, "password": password})
	_enqueue_request("login", API_BASE + "/auth/login", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

## Signs in via a Steam/Google Play identity — creates a new account the first
## time this device/identity is seen, or logs into the account it was
## previously linked to. `platform` is "steam" or "google_play"; `token` comes
## from PlatformAuth.gd (a dev-stub token until real platform SDKs are added).
func login_with_platform(platform: String, platform_token: String) -> void:
	var body := JSON.stringify({"platform": platform, "token": platform_token})
	_enqueue_request("platform_login", API_BASE + "/auth/platform-login", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

## Links a Steam/Google Play identity to the currently-logged-in account.
func link_platform(platform: String, platform_token: String) -> void:
	if token.is_empty(): return
	var body := JSON.stringify({"platform": platform, "token": platform_token})
	_enqueue_request("link_platform", API_BASE + "/account/link-platform", ["Authorization: Bearer " + token, "Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func fetch_linked_platforms() -> void:
	if token.is_empty(): return
	_enqueue_request("platforms", API_BASE + "/account/platforms", ["Authorization: Bearer " + token], HTTPClient.METHOD_GET)

func logout() -> void:
	if not token.is_empty():
		_enqueue_request("logout", API_BASE + "/auth/logout", ["Authorization: Bearer " + token], HTTPClient.METHOD_POST)
	token = ""
	entitlements = []
	_save()
	entitlements_updated.emit(entitlements)

func refresh_entitlements() -> void:
	if token.is_empty(): return
	_enqueue_request("me", API_BASE + "/account/me", ["Authorization: Bearer " + token], HTTPClient.METHOD_GET)

func purchase(item_id: int) -> void:
	if token.is_empty(): return
	var body := JSON.stringify({"item_id": item_id})
	_enqueue_request("purchase", API_BASE + "/store/purchase", ["Authorization: Bearer " + token, "Content-Type: application/json"], HTTPClient.METHOD_POST, body)

## Requests the server grant every asset `achievement_id` unlocks. Idempotent
## server-side, so safe to call for an already-synced achievement. No-op if
## logged out — AchievementManager keeps local-only progress local in that case.
func unlock_achievement(achievement_id: String) -> void:
	if token.is_empty(): return
	if _achievement_queue.has(achievement_id): return
	_achievement_queue.append(achievement_id)
	_process_achievement_queue()

func _process_achievement_queue() -> void:
	if _achievement_busy or _achievement_queue.is_empty(): return
	_achievement_busy = true
	var achievement_id: String = _achievement_queue.pop_front()
	var body := JSON.stringify({"achievement_id": achievement_id})
	_achievement_http.request(API_BASE + "/account/unlock-achievement", ["Authorization: Bearer " + token, "Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _on_achievement_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_achievement_busy = false
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		var data: Dictionary = json if json is Dictionary else {}
		entitlements = data.get("entitlements", entitlements)
		_save()
		entitlements_updated.emit(entitlements)
	_process_achievement_queue()

func _enqueue_request(kind: String, url: String, headers: PackedStringArray, method: int, body: String = "") -> void:
	_http_queue.append({"kind": kind, "url": url, "headers": headers, "method": method, "body": body})
	_process_http_queue()

func _process_http_queue() -> void:
	if _http_busy or _http_queue.is_empty(): return
	_http_busy = true
	var req: Dictionary = _http_queue.pop_front()
	_http.request(req["url"], req["headers"], req["method"], req["body"])
	## Stashed on the request dict rather than a separate _pending var, since
	## queued requests would otherwise race to overwrite _pending before their
	## own response arrives.
	_current_kind = req["kind"]

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http_busy = false
	var kind := _current_kind
	_current_kind = ""
	var json = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = json if json is Dictionary else {}

	match kind:
		"register":
			if response_code == 200:
				token = data.get("token", "")
				username = data.get("username", username)
				_save()
				register_succeeded.emit()
				refresh_entitlements()
			else:
				register_failed.emit(data.get("error", "Registration failed"))

		"login":
			if response_code == 200:
				token = data.get("token", "")
				username = data.get("username", username)
				_save()
				login_succeeded.emit()
				refresh_entitlements()
			else:
				login_failed.emit(data.get("error", "Login failed"))

		"platform_login":
			if response_code == 200:
				token = data.get("token", "")
				username = data.get("username", username)
				_save()
				## Emitted before login_succeeded so a listener (AccountPanel)
				## can flag "don't auto-close" before login_succeeded's
				## handler would otherwise close the dialog immediately.
				if data.get("is_new_account", false):
					new_platform_account_created.emit()
				login_succeeded.emit()
				refresh_entitlements()
			else:
				login_failed.emit(data.get("error", "Login failed"))

		"me":
			if response_code == 200:
				username = data.get("username", username)
				entitlements = data.get("entitlements", [])
				_save()
				entitlements_updated.emit(entitlements)

		"purchase":
			if response_code == 200:
				entitlements = data.get("entitlements", [])
				_save()
				entitlements_updated.emit(entitlements)

		"link_platform":
			if response_code == 200:
				platform_link_succeeded.emit()
				fetch_linked_platforms()
			else:
				platform_link_failed.emit(data.get("error", "Linking failed"))

		"platforms":
			if response_code == 200:
				linked_platforms = data.get("platforms", [])
				linked_platforms_updated.emit(linked_platforms)

		"logout":
			pass ## token/entitlements already cleared synchronously in logout()

	_process_http_queue()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) == OK:
		username = cfg.get_value("account", "username", "Player")
		token = cfg.get_value("account", "token", "")

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("account", "username", username)
	cfg.set_value("account", "token", token)
	cfg.save(SAVE_FILE)
