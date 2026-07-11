extends Node

## UpdateManager.gd — checks for a newer game version on launch and, if the
## player accepts, downloads it and applies it via a .pck content swap
## (Godot's ProjectSettings.load_resource_pack — updates scripts/scenes/
## assets without touching the executable). Registered FIRST in
## project.godot's [autoload] list so a previously-downloaded update is
## applied before any other autoload uses game content.
##
## Soft/non-blocking: nothing here ever prevents play. A found update just
## downloads in the background and offers a restart; ignoring it is fine —
## it still applies automatically the next time the player naturally
## relaunches the game, since it's already staged in user://update.pck.
##
## IMPORTANT: Godot does not remember a loaded resource pack across process
## restarts — every single launch has to call load_resource_pack() again to
## get the updated content. The "current version" this class reports is
## therefore NEVER a bare remembered flag — it's only set the moment
## load_resource_pack() actually, verifiably succeeds, fresh, this boot. Two
## real bugs have existed here from trusting a remembered flag instead of a
## fresh verification:
##   1. Clearing the staged record the first time it applied, which made the
##      update work for exactly one session and then silently revert (Godot
##      forgets the pack next launch) — "update available" showed up again
##      forever.
##   2. Recording success at DOWNLOAD time rather than at LOAD time — so if
##      load_resource_pack() ever failed on a later launch (reported in the
##      wild on Android; cause unconfirmed without a device to test), the
##      game had already told itself "you're up to date" and silently never
##      re-offered the update or reported anything was wrong.
## Don't reintroduce either pattern — "applied" must always mean "verified
## just now," never "recorded once, trust forever."

const API_BASE := "https://hex-relay-server-2.onrender.com"
const STATE_FILE := "user://update_state.cfg"
const DOWNLOAD_PATH := "user://update_download.pck"
const STAGED_PCK_PATH := "user://update.pck"

signal update_available(version: String)
signal update_download_failed(reason: String)
signal update_ready_to_restart
signal update_download_progress(fraction: float) ## 0.0–1.0

## True only for the boot where load_resource_pack() was actually just
## confirmed to succeed — never inferred from a saved flag.
var _applied_version: String = ""
## Set if a staged pack exists but failed to load this boot — surfaced in the
## version label (MainMenu.gd) so this is visible instead of a silent no-op.
var _last_load_failed: bool = false

var _latest_version: String = ""
var _latest_pck_url: String = ""
var _latest_sha256: String = ""
var _downloading: bool = false

## Godot's HTTPRequest has no built-in timeout by default, so a connection
## that stalls mid-download (common on mobile — screen lock, network handoff,
## a dropped redirect) can otherwise sit forever with the progress bar frozen
## and no error ever firing. Tracked here so a truly-dead download surfaces a
## real failure instead of silently hanging (reported in the wild: a download
## that ran "for a while" then just never finished, with no error shown).
var _last_downloaded_bytes: int = -1
var _stall_seconds: float = 0.0
const STALL_TIMEOUT_SEC: float = 20.0

var _check_http:    HTTPRequest
var _download_http: HTTPRequest

func _ready() -> void:
	_apply_staged_pack_if_any()

	_check_http = HTTPRequest.new()
	add_child(_check_http)
	_check_http.request_completed.connect(_on_check_completed)

	_download_http = HTTPRequest.new()
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_completed)

	set_process(false)

	## Slight delay so this never competes with the very first frame's setup.
	get_tree().create_timer(1.0).timeout.connect(check_for_update)

## Mobile OSes (Android especially) frequently don't actually kill the app
## process when the player "closes" it — backgrounding and resuming the same
## still-running process is the common case, not a fresh relaunch. Since
## _ready() only runs once per real process lifetime, a version check on
## resume is the only way to reliably notice a newer release without
## requiring the player to force-stop the app. This only refreshes the
## "update available" check itself — actually applying a pending update still
## requires a genuine fresh process start, per the class doc comment above.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		check_for_update()

func _process(delta: float) -> void:
	if not _downloading: return
	var downloaded: int = _download_http.get_downloaded_bytes()

	if downloaded != _last_downloaded_bytes:
		_last_downloaded_bytes = downloaded
		_stall_seconds = 0.0
	else:
		_stall_seconds += delta
		if _stall_seconds >= STALL_TIMEOUT_SEC:
			_cancel_stalled_download()
			return

	var total: int = _download_http.get_body_size()
	if total <= 0: return ## server didn't send Content-Length — can't show a fraction yet
	update_download_progress.emit(clampf(float(downloaded) / float(total), 0.0, 1.0))

func _cancel_stalled_download() -> void:
	_downloading = false
	set_process(false)
	_download_http.cancel_request()
	if FileAccess.file_exists(DOWNLOAD_PATH):
		DirAccess.remove_absolute(DOWNLOAD_PATH)
	update_download_failed.emit("Download stalled — no progress for %d seconds. Check your connection and try again." % int(STALL_TIMEOUT_SEC))

func get_current_version() -> String:
	if not _applied_version.is_empty():
		return _applied_version
	return str(ProjectSettings.get_setting("application/config/version", "1.0.0"))

## Diagnostic string for a small on-screen label (see MainMenu.gd) — makes a
## silent load failure visible instead of an unexplained "nothing happened."
func get_status_suffix() -> String:
	if _last_load_failed:
		return " (update failed to apply)"
	return ""

func check_for_update() -> void:
	## The editor never applies a staged patch (see _apply_staged_pack_if_any),
	## so offering one here would just be a dead-end "update available" badge
	## the player/dev can never actually act on. Only exported builds check.
	if OS.has_feature("editor"): return
	_check_http.request(API_BASE + "/version")

func start_download() -> void:
	if _latest_pck_url.is_empty(): return
	_download_http.set_download_file(DOWNLOAD_PATH)
	_download_http.request(_latest_pck_url)
	_downloading = true
	_last_downloaded_bytes = -1
	_stall_seconds = 0.0
	set_process(true)

## Relaunches on desktop (spawns a fresh process, then quits this one). Uses
## OS.create_instance() — Godot's own "launch another copy of this game"
## primitive (4.2+), which handles executable path/working directory more
## reliably than manually resolving OS.get_executable_path(). The new window
## may not immediately grab focus (an OS-level restriction, not something we
## can force) — that's cosmetic; the new process still boots and applies the
## update regardless of whether its window is focused.
## On platforms with no relaunch primitive (Android), just quits — the
## staged update applies automatically on the next natural launch, per
## _apply_staged_pack_if_any() above. NOTE: on Android specifically, "quit"
## frequently just backgrounds the process rather than killing it — the
## player may need to fully swipe it away or Force Stop it for a launch to
## actually be fresh.
func restart_now() -> void:
	## Brief pause before actually terminating — cheap insurance in case the
	## OS hasn't yet durably flushed the just-written state file/pack to disk
	## before the process dies (plausible on Android if the process is killed
	## very soon after a write).
	await get_tree().create_timer(0.3).timeout
	if OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos"):
		OS.create_instance(OS.get_cmdline_args())
	get_tree().quit()

func _on_check_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200: return
	var json = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = json if json is Dictionary else {}

	var version: String = data.get("version", "")
	var pck_url = data.get("pck_url", null)
	if version.is_empty() or pck_url == null: return
	if not _is_newer(version, get_current_version()): return

	_latest_version = version
	_latest_pck_url  = pck_url
	_latest_sha256   = data.get("sha256", "")
	update_available.emit(version)

func _on_download_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	set_process(false)

	if response_code != 200:
		update_download_failed.emit("Download failed (HTTP %d)" % response_code)
		return

	## Integrity check — this file gets loaded as executable game content, so
	## a hash mismatch (corrupt download or tampering) must never be applied.
	var actual_hash := FileAccess.get_sha256(DOWNLOAD_PATH)
	if _latest_sha256.is_empty() or actual_hash != _latest_sha256:
		DirAccess.remove_absolute(DOWNLOAD_PATH)
		update_download_failed.emit("Downloaded update failed verification and was discarded.")
		return

	## Stage the verified download. Must confirm the rename actually succeeds
	## before recording it — otherwise a silent failure leaves nothing staged
	## while the game still thinks there's something to apply.
	if FileAccess.file_exists(STAGED_PCK_PATH):
		DirAccess.remove_absolute(STAGED_PCK_PATH)
	var dir := DirAccess.open("user://")
	var rename_ok: bool = dir != null and dir.rename(DOWNLOAD_PATH.get_file(), STAGED_PCK_PATH.get_file()) == OK
	if not rename_ok:
		DirAccess.remove_absolute(DOWNLOAD_PATH)
		update_download_failed.emit("Could not stage the downloaded update. Please try again.")
		return

	## Eagerly try loading it right now, in this same session, purely as a
	## validation smoke test — merging the overlay is harmless/idempotent even
	## though this session's already-running scripts won't actually change
	## until a genuine restart. If it fails THIS immediately, the download
	## itself is bad (wrong export format, corrupt content, etc.) — fail the
	## whole update now rather than only discovering that after a pointless
	## restart cycle.
	if not ProjectSettings.load_resource_pack(STAGED_PCK_PATH):
		DirAccess.remove_absolute(STAGED_PCK_PATH)
		update_download_failed.emit("This update could not be loaded on this device and was discarded.")
		return

	## Record which version is staged — NOT "applied". Whether it's actually
	## running is re-verified fresh on every boot by _apply_staged_pack_if_any().
	## Must confirm this save actually succeeds — an unchecked failure here
	## would leave the pack file present but the record of it silently
	## missing, which looks identical to "nothing happened" on next launch.
	var cfg := ConfigFile.new()
	cfg.load(STATE_FILE) # ignore error — a missing file just means first update ever
	cfg.set_value("update", "staged_version", _latest_version)
	if cfg.save(STATE_FILE) != OK:
		DirAccess.remove_absolute(STAGED_PCK_PATH)
		update_download_failed.emit("Could not save update state. Please try again.")
		return

	update_ready_to_restart.emit()

## Reloads the currently-staged update pack, if any, and ONLY reports it as
## the current version if load_resource_pack() actually succeeds THIS boot.
## Runs on every launch — Godot never remembers a pack load across restarts.
func _apply_staged_pack_if_any() -> void:
	## Never overlay a staged patch when running from the editor (this covers
	## both the editor UI and hitting Play/F5 — both carry the "editor"
	## feature tag, unlike a real exported build). Otherwise a leftover
	## user://update.pck from earlier testing silently shadows every current
	## source edit on every single editor run, forever, with no visible sign
	## anything is wrong — exactly what happened here: a stale staged v1.0.7
	## pack made scrollbar-width and version-label fixes look like they never
	## took effect, when the editor was actually still running old overlaid
	## content. Exported/production builds are unaffected by this guard.
	if OS.has_feature("editor"):
		return
	var cfg := ConfigFile.new()
	if cfg.load(STATE_FILE) != OK: return
	var staged_version: String = cfg.get_value("update", "staged_version", "")
	if staged_version.is_empty(): return

	if not FileAccess.file_exists(STAGED_PCK_PATH):
		## Nothing to reload (e.g. the staged file went missing) — clear the
		## stale marker; check_for_update() will just offer the update again.
		cfg.set_value("update", "staged_version", "")
		cfg.save(STATE_FILE)
		return

	if ProjectSettings.load_resource_pack(STAGED_PCK_PATH):
		_applied_version = staged_version
		_last_load_failed = false
	else:
		## Do NOT record this as applied — get_current_version() correctly
		## falls back to the original baseline, so check_for_update() keeps
		## legitimately offering the update instead of silently giving up.
		_last_load_failed = true
		push_warning("UpdateManager: load_resource_pack failed for staged update %s" % staged_version)

## Simple dotted-integer version compare ("1.2.10" > "1.2.9"). Treats
## missing/malformed segments as 0.
func _is_newer(a: String, b: String) -> bool:
	var a_parts := a.split(".")
	var b_parts := b.split(".")
	for i in maxi(a_parts.size(), b_parts.size()):
		var a_num: int = int(a_parts[i]) if i < a_parts.size() else 0
		var b_num: int = int(b_parts[i]) if i < b_parts.size() else 0
		if a_num != b_num:
			return a_num > b_num
	return false
