extends Node
## Root: swaps between the main menu and the office world.
##
## CLI (after `--`):  --host [--pvp] [--autostart] [--day_seconds=N]
##                    --join=IP  [--name=Bob]  [--smoke=host|client]

const WorldScript = preload("res://scripts/world/world.gd")
const MenuScript = preload("res://scripts/ui/main_menu.gd")

var menu: Control
var world: Node3D


func _ready() -> void:
	get_tree().auto_accept_quit = false
	Net.connected_ok.connect(_on_connected)
	Net.connection_failed.connect(func(r): _show_menu(r))
	Net.server_gone.connect(func(): leave_game("The host closed the office."))
	if Config.cli.has("name"):
		Config.player_name = Config.cli.name
	if Config.cli.has("smoke"):
		var drv_script = load("res://tests/smoke_driver.gd")
		if drv_script:
			var drv = drv_script.new()
			drv.name = "SmokeDriver"
			add_child(drv)
	if Config.cli.has("savecheck"):     # save -> continue test (sets up before the host starts)
		var sv = load("res://tests/save_driver.gd").new()
		sv.name = "SaveDriver"
		add_child(sv)
	if Config.cli.has("clicktest"):
		var ck = load("res://tests/click_driver.gd")
		if ck:
			add_child(ck.new())
	if Config.cli.has("fit"):
		var fit_script = load("res://tests/fit_driver.gd")
		if fit_script:
			add_child(fit_script.new())
			return
	if Config.cli.has("dancecheck"):
		var dc_script = load("res://tests/dance_driver.gd")
		var dc = dc_script.new()
		add_child(dc)
		return
	if Config.cli.has("lineup"):
		var lu_script = load("res://tests/lineup_driver.gd")
		if lu_script:
			add_child(lu_script.new())
			return
	if Config.cli.has("shots"):
		var sd_script = load("res://tests/screenshot_driver.gd")
		if sd_script:
			var sd = sd_script.new()
			sd.name = "ScreenshotDriver"
			add_child(sd)
	if Config.cli.has("host"):
		host_game(int(Config.cli.get("port", Config.port)), "pvp" if Config.cli.has("pvp") else "coop")
	elif Config.cli.has("join"):
		join_game(Config.cli.join, int(Config.cli.get("port", Config.port)))
	else:
		_show_menu("")


func _show_menu(msg: String) -> void:
	_free_world()
	if menu == null:
		menu = MenuScript.new()
		menu.name = "Menu"
		menu.main = self
		add_child(menu)
	menu.visible = true
	menu.set_status(msg)
	Music.clear_event()
	Music.set_bed("vyzee")                    # title screen
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func host_game(port: int, game_mode: String) -> void:
	var err := Net.host(port, game_mode)
	if err != OK:
		_show_menu("Couldn't host on port %d (error %d). Is another copy running?" % [port, err])
		return
	_start_world()
	if Config.cli.has("autostart"):
		world.match_node.request_start.call_deferred()


func join_game(ip: String, port: int) -> void:
	var err := Net.join(ip, port)
	if err != OK:
		_show_menu("Couldn't start connection (error %d)." % err)
		return
	if menu:
		menu.set_status("Connecting to %s:%d ..." % [ip, port])


func _on_connected() -> void:
	_start_world()


func _start_world() -> void:
	if menu:
		menu.visible = false
	_free_world()
	world = WorldScript.new()
	world.name = "World"
	add_child(world)


func leave_game(msg: String = "") -> void:
	Net.leave()
	_show_menu(msg)


## Remove immediately so a new "World" can take the same node path (RPCs).
func _free_world() -> void:
	if world:
		remove_child(world)
		world.queue_free()
		world = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Net.leave()
		Sfx.quit_game()
