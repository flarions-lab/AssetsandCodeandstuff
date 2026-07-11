extends Node

## NetworkManager.gd — WebSocket relay-based online multiplayer.

const RELAY_URL := "wss://hex-relay-server-2.onrender.com"

signal lobby_ready(code: String)
signal peer_joined
signal peer_left
signal connected_to_host
signal connection_failed
signal game_start_received
signal lobby_list_received(lobbies: Array)
signal matchmake_waiting
signal matchmake_matched
signal opponent_username_received(username: String)
## Rejoin / state-sync
signal game_state_received(state: Dictionary)   ## opponent sent us the live board
signal opponent_forfeited                        ## opponent chose a fresh game (we win)

var is_multiplayer:      bool   = false
var is_host:             bool   = false
var opponent_username:   String = "Opponent"
var last_lobby_code:     String = ""

var _ws:              WebSocketPeer = null
var _ws_state:        int           = WebSocketPeer.STATE_CLOSED
var _join_code:       String        = ""
var _pending_action:  String        = ""
var _host_lobby_name: String        = ""
var _peer_connected:  bool          = false

func _ready() -> void:
	set_process(false)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func host(lobby_name: String = "Open Lobby") -> void:
	_join_code        = ""
	_host_lobby_name  = lobby_name
	is_multiplayer    = true
	_pending_action   = "host"
	_open()

func join(code: String) -> void:
	_join_code      = code.strip_edges().to_upper()
	last_lobby_code = _join_code
	is_multiplayer  = true
	_pending_action = "join"
	_open()

func rejoin() -> void:
	if last_lobby_code.is_empty(): return
	join(last_lobby_code)

## True while the relay socket is open — i.e. this client is still "in" the game
## (used to tell the player who stayed from the one whose connection dropped).
func is_connected_to_relay() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func list_lobbies() -> void:
	_pending_action = "list"
	_open()

func matchmake() -> void:
	is_multiplayer  = true
	_pending_action = "matchmake"
	_open()

func cancel_matchmake() -> void:
	_send({"type": "cancel_matchmake"})

func disconnect_all() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	set_process(false)
	is_multiplayer   = false
	is_host          = false
	_join_code       = ""
	_pending_action  = ""
	_host_lobby_name = ""
	_peer_connected  = false
	_ws_state        = WebSocketPeer.STATE_CLOSED

# ---------------------------------------------------------------------------
# Connection internals
# ---------------------------------------------------------------------------
func _open() -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_dispatch_pending_action()
		return
	_ws = WebSocketPeer.new()
	if _ws.connect_to_url(RELAY_URL) != OK:
		connection_failed.emit()
		disconnect_all()
		return
	_ws_state = WebSocketPeer.STATE_CONNECTING
	set_process(true)

func _process(_delta: float) -> void:
	if _ws == null: return
	_ws.poll()

	var state := _ws.get_ready_state()
	if state != _ws_state:
		_ws_state = state
		if state == WebSocketPeer.STATE_OPEN:
			_dispatch_pending_action()
		elif state == WebSocketPeer.STATE_CLOSED:
			if _peer_connected:
				peer_left.emit()
			else:
				connection_failed.emit()
			disconnect_all()

	if state == WebSocketPeer.STATE_OPEN:
		while _ws != null and _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			var msg  = JSON.parse_string(raw)
			if msg != null:
				_handle(msg)

func _dispatch_pending_action() -> void:
	match _pending_action:
		"host":
			_send({"type": "host", "name": _host_lobby_name,
				   "username": AccountManager.username, "token": AccountManager.token})
			is_host = true
		"join":
			_send({"type": "join", "code": _join_code,
				   "username": AccountManager.username, "token": AccountManager.token})
			is_host = false
		"list":
			_send({"type": "list"})
		"matchmake":
			_send({"type": "matchmake", "username": AccountManager.username, "token": AccountManager.token})
	_pending_action = ""

func _send(obj: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(obj))

func _handle(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"code":
			last_lobby_code = msg.get("code", "???")
			lobby_ready.emit(last_lobby_code)
		"joined":
			_peer_connected = true
			opponent_username = msg.get("host_username", "Opponent")
			opponent_username_received.emit(opponent_username)
			connected_to_host.emit()
		"peer_joined":
			_peer_connected = true
			opponent_username = msg.get("guest_username", "Opponent")
			opponent_username_received.emit(opponent_username)
			peer_joined.emit()
		"peer_left":
			peer_left.emit()
		"started":
			game_start_received.emit()
		"error":
			connection_failed.emit()
		"lobby_list":
			var raw: Array = msg.get("lobbies", [])
			var out: Array = []
			for entry in raw:
				if entry is Dictionary: out.append(entry)
			lobby_list_received.emit(out)
			if not is_multiplayer: disconnect_all()
		"mm_waiting":
			matchmake_waiting.emit()
		"mm_matched":
			var role: String = msg.get("role", "guest")
			is_host = (role == "host")
			_peer_connected = true
			opponent_username = msg.get("opponent_username", "Opponent")
			opponent_username_received.emit(opponent_username)
			matchmake_matched.emit()
		"mm_cancelled":
			pass
		"game":
			_apply_game(msg.get("action",""), msg.get("data", {}))

func _apply_game(action: String, data: Dictionary) -> void:
	if not is_instance_valid(GameManager): return
	match action:
		"dice":
			GameManager._net_apply_dice(
				int(data.get("a",1)), int(data.get("b",2)), int(data.get("total",3)))
		"move":
			GameManager._net_apply_move(
				Vector2i(int(data.get("fx",0)), int(data.get("fy",0))),
				Vector2i(int(data.get("tx",0)), int(data.get("ty",0))),
				float(data.get("rot",0.0)))
		"rotate":
			GameManager._net_apply_rotate(
				Vector2i(int(data.get("cx",0)), int(data.get("cy",0))),
				float(data.get("deg",0.0)))
		"state_sync":
			game_state_received.emit(data)
		"forfeit":
			opponent_forfeited.emit()

# ---------------------------------------------------------------------------
# Outbound helpers
# ---------------------------------------------------------------------------
func send_dice(a: int, b: int, total: int) -> void:
	_send({"type":"game","action":"dice","data":{"a":a,"b":b,"total":total}})

func send_move(from: Vector2i, to: Vector2i, rot: float) -> void:
	_send({"type":"game","action":"move",
		"data":{"fx":from.x,"fy":from.y,"tx":to.x,"ty":to.y,"rot":rot}})

func send_rotate(coord: Vector2i, degrees: float) -> void:
	_send({"type":"game","action":"rotate",
		"data":{"cx":coord.x,"cy":coord.y,"deg":degrees}})

func send_start() -> void:
	_send({"type":"start"})

## Send the full serialized game state to the peer (used on rejoin to resync).
func send_state(state: Dictionary) -> void:
	_send({"type":"game","action":"state_sync","data":state})

## Tell the peer we abandoned the match (they are declared the winner).
func send_forfeit() -> void:
	_send({"type":"game","action":"forfeit","data":{}})
