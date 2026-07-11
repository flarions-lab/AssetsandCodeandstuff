extends RefCounted
class_name PlatformAuth

## PlatformAuth.gd — DEV STUB. Neither a Steam App ID nor a Google Play
## Console app exists yet, so there is no real platform SDK to call. This
## generates and persists a per-device fake token per platform so the
## account-linking flow (create/find/link, server-side in
## relay_server/platformAuth.js) can be exercised end-to-end before real
## credentials exist.
##
## Replace get_dev_token() call sites with real platform calls once available:
##   - steam:       Steam.getAuthSessionTicket() via the GodotSteam plugin
##   - google_play: a Google Sign-In / Play Games Services ID token, via
##                  an Android plugin (no such plugin is installed yet)

const SAVE_FILE := "user://platform_dev_tokens.cfg"

## DEV STUB — returns a token that is stable per platform per device (not
## per-account), so testing login/link/create repeatedly re-uses the same
## fake identity. Never used once real SDKs are wired in.
static func get_dev_token(platform: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_FILE) # ignore error — a missing file just means no tokens yet

	var existing: String = cfg.get_value("tokens", platform, "")
	if not existing.is_empty():
		return existing

	var new_token: String = "%s-%d" % [platform, randi()]
	cfg.set_value("tokens", platform, new_token)
	cfg.save(SAVE_FILE)
	return new_token
