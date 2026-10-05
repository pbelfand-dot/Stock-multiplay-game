extends Node
## Connection + crew roster (autoload "Net"). The host is the authoritative
## server (peer id 1) for the stage: which seed, when the countdown starts,
## the results. The CAR belongs to whoever sits in the driver's seat: their
## machine simulates it and streams it to the other.
## ENet over UDP, default port 7777. Two players max (one crew).

signal roster_changed
signal connected_ok
signal connection_failed(reason: String)
signal server_gone

const MAX_PLAYERS := 2

var players := {}          # peer_id -> {name, seat ("driver" | "codriver")}
var in_session := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected_ok.emit())
	multiplayer.connection_failed.connect(func(): _drop(); connection_failed.emit("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(func(): _drop(); server_gone.emit())


func online() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func is_server() -> bool:
	return not online() or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if online() else 1


func host(port: int, seat: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": Config.player_name, "seat": seat}}
	in_session = true
	roster_changed.emit()
	return OK


func join(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {}
	in_session = true
	return OK


## Solo: no network, you're the driver.
func solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: {"name": Config.player_name, "seat": "driver"}}
	in_session = true
	roster_changed.emit()


func leave() -> void:
	_drop()


func _drop() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	in_session = false


## Peer id in a seat (0 = empty).
func peer_in(seat: String) -> int:
	for id in players:
		if players[id].seat == seat:
			return id
	return 0


func my_seat() -> String:
	return players.get(my_id(), {}).get("seat", "driver")


func crew_full() -> bool:
	return peer_in("driver") != 0 and peer_in("codriver") != 0


# ── roster (server decides, everyone gets a copy) ─────────────────────────

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.size() >= MAX_PLAYERS:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
		return
	var free_seat := "codriver" if peer_in("driver") != 0 else "driver"
	players[id] = {"name": "Player %d" % players.size(), "seat": free_seat}
	_send_roster()


func _on_peer_disconnected(id: int) -> void:
	if players.erase(id) and multiplayer.is_server():
		_send_roster()
	roster_changed.emit()


## The joining player tells the host their name.
@rpc("any_peer", "reliable")
func hello(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.has(id):
		players[id].name = player_name.substr(0, 20)
		_send_roster()


## Host: swap who drives (only between stages).
func swap_seats() -> void:
	if not multiplayer.is_server():
		return
	for id in players:
		players[id].seat = "codriver" if players[id].seat == "driver" else "driver"
	_send_roster()


func _send_roster() -> void:
	roster_changed.emit()
	if online():
		set_roster.rpc(players)


@rpc("authority", "reliable")
func set_roster(p: Dictionary) -> void:
	players = p
	roster_changed.emit()
