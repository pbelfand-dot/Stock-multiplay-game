extends Node
## Connection + lobby roster. The host is also the authoritative server
## (peer id 1). Uses ENet over UDP — default port 7777.

signal players_changed
signal connected_ok
signal connection_failed(reason: String)
signal server_gone

const MAX_PLAYERS := 6
const Character = preload("res://scripts/art/character.gd")
const SUIT_COLORS := [
	Color(0.35, 0.36, 0.4), Color(0.12, 0.13, 0.2), Color(0.45, 0.12, 0.14),
	Color(0.15, 0.3, 0.2), Color(0.5, 0.42, 0.3), Color(0.3, 0.2, 0.45),
]

const LOAD_TIMEOUT_MS := 30000   # how long a silent peer (loading the world) stays connected

var players := {}        # peer_id -> {name, color}
var mode := "coop"       # "coop" | "pvp"
var in_session := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


func host(port: int, game_mode: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = game_mode
	players.clear()
	players[1] = {"name": Config.player_name, "color": _color_for(0), "look": Character.sanitize(Config.look)}
	in_session = true
	players_changed.emit()
	return OK


func join(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_session = false


func _color_for(index: int) -> Color:
	return SUIT_COLORS[index % SUIT_COLORS.size()]


func _on_peer_connected(id: int) -> void:
	# clients register themselves once connected. Building the world freezes a joining
	# game for several seconds (more on a slow machine): ENet's default drops a peer that
	# goes 5 s without an ack, so the host would quietly lose them mid-load. Allow 30 s.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		var pp := enet.get_peer(id)
		if pp:
			pp.set_timeout(32, LOAD_TIMEOUT_MS, LOAD_TIMEOUT_MS * 2)


func _on_peer_disconnected(id: int) -> void:
	if is_server() and players.has(id):
		players.erase(id)
		_sync_players.rpc(players, mode)
		players_changed.emit()


func _on_connected() -> void:
	in_session = true
	_register.rpc_id(1, Config.player_name.substr(0, 16), Config.look)
	connected_ok.emit()


func _on_failed() -> void:
	leave()
	connection_failed.emit("Could not reach the host.")


func _on_server_gone() -> void:
	leave()
	server_gone.emit()


@rpc("any_peer", "reliable")
func _register(pname: String, look: Dictionary = {}) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	pname = pname.strip_edges()
	if pname.is_empty():
		pname = "Trader %d" % players.size()
	players[id] = {"name": pname, "color": _color_for(players.size()), "look": Character.sanitize(look)}
	_sync_players.rpc(players, mode)
	players_changed.emit()


@rpc("authority", "reliable")
func _sync_players(p: Dictionary, m: String) -> void:
	players = p
	mode = m
	players_changed.emit()


## The Tailor on the street: change your look mid-game, everyone sees it.
func set_look(look: Dictionary) -> void:
	if is_server():
		_apply_look(1, look)
	else:
		_req_look.rpc_id(1, look)


@rpc("any_peer", "reliable")
func _req_look(look: Dictionary) -> void:
	if is_server():
		_apply_look(multiplayer.get_remote_sender_id(), look)


func _apply_look(id: int, look: Dictionary) -> void:
	if not players.has(id):
		return
	players[id]["look"] = Character.sanitize(look)
	_sync_players.rpc(players, mode)
	players_changed.emit()


func player_name(id: int) -> String:
	return players.get(id, {}).get("name", "???")


## The look a player chose in the tailor (falls back to a default per slot).
func look_of(id: int, slot: int) -> Dictionary:
	var l: Dictionary = players.get(id, {}).get("look", {})
	return l if not l.is_empty() else Character.player_look(slot)
