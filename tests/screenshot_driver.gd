extends Node
## Takes screenshots of the office + UIs. Needs a real display (e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . -- --host --autostart --shots=/tmp/shots

var out_dir := ""


func _ready() -> void:
	out_dir = Config.cli.get("shots", "user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot: ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	if not Config.cli.has("host"):
		await _frames(30)
		await _snap("00_menu")
		Sfx.quit_game()
		return
	while get_node_or_null("/root/Main/World/Match") == null:
		await get_tree().process_frame
	var world = get_node("/root/Main/World")
	var m = world.match_node
	var hud = world.hud
	await get_tree().create_timer(12.0).timeout   # let the first headline air
	var p = world.local_player
	var views := [
		["01_spawn_bullpen", Vector3(0, 0.1, 9), 0.0, -0.05],
		["02_desk_crt", Vector3(-5, 0.1, 4.2), 0.0, -0.35],
		["03_casino", Vector3(14, 0.1, -3), -1.9, -0.1],
		["04_tv_wall", Vector3(12, 0.1, 5.5), -PI / 2, 0.05],
		["05_lounge_tony", Vector3(-12, 0.1, 5), 0.9, -0.1],
		["06_west_wall", Vector3(-14, 0.1, -4), 1.3, 0.05],
		["07_windows", Vector3(3, 0.1, -6), 0.3, 0.12],
		["16_streamer_corner", Vector3(11.5, 0.1, 6.5), -2.45, 0.02],
		["17_hoop_ball", Vector3(-15.0, 0.1, -9.0), PI / 2 - 0.1, 0.25],
	]
	world._say("TJZ", "OH MY GOD, TRADE! LONG BTC RIGHT NOW!", 30.0)
	world._say("KIMCHEE", "APING MY WHOLE BAG INTO $WAGMI. NFA", 30.0)
	for v in views:
		p.teleport(v[1])
		p.rotation.y = v[2]
		p.pitch = v[3]
		p.head.rotation.x = v[3]
		await _frames(10)
		await _snap(v[0])
	# Terminal with a live position
	m.request_open("BTC", 1, 25_000.0, 100)
	m.request_open("BTC", -1, 5_000.0, 25)
	await get_tree().create_timer(3.0).timeout
	hud.open_interact({"type": "terminal", "id": 0})
	await _frames(10)
	await _snap("08_terminal")
	m.request_close_all()
	await get_tree().create_timer(0.4).timeout
	await _snap("09_trade_closed_popup")
	hud.close_modals()
	hud.open_interact({"type": "slots", "id": 0})
	hud.slots.spin()
	await get_tree().create_timer(2.2).timeout
	await _snap("10_slots")
	hud.close_modals()
	hud.open_interact({"type": "shop", "id": 0})
	await _frames(5)
	await _snap("11_shop")
	hud.close_modals()
	m.request_buy("cigar")
	m.request_buy("moneygun")
	await get_tree().create_timer(0.5).timeout
	m.request_use("cigar")
	await get_tree().create_timer(1.5).timeout
	await _snap("12_hud_items")
	hud.mugshot.play(4298, "Trader", Color(0.12, 0.13, 0.2))
	await get_tree().create_timer(1.0).timeout
	await _snap("13_mugshot")
	hud.mugshot.visible = false
	hud.summary.show_summary({"day": 1, "quota": 150000.0, "mode": "coop", "balance": 187000.0, "passed": true,
		"next_quota": 225000.0, "over": false, "players": {1: {"name": "Trader", "stats": m.stats.get(1, {})}}})
	await _frames(5)
	await _snap("14_summary")
	hud.summary.visible = false
	# Cops raid on ourselves
	p.teleport(Vector3(-3, 0.1, -12))
	p.rotation.y = PI
	p.pitch = -0.05
	p.head.rotation.x = -0.05
	m._add_heat(1, 200.0)
	await get_tree().create_timer(2.2).timeout
	await _snap("15_cops_raid")
	Sfx.quit_game()
